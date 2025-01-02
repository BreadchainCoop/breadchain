// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IProveableMultiplier} from "src/interfaces/multipliers/IProveableMultiplier.sol";
/// @title On-Chain Proveable Multiplier Interface
/// @notice Interface for contracts that provide an on-chain proveable multiplying factor
interface IOnChainProveableMultiplier is IProveableMultiplier {
    /// @notice Get the address of the activity contract
    /// @return The address of the contract used for verifying on-chain activities
    function activityContract() external view returns (address);
}
