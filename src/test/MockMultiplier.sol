// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IMultiplier} from "src/interfaces/IVotingMultipliers.sol";

/// @title MockMultiplier
/// @notice A mock contract implementing the IMultiplier interface for testing purposes
contract MockMultiplier is IMultiplier {
    uint256 private _multiplyingFactor;
    uint256 private _validUntil;

    /// @notice Sets the multiplying factor and valid until block for testing
    /// @param factor The multiplying factor to set
    /// @param validUntilBlock The block number until which the multiplier is valid
    function setMultiplier(uint256 factor, uint256 validUntilBlock) external {
        _multiplyingFactor = factor;
        _validUntil = validUntilBlock;
    }

    /// @notice Returns the multiplying factor for a given user
    /// @return The multiplying factor
    function getMultiplyingFactor(address /* user */ ) external view returns (uint256) {
        return _multiplyingFactor;
    }

    /// @notice Returns the block number until which the multiplier is valid for a given user
    /// @return The block number until which the multiplier is valid
    function validUntil(address /* user */ ) external view returns (uint256) {
        return _validUntil;
    }
}
