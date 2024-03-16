// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {YieldDisburser} from "../src/YieldDisburser.sol";
import {ERC20VotesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract Bread is ERC20VotesUpgradeable, OwnableUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external virtual;
    function mint(address receiver) external payable virtual;
}
contract YieldDisburserTest is Test {
    YieldDisburser public yieldDisburser;
    Bread public bread;
    function setUp() public {
        bread = Bread(address(0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3));
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
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDisburser));
        yieldDisburser.addProject(address(this));
    }
    function test_simple_claim() public {
        uint256 bread_bal_before = bread.balanceOf(address(this));
        assertEq(bread_bal_before, 0);
        yieldDisburser.distributeYield();
        uint256 bread_bal_after = bread.balanceOf(address(this));
        assertGt(bread_bal_after, 0);
    }

    function test_add_project() public {
        assert(yieldDisburser.breadchainProjects(0) == address(this));
        yieldDisburser.removeProject(address(this));
        assert(yieldDisburser.breadchainProjects(0) == address(0));
    }
    function test_set_duration() public {
        uint48 durationBefore = yieldDisburser.duration();
        yieldDisburser.setDuration(10);
        uint48 durationAfter = yieldDisburser.duration();
        assertEq(durationBefore + 10 minutes, durationAfter);
    }
    function test_voting_power() public {
        vm.roll(32323232323);
        vm.expectRevert();
        uint256 votingPowerBefore =  yieldDisburser.getVotingPowerForPeriod(32323232323, 32323232324, address(this));
        vm.deal(address(this),1000000);
        vm.roll(42424242424);
        bread.mint{value:1000000}(address(this));
        vm.roll(42424242425);
        uint256 votingPowerAfter =  yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242425, address(this));
        console2.log("votingpower", votingPowerAfter);
        assertGt(votingPowerAfter, 0);

    }
}
