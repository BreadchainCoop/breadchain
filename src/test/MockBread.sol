// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20VotesIBreadAdapter} from "src/test/ERC20VotesIBreadAdapter.sol";

/// @title MockBread
/// @notice Dummy Bread token for testing with public mint/burn and configurable yield.
/// @dev Structurally compatible with IBread. Use in tests that need a Bread-like token without
///      WXDAI/sDAI dependencies. Supports arbitrary minting (payable or approval-based), burning,
///      and simulating yield via setYieldAccrued + claimYield.
contract MockBread is ERC20VotesIBreadAdapter, Ownable2Step {
    /// @dev Thrown when claimYield is called by an address that is neither owner nor yieldClaimer.
    error OnlyClaimers();

    /// @notice Address authorized to call claimYield (e.g. YieldDistributor).
    address public yieldClaimer;

    /// @dev Simulated accrued yield for claimYield. Set via setYieldAccrued for testing.
    uint256 private _yieldAccrued;

    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    constructor(string memory name_, string memory symbol_)
        ERC20VotesIBreadAdapter(name_, symbol_)
        Ownable(msg.sender)
    {}

    /// @notice Sets the address authorized to call claimYield.
    /// @param _yieldClaimer New yield claimer address.
    function setYieldClaimer(address _yieldClaimer) external onlyOwner {
        yieldClaimer = _yieldClaimer;
    }

    /// @notice Sets the simulated accrued yield for testing claimYield.
    /// @param amount Amount of yield to report as accrued.
    function setYieldAccrued(uint256 amount) external onlyOwner {
        _yieldAccrued = amount;
    }

    /// @notice Returns the current simulated accrued yield.
    /// @return Amount of yield available to claim.
    function yieldAccrued() external view returns (uint256) {
        return _yieldAccrued;
    }

    /// @notice Mints yield to `receiver`. Callable by owner or yieldClaimer.
    /// @param amount Amount of yield to mint.
    /// @param receiver Address to receive the minted tokens.
    function claimYield(uint256 amount, address receiver) external {
        if (msg.sender != owner() && msg.sender != yieldClaimer) revert OnlyClaimers();
        if (amount == 0) return;
        if (amount >= _yieldAccrued) {
            _yieldAccrued = 0;
        } else {
            _yieldAccrued -= amount;
        }
        _mintWithDelegate(receiver, amount);
    }

    /// @notice Mints tokens to `receiver` using sent ETH.
    /// @param receiver Address to receive the minted tokens.
    function mint(address receiver) external payable {
        _mintWithDelegate(receiver, msg.value);
    }

    /// @notice Mints tokens to `receiver` (transfers from msg.sender approval).
    /// @param receiver Address to receive the minted tokens.
    /// @param amount Amount to mint.
    function mint(address receiver, uint256 amount) external {
        _mintWithDelegate(receiver, amount);
    }

    /// @notice Burns tokens from msg.sender.
    /// @param amount Amount to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burns tokens from msg.sender. Compatible with IBread signature (receiver unused in mock).
    /// @param amount Amount to burn.
    /// @param receiver Unused; present for interface compatibility with real Bread burn.
    function burn(uint256 amount, address receiver) external {
        _burn(receiver, amount);
    }

    /// @notice Transfers tokens and auto-delegates recipient to self if not already delegated.
    /// @param recipient Address to receive tokens.
    /// @param amount Amount to transfer.
    /// @return True if successful.
    function transfer(address recipient, uint256 amount) public override(ERC20VotesIBreadAdapter) returns (bool) {
        super.transfer(recipient, amount);
        _autoDelegate(recipient);
        return true;
    }

    /// @notice Transfers tokens from `from` to `to` and auto-delegates `to` to self if not already delegated.
    /// @param from Address to transfer from.
    /// @param to Address to transfer to.
    /// @param value Amount to transfer.
    /// @return True if successful.
    function transferFrom(address from, address to, uint256 value)
        public
        override(ERC20VotesIBreadAdapter)
        returns (bool)
    {
        super.transferFrom(from, to, value);
        _autoDelegate(to);
        return true;
    }

    /// @dev Mints tokens to `receiver` and auto-delegates to self if not already delegated.
    /// @param receiver Address to receive minted tokens.
    /// @param amount Amount to mint.
    function _mintWithDelegate(address receiver, uint256 amount) internal {
        if (amount == 0) return;
        _mint(receiver, amount);
        _autoDelegate(receiver);
    }

    /// @dev Delegates `account` to itself if it has no delegate set.
    /// @param account Address to auto-delegate.
    function _autoDelegate(address account) internal {
        if (delegates(account) == address(0)) _delegate(account, account);
    }
}
