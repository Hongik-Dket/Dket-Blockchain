// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DketNFT is ERC721URIStorage, Ownable {

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
        uint256[] randomPhotoCardIndices;
    }

    mapping(uint256 => EventInfo) public events;
    mapping(uint256 => mapping(uint256 => SessionInfo)) public sessions;

    constructor() ERC721("DketNFT", "Dket") Ownable(msg.sender) { }
    
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
        require(sessions[_eventId][_sessionId].sessionId == 0, "Session already exists");

        sessions[_eventId][_sessionId] = SessionInfo({
            eventId: _eventId,
            sessionId: _sessionId,
            maxWinners: _maxWinners,
            raffleDone: false,
            winners: new address[](_maxWinners),
            applications: _applications,
            randomPhotoCardIndices: new uint256[](_maxWinners)
        });

        drawWinnersAndAssignPhotoCards(_eventId, _sessionId);
    }

    // Todo: internal로 변경!! 테스트를 위해 열어둠
    function drawWinnersAndAssignPhotoCards(uint256 _eventId, uint256 _sessionId) public {
        require(!sessions[_eventId][_sessionId].raffleDone, "Raffle already done");

        address[] storage applications = sessions[_eventId][_sessionId].applications;
        uint256 maxWinners = sessions[_eventId][_sessionId].maxWinners;
        
        // Todo: 랜덤 추첨 프로세스 구현
        address[] storage winners = sessions[_eventId][_sessionId].winners;

        for (uint256 i = 0; i < maxWinners; i++) {
            winners.push(applications[i]);
            sessions[_eventId][_sessionId].randomPhotoCardIndices[i] = 0;
        }


        sessions[_eventId][_sessionId].raffleDone = true;
    }

    function mintTicket(
        address to,
        uint256 eventId,
        uint256 sessionId
    ) external onlyOwner {
        require(
            sessions[eventId][sessionId].raffleDone,
            "Raffle not completed"
        );

        uint256 tokenId = nextTokenId;

        uint256 photoCardIndex = sessions[eventId][sessionId].randomPhotoCardIndices[tokenId];
        string memory tokenURI = events[eventId].photoCardURIs[photoCardIndex];

        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        nextTokenId++;
    }

    function getWinners(uint256 eventId, uint256 sessionId) external view returns (address[] memory) {
        return sessions[eventId][sessionId].winners;
    }

}
