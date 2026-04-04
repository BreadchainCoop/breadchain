// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {MultiplierConstants} from "src/libraries/MultiplierConstants.sol";

/// @title POAP Multiplier
/// @notice Grants a voting power boost to users who hold a qualifying POAP
///         (Proof of Attendance Protocol) token from approved events.
///
/// @dev The POAP ERC-721 contract on Gnosis Chain is at 0x22C1f6050E56d2876009903609a2cC3fEf83B415.
///
/// On-chain event-ID enumeration limitation
/// -----------------------------------------
/// The POAP ERC-721 token encodes an event ID per token. The POAP contract exposes a
/// non-standard helper `tokenDetailsOfOwnerByIndex(address owner, uint256 index)`
/// that returns `(uint256 eventId, uint256 tokenId)`. However, calling this in a view
/// function to iterate over all of a user's tokens is unbounded (O(n) per user, where
/// n is the number of tokens held) and is not guaranteed to be available on every
/// deployment or fork of the POAP contract.
///
/// Oracle-assisted event-ID enforcement
/// --------------------------------------
/// When `acceptAnyPoap = false` and qualifying event IDs are configured, pure on-chain
/// enforcement requires iterating token ownership — which is not feasible for arbitrary
/// holders. Therefore this contract follows the same oracle-assisted pattern as
/// BreadBakeCountMultiplier and NeverBurnedBreadMultiplier:
///
/// - A trusted off-chain oracle (or the contract owner) monitors POAP token transfers
///   on-chain, looks up the event ID of each relevant token via `tokenDetailsOfOwnerByIndex`
///   or the Gnosis Chain POAP subgraph, and calls `attestQualifyingHolder` (or the
///   batch variant) to record that an address holds a POAP from a qualifying event.
/// - Attesetd eligibility is stored in `isAttested[user]` and is revocable by the oracle
///   or owner if the user later transfers away their qualifying POAP.
///
/// Trust model and risks
/// ----------------------
/// @custom:security-note The oracle is a single point of trust. If the oracle key is
/// compromised, the attacker can grant the multiplier to arbitrary addresses. For
/// production deployments, the oracle should be a multisig (e.g. a Gnosis Safe) or
/// a decentralised keeper network to reduce this risk. The contract owner can always
/// override the oracle by calling the attest/revoke functions directly.
///
/// Modes of operation
/// -------------------
/// 1. `acceptAnyPoap = true` — Any POAP holder qualifies; no event-ID check, no oracle needed.
/// 2. `acceptAnyPoap = false` with empty `qualifyingEventIds` — No one qualifies; acts as a pause.
/// 3. `acceptAnyPoap = false` with event IDs configured — Only oracle-attested holders qualify.
///    The oracle should monitor qualifying events and call `attestQualifyingHolder`.
contract POAPMultiplier is Initializable, Ownable2StepUpgradeable, IMultiplier {
    /// @custom:storage-location erc7201:breadchain.POAPMultiplier.storage
    struct POAPMultiplierStorage {
        /// @notice The POAP ERC-721 contract
        IERC721 poapContract;
        /// @notice Multiplying factor granted to POAP holders (fixed-point, 1e18 = 1x)
        uint256 multiplyingFactor;
        /// @notice If true, any POAP qualifies (event ID check is skipped).
        ///         Set by the owner to simplify integration before event IDs are known.
        bool acceptAnyPoap;
        /// @notice Allowlisted POAP event IDs whose holders qualify
        /// @dev Iterable list; also mirrored in a mapping for O(1) lookup
        uint256[] qualifyingEventIds;
        /// @notice O(1) lookup: event ID → whether it's approved
        mapping(uint256 => bool) isQualifyingEventId;
        /// @notice The trusted off-chain oracle that attests qualifying POAP holders.
        ///
        /// @dev The oracle monitors POAP token transfers on-chain and checks whether a holder
        ///      owns a token whose event ID appears in `qualifyingEventIds`. When confirmed, the
        ///      oracle calls `attestQualifyingHolder`. The oracle should be a multisig in production.
        ///
        /// @custom:security-note This is a single point of trust. See the contract-level NatSpec
        ///      for a full discussion of the trust model and mitigation recommendations.
        address oracle;
        /// @notice Records addresses that have been attested by the oracle as holding a
        ///         qualifying POAP. Used only when `acceptAnyPoap = false`.
        mapping(address => bool) isAttested;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.POAPMultiplier.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POAP_MULTIPLIER_STORAGE_LOCATION =
        0xb7a828628f9ae0dcaafc87f9e42c18b49ad328afdbfda7bf94e7ef79814d1100;

    function _getPOAPMultiplierStorage() private pure returns (POAPMultiplierStorage storage $) {
        assembly {
            $.slot := POAP_MULTIPLIER_STORAGE_LOCATION
        }
    }

    /// @notice Error emitted when trying to add a duplicate event ID
    error EventIdAlreadyAllowlisted(uint256 eventId);
    /// @notice Error emitted when trying to remove a non-existent event ID
    error EventIdNotAllowlisted(uint256 eventId);
    /// @notice Error emitted when an invalid multiplying factor is provided
    error InvalidMultiplyingFactor();
    /// @notice Error emitted when an unauthorized address tries to attest/revoke
    error OnlyOracle();
    /// @notice Error emitted when a zero oracle address is provided
    error ZeroOracleAddress();

    /// @notice Emitted when a POAP event ID is added to the allowlist
    event EventIdAdded(uint256 indexed eventId);
    /// @notice Emitted when a POAP event ID is removed from the allowlist
    event EventIdRemoved(uint256 indexed eventId);
    /// @notice Emitted when an address is attested as holding a qualifying POAP
    event HolderAttested(address indexed user);
    /// @notice Emitted when an attestation is revoked (user no longer holds a qualifying POAP)
    event AttestationRevoked(address indexed user);
    /// @notice Emitted when the oracle address changes
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _poapContract Address of the POAP ERC-721 contract
    /// @param _multiplyingFactor Boost factor for POAP holders (>= BASE_MULTIPLIER)
    /// @param _acceptAnyPoap If true, any POAP token qualifies regardless of event ID
    /// @param _initialEventIds Initial list of qualifying POAP event IDs
    /// @param _oracle Address of the trusted off-chain oracle (may be address(0) when
    ///        acceptAnyPoap=true, but must be non-zero if event-ID filtering is intended)
    function initialize(
        IERC721 _poapContract,
        uint256 _multiplyingFactor,
        bool _acceptAnyPoap,
        uint256[] calldata _initialEventIds,
        address _oracle
    ) public initializer {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();

        __Ownable2Step_init();
        _transferOwnership(msg.sender);

        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        $.poapContract = _poapContract;
        $.multiplyingFactor = _multiplyingFactor;
        $.acceptAnyPoap = _acceptAnyPoap;
        $.oracle = _oracle;

        for (uint256 i = 0; i < _initialEventIds.length; i++) {
            _addEventId(_initialEventIds[i]);
        }
    }

    /// @notice Returns the multiplying factor if the user holds a qualifying POAP
    ///
    /// Logic:
    ///  - If the user holds no POAP at all → 0
    ///  - If `acceptAnyPoap = true` → multiplyingFactor (any POAP holder qualifies)
    ///  - If `acceptAnyPoap = false` and no event IDs configured → 0 (paused state)
    ///  - If `acceptAnyPoap = false` and event IDs are configured → only oracle-attested
    ///    holders qualify (`isAttested[_user]` must be true)
    ///
    /// @param _user The address of the user
    /// @return The multiplyingFactor if the user holds a qualifying POAP, 0 otherwise
    function getMultiplyingFactor(address _user) external view override returns (uint256) {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();

        // Fast exit: no POAP at all
        if ($.poapContract.balanceOf(_user) == 0) return 0;

        // Mode 1: accept any POAP
        if ($.acceptAnyPoap) return $.multiplyingFactor;

        // Mode 2: paused — no qualifying events configured
        if ($.qualifyingEventIds.length == 0) return 0;

        // Mode 3: event-ID filtered — require oracle attestation.
        // On-chain enumeration of which event a specific POAP token belongs to is not
        // feasible in a general way (the POAP ERC-721 standard does not extend
        // ERC721Enumerable, and the `tokenDetailsOfOwnerByIndex` helper is not available
        // on all deployments). The trusted oracle must attest qualifying holders off-chain.
        return $.isAttested[_user] ? $.multiplyingFactor : 0;
    }

    /// @notice The multiplier is always live; validity is managed per user's POAP holding.
    function validUntil(address /* _user */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice No state to update; computed fresh each call.
    function updateMultiplyingFactor(address /* _user */ ) external pure override {
        return;
    }

    // ───────────────────────── Oracle ─────────────────────────

    /// @notice Attest that a user holds a POAP from one of the qualifying events.
    ///
    /// @dev Called by the off-chain oracle after confirming (e.g. via the Gnosis Chain
    ///      POAP subgraph or `tokenDetailsOfOwnerByIndex`) that the user owns a token
    ///      whose event ID is in `qualifyingEventIds`. The oracle should also monitor
    ///      Transfer events to revoke attestations when the qualifying POAP is transferred.
    ///
    /// @param _user The address to attest
    function attestQualifyingHolder(address _user) external {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        if (!$.isAttested[_user]) {
            $.isAttested[_user] = true;
            emit HolderAttested(_user);
        }
    }

    /// @notice Batch-attest multiple qualifying holders
    /// @param _users Array of user addresses to attest
    function attestQualifyingHolderBatch(address[] calldata _users) external {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        for (uint256 i = 0; i < _users.length; i++) {
            if (!$.isAttested[_users[i]]) {
                $.isAttested[_users[i]] = true;
                emit HolderAttested(_users[i]);
            }
        }
    }

    /// @notice Revoke an attestation (e.g. user transferred their qualifying POAP away)
    ///
    /// @dev The oracle should monitor Transfer events on the POAP contract and call this
    ///      function when a previously-attested holder no longer owns a qualifying token.
    ///
    /// @param _user The address whose attestation should be revoked
    function revokeAttestation(address _user) external {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        if ($.isAttested[_user]) {
            $.isAttested[_user] = false;
            emit AttestationRevoked(_user);
        }
    }

    /// @notice Batch-revoke attestations
    /// @param _users Array of user addresses to revoke
    function revokeAttestationBatch(address[] calldata _users) external {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        if (msg.sender != $.oracle && msg.sender != owner()) revert OnlyOracle();
        for (uint256 i = 0; i < _users.length; i++) {
            if ($.isAttested[_users[i]]) {
                $.isAttested[_users[i]] = false;
                emit AttestationRevoked(_users[i]);
            }
        }
    }

    // ───────────────────────── Admin ─────────────────────────

    /// @notice Add a qualifying POAP event ID
    /// @param _eventId The POAP event ID to approve
    function addEventId(uint256 _eventId) external onlyOwner {
        _addEventId(_eventId);
    }

    /// @notice Remove a qualifying POAP event ID
    /// @param _eventId The POAP event ID to remove
    function removeEventId(uint256 _eventId) external onlyOwner {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        if (!$.isQualifyingEventId[_eventId]) revert EventIdNotAllowlisted(_eventId);
        $.isQualifyingEventId[_eventId] = false;

        // Swap-and-pop removal
        for (uint256 i = 0; i < $.qualifyingEventIds.length; i++) {
            if ($.qualifyingEventIds[i] == _eventId) {
                $.qualifyingEventIds[i] = $.qualifyingEventIds[$.qualifyingEventIds.length - 1];
                $.qualifyingEventIds.pop();
                break;
            }
        }
        emit EventIdRemoved(_eventId);
    }

    /// @notice Set whether any POAP qualifies (overrides event ID list)
    /// @param _acceptAnyPoap If true, any POAP token holder qualifies regardless of event ID
    function setAcceptAnyPoap(bool _acceptAnyPoap) external onlyOwner {
        _getPOAPMultiplierStorage().acceptAnyPoap = _acceptAnyPoap;
    }

    /// @notice Update the oracle address
    /// @param _oracle New oracle address (use address(0) only if acceptAnyPoap=true)
    function setOracle(address _oracle) external onlyOwner {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        emit OracleUpdated($.oracle, _oracle);
        $.oracle = _oracle;
    }

    /// @notice Update the multiplying factor applied to qualifying POAP holders
    /// @param _multiplyingFactor New multiplier (must be >= BASE_MULTIPLIER, i.e. 1e18)
    function setMultiplyingFactor(uint256 _multiplyingFactor) external onlyOwner {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        _getPOAPMultiplierStorage().multiplyingFactor = _multiplyingFactor;
    }

    /// @notice Update the POAP ERC-721 contract address
    /// @param _poapContract New POAP contract address
    function setPoapContract(IERC721 _poapContract) external onlyOwner {
        _getPOAPMultiplierStorage().poapContract = _poapContract;
    }

    function _addEventId(uint256 _eventId) internal {
        POAPMultiplierStorage storage $ = _getPOAPMultiplierStorage();
        if ($.isQualifyingEventId[_eventId]) revert EventIdAlreadyAllowlisted(_eventId);
        $.isQualifyingEventId[_eventId] = true;
        $.qualifyingEventIds.push(_eventId);
        emit EventIdAdded(_eventId);
    }

    // ───────────────────────── Public getters ─────────────────────────

    /// @notice The POAP ERC-721 contract
    function poapContract() external view returns (IERC721) {
        return _getPOAPMultiplierStorage().poapContract;
    }

    /// @notice Multiplying factor granted to POAP holders
    function multiplyingFactor() external view returns (uint256) {
        return _getPOAPMultiplierStorage().multiplyingFactor;
    }

    /// @notice If true, any POAP qualifies
    function acceptAnyPoap() external view returns (bool) {
        return _getPOAPMultiplierStorage().acceptAnyPoap;
    }

    /// @notice Allowlisted POAP event IDs whose holders qualify
    function qualifyingEventIds(uint256 index) external view returns (uint256) {
        return _getPOAPMultiplierStorage().qualifyingEventIds[index];
    }

    /// @notice Number of qualifying event IDs
    function qualifyingEventIdsLength() external view returns (uint256) {
        return _getPOAPMultiplierStorage().qualifyingEventIds.length;
    }

    /// @notice O(1) lookup: event ID → whether it's approved
    function isQualifyingEventId(uint256 eventId) external view returns (bool) {
        return _getPOAPMultiplierStorage().isQualifyingEventId[eventId];
    }

    /// @notice The trusted off-chain oracle that attests qualifying POAP holders
    function oracle() external view returns (address) {
        return _getPOAPMultiplierStorage().oracle;
    }

    /// @notice Records addresses attested by the oracle as holding a qualifying POAP
    function isAttested(address user) external view returns (bool) {
        return _getPOAPMultiplierStorage().isAttested[user];
    }
}
