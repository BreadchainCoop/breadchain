// IMultiplier.sol
pragma solidity ^0.8.22;

interface IMultiplier {
    function getMultiplyingFactor(address user) external view returns (uint256);
    function validUntil(address user) external view returns (uint256);
}

// INFTMultiplier.sol
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IMultiplier.sol";

interface INFTMultiplier is IMultiplier {
    function NFTAddress() external view returns (IERC721);
    function hasNFT(address user) external view returns (bool);
}

// PermanentNFTMultiplier.sol
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./INFTMultiplier.sol";

contract PermanentNFTMultiplier is INFTMultiplier {
    IERC721 public immutable NFTAddress;
    uint256 public immutable multiplyingFactor;
    uint256 public constant validity = type(uint256).max;

    constructor(IERC721 _nftAddress, uint256 _multiplyingFactor) {
        NFTAddress = _nftAddress;
        multiplyingFactor = _multiplyingFactor;
    }

    function getMultiplyingFactor(address user) external view override returns (uint256) {
        return hasNFT(user) ? multiplyingFactor : 0;
    }

    function validUntil(address) external pure override returns (uint256) {
        return validity;
    }

    function hasNFT(address user) public view override returns (bool) {
        return NFTAddress.balanceOf(user) > 0;
    }
}

// DynamicNFTMultiplier.sol
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./INFTMultiplier.sol";

contract DynamicNFTMultiplier is INFTMultiplier {
    IERC721 public immutable NFTAddress;
    mapping(address => uint256) public userToFactor;
    mapping(address => uint256) public userToValidity;

    constructor(IERC721 _nftAddress) {
        NFTAddress = _nftAddress;
    }

    function getMultiplyingFactor(address user) external view override returns (uint256) {
        return hasNFT(user) ? userToFactor[user] : 0;
    }

    function validUntil(address user) external view override returns (uint256) {
        return userToValidity[user];
    }

    function hasNFT(address user) public view override returns (bool) {
        return NFTAddress.balanceOf(user) > 0;
    }

    function setUserFactor(address user, uint256 factor, uint256 validity) external {
        // Add appropriate access control
        require(hasNFT(user), "User does not have the required NFT");
        userToFactor[user] = factor;
        userToValidity[user] = validity;
    }
}