// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {YieldDisburser} from "../src/YieldDisburser.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract Bread is ERC20VotesUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
}
contract MockBread is Bread {
    function claimYield(uint256 amount, address receiver) public override {
        super._mint(receiver, amount);
    }
    function yieldAccrued() external pure override returns (uint256) {
        return 5;
    }
}
contract YieldDisburserTest is Test {
    YieldDisburser public yieldDisburser;
    MockBread public bread;

    function setUp() public {
        bread = new MockBread();
        // ProxyAdmin proxyAdmin = new ProxyAdmin(
        //     address(this)
        // );
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        yieldDisburser = YieldDisburser(
            address(
                new TransparentUpgradeableProxy(
                    address(yieldDisburserImplementation),
                    address(this),
                    abi.encodeWithSelector(
                        YieldDisburser.initialize.selector,
                        address(bread)
                    )
                )
            )
        );
    }
    function test_simple_claim() public{
        yieldDisburser.addProject(address(this));
        yieldDisburser.distributeYield();
    }
}
