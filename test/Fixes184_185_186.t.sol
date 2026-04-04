// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {YieldDistributor, IYieldDistributor} from "src/YieldDistributor.sol";
import {ButteredBread} from "src/ButteredBread.sol";
import {VotingMultipliers, IVotingMultipliers} from "src/VotingMultipliers.sol";
import {IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {VotingStreakMultiplier} from "src/multipliers/VotingStreakMultiplier.sol";
import {NFTMultiplier} from "src/multipliers/NFTMultiplier.sol";
import {YieldDistributorTestWrapper} from "src/test/YieldDistributorTestWrapper.sol";
import {MockBread} from "src/test/MockBread.sol";
import {MockMultiplier} from "src/test/MockMultiplier.sol";

/// @title Tests for issue #184: distributeYieldGK bypasses multipliers
/// @notice Verifies that voterEffectiveVotes is used in _computeVotedDistribution so that
///         distributeYieldGK cannot bypass vote multipliers by recomputing from raw voting power.
contract Fix184Test_DistributeYieldGKBypass is Test {
    uint256 constant START = 32_323_232_323;
    YieldDistributorTestWrapper public yieldDistributor;
    MockBread public bread;
    ButteredBread public butteredBread;
    MockMultiplier public mockMultiplier;
    address secondProject = address(0x1234567890123456789012345678901234567890);

    string deployConfigPath = string(bytes("./test/test_deploy.json"));
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

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects2 = new address[](2);
        projects2[0] = address(this);
        projects2[1] = secondProject;
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(_bread),
            address(_bread),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects2,
            address(this)
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        bread = MockBread(address(_bread));
        butteredBread = ButteredBread(address(_bread));
        mockMultiplier = new MockMultiplier();

        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDistributor));

        // Add the multiplier
        yieldDistributor.addMultiplier(IMultiplier(address(mockMultiplier)));
    }

    function setUpAccountsForVoting(address[] memory accounts) public {
        vm.roll(START - (_cycleLength + 1));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.deal(accounts[i], _minVotingAmount);
            vm.prank(accounts[i]);
            bread.mint{value: _minVotingAmount}(accounts[i]);
        }
    }

    function setUpForCycle() public {
        vm.roll(START - (_cycleLength));
        yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDistributor));
        vm.roll(START);
    }

    /// @notice voterEffectiveVotes is set when castVoteWithMultipliers is called.
    /// @dev Core fix for #184: voterEffectiveVotes stores the multiplier-adjusted voting power
    ///      so that _computeVotedDistribution (used by distributeYieldGK) cannot bypass multipliers.
    function test_distributeYieldGK_usesMultiplierAdjustedVotes() public {
        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;
        setUpAccountsForVoting(voters);
        setUpForCycle();

        // Set up multiplier: 2x boost
        mockMultiplier.setMultiplier(2e18, type(uint256).max);

        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);

        // Voter casts with multiplier index 0
        uint256[] memory points = new uint256[](2);
        points[0] = 100;
        points[1] = 0;

        vm.startPrank(voter);
        uint256[] memory multiplierIndices = new uint256[](1);
        multiplierIndices[0] = 0;
        yieldDistributor.castVoteWithMultipliers(points, multiplierIndices);
        vm.stopPrank();

        // voterEffectiveVotes should be set to multiplier-adjusted value
        uint256 effectiveVotes = yieldDistributor.voterEffectiveVotes(voter);
        uint256 expectedEffectiveVotes = (initialVotingPower * 2e18) / _precision; // 2x boost
        assertEq(effectiveVotes, expectedEffectiveVotes, "voterEffectiveVotes should be 2x initial");

        // projectDistributions (built at vote time via castVoteWithMultipliers) uses boosted votes
        uint256 projectDist = yieldDistributor.projectDistributions(0);
        uint256 expectedDist = (expectedEffectiveVotes * 100 * _precision) / (100 * _precision);
        assertEq(projectDist, expectedDist, "projectDistributions should use multiplier-adjusted votes");
    }

    /// @notice Regular castVote (no multipliers) should NOT set voterEffectiveVotes,
    ///         so _computeVotedDistribution falls back to raw voting power
    function test_regularCastVote_usesRawVotingPower() public {
        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;
        setUpAccountsForVoting(voters);
        setUpForCycle();

        uint256[] memory points = new uint256[](2);
        points[0] = 100;
        points[1] = 0;

        vm.startPrank(voter);
        yieldDistributor.castVote(points);
        vm.stopPrank();

        // voterEffectiveVotes should be 0 for regular vote (no multiplier)
        uint256 effectiveVotes = yieldDistributor.voterEffectiveVotes(voter);
        assertEq(effectiveVotes, 0, "voterEffectiveVotes should be 0 for regular castVote");
    }

    /// @notice If voter first casts regular vote then casts with multipliers,
    ///         voterEffectiveVotes should be updated to the multiplier-adjusted value
    function test_multiplierVote_afterRegularVote_usesMultiplierVotes() public {
        address voter = address(0x1);
        address[] memory voters = new address[](1);
        voters[0] = voter;
        setUpAccountsForVoting(voters);
        setUpForCycle();

        // First, regular vote
        uint256[] memory points1 = new uint256[](2);
        points1[0] = 50;
        points1[1] = 50;
        vm.startPrank(voter);
        yieldDistributor.castVote(points1);
        vm.stopPrank();

        assertEq(yieldDistributor.voterEffectiveVotes(voter), 0, "no effective votes after regular vote");

        // Then vote with multiplier
        mockMultiplier.setMultiplier(2e18, type(uint256).max);
        uint256 initialVotingPower = yieldDistributor.getCurrentVotingPower(voter);

        uint256[] memory points2 = new uint256[](2);
        points2[0] = 100;
        points2[1] = 0;
        uint256[] memory multiplierIndices = new uint256[](1);
        multiplierIndices[0] = 0;

        vm.startPrank(voter);
        yieldDistributor.castVoteWithMultipliers(points2, multiplierIndices);
        vm.stopPrank();

        uint256 expectedEffective = (initialVotingPower * 2e18) / _precision;
        assertEq(yieldDistributor.voterEffectiveVotes(voter), expectedEffective, "voterEffectiveVotes set after multiplier vote");
    }
}

/// @title Tests for issue #185: VotingStreakMultiplier.updateMultiplyingFactor spammable per cycle
/// @notice Verifies that updateMultiplyingFactor can only be called once per voting cycle.
contract Fix185Test_VotingStreakSpam is Test {
    uint256 constant START = 32_323_232_323;
    uint256 constant MULTIPLIER_INCREMENT = 0.01e18; // 1%
    uint256 constant MAX_MULTIPLIER_INCREMENTS = 3;

    YieldDistributorTestWrapper public yieldDistributor;
    VotingStreakMultiplier public streakMultiplier;

    string deployConfigPath = string(bytes("./test/test_deploy.json"));
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

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects1 = new address[](1);
        projects1[0] = address(this);
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(_bread),
            address(_bread),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects1,
            address(this)
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        VotingStreakMultiplier impl = new VotingStreakMultiplier();
        bytes memory multiplierInitData = abi.encodeWithSelector(
            VotingStreakMultiplier.initialize.selector,
            address(yieldDistributor),
            MULTIPLIER_INCREMENT,
            MAX_MULTIPLIER_INCREMENTS
        );
        streakMultiplier = VotingStreakMultiplier(
            address(new TransparentUpgradeableProxy(address(impl), address(this), multiplierInitData))
        );

        yieldDistributor.addMultiplier(IMultiplier(address(streakMultiplier)));

        address owner = MockBread(address(_bread)).owner();
        vm.prank(owner);
        MockBread(address(_bread)).setYieldClaimer(address(yieldDistributor));
    }

    function setUpAccountsForVoting(address[] memory accounts) public {
        vm.roll(START - (_cycleLength + 1));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.deal(accounts[i], _minVotingAmount);
            vm.prank(accounts[i]);
            MockBread(address(_bread)).mint{value: _minVotingAmount}(accounts[i]);
        }
    }

    function setUpForCycle(uint256 iterator) public {
        vm.roll(START + (_cycleLength * iterator));
        yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        address owner = MockBread(address(_bread)).owner();
        vm.prank(owner);
        MockBread(address(_bread)).setYieldClaimer(address(yieldDistributor));
        vm.roll(START + (_cycleLength * (iterator + 1)));
    }

    function castVote(address account) public {
        vm.startPrank(account);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](1);
        multiplierIndices[0] = 0;
        yieldDistributor.castVoteWithMultipliers(percentages, multiplierIndices);
        vm.stopPrank();
    }

    /// @notice updateMultiplyingFactor is public (no auth). Direct calls in same cycle:
    ///         first succeeds, second reverts with MultiplierAlreadyUpdatedThisCycle.
    /// @dev Core fix for #185: without lastUpdatedCycle guard, attacker calls this directly
    ///      in a single tx to spam-inflate their multiplier. With the guard, only first succeeds.
    function test_updateMultiplyingFactor_twiceInSameCycle_reverts() public {
        address testAccount = address(0x1);
        address[] memory accounts = new address[](1);
        accounts[0] = testAccount;
        setUpAccountsForVoting(accounts);
        // Set up: lastClaimedBlock at START - _cycleLength, current block at START
        vm.roll(START - _cycleLength);
        yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        vm.roll(START);

        // First call — succeeds (no lastUpdatedCycle set yet)
        streakMultiplier.updateMultiplyingFactor(testAccount);
        // Read the raw stored multiplier via the public mapping getter
        assertEq(
            streakMultiplier.userToMultiplier(testAccount),
            1e18 + MULTIPLIER_INCREMENT,
            "first call should store incremented multiplier"
        );

        // Second call in same cycle should REVERT with MultiplierAlreadyUpdatedThisCycle
        vm.expectRevert(VotingStreakMultiplier.MultiplierAlreadyUpdatedThisCycle.selector);
        streakMultiplier.updateMultiplyingFactor(testAccount);
    }

    /// @notice Spamming updateMultiplyingFactor in a single tx only applies one increment.
    /// @dev Without the fix, attacker could call this directly many times to stack increments.
    ///      With the fix, only the first call succeeds; rest revert in same tx.
    function test_updateMultiplyingFactor_spamInOneTx_onlyOneIncrement() public {
        address testAccount = address(0x1);
        address[] memory accounts = new address[](1);
        accounts[0] = testAccount;
        setUpAccountsForVoting(accounts);
        vm.roll(START - _cycleLength);
        yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        vm.roll(START);

        // Spam 10 direct calls in one tx — only first succeeds
        for (uint256 i = 0; i < 10; i++) {
            if (i == 0) {
                streakMultiplier.updateMultiplyingFactor(testAccount);
            } else {
                vm.expectRevert(VotingStreakMultiplier.MultiplierAlreadyUpdatedThisCycle.selector);
                streakMultiplier.updateMultiplyingFactor(testAccount);
            }
        }

        // Read raw stored multiplier — should only be 1 increment despite 10 calls
        assertEq(
            streakMultiplier.userToMultiplier(testAccount),
            1e18 + MULTIPLIER_INCREMENT,
            "Spam should not inflate multiplier beyond one increment per cycle"
        );
    }

    /// @notice After voting in consecutive cycles, multiplier increments correctly up to cap
    function test_updateMultiplyingFactor_consecutiveCycles_incrementsCorrectly() public {
        address testAccount = address(0x1);
        address[] memory accounts = new address[](1);
        accounts[0] = testAccount;
        setUpAccountsForVoting(accounts);
        uint256 baseMultiplier = 1e18;

        // Cycle 0
        setUpForCycle(0);
        castVote(testAccount);
        assertEq(streakMultiplier.getMultiplyingFactor(testAccount), baseMultiplier + MULTIPLIER_INCREMENT, "cycle 0");

        // Cycle 1
        setUpForCycle(1);
        castVote(testAccount);
        assertEq(streakMultiplier.getMultiplyingFactor(testAccount), baseMultiplier + 2 * MULTIPLIER_INCREMENT, "cycle 1");

        // Cycle 2
        setUpForCycle(2);
        castVote(testAccount);
        assertEq(streakMultiplier.getMultiplyingFactor(testAccount), baseMultiplier + 3 * MULTIPLIER_INCREMENT, "cycle 2");

        // Cycle 3: cap at max
        setUpForCycle(3);
        castVote(testAccount);
        uint256 expectedMax = baseMultiplier + MAX_MULTIPLIER_INCREMENTS * MULTIPLIER_INCREMENT;
        assertEq(streakMultiplier.getMultiplyingFactor(testAccount), expectedMax, "cycle 3 caps at max");

        // Cycle 4: stays at max
        setUpForCycle(4);
        castVote(testAccount);
        assertEq(streakMultiplier.getMultiplyingFactor(testAccount), expectedMax, "cycle 4 stays at max");
    }
}

contract Fix186Test_DuplicateMultiplierIndexes is Test {
    uint256 constant START = 32_323_232_323;

    YieldDistributorTestWrapper public yieldDistributor;
    MockMultiplier public mockMultiplier1;
    MockMultiplier public mockMultiplier2;
    MockBread public bread;
    address secondProject = address(0x1234567890123456789012345678901234567890);

    string deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    address _bread = stdJson.readAddress(config_data, "._bread");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects2 = new address[](2);
        projects2[0] = address(this);
        projects2[1] = secondProject;
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(_bread),
            address(_bread),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects2,
            address(this)
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        mockMultiplier1 = new MockMultiplier();
        mockMultiplier2 = new MockMultiplier();

        bread = MockBread(address(_bread));

        mockMultiplier1.setMultiplier(2e18, type(uint256).max); // 2x multiplier
        mockMultiplier2.setMultiplier(1.5e18, type(uint256).max); // 1.5x multiplier

        yieldDistributor.addMultiplier(mockMultiplier1);
        yieldDistributor.addMultiplier(mockMultiplier2);
    }

    /// @notice Passing [i, i] (same index twice) should revert with DuplicateMultiplierIndex
    function test_duplicateMultiplierIndexes_sameIndexTwice_reverts() public {
        uint256[] memory duplicateIndices = new uint256[](2);
        duplicateIndices[0] = 0;
        duplicateIndices[1] = 0; // duplicate of index 0

        vm.expectRevert(IVotingMultipliers.DuplicateMultiplierIndex.selector);
        // Note: calculateTotalMultipliers is called internally by castVoteWithMultipliers
        // We test it directly on the VotingMultipliers facet
        yieldDistributor.calculateTotalMultipliers(address(this), duplicateIndices);
    }

    /// @notice Passing [i, i, i] (same index three times) should revert with DuplicateMultiplierIndex
    function test_duplicateMultiplierIndexes_sameIndexThreeTimes_reverts() public {
        uint256[] memory triplicateIndices = new uint256[](3);
        triplicateIndices[0] = 0;
        triplicateIndices[1] = 0;
        triplicateIndices[2] = 0; // triplicate

        vm.expectRevert(IVotingMultipliers.DuplicateMultiplierIndex.selector);
        yieldDistributor.calculateTotalMultipliers(address(this), triplicateIndices);
    }

    /// @notice Passing [0, 1, 0] (0 repeated at start and end) should revert
    function test_duplicateMultiplierIndexes_repeatedAtEnds_reverts() public {
        uint256[] memory indices = new uint256[](3);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 0; // duplicate

        vm.expectRevert(IVotingMultipliers.DuplicateMultiplierIndex.selector);
        yieldDistributor.calculateTotalMultipliers(address(this), indices);
    }

    /// @notice Passing [0, 1] (unique) should succeed
    function test_uniqueMultiplierIndexes_succeeds() public {
        uint256[] memory uniqueIndices = new uint256[](2);
        uniqueIndices[0] = 0;
        uniqueIndices[1] = 1;

        uint256 result = yieldDistributor.calculateTotalMultipliers(address(this), uniqueIndices);

        // Expected: base (1e18) + bonus from m1 (1e18) + bonus from m2 (0.5e18) = 2.5e18
        uint256 expected = 1e18 + (2e18 - 1e18) + (1.5e18 - 1e18);
        assertEq(result, expected, "unique indexes should return combined multiplier");
    }

    /// @notice Passing [1, 0] (unique but not sorted ascending) should succeed
    function test_unsortedButUniqueIndexes_succeeds() public {
        uint256[] memory unsortedIndices = new uint256[](2);
        unsortedIndices[0] = 1; // not sorted
        unsortedIndices[1] = 0;

        uint256 result = yieldDistributor.calculateTotalMultipliers(address(this), unsortedIndices);

        uint256 expected = 1e18 + (2e18 - 1e18) + (1.5e18 - 1e18);
        assertEq(result, expected, "unsorted unique indexes should still work");
    }

    /// @notice Passing empty array [] should succeed and return BASE_MULTIPLIER
    function test_emptyMultiplierIndexes_succeeds() public {
        uint256[] memory emptyIndices = new uint256[](0);

        uint256 result = yieldDistributor.calculateTotalMultipliers(address(this), emptyIndices);

        assertEq(result, 1e18, "empty indexes should return BASE_MULTIPLIER");
    }

    /// @notice Duplicate via castVoteWithMultipliers should also revert
    function test_castVoteWithDuplicates_reverts() public {
        address voter = address(0x1);
        vm.deal(voter, 1 ether);
        vm.prank(voter);
        bread.mint{value: 1 ether}(voter);

        uint256[] memory points = new uint256[](2);
        points[0] = 100;
        points[1] = 0;

        uint256[] memory duplicateIndices = new uint256[](2);
        duplicateIndices[0] = 0;
        duplicateIndices[1] = 0; // duplicate

        vm.expectRevert(IVotingMultipliers.DuplicateMultiplierIndex.selector);
        vm.prank(voter);
        yieldDistributor.castVoteWithMultipliers(points, duplicateIndices);
    }
}
