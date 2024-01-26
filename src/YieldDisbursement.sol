// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
abstract contract Bread is ERC20VotesUpgradeable {
    function claimYieldForDisbursement() virtual public;
}



contract YieldDisburser is OwnableUpgradeable {
    Bread public bread;
    function initialize(address breadAddress) public initializer {
        bread = Bread(breadAddress);
        __Ownable_init(msg.sender);
    }

    function claimYield() internal  {
        bread.claimYieldForDisbursement();
    }

}