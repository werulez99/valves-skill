<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Variable-Flow Attribution Audit (BC-041)

Source-of-truth for the **Variable-Flow Attribution** sub-check run by the Validation Sweep Agent (Phase 4b iter 1). Emits `[VS-AT-1]` consolidated findings with multi-location tables, all tagged `[CORRECTNESS-WINNER]`. BC class: BC-041 in `~/.valves/state/bug_class_registry.md`.

## Purpose

Audited contracts often track the same conceptual quantity in multiple variables: `totalAssets` and `sum(individual balances)`, `globalRewardIndex` and `sum(per-user accrued)`, `totalShares` and `sum(balanceOf)`. When the variables drift — one is updated on a path, the other is not — downstream calculations mis-attribute funds, rewards, or voting power.

The Attribution Audit is mechanical: enumerate variable pairs that should track the same quantity, list every function that mutates either side, and flag pairs whose mutation sets diverge.

## Scope

Run over `{scratchpad}/state_variables.md` (storage variables) and `{scratchpad}/semantic_invariants.md` § Mirror Variable Pairs (if produced by Phase 4a.5.a Pass 1).

## § Detection methodology

### Step 1: Identify attribution pairs

A pair (A, B) is an **attribution pair** when:
- A and B are storage variables (or A is a single variable and B is `sum-over-mapping(...)`).
- They MUST track the same conceptual quantity per documented Key Invariants in `design_context.md` (e.g., "totalAssets equals the sum of all account balances").
- A canonical source for the pair list:
  1. Mirror Variable Pairs in `semantic_invariants.md` (if Phase 4a.5.a Pass 1 produced them).
  2. Common-pattern enumeration: any `total*` variable paired with the corresponding `mapping → balance` whose values are summed elsewhere.
  3. Reward index / accrued reward pairs (e.g., `rewardIndex` / `userRewardOwed[user]`).
  4. Vote-power / delegation pairs (e.g., `totalSupply` / `sum(votes[user])`).

### Step 2: Enumerate mutators per side

For each pair (A, B):
- List **every** function that writes A.
- List **every** function that writes B (or any element of the mapping for sum-over-mapping pairs).

### Step 3: Symmetric-difference flag

Compute the symmetric difference of the two mutator sets:
- Functions that write A but not B → `ATTR_GAP_A` (A leads, B lags).
- Functions that write B but not A → `ATTR_GAP_B` (B leads, A lags).

For each function in either set, classify the gap:
- **Branch-conditional**: function has both write paths but one is gated; check whether the gating condition can occur in production.
- **Asymmetric branch**: same function, but one branch writes A only and another writes B only — flag as `BRANCH_ATTR_GAP`.
- **Genuine omission**: function writes one side and never the other.

## § Output: consolidated `[VS-AT-1]`

```markdown
## [VS-AT-1] — Variable-Flow Attribution Mismatches  [CORRECTNESS-WINNER]
- BC-Class: BC-041 (Variable-Flow Attribution Audit)
- Severity: {worst across instances}
- Description: One or more storage variables that should track the same quantity have divergent mutator sets. Per-pair table below.

| Pair (A, B) | Function | Gap class | A mutated? | B mutated? | Pre-state stale? | Post-state stale? | Severity | Fix |
|---|---|---|---|---|---|---|---|---|
| totalAssets / sum(balances) | rebalance() | ATTR_GAP_A | YES | NO | totalAssets accurate | sum(balances) stale | High | also update affected balances mapping |
| rewardIndex / userRewardOwed | emergencyExit(user) | ATTR_GAP_B | NO | partial | rewardIndex stale | userRewardOwed cleared | Medium | call `_updateRewards(user)` before clearing |
| totalShares / balanceOf sum | mintWithFee() | BRANCH_ATTR_GAP | branch X only | branch Y only | branch-dep | branch-dep | High | unify branches |

- Worst-state severity (R10): {High}
- Recommendation: per-row fix above. Where appropriate, refactor the mutating function to use a helper that updates both sides atomically.
```

## § Severity rules

- Drift causes mis-attributed user funds (balance underflow, share-price wrong) → **High** baseline; **Critical** when the drift is reachable by an untrusted actor.
- Drift causes wrong reward accounting → **High** when an actor can extract more than entitled, **Medium** when only griefing.
- Drift causes wrong vote-power → **Medium** baseline; **High** when a single-block delta can swing governance.
- Drift only on admin paths with documented compensating action → **Low**.

R10 worst-state severity applies — the consolidated finding inherits the worst row.

## § Cross-references

- Reads `semantic_invariants.md` Mirror Variable Pairs as canonical input. If Phase 4a.5.a was skipped (Light) or timed out, the agent still runs by enumerating pairs from common patterns + Key Invariants.
- Pairs naturally with `~/.valves/rules/symmetric-pairs.md` (often the same BRANCH_ATTR_GAP also appears as a sibling-pair asymmetry).
- Feeds `~/.valves/rules/correctness-winner-preservation.md` — every per-pair row in the consolidated finding is a correctness winner that must NOT be absorbed into a generic "missing accounting update" cluster.

## § Why consolidate

A naive run can produce 5–20 per-row findings depending on how many attribution pairs the codebase has. The consolidation pattern keeps the report navigable while preserving fix-distinctness via the per-pair table. The Full Cluster Agent (4a.2-full) splits this into subgroups (BC-041.A, BC-041.B, ...) when fixes differ.

## § Why this is BC-041 specifically

The bug-class registry reserves BC-041 for variable-flow attribution defects. Maintaining a stable BC tag across audits enables FP calibration in `~/.valves/state/bc_class_calibration.md` and lets Phase 4a.5.c Propagation P1 grep for its registered signatures during structural sweeps.
