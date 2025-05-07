// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IMultiplier} from "src/interfaces/IVotingMultipliers.sol";

/// @title MockMultiplier
/// @notice A mock contract implementing the IMultiplier interface for testing purposes
contract MockMultiplier is IMultiplier {
    uint256 private _multiplyingFactor;
    uint256 private _validUntil;

    /// @notice Sets the multiplying factor and valid until block for testing
    /// @param _factor  The multiplying factor to set
    /// @param _validUntilBlock The block number until which the multiplier is valid
    function setMultiplier(uint256 _factor, uint256 _validUntilBlock) external {
        _multiplyingFactor = _factor;
        _validUntil = _validUntilBlock;
    }

    /// @notice Returns the multiplying factor for a given _user
    /// @return The multiplying factor
    function getMultiplyingFactor(address /* _user */ ) external view returns (uint256) {
        return _multiplyingFactor;
    }

    /// @notice Returns the block number until which the multiplier is valid for a given _user
    /// @return The block number until which the multiplier is valid
    function validUntil(address /* _user */ ) external view returns (uint256) {
        return _validUntil;
    }

    /// @notice Updates the multiplying factor
    /// @param _newMultiplyingFactor The new multiplying factor
    function updateMultiplyingFactor(uint256 _newMultiplyingFactor) external pure {
        _multiplyingFactor = _newMultiplyingFactor;
        return;
    }

    /// @notice This is a no-op function that exists solely to implement the IMultiplier interface
    /// @dev This function does nothing and always returns, as the actual multiplier update logic
    ///      is handled by passing a new multiplying factor to updateMultiplyingFactor(uint256)
    /// @param _user Unused parameter
    function updateMultiplyingFactor(address _user) external pure {
        return;
    }
}
