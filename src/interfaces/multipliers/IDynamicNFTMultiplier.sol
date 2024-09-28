// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {INFTMultiplier} from "src/interfaces/multipliers/INFTMultiplier.sol";
/// @title Dynamic NFT Multiplier Interface
/// @notice Interface for contracts that provide a dynamic multiplying factor for users based on NFT ownership
/// @dev Extends the INFTMultiplier interface with dynamic multiplier functionality

interface IDynamicNFTMultiplier is INFTMultiplier {
    /// @notice Get the multiplying factor for a user
    /// @param user The address of the user
    /// @return The multiplying factor for the user
    function userToFactor(address user) external view returns (uint256);

    /// @notice Get the validity period for a user's factor
    /// @param user The address of the user
    /// @return The timestamp until which the user's factor is valid
    function userToValidity(address user) external view returns (uint256);
}
