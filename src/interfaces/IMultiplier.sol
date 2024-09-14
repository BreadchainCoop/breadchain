// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiplier {
    /// @notice Returns the voting multiplier for `user`.
    function getMultiplyingFactor(address user) external view returns (uint256);

    /// @notice Returns the validity period of the multiplier for `user`.
    function validUntil(address user) external view returns (uint256);
}
