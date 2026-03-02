// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {INFTMultiplier} from "src/interfaces/multipliers/INFTMultiplier.sol";

/// @title NFT Multiplier
/// @notice Implementation of INFTMultiplier interface
/// @dev Provides multiplying factors based on NFT ownership
contract NFTMultiplier is INFTMultiplier, Initializable, Ownable2StepUpgradeable {
    IERC721 public nftContract;
    uint256 public multiplyingFactor;
    uint256 public validUntilBlock;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer function to set the NFT contract address and initial multiplying factor
    /// @param _nftContract Address of the NFT contract
    /// @param _initialMultiplyingFactor Initial multiplying factor
    /// @param _validUntilBlock Block number until which the multiplier is valid
    function initialize(IERC721 _nftContract, uint256 _initialMultiplyingFactor, uint256 _validUntilBlock)
        public
        initializer
    {
        __Ownable_init(msg.sender);

        nftContract = _nftContract;
        multiplyingFactor = _initialMultiplyingFactor;
        validUntilBlock = _validUntilBlock;
    }

    /// @notice Get the address of the NFT contract
    /// @return The address of the NFT contract used for checking ownership
    function NFT_ADDRESS() external view override returns (IERC721) {
        return nftContract;
    }

    /// @notice Check if a _user owns an NFT
    /// @param _user The address of the _user to check
    /// @return True if the _user owns at least one NFT, false otherwise
    function hasNFT(address _user) public view override returns (bool) {
        return nftContract.balanceOf(_user) > 0;
    }

    /// @notice Get the multiplying factor for a given _user
    /// @param _user The address of the _user
    /// @return The multiplying factor if the _user owns an NFT, 0 otherwise
    function getMultiplyingFactor(address _user) external view override returns (uint256) {
        return hasNFT(_user) ? multiplyingFactor : 0;
    }

    /// @notice Get the block number until which the multiplier is valid
    /// @return The block number until which the multiplier is valid
    function validUntil(
        address /* _user */
    )
        external
        view
        override
        returns (uint256)
    {
        return validUntilBlock;
    }

    /// @notice Updates the multiplying factor for a specific user
    function updateMultiplyingFactor(
        address /* _user */
    )
        external
        pure
    {
        return;
    }

    /// @notice Update the valid until block
    /// @param _newValidUntilBlock New block number until which the multiplier is valid
    function updateValidUntilBlock(uint256 _newValidUntilBlock) external onlyOwner {
        validUntilBlock = _newValidUntilBlock;
    }

    /// @notice Update the NFT contract address
    /// @param _newNFTContract New NFT contract address
    function updateNFTContract(IERC721 _newNFTContract) external onlyOwner {
        nftContract = _newNFTContract;
    }
}
