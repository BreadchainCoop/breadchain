// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {INFTMultiplier} from "src/interfaces/multipliers/INFTMultiplier.sol";

/// @title Permanent NFT Multiplier
/// @notice This contract provides a permanent multiplying factor for _users based on NFT ownership
/// @dev Implements the INFTMultiplier interface
contract PermanentNFTMultiplier is INFTMultiplier {
    /// @notice The address of the NFT contract
    IERC721 public immutable NFT_ADDRESS;
    /// @notice The multiplying factor applied to NFT holders
    uint256 public immutable FACTOR;

    /// @notice Constructs the PermanentNFTMultiplier contract
    /// @param _NFT_ADDRESS The address of the NFT contract to check for ownership
    /// @param _FACTOR The multiplying factor to apply to NFT holders
    constructor(IERC721 _NFT_ADDRESS, uint256 _FACTOR) {
        NFT_ADDRESS = _NFT_ADDRESS;
        FACTOR = _FACTOR;
    }

    /// @notice Get the multiplying factor for a _user
    /// @param _user The address of the _user
    /// @return The multiplying factor if the _user has an NFT, 0 otherwise
    function getMultiplyingFactor(address _user) external view override returns (uint256) {
        return hasNFT(_user) ? FACTOR : 0;
    }

    /// @notice Get the validity period for a _user's factor
    /// @return Always returns type(uint256).max as the factor is permanent
    function validUntil(
        address /* _user */
    )
        external
        pure
        override
        returns (uint256)
    {
        return type(uint256).max;
    }

    /// @notice Check if a _user owns an NFT
    /// @param _user The address of the _user to check
    /// @return True if the _user owns at least one NFT, false otherwise
    function hasNFT(address _user) public view override returns (bool) {
        return NFT_ADDRESS.balanceOf(_user) > 0;
    }

    /// @notice Updates the multiplying factor for a specific user
    function updateMultiplyingFactor(
        address /* _user */
    )
        external
        pure
        override
    {
        return;
    }
}
