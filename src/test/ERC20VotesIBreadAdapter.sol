// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IBread} from "src/interfaces/IBread.sol";
import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";

/// @title ERC20VotesIBreadAdapter
/// @notice Abstract adapter that resolves ERC20Votes + IBread (IERC20Votes) inheritance conflicts.
/// @dev IBread extends IERC20Votes, and ERC20Votes provides implementations of the same functions.
///      Solidity requires explicit override resolution when the same function is defined in multiple ancestors.
///      Extend this contract when implementing IBread with ERC20Votes to isolate that boilerplate.
///      Concrete contracts (e.g. MockBread) can then focus on their specific logic.
abstract contract ERC20VotesIBreadAdapter is ERC20Votes, IBread {
    /// @param name_ Token name (used for ERC20 and EIP712 domain).
    /// @param symbol_ Token symbol.
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) EIP712(name_, "1") {}

    /// @notice Returns the current clock value (block number).
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function clock() public view override(Votes, IERC20Votes) returns (uint48) {
        return super.clock();
    }

    /// @notice Returns the delegate chosen by `account`.
    /// @param account Address to query.
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function delegates(address account) public view override(Votes, IERC20Votes) returns (address) {
        return super.delegates(account);
    }

    /// @notice Delegates votes from the sender to `delegatee`.
    /// @param delegatee Address to receive delegated votes.
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function delegate(address delegatee) public override(Votes, IERC20Votes) {
        super.delegate(delegatee);
    }

    /// @notice Delegates votes from signer to `delegatee` via EIP-712 signature.
    /// @param delegatee Address to receive delegated votes.
    /// @param nonce Signer's nonce.
    /// @param expiry Signature expiry timestamp.
    /// @param v Signature v component.
    /// @param r Signature r component.
    /// @param s Signature s component.
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override(Votes, IERC20Votes)
    {
        super.delegateBySig(delegatee, nonce, expiry, v, r, s);
    }

    /// @notice Returns the current amount of votes for `account`.
    /// @param account Address to query.
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function getVotes(address account) public view override(Votes, IERC20Votes) returns (uint256) {
        return super.getVotes(account);
    }

    /// @notice Returns the amount of votes `account` had at a past timepoint.
    /// @param account Address to query.
    /// @param timepoint Block number (or timestamp) in the past.
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function getPastVotes(address account, uint256 timepoint)
        public
        view
        override(Votes, IERC20Votes)
        returns (uint256)
    {
        return super.getPastVotes(account, timepoint);
    }

    /// @notice Returns the total supply of votes at a past timepoint.
    /// @param timepoint Block number (or timestamp) in the past.
    /// @dev Resolves Votes / IERC20Votes override conflict.
    function getPastTotalSupply(uint256 timepoint) public view override(Votes, IERC20Votes) returns (uint256) {
        return super.getPastTotalSupply(timepoint);
    }

    /// @notice Returns the checkpoint at `pos` for `account`.
    /// @param account Address to query.
    /// @param pos Checkpoint index.
    /// @dev Resolves ERC20Votes / IERC20Votes override conflict.
    function checkpoints(address account, uint32 pos)
        public
        view
        override(ERC20Votes, IERC20Votes)
        returns (Checkpoints.Checkpoint208 memory)
    {
        return super.checkpoints(account, pos);
    }

    /// @notice Returns the number of checkpoints for `account`.
    /// @param account Address to query.
    /// @dev Resolves ERC20Votes / IERC20Votes override conflict.
    function numCheckpoints(address account) public view override(ERC20Votes, IERC20Votes) returns (uint32) {
        return super.numCheckpoints(account);
    }

    /// @notice Transfers tokens to `recipient`.
    /// @param recipient Address to receive tokens.
    /// @param amount Amount to transfer.
    /// @return True if successful.
    /// @dev Resolves ERC20 / IERC20 override conflict. Marked virtual for concrete contracts that add auto-delegation.
    function transfer(address recipient, uint256 amount) public virtual override(ERC20, IERC20) returns (bool) {
        return super.transfer(recipient, amount);
    }

    /// @notice Transfers tokens from `from` to `to` using allowance.
    /// @param from Address to transfer from.
    /// @param to Address to transfer to.
    /// @param value Amount to transfer.
    /// @return True if successful.
    /// @dev Resolves ERC20 / IERC20 override conflict. Marked virtual for concrete contracts that add auto-delegation.
    function transferFrom(address from, address to, uint256 value)
        public
        virtual
        override(ERC20, IERC20)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }
}
