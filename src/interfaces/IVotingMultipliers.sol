pragma solidity ^0.8.22;

import {IMultiplier} from "./multipliers/IMultiplier.sol";

/// @title IVotingMultipliers
/// @notice Interface for the VotingMultipliers contract
/// @dev This interface defines the structure and functions for managing voting multipliers
interface IVotingMultipliers {
    /// @notice Thrown when attempting to add a multiplier that is already whitelisted
    error MultiplierAlreadyWhitelisted();
    /// @notice Thrown when attempting to remove a multiplier that is not whitelisted
    error MultiplierNotWhitelisted();
    /// @notice Emitted when a new multiplier is added to the whitelist
    /// @param multiplier The address of the added multiplier

    event MultiplierAdded(IMultiplier indexed multiplier);
    /// @notice Emitted when a multiplier is removed from the whitelist
    /// @param multiplier The address of the removed multiplier
    event MultiplierRemoved(IMultiplier indexed multiplier);
    /// @notice Returns the multiplier at the specified index in the whitelist
    /// @param index The index of the multiplier in the whitelist
    /// @return The multiplier contract at the specified index

    function whitelistedMultipliers(uint256 index) external view returns (IMultiplier);
    /// @notice Calculates the total multiplier for a given user
    /// @param user The address of the user
    /// @return The total multiplier value for the user
    function getTotalMultipliers(address user) external view returns (uint256);
    /// @notice Adds a multiplier to the whitelist
    /// @param _multiplier The multiplier contract to be added
    function addMultiplier(IMultiplier _multiplier) external;
    /// @notice Removes a multiplier from the whitelist
    /// @param _multiplier The multiplier contract to be removed
    function removeMultiplier(IMultiplier _multiplier) external;
}
