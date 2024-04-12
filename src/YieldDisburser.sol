// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Checkpoints} from "openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";

import {IBreadToken} from "./IBreadToken.sol";

/**
 * @title TODO
 * @author Ron
 * @author bagelface.eth
 * @notice TODO
 */
contract YieldDisburser is OwnableUpgradeable {
    event BaseYieldDistributed(uint256 amount, address project);

    error AlreadyClaimed();
    error EndAfterCurrentBlock();
    error IncorrectNumberOfProjects();
    error InsufficientYield();
    error InvalidSignature();
    error MustBeGreaterThanZero();
    error MustEqualOneHundredPercent();
    error NoCheckpointsForAccount();
    error StartMustBeBeforeEnd();

    IBreadToken public breadToken;
    address[] public breadchainProjects;
    address[] public breadchainVoters;
    uint48 public lastClaimedTimestamp;
    uint48 public lastClaimedBlockNumber;
    uint48 public minimumTimeBetweenClaims;
    mapping(address => uint256[]) public holderToDistribution;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize this contract from a proxy contract
     * @param _breadToken address BreadToken contract from which to disburse $BREAD yield
     */
    function initialize(address _breadToken) public initializer {
        breadToken = IBreadToken(_breadToken);
        __Ownable_init(msg.sender);
    }

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     *
     *          Public Functions
     *
     *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /**
     * @notice Distribute $BREAD yield to projects based on cast votes
     */
    function distributeYield() public {
        if (currentBalance() < breadchainProjects.length) revert InsufficientYield();
        if (Time.timestamp() < claimableAt()) revert AlreadyClaimed();

        breadToken.claimYield(breadToken.yieldAccrued(), address(this));

        (uint256[] memory projectDistributions, uint256 totalVotes) = _getVotedDistribution(breadchainProjects.length);

        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlockNumber = Time.blockNumber();

        uint256 halfBalance = breadToken.balanceOf(address(this)) / 2;
        uint256 baseSplit = halfBalance / breadchainProjects.length;

        for (uint256 i; i < breadchainProjects.length; ++i) {
            uint256 votedSplit = ((projectDistributions[i] * halfBalance) / totalVotes);
            breadToken.transfer(breadchainProjects[i], votedSplit + baseSplit);
        }
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield
     * @param _percentages uint256[] List of percentages as integers for each breadchain project
     */
    function castVote(uint256[] calldata _percentages) public {
        _castVote(_percentages, msg.sender);
    }

    /**
     * @notice Cast votes for the distribution of $BREAD yield on behalf of a holder
     * @dev This function call is vulnerable to a replay attack.
     * @dev A timestamp should be included in the signature after which it is no longer valid.
     * @dev TODO Fix this vulnerability https://github.com/BreadchainCoop/breadchain/issues/5
     * @param _percentages uint256[] List of percentages as integers for each breadchain project
     * @param _signature bytes ECDSA signature created by the voter of their vote percentages
     * @param _voter address Voter that having votes cast on their behalf
     */
    function castVoteBySignature(uint256[] calldata _percentages, bytes calldata _signature, address _voter) public {
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(_signature, (uint8, bytes32, bytes32));
        address signer = ecrecover(keccak256(abi.encodePacked(_percentages)), v, r, s);
        if (signer != _voter) revert InvalidSignature();

        _castVote(_percentages, _voter);
    }

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     *
     *          View Functions
     *
     *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /**
     * @notice Return the current balance of the contract, including yield
     * @return uint256 Current total balance of the contract
     */
    function currentBalance() public view returns (uint256) {
        return (breadToken.balanceOf(address(this)) + breadToken.yieldAccrued());
    }

    /**
     * @notice Return the timestamp after which yield can be claimed
     * @return uint48 Timestamp after which yield can be claimed
     */
    function claimableAt() public view returns (uint48) {
        return lastClaimedTimestamp + minimumTimeBetweenClaims;
    }

    /**
     * @notice TODO
     * @dev TODO Refactor this to be more readable
     * @param _start TODO
     * @param _end TODO
     * @param _account TODO
     * @return uint256 TODO
     */
    function getVotingPowerForPeriod(uint48 _start, uint48 _end, address _account) external view returns (uint256) {
        if (_start < _end) revert StartMustBeBeforeEnd();
        if (_end <= Time.blockNumber()) revert EndAfterCurrentBlock();
        uint32 latestCheckpointPos = breadToken.numCheckpoints(_account);
        if (latestCheckpointPos == 0) revert NoCheckpointsForAccount();
        latestCheckpointPos--;
        Checkpoints.Checkpoint208 memory intervalEnd = breadToken.checkpoints(_account, latestCheckpointPos); // Subtract 1 for 0-indexed
        uint48 prevKey = intervalEnd._key;
        uint256 intervalEndValue = intervalEnd._value;
        uint256 votingPower = intervalEndValue * (_end - prevKey);
        if (latestCheckpointPos == 0) return votingPower;
        // Iterate through checkpoints in reverse order, starting one before the latest checkpoint because we already handled it above
        for (uint32 i = latestCheckpointPos - 1; i >= 0; i--) {
            Checkpoints.Checkpoint208 memory checkpoint = breadToken.checkpoints(_account, i);
            uint48 key = checkpoint._key;
            uint256 value = checkpoint._value;
            if (key <= _start) {
                votingPower += value * (prevKey - _start);
                break;
            }
            if (key > _start) {
                votingPower += value * (prevKey - key);
            }
        }
        return votingPower;
    }

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     *
     *          Internal Functions          
     *
     *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /**
     * @notice TODO
     * @dev TODO Refactor this to be more readable
     * @param _percentages TODO
     * @param _holder TODO
     */
    function _castVote(uint256[] calldata _percentages, address _holder) internal {
        uint256 length = breadchainProjects.length;
        if (_percentages.length != length) revert IncorrectNumberOfProjects();

        uint256 total;
        for (uint256 i = 0; i < length; i++) {
            total += _percentages[i];
        }
        if (total != 100) revert MustEqualOneHundredPercent();

        if (holderToDistribution[_holder].length > 0) {
            delete holderToDistribution[_holder];
        } else {
            breadchainVoters.push(_holder);
        }
        holderToDistribution[_holder] = _percentages;
    }

    /**
     * @notice TODO
     * @dev TODO Refactor this to be more readable
     * @param _projectCount TODO
     * @return uint256[] TODO
     * @return uint256 TODO
     */
    function _getVotedDistribution(uint256 _projectCount) internal returns (uint256[] memory, uint256) {
        uint256 totalVotes;
        uint256[] memory projectDistributions = new uint256[](_projectCount);

        for (uint256 i; i < breadchainVoters.length; ++i) {
            address voter = breadchainVoters[i];
            uint256 voterPower = this.getVotingPowerForPeriod(lastClaimedBlockNumber, Time.blockNumber(), voter);
            uint256[] memory voterDistribution = holderToDistribution[voter];
            for (uint256 j; j < _projectCount; ++j) {
                uint256 vote = voterPower * voterDistribution[j];
                projectDistributions[j] += vote;
                totalVotes += vote;
            }
            delete holderToDistribution[voter];
        }

        return (projectDistributions, totalVotes);
    }

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     *
     *             Owner Functions             
     *
     *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /**
     * @notice TODO
     * @dev TODO Remove this https://github.com/BreadchainCoop/breadchain/issues/9
     * @param _minimumTimeBetweenClaims TODO
     */
    function setMinimumTimeBetweenClaims(uint48 _minimumTimeBetweenClaims) public onlyOwner {
        if (_minimumTimeBetweenClaims == 0) revert MustBeGreaterThanZero();
        minimumTimeBetweenClaims = _minimumTimeBetweenClaims * 1 minutes;
    }

    /**
     * @notice Add a project to the list of yield recipients
     * @param _project Address of the project to add
     */
    function addProject(address _project) public onlyOwner {
        breadchainProjects.push(_project);
    }

    /**
     * @notice Remove a project from the list of yield recipients
     * @param _project Address of the project to remove
     */
    function removeProject(address _project) public onlyOwner {
        for (uint256 i; i < breadchainProjects.length; ++i) {
            if (breadchainProjects[i] == _project) {
                delete breadchainProjects[i];
                break;
            }
        }
    }
}
