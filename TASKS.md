# Solidarity Fund - Task Tracker
# BreadchainCoop/solidarity-fund
# https://github.com/BreadchainCoop/solidarity-fund
# Last updated: 2026-04-04

Issues with open PRs are marked SKIP and excluded from active work.
Remaining 20 workable issues are grouped by priority below.

---

## SKIP - Issues With Existing PRs

  #187 - [SKIP] Has open PR #188
  #132 - [SKIP] Has open PR #145
  #122 - [SKIP] Has PR #199 (refactor/update-foundry-template)
  #141 - [SKIP] Has PR #200 (feat/upgrade-safety-ci)  
  #142 - [SKIP] Has PR #200 (feat/upgrade-safety-ci)
  #97  - [SKIP] Has PR #201 (refactor/testing-infrastructure)
  #81  - [SKIP] Has PR #202 (refactor/project-struct-coupling)
  #112 - [SKIP] Has PR #203 (refactor/erc-7201-namespaced-storage)
  #186 - [SKIP] Closed #195, superseded by individual PR #196
  #185 - [SKIP] Closed #195, superseded by individual PR #197
  #184 - [SKIP] Closed #195, superseded by individual PR #198

---

## PRIORITY 1 - Security Bugs (Fix First)

These issues represent exploitable or incorrect behavior in the on-chain
voting and yield distribution logic. They must be resolved before any release.

---

  TASK-001 | Issue #186 | Voting Power Amplified by Repeating Multiplier Indexes
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/186

  Description:
    A user can artificially inflate their voting power by submitting duplicate
    multiplier indexes in a single call. The contract does not validate that
    the provided indexes are unique before applying each multiplier, so the
    same boost can be counted multiple times. This results in voting power far
    exceeding the intended cap.

  Acceptance Criteria:
    - Add de-duplication or uniqueness checks on multiplier index arrays before
      any boost calculation is applied.
    - Add unit tests covering the duplicate-index attack vector.
    - Voting power must not exceed the sum of all distinct applicable multipliers.

---

  TASK-002 | Issue #185 | Streak Multiplier Can Be Maxed in One Cycle
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/185

  Description:
    The streak multiplier is designed to reward consistent participation over
    multiple cycles, but a logic flaw allows a user to reach the maximum streak
    multiplier within a single distribution cycle. This bypasses the intended
    time-based progression of the boost.

  Acceptance Criteria:
    - Enforce that streak multiplier increments are bounded to one step per
      eligible cycle.
    - Prevent any single transaction or cycle from jumping multiple streak levels.
    - Add regression tests covering single-cycle max-streak scenarios.

---

  TASK-003 | Issue #184 | distributeYieldGK Bypasses Multipliers
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/184

  Description:
    The gatekeeper yield distribution function distributeYieldGK does not apply
    the standard voting power multipliers that the normal distribution path uses.
    This allows yields to be distributed without accounting for boosts or
    penalties, breaking parity between distribution paths.

  Acceptance Criteria:
    - Ensure distributeYieldGK applies the same multiplier logic as the primary
      distribution path, or explicitly document and enforce why it should differ.
    - Add tests asserting multiplier parity across both distribution entry points.

---

## PRIORITY 2 - Enhancements

New features and on-chain behavior improvements. These should be implemented
after all security issues are resolved and before v1.0.5 is cut.

---

  TASK-004 | Issue #170 | Voting Boost for BREAD Transactions
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/170

  Description:
    Introduce a voting power boost for users who have made BREAD token
    transactions within a qualifying window. This incentivizes active use of the
    BREAD token ecosystem as a condition for increased governance influence.

  Acceptance Criteria:
    - Define the qualifying transaction window and minimum threshold.
    - Implement and integrate the boost module into the multiplier pipeline.
    - Add tests for eligible and ineligible BREAD transaction histories.

---

  TASK-005 | Issue #169 | Boost for Never Burning BREAD
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/169

  Description:
    Add a voting power boost for users who have never burned BREAD tokens.
    This rewards long-term holders who demonstrate commitment to the ecosystem
    by not reducing the circulating supply.

  Acceptance Criteria:
    - Implement a burn-history check against the BREAD token contract.
    - Apply the boost only to addresses with zero lifetime burn activity.
    - Add tests for accounts with and without burn history.

---

  TASK-006 | Issue #168 | Boost for Baking 10+ Times
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/168

  Description:
    Grant a voting power boost to users who have baked BREAD 10 or more times.
    This rewards repeated participation in the baking process as a signal of
    ecosystem engagement.

  Acceptance Criteria:
    - Implement a bake-count lookup or on-chain event aggregation.
    - Apply the boost when the bake count meets or exceeds the threshold of 10.
    - Add tests for accounts at, above, and below the bake threshold.

---

  TASK-007 | Issue #167 | POAP Boost
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/167

  Description:
    Add a voting power boost for users who hold a qualifying POAP (Proof of
    Attendance Protocol) token. This rewards community members who have
    participated in Breadchain events or milestones.

  Acceptance Criteria:
    - Define which POAP event IDs or token contracts qualify.
    - Implement an ownership check against the POAP contract.
    - Add tests for holders and non-holders of qualifying POAPs.

---

  TASK-008 | Issue #166 | TBS NFT Boost
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/166

  Description:
    Add a voting power boost for holders of the TBS (The Bread Social) NFT.
    This extends the multiplier system to reward NFT-based community membership.

  Acceptance Criteria:
    - Identify the TBS NFT contract address and relevant token criteria.
    - Implement an ownership check and integrate into the multiplier pipeline.
    - Add tests for TBS NFT holders and non-holders.

---

  TASK-009 | Issue #156 | VotesExtendedUpgradeable Implementation
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/156

  Description:
    Implement or integrate VotesExtendedUpgradeable to extend the OpenZeppelin
    Votes module with upgradeability support. This is a prerequisite for safely
    upgrading governance-related contracts without losing voting state.

  Acceptance Criteria:
    - Implement VotesExtendedUpgradeable compatible with the existing governance
      setup.
    - Ensure storage layout is upgrade-safe (see also #112 for ERC-7201).
    - Add tests covering delegation and checkpoint behavior across upgrades.

---

  TASK-010 | Issue #112 | ERC-7201 Namespaced Storage
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/112

  Description:
    Migrate contract storage to use ERC-7201 namespaced storage slots. This
    prevents storage collisions in upgradeable contracts and aligns with current
    Solidity and OpenZeppelin best practices for proxy-based systems.

  Acceptance Criteria:
    - Refactor all upgradeable contracts to use ERC-7201 storage namespacing.
    - Verify storage layout compatibility with existing deployed proxy state.
    - Update or add upgrade safety tests (see also #141).

---

  TASK-011 | Issue #122 | Update Foundry Template
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/122

  Description:
    Update the project's Foundry template and tooling to the latest recommended
    configuration. This includes updating foundry.toml, remappings, forge
    dependencies, and any outdated patterns inherited from an older template.

  Acceptance Criteria:
    - Bring foundry.toml and remappings.txt up to current Foundry conventions.
    - Update forge-std and any other lib dependencies to latest stable versions.
    - Confirm all existing tests continue to pass after the update.

---

## PRIORITY 3 - Infrastructure and CI

Automation, deployment pipelines, and upgrade safety tooling. These improve
developer confidence and operational reliability.

---

  TASK-012 | Issue #142 | CI/CD Auto-Deploy Pipeline
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/142

  Description:
    Set up a CI/CD pipeline that automatically deploys contracts or publishes
    build artifacts on merge to the main branch or on tag push. This reduces
    manual deployment overhead and improves release consistency.

  Acceptance Criteria:
    - Define deployment targets (testnet, mainnet staging) and triggers.
    - Implement a GitHub Actions workflow for automated deployment.
    - Ensure secrets (RPC URLs, deployer keys) are managed via GitHub Secrets.
    - Dry-run mode must be available for PRs without executing live deployment.

---

  TASK-013 | Issue #141 | Upgrade Safety CI Check
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/141

  Description:
    Add a CI step that validates upgrade safety for all upgradeable contracts.
    This should catch storage layout conflicts, missing initializers, and other
    upgrade hazards before they reach a deployed network.

  Acceptance Criteria:
    - Integrate a tool such as OpenZeppelin Upgrades or a custom Foundry script
      to check storage layout diffs on every PR.
    - Fail the CI pipeline if any breaking storage changes are detected.
    - Document the upgrade safety process in the repo.

---

  TASK-014 | Issue #136 | Gelato Automation Integration
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/136

  Description:
    Integrate Gelato Network automation to trigger on-chain functions such as
    yield distribution or cycle advancement without relying on a manual keeper
    or centralized cron job.

  Acceptance Criteria:
    - Identify which contract functions require automated execution.
    - Implement Gelato-compatible resolver and execution logic.
    - Add documentation on how to register and manage Gelato tasks for this
      contract.

---

## PRIORITY 4 - Documentation and Releases

Release management, test coverage improvements, and developer documentation.
Complete these after security and enhancement work is merged.

---

  TASK-015 | Issue #171 | Release v1.0.5
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/171

  Description:
    Cut the v1.0.5 release. This should include all security fixes and
    enhancements targeted for this milestone, a changelog entry, and any
    required deployment artifacts or upgrade scripts.

  Acceptance Criteria:
    - All security issues (#184, #185, #186) must be merged before this release.
    - Changelog updated with all changes since v1.0.4.
    - Git tag v1.0.5 created and pushed.
    - Deployment artifacts or upgrade scripts published if applicable.

---

  TASK-016 | Issue #164 | Release v1.0.4
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/164

  Description:
    Cut the v1.0.4 release. Verify that all changes intended for this version
    are merged, the changelog is accurate, and any deployment steps are
    documented.

  Acceptance Criteria:
    - Changelog updated for v1.0.4.
    - Git tag v1.0.4 created and pushed.
    - Any outstanding blockers for this release identified and resolved or
      deferred to v1.0.5.

---

  TASK-017 | Issue #172 | Test Upgrade Simulation
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/172

  Description:
    Write a Foundry test or script that simulates a full contract upgrade end
    to end, including forking from a deployed state, executing the upgrade, and
    asserting that all state and behavior is preserved post-upgrade.

  Acceptance Criteria:
    - Fork test against a deployed environment (testnet or mainnet fork).
    - Assert storage continuity before and after upgrade.
    - Assert all core functions behave correctly after the upgrade completes.
    - Integrate with the upgrade safety CI check from #141.

---

  TASK-018 | Issue #111 | Documentation Scope
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/111

  Description:
    Define and write the documentation scope for the solidarity fund contracts.
    This includes NatSpec comments on all public and external functions,
    a high-level architecture overview, and a developer onboarding guide.

  Acceptance Criteria:
    - All public and external contract functions have complete NatSpec comments.
    - A README or docs folder contains an architecture overview diagram or
      description.
    - Developer setup instructions are clear and tested on a clean environment.

---

  TASK-019 | Issue #97 | Testing Refactor
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/97

  Description:
    Refactor the existing test suite for better organization, coverage, and
    maintainability. This includes splitting monolithic test files, improving
    test naming conventions, and ensuring edge cases for all major code paths
    are covered.

  Acceptance Criteria:
    - Tests reorganized by contract or feature area.
    - Test names clearly describe the scenario and expected outcome.
    - Coverage for all public and external functions measurably improved.
    - No existing passing tests are broken by the refactor.

---

  TASK-020 | Issue #81 | Decouple Addresses and Distributions
  Status: Open
  Repo: https://github.com/BreadchainCoop/solidarity-fund/issues/81

  Description:
    Refactor the contract or configuration to decouple hardcoded addresses from
    distribution logic. Currently addresses and distribution parameters appear
    to be tightly coupled, making it difficult to update recipients or
    parameters without contract changes or redeployment.

  Acceptance Criteria:
    - Addresses and distribution parameters are configurable via admin functions
      or a separate configuration contract rather than being hardcoded.
    - Existing behavior is preserved for all current recipients and distributions.
    - Add tests asserting that address and distribution updates work correctly
      without requiring a full redeployment.

---

## Summary

  Total workable issues: 20
  Security (fix first):  3   (TASK-001 to TASK-003)
  Enhancements:          8   (TASK-004 to TASK-011)
  Infrastructure/CI:     3   (TASK-012 to TASK-014)
  Docs/Releases:         6   (TASK-015 to TASK-020)
  Skipped (have PRs):    2   (#187 -> PR #188, #132 -> PR #145)

  Recommended order of execution:
    1. Resolve all PRIORITY 1 security bugs before any release.
    2. Implement PRIORITY 2 enhancements targeted for v1.0.5.
    3. Set up PRIORITY 3 infra/CI to support safe releases.
    4. Complete PRIORITY 4 docs, simulations, and cut releases.
