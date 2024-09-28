// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title IVotingStreakMultiplier
/// @notice Interface for the VotingStreakMultiplier contract
/// @dev This interface is used by the YieldDistributor to interact with the VotingStreakMultiplier
interface IVotingStreakMultiplier {
    /// @notice Updates the user's multiplier when a vote is cast
    /// @param voter The address of the voter
    function onVoteCast(address voter) external;
}
