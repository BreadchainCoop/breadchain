pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {VotingStreakMultiplier} from "../../src/multipliers/VotingStreakMultiplier.sol";

contract DeployVotingStreakMultiplier is Script {
    string public deployConfigPath = string(bytes("./script/deploy/config/deployVotingStreakMultiplier.json"));
    string configData = vm.readFile(deployConfigPath);
    address _yieldDistributor = stdJson.readAddress(configData, "._yieldDistributor");
    uint256 _multiplierIncrement = stdJson.readUint(configData, "._multiplierIncrement");
    uint256 _maxMultiplierIncrements = stdJson.readUint(configData, "._maxMultiplierIncrements");
    address _owner = stdJson.readAddress(configData, "._owner");

    bytes initData = abi.encodeWithSelector(
        VotingStreakMultiplier.initialize.selector, _yieldDistributor, _multiplierIncrement, _maxMultiplierIncrements
    );

    function run() external {
        vm.startBroadcast();
        VotingStreakMultiplier votingStreakMultiplierImplementation = new VotingStreakMultiplier();
        VotingStreakMultiplier votingStreakMultiplier = VotingStreakMultiplier(
            address(new TransparentUpgradeableProxy(address(votingStreakMultiplierImplementation), _owner, initData))
        );
        console2.log("Deployed VotingStreakMultiplier at address: {}", address(votingStreakMultiplier));
        vm.stopBroadcast();
    }
}
