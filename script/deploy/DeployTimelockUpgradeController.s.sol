// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {TimelockUpgradeController} from "src/TimelockUpgradeController.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployTimelockUpgradeController is Script {
    function run() external returns (address) {
        address multisig = vm.envAddress("MULTISIG_ADDRESS");
        
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        
        address admin = address(0);

        vm.startBroadcast();
        
        address proxy = Upgrades.deployUUPSProxy(
            "TimelockUpgradeController.sol:TimelockUpgradeController",
            abi.encodeCall(TimelockUpgradeController.initialize, (proposers, executors, admin))
        );
        
        vm.stopBroadcast();
        
        return proxy;
    }
}