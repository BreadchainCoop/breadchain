// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {IMultiplier} from "src/interfaces/multipliers/IMultiplier.sol";
import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";
import {MultiplierConstants} from "src/libraries/MultiplierConstants.sol";

/// @title Bread Transaction Multiplier
/// @notice Grants a voting power boost to users who have made BREAD token transactions
///         within a qualifying window of blocks.
/// @dev Uses the ERC20Votes checkpoint history of the BREAD token to verify activity.
///      A checkpoint is created whenever a user's delegated-vote balance changes
///      (i.e. on any transfer from/to an account that has self-delegated). This is a
///      reliable on-chain signal that the user is actively transacting in BREAD.
contract BreadTransactionMultiplier is Initializable, OwnableUpgradeable, IMultiplier {
    /// @custom:storage-location erc7201:breadchain.BreadTransactionMultiplier.storage
    struct BreadTransactionMultiplierStorage {
        /// @notice The BREAD token contract (must implement IERC20Votes)
        IERC20Votes breadToken;
        /// @notice Multiplying factor granted to qualifying users (fixed-point, 1e18 = 1x)
        uint256 multiplyingFactor;
        /// @notice Number of blocks that define the qualifying activity window.
        ///         A user qualifies if their most recent BREAD checkpoint falls within
        ///         the last `qualifyingWindow` blocks.
        uint256 qualifyingWindow;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.BreadTransactionMultiplier.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BREAD_TRANSACTION_MULTIPLIER_STORAGE_LOCATION =
        0xe2e42077bd75363d8940e45df66a43416e57f9d9e336cd68df4a57e6c2adb300;

    function _getBreadTransactionMultiplierStorage()
        private
        pure
        returns (BreadTransactionMultiplierStorage storage $)
    {
        assembly {
            $.slot := BREAD_TRANSACTION_MULTIPLIER_STORAGE_LOCATION
        }
    }

    /// @notice Error emitted when an invalid qualifying window is provided
    error InvalidQualifyingWindow();

    /// @notice Error emitted when an invalid multiplying factor is provided
    error InvalidMultiplyingFactor();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _breadToken Address of the BREAD token (must implement IERC20Votes)
    /// @param _multiplyingFactor The multiplying factor for active BREAD users (fixed-point 1e18 = 1x)
    /// @param _qualifyingWindow Number of blocks in which activity must have occurred
    function initialize(address _breadToken, uint256 _multiplyingFactor, uint256 _qualifyingWindow)
        public
        initializer
    {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        if (_qualifyingWindow == 0) revert InvalidQualifyingWindow();

        __Ownable_init(msg.sender);

        BreadTransactionMultiplierStorage storage $ = _getBreadTransactionMultiplierStorage();
        $.breadToken = IERC20Votes(_breadToken);
        $.multiplyingFactor = _multiplyingFactor;
        $.qualifyingWindow = _qualifyingWindow;
    }

    /// @notice Returns the multiplying factor if the user has been active within the qualifying window
    /// @dev Walks the user's BREAD vote checkpoints backwards to find a recent one.
    ///      A checkpoint is created when a delegated balance changes (transfer, mint, burn),
    ///      so this is a faithful proxy for BREAD transaction activity.
    /// @param _user The address of the user to check
    /// @return The multiplyingFactor if active, 0 otherwise
    function getMultiplyingFactor(address _user) public view override returns (uint256) {
        BreadTransactionMultiplierStorage storage $ = _getBreadTransactionMultiplierStorage();
        uint32 numCheckpoints = $.breadToken.numCheckpoints(_user);
        if (numCheckpoints == 0) return 0;

        uint256 windowStart = block.number > $.qualifyingWindow ? block.number - $.qualifyingWindow : 0;

        // Walk backwards from most recent checkpoint to find activity within the window.
        // In practice the most recent checkpoint is almost always within the window,
        // so this is O(1) in the common case.
        for (uint32 i = numCheckpoints; i > 0;) {
            Checkpoints.Checkpoint208 memory cp = $.breadToken.checkpoints(_user, --i);
            if (cp._key >= windowStart) {
                return $.multiplyingFactor;
            }
            // Checkpoints are stored in ascending order; if this one is already before
            // the window, all earlier ones will be too — stop early.
            break;
        }

        return 0;
    }

    /// @notice The multiplier check is always live; returns type(uint256).max so the
    ///         VotingMultipliers router never gates on block validity.
    function validUntil(address /* _user */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice No persistent state to update; the check is computed fresh each call.
    function updateMultiplyingFactor(address /* _user */ ) external pure override {
        return;
    }

    // ───────────────────────── Admin ─────────────────────────

    /// @notice Update the qualifying activity window
    /// @param _qualifyingWindow New window size in blocks
    function setQualifyingWindow(uint256 _qualifyingWindow) external onlyOwner {
        if (_qualifyingWindow == 0) revert InvalidQualifyingWindow();
        _getBreadTransactionMultiplierStorage().qualifyingWindow = _qualifyingWindow;
    }

    /// @notice Update the multiplying factor
    /// @param _multiplyingFactor New factor (must be >= BASE_MULTIPLIER)
    function setMultiplyingFactor(uint256 _multiplyingFactor) external onlyOwner {
        if (_multiplyingFactor < MultiplierConstants.BASE_MULTIPLIER) revert InvalidMultiplyingFactor();
        _getBreadTransactionMultiplierStorage().multiplyingFactor = _multiplyingFactor;
    }

    /// @notice Update the BREAD token address used for checkpoint lookups
    /// @param _breadToken New BREAD token address (must implement IERC20Votes)
    function setBreadToken(address _breadToken) external onlyOwner {
        _getBreadTransactionMultiplierStorage().breadToken = IERC20Votes(_breadToken);
    }

    // ───────────────────────── Public getters ─────────────────────────

    /// @notice The BREAD token contract
    function breadToken() external view returns (IERC20Votes) {
        return _getBreadTransactionMultiplierStorage().breadToken;
    }

    /// @notice Multiplying factor granted to qualifying users
    function multiplyingFactor() external view returns (uint256) {
        return _getBreadTransactionMultiplierStorage().multiplyingFactor;
    }

    /// @notice Number of blocks that define the qualifying activity window
    function qualifyingWindow() external view returns (uint256) {
        return _getBreadTransactionMultiplierStorage().qualifyingWindow;
    }
}
