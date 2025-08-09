// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/governance/TimelockControllerUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TimelockUpgradeController
 * @notice Manages upgrades to Breadchain contracts with a mandatory timelock delay
 * @dev This contract enforces a time delay between proposal and execution of upgrades
 * @author Breadchain Collective
 */
contract TimelockUpgradeController is TimelockControllerUpgradeable {
    /// @notice The minimum delay for upgrades (48 hours)
    uint256 public constant UPGRADE_TIMELOCK_DELAY = 48 hours;

    /// @notice Event emitted when an upgrade is proposed
    event UpgradeProposed(
        address indexed implementation, address indexed proxy, bytes32 indexed operationId, uint256 executeAfter
    );

    /// @notice Event emitted when an upgrade is executed
    event UpgradeExecuted(address indexed implementation, address indexed proxy, bytes32 indexed operationId);

    /// @notice Event emitted when an upgrade is cancelled
    event UpgradeCancelled(bytes32 indexed operationId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the timelock controller
     * @param proposers Array of addresses that can propose upgrades (multisig)
     * @param executors Array of addresses that can execute upgrades after timelock
     * @param admin Optional admin address for initial setup (should be renounced after)
     */
    function initialize(address[] memory proposers, address[] memory executors, address admin) public initializer {
        __TimelockController_init(UPGRADE_TIMELOCK_DELAY, proposers, executors, admin);
    }

    /**
     * @notice Propose an upgrade to a UUPS proxy contract
     * @param proxy Address of the proxy contract to upgrade
     * @param newImplementation Address of the new implementation contract
     * @param data Optional initialization data for the upgrade
     * @param salt Salt for operation uniqueness
     * @return operationId The ID of the scheduled operation
     */
    function proposeUpgrade(address proxy, address newImplementation, bytes calldata data, bytes32 salt)
        external
        onlyRole(PROPOSER_ROLE)
        returns (bytes32 operationId)
    {
        // Encode the upgrade call
        bytes memory upgradeCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, 
            newImplementation, 
            data
        );
        
        // Calculate the operation ID
        operationId = keccak256(abi.encode(proxy, uint256(0), upgradeCall, bytes32(0), salt));
        
        // Schedule using internal helper
        _scheduleUpgrade(proxy, upgradeCall, salt);
        
        uint256 executeAfter = block.timestamp + UPGRADE_TIMELOCK_DELAY;
        emit UpgradeProposed(newImplementation, proxy, operationId, executeAfter);
    }

    /**
     * @notice Execute a previously proposed upgrade after timelock expires
     * @param proxy Address of the proxy contract to upgrade
     * @param newImplementation Address of the new implementation contract
     * @param data Optional initialization data for the upgrade
     * @param salt Salt used when proposing the upgrade
     */
    function executeUpgrade(address proxy, address newImplementation, bytes calldata data, bytes32 salt) 
        external 
        payable
        onlyRoleOrOpenRole(EXECUTOR_ROLE) 
    {
        // Encode the upgrade call
        bytes memory upgradeCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, 
            newImplementation, 
            data
        );
        
        bytes32 operationId = keccak256(abi.encode(proxy, uint256(0), upgradeCall, bytes32(0), salt));
        
        // Execute using internal helper
        _executeUpgrade(proxy, upgradeCall, salt);
        
        emit UpgradeExecuted(newImplementation, proxy, operationId);
    }

    /**
     * @notice Cancel a proposed upgrade
     * @param proxy Address of the proxy contract
     * @param newImplementation Address of the new implementation contract
     * @param data Optional initialization data
     * @param salt Salt used when proposing the upgrade
     */
    function cancelUpgrade(address proxy, address newImplementation, bytes calldata data, bytes32 salt) 
        external
        onlyRole(CANCELLER_ROLE)
    {
        // Encode the upgrade call
        bytes memory upgradeCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, 
            newImplementation, 
            data
        );
        
        bytes32 operationId = keccak256(abi.encode(proxy, uint256(0), upgradeCall, bytes32(0), salt));
        
        // Cancel the operation
        cancel(operationId);
        
        emit UpgradeCancelled(operationId);
    }

    /**
     * @notice Get the status and timing of a proposed upgrade
     * @param proxy Address of the proxy contract
     * @param newImplementation Address of the new implementation contract
     * @param data Optional initialization data
     * @param salt Salt used when proposing the upgrade
     * @return isScheduled Whether the upgrade is scheduled
     * @return isReady Whether the timelock has expired and upgrade can be executed
     * @return timestamp When the upgrade can be executed (0 if not scheduled)
     */
    function getUpgradeStatus(address proxy, address newImplementation, bytes calldata data, bytes32 salt)
        external
        view
        returns (bool isScheduled, bool isReady, uint256 timestamp)
    {
        // Encode the upgrade call
        bytes memory upgradeCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, 
            newImplementation, 
            data
        );
        
        bytes32 operationId = keccak256(abi.encode(proxy, uint256(0), upgradeCall, bytes32(0), salt));
        
        timestamp = getTimestamp(operationId);
        isScheduled = isOperationPending(operationId);
        isReady = isOperationReady(operationId);
    }

    /**
     * @dev Internal helper to schedule an upgrade
     */
    function _scheduleUpgrade(address proxy, bytes memory upgradeCall, bytes32 salt) internal {
        // Schedule by calling parent's schedule with a bytes calldata wrapper
        this.scheduleWithCalldata(proxy, upgradeCall, salt);
    }

    /**
     * @dev Internal helper to execute an upgrade
     */
    function _executeUpgrade(address proxy, bytes memory upgradeCall, bytes32 salt) internal {
        // Execute by calling parent's execute with a bytes calldata wrapper
        this.executeWithCalldata(proxy, upgradeCall, salt);
    }

    /**
     * @notice Schedule wrapper that accepts bytes memory
     */
    function scheduleWithCalldata(address target, bytes calldata data, bytes32 salt) 
        external 
        onlyRole(PROPOSER_ROLE) 
    {
        schedule(target, 0, data, 0, salt, UPGRADE_TIMELOCK_DELAY);
    }

    /**
     * @notice Execute wrapper that accepts bytes memory
     */
    function executeWithCalldata(address target, bytes calldata data, bytes32 salt) 
        external 
        payable
        onlyRoleOrOpenRole(EXECUTOR_ROLE) 
    {
        execute(target, 0, data, 0, salt);
    }
}