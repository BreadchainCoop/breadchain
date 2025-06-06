// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IVotingMultipliers, IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title VotingMultipliers
/// @notice A contract for managing voting multipliers
/// @dev Implements IVotingMultipliers interface
contract VotingMultipliers is Ownable2StepUpgradeable, IVotingMultipliers {
    /// @notice Array of allowlisted multiplier contracts
    IMultiplier[] public allowlistedMultipliers;

    /// @notice Initializes the contract
    function initialize() public initializer {
        __Ownable_init(msg.sender);
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
        bool isallowlisted = false;
        for (uint256 i = 0; i < allowlistedMultipliers.length; i++) {
            if (allowlistedMultipliers[i] == _multiplier) {
                allowlistedMultipliers[i] = allowlistedMultipliers[allowlistedMultipliers.length - 1];
                allowlistedMultipliers.pop();
                isallowlisted = true;
                emit MultiplierRemoved(_multiplier);
                break;
            }
        }
        if (!isallowlisted) {
            revert MultiplierNotAllowlisted();
        }
    }

    /// @notice Gets the indexes of valid multipliers for a user
    /// @param _user The address of the user
    /// @return uint256[] Array of valid multiplier indexes
    function getValidMultiplierIndexes(address _user) public view returns (uint256[] memory) {
        uint256[] memory validIndexes = new uint256[](allowlistedMultipliers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allowlistedMultipliers.length; i++) {
            if (
                block.number <= allowlistedMultipliers[i].validUntil(_user)
                    && allowlistedMultipliers[i].getMultiplyingFactor(_user) > 0
            ) {
                validIndexes[count] = i;
                count++;
            }
        }

        // Create correctly sized array
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = validIndexes[i];
        }
        return result;
    }

    /// @notice Calculates the total multiplier for a given user using specific multiplier indexes
    /// @notice Performs the updateMultiplyingFactor function for each multiplier to ensure the multiplier is up to date
    /// @param _user The address of the user
    /// @param _multiplierIndexes Array of multiplier indexes to use
    /// @return The total multiplier value for the user
    function calculateTotalMultipliers(address _user, uint256[] calldata _multiplierIndexes) public returns (uint256) {
        uint256 _totalMultiplier = MultiplierConstants.BASE_MULTIPLIER;

        for (uint256 i = 0; i < _multiplierIndexes.length; i++) {
            uint256 index = _multiplierIndexes[i];
            if (index >= allowlistedMultipliers.length) {
                revert InvalidMultiplierIndex();
            }

            IMultiplier multiplier = allowlistedMultipliers[index];
            multiplier.updateMultiplyingFactor(_user);
            if (block.number <= multiplier.validUntil(_user)) {
                uint256 factor = multiplier.getMultiplyingFactor(_user);
                if (factor > MultiplierConstants.BASE_MULTIPLIER) {
                    // Add only the bonus amount to the total
                    _totalMultiplier += (factor - MultiplierConstants.BASE_MULTIPLIER);
                }
            }
        }
        return Math.max(_totalMultiplier, MultiplierConstants.BASE_MULTIPLIER);
    }

    /// @notice Calculates the total multiplier for a given user
    /// @param _user The address of the _user
    /// @return The total multiplier value for the _user
    /// @dev This function is intended for frontend and testing purposes
    function getTotalMultipliers(address _user) public view returns (uint256) {
        uint256 _totalMultiplier = MultiplierConstants.BASE_MULTIPLIER;
        for (uint256 i = 0; i < allowlistedMultipliers.length; i++) {
            IMultiplier multiplier = allowlistedMultipliers[i];
            if (block.number <= multiplier.validUntil(_user)) {
                uint256 factor = multiplier.getMultiplyingFactor(_user);
                if (factor > MultiplierConstants.BASE_MULTIPLIER) {
                    // Add only the bonus amount to the total
                    _totalMultiplier += (factor - MultiplierConstants.BASE_MULTIPLIER);
                }
            }
        }
        return Math.max(_totalMultiplier, MultiplierConstants.BASE_MULTIPLIER);
    }
}
