// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 that deducts a percentage fee on every transfer (fee is burned)
contract FeeOnTransferERC20 is ERC20 {
    uint256 public feePercent;

    constructor(uint256 _feePercent) ERC20("FeeOnTransfer", "FOT") {
        feePercent = _feePercent;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value * feePercent / 100;
            // Transfer (value - fee) to recipient, then burn the fee from sender
            super._update(from, to, value - fee);
            super._update(from, address(0), fee);
        } else {
            super._update(from, to, value);
        }
    }
}
