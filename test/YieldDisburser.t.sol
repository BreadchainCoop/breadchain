// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

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
    uint256[] blockNumbers;
    uint256[] percentages;
    uint256[] votes;
    string public deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    bytes breadchainProjectsRaw = stdJson.parseRaw(config_data, "._breadchainProjects");
    address[] breadchainProjects = abi.decode(breadchainProjectsRaw, (address[]));
    address breadAddress = stdJson.readAddress(config_data, ".breadAddress");
    uint256 _blocktime = stdJson.readUint(config_data, "._blocktime");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");
    uint256 _minVotingHoldingDuration = stdJson.readUint(config_data, "._minVotingHoldingDuration");
    uint256 _pointsMax = stdJson.readUint(config_data, "._pointsMax");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _lastClaimedTimestamp = stdJson.readUint(config_data, "._lastClaimedTimestamp");
    uint256 _lastClaimedBlocknumber = stdJson.readUint(config_data, "._lastClaimedBlocknumber");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    Bread public bread = Bread(address(breadAddress));

    function setUp() public {
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        address[] memory projects = new address[](1);
        projects[0] = address(this);
        bytes memory initData = abi.encodeWithSelector(
            YieldDisburser.initialize.selector,
            address(bread),
            projects,
            _blocktime,
            _minVotingAmount,
            _minVotingHoldingDuration,
            _pointsMax,
            _cycleLength,
            _lastClaimedTimestamp,
            _lastClaimedBlocknumber,
            _precision
        );
        yieldDisburser = YieldDisburser(
            address(new TransparentUpgradeableProxy(address(yieldDisburserImplementation), address(this), initData))
        );
        secondProject = address(0x1234567890123456789012345678901234567890);
        address[] memory projects2 = new address[](2);
        projects2[0] = address(this);
        projects2[1] = secondProject;
        initData = abi.encodeWithSelector(
            YieldDisburser.initialize.selector,
            address(bread),
            projects2,
            _blocktime,
            _minVotingAmount,
            _minVotingHoldingDuration,
            _pointsMax,
            _cycleLength,
            _lastClaimedTimestamp,
            _lastClaimedBlocknumber,
            _precision
        );
        yieldDisburser2 = YieldDisburser(
            address(new TransparentUpgradeableProxy(address(yieldDisburserImplementation), address(this), initData))
        );
        yieldDisburser.setCycleLength(1);
        yieldDisburser2.setCycleLength(1);
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDisburser));
    }

    function test_simple_distribute() public {
        uint256 start = 32323232323;
        vm.roll(start);
        yieldDisburser.setlastClaimedTimestamp(uint48(vm.getBlockTimestamp()));
        yieldDisburser.setLastClaimedBlocknumber(vm.getBlockNumber());
        yieldDisburser.setCycleLength(1);
        uint256 bread_bal_before = bread.balanceOf(address(this));
        assertEq(bread_bal_before, 0);
        address holder = address(0x1234567890123456789012345678901234567890);
        vm.deal(holder, 5 * 1e18);
        vm.prank(holder);
        bread.mint{value: 5 * 1e18}(holder);
        vm.roll(start + 11 days / 5);
        vm.warp((start / 5) + 11 days);
        uint256 vote = 100;
        percentages.push(vote);
        uint256 yieldAccrued = bread.yieldAccrued();
        vm.prank(holder);
        yieldDisburser.castVote(percentages);
        yieldDisburser.distributeYield();
        uint256 bread_bal_after = bread.balanceOf(address(this));
        assertGt(bread_bal_after, yieldAccrued - 2);
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
        yieldDisburser2.setCycleLength(1);
        uint48 startTimestamp = uint48(vm.getBlockTimestamp());
        yieldDisburser2.setlastClaimedTimestamp(startTimestamp);
        yieldDisburser2.setLastClaimedBlocknumber(start);
        uint256 yieldAccrued;
        uint256 currentBlockNumber = start + 1;
        vm.roll(currentBlockNumber);
        for (uint256 i = 0; i < accounts; i++) {
            uint256 randomval = uint256(keccak256(abi.encodePacked(seed, i)));
            address holder = address(uint160(randomval));
            uint256 token_amount = bound(randomval, 5 * 1e18, 1000 * 1e18);
            vm.deal(holder, token_amount);
            vm.prank(holder);
            bread.mint{value: token_amount}(holder);
            uint256 vote = randomval % 100;
            currentBlockNumber += ((11 days / 5) + randomval % 5);
            vm.roll(currentBlockNumber);
            votes.push(vote);
            votes.push(10000 - vote);
            vm.prank(holder);
            yieldDisburser2.castVote(votes);
            votes.pop();
            votes.pop();
        }
        vm.warp(startTimestamp + 5000);
        yieldAccrued = bread.yieldAccrued() / 2;
        yieldDisburser2.distributeYield();
        uint256 this_bal_after = bread.balanceOf(address(this));
        uint256 second_bal_after = bread.balanceOf(secondProject);
        assertGt(this_bal_after, breadbalproject1start);
        assertGt(second_bal_after, breadbalproject2start);
    }

    function test_set_duration() public {
        yieldDisburser.setCycleLength(10);
        uint256 cycleLength = yieldDisburser.cycleLength();
        assertEq(10, cycleLength);
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

    function test_adding_removing_projects() public {
        vm.expectRevert();
        address projects_before_len;
        projects_before_len = yieldDisburser.breadchainProjects(1);
        address active_project = yieldDisburser.breadchainProjects(0);
        assertEq(active_project, address(this));
        yieldDisburser.queueProjectAddition(secondProject);
        yieldDisburser.queueProjectRemoval(address(this));
        uint256 start = 32323232323;
        vm.roll(start);
        yieldDisburser.setCycleLength(1);
        uint48 startTimestamp = uint48(vm.getBlockTimestamp());
        yieldDisburser.setlastClaimedTimestamp(startTimestamp);
        yieldDisburser.setLastClaimedBlocknumber(start);
        vm.warp(startTimestamp + 5000);
        vm.deal(address(this), 5 * 1e18);
        bread.mint{value: 5 * 1e18}(address(this));
        vm.roll(start + 11 days / 5);
        uint256 vote = 100;
        percentages.push(vote);
        votes = new uint256[](1);
        votes[0] = 100;
        yieldDisburser.castVote(votes);
        yieldDisburser.distributeYield();
        address project_added_after = yieldDisburser.breadchainProjects(0);
        assertEq(project_added_after, secondProject);
        vm.expectRevert();
        yieldDisburser.queuedProjectsForAddition(0);
        vm.expectRevert();
        yieldDisburser.queuedProjectsForRemoval(0);
        address random_project = address(0x1244567830123456789012345478901234567890);
        vm.expectRevert();
        yieldDisburser.queueProjectRemoval(random_project);
        uint256 length = yieldDisburser.getBreadchainProjectsLength();
        assertEq(length, 1);
    }

    function test_below_min_required_voting_power() public {
        uint256 start = 32323232323;
        vm.roll(start);
        yieldDisburser.setlastClaimedTimestamp(uint48(block.timestamp));
        yieldDisburser.setLastClaimedBlocknumber(block.number);
        address holder = address(0x1234567890123356789012345672901234567890);
        vm.deal(holder, 5 * 1e18);
        vm.prank(holder);
        bread.mint{value: 5 * 1e18}(holder);
        vm.roll(start + 9 days / 5);
        uint256 vote = 100;
        percentages.push(vote);
        vm.expectRevert();
        vm.prank(holder);
        yieldDisburser.castVote(percentages);
        vm.roll(start + 11 days / 5);
        vm.prank(holder);
        yieldDisburser.castVote(percentages);
    }
}
