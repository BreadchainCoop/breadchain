// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

/**
 * @title `YieldDistributor` interface
 */
interface IYieldDistributor {
    /// @notice The error emitted when attempting to add a project that is already in the `projects` array
    error AlreadyMemberProject();
    /// @notice The error emitted when a user attempts to vote without the minimum required voting power
    error BelowMinRequiredVotingPower();
    /// @notice The error emitted when attempting to calculate voting power for a period that has not yet ended
    error EndAfterCurrentBlock();
    /// @notice The error emitted when attempting to vote with a point value greater than `pointsMax`
    error ExceedsMaxPoints();
    /// @notice The error emitted when attempting to vote with an incorrect number of projects
    error IncorrectNumberOfProjects();
    /// @notice The error emitted when attempting to instantiate a variable with a zero value
    error MustBeGreaterThanZero();
    /// @notice The error emitted when attempting to add or remove a project that is already queued for addition or removal
    error ProjectAlreadyQueued();
    /// @notice The error emitted when attempting to remove a project that is not in the `projects` array
    error ProjectNotFound();
    /// @notice The error emitted when attempting to calculate voting power for a period with a start block greater than the end block
    error StartMustBeBeforeEnd();
    /// @notice The error emitted when attempting to distribute yield when access conditions are not met
    error YieldNotResolved();
    /// @notice The error emitted if a user with zero points attempts to cast votes
    error ZeroVotePoints();

    /// @notice The event emitted when an account casts a vote
    event BreadHolderVoted(address indexed account, uint256[] points, address[] projects);
    /// @notice The event emitted when a project is added as eligibile for yield distribution
    event ProjectAdded(address project);
    /// @notice The event emitted when a project is removed as eligibile for yield distribution
    event ProjectRemoved(address project);
    /// @notice The event emitted when yield is distributed
    event YieldDistributed(uint256 yield, uint256 totalVotes, uint256[] projectDistributions);
}
