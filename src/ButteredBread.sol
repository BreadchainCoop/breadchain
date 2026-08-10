// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
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
contract ButteredBread is IButteredBread, ERC20VotesUpgradeable, Ownable2StepUpgradeable, ReentrancyGuard {
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

    /// @dev Applied to functions to only allow access for sanctioned liquidity pools
    modifier onlyAllowed(address _lp) {
        if (!allowlistedLPs[_lp]) revert NotAllowListed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @param _initData See `IButteredBread`
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

    /// @notice Sync this delegation with user delegate selection on $BREAD
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

    /// @notice `ButteredBread` tokens are non-transferable
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /// @notice `ButteredBread` tokens are non-transferable
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /// @notice `ButteredBread` delegation is determined by `BreadToken`
    function delegate(address) public virtual override {
        revert NonDelegatable();
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

        uint256 previousBalance = _accountToLPData[_account][_lp].balance;
        uint256 newBalance = previousBalance + _amount;
        _accountToLPData[_account][_lp].balance = newBalance;

        _mint(_account, _scaledBalance(newBalance, _lp) - _scaledBalance(previousBalance, _lp));

        emit ButterAdded(_account, _lp, _amount);
    }

    /// @notice Withdraw LP tokens and burn ButteredBread with corresponding LP scaling factor
    function _withdraw(address _account, address _lp, uint256 _amount) internal {
        uint256 previousBalance = _accountToLPData[_account][_lp].balance;
        if (_amount > previousBalance) revert InsufficientFunds();
        _syncDelegation(_account);

        /// @dev ensure proper accounting in case of admin error in `modifyScalingFactor` where not all holders are updated
        _syncVotingWeight(_account, _lp);

        /// @dev `_syncVotingWeight` only adjusts the stored scaling factor, so `previousBalance` is still current
        uint256 newBalance = previousBalance - _amount;
        _accountToLPData[_account][_lp].balance = newBalance;

        _burnUpToBalance(_account, _scaledBalance(previousBalance, _lp) - _scaledBalance(newBalance, _lp));

        bool success = IERC20(_lp).transfer(_account, _amount);
        if (!success) revert TransferFailed();

        emit ButterRemoved(_account, _lp, _amount);
    }

    function _modifyScalingFactor(address _lp, uint256 _factor, address[] calldata _holders) internal {
        if (_factor < FIXED_POINT_PERCENT) revert InvalidValue();

        uint256 old = scalingFactors[_lp];
        scalingFactors[_lp] = _factor;
        emit ScalingFactorModified(_lp, old, _factor);

        for (uint256 i = 0; i < _holders.length; i++) {
            _syncVotingWeight(_holders[i], _lp);
        }
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
                /// @dev difference of scaled balances, matching how `_deposit` and `_withdraw` scale
                uint256 currentWeight = lpBalance * currentScalingFactor / FIXED_POINT_PERCENT;
                uint256 initialWeight = lpBalance * initialScalingFactor / FIXED_POINT_PERCENT;

                if (currentWeight > initialWeight) {
                    _mint(_account, currentWeight - initialWeight);
                } else {
                    _burnUpToBalance(_account, initialWeight - currentWeight);
                }
            }
        }
    }

    /// @notice Apply the scaling factor of a liquidity pool to an LP token balance
    function _scaledBalance(uint256 _balance, address _lp) internal view returns (uint256) {
        return _balance * scalingFactors[_lp] / FIXED_POINT_PERCENT;
    }

    /**
     * @notice Burn `ButteredBread`, capped at the balance of the account
     * @dev Accounts that deposited before scaled balances were differenced hold slightly less `ButteredBread`
     *  than their aggregate entitlement, because each deposit floored its own mint. Capping lets those accounts
     *  withdraw their full LP balance instead of reverting in `_burn`. For every deposit made under the current
     *  accounting the requested amount is already covered, so the cap does not apply.
     */
    function _burnUpToBalance(address _account, uint256 _amount) internal {
        uint256 accountBalance = balanceOf(_account);
        _burn(_account, _amount > accountBalance ? accountBalance : _amount);
    }
}
