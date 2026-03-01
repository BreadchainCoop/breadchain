// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "script/Constants.s.sol";
import "forge-std/StdJson.sol";
import "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IBread} from "bread-token/src/interfaces/IBread.sol";

import {ButteredBread, IButteredBread} from "src/ButteredBread.sol";
import {ICurveStableSwap} from "src/interfaces/ICurveStableSwap.sol";
import {IERC20Votes} from "src/interfaces/IERC20Votes.sol";
import {YieldDistributorTestWrapper} from "src/test/YieldDistributorTestWrapper.sol";
import {YieldDistributor, IYieldDistributor} from "src/YieldDistributor.sol";
import {FeeOnTransferERC20} from "src/test/FeeOnTransferERC20.sol";

uint256 constant XDAI_FACTOR = 700; // 700% scaling factor; 7X
uint256 constant TOKEN_AMOUNT = 1000 ether;
address constant TEST_ADDR = address(0x69);

contract ButteredBreadTest is Test {
    ButteredBread public bb;
    ICurveStableSwap public curvePoolXdai;

    uint256 public fixedPointPercent;
    address[] public userList;
    YieldDistributorTestWrapper public yieldDistributor;
    string public deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    bytes projectsRaw = stdJson.parseRaw(config_data, "._projects");
    address[] projects = abi.decode(projectsRaw, (address[]));
    uint256 _blocktime = stdJson.readUint(config_data, "._blocktime");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _minHoldingDuration = stdJson.readUint(config_data, "._minHoldingDuration");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));
        curvePoolXdai = ICurveStableSwap(GNOSIS_CURVE_POOL_XDAI_BREAD);

        address[] memory _liquidityPools = new address[](1);
        _liquidityPools[0] = address(curvePoolXdai);

        uint256[] memory _scalingFactors = new uint256[](1);
        _scalingFactors[0] = XDAI_FACTOR;

        IButteredBread.InitData memory initData = IButteredBread.InitData({
            breadToken: GNOSIS_BREAD,
            liquidityPools: _liquidityPools,
            scalingFactors: _scalingFactors,
            name: "ButteredBread",
            symbol: "BB"
        });

        bytes memory implementationData = abi.encodeWithSelector(ButteredBread.initialize.selector, initData);

        address bbImplementation = address(new ButteredBread());
        bb =
            ButteredBread(address(new TransparentUpgradeableProxy(bbImplementation, address(this), implementationData)));

        fixedPointPercent = bb.FIXED_POINT_PERCENT();

        vm.label(address(bb), "ButteredBread");
        vm.label(GNOSIS_CURVE_POOL_XDAI_BREAD, "CurveLP_XDAI_BREAD");

        userList.push(ALICE);

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects1 = new address[](1);
        projects1[0] = address(this);
        bytes memory ydinitData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(GNOSIS_BREAD),
            address(bb),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects1,
            address(this)
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), ydinitData))
        );
    }

    function _helperAddLiquidity(address _account, uint256 _amountT0, uint256 _amountT1) internal {
        uint256 min_lp_mint = 1;

        deal(GNOSIS_BREAD, _account, _amountT0);
        deal(GNOSIS_XDAI, _account, _amountT1);

        uint256[] memory liquidityAmounts = new uint256[](2);
        liquidityAmounts[0] = _amountT0;
        liquidityAmounts[1] = _amountT1;

        vm.startPrank(_account);
        IERC20(GNOSIS_XDAI).approve(GNOSIS_CURVE_POOL_XDAI_BREAD, type(uint256).max);
        IERC20(GNOSIS_BREAD).approve(GNOSIS_CURVE_POOL_XDAI_BREAD, type(uint256).max);
        curvePoolXdai.add_liquidity(liquidityAmounts, min_lp_mint);
        curvePoolXdai.approve(address(bb), type(uint256).max);
        vm.stopPrank();
    }
}

contract ButteredBreadTest_MetaData is ButteredBreadTest {
    function testCurvePoolXdaiBread() public {
        assertEq(curvePoolXdai.name(), "BREAD / WXDAI");
        assertEq(curvePoolXdai.symbol(), "BUTTER");
    }

    function testButteredBread() public view {
        assertEq(bb.name(), "ButteredBread");
        assertEq(bb.symbol(), "BB");
    }
}

contract ButteredBreadTest_Unit is ButteredBreadTest {
    function setUp() public virtual override {
        super.setUp();
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);
    }

    function testGotButter() public view {
        assertGt(curvePoolXdai.balanceOf(ALICE), TOKEN_AMOUNT * 3 / 2);
    }

    function testAccessControlForLp() public {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));
    }

    function testAccessControlForLpRevert() public {
        deal(GNOSIS_BREAD, ALICE, TOKEN_AMOUNT);
        vm.prank(ALICE);
        vm.expectRevert();
        bb.deposit(GNOSIS_BREAD, TOKEN_AMOUNT);
    }

    function testAccessControlForOwner() public {
        address[] memory emptyList = new address[](0);
        bb.modifyScalingFactor(TEST_ADDR, XDAI_FACTOR, emptyList);
        bb.modifyAllowList(TEST_ADDR, true);
        assertTrue(bb.allowlistedLPs(TEST_ADDR));
    }

    function testAccessControlForOwnerRevert() public {
        address[] memory emptyList = new address[](0);
        bb.modifyScalingFactor(TEST_ADDR, XDAI_FACTOR, emptyList);

        vm.prank(ALICE);
        vm.expectRevert();
        bb.modifyAllowList(TEST_ADDR, true);
        assertFalse(bb.allowlistedLPs(TEST_ADDR));
    }

    function testAccessControlForOwnerRevertUnset() public {
        vm.expectRevert();
        bb.modifyAllowList(TEST_ADDR, true);
        assertFalse(bb.allowlistedLPs(TEST_ADDR));
    }

    function testDeposit() public {
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), depositAmount);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(address(bb)), 0);
    }

    function testWithdrawRevertAccessControl() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(BOBBY);
        vm.expectRevert();
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);
    }

    function testWithdrawRevertOverdraw() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), depositAmount);
        assertEq(curvePoolXdai.balanceOf(address(bb)), depositAmount);

        vm.prank(ALICE);
        vm.expectRevert();
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount + 1);
    }

    function testMintScalingFactor() public {
        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), XDAI_FACTOR);

        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledMintAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledMintAmount);
    }

    function testBurnScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testBurnScalingFactorWithUpdatedScalingFactor() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, 1000, userList);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);

        assertEq(bb.balanceOf(ALICE), 0);
    }

    function testBurnScalingFactorWithUpdatedScalingFactorPartialAmount() public {
        uint256 depositAmount = curvePoolXdai.balanceOf(ALICE);
        uint256 scaledBurnAmount = depositAmount * XDAI_FACTOR / fixedPointPercent;

        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, depositAmount);
        assertEq(bb.balanceOf(ALICE), scaledBurnAmount);

        uint256 updatedScalingFactor = 1000;
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, updatedScalingFactor, userList);

        uint256 quaterWithdraw = depositAmount / 4;
        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, quaterWithdraw);

        uint256 adjustedVotingWeight =
            ((depositAmount * updatedScalingFactor) - (quaterWithdraw * updatedScalingFactor)) / fixedPointPercent;
        assertEq(bb.balanceOf(ALICE), adjustedVotingWeight);
    }

    function testModifyScalingFactorEmitsEvent() public {
        address lp = GNOSIS_CURVE_POOL_XDAI_BREAD;
        uint256 oldFactor = bb.scalingFactors(lp);
        uint256 newFactor = oldFactor + 50;

        vm.expectEmit(true, false, false, true);
        emit IButteredBread.ScalingFactorModified(lp, oldFactor, newFactor);

        bb.modifyScalingFactor(lp, newFactor, userList);

        assertEq(bb.scalingFactors(lp), newFactor);
    }

    function testTransferRevertFuzzy(address _receiver) public {
        vm.assume(_receiver != address(0));
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));

        uint256 bbBalance = bb.balanceOf(ALICE);
        assertGt(bbBalance, 0);

        vm.expectRevert();
        bb.transfer(_receiver, bbBalance);
    }

    function testTransferFromRevertFuzzy(address _operator, address _receiver) public {
        vm.assume(_operator != address(0));
        vm.assume(_receiver != address(0));
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, curvePoolXdai.balanceOf(ALICE));

        uint256 bbBalance = bb.balanceOf(ALICE);
        assertGt(bbBalance, 0);
        bb.approve(_operator, bbBalance);
        vm.stopPrank();

        vm.prank(_operator);
        vm.expectRevert();
        bb.transferFrom(ALICE, _receiver, bbBalance);
    }
}

contract ButteredBreadTest_Fuzz is ButteredBreadTest {
    struct Scenario {
        uint256 deposit;
        uint256 withdrawal;
        uint256 initialFactor;
        uint256 updatedFactor;
    }

    modifier happyPath(Scenario memory _s) {
        // scaling factor range of 1X - 100X
        _s.initialFactor = bound(_s.initialFactor, 100, 100_000);
        _s.updatedFactor = bound(_s.updatedFactor, 100, 100_000);

        _s.deposit = bound(_s.deposit, 1 ether, 10_000 ether);
        vm.assume(_s.withdrawal <= _s.deposit);
        vm.assume(_s.withdrawal > 1 ether / 2);

        deal(GNOSIS_CURVE_POOL_XDAI_BREAD, ALICE, _s.deposit);
        vm.prank(ALICE);
        curvePoolXdai.approve(address(bb), _s.deposit);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.initialFactor, userList);

        assertEq(bb.scalingFactors(GNOSIS_CURVE_POOL_XDAI_BREAD), _s.initialFactor);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), 0);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.deposit);
        _;
    }

    function testDepositAndMint(Scenario memory _s) public happyPath(_s) {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        assertEq(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor / fixedPointPercent);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);
    }

    function testWithdrawAndBurn(Scenario memory _s) public happyPath(_s) {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);

        uint256 preWithdrawBalance = bb.balanceOf(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.withdrawal);

        assertEq(bb.balanceOf(ALICE), preWithdrawBalance - (_s.withdrawal * _s.initialFactor / fixedPointPercent));
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit - _s.withdrawal);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.withdrawal);
    }

    function testWithdrawAndBurnWithUpdatedScalingFactor(Scenario memory _s) public happyPath(_s) {
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit);

        uint256 initDeposit = bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD);
        assertEq(initDeposit, _s.deposit);
        assertEq(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor / fixedPointPercent);
        assertEq(curvePoolXdai.balanceOf(ALICE), 0);

        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.updatedFactor, userList);

        vm.prank(ALICE);
        bb.withdraw(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.withdrawal);

        uint256 maxDelta = 1;
        /// @dev accuracy within 1 wei
        assertApproxEqAbs(
            bb.balanceOf(ALICE),
            (_s.deposit * _s.updatedFactor / fixedPointPercent) - (_s.withdrawal * _s.updatedFactor / fixedPointPercent),
            maxDelta
        );

        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit - _s.withdrawal);
        assertEq(curvePoolXdai.balanceOf(ALICE), _s.withdrawal);
    }

    function testModifyScalingFactorAndSync(Scenario memory _s) public happyPath(_s) {
        vm.assume(_s.deposit % 2 == 0);

        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit / 2);
        /// @dev deposit twice to check non-duplication of depositors array
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.deposit / 2);
        vm.stopPrank();

        uint256 doubleDeposit = _s.deposit * 2;
        deal(GNOSIS_CURVE_POOL_XDAI_BREAD, BOBBY, doubleDeposit);

        vm.startPrank(BOBBY);
        curvePoolXdai.approve(address(bb), doubleDeposit);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, doubleDeposit);
        vm.stopPrank();

        /// @dev accuracy within 1 or 2 wei (due to fixed point division in test setup)
        uint256 maxDelta = 1;
        uint256 maxDeltaDouble = 2;
        assertApproxEqAbs(bb.balanceOf(ALICE), _s.deposit * _s.initialFactor / fixedPointPercent, maxDeltaDouble);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), _s.deposit);
        assertEq(bb.balanceOf(BOBBY), doubleDeposit * _s.initialFactor / fixedPointPercent);
        assertEq(bb.accountToLPBalance(BOBBY, GNOSIS_CURVE_POOL_XDAI_BREAD), doubleDeposit);

        userList.push(BOBBY);
        bb.modifyScalingFactor(GNOSIS_CURVE_POOL_XDAI_BREAD, _s.updatedFactor, userList);

        /// @dev accuracy within 1 wei
        assertApproxEqAbs(bb.balanceOf(ALICE), _s.deposit * _s.updatedFactor / fixedPointPercent, maxDeltaDouble);
        assertApproxEqAbs(bb.balanceOf(BOBBY), doubleDeposit * _s.updatedFactor / fixedPointPercent, maxDelta);
    }

    function testAccessControlForOwner(address _attacker, address _contract, bool _allow) public {
        vm.assume(_attacker != address(this));
        vm.prank(_attacker);
        vm.expectRevert();
        bb.modifyAllowList(_contract, _allow);
    }

    function testAccessControlOnNonExistent(address _contract) public {
        vm.assume(_contract != GNOSIS_CURVE_POOL_XDAI_BREAD);
        vm.expectRevert();
        bb.modifyScalingFactor(_contract, 69, userList);
    }
}

contract ButteredBreadTest_Delegation is ButteredBreadTest {
    uint256 public constant BOBBY_AMOUNT = TOKEN_AMOUNT / 2;
    address public constant DELEGATEE = address(0x420);
    address public constant ZERO_ADDR = address(0);

    function setUp() public virtual override {
        super.setUp();
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);
        _helperAddLiquidity(BOBBY, BOBBY_AMOUNT, BOBBY_AMOUNT);

        vm.prank(ALICE);
        IERC20Votes(GNOSIS_BREAD).delegate(ALICE);

        vm.prank(BOBBY);
        IERC20Votes(GNOSIS_BREAD).delegate(DELEGATEE);
    }

    function testSetup() public view {
        assertGt(curvePoolXdai.balanceOf(ALICE), TOKEN_AMOUNT);
        assertGt(curvePoolXdai.balanceOf(BOBBY), BOBBY_AMOUNT);
    }

    function testDelegation() public {
        vm.prank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, TOKEN_AMOUNT);

        vm.prank(BOBBY);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, BOBBY_AMOUNT);

        assertEq(bb.delegates(ALICE), ALICE);
        assertEq(bb.delegates(BOBBY), DELEGATEE);
    }

    function testDelegationRevert() public {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, TOKEN_AMOUNT / 3);

        assertEq(bb.delegates(ALICE), ALICE);

        vm.expectRevert(abi.encodeWithSelector(IButteredBread.NonDelegatable.selector));
        bb.delegate(DELEGATEE);

        assertEq(bb.delegates(ALICE), ALICE);
    }

    function testDelegationChange() public {
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, TOKEN_AMOUNT / 3);

        assertEq(bb.delegates(ALICE), ALICE);

        IERC20Votes(GNOSIS_BREAD).delegate(DELEGATEE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, TOKEN_AMOUNT / 3);

        assertEq(bb.delegates(ALICE), DELEGATEE);
    }

    function testDelegationDefaultAssignment() public {
        vm.startPrank(ALICE);
        IERC20Votes(GNOSIS_BREAD).delegate(ZERO_ADDR);

        assertEq(bb.delegates(ALICE), ZERO_ADDR);
        assertEq(IERC20Votes(GNOSIS_BREAD).delegates(ALICE), ZERO_ADDR);

        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, TOKEN_AMOUNT);

        assertEq(bb.delegates(ALICE), ALICE);
        assertEq(IERC20Votes(GNOSIS_BREAD).delegates(ALICE), ZERO_ADDR);
    }

    function testDelegationSyncDelegation() public {
        vm.startPrank(ALICE);
        assertEq(bb.delegates(ALICE), ZERO_ADDR);

        IERC20Votes(GNOSIS_BREAD).delegate(DELEGATEE);
        assertEq(bb.delegates(ALICE), ZERO_ADDR);

        bb.syncDelegation();

        assertEq(bb.delegates(ALICE), DELEGATEE);
    }
}

interface Mintable {
    function mint(address account) external payable;
}

contract ButteredBreadTest_Integration is ButteredBreadTest {
    uint256 public start = 32_323_232_323;

    function setUp() public virtual override {
        super.setUp();
        _helperAddLiquidity(ALICE, TOKEN_AMOUNT, TOKEN_AMOUNT);
    }

    function setUpForCycle(YieldDistributorTestWrapper _yieldDistributor) public {
        vm.roll(start - (_cycleLength));
        address yieldDistributorOwner = Ownable2StepUpgradeable(_yieldDistributor).owner();
        vm.prank(yieldDistributorOwner);
        _yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        address breadOwner = Ownable2StepUpgradeable(GNOSIS_BREAD).owner();
        vm.prank(breadOwner);
        IBread(GNOSIS_BREAD).setYieldClaimer(address(_yieldDistributor));
        vm.roll(start - (_cycleLength + 1));
        vm.deal(ALICE, _minVotingAmount);
        vm.startPrank(ALICE);
        bb.deposit(GNOSIS_CURVE_POOL_XDAI_BREAD, TOKEN_AMOUNT);
        Mintable(GNOSIS_BREAD).mint{value: _minVotingAmount}(ALICE);
        vm.roll(start);
    }

    function testIntegration() public {
        setUpForCycle(yieldDistributor);
        assertEq(bb.balanceOf(ALICE), TOKEN_AMOUNT * XDAI_FACTOR / fixedPointPercent);
        assertEq(bb.accountToLPBalance(ALICE, GNOSIS_CURVE_POOL_XDAI_BREAD), TOKEN_AMOUNT);
        uint256 bbBalance = bb.balanceOf(ALICE);
        uint256 bBalance = IERC20(GNOSIS_BREAD).balanceOf(ALICE);
        assertEq(yieldDistributor.getCurrentVotingPower(ALICE), bbBalance + bBalance);
    }
}

/// @notice Tests for issue #187: fee-on-transfer token accounting
contract ButteredBreadTest_FeeOnTransfer is ButteredBreadTest {
    FeeOnTransferERC20 public fotToken;
    uint256 public constant FEE_PERCENT = 5;
    uint256 public constant FOT_FACTOR = 200; // 2X scaling

    function setUp() public virtual override {
        super.setUp();
        fotToken = new FeeOnTransferERC20(FEE_PERCENT);

        // Allowlist the fee-on-transfer token
        address[] memory emptyList = new address[](0);
        bb.modifyScalingFactor(address(fotToken), FOT_FACTOR, emptyList);
        bb.modifyAllowList(address(fotToken), true);
    }

    /// @dev Helper to mint FOT tokens and approve ButteredBread
    function _setupFotDepositor(address _account, uint256 _amount) internal {
        fotToken.mint(_account, _amount);
        vm.prank(_account);
        fotToken.approve(address(bb), _amount);
    }

    /// @notice Deposit should record actual received amount, not requested amount
    function testDepositAccountsForTransferFee() public {
        uint256 depositAmount = 1000 ether;
        uint256 expectedReceived = depositAmount - (depositAmount * FEE_PERCENT / 100); // 950 ether

        _setupFotDepositor(ALICE, depositAmount);

        vm.prank(ALICE);
        bb.deposit(address(fotToken), depositAmount);

        // Internal balance should reflect actual tokens received, not requested amount
        uint256 recordedBalance = bb.accountToLPBalance(ALICE, address(fotToken));
        assertEq(recordedBalance, expectedReceived, "Recorded balance should equal actual received amount");

        // Contract's token balance should match recorded balance
        uint256 contractBalance = fotToken.balanceOf(address(bb));
        assertEq(contractBalance, expectedReceived, "Contract token balance should match recorded balance");

        // ButteredBread minted should be based on actual received amount
        uint256 expectedBB = expectedReceived * FOT_FACTOR / fixedPointPercent;
        assertEq(bb.balanceOf(ALICE), expectedBB, "BB minted should be based on actual received amount");
    }

    /// @notice Multiple depositors should not allow early withdrawers to drain the contract
    function testFeeOnTransferNoDrain() public {
        uint256 aliceDeposit = 1000 ether;
        uint256 bobbyDeposit = 1000 ether;
        uint256 aliceReceived = aliceDeposit - (aliceDeposit * FEE_PERCENT / 100); // 950
        uint256 bobbyReceived = bobbyDeposit - (bobbyDeposit * FEE_PERCENT / 100); // 950

        _setupFotDepositor(ALICE, aliceDeposit);
        _setupFotDepositor(BOBBY, bobbyDeposit);

        vm.prank(ALICE);
        bb.deposit(address(fotToken), aliceDeposit);

        vm.prank(BOBBY);
        bb.deposit(address(fotToken), bobbyDeposit);

        // Contract should hold exactly what was actually received
        assertEq(
            fotToken.balanceOf(address(bb)),
            aliceReceived + bobbyReceived,
            "Contract should hold sum of actual received amounts"
        );

        // Alice withdraws her full recorded balance
        uint256 aliceRecorded = bb.accountToLPBalance(ALICE, address(fotToken));
        vm.prank(ALICE);
        bb.withdraw(address(fotToken), aliceRecorded);

        // Contract should still hold enough for Bobby's withdrawal
        uint256 contractRemaining = fotToken.balanceOf(address(bb));
        uint256 bobbyRecorded = bb.accountToLPBalance(BOBBY, address(fotToken));
        assertGe(
            contractRemaining, bobbyRecorded, "Contract must hold enough tokens for remaining depositors to withdraw"
        );

        // Bobby should be able to withdraw without reverting
        vm.prank(BOBBY);
        bb.withdraw(address(fotToken), bobbyRecorded);

        assertEq(bb.accountToLPBalance(BOBBY, address(fotToken)), 0, "Bobby should have zero balance after withdrawal");
    }

    /// @notice Voting power (BB balance) should not be inflated beyond actual deposits
    function testFeeOnTransferVotingPowerNotInflated() public {
        uint256 depositAmount = 1000 ether;
        uint256 expectedReceived = depositAmount - (depositAmount * FEE_PERCENT / 100);

        _setupFotDepositor(ALICE, depositAmount);

        vm.prank(ALICE);
        bb.deposit(address(fotToken), depositAmount);

        // BB balance should be based on actual received, not the inflated requested amount
        uint256 inflatedBB = depositAmount * FOT_FACTOR / fixedPointPercent;
        uint256 correctBB = expectedReceived * FOT_FACTOR / fixedPointPercent;

        assertEq(bb.balanceOf(ALICE), correctBB, "BB should reflect actual deposit");
        assertLt(bb.balanceOf(ALICE), inflatedBB, "BB must be less than inflated amount");
    }

    /// @notice ButterAdded event should emit the actual received amount
    function testFeeOnTransferEventEmitsActualAmount() public {
        uint256 depositAmount = 1000 ether;
        uint256 expectedReceived = depositAmount - (depositAmount * FEE_PERCENT / 100);

        _setupFotDepositor(ALICE, depositAmount);

        vm.expectEmit(true, true, false, true);
        emit IButteredBread.ButterAdded(ALICE, address(fotToken), expectedReceived);

        vm.prank(ALICE);
        bb.deposit(address(fotToken), depositAmount);
    }

    /// @notice Fuzz test: deposit accounting holds for any fee percentage and amount
    function testFeeOnTransferDepositFuzz(uint256 _depositAmount, uint256 _feePercent) public {
        _feePercent = bound(_feePercent, 1, 50); // 1% to 50% fee
        _depositAmount = bound(_depositAmount, 1 ether, 100_000 ether);

        FeeOnTransferERC20 fuzzToken = new FeeOnTransferERC20(_feePercent);

        address[] memory emptyList = new address[](0);
        bb.modifyScalingFactor(address(fuzzToken), FOT_FACTOR, emptyList);
        bb.modifyAllowList(address(fuzzToken), true);

        fuzzToken.mint(ALICE, _depositAmount);
        vm.prank(ALICE);
        fuzzToken.approve(address(bb), _depositAmount);

        vm.prank(ALICE);
        bb.deposit(address(fuzzToken), _depositAmount);

        uint256 expectedReceived = _depositAmount - (_depositAmount * _feePercent / 100);
        uint256 contractBalance = fuzzToken.balanceOf(address(bb));
        uint256 recordedBalance = bb.accountToLPBalance(ALICE, address(fuzzToken));

        assertEq(recordedBalance, expectedReceived, "Recorded balance must match actual received");
        assertEq(contractBalance, expectedReceived, "Contract balance must match actual received");
        assertEq(recordedBalance, contractBalance, "Recorded and contract balances must be in sync");
    }
}
