// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";

/// @title NFT Multiplier Interface
/// @notice Interface for contracts that provide multiplying factors based on NFT ownership
/// @dev Extends the IMultiplier interface with NFT-specific functionality
interface INFTMultiplier is IMultiplier {
    /// @notice Get the address of the NFT contract
    /// @return The address of the NFT contract used for checking ownership
    function NFT_ADDRESS() external view returns (IERC721);

    /// @notice Check if a _user owns an NFT
    /// @param _user The address of the _user to check
    /// @return True if the _user owns at least one NFT, false otherwise
    function hasNFT(address _user) external view returns (bool);
}
