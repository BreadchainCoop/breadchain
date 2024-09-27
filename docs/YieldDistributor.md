```mermaid
classDiagram
    class YieldDistributor {
        <<abstract>> IYieldDistributor
        <<abstract>> OwnableUpgradeable
        
        +Bread BREAD
        +uint256 PRECISION
        +uint256 cycleLength
        +uint256 maxPoints
        +uint256 minRequiredVotingPower
        +uint256 lastClaimedBlockNumber
        +uint256 currentVotes
        +address projects
        +address queuedProjectsForAddition
        +address queuedProjectsForRemoval
        +uint256 projectDistributions
        +mapping(address => uint256) accountLastVoted
        #mapping(address => null) voterDistributions
        +uint256 yieldFixedSplitDivisor
        +ERC20VotesUpgradeable BUTTERED_BREAD

        +__constructor__()
        +initialize()
        +getCurrentVotingDistribution()
        +getCurrentVotingPower()
        +getVotingPowerForPeriod()
        +resolveYieldDistribution()
        +distributeYield()
        +castVote()
        #_castVote()
        #_updateBreadchainProjects()
        +queueProjectAddition()
        +queueProjectRemoval()
        +setMinRequiredVotingPower()
        +setMaxPoints()
        +setCycleLength()
        +setyieldFixedSplitDivisor()
        +setButteredBread()
    }

    YieldDistributor --|> IYieldDistributor : Inherits
    YieldDistributor --|> OwnableUpgradeable : Inherits

```

# YieldDistributor 
The YieldDistributor contract is a smart contract designed to manage and distribute yield (in the form of $BREAD tokens) to eligible member projects within the Breadchain ecosystem. This contract implements a voting mechanism that allows token holders to influence the distribution of yield across various projects. By leveraging both $BREAD and $BUTTERED_BREAD tokens, the system creates a dual-token voting power structure, encouraging active participation and long-term commitment from community members.

At its core, the YieldDistributor contract enables a democratic and transparent process for allocating resources within the Breadchain network. It features a cyclical distribution system, where token holders can cast votes using their voting power, which is calculated based on their token holdings over time. The contract supports dynamic project management, allowing for the addition and removal of eligible projects, and incorporates both fixed and voted components in the yield distribution to ensure a balance between equity and direct democracy. 

# Voting 
The `castVote` function allows users to participate in the yield distribution process by allocating their voting power to different projects. Here's a detailed explanation:

```mermaid
sequenceDiagram
    actor User
    participant YD as YieldDistributor
    participant BREAD as BREAD Token
    participant BB as BUTTERED_BREAD Token

    User->>YD: castVote(_points)
    activate YD
    YD->>YD: getCurrentVotingPower(msg.sender)
    activate YD
    YD->>YD: getVotingPowerForPeriod(BREAD, ...)
    YD->>BREAD: numCheckpoints(account)
    YD->>BREAD: checkpoints(account, index)
    YD->>YD: getVotingPowerForPeriod(BUTTERED_BREAD, ...)
    YD->>BB: numCheckpoints(account)
    YD->>BB: checkpoints(account, index)
    deactivate YD
    
    alt _currentVotingPower < minRequiredVotingPower
        YD-->>User: revert BelowMinRequiredVotingPower
    else _currentVotingPower >= minRequiredVotingPower
        YD->>YD: _castVote(msg.sender, _points, _currentVotingPower)
    end
    deactivate YD
```


1. The function takes an array of `_points` as input, representing the user's vote allocation for each project. These points allow for a dynamic and flexible voting system:

   - Each project can be assigned a number of points, up to `maxPoints`.
   - The total number of points allocated across all projects can vary.
   - The actual voting power distributed to each project is calculated proportionally based on the points allocated.
   - This system allows users to express their preferences with fine-grained control, as they can allocate any number of points (up to `maxPoints`) to each project.
   - For example, if there are two projects and `maxPoints` is 100, a user could vote [100, 50], [1, 2], or any other combination, providing a wide range of possible distributions within the precision of the points system.

2. It first calculates the user's current voting power using `getCurrentVotingPower`.

3. It checks if the user has sufficient voting power to participate. If not, it reverts.

4. If the user has enough voting power, it calls the internal `_castVote` function.

The internal `_castVote` function does the heavy lifting:

```mermaid
sequenceDiagram
    participant YD as YieldDistributor
    participant Storage as Contract Storage

    activate YD
    YD->>YD: Check _points.length == projects.length
    YD->>YD: Calculate _totalPoints
    YD->>YD: Check each point <= maxPoints
    YD->>YD: Check _totalPoints > 0
    
    YD->>Storage: Read accountLastVoted[_account]
    YD->>Storage: Read lastClaimedBlockNumber
    YD->>YD: Calculate _hasVotedInCycle
    
    alt !_hasVotedInCycle
        YD->>Storage: Delete voterDistributions[_account]
        YD->>Storage: Update currentVotes += _votingPower
    end
    
    loop For each project
        alt !_hasVotedInCycle
            YD->>Storage: Initialize _voterDistributions[i] = 0
        else
            YD->>Storage: Update projectDistributions[i]
        end
        
        YD->>YD: Calculate _currentProjectDistribution
        YD->>Storage: Update projectDistributions[i]
        YD->>Storage: Update _voterDistributions[i]
    end
    
    YD->>Storage: Update accountLastVoted[_account]
    YD->>YD: Emit BreadHolderVoted event
    deactivate YD
```

Here's what this function does:

1. It checks if the number of points matches the number of projects.

2. It calculates the total points and ensures they don't exceed the maximum allowed per project.

3. It checks if the user has already voted in this cycle.

4. If it's a new vote in the cycle, it resets the user's previous votes and adds their voting power to the current total votes.

5. For each project:

   - If it's a new vote, it initializes the user's distribution for that project.

   - If it's an update to an existing vote, it subtracts the user's previous distribution.

   - It calculates the new distribution based on the points allocated and the user's voting power.

   - It updates both the overall project distribution and the user's personal distribution.

6. It updates the last voted block number for the user.

7. Finally, it emits an event with the voting details.


Key points:
- The function allows users to update their votes within a cycle.
- It uses precision calculations to ensure accurate distribution of voting power.
- It maintains both global project distributions and individual user distributions.
- The voting power is based on the user's token holdings (both BREAD and BUTTERED_BREAD) over a specific period.

## Voting power 
```mermaid 
sequenceDiagram
    actor User
    participant YD as YieldDistributor
    participant BREAD as BREAD Token
    participant BB as BUTTERED_BREAD Token

    User->>YD: getCurrentVotingPower(account)
    activate YD
    YD->>YD: Calculate period start and end
    YD->>YD: getVotingPowerForPeriod(BREAD, start, end, account)
    activate YD
    YD->>BREAD: numCheckpoints(account)
    alt numCheckpoints == 0
        YD-->>YD: Return 0
    else numCheckpoints > 0
        YD->>BREAD: checkpoints(account, 0)
        alt first checkpoint > end
            YD-->>YD: Return 0
        else first checkpoint <= end
            loop Find latest checkpoint within interval
                YD->>BREAD: checkpoints(account, index)
            end
            YD->>YD: Calculate initial voting power
            loop Process remaining checkpoints
                YD->>BREAD: checkpoints(account, index)
                YD->>YD: Update total voting power
                alt checkpoint <= start
                    YD->>YD: Adjust for interval start
                    YD-->>YD: Break loop
                end
            end
        end
    end
    YD-->>YD: Return BREAD voting power
    deactivate YD
    
    YD->>YD: getVotingPowerForPeriod(BUTTERED_BREAD, start, end, account)
    activate YD
    Note over YD: Same process as BREAD
    YD-->>YD: Return BUTTERED_BREAD voting power
    deactivate YD
    
    YD->>YD: Sum BREAD and BUTTERED_BREAD voting power
    YD-->>User: Return total voting power
    deactivate YD
```
Now, let's break down the getVotingPowerForPeriod function step by step:
1. Input Validation:
    - Check if the start time is before the end time.
    - Ensure the end time is not after the current block.
2. Initial Checkpoint Check:
    - Get the total number of checkpoints for the account.
    - If there are no checkpoints, return 0 voting power.
3. Boundary Checks:
    - If the first checkpoint is after the end of the interval, return 0 voting power.
4. Find Relevant Checkpoints:
    - Start from the latest checkpoint and move backwards.
    - Find the most recent checkpoint that is within or before the end of the interval.
5. Initialize Voting Power Calculation:
    - Set the initial voting power based on the latest relevant checkpoint.
    - Calculate the duration from this checkpoint to the end of the interval.
6. Process Earlier Checkpoints:
    - Iterate through earlier checkpoints, moving backwards in time.
    - For each checkpoint:
        - Calculate the voting power for the sub-interval between checkpoints.
        - Add this to the total voting power.
        - If the checkpoint is before or at the start of the interval:
            - Adjust the voting power to exclude time before the interval start.
            - Break the loop as we've covered the entire interval.
7. Return Total Voting Power:
    - The function returns the accumulated voting power over the specified interval.
Key Points:
    - The function uses a checkpoint system to track voting power changes over time.
    - It calculates voting power as a product of token balance and time held within the specified interval.
    - The calculation is done separately for both BREAD and BUTTERED_BREAD tokens, then summed for the total voting power.
    - This method allows for accurate representation of voting power even with balance changes during the period.
    - This approach ensures that voting power is proportional to both the amount of tokens held and the duration of holding within the specified period, promoting long-term engagement and preventing last-minute large token transfers from disproportionately influencing votes.