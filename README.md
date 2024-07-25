## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Test 

```shell 
$ forge test --fork-url "https://rpc.gnosis.gateway.fm" -vvvv
```
### Deploy

```shell
forge script script/deploy/DeployYieldDistributor.s.sol:DeployYieldDistributor --rpc-url "https://rpc.gnosis.gateway.fm" --broadcast --private-key <pk>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Validate Upgrade Safety 
1. Checkout to the deployed implementation commit 
2. Copy "YieldDistributor.sol" to `test/upgrades/<version>/YieldDistributor.sol`
3. Checkout to upgrade candidate version (A version that is strictly higher than the version in the previous step)
4. Update the version in the options object of the `script/upgrades/ValidateUpgrade.s.sol` script
5. Run `forge clean && forge build && forge script script/upgrades/ValidateUpgrade.s.sol`
6. If script is runs successfully, proceed, otherwise address errors produced by the script until no errors are produced.

## Test Upgrade with Calldata Locally 
1. Amend the `data` variable in `script/upgrades/UpgradeYieldDistributor.s.sol` to match desired data 
2. run `forge clean && forge build && forge script script/upgrades/UpgradeYieldDistributor.s.sol --sig "run(address)" <proxy_address> --rpc-url $RPC_URL  --sender <proxy_admin>` 

The proxy admin address is configured to be the Breadchain multisig at address `0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad` and the Yield Distributor proxy address is `0xeE95A62b749d8a2520E0128D9b3aCa241269024b`