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
        ProxyAdmin proxyAdmin = new ProxyAdmin(
            address(0x86213f1cf0a501857B70Df35c1cb3C2EcF112844)
        );
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        TransparentUpgradeableProxy yieldDisburser = new TransparentUpgradeableProxy(
                address(yieldDisburserImplementation),
                address(proxyAdmin),
                abi.encodeWithSelector(
                    YieldDisburser.initialize.selector,
                    0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3
                )
            );

        vm.stopBroadcast();
    }
}
