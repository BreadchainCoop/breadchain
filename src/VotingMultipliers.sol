// VotingMultipliers.sol
pragma solidity ^0.8.22;

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VotingMultipliers is OwnableUpgradeable {
    IMultiplier[] public whitelistedMultipliers;
    IMultiplier[] public queuedMultipliersForAddition;
    IMultiplier[] public queuedMultipliersForRemoval;

    event MultiplierAdded(IMultiplier indexed multiplier);
    event MultiplierRemoved(IMultiplier indexed multiplier);

    function getTotalMultipliers(address user) external view returns (uint256) {
        uint256 totalMultiplier = 1e18; // Start with 100% (no multiplier)
        for (uint256 i = 0; i < whitelistedMultipliers.length; i++) {
            IMultiplier multiplier = whitelistedMultipliers[i];
            if (block.number <= multiplier.validUntil(user)) {
                totalMultiplier += multiplier.getMultiplyingFactor(user);
            }
        }
        return totalMultiplier;
    }

    function queueMultiplierAddition(IMultiplier _multiplier) external onlyOwner {
        queuedMultipliersForAddition.push(_multiplier);
    }

    function queueMultiplierRemoval(IMultiplier _multiplier) external onlyOwner {
        queuedMultipliersForRemoval.push(_multiplier);
    }

    function updateMultipliers() external onlyOwner {
        // Add queued multipliers
        for (uint256 i = 0; i < queuedMultipliersForAddition.length; i++) {
            whitelistedMultipliers.push(queuedMultipliersForAddition[i]);
            emit MultiplierAdded(queuedMultipliersForAddition[i]);
        }
        delete queuedMultipliersForAddition;

        // Remove queued multipliers
        for (uint256 i = 0; i < queuedMultipliersForRemoval.length; i++) {
            for (uint256 j = 0; j < whitelistedMultipliers.length; j++) {
                if (whitelistedMultipliers[j] == queuedMultipliersForRemoval[i]) {
                    whitelistedMultipliers[j] = whitelistedMultipliers[whitelistedMultipliers.length - 1];
                    whitelistedMultipliers.pop();
                    emit MultiplierRemoved(queuedMultipliersForRemoval[i]);
                    break;
                }
            }
        }
        delete queuedMultipliersForRemoval;
    }
}
