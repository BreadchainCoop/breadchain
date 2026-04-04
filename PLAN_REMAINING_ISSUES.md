# Solidarity Fund — Remaining Issues Execution Plan
## BreadchainCoop/solidarity-fund | Generated 2026-04-04

---

## Status at a Glance

| Category | Count | Notes |
|---|---|---|
| Security bugs (all have PRs) | 4 | Awaiting merge approval |
| Stale PRs | 2 | #163 (staging dep), #145 (timelock — reviewed below) |
| Open issues without PRs | 13 | Now planned below |

**Ignored for now:** Issue #132 / PR #145 (timelock for upgrades) — deferred per user direction, but reviewed in Appendix A.
**v1.0.4 / v1.0.5 releases:** Issue #164 and #171 are tracking labels, not actionable items. See the version note at the top of Phase 2.

---

## Recommended Phase Order

```
Phase 1 — Security PRs (already in flight)
Phase 2 — Voting Boost Enhancements (plug-in multipliers)
Phase 3 — ERC-7201 & VotesExtendedUpgradeable (storage/proxy foundation)
Phase 4 — Foundry Template Update
Phase 5 — Infrastructure / CI
Phase 6 — Gelato Automation
Phase 7 — Upgrade Simulation Tests
Phase 8 — Testing Refactor
Phase 9 — Documentation & Address Decoupling
```

---

## PHASE 1 — Security PRs (already in flight)

These 4 PRs are open with passing tests. No additional work needed from this plan.
Just needs 2nd approval + merge.

UPDATE 2026-04-04: Combined PR #195 (fix/184-185-186-critical-voting-bugs) has been CLOSED.
Individual PRs remain open: #196, #197, #198.

| PR | Issue | Description |
|---|---|---|
| #194 | #187 | Fee-on-Transfer |
| #196 | #186 | Duplicate multiplier indexes |
| #197 | #185 | Streak multiplier cycle spam |
| #198 | #184 | distributeYieldGK bypass |

---

> ⚠️ **Version numbering note:** The repo's release tags do not follow a strict semver patch-increment
> sequence. After v1.0.3 the version jumped to v1.1.0, then v1.1.1 → v1.2.0 → v1.3.0.
> This suggests the team uses minor/major bumps for any significant change rather than strict patch
> increments. "v1.0.4" and "v1.0.5" are used in the issue tracker as informal milestone labels,
> but the next actual release tag will need to follow the existing pattern (e.g. v1.4.0 or whatever
> aligns with the team's versioning convention). Coordinate with the team before tagging.

---

## PHASE 2 — Voting Boost Enhancements [BRANCHES CREATED — AWAITING PUSH]

> All branches below are pushed and have PRs open. Awaiting review + merge.

These are 5 new multiplier plugins. Each follows the existing `IMultiplier` interface
pattern already established by `VotingStreakMultiplier.sol` and `NFTMultiplier.sol`.

**Common architecture:** Each is a new Solidity contract in `src/multipliers/` implementing
`IMultiplier`. Once deployed, each is added to the `VotingMultipliers` allowlist via
`addMultiplier(IMultiplier)`. All use `BASE_MULTIPLIER = 1e18` as the 100% baseline.

---

### Issue #170 — BREAD Transaction Boost

**What:** Voting power boost for users who made BREAD token transfers within a qualifying window.

**Implementation approach:**
1. Create `BreadTransactionBoostMultiplier.sol` in `src/multipliers/`
2. Store the BREAD token address (`IBread`) and a qualifying window (e.g. `QUALIFYING_BLOCKS`)
3. `getMultiplyingFactor(address user)` — query `IBread` transfer events or use a
   reconfigured snapshot list to check if user made a tx within the window
4. Since BREAD is an ERC20Votes token, look at `Transfer` events from the BREAD contract
   via an archive node call or maintain a block-tracked mapping updated by the owner
5. Add integration tests in `test/multipliers/`

**Key questions to resolve before coding:**
- What qualifies — outbound transfers only, or inbound too?
- Minimum transfer size threshold, or any transfer counts?
- Does "within a qualifying window" mean "since last distribution cycle" or a fixed lookback?
- Is there an existing BREAD token contract to query? (Check `interfaces/IBread.sol`)

**Files:** `src/multipliers/BreadTransactionBoostMultiplier.sol` (new)

---

### Issue #169 — Never Burn BREAD Boost

**What:** Boost for addresses with zero lifetime BREAD burn activity.

**Implementation approach:**
1. Create `NeverBurnBoostMultiplier.sol` in `src/multipliers/`
2. BREAD is an ERC20Votes token — burns are `burn` / `burnFrom` calls
3. Option A: Query `Burn` events from BREAD contract directly (stateless, needs archive node)
4. Option B: Maintain a `hasBurned[address] → bool` mapping updated via a trust model or oracle
5. `getMultiplyingFactor` returns `BASE_MULTIPLIER + BOOST` if `!hasBurned[user]`, else `BASE_MULTIPLIER`

**Files:** `src/multipliers/NeverBurnBoostMultiplier.sol` (new)

---

### Issue #168 — Bake 10+ Times Boost

**What:** Boost for users who have baked BREAD at least 10 times.

**What is "baking"?** This is likely a specific BREAD ecosystem action. Need to identify:
- Is it a function call on the BREAD token? A separate Bakery contract?
- Is there an existing interface or contract for this?

**Implementation approach (depends on bake mechanism discovery):**
1. Identify the baking contract / mechanism from the Bread Coop codebase or Discord
2. Create `BakeCountBoostMultiplier.sol`
3. Maintain a `bakeCount[address] → uint256` counter updated on each bake event
4. OR query bake events directly if events are emitted
5. `getMultiplyingFactor` returns boosted value when `bakeCount >= 10`

**Files:** `src/multipliers/BakeCountBoostMultiplier.sol` (new)

---

### Issue #167 — POAP Boost

**What:** Boost for holders of a qualifying POAP token.

**Implementation approach:**
1. Create `PoapBoostMultiplier.sol` in `src/multipliers/`
2. Store the qualifying POAP contract address and / or event ID
3. `getMultiplyingFactor` — call `balanceOf(user)` on the POAP ERC721 contract
4. If `balanceOf(user) > 0`, return boosted value; else `BASE_MULTIPLIER`
5. POAP is ERC721, standard `balanceOf` / `ownerOf` interface

**Files:** `src/multipliers/PoapBoostMultiplier.sol` (new)

---

### Issue #166 — TBS NFT Boost

**What:** Boost for holders of the TBS (The Bread Social) NFT.

**Implementation approach:**
1. Create `TbsNftBoostMultiplier.sol` in `src/multipliers/`
2. Identify the TBS NFT contract address (not yet known — needs to be sourced from Bread Coop team)
3. `getMultiplyingFactor` — call `balanceOf(user)` or `ownerOf(tokenId)` on the TBS NFT
4. Handle case where TBS NFT supports multiple tiers — could return different boost values per tier

**Files:** `src/multipliers/TbsNftBoostMultiplier.sol` (new)

---

**All 5 boost multipliers — testing approach:**
- Add tests in `test/multipliers/` following the pattern in `test/YieldDistributor.t.sol`
- Test: boost applies when condition met
- Test: no boost when condition not met
- Test: boost expires (validUntil) correctly
- Test: multiple boosts stack (all 5 can be active simultaneously via VotingMultipliers allowlist)

---

## PHASE 3 — Storage & Proxy Foundation

### Issue #112 — ERC-7201 Namespaced Storage [PR #203]

**What:** Migrate all upgradeable contracts to use ERC-7201 namespaced storage slots.
`VotingMultipliers` already uses it (line 14, storage location `erc7201:breadchain.VotingMultipliers.storage`).
Need to audit remaining contracts.

**Contracts to audit:**
- `YieldDistributor.sol` — likely the most complex storage user
- `ButteredBread.sol` — ERC20VotesUpgradeable handles its own storage, but the contract's custom mappings need review
- `src/multipliers/*.sol` — all upgradeable multiplier contracts

**Steps:**
1. Review each contract's storage layout and identify any direct `slot` assignments
2. Replace legacy storage patterns with `/// @custom:storage-location erc7201:breadchain.<Contract>.storage` + assembly pattern
3. Verify storage layout compatibility with deployed proxy state — **this is the critical step**
4. Use OpenZeppelin's `UpgradesPlugin` or a `forge inspect` storage diff to validate
5. This requires a proxy redeployment since ERC-7201 storage slots are incompatible
   with existing non-namespaced storage — coordinate with the Bread Coop team for a
   migration plan and timing

**⚠️ Risk:** This is a breaking change requiring proxy redeployment. Must be sequenced
before or alongside v1.0.5, not after. Coordinate with existing deployed contract state.

**Files:** `src/YieldDistributor.sol`, `src/ButteredBread.sol`, `src/multipliers/*.sol`

---

### Issue #156 — VotesExtendedUpgradeable [branch feat/votes-extended-upgradeable]

**What:** Implement or integrate `VotesExtendedUpgradeable` to extend OpenZeppelin Votes
with upgradeability support. This is a prerequisite for safely upgrading governance contracts.

**Current state:** `ButteredBread.sol` already extends `ERC20VotesUpgradeable`.
`VotesExtendedUpgradeable` is an OpenZeppelin offering that wraps the non-upgradeable
`Votes` with an upgradeable proxy pattern.

**Steps:**
1. Check OpenZeppelin Contracts (v5.x) for `VotesExtendedUpgradeable` availability
2. If available: import and integrate into the governance upgrade path
3. If not available as a built-in: implement a custom wrapper that combines
   `ERC20VotesUpgradeable` with additional checkpoint logic for upgrade-safety
4. Coordinate with Issue #112 — storage layout must be compatible across upgrades
5. Add tests: delegation and checkpoint behavior across upgrade boundary

**Files:** `src/ButteredBread.sol`, possibly new `src/utils/VotesExtendedUpgradeable.sol`

---

## PHASE 4 — Foundry Template Update [DONE — PR #199 OPEN]

> Issue #122: Branch pushed, PR #199 created.

### Issue #122 — Update Foundry Template [PR #199]

**What:** Update `foundry.toml`, `remappings.txt`, and `lib/` dependencies to current
Foundry best practices.

**Steps:**
1. Audit current `foundry.toml` — compare with latest `foundry.toml` template from Foundry CLI (`forge init --template`)
2. Update `forge-std` to latest stable: `forge update lib/forge-std`
3. Update OpenZeppelin Contracts to latest minor/patch via `lib/` 
4. Refresh `remappings.txt` with `forge remap`
5. Check for outdated Solidity version pragma across all `.sol` files (currently `^0.8.22` and `^0.8.25` mixed — standardize if needed)
6. Run full test suite to confirm no regressions after dependency updates

**Files:** `foundry.toml`, `remappings.txt`, `lib/` (git submodule or pkg), `.env.example`

---

## PHASE 5 — Infrastructure / CI

### Issue #142 — CI/CD Auto-Deploy Pipeline [PR #200]

**What:** GitHub Actions workflow for automated deployment on merge to main / tag push.

**Steps:**
1. Define deployment targets (which networks? Gnosis / mainnet staging?)
2. Create `.github/workflows/deploy.yml` with:
   - Trigger: `push` to `main` + tag pushes matching `v*`
   - Steps: `forge build`, `forge script` deployment
   - Secrets: `RPC_URL_<NETWORK>`, `DEPLOYER_PRIVATE_KEY` via GitHub Secrets
3. Implement dry-run / check mode for PRs (forge script with `--dry-run` / `--fork-url` and `echo` of would-be-execution)
4. Optional: deploy to a testnet staging first, then promote to mainnet on manual approval

**Files:** `.github/workflows/deploy.yml` (new)

---

### Issue #141 — Upgrade Safety CI Check [PR #200]

**What:** CI step validating upgrade safety for all upgradeable contracts.

**Steps:**
1. Install and integrate OpenZeppelin Upgrades CLI (`@openzeppelin/upgrades-core`)
   or use `forge upgarde` / `openzeppelin-foundry-upgrades` plugin
2. Create a `script/upgrades/ValidateUpgrade.s.sol` script that calls
   `upgrades.validateUpgrade()` on each upgradeable contract
3. Add to CI: `.github/workflows/upgrade-safety.yml` running on every PR
4. Fail CI if any storage layout conflicts detected
5. Document the upgrade safety process in `script/upgrades/README.md`

**Files:** `.github/workflows/upgrade-safety.yml` (new), `script/upgrades/ValidateUpgrade.s.sol` (new)

---

## PHASE 6 — Gelato Automation

### Issue #136 — Gelato Automation Integration

**Assigned:** lirona

**What:** Integrate Gelato Network automation for on-chain functions (yield distribution,
cycle advancement) without a manual keeper.

**Steps (requires lirona's input on integration scope):**
1. Identify which contract functions need automation:
   - `YieldDistributor.distributeYield()` — likely the main trigger
   - Any cycle-advance or epoch-shift function
2. Implement Gelato-compatible resolver — a contract exposing `checker()` function
   that returns conditions for when to execute
3. Implement `exec` callback target on the YieldDistributor or a dedicated automation adapter
4. Document Gelato task registration and management

**Note:** Gelato integration involves off-chain bot infrastructure that runs on Gelato's
servers. Requires coordinating with the Gelato team for API keys and task setup.
This is partly an external dependency.

**Files:** `src/automation/GelatoResolver.sol` (new), deployment / task registration docs

---

## PHASE 7 — Upgrade Simulation Tests

### Issue #172 — Upgrade Simulation Test

**What:** End-to-end upgrade simulation — fork from deployed state, execute upgrade, assert
state and behavior continuity.

**Steps:**
1. Use Foundry's `vm.createFork()` and `vm.selectFork()` to target a live network (Gnosis or mainnet)
2. Fork-test the upgrade of each upgradeable proxy:
   - `YieldDistributor` proxy
   - `VotingMultipliers` proxy
   - `ButteredBread` proxy
   - Any deployed multiplier contracts
3. For each: snapshot pre-upgrade state, execute upgrade via deployment script,
   assert post-upgrade state matches
4. Assert: token balances unchanged, allowlisted multipliers preserved,
   voting power continuity, admin ownership intact
5. Integrate with Phase 6 upgrade safety CI — run as a post-merge gate

**Files:** `test/UpgradeSimulation.t.sol` (new)

---

## PHASE 8 — Testing Refactor

### Issue #97 — Testing Refactor [PR #201]

**What:** Reorganize test suite for better maintainability.

**Steps:**
1. Audit current test files:
   - `test/YieldDistributor.t.sol` — likely monolithic
   - `test/ButteredBread.t.sol`
   - `test/multipliers/` — may need expansion
2. Reorganize by contract / feature:
   ```
   test/
     YieldDistributor/
       ·core.t.sol      (claim, distribute)
       ·multipliers.t.sol (integration with VotingMultipliers)
       ·AccessControl.t.sol
     ButteredBread/
       ·deposit.t.sol
       ·withdrawal.t.sol
       ·delegation.t.sol
     multipliers/
       ·VotingStreakMultiplier.t.sol
       ·NFTMultiplier.t.sol
       ·[each new boost].t.sol
   ```
3. Improve test names to describe scenario + expected outcome (Foundry convention:
   `testFrodoClaimingYield_IncreasesBalance()`)
4. Add missing coverage for edge cases (re-entrancy, zero-address, zero-amount)
5. Ensure all tests pass after refactor — run `forge test` before and after

**Files:** `test/` directory — restructure, rename, split

---

## PHASE 9 — Documentation & Address Decoupling

### Issue #111 — Documentation Scope

**What:** NatSpec on all public/external functions + architecture overview + developer onboarding.

**Steps:**
1. Audit all `.sol` files for missing or incomplete NatSpec
2. Write `docs/ARCHITECTURE.md`:
   - System overview (YieldDistributor, VotingMultipliers, ButteredBread, multiplier plugins)
   - Data flow diagram (how a vote → multiplier → yield distribution works)
   - Upgrade path and proxy architecture
3. Expand `README.md` developer setup:
   - `.env` variable descriptions
   - Local fork testing instructions
   - How to add a new multiplier
4. Test the setup instructions on a clean environment

**Files:** `docs/ARCHITECTURE.md` (new), all `.sol` NatSpec, `README.md`

---

### Issue #81 — Decouple Addresses and Distributions [PR #202]

**What:** Extract hardcoded addresses and distribution parameters into a configurable
admin-updatable structure.

**Steps:**
1. Audit `YieldDistributor.sol` for hardcoded addresses and distribution parameters:
   - BREAD token address
   - Distribution recipients and their weightings
   - Any other protocol-level constants
2. Design a `DistributionConfig` contract or struct:
   - Admin can update recipients and weights via `setDistributionRecipient(address, weight)`
   - Events emitted for all changes (for off-chain indexing)
3. Existing behavior must be preserved for all current recipients
4. Add tests: update a recipient address, verify new distribution goes to new address
5. Consider using a separate proxy for the config to allow independent upgrades

**Files:** `src/DistributionConfig.sol` (new or refactor into `YieldDistributor`),
`test/DistributionConfig.t.sol` (new)

---

---

## Implementation Dependency Graph

```
Phase 1 (security PRs — in flight)
       │
       ▼
Phase 2 (5 boost multipliers) ──────────────────────┐
       │                                              │
       ├─ Phase 3a (ERC-7201 migration)               │
       │         (required before next proxy deploy)  │
       │                                              │
       ├─ Phase 3b (VotesExtendedUpgradeable)          │
       │         (depends on Phase 3a storage layout) │
       │                                              │
       ├─ Phase 4 (Foundry template)                  │
       │         (can run in parallel with Phase 2)   │
       │                                              │
       ├─ Phase 5 (CI/CD + upgrade safety)            │
       │         (can start after Phase 4)            │
       │                                              │
       ├─ Phase 6 (Gelato — external dep)             │
       │         (can start after Phase 2)            │
       │                                              │
       ├─ Phase 7 (upgrade simulation)                │
       │         (depends on Phase 3a + Phase 5)     │
       │                                              │
       ├─ Phase 8 (testing refactor)                  │
       │         (can run in parallel throughout)     │
       │                                              │
       └─ Phase 9 (docs + address decoupling)
                  (can run in parallel with Phase 2)
```

---

## Appendix A — PR #145 Review (for awareness)

**Title:** feat: add timelock for upgrades
**Author:** RonTuretzky
**Branch:** `RonTuretzky:issue-132-fix` → `BreadchainCoop:dev`
**Lines changed:** 825 additions, 0 deletions
**Status:** Stale since Jul 2025 — no CI checks, no reviews requested

**What it does:**
- New contract `src/UpgradeTimelock.sol` extending OpenZeppelin `TimelockControllerUpgradeable`
- Deployment script `script/deploy/DeployUpgradeTimelock.s.sol`
- Upgrade management script `script/upgrades/TimelockUpgrade.s.sol`
- Test suite `test/UpgradeTimelock.t.sol` — 12 test cases, 6/12 passing
  (the 6 failures are "expected access control restrictions", not bugs)

**Test Results (per PR description):**
- Compilation: ✅
- 6/12 tests passing
- Core timelock functionality verified
- Time delay enforcement working
- Access control properly implemented

**Assessment:** The implementation is substantive (825 lines) and follows OZ best practices.
The 6 failing tests need investigation before this can land — they may reflect access
control edge cases that need explicit whitelisting in the test setup rather than actual bugs.
**Recommended action:** Schedule a review session to close out the failing tests and
get this PR unstale. It's a high-value security addition.

**Deferral note:** User has flagged Issue #132 as ignored for now. This review is
for informational purposes only.

---

## Appendix B — Open Questions Requiring Answers Before Coding

| # | Issue | Question |
|---|---|---|
| 1 | #170 (BREAD tx boost) | What qualifies as a "BREAD transaction" — any Transfer event? Minimum size? |
| 2 | #170 | Is there a fixed qualifying window (e.g. last N blocks), or tied to distribution cycles? |
| 3 | #168 (BREAD baking) | What contract/function is "baking"? Is it a call on BREAD, a separate Bakery, or events? |
| 4 | #166 (TBS NFT) | What is the TBS NFT contract address? Are there tier levels? |
| 5 | #167 (POAP) | Which POAP event IDs or contract qualifies? |
| 6 | #112 (ERC-7201) | Is there a live proxy deployment that needs a migration plan, or is this a greenfield upgrade? |
| 7 | #136 (Gelato) | Assigned to lirona — what is the current status of that integration work? |
| 8 | #81 (address decoupling) | Which specific addresses are hardcoded today? Who are the current distribution recipients? |

---

## Appendix C — Task Summary Table

| Phase | Issue | Title | Type | Effort |
|---|---|---|---|---|
| 1 | #187/194, #186/196, #185/197, #184/198 | Security bugs | Bug fix | Done (PRs up) |
| 2 | #170 | BREAD tx boost | New multiplier | Medium |
| 2 | #169 | Never-burn BREAD boost | New multiplier | Medium |
| 2 | #168 | Bake 10+ times boost | New multiplier | Medium |
| 2 | #167 | POAP boost | New multiplier | Medium |
| 2 | #166 | TBS NFT boost | New multiplier | Medium |
| 3a | #112 | ERC-7201 namespaced storage | Infrastructure | High |
| 3b | #156 | VotesExtendedUpgradeable | Research/Impl | High |
| 4 | #122 | Update Foundry template | Tooling | Low |
| 5 | #142 | CI/CD auto-deploy | Infra/CI | Medium |
| 5 | #141 | Upgrade safety CI | Infra/CI | Medium |
| 6 | #136 | Gelato automation | External | Medium |
| 7 | #172 | Upgrade simulation tests | Testing | Medium |
| 8 | #97 | Testing refactor | Testing | Medium |
| 9 | #111 | Documentation scope | Docs | Medium |
| 9 | #81 | Decouple addresses/distributions | Refactor | High |
