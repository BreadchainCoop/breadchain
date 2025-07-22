// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeTimelock} from "../src/UpgradeTimelock.sol";
import {YieldDistributor} from "../src/YieldDistributor.sol";

/**
 * @title UpgradeTimelockTest
 * @notice Tests for the UpgradeTimelock contract functionality
 */
contract UpgradeTimelockTest is Test {
    UpgradeTimelock public timelock;
    TransparentUpgradeableProxy public timelockProxy;
    
    // Test proxy and implementations
    TransparentUpgradeableProxy public testProxy;
    YieldDistributor public implementationV1;
    YieldDistributor public implementationV2;
    
    // Test accounts
    address public admin = makeAddr("admin");
    address public proposer = makeAddr("proposer");
    address public executor = makeAddr("executor");
    address public unauthorized = makeAddr("unauthorized");
    
    // Timelock configuration
    uint256 public constant MIN_DELAY = 1 days;

    function setUp() public {
        // Deploy timelock implementation
        UpgradeTimelock timelockImpl = new UpgradeTimelock();
        
        // Setup roles
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        
        address[] memory executors = new address[](1);
        executors[0] = executor;
        
        // Initialize timelock via proxy
        bytes memory initData = abi.encodeCall(
            UpgradeTimelock.initialize,
            (MIN_DELAY, proposers, executors, admin)
        );
        
        timelockProxy = new TransparentUpgradeableProxy(
            address(timelockImpl),
            admin,
            initData
        );
        
        timelock = UpgradeTimelock(payable(address(timelockProxy)));
        
        // Deploy test implementations
        implementationV1 = new YieldDistributor();
        implementationV2 = new YieldDistributor();
        
        // Deploy a test proxy that will be managed by the timelock
        testProxy = new TransparentUpgradeableProxy(
            address(implementationV1),
            address(timelock), // Timelock is the proxy admin
            ""
        );
    }

    function test_Initialize() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), executor));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_GetUpgradeSalt() public view {
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        assertTrue(salt != bytes32(0));
        
        // Salt should be deterministic
        bytes32 salt2 = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        assertEq(salt, salt2);
    }

    function test_GetUpgradeOperationId() public view {
        bytes32 operationId = timelock.getUpgradeOperationId(address(testProxy), address(implementationV2));
        assertTrue(operationId != bytes32(0));
    }

    function test_ScheduleUpgrade() public {
        // Prepare upgrade parameters
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelock.getMinDelay();
        
        // Schedule the upgrade
        vm.prank(proposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        // Verify the operation was scheduled
        bytes32 operationId = timelock.getUpgradeOperationId(address(testProxy), address(implementationV2));
        assertTrue(timelock.isOperation(operationId));
        assertFalse(timelock.isUpgradeReady(address(testProxy), address(implementationV2)));
    }

    function test_ExecuteUpgrade_AfterDelay() public {
        // First schedule the upgrade
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelock.getMinDelay();
        
        vm.prank(proposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        // Fast forward time
        vm.warp(block.timestamp + MIN_DELAY + 1);
        
        // Verify upgrade is ready
        assertTrue(timelock.isUpgradeReady(address(testProxy), address(implementationV2)));
        
        // Execute upgrade
        vm.prank(executor);
        timelock.execute(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt
        );
        
        // Verify operation is marked as done
        bytes32 operationId = timelock.getUpgradeOperationId(address(testProxy), address(implementationV2));
        assertTrue(timelock.isOperationDone(operationId));
    }

    function test_ExecuteUpgrade_BeforeDelayFails() public {
        // Schedule upgrade
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelock.getMinDelay();
        
        vm.prank(proposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        // Try to execute immediately (should fail)
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt
        );
    }

    function test_UnauthorizedScheduleFails() public {
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        
        vm.prank(unauthorized);
        vm.expectRevert();
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            bytes32(0),
            salt,
            timelock.getMinDelay()
        );
    }

    function test_UnauthorizedExecuteFails() public {
        // Schedule upgrade first
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelock.getMinDelay();
        
        vm.prank(proposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        // Fast forward time
        vm.warp(block.timestamp + MIN_DELAY + 1);
        
        // Try to execute with unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert();
        timelock.execute(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt
        );
    }

    function test_GetUpgradeTimestamp() public {
        uint256 scheduledTime = block.timestamp;
        
        // Schedule upgrade
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        
        vm.prank(proposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            bytes32(0),
            salt,
            timelock.getMinDelay()
        );
        
        uint256 readyTimestamp = timelock.getUpgradeTimestamp(
            address(testProxy),
            address(implementationV2)
        );
        
        assertEq(readyTimestamp, scheduledTime + MIN_DELAY);
    }

    function test_CancelOperation() public {
        // Schedule upgrade
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelock.getMinDelay();
        
        vm.prank(proposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        bytes32 operationId = timelock.getUpgradeOperationId(address(testProxy), address(implementationV2));
        
        // Admin can cancel the operation
        vm.prank(admin);
        timelock.cancel(operationId);
        
        // Fast forward time
        vm.warp(block.timestamp + MIN_DELAY + 1);
        
        // Should not be ready anymore
        assertFalse(timelock.isUpgradeReady(address(testProxy), address(implementationV2)));
        
        // Execution should fail
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(
            address(testProxy),
            0,
            upgradeCalldata,
            predecessor,
            salt
        );
    }

    function test_RoleManagement() public {
        address newProposer = makeAddr("newProposer");
        
        // Admin can grant roles
        vm.prank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), newProposer);
        
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), newProposer));
        
        // New proposer can schedule upgrades
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", address(implementationV2));
        bytes32 salt = timelock.getUpgradeSalt(address(testProxy), address(implementationV2));
        
        vm.prank(newProposer);
        timelock.schedule(
            address(testProxy),
            0,
            upgradeCalldata,
            bytes32(0),
            salt,
            timelock.getMinDelay()
        );
        
        // Verify operation was scheduled
        bytes32 operationId = timelock.getUpgradeOperationId(address(testProxy), address(implementationV2));
        assertTrue(timelock.isOperation(operationId));
    }
}