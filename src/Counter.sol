// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Counter {
    uint256 public number;
    function resolve() public view returns(bool,bytes memory){
        bytes memory a; 
        return (number == 1,a);
    }
    function setNumber(uint256 x) public {
        number = x;
    }

    function increment() public {
        number++;
    }
}
