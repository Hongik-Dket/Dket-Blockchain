// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

uint16 constant REQUEST_CONFIRMATIONS = 3;
uint32 constant CALLBACK_GAS_LIMIT = 300000;
uint32 constant NUM_WORDS = 1;


contract DketNFT is ERC721URIStorage, Ownable, VRFConsumerBaseV2 {

    event ConcertCreated(uint256 indexed concertId, string title, address organizer);
    event SessionCreated(uint256 indexed concertId, uint256 indexed sessionId, uint256 applicationCount);

    event VRFRequestSent(uint256 indexed sessionId, uint256 indexed requestId);
    event RandomFulfilled(uint256 indexed sessionId, uint256 randomWord);

    event WinnersDrawn(uint256 indexed sessionId, address[] winners);
    event SetDrawn(uint256 indexed sessionId);
    event SessionMinted(uint256 indexed sessionId, uint256[] tokenIds);

    event PaymentTransferred(address to, uint256 indexed sessionId, uint256 indexed tokenId, uint256 amount);

    event PublicSaleOpened(uint256 indexed concertId);

    event TransferAgentSet(address indexed agent, bool allowed);


    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    bytes32 s_keyHash;

    uint256 private nextTokenId;

    struct ConcertInfo {
        uint256 concertId;
        address organizer;
        string title;
        uint256 maxWinners;
        uint256 price;
        bool publicSale;
    }

    struct SessionInfo {
        uint256 concertId;
        uint256 sessionId;
        uint256[] tokenIds;
        address[] applications;
        address[] winners;
    }

    mapping(uint256 => ConcertInfo) public concerts;
    mapping(uint256 => SessionInfo) private sessions;

    enum SessionStatus { Created, Drawn, Minted }
    mapping(uint256 => SessionStatus) public sessionStatus;

    mapping(uint256 => uint256) private requestToSessionId;
    mapping(uint256 => uint256) private sessionRandomSeed;

    mapping(uint256 => mapping(address => uint256)) public sessionTicketOf; // sessionId -> buyer -> tokenId
    mapping(uint256 => uint256[]) public availableTokens; // sessionId -> available tokenIds
    
    mapping(uint256 => mapping(address => uint256)) public winnerIndexMaps;

    mapping(address => bool) public isTransferAgent;


    constructor(address vrfCoordinator, uint64 subscriptionId, bytes32 keyHash) 
        ERC721("DketNFT", "Dket") 
        Ownable(msg.sender)
        VRFConsumerBaseV2(vrfCoordinator) {
            COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
            s_subscriptionId = subscriptionId;
            s_keyHash = keyHash;
            nextTokenId = 1;

            isTransferAgent[address(this)] = true;
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
        uint256 _price
    ) external onlyOwner {
        require(concerts[_concertId].concertId == 0, "Concert already exists");

        concerts[_concertId] = ConcertInfo({
            concertId: _concertId,
            organizer: _organizer,
            title: _title,
            maxWinners: _maxWinners,
            price: _price,
            publicSale: false
        });

        emit ConcertCreated(_concertId, _title, _organizer);
    }

    function createSession(
        uint256 _concertId,
        uint256 _sessionId,
        address[] memory _applications
    ) external onlyOwner {
        SessionInfo storage session = sessions[_sessionId];
        require(session.sessionId == 0, "Session exists");

        session.concertId = _concertId;
        session.sessionId = _sessionId;
        sessionStatus[_sessionId] = SessionStatus.Created;

        emit SessionCreated(_concertId, _sessionId, _applications.length);

        session.applications = _applications;

        requestVRF(_sessionId);
    }

    function requestVRF(uint256 sessionId) public {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
    
        require(session.sessionId != 0, "Session not exists");

        uint256 requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
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

        emit RandomFulfilled(sessionId, randomWords[0]);
    }

    function drawSession(uint256 sessionId) external onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        require(sessionStatus[sessionId] == SessionStatus.Created, "Invalid state");

        uint256 randomSeed = sessionRandomSeed[sessionId];
        require(randomSeed != 0, "Random seed not set");

        if (session.applications.length > 0)
            drawWinners(sessionId, randomSeed);
        
        setDrawn(sessionId);
    }

    function drawWinners(uint256 sessionId, uint256 randomSeed) private {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];

        require(concerts[session.concertId].concertId != 0, "Invalid concert");
        ConcertInfo storage concert = concerts[session.concertId];

        uint256 winnerCount = concert.maxWinners;
        uint256 applyCount = session.applications.length;

        if (applyCount > winnerCount) {
            address[] memory shuffled = shuffle(session.applications, randomSeed);
            session.winners = new address[](winnerCount);

            for (uint256 i = 0; i < winnerCount; i++) {
                session.winners[i] = shuffled[i];
                winnerIndexMaps[sessionId][session.winners[i]] = i; 
            }

        } else {
            session.winners = new address[](applyCount);

            for (uint256 i = 0; i < applyCount; i++) {
                session.winners[i] = session.applications[i];
                winnerIndexMaps[sessionId][session.winners[i]] = i; 
            }
        }

        emit WinnersDrawn(sessionId, session.winners);
    }

    function setDrawn(uint256 sessionId) private {
        sessionStatus[sessionId] = SessionStatus.Drawn;

        emit SetDrawn(sessionId);
    }

    function mintSessionTicket(uint256 sessionId, string[] memory uris) external onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        
        require(concerts[session.concertId].concertId != 0, "Invalid concert");
        ConcertInfo storage concert = concerts[session.concertId];

        require(sessionStatus[sessionId] == SessionStatus.Drawn, "Invalid state");
        require(uris.length == concert.maxWinners, "Invalid number of URIs");

        address to = owner();

        for (uint256 i = 0; i < uris.length; i++) {
            uint256 currentTokenId = nextTokenId++;

            _safeMint(to, currentTokenId);
            _setTokenURI(currentTokenId, uris[i]);

            session.tokenIds.push(currentTokenId);
            availableTokens[sessionId].push(currentTokenId);
        }
        sessionStatus[sessionId] = SessionStatus.Minted;

        emit SessionMinted(sessionId, session.tokenIds);
    }

    function buyTicket(uint256 sessionId) public payable {
        address buyer = msg.sender;

        require(sessionTicketOf[sessionId][buyer] == 0, "Already purchased");
        require(availableTokens[sessionId].length > 0, "Sold out");

        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        
        require(concerts[session.concertId].concertId != 0, "Invalid concert");
        ConcertInfo storage concert = concerts[session.concertId];

        require(msg.value == concert.price, "Incorrect payment amount");
        require(sessionStatus[sessionId] == SessionStatus.Minted, "Invalid state");

        if (!concert.publicSale)
            require(validateWinner(buyer, sessionId), "Not a winner");

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

        _safeTransfer(owner(), buyer, tokenId, "");
        sessionTicketOf[sessionId][buyer] = tokenId;

        emit PaymentTransferred(buyer, sessionId, tokenId, msg.value);
    }

    function openPublicSale(uint256 concertId) external onlyOwner {
        require(concerts[concertId].concertId != 0, "Invalid concert");
        ConcertInfo storage concert = concerts[concertId];
        concert.publicSale = true;
        emit PublicSaleOpened(concertId); 
    }

    function getSessionInfo(uint256 sessionId) external view returns (
        uint256 concertId,
        address[] memory applications,
        address[] memory winners,
        uint256[] memory tokenIds
    )
    {
        SessionInfo storage session = sessions[sessionId];
        return (
            session.concertId,
            session.applications,
            session.winners,
            session.tokenIds
        );
    }

    function shuffle(address[] memory array, uint256 seed) private pure returns (address[] memory) {
        if (array.length <= 1) return array;

        for (uint256 i = array.length - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encodePacked(seed, i))) % (i + 1);
            (array[i], array[j]) = (array[j], array[i]);
        }

        return array;
    }

    function validateWinner(address user, uint256 sessionId) private view returns (bool) {
        SessionInfo storage session = sessions[sessionId];
        uint256 winnerIndex = winnerIndexMaps[sessionId][user];

        if (winnerIndex < session.winners.length && session.winners[winnerIndex] == user)
            return true;
        else
            return false;
    }

}