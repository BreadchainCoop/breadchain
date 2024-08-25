// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiplier {
    // Function to get the multiplying factor for a specific address
    function getMultiplyingFactor(address user) external view returns (uint256);

    // Function to get the validity period for a specific address
    function validUntil(address user) external view returns (uint256);
}