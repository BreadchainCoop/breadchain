pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {YieldDistributor} from "../../src/YieldDistributor.sol";

contract DeployYieldDistributor is Script {
    string public deployConfigPath = string(bytes("./script/deploy/config/deployYD.json"));
    string config_data = vm.readFile(deployConfigPath);
    address _bread = stdJson.readAddress(config_data, "._bread");
    address _butteredBread = stdJson.readAddress(config_data, "._butteredBread");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");
    address _owner = stdJson.readAddress(config_data, "._owner");
    address[] _projects = abi.decode(stdJson.parseRaw(config_data, "._projects"), (address[]));

    function run() external {
        uint256 lastClaimedBlockNumber = _lastClaimedBlockNumber == 0 ? block.number : _lastClaimedBlockNumber;
        if (_lastClaimedBlockNumber == 0) {
            console2.log("Using current block as lastClaimedBlockNumber:", lastClaimedBlockNumber);
        }

        bytes memory initData = abi.encodeWithSelector(
            YieldDistributor.initialize.selector,
            _bread,
            _butteredBread,
            _precision,
            _maxPoints,
            _cycleLength,
            _yieldFixedSplitDivisor,
            lastClaimedBlockNumber,
            _projects,
            _owner
        );

        vm.startBroadcast();
        YieldDistributor yieldDistributorImplementation = new YieldDistributor();
        YieldDistributor yieldDistributor = YieldDistributor(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), _owner, initData))
        );
        console2.log("Deployed YieldDistributor at address: {}", address(yieldDistributor));
        vm.stopBroadcast();
    }
}
