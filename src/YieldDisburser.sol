// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Checkpoints} from "openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";

import {IBreadToken} from "./IBreadToken.sol";

error AlreadyClaimed();

contract YieldDisburser is OwnableUpgradeable {
    address[] public breadchainProjects;
    uint256[] projectYieldDistributions;
    address[] public breadchainVoters;
    IBreadToken public breadToken;
    uint48 public lastClaimedTimestamp;
    uint256 public lastClaimedBlocknumber;
    uint48 public minimumTimeBetweenClaims;
    mapping(address => uint256[]) holderToDistribution;

    event BaseYieldDistributed(uint256 amount, address project);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address breadAddress) public initializer {
        breadToken = IBreadToken(breadAddress);
        __Ownable_init(msg.sender);
    }

    /**
     *
     *          Public Functions         *
     *
     */

    function distributeYield() public {
        (bool _resolved, /*bytes memory _data */ ) = resolveYieldDistribution();
        require(_resolved, "Yield not resolved");
        _claimYield();
        uint256 balance = breadToken.balanceOf(address(this)) / 2;
        uint256 projectCount = breadchainProjects.length;
        _distributeBaseYield(balance, projectCount);
        _distributedVotedYield(balance, projectCount);
        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlocknumber = Time.blockNumber();
    }

    function castVoteBySignature(uint256[] calldata percentages, bytes calldata signature, address holder) public {
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        address signer = ecrecover(keccak256(abi.encodePacked(percentages)), v, r, s);
        if (signer != holder) revert("Invalid signature");
        _castVote(percentages, holder);
    }

    function castVote(uint256[] calldata percentages) public {
        _castVote(percentages, msg.sender);
    }

    /**
     *
     *           View Functions          *
     *
     */

    function resolveYieldDistribution() public view returns (bool, bytes memory) {
        uint48 _now = Time.timestamp();
        uint256 balance = (breadToken.balanceOf(address(this)) + breadToken.yieldAccrued());
        require(balance > breadchainProjects.length, "Yield too low to distribute");
        if (_now < lastClaimedTimestamp + minimumTimeBetweenClaims) {
            revert AlreadyClaimed();
        }
        bytes memory ret = abi.encodePacked(this.distributeYield.selector);
        return (true, ret);
    }

    function getVotingPowerForPeriod(uint256 start, uint256 end, address account) external view returns (uint256) {
        require(start < end, "Start must be before end");
        require(end <= Time.blockNumber());
        uint32 latestCheckpointPos = breadToken.numCheckpoints(account);
        require(latestCheckpointPos > 0, "No checkpoints for account");
        latestCheckpointPos--;
        Checkpoints.Checkpoint208 memory intervalEnd = breadToken.checkpoints(account, latestCheckpointPos); // Subtract 1 for 0-indexed
        uint48 prevKey = intervalEnd._key;
        uint256 intervalEndValue = intervalEnd._value;
        uint256 votingPower = intervalEndValue * (end - prevKey);
        if (latestCheckpointPos == 0) return votingPower;
        // Iterate through checkpoints in reverse order, starting one before the latest checkpoint because we already handled it above
        for (uint32 i = latestCheckpointPos - 1; i >= 0; i--) {
            Checkpoints.Checkpoint208 memory checkpoint = breadToken.checkpoints(account, i);
            uint48 key = checkpoint._key;
            uint256 value = checkpoint._value;
            if (key <= start) {
                votingPower += value * (prevKey - start);
                break;
            }
            if (key > start) {
                votingPower += value * (prevKey - key);
            }
        }
        return votingPower;
    }

    function getNextWindowTimestamp() public view returns (uint256) {
        return lastClaimedTimestamp + minimumTimeBetweenClaims;
    }

    function getCurrentMemberProjects() public view returns (address[] memory) {
        return breadchainProjects;
    }

    /**
     *
     *         Internal Functions        *
     *
     */

    function _distributeBaseYield(uint256 balance, uint256 projectCount) internal {
        uint256 baseYield = balance / projectCount;
        for (uint256 i = 0; i < projectCount; i++) {
            breadToken.transfer(breadchainProjects[i], baseYield);
            emit BaseYieldDistributed(baseYield, breadchainProjects[i]);
        }
    }

    function _castVote(uint256[] calldata percentages, address holder) internal {
        uint256 length = breadchainProjects.length;
        require(percentages.length == length, "Incorrect number of projects");
        uint256 total;
        for (uint256 i = 0; i < length; i++) {
            total += percentages[i];
        }
        require(total == 100, "Total must equal 100");
        if (holderToDistribution[holder].length > 0) {
            delete holderToDistribution[holder];
        }
        holderToDistribution[holder] = percentages;
        breadchainVoters.push(holder);
    }

    function _distributedVotedYield(uint256 balance, uint256 projectCount) internal {
        uint256 currentBlock = Time.blockNumber();
        uint256 total_votes_casted;
        for (uint256 k = 0; k < projectCount; k++) {
            projectYieldDistributions.push(0);
        }
        while (breadchainVoters.length > 0) {
            address voter = breadchainVoters[breadchainVoters.length - 1];
            breadchainVoters.pop();
            uint256 votingpower = this.getVotingPowerForPeriod(lastClaimedBlocknumber, currentBlock, voter);
            uint256[] memory percentages = holderToDistribution[voter];
            delete holderToDistribution[voter];
            for (uint256 j = 0; j < projectCount; j++) {
                uint256 vote = votingpower * percentages[j];
                projectYieldDistributions[j] += vote;
                total_votes_casted += vote;
            }
        }
        for (uint256 l = 0; l < projectCount; l++) {
            breadToken.transfer(breadchainProjects[l], (projectYieldDistributions[l] / total_votes_casted) * balance);
        }
        for (uint256 m = 0; m < projectCount; m++) {
            projectYieldDistributions.pop();
        }
    }

    function _claimYield() internal {
        breadToken.claimYield(breadToken.yieldAccrued(), address(this));
    }

    /**
     *
     *        Only Owner Functions       *
     *
     */

    function setMinimumTimeBetweenClaims(uint48 _minimumTimeBetweenClaims) public onlyOwner {
        require(_minimumTimeBetweenClaims > 0, "minimumTimeBetweenClaims must be greater than 0");
        minimumTimeBetweenClaims = _minimumTimeBetweenClaims * 1 minutes;
    }

    function setlastClaimedTimestamp(uint48 _lastClaimedTimestamp) public onlyOwner {
        lastClaimedTimestamp = _lastClaimedTimestamp;
    }

    function setLastClaimedBlocknumber(uint256 _lastClaimedBlocknumber) public onlyOwner {
        lastClaimedBlocknumber = _lastClaimedBlocknumber;
    }

    function addProject(address projectAddress) public onlyOwner {
        breadchainProjects.push(projectAddress);
    }

    function removeProject(address projectAddress) public onlyOwner {
        for (uint256 i = 0; i < breadchainProjects.length; i++) {
            if (breadchainProjects[i] == projectAddress) {
                delete breadchainProjects[i];
                break;
            }
        }
    }
}
