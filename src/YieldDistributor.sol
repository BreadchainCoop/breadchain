// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {GasKillerSDK} from "gas-killer/flat/GasKillerSDK.flat.sol";

import {IYieldDistributor} from "src/interfaces/IYieldDistributor.sol";
import {IBread} from "src/interfaces/IBread.sol";
import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";
import {VotingMultipliers} from "src/VotingMultipliers.sol";

/**
 * @title Breadchain Yield Distributor
 * @notice Distribute $BREAD yield to eligible member projects based on a voted distribution
 * @author Breadchain Collective
 * @custom:coauthor postcapitalistcrypto.eth
 * @custom:coauthor bagelface.eth
 * @custom:coauthor prosalads.eth
 * @custom:coauthor kassandra.eth
 * @custom:coauthor theblockchainsocialist.eth
 * @custom:coauthor postcapitalistcrypto.eth
 * @custom:coauthor github.com/daopunk
 * @custom:coauthor github.com/secbajor
 * @custom:coauthor github.com/hudsonhrh
 * @custom:coauthor github.com/Tranquil-Flow
 */
contract YieldDistributor is IYieldDistributor, Ownable2StepUpgradeable, VotingMultipliers, GasKillerSDK {
    /// @notice The address of the $BREAD token contract
    IBread public BREAD;
    /// @notice The precision to use for calculations
    uint256 public PRECISION;
    /// @notice The minimum number of blocks between yield distributions
    uint256 public cycleLength;
    /// @notice The maximum number of points a voter can allocate to a project
    uint256 public maxPoints;
    /// @notice The minimum required voting power participants must have to cast a vote
    uint256 public minRequiredVotingPower;
    /// @notice The block number of the last yield distribution
    uint256 public lastClaimedBlockNumber;
    /// @notice The total voting power accumulated in the current cycle
    uint256 public currentVotes;
    /// @notice Array of projects eligible for yield distribution
    address[] public projects;
    /// @notice Array of projects queued for addition to the next cycle
    address[] public queuedProjectsForAddition;
    /// @notice Array of projects queued for removal from the next cycle
    address[] public queuedProjectsForRemoval;
    /// @notice The voting power allocated to each project by voters in the current cycle
    uint256[] public projectDistributions;
    /// @notice The last block number in which a specified account cast a vote
    mapping(address => uint256) public accountLastVoted;
    /// @notice The voting power allocated to each project by a specific voter in the current cycle
    mapping(address => uint256[]) voterDistributions;
    /// @notice How much of the yield is divided equally among projects
    uint256 public yieldFixedSplitDivisor;
    /// @notice The address of the `ButteredBread` token contract
    IERC20Votes public BUTTERED_BREAD;
    /// @notice The block number before the last yield distribution
    uint256 public previousCycleStartingBlock;
    /// @notice Array of voters who have cast votes in the current cycle
    address[] public voters;
    /// @notice The mapping of holders to their vote distributions
    mapping(address => uint256[]) public holderToDistribution;
    /// @notice The mapping of holders to their total vote distribution
    mapping(address => uint256) public holderToDistributionTotal;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bread,
        address _butteredBread,
        uint256 _precision,
        uint256 _minRequiredVotingPower,
        uint256 _maxPoints,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor,
        uint256 _lastClaimedBlockNumber,
        address[] memory _projects
    ) public initializer {
        if (
            _bread == address(0) || _butteredBread == address(0) || _precision == 0 || _minRequiredVotingPower == 0
                || _maxPoints == 0 || _cycleLength == 0 || _yieldFixedSplitDivisor == 0 || _lastClaimedBlockNumber == 0
                || _projects.length == 0
        ) {
            revert MustBeGreaterThanZero();
        }

        BREAD = IBread(_bread);
        BUTTERED_BREAD = IERC20Votes(_butteredBread);
        PRECISION = _precision;
        minRequiredVotingPower = _minRequiredVotingPower;
        maxPoints = _maxPoints;
        cycleLength = _cycleLength;
        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;
        lastClaimedBlockNumber = _lastClaimedBlockNumber;

        projectDistributions = new uint256[](_projects.length);
        projects = new address[](_projects.length);
        for (uint256 i; i < _projects.length; ++i) {
            projects[i] = _projects[i];
        }
    }

    /**
     * @notice Initializes the VotingMultipliers contract
     * @param _initialOwner The address of the initial owner
     * @custom:oz-upgrades-validate-as-initializer
     */
    function initializeVotingMultipliers(address _initialOwner) public reinitializer(1) {
        __VotingMultipliers_init(_initialOwner);
    }

    /**
     * @notice Initializes the GasKiller SDK
     * @param _avsAddress The address of the AVS service manager
     * @param _blsSignatureChecker The address of the BLS signature checker
     * @custom:oz-upgrades-validate-as-initializer
     */
    function initializeGasKiller(address _avsAddress, address _blsSignatureChecker) public reinitializer(2) {
        _setAvsAddress(_avsAddress);
        _setBlsSignatureChecker(_blsSignatureChecker);
    }

    /**
     * @notice Returns the current distribution of voting power for projects
     * @return address[] The current eligible member projects
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
        return this.getVotingPowerForPeriod(BREAD, previousCycleStartingBlock, lastClaimedBlockNumber, _account)
            + this.getVotingPowerForPeriod(BUTTERED_BREAD, previousCycleStartingBlock, lastClaimedBlockNumber, _account);
    }

    /// @notice Get the current accumulated voting power for a user
    /// @dev This is the voting power that has been accumulated since the last yield distribution
    /// @param _account Address of the user to get the current accumulated voting power for
    /// @return uint256 The current accumulated voting power for the user
    function getCurrentAccumulatedVotingPower(address _account) public view returns (uint256) {
        return this.getVotingPowerForPeriod(BUTTERED_BREAD, lastClaimedBlockNumber, block.number, _account)
            + this.getVotingPowerForPeriod(BREAD, lastClaimedBlockNumber, block.number, _account);
    }

    /**
     * @notice Return the voting power for a specified user during a specified period of time
     * @param _start Start time of the period to return the voting power for
     * @param _end End time of the period to return the voting power for
     * @param _account Address of user to return the voting power for
     * @return uint256 Voting power of the specified user at the specified period of time
     */
    function getVotingPowerForPeriod(
        IERC20Votes _sourceContract,
        uint256 _start,
        uint256 _end,
        address _account
    ) public view returns (uint256) {
        if (_start >= _end) revert StartMustBeBeforeEnd();
        if (_end > block.number) revert EndAfterCurrentBlock();

        /// Initialized as the checkpoint count, but later used to track checkpoint index
        uint32 _numCheckpoints = _sourceContract.numCheckpoints(_account);
        if (_numCheckpoints == 0) return 0;

        /// No voting power if the first checkpoint is after the end of the interval
        Checkpoints.Checkpoint208 memory _currentCheckpoint = _sourceContract.checkpoints(_account, 0);
        if (_currentCheckpoint._key > _end) return 0;

        uint256 _totalVotingPower;

        for (uint32 i = _numCheckpoints; i > 0;) {
            _currentCheckpoint = _sourceContract.checkpoints(_account, --i);

            if (_currentCheckpoint._key <= _end) {
                uint48 _effectiveStart = _currentCheckpoint._key < _start ? uint48(_start) : _currentCheckpoint._key;
                _totalVotingPower += _currentCheckpoint._value * (_end - _effectiveStart);

                if (_effectiveStart == _start) break;
                _end = _currentCheckpoint._key;
            }
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
        uint256 _available_yield = BREAD.balanceOf(address(this)) + BREAD.yieldAccrued();
        if (
            /// No votes were cast
            /// OR already claimed this cycle
            /// OR yield is insufficient
            currentVotes == 0 || block.number < lastClaimedBlockNumber + cycleLength
                || _available_yield / yieldFixedSplitDivisor < projects.length
        ) {
            return (false, new bytes(0));
        } else {
            return (true, abi.encodePacked(this.distributeYield.selector));
        }
    }

    /**
     * @notice Claims yield and prepares amounts for distribution
     * @return _balance Total balance available for distribution
     * @return _baseSplit Fixed split amount per project
     * @return _votedYield Amount available for voted distribution
     */
    function _claimAndPrepareYield() internal returns (uint256 _balance, uint256 _baseSplit, uint256 _votedYield) {
        (bool _resolved,) = resolveYieldDistribution();
        if (!_resolved) revert YieldNotResolved();

        BREAD.claimYield(BREAD.yieldAccrued(), address(this));
        previousCycleStartingBlock = lastClaimedBlockNumber;
        lastClaimedBlockNumber = block.number;

        _balance = BREAD.balanceOf(address(this));
        uint256 _fixedYield = _balance / yieldFixedSplitDivisor;
        _baseSplit = _fixedYield / projects.length;
        _votedYield = _balance - _fixedYield;
    }

    /**
     * @notice Execute distribution to projects and finalize with cleanup
     * @param distributions Array of voting power distributions per project
     * @param totalVotes Total voting power
     * @param balance Total balance being distributed
     * @param _baseSplit Fixed split amount per project
     * @param _votedYield Amount available for voted distribution
     */
    function _executeAndFinalizeDistribution(
        uint256[] memory distributions,
        uint256 totalVotes,
        uint256 balance,
        uint256 _baseSplit,
        uint256 _votedYield
    ) internal {
        // Execute transfers to projects
        for (uint256 i; i < projects.length; ++i) {
            uint256 _votedSplit = ((distributions[i] * _votedYield * PRECISION) / totalVotes) / PRECISION;
            bool _success = BREAD.transfer(projects[i], _votedSplit + _baseSplit);
            if (!_success) revert TransferFailed();
        }

        // Finalize with cleanup
        _updateBreadchainProjects();
        emit YieldDistributed(balance, totalVotes, distributions);

        delete voters;
        delete currentVotes;
        projectDistributions = new uint256[](projects.length);
    }

    /**
     * @notice Distribute $BREAD yield to projects using GasKiller voting system
     */
    function distributeYieldGK() public trackState {
        (uint256 _balance, uint256 _baseSplit, uint256 _votedYield) = _claimAndPrepareYield();
        (uint256[] memory _currentProjectDistributions, uint256 _totalVotes) = _commitVotedDistribution();

        _executeAndFinalizeDistribution(_currentProjectDistributions, _totalVotes, _balance, _baseSplit, _votedYield);
    }

    /**
     * @notice Distribute $BREAD yield to projects using gas efficient voting system to avoid OOG errors
     */
    function distributeYield() public trackState {
        (uint256 balance, uint256 _baseSplit, uint256 _votedYield) = _claimAndPrepareYield();

        _executeAndFinalizeDistribution(projectDistributions, currentVotes, balance, _baseSplit, _votedYield);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield
     * @param _points List of points as integers for each project
     */
    function castVote(uint256[] calldata _points) public trackState {
        uint256 _currentVotingPower = getCurrentVotingPower(msg.sender);

        if (_currentVotingPower < minRequiredVotingPower) revert BelowMinRequiredVotingPower();

        _castVote(msg.sender, _points, _currentVotingPower);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield with multipliers
     * @param _points List of points as integers for each project
     * @param _multiplierIndices List of indices of multipliers to use for each project
     */
    function castVoteWithMultipliers(uint256[] calldata _points, uint256[] calldata _multiplierIndices)
        public
        trackState
    {
        uint256 _currentVotingPower = getCurrentVotingPower(msg.sender);
        uint256 _multiplier = calculateTotalMultipliers(msg.sender, _multiplierIndices);
        _currentVotingPower = _multiplier == 0 ? _currentVotingPower : (_currentVotingPower * _multiplier) / PRECISION;
        if (_currentVotingPower < minRequiredVotingPower) revert BelowMinRequiredVotingPower();

        _castVote(msg.sender, _points, _currentVotingPower);
    }

    /**
     * @notice Internal function for casting votes for a specified user
     * @param _account Address of user to cast votes for
     * @param _points Basis points for calculating the amount of votes cast
     * @param _votingPower Amount of voting power being cast
     */
    function _castVote(address _account, uint256[] calldata _points, uint256 _votingPower) internal {
        uint256 _projectsLength = projects.length;
        if (_points.length != _projectsLength) revert IncorrectNumberOfProjects();

        /// Add voter to list if they have not voted yet
        if (holderToDistribution[_account].length > 0) {
            delete holderToDistribution[_account];
        } else {
            voters.push(_account);
        }
        holderToDistribution[_account] = _points;

        /// Calculate total points
        uint256 _totalPoints;
        for (uint256 i; i < _projectsLength; ++i) {
            if (_points[i] > maxPoints) revert ExceedsMaxPoints();
            _totalPoints += _points[i];
        }
        if (_totalPoints == 0) revert ZeroVotePoints();
        holderToDistributionTotal[_account] = _totalPoints;

        bool _hasVotedInCycle = accountLastVoted[_account] > lastClaimedBlockNumber;
        uint256[] storage _voterDistributions = voterDistributions[_account];
        if (!_hasVotedInCycle) {
            delete voterDistributions[_account];
            currentVotes += _votingPower;
        } else {
            // When recasting, we need to subtract the old voting power and add the new one
            uint256 _previousVotingPower;
            for (uint256 i; i < _projectsLength; ++i) {
                _previousVotingPower += _voterDistributions[i];
            }
            currentVotes = currentVotes - _previousVotingPower + _votingPower;
        }

        for (uint256 i; i < _projectsLength; ++i) {
            uint256 _currentProjectDistribution = ((_points[i] * _votingPower * PRECISION) / _totalPoints) / PRECISION;
            if (!_hasVotedInCycle) {
                projectDistributions[i] += _currentProjectDistribution;
                _voterDistributions.push(_currentProjectDistribution);
            } else {
                // Update projectDistributions with the delta between new and old distributions
                projectDistributions[i] = projectDistributions[i] - _voterDistributions[i] + _currentProjectDistribution;
                _voterDistributions[i] = _currentProjectDistribution;
            }
        }

        accountLastVoted[_account] = block.number;

        emit BreadHolderVoted(_account, _points, projects);
    }

    /**
     * @notice Internal function for committing the voted distributions for projects
     * @return _newProjectDistributions Distribution of votes for projects
     * @return _totalVotes Total number of votes cast
     */
    function _commitVotedDistribution()
        internal
        returns (uint256[] memory _newProjectDistributions, uint256 _totalVotes)
    {
        _newProjectDistributions = new uint256[](projects.length);

        for (uint256 i; i < voters.length; ++i) {
            address _voter = voters[i];
            uint256 _voterPower = getCurrentVotingPower(_voter);
            uint256[] memory _voterDistribution = holderToDistribution[_voter];
            uint256 _vote;
            for (uint256 j; j < projects.length; ++j) {
                _vote =
                    (_voterPower * _voterDistribution[j] * PRECISION / holderToDistributionTotal[_voter]) / PRECISION;
                _newProjectDistributions[j] += _vote;
                _totalVotes += _vote;
            }
            delete holderToDistribution[_voter];
            delete holderToDistributionTotal[_voter];
        }
    }

    /**
     * @notice Internal function for updating the project list
     */
    function _updateBreadchainProjects() internal {
        for (uint256 i; i < queuedProjectsForAddition.length; ++i) {
            address _project = queuedProjectsForAddition[i];

            projects.push(_project);

            emit ProjectAdded(_project);
        }

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

        delete queuedProjectsForAddition;
        delete queuedProjectsForRemoval;
    }

    /**
     * @notice Queue a new project to be added to the project list
     * @param _project Project to be added to the project list
     */
    function queueProjectAddition(address _project) public onlyOwner trackState {
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
    function queueProjectRemoval(address _project) public onlyOwner trackState {
        bool _found = false;
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
     * @notice Set a new minimum required voting power a user must have to vote
     * @param _minRequiredVotingPower New minimum required voting power a user must have to vote
     */
    function setMinRequiredVotingPower(uint256 _minRequiredVotingPower) public onlyOwner trackState {
        if (_minRequiredVotingPower == 0) revert MustBeGreaterThanZero();

        minRequiredVotingPower = _minRequiredVotingPower;
    }

    /**
     * @notice Set a new maximum number of points a user can allocate to a project
     * @param _maxPoints New maximum number of points a user can allocate to a project
     */
    function setMaxPoints(uint256 _maxPoints) public onlyOwner trackState {
        if (_maxPoints == 0) revert MustBeGreaterThanZero();

        maxPoints = _maxPoints;
    }

    /**
     * @notice Set a new cycle length in blocks
     * @param _cycleLength New cycle length in blocks
     */
    function setCycleLength(uint256 _cycleLength) public onlyOwner trackState {
        if (_cycleLength == 0) revert MustBeGreaterThanZero();

        cycleLength = _cycleLength;
    }

    /**
     * @notice Set a new fixed split for the yield distribution
     * @param _yieldFixedSplitDivisor New fixed split for the yield distribution
     */
    function setYieldFixedSplitDivisor(uint256 _yieldFixedSplitDivisor) public onlyOwner trackState {
        if (_yieldFixedSplitDivisor == 0) revert MustBeGreaterThanZero();

        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;
    }

    /**
     * @notice Set the ButteredBread token contract
     * @param _butteredBread Address of the ButteredBread token contract
     */
    function setButteredBread(address _butteredBread) public onlyOwner trackState {
        BUTTERED_BREAD = IERC20Votes(_butteredBread);
    }

    /**
     * @notice Allows the owner to set the AVS address
     * @param newAvsAddress The new AVS address
     * @dev Also updates the namespace for the contract
     */
    function setAvsAddress(address newAvsAddress) external onlyOwner trackState {
        _setAvsAddress(newAvsAddress);
    }

    /**
     * @notice Allows the owner to set the BLS signature checker address
     * @param newBlsSignatureChecker The new BLS signature checker address
     */
    function setBlsSignatureChecker(address newBlsSignatureChecker) external onlyOwner trackState {
        _setBlsSignatureChecker(newBlsSignatureChecker);
    }
}
