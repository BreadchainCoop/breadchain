// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {MultiplierConstants} from "src/libraries/MultiplierConstants.sol";

/// @title Never Burned Bread Multiplier
/// @notice Grants a voting power boost to BREAD holders who have never burned BREAD tokens.
///
/// @dev Burning BREAD emits a Transfer event from the holder to address(0). Because Solidity
///      cannot scan past events on-chain, eligibility is maintained off-chain by a trusted
///      verifier (the `oracle` address) that monitors the BREAD contract for Burned events and
///      revokes eligibility by calling `recordBurn(user)`.
///      New users are considered eligible by default (no burn ≡ eligible). Once revoked,
///      eligibility cannot be restored — the burn record is permanent.
///
/// Oracle trust model
/// -------------------
/// @custom:security-note This contract relies on a single trusted oracle address to record
/// whether a user has burned BREAD. This introduces a centralisation risk:
///
/// - SINGLE POINT OF FAILURE: If the oracle key is compromised, an attacker can permanently
///   revoke the multiplier for arbitrary users (denial-of-service), or if the oracle is
///   negligent it may fail to record burns (false positives — users retain the multiplier
///   after burning).
///
/// - NO ON-CHAIN VERIFICATION: The oracle's attestations cannot be independently verified
///   on-chain. The contract trusts whatever the oracle reports.
///
/// - MITIGATION: In production the oracle address should be a Gnosis Safe multisig (or an
///   equivalent M-of-N threshold scheme) rather than an externally owned account (EOA).
///   This distributes the trust and prevents a single key compromise from affecting users.
///   The contract owner retains the ability to call `recordBurn` and `recordBurns` directly
///   as a fallback, and can rotate the oracle via `setOracle` if the current one is compromised.
contract NeverBurnedBreadMultiplier is Initializable, OwnableUpgradeable, IMultiplier {
    /// @custom:storage-location erc7201:breadchain.NeverBurnedBreadMultiplier.storage
    struct NeverBurnedBreadMultiplierStorage {
        /// @notice Multiplying factor for users who have never burned BREAD (fixed-point, 1e18 = 1x)
        uint256 multiplyingFactor;
        /// @notice The trusted off-chain verifier that can revoke eligibility
        address oracle;
        /// @notice Tracks users whose eligibility has been explicitly revoked (burned BREAD)
        /// @dev Absence from this mapping means the user has never burned (eligible).
        mapping(address => bool) hasBurned;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.NeverBurnedBreadMultiplier.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NEVER_BURNED_BREAD_MULTIPLIER_STORAGE_LOCATION =
        0xc351da930d721e83a504690036fa250f9bd0d16b0ba735ba19fd902d1d497c00;

    function _getNeverBurnedBreadMultiplierStorage()
        private
        pure
        returns (NeverBurnedBreadMultiplierStorage storage $)
    {
        assembly {
            $.slot := NEVER_BURNED_BREAD_MULTIPLIER_STORAGE_LOCATION
        }
    }

    /// @notice Error emitted when an unauthorized address tries to revoke eligibility
    error OnlyOracle();
    /// @notice Error emitted when an invalid multiplying factor is provided
    error InvalidMultiplyingFactor();
    /// @notice Error emitted when a zero oracle address is provided
    error ZeroOracleAddress();

    /// @notice Emitted when a user's burn status is recorded
    event BurnStatusRecorded(address indexed user, bool burned);
    /// @notice Emitted when the oracle address changes
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _multiplyingFactor Boost factor for never-burned users (>= BASE_MULTIPLIER)
    /// @param _oracle Address of the trusted off-chain oracle that records burns
    function initialize(uint256 _multiplyingFactor, address _oracle) public initializer {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        if (_oracle == address(0)) revert ZeroOracleAddress();

        __Ownable_init(msg.sender);

        NeverBurnedBreadMultiplierStorage storage $ = _getNeverBurnedBreadMultiplierStorage();
        $.multiplyingFactor = _multiplyingFactor;
        $.oracle = _oracle;
    }

    /// @notice Returns the multiplying factor if the user has never burned BREAD
    /// @param _user The address of the user
    /// @return The multiplyingFactor if not burned, 0 otherwise
    function getMultiplyingFactor(address _user) external view override returns (uint256) {
        NeverBurnedBreadMultiplierStorage storage $ = _getNeverBurnedBreadMultiplierStorage();
        return $.hasBurned[_user] ? 0 : $.multiplyingFactor;
    }

    /// @notice The multiplier is permanent once granted; validity is tracked via hasBurned.
    function validUntil(address /* _user */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice No op — eligibility is managed by the oracle, not lazily updated on-chain.
    function updateMultiplyingFactor(address /* _user */ ) external pure override {
        return;
    }

    // ───────────────────────── Oracle ─────────────────────────

    /// @notice Record that a user has burned BREAD (revokes their multiplier permanently)
    /// @dev Called by the off-chain oracle when a Burned event is detected on the BREAD contract.
    ///      The owner may also call this directly for manual corrections.
    /// @param _user The address of the user who burned BREAD
    function recordBurn(address _user) external {
        NeverBurnedBreadMultiplierStorage storage $ = _getNeverBurnedBreadMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        if (!$.hasBurned[_user]) {
            $.hasBurned[_user] = true;
            emit BurnStatusRecorded(_user, true);
        }
    }

    /// @notice Batch-record burns for multiple users
    /// @param _users Array of user addresses who have burned BREAD
    function recordBurns(address[] calldata _users) external {
        NeverBurnedBreadMultiplierStorage storage $ = _getNeverBurnedBreadMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        for (uint256 i = 0; i < _users.length; i++) {
            if (!$.hasBurned[_users[i]]) {
                $.hasBurned[_users[i]] = true;
                emit BurnStatusRecorded(_users[i], true);
            }
        }
    }

    // ───────────────────────── Admin ─────────────────────────

    /// @notice Update the oracle address
    /// @param _oracle New oracle address (must be non-zero)
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert ZeroOracleAddress();
        NeverBurnedBreadMultiplierStorage storage $ = _getNeverBurnedBreadMultiplierStorage();
        emit OracleUpdated($.oracle, _oracle);
        $.oracle = _oracle;
    }

    /// @notice Update the multiplying factor applied to users who have never burned BREAD
    /// @param _multiplyingFactor New multiplier (must be >= BASE_MULTIPLIER, i.e. 1e18)
    function setMultiplyingFactor(uint256 _multiplyingFactor) external onlyOwner {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        _getNeverBurnedBreadMultiplierStorage().multiplyingFactor = _multiplyingFactor;
    }

    // ───────────────────────── Public getters ─────────────────────────

    /// @notice Multiplying factor for users who have never burned BREAD
    function multiplyingFactor() external view returns (uint256) {
        return _getNeverBurnedBreadMultiplierStorage().multiplyingFactor;
    }

    /// @notice The trusted off-chain verifier that can revoke eligibility
    function oracle() external view returns (address) {
        return _getNeverBurnedBreadMultiplierStorage().oracle;
    }

    /// @notice Tracks users whose eligibility has been explicitly revoked (burned BREAD)
    function hasBurned(address user) external view returns (bool) {
        return _getNeverBurnedBreadMultiplierStorage().hasBurned[user];
    }
}
