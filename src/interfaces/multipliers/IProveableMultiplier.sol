// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IDynamicNFTMultiplier} from "src/interfaces/multipliers/IDynamicNFTMultiplier.sol";
/// @title Proveable Multiplier Interface
/// @notice Interface for contracts that provide a proveable multiplying factor based on _user activities
interface IProveableMultiplier is IERC721, IDynamicNFTMultiplier {
    /// @notice Submit activities to potentially earn or upgrade an NFT
    /// @param data Encoded data representing the activities
    function submitActivities(bytes calldata data) external;
}
