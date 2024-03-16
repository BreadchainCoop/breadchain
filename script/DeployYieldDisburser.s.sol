// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {YieldDisburser} from "../src/YieldDisburser.sol";
contract DeployYieldDisburser is Script {
    function run() external {
        vm.startBroadcast();
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        TransparentUpgradeableProxy yieldDisburser = new TransparentUpgradeableProxy(
                address(yieldDisburserImplementation),
                address(msg.sender),
                abi.encodeWithSelector(
                    YieldDisburser.initialize.selector,
                    0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3
                )
            );

        vm.stopBroadcast();
    }
}
