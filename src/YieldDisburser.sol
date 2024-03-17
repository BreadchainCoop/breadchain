// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Time} from "openzeppelin-contracts/contracts/utils/types/Time.sol";
import {Checkpoints} from "openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";

abstract contract Bread is ERC20VotesUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
}

contract YieldDisburser is OwnableUpgradeable {
    address[] public breadchainProjects;
    uint256[]  projectYieldDistributions;
    address[] public breadchainVoters;
    Bread public breadToken;
    uint48 public lastClaimedTimestamp;
    uint256 public lastClaimedBlocknumber; 
    uint48 public duration;
    mapping(address => uint256[]) holderToDistribution;
    error AlreadyClaimed();
    event BaseYieldDistributed(uint256 amount, address project);
    function initialize(address breadAddress) public initializer {
        breadToken = Bread(breadAddress);
        __Ownable_init(msg.sender);
    }
    /// ##########################################
    /// ## Public Functions ##
    /// ##########################################
    function distributeYield() public {
        (bool _resolved /*bytes memory _data */, ) = resolveYieldDistribution();
        claimYield();
        uint256 balance = breadToken.balanceOf(address(this)) / 2;
        uint256 projectCount = breadchainProjects.length;
        if (_resolved) {
            _distributeBaseYield(balance, projectCount);
            _distributedVotedYield(balance, projectCount);
        }
        lastClaimedTimestamp = Time.timestamp();
        lastClaimedBlocknumber = Time.blockNumber();
    }
    function castVoteBySignature(
        uint256[] calldata percentages,
        bytes calldata signature,
        address holder
    ) public {
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        address signer = ecrecover(keccak256(abi.encodePacked(percentages)), v, r, s);
        if (signer != holder) revert("Invalid signature");
        _castVote(percentages,holder);
    }
    function castVote(
        uint256[] calldata percentages
    ) public {
        _castVote(percentages, msg.sender);
        
        
    }

    /// ##########################################
    /// ## View Functions ##
    /// ##########################################
    function resolveYieldDistribution()
        public
        view
        returns (bool, bytes memory)
    {
        uint48 _now = Time.timestamp();
        uint256 balance = (breadToken.balanceOf(address(this)) +
            breadToken.yieldAccrued()) / 2;
        require(
            balance > breadchainProjects.length,
            "Yield too low to distribute"
        );
        if (_now < lastClaimedTimestamp + duration) revert AlreadyClaimed();
        bytes memory ret = abi.encodePacked(this.distributeYield.selector);
        return (true, ret);
    }
    function getVotingPowerForPeriod(
        uint256 start,
        uint256 end,
        address account
    ) external view returns (uint256) {
        require(start < end, "Start must be before end");
        require(end<= Time.blockNumber());
        uint32 latestCheckpointPos = breadToken.numCheckpoints(account);
        require(latestCheckpointPos > 0, "No checkpoints for account");
        latestCheckpointPos--;
        Checkpoints.Checkpoint208 memory intervalEnd = breadToken.checkpoints(account, latestCheckpointPos); // Subtract 1 for 0-indexed
        uint48 prevKey = intervalEnd._key;
        uint256 intervalEndValue = intervalEnd._value;
        uint256 votingPower = intervalEndValue * (end - prevKey);
        if (latestCheckpointPos == 0) return votingPower;
        // Iterate through checkpoints in reverse order, starting one before the latest checkpoint because we already handled it above
        for (uint32 i = latestCheckpointPos - 1 ; i >= 0; i--) {
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
    /// ##########################################
    /// ## Internal Functions ##
    /// ##########################################

    function _distributeBaseYield(
        uint256 balance,
        uint256 projectCount
    ) internal {
        uint256 baseYield = balance / projectCount;
        for (uint i = 0; i < projectCount; i++) {
            breadToken.transfer(breadchainProjects[i], baseYield);
            emit BaseYieldDistributed(baseYield, breadchainProjects[i]);
        }
    }
    function _castVote(uint256[] calldata percentages,address holder) internal {
        uint256 length = breadchainProjects.length;
        require(
            percentages.length == length,
            "Incorrect number of projects"
        );
        uint256 total;
        for (uint i = 0; i < length; i++) {
            total += percentages[i];
        }
        require(total == 100, "Total must equal 100");
        if (holderToDistribution[holder].length > 0) {
            delete holderToDistribution[holder];
        }
        holderToDistribution[holder]= percentages;
        breadchainVoters.push(holder);
    }
    function _distributedVotedYield(uint256 balance,uint256 projectCount) internal {
        uint256 currentBlock = Time.blockNumber();
        uint256 total_votes_casted;     
        for (uint k = 0; k < projectCount; k++) {
            projectYieldDistributions.push(0);
        }
        while (breadchainVoters.length > 0){
            address voter = breadchainVoters[breadchainVoters.length - 1];
            breadchainVoters.pop();
            uint256 votingpower = this.getVotingPowerForPeriod(lastClaimedBlocknumber,currentBlock , voter);
            uint256[] memory percentages = holderToDistribution[voter];
            delete holderToDistribution[voter];
            for (uint j = 0; j < projectCount; j++) {
                uint256 vote = votingpower * percentages[j];
                projectYieldDistributions[j]+=vote;
                total_votes_casted += vote;
            }
        }
        for (uint l = 0; l < projectCount; l++) {
            breadToken.transfer(breadchainProjects[l], (projectYieldDistributions[l] / total_votes_casted) * balance);
        }
        for (uint m = 0; m < projectCount; m++) {
            projectYieldDistributions.pop();
        }
    }
    function claimYield() internal {
        breadToken.claimYield(breadToken.yieldAccrued(), address(this));
    }
    /// ##########################################
    /// ## Only Owner Functions ##
    /// ##########################################
    function setDuration(uint48 _duration) public onlyOwner {
        require(_duration > 0, "Duration must be greater than 0");
        duration = _duration * 1 minutes;
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
        for (uint i = 0; i < breadchainProjects.length; i++) {
            if (breadchainProjects[i] == projectAddress) {
                delete breadchainProjects[i];
                break;
            }
        }
    }
}
