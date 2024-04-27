// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {YieldDisburser} from "../src/YieldDisburser.sol";

abstract contract Bread is ERC20VotesUpgradeable, OwnableUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external virtual;
    function mint(address receiver) external payable virtual;
}

contract YieldDisburserTest is Test {
    YieldDisburser public yieldDisburser;
    YieldDisburser public yieldDisburser2;
    address secondProject;
    Bread public bread;
    uint256[] blockNumbers;
    uint256[] percentages;
    uint256[] votes;

    function setUp() public {
        bread = Bread(address(0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3));
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        address[] memory projects = new address[](1);
        projects[0] = address(this);
        yieldDisburser = YieldDisburser(
            address(
                new TransparentUpgradeableProxy(
                    address(yieldDisburserImplementation),
                    address(this),
                    abi.encodeWithSelector(YieldDisburser.initialize.selector, address(bread), projects)
                )
            )
        );
        secondProject = address(0x1234567890123456789012345678901234567890);
        address[] memory projects2 = new address[](2);
        projects2[0] = address(this);
        projects2[1] = secondProject;
        yieldDisburser2 = YieldDisburser(
            address(
                new TransparentUpgradeableProxy(
                    address(yieldDisburserImplementation),
                    address(this),
                    abi.encodeWithSelector(YieldDisburser.initialize.selector, address(bread), projects2)
                )
            )
        );
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDisburser));
        yieldDisburser.addProject(address(this));
    }
    
    function test_fuzzy_distribute(uint256 seed) public {
        uint256 breadbalproject1start = bread.balanceOf(address(this));
        uint256 breadbalproject2start = bread.balanceOf(secondProject);
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDisburser2));
        vm.assume(seed > 10);
        uint256 accounts = 3;
        seed = uint256(bound(seed, 1, 100000000000));
        uint256 start = 32323232323;
        vm.roll(start);
        yieldDisburser2.setMinimumTimeBetweenClaims(1);
        uint48 startTimestamp = uint48(vm.getBlockTimestamp());
        yieldDisburser2.setlastClaimedTimestamp(startTimestamp);
        yieldDisburser2.setLastClaimedBlocknumber(start);
        uint256 yieldAccrued;
        uint256 currentBlockNumber = start + 1;
        vm.roll(currentBlockNumber);
        for (uint256 i = 0; i < accounts; i++) {
            uint256 randomval = uint256(keccak256(abi.encodePacked(seed, i)));
            address holder = address(uint160(randomval));
            uint256 token_amount = bound(randomval, 100, 10000);
            vm.deal(holder, token_amount);
            vm.prank(holder);
            bread.mint{value: token_amount}(holder);
            uint256 vote = randomval % 1000;
            currentBlockNumber += randomval % 5;
            vm.roll(currentBlockNumber);
            votes.push(vote);
            votes.push(100 - vote);
            vm.prank(holder);
            yieldDisburser2.castVote(votes);
            votes.pop();
            votes.pop();
        }
        vm.warp(startTimestamp + 5000);
        console2.log("Current block timestamp: %d", block.timestamp);
        yieldAccrued = bread.yieldAccrued() / 2;
        yieldDisburser2.distributeYield();
        uint256 this_bal_after = bread.balanceOf(address(this));
        uint256 second_bal_after = bread.balanceOf(secondProject);
        assertGt(this_bal_after, breadbalproject1start);
        assertGt(second_bal_after, breadbalproject2start);
    }

    function test_add_project() public {
        assert(yieldDisburser.breadchainProjects(0) == address(this));
        yieldDisburser.removeProject(address(this));
        assert(yieldDisburser.breadchainProjects(0) == address(0));
    }

    function test_set_duration() public {
        uint48 TimeBetweenClaimsBefore = yieldDisburser.minimumTimeBetweenClaims();
        yieldDisburser.setMinimumTimeBetweenClaims(10);
        uint48 TimeBetweenClaimsAfter = yieldDisburser.minimumTimeBetweenClaims();
        assertEq(TimeBetweenClaimsBefore + 10 minutes, TimeBetweenClaimsAfter);
    }

    function test_voting_power() public {
        vm.roll(32323232323);
        uint256 votingPowerBefore;
        vm.expectRevert();
        votingPowerBefore = yieldDisburser.getVotingPowerForPeriod(32323232323, 32323232324, address(this));
        vm.deal(address(this), 1000000000000);
        vm.roll(42424242424);
        bread.mint{value: 1000000}(address(this));
        vm.roll(42424242425);
        uint256 votingPowerAfter = yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242425, address(this));
        assertEq(votingPowerAfter, 1000000);
        vm.roll(42424242426);
        votingPowerAfter = yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242426, address(this));
        assertEq(votingPowerAfter, 2000000);
        vm.roll(42424242427);
        bread.mint{value: 1000000}(address(this));
        vm.roll(42424242428);
        votingPowerAfter = yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242428, address(this));
        assertEq(votingPowerAfter, 5000000);
        vm.roll(42424242430);
        votingPowerAfter = yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242430, address(this));
        assertEq(votingPowerAfter, 9000000);
        vm.expectRevert();
        votingPowerAfter = yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242431, address(this));
    }

    function testFuzzy_voting_power(uint256 seed, uint256 mints) public {
        mints = uint256(bound(mints, 1, 100));
        vm.assume(seed < 100000000000 / mints);
        vm.assume(seed > 0);
        vm.assume(mints > 2);
        uint256 start = 32323232323;
        vm.roll(start);
        address holder = address(0x1234567840123456789012345678701234567890);
        vm.deal(holder, 1000000000000000000);
        uint256 prevblocknum = vm.getBlockNumber();
        uint256 mintblocknum = prevblocknum;
        uint256 expectedVotingPower = 0;
        for (uint256 i = 0; i < mints; i++) {
            mintblocknum = start + seed * i;
            blockNumbers.push(mintblocknum);
            vm.roll(mintblocknum);
            vm.prank(holder);
            bread.mint{value: seed}(holder);
        }
        for (uint256 i = blockNumbers.length - 1; i >= 0; i--) {
            if (i == 0) {
                break;
            }
            uint256 end_interval = blockNumbers[i];
            uint256 start_interval = blockNumbers[i - 1];
            uint256 expected_balance = seed * (i);
            uint256 interval_voting_power = (end_interval - start_interval) * expected_balance;
            expectedVotingPower += interval_voting_power;
        }
        uint256 vote = yieldDisburser.getVotingPowerForPeriod(start, mintblocknum, holder);
        assertEq(vote, expectedVotingPower);
    }
}
