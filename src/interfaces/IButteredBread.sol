// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

/**
 * @title `ButteredBread` interface
 */
interface IButteredBread {
    /// @notice Occurs when a user does not have sufficient Butter to mint `ButteredBread`
    error InsufficientFunds();
    /// @notice Occurs when an invalid value is attempted to be used in setter functions
    error InvalidValue();
    /// @notice Occurs when attempting a deposit with a non-sanctioned LP
    error NotAllowListed();
    /// @notice Occurs when attempting to delegate `ButteredBrea`d tokens. Delegations are set via the $BREAD contract
    error NonDelegatable();
    /// @notice Occurs when attempting to transfer soulbound `ButteredBread` tokens
    error NonTransferable();
    /// @notice Occurs when a dependent variable is not set
    error UnsetVariable();
    /// @notice Occurs when a transfer fails
    error TransferFailed();
    /// @notice Occurs when an amount is 0
    error AmountZero();

    /// @notice The event emitted when an LP Token (Butter) has been added
    event ButterAdded(address _account, address _lp, uint256 _amount);
    /// @notice The event emitted when an LP Token (Butter) has been removed
    event ButterRemoved(address _account, address _lp, uint256 _amount);

    /**
     * @param breadToken Address of `BreadToken`
     * @param liquidityPools Sanctioned LPs
     * @param scalingFactors Scaling factor on mint per sanctioned LP
     * @dev Each scaling factor is a fixed point percent (e.g. 100 = 1X, 150 = 1.5X, 1000 = 10X)
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     */
    struct InitData {
        address breadToken;
        address[] liquidityPools;
        uint256[] scalingFactors;
        string name;
        string symbol;
    }

    /**
     * @param balance Value of deposited LP tokens (Butter)
     * @param scalingFactor At the time of deposit or updated with `syncVotingWeight` function
     */
    struct LPData {
        uint256 balance;
        uint256 scalingFactor;
    }

    /// @notice Initialize contract as a `TransparentUpgradeableProxy`
    function initialize(InitData calldata _initData) external;

    /// @notice Returns whether a given liquidity pool is Breadchain sanctioned or not
    /// @return allowed True if the LP is allowlisted, false otherwise
    function allowlistedLPs(address _lp) external view returns (bool allowed);

    /// @notice Returns the factor that determines how much `ButteredBread` should be minted for a Liquidity Pool token
    /// @return factor The scaling factor for the LP token where 10000 = 100%
    function scalingFactors(address _lp) external view returns (uint256 factor);

    /// @notice Returns the amount of LP tokens (Butter) deposited for an account
    /// @return balance The amount of LP tokens deposited
    function accountToLPBalance(address _account, address _lp) external view returns (uint256 balance);

    /// @notice Deposits LP tokens (Butter) and mints `ButteredBread` according to the respective LP scaling factor
    function deposit(address _lp, uint256 _amount) external;

    /// @notice Withdraws some amount of Butter (LP token) and burns an amount of the user's `ButteredBread` according to the respective scaling factor
    function withdraw(address _lp, uint256 _amount) external;

    /// @notice Defines a liquidity pool's status as sanctioned or unsanctioned by Breadchain
    function modifyAllowList(address _lp, bool _allowed) external;

    /// @notice Modifies how much `ButteredBread` should be minted for a Liquidity Pool token (Butter)
    function modifyScalingFactor(address _lp, uint256 _factor, address[] calldata holders) external;

    /// @notice Get the current multiplier value for a user
    /// @return multiplier The current multiplier value as a percentage where 10000 = 100%
    function getMultiplier(address user) external view returns (uint256 multiplier);

    /// @notice Get the timestamp when the user's temporary multiplier boost expires
    /// @return expiry The expiry timestamp of the multiplier boost
    function getMultiplierBoostExpiry(address user) external view returns (uint256 expiry);

    /// @notice Get the user's base multiplier without any temporary boosts
    /// @return baseMultiplier The base multiplier value as a percentage where 10000 = 100%
    function getBaseMultiplier(address user) external view returns (uint256 baseMultiplier);
}
