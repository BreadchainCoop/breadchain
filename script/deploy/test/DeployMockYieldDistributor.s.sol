// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockBread} from "src/test/MockBread.sol";
import {ButteredBread, IButteredBread} from "src/ButteredBread.sol";
import {YieldDistributor} from "src/YieldDistributor.sol";

contract DeployMockYieldDistributor is Script {
    function run() external {
        address owner = vm.addr(vm.envUint("PRIVATE_KEY"));
        vm.startBroadcast();

        // 1. Deploy MockBread
        MockBread bread = new MockBread("Bread", "BREAD");
        console2.log("MockBread:", address(bread));

        // 2. Deploy ButteredBread with no liquidity pools
        IButteredBread.InitData memory initData = IButteredBread.InitData({
            breadToken: address(bread),
            liquidityPools: new address[](0),
            scalingFactors: new uint256[](0),
            name: "ButteredBread",
            symbol: "BB"
        });
        address bbImpl = address(new ButteredBread());
        ButteredBread butteredBread = ButteredBread(
            address(new TransparentUpgradeableProxy(bbImpl, owner, abi.encodeCall(ButteredBread.initialize, (initData))))
        );
        console2.log("ButteredBread:", address(butteredBread));

        // 3. Deploy YieldDistributor with default values
        address[] memory projects = new address[](1);
        projects[0] = owner;
        bytes memory ydInitData = abi.encodeCall(
            YieldDistributor.initialize,
            (
                address(bread),
                address(butteredBread),
                1e18, // _precision
                10_000, // _maxPoints
                518_400, // _cycleLength
                2, // _yieldFixedSplitDivisor
                1, // _lastClaimedBlockNumber
                projects,
                owner
            )
        );
        YieldDistributor yieldDistributor = YieldDistributor(
            address(new TransparentUpgradeableProxy(address(new YieldDistributor()), owner, ydInitData))
        );
        console2.log("YieldDistributor:", address(yieldDistributor));

        // 4. Set YieldDistributor as yield claimer on MockBread
        bread.setYieldClaimer(address(yieldDistributor));
        console2.log("Set yield claimer");

        vm.stopBroadcast();
    }
}
