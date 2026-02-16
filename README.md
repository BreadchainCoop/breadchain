# Solidarity Fund

These smart contracts power Bread Coop's [solidarity fund](https://fund.bread.coop/) and [governance application](https://fund.bread.coop/governance).

To learn more check out the [Bread Coop wiki](https://docs.bread.coop).

## Contributing

Join in on the conversation in our [Discord](https://discord.gg/XJKCQagdXb).

If you have skills (either technical or non-technical) that you believe would benefit our mission, you can fill out [this Google Form](https://docs.google.com/forms/d/e/1FAIpQLSfOWubPChHH14LpV4GwgXrrot0Smqd1rmypN4MEULdw7n1o4g/viewform). Expect to hear from a member of our team within a week regarding any potential opportunities for collaboration.

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
