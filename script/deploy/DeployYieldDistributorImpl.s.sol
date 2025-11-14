pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

import {YieldDistributor} from "../../src/YieldDistributor.sol";

contract DeployYieldDistributorImpl is Script {
    function run() external {
        vm.startBroadcast();
        YieldDistributor yieldDistributor = new YieldDistributor();
        console2.log("Deployed YieldDistributor at address: {}", address(yieldDistributor));
        vm.stopBroadcast();
    }
}
