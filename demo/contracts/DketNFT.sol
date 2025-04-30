// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

uint16 constant REQUEST_CONFIRMATIONS = 3;
uint32 constant CALLBACK_GAS_LIMIT = 200000;
uint32 constant NUM_WORDS = 1;


contract DketNFT is ERC721URIStorage, Ownable, VRFConsumerBaseV2 {

    event WinnersDrawn(uint256 eventId, uint256 sessionId, address[] winners, uint256[] photoCardIndices);

    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    bytes32 s_keyHash;

    uint256 private nextTokenId;

    struct EventInfo {
        uint256 eventId;
        string title;
        string[] photoCardURIs;
    }

    struct SessionInfo {
        uint256 eventId;
        uint256 sessionId;
        uint256 maxWinners;
        bool raffleDone;
        address[] applications;
        address[] winners;
        uint256[] photoCardIndices;
        mapping(address => uint256) winnerIndexMap;
    }

    mapping(uint256 => EventInfo) public events;
    mapping(uint256 => mapping(uint256 => SessionInfo)) public sessions;

    mapping(uint256 => uint256) private requestToEventId;
    mapping(uint256 => uint256) private requestToSessionId;

    mapping(uint256 => mapping(address => bool)) public minted;

    constructor(address vrfCoordinator, uint64 subscriptionId, bytes32 keyHash) 
        ERC721("DketNFT", "Dket") 
        Ownable(msg.sender)
        VRFConsumerBaseV2(vrfCoordinator) {
            COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
            s_subscriptionId = subscriptionId;
            s_keyHash = keyHash;
        } 
    
    function createEvent(
        uint256 _eventId,
        string memory _title,
        string[] memory _photoCardURIs
    ) external onlyOwner {
        require(events[_eventId].eventId == 0, "Event already exists");

        events[_eventId] = EventInfo({
            eventId: _eventId,
            title: _title,
            photoCardURIs: _photoCardURIs
        });
    }

    function createSession(
        uint256 _eventId,
        uint256 _sessionId,
        uint256 _maxWinners,
        address[] memory _applications
    ) external onlyOwner {
        SessionInfo storage session = sessions[_eventId][_sessionId];
        require(session.sessionId == 0, "Session exists");

        session.eventId = _eventId;
        session.sessionId = _sessionId;
        session.maxWinners = _maxWinners;
        session.raffleDone = false;
        session.applications = _applications;

        uint256 requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        requestToEventId[requestId] = _eventId;
        requestToSessionId[requestId] = _sessionId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 eventId = requestToEventId[requestId];
        uint256 sessionId = requestToSessionId[requestId];

        SessionInfo storage session = sessions[eventId][sessionId];
        require(!session.raffleDone, "Already drawn");

        address[] memory shuffled = shuffle(session.applications, randomWords[0]);
        uint256 winnerCount = session.maxWinners;
        uint256 applyCount = session.applications.length;

        session.winners = new address[](winnerCount);
        session.photoCardIndices = new uint256[](winnerCount);

        for (uint256 i = 0; i < winnerCount; i++) {
            if (i < applyCount) {
                address winner = shuffled[i];
                session.winners[i] = winner;
                session.winnerIndexMap[winner] = i;
            }

            uint256 photoIndex = uint256(keccak256(abi.encode(randomWords[0], i, "card")))
                % events[eventId].photoCardURIs.length;
            session.photoCardIndices[i] = photoIndex;
        }

        emit WinnersDrawn(eventId, sessionId, session.winners, session.photoCardIndices);

        session.raffleDone = true;
    }

    function mintTicket(address to, uint256 eventId, uint256 sessionId) external onlyOwner {
        SessionInfo storage session = sessions[eventId][sessionId];
        require(session.raffleDone, "Not drawn");

        uint256 winnerIndex = session.winnerIndexMap[to];
        require(validateWinner(to, eventId, sessionId), "Not a winner");

        require(!minted[sessionId][to], "Ticket already minted");

        string memory tokenURI = events[eventId].photoCardURIs[session.photoCardIndices[winnerIndex]];
        _safeMint(to, nextTokenId);
        _setTokenURI(nextTokenId, tokenURI);
        nextTokenId++;

        minted[sessionId][to] = true;
    }

    function shuffle(address[] memory array, uint256 seed) internal pure returns (address[] memory) {
        if (array.length == 0) return array;

        for (uint256 i = array.length - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encode(seed, i))) % (i + 1);
            (array[i], array[j]) = (array[j], array[i]);
        }

        return array;
    }

    function validateWinner(address user, uint256 eventId, uint256 sessionId) public view returns (bool) {
        require(msg.sender == owner() || msg.sender == user, "Not authorized");

        SessionInfo storage session = sessions[eventId][sessionId];
        uint256 winnerIndex = session.winnerIndexMap[user];

        if (winnerIndex < session.winners.length && session.winners[winnerIndex] == user)
            return true;
        else
            return false;
    }

}
