pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std/StdJson.sol";

import {YieldDisburser} from "../../src/YieldDisburser.sol";

contract DeployYieldDisburser is Script {
    string public deployConfigPath = string(bytes("./script/deploy/config/deploy.json"));
    string config_data = vm.readFile(deployConfigPath);
    address breadAddress = stdJson.readAddress(config_data, ".breadAddress");
    uint256 _blocktime = stdJson.readUint(config_data, "._blocktime");
    uint256 _minVotingAmount = stdJson.readUint(config_data, "._minVotingAmount");
    uint256 _minHoldingDuration = stdJson.readUint(config_data, "._minHoldingDuration");
    uint256 _cycleLength = stdJson.readUint(config_data, "._cycleLength");
    uint256 _maxPoints = stdJson.readUint(config_data, "._maxPoints");
    uint256 _minTimeBetweenClaims = stdJson.readUint(config_data, "._minTimeBetweenClaims");
    uint256 _precision = stdJson.readUint(config_data, "._precision");
    uint256 _lastClaimedTimestamp = stdJson.readUint(config_data, "._lastClaimedTimestamp");
    uint256 _lastClaimedBlockNumber = stdJson.readUint(config_data, "._lastClaimedBlockNumber");
    bytes projectsRaw = stdJson.parseRaw(config_data, "._projects");
    address[] projects = abi.decode(projectsRaw, (address[]));
    bytes initData = abi.encodeWithSelector(
        YieldDisburser.initialize.selector,
        breadAddress,
        projects,
        _blocktime,
        _minVotingAmount,
        _minHoldingDuration,
        _maxPoints,
        _cycleLength,
        _lastClaimedTimestamp,
        _lastClaimedBlockNumber,
        _precision
    );

    function run() external {
        vm.startBroadcast();
        YieldDisburser yieldDisburserImplementation = new YieldDisburser();
        YieldDisburser yieldDisburser = YieldDisburser(
            address(new TransparentUpgradeableProxy(address(yieldDisburserImplementation), address(this), initData))
        );
        console2.log("Deployed YieldDisburser at address: {}", address(yieldDisburser));
        vm.stopBroadcast();
    }
}
