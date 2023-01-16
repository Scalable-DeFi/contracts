// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC721A.sol";

contract MyToken is ERC721A, Ownable {

    bool public mintPaused;
    string private _baseTokenURI;
    mapping(address => uint256) public addressToNFTsMinted;
    uint256 public NFTPrice;



    constructor(string memory _name, string memory _symbol, uint256 _price) ERC721A(_name, _symbol) {
        NFTPrice = _price;
    }

    mapping(address => bool) public isWhitelisted;

    function mint() public payable {
        require(isWhitelisted[msg.sender], "Address not whitelisted");
        require(!mintPaused, "Constract is not open");
        require(addressToNFTsMinted[msg.sender] == 0, "You cant mint more than 1 NFT");
        require(msg.value >= NFTPrice, "Value underpriced.");

        addressToNFTsMinted[msg.sender] = 1;
        _mint(msg.sender, 1);
    }

    function setWhitelist(address _address, bool _bool) public onlyOwner {
        isWhitelisted[_address] = _bool;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function pauseMint(bool _paused) external onlyOwner {
        require(!mintPaused, "Contract paused.");
        mintPaused = _paused;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

}
