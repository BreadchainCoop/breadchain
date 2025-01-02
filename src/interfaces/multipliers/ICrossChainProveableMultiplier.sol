// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IProveableMultiplier} from "src/interfaces/multipliers/IProveableMultiplier.sol";

/// @title Cross-Chain Proveable Multiplier Interface
/// @notice Interface for contracts that provide a cross-chain proveable multiplying factor
interface ICrossChainProveableMultiplier is IProveableMultiplier {
    /// @notice Get the address of the bridge contract
    /// @return The address of the contract used for cross-chain communication
    function bridge() external view returns (address);
}
