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

See [script/upgrades/README.md](script/upgrades/README.md) for upgrade validation and deployment instructions.
