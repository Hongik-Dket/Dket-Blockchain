// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

uint16 constant REQUEST_CONFIRMATIONS = 3;
uint32 constant CALLBACK_GAS_LIMIT = 1000000;
uint32 constant NUM_WORDS = 1;


contract DketNFT is ERC721URIStorage, Ownable, VRFConsumerBaseV2 {

    event EventCreated(uint256 indexed eventId, string title, address organizer);
    event SessionCreated(uint256 indexed eventId, uint256 indexed sessionId, uint256 applicationCount);
    event VRFRequestSent(uint256 indexed sessionId, uint256 indexed requestId);
    event WinnersDrawn(uint256 indexed sessionId, address[] winners);
    event TicketMinted(uint256 indexed sessionId, address user, uint256 tokenId, bool isWinner);
    event PublicSaleOpened(uint256 indexed eventId);
    event PaymentTransferred(address to, uint256 amount);


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
        string[] photoCardURIs;
    }

    struct SessionInfo {
        uint256 eventId;
        uint256 sessionId;
        bool isDrawn;
        uint256 mintCount;
        address[] applications;
        address[] winners;
        uint256[] photoCardIndices;
    }

    mapping(uint256 => EventInfo) public events;
    mapping(uint256 => SessionInfo) private sessions;

    mapping(uint256 => uint256) private requestToSessionId;

    mapping(uint256 => mapping(address => bool)) public minted;
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
        uint256 _price,
        string[] memory _photoCardURIs
    ) external onlyOwner {
        require(events[_eventId].eventId == 0, "Event already exists");

        events[_eventId] = EventInfo({
            eventId: _eventId,
            organizer: _organizer,
            title: _title,
            maxWinners: _maxWinners,
            price: _price,
            publicSale: false,
            photoCardURIs: _photoCardURIs
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
        session.isDrawn = false;
        session.applications = _applications;
        session.mintCount = 0;

        emit SessionCreated(_eventId, _sessionId, _applications.length);

        uint256 requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        requestToSessionId[requestId] = _sessionId;

        emit VRFRequestSent(_sessionId, requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 sessionId = requestToSessionId[requestId];

        SessionInfo storage session = sessions[sessionId];
        require(!session.isDrawn, "Already drawn");

        EventInfo storage _event = events[session.eventId];

        address[] memory shuffled = shuffle(session.applications, randomWords[0]);
        uint256 winnerCount = _event.maxWinners;
        uint256 applyCount = session.applications.length;

        session.winners = new address[](winnerCount < applyCount ? winnerCount : applyCount);
        session.photoCardIndices = new uint256[](winnerCount);

        for (uint256 i = 0; i < winnerCount; i++) {

            if (i < applyCount) {
                address winner = shuffled[i];
                session.winners[i] = winner;
                winnerIndexMaps[sessionId][winner] = i; 
            }
        
            uint256 photoIndex = uint256(keccak256(abi.encode(randomWords[0], i, "card")))
                % _event.photoCardURIs.length;
            session.photoCardIndices[i] = photoIndex;
        }

        emit WinnersDrawn(sessionId, session.winners);

        session.isDrawn = true;
    }

    function mintWinnerTicket(uint256 sessionId) external payable {
        SessionInfo storage session = sessions[sessionId];
        EventInfo storage _event = events[session.eventId];
        address to = msg.sender;

        require(session.isDrawn, "Not drawn");
        require(!_event.publicSale, "Public sale opened");
        require(validateWinner(to, sessionId), "Not a winner");
        require(!minted[sessionId][to], "Ticket already minted");
        require(msg.value == _event.price, "Incorrect payment amount");

        string memory tokenURI = _event.photoCardURIs[session.photoCardIndices[session.mintCount]];
        _safeMint(to, nextTokenId);
        _setTokenURI(nextTokenId, tokenURI);

        emit TicketMinted(sessionId, to, nextTokenId, true);

        nextTokenId++;

        (bool success, ) = payable(_event.organizer).call{value: msg.value}("");
        require(success, "Payment failed");
        emit PaymentTransferred(_event.organizer, msg.value);

        minted[sessionId][to] = true;
        session.mintCount++;
    }

    function openPublicSale(uint256 eventId) external onlyOwner {
        EventInfo storage _event = events[eventId];
        _event.publicSale = true;
        emit PublicSaleOpened(eventId); 
    }

    function mintPublicTicket(uint256 sessionId) external payable {
        SessionInfo storage session = sessions[sessionId];
        EventInfo storage _event = events[session.eventId];
        address to = msg.sender;

        require(_event.publicSale, "Pulic sale not opened");
        require(!minted[sessionId][to], "Ticket already minted");
        require(msg.value == _event.price, "Incorrect payment amount");


        string memory tokenURI = _event.photoCardURIs[session.photoCardIndices[session.mintCount]];
        _safeMint(to, nextTokenId);
        _setTokenURI(nextTokenId, tokenURI);

        emit TicketMinted(sessionId, to, nextTokenId, false);

        nextTokenId++;

        (bool success, ) = payable(_event.organizer).call{value: msg.value}("");
        require(success, "Payment failed");
        emit PaymentTransferred(_event.organizer, msg.value);
        
        minted[sessionId][to] = true;
        session.mintCount++;
    }

    function getSessionInfo(uint256 sessionId) external view returns (
        uint256 eventId,
        bool isDrawn,
        uint256 mintCount,
        address[] memory applications,
        address[] memory winners,
        uint256[] memory photoCardIndices
    )
    {
        SessionInfo storage session = sessions[sessionId];
        return (
            session.eventId,
            session.isDrawn,
            session.mintCount,
            session.applications,
            session.winners,
            session.photoCardIndices
        );
    }


    function shuffle(address[] memory array, uint256 seed) private pure returns (address[] memory) {
        if (array.length == 0) return array;

        for (uint256 i = array.length - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % (i + 1);
            (array[i], array[j]) = (array[j], array[i]);
        }

        return array;
    }

    function validateWinner(address user, uint256 sessionId) private view returns (bool) {
        require(msg.sender == owner() || msg.sender == user, "Not authorized");

        SessionInfo storage session = sessions[sessionId];
        uint256 winnerIndex = winnerIndexMaps[sessionId][user];

        if (winnerIndex < session.winners.length && session.winners[winnerIndex] == user)
            return true;
        else
            return false;
    }

}
