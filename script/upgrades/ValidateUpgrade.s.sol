pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";
import {ButteredBread} from "../../src/ButteredBread.sol";

contract ValidateUpgrade is Script {
    function run() external {
        vm.startBroadcast();
        
        // Validate YieldDistributor upgrade
        Options memory yieldOpts;
        yieldOpts.referenceContract = "v1.0.4/YieldDistributor.sol:YieldDistributor";
        yieldOpts.unsafeSkipStorageCheck = true; // Skip storage check due to ERC7201 migration
        Upgrades.validateUpgrade("YieldDistributor.sol:YieldDistributor", yieldOpts);
        
        // Validate ButteredBread upgrade
        Options memory breadOpts;
        breadOpts.referenceContract = "v1.0.4/ButteredBread.sol:ButteredBread";
        Upgrades.validateUpgrade("ButteredBread.sol:ButteredBread", breadOpts);
        
        vm.stopBroadcast();
    }
}
