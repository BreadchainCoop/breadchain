// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {ButteredBread}   from "../src/ButteredBread.sol";
import {IButteredBread}  from "../src/interfaces/IButteredBread.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ModifyScalingFactorTest is Test {
    ButteredBread bb;
    address lp;

    function setUp() public {
        lp = address(new ERC20Mock());

        address[] memory pools = new address[](1);
        uint256[] memory factors = new uint256[](1);
        pools[0]   = lp;
        factors[0] = 100;                               // 1× scaling

        IButteredBread.InitData memory init;
        init.breadToken     = address(0);
        init.liquidityPools = pools;
        init.scalingFactors = factors;
        init.name           = "BB";
        init.symbol         = "BB";

        ButteredBread impl = new ButteredBread();
        bytes memory initCall = abi.encodeWithSelector(
            ButteredBread.initialize.selector,
            init
        );
        bb = ButteredBread(
                address(new TransparentUpgradeableProxy(
                    address(impl),
                    address(this),
                    initCall
                ))
        );
    }

    function testEventIsEmitted() public {
        address[] memory holders = new address[](0);  

        vm.expectEmit(true, false, false, true);
        emit IButteredBread.ScalingFactorModified(lp, 100, 150);

        bb.modifyScalingFactor(lp, 150, holders);
        assertEq(bb.scalingFactors(lp), 150);
    }
}
