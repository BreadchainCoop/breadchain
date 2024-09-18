pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GNOSIS_BREAD} from "script/Constants.s.sol";
import {ButteredBread, IButteredBread} from "src/ButteredBread.sol";

contract DeployButteredBread is Script {
    string public deployConfigPath = string(bytes("./script/deploy/config/deployBB.json"));
    string config_data = vm.readFile(deployConfigPath);
    address _owner = stdJson.readAddress(config_data, "._owner");

    IButteredBread.InitData _initData = IButteredBread.InitData({
        breadToken: GNOSIS_BREAD,
        liquidityPools: abi.decode(stdJson.parseRaw(config_data, "._liquidityPools"), (address[])),
        scalingFactors: abi.decode(stdJson.parseRaw(config_data, "._scalingFactors"), (uint256[])),
        name: stdJson.readString(config_data, "._name"),
        symbol: stdJson.readString(config_data, "._symbol")
    });

    bytes _implementationData = abi.encodeWithSelector(ButteredBread.initialize.selector, _initData);

    function run() external {
        vm.rpcUrl("gnosis");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address butteredBreadImplementation = address(new ButteredBread());
        ButteredBread butteredBread = ButteredBread(
            address(new TransparentUpgradeableProxy(butteredBreadImplementation, _owner, _implementationData))
        );
        console2.log("Deployed ButteredBread at address: {}", address(butteredBread));
        vm.stopBroadcast();
    }
}
