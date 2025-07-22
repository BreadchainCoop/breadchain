// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeTimelock} from "../../src/UpgradeTimelock.sol";

/**
 * @title DeployUpgradeTimelock
 * @notice Script to deploy the UpgradeTimelock contract for managing upgrades
 */
contract DeployUpgradeTimelock is Script {
    
    struct TimelockConfig {
        uint256 minDelay;         // Minimum delay in seconds (e.g., 86400 for 24 hours)
        address[] proposers;      // Addresses that can propose operations
        address[] executors;      // Addresses that can execute operations
        address admin;            // Optional admin address (can be zero address)
    }

    function run() public {
        // Load configuration
        TimelockConfig memory config = getConfig();
        
        // Deploy the timelock
        vm.startBroadcast();
        UpgradeTimelock timelock = deployTimelock(config);
        vm.stopBroadcast();
        
        // Log deployment details
        console.log("UpgradeTimelock deployed at:", address(timelock));
        console.log("Minimum delay:", config.minDelay, "seconds");
        console.log("Number of proposers:", config.proposers.length);
        console.log("Number of executors:", config.executors.length);
        
        if (config.admin != address(0)) {
            console.log("Admin address:", config.admin);
        }
    }

    /**
     * @notice Deploy the UpgradeTimelock contract
     * @param config The timelock configuration
     * @return timelock The deployed timelock contract
     */
    function deployTimelock(TimelockConfig memory config) public returns (UpgradeTimelock) {
        // Deploy implementation
        UpgradeTimelock implementation = new UpgradeTimelock();
        console.log("UpgradeTimelock implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            UpgradeTimelock.initialize,
            (config.minDelay, config.proposers, config.executors, config.admin)
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            msg.sender, // Proxy admin (should be changed to timelock itself or multisig later)
            initData
        );

        return UpgradeTimelock(payable(address(proxy)));
    }

    /**
     * @notice Get timelock configuration
     * @dev Override this function or set environment variables for different deployments
     * @return config The timelock configuration
     */
    function getConfig() public view returns (TimelockConfig memory config) {
        // Default configuration - can be overridden via environment variables or JSON config
        try vm.envUint("TIMELOCK_MIN_DELAY") returns (uint256 delay) {
            config.minDelay = delay;
        } catch {
            config.minDelay = 86400; // 24 hours default
        }
        
        // Get proposers from environment or use deployer as default
        try vm.envString("TIMELOCK_PROPOSERS") returns (string memory proposersEnv) {
            if (bytes(proposersEnv).length > 0) {
                // Parse comma-separated addresses from environment
                config.proposers = parseAddresses(proposersEnv);
            } else {
                // Default: deployer can propose
                config.proposers = new address[](1);
                config.proposers[0] = msg.sender;
            }
        } catch {
            // Default: deployer can propose
            config.proposers = new address[](1);
            config.proposers[0] = msg.sender;
        }

        // Get executors from environment or use deployer as default
        try vm.envString("TIMELOCK_EXECUTORS") returns (string memory executorsEnv) {
            if (bytes(executorsEnv).length > 0) {
                // Parse comma-separated addresses from environment
                config.executors = parseAddresses(executorsEnv);
            } else {
                // Default: deployer can execute
                config.executors = new address[](1);
                config.executors[0] = msg.sender;
            }
        } catch {
            // Default: deployer can execute
            config.executors = new address[](1);
            config.executors[0] = msg.sender;
        }

        // Admin address (optional)
        try vm.envAddress("TIMELOCK_ADMIN") returns (address adminAddr) {
            config.admin = adminAddr;
        } catch {
            config.admin = address(0);
        }
    }

    /**
     * @notice Parse comma-separated addresses from a string
     * @param addressesStr Comma-separated address string
     * @return addresses Array of parsed addresses
     */
    function parseAddresses(string memory addressesStr) internal pure returns (address[] memory addresses) {
        // Simple implementation - in production, use a more robust parser
        // For now, assume single address (can be extended)
        addresses = new address[](1);
        addresses[0] = vm.parseAddress(addressesStr);
    }

    /**
     * @notice Alternative deployment with JSON config
     * @param configPath Path to JSON configuration file
     * @return timelock The deployed timelock contract
     */
    function deployWithConfig(string memory configPath) public returns (UpgradeTimelock) {
        string memory json = vm.readFile(configPath);
        
        TimelockConfig memory config;
        config.minDelay = vm.parseJsonUint(json, ".minDelay");
        
        // For simplicity, assume single proposer and executor in JSON
        // In production, extend to support arrays
        config.proposers = new address[](1);
        config.proposers[0] = vm.parseJsonAddress(json, ".proposer");
        
        config.executors = new address[](1);
        config.executors[0] = vm.parseJsonAddress(json, ".executor");
        
        config.admin = vm.parseJsonAddress(json, ".admin");
        
        return deployTimelock(config);
    }
}