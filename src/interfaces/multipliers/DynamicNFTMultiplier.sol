// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./INFTMultiplier.sol";

/// @title Dynamic NFT Multiplier
/// @notice This contract provides a dynamic multiplying factor for users based on NFT ownership
/// @dev Implements the INFTMultiplier interface
contract DynamicNFTMultiplier is INFTMultiplier {
    /// @notice The address of the NFT contract
    IERC721 public immutable NFTAddress;

    /// @notice Mapping of user addresses to their multiplying factors
    mapping(address => uint256) public userToFactor;

    /// @notice Mapping of user addresses to the validity period of their multiplying factors
    mapping(address => uint256) public userToValidity;

    /// @notice Constructs the DynamicNFTMultiplier contract
    /// @param _nftAddress The address of the NFT contract to check for ownership
    constructor(IERC721 _nftAddress) {
        NFTAddress = _nftAddress;
    }

    /// @notice Get the multiplying factor for a user
    /// @param user The address of the user
    /// @return The multiplying factor if the user has an NFT, 0 otherwise
    function getMultiplyingFactor(address user) external view override returns (uint256) {
        return hasNFT(user) ? userToFactor[user] : 0;
    }

    /// @notice Get the validity period for a user's factor
    /// @param user The address of the user
    /// @return The timestamp until which the user's factor is valid
    function validUntil(address user) external view override returns (uint256) {
        return userToValidity[user];
    }

    /// @notice Check if a user owns an NFT
    /// @param user The address of the user to check
    /// @return True if the user owns at least one NFT, false otherwise
    function hasNFT(address user) public view override returns (bool) {
        return NFTAddress.balanceOf(user) > 0;
    }
}
