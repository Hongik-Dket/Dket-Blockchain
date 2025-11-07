// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

uint16 constant REQUEST_CONFIRMATIONS = 3;
uint32 constant CALLBACK_GAS_LIMIT = 300000;
uint32 constant NUM_WORDS = 1;

interface IWinVerifier {
    function verifyWinProof(
        bytes calldata proof,
        bytes32 winnersRoot,
        uint256 sessionId,
        bytes32 paymentNullifier
    ) external view returns (bool);
}

contract DketNFT is ERC721URIStorage, Ownable, VRFConsumerBaseV2, ReentrancyGuard {

    event ConcertCreated(uint256 indexed concertId, string title, address organizer);
    event SessionCreated(uint256 indexed concertId, uint256 indexed sessionId);

    event VRFRequestSent(uint256 indexed sessionId, uint256 indexed requestId);
    event RandomFulfilled(uint256 indexed sessionId, uint256 randomWord);

    event SessionMinted(uint256 indexed sessionId, uint256[] tokenIds);

    event ApplicantsListCommitted(uint256 indexed sessionId, bytes32 listHash, uint32 count);
    event WinnersDrawn(uint256 indexed sessionId, uint32 count, uint32[] winnerIdx);
    event WinnersRootSet(uint256 indexed sessionId, bytes32 winnersRoot);
    event VerifierSet(address win);

    event SetDrawn(uint256 indexed sessionId);

    event PaymentTransferred(address to, uint256 indexed sessionId, uint256 indexed tokenId, uint256 amount);

    event PublicSaleOpened(uint256 indexed concertId);

    event TransferAgentSet(address indexed agent, bool allowed);


    address public constant VRF_COORDINATOR = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625;
    bytes32 public constant KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint64 s_subscriptionId;
    VRFCoordinatorV2Interface public immutable COORDINATOR;

    uint256 private nextTokenId;

    struct ConcertInfo {
        uint256 concertId;
        address organizer;
        string title;
        uint256 maxWinners;
        uint256 price;
        bool publicSale;
        bool isResaleAllowed;
    }

    struct SessionInfo {
        uint256 concertId;
        uint256 sessionId;
        uint64 startAt;
        uint256[] tokenIds;
    }

    mapping(uint256 => ConcertInfo) public concerts;
    mapping(uint256 => SessionInfo) public sessions;

    enum SessionStatus { Created, Pending, Minted, Drawn, Ready }
    mapping(uint256 => SessionStatus) public sessionStatus;

    mapping(uint256 => uint256) private requestToSessionId;
    mapping(uint256 => uint256) private sessionRandomSeed;

    mapping(uint256 => mapping(address => uint256)) public sessionTicketOf; // sessionId -> buyer -> tokenId
    mapping(uint256 => uint256[]) public availableTokens; // sessionId -> available tokenIds

    mapping(uint256 => bytes32) public applicantsListHashOf; // sessionId -> keccak(leaves[0]||...||leaves[N-1])
    mapping(uint256 => uint32)  public applicantsCountOf;    // sessionId -> 응모자 수 N

    mapping(uint256 => uint32)  public stepCursorOf;         // sessionId -> next step
    mapping(uint256 => mapping(uint32 => bool)) public claimedIndex; // sessionId -> index -> claimed

    mapping(uint256 => bytes32[]) public winnerLeavesOf;        // sessionId -> winner leaves

    mapping(uint256 => bytes32) public winnersRootOf;       // Poseidon-Merkle winners root
    mapping(bytes32 => bool)    public usedPaymentNullifier; // Poseidon(IC,sessionId,"pay")

    mapping(address => bool) public isTransferAgent;

    mapping(uint256 => uint256) public enteredAt; // tokenId -> timestamp(0이면 미입장)


    IWinVerifier public winVerifier;

    function setWinVerifier(address win) external onlyOwner {
        winVerifier = IWinVerifier(win);
        emit VerifierSet(win);
    }


    constructor(uint64 subscriptionId) 
        ERC721("DketNFT", "Dket") 
        Ownable(msg.sender)
        VRFConsumerBaseV2(VRF_COORDINATOR) {
            COORDINATOR = VRFCoordinatorV2Interface(VRF_COORDINATOR);
            s_subscriptionId = subscriptionId;
            nextTokenId = 1;

            isTransferAgent[address(this)] = true;
            isTransferAgent[address(msg.sender)] = true;

            setApprovalForAll(address(msg.sender), true);
    }

    
    bool private _internalMove;

    function setTransferAgent(address agent, bool allowed) external onlyOwner {
        isTransferAgent[agent] = allowed;
        emit TransferAgentSet(agent, allowed);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal override(ERC721) returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            require(_internalMove || isTransferAgent[_msgSender()], "Transfers restricted");
        }
        return super._update(to, tokenId, auth);
    }

    function setApprovalForAll(address operator, bool approved)
        public override(ERC721, IERC721) 
    {
        require(isTransferAgent[operator], "Only transfer agents can be operators");
        super.setApprovalForAll(operator, approved);
    }

    function approve(address to, uint256 tokenId)
        public override(ERC721, IERC721) 
    {
        require(isTransferAgent[to], "Only transfer agents can be approved");
        super.approve(to, tokenId);
    }

    function createConcert(
        uint256 _concertId,
        address _organizer,
        string memory _title,
        uint256 _maxWinners,
        uint256 _price,
        bool _isResaleAllowed,
        uint256[] calldata sessionIds,
        uint64[] calldata startAts
    ) external onlyOwner {
        require(concerts[_concertId].concertId == 0, "Concert already exists");
        require(sessionIds.length == startAts.length, "Length mismatch");

        concerts[_concertId] = ConcertInfo({
            concertId: _concertId,
            organizer: _organizer,
            title: _title,
            maxWinners: _maxWinners,
            price: _price,
            publicSale: false,
            isResaleAllowed: _isResaleAllowed
        });

        emit ConcertCreated(_concertId, _title, _organizer);

        uint256 len = sessionIds.length;
        for (uint256 i = 0; i < len; ++i) {
            createSession(_concertId, sessionIds[i], startAts[i]);
        }
    }

    function createSession(uint256 _concertId, uint256 _sessionId, uint64 _startAt) internal {
        require(_startAt > block.timestamp, "startAt must be future");

        SessionInfo storage session = sessions[_sessionId];
        require(session.sessionId == 0, "Session exists");

        session.concertId = _concertId;
        session.sessionId = _sessionId;
        session.startAt = _startAt;

        sessionStatus[_sessionId] = SessionStatus.Created;

        emit SessionCreated(_concertId, _sessionId);
        
        requestVRF(_sessionId);
    }

    function requestVRF(uint256 sessionId) public onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        require(session.sessionId != 0, "Session not exists");

        uint256 requestId = COORDINATOR.requestRandomWords(
            KEY_HASH,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        requestToSessionId[requestId] = sessionId;

        emit VRFRequestSent(sessionId, requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 sessionId = requestToSessionId[requestId];
        require(sessions[sessionId].sessionId != 0, "Invalid sessionId from requestId");

        sessionRandomSeed[sessionId] = randomWords[0];
        sessionStatus[sessionId] = SessionStatus.Pending;

        emit RandomFulfilled(sessionId, randomWords[0]);
    }

    function mintSessionTicket(uint256 sessionId, string[] memory uris) external onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];

        require(sessionStatus[sessionId] != SessionStatus.Created, "Invalid state");
        require(session.tokenIds.length == 0, "Already minted");
        
        require(concerts[session.concertId].concertId != 0, "Invalid concert");
        ConcertInfo storage concert = concerts[session.concertId];

        require(uris.length == concert.maxWinners, "Invalid number of URIs");

        address to = owner();

        for (uint256 i = 0; i < uris.length; i++) {
            uint256 currentTokenId = nextTokenId++;

            _safeMint(to, currentTokenId);
            _setTokenURI(currentTokenId, uris[i]);

            session.tokenIds.push(currentTokenId);
            availableTokens[sessionId].push(currentTokenId);
        }

        emit SessionMinted(sessionId, session.tokenIds);

        if (sessionStatus[sessionId] == SessionStatus.Drawn) {
            sessionStatus[sessionId] = SessionStatus.Ready;
        } else {
            sessionStatus[sessionId] = SessionStatus.Minted;
        }
    }

   function setApplicantsListCommitment(
        uint256 sessionId,
        bytes32 listHash,
        uint32 count
    ) external onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        require(applicantsListHashOf[sessionId] == bytes32(0), "List committed");
        require(count > 0, "Empty applicants");

        applicantsListHashOf[sessionId] = listHash;
        applicantsCountOf[sessionId]    = count;

        emit ApplicantsListCommitted(sessionId, listHash, count);
    }

    function drawIndex(uint256 sessionId, uint32 step) public view returns (uint32) {
        require(sessionRandomSeed[sessionId] != 0, "Seed not set");

        uint32 N = applicantsCountOf[sessionId];
        require(N > 0, "No applicants");

        return uint32(uint256(keccak256(abi.encodePacked(sessionRandomSeed[sessionId], step))) % N);
    }

    function _winnersRemaining(uint256 sessionId) internal view returns (uint256) {
        uint256 concertId = sessions[sessionId].concertId;
        return concerts[concertId].maxWinners - winnerLeavesOf[sessionId].length;
    }

    function drawWinners(
        uint256 sessionId,
        uint32 count,
        bytes32[] calldata leaves
    ) external onlyOwner {
        require(leaves.length == applicantsCountOf[sessionId], "Leaves must be full applicants list");
        require(sessionRandomSeed[sessionId] != 0, "Seed not set");
        require(applicantsCountOf[sessionId] > 0, "Applicants not set");
        require(count <= _winnersRemaining(sessionId), "Exceeds remaining winners");

        uint32 cursor = stepCursorOf[sessionId];
        uint32 accepted = 0;
        uint32[] memory winnerIdx = new uint32[](count);

        for (uint32 k = 0; k < count; k++) {
            uint32 idx;
            while (true) {
                idx = drawIndex(sessionId, cursor);
                cursor++;
                if (!claimedIndex[sessionId][idx]) break;
            }
            
            claimedIndex[sessionId][idx] = true;
            winnerLeavesOf[sessionId].push(leaves[idx]);

            winnerIdx[k] = idx;
            accepted++;
        }

        stepCursorOf[sessionId] = cursor;
        emit WinnersDrawn(sessionId, accepted, winnerIdx);
    }

    function finalizeWinnersRoot(uint256 sessionId, bytes32 winnersRoot) external onlyOwner {
        require(winnerLeavesOf[sessionId].length > 0, "No winners");
        require(winnersRootOf[sessionId] == bytes32(0), "Already finalized"); 

        winnersRootOf[sessionId] = winnersRoot;

        if (sessionStatus[sessionId] == SessionStatus.Minted) {
            sessionStatus[sessionId] = SessionStatus.Ready;
        } else {
            sessionStatus[sessionId] = SessionStatus.Drawn;
        }

        emit WinnersRootSet(sessionId, winnersRoot);
    }

    function setDrawn(uint256 sessionId) external onlyOwner {
        if (sessionStatus[sessionId] == SessionStatus.Minted) {
            sessionStatus[sessionId] = SessionStatus.Ready;
        } else {
            sessionStatus[sessionId] = SessionStatus.Drawn;
        }

        emit SetDrawn(sessionId);
    }

    function openPublicSale(uint256 concertId) external onlyOwner {
        require(concerts[concertId].concertId != 0, "Invalid concert");

        ConcertInfo storage concert = concerts[concertId];
        concert.publicSale = true;

        emit PublicSaleOpened(concertId); 
    }

    function buyTicket(
        uint256 sessionId,
        bytes calldata proof,
        bytes32 paymentNullifier
    ) public payable nonReentrant {
        address buyer = msg.sender;

        require(sessionTicketOf[sessionId][buyer] == 0, "Already purchased");
        require(availableTokens[sessionId].length > 0, "Sold out");

        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];

        require(concerts[session.concertId].concertId != 0, "Invalid concert");
        ConcertInfo storage concert = concerts[session.concertId];

        require(msg.value == concert.price, "Incorrect payment amount");
        require(sessionStatus[sessionId] == SessionStatus.Ready, "Invalid state");

        if (!concert.publicSale) {
            bytes32 root = winnersRootOf[sessionId];
            require(root != bytes32(0), "WinnersRoot not set");
            require(!usedPaymentNullifier[paymentNullifier], "Nullifier used");
            require(
                address(winVerifier) != address(0) &&
                winVerifier.verifyWinProof(proof, root, sessionId, paymentNullifier),
                "WIN proof invalid"
            );

            usedPaymentNullifier[paymentNullifier] = true;
        } else {
            require(proof.length == 0, "Proof must be empty in public sale");
            require(paymentNullifier == bytes32(0), "Nullifier must be zero in public sale");
        }

        (bool success, ) = payable(concert.organizer).call{value: msg.value}("");
        require(success, "Payment failed");

        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            sessionRandomSeed[sessionId],
            block.timestamp,
            msg.sender
        )));
        uint256 idx = randomSeed % availableTokens[sessionId].length;
        uint256 tokenId = availableTokens[sessionId][idx];

        availableTokens[sessionId][idx] = availableTokens[sessionId][availableTokens[sessionId].length - 1];
        availableTokens[sessionId].pop();

        _internalMove = true;
        _safeTransfer(owner(), buyer, tokenId, "");
        _internalMove = false;

        sessionTicketOf[sessionId][buyer] = tokenId;

        emit PaymentTransferred(buyer, sessionId, tokenId, msg.value);
    }

    function enter(uint256 tokenId) external onlyOwner {
        require((_ownerOf(tokenId) != address(0)) && (_ownerOf(tokenId) != owner()), "Invalid token");
        require(enteredAt[tokenId] == 0, "Already entered");
        
        enteredAt[tokenId] = block.timestamp;
    }


    function getConcertIdOfSession(uint256 sessionId) external view returns (uint256) {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        return sessions[sessionId].concertId;
    }

    function getSessionHeader(uint256 sessionId) external view returns (uint256, uint64) {
        require(sessions[sessionId].sessionId != 0, "Invalid session");

        return (sessions[sessionId].concertId, sessions[sessionId].startAt);
    }

    function winnerIndexAt(uint256 sessionId, uint32 targetRank) public view returns (uint32 index) {
        require(sessionRandomSeed[sessionId] != 0, "Seed not set");
        uint32 N = applicantsCountOf[sessionId];
        require(N > 0, "No applicants");

        bool[] memory used = new bool[](N);
        uint32 found = 0;
        uint32 step = 0;

        while (true) {
            uint32 idx = drawIndex(sessionId, step);
            step++;
            if (!used[idx]) {
                if (found == targetRank) {
                    index = idx;
                    return index;
                }

                used[idx] = true;
                found++;
            }
        }
    }

    function computeWinnerIndices(uint256 sessionId, uint32 k) external view returns (uint32[] memory out) {
        require(sessionRandomSeed[sessionId] != 0, "Seed not set");
        uint32 N = applicantsCountOf[sessionId];
        require(N > 0 && k > 0 && k <= N, "Bad args");

        out = new uint32[](k);
        bool[] memory used = new bool[](N);
        uint32 found = 0;
        uint32 step = 0;

        while (found < k) {
            uint32 idx = drawIndex(sessionId, step);
            step++;

            if (!used[idx]) {
                used[idx] = true;
                out[found++] = idx;
            }
        }
    }

}