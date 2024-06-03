// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {YieldDisburser} from "../YieldDisburser.sol";

contract YieldDisburserTestWrapper is YieldDisburser {
    constructor() {}

    /**
     * @notice Set the number of votes cast in the current cycle
     * @param _currentVotes New number of votes cast in the current cycle
     */
    function setCurrentVotes(uint256 _currentVotes) public onlyOwner {
        currentVotes = _currentVotes;
    }

    /**
     * @notice Set a new timestamp of the most recent yield distribution
     * @param _lastClaimedTimestamp New timestamp of the most recent yield distribution
     */
    function setLastClaimedTimestamp(uint48 _lastClaimedTimestamp) public onlyOwner {
        lastClaimedTimestamp = _lastClaimedTimestamp;
    }

    /**
     * @notice Set a new block number of the most recent yield distribution
     * @param _lastClaimedBlockNumber New block number of the most recent yield distribution
     */
    function setLastClaimedBlockNumber(uint256 _lastClaimedBlockNumber) public onlyOwner {
        lastClaimedBlockNumber = _lastClaimedBlockNumber;
    }
}
