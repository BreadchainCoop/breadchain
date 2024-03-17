// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {YieldDisburser} from "../src/YieldDisburser.sol";
import {ERC20VotesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract Bread is ERC20VotesUpgradeable, OwnableUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external virtual;
    function mint(address receiver) external payable virtual;
}
contract YieldDisburserTest is Test {
    YieldDisburser public yieldDisburser;
    Bread public bread;
    uint256[] blockNumbers;
    uint256[] percentages;
    uint256[] votes;


    function setUp() public {
        bread = Bread(address(0xa555d5344f6FB6c65da19e403Cb4c1eC4a1a5Ee3));
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        yieldDisburser = YieldDisburser(
            address(
                new TransparentUpgradeableProxy(
                    address(yieldDisburserImplementation),
                    address(this),
                    abi.encodeWithSelector(
                        YieldDisburser.initialize.selector,
                        address(bread)
                    )
                )
            )
        );
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDisburser));
        yieldDisburser.addProject(address(this));
    }
    function test_simple_distribute() public {
        vm.roll(32323232323);
        yieldDisburser.setlastClaimedTimestamp(uint48(block.timestamp));
        yieldDisburser.setLastClaimedBlocknumber(block.number);
        uint256 bread_bal_before = bread.balanceOf(address(this));
        assertEq(bread_bal_before, 0);
        address holder = address(0x1234567890123456789012345678901234567890);
        vm.deal(holder,1000000000000);
        vm.prank(holder);
        bread.mint{value:1000000}(holder);
        vm.roll(32323332323);
        uint256 vote = 100;
        percentages.push(vote);
        uint256 yieldAccrued = bread.yieldAccrued();
        vm.prank(holder);
        yieldDisburser.castVote(percentages);
        yieldDisburser.distributeYield();
        uint256 bread_bal_after = bread.balanceOf(address(this));
        assertEq(bread_bal_after, yieldAccrued);
    }
    function testFuzzyDistribute(uint256 seed, uint256 accounts) public {
        address secondProject = address(0x1234567890123456789012345678901234567890);
        yieldDisburser.addProject(secondProject);
        accounts = uint256(bound( accounts,  1, 3));
        seed = uint256(bound( seed,  1, 100000000000));
        vm.assume(seed>0);
        vm.assume(accounts>0);
        uint256 start = 32323232323;
        vm.roll(start);
        yieldDisburser.setlastClaimedTimestamp(uint48(block.timestamp));
        yieldDisburser.setLastClaimedBlocknumber(start);
        uint256 yieldAccrued;
        uint256 currentBlockNumber =32323232323;
        for (uint256 i = 0; i< accounts; i++){
            uint256 randomval = uint256(keccak256(abi.encodePacked(seed, i)));
            address holder = address(uint160(randomval));
            uint256 token_amount = bound(randomval,100,10000);
            vm.deal(holder, token_amount);
            vm.prank(holder);
            bread.mint{value: token_amount}(holder);
            uint256 vote = randomval % 100;
            currentBlockNumber += randomval % 5;
            vm.roll(currentBlockNumber);
            votes.push(vote);
            votes.push(100-vote);
            vm.prank(holder);
            yieldDisburser.castVote(votes);
            votes.pop();
            votes.pop();
        }
        yieldAccrued = bread.yieldAccrued() / 2;
        yieldDisburser.distributeYield();
        uint256 this_bal_after = bread.balanceOf(address(this));
        uint256 second_bal_after = bread.balanceOf(secondProject);
        assertEq(this_bal_after + second_bal_after, yieldAccrued -1 );

    }

    function test_add_project() public {
        assert(yieldDisburser.breadchainProjects(0) == address(this));
        yieldDisburser.removeProject(address(this));
        assert(yieldDisburser.breadchainProjects(0) == address(0));
    }
    function test_set_duration() public {
        uint48 durationBefore = yieldDisburser.duration();
        yieldDisburser.setDuration(10);
        uint48 durationAfter = yieldDisburser.duration();
        assertEq(durationBefore + 10 minutes, durationAfter);
    }
    function test_voting_power() public {
        vm.roll(32323232323);
        vm.expectRevert();
        uint256 votingPowerBefore =  yieldDisburser.getVotingPowerForPeriod(32323232323, 32323232324, address(this));
        vm.deal(address(this),1000000000000);
        vm.roll(42424242424);
        bread.mint{value:1000000}(address(this));
        vm.roll(42424242425);
        uint256 votingPowerAfter =  yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242425, address(this));
        assertEq(votingPowerAfter, 1000000);
        vm.roll(42424242426);
        votingPowerAfter =  yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242426, address(this));
        assertEq(votingPowerAfter, 2000000);
        vm.roll(42424242427);
        bread.mint{value:1000000}(address(this));
        vm.roll(42424242428);
        votingPowerAfter =  yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242428, address(this));
        assertEq(votingPowerAfter, 5000000);
        vm.roll(42424242430);
        votingPowerAfter =  yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242430, address(this));
        assertEq(votingPowerAfter, 9000000);
        vm.expectRevert();
        votingPowerAfter =  yieldDisburser.getVotingPowerForPeriod(42424242424, 42424242431, address(this));

    }
    function testFuzzy_voting_power( uint256 seed,uint256 mints) public {
        mints = uint256(bound( mints,  1, 100));
        vm.assume(seed < 100000000000 / mints);
        vm.assume(seed>0);
        uint256 start = 32323232323;
        vm.roll(start);
        address holder = address(this);
        vm.deal(holder, 100000000000);
        for (uint256 i = 0; i< mints; i++){
            uint256 mintblocknum = start + seed; 
            vm.roll(mintblocknum);
            bread.mint{value:seed}(holder);
            blockNumbers.push(mintblocknum);
        }
        uint256 votingPower =  yieldDisburser.getVotingPowerForPeriod(start, blockNumbers[(blockNumbers.length)-1], holder);
        uint256 expectedVotingPower = 0;
        for (uint256 i = 0; i< blockNumbers.length -1; i++){
            uint256 mintblocknum = blockNumbers[i];
            uint256 nextMintBlockNum = blockNumbers[i+1];
            expectedVotingPower += (nextMintBlockNum - mintblocknum) * seed;
        }
        assertEq(votingPower, expectedVotingPower);
        votingPower =  yieldDisburser.getVotingPowerForPeriod(start- 1000, blockNumbers[(blockNumbers.length)-1], holder);
        assertEq(votingPower, expectedVotingPower);
       
    }
    
}
