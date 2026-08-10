// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "script/Constants.s.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ButteredBread} from "src/ButteredBread.sol";

/// @dev Live `ButteredBread` proxy on Gnosis
address constant GNOSIS_BUTTERED_BREAD = 0x680B581605DC0A6902735a80dE35Cb0Ef6E90865;
/// @dev `ProxyAdmin` owning the live proxy
address constant GNOSIS_BUTTERED_BREAD_PROXY_ADMIN = 0x671180547cD5AAaedEf2B087d3d7Ed9166AfceB6;

/// @dev Block at which the accounts below were unable to withdraw their full LP balance
uint256 constant FORK_BLOCK = 47_651_977;

interface IProxyAdmin {
    function owner() external view returns (address);
    function upgradeAndCall(address proxy, address implementation, bytes memory data) external payable;
}

/**
 * @notice Verifies the deployed proxy against accounts that could not withdraw
 * @dev Deposits made before this fix hold slightly less `ButteredBread` than their aggregate entitlement, so the
 *  burn in `_withdraw` exceeded their balance and a full withdrawal reverted. Upgrading must let each of them exit
 *  in a single call. See BreadchainCoop/crowdstaking-v2#408
 */
contract ButteredBreadUpgradeTest is Test {
    ButteredBread public bb;
    IERC20 public lp;

    /// @dev Accounts holding a position that could not be fully withdrawn at `FORK_BLOCK`
    address[3] public affectedAccounts = [
        0x37cc13650d0D2A73E181cbF48A1847AE5f0531b5,
        0x18A725aD96aE6a8b6e8DbE3FB3a8eb042e2F8879,
        0xcF26fE037743F56daB8f9CA509E9FB7f59071BF1
    ];

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("gnosis"), FORK_BLOCK);
        bb = ButteredBread(GNOSIS_BUTTERED_BREAD);
        lp = IERC20(GNOSIS_CURVE_POOL_XDAI_BREAD);
    }

    function _upgradeToFixedImplementation() internal {
        IProxyAdmin proxyAdmin = IProxyAdmin(GNOSIS_BUTTERED_BREAD_PROXY_ADMIN);
        address newImplementation = address(new ButteredBread());

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgradeAndCall(GNOSIS_BUTTERED_BREAD, newImplementation, "");
    }

    /// @dev Confirms the reverting state is real before the upgrade is applied
    function testFullWithdrawRevertsBeforeUpgrade() public {
        for (uint256 i; i < affectedAccounts.length; ++i) {
            address account = affectedAccounts[i];
            uint256 stakedBalance = bb.accountToLPBalance(account, GNOSIS_CURVE_POOL_XDAI_BREAD);
            assertGt(stakedBalance, 0);

            vm.prank(account);
            vm.expectRevert();
            bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, stakedBalance);
        }
    }

    /// @dev Each affected account must recover its entire staked balance in a single call after the upgrade
    function testFullWithdrawSucceedsAfterUpgrade() public {
        _upgradeToFixedImplementation();

        for (uint256 i; i < affectedAccounts.length; ++i) {
            address account = affectedAccounts[i];
            uint256 stakedBalance = bb.accountToLPBalance(account, GNOSIS_CURVE_POOL_XDAI_BREAD);
            uint256 walletBalanceBefore = lp.balanceOf(account);

            vm.prank(account);
            bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, stakedBalance);

            assertEq(lp.balanceOf(account), walletBalanceBefore + stakedBalance);
            assertEq(bb.accountToLPBalance(account, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
            assertEq(bb.balanceOf(account), 0);
        }
    }

    /// @dev The upgrade adds no storage, so existing positions and voting weight must be untouched
    function testUpgradePreservesExistingState() public {
        uint256 totalSupplyBefore = bb.totalSupply();
        uint256 contractLpBefore = lp.balanceOf(GNOSIS_BUTTERED_BREAD);
        uint256 scalingFactorBefore = bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD);

        uint256[3] memory stakedBefore;
        uint256[3] memory holdingBefore;
        for (uint256 i; i < affectedAccounts.length; ++i) {
            stakedBefore[i] = bb.accountToLPBalance(affectedAccounts[i], GNOSIS_CURVE_POOL_XDAI_BREAD);
            holdingBefore[i] = bb.balanceOf(affectedAccounts[i]);
        }

        _upgradeToFixedImplementation();

        assertEq(bb.totalSupply(), totalSupplyBefore);
        assertEq(lp.balanceOf(GNOSIS_BUTTERED_BREAD), contractLpBefore);
        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), scalingFactorBefore);
        assertTrue(bb.allowlistedLPs(GNOSIS_CURVE_POOL_XDAI_BREAD));

        for (uint256 i; i < affectedAccounts.length; ++i) {
            assertEq(bb.accountToLPBalance(affectedAccounts[i], GNOSIS_CURVE_POOL_XDAI_BREAD), stakedBefore[i]);
            assertEq(bb.balanceOf(affectedAccounts[i]), holdingBefore[i]);
        }
    }

    /// @dev A deposit and withdrawal cycle on the upgraded proxy must leave no residual holding
    function testDepositAndFullWithdrawAfterUpgrade() public {
        _upgradeToFixedImplementation();

        address account = affectedAccounts[0];
        uint256 stakedBalance = bb.accountToLPBalance(account, GNOSIS_CURVE_POOL_XDAI_BREAD);

        vm.startPrank(account);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, stakedBalance);

        /// @dev redeposit the recovered balance in two parts, the pattern that produced the shortfall
        lp.approve(GNOSIS_BUTTERED_BREAD, type(uint256).max);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, stakedBalance / 3);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, stakedBalance - (stakedBalance / 3));

        uint256 restakedBalance = bb.accountToLPBalance(account, GNOSIS_CURVE_POOL_XDAI_BREAD);
        assertEq(restakedBalance, stakedBalance);

        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, restakedBalance);
        vm.stopPrank();

        assertEq(bb.accountToLPBalance(account, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(bb.balanceOf(account), 0);
        assertEq(lp.balanceOf(account), stakedBalance);
    }
}
