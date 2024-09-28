// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {INFTMultiplier} from "src/interfaces/multipliers/INFTMultiplier.sol";

/// @title Permanent NFT Multiplier
/// @notice This contract provides a permanent multiplying factor for users based on NFT ownership
/// @dev Implements the INFTMultiplier interface
contract PermanentNFTMultiplier is INFTMultiplier {
    /// @notice The address of the NFT contract
    IERC721 public immutable NFTAddress;
    /// @notice The multiplying factor applied to NFT holders
    uint256 public immutable factor;

    /// @notice Constructs the PermanentNFTMultiplier contract
    /// @param _nftAddress The address of the NFT contract to check for ownership
    /// @param _factor The multiplying factor to apply to NFT holders
    constructor(IERC721 _nftAddress, uint256 _factor) {
        NFTAddress = _nftAddress;
        factor = _factor;
    }

    /// @notice Get the multiplying factor for a user
    /// @param user The address of the user
    /// @return The multiplying factor if the user has an NFT, 0 otherwise
    function getMultiplyingFactor(address user) external view override returns (uint256) {
        return hasNFT(user) ? factor : 0;
    }

    /// @notice Get the validity period for a user's factor
    /// @return Always returns type(uint256).max as the factor is permanent
    function validUntil(address /* user */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Check if a user owns an NFT
    /// @param user The address of the user to check
    /// @return True if the user owns at least one NFT, false otherwise
    function hasNFT(address user) public view override returns (bool) {
        return NFTAddress.balanceOf(user) > 0;
    }
}
