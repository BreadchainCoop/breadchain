// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {
    VotesExtendedUpgradeable,
    VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesExtendedUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IButteredBread} from "src/interfaces/IButteredBread.sol";
import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";

/**
 * @title Breadchain Buttered Bread
 * @notice Deposit LP tokens (Butter) to earn scaling rewards
 * @author Breadchain Collective
 * @custom:coauthor @RonTuretzky
 * @custom:coauthor @daopunk
 * @custom:coauthor @bagelface
 */
contract ButteredBread is
    IButteredBread,
    ERC20VotesUpgradeable,
    VotesExtendedUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuard
{
    /// @notice Value used for calculating the precision of scaling factors
    uint256 public constant FIXED_POINT_PERCENT = 100;
    /// @notice `IERC20Votes` contract used for powering `ButteredBread` voting
    IERC20Votes public bread;
    /// @notice Access control for Breadchain sanctioned liquidity pools
    mapping(address lp => bool allowed) public allowlistedLPs;
    /// @notice How much ButteredBread should be minted for a Liquidity Pool token (Butter)
    mapping(address lp => uint256 factor) public scalingFactors;
    /// @notice Butter balance by account and Liquidity Pool token deposited
    mapping(address account => mapping(address lp => LPData)) internal _accountToLPData;

    // -------------------------------------------------------------------------
    // Legacy storage layout — frozen for deployed proxy compatibility
    // -------------------------------------------------------------------------
    // IMPORTANT: This contract is deployed on Gnosis mainnet behind a UUPS proxy.
    // The variables above occupy slots 0–3 and MUST NOT be reordered, removed,
    // or have new variables inserted among them. The __gap below reserves slots
    // 4–49 so that any parent-contract storage growth does not collide with
    // future additions made via the ERC-7201 namespaced struct below.
    //
    // @custom:storage-location erc7201:breadchain.ButteredBread.legacy
    // (Documented for tooling; the flat variables above ARE the legacy layout.)
    //
    // NOTE on ReentrancyGuard: ButteredBread inherits `ReentrancyGuard` from
    // OpenZeppelin 5.x, which already uses ERC-7201 namespaced storage for its
    // `_status` variable (`openzeppelin.storage.ReentrancyGuard`). There is
    // therefore NO sequential-storage slot occupied by reentrancy state — it
    // is safe as-is and does NOT require migration. Do not switch to the
    // Upgradeable variant for existing deployments, as that would be a no-op
    // at best and a source of confusion at worst.
    // -------------------------------------------------------------------------

    /// @dev Reserves storage slots 4–49 to protect against inheritance-chain
    ///      collisions. Size = 50 − 4 (used slots 0–3) = 46.
    ///      DO NOT add new flat state variables below this gap — use
    ///      `_getButteredBreadExtendedStorage()` instead.
    uint256[46] private __gap;

    // =========================================================================
    // ERC-7201 Namespaced storage — use this for ALL future storage additions
    // =========================================================================

    /// @custom:storage-location erc7201:breadchain.ButteredBread.extended
    struct ButteredBreadExtendedStorage {
        // Add new storage variables here in future upgrades.
        // Example:
        //   uint256 depositCap;
        //   mapping(address => bool) featureFlags;
        //
        // Placeholder — Solidity ≥ 0.8.28 disallows empty structs.
        // Replace with the first real field when extending storage.
        uint256 _placeholder;
    }

    // keccak256(abi.encode(uint256(keccak256("breadchain.ButteredBread.extended")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BUTTERED_BREAD_EXTENDED_STORAGE_LOCATION =
        0xa0e8115f0ef7b7bb79a381aeedea22848ca0c05b285f05ae260071d211f86b00;

    /// @dev Returns a pointer to the ERC-7201 extended storage struct.
    ///      Use this accessor in new functions that need additional state.
    function _getButteredBreadExtendedStorage()
        private
        pure
        returns (ButteredBreadExtendedStorage storage $)
    {
        assembly {
            $.slot := BUTTERED_BREAD_EXTENDED_STORAGE_LOCATION
        }
    }

    /// @dev Applied to functions to only allow access for sanctioned liquidity pools
    modifier onlyAllowed(address _lp) {
        if (!allowlistedLPs[_lp]) revert NotAllowListed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ButteredBread token with LP configuration and token metadata
     * @dev Registers each LP in `_initData.liquidityPools` with its corresponding scaling factor
     *      and adds it to the allowlist. `_initData.liquidityPools` and `_initData.scalingFactors`
     *      must have the same length. Reverts with `InvalidValue` if they differ.
     *      The contract owner is set to `msg.sender` (the deployer / proxy admin).
     * @param _initData Initialization struct; see `IButteredBread.InitData` for field details
     */
    function initialize(InitData calldata _initData) external initializer {
        if (_initData.liquidityPools.length != _initData.scalingFactors.length) revert InvalidValue();
        bread = IERC20Votes(_initData.breadToken);

        __ERC20_init(_initData.name, _initData.symbol);
        __EIP712_init(_initData.name, "1");
        __ERC20Votes_init();
        __Ownable_init(msg.sender);

        for (uint256 i; i < _initData.liquidityPools.length; ++i) {
            scalingFactors[_initData.liquidityPools[i]] = _initData.scalingFactors[i];
            allowlistedLPs[_initData.liquidityPools[i]] = true;
        }
    }

    /**
     * @notice Return token balance of account for a specified LP
     * @param _account Voting account
     * @param _lp Liquidity Pool token
     * @return _lpBalance Balance of LP tokens for an account by LP address
     */
    function accountToLPBalance(address _account, address _lp) external view returns (uint256 _lpBalance) {
        _lpBalance = _accountToLPData[_account][_lp].balance;
    }

    /**
     * @notice Syncs the caller's ButteredBread delegation to match their current $BREAD delegate
     * @dev Reads `bread.delegates(msg.sender)` and calls `_delegate` accordingly. If the
     *      resulting delegate is `address(0)` (no delegation set on BREAD), self-delegates.
     *      Anyone may call this to re-sync after changing their $BREAD delegation.
     */
    function syncDelegation() external {
        _syncDelegation(msg.sender);
    }

    /**
     * @notice Deposit LP tokens and mint ButteredBread
     *  NOTE: Additional ButteredBread can be minted/burned due to scaling factor changes
     * @param _lp Liquidity Pool token
     * @param _amount Value of LP token
     */
    function deposit(address _lp, uint256 _amount) external onlyAllowed(_lp) nonReentrant {
        if (_amount == 0) revert AmountZero();
        _deposit(msg.sender, _lp, _amount);
    }

    /**
     * @notice Withdraw LP tokens and burn ButteredBread
     *  NOTE: Additional ButteredBread can be minted/burned due to scaling factor changes
     * @param _lp Liquidity Pool token
     * @param _amount Value of LP token
     */
    function withdraw(address _lp, uint256 _amount) external onlyAllowed(_lp) nonReentrant {
        if (_amount == 0) revert AmountZero();
        _withdraw(msg.sender, _lp, _amount);
    }

    /**
     * @notice Allow or deny LP token
     * @dev Must set scaling factor before sanctioning LP token
     * @dev WARNING: When adding a new LP token, ensure that it has 18 decimals
     * @param _lp Liquidity Pool token
     * @param _allowed Sanction status of LP token
     */
    function modifyAllowList(address _lp, bool _allowed) external onlyOwner {
        if (scalingFactors[_lp] == 0) revert UnsetVariable();
        allowlistedLPs[_lp] = _allowed;
    }

    /**
     * @notice Set LP token scaling factor
     * @param _lp Liquidity Pool token
     * @param _factor Scaling percentage incentive of LP token (e.g. 100 = 1X, 150 = 1.5X, 1000 = 10X)
     * @param _holders List of accounts to update with new scaling factor
     */
    function modifyScalingFactor(address _lp, uint256 _factor, address[] calldata _holders) external onlyOwner {
        _modifyScalingFactor(_lp, _factor, _holders);
    }

    /**
     * @notice ButteredBread tokens are non-transferable; always reverts
     * @dev Overrides ERC20 `transfer` to enforce soulbound behaviour.
     *      ButteredBread is minted/burned only through `deposit`/`withdraw`.
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice ButteredBread tokens are non-transferable; always reverts
     * @dev Overrides ERC20 `transferFrom` to enforce soulbound behaviour.
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice ButteredBread delegation is managed automatically from $BREAD; always reverts
     * @dev Overrides ERC20Votes `delegate`. Use `syncDelegation()` to update delegation.
     *      Delegation follows the holder's $BREAD delegate choice rather than being
     *      independently configurable.
     */
    function delegate(address) public virtual override {
        revert NonDelegatable();
    }

    /**
     * @notice Initialize VotesExtended checkpoints for delegation and balance history
     * @dev Must be called once after upgrading from a version without VotesExtended.
     *      Uses ERC-7201 namespaced storage, so no storage collision risk.
     * @custom:oz-upgrades-validate-as-initializer
     * @custom:oz-upgrades-unsafe-allow missing-initializer-call
     */
    function initializeVotesExtended() public reinitializer(2) {
        __VotesExtended_init();
    }

    /// @notice Get the LP data (balance and scaling factor) of a specific LP for a given account
    /// @param _holder The address of the account to get the data for
    /// @param _lp The address of the LP to get the data for
    /// @return LPData memory The LP data containing balance and scaling factor for the given account
    function getLPData(address _holder, address _lp) external view returns (LPData memory) {
        return _accountToLPData[_holder][_lp];
    }

    /// @notice Deposit LP tokens and mint ButteredBread with corresponding LP scaling factor
    function _deposit(address _account, address _lp, uint256 _amount) internal {
        bool success = IERC20(_lp).transferFrom(_account, address(this), _amount);
        if (!success) revert TransferFailed();

        _syncDelegation(_account);

        /// @dev ensure proper accounting in case of admin error in `modifyScalingFactor` where not all holders are updated
        _syncVotingWeight(_account, _lp);
        _accountToLPData[_account][_lp].balance += _amount;

        _mint(_account, _amount * scalingFactors[_lp] / FIXED_POINT_PERCENT);

        emit ButterAdded(_account, _lp, _amount);
    }

    /// @notice Withdraw LP tokens and burn ButteredBread with corresponding LP scaling factor
    function _withdraw(address _account, address _lp, uint256 _amount) internal {
        if (_amount > _accountToLPData[_account][_lp].balance) revert InsufficientFunds();
        _syncDelegation(_account);

        /// @dev ensure proper accounting in case of admin error in `modifyScalingFactor` where not all holders are updated
        _syncVotingWeight(_account, _lp);
        _accountToLPData[_account][_lp].balance -= _amount;

        _burn(_account, _amount * scalingFactors[_lp] / FIXED_POINT_PERCENT);
        bool success = IERC20(_lp).transfer(_account, _amount);
        if (!success) revert TransferFailed();

        emit ButterRemoved(_account, _lp, _amount);
    }

    /// @notice Internal implementation of scaling factor update; syncs voting weights for all affected holders
    /// @dev Reverts with `InvalidValue` if `_factor` is less than `FIXED_POINT_PERCENT` (i.e. less than 1×).
    ///      For each holder, calls `_syncVotingWeight` which mints or burns ButteredBread to reflect
    ///      the new scaling factor relative to their current LP balance.
    /// @param _lp Liquidity Pool token address
    /// @param _factor New scaling percentage (must be >= FIXED_POINT_PERCENT = 100)
    /// @param _holders Array of holder addresses whose ButteredBread balance should be resynced
    function _modifyScalingFactor(address _lp, uint256 _factor, address[] calldata _holders) internal {
        if (_factor < FIXED_POINT_PERCENT) revert InvalidValue();

        uint256 old = scalingFactors[_lp];
        scalingFactors[_lp] = _factor;
        emit ScalingFactorModified(_lp, old, _factor);

        for (uint256 i = 0; i < _holders.length; i++) {
            _syncVotingWeight(_holders[i], _lp);
        }
    }

    /// @inheritdoc VotesUpgradeable
    /// @dev Resolves diamond inheritance: VotesUpgradeable ← VotesExtendedUpgradeable
    ///      VotesExtended._delegate records delegation checkpoints before calling super.
    function _delegate(address account, address delegatee)
        internal
        virtual
        override(VotesUpgradeable, VotesExtendedUpgradeable)
    {
        super._delegate(account, delegatee);
    }

    /// @inheritdoc VotesUpgradeable
    /// @dev Resolves diamond inheritance: VotesUpgradeable ← VotesExtendedUpgradeable
    ///      VotesExtended._transferVotingUnits records balance checkpoints after calling super.
    function _transferVotingUnits(address from, address to, uint256 amount)
        internal
        virtual
        override(VotesUpgradeable, VotesExtendedUpgradeable)
    {
        super._transferVotingUnits(from, to, amount);
    }

    /// @notice Sync this delegation with delegate selection on $BREAD
    function _syncDelegation(address _account) internal {
        _delegate(_account, bread.delegates(_account));
        if (this.delegates(_account) == address(0)) _delegate(_account, _account);
    }

    /// @notice Sync voting weight with scaling factor
    function _syncVotingWeight(address _account, address _lp) internal {
        uint256 currentScalingFactor = scalingFactors[_lp];
        uint256 initialScalingFactor = _accountToLPData[_account][_lp].scalingFactor;

        if (currentScalingFactor != initialScalingFactor) {
            uint256 lpBalance = _accountToLPData[_account][_lp].balance;
            _accountToLPData[_account][_lp].scalingFactor = currentScalingFactor;

            if (lpBalance > 0) {
                if (currentScalingFactor > initialScalingFactor) {
                    _mint(
                        _account,
                        (lpBalance * currentScalingFactor - lpBalance * initialScalingFactor) / FIXED_POINT_PERCENT
                    );
                } else {
                    _burn(
                        _account,
                        (lpBalance * initialScalingFactor - lpBalance * currentScalingFactor) / FIXED_POINT_PERCENT
                    );
                }
            }
        }
    }
}
