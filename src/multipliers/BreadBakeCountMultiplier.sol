// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {MultiplierConstants} from "src/libraries/MultiplierConstants.sol";

/// @title Bread Bake Count Multiplier
/// @notice Grants a voting power boost to BREAD holders who have baked BREAD 10 or more times.
///
/// @dev "Baking" refers to calling the BREAD `mint()` function (depositing xDAI to receive BREAD).
///      Because Solidity cannot count past Minted events on-chain, bake counts are maintained
///      off-chain by a trusted oracle that monitors the BREAD contract and records when an
///      address reaches or exceeds the `BAKE_THRESHOLD`.
///      The oracle calls `grantEligibility(user)` once a user crosses the threshold.
///      Eligibility cannot be revoked once granted.
///
/// Oracle trust model
/// -------------------
/// @custom:security-note This contract relies on a single trusted oracle address to grant
/// eligibility to users who have baked BREAD 10 or more times. This introduces a
/// centralisation risk:
///
/// - SINGLE POINT OF FAILURE: If the oracle key is compromised, an attacker can grant the
///   multiplier to arbitrary addresses, inflating those addresses' voting power. Conversely,
///   a negligent or offline oracle may fail to grant eligibility to users who have genuinely
///   reached the threshold.
///
/// - NO ON-CHAIN VERIFICATION: Bake counts are computed off-chain by scanning Minted events.
///   The contract trusts the oracle's reports without any on-chain proof.
///
/// - MITIGATION: In production the oracle address should be a Gnosis Safe multisig (or an
///   equivalent M-of-N threshold scheme) rather than an externally owned account (EOA).
///   This distributes the trust and prevents a single key compromise from granting spurious
///   eligibility. The contract owner retains the ability to call `grantEligibility` and
///   `grantEligibilityBatch` directly as a fallback, and can rotate the oracle via
///   `setOracle` if the current one is compromised.
contract BreadBakeCountMultiplier is Initializable, OwnableUpgradeable, IMultiplier {
    /// @notice Minimum number of bakes required to earn the multiplier
    uint256 public constant BAKE_THRESHOLD = 10;

    /// @custom:storage-location erc7201:breadchain.BreadBakeCountMultiplier.storage
    struct BreadBakeCountMultiplierStorage {
        /// @notice Multiplying factor for users who have baked 10+ times (fixed-point, 1e18 = 1x)
        uint256 multiplyingFactor;
        /// @notice The trusted off-chain verifier that records bake-count eligibility
        address oracle;
        /// @notice Tracks users who have reached or exceeded the bake threshold
        mapping(address => bool) isEligible;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.BreadBakeCountMultiplier.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BREAD_BAKE_COUNT_MULTIPLIER_STORAGE_LOCATION =
        0x03785cbc7f5634abcf1c8e1fb3ca142488b2f4ec03175d5e34fa9e4032199400;

    function _getBreadBakeCountMultiplierStorage() private pure returns (BreadBakeCountMultiplierStorage storage $) {
        assembly {
            $.slot := BREAD_BAKE_COUNT_MULTIPLIER_STORAGE_LOCATION
        }
    }

    /// @notice Error emitted when an unauthorized address tries to set eligibility
    error OnlyOracle();
    /// @notice Error emitted when an invalid multiplying factor is provided
    error InvalidMultiplyingFactor();
    /// @notice Error emitted when a zero oracle address is provided
    error ZeroOracleAddress();

    /// @notice Emitted when a user becomes eligible (≥10 bakes confirmed)
    event EligibilityGranted(address indexed user);
    /// @notice Emitted when the oracle address changes
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _multiplyingFactor Boost factor for qualifying users (>= BASE_MULTIPLIER)
    /// @param _oracle Address of the trusted off-chain oracle
    function initialize(uint256 _multiplyingFactor, address _oracle) public initializer {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        if (_oracle == address(0)) revert ZeroOracleAddress();

        __Ownable_init(msg.sender);

        BreadBakeCountMultiplierStorage storage $ = _getBreadBakeCountMultiplierStorage();
        $.multiplyingFactor = _multiplyingFactor;
        $.oracle = _oracle;
    }

    /// @notice Returns the multiplying factor if the user has baked 10+ times
    /// @param _user The address of the user
    /// @return The multiplyingFactor if eligible, 0 otherwise
    function getMultiplyingFactor(address _user) external view override returns (uint256) {
        BreadBakeCountMultiplierStorage storage $ = _getBreadBakeCountMultiplierStorage();
        return $.isEligible[_user] ? $.multiplyingFactor : 0;
    }

    /// @notice Once granted, bake-count eligibility never expires.
    function validUntil(address /* _user */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice No op — eligibility is set by the oracle, not computed lazily.
    function updateMultiplyingFactor(address /* _user */ ) external pure override {
        return;
    }

    // ───────────────────────── Oracle ─────────────────────────

    /// @notice Grant the multiplier to a user who has reached 10+ bakes
    /// @dev Called by the oracle when it detects a user's bake count crosses BAKE_THRESHOLD.
    /// @param _user The address to grant eligibility to
    function grantEligibility(address _user) external {
        BreadBakeCountMultiplierStorage storage $ = _getBreadBakeCountMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        if (!$.isEligible[_user]) {
            $.isEligible[_user] = true;
            emit EligibilityGranted(_user);
        }
    }

    /// @notice Batch-grant eligibility to multiple users
    /// @param _users Array of user addresses to grant eligibility to
    function grantEligibilityBatch(address[] calldata _users) external {
        BreadBakeCountMultiplierStorage storage $ = _getBreadBakeCountMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        for (uint256 i = 0; i < _users.length; i++) {
            if (!$.isEligible[_users[i]]) {
                $.isEligible[_users[i]] = true;
                emit EligibilityGranted(_users[i]);
            }
        }
    }

    // ───────────────────────── Admin ─────────────────────────

    /// @notice Update the oracle address
    /// @param _oracle New oracle address (must be non-zero)
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert ZeroOracleAddress();
        BreadBakeCountMultiplierStorage storage $ = _getBreadBakeCountMultiplierStorage();
        emit OracleUpdated($.oracle, _oracle);
        $.oracle = _oracle;
    }

    /// @notice Update the multiplying factor applied to qualifying bakers
    /// @param _multiplyingFactor New multiplier (must be >= BASE_MULTIPLIER, i.e. 1e18)
    function setMultiplyingFactor(uint256 _multiplyingFactor) external onlyOwner {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        _getBreadBakeCountMultiplierStorage().multiplyingFactor = _multiplyingFactor;
    }

    // ───────────────────────── Public getters ─────────────────────────

    /// @notice Multiplying factor for users who have baked 10+ times
    function multiplyingFactor() external view returns (uint256) {
        return _getBreadBakeCountMultiplierStorage().multiplyingFactor;
    }

    /// @notice The trusted off-chain verifier that records bake-count eligibility
    function oracle() external view returns (address) {
        return _getBreadBakeCountMultiplierStorage().oracle;
    }

    /// @notice Tracks users who have reached or exceeded the bake threshold
    function isEligible(address user) external view returns (bool) {
        return _getBreadBakeCountMultiplierStorage().isEligible[user];
    }
}
