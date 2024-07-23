pragma solidity ^0.8.20;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract DeployYieldDistributor is Script {
    function run() external {
        vm.startBroadcast();
        address proxyAddress = 0xeE95A62b749d8a2520E0128D9b3aCa241269024b;
        bytes memory data;
        Options memory opts;
        opts.referenceContract = "v1.0.0/YieldDistributor.sol:YieldDistributor";
        Upgrades.upgradeProxy(proxyAddress, "YieldDistributor.sol:YieldDistributor", data, opts);
        vm.stopBroadcast();
    }
}
