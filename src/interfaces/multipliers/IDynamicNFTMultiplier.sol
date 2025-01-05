// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {INFTMultiplier} from "src/interfaces/multipliers/INFTMultiplier.sol";
/// @title Dynamic NFT Multiplier Interface
/// @notice Interface for contracts that provide a dynamic multiplying factor for _users based on NFT ownership
/// @dev Extends the INFTMultiplier interface with dynamic multiplier functionality
interface IDynamicNFTMultiplier is INFTMultiplier {
    /// @notice Get the multiplying factor for a _user
    /// @param _user The address of the _user
    /// @return The multiplying factor for the _user
    function userToFactor(address _user) external view returns (uint256);

    /// @notice Get the validity period for a _user's factor
    /// @param _user The address of the _user
    /// @return The timestamp until which the _user's factor is valid
    function _userToValidity(address _user) external view returns (uint256);
}
