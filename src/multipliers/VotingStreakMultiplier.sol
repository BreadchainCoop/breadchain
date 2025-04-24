// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {YieldDistributor} from "src/YieldDistributor.sol";
import {IVotingStreakMultiplier} from "src/interfaces/multipliers/IVotingStreakMultiplier.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title VotingStreakMultiplier
/// @notice A contract for managing voting streak multipliers
/// @dev Implements IMultiplier and IVotingStreakMultiplier interfaces
contract VotingStreakMultiplier is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    IMultiplier,
    IVotingStreakMultiplier
{
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
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);

        yieldDistributor = YieldDistributor(_yieldDistributor);
        multiplierIncrement = _multiplierIncrement;
        maxMultiplier = _maxMultiplier;
    }

    /// @notice Updates the user's multiplier when a vote is cast
    /// @param voter The address of the voter
    function onVoteCast(address voter) external {
        require(msg.sender == address(yieldDistributor), "Only YieldDistributor can call");

        uint256 currentMultiplier = getMultiplyingFactor(voter);
        uint256 newMultiplier = (currentMultiplier == 0)
            ? multiplierIncrement
            : Math.min(currentMultiplier + multiplierIncrement, maxMultiplier * multiplierIncrement);

        userToMultiplier[voter] = newMultiplier;
        userToValidity[voter] = yieldDistributor.lastClaimedBlockNumber() + 2 * yieldDistributor.cycleLength();

        emit MultiplierUpdated(voter, newMultiplier, userToValidity[voter]);
    }

    /// @notice Gets the current multiplying factor for a user
    /// @param user The address of the user
    /// @return The current multiplying factor
    function getMultiplyingFactor(address user) external view override returns (uint256) {
        if (block.number > userToValidity[user]) {
            return 0;
        }
        return userToMultiplier[user];
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
