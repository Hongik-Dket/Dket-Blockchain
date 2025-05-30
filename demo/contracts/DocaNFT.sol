// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DocaNFT is ERC1155URIStorage, Ownable {
    mapping(uint256 => bool) public uriSet;

    event Minted(address indexed to, uint256 indexed tokenId);
    event URISet(uint256 indexed tokenId, string uri);

    constructor() ERC1155("") Ownable(msg.sender) {}

    function mint(address to, uint256 id) external onlyOwner {
        require(balanceOf(to, id) == 0, "This address already owns the token");

        _mint(to, id, 1, "");
        emit Minted(to, id);
    }

    function setURI(uint256 id, string memory newuri) external onlyOwner {
        require(!uriSet[id], "URI already set");

        _setURI(id, newuri);
        uriSet[id] = true;
        
        emit URISet(id, newuri);
    }

    function uri(uint256 id) public view override returns (string memory) {
        return super.uri(id);
    }
}
