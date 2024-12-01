// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IVotingMultipliers, IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title VotingMultipliers
/// @notice A contract for managing voting multipliers
/// @dev Implements IVotingMultipliers interface
contract VotingMultipliers is OwnableUpgradeable, IVotingMultipliers {
    /// @notice Array of whitelisted multiplier contracts
    IMultiplier[] public whitelistedMultipliers;

    /// @notice Calculates the total multiplier for a given user
    /// @param user The address of the user
    /// @return The total multiplier value for the user
    function getTotalMultipliers(address user) public view returns (uint256) {
        uint256 totalMultiplier = 0;
        for (uint256 i = 0; i < whitelistedMultipliers.length; i++) {
            IMultiplier multiplier = whitelistedMultipliers[i];
            if (block.number <= multiplier.validUntil(user)) {
                totalMultiplier += multiplier.getMultiplyingFactor(user);
            }
        }
        return totalMultiplier;
    }

    /// @notice Adds a multiplier to the whitelist
    /// @param _multiplier The multiplier contract to be added
    function addMultiplier(IMultiplier _multiplier) external onlyOwner {
        // Check if the multiplier is already whitelisted
        for (uint256 i = 0; i < whitelistedMultipliers.length; i++) {
            if (whitelistedMultipliers[i] == _multiplier) {
                revert MultiplierAlreadyWhitelisted();
            }
        }
        whitelistedMultipliers.push(_multiplier);
        emit MultiplierAdded(_multiplier);
    }

    /// @notice Removes a multiplier from the whitelist
    /// @param _multiplier The multiplier contract to be removed
    function removeMultiplier(IMultiplier _multiplier) external onlyOwner {
        bool isWhitelisted = false;
        for (uint256 i = 0; i < whitelistedMultipliers.length; i++) {
            if (whitelistedMultipliers[i] == _multiplier) {
                whitelistedMultipliers[i] = whitelistedMultipliers[whitelistedMultipliers.length - 1];
                whitelistedMultipliers.pop();
                isWhitelisted = true;
                emit MultiplierRemoved(_multiplier);
                break;
            }
        }
        if (!isWhitelisted) {
            revert MultiplierNotWhitelisted();
        }
    }
}
