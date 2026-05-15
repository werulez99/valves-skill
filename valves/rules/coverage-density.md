<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Coverage Density Map (PATCH A)

Source-of-truth for `{SCRATCHPAD}/coverage_density.md`. Mechanical, orchestrator-inline. Written during the Session A → B Handoff Build sub-step inside the COMPLETE_A boundary, before `session_checkpoint.md` is rewritten and before `session_a_to_b_handoff.md` is composed.

## Purpose

Give Session B a ranked map of dangerous underexplored areas. Coverage Density does not say "this contract has bugs"; it says "this contract has high-risk surfaces and zero or near-zero discovery effort landed on them — Session B should look here first."

## Inputs

- `{SCRATCHPAD}/contract_inventory.md` — list of contracts in scope.
- `{SCRATCHPAD}/function_list.md` — every function with signature, modifiers, and (where available) inferred role.
- `{SCRATCHPAD}/findings_inventory.md` — Session A findings post-iter-1 (post-merge in Thorough).
- `{SCRATCHPAD}/setter_list.md` — admin/privileged setters per contract.
- `{SCRATCHPAD}/state_variables.md` — storage variables per contract (custody / accounting / privilege markers help risk classification).
- `{SCRATCHPAD}/attack_surface.md` — entry points + dependency edges.
- `{SCRATCHPAD}/system_breakpoints.md` (if produced) — breakpoint reachability per contract.
- `{SCRATCHPAD}/economic_findings.md` (if produced) — Phase 4b iter-1 economic agent output.
- `{SCRATCHPAD}/contract_inventory.md` § dependency graph — for cross-contract markers.

## § Risky Function classifier

A function is **Risky** if **any** of:

- **R-CUSTODY**: transfers tokens / NFTs / native value from one party to another, OR mutates a balance/share/position storage slot.
- **R-PRIV**: gated by a privileged role modifier (`onlyOwner`, `onlyAdmin`, role-check, multisig-gated), OR writes a parameter listed in `setter_list.md`.
- **R-ACCT**: reads or writes any storage in `state_variables.md` flagged as accumulator / total / share-price / reward-index / fee.
- **R-XCC**: makes a contract-to-contract call (`.call`, `.transfer`, an `IExternal(...)` invocation, a `delegatecall`, or any address.code-dependent path), excluding view-only reads.
- **R-EXT**: depends on an external value flagged in `external_mutability_candidates.md` OR `external_platform_limits.md` OR a Hidden External Dependency seed (Sweep 5/8 in `candidate_seeds.md`).

A function may carry multiple R-flags. A function with NO R-flags is "Cold" — typical for views, getters, internal helpers without state writes.

## § Per-contract row schema

```markdown
| Contract | Total Functions | Risky Functions | Findings Mapped | Depth Touched? | Cross-Contract Touched? | Economic Touched? | Zero-Finding but High-Risk? | Coverage Score | Priority |
```

Definitions:
- **Total Functions** — count from `function_list.md` for this contract.
- **Risky Functions** — count of R-* flagged functions (any flag).
- **Findings Mapped** — count of entries in `findings_inventory.md` whose Location matches this contract (file or contract name).
- **Depth Touched?** — `Y` if any depth agent's output (`analysis_depth_*.md` for any of token-flow/state-trace/edge-case/external) cites this contract; else `N`.
- **Cross-Contract Touched?** — `Y` if any finding mapped to this contract has cross-contract evidence in its trace, OR if a cross-contract structural seed (Sweep 2 INTERFACE_SEED) was raised here.
- **Economic Touched?** — `Y` if `economic_findings.md` (when present) cites this contract.
- **Zero-Finding but High-Risk?** — `Y` if `Findings Mapped == 0` AND `Risky Functions / Total Functions ≥ 0.20` (meaning at least one in five functions is risky).

## § Coverage Score (penalize zero-finding high-risk modules)

Mechanical formula. No agent reasoning.

```
risk_density   = Risky Functions / max(Total Functions, 1)
finding_density = Findings Mapped / max(Risky Functions, 1)

# Base coverage from finding density on risky surfaces only
base = clamp(finding_density, 0.0, 1.0)

# Penalties (subtract from base)
penalty_zero_high  = 0.50 if Zero-Finding-but-High-Risk else 0.0
penalty_no_depth   = 0.20 if Depth Touched == N and Risky Functions >= 3 else 0.0
penalty_no_xcc     = 0.10 if Cross-Contract Touched == N and contract has cross-contract calls in attack_surface.md else 0.0

Coverage Score = max(0.0, base - penalty_zero_high - penalty_no_depth - penalty_no_xcc)
```

Range: 0.00 (worst — high-risk module the audit barely touched) to 1.00 (best — every risky function got at least one finding).

## § Priority bands

- **CRITICAL** — Coverage Score ≤ 0.15 AND Risky Functions ≥ 5
- **HIGH**     — Coverage Score ≤ 0.30 AND Risky Functions ≥ 3
- **MEDIUM**   — Coverage Score ≤ 0.50
- **LOW**      — Coverage Score >  0.50

Sort the table descending by priority then ascending by Coverage Score.

## § Output (`coverage_density.md`)

```markdown
# Coverage Density Map — {project} — {ISO timestamp}

## Per-contract table
{the schema above, one row per contract in contract_inventory.md, sorted by priority}

## Summary
- Critical contracts: {N}
- High contracts:     {M}
- Total Risky Functions across scope: {R}
- Findings mapped to risky functions: {F}
- Risky functions with zero finding mapped: {Z}

## Notes
- Risky function classifier: see `~/.valves/rules/coverage-density.md` § Risky Function classifier (R-CUSTODY / R-PRIV / R-ACCT / R-XCC / R-EXT).
- Coverage Score formula: see § Coverage Score in the same rule file.
- This artifact is consumed by `~/.valves/rules/session-a-to-b-handoff.md` § Inputs and feeds Session B target ranking. It does NOT generate findings.
```

## Soft-required (Rule 15)

This artifact is SOFT-required. If the orchestrator-inline build fails (missing input files, parse errors), log `coverage_density_INCOMPLETE` to `{SCRATCHPAD}/degradation_log.md` and proceed with a partial table. The Session A → B Handoff Build still runs without a perfect coverage map; it falls back to `attack_surface.md` + `findings_inventory.md` directly.

## Why this improves recall (and does not increase FP)

- It does not generate findings. It directs **investigation budget** to where Session A already missed the most.
- The penalty terms target three concrete miss-modes: (a) a contract with risky surfaces but zero findings, (b) a contract that depth never touched, (c) a contract whose cross-contract surface was unexplored.
- All inputs are mechanical reads of existing artifacts — no model reasoning, no new false-positive surface.
