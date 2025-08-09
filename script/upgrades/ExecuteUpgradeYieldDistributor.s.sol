// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {TimelockUpgradeController} from "src/TimelockUpgradeController.sol";

contract ExecuteUpgradeYieldDistributor is Script {
    function run(
        address proxyAddress,
        address timelockAddress,
        address newImplementation,
        bytes calldata data,
        bytes32 salt
    ) external {
        vm.startBroadcast();
        
        TimelockUpgradeController timelock = TimelockUpgradeController(payable(timelockAddress));
        timelock.executeUpgrade(proxyAddress, newImplementation, data, salt);
        
        vm.stopBroadcast();
    }
}