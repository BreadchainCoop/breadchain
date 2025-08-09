// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TimelockUpgradeController} from "src/TimelockUpgradeController.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract MockUpgradeableContract is Initializable, UUPSUpgradeable {
    uint256 public version;
    
    function initialize(uint256 _version) public initializer {
        version = _version;
    }
    
    function _authorizeUpgrade(address) internal override {}
}

contract TimelockUpgradeControllerTest is Test {
    TimelockUpgradeController public timelock;
    MockUpgradeableContract public implementation;
    address public proxy;
    
    address public multisig = address(0x1234);
    address public attacker = address(0x5678);
    
    uint256 constant UPGRADE_TIMELOCK_DELAY = 48 hours;
    
    event UpgradeProposed(
        address indexed implementation,
        address indexed proxy,
        bytes32 indexed operationId,
        uint256 executeAfter
    );
    
    event UpgradeExecuted(
        address indexed implementation,
        address indexed proxy,
        bytes32 indexed operationId
    );
    
    event UpgradeCancelled(bytes32 indexed operationId);
    
    function setUp() public {
        // Deploy timelock controller
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        
        TimelockUpgradeController timelockImpl = new TimelockUpgradeController();
        bytes memory timelockInitData = abi.encodeCall(
            TimelockUpgradeController.initialize,
            (proposers, executors, address(0))
        );
        address timelockProxy = address(new ERC1967Proxy(address(timelockImpl), timelockInitData));
        timelock = TimelockUpgradeController(payable(timelockProxy));
        
        // Deploy mock upgradeable contract
        MockUpgradeableContract impl = new MockUpgradeableContract();
        bytes memory initData = abi.encodeCall(MockUpgradeableContract.initialize, (1));
        proxy = address(new ERC1967Proxy(address(impl), initData));
        implementation = MockUpgradeableContract(proxy);
    }
    
    function testProposeUpgrade() public {
        vm.startPrank(multisig);
        
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt = keccak256("test");
        
        vm.expectEmit(true, true, true, false);
        emit UpgradeProposed(newImplementation, proxy, bytes32(0), block.timestamp + UPGRADE_TIMELOCK_DELAY);
        
        bytes32 operationId = timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        (bool isScheduled, bool isReady, uint256 timestamp) = 
            timelock.getUpgradeStatus(proxy, newImplementation, data, salt);
        
        assertTrue(isScheduled, "Upgrade should be scheduled");
        assertFalse(isReady, "Upgrade should not be ready immediately");
        assertEq(timestamp, block.timestamp + UPGRADE_TIMELOCK_DELAY, "Incorrect timestamp");
        
        vm.stopPrank();
    }
    
    function testCannotExecuteBeforeTimelock() public {
        vm.startPrank(multisig);
        
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt = keccak256("test");
        
        timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        vm.expectRevert();
        timelock.executeUpgrade(proxy, newImplementation, data, salt);
        
        vm.stopPrank();
    }
    
    function testExecuteAfterTimelock() public {
        vm.startPrank(multisig);
        
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = abi.encodeCall(MockUpgradeableContract.initialize, (2));
        bytes32 salt = keccak256("test");
        
        bytes32 operationId = timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        vm.warp(block.timestamp + UPGRADE_TIMELOCK_DELAY + 1);
        
        (bool isScheduled, bool isReady, ) = 
            timelock.getUpgradeStatus(proxy, newImplementation, data, salt);
        
        assertTrue(isScheduled, "Upgrade should still be scheduled");
        assertTrue(isReady, "Upgrade should be ready after timelock");
        
        vm.expectEmit(true, true, true, false);
        emit UpgradeExecuted(newImplementation, proxy, operationId);
        
        timelock.executeUpgrade(proxy, newImplementation, data, salt);
        
        assertEq(implementation.version(), 2, "Upgrade should have been executed");
        
        vm.stopPrank();
    }
    
    function testCancelUpgrade() public {
        vm.startPrank(multisig);
        
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt = keccak256("test");
        
        bytes32 operationId = timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        vm.expectEmit(true, false, false, false);
        emit UpgradeCancelled(operationId);
        
        timelock.cancelUpgrade(proxy, newImplementation, data, salt);
        
        (bool isScheduled, bool isReady, uint256 timestamp) = 
            timelock.getUpgradeStatus(proxy, newImplementation, data, salt);
        
        assertFalse(isScheduled, "Upgrade should not be scheduled after cancellation");
        assertFalse(isReady, "Upgrade should not be ready after cancellation");
        assertEq(timestamp, 0, "Timestamp should be 0 after cancellation");
        
        vm.stopPrank();
    }
    
    function testOnlyProposerCanPropose() public {
        vm.startPrank(attacker);
        
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt = keccak256("test");
        
        vm.expectRevert();
        timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        vm.stopPrank();
    }
    
    function testOnlyExecutorCanExecute() public {
        vm.prank(multisig);
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt = keccak256("test");
        
        timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        vm.warp(block.timestamp + UPGRADE_TIMELOCK_DELAY + 1);
        
        vm.prank(attacker);
        vm.expectRevert();
        timelock.executeUpgrade(proxy, newImplementation, data, salt);
    }
    
    function testOnlyCancellerCanCancel() public {
        vm.prank(multisig);
        address newImplementation = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt = keccak256("test");
        
        timelock.proposeUpgrade(proxy, newImplementation, data, salt);
        
        vm.prank(attacker);
        vm.expectRevert();
        timelock.cancelUpgrade(proxy, newImplementation, data, salt);
    }
    
    function testMultipleUpgradesWithDifferentSalts() public {
        vm.startPrank(multisig);
        
        address newImplementation1 = address(new MockUpgradeableContract());
        address newImplementation2 = address(new MockUpgradeableContract());
        bytes memory data = "";
        bytes32 salt1 = keccak256("upgrade1");
        bytes32 salt2 = keccak256("upgrade2");
        
        bytes32 operationId1 = timelock.proposeUpgrade(proxy, newImplementation1, data, salt1);
        bytes32 operationId2 = timelock.proposeUpgrade(proxy, newImplementation2, data, salt2);
        
        assertNotEq(operationId1, operationId2, "Operation IDs should be different");
        
        (bool isScheduled1, , ) = timelock.getUpgradeStatus(proxy, newImplementation1, data, salt1);
        (bool isScheduled2, , ) = timelock.getUpgradeStatus(proxy, newImplementation2, data, salt2);
        
        assertTrue(isScheduled1, "First upgrade should be scheduled");
        assertTrue(isScheduled2, "Second upgrade should be scheduled");
        
        vm.stopPrank();
    }
    
    function testTimelockDelayIs48Hours() public view {
        assertEq(timelock.UPGRADE_TIMELOCK_DELAY(), 48 hours, "Timelock delay should be 48 hours");
    }
}