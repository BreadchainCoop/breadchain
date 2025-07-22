// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title UpgradeTimelock
 * @notice Timelock controller specifically designed for managing upgrades of transparent proxies.
 *         This contract enforces a time delay between proposal and execution of proxy upgrades.
 * 
 * @dev This contract is a wrapper around OpenZeppelin's TimelockControllerUpgradeable,
 *      providing convenience functions for proxy upgrades while maintaining full compatibility
 *      with the standard timelock interface.
 */
contract UpgradeTimelock is TimelockControllerUpgradeable {

    /**
     * @notice Initialize the timelock controller
     * @param minDelay The minimum delay for operations
     * @param proposers Array of addresses that can propose operations
     * @param executors Array of addresses that can execute operations
     * @param admin Optional account to be granted admin role (can be zero address)
     */
    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors, admin);
    }

    /**
     * @notice Get a deterministic salt for upgrade operations
     * @param proxy The proxy address
     * @param newImplementation The new implementation address
     * @return salt The deterministic salt
     */
    function getUpgradeSalt(address proxy, address newImplementation) external pure returns (bytes32 salt) {
        return keccak256(abi.encodePacked("UPGRADE", proxy, newImplementation));
    }

    /**
     * @notice Helper to get the operation ID for a proxy upgrade
     * @param proxy The proxy address
     * @param newImplementation The new implementation address
     * @return operationId The operation identifier
     */
    function getUpgradeOperationId(address proxy, address newImplementation) external pure returns (bytes32 operationId) {
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", newImplementation);
        bytes32 salt = keccak256(abi.encodePacked("UPGRADE", proxy, newImplementation));
        // Manual hash calculation to avoid type conversion issues
        return keccak256(abi.encode(proxy, 0, keccak256(upgradeCalldata), bytes32(0), salt));
    }

    /**
     * @notice Check if a proxy upgrade is ready for execution
     * @param proxy The proxy address
     * @param newImplementation The new implementation address
     * @return ready True if the upgrade can be executed
     */
    function isUpgradeReady(address proxy, address newImplementation) external view returns (bool ready) {
        bytes32 operationId = this.getUpgradeOperationId(proxy, newImplementation);
        return isOperationReady(operationId);
    }

    /**
     * @notice Get the timestamp when an upgrade will be ready
     * @param proxy The proxy address
     * @param newImplementation The new implementation address
     * @return timestamp The ready timestamp
     */
    function getUpgradeTimestamp(address proxy, address newImplementation) external view returns (uint256 timestamp) {
        bytes32 operationId = this.getUpgradeOperationId(proxy, newImplementation);
        return getTimestamp(operationId);
    }
}