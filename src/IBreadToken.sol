// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Checkpoints} from "openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";

interface IBreadToken is IERC20 {
    function claimYield(uint256 amount, address receiver) external;
    function yieldAccrued() external view returns (uint256);
    function numCheckpoints(address account) external view returns (uint32);
    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory);
}
