// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "script/Constants.s.sol";
import "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ButteredBread, IButteredBread} from "src/ButteredBread.sol";
import {ICurveStableSwap} from "src/interfaces/ICurveStableSwap.sol";
import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";

/**
 * @title VotesExtended Tests for ButteredBread
 * @notice Tests for getPastDelegate and getPastBalanceOf checkpoints (Issue #156)
 */
contract VotesExtendedTest is Test {
    ButteredBread public bb;
    ICurveStableSwap public curvePoolXdai;
    address public proxyAdmin;

    uint256 constant XDAI_FACTOR = 700;
    uint256 constant TOKEN_AMOUNT = 10 ether;

    string public deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));
        curvePoolXdai = ICurveStableSwap(GNOSIS_CURVE_POOL_XDAI_BREAD);

        address[] memory _liquidityPools = new address[](1);
        _liquidityPools[0] = address(curvePoolXdai);

        uint256[] memory _scalingFactors = new uint256[](1);
        _scalingFactors[0] = XDAI_FACTOR;

        IButteredBread.InitData memory initData = IButteredBread.InitData({
            breadToken: GNOSIS_BREAD,
            liquidityPools: _liquidityPools,
            scalingFactors: _scalingFactors,
            name: "ButteredBread",
            symbol: "BB"
        });

        bytes memory implementationData = abi.encodeWithSelector(ButteredBread.initialize.selector, initData);

        address bbImplementation = address(new ButteredBread());
        bb = ButteredBread(
            address(new TransparentUpgradeableProxy(bbImplementation, address(this), implementationData))
        );

        vm.label(address(bb), "ButteredBread");
        vm.label(GNOSIS_CURVE_POOL_XDAI_BREAD, "CurveLP_XDAI_BREAD");
    }

    function _helperAddLiquidity(address _account, uint256 _amountBread, uint256 _amountXdai) internal {
        deal(GNOSIS_BREAD, _account, _amountBread);
        deal(GNOSIS_XDAI, _account, _amountXdai);

        uint256[] memory liquidityAmounts = new uint256[](2);
        liquidityAmounts[0] = _amountBread;
        liquidityAmounts[1] = _amountXdai;

        vm.startPrank(_account);
        IERC20(GNOSIS_XDAI).approve(GNOSIS_CURVE_POOL_XDAI_BREAD, type(uint256).max);
        IERC20(GNOSIS_BREAD).approve(GNOSIS_CURVE_POOL_XDAI_BREAD, type(uint256).max);
        curvePoolXdai.add_liquidity(liquidityAmounts, 1);
        curvePoolXdai.approve(address(bb), type(uint256).max);
        vm.stopPrank();
    }

    function _helperDeposit(address _account) internal {
        uint256 lpBalance = IERC20(address(curvePoolXdai)).balanceOf(_account);
        vm.startPrank(_account);
        bb.deposit(address(curvePoolXdai), lpBalance);
        vm.stopPrank();
    }

    /// @notice Test that getPastBalanceOf returns correct historical balances after deposit
    function test_getPastBalanceOf_afterDeposit() public {
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);

        uint256 blockBeforeDeposit = block.number;
        vm.roll(block.number + 1);

        _helperDeposit(ALICE);

        uint256 blockAfterDeposit = block.number;
        vm.roll(block.number + 1);

        // Before deposit: balance should be 0
        uint256 pastBalanceBefore = bb.getPastBalanceOf(ALICE, blockBeforeDeposit);
        assertEq(pastBalanceBefore, 0, "Balance before deposit should be 0");

        // After deposit: balance should be > 0
        uint256 pastBalanceAfter = bb.getPastBalanceOf(ALICE, blockAfterDeposit);
        assertGt(pastBalanceAfter, 0, "Balance after deposit should be > 0");

        // Balance should match the actual token balance at that point
        uint256 expectedBalance = bb.balanceOf(ALICE);
        assertEq(pastBalanceAfter, expectedBalance, "Past balance should match current balance");
    }

    /// @notice Test that getPastDelegate returns correct historical delegation
    function test_getPastDelegate_afterDelegation() public {
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);

        // Set up BREAD delegation for ALICE to BOBBY (ButteredBread syncs from BREAD)
        vm.prank(ALICE);
        IERC20Votes(GNOSIS_BREAD).delegate(BOBBY);

        uint256 blockBeforeDeposit = block.number;
        vm.roll(block.number + 1);

        // Deposit triggers _syncDelegation which calls _delegate
        _helperDeposit(ALICE);

        uint256 blockAfterDeposit = block.number;
        vm.roll(block.number + 1);

        // After deposit: delegate should be BOBBY (synced from BREAD)
        address pastDelegate = bb.getPastDelegate(ALICE, blockAfterDeposit);
        assertEq(pastDelegate, BOBBY, "Past delegate should be BOBBY after deposit sync");
    }

    /// @notice Test that getPastDelegate tracks delegation changes over time
    function test_getPastDelegate_tracksDelegationChanges() public {
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);

        // Initial deposit — ALICE has no BREAD delegation, so self-delegates
        _helperDeposit(ALICE);
        uint256 blockSelfDelegated = block.number;
        vm.roll(block.number + 1);

        // Now change BREAD delegation to BOBBY
        vm.prank(ALICE);
        IERC20Votes(GNOSIS_BREAD).delegate(BOBBY);

        // Trigger sync
        vm.prank(ALICE);
        bb.syncDelegation();
        uint256 blockDelegatedBob = block.number;
        vm.roll(block.number + 1);

        // Check historical delegates
        address delegateAtSelf = bb.getPastDelegate(ALICE, blockSelfDelegated);
        address delegateAtBob = bb.getPastDelegate(ALICE, blockDelegatedBob);

        assertEq(delegateAtSelf, ALICE, "Should be self-delegated initially");
        assertEq(delegateAtBob, BOBBY, "Should be delegated to BOBBY after sync");
    }

    /// @notice Test that getPastBalanceOf tracks balance changes from withdraw
    function test_getPastBalanceOf_afterWithdraw() public {
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);
        _helperDeposit(ALICE);

        uint256 balanceAfterDeposit = bb.balanceOf(ALICE);
        uint256 blockAfterDeposit = block.number;
        vm.roll(block.number + 1);

        // Withdraw half of the LP tokens
        uint256 lpBalance = IERC20(address(curvePoolXdai)).balanceOf(address(bb));
        // Get Alice's LP balance tracked by ButteredBread
        uint256 aliceLpBalance = bb.accountToLPBalance(ALICE, address(curvePoolXdai));
        uint256 withdrawAmount = aliceLpBalance / 2;

        vm.prank(ALICE);
        bb.withdraw(address(curvePoolXdai), withdrawAmount);
        uint256 blockAfterWithdraw = block.number;
        vm.roll(block.number + 1);

        // Historical balance after deposit should be full
        uint256 pastBalanceDeposit = bb.getPastBalanceOf(ALICE, blockAfterDeposit);
        assertEq(pastBalanceDeposit, balanceAfterDeposit, "Past balance should match full deposit");

        // Historical balance after withdraw should be reduced
        uint256 pastBalanceWithdraw = bb.getPastBalanceOf(ALICE, blockAfterWithdraw);
        assertLt(pastBalanceWithdraw, balanceAfterDeposit, "Past balance should be less after withdraw");
        assertEq(pastBalanceWithdraw, bb.balanceOf(ALICE), "Past balance should match current balance");
    }

    /// @notice Test getPastBalanceOf with multiple users
    function test_getPastBalanceOf_multipleUsers() public {
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);
        _helperAddLiquidity(BOBBY, TOKEN_AMOUNT * 2, TOKEN_AMOUNT * 2);

        _helperDeposit(ALICE);
        uint256 aliceBlock = block.number;
        vm.roll(block.number + 1);

        _helperDeposit(BOBBY);
        uint256 bobBlock = block.number;
        vm.roll(block.number + 1);

        uint256 alicePastBalance = bb.getPastBalanceOf(ALICE, bobBlock);
        uint256 bobPastBalance = bb.getPastBalanceOf(BOBBY, bobBlock);

        assertGt(alicePastBalance, 0, "Alice should have balance");
        assertGt(bobPastBalance, 0, "Bob should have balance");
        // Bob deposited ~2x as many tokens, so should have roughly 2x balance
        assertGt(bobPastBalance, alicePastBalance, "Bob should have more balance than Alice");
    }

    /// @notice Test that getPastDelegate reverts for future timepoints
    function test_getPastDelegate_revertsFutureTimepoint() public {
        vm.expectRevert();
        bb.getPastDelegate(ALICE, block.number + 100);
    }

    /// @notice Test that getPastBalanceOf reverts for future timepoints
    function test_getPastBalanceOf_revertsFutureTimepoint() public {
        vm.expectRevert();
        bb.getPastBalanceOf(ALICE, block.number + 100);
    }
}
