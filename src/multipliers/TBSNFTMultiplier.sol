// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {MultiplierConstants} from "src/libraries/MultiplierConstants.sol";

/// @title TBS NFT Multiplier
/// @notice Grants a voting power boost to holders of The Bread Social (TBS) NFT.
/// @dev Ownership of at least one TBS NFT token is sufficient to qualify.
///      The TBS NFT contract address and multiplying factor are set at initialization
///      and can be updated by the owner.
contract TBSNFTMultiplier is Initializable, Ownable2StepUpgradeable, IMultiplier {
    /// @custom:storage-location erc7201:breadchain.TBSNFTMultiplier.storage
    struct TBSNFTMultiplierStorage {
        /// @notice The TBS NFT ERC-721 contract
        IERC721 tbsNFTContract;
        /// @notice Multiplying factor granted to TBS NFT holders (fixed-point, 1e18 = 1x)
        uint256 multiplyingFactor;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.TBSNFTMultiplier.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TBS_NFT_MULTIPLIER_STORAGE_LOCATION =
        0xaaf0cd467fca9524f0c356b2599e71096909e716f05151099dc61df46f997d00;

    function _getTBSNFTMultiplierStorage() private pure returns (TBSNFTMultiplierStorage storage $) {
        assembly {
            $.slot := TBS_NFT_MULTIPLIER_STORAGE_LOCATION
        }
    }

    /// @notice Error emitted when an invalid multiplying factor is provided
    error InvalidMultiplyingFactor();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _tbsNFTContract Address of the TBS NFT ERC-721 contract
    /// @param _multiplyingFactor Boost factor for TBS holders (>= BASE_MULTIPLIER)
    function initialize(IERC721 _tbsNFTContract, uint256 _multiplyingFactor) public initializer {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();

        __Ownable2Step_init();
        _transferOwnership(msg.sender);

        TBSNFTMultiplierStorage storage $ = _getTBSNFTMultiplierStorage();
        $.tbsNFTContract = _tbsNFTContract;
        $.multiplyingFactor = _multiplyingFactor;
    }

    /// @notice Returns the multiplying factor if the user holds at least one TBS NFT
    /// @param _user The address of the user
    /// @return The multiplyingFactor if the user owns a TBS NFT, 0 otherwise
    function getMultiplyingFactor(address _user) external view override returns (uint256) {
        TBSNFTMultiplierStorage storage $ = _getTBSNFTMultiplierStorage();
        return $.tbsNFTContract.balanceOf(_user) > 0 ? $.multiplyingFactor : 0;
    }

    /// @notice The TBS multiplier is permanent; returns type(uint256).max
    function validUntil(address /* _user */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice No per-user state to update; computed fresh each call.
    function updateMultiplyingFactor(address /* _user */ ) external pure override {
        return;
    }

    // ───────────────────────── Admin ─────────────────────────

    /// @notice Update the TBS NFT contract address
    /// @param _tbsNFTContract New TBS NFT contract address
    function setTBSNFTContract(IERC721 _tbsNFTContract) external onlyOwner {
        _getTBSNFTMultiplierStorage().tbsNFTContract = _tbsNFTContract;
    }

    /// @notice Update the multiplying factor
    /// @param _multiplyingFactor New factor (must be >= BASE_MULTIPLIER)
    function setMultiplyingFactor(uint256 _multiplyingFactor) external onlyOwner {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        _getTBSNFTMultiplierStorage().multiplyingFactor = _multiplyingFactor;
    }

    // ───────────────────────── Public getters ─────────────────────────

    /// @notice The TBS NFT ERC-721 contract
    function tbsNFTContract() external view returns (IERC721) {
        return _getTBSNFTMultiplierStorage().tbsNFTContract;
    }

    /// @notice Multiplying factor granted to TBS NFT holders
    function multiplyingFactor() external view returns (uint256) {
        return _getTBSNFTMultiplierStorage().multiplyingFactor;
    }
}
