// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiplier {
    /// @notice Returns the voting multiplier for `_user`.
    function getMultiplyingFactor(address _user) external view returns (uint256);

    /// @notice Returns the validity period of the multiplier for `_user`.
    function validUntil(address _user) external view returns (uint256);
}
