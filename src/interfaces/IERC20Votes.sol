// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IERC20Votes is IERC20 {
    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) external view returns (address);
}
