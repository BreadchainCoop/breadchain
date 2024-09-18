// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ICurveStableSwap is IERC20 {
    /**
     * @dev Returns the name of the token
     */
    function name() external returns (string memory);

    /**
     * @dev Returns the symbol of the token
     */
    function symbol() external returns (string memory);

    /**
     * @dev Add liquidity to a Curve pool
     */
    function add_liquidity(uint256[] memory _amounts, uint256 _min_mint_amount) external returns (uint256);
}
