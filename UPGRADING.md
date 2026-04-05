# Upgrade Safety Guide

This document explains how storage-layout safety is enforced for the
upgradeable contracts in this project and what to do when a CI check fails.

---

## Background

`YieldDistributor` and `ButteredBread` are both proxy-upgradeable contracts
that use OpenZeppelin's upgradeable base contracts
(`Ownable2StepUpgradeable`, `ERC20VotesUpgradeable`, etc.) and call
`_disableInitializers()` in their constructors.

Because they live behind a proxy, **the storage layout of the implementation
contract is permanently shared with the proxy**. Adding, removing, or
reordering storage variables in an incompatible way will silently corrupt
on-chain state after an upgrade. The upgrade-safety CI job exists to catch
these problems before code is merged.

---

## How CI Enforces Upgrade Safety

The workflow at `.github/workflows/upgrade-safety.yml` runs on every pull
request. It:

1. Checks out the repository (including all submodules).
2. Compiles all contracts with `forge build`, which generates
   `out/build-info/*.json` files containing full storage-layout metadata
   (enabled by `build_info = true` and `extra_output = ["storageLayout"]` in
   `foundry.toml`).
3. Runs `npx @openzeppelin/upgrades-core validate` against those build-info
   files for each upgradeable contract:
   - `YieldDistributor`
   - `ButteredBread`
4. Fails the pipeline if any storage-layout violation or upgrade-safety rule
   is detected.

---

## Running the Check Locally

Install the CLI once (requires Node.js ≥ 18):

```bash
npm install --global @openzeppelin/upgrades-core
```

Then, from the project root:

```bash
# 1. Build (generates the build-info JSON files)
forge build

# 2. Validate each upgradeable contract
npx @openzeppelin/upgrades-core validate out/build-info --contract YieldDistributor
npx @openzeppelin/upgrades-core validate out/build-info --contract ButteredBread
```

A clean result looks like:

```
Validation successful.
```

Any violation is printed with the variable name, source location, and the
rule that was broken.

---

## Understanding Validation Failures

The tool checks for the following categories of problems:

| Error kind | Meaning |
|---|---|
| `storage-variable-addition` | A new variable was inserted before existing ones, shifting their slots |
| `storage-variable-deletion` | A storage variable was removed (its slot will be uninitialized garbage on-chain) |
| `storage-type-change` | A variable's type changed in an incompatible way (e.g. `uint256` → `address`) |
| `missing-initializer-call` | A base-contract `__Foo_init()` call was omitted from an initializer |
| `incorrect-initializer-order` | Initializer chain calls are in the wrong order |
| `constructor` | Logic runs in a constructor of an upgradeable contract without `_disableInitializers()` |

---

## What To Do When the Check Fails

### Option A — Fix the code (preferred)

Restructure the change so it does not break the storage layout:

- **Adding a new variable**: append it *after* all existing variables, never
  insert it in the middle.
- **Removing a variable**: replace it with a same-sized "gap" variable
  rather than deleting it, and annotate it:

  ```solidity
  /// @custom:oz-renamed-from oldVariableName
  uint256 internal _deprecated_oldVariableName;
  ```

- **Renaming a variable**: annotate with `@custom:oz-renamed-from` so the
  tool understands the slot is intentionally reused.

### Option B — Suppress a known-safe exception

If you have thoroughly verified that a specific change is safe (e.g. an
immutable, a constant, or a variable that is known to be zero on all live
deployments), you can suppress individual rules with an NatSpec annotation
directly on the affected declaration:

```solidity
/// @custom:oz-upgrades-unsafe-allow state-variable-immutable
uint256 private immutable MY_IMMUTABLE;
```

```solidity
/// @custom:oz-upgrades-unsafe-allow state-variable-assignment
uint256 private myVar = 42;
```

To suppress a rule at the contract level (use sparingly):

```solidity
/// @custom:oz-upgrades-unsafe-allow constructor
constructor() {
    _disableInitializers();
}
```

Multiple rules can be combined on one line:

```solidity
/// @custom:oz-upgrades-unsafe-allow missing-initializer-call incorrect-initializer-order
```

> ⚠️ **Suppression annotations bypass automated safety checks.** Always have
> a second engineer review any suppression and document *why* it is safe in
> the same NatSpec comment.

---

## Further Reading

- [OpenZeppelin Upgrades Plugins — validation rules](https://docs.openzeppelin.com/upgrades-plugins/api-core)
- [Writing Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable)
- [ERC-7201: Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201)
- [Foundry build-info output](https://book.getfoundry.sh/reference/config/compiler#build_info)
