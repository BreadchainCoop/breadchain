// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IVotingMultipliers, IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title VotingMultipliers
/// @notice A contract for managing voting multipliers
/// @dev Implements IVotingMultipliers interface
contract VotingMultipliers is OwnableUpgradeable, IVotingMultipliers {
    /// @notice Array of allowlisted multiplier contracts
    IMultiplier[] public allowlistedMultipliers;

    /// @notice Calculates the total multiplier for a given user
    /// @param user The address of the user
    /// @return The total multiplier value for the user
    function getTotalMultipliers(address user) public view returns (uint256) {
        uint256 totalMultiplier = 0;
        for (uint256 i = 0; i < allowlistedMultipliers.length; i++) {
            IMultiplier multiplier = allowlistedMultipliers[i];
            if (block.number <= multiplier.validUntil(user)) {
                totalMultiplier += multiplier.getMultiplyingFactor(user);
            }
        }
        return totalMultiplier;
    }

    /// @notice Adds a multiplier to the allowlist
    /// @param _multiplier The multiplier contract to be added
    function addMultiplier(IMultiplier _multiplier) external onlyOwner {
        // Check if the multiplier is already allowlisted
        for (uint256 i = 0; i < allowlistedMultipliers.length; i++) {
            if (allowlistedMultipliers[i] == _multiplier) {
                revert MultiplierAlreadyAllowlisted();
            }
        }
        allowlistedMultipliers.push(_multiplier);
        emit MultiplierAdded(_multiplier);
    }

    /// @notice Removes a multiplier from the allowlist
    /// @param _multiplier The multiplier contract to be removed
    function removeMultiplier(IMultiplier _multiplier) external onlyOwner {
        bool isAllowListed = false;
        for (uint256 i = 0; i < allowlistedMultipliers.length; i++) {
            if (allowlistedMultipliers[i] == _multiplier) {
                allowlistedMultipliers[i] = allowlistedMultipliers[allowlistedMultipliers.length - 1];
                allowlistedMultipliers.pop();
                isAllowListed = true;
                emit MultiplierRemoved(_multiplier);
                break;
            }
        }
        if (!isAllowListed) {
            revert MultiplierNotAllowlisted();
        }
    }
}
