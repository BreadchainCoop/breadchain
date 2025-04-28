// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {YieldDistributor} from "src/YieldDistributor.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title VotingStreakMultiplier
/// @notice A contract for managing voting streak multipliers
/// @dev Implements IMultiplier and IVotingStreakMultiplier interfaces
contract VotingStreakMultiplier is Initializable, OwnableUpgradeable, IMultiplier {
    /// @notice The maximum multiplier incrementation
    uint256 public maxMultiplier;

    /// @notice The increment value for the multiplier
    uint256 public multiplierIncrement;

    /// @notice The YieldDistributor contract
    YieldDistributor public yieldDistributor;

    /// @notice Mapping of user addresses to their current multiplier factor
    mapping(address => uint256) public userToMultiplier;

    /// @notice Mapping of user addresses to their multiplier validity period
    mapping(address => uint256) public userToValidity;

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
    /// @param _maxMultiplier The maximum multiplier value
    function initialize(address _yieldDistributor, uint256 _multiplierIncrement, uint256 _maxMultiplier)
        public
        initializer
    {
        __Ownable_init(msg.sender);

        yieldDistributor = YieldDistributor(_yieldDistributor);
        multiplierIncrement = _multiplierIncrement;
        maxMultiplier = _maxMultiplier;
    }

    /// @notice Gets the current multiplying factor for a user
    /// @param user The address of the user
    /// @return The current multiplying factor
    function getMultiplyingFactor(address user) external view override returns (uint256) {
        if (
            yieldDistributor.accountLastVoted(user)
                > yieldDistributor.lastClaimedBlockNumber() - yieldDistributor.cycleLength()
                && block.number < userToValidity[user]
        ) {
            return userToMultiplier[user];
        }
        return 0;
    }

    /// @notice Updates the multiplying factor for a user
    /// @param user The address of the user
    function updateMultiplyingFactor(address user) external override {
        // Check if user has already voted in current cycle
        uint256 lastVotedBlock = yieldDistributor.accountLastVoted(user);
        uint256 lastClaimedBlock = yieldDistributor.lastClaimedBlockNumber();
        uint256 cycleLength = yieldDistributor.cycleLength();

        // If user has already voted in current cycle, do nothing
        if (lastVotedBlock > lastClaimedBlock - cycleLength) {
            return;
        }

        uint256 currentMultiplier = getMultiplyingFactor(user);
        uint256 newMultiplier = (currentMultiplier == 0)
            ? multiplierIncrement
            : Math.min(currentMultiplier + multiplierIncrement, maxMultiplier * multiplierIncrement);

        userToMultiplier[user] = newMultiplier;
        userToValidity[user] = yieldDistributor.lastClaimedBlockNumber() + 2 * yieldDistributor.cycleLength();
        emit MultiplierUpdated(user, newMultiplier, userToValidity[user]);
    }

    /// @notice Gets the validity period for a user's multiplier
    /// @param user The address of the user
    /// @return The block number until which the multiplier is valid
    function validUntil(address user) external view override returns (uint256) {
        return userToValidity[user];
    }

    /// @notice Sets the YieldDistributor contract address
    /// @param _yieldDistributor The new YieldDistributor contract address
    function setYieldDistributor(address _yieldDistributor) external onlyOwner {
        yieldDistributor = YieldDistributor(_yieldDistributor);
    }

    /// @notice Sets the multiplier increment value
    /// @param _multiplierIncrement The new multiplier increment value
    function setMultiplierIncrement(uint256 _multiplierIncrement) external onlyOwner {
        multiplierIncrement = _multiplierIncrement;
    }

    /// @notice Sets the maximum multiplier value
    /// @param _maxMultiplier The new maximum multiplier value
    function setMaxMultiplier(uint256 _maxMultiplier) external onlyOwner {
        maxMultiplier = _maxMultiplier;
    }
}
