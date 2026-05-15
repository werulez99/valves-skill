<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Bug-Class Registry (global, persistent)

Stable BC-NNN class definitions across audits. Read by Phase 4a.2-lite Classification Agent (signature/semantic match), Phase 4a.5.c Propagation P1 Agent (multi-pattern grep sweep), and Phase 5.6.4 New Class Promotion Protocol.

> **STATE FILE — RECONSTRUCTED SCAFFOLDING.** All BC-001..BC-041 entries below are stubs created during cold reconstruction. Anchored names (BC-007, BC-014, BC-019, BC-041) come from explicit references in `~/.valves/commands/valves.md` and Phase 1 rule files. All other slots are RESERVED placeholders — names, patterns, scopes, fixes, severity priors, and audit history WILL populate as real audits run and the New Class Promotion Protocol fires. Do **not** treat any field below as validated historical data until at least one audit appends a `confirmed` row to its history.

---

## § Update Protocol

This file is appended to (never overwritten in-place — snapshot the prior version first) by:

1. **Phase 5.6.4 § New Class Promotion Protocol** — for each `BC-NEW-{N}` cluster in the current audit's `root_cause_clusters.md` with **≥1 finding verdict `[POC-PASS]`**:
   - Assign the next free BC-NNN number.
   - Replace the stub block below (or append a new one if all 41 stubs are taken) with the validated fields: name, pattern (≥3 grep signatures), typical scope, common fix, severity prior counts.
   - Append the audit to that BC's history table.
2. **Phase 5.6.4-pre § Bug-Class FP Calibration Update** — does NOT modify this file. It writes to `~/.valves/state/bc_class_calibration.md` instead.

Snapshot the pre-update version to `~/.valves/state/bug_class_registry_snapshots/{YYYY-MM-DD}_{project}.md` before any append.

---

## § Class Index (one row per BC-NNN, stub-aware)

| BC | Name | Status | Anchor source |
|---|---|---|---|
| BC-001 | RESERVED | STUB | example reference in slash command (`finding_classification.md` row example) |
| BC-002 | RESERVED | STUB | — |
| BC-003 | RESERVED | STUB | — |
| BC-004 | RESERVED | STUB | — |
| BC-005 | RESERVED | STUB | — |
| BC-006 | RESERVED | STUB | — |
| BC-007 | Reentrancy → drain | STUB (anchored name) | slash command Phase 4c.5 EV-queue example: `CH-01 \| High \| Reentrancy → drain \| BC-007` |
| BC-008 | RESERVED | STUB | — |
| BC-009 | RESERVED | STUB | — |
| BC-010 | RESERVED | STUB | — |
| BC-011 | RESERVED | STUB | — |
| BC-012 | RESERVED | STUB | — |
| BC-013 | RESERVED | STUB | — |
| BC-014 | Share inflation | STUB (anchored name) | slash command cluster summary example: `BC-014 \| Share inflation \| High \| SEC-2 \| 3 \| 0.74` |
| BC-015 | RESERVED | STUB | — |
| BC-016 | RESERVED | STUB | — |
| BC-017 | RESERVED | STUB | — |
| BC-018 | RESERVED | STUB | — |
| BC-019 | Admin Setter Validation Gaps | STUB (anchored name) | `~/.valves/rules/admin-setter-validation.md` consolidated `[VS-AS-1]` BC-class assignment |
| BC-020 | RESERVED | STUB | — |
| BC-021 | RESERVED | STUB | — |
| BC-022 | RESERVED | STUB | referenced as a reachable BC tag in BP example tables (no canonical name) |
| BC-023 | RESERVED | STUB | — |
| BC-024 | RESERVED | STUB | — |
| BC-025 | RESERVED | STUB | — |
| BC-026 | RESERVED | STUB | — |
| BC-027 | RESERVED | STUB | — |
| BC-028 | RESERVED | STUB | — |
| BC-029 | RESERVED | STUB | — |
| BC-030 | RESERVED | STUB | — |
| BC-031 | RESERVED | STUB | — |
| BC-032 | RESERVED | STUB | — |
| BC-033 | RESERVED | STUB | — |
| BC-034 | RESERVED | STUB | — |
| BC-035 | RESERVED | STUB | — |
| BC-036 | RESERVED | STUB | — |
| BC-037 | RESERVED | STUB | — |
| BC-038 | RESERVED | STUB | — |
| BC-039 | RESERVED | STUB | — |
| BC-040 | RESERVED | STUB | — |
| BC-041 | Variable-Flow Attribution | STUB (anchored name) | `~/.valves/rules/attribution-audit.md` consolidated `[VS-AT-1]` BC class |

---

## § Per-BC Stub Blocks

Every block below uses the canonical schema from `~/.valves/rules/bug-class-registry.md` § New Class Promotion Protocol. Fields marked `(none)` / `TBD` are populated by the first audit that confirms an instance. Until then, the block is **STUB scaffolding**, not validated history.

### BC-001
- Name: RESERVED
- First seen: TBD
- Pattern: (none — populated on first promotion)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-002
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-003
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-004
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-005
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-006
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-007 — Reentrancy → drain
- Name: Reentrancy → drain (anchored name from slash command)
- First seen: TBD
- Pattern: (none — populated on first promotion. Expect ≥3 grep signatures covering: external call before state-write; reentrancy guard absence; same-contract / cross-contract / cross-function variants.)
- Typical scope: contracts that hold user funds and make external calls (vaults, lending pools, NFT escrow, bridge endpoints)
- Common fix: CEI ordering OR `nonReentrant` modifier OR pull-payment refactor
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB (name anchored, fields unpopulated)

### BC-008
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-009
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-010
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-011
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-012
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-013
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-014 — Share inflation
- Name: Share inflation (anchored name from slash command)
- First seen: TBD
- Pattern: (none — populated on first promotion. Expect ≥3 grep signatures covering: first-deposit share-mint, donation-attack-style asset injection, exchange-rate read before share computation.)
- Typical scope: ERC4626 vaults, share-based pools, single-sided deposit primitives with `previewDeposit` / `convertToShares`
- Common fix: virtual shares offset / dead-share burn / minimum-liquidity lock
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB (name anchored, fields unpopulated)

### BC-015
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-016
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-017
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-018
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-019 — Admin Setter Validation Gaps
- Name: Admin Setter Validation Gaps (anchored name from `~/.valves/rules/admin-setter-validation.md`)
- First seen: TBD
- Pattern: (none — populated on first promotion. The Validation Sweep Agent does NOT need registry signatures here; it runs the canonical 7-check sweep over `setter_list.md` directly.)
- Typical scope: any contract with privileged setters (admin / owner / operator / guardian / keeper / governance / multisig)
- Common fix: per-row fix in the consolidated `[VS-AS-1]` table — zero-address check, bounds, state-precondition, active-flag handling, approve revoke, pointer-replacement migration, governance parity inverse
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB (name anchored, fields unpopulated)

### BC-020
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-021
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-022
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB (referenced in BP reachability example tables; canonical name to be set on first promotion)

### BC-023
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-024
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-025
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-026
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-027
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-028
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-029
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-030
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-031
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-032
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-033
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-034
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-035
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-036
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-037
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-038
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-039
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-040
- Name: RESERVED
- First seen: TBD
- Pattern: (none)
- Typical scope: (none)
- Common fix: (none)
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB

### BC-041 — Variable-Flow Attribution
- Name: Variable-Flow Attribution (anchored name from `~/.valves/rules/attribution-audit.md`)
- First seen: TBD
- Pattern: (none — populated on first promotion. Source patterns from Mirror Variable Pairs in `semantic_invariants.md`: `total*` paired with `sum-over-mapping(...)`, `globalRewardIndex` / `userRewardOwed[user]`, `totalSupply` / `sum(votes[user])`.)
- Typical scope: contracts that track the same conceptual quantity in two storage slots — total counters paired with per-user mappings, reward indices paired with accrued claims, vote-power totals paired with delegations
- Common fix: wrap mutators in a helper that updates both sides atomically; add a Phase-4-style invariant test
- Severity priors: Critical 0 / High 0 / Medium 0 / Low 0
- Audit history: (none)
- Status: STUB (name anchored, fields unpopulated)

---

## § Allocation note (when all 41 stubs are taken)

When the next promotion would assign BC-042 and beyond, append new blocks below this section using the same schema. Do NOT renumber existing entries — the BC-NNN identifier is stable across audits forever.

Snapshot policy: append-with-snapshot (snapshot prior file → append new BC). Rewrites of existing BC entries (e.g., correcting a name, sharpening a Pattern) follow the same snapshot rule.
