// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {TimelockUpgradeController} from "src/TimelockUpgradeController.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract ProposeUpgradeYieldDistributor is Script {
    function run(address proxyAddress, address timelockAddress) external returns (bytes32) {
        vm.startBroadcast();
        
        Options memory opts;
        opts.referenceContract = "v1.0.0/YieldDistributor.sol:YieldDistributor";
        
        address newImplementation = Upgrades.prepareUpgrade(
            "YieldDistributor.sol:YieldDistributor", 
            opts
        );
        
        bytes memory data = "";
        
        bytes32 salt = keccak256(abi.encodePacked("YieldDistributor", block.timestamp));
        
        TimelockUpgradeController timelock = TimelockUpgradeController(payable(timelockAddress));
        bytes32 operationId = timelock.proposeUpgrade(proxyAddress, newImplementation, data, salt);
        
        vm.stopBroadcast();
        
        return operationId;
    }
}