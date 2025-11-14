// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {IBread as IBreadSource} from "bread-token/src/interfaces/IBread.sol";

import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";

interface IBread is IBreadSource, IERC20Votes {}
