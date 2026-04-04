# SOLIDARITY FUND — Agent Handover Document
Generated: 2026-04-04
Author: Moonsong (Tranquil-Flow/Evi Nova)

## REPO CONTEXT

**Repo:** BreadchainCoop/solidarity-fund
**Clone:** https://github.com/BreadchainCoop/solidarity-fund.git
**Local working dir used:** /tmp/solidarity-fund
**Default branch:** dev
**Latest release tag:** v1.3.0 (in test/upgrades/latest/.tag)
**Solidity version:** 0.8.27
**Foundry:** forge + cast + anvil. Binaries at ~/.foundry/bin/
**RPC endpoints (in foundry.toml):** gnosis = ${GNOSIS_RPC_URL}, sepolia = ${SEPOLIA_RPC_URL}

### Repo structure
```
src/
  YieldDistributor.sol          # Main voting + yield distribution
  ButteredBread.sol             # ERC20 wrapper with deposit/withdrawal
  VotingMultipliers.sol          # Voting multiplier calculation logic
  multipliers/
    VotingStreakMultiplier.sol  # Streak-based multiplier
    NFTMultiplier.sol
    PermanentNFTMultiplier.sol
  interfaces/
    IVotingMultipliers.sol
    IYieldDistributor.sol
    IButteredBread.sol
    IBread.sol
  libraries/
    MultiplierConstants.sol
test/
  YieldDistributor.t.sol        # 52,633 lines, 34 tests — NEEDS REFACTOR (#97)
  ButteredBread.t.sol
  Fixes184_185_186.t.sol        # New test file with 13 tests (2026-04-04)
  upgrades/latest/              # Flattened contracts from v1.3.0
    .tag = v1.3.0
    YieldDistributor.sol
    ButteredBread.sol
script/
  upgrades/
    ValidateUpgrade.s.sol       # OZ upgrade safety check script
    README.md                   # Manual upgrade instructions
  deploy/
    DeployYieldDistributor.s.sol
    DeployButteredBread.sol
    DeployNFTMultiplier.s.sol
    DeployVotingStreakMultiplier.s.sol
.github/workflows/
  test.yml                      # Forge build + test on every push/PR
  CODEOWNERS                    # @RonTuretzky @kassandraoftroy
```

---

## PART 1: EXISTING PRs — STATUS AND ACTIONS NEEDED

### PR #195 ✅ READY TO MERGE (no action needed from you)
- **Title:** fix: resolve critical voting exploits (#184, #185, #186)
- **Branch:** fix/184-185-186-critical-voting-bugs (on origin)
- **Status:** Mergeable, targeting dev
- **What it does:** Combined fix for 3 critical bugs — distributesYieldGK multiplier bypass (#184), streak multiplier spam (#185), duplicate multiplier index inflation (#186)
- **Files changed:** VotingMultipliers.sol, YieldDistributor.sol, IVotingMultipliers.sol, VotingStreakMultiplier.sol, test/Fixes184_185_186.t.sol
- **Tests:** 13 new tests passing on Gnosis fork
- **Action needed:** MERGE THIS FIRST. It does NOT touch ButteredBread.sol, so it will not conflict with any other open PR.

### PR #194 ✅ READY TO MERGE — fee-on-transfer fix
- **Title:** Ss251fix/187 fee on transfer accounting
- **Branch:** ss251fix/187-fee-on-transfer-accounting (on origin)
- **Author:** bagelface
- **Status:** Mergeable, targeting dev
- **What it does:** Fixes ButteredBread._deposit() trusting the _amount parameter instead of checking actual tokens received. Also adds FeeOnTransferERC20 mock for testing.
- **Files changed:** src/ButteredBread.sol (+8 -4), src/test/FeeOnTransferERC20.sol (+28), test/ButteredBread.t.sol (+149)
- **Conflicts with #195?** NO — #195 does not touch ButteredBread.sol or any ButteredBread test files. Merge #195 first, then this one.
- **Action needed:** Review and merge after #195. Check that tests pass.

### PR #145 ✅ READY TO MERGE — timelock for upgrades
- **Title:** feat: add timelock for upgrades
- **Branch:** issue-132-fix (on origin)
- **Author:** RonTuretzky
- **Status:** Mergeable, targeting dev
- **What it does:** Adds UpgradeTimelock contract (extends OZ TimelockControllerUpgradeable) + deploy/upgrade scripts + 322-line test suite. 4 files changed, 825 additions.
- **Files changed:** src/UpgradeTimelock.sol, script/deploy/DeployUpgradeTimelock.s.sol, script/upgrades/TimelockUpgrade.s.sol, test/UpgradeTimelock.t.sol
- **Action needed:** Review and merge. 6/12 tests passing is expected per author (some fail due to access control restrictions). Merge when satisfied.

### PR #163 ✅ READY TO MERGE — staging deployment
- **Title:** Staging deployment
- **Branch:** staging-deployment (on origin)
- **Author:** RonTuretzky
- **Status:** Mergeable, targeting dev
- **What it does:** Adds GitHub Actions workflow to auto-deploy all contracts to testnet on merge to dev. Adds TESTNET_DEPLOYMENT.md docs.
- **Files changed:** .github/workflows/deploy-testnet.yml (+443 lines), TESTNET_DEPLOYMENT.md (+115 lines)
- **Action needed:** Review and merge. No conflicts with any other open PR.

### PR #196, #197, #198 ❌ ALREADY CLOSED
- **Title:** Individual fix PRs for #184, #185, #186
- **Status:** Closed via API (gh api PATCH). These were duplicates of #195. Do NOT reopen.
- **Action needed:** None.

---

## PART 2: NEW PRs TO CREATE (in recommended order)

### PR-A — Issue #122 — Update Foundry Template
**Issue:** https://github.com/BreadchainCoop/solidarity-fund/issues/122
**Branch name:** `refactor/update-foundry-template`
**Est. effort:** 3–5 hours

**What to do:**

1. **Sync boilerplate repo first** — BreadchainCoop/solidity-foundry-boilerplate is 7 commits behind defi-wonderland/solidity-foundry-boilerplate:main. The missing commits add:
   - `solhint.json` (solhint linting)
   - `.husky/` (pre-commit hooks)
   - `commitlint.config.js` (conventional commits)
   - `natspec-smells.config.js` (NatSpec quality)
   - `package.json`/`yarn.lock` (JS tooling)

2. **Pull into solidarity-fund:**
   - Copy new configs from updated boilerplate into solidarity-fund
   - Update foundry.toml if needed
   - Add linting step to `.github/workflows/test.yml`
   - Add commitlint to husky pre-commit hook

**Key file to check:** `.github/workflows/test.yml` (currently just forge build + test — add lint step)

**Verification:** `forge fmt` passes, solhint passes, forge build passes.

---

### PR-B — Issue #141 — Automate Upgrade Safety Check in CI
**Issue:** https://github.com/BreadchainCoop/solidarity-fund/issues/141
**Branch name:** `feat/upgrade-safety-ci`
**Est. effort:** ~2 hours

**What to do:**

Create `.github/workflows/upgrade-safety.yml`:

```yaml
name: Upgrade Safety Check

on:
  push:
    branches: [dev]
    paths: ['src/**/*.sol', 'script/**/*.sol']
  pull_request:
    branches: [dev]
    paths: ['src/**/*.sol', 'script/**/*.sol']

jobs:
  validate-upgrade:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # need tags

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1

      - name: Flatten contracts for comparison
        run: |
          forge flatten src/YieldDistributor.sol > test/upgrades/latest/YieldDistributor.sol
          forge flatten src/ButteredBread.sol > test/upgrades/latest/ButteredBread.sol

      - name: Run upgrade safety validation
        run: forge script script/upgrades/ValidateUpgrade.s.sol
        env:
          GNOSIS_RPC_URL: ${{ secrets.GNOSIS_RPC_URL }}

      - name: Commit updated flattened files
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: 'chore: update flattened contracts for upgrade safety'
          file_pattern: 'test/upgrades/latest/*.sol'
```

**IMPORTANT NOTES:**
- The `.tag` file reads `v1.3.0`. The OZ upgrades plugin's `validateUpgrade()` does NOT require the tag file to be accurate — it only compares the flattened file against the current implementation. You do NOT need to update the tag file in CI.
- The CI commits the updated flattened files back to dev automatically, keeping the upgrade baseline current.
- This workflow only triggers when `src/**/*.sol` or `script/**/*.sol` files change.

**Verification:** Run locally: `forge script script/upgrades/ValidateUpgrade.s.sol`. Should succeed with no errors.

---

### PR-C — Issue #97 — Testing Refactor
**Issue:** https://github.com/BreadchainCoop/solidarity-fund/issues/97
**Branch name:** `refactor/testing-infrastructure`
**Est. effort:** 6–10 hours

**What to do:**

**Goal:** Break up the 52,633-line `test/YieldDistributor.t.sol` into reusable components.

**Structure to create:**
```
test/
  helpers/
    TestHelpers.sol              # NEW — base contract with shared setup
    YieldDistributorTestConfig.sol  # NEW — typed access to test_deploy.json
  YieldDistributor.t.sol         # MODIFY — slim down, import TestHelpers
  ButteredBread.t.sol           # MODIFY — slim down, import TestHelpers
  Fixes184_185_186.t.sol       # KEEP AS-IS — already clean
```

**TestHelpers.sol** should contain:
- `createFork()` — forks Gnosis at block 32_323_232_323
- `newYieldDistributor(address[] memory _projects)` — full proxy deployment boilerplate
- `setUpAccountsForVoting(address[] memory accounts)` — already exists in t.sol, move here
- `setUpForCycle(YieldDistributorTestWrapper _yd)` — already exists in t.sol, move here
- `mintBreadAndDelegate(address account, uint256 amount)` — combine common minting pattern

**YieldDistributorTestConfig.sol** should:
- Read `test/test_deploy.json` once in constructor
- Expose typed getters: `projects()`, `bread()`, `cycleLength()`, `_cycleLength`, `_precision`, `_minVotingAmount`, `_minHoldingDuration`, `_yieldFixedSplitDivisor`, `_lastClaimedBlockNumber`, `_blocktime`, `maxPoints`

**Inherit deployment scripts into tests:**
- Import `DeployYieldDistributor.s.sol` into tests so the deployment code path is actually exercised
- This ensures deployment scripts don't diverge from actual deployed code

**Fuzzing modifiers:**
```solidity
modifier withValidPoints(uint256[] memory pts) {
    require(pts.length > 0 && pts.length <= maxPoints);
    _;
}
```

**CAUTION:** The existing `YieldDistributor.t.sol` has 34 tests across 52,633 lines. When you slim it down, you must NOT change any test logic — only extract the setup boilerplate into TestHelpers. The test assertions and behavior must remain identical.

**Verification:** `forge test` passes with identical results before and after refactor.

---

### PR-D — Issue #81 — Couple Project Addresses and Distributions
**Issue:** https://github.com/BreadchainCoop/solidarity-fund/issues/81
**Branch name:** `refactor/project-struct-coupling`
**Est. effort:** 4–6 hours
**⚠️ BREAKING CHANGE — requires proxy redeployment**

**What to do:**

**Before:**
```solidity
address[] public projects;          // [0xaaa, 0xbbb]
uint256[] public projectDistributions; // [100, 200]
// Risk: these can silently go out of sync
```

**After:**
```solidity
struct Project {
    address addr;
    uint256 distribution;
}
Project[] public projects;  // projects[0].addr + projects[0].distribution always coupled
```

**Files to change:**
1. `src/YieldDistributor.sol` — change `projects` from `address[]` to `Project[]`; update all functions that read/write `projects[i]` and `projectDistributions[i]`:
   - `addProject(address _project, uint256 _distribution)` — signature changes
   - `removeProject(address _project)` — still searches by `.addr`
   - `_castVote()` — uses `projects[i].addr` and `projects[i].distribution`
   - `_computeVotedDistribution()` — uses `projects[i].addr`
   - `castVote()` — no change to logic, just storage access pattern
   - `castVoteWithMultipliers()` — no change to logic
   - `getCurrentVotedDistribution(address _account)` — uses `projects[i].addr`
   - `distributeYield()` — uses `projects[i]`
   - `getProjects()` — returns `Project[]` (update IYieldDistributor interface too)

2. `src/interfaces/IYieldDistributor.sol` — update `addProject`/`removeProject`/`getProjects` signatures

3. `src/VotingMultipliers.sol` — `getProjects()` return type changes

4. All tests and scripts that reference `projects[i]` or `projectDistributions[i]`:
   - `test/YieldDistributor.t.sol`
   - `test/Fixes184_185_186.t.sol`
   - `script/deploy/DeployYieldDistributor.s.sol`
   - `script/deploy/config/deployYD.json`

**Queues don't change:** `queuedProjectsForAddition` and `queuedProjectsForRemoval` remain `address[]` — these are just pending addresses, not vote-coupled data.

**Important note on storage:**
- Adding a new struct type doesn't break storage layout if you add it as a new variable.
- The OLD `projects` (address[]) and `projectDistributions` (uint256[]) will need to be migrated or deprecated.
- Best approach: rename old arrays with `_deprecated_` prefix and add new `Project[] public projects` struct. This preserves storage layout compatibility with existing proxies (proxy reads from the old slots and gets zeroes for the new struct).
- Then write a migration function that reads from old arrays and populates the new struct.

**Verification:**
1. `forge build` — should compile without errors
2. `forge test` — all tests pass
3. `forge script script/upgrades/ValidateUpgrade.s.sol` — validates storage compatibility (will need to flatten first)

---

### PR-E — Issue #112 — ERC-7201 Namespaced Storage
**Issue:** https://github.com/BreadchainCoop/solidarity-fund/issues/112
**Branch name:** `refactor/erc-7201-namespaced-storage`
**Est. effort:** 20–30 hours
**⚠️ BREAKING CHANGE — all 4 proxies must be redeployed**

**What to do:**

**Concept:** Replace all storage state variables with ERC-7201 namespaced regions.

**Example pattern:**
```solidity
bytes32 constant YIELD_DISTRIBUTOR_STORAGE =
    bytes32(uint256(keccak256("bread.yield-distributor")) - 1);

function _getYDStorage()
    internal
    pure
    returns (YieldDistributorStorage storage ds)
{
    assembly { ds.slot := YIELD_DISTRIBUTOR_STORAGE }
}

struct YieldDistributorStorage {
    IBread BREAD;
    uint256 PRECISION;
    uint256 cycleLength;
    uint256 maxPoints;
    // ... ALL state variables ...
    mapping(address => uint256) voterEffectiveVotes;
    // ...
}
```

**Contracts to refactor:**
- `YieldDistributor.sol` — all ~20 state variables → namespaced
- `ButteredBread.sol` — all state variables → namespaced
- `VotingMultipliers.sol` — all state variables → namespaced
- `NFTMultiplier.sol`, `PermanentNFTMultiplier.sol`, `VotingStreakMultiplier.sol`

**Deployment implications:**
- ALL 4 proxy contracts (YieldDistributor, ButteredBread, NFTMultiplier, VotingStreakMultiplier) must be redeployed to NEW proxy addresses
- Old proxies become useless
- This is a coordinated deployment event — need to plan with the multisig holders

**Consider pairing with PR-D (#81):** Both require proxy redeployment. Doing them together means only ONE redeployment event. The struct coupling from #81 could be implemented alongside ERC-7201 in the same namespaced storage structs.

**Recommended approach:**
1. Implement #112 using the same namespaced storage structure
2. Include the Project struct from #81 as part of the namespaced storage
3. One combined PR with both breaking changes = single proxy redeployment

**Verification:**
1. `forge build` — compiles
2. `forge test` — all tests pass
3. Full integration test from the latest tagged release state
4. `forge script script/upgrades/ValidateUpgrade.s.sol` — will FAIL because storage layout is fundamentally different. This is expected. Document that this requires new proxy deployment.

---

## PART 3: ISSUE COMMENTS ALREADY POSTED

### ✅ Already done (by Moonsong):
- **#136 (Gelato)** — Comment posted showing Gelato is dead, suggesting Keeper bot alternatives
- **#172 (Test upgrade simulation)** — Comment posted showing it's already done via ValidateUpgrade.s.sol

### Still needed:

**#171 (Release v1.0.5 tracking issue)** — Post this comment:
```
## v1.0.5 Scope — Implementation Plan

The following issues are planned for v1.0.5. Each will be a separate PR:

| # | Issue | PR Branch | Type | Status |
|---|---|---|---|---|
| #122 | Update Foundry template | refactor/update-foundry-template | Enhancement | In progress |
| #141 | Automate upgrade safety CI | feat/upgrade-safety-ci | Infrastructure | In progress |
| #97 | Testing refactor | refactor/testing-infrastructure | Refactor | Planned |
| #81 | Couple project addresses+distributions | refactor/project-struct-coupling | Enhancement (breaking) | Planned |
| #112 | ERC-7201 namespaced storage | refactor/erc-7201-namespaced-storage | Enhancement (breaking) | Planned |

Recommended merge order: #122 → #141 → #97 → #81 + #112 (together, paired redeployment)

Additional items still open from v1.0.4 that are done but unmerged:
- PR #145 (timelock for upgrades) — ready to merge
- PR #163 (staging deployment CI) — ready to merge
```

**#170, #169, #168, #167, #166 (Voting Boosts)** — Close each with this comment:
```
This voting boost idea is noted but not currently prioritized for implementation. 
The core team has not discussed or approved a design for this feature.
If/when there is governance appetite to implement voting boosts, a fresh issue 
with a concrete spec would be welcome. Closing to keep the issue list actionable.
```
Labels to add before closing: `invalid` or ` wontfix`

**#164 (Release v1.0.4)** — Close with:
```
v1.0.4 was effectively superseded by v1.3.0. The key items that were part 
of the v1.0.4 scope (timelock #132, CI/CD #142) have PRs in flight (#145, #163).
The ERC-7201 (#112) and testing refactor (#97) work continues in v1.0.5 planning.
```

**#111 (Documentation Scope)** — Keep open per user request. No comment needed yet.

---

## PART 4: ISSUES TO CLOSE (no comment needed, just close)

| # | Title | Close label |
|---|---|---|
| #136 | Gelato Automation | `invalid` (Gelato is dead; alternatives exist) |
| #172 | Test Upgrade Simulation for Latest Release | `completed` (already done) |
| #170 | Voting Boost for BREAD Transactions | `wontfix` |
| #169 | Boost for Never Burning BREAD | `wontfix` |
| #168 | Boost for Baking ≥10 BREAD | `wontfix` |
| #167 | POAP Boost for Attending Community Calls | `wontfix` |
| #166 | Voting Boost for TBS NFT Holders | `wontfix` |
| #164 | Release v1.0.4 | `completed` (superseded by v1.3.0) |

**How to close in bulk:**
```bash
gh issue close BreadchainCoop/solidarity-fund#136 --repo BreadchainCoop/solidarity-fund
# repeat for each
```
Or use `gh api -X PATCH repos/BreadchainCoop/solidarity-fund/issues/<number> -f state=closed`

---

## PART 5: ISSUES TO KEEP OPEN

| # | Title | Notes |
|---|---|---|
| #111 | Documentation Scope | User asked to keep open; blocked on team decision |
| #156 | Extend VotesExtendedUpgradeable for variable delegations | Legitimate enhancement; needs research first |
| #122 | Update Foundry Template | PR-A in progress |
| #141 | Automate Upgrade Safety Check in CI | PR-B in progress |
| #97 | Testing Refactor | PR-C planned |
| #81 | Couple project addresses+distributions | PR-D planned (breaking) |
| #112 | ERC-7201 Namespaced Storage | PR-E planned (breaking) |

---

## PART 6: MERGE ORDER FOR OPEN PRs

```
1. MERGE #195  ← voting exploits fix (safe, no conflicts)
2. MERGE #194  ← fee-on-transfer fix (clean diff, no conflicts with above)
3. MERGE #145  ← timelock for upgrades (independent)
4. MERGE #163  ← staging deployment CI (independent)
5. Then create and merge PR-A through PR-E in order
```

---

## PART 7: TESTING NOTES

**Run tests:**
```bash
cd /tmp/solidarity-fund
forge test --fork-url https://gnosis.publicnode.com -vvv
```

**Current test status (2026-04-04):**
- `test/YieldDistributor.t.sol` — 34 tests (existing)
- `test/ButteredBread.t.sol` — existing
- `test/Fixes184_185_186.t.sol` — 13 NEW tests, all passing

**Key test file for #184/#185/#186:**
`test/Fixes184_185_186.t.sol` — dedicated test file for the three voting bug fixes. This file uses `YieldDistributorTestWrapper` and a `VotingStreakMultiplier` test instance. Tests use `vm.roll()` for block manipulation and `vm.createSelectFork()` for Gnosis chain forking.

**IMPORTANT:** After merging #195, the `voterEffectiveVotes` mapping in YieldDistributor.sol will be live. The `castVoteWithMultipliers()` stores multiplier-adjusted voting power there. The `_computeVotedDistribution()` uses it. Make sure #194's ButteredBread.sol changes don't inadvertently affect the YieldDistributor's voterEffectiveVotes logic.

---

## PART 8: DEPENDENCIES AND PAIRING OPPORTUNITIES

### Pair PR-D (#81) + PR-E (#112) for single redeployment
Both are breaking changes requiring new proxy addresses. Doing them together:
- Saves one full redeployment event
- The Project struct can be part of the ERC-7201 namespaced storage
- Combined effort is still ~25-30 hours (not additive)

### Run PR-A (#122) early
The Foundry template update (solhint, husky, commitlint) makes the codebase healthier before tackling bigger refactors. Easy win, builds momentum.

### PR-B (#141) is a prerequisite for safe upgrades
Before doing PR-D or PR-E (both breaking changes requiring redeployment), the upgrade safety CI should be in place to catch regressions.

**Recommended sequence:** PR-A → PR-B → PR-C → PR-D+PR-E (together)

---

## APPENDIX: KEY CONTRACT INTERFACES

### YieldDistributor.sol state variables (current, before PR-D/E)
```
IBread public BREAD;
uint256 public PRECISION;
uint256 public cycleLength;
uint256 public maxPoints;
uint256 internal _deprecated_minRequiredVotingPower;
uint256 public lastClaimedBlockNumber;
uint256 public currentVotes;
address[] public projects;          ← #81: change to Project[] struct
uint256[] public projectDistributions; ← #81: merge into Project struct
address[] public queuedProjectsForAddition;
address[] public queuedProjectsForRemoval;
mapping(address => uint256) public accountLastVoted;
mapping(address => uint256[]) voterDistributions;
uint256 public yieldFixedSplitDivisor;
IERC20Votes public BUTTERED_BREAD;
uint256 public previousCycleStartingBlock;
address[] internal _deprecated_voters;
mapping(address => uint256[]) internal _holderToDistribution;
mapping(address => uint256) internal _holderToDistributionTotal;
uint256 public votingCycle;
uint256 public votersCount;
mapping(uint256 => address) public voterAtIndex;
mapping(address => uint256) public voterVotedCycle;
mapping(address => uint256) public voterEffectiveVotes;  ← #184 fix
```

### Deployed contract addresses (from script/upgrades/README.md)
```
Proxy Admin (Breadchain multisig): 0x918dEf5d593F46735f74F9E2B280Fe51AF3A99ad
Yield Distributor Proxy:           0xeE95A62b749d8a2520E0128D9b3aCa241269024b
```

