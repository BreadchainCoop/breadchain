# Upgrading

## Validate Upgrade Safety

Before upgrading to a new version of our deployed contracts, it is necessary to run the upgrade safety validation check. This ensures that upgrading won't break existing functionality or corrupt the contract's state.

1. Checkout the latest deployed implementation commit (usually the latest tagged release)
2. Flatten "YieldDistributor" and "ButteredBread" contracts (this will output a single `.sol` file with all dependencies inlined for comparison by the upgrade script):

```
forge flatten src/ButteredBread.sol > test/upgrades/latest/ButteredBread.sol
forge flatten src/YieldDistributor.sol > test/upgrades/latest/YieldDistributor.sol
```

3. Update `test/upgrades/latest/.tag` to be the current tag version, if it isn't already
4. Checkout the upgrade branch
5. Run `forge clean && forge build && forge script script/upgrades/ValidateUpgrade.s.sol`
6. If the script runs successfully, proceed. Otherwise, address errors produced by the script. Go back to the previous step and repeat until no errors are produced.

## Test Upgrade with Calldata Locally

1. Amend the `data` variable in `script/upgrades/UpgradeYieldDistributor.s.sol` to match desired data
2. run `forge clean && forge build && forge script script/upgrades/UpgradeYieldDistributor.s.sol --sig "run(address)" <proxy_address> --rpc-url $RPC_URL  --sender <proxy_admin>`

The proxy admin address is configured to be the Breadchain multisig at address `0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad` and the Yield Distributor proxy address is `0xeE95A62b749d8a2520E0128D9b3aCa241269024b`
