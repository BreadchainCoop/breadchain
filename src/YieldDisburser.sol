// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Checkpoints} from
    "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";
import {Bread} from "bread-token/src/Bread.sol";

/**
 * @title Breadchain Yield Disburser
 * @notice Disburse $BREAD yield to eligible member projects based on a voted distribution
 * @author Breadchain Collective
 * @custom:coauthor @RonTuretzky
 * @custom:coauthor bagelface.eth
 * @custom:coauthor prosalads.eth
 * @custom:coauthor kassandra.eth
 * @custom:coauthor theblockchainsocialist.eth
 */
contract YieldDisburser is OwnableUpgradeable {
    // @notice The error emitted when the yield for the distribution period has already been claimed
    error AlreadyClaimed();
    // @notice the error emitted when attemping to vote in the same cycle twice
    error AlreadyVotedInCycle();
    // @notice The error emitted when attempting to calculate voting power for a period that has not yet ended
    error EndAfterCurrentBlock();
    // @notice The error emitted when attempting to vote with an incorrect number of projects
    error IncorrectNumberOfProjects();
    // @notice The error emitted when attempting to instantiate a variable with a zero value
    error MustBeGreaterThanZero();
    // @notice The error emitted when attempting to vote with a point value greater than `pointsMax`
    error VotePointsTooLarge();
    // @notice The error emitted when a voter has never held $BREAD before
    error NoCheckpointsForAccount();
    // @notice The error emitted when attempting to distribute yield without any votes casted
    error NoVotesCasted();
    // @notice The error emitted when attempting to calculate voting power for a period with a start block greater than the end block
    error StartMustBeBeforeEnd();
    // @notice The error emitted when attempting to distribute yield when access conditions are not met
    error YieldNotResolved();
    // @notice The error emitted when attempting to distribute yield with a balance less than the number of projects
    error YieldTooLow(uint256);
    // @notice The error emitted when attempting to remove a project that is not in the `projects` array
    error ProjectNotFound();
    // @notice The error emitted when attempting to add or remove a project that is already queued for addition or removal
    error ProjectAlreadyQueued();
    // @notice The error emitted when attempting to add a project that is already in the `projects` array
    error AlreadyMemberProject();
    // @notice The error emitted when a user attempts to vote without the minimum required voting power
    error BelowMinRequiredVotingPower(uint256 minimum);
    // @notice The error emitted if a user with zero points attempts to cast votes
    error ZeroVotePoints();

    // @notice The event emitted when a project is added as eligibile for yield distribution
    event ProjectAdded(address project);
    // @notice The event emitted when a project is removed as eligibile for yield distribution
    event ProjectRemoved(address project);
    // @notice The event emitted when yield is distributed
    event YieldDistributed(uint256[] votedYield, uint256 baseYield, uint256[] percentage, address[] project);
    // @notice The event emitted when a holder casts a vote
    event BreadHolderVoted(address indexed holder, uint256[] percentages, address[] projects);

    // @notice The address of the $BREAD token contract
    Bread public BREAD;
    // @notice The precision to use for calculations
    uint256 public PRECISION;
    // @notice The minimum blocks between yield distributions
    uint256 public cycleLength;
    // @notice The minimum required voting power participants must have to vote
    uint256 public minRequiredVotingPower;
    // @notice The minimum amount of bread required to vote
    uint256 public minVotingAmount;
    // @notice The minimum amount of time a user must hold minVotingAmount
    uint256 public minHoldingDuration;
    // @notice The maximum number of points a user can allocate to a project
    uint256 public maxPoints;
    // @notice The block time of the EVM in seconds
    uint256 public blockTime;

    // @notice The array of projects eligible for yield distribution
    address[] public projects;
    // @notice The array of projects queued for addition
    address[] public queuedProjectsForAddition;
    // @notice The array of projects queued for removal
    address[] public queuedProjectsForRemoval;
    // @notice The array of voters who have cast votes in the current cycle
    address[] public voters;
    // @notice The timestamp of the last yield distribution
    uint48 public lastClaimedTimestamp;
    // @notice The block number of the last yield distribution
    uint256 public lastClaimedBlockNumber;
    // @notice The number of votes cast in the current cycle
    uint256 public currentVotes;
    // @notice the voting power allocated to projects by voters in the current cycle
    uint256[] public projectDistributions;
    // @notice the last timestamp a voter cast a vote
    mapping(address => uint48) public holderToLastVoted;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address breadAddress,
        address[] memory _projects,
        uint256 _blockTime,
        uint256 _minVotingAmount,
        uint256 _minHoldingDuration,
        uint256 _maxPoints,
        uint256 _cycleLength,
        uint48 _lastClaimedTimestamp,
        uint256 _lastClaimedBlockNumber,
        uint256 _precision
    ) public initializer {
        __Ownable_init(msg.sender);
        BREAD = Bread(breadAddress);
        uint256 projectLength = _projects.length;
        projects = new address[](projectLength);
        for (uint256 i; i < projectLength; ++i) {
            projects[i] = _projects[i];
        }
        projectDistributions = new uint256[](projectLength);
        blockTime = _blockTime;
        PRECISION = _precision;
        minVotingAmount = _minVotingAmount;
        minHoldingDuration = _minHoldingDuration * 1 days; // must hold for atleast _minVotingHoldingDuration  days
        minRequiredVotingPower = ((minVotingAmount * minHoldingDuration) * PRECISION) / blockTime; // Holding minVotingAmount bread for minVotingHoldingDuration days , assuming a blockTime second block time
        maxPoints = _maxPoints;
        cycleLength = (_cycleLength * 1 days) / blockTime;
        lastClaimedTimestamp = _lastClaimedTimestamp;
        lastClaimedBlockNumber = _lastClaimedBlockNumber;
    }

    /**
     * @notice Return the number of projects
     * @return uint256 Number of projects
     */
    function getProjectsLength() public view returns (uint256) {
        return projects.length;
    }

    /**
     * @notice Determine if the yield distribution is available
     * @return bool Flag indicating if the yield distribution is able to be claimed
     * @return bytes Function selector used to distribute the yield
     */
    function resolveYieldDistribution() public view returns (bool, bytes memory) {
        if (currentVotes == 0) revert NoVotesCasted();
        uint256 balance = (BREAD.balanceOf(address(this)) + BREAD.yieldAccrued());
        if (balance < projects.length) revert YieldTooLow(balance);
        if (block.number < lastClaimedTimestamp + cycleLength) {
            revert AlreadyClaimed();
        }
        bytes memory ret = abi.encodePacked(this.distributeYield.selector);
        return (true, ret);
    }

    /**
     * @notice Return the voting power for a specified user during a specified period of time
     * @param _start Start time of the period to return the voting power for
     * @param _end End time of the period to return the voting power for
     * @param _account Address of user to return the voting power for
     * @return uint256 Voting power of the specified user at the specified period of time
     */
    function getVotingPowerForPeriod(uint256 _start, uint256 _end, address _account) external view returns (uint256) {
        // Checking if the start time is before the end time, if the end time is after the current
        // block and if the user has ever held $BREAD comparing the first mint to the end of the interval

        if (_start > _end) revert StartMustBeBeforeEnd();
        if (_end > Time.blockNumber()) revert EndAfterCurrentBlock();
        uint32 latestCheckpointPos = BREAD.numCheckpoints(_account);
        if (latestCheckpointPos == 0) revert NoCheckpointsForAccount();
        if (BREAD.checkpoints(_account, 0)._key > _end) return 0;

        // Starting to filter out irrelevant checkpoints that are not in the interval

        uint256 intervalEndValue;
        Checkpoints.Checkpoint208 memory intervalEnd;
        uint48 prevKey;

        // Find the latest checkpoint that is within the interval
        while (true) {
            latestCheckpointPos--;
            intervalEnd = BREAD.checkpoints(_account, latestCheckpointPos);
            prevKey = intervalEnd._key;
            if (prevKey <= _end) {
                break;
            }
        }

        // We are now at a position where the checkpoint is within the interval
        // Calculate the voting power for the interval
        intervalEndValue = intervalEnd._value;
        uint256 votingPowerTotal = intervalEndValue * (_end - prevKey);
        // If there's a single checkpoint in the interval, return the voting power from the interval (including the edge case where the interval ends at the first checkpoint)
        if (latestCheckpointPos == 0) {
            return _end == prevKey ? intervalEndValue : votingPowerTotal;
        }
        uint48 key;
        uint256 value;
        Checkpoints.Checkpoint208 memory checkpoint;
        // Iterate through checkpoints in reverse order, only considering checkpoints within the interval
        for (uint32 i = latestCheckpointPos - 1; i >= 0; i--) {
            // Getting current checkpoint and its key and value
            checkpoint = BREAD.checkpoints(_account, i);
            key = checkpoint._key;
            value = checkpoint._value;

            // Adding the voting power for the sub interval to the total
            votingPowerTotal += value * (prevKey - key);

            // If we reached the start of the interval, deduct the voting power accured before the interval and return the total
            if (key <= _start) {
                votingPowerTotal -= value * (_start - key);
                break;
            }

            // Otherwise update the previous key and continue to the next checkpoint
            prevKey = key;
        }
        return votingPowerTotal;
    }

    /**
     * @notice Distribute $BREAD yield to projects based on cast votes
     */
    function distributeYield() public {
        (bool _resolved, /* bytes memory _data */ ) = resolveYieldDistribution();
        if (!_resolved) revert YieldNotResolved();

        BREAD.claimYield(BREAD.yieldAccrued(), address(this));
        uint256 projectsLength = projects.length;

        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlockNumber = Time.blockNumber();
        uint256 halfBalance = BREAD.balanceOf(address(this)) / 2;
        uint256 baseSplit = halfBalance / projectsLength;
        uint256 percentageOfTotalVote;
        uint256 votedSplit;
        uint256[] memory votedSplits = new uint256[](projectsLength);
        uint256[] memory percentages = new uint256[](projectsLength);
        for (uint256 i; i < projectsLength; ++i) {
            percentageOfTotalVote = projectDistributions[i] / currentVotes;
            votedSplit = halfBalance * (projectDistributions[i] * PRECISION / currentVotes) / PRECISION;
            BREAD.transfer(projects[i], votedSplit + baseSplit);
            votedSplits[i] = votedSplit;
            percentages[i] = percentageOfTotalVote;
        }
        _updateBreadchainProjects();
        delete currentVotes;
        delete projectDistributions;
        projectDistributions = new uint256[](projects.length);
        emit YieldDistributed(votedSplits, baseSplit, percentages, projects);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield
     * @param _percentages List of percentages as integers for each project
     */
    function castVote(uint256[] calldata _percentages) public {
        if (holderToLastVoted[msg.sender] > lastClaimedTimestamp) revert AlreadyVotedInCycle();
        uint256 votingPower =
            this.getVotingPowerForPeriod(lastClaimedBlockNumber - cycleLength, lastClaimedBlockNumber, msg.sender);
        if (votingPower < minRequiredVotingPower) revert BelowMinRequiredVotingPower(minRequiredVotingPower);
        _castVote(msg.sender, _percentages, votingPower);
    }

    /**
     * @notice Internal function for casting votes for a specified user
     * @param _account Address of user to cast votes for
     * @param _points Basis points for calculating the amount of votes cast
     */
    function _castVote(address _account, uint256[] calldata _points, uint256 _votingPower) internal {
        uint256 length = projects.length;
        if (_points.length != length) revert IncorrectNumberOfProjects();

        uint256 total;
        for (uint256 i; i < length; ++i) {
            if (_points[i] > maxPoints) revert VotePointsTooLarge();
            total += _points[i];
        }
        if (total == 0) revert ZeroVotePoints();
        for (uint256 i; i < length; ++i) {
            projectDistributions[i] += ((_points[i] * _votingPower * PRECISION) / total) / PRECISION;
        }
        holderToLastVoted[_account] = Time.timestamp();
        currentVotes += _votingPower;
        emit BreadHolderVoted(_account, _points, projects);
    }

    /**
     * @notice Internal function for updating the project list
     */
    function _updateBreadchainProjects() internal {
        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            address project = queuedProjectsForAddition[i];
            projects.push(project);
            emit ProjectAdded(project);
        }
        delete queuedProjectsForAddition;
        address[] memory oldProjects = projects;
        delete projects;
        for (uint256 i; i < oldProjects.length; ++i) {
            address project = oldProjects[i];
            bool remove;
            for (uint256 j; j < queuedProjectsForRemoval.length; ++j) {
                if (project == queuedProjectsForRemoval[j]) {
                    remove = true;
                    emit ProjectRemoved(project);
                    break;
                }
            }
            if (!remove) {
                projects.push(project);
            }
        }
        delete queuedProjectsForRemoval;
    }

    /**
     * @notice Queue a new project to be added to the project list
     * @param _project Project to be added to the project list
     */
    function queueProjectAddition(address _project) public onlyOwner {
        for (uint256 i; i < projects.length; ++i) {
            if (projects[i] == _project) {
                revert AlreadyMemberProject();
            }
        }
        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            if (queuedProjectsForAddition[i] == _project) {
                revert ProjectAlreadyQueued();
            }
        }
        queuedProjectsForAddition.push(_project);
    }

    /**
     * @notice Queue an existing project to be removed from the project list
     * @param _project Project to be removed from the project list
     */
    function queueProjectRemoval(address _project) public onlyOwner {
        bool found = false;
        for (uint256 i; i < projects.length; ++i) {
            if (projects[i] == _project) {
                found = true;
            }
        }
        if (!found) revert ProjectNotFound();
        for (uint256 i; i < queuedProjectsForRemoval.length; ++i) {
            if (queuedProjectsForRemoval[i] == _project) {
                revert ProjectAlreadyQueued();
            }
        }
        queuedProjectsForRemoval.push(_project);
    }

    /**
     * @notice Set a new minimum amount of time to hold the minimum voting amount
     * @param _minHoldingDuration New minimum amount of time to hold the minimum voting amount
     */
    function setMinHoldingDuration(uint256 _minHoldingDuration) public onlyOwner {
        minHoldingDuration = _minHoldingDuration;
    }

    /**
     * @notice Set a new minimum voting amount
     * @param _minVotingAmount New minimum voting amount
     */
    function setMinVotingAmount(uint256 _minVotingAmount) public onlyOwner {
        minVotingAmount = _minVotingAmount;
    }

    /**
     * @notice Set a new minimum required voting power a user must have to vote
     * @param _minRequiredVotingPower New minimum required voting power a user must have to vote
     */
    function setMinRequiredVotingPower(uint256 _minRequiredVotingPower) public onlyOwner {
        minRequiredVotingPower = _minRequiredVotingPower;
    }

    /**
     * @notice Set a new maximum number of points a user can allocate to a project
     * @param _maxPoints New maximum number of points a user can allocate to a project
     */
    function setMaxPoints(uint256 _maxPoints) public onlyOwner {
        maxPoints = _maxPoints;
    }

    /**
     * @notice Set a new block time
     * @param _blockTime New block time
     */
    function setBlockTime(uint256 _blockTime) public onlyOwner {
        if (_blockTime == 0) revert MustBeGreaterThanZero();

        blockTime = _blockTime;
    }
    
    /**
     * @notice Set a new cycle length
     * @param _cycleLength New cycle length
     */
    function setCycleLength(uint256 _cycleLength) public onlyOwner {
        if (_cycleLength == 0) revert MustBeGreaterThanZero();

        cycleLength = _cycleLength;
    }
}
