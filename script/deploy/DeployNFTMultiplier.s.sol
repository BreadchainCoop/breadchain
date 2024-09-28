// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {NFTMultiplier} from "src/multipliers/NFTMultiplier.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {console} from "forge-std/console.sol";

contract DeployNFTMultiplier is Script {
    function run() external {
        uint256 deployerPrivateKey;
        address nftContractAddress;
        uint256 initialMultiplyingFactor;
        uint256 validUntilBlock;

        string memory configPath = "deploy_config.json";
        string memory jsonData;
        // Try to read the JSON file, if it doesn't exist or can't be read, catch the error
        try vm.readFile(configPath) returns (string memory data) {
            jsonData = data;
        } catch {
            console.log("Config file not found or couldn't be read. Falling back to environment variables.");
            jsonData = "";
        }

        if (bytes(jsonData).length > 0) {
            // Read from JSON if file exists
            deployerPrivateKey = vm.parseJsonUint(jsonData, ".deployerPrivateKey");
            nftContractAddress = vm.parseJsonAddress(jsonData, ".nftContractAddress");
            initialMultiplyingFactor = vm.parseJsonUint(jsonData, ".initialMultiplyingFactor");
            validUntilBlock = vm.parseJsonUint(jsonData, ".validUntilBlock");
        } else {
            // Fall back to environment variables
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            nftContractAddress = vm.envAddress("NFT_CONTRACT_ADDRESS");
            initialMultiplyingFactor = vm.envUint("INITIAL_MULTIPLYING_FACTOR");
            validUntilBlock = vm.envUint("VALID_UNTIL_BLOCK");
        }

        // Check if all required variables are set
        require(deployerPrivateKey != 0, "Deployer private key not set");
        require(nftContractAddress != address(0), "NFT contract address not set");
        require(initialMultiplyingFactor != 0, "Initial multiplying factor not set");
        require(validUntilBlock != 0, "Valid until block not set");

        vm.startBroadcast(deployerPrivateKey);

        NFTMultiplier implementation = new NFTMultiplier();

        bytes memory initData = abi.encodeWithSelector(
            NFTMultiplier.initialize.selector, IERC721(nftContractAddress), initialMultiplyingFactor, validUntilBlock
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), vm.addr(deployerPrivateKey), initData);

        NFTMultiplier nftMultiplier = NFTMultiplier(address(proxy));

        vm.stopBroadcast();

        console.log("NFTMultiplier deployed at:", address(nftMultiplier));
    }
}
