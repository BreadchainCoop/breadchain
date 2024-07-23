
## Requirements 
-  Allow users who hold Breadchain sanctioned LPs to participate in governance 
-  Support multiple implementations of liquidity pools 
-  LP Token holders should be able to redeem their full amount deposited according to the LP conventions, and lose voting right if they redeem the non-$BREAD option 
-  Users should maintain usability of the LP frontend 
-  Removing or adding LP should be supported 
- Getting voting rights from multiple LP should be supported 
- Getting voting rights from LP and $BREAD at the same time should be supported 
## Concessions 
- Contributing non-$BREAD tokens to the LP will afford voting power 
- Users will have to alternate between LP Frontend and Breadchain Frontend 
- Voting power is effective only after `cycleLength` after LP tokens were exchanged for voting rights regardless of duration of tokens being in the LP 
- The voting token will not be transferable 
### Notes 
Butter -> Some LP Token 
ButteredBread -> A voting compatible token ,minted with different Butters  

## User flows 

```mermaid
sequenceDiagram

BreadHolder ->> LP : Deposit $BREAD and recieve LP Tokens

BreadHolder ->> ButteredBread : Deposit LP Tokens

ButteredBread ->> ButteredBread : Record LP token amount

ButteredBread ->> BreadHolder : Mint $BB

BreadHolder ->> YieldDistributor : Use $BB to vote

note right of BreadHolder : Some time has passed and BreadHolder wants to withdraw their bread from the LP

BreadHolder ->> ButteredBread : Exchange $BB for LP token

BreadHolder ->> Liquidity Pool : Withdraw
```


## Implementation Suggestion 

This implementation relies on the idea that the "weight" for LP tokens is a constant, initialised when whitelisting a new LP. 
This relies on the assumption that the LP will always try to balance itself such that Butter will reach equilibrium, and if initialising the LP with an equal amount of $BREAD and some token in value (for example 1000 bread and 920 EUROs), we can take the virtual price of the Butter at that point to be our constant scaling factor. Given our assumption that the liquidity pools won't significantly depeg, this constant scaling factors simplifies our implementation. 

Without this assumption, another option is for the scaling factor to be determined at the time of deposit, and so $BB will be minted according to how much $BREAD the Butter is worth at the time of deposit. This introduces several dependencies 
- Each liquidity pool added must be added with an interface for fetching the current value of the LP tokens in BREAD 
- Only full unwraps of $BB for a given liquidity pool are allowed as the exchange rate between $BB and the Butter is dynamic and changing, and a partial withdrawal would require calculating how much $BB should be burned 


### UML 
```mermaid
classDiagram

class IERC20{

totalSupply() external view returns (uint256);

balanceOf(address account) external view returns (uint256);

transfer(address to, uint256 value) external returns (bool);

allowance(address owner, address spender) external view returns (uint256);

approve(address spender, uint256 value) external returns (bool);

transferFrom(address from, address to, uint256 value) external returns (bool);

  

}

class ERC20VotesUpgradeable{

checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory)

numCheckpoints(address account) public view virtual returns (uint32)

delegate(address delegatee)

}

  

class ButteredBread {

address => bool whitelistedLP

address => address=> uint256 accountToLPBalance

address => uint256 scalingFactors

deposit(address lp, uint256 amount)

withdraw(address lp,uint256 amount)
mint(address to, uint256 amount)
_burn(address holder, uint256 amount)

  

}

  

ERC20VotesUpgradeable <|-- ButteredBread

  

class ILiquidityPool1{

Curve Monerium <> BREAD

}

class ILiquidityPool2{

Curve xDAI <> BREAD

}

class ILiquidityPool3{

UniswapV3 USDC <> BREAD

}

IERC20<|-- ILiquidityPool1

IERC20<|-- ILiquidityPool2

IERC20<|-- ILiquidityPool3

IERC20<|-- ERC20VotesUpgradeable

  
  

class YieldDistributorV2{

address [] votingTokens

castVote(uint256[] calldata _points)
 _castVote(address _account, uint256[] calldata _points, uint256 _votingPower) internal
  

}

class YieldDistributor{

uint256 cycleLength

uint256 currentVotes

uint256[] projectDistributions

address=>uint256 accountLastVoted

address=> uint256[] voterDistributions

getVotingPowerForPeriod(uint256 _start, uint256 _end, address _account, address token) external view returns (uint256)

castVote(uint256 [] points)

resolveYieldDistribution()

distributeYield()

}

  

YieldDistributor <|-- YieldDistributorV2

  

YieldDistributorV2 o-- ButteredBread

  

class Bread{

claimYield(uint256 amount, address receiver) external ;

yieldAccrued() external view returns (uint256);

setYieldClaimer(address _yieldClaimer) external ;

}

  

Bread --o YieldDistributorV2

  

ILiquidityPool1 --o ButteredBread

ILiquidityPool2 --o ButteredBread

ILiquidityPool3 --o ButteredBread
```
### Function Flow 

```mermaid 
sequenceDiagram

autonumber

BreadHolder ->> BREAD : Mint 20 BREAD

BreadHolder ->> LP : Deposit $BREAD 10 and recieve n LP Tokens

BreadHolder ->> LP : approve(address,amount)

LP ->> ButteredBread : Approve spending n LP Tokens

BreadHolder ->> ButteredBread : deposit(address,amount)

alt if !whitelistedLP[address]

ButteredBread ->> ButteredBread : Revert

else

ButteredBread ->> LP : transferFrom(address,amount)

ButteredBread ->> ButteredBread : accountToLPBalance[msg.sender][lpaddress]=amount

ButteredBread ->> BreadHolder : mint(msg.sender, amount * scalingFactors[lpaddress])

BreadHolder ->> YieldDistributor : castVote(uin256[] percentages)

YieldDistributor ->> YieldDistributor : voting power = sum([getCurrentVotingPower(token) for token in votingTokens])

YieldDistributor ->> YieldDistributor : _castVote(address _account, uint256[] calldata _points, uint256 _votingPower)

note right of BreadHolder : Some time has passed and BreadHolder wants to withdraw their bread from the LP

BreadHolder ->> ButteredBread : withdraw(address,amount)

alt if !whitelistedLP[address] || accountToLPBalance[msg.sender][lpaddress] < amount

ButteredBread ->> ButteredBread : Revert

else

end

ButteredBread ->> ButteredBread : accountToLPBalance[msg.sender][lpaddress]-=amount

ButteredBread ->> ButteredBread : _burn(msg.sender, amount * scalingFactors[lpaddress])

ButteredBread ->> LP: transfer(msg.sender,amount)

end
```