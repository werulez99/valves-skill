<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# System Breakpoints

Methodology for the **System Breakpoints Agent** (Phase 4a.5.b, sonnet) and the system-level failure-mode artifact `{scratchpad}/system_breakpoints.md`.

## Purpose

Breadth and depth agents look at functions and state variables. Breakpoints look at the *system*: the conditions under which the protocol stops behaving as advertised, who absorbs the loss, whether the trigger is observable before damage, and which findings or BC tags map to each breakpoint.

This artifact feeds:
- Phase 4a.5 depth-agent injection (`reachability cross-reference` to BC tags).
- Phase 4c chain analysis (chains that culminate at a breakpoint get +EV).
- Phase 4c.5 EV ranking (Reality-HIGH / Report-LOW quadrant + Tier A/B diff-audit bonuses).
- Phase 6 Residual Risk Summary (carried via `attack_thesis.md` v3).

## Inputs

- `{scratchpad}/design_context.md` (Key Invariants + Operational Implications)
- `{scratchpad}/state_variables.md`
- `{scratchpad}/findings_inventory.md`
- `{scratchpad}/finding_classification.md` (flat BC tags — used for reachability cross-reference)
- `{scratchpad}/attack_thesis.md` v1

## Output schema (`system_breakpoints.md`)

```markdown
## BP-{NN} — {one-line breakpoint name}
- Family: {Insolvency | Backstop | Cascade | DoS | OracleDrift | FirstLossExhaustion | OrderingViolation | Other}
- Invariant violated: {from design_context.md Key Invariants}
- Conditions that break it: {what state + which actors needed}
- First-loss path:
    - Designed absorber: {what the docs say absorbs the loss — protocol treasury, insurance, etc.}
    - Actual absorber:   {what the code/state actually shows absorbs the loss}
    - Mismatch:          {YES / NO — if YES, this is high-signal}
- Observability:
    - Pre-trigger:  {is there a way to observe the system approaching this state?}
    - At-trigger:   {what events fire / what state changes are visible at the moment of breakpoint?}
    - Atomic-only:  {can the breakpoint be reached + exploited within a single tx so observability is moot?}
- Reachability:
    - Findings:     [F-12], [F-44], ...
    - BC tags:      BC-014, BC-022, ...
    - Cards:        SEC-3
- Worst-state severity: {Critical / High / Medium}
- Notes: {free text}
```

## § BP-FAMILY-IBC

The "IBC" family covers Insolvency, Backstop, Cascade — the breakpoints whose downstream effect is loss of user funds. Findings whose card winner ties to an IBC breakpoint get the `BP-FAMILY-IBC: BP-NN` annotation in their card (see `~/.valves/rules/strongest-exploit-preservation.md` § BP-FAMILY-IBC Tagging).

## Methodology

For each documented Key Invariant in `design_context.md`:
1. Ask: "What state would violate this?" Enumerate concrete state-tuples.
2. For each violating state, identify all reachability paths from each finding/BC.
3. For each path, list the specific user/admin actions that move the system there.
4. Classify the absorber: who pays the loss when the invariant breaks?
5. Classify observability: pre-trigger / at-trigger / atomic-only.
6. Map findings + BC tags + cards that contribute to the path.

Then run a sweep over standard breakpoint families even if no Key Invariant explicitly names them:
- **Insolvency**: total liabilities > total assets after some action.
- **Backstop drained**: insurance/buffer/treasury hits zero before liabilities are covered.
- **Liquidation cascade**: one liquidation triggers another via shared price/state, even when each in isolation is healthy.
- **DoS**: the system stops servicing legitimate users (revert path, gas-blow, oracle stale, etc.).
- **OracleDrift**: oracle reports a value outside tolerance and the protocol acts on it.
- **FirstLossExhaustion**: designed first-loss capital is depleted leaving subsequent losers unprotected.
- **OrderingViolation** (v1.7-PATCH7): the system reaches an invariant-violating state because an expected call-order assumption was not enforced. The trigger is not a single function in isolation but a SEQUENCE the developer assumed but did not check: skipped predecessor step (e.g., reward-claim called before reward-index update); reversed order (e.g., withdraw before settle); repeated call (e.g., harvest twice in one block); admin mutation interleaved between user steps (e.g., setStrategy() between user.deposit() and user.withdraw()); emergency path called early (e.g., emergencyExit() before pendingMigration finalizes); external dependency update inserted between two reads (e.g., oracle update between price snapshot and consumption); cross-contract sequencing reordered. When this family fires, the `Conditions that break it` field MUST name (a) the unenforced order assumption and (b) the concrete call sequence that violates it. The `Reachability:` block cites the E11 SEQUENCE canonicals from `canonical_seed_map.md` and any AB-7 seeds from `assumption_breaker_seeds.md` that contributed.

## Output rules

- Do NOT invent breakpoints with no plausible trigger path. If the family doesn't apply (e.g., no oracle in the protocol), say so in `## Not applicable` with a one-line reason.
- Do NOT re-state findings as breakpoints. Findings are *symptoms*; breakpoints are *system states*. They reference each other via the `Reachability:` block, but they are different artifacts.
- The first-loss `Designed absorber` vs `Actual absorber` mismatch is the highest-signal field. When they disagree, that disagreement is itself a finding candidate — flag it for depth.

## Soft-required gate (Rule 15)

`system_breakpoints.md` is SOFT-required. If the agent times out, log `system_breakpoints_TIMEOUT` to `{scratchpad}/degradation_log.md` and proceed — depth agents fall back to `state_variables.md` + `attack_thesis.md` v1. Do NOT re-spawn the agent.
