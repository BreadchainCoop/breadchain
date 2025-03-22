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
/// @notice A contract for managing voting streak multipliers as NFTs
/// @dev Implements IDynamicNFTMultiplier interface

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

    /// @notice Gets the current multiplying factor for a user
    /// @param user The address of the user
    /// @return The current multiplying factor
    function getMultiplyingFactor(address user) external view override returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < 3; i++) {
            uint256 index = yieldDistributor.cycles.length - 1 - i; // Get the index for the latest, second latest, and third latest cycles
            if (index < yieldDistributor.cycles.length && yieldDistributor.cycles[index].voted[user]) {
                count++; // Increment if the user has voted in the cycle
            }
        }
        return multiplierIncrement * count;
    }

    /// @notice Gets the validity period for a user's multiplier
    /// @param user The address of the user
    /// @return The block number until which the multiplier is valid
    function validUntil(address user) external view override returns (uint256) {
        return yieldDistributor.lastClaimedBlockNumber() + yieldDistributor.cycleLength();
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
