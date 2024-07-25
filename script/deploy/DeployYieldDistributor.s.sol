pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std/StdJson.sol";

import {YieldDistributor} from "../../src/YieldDistributor.sol";

contract DeployYieldDistributor is Script {
    string public deployConfigPath = string(bytes("./script/deploy/config/deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    address _bread = stdJson.readAddress(config_data, "._bread");
    uint256 _minRequiredVotingPower = stdJson.readUint(config_data, "._minRequiredVotingPower");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    uint256 _yieldFixedSplitDivisor = stdJson.readUint(config_data, "._yieldFixedSplitDivisor");
    address _owner = stdJson.readAddress(config_data, "._owner");
    bytes projectsRaw = stdJson.parseRaw(config_data, "._projects");
    address[] projects = abi.decode(projectsRaw, (address[]));
    bytes initData = abi.encodeWithSelector(
        YieldDistributor.initialize.selector,
        _bread,
        _precision,
        _minRequiredVotingPower,
        _maxPoints,
        _cycleLength,
        _yieldFixedSplitDivisor,
        _lastClaimedBlockNumber,
        projects
    );

    function run() external {
        vm.startBroadcast();
        YieldDistributor yieldDistributorImplementation = new YieldDistributor();
        YieldDistributor yieldDistributor = YieldDistributor(
            address(new TransparentUpgradeableProxy(address(yieldDistributorImplementation), _owner, initData))
        );
        console2.log("Deployed YieldDistributor at address: {}", address(yieldDistributor));
        vm.stopBroadcast();
    }
}
