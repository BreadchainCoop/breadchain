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
    error YieldTooLow();
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
    // @notice The minimum blocks between yield distributions
    uint256 public cycleLength;
    // @notice The minimum required voting power participants must have to vote
    uint256 public minRequiredVotingPower;
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
    // @notice The block number of the last yield distribution
    uint256 public lastClaimedBlockNumber;
    // @notice The number of votes cast in the current cycle
    uint256 public currentVotes;
    // @notice the voting power allocated to projects by voters in the current cycle
    uint256[] public projectDistributions;
    // @notice the last blocknumber a voter cast a vote
    mapping(address => uint256) public holderToLastVoted;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bread,
        uint256 _precision,
        uint256 _blockTime,
        address[] memory _projects,
        uint256 _minRequiredVotingPower,
        uint256 _maxPoints,
        uint256 _cycleLength,
        uint256 _lastClaimedBlockNumber
    ) public initializer {
        __Ownable_init(msg.sender);

        BREAD = Bread(_bread);
        PRECISION = _precision;
        blockTime = _blockTime;
        minRequiredVotingPower = _minRequiredVotingPower;
        maxPoints = _maxPoints;
        cycleLength = _cycleLength;
        lastClaimedBlockNumber = _lastClaimedBlockNumber;

        projectDistributions = new uint256[](_projects.length);
        projects = new address[](_projects.length);
        for (uint256 i; i < _projects.length; ++i) {
            projects[i] = _projects[i];
        }
    }

    /**
     * @notice Returns the current distribution of voting power for projects
     * @return address[] The current participating projects
     * @return uint256[] The current distribution of voting power for projects
     */
    function getCurrentVotingDistribution() public view returns (address[] memory, uint256[] memory) {
        return (projects, projectDistributions);
    }

    /**
     * @notice Return the current voting power of a user
     * @param _account Address of the user to return the voting power for
     * @return uint256 The voting power of the user
     */
    function getCurrentVotingPower(address _account) public view returns (uint256) {
        return this.getVotingPowerForPeriod(lastClaimedBlockNumber - cycleLength, lastClaimedBlockNumber, _account);
    }

    /**
     * @notice Return the voting power for a specified user during a specified period of time
     * @param _start Start time of the period to return the voting power for
     * @param _end End time of the period to return the voting power for
     * @param _account Address of user to return the voting power for
     * @return uint256 Voting power of the specified user at the specified period of time
     */
    function getVotingPowerForPeriod(uint256 _start, uint256 _end, address _account) external view returns (uint256) {
        if (_start >= _end) revert StartMustBeBeforeEnd();
        if (_end > Time.blockNumber()) revert EndAfterCurrentBlock();

        // Initialized as the checkpoint count, but later used to track checkpoint index
        uint32 _currentCheckpointIndex = BREAD.numCheckpoints(_account);
        if (_currentCheckpointIndex == 0) revert NoCheckpointsForAccount();

        // No voting power if the first checkpoint is after the end of the interval
        Checkpoints.Checkpoint208 memory _currentCheckpoint = BREAD.checkpoints(_account, 0);
        if (_currentCheckpoint._key > _end) return 0;

        // Find the latest checkpoint that is within the interval
        do {
            --_currentCheckpointIndex;
            _currentCheckpoint = BREAD.checkpoints(_account, _currentCheckpointIndex);
        } while (_currentCheckpoint._key > _end);

        // Initialize voting power with the latest checkpoint thats within the interval (or nearest to it)
        uint48 _latestKey = _currentCheckpoint._key < _start ? uint48(_start) : _currentCheckpoint._key;
        uint256 _totalVotingPower = _currentCheckpoint._value * (_end - _latestKey);

        for (uint32 i = _currentCheckpointIndex; i > 0;) {
            // Latest checkpoint voting power is calculated when initializing `_totalVotingPower`, so we pre-decrement the index here
            _currentCheckpoint = BREAD.checkpoints(_account, --i);

            // Add voting power for the sub-interval to the total
            _totalVotingPower += _currentCheckpoint._value * (_latestKey - _currentCheckpoint._key);

            // At the start of the interval, deduct voting power accrued before the interval and return the total
            if (_currentCheckpoint._key <= _start) {
                _totalVotingPower -= _currentCheckpoint._value * (_start - _currentCheckpoint._key);
                break;
            }

            _latestKey = _currentCheckpoint._key;
        }

        return _totalVotingPower;
    }

    /**
     * @notice Determine if the yield distribution is available
     * @dev Resolver function required for Powerpool job registration. For more details, see the Powerpool documentation:
     * @dev https://docs.powerpool.finance/powerpool-and-poweragent-network/power-agent/user-guides-and-instructions/i-want-to-automate-my-tasks/job-registration-guide#resolver-job
     * @return bool Flag indicating if the yield is able to be distributed
     * @return bytes Calldata used by the resolver to distribute the yield
     */
    function resolveYieldDistribution() public view returns (bool, bytes memory) {
        if (
            currentVotes == 0 || // No votes were cast
            block.number < lastClaimedBlockNumber + cycleLength || // Already claimed this cycle
            BREAD.balanceOf(address(this)) + BREAD.yieldAccrued() < projects.length // Yield is insufficient
        ) {
            return (false, new bytes(0));
        } else {
            return (true, abi.encodePacked(this.distributeYield.selector));
        }
    }

    /**
     * @notice Distribute $BREAD yield to projects based on cast votes
     */
    function distributeYield() public {
        (bool _resolved,) = resolveYieldDistribution();
        if (!_resolved) revert YieldNotResolved();

        BREAD.claimYield(BREAD.yieldAccrued(), address(this));
        uint256 projectsLength = projects.length;
        lastClaimedBlockNumber = Time.blockNumber();
        uint256 halfBalance = BREAD.balanceOf(address(this)) / 2;
        uint256 baseSplit = halfBalance / projectsLength;
        uint256 percentageOfTotalVote;
        uint256 votedSplit;
        uint256[] memory votedSplits = new uint256[](projectsLength);
        uint256[] memory percentages = new uint256[](projectsLength);

        for (uint256 i; i < projectsLength; ++i) {
            percentageOfTotalVote = ((projectDistributions[i] * PRECISION) / currentVotes) / PRECISION;
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
        if (holderToLastVoted[msg.sender] > lastClaimedBlockNumber) revert AlreadyVotedInCycle();

        uint256 _currentVotingPower = getCurrentVotingPower(msg.sender);

        if (_currentVotingPower < minRequiredVotingPower) revert BelowMinRequiredVotingPower();

        _castVote(msg.sender, _percentages, _currentVotingPower);
    }

    /**
     * @notice Internal function for casting votes for a specified user
     * @param _account Address of user to cast votes for
     * @param _points Basis points for calculating the amount of votes cast
     */
    function _castVote(address _account, uint256[] calldata _points, uint256 _votingPower) internal {
        if (_points.length != projects.length) revert IncorrectNumberOfProjects();

        uint256 _totalPoints;

        for (uint256 i; i < _points.length; ++i) {
            if (_points[i] > maxPoints) revert VotePointsTooLarge();
            _totalPoints += _points[i];
        }

        if (_totalPoints == 0) revert ZeroVotePoints();

        for (uint256 i; i < _points.length; ++i) {
            projectDistributions[i] += ((_points[i] * _votingPower * PRECISION) / _totalPoints) / PRECISION;
        }

        holderToLastVoted[_account] = block.number;
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
     * @notice Set a new minimum required voting power a user must have to vote
     * @param _minRequiredVotingPower New minimum required voting power a user must have to vote
     */
    function setMinRequiredVotingPower(uint256 _minRequiredVotingPower) public onlyOwner {
        if (_minRequiredVotingPower == 0) revert MustBeGreaterThanZero();

        minRequiredVotingPower = _minRequiredVotingPower;
    }

    /**
     * @notice Set a new maximum number of points a user can allocate to a project
     * @param _maxPoints New maximum number of points a user can allocate to a project
     */
    function setMaxPoints(uint256 _maxPoints) public onlyOwner {
        if (_maxPoints == 0) revert MustBeGreaterThanZero();

        maxPoints = _maxPoints;
    }

    /**
     * @notice Set a new cycle length in blocks
     * @param _cycleLength New cycle length in blocks
     */
    function setCycleLength(uint256 _cycleLength) public onlyOwner {
        if (_cycleLength == 0) revert MustBeGreaterThanZero();

        cycleLength = _cycleLength;
    }
}
