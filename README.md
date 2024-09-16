# Breadchain
Breadchain smart contracts power [Breadchain's governance application](https://app.breadchain.xyz/governance).

To learn more check out the [Breadchain wiki](https://breadchain.notion.site/4d496b311b984bd9841ef9c192b9c1c7).

## Contributing
Join in on the conversation in our [Discord](https://discord.com/invite/zmNqsHRHDa).

If you have skills (both technical and non-technical) that you believe would benefit our mission, you can fill out [this Google Form](https://forms.gle/UU4FmHq4CZbiEKPc6). Expect to hear from a member of our team shortly regarding any potential opportunities for collaboration.

### Style Guide
Contributions to this repo are expected to adhere to the [Biconomy Solidity Style Guide](https://github.com/bcnmy/biconomy-solidity-style-guide).

## Usage

### Build

```shell
$ forge build
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Test 

```shell 
$ forge test --fork-url "https://rpc.gnosis.gateway.fm" -vvvv
```
### Deploy

```shell
forge script script/deploy/DeployYieldDistributor.s.sol:DeployYieldDistributor --rpc-url "https://rpc.gnosis.gateway.fm" --broadcast --private-key <pk>
```

## Upgrading
### Validate Upgrade Safety 
1. Checkout to the deployed implementation commit 
2. Copy "YieldDistributor.sol" to `test/upgrades/<version>/YieldDistributor.sol`
3. Checkout to upgrade candidate version (A version that is strictly higher than the version in the previous step)
4. Update the version in the options object of the `script/upgrades/ValidateUpgrade.s.sol` script
5. Run `forge clean && forge build && forge script script/upgrades/ValidateUpgrade.s.sol`
6. If script is runs successfully, proceed, otherwise address errors produced by the script until no errors are produced.

### Test Upgrade with Calldata Locally 
1. Amend the `data` variable in `script/upgrades/UpgradeYieldDistributor.s.sol` to match desired data 
2. run `forge clean && forge build && forge script script/upgrades/UpgradeYieldDistributor.s.sol --sig "run(address)" <proxy_address> --rpc-url $RPC_URL  --sender <proxy_admin>` 

The proxy admin address is configured to be the Breadchain multisig at address `0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad` and the Yield Distributor proxy address is `0xeE95A62b749d8a2520E0128D9b3aCa241269024b`