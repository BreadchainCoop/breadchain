import "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import "script/Constants.s.sol";
import {ButteredBread} from "src/ButteredBread.sol";
import {IMultiplier} from "src/interfaces/IVotingMultipliers.sol";
import {VotingMultipliers, IVotingMultipliers} from "src/VotingMultipliers.sol";
import {VotingStreakMultiplier} from "src/multipliers/VotingStreakMultiplier.sol";
import {YieldDistributor, IYieldDistributor} from "src/YieldDistributor.sol";
import {YieldDistributorTestWrapper} from "src/test/YieldDistributorTestWrapper.sol";

abstract contract Bread is ERC20VotesUpgradeable, Ownable2StepUpgradeable {
    function claimYield(uint256 amount, address receiver) public virtual;
    function yieldAccrued() external view virtual returns (uint256);
    function setYieldClaimer(address _yieldClaimer) external virtual;
    function mint(address receiver) external payable virtual;
}

contract VotingStreakMultiplierTest is Test {
    uint256 constant START = 32_323_232_323;
    uint256 constant MULTIPLIER_INCREMENT = 0.02e20;
    uint256 constant MAX_MULTIPLIER = 3;

    YieldDistributorTestWrapper public yieldDistributor;
    string public deployConfigPath = string(bytes("./test/test_deploy.json"));
    string config_data = vm.readFile(deployConfigPath);

    address _bread = stdJson.readAddress(config_data, "._bread");
    Bread public bread = Bread(address(_bread));
    ButteredBread public butteredBread = ButteredBread(address(_bread));

    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _minRequiredVotingPower = stdJson.readUint(config_data, "._minRequiredVotingPower");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("gnosis"));

        address[] memory projects = new address[](1);
        projects[0] = address(this);

        YieldDistributorTestWrapper yieldDistributorImplementation = new YieldDistributorTestWrapper();
        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            address(bread),
            address(butteredBread),
            _precision,
            _minRequiredVotingPower,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            _lastClaimedBlockNumber,
            projects
        );
        yieldDistributor = YieldDistributorTestWrapper(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), address(this), initData))
        );

        // Deploy implementation
        VotingStreakMultiplier multiplierImplementation = new VotingStreakMultiplier();

        // Create initialization data
        bytes memory initDataForMultiplier = abi.encodeWithSelector(
            VotingStreakMultiplier.initialize.selector, address(yieldDistributor), MULTIPLIER_INCREMENT, MAX_MULTIPLIER
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(multiplierImplementation),
            address(this), // admin
            initDataForMultiplier
        );

        // Add the proxied multiplier to the yield distributor
        yieldDistributor.addMultiplier(IMultiplier(address(proxy)));
    }

    function setUpForCycle(YieldDistributorTestWrapper _yieldDistributor, uint256 iterator) public {
        vm.roll(START + (_cycleLength * (iterator)));
        _yieldDistributor.setLastClaimedBlockNumber(vm.getBlockNumber());
        address owner = bread.owner();
        vm.prank(owner);
        bread.setYieldClaimer(address(_yieldDistributor));
        vm.roll(START + (_cycleLength * ((iterator) + 1)));
    }

    function setUpAccountsForVoting(address[] memory accounts) public {
        vm.roll(START - (_cycleLength + 1));
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.deal(accounts[i], _minVotingAmount);
            vm.prank(accounts[i]);
            bread.mint{value: _minVotingAmount}(accounts[i]);
        }
    }

    function castVote(address account) public {
        vm.startPrank(account);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 100;
        uint256[] memory multiplierIndices = new uint256[](1);
        multiplierIndices[0] = 0;
        yieldDistributor.castVoteWithMultipliers(percentages, multiplierIndices);
        vm.stopPrank();
    }

    function setUpTestAccount() public returns (address) {
        address testAccount = address(0x1234);
        address[] memory accounts = new address[](1);
        accounts[0] = testAccount;
        setUpAccountsForVoting(accounts);
        return testAccount;
    }

    function setUpVotingStreakMultiplier() public returns (VotingStreakMultiplier) {
        VotingStreakMultiplier multiplier = VotingStreakMultiplier(address(yieldDistributor.allowlistedMultipliers(0)));
        multiplier.setMultiplierIncrement(MULTIPLIER_INCREMENT);
        multiplier.setMaxMultiplier(MAX_MULTIPLIER);
        return multiplier;
    }

    // when the account votes in multiple cycles, the multiplier is updated correctly
    function testFuzz_multiplier_increment_after_cycles(uint8 numCycles) public {
        // Bound number of cycles to reasonable range (1-10)
        numCycles = uint8(bound(numCycles, 1, 10));

        VotingStreakMultiplier multiplier = setUpVotingStreakMultiplier();
        address testAccount = setUpTestAccount();
        uint256 cycleIterator = 0;
        setUpForCycle(yieldDistributor, cycleIterator);

        // Initial multiplier should be 0
        assertEq(multiplier.getMultiplyingFactor(testAccount), 0);

        // Vote in each cycle and verify multiplier
        for (uint8 i = 0; i < numCycles; i++) {
            castVote(testAccount);

            // Calculate expected multiplier based on cycle number
            uint256 expectedMultiplier;
            if (i == 0) {
                expectedMultiplier = multiplier.multiplierIncrement();
            } else {
                expectedMultiplier =
                    Math.min((i + 1) * multiplier.multiplierIncrement(), MAX_MULTIPLIER * MULTIPLIER_INCREMENT);
            }

            // Verify multiplier was updated correctly
            assertEq(multiplier.getMultiplyingFactor(testAccount), expectedMultiplier);

            // Verify validity period
            assertEq(
                multiplier.validUntil(testAccount),
                yieldDistributor.lastClaimedBlockNumber() + 2 * yieldDistributor.cycleLength()
            );

            // Move to next cycle if not the last cycle
            if (i < numCycles - 1) {
                cycleIterator++;
                setUpForCycle(yieldDistributor, cycleIterator);
            }
        }
    }

    // when the account votes again in the same cycle, the account's multiplier value does not change
    function test_multiplier_no_change_after_vote_in_same_cycle() public {
        VotingStreakMultiplier multiplier = setUpVotingStreakMultiplier();
        address testAccount = setUpTestAccount();
        uint256 cycleIterator = 0;
        setUpForCycle(yieldDistributor, cycleIterator);

        // Initial multiplier should be 0
        assertEq(multiplier.getMultiplyingFactor(testAccount), 0);

        castVote(testAccount);

        // Verify multiplier was updated to multiplierIncrement
        assertEq(multiplier.getMultiplyingFactor(testAccount), multiplier.multiplierIncrement());

        // Cast a vote again in the same cycle
        castVote(testAccount);

        // Verify multiplier value did not change
        assertEq(multiplier.getMultiplyingFactor(testAccount), multiplier.multiplierIncrement());
    }

    // when the account votes, but has not voted in the previous cycle, the multiplier is reset
    function test_multiplier_reset_after_missed_cycle() public {
        VotingStreakMultiplier multiplier = setUpVotingStreakMultiplier();
        address testAccount = setUpTestAccount();
        uint256 cycleIterator = 0;
        setUpForCycle(yieldDistributor, cycleIterator);

        // Initial multiplier should be 0
        assertEq(multiplier.getMultiplyingFactor(testAccount), 0);

        castVote(testAccount);

        // Verify multiplier was updated to multiplierIncrement
        assertEq(multiplier.getMultiplyingFactor(testAccount), multiplier.multiplierIncrement());
        assertEq(
            multiplier.validUntil(testAccount),
            yieldDistributor.lastClaimedBlockNumber() + 2 * yieldDistributor.cycleLength()
        );

        // Roll to the next cycle
        cycleIterator++;
        setUpForCycle(yieldDistributor, cycleIterator);

        castVote(testAccount);

        // Verify multiplier was updated to 2 * multiplierIncrement
        assertEq(multiplier.getMultiplyingFactor(testAccount), 2 * multiplier.multiplierIncrement());

        // Roll to the next cycle
        cycleIterator++;
        setUpForCycle(yieldDistributor, cycleIterator);

        // Roll to the next cycle
        cycleIterator++;
        setUpForCycle(yieldDistributor, cycleIterator);

        castVote(testAccount);

        // Verify multiplier was reset to the base multiplier
        assertEq(multiplier.getMultiplyingFactor(testAccount), multiplier.multiplierIncrement());
    }
}
