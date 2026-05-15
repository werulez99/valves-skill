<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Reference Diff-Audit

Methodology for the **Reference Diff-Audit Agent** (Phase 1.5, up to 4 opus agents in parallel). Catches bugs introduced when the team modifies a known reference (Uniswap V3, OpenZeppelin, Aave, Compound, Balancer, ERC4626).

## Purpose

Forks of well-audited code are often *almost* correct. The reference's invariants and tests cover most paths. Bugs cluster at the diff: the lines the team changed. A function-by-function diff against the parent identifies high-signal targets that depth iter 1 should reach first.

The output is a **Tier A/B/C global prioritization table** that Phase 4b iter 1 depth agents use to seed mandatory and recommended targets.

## Trigger

Either:
- Agent 1B's fork-ancestry output in `meta_buffer.md` identifies a known parent, OR
- `contract_inventory.md` flags a fork pattern (vendored copy in `lib/`, comment header citing parent, identical struct layouts).

If neither triggers → skip this phase.

## Reference resolution

Per detected parent, resolve the reference source in this order:
1. **Local vendored copy**: `lib/`, `vendor/`, or `node_modules/`.
2. **URL cited in `design_context.md`**: fetched via WebFetch when allowed.
3. **Valves-bundled reference**: `~/.valves/references/{parent_name}.{ext}` per the manifest at `~/.valves/references/MANIFEST.md` (v1.7-PATCH3 PATCH 5 — minimal scaffold). When the manifest entry exists for the resolved parent, verify the file's sha256 against the manifest's `Hash` column before reading. Mismatch → log `REFERENCE_TAMPER_DETECTED` to `degradation_log.md` and skip this source. When the manifest is empty or the parent is not listed → silent skip (graceful degradation).

If none resolvable → log `"reference unavailable for {parent}"` in `{scratchpad}/diff_audit_log.md` and skip THIS parent (other parents continue).

## Spawn topology

- Up to 4 diff-audit agents in parallel (all opus — judgment-heavy).
- One agent per resolved (target, reference) pair.
- Each agent writes `{scratchpad}/diff_audit_{parent_name}.md`.
- After all return, orchestrator merges per-parent tier data into `{scratchpad}/diff_audit_tiers.md`.

## Per-agent task

Function-by-function diff between target and reference. For EACH non-trivial diff, classify the function under the **Global Tier** scheme:

| Tier | Meaning | Depth disposition |
|---|---|---|
| **A** | Diff touches a function critical to invariants (transfer logic, accounting, access control, oracle reads, share math). Likely to introduce a defect. | **MANDATORY** depth target in Phase 4b iter 1 |
| **B** | Diff touches a function with material behavior change (param added, condition relaxed, event added/removed) but not on a critical path. | **RECOMMENDED** depth target |
| **C** | Cosmetic diff (rename, comment, style, gas micro-opt) with no behavioral change. | Logged only; not a depth target |

### Output format per agent

```markdown
# Diff Audit — {parent_name} → {target}
- Reference resolved: {path or URL}
- Diff scope: {N changed functions out of M total}

## Function-by-function diff
### {ContractName}.{functionName}
- Global Tier: A | B | C
- Diff summary: {one-paragraph what changed}
- Critical change: {YES/NO — if YES, why}
- Rationale: {why this Tier was assigned}
- Suggested depth domain: token_flow | state_trace | edge_case | external

### ...

## Tier roll-up
| Tier A | Tier B | Tier C |
|---|---|---|
| {function list} | {function list} | {function list} |
```

## Orchestrator merge → `diff_audit_tiers.md`

```markdown
# Diff Audit Tiers (merged across {N} parents)

## Tier A — MANDATORY depth (Phase 4b iter 1)
| Function | Parent | Reason | Assigned depth agent |
|---|---|---|---|

## Tier B — RECOMMENDED depth
| Function | Parent | Reason | Assigned depth agent |
|---|---|---|---|

## Tier C — Logged only
| Function | Parent | Note |
|---|---|---|
```

The "Assigned depth agent" column is filled by the orchestrator based on `Suggested depth domain` from the per-agent reports + load balancing across token_flow / state_trace / edge_case / external agents.

## Hard rule (Phase 2 instantiation)

Every Tier A row becomes a **mandatory depth target** in Phase 4b iteration 1. Every Tier B row becomes **recommended**. Tier C is logged only.

Depth agent prompts in Phase 2 are injected with their assigned Tier A/B entries from `diff_audit_tiers.md`. Each depth agent is told: "These are diff targets — they are the highest-signal locations in your domain."

## Phase 4c.5 EV bonus

Findings discovered at Tier A diff-audit locations get **+2 EV** in the Verification Priority Queue (see `~/.valves/rules/verification-priority-queue.md`). The forking team's modification is statistically the riskiest part of the codebase.

## Hard rule (timing)

Diff-audit runs **in parallel with Phase 2 instantiation**. It MUST complete before Phase 4b begins so Tier A/B targets can be injected into depth agent prompts. If a diff-audit agent hangs past Phase 2 completion → orchestrator proceeds without that parent's tiers and logs `diff_audit_TIMEOUT_{parent}` in `degradation_log.md`.

## Skipped in Light mode

Light mode skips Phase 1.5 entirely (see Mode table in slash command).
