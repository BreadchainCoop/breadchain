// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {YieldDistributor} from "src/YieldDistributor.sol";

contract YieldDistributorTestWrapper is YieldDistributor {
    constructor() {}

    /**
     * @notice Return the number of projects
     * @return uint256 Number of projects
     */
    function getProjectsLength() public view returns (uint256) {
        return projects.length;
    }

    /**
     * @notice Set the number of votes cast in the current cycle
     * @param _currentVotes New number of votes cast in the current cycle
     */
    function setCurrentVotes(uint256 _currentVotes) public onlyOwner {
        currentVotes = _currentVotes;
    }

    /**
     * @notice Set a new block number of the most recent yield distribution
     * @param _lastClaimedBlockNumber New block number of the most recent yield distribution
     */
    function setLastClaimedBlockNumber(uint256 _lastClaimedBlockNumber) public onlyOwner {
        lastClaimedBlockNumber = _lastClaimedBlockNumber;
    }
}
