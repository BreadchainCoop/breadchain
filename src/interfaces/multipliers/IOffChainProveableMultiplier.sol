// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IProveableMultiplier} from "src/interfaces/multipliers/IProveableMultiplier.sol";

/// @title Off-Chain Proveable Multiplier Interface
/// @notice Interface for contracts that provide an off-chain proveable multiplying factor
interface IOffChainProveableMultiplier is IProveableMultiplier {
    /// @notice Get the address of the pull oracle
    /// @return The address of the oracle used for off-chain data verification
    function oracle() external view returns (address);
}
