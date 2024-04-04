// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Checkpoints} from "openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";

import {IBreadToken} from "./IBreadToken.sol";

error AlreadyClaimed();

contract YieldDisburser is OwnableUpgradeable {
    address[] public breadchainProjects;
    address[] public breadchainVoters;
    IBreadToken public breadToken;
    uint48 public lastClaimedTimestamp;
    uint256 public lastClaimedBlocknumber;
    uint48 public minimumTimeBetweenClaims;
    mapping(address => uint256[]) public holderToDistribution;

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
        (bool _resolved, /* bytes memory _data */ ) = resolveYieldDistribution();
        require(_resolved, "Yield not resolved");

        breadToken.claimYield(breadToken.yieldAccrued(), address(this));

        uint256 halfBalance = breadToken.balanceOf(address(this)) / 2;
        uint256 baseSplit = halfBalance / breadchainProjects.length;

        (uint256[] memory projectDistributions, uint256 totalVotes) = _getVotedDistribution(breadchainProjects.length);
        for (uint256 i; i < breadchainProjects.length; ++i) {
            uint256 votedSplit = ((projectDistributions[i] * halfBalance) / totalVotes);
            breadToken.transfer(breadchainProjects[i], votedSplit + baseSplit);
        }

        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlocknumber = Time.blockNumber();
    }

    function castVoteBySignature(uint256[] calldata percentages, bytes calldata signature, address holder) public {
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        address signer = ecrecover(keccak256(abi.encodePacked(percentages)), v, r, s);
        if (signer != holder) revert("Invalid signature");
        _castVote(percentages, holder);
    }

    // TODO: Is there any kind of access control to this function?
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

    /**
     *
     *         Internal Functions        *
     *
     */

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

    function _getVotedDistribution(uint256 projectCount) internal view returns (uint256[] memory, uint256) {
        uint256 totalVotes;
        uint256[] memory projectDistributions = new uint256[](projectCount);

        for (uint256 i; i < breadchainVoters.length; ++i) {
            address voter = breadchainVoters[i];
            uint256 voterPower = this.getVotingPowerForPeriod(lastClaimedBlocknumber, Time.blockNumber(), voter);
            uint256[] memory voterDistribution = holderToDistribution[voter];

            for (uint256 j; j < projectCount; ++j) {
                uint256 vote = voterPower * voterDistribution[j];
                projectDistributions[j] += vote;
                totalVotes += vote;
            }
        }

        return (projectDistributions, totalVotes);
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
