// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

uint16 constant REQUEST_CONFIRMATIONS = 3;
uint32 constant CALLBACK_GAS_LIMIT = 300000;
uint32 constant NUM_WORDS = 1;


contract DketNFT is ERC721URIStorage, Ownable, VRFConsumerBaseV2 {

    event EventCreated(uint256 indexed eventId, string title, address organizer);
    event SessionCreated(uint256 indexed eventId, uint256 indexed sessionId, uint256 applicationCount);

    event VRFRequestSent(uint256 indexed sessionId, uint256 indexed requestId);
    event RandomFulfilled(uint256 indexed sessionId, uint256 randomWord);

    event WinnersDrawn(uint256 indexed sessionId, address[] winners);
    event SessionMinted(uint256 indexed sessionId, uint256[] tokenIds);

    event TokenApproved(uint256 indexed sessionId, uint256 tokenId, address to);
    event ApproveCanceled(uint256 indexed tokenId, address from);

    event PaymentTransferred(address to, uint256 indexed sessionId, uint256 indexed tokenId, uint256 amount);

    event PublicSaleOpened(uint256 indexed eventId);


    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    bytes32 s_keyHash;

    uint256 private nextTokenId;

    struct EventInfo {
        uint256 eventId;
        address organizer;
        string title;
        uint256 maxWinners;
        uint256 price;
        bool publicSale;
    }

    struct SessionInfo {
        uint256 eventId;
        uint256 sessionId;
        uint256[] tokenIds;
        address[] applications;
        address[] winners;
    }

    mapping(uint256 => EventInfo) public events;
    mapping(uint256 => SessionInfo) private sessions;

    enum SessionStatus { Created, Drawn, Minted, SaleOpened }
    mapping(uint256 => SessionStatus) public sessionStatus;

    mapping(uint256 => uint256) private requestToSessionId;
    mapping(uint256 => uint256) private sessionRandomSeed;

    mapping(uint256 => mapping(address => bool)) public ticketed;
    mapping(uint256 => bool) public paid;
    
    mapping(uint256 => mapping(address => uint256)) public winnerIndexMaps;

    constructor(address vrfCoordinator, uint64 subscriptionId, bytes32 keyHash) 
        ERC721("DketNFT", "Dket") 
        Ownable(msg.sender)
        VRFConsumerBaseV2(vrfCoordinator) {
            COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
            s_subscriptionId = subscriptionId;
            s_keyHash = keyHash;
            nextTokenId = 1;
        } 
    
    function createEvent(
        uint256 _eventId,
        address _organizer,
        string memory _title,
        uint256 _maxWinners,
        uint256 _price
    ) external onlyOwner {
        require(events[_eventId].eventId == 0, "Event already exists");

        events[_eventId] = EventInfo({
            eventId: _eventId,
            organizer: _organizer,
            title: _title,
            maxWinners: _maxWinners,
            price: _price,
            publicSale: false
        });

        emit EventCreated(_eventId, _title, _organizer);
    }

    function createSession(
        uint256 _eventId,
        uint256 _sessionId,
        address[] memory _applications
    ) external onlyOwner {
        SessionInfo storage session = sessions[_sessionId];
        require(session.sessionId == 0, "Session exists");

        session.eventId = _eventId;
        session.sessionId = _sessionId;
        sessionStatus[_sessionId] = SessionStatus.Created;

        emit SessionCreated(_eventId, _sessionId, _applications.length);

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

        require(events[session.eventId].eventId != 0, "Invalid event");
        EventInfo storage _event = events[session.eventId];

        uint256 winnerCount = _event.maxWinners;
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
    }

    function mintSessionTicket(uint256 sessionId, string[] memory uris) external onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        
        require(events[session.eventId].eventId != 0, "Invalid event");
        EventInfo storage _event = events[session.eventId];

        require(sessionStatus[sessionId] == SessionStatus.Drawn, "Invalid state");
        require(uris.length == _event.maxWinners, "Invalid number of URIs");

        address to = msg.sender;

        for (uint256 i = 0; i < uris.length; i++) {
            uint256 currentTokenId = nextTokenId++;

            _safeMint(to, currentTokenId);
            _setTokenURI(currentTokenId, uris[i]);

            session.tokenIds.push(currentTokenId);
        } 

        sessionStatus[sessionId] = SessionStatus.Minted;

        emit SessionMinted(sessionId, session.tokenIds);
    }

    function approveToken(address to, uint256 sessionId) public onlyOwner {
        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        
        require(events[session.eventId].eventId != 0, "Invalid event");
        EventInfo storage _event = events[session.eventId];

        address owner = msg.sender;

        require(sessionStatus[sessionId] == SessionStatus.Minted, "Invalid state");
        require(to != owner, "ERC721: approval to current owner");

        if (!_event.publicSale)
            require(validateWinner(to, sessionId), "Not a winner");
        
        require(!ticketed[sessionId][to], "Ticket already paid");

        for (uint256 i = 0; i < session.tokenIds.length; i++) {
            uint256 tid = session.tokenIds[i];

            if (getApproved(tid) == address(0)) {
                _approve(to, tid, owner);

                emit TokenApproved(sessionId, tid, to);
                return;
            }
        }

        revert("No available token to approve");
    }

    function cancelApprove(address from, uint256 tokenId) public onlyOwner {
        require(getApproved(tokenId) == from, "Not approved to target");
        require(ownerOf(tokenId) == msg.sender, "Already Transferred");

        _approve(address(0), tokenId, msg.sender);

        emit ApproveCanceled(tokenId, from);
    }

    function buyTicket(address from, address to, uint256 tokenId, uint256 sessionId) public payable {
        require(getApproved(tokenId) == to, "Not approved to target");
        require(!ticketed[sessionId][to], "You already have a ticket");
        require(!paid[tokenId], "Ticket already bought");
        require(msg.sender == to, "Only approved user can buy the ticket");

        require(sessions[sessionId].sessionId != 0, "Invalid session");
        SessionInfo storage session = sessions[sessionId];
        
        require(events[session.eventId].eventId != 0, "Invalid event");
        EventInfo storage _event = events[session.eventId];

        require(msg.value == _event.price, "Incorrect payment amount");

        (bool success, ) = payable(_event.organizer).call{value: msg.value}("");
        require(success, "Payment failed");

        _safeTransfer(from, to, tokenId, "");

        paid[tokenId] = true;
        ticketed[sessionId][to] = true;

       emit PaymentTransferred(to, sessionId, tokenId, msg.value);
    }

    function openPublicSale(uint256 eventId) external onlyOwner {
        require(events[eventId].eventId != 0, "Invalid event");
        EventInfo storage _event = events[eventId];
        _event.publicSale = true;
        emit PublicSaleOpened(eventId); 
    }

    function getSessionInfo(uint256 sessionId) external view returns (
        uint256 eventId,
        address[] memory applications,
        address[] memory winners,
        uint256[] memory tokenIds
    )
    {
        SessionInfo storage session = sessions[sessionId];
        return (
            session.eventId,
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