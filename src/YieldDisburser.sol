// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Checkpoints} from
    "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";
import {Bread} from "../lib/bread-token-v2/src/Bread.sol";

error AlreadyClaimed();

contract YieldDisburser is OwnableUpgradeable {
    // Storage of intristic , assumed constants
    // @notice The address of the Bread token contract
    Bread public breadToken;
    // @notice The block time of the evm in seconds
    uint256 public blockTime;
    // @notice The precision to use for calculations
    uint256 public PRECISION;

    // Storage of configuration variables
    // @notice The minimum blocks between yield distributions
    uint256 public cycleLength;
    // @notice The minimum required voting power participants must have to vote
    uint256 public minRequiredVotingPower;
    // @notice The minimum amount of bread required to vote
    uint256 public minVotingAmount;
    // @notice The minimum amount of time a user must hold minVotingAmount
    uint256 public minVotingHoldingDuration;
    // @notice The maximum number of points a user can allocate to a project
    uint256 public pointsMax;

    // Storage of state variables
    // @notice The array of breadchain projects eligible for yield distribution
    address[] public breadchainProjects;
    // @notice The array of projects queued for addition
    address[] public queuedProjectsForAddition;
    // @notice The array of projects queued for removal
    address[] public queuedProjectsForRemoval;
    // @notice The array of voters who have cast votes in the current cycle
    address[] public breadchainVoters;
    // @notice The timestamp of the last yield distribution
    uint48 public lastClaimedTimestamp;
    // @notice The block number of the last yield distribution
    uint256 public lastClaimedBlocknumber;
    // @notice The number of votes cast in the current cycle
    uint256 public totalVotes;
    // @notice the last timestamp a voter cast a vote
    mapping(address => uint48) public holderToLastVoted;
    // @notice the voting power allocated to projects by voters in the current cycle
    uint256[] public projectDistributions;

    // @notice The event emitted when a project is added as eligibile for yield distribution
    event ProjectAdded(address project);
    // @notice The event emitted when a project is removed as eligibile for yield distribution
    event ProjectRemoved(address project);
    // @notice The event emitted when yield is distributed
    event YieldDistributed(uint256[] votedYield, uint256 baseYield, uint256[] percentage, address[] project);
    // @notice The event emitted when a holder casts a vote
    event BreadHolderVoted(address indexed holder, uint256[] percentages, address[] projects);

    // @notice the error emitted when attemping to vote in the same cycle twice
    error AlreadyVotedInCycle();
    // @notice The error emitted when attempting to calculate voting power for a period that has not yet ended
    error EndAfterCurrentBlock();
    // @notice The error emitted when attempting to vote with an incorrect number of projects
    error IncorrectNumberOfProjects();
    // @notice The error emitted when attempting to instantiate a variable with a zero value
    error MustBeGreaterThanZero();
    // @notice The error emitted when attempting to vote with a point value greater than pointsMax
    error VotePointsTooLarge();
    // @notice The error emitted when a voter has never held bread before
    error NoCheckpointsForAccount();
    // @notice The error emitted when attempting to calculate voting power for a period with a start block greater than the end block
    error StartMustBeBeforeEnd();
    // @notice The error emitted when attempting to distribute yield when access conditions are not met
    error YieldNotResolved();
    // @notice The error emitted when attempting to distribute yield with a balance less than the number of projects
    error YieldTooLow(uint256);
    // @notice The error emitted when attempting to remove a project that is not in the breadchainProjects array
    error ProjectNotFound();
    // @notice The error emitted when attempting to add or remove a project that is already queued for addition or removal
    error ProjectAlreadyQueued();
    // @notice The error emitted when attempting to add a project that is already in the breadchainProjects array
    error AlreadyMemberProject();
    // @notice The error emitted when a user attempts to vote without the minimum required voting power
    error BelowMinRequiredVotingPower();
    error ZeroVotePoints();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address breadAddress,
        address[] memory _breadchainProjects,
        uint256 _blockTime,
        uint256 _minVotingAmount,
        uint256 _minVotingHoldingDuration,
        uint256 _pointsMax,
        uint256 _cycleLength,
        uint48 _lastClaimedTimestamp,
        uint256 _lastClaimedBlocknumber,
        uint256 _precision
    ) public initializer {
        breadToken = Bread(breadAddress);
        breadchainProjects = new address[](_breadchainProjects.length);
        for (uint256 i; i < _breadchainProjects.length; ++i) {
            breadchainProjects[i] = _breadchainProjects[i];
        }
        blockTime = _blockTime;
        PRECISION = _precision;
        minVotingAmount = _minVotingAmount;
        minVotingHoldingDuration = _minVotingHoldingDuration * 1 days; // must hold for atleast _minVotingHoldingDuration  days
        minRequiredVotingPower = ((minVotingAmount * minVotingHoldingDuration) * PRECISION) / blockTime; // Holding minVotingAmount bread for minVotingHoldingDuration days , assuming a blockTime second block time
        pointsMax = _pointsMax;
        cycleLength = _cycleLength;
        lastClaimedTimestamp = _lastClaimedTimestamp;
        lastClaimedBlocknumber = _lastClaimedBlocknumber;
        __Ownable_init(msg.sender);
    }

    /**
     *
     *          Public Functions         *
     *
     */
    function distributeYield() public {
        (bool _resolved, /* bytes memory _data */ ) = resolveYieldDistribution();
        if (!_resolved) revert YieldNotResolved();

        breadToken.claimYield(breadToken.yieldAccrued(), address(this));
        uint256 breadchainProjectsLength = breadchainProjects.length;

        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlocknumber = Time.blockNumber();
        // logic here to create projectDistributions

        uint256 halfBalance = breadToken.balanceOf(address(this)) / 2;
        uint256 baseSplit = halfBalance / breadchainProjectsLength;
        uint256 percentageOfTotalVote;
        uint256 votedSplit;
        uint256[] memory votedSplits = new uint256[](breadchainProjectsLength);
        uint256[] memory percentages = new uint256[](breadchainProjectsLength);
        for (uint256 i; i < breadchainProjectsLength; ++i) {
            percentageOfTotalVote = projectDistributions[i] / totalVotes;
            votedSplit = halfBalance * (projectDistributions[i] * PRECISION / totalVotes) / PRECISION;
            breadToken.transfer(breadchainProjects[i], votedSplit + baseSplit);
            votedSplits[i] = votedSplit;
            percentages[i] = percentageOfTotalVote;
        }
        _updateBreadchainProjects();
        delete totalVotes;
        delete projectDistributions;
        emit YieldDistributed(votedSplits, baseSplit, percentages, breadchainProjects);
    }

    function castVote(uint256[] calldata percentages) public {
        if (holderToLastVoted[msg.sender] > lastClaimedTimestamp) revert AlreadyVotedInCycle();
        uint256 votingPower =
            this.getVotingPowerForPeriod(lastClaimedBlocknumber - cycleLength, lastClaimedBlocknumber, msg.sender);
        if (votingPower < minRequiredVotingPower) revert BelowMinRequiredVotingPower();
        _castVote(percentages, msg.sender, votingPower);
    }

    /**
     *
     *           View Functions          *
     *
     */
    function resolveYieldDistribution() public view returns (bool, bytes memory) {
        uint256 balance = (breadToken.balanceOf(address(this)) + breadToken.yieldAccrued());
        if (balance < breadchainProjects.length) revert YieldTooLow(balance);
        if (block.number < lastClaimedTimestamp + cycleLength) {
            revert AlreadyClaimed();
        }
        bytes memory ret = abi.encodePacked(this.distributeYield.selector);
        return (true, ret);
    }

    function getVotingPowerForPeriod(uint256 start, uint256 end, address account) external view returns (uint256) {
        if (start > end) revert StartMustBeBeforeEnd();
        if (end > Time.blockNumber()) revert EndAfterCurrentBlock();
        uint32 latestCheckpointPos = breadToken.numCheckpoints(account);
        if (latestCheckpointPos == 0) revert NoCheckpointsForAccount();
        latestCheckpointPos--; // Subtract 1 for 0-indexed array
        Checkpoints.Checkpoint208 memory intervalEnd = breadToken.checkpoints(account, latestCheckpointPos);
        uint48 prevKey = intervalEnd._key;
        uint256 intervalEndValue = intervalEnd._value;
        uint256 votingPower = intervalEndValue * ((end) - prevKey);
        if (latestCheckpointPos == 0) {
            if (end == prevKey) {
                // If the latest checkpoint is exactly at the end of the interval, return the value at that checkpoint
                return intervalEndValue;
            } else {
                return votingPower; // Otherwise, return the voting power calculated above, which is the value at the latest checkpoint multiplied by the length of the interval
            }
        }
        uint48 key;
        uint256 value;
        Checkpoints.Checkpoint208 memory checkpoint;
        // Iterate through checkpoints in reverse order, starting one before the latest checkpoint because we already handled it above
        for (uint32 i = latestCheckpointPos - 1; i >= 0; i--) {
            checkpoint = breadToken.checkpoints(account, i);
            key = checkpoint._key;
            value = checkpoint._value;
            if (key <= start) {
                votingPower += value * (prevKey - start);
                break;
            } else {
                votingPower += value * (prevKey - key);
            }
            prevKey = key;
        }
        return votingPower;
    }

    /**
     *
     *         Internal Functions        *
     *
     */
    function _castVote(uint256[] calldata points, address holder, uint256 votingPower) internal {
        uint256 length = breadchainProjects.length;
        if (points.length != length) revert IncorrectNumberOfProjects();

        uint256 total;
        for (uint256 i; i < length; ++i) {
            if (points[i] > pointsMax) revert VotePointsTooLarge();
            total += points[i];
        }
        if (total == 0) revert ZeroVotePoints();
        for (uint256 i; i < length; ++i) {
            projectDistributions[i] += ((points[i] * votingPower * PRECISION) / total) / PRECISION;
        }
        holderToLastVoted[holder] = Time.timestamp();
        totalVotes += votingPower;
        emit BreadHolderVoted(holder, points, breadchainProjects);
    }

    function _updateBreadchainProjects() internal {
        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            address project = queuedProjectsForAddition[i];
            breadchainProjects.push(project);
            emit ProjectAdded(project);
        }
        delete queuedProjectsForAddition;
        address[] memory oldBreadChainProjects = breadchainProjects;
        delete breadchainProjects;
        for (uint256 i; i < oldBreadChainProjects.length; ++i) {
            address project = oldBreadChainProjects[i];
            bool remove;
            for (uint256 j; j < queuedProjectsForRemoval.length; ++j) {
                if (project == queuedProjectsForRemoval[j]) {
                    remove = true;
                    emit ProjectRemoved(project);
                    break;
                }
            }
            if (!remove) {
                breadchainProjects.push(project);
            }
        }
        delete queuedProjectsForRemoval;
    }

    /**
     *
     *        Only Owner Functions       *
     *
     */
    function setlastClaimedTimestamp(uint48 _lastClaimedTimestamp) public onlyOwner {
        lastClaimedTimestamp = _lastClaimedTimestamp;
    }

    function setTotalVotes(uint256 _totalVotes) public onlyOwner {
        totalVotes = _totalVotes;
    }

    function setLastClaimedBlocknumber(uint256 _lastClaimedBlocknumber) public onlyOwner {
        lastClaimedBlocknumber = _lastClaimedBlocknumber;
    }

    function queueProjectAddition(address project) public onlyOwner {
        for (uint256 i; i < breadchainProjects.length; ++i) {
            if (breadchainProjects[i] == project) {
                revert AlreadyMemberProject();
            }
        }
        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            if (queuedProjectsForAddition[i] == project) {
                revert ProjectAlreadyQueued();
            }
        }
        queuedProjectsForAddition.push(project);
    }

    function setMinRequiredVotingPower(uint256 _minRequiredVotingPower) public onlyOwner {
        minRequiredVotingPower = _minRequiredVotingPower;
    }

    function setPointsMax(uint256 _pointsMax) public onlyOwner {
        pointsMax = _pointsMax;
    }

    function queueProjectRemoval(address project) public onlyOwner {
        bool found = false;
        for (uint256 i; i < breadchainProjects.length; ++i) {
            if (breadchainProjects[i] == project) {
                found = true;
            }
        }
        if (!found) revert ProjectNotFound();
        for (uint256 i; i < queuedProjectsForRemoval.length; ++i) {
            if (queuedProjectsForRemoval[i] == project) {
                revert ProjectAlreadyQueued();
            }
        }
        queuedProjectsForRemoval.push(project);
    }

    function getBreadchainProjectsLength() public view returns (uint256) {
        return breadchainProjects.length;
    }

    function setMinVotingHoldingDuration(uint256 _minVotingHoldingDuration) public onlyOwner {
        minVotingHoldingDuration = _minVotingHoldingDuration;
    }

    function setMinVotingAmount(uint256 _minVotingAmount) public onlyOwner {
        minVotingAmount = _minVotingAmount;
    }

    function setBlockTime(uint256 _blockTime) public onlyOwner {
        if (_blockTime == 0) revert MustBeGreaterThanZero();
        blockTime = _blockTime;
    }

    function setCycleLength(uint256 _cycleLength) public onlyOwner {
        cycleLength = _cycleLength;
    }
}
