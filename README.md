# Breadchain

Breadchain smart contracts power [Breadchain's governance application](https://app.breadchain.xyz/governance).

To learn more check out the [Breadchain wiki](https://breadchain.notion.site/4d496b311b984bd9841ef9c192b9c1c7).

## Contributing

Join in on the conversation in our [Discord](https://discord.com/invite/zmNqsHRHDa).

If you have skills (both technical and non-technical) that you believe would benefit our mission, you can fill out [this Google Form](https://forms.gle/UU4FmHq4CZbiEKPc6). Expect to hear from a member of our team shortly regarding any potential opportunities for collaboration.

### Style Guide

Contributions to this repo are expected to adhere to the [Biconomy Solidity Style Guide](https://github.com/bcnmy/biconomy-solidity-style-guide).

## Usage

### Setup

```shell
$ cp .env.example .env
```

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

Before upgrading to a new version of our deployed contracts, it is necessary to run the upgrade safety validation check. This ensures that upgrading won't break existing functionality or corrupt the contract's state.

1. Checkout the deployed implementation commit (usually the `dev` branch)
2. Determine the new version targeted by the upgrade; it should be strictly higher than the latest deployed version [tag](https://github.com/BreadchainCoop/breadchain/tags)
3. Flatten YieldDistributor and ButteredBread (this will output a single .sol file with all dependencies inlined for comparison by the upgrade script):

```
forge flatten src/YieldDistributor.sol > test/upgrades/<new_version>/YieldDistributor.sol
forge flatten src/ButteredBread.sol > test/upgrades/<new_version>/ButteredBread.sol
```

4. Checkout the upgrade branch
5. Update the version in the options object of the `script/upgrades/ValidateUpgrade.s.sol` script
6. Run `forge clean && forge build && forge script script/upgrades/ValidateUpgrade.s.sol`
7. If script is runs successfully, proceed, otherwise address errors produced by the script until no errors are produced.

### Test Upgrade with Calldata Locally

1. Amend the `data` variable in `script/upgrades/UpgradeYieldDistributor.s.sol` to match desired data
2. run `forge clean && forge build && forge script script/upgrades/UpgradeYieldDistributor.s.sol --sig "run(address)" <proxy_address> --rpc-url $RPC_URL  --sender <proxy_admin>`

The proxy admin address is configured to be the Breadchain multisig at address `0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad` and the Yield Distributor proxy address is `0xeE95A62b749d8a2520E0128D9b3aCa241269024b`
