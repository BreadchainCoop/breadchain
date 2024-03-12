// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
abstract contract Bread is ERC20VotesUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
}

contract YieldDisburser is OwnableUpgradeable {
    //implement a monthly counter so yield can only be claimed and distributed once a month ++
    //implement a function that can cast a single vote of the yield distribution between all projects, accepting a list of tuples of project addresses and % amounts
    //implement a function that can cast multiple votes, accepting a list of tuples of project addresses ,% amounts and a signature for each vote + the month number
    //time weighted voting
    // a mapping for each projects yearly/ monthly yield percentage
    address[] public breadchainProjects;
    uint[] public breadchainProjectsYield;
    uint constant SCALE = 1e6; // Scale factor to maintain precision
    Bread public breadToken;
    uint48 public lastClaimed;
    uint48 public duration;
    error AlreadyClaimed();
    function initialize(address breadAddress) public initializer {
        breadToken = Bread(breadAddress);
        __Ownable_init(msg.sender);
    }

    function resolveYieldDistribution()
        public
        view
        returns (bool, bytes memory)
    {
        uint48 _now = Time.timestamp();
        if (_now > lastClaimed + duration) revert AlreadyClaimed();
        bytes memory ret;
        return(true, ret);

    }

    function distributeYield() public {
        (bool _resolved, /*bytes memory _data */)= resolveYieldDistribution();
        if (_resolved) {
            _distributeYield();
        }
    }
    function _distributeYield() internal{
        claimYield();
        uint256 balance = breadToken.balanceOf(address(this));
        uint256 projectCount = breadchainProjects.length;
        require(
            balance > breadchainProjects.length,
            "Yield too low to distribute"
        );
        for (uint i = 0; i < projectCount; i++) {
            // breadToken.transfer(breadchainProjects[i], balance / projectCount);
            breadToken.transfer(breadchainProjects[i], 1);
        }

    }

    //## Only Owner Functions ##
    function setDuration(uint48 _duration) public onlyOwner {
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
    // ### BREAD Token Functions ###
    function claimYield() internal {
        breadToken.claimYield(breadToken.yieldAccrued(), address(this));
    }
}
