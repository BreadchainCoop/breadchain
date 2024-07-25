pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployYieldDistributor is Script {
    function run(address proxyAddress) external {
        vm.startBroadcast();
        bytes memory data;
        Options memory opts;
        opts.referenceContract = "v1.0.0/YieldDistributor.sol:YieldDistributor";
        Upgrades.upgradeProxy(proxyAddress, "YieldDistributor.sol:YieldDistributor", data, opts);
        vm.stopBroadcast();
    }
}
