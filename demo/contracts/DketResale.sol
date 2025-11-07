// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

interface IDketNFT {
    function owner() external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function getApproved(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function getConcertIdOfSession(uint256 sessionId) external view returns (uint256);
    function getSessionHeader(uint256 sessionId) external view returns (
        uint256 concertId,
        uint64 startAt
    );
    function concerts(uint256 concertId) external view returns (
        uint256 /*concertId*/,
        address /*organizer*/,
        string memory /*title*/,
        uint256 /*maxWinners*/,
        uint256 /*price*/,
        bool /*publicSale*/,
        bool /*isResaleAllowed*/
    );

    function enteredAt(uint256 tokenId) external view returns (uint256);
}

contract DketResale is Ownable, EIP712, ReentrancyGuard {
    using ECDSA for bytes32;

    uint16 public constant BPS_DENOMINATOR = 10000;
    uint16 public constant ORGANIZER_FEE_BPS = 1000;

    IDketNFT public immutable nft;
    address public resaleSigner;

    struct ResaleInfo {
        uint256 resaleId;
        uint256 tokenId;
        uint256 sessionId;
        address seller;
        uint256 price;
        bool    isSold; 
    }

    mapping(uint256 => ResaleInfo) public resales;       // resaleId -> info
    mapping(uint256 => uint256) public activeResaleIdByToken;

    // EIP-712
    bytes32 private constant _PERMITPURCHASE_TYPEHASH =
        keccak256("PermitPurchase(address buyer,uint256 resaleId,uint256 tokenId,uint256 price,uint64 expireAt)");

    event ResaleListed(uint256 indexed resaleId, uint256 indexed tokenId, uint256 indexed sessionId, address seller, uint256 price);
    event ResaleSold(uint256 indexed resaleId, uint256 indexed tokenId, address indexed seller, address buyer);


    constructor(address dketNft) 
        Ownable(msg.sender)
        EIP712("DketResalePermit", "1") {
            require(dketNft != address(0), "nft=0");
            nft = IDketNFT(dketNft);
            resaleSigner = nft.owner();
    }

    function listResale(
        uint256 resaleId,
        uint256 tokenId,
        uint256 sessionId,
        address _seller,
        uint256 price
    ) external onlyOwner {
        require(resales[resaleId].resaleId == 0, "Resale already exists");

        uint256 activeId = activeResaleIdByToken[tokenId];
        require(activeId == 0 || resales[activeId].isSold, "Token already listed");

        address seller = nft.ownerOf(tokenId);
        require(seller == _seller, "Invalid seller");

        (uint256 concertId, ) = nft.getSessionHeader(sessionId);
        require(concertId != 0, "Session not found");

        (, , , , , , bool isResaleAllowed) = nft.concerts(concertId);
        require(isResaleAllowed, "Resale not allowed");

        require(
            nft.isApprovedForAll(seller, address(this)) || nft.getApproved(tokenId) == address(this),
            "Approve contract first"
        );

        resales[resaleId] = ResaleInfo({
            resaleId: resaleId,
            tokenId: tokenId,
            sessionId: sessionId,
            seller: seller,
            price: price,
            isSold: false
        });

        activeResaleIdByToken[tokenId] = resaleId;

        emit ResaleListed(resaleId, tokenId, sessionId, seller, price);
    }

    function buyResaleWithSig(
        uint256 resaleId,
        uint256 tokenId,
        uint64  expireAt,
        bytes calldata signature
    ) external payable nonReentrant {
        ResaleInfo storage r = resales[resaleId];

        require(r.resaleId != 0, "Resale not found");
        require(!r.isSold, "Already sold");
        require(r.tokenId == tokenId, "Token mismatch");
        require(activeResaleIdByToken[tokenId] == resaleId, "Listing not active");
        require(r.price == msg.value, "Incorrect payment amount");
        require(block.timestamp <= expireAt, "Permit expired");
        require(nft.ownerOf(tokenId) == r.seller, "Seller no longer owner");
        require(
        nft.isApprovedForAll(r.seller, address(this)) || nft.getApproved(tokenId) == address(this),
        "Not approved"
        );

        (uint256 concertId, uint64 startAt) = nft.getSessionHeader(r.sessionId);
        (, address organizer, , , uint256 basePrice, , ) = nft.concerts(concertId);

        verifySig(msg.sender, resaleId, tokenId, msg.value, expireAt, signature);

        r.isSold = true;
        if (activeResaleIdByToken[tokenId] == resaleId) {
            activeResaleIdByToken[tokenId] = 0;
        }

        uint256 entered = nft.enteredAt(tokenId);
        settleAndTransfer(organizer, r.seller, tokenId, startAt, basePrice, entered);

        emit ResaleSold(resaleId, tokenId, r.seller, msg.sender);
    }

    function verifySig(
        address buyer,
        uint256 resaleId,
        uint256 tokenId,
        uint256 price,
        uint64  expireAt,
        bytes calldata signature
    ) internal view {
        bytes32 structHash = keccak256(abi.encode(
            _PERMITPURCHASE_TYPEHASH,
            buyer,
            resaleId,
            tokenId,
            price,
            expireAt
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, signature);
        require(recovered == resaleSigner, "Invalid signature");
    }

    function calcFees(
        uint64 startAt,
        uint256 basePrice,
        uint256 enteredAt,
        uint256 price
    ) internal view returns (uint256 organizerFee, uint256 sellerNet) {
        if (block.timestamp < startAt && enteredAt == 0) {
            organizerFee = price > basePrice ? ((price - basePrice) * ORGANIZER_FEE_BPS) / BPS_DENOMINATOR : 0;
        } else {
            organizerFee = (price * ORGANIZER_FEE_BPS) / BPS_DENOMINATOR;
        }
        sellerNet = price - organizerFee;
    }

    function settleAndTransfer(
        address organizer,
        address seller,
        uint256 tokenId,
        uint64  startAt,
        uint256 basePrice,
        uint256 entered
    ) internal {
        (uint256 organizerFee, uint256 sellerNet) = calcFees(startAt, basePrice, entered, msg.value);

        (bool ok1,) = payable(organizer).call{value: organizerFee}("");
        require(ok1, "Organizer payout failed");

        (bool ok2,) = payable(seller).call{value: sellerNet}("");
        require(ok2, "Seller payout failed");

        nft.safeTransferFrom(seller, msg.sender, tokenId);

    }
}