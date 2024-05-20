// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Checkpoints} from
    "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";

import {Bread} from "bread-token/src/Bread.sol";

/**
 * @title Breadchain Yield Disburser
 * @notice TODO
 * @author Breadchain Collective
 * @custom:coauthor TODO Ron ENS
 * @custom:coauthor bagelface.eth
 * @custom:coauthor theblockchainsocialist.eth
 * @custom:coauthor kassandra.eth
 * @custom:coauthor TODO lewis/subject026 ENS
 */
contract YieldDisburser is OwnableUpgradeable {
    // @notice The error emitted when the yield for the distribution period has already been claimed
    error AlreadyClaimed();
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
    error BelowMinRequiredVotingPower();
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

    // @notice The minimum time between claims in seconds
    uint48 public minTimeBetweenClaims;
    // @notice The minimum required voting power a user must have to vote
    uint256 public minRequiredVotingPower;
    // @notice The maximum number of votes in a distribution cycle
    uint256 public maxVotes;
    // @notice The minimum amount of $BREAD required to vote
    uint256 public minVotingAmount;
    // @notice The minimum amount of time a user must hold `minVotingAmount`
    uint256 public minHoldingDuration;
    // @notice The maximum number of points a user can allocate to a project
    uint256 public pointsMax;
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
    // @notice The timestamp of the most recent yield distribution
    uint48 public lastClaimedTimestamp;
    // @notice The block number of the most recent yield distribution
    uint256 public lastClaimedBlocknumber;
    // @notice The number of votes cast in the current cycle
    uint256 public currentVotes;
    // @notice The mapping of holders to their vote distributions
    mapping(address => uint256[]) public holderToDistribution;
    // @notice The mapping of holders to their total vote distribution
    mapping(address => uint256) public holderToDistributionTotal;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bread,
        address[] memory _projects,
        uint256 _blockTime,
        uint256 _minVotingAmount,
        uint256 _minHoldingDuration,
        uint256 _maxVotes,
        uint256 _pointsMax,
        uint48 _minTimeBetweenClaims,
        uint48 _lastClaimedTimestamp,
        uint256 _lastClaimedBlocknumber,
        uint256 _precision
    ) public initializer {
        __Ownable_init(msg.sender);

        BREAD = Bread(_bread);
        PRECISION = _precision;

        projects = new address[](_projects.length);
        for (uint256 i; i < _projects.length; ++i) {
            _projects[i] = _projects[i];
        }

        blockTime = _blockTime;
        minVotingAmount = _minVotingAmount;
        minHoldingDuration = _minHoldingDuration * 1 days;
        minRequiredVotingPower = (minVotingAmount * minHoldingDuration * PRECISION) / blockTime;
        maxVotes = _maxVotes;
        pointsMax = _pointsMax;
        minTimeBetweenClaims = _minTimeBetweenClaims * 1 days;
        lastClaimedTimestamp = _lastClaimedTimestamp;
        lastClaimedBlocknumber = _lastClaimedBlocknumber;
    }

    /**
     * @notice Return the number of projects
     * @return uint256 Number of projects
     */
    function getProjectsLength() public view returns (uint256) {
        return projects.length;
    }

    /**
     * @notice Return the current votes cast
     * @return address[] Array of voters
     * @return uint256[][] Array of vote distributions
     */
    function currentVotesCast() public view returns (address[] memory, uint256[][] memory) {
        uint256 _projectsLength = projects.length;
        uint256 _votersLength = voters.length;
        uint256[][] memory _voterDistributions = new uint256[][](_votersLength);

        for (uint256 i; i < _votersLength; ++i) {
            uint256 _vote;
            address _voter = voters[i];
            uint256[] memory _distribution = holderToDistribution[_voter];
            uint256[] memory _votes = new uint256[](_projectsLength);
            uint256 _voterPower = this.getVotingPowerForPeriod(lastClaimedBlocknumber, Time.blockNumber(), _voter);

            for (uint256 j; j < _projectsLength; ++j) {
                _vote = ((_voterPower * _distribution[j] * PRECISION) / holderToDistributionTotal[_voter]) / PRECISION;
                _votes[j] = _vote;
            }

            _voterDistributions[i] = _votes;
        }

        return (voters, _voterDistributions);
    }

    /**
     * @notice Return the current votes cast by a specified holder
     * @param _holder Holder to return the current votes cast of
     * @return uint256[] Distribution of votes cast by the specified holder
     */
    function currentVotesCast(address _holder) public view returns (uint256[] memory) {
        return holderToDistribution[_holder];
    }

    /**
     * @notice Determine if the yield distribution is available
     * @return bool Flag indicating if the yield distribution is able to be claimed
     * @return bytes Function selector used to distribute the yield
     */
    function resolveYieldDistribution() public view returns (bool, bytes memory) {
        uint48 _now = Time.timestamp();
        uint256 _balance = BREAD.balanceOf(address(this)) + BREAD.yieldAccrued();
        if (_balance < projects.length) revert YieldTooLow(_balance);
        if (_now < lastClaimedTimestamp + minTimeBetweenClaims) {
            revert AlreadyClaimed();
        }

        bytes memory _selector = abi.encodePacked(this.distributeYield.selector);
        return (true, _selector);
    }

    /**
     * @notice Return the voting power for a specified user during a specified period of time
     * @param _start Start time of the period to return the voting power for
     * @param _end End time of the period to return the voting power for
     * @param _account User to return the voting power for
     * @return uint256 Voting power of the specified user at the specified period of time
     */
    function getVotingPowerForPeriod(uint256 _start, uint256 _end, address _account) public view returns (uint256) {
        if (_start > _end) revert StartMustBeBeforeEnd();
        if (_end > Time.blockNumber()) revert EndAfterCurrentBlock();

        uint32 _latestCheckpointPosition = BREAD.numCheckpoints(_account);
        if (_latestCheckpointPosition == 0) revert NoCheckpointsForAccount();
        _latestCheckpointPosition--; // Subtract 1 for 0-indexed array
        Checkpoints.Checkpoint208 memory intervalEnd = BREAD.checkpoints(_account, _latestCheckpointPosition);
        uint48 _previousCheckpointKey = intervalEnd._key;
        uint256 _intervalEndValue = intervalEnd._value;
        uint256 _votingPower = _intervalEndValue * (_end - _previousCheckpointKey);
        if (_latestCheckpointPosition == 0) {
            // If the latest checkpoint is exactly at the end of the interval, return the value at that checkpoint
            // Otherwise, return the voting power calculated above (the value at the latest checkpoint multiplied by the length of the interval)
            return _end == _previousCheckpointKey ? _intervalEndValue : _votingPower;
        }
        uint256 _intervalVotingPower;
        uint48 _checkpointKey;
        Checkpoints.Checkpoint208 memory _checkpoint;
        // Iterate through checkpoints in reverse order, starting one before the latest checkpoint because we already handled it above
        for (uint32 i = _latestCheckpointPosition - 1; i >= 0; i--) {
            _checkpoint = BREAD.checkpoints(_account, i);
            _checkpointKey = _checkpoint._key;
            _intervalVotingPower = _checkpoint._value * (_previousCheckpointKey - _checkpointKey);
            if (_checkpointKey <= _start) {
                _votingPower += _intervalVotingPower;
                break;
            } else {
                _votingPower += _intervalVotingPower;
            }
            _previousCheckpointKey = _checkpointKey;
        }

        return _votingPower;
    }

    /**
     * @notice Distribute $BREAD yield to projects based on cast votes
     */
    function distributeYield() public {
        (bool _resolved, /* bytes memory _data */ ) = resolveYieldDistribution();
        if (!_resolved) revert YieldNotResolved();

        BREAD.claimYield(BREAD.yieldAccrued(), address(this));
        uint256 _projectsLength = projects.length;
        (uint256[] memory projectDistributions, uint256 totalVotes) = _commitVotedDistribution();
        if (totalVotes == 0) {
            projectDistributions = new uint256[](_projectsLength);
            for (uint256 i; i < _projectsLength; ++i) {
                projectDistributions[i] = 1;
            }
            totalVotes = _projectsLength;
        }

        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlocknumber = Time.blockNumber();
        currentVotes = 0;

        uint256 _halfBalance = BREAD.balanceOf(address(this)) / 2;
        uint256 _baseSplit = _halfBalance / _projectsLength;
        uint256[] memory _votedSplits = new uint256[](_projectsLength);
        uint256[] memory _percentages = new uint256[](_projectsLength);
        for (uint256 i; i < _projectsLength; ++i) {
            _percentages[i] = projectDistributions[i] / totalVotes;
            _votedSplits[i] = _halfBalance * (projectDistributions[i] * PRECISION / totalVotes) / PRECISION;
            BREAD.transfer(projects[i], _votedSplits[i] + _baseSplit);
        }

        _updateProjects();

        emit YieldDistributed(_votedSplits, _baseSplit, _percentages, projects);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield
     * @param _percentages List of percentages as integers for each project
     */
    function castVote(uint256[] calldata _percentages) public {
        if (
            this.getVotingPowerForPeriod(block.number - (minHoldingDuration / blockTime), block.number, msg.sender)
                < minRequiredVotingPower
        ) revert BelowMinRequiredVotingPower();

        _castVote(msg.sender, _percentages);
    }

    /**
     * @notice Internal function for casting votes for a specified user
     * @param _holder User to cast votes for
     * @param _points Basis points for calculating the amount of votes cast
     */
    function _castVote(address _holder, uint256[] calldata _points) internal {
        uint256 _projectsLength = projects.length;
        if (_points.length != _projectsLength) revert IncorrectNumberOfProjects();

        if (holderToDistribution[_holder].length > 0) {
            delete holderToDistribution[_holder];
        } else {
            voters.push(_holder);
        }

        // TODO This is the same bug that was fixed in a previous version of the contract?
        currentVotes++;

        holderToDistribution[_holder] = _points;
        uint256 _totalPoints;
        for (uint256 i; i < _projectsLength; ++i) {
            if (_points[i] > pointsMax) revert VotePointsTooLarge();
            _totalPoints += _points[i];
        }

        if (_totalPoints == 0) revert ZeroVotePoints();
        holderToDistributionTotal[_holder] = _totalPoints;

        emit BreadHolderVoted(_holder, _points, projects);
    }

    /**
     * @notice Internal function for updating the project list
     */
    function _updateProjects() internal {
        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            address _project = queuedProjectsForAddition[i];
            projects.push(_project);
            emit ProjectAdded(_project);
        }

        delete queuedProjectsForAddition;
        address[] memory _oldProjects = projects;
        delete projects;

        for (uint256 i; i < _oldProjects.length; ++i) {
            address _project = _oldProjects[i];
            bool _remove;
            for (uint256 j; j < queuedProjectsForRemoval.length; ++j) {
                if (_project == queuedProjectsForRemoval[j]) {
                    _remove = true;
                    emit ProjectRemoved(_project);
                    break;
                }
            }
            if (!_remove) {
                projects.push(_project);
            }
        }

        delete queuedProjectsForRemoval;
    }

    /**
     * @notice Internal function for committing the voted distributions for projects
     * @return uint256[] Distribution of votes for projects
     * @return uint256 Total number of votes cast
     */
    function _commitVotedDistribution() internal returns (uint256[] memory, uint256) {
        uint256 _totalVotes;
        uint256[] memory _projectDistributions = new uint256[](projects.length);

        for (uint256 i; i < voters.length; ++i) {
            uint256 _vote;
            address _voter = voters[i];
            uint256 _voterPower = this.getVotingPowerForPeriod(lastClaimedBlocknumber, Time.blockNumber(), _voter);
            uint256[] memory _voterDistribution = holderToDistribution[_voter];

            for (uint256 j; j < _projectDistributions.length; ++j) {
                _vote = _voterPower * _voterDistribution[j] / holderToDistributionTotal[_voter];
                _projectDistributions[j] += _vote;
                _totalVotes += _vote;
            }

            delete holderToDistribution[_voter];
            delete holderToDistributionTotal[_voter];
        }

        return (_projectDistributions, _totalVotes);
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
        bool _found;
        for (uint256 i; i < projects.length; ++i) {
            if (projects[i] == _project) {
                _found = true;
            }
        }
        if (!_found) revert ProjectNotFound();

        for (uint256 i; i < queuedProjectsForRemoval.length; ++i) {
            if (queuedProjectsForRemoval[i] == _project) {
                revert ProjectAlreadyQueued();
            }
        }

        queuedProjectsForRemoval.push(_project);
    }

    /**
     * @notice Set the minimum time between claims in seconds
     * @param _minTimeBetweenClaims New minimum time between claims in seconds
     */
    function setMinTimeBetweenClaims(uint48 _minTimeBetweenClaims) public onlyOwner {
        if (_minTimeBetweenClaims == 0) revert MustBeGreaterThanZero();

        minTimeBetweenClaims = _minTimeBetweenClaims * 1 minutes;
    }

    /**
     * @notice Set the maximum number of votes in a distribution cycle
     * @param _maxVotes New maximum number of votes in a distribution cycle
     */
    function setMaxVotes(uint256 _maxVotes) public onlyOwner {
        maxVotes = _maxVotes;
    }

    /**
     * @notice Set the number of votes cast in the current cycle
     * @dev TODO Remove this function and replace with a test wrapper
     * @param _currentVotes New number of votes cast in the current cycle
     */
    function setCurrentVotes(uint256 _currentVotes) public onlyOwner {
        currentVotes = _currentVotes;
    }

    /**
     * @notice Set a new timestamp of the most recent yield distribution
     * @dev TODO Remove this function and replace with a test wrapper
     * @param _lastClaimedTimestamp New timestamp of the most recent yield distribution
     */
    function setLastClaimedTimestamp(uint48 _lastClaimedTimestamp) public onlyOwner {
        lastClaimedTimestamp = _lastClaimedTimestamp;
    }

    /**
     * @notice Set a new block number of the most recent yield distribution
     * @dev TODO Remove this function and replace with a test wrapper
     * @param _lastClaimedBlocknumber New block number of the most recent yield distribution
     */
    function setLastClaimedBlocknumber(uint256 _lastClaimedBlocknumber) public onlyOwner {
        lastClaimedBlocknumber = _lastClaimedBlocknumber;
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
     * @param _pointsMax New maximum number of points a user can allocate to a project
     */
    function setPointsMax(uint256 _pointsMax) public onlyOwner {
        pointsMax = _pointsMax;
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
     * @notice Set a new block time
     * @dev TODO Why are we setting the block time instead of just measuring based on blocks?
     * @param _blockTime New block time
     */
    function setBlockTime(uint256 _blockTime) public onlyOwner {
        if (_blockTime == 0) revert MustBeGreaterThanZero();

        blockTime = _blockTime;
    }
}
