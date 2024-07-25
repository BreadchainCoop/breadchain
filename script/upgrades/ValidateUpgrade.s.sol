pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {YieldDistributor} from "../../src/YieldDistributor.sol";

contract DeployYieldDistributor is Script {
    function run() external {
        vm.startBroadcast();
        Options memory opts;
        opts.referenceContract = "v1.0.0/YieldDistributor.sol:YieldDistributor";
        Upgrades.validateUpgrade("YieldDistributor.sol:YieldDistributor", opts);
        vm.stopBroadcast();
    }
}
