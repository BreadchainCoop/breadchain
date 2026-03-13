// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockBread} from "src/test/MockBread.sol";
import {ButteredBread, IButteredBread} from "src/ButteredBread.sol";
import {YieldDistributor} from "src/YieldDistributor.sol";

interface IVmWallets {
    function getWallets() external returns (address[] memory);
}

contract DeployMockYieldDistributor is Script {
    // ─── MockBread ─────────────────────────────────────────────────────────
    string constant BREAD_NAME = "Bread";
    string constant BREAD_SYMBOL = "BREAD";

    // ─── ButteredBread ─────────────────────────────────────────────────────
    string constant BB_NAME = "ButteredBread";
    string constant BB_SYMBOL = "BB";

    // ─── YieldDistributor ──────────────────────────────────────────────────
    address constant PROJECT_1 = address(0xB0B);
    address constant PROJECT_2 = address(0xCAFE);
    address constant PROJECT_3 = address(0xF00D);
    uint256 constant PRECISION = 1e18;
    uint256 constant MAX_POINTS = 10_000;
    uint256 constant CYCLE_LENGTH = 60; // ~5 mins at 5s/block
    uint256 constant YIELD_FIXED_SPLIT_DIVISOR = 2;
    uint256 constant LAST_CLAIMED_BLOCK_NUMBER = 0;

    function run() external {
        address owner = vm.envOr("OWNER", address(0));
        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (owner == address(0)) {
            if (privateKey != 0) {
                owner = vm.addr(privateKey);
            } else {
                try IVmWallets(address(vm)).getWallets() returns (address[] memory wallets) {
                    if (wallets.length > 0) owner = wallets[0];
                } catch {}
            }
        }
        require(owner != address(0), "Set OWNER or PRIVATE_KEY / --private-key");

        if (privateKey != 0) {
            vm.startBroadcast(privateKey);
        } else {
            vm.startBroadcast(owner);
        }

        // 1. Deploy MockBread
        MockBread bread = new MockBread(BREAD_NAME, BREAD_SYMBOL);
        console2.log("MockBread:", address(bread));

        // 2. Deploy ButteredBread with no liquidity pools
        IButteredBread.InitData memory initData = IButteredBread.InitData({
            breadToken: address(bread),
            liquidityPools: new address[](0),
            scalingFactors: new uint256[](0),
            name: BB_NAME,
            symbol: BB_SYMBOL
        });
        address bbImpl = address(new ButteredBread());
        ButteredBread butteredBread = ButteredBread(
            address(
                new TransparentUpgradeableProxy(bbImpl, owner, abi.encodeCall(ButteredBread.initialize, (initData)))
            )
        );
        console2.log("ButteredBread:", address(butteredBread));

        // 3. Deploy YieldDistributor
        address[] memory projects = new address[](3);
        projects[0] = PROJECT_1;
        projects[1] = PROJECT_2;
        projects[2] = PROJECT_3;
        bytes memory ydInitData = abi.encodeCall(
            YieldDistributor.initialize,
            (
                address(bread),
                address(butteredBread),
                PRECISION,
                MAX_POINTS,
                CYCLE_LENGTH,
                YIELD_FIXED_SPLIT_DIVISOR,
                LAST_CLAIMED_BLOCK_NUMBER,
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
