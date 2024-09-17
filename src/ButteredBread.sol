// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
contract ButteredBread is IButteredBread, ERC20VotesUpgradeable, OwnableUpgradeable {
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

        __Ownable_init(msg.sender);
        __ERC20_init(_initData.name, _initData.symbol);

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
     * @notice Deposit LP tokens
     * @param _lp Liquidity Pool token
     * @param _amount Value of LP token
     */
    function deposit(address _lp, uint256 _amount) external onlyAllowed(_lp) {
        _deposit(msg.sender, _lp, _amount);
    }

    /**
     * @notice Withdraw LP tokens
     * @param _lp Liquidity Pool token
     * @param _amount Value of LP token
     */
    function withdraw(address _lp, uint256 _amount) external onlyAllowed(_lp) {
        _withdraw(msg.sender, _lp, _amount);
    }

    /**
     * @notice Allow or deny LP token
     * @dev Must set scaling factor before sanctioning LP token
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

    /// @notice Deposit LP tokens and mint ButteredBread with corresponding LP scaling factor
    function _deposit(address _account, address _lp, uint256 _amount) internal {
        IERC20(_lp).transferFrom(_account, address(this), _amount);
        _accountToLPData[_account][_lp].balance += _amount;

        uint256 currentScalingFactor = scalingFactors[_lp];
        _accountToLPData[_account][_lp].scalingFactor = currentScalingFactor;

        _mint(_account, _amount * currentScalingFactor / FIXED_POINT_PERCENT);
        _syncDelegation(_account);

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
        IERC20(_lp).transfer(_account, _amount);

        emit ButterRemoved(_account, _lp, _amount);
    }

    function _modifyScalingFactor(address _lp, uint256 _factor, address[] calldata _holders) internal {
        if (_factor < FIXED_POINT_PERCENT) revert InvalidValue();

        scalingFactors[_lp] = _factor;
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
