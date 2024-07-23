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
2. Copy the YieldDistributor to test/upgrades/<version>/YieldDistributor.sol
3. Checkout to upgrade candidate version (A version that is strictly higher than the version in the previous step)
4. Update the version in the options object of the script/upgrades/ValidateUpgrade.s.sol script
5. Run `forge clean && forge build && forge script script/upgrades/ValidateUpgrade.s.sol`
6. If script is run succesfully , proceed , otherwise address errors produced by the script unti no errors are produced.
