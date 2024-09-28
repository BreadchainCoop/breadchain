// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {YieldDistributor, IYieldDistributor} from "src/YieldDistributor.sol";
import {YieldDistributorTestWrapper} from "src/test/YieldDistributorTestWrapper.sol";
import {ButteredBread} from "src/ButteredBread.sol";
import {VotingMultipliers, IVotingMultipliers} from "src/VotingMultipliers.sol";
import {MockMultiplier} from "src/test/MockMultiplier.sol";
import {IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {NFTMultiplier} from "src/multipliers/NFTMultiplier.sol";
import {DeployNFTMultiplier} from "script/deploy/DeployNFTMultiplier.s.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

abstract contract Bread is ERC20VotesUpgradeable, Ownable2StepUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external virtual;
    function mint(address receiver) external payable virtual;
}

contract YieldDistributorTest is Test {
    uint256 constant START = 32_323_232_323;
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
    ButteredBread public butteredBread = ButteredBread(address(_bread));
    uint256 minHoldingDurationInBlocks = _minHoldingDuration / _blocktime;

    // For testing purposes, these values were used in the following way to configure _minRequiredVotingPower
    // uint256 minHoldingDuration = 10 days;
    // uint256 blockTime = 5;
    // uint256 minRequiredVotingPower = (minVotingAmount * minHoldingDuration) / blockTime; // We can assume that blockTime is small enough

    uint256 _minRequiredVotingPower = stdJson.readUint(config_data, "._minRequiredVotingPower");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects1 = new address[](1);
        projects1[0] = address(this);
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            address(butteredBread),
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
            address(butteredBread),
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
        yieldDistributor2.setYieldFixedSplitDivisor(3);

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
        uint256 bread_bal_after = bread.balanceOf(secondProject);
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
        seed = uint256(bound(seed, 1, 100_000_000_000));

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
            votes.push(10_000 - vote);
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
        seed = uint256(bound(seed, 1, 100_000_000_000));

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
            votes.push(10_000 - vote);
            vm.prank(holder);
            yieldDistributor2.castVote(votes);
            votes.pop();
            votes.pop();
            votes.push(vote2);
            votes.push(10_000 - vote2);
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
        vm.roll(32_323_232_323);
        uint256 votingPowerBefore;
        vm.expectRevert();
        votingPowerBefore =
            yieldDistributor.getVotingPowerForPeriod(bread, 32_323_232_323, 32_323_232_324, address(this));
        vm.deal(address(this), 1_000_000_000_000);
        vm.roll(42_424_242_424);
        bread.mint{value: 1_000_000}(address(this));
        vm.roll(42_424_242_425);
        uint256 votingPowerAfter =
            yieldDistributor.getVotingPowerForPeriod(bread, 42_424_242_424, 42_424_242_425, address(this));
        assertEq(votingPowerAfter, 1_000_000);
        vm.roll(42_424_242_426);
        votingPowerAfter =
            yieldDistributor.getVotingPowerForPeriod(bread, 42_424_242_424, 42_424_242_426, address(this));
        assertEq(votingPowerAfter, 2_000_000);
        vm.roll(42_424_242_427);
        bread.mint{value: 1_000_000}(address(this));
        vm.roll(42_424_242_428);
        votingPowerAfter =
            yieldDistributor.getVotingPowerForPeriod(bread, 42_424_242_424, 42_424_242_428, address(this));
        assertEq(votingPowerAfter, 5_000_000);
        vm.roll(42_424_242_430);
        votingPowerAfter =
            yieldDistributor.getVotingPowerForPeriod(bread, 42_424_242_424, 42_424_242_430, address(this));
        assertEq(votingPowerAfter, 9_000_000);
        vm.expectRevert();
        votingPowerAfter =
            yieldDistributor.getVotingPowerForPeriod(bread, 42_424_242_424, 42_424_242_431, address(this));
    }

    function testFuzzy_voting_power(uint256 seed, uint256 mints) public {
        mints = uint256(bound(mints, 1, 100));
        vm.assume(seed < 100_000_000_000 / mints);
        vm.assume(seed > 0);
        vm.assume(mints > 2);
        uint256 start = 32_323_232_323;
        vm.roll(start);
        address holder = address(0x1234567840123456789012345678701234567890);
        vm.deal(holder, 1_000_000_000_000_000_000);
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

        vm.expectRevert(abi.encodeWithSelector(IYieldDistributor.BelowMinRequiredVotingPower.selector));
        yieldDistributor.castVote(percentages);
    }
}

contract VotingMultipliersTest is YieldDistributorTest {
    MockMultiplier public mockMultiplier1;
    MockMultiplier public mockMultiplier2;
    NFTMultiplier public nftMultiplier;

    function setUp() public override {
        super.setUp();

        mockMultiplier1 = new MockMultiplier();
        mockMultiplier2 = new MockMultiplier();
    }

    function testAddMultiplier() public {
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
<<<<<<< HEAD
        assertEq(address(yieldDistributor.allowlistedMultipliers(0)), address(mockMultiplier1));
    }

    function testAddMultiplierRevertAlreadyAllowlisted() public {
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
        vm.expectRevert(IVotingMultipliers.MultiplierAlreadyAllowlisted.selector);
=======
        assertEq(address(yieldDistributor.whitelistedMultipliers(0)), address(mockMultiplier1));
    }

    function testAddMultiplierRevertAlreadyWhitelisted() public {
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
        vm.expectRevert(IVotingMultipliers.MultiplierAlreadyWhitelisted.selector);
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
    }

    function testRemoveMultiplier() public {
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
        yieldDistributor.removeMultiplier(IMultiplier(address(mockMultiplier1)));
        vm.expectRevert();
<<<<<<< HEAD
        yieldDistributor.allowlistedMultipliers(0);
    }

    function testRemoveMultiplierRevertNotallowlisted() public {
        vm.expectRevert(IVotingMultipliers.MultiplierNotAllowlisted.selector);
=======
        yieldDistributor.whitelistedMultipliers(0);
    }

    function testRemoveMultiplierRevertNotWhitelisted() public {
        vm.expectRevert(IVotingMultipliers.MultiplierNotWhitelisted.selector);
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)
        yieldDistributor.removeMultiplier(IMultiplier(address(mockMultiplier1)));
    }

    function testGetTotalMultipliers() public {
        uint256 factor1 = 1.5e18;
        uint256 factor2 = 2e18;
        uint256 validUntil = block.number + 1000;
        mockMultiplier1.setMultiplier(factor1, validUntil);
        mockMultiplier2.setMultiplier(factor2, validUntil);

        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier2)));

        uint256 totalMultiplier = yieldDistributor.getTotalMultipliers(address(this));
        assertEq(totalMultiplier, factor1 + factor2);
    }

<<<<<<< HEAD
    function testCastVoteWithMultipliersIndices() public {
        // Set up two multipliers with different factors
        mockMultiplier1.setMultiplier(1.5e18, type(uint256).max);
        mockMultiplier2.setMultiplier(2e18, type(uint256).max);
=======
    function testGetTotalMultipliersExpired() public {
        uint256 expiredMultiplier = 1.5e18;
        uint256 validMultiplier = 2e18;
        uint256 expiredBlockOffset = 1;
        uint256 validBlockOffset = 1000;

        mockMultiplier1.setMultiplier(expiredMultiplier, block.number - expiredBlockOffset);
        mockMultiplier2.setMultiplier(validMultiplier, block.number + validBlockOffset);

        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier1)));
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier2)));

        uint256 totalMultiplier = yieldDistributor.getTotalMultipliers(address(this));
        assertEq(totalMultiplier, validMultiplier);
    }

    function testCastVoteWithMultipliers() public {
        mockMultiplier1.setMultiplier(2e18, type(uint256).max);
        address voter = address(0x1);
        assertEq(mockMultiplier1.getMultiplyingFactor(voter), 2e18);
        address[] memory voters = new address[](1);
        voters[0] = voter;
        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);
        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
        yieldDistributor.addMultiplier(mockMultiplier1);
        vm.startPrank(voter);
        yieldDistributor.castVote(points);

        // Check that the voting power was doubled
        assertEq(yieldDistributor.projectDistributions(0), initialVotingPower * 2);
        vm.stopPrank();
    }

    function testCastVoteWithMultipleMultipliers() public {
        uint256 multiplier1Factor = 1.5e18;
        uint256 multiplier2Factor = 2e18;
        uint256 validUntil = type(uint256).max;

        mockMultiplier1.setMultiplier(multiplier1Factor, validUntil);
        mockMultiplier2.setMultiplier(multiplier2Factor, validUntil);
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)

        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;

        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);

        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);

<<<<<<< HEAD
        // Add multipliers to the distributor
        yieldDistributor.addMultiplier(mockMultiplier1);
        yieldDistributor.addMultiplier(mockMultiplier2);

        // Set up vote points and multiplier indices
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](2);
        multiplierIndices[0] = 0; // mockMultiplier1
        multiplierIndices[1] = 1; // mockMultiplier2

        vm.startPrank(voter);
        yieldDistributor.castVoteWithMultipliers(points, multiplierIndices);

        // Expected voting power = initial * (1.5 + 2.0)
        uint256 expectedVotingPower = (initialVotingPower * 3.5e18) / yieldDistributor.PRECISION();
        assertEq(yieldDistributor.projectDistributions(0), expectedVotingPower);
        vm.stopPrank();
    }

    function testCastVoteWithMultipliersIndicesInvalidIndex() public {
        mockMultiplier1.setMultiplier(1.5e18, type(uint256).max);

        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;

        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);

        yieldDistributor.addMultiplier(mockMultiplier1);

        uint256[] memory points = new uint256[](1);
        points[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](1);
        multiplierIndices[0] = 999; // Invalid index

        vm.startPrank(voter);
        vm.expectRevert();
        yieldDistributor.castVoteWithMultipliers(points, multiplierIndices);
        vm.stopPrank();
    }

    function testCastVoteWithMultipliersExpiredMultiplier() public {
        // Set up one expired and one valid multiplier
        mockMultiplier1.setMultiplier(1.5e18, block.number - 1); // Expired
        mockMultiplier2.setMultiplier(2e18, type(uint256).max); // Valid

        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;

        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);

        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);
=======
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)

        yieldDistributor.addMultiplier(mockMultiplier1);
        yieldDistributor.addMultiplier(mockMultiplier2);

<<<<<<< HEAD
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](2);
        multiplierIndices[0] = 0;
        multiplierIndices[1] = 1;

        vm.startPrank(voter);
        yieldDistributor.castVoteWithMultipliers(points, multiplierIndices);

        // Only the valid multiplier should be applied
        uint256 expectedVotingPower = (initialVotingPower * 2e18) / yieldDistributor.PRECISION();
=======
        vm.startPrank(voter);
        yieldDistributor.castVote(points);

        // Calculate expected voting power
        uint256 expectedVotingPower =
            (initialVotingPower * (multiplier1Factor + multiplier2Factor)) / yieldDistributor.PRECISION();

        // Check that the voting power was multiplied correctly
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)
        assertEq(yieldDistributor.projectDistributions(0), expectedVotingPower);
        vm.stopPrank();
    }

<<<<<<< HEAD
    function testFuzzCastVoteWithMultipliersIndices(
        uint256 multiplier1Factor,
        uint256 multiplier2Factor,
        uint8 numIndices
    ) public {
        // Bound the inputs to reasonable ranges
        multiplier1Factor = bound(multiplier1Factor, 1e18, 5e18);
        multiplier2Factor = bound(multiplier2Factor, 1e18, 5e18);
        numIndices = uint8(bound(numIndices, 1, 2));

        mockMultiplier1.setMultiplier(multiplier1Factor, type(uint256).max);
        mockMultiplier2.setMultiplier(multiplier2Factor, type(uint256).max);
=======
    function testFuzzCastVoteWithMultipliers(uint256 multiplier1Factor, uint256 multiplier2Factor) public {
        // Bound the inputs to reasonable ranges
        multiplier1Factor = bound(multiplier1Factor, 1e18, 5e18);
        multiplier2Factor = bound(multiplier2Factor, 1e18, 5e18);

        uint256 validUntil = type(uint256).max;

        mockMultiplier1.setMultiplier(multiplier1Factor, validUntil);
        mockMultiplier2.setMultiplier(multiplier2Factor, validUntil);
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)

        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;

        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);
<<<<<<< HEAD

        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);
=======
        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)

        yieldDistributor.addMultiplier(mockMultiplier1);
        yieldDistributor.addMultiplier(mockMultiplier2);

<<<<<<< HEAD
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](numIndices);
        for (uint8 i = 0; i < numIndices; i++) {
            multiplierIndices[i] = i;
        }

        vm.prank(voter);
        yieldDistributor.castVoteWithMultipliers(points, multiplierIndices);

        // Calculate expected total multiplier based on number of indices
        uint256 totalMultiplier = numIndices == 1 ? multiplier1Factor : (multiplier1Factor + multiplier2Factor);
        uint256 expectedVotingPower = (initialVotingPower * totalMultiplier) / yieldDistributor.PRECISION();

        assertApproxEqRel(yieldDistributor.projectDistributions(0), expectedVotingPower, 1e15); // Allow 0.1% deviation
    }

    function testFuzzCastVoteWithDynamicMultipliers(uint8 numMultipliers, bytes32[] calldata multiplierSeeds) public {
        // Bound number of multipliers to reasonable range (1-10)
        numMultipliers = uint8(bound(numMultipliers, 1, 10));

        // Create array of mock multipliers
        MockMultiplier[] memory multipliers = new MockMultiplier[](numMultipliers);
        uint256 expectedTotalMultiplier = 0;
        uint256 numValidMultipliers = 0;
        // Set up each multiplier with unique factor based on seed
        for (uint8 i = 0; i < numMultipliers; i++) {
            multipliers[i] = new MockMultiplier();

            // Generate multiplier factor from seed (between 1x and 5x)
            uint256 multiplierFactor;
            if (i < multiplierSeeds.length) {
                multiplierFactor = bound(uint256(multiplierSeeds[i]), 1e18, 5e18);
            } else {
                multiplierFactor = bound(uint256(keccak256(abi.encode(i))), 1e18, 5e18);
            }

            // Randomly decide if multiplier should be expired (10% chance)
            bool isExpired = uint256(keccak256(abi.encode(multiplierFactor, i))) % 10 == 0;
            uint256 validUntil = isExpired ? block.number - 1 : type(uint256).max;

            multipliers[i].setMultiplier(multiplierFactor, validUntil);
            yieldDistributor.addMultiplier(multipliers[i]);

            if (!isExpired) {
                expectedTotalMultiplier += multiplierFactor;
                numValidMultipliers++;
            }
        }

        // Set up voter
=======
        vm.prank(voter);
        yieldDistributor.castVote(points);

        // Calculate expected voting power
        uint256 expectedVotingPower =
            (initialVotingPower * (multiplier1Factor + multiplier2Factor)) / yieldDistributor.PRECISION();

        // Check that the voting power was multiplied correctly
        assertApproxEqRel(yieldDistributor.projectDistributions(0), expectedVotingPower, 1e15); // Allow 0.1% deviation
    }

    function testFuzzCastVoteWithDynamicMultipliers(uint8 numMultipliers) public {
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)
        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;

        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);
<<<<<<< HEAD

        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);

        // Create vote points and multiplier indices
        uint256[] memory points = new uint256[](1);
        points[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](numMultipliers);
        for (uint8 i = 0; i < numMultipliers; i++) {
            multiplierIndices[i] = i;
        }
        uint256[] memory fetchedMultipliers = yieldDistributor.getValidMultiplierIndexes(voter);
        assertEq(fetchedMultipliers.length, numValidMultipliers);
        vm.prank(voter);
        yieldDistributor.castVoteWithMultipliers(points, fetchedMultipliers);

        // If no valid multipliers, should use precision as multiplier
        if (expectedTotalMultiplier == 0) {
            expectedTotalMultiplier = yieldDistributor.PRECISION();
        }

        uint256 expectedVotingPower = (initialVotingPower * expectedTotalMultiplier) / yieldDistributor.PRECISION();

        // Allow for small rounding errors in calculation
        assertApproxEqRel(
            yieldDistributor.projectDistributions(0),
            expectedVotingPower,
            1e15 // 0.1% tolerance
        );

        // Verify all multipliers were properly registered
        for (uint8 i = 0; i < numMultipliers; i++) {
            assertEq(address(yieldDistributor.allowlistedMultipliers(i)), address(multipliers[i]));
        }
=======
        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);

        // Bound the number of multipliers to a reasonable range
        numMultipliers = uint8(bound(uint256(numMultipliers), 1, 10));

        // Create and set up mock multipliers
        MockMultiplier[] memory mockMultipliers = new MockMultiplier[](numMultipliers);
        uint256 totalMultiplier = 0;
        uint256 validUntil = type(uint256).max;
        for (uint8 i = 0; i < numMultipliers; i++) {
            mockMultipliers[i] = new MockMultiplier();
            uint256 multiplierFactor = bound(uint256(keccak256(abi.encode(i))), 1e18, 5e18);
            mockMultipliers[i].setMultiplier(multiplierFactor, validUntil);
            totalMultiplier += multiplierFactor;
            yieldDistributor.addMultiplier(mockMultipliers[i]);
        }

        uint256[] memory points = new uint256[](1);
        points[0] = 100;

        vm.prank(voter);
        yieldDistributor.castVote(points);

        // Calculate expected voting power
        uint256 expectedVotingPower = (initialVotingPower * totalMultiplier) / yieldDistributor.PRECISION();

        // Check that the voting power was multiplied correctly
        assertApproxEqRel(yieldDistributor.projectDistributions(0), expectedVotingPower, 1e15); // Allow 0.1% deviation
    }

    function testNFTMultiplierDeployment() public {
        address nftContractAddress = address(0x1234567890123456789012345678901234567890);
        uint256 multiplyingFactor = 1.5e18; // 1.5x
        uint256 validUntilBlock = type(uint256).max;

        // Set up environment variables for the deployment script
        vm.setEnv("PRIVATE_KEY", "0x1234567890123456789012345678901234567890123456789012345678901234");
        vm.setEnv("NFT_CONTRACT_ADDRESS", vm.toString(nftContractAddress));
        vm.setEnv("INITIAL_MULTIPLYING_FACTOR", vm.toString(multiplyingFactor));
        vm.setEnv("VALID_UNTIL_BLOCK", vm.toString(validUntilBlock));

        // Mock the NFT contract's balanceOf function
        vm.mockCall(nftContractAddress, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        // Run the deployment script
        DeployNFTMultiplier deployer = new DeployNFTMultiplier();
        vm.recordLogs();
        deployer.run();

        // Get the deployed contract address from the logs
        address deployedAddress = vm.getRecordedLogs()[1].emitter;

        // Create an instance of the deployed contract
        nftMultiplier = NFTMultiplier(deployedAddress);

        // Verify the deployment
        assertEq(address(nftMultiplier.NFTAddress()), nftContractAddress);
        assertEq(nftMultiplier.multiplyingFactor(), multiplyingFactor);
        assertEq(nftMultiplier.validUntil(address(this)), validUntilBlock);

        // Test integration with YieldDistributor

        // Set up a voter with an NFT
        address voter = address(0x1);
        vm.mockCall(nftContractAddress, abi.encodeWithSelector(IERC721.balanceOf.selector, voter), abi.encode(1));

        // Set up voting
        address[] memory voters = new address[](1);
        voters[0] = voter;
        setUpAccountsForVoting(voters);
        setUpForCycle(yieldDistributor);
        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);

        yieldDistributor.addMultiplier(IMultiplier(address(nftMultiplier)));

        uint256[] memory points = new uint256[](1);
        points[0] = 100;

        // Cast vote
        vm.prank(voter);
        yieldDistributor.castVote(points);

        // Check that the voting power was multiplied correctly
        uint256 expectedVotingPower = (initialVotingPower * multiplyingFactor) / 1e18;
        assertEq(yieldDistributor.projectDistributions(0), expectedVotingPower);
>>>>>>> fffe13b (chore: adding unit and fuzzy tests)
    }
}
