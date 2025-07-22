// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UpgradeTimelock} from "../../src/UpgradeTimelock.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title TimelockUpgrade
 * @notice Script for scheduling and executing upgrades through the timelock controller
 */
contract TimelockUpgrade is Script {
    
    struct UpgradeParams {
        address timelock;           // Address of the UpgradeTimelock contract
        address proxy;              // Address of the proxy to upgrade
        address newImplementation;  // Address of the new implementation
        bytes upgradeData;          // Optional data for upgradeToAndCall
    }

    /**
     * @notice Schedule an upgrade operation
     * @dev This function schedules an upgrade that must wait for the timelock delay
     */
    function scheduleUpgrade() public {
        UpgradeParams memory params = getUpgradeParams();
        
        vm.startBroadcast();
        
        UpgradeTimelock timelock = UpgradeTimelock(payable(params.timelock));
        
        // Schedule the upgrade
        // Prepare upgrade calldata
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", params.newImplementation);
        bytes32 salt = timelock.getUpgradeSalt(params.proxy, params.newImplementation);
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelock.getMinDelay();
        
        // Schedule the upgrade
        timelock.schedule(
            params.proxy,
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        bytes32 operationId = timelock.getUpgradeOperationId(params.proxy, params.newImplementation);
        
        vm.stopBroadcast();
        
        console.log("Upgrade scheduled!");
        console.log("Operation ID:", vm.toString(operationId));
        console.log("Proxy:", params.proxy);
        console.log("New Implementation:", params.newImplementation);
        console.log("Timelock:", params.timelock);
        
        uint256 readyTimestamp = timelock.getUpgradeTimestamp(
            params.proxy,
            params.newImplementation
        );
        
        console.log("Ready for execution at timestamp:", readyTimestamp);
        console.log("Ready for execution at (human readable):", timestampToString(readyTimestamp));
    }

    /**
     * @notice Execute a previously scheduled upgrade
     * @dev This function executes an upgrade that has passed the timelock delay
     */
    function executeUpgrade() public {
        UpgradeParams memory params = getUpgradeParams();
        
        UpgradeTimelock timelock = UpgradeTimelock(payable(params.timelock));
        
        // Check if upgrade is ready
        bool ready = timelock.isUpgradeReady(params.proxy, params.newImplementation);
        require(ready, "Upgrade is not ready for execution yet");
        
        // Prepare upgrade parameters
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", params.newImplementation);
        bytes32 salt = timelock.getUpgradeSalt(params.proxy, params.newImplementation);
        bytes32 predecessor = bytes32(0);
        
        vm.startBroadcast();
        
        // Execute the upgrade
        timelock.execute(
            params.proxy,
            0,
            upgradeCalldata,
            predecessor,
            salt
        );
        
        vm.stopBroadcast();
        
        console.log("Upgrade executed successfully!");
        console.log("Proxy:", params.proxy);
        console.log("New Implementation:", params.newImplementation);
    }

    /**
     * @notice Check the status of an upgrade operation
     */
    function checkUpgradeStatus() public view {
        UpgradeParams memory params = getUpgradeParams();
        
        UpgradeTimelock timelock = UpgradeTimelock(payable(params.timelock));
        
        bool ready = timelock.isUpgradeReady(params.proxy, params.newImplementation);
        uint256 readyTimestamp = timelock.getUpgradeTimestamp(params.proxy, params.newImplementation);
        
        console.log("=== Upgrade Status ===");
        console.log("Proxy:", params.proxy);
        console.log("New Implementation:", params.newImplementation);
        console.log("Timelock:", params.timelock);
        console.log("Ready for execution:", ready);
        console.log("Ready timestamp:", readyTimestamp);
        
        if (readyTimestamp > 0) {
            console.log("Ready at (human readable):", timestampToString(readyTimestamp));
            
            if (block.timestamp < readyTimestamp) {
                uint256 timeLeft = readyTimestamp - block.timestamp;
                console.log("Time remaining:", timeLeft, "seconds");
                console.log("Time remaining (human readable):", secondsToString(timeLeft));
            }
        } else {
            console.log("Operation not scheduled");
        }
    }

    /**
     * @notice Get upgrade parameters from environment variables or override this function
     * @return params The upgrade parameters
     */
    function getUpgradeParams() public view returns (UpgradeParams memory params) {
        params.timelock = vm.envAddress("UPGRADE_TIMELOCK");
        params.proxy = vm.envAddress("UPGRADE_PROXY");
        params.newImplementation = vm.envAddress("UPGRADE_NEW_IMPLEMENTATION");
        
        // Optional upgrade data
        try vm.envString("UPGRADE_DATA") returns (string memory upgradeDataHex) {
            if (bytes(upgradeDataHex).length > 0) {
                params.upgradeData = vm.parseBytes(upgradeDataHex);
            } else {
                params.upgradeData = "";
            }
        } catch {
            params.upgradeData = "";
        }
    }

    /**
     * @notice Convert timestamp to human readable string
     * @param timestamp The timestamp to convert
     * @return Human readable date/time string (simplified)
     */
    function timestampToString(uint256 timestamp) internal pure returns (string memory) {
        if (timestamp == 0) return "Not scheduled";
        return string(abi.encodePacked("Timestamp: ", vm.toString(timestamp)));
    }

    /**
     * @notice Convert seconds to human readable duration
     * @param secondsAmount The number of seconds
     * @return Human readable duration string
     */
    function secondsToString(uint256 secondsAmount) internal pure returns (string memory) {
        if (secondsAmount < 60) {
            return string(abi.encodePacked(vm.toString(secondsAmount), " seconds"));
        } else if (secondsAmount < 3600) {
            uint256 minutesAmount = secondsAmount / 60;
            uint256 remainingSecs = secondsAmount % 60;
            return string(abi.encodePacked(
                vm.toString(minutesAmount), " minutes, ",
                vm.toString(remainingSecs), " seconds"
            ));
        } else if (secondsAmount < 86400) {
            uint256 hoursAmount = secondsAmount / 3600;
            uint256 remainingMins = (secondsAmount % 3600) / 60;
            return string(abi.encodePacked(
                vm.toString(hoursAmount), " hours, ",
                vm.toString(remainingMins), " minutes"
            ));
        } else {
            uint256 daysAmount = secondsAmount / 86400;
            uint256 remainingHrs = (secondsAmount % 86400) / 3600;
            return string(abi.encodePacked(
                vm.toString(daysAmount), " days, ",
                vm.toString(remainingHrs), " hours"
            ));
        }
    }

    /**
     * @notice Helper function for YieldDistributor upgrades
     */
    function scheduleYieldDistributorUpgrade(
        address timelock,
        address yieldDistributorProxy,
        address newImplementation
    ) public {
        vm.startBroadcast();
        
        UpgradeTimelock timelockContract = UpgradeTimelock(payable(timelock));
        
        // Prepare upgrade parameters
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", newImplementation);
        bytes32 salt = timelockContract.getUpgradeSalt(yieldDistributorProxy, newImplementation);
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelockContract.getMinDelay();
        
        // Schedule the upgrade
        timelockContract.schedule(
            yieldDistributorProxy,
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        bytes32 operationId = timelockContract.getUpgradeOperationId(yieldDistributorProxy, newImplementation);
        
        vm.stopBroadcast();
        
        console.log("YieldDistributor upgrade scheduled!");
        console.log("Operation ID:", vm.toString(operationId));
    }

    /**
     * @notice Helper function for ButteredBread upgrades
     */
    function scheduleButteredBreadUpgrade(
        address timelock,
        address butteredBreadProxy,
        address newImplementation
    ) public {
        vm.startBroadcast();
        
        UpgradeTimelock timelockContract = UpgradeTimelock(payable(timelock));
        
        // Prepare upgrade parameters
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeTo(address)", newImplementation);
        bytes32 salt = timelockContract.getUpgradeSalt(butteredBreadProxy, newImplementation);
        bytes32 predecessor = bytes32(0);
        uint256 delay = timelockContract.getMinDelay();
        
        // Schedule the upgrade
        timelockContract.schedule(
            butteredBreadProxy,
            0,
            upgradeCalldata,
            predecessor,
            salt,
            delay
        );
        
        bytes32 operationId = timelockContract.getUpgradeOperationId(butteredBreadProxy, newImplementation);
        
        vm.stopBroadcast();
        
        console.log("ButteredBread upgrade scheduled!");
        console.log("Operation ID:", vm.toString(operationId));
    }
}