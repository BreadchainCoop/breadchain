// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {MultiplierConstants} from "src/libraries/MultiplierConstants.sol";
import {YieldDistributor} from "src/YieldDistributor.sol";

/// @title VotingStreakMultiplier
/// @notice A contract for managing voting streak multipliers
/// @dev Implements IMultiplier and IVotingStreakMultiplier interfaces
contract VotingStreakMultiplier is Initializable, OwnableUpgradeable, IMultiplier {
    /// @notice The maximum number of times the multiplier can be incremented
    uint256 public maxMultiplierIncrements;

    /// @notice The increment value for the multiplier
    /// @dev must be a fixed-point representation of the percentage i.e. 1e18 (1%)
    uint256 public multiplierIncrement;

    /// @notice The YieldDistributor contract
    YieldDistributor public yieldDistributor;

    /// @notice Mapping of user addresses to their current multiplier factor
    mapping(address => uint256) public userToMultiplier;

    /// @notice Mapping of user addresses to their multiplier validity period
    mapping(address => uint256) public userToValidUntil;

    /// @notice lastClaimedBlockNumber of the cycle when the user's streak was last incremented
    /// @dev Prevents maxing the streak in one cycle by spamming updateMultiplyingFactor (issue #185)
    mapping(address => uint256) public userLastUpdatedCycle;

    /// @notice Error emitted when an invalid multiplier increment is provided
    error InvalidMultiplierIncrement();

    /// @notice Emitted when a user's multiplier is updated
    /// @param user The address of the user
    /// @param newFactor The new multiplier factor
    /// @param validity The new validity period
    event MultiplierUpdated(address indexed user, uint256 newFactor, uint256 validity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _yieldDistributor The address of the YieldDistributor contract
    /// @param _multiplierIncrement The initial multiplier increment value
    /// @param _maxMultiplierIncrements The maximum number of times the multiplier can be incremented
    function initialize(address _yieldDistributor, uint256 _multiplierIncrement, uint256 _maxMultiplierIncrements)
        public
        initializer
    {
        __Ownable_init(msg.sender);

        yieldDistributor = YieldDistributor(_yieldDistributor);
        multiplierIncrement = _multiplierIncrement;
        maxMultiplierIncrements = _maxMultiplierIncrements;
    }

    /// @notice Gets the current multiplying factor for a user
    /// @param user The address of the user
    /// @return The current multiplying factor
    function getMultiplyingFactor(address user) public view override returns (uint256) {
        if (
            yieldDistributor.accountLastVoted(user)
                    > yieldDistributor.lastClaimedBlockNumber() - yieldDistributor.cycleLength()
                && block.number <= userToValidUntil[user]
        ) {
            return userToMultiplier[user];
        }

        // If the user does not have a multiplier, returning 1e18 ensures that the user's voting power is not modified by this multiplier
        return MultiplierConstants.BASE_MULTIPLIER;
    }

    /// @notice Gets the validity period for a user's multiplier
    /// @param user The address of the user
    /// @return The block number until which the multiplier is valid
    function validUntil(address user) external view override returns (uint256) {
        return userToValidUntil[user];
    }

    /// @notice Updates the multiplying factor for a user
    /// @param _user The address of the user to update the multiplying factor for
    function updateMultiplyingFactor(address _user) external override {
        // Check if user has already voted in current cycle
        uint256 lastVotedBlock = yieldDistributor.accountLastVoted(_user);
        uint256 lastClaimedBlock = yieldDistributor.lastClaimedBlockNumber();
        uint256 cycleLength = yieldDistributor.cycleLength();

        // If user has already voted in current cycle, do nothing
        if (lastVotedBlock > lastClaimedBlock) {
            return;
        }

        // At most one streak increment per distribution cycle (issue #185).
        // lastClaimedBlockNumber advances each distribute, so it identifies the cycle.
        if (userLastUpdatedCycle[_user] == lastClaimedBlock) {
            return;
        }

        uint256 currentMultiplier = getMultiplyingFactor(_user);
        uint256 newMultiplier = (currentMultiplier == MultiplierConstants.BASE_MULTIPLIER)
            ? MultiplierConstants.BASE_MULTIPLIER + multiplierIncrement
            : Math.min(
                currentMultiplier + multiplierIncrement,
                (MultiplierConstants.BASE_MULTIPLIER + (maxMultiplierIncrements * multiplierIncrement))
            );

        userLastUpdatedCycle[_user] = lastClaimedBlock;
        userToMultiplier[_user] = newMultiplier;
        userToValidUntil[_user] = lastClaimedBlock + (2 * cycleLength);
        emit MultiplierUpdated(_user, newMultiplier, userToValidUntil[_user]);
    }

    /// @notice Sets the YieldDistributor contract address
    /// @param _yieldDistributor The new YieldDistributor contract address
    function setYieldDistributor(address _yieldDistributor) external onlyOwner {
        yieldDistributor = YieldDistributor(_yieldDistributor);
    }

    /// @notice Sets the multiplier increment value
    /// @param _multiplierIncrement The new multiplier increment value
    function setMultiplierIncrement(uint256 _multiplierIncrement) external onlyOwner {
        if (_multiplierIncrement == 0) {
            revert InvalidMultiplierIncrement();
        }
        multiplierIncrement = _multiplierIncrement;
    }

    /// @notice Sets the maximum number of times the multiplier can be incremented
    /// @param _maxMultiplierIncrements The new maximum number of times the multiplier can be incremented
    function setMaxMultiplierIncrements(uint256 _maxMultiplierIncrements) external onlyOwner {
        maxMultiplierIncrements = _maxMultiplierIncrements;
    }
}
