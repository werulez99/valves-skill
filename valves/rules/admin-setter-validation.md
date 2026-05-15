<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Admin-Setter Validation (Consolidated 7-Check Sub-Check)

Source-of-truth for the Admin-Setter Validation Consolidated sub-check run by the **Validation Sweep Agent** (Phase 4b iter 1). The agent emits `[VS-AS-1]` findings with multi-location tables, all tagged `[CORRECTNESS-WINNER]` per `~/.valves/rules/correctness-winner-preservation.md`.

## Scope

Run over every privileged setter listed in `{scratchpad}/setter_list.md` (admin, owner, operator, guardian, keeper, governance, multisig). For each setter, run the 7 checks below and consolidate gaps into a single `[VS-AS-1]` finding with a per-location table.

## § The 7 Checks

### Check 1 — Zero-Address

For each setter that writes a storage variable holding an address (token, oracle, vault, strategy, treasury, adapter):

- Does the function `require(newAddress != address(0))` or equivalent before the write?
- If NO → flag `ZERO_ADDRESS` for this location.

Exception: setters whose explicit purpose is to clear a slot (e.g., `clearOracle()`). The setter name + comments should make this intent obvious.

### Check 2 — Bounds

For each setter that writes a numeric storage variable used in calculations (rate, fee, multiplier, threshold, deadline):

- Does the function bound the value (`require(newRate <= MAX_RATE)`, etc.)?
- If NO → flag `BOUNDS` for this location.
- If bounds exist but are wider than the documented invariant in `design_context.md` → flag `BOUNDS_TOO_LOOSE`.

### Check 3 — State-Dependent

For each setter that depends on the system being in a particular state:

- Does the function check the system state before allowing the write? (e.g., `setPaused(false)` should require currently paused; `setStrategy(addr)` may require there are no in-flight positions in the old strategy.)
- If NO and the documented intent requires a state precondition → flag `STATE_DEPENDENT`.

### Check 4 — Active-Flag (live update during operations)

For each setter that writes a parameter read by an active operation (deposit, withdraw, claim, rebalance):

- Does the contract have a way to handle in-flight state when the parameter changes? (snapshot the old value for in-flight, time-locked update, or reject the setter while ops are pending.)
- If NO → flag `ACTIVE_FLAG_DESYNC`. This is the same family as DESYNC_SEED in `~/.valves/rules/symmetric-pairs.md` and Structural Anomaly Harvester Sweep 3.

### Check 5 — Approve Hygiene

For each setter that swaps a pointer to a contract this contract has approved tokens to (vault → strategy, vault → adapter, treasury → router):

- Does the setter REVOKE the old approval (`approve(oldAddr, 0)`) before granting the new one?
- If NO → flag `APPROVE_HYGIENE`. The old contract retains a dangling allowance; if it can call the same `transferFrom` post-replacement, custody may leak.

### Check 6 — Pointer Replacement (live in-flight state)

For each setter that swaps a "live pointer" — a reference variable that has user state mapped to it (vault, adapter, oracle, strategy, treasury):

- Cross-check `live_pointer_transitions.md` (if produced by recon) for LIVE_POINTER_REPLACEMENT entries.
- Does the setter have a migration / reconciliation path for the pre-existing user state under the OLD pointer?
- If NO → flag `POINTER_REPLACEMENT_NO_MIGRATION`. This often pairs with E5 in `~/.valves/rules/strongest-exploit-preservation.md` (Strongest-Exploit Card Eligibility) and is a strong custody-loss candidate.

### Check 7 — Cross-Component Governance Parity (v1.4)

For each privileged role used in this setter, list the symmetric inverse operation:

- If `pause()` exists, does `unpause()` exist with the same role?
- If `setAdapter(addr)` exists, does the role also have `migratePositions(oldAdapter, newAdapter)` or equivalent?
- If `freeze(user)` exists, is there `unfreeze(user)` or a time-bound auto-thaw?
- For roles that gate a setter in contract A, does the same role gate the symmetric inverse in contract B (when A and B are paired)?

Flag `PARITY_GAP` when a privileged action is reachable but its inverse is not — locking an actor or state in a way only governance can release with no fallback.

This is the same pattern as Sweep 4 in `~/.valves/rules/system-breakpoints.md`-adjacent code (Structural Anomaly Harvester PARITY_SEED) but elevated to a finding when there's a clear inverse expected.

## § Output: consolidated `[VS-AS-1]`

The Validation Sweep Agent emits ONE consolidated finding per check-class with a multi-location table:

```markdown
## [VS-AS-1] — Admin Setter Validation Gaps  [CORRECTNESS-WINNER]
- BC-Class: BC-019 (or BC-NEW if novel)
- Severity: {worst-case across instances}
- Description: One or more privileged setters lack standard validation. Per-location table below.

| Location | Check failed | Specific gap | Severity | Fix |
|---|---|---|---|---|
| Vault.sol:142 setStrategy | ZERO_ADDRESS | newStrategy not validated | Medium | `require(newStrategy != address(0))` |
| Vault.sol:198 setFeeRate | BOUNDS | no upper bound | Medium | `require(newRate <= MAX_FEE)` |
| Treasury.sol:66 setRouter | APPROVE_HYGIENE | dangling allowance to old router | High | `IERC20(token).approve(oldRouter, 0)` before set |
| ... |

- Worst-state severity (R10): {High}
- Recommendation: apply per-location fixes above. Adopt a setter template that includes all 7 checks.
```

Each row is a distinct correctness defect. Per `~/.valves/rules/correctness-winner-preservation.md`, the Full Cluster Agent (4a.2-full) MUST split this finding into subgroups when fixes differ — each row may end up in its own subgroup (BC-019.A zero-address, BC-019.B bounds, etc.).

## § Severity rules

- ZERO_ADDRESS without recovery → Medium (may brick the contract until governance acts).
- BOUNDS without recovery on a fee/rate → Medium; on a slippage / liquidation threshold that gates user funds → High.
- STATE_DEPENDENT missing precondition → severity depends on consequence (pause-bypass on a rugpull-prevention contract → Critical).
- ACTIVE_FLAG_DESYNC → Medium baseline; High when the desync directly mis-attributes user funds (reward index, share price).
- APPROVE_HYGIENE → High when the dangling allowance is a custody path; Medium when bounded.
- POINTER_REPLACEMENT_NO_MIGRATION → typically Critical (custody loss / orphaning under E5).
- PARITY_GAP → Medium baseline; High when a user can be locked indefinitely.

R10 worst-state severity applies — the consolidated finding inherits the worst of its rows.

## § Why consolidate

A naive run of 7 checks across 30 setters would produce up to 210 findings. The consolidation pattern keeps the report readable while preserving fix-distinctness via the per-location table. Consumers (depth, verification, report) read the per-location rows for granular fixes; the report renders one finding section per check-class.
