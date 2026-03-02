// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {MockBread} from "src/test/MockBread.sol";

contract DeployMockBread is Script {
    string public tokenName = "Bread";
    string public tokenSymbol = "BREAD";

    function run() external {
        vm.startBroadcast();
        MockBread bread = new MockBread(tokenName, tokenSymbol);
        console2.log("Deployed MockBread at address: {}", address(bread));
        vm.stopBroadcast();
    }
}
