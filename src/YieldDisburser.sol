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
    uint[] public breadchainProjectsYield;
    Bread public breadToken;
    uint48 public lastClaimed;
    uint48 public duration;
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
            _distributedVotedYield(projectCount);
        }
        lastClaimed = Time.timestamp();
    }

    function castVote(
        uint[] memory percentages
    ) internal {
        require(projectindex.length == breadchainProjects.length);
        for (uint i = 0; i < projectindex.length; i++) {
            breadchainProjectsYield[projectindex[i]] = percentages[i];
        }
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
        if (_now < lastClaimed + duration) revert AlreadyClaimed();
        bytes memory ret = abi.encodePacked(this.distributeYield.selector);
        return (true, ret);
    }
    function getVotingPowerForPeriod(
        uint256 start,
        uint256 end,
        address account
    ) external view returns (uint256) {
        require(start < end, "Start must be before end");
        uint32 latestCheckpointPos = breadToken.numCheckpoints(account);
        require(latestCheckpointPos > 0, "No checkpoints for account");
        latestCheckpointPos--; // -1 because it's 0-indexed
        uint256 votingPower = 0;
        uint48 _prev_key = latestCheckpointPos; // Initializing the previous key
        for (uint32 i = latestCheckpointPos; ; i--) {
            // Looping through the checkpoints
            Checkpoints.Checkpoint208 memory checkpoint = breadToken
                .checkpoints(account, i); // Getting the checkpoint
            uint48 _key = checkpoint._key; // Block number
            uint208 _value = checkpoint._value; // Voting power
            if (_key <= end && _key >= start) {
                votingPower += (_value * (_key - _prev_key)); // Adding the voting power for the period
            }
            if (_key <= start) {
                return votingPower; // If we are before the start of the period, we can return the voting power
            }
            _prev_key = _key; // Updating the previous key
        }
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
    function _distributedVotedYield(uint256 projectCount) internal {
        for (uint i = 0; i < projectCount; i++) {}
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
    function setLastClaimed(uint48 _lastClaimed) public onlyOwner {
        lastClaimed = _lastClaimed;
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
