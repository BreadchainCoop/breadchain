// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {YieldDistributor} from "../src/YieldDistributor.sol";
import {YieldDistributorTestWrapper} from "../src/test/YieldDistributorTestWrapper.sol";

abstract contract Bread is ERC20VotesUpgradeable, OwnableUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external virtual;
    function mint(address receiver) external payable virtual;
}

contract YieldDistributorTest is Test {
    uint256 constant START = 32323232323;
    uint256 marginOfError = 3;
    YieldDistributorTestWrapper public yieldDistributor;
    YieldDistributorTestWrapper public yieldDistributor2;
    address secondProject;
    uint256[] blockNumbers;
    uint256[] percentages;
    uint256[] votes;
    string public deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    bytes projectsRaw = stdJson.parseRaw(config_data, "._projects");
    address[] projects = abi.decode(projectsRaw, (address[]));
    address _bread = stdJson.readAddress(config_data, "._bread");
    uint256 _blocktime = stdJson.readUint(config_data, "._blocktime");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _minHoldingDuration = stdJson.readUint(config_data, "._minHoldingDuration");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");
    Bread public bread = Bread(address(_bread));
    uint256 minHoldingDurationInBlocks = _minHoldingDuration / _blocktime;

    // For testing purposes, these values were used in the following way to configure _minRequiredVotingPower
    // uint256 minHoldingDuration = 10 days;
    // uint256 blockTime = 5;
    // uint256 minRequiredVotingPower = (minVotingAmount * minHoldingDuration) / blockTime; // We can assume that blockTime is small enough

    uint256 _minRequiredVotingPower = stdJson.readUint(config_data, "._minRequiredVotingPower");

    function setUp() public {
        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects1 = new address[](1);
        projects1[0] = address(this);
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            _precision,
            _minRequiredVotingPower,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects1
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );
        secondProject = address(0x1234567890123456789012345678901234567890);
        address[] memory projects2 = new address[](2);
        projects2[0] = address(this);
        projects2[1] = secondProject;
        initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            _precision,
            _minRequiredVotingPower,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects2
        );
        yieldDistributor2 = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDistributor));
    }

    function setUpForCycle(YieldDistributorTestWrapper _yieldDistributor) public {
        vm.roll(START - (_cycleLength));
        _yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(_yieldDistributor));
        vm.roll(START);
    }

    function setUpAccountsForVoting(address[] memory accounts) public {
        vm.roll(START - (_cycleLength + 1));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.deal(accounts[i], _minVotingAmount);
            vm.prank(accounts[i]);
            bread.mint{value: _minVotingAmount}(accounts[i]);
        }
    }

    function test_simple_distribute() public {
        // Getting the balance of the project before the distribution
        uint256 bread_bal_before = bread.balanceOf(address(this));
        assertEq(bread_bal_before, 0);
        // Getting the amount of yield to be distributed
        uint256 yieldAccrued = bread.yieldAccrued();

        // Setting up a voter
        address account = address(0x1234567890123456789012345678901234567890);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        setUpAccountsForVoting(accounts);

        // Setting up for a cycle
        setUpForCycle(yieldDistributor);

        // Casting vote and distributing yield
        uint256 vote = 100;
        percentages.push(vote);
        vm.prank(account);
        yieldDistributor.castVote(percentages);
        yieldDistributor.distributeYield();

        // Getting the balance of the project after the distribution and checking if it similiar to the yield accrued (there may be rounding issues)
        uint256 bread_bal_after = bread.balanceOf(address(this));
        assertGt(bread_bal_after, yieldAccrued - marginOfError);
    }

    function test_fixed_yield_split() public {
        // Getting the balance of the project before the distribution
        uint256 bread_bal_before = bread.balanceOf(address(this));
        assertEq(bread_bal_before, 0);
        // Getting the amount of yield to be distributed
        uint256 yieldAccrued = bread.yieldAccrued();

        // Setting up a voter
        address account = address(0x1234567890123456789012345678901234567890);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        setUpAccountsForVoting(accounts);

        // Setting up for a cycle
        setUpForCycle(yieldDistributor2);
        address owner = yieldDistributor2.owner();
        vm.prank(owner);
        yieldDistributor2.setyieldFixedSplitDivisor(3);

        // Casting vote and distributing yield
        uint256 vote = 50;
        uint256 vote2 = 50;
        percentages.push(vote);
        percentages.push(vote2);
        vm.prank(account);
        yieldDistributor2.castVote(percentages);
        yieldDistributor2.distributeYield();
        uint256 fixedSplit = yieldAccrued / _yieldFixedSplitDivisor;
        uint256 votedSplit = yieldAccrued - fixedSplit;
        uint256 projectsLength = yieldDistributor2.getProjectsLength();
        // Getting the balance of the project after the distribution and checking if it similiar to the yield accrued (there may be rounding issues)
        uint256 bread_bal_after = bread.balanceOf(address(secondProject));
        assertGt(bread_bal_after, ((fixedSplit + votedSplit) / projectsLength) - marginOfError);
    }

    function test_simple_recast_vote() public {
        // Getting the balance of the project before the distribution
        uint256 bread_bal_before = bread.balanceOf(address(this));
        assertEq(bread_bal_before, 0);
        // Getting the amount of yield to be distributed
        uint256 yieldAccrued = bread.yieldAccrued();

        // Setting up a voter
        address account = address(0x1234567890123456789012345678901234567890);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        setUpAccountsForVoting(accounts);

        // Setting up for a cycle
        setUpForCycle(yieldDistributor);

        // Casting vote and distributing yield
        uint256 vote = 100;
        percentages.push(vote);
        vm.prank(account);
        yieldDistributor.castVote(percentages);
        percentages.pop();
        percentages.push(70);
        vm.prank(account);
        yieldDistributor.castVote(percentages);
        yieldDistributor.distributeYield();

        // Getting the balance of the project after the distribution and checking if it similiar to the yield accrued (there may be rounding issues)
        uint256 bread_bal_after = bread.balanceOf(address(this));
        assertGt(bread_bal_after, yieldAccrued - marginOfError);
    }

    function test_fuzzy_distribute(uint256 seed) public {
        // Getting the balance of the projects before the distribution
        uint256 breadbalproject1start = bread.balanceOf(address(this));
        uint256 breadbalproject2start = bread.balanceOf(secondProject);

        // Generating random values for the test
        vm.assume(seed > 10);
        uint256 accounts = 3;
        seed = uint256(bound(seed, 1, 100000000000));

        setUpForCycle(yieldDistributor2);
        for (uint256 i = 0; i < accounts; i++) {
            // Generating random values for the test
            uint256 randomval = uint256(keccak256(abi.encodePacked(seed, i)));
            uint256 vote = randomval % 100;
            address holder = address(uint160(randomval));
            uint256 token_amount = bound(randomval, _minVotingAmount, 1000 * _minVotingAmount);

            // Setting up the account for voting
            vm.roll(START - (minHoldingDurationInBlocks));
            vm.deal(holder, token_amount);
            vm.prank(holder);
            bread.mint{value: token_amount}(holder);

            // Casting vote with random distribution
            vm.roll(START);
            votes.push(vote);
            votes.push(10000 - vote);
            vm.prank(holder);
            yieldDistributor2.castVote(votes);
            votes.pop();
            votes.pop();
        }
        // Distributing yield
        yieldDistributor2.distributeYield();

        // Getting the balance of the projects after the distribution
        uint256 this_bal_after = bread.balanceOf(address(this));
        uint256 second_bal_after = bread.balanceOf(secondProject);
        assertGt(this_bal_after, breadbalproject1start);
        assertGt(second_bal_after, breadbalproject2start);
    }

    function test_fuzzy_recast_vote(uint256 seed) public {
        // Getting the balance of the projects before the distribution
        uint256 breadbalproject1start = bread.balanceOf(address(this));
        uint256 breadbalproject2start = bread.balanceOf(secondProject);

        // Generating random values for the test
        vm.assume(seed > 10);
        uint256 accounts = 3;
        seed = uint256(bound(seed, 1, 100000000000));

        setUpForCycle(yieldDistributor2);
        for (uint256 i = 0; i < accounts; i++) {
            // Generating random values for the test
            uint256 randomval = uint256(keccak256(abi.encodePacked(seed, i)));
            uint256 vote = randomval % 100;
            uint256 vote2 = (randomval + 1) % 100;
            address holder = address(uint160(randomval));
            uint256 token_amount = bound(randomval, _minVotingAmount, 1000 * _minVotingAmount);

            // Setting up the account for voting
            vm.roll(START - (minHoldingDurationInBlocks));
            vm.deal(holder, token_amount);
            vm.prank(holder);
            bread.mint{value: token_amount}(holder);

            // Casting vote with random distribution
            vm.roll(START);
            votes.push(vote);
            votes.push(10000 - vote);
            vm.prank(holder);
            yieldDistributor2.castVote(votes);
            votes.pop();
            votes.pop();
            votes.push(vote2);
            votes.push(10000 - vote2);
            vm.roll(START + 10);
            vm.prank(holder);
            yieldDistributor2.castVote(votes);
            votes.pop();
            votes.pop();
        }
        vm.roll(START);
        // Distributing yield
        yieldDistributor2.distributeYield();

        // Getting the balance of the projects after the distribution
        uint256 this_bal_after = bread.balanceOf(address(this));
        uint256 second_bal_after = bread.balanceOf(secondProject);
        assertGt(this_bal_after, breadbalproject1start);
        assertGt(second_bal_after, breadbalproject2start);
    }

    function test_set_duration() public {
        yieldDistributor.setCycleLength(10);
        uint256 cycleLength = yieldDistributor.cycleLength();
        assertEq(10, cycleLength);
    }

    function test_voting_power() public {
        vm.roll(32323232323);
        uint256 votingPowerBefore;
        vm.expectRevert();
        votingPowerBefore = yieldDistributor.getVotingPowerForPeriod(bread, 32323232323, 32323232324, address(this));
        vm.deal(address(this), 1000000000000);
        vm.roll(42424242424);
        bread.mint{value: 1000000}(address(this));
        vm.roll(42424242425);
        uint256 votingPowerAfter =
            yieldDistributor.getVotingPowerForPeriod(bread, 42424242424, 42424242425, address(this));
        assertEq(votingPowerAfter, 1000000);
        vm.roll(42424242426);
        votingPowerAfter = yieldDistributor.getVotingPowerForPeriod(bread, 42424242424, 42424242426, address(this));
        assertEq(votingPowerAfter, 2000000);
        vm.roll(42424242427);
        bread.mint{value: 1000000}(address(this));
        vm.roll(42424242428);
        votingPowerAfter = yieldDistributor.getVotingPowerForPeriod(bread, 42424242424, 42424242428, address(this));
        assertEq(votingPowerAfter, 5000000);
        vm.roll(42424242430);
        votingPowerAfter = yieldDistributor.getVotingPowerForPeriod(bread, 42424242424, 42424242430, address(this));
        assertEq(votingPowerAfter, 9000000);
        vm.expectRevert();
        votingPowerAfter = yieldDistributor.getVotingPowerForPeriod(bread, 42424242424, 42424242431, address(this));
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
        uint256 vote = yieldDistributor.getVotingPowerForPeriod(bread, start, mintblocknum, holder);
        assertEq(vote, expectedVotingPower);
    }

    function test_adding_removing_projects() public {
        // Checking to see if the project list length  is initialized correctly
        vm.expectRevert();
        address projects_before_len;
        projects_before_len = yieldDistributor.projects(1);

        // Checking to see if the project list is initialized correctly
        address active_project = yieldDistributor.projects(0);
        assertEq(active_project, address(this));

        // Initalizing voter to complete cycle
        address[] memory voters = new address[](1);
        voters[0] = address(this);
        setUpAccountsForVoting(voters);

        // Setting up for a cycle and queueing project addition/removal
        setUpForCycle(yieldDistributor);
        yieldDistributor.queueProjectAddition(secondProject);
        yieldDistributor.queueProjectRemoval(address(this));

        // Casting vote and distributing yield
        uint256 vote = 100;
        percentages.push(vote);
        yieldDistributor.castVote(percentages);
        yieldDistributor.distributeYield();

        // Checking if the project was added correctly
        address project_added_after = yieldDistributor.projects(0);
        assertEq(project_added_after, secondProject);

        // Checking to see if addition queue is empty
        vm.expectRevert();
        yieldDistributor.queuedProjectsForAddition(0);

        // Checking to see if removal queue is empty
        vm.expectRevert();
        yieldDistributor.queuedProjectsForRemoval(0);

        // Checking to see if project which is not in the list can be removed
        address random_project = address(0x1244567830123456789012345478901234567890);
        vm.expectRevert();
        yieldDistributor.queueProjectRemoval(random_project);

        // Making sure the project was removed
        uint256 length = yieldDistributor.getProjectsLength();
        assertEq(length, 1);
    }

    function test_below_min_required_voting_power() public {
        // Setting up an account without the minimum required voting power
        address account = address(0x1234567890123356789012345672901234567890);

        vm.roll(START - (minHoldingDurationInBlocks - 1));
        vm.deal(account, _minVotingAmount);
        vm.prank(account);
        bread.mint{value: 5 * 1e4}(account);

        // Setting up for a cycle and casting vote
        setUpForCycle(yieldDistributor);
        uint256 vote = 100;
        percentages.push(vote);
        vm.prank(account);

        vm.expectRevert(abi.encodeWithSelector(YieldDistributor.BelowMinRequiredVotingPower.selector));
        yieldDistributor.castVote(percentages);
    }
}
