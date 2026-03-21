// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {YieldDistributor, IYieldDistributor} from "src/YieldDistributor.sol";
import {ButteredBread} from "src/ButteredBread.sol";
import {VotingMultipliers, IVotingMultipliers} from "src/VotingMultipliers.sol";
import {IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {VotingStreakMultiplier} from "src/multipliers/VotingStreakMultiplier.sol";
import {NFTMultiplier} from "src/multipliers/NFTMultiplier.sol";
import {YieldDistributorTestWrapper} from "src/test/YieldDistributorTestWrapper.sol";
import {MockBread} from "src/test/MockBread.sol";
import {MockMultiplier} from "src/test/MockMultiplier.sol";
import {DeployNFTMultiplier} from "script/deploy/DeployNFTMultiplier.s.sol";

/// @title YieldDistributorTestBase
/// @notice Shared base contract for all YieldDistributor test suites
/// @dev Contains setUp logic, helper functions, and shared state used across test files
contract YieldDistributorTestBase is Test {
    uint256 constant START = 32_323_232_323;
    uint256 marginOfError = 3;
    YieldDistributorTestWrapper public yieldDistributor;
    YieldDistributorTestWrapper public yieldDistributor2;
    YieldDistributorTestWrapper public yieldDistributorGasKiller;
    address secondProject;
    uint256[] blockNumbers;
    uint256[] percentages;
    uint256[] votes;
    string public deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    bytes projectsRaw = stdJson.parseRaw(config_data, "._projects");
    address[] projects = abi.decode(projectsRaw, (address[]));
    address _bread = stdJson.readAddress(config_data, "._bread");
    uint256 _blocktime = stdJson.readUint(config_data, "._blocktime");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _minHoldingDuration = stdJson.readUint(config_data, "._minHoldingDuration");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");
    MockBread public bread = MockBread(address(_bread));
    ButteredBread public butteredBread = ButteredBread(address(_bread));
    uint256 minHoldingDurationInBlocks = _minHoldingDuration / _blocktime;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        address[] memory projects1 = new address[](1);
        projects1[0] = address(this);
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            address(butteredBread),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects1,
            address(this)
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        secondProject = address(0x1234567890123456789012345678901234567890);
        address[] memory projects2 = new address[](2);
        projects2[0] = address(this);
        projects2[1] = secondProject;
        initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            address(butteredBread),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects2,
            address(this)
        );
        yieldDistributor2 = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        address[] memory projects3 = new address[](1);
        projects3[0] = address(this);
        initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            address(butteredBread),
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects3,
            address(this)
        );
        yieldDistributorGasKiller = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(yieldDistributor));
    }

    function setUpForCycle(YieldDistributorTestWrapper _yieldDistributor) public {
        vm.roll(START - (_cycleLength));
        _yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(_yieldDistributor));
        vm.roll(START);
    }

    function setUpAccountsForVoting(address[] memory accounts) public {
        vm.roll(START - (_cycleLength + 1));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.deal(accounts[i], _minVotingAmount);
            vm.prank(accounts[i]);
            bread.mint{value: _minVotingAmount}(accounts[i]);
        }
    }
}
