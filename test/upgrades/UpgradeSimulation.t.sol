// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {YieldDistributor} from "src/YieldDistributor.sol";

/**
 * @title UpgradeSimulation
 * @notice End-to-end fork test that simulates upgrading the YieldDistributor proxy on Gnosis mainnet.
 *
 * The test:
 *  1. Forks Gnosis mainnet via GNOSIS_RPC_URL.
 *  2. Snapshots all key state variables from the proxy *before* the upgrade.
 *  3. Discovers the ProxyAdmin contract address from the ERC-1967 admin storage slot.
 *  4. Pranks as the Breadchain multisig (owner of ProxyAdmin) to authorise the upgrade.
 *  5. Deploys a fresh YieldDistributor implementation.
 *  6. Calls ProxyAdmin.upgradeAndCall to point the proxy at the new implementation.
 *  7. Asserts every captured state variable is unchanged after the upgrade.
 *  8. Smoke-tests several view functions to confirm the contract is still fully operational.
 *
 * Architecture note (OZ v5 TransparentUpgradeableProxy):
 *   When the proxy was originally deployed the constructor created a dedicated ProxyAdmin
 *   contract and stored its address in the ERC-1967 admin slot.  The Breadchain multisig
 *   owns that ProxyAdmin.  Therefore upgrades must go through:
 *     ProxyAdmin.upgradeAndCall(proxy, newImpl, "")   ← called by the multisig
 *   NOT by calling upgradeToAndCall directly on the proxy from the multisig.
 *
 * Addresses (Gnosis mainnet, tag v1.3.0):
 *   Proxy:               0xeE95A62b749d8a2520E0128D9b3aCa241269024b
 *   Breadchain multisig: 0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad
 */
contract UpgradeSimulationTest is Test {
    // ─── Constants ──────────────────────────────────────────────────────────

    /// @dev YieldDistributor TransparentUpgradeableProxy on Gnosis.
    address constant PROXY = 0xeE95A62b749d8a2520E0128D9b3aCa241269024b;

    /// @dev Breadchain multisig – owner of the ProxyAdmin contract.
    address constant MULTISIG = 0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad;

    /// @dev ERC-1967 admin storage slot: keccak256("eip1967.proxy.admin") - 1
    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // ─── Pre-upgrade state snapshot ─────────────────────────────────────────

    uint256 pre_cycleLength;
    uint256 pre_lastClaimedBlockNumber;
    uint256 pre_yieldFixedSplitDivisor;
    address pre_owner;
    address pre_BREAD;
    address pre_BUTTERED_BREAD;
    uint256 pre_PRECISION;
    uint256 pre_maxPoints;
    uint256 pre_currentVotes;
    uint256 pre_previousCycleStartingBlock;
    uint256 pre_votingCycle;
    uint256 pre_votersCount;

    // Projects array snapshot
    address[] pre_projects;

    // ─── Convenience handles ────────────────────────────────────────────────

    YieldDistributor proxy;
    ProxyAdmin proxyAdmin;

    // ─── Fork setup ─────────────────────────────────────────────────────────

    function setUp() public {
        // 1. Create and select a Gnosis mainnet fork.
        uint256 forkId = vm.createFork(vm.envString("GNOSIS_RPC_URL"));
        vm.selectFork(forkId);

        // Wrap the proxy address with the YieldDistributor ABI for convenient state reads.
        proxy = YieldDistributor(PROXY);

        // 2. Discover the ProxyAdmin contract deployed by the TransparentUpgradeableProxy
        //    constructor.  Its address lives in the ERC-1967 admin slot of the proxy.
        bytes32 rawAdmin = vm.load(PROXY, ADMIN_SLOT);
        address proxyAdminAddr = address(uint160(uint256(rawAdmin)));
        proxyAdmin = ProxyAdmin(proxyAdminAddr);

        console2.log("ProxyAdmin contract address:", proxyAdminAddr);
        console2.log("ProxyAdmin owner            :", proxyAdmin.owner());

        // Sanity: the multisig must own the ProxyAdmin.
        assertEq(proxyAdmin.owner(), MULTISIG, "ProxyAdmin owner is not the Breadchain multisig");

        // 3. Capture pre-upgrade state.
        _snapshotState();
    }

    // ─── Main upgrade simulation test ────────────────────────────────────────

    /**
     * @notice Full upgrade flow: deploy new implementation → upgrade proxy → assert state preserved.
     */
    function test_upgradePreservesState() public {
        // ── Step 4: Deploy a fresh implementation contract. ──────────────────
        // The constructor calls _disableInitializers(), which is safe on an
        // implementation contract (not a proxy).
        YieldDistributor newImpl = new YieldDistributor();
        console2.log("New implementation deployed:", address(newImpl));

        // ── Step 5: Upgrade the proxy as the Breadchain multisig. ────────────
        // The multisig owns the ProxyAdmin, so it calls upgradeAndCall on it.
        vm.startPrank(MULTISIG);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(PROXY),
            address(newImpl),
            "" // No initialisation call needed; storage already initialised.
        );
        vm.stopPrank();

        console2.log("Proxy upgraded to new implementation.");

        // ── Step 6: Assert all state variables are preserved. ─────────────────
        _assertStatePreserved();

        // ── Step 7: Smoke-test view functions. ────────────────────────────────
        _smokeTestViewFunctions();
    }

    /**
     * @notice Ensure the new implementation address is actually different from the old one
     *         (i.e., the upgrade was applied) and that re-initialisation is blocked.
     */
    function test_upgradeChangesImplementation() public {
        // Read the ERC-1967 implementation slot before upgrade.
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address oldImpl = address(uint160(uint256(vm.load(PROXY, implSlot))));

        YieldDistributor newImpl = new YieldDistributor();

        vm.startPrank(MULTISIG);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(PROXY), address(newImpl), "");
        vm.stopPrank();

        address currentImpl = address(uint160(uint256(vm.load(PROXY, implSlot))));

        console2.log("Old implementation:", oldImpl);
        console2.log("New implementation:", currentImpl);

        assertEq(currentImpl, address(newImpl), "Implementation address not updated");
        assertTrue(currentImpl != oldImpl, "Implementation address unchanged after upgrade");
    }

    /**
     * @notice Confirm that consumed reinitializer versions cannot be replayed after upgrade.
     * @dev Tests reinitializer(3) (initializeVotingCycle) which is known to have been
     *      called on-chain (votingCycle > 0). The original initialize() uses the
     *      `initializer` modifier whose guard behaviour may differ between OZ versions
     *      when the proxy was deployed with OZ v4 and upgraded to OZ v5, so we test
     *      a reinitializer that is unambiguously consumed.
     */
    function test_cannotReinitialize() public {
        YieldDistributor newImpl = new YieldDistributor();

        vm.startPrank(MULTISIG);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(PROXY), address(newImpl), "");

        // initializeVotingCycle uses reinitializer(3) — already consumed on-chain
        // (votingCycle > 0 confirms this). Calling it again must revert.
        vm.expectRevert();
        proxy.initializeVotingCycle(999);
        vm.stopPrank();
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// @dev Reads and stores every public state variable of the proxy.
    function _snapshotState() internal {
        pre_cycleLength = proxy.cycleLength();
        pre_lastClaimedBlockNumber = proxy.lastClaimedBlockNumber();
        pre_yieldFixedSplitDivisor = proxy.yieldFixedSplitDivisor();
        pre_owner = proxy.owner();
        pre_BREAD = address(proxy.BREAD());
        pre_BUTTERED_BREAD = address(proxy.BUTTERED_BREAD());
        pre_PRECISION = proxy.PRECISION();
        pre_maxPoints = proxy.maxPoints();
        pre_currentVotes = proxy.currentVotes();
        pre_previousCycleStartingBlock = proxy.previousCycleStartingBlock();
        pre_votingCycle = proxy.votingCycle();
        pre_votersCount = proxy.votersCount();

        // Capture the projects array.
        uint256 i;
        while (true) {
            try proxy.projects(i) returns (address p) {
                pre_projects.push(p);
                unchecked { ++i; }
            } catch {
                break;
            }
        }

        console2.log("=== Pre-upgrade snapshot ===");
        console2.log("cycleLength             :", pre_cycleLength);
        console2.log("lastClaimedBlockNumber  :", pre_lastClaimedBlockNumber);
        console2.log("yieldFixedSplitDivisor  :", pre_yieldFixedSplitDivisor);
        console2.log("owner                   :", pre_owner);
        console2.log("BREAD                   :", pre_BREAD);
        console2.log("BUTTERED_BREAD          :", pre_BUTTERED_BREAD);
        console2.log("PRECISION               :", pre_PRECISION);
        console2.log("maxPoints               :", pre_maxPoints);
        console2.log("currentVotes            :", pre_currentVotes);
        console2.log("previousCycleStartBlock :", pre_previousCycleStartingBlock);
        console2.log("votingCycle             :", pre_votingCycle);
        console2.log("votersCount             :", pre_votersCount);
        console2.log("projects.length         :", pre_projects.length);
        for (uint256 j; j < pre_projects.length; ++j) {
            console2.log("  projects[", j, "]:", pre_projects[j]);
        }
    }

    /// @dev Asserts that all captured state variables match the current proxy values.
    function _assertStatePreserved() internal view {
        assertEq(proxy.cycleLength(), pre_cycleLength, "cycleLength changed");
        assertEq(proxy.lastClaimedBlockNumber(), pre_lastClaimedBlockNumber, "lastClaimedBlockNumber changed");
        assertEq(proxy.yieldFixedSplitDivisor(), pre_yieldFixedSplitDivisor, "yieldFixedSplitDivisor changed");
        assertEq(proxy.owner(), pre_owner, "owner changed");
        assertEq(address(proxy.BREAD()), pre_BREAD, "BREAD address changed");
        assertEq(address(proxy.BUTTERED_BREAD()), pre_BUTTERED_BREAD, "BUTTERED_BREAD address changed");
        assertEq(proxy.PRECISION(), pre_PRECISION, "PRECISION changed");
        assertEq(proxy.maxPoints(), pre_maxPoints, "maxPoints changed");
        assertEq(proxy.currentVotes(), pre_currentVotes, "currentVotes changed");
        assertEq(proxy.previousCycleStartingBlock(), pre_previousCycleStartingBlock, "previousCycleStartingBlock changed");
        assertEq(proxy.votingCycle(), pre_votingCycle, "votingCycle changed");
        assertEq(proxy.votersCount(), pre_votersCount, "votersCount changed");

        // Projects array length and contents.
        uint256 i;
        while (true) {
            try proxy.projects(i) returns (address p) {
                assertTrue(i < pre_projects.length, "projects array grew after upgrade");
                assertEq(p, pre_projects[i], "projects element changed after upgrade");
                unchecked { ++i; }
            } catch {
                break;
            }
        }
        assertEq(i, pre_projects.length, "projects array length changed after upgrade");

        console2.log("All state variables preserved after upgrade.");
    }

    /// @dev Calls read-only functions to confirm the contract is still operational.
    function _smokeTestViewFunctions() internal view {
        // getCurrentVotingDistribution returns (projects[], distributions[]).
        (address[] memory projs, uint256[] memory dists) = proxy.getCurrentVotingDistribution();
        assertEq(projs.length, pre_projects.length, "getCurrentVotingDistribution: projects length mismatch");
        assertEq(dists.length, pre_projects.length, "getCurrentVotingDistribution: distributions length mismatch");

        for (uint256 i; i < projs.length; ++i) {
            assertEq(projs[i], pre_projects[i], "getCurrentVotingDistribution: project address mismatch");
        }

        // getCurrentCycleVoters – returns the voters who have voted in the current cycle.
        address[] memory voters = proxy.getCurrentCycleVoters();
        assertEq(voters.length, pre_votersCount, "getCurrentCycleVoters: length mismatch");

        // resolveYieldDistribution – view function, should not revert.
        (bool canDistribute,) = proxy.resolveYieldDistribution();
        console2.log("resolveYieldDistribution:", canDistribute);

        console2.log("View-function smoke tests passed.");
    }
}
