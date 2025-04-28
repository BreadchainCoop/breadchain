// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiplier {
    /// @notice Updates the multiplying factor
    /// @param _newMultiplyingFactor The new multiplying factor
    function updateMultiplyingFactor(uint256 _newMultiplyingFactor) external;

    /// @notice Updates the multiplying factor
    function updateMultiplyingFactor() external;

    /// @notice Returns the multiplying factor for `_user`.
    function getMultiplyingFactor(address _user) external view returns (uint256);

    /// @notice Returns the validity period of the multiplier for `_user`.
    function validUntil(address _user) external view returns (uint256);
}
