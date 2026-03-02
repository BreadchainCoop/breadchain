// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title MockBread
/// @notice Dummy Bread token for testing with public mint/burn
contract MockBread is ERC20Votes, Ownable2Step {
    error OnlyClaimers();

    address public yieldClaimer;
    uint256 private _yieldAccrued;

    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        EIP712(name_, "1")
        Ownable(msg.sender)
    {}

    function setYieldClaimer(address _yieldClaimer) external onlyOwner {
        yieldClaimer = _yieldClaimer;
    }

    function setYieldAccrued(uint256 amount) external onlyOwner {
        _yieldAccrued = amount;
    }

    function yieldAccrued() external view returns (uint256) {
        return _yieldAccrued;
    }

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

    function mint(address receiver) external payable {
        _mintWithDelegate(receiver, msg.value);
    }

    function mint(address receiver, uint256 amount) external {
        _mintWithDelegate(receiver, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burn(uint256 amount, address /* receiver */ ) external {
        _burn(msg.sender, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        super.transfer(recipient, amount);
        _autoDelegate(recipient);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        super.transferFrom(from, to, value);
        _autoDelegate(to);
        return true;
    }

    function _mintWithDelegate(address receiver, uint256 amount) internal {
        if (amount == 0) return;
        _mint(receiver, amount);
        _autoDelegate(receiver);
    }

    function _autoDelegate(address account) internal {
        if (delegates(account) == address(0)) _delegate(account, account);
    }
}
