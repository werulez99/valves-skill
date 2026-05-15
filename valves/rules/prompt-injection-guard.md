<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Prompt Injection Guard (Pre-Spawn Length Discipline)

Source-of-truth for the **Pre-Spawn Prompt-Length Guard** that runs before EVERY agent spawn in Phase 4b (depth, scanner, niche, injectable, economic, thesis synthesis, P2 propagation) and Phase 4c (chain). Pure mechanical pre-spawn arithmetic — zero new phase, zero new spawn.

Companion to Rule 18 in `~/.valves/CLAUDE.md` (FILTERED INJECTION).

## Purpose

Agent attention degrades on oversized prompts. Above ~600 lines of injected context, depth agents start dropping methodology steps; above ~1500 lines, they truncate mid-task. This guard mechanically computes the prompt length BEFORE spawn and either substitutes summary tables for oversized artifacts (compaction) or drops non-critical artifacts entirely (emergency truncation).

## § Thresholds

```
WARN_LINES        = 600    → log + emit warning, no behavior change
COMPACT_LINES     = 1000   → auto-substitute summary-table view per-artifact
HARD_LIMIT_LINES  = 1500   → emergency truncation: drop non-critical artifacts
```

Lines are counted across **all** injected artifacts AND the agent's instructional preamble.

## § Computation

For each planned agent spawn:

```
total_lines = 0
for artifact in injected_artifacts:
    total_lines += line_count(rendered(artifact))   # post-filter, not raw file
total_lines += line_count(agent_preamble)
total_lines += line_count(skill_payload)
```

`rendered(artifact)` already applies Rule 18 filtering — max 40 lines / ~800 tokens per artifact. The guard sees the post-filter view.

## § Action by threshold

- **`total_lines ≤ WARN_LINES`** → spawn as-is.
- **`WARN_LINES < total_lines ≤ COMPACT_LINES`** → log `PROMPT_LENGTH_WARN` to `{SCRATCHPAD}/prompt_guard_log.md` with the per-artifact breakdown. Spawn as-is.
- **`COMPACT_LINES < total_lines ≤ HARD_LIMIT_LINES`** → for each artifact above its per-artifact target (40 lines), substitute the canonical summary-table view (see § Per-Artifact Compaction Rules). Re-compute total. Log `PROMPT_LENGTH_COMPACT`.
- **`total_lines > HARD_LIMIT_LINES`** (after compaction) → drop non-critical artifacts in priority order: Pipeline Trace (lowest priority — not needed by depth) → Strongest Exploit Cards summary (keep IDs only) → Cluster table (keep ID + 1-line description). Log `PROMPT_LENGTH_HARD_LIMIT`. If still over → log `PROMPT_LENGTH_EMERGENCY` to `{SCRATCHPAD}/violations.md` and spawn with whatever fits.

The guard never blocks a spawn. It always produces a runnable prompt; the goal is graceful degradation, not a gate.

## § Per-Artifact Compaction Rules

Each Valves artifact has a canonical summary-table format used at COMPACT thresholds.

### Cluster table (from `root_cause_clusters.md`)
```markdown
| BC | Cluster name | Severity | Card refs | Cluster size | Confidence |
|---|---|---|---|---|---|
| BC-014 | Share inflation | High | SEC-2 | 3 | 0.74 |
```

### BP table (from `system_breakpoints.md`)
```markdown
| BP | Family | Invariant | First-loss absorber | Reachability (BC tags) |
|---|---|---|---|---|
| BP-03 | Insolvency | totalAssets ≥ totalLiabilities | treasury (designed: insurance) | BC-014, BC-022 |
```

### SEC-N summary (from `strongest_exploit_cards.md`)
```markdown
| SEC | Eligibility | Severity | Surface | Parent exploit (1-line) |
|---|---|---|---|---|
| SEC-2 | E1 + E5 | Critical | Vault.setStrategy | live pointer replacement strands user state |
```

### finding_classification summary (from `finding_classification.md`)
When classification has > 50 rows, compact to a per-BC count + flagged sample:
```markdown
| BC | Count | Card-winners | Correctness-winners | Sample IDs |
|---|---|---|---|---|
| BC-014 | 3 | 1 | 0 | [F-12], [F-44], [F-67] |
```

### candidate_seeds.md summary (from Phase 4a.5.d)
When > 15 seeds, compact to per-domain count + top-3 highest-priority seeds verbatim:
```markdown
| Depth domain | Seed count | Top-3 (Seed ID, sweep, location) |
|---|---|---|
| token_flow | 6 | INTERFACE-2 (Sweep 2, Vault.sol:142), DESYNC-4 (Sweep 3, Strategy.sol:88), ASYMMETRY-1 (Sweep 1, Vault.sol:200) |
```

### attack_thesis.md (v1/v2/v3) summary
```markdown
| Path ID | Status | Triple (victim, attacker, entry) | Card refs | Confidence |
|---|---|---|---|---|
| P-1 | CANDIDATE | (depositor, attacker EOA, deposit) | SEC-1, SEC-2 | 0.62 |
```

### confidence_scores.md summary
When > 30 rows, compact to per-band count + top-N uncertain findings:
```markdown
| Band | Count | Top-3 IDs |
|---|---|---|
| CONFIDENT (≥0.7) | 14 | [F-3], [F-8], [F-12] |
| UNCERTAIN (0.4–0.7) | 7 | [F-22], [F-44], [F-66] |
| LOW (<0.4) | 2 | [F-71], [F-78] |
```

### propagation_structural.md summary
```markdown
| BC class | Net candidates | Already-found | Cleared | Alarms |
|---|---|---|---|---|
| BC-014 | 4 | 3 | 0 | 0 |
| BC-022 | 0 | 0 | 0 | 1 (BUG_CLASS_ZERO_CANDIDATE_ALARM) |
```

### symmetric_pairs.md summary
```markdown
| Pair | Aspects checked | ASYMMETRY_FLAG? | Mandatory depth domain |
|---|---|---|---|
| deposit/withdraw in Vault.sol | 7 | YES (guards differ) | edge_case |
```

### external_platform_limits.md summary
```markdown
| Platform | Function | Symbolic max | Limit | OVERFLOW_CANDIDATE |
|---|---|---|---|---|
| Chainlink Automation | Vault.checkUpkeep | UNBOUNDED (subscribers[]) | 5,000 B | YES |
```

### external_mutability_candidates.md summary
```markdown
| Cache | Upstream | Mutability | Refresh? | Severity |
|---|---|---|---|---|
| Vault.aaveLTV | Aave Pool | governance | NONE | High |
```

### pipeline_trace.md
**Always omit from agent prompts.** This is an orchestrator-only artifact (used at Phase 6e for the Conservation Check). Agents never need it; if injected, it counts toward prompt length without contributing methodology signal.

## § Logging schema

`{SCRATCHPAD}/prompt_guard_log.md` — append on every WARN / COMPACT / HARD_LIMIT firing:

```markdown
## {ISO timestamp} — Agent {agent name} — {threshold fired}
- total_lines (pre-action): {N}
- per-artifact breakdown:
  - {artifact}: {lines} → after compaction: {lines}
- total_lines (post-action): {M}
- artifacts dropped (HARD_LIMIT only): {list}
- Spawn proceeded: YES (always)
```

`{SCRATCHPAD}/violations.md` — append only on `PROMPT_LENGTH_EMERGENCY` (post-truncation still over HARD_LIMIT):

```markdown
PROMPT_LENGTH_EMERGENCY @ {ISO} — {agent name}
  total_lines (post-truncation): {M}  > HARD_LIMIT_LINES (1500)
  Action: spawned with maximum-fit context. Quality may be degraded.
```

## § Why this is mechanical

The guard runs before every spawn — between 8 and 25 times per Phase 4b iteration in Thorough mode. Any per-spawn agent decision would burn budget. The guard does pure arithmetic on file line counts + a fixed substitution table — fast, deterministic, drift-resistant.

## § What the guard does NOT do

- It does NOT decide *which* artifacts an agent needs — that's set by the spawn-time prompt builder.
- It does NOT rewrite content semantically — only mechanical replacement with the canonical summary table.
- It does NOT block spawns — degradation is preferred to a stalled pipeline.
- It does NOT touch agent prompts that lack injected artifacts (e.g., Phase 1 recon prompts that read files at runtime — they go through `~/.claude/prompts/{LANGUAGE}/phase1-recon-prompt.md` not via injection).
