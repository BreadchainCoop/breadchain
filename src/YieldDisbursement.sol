// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
abstract contract Bread is ERC20VotesUpgradeable {
    function claimYieldForDisbursement() virtual public;
}



contract YieldDisburser is OwnableUpgradeable {
    //implement a monthly counter so yield can only be claimed and distributed once a month ++
    //implement a function that can cast a single vote of the yield distribution between all projects, accepting a list of tuples of project addresses and % amounts
    //implement a function that can cast multiple votes, accepting a list of tuples of project addresses ,% amounts and a signature for each vote + the month number
    //time weighted voting
    mapping(uint256 => mapping(uint256 => bool)) public calledInMonth;
    // a mapping for each projects yearly/ monthly yield percentage 
    address[] public breadchainProjects;
    uint[] public breadchainProjectsYield;
    uint constant SCALE = 1e6; // Scale factor to maintain precision
    Bread public breadToken;
    function initialize(address breadAddress) public initializer {
        breadToken = Bread(breadAddress);
        __Ownable_init(msg.sender);
    }
    function distributeYield() public {
        (uint256 year, uint256 month) = getCurrentYearMonth();
        require(!calledInMonth[year][month]);
        //get the list of projects
        //get the list of votes
        //cast the votes
        //claim the yield
        //distribute the yield
        calledInMonth[year][month] = true;
    }

    function claimYield() internal  {
        breadToken.claimYieldForDisbursement();
    }

    function resolveTest() public view returns(bool){
        uint256 year;
        uint256 month;
        (year, month) = getCurrentYearMonth();
        return calledInMonth[year][month];
    }
    function keeperHook() public {
        uint256 year;
        uint256 month;
        (year, month) = getCurrentYearMonth();
        calledInMonth[year][month] = true;
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
    
    function getCurrentYearMonth() public view returns (uint256 year, uint256 month) {
        uint256 secondsInMonth = 30 days;
        uint256 monthsSinceEpoch = block.timestamp / secondsInMonth;
        year = 1970 + (monthsSinceEpoch / 12);
        month = (monthsSinceEpoch % 12) + 1; 
        
    }
    function castVote(uint[] memory projectindex, uint[] memory percentages) internal {
        require(projectindex.length == percentages.length);
        require(projectindex.length == breadchainProjects.length);
        // calculate the sum of the percentages
        uint sum = 0;
        for (uint i = 0; i < percentages.length; i++) {
            sum += percentages[i];
        }
        // sum of percentages must be 100
        require(sum == 1);

        for (uint i = 0; i < projectindex.length; i++) {
            breadchainProjectsYield[projectindex[i]] = percentages[i];
        }

    }

   function computeScaledAverage(uint[][] memory vectors) public  view returns (uint[] memory) {
        uint VECTOR_LENGTH = breadchainProjects.length;
        uint[] memory sum;
        uint[] memory average;
        // Step 1: Calculate sum and then the average of each element
        for(uint i = 0; i < VECTOR_LENGTH; i++) {
            // Summing elements of the two vectors
            sum[i] = vectors[0][i] + vectors[1][i];
            // Calculating the average, scaled to maintain precision
            average[i] = (sum[i] * SCALE) / VECTOR_LENGTH;
        }

        // Step 2: Calculate the total sum of the average vector
        uint totalSum = 0;
        for(uint i = 0; i < VECTOR_LENGTH; i++) {
            totalSum += average[i];
        }

        // Step 3: Normalize the average vector so it sums up to 100 * SCALE
        uint[] memory normalizedAverage;
        for(uint i = 0; i < VECTOR_LENGTH; i++) {
            normalizedAverage[i] = (average[i] * SCALE) / totalSum;
        }

        return normalizedAverage;
    }
}