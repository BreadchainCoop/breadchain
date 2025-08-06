pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";
import {ButteredBread} from "../../src/ButteredBread.sol";

contract ValidateUpgrade is Script {
    function run() external {
        vm.startBroadcast();
        
        // Validate that YieldDistributor implementation is upgrade-safe
        Options memory yieldOpts;
        yieldOpts.unsafeSkipStorageCheck = true; // Skip storage check since we're not comparing versions
        Upgrades.validateImplementation("YieldDistributor.sol:YieldDistributor", yieldOpts);
        
        // Validate that ButteredBread implementation is upgrade-safe
        Options memory breadOpts;
        breadOpts.unsafeSkipStorageCheck = true; // Skip storage check since we're not comparing versions
        Upgrades.validateImplementation("ButteredBread.sol:ButteredBread", breadOpts);
        
        vm.stopBroadcast();
    }
}
