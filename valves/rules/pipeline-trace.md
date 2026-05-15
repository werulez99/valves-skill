<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Pipeline Trace

Source-of-truth for `{scratchpad}/pipeline_trace.md` — the audit's mass-balance ledger. Always-on regardless of mode.

## Purpose

The pipeline transforms findings across phases (deduplication, clustering, propagation, verification, absorption). Without a trace, findings drift silently — the report ends up with N IDs and the audit can't prove they came from M discoveries. The trace records every transition mechanically so the Conservation Check at Phase 6e can verify mass-balance.

## Initialization (Phase 1 Step 0.85b)

Orchestrator inline. Create `{scratchpad}/pipeline_trace.md`:

```markdown
# Pipeline Trace — {project} — {ISO timestamp}

## Configuration
- Mode: {Light / Core / Thorough}
- Historical Prime: {ON / OFF}
- Benchmark: {ON / OFF}
- PROVEN_ONLY: {true / false}
- Total budget: (computed at Phase 2)

## Phase Trace
| Phase | Agents Spawned | Findings In | Findings Out | Dropped | Absorbed | Escalated | Demoted | Notes |
|-------|----------------|------------:|-------------:|--------:|---------:|----------:|--------:|-------|
```

## § Orchestrator Write Protocol

Append exactly one row after every phase transition. Counts come from the relevant scratchpad artifact (mechanical — read the file, count the rows, compare to the previous phase's count).

Phase ID column values include:
`1, 1.2, 1.5, 3, 4a.1-pre, 3b, 3c, 4a.1-final, 4a.1.5, 4a.2, 4a.3, 4a.5.a, 4a.5.b, 4a.5.c, 4a.5.d (v1.7), 4b iter 1, 4b thesis v2, 4b 8b (Cluster), 4b P2, 4b iter 2, 4b iter 3, 4c.1, 4c.2, 4c.5, 5 (per batch A/B/C/D), 5.1, 5.2, 5.5, 5.6, 5.6.5, 6a, 6b, 6c, 6d, 6e`.

### Column semantics

| Column | Meaning |
|---|---|
| `Findings In` | Count of findings entering this phase (from prior phase's `Findings Out`) |
| `Findings Out` | Count after this phase's transformations |
| `Dropped` | Removed entirely (e.g., REFUTED at chain → moved to NR) |
| `Absorbed` | Merged into another finding/cluster (count of children absorbed into parents) |
| `Escalated` | Severity raised by R10 worst-state, R17 floor, or skeptic-judge upgrade |
| `Demoted` | Severity lowered by PROVEN_ONLY, [EI-THEORY] cap, or skeptic-judge downgrade |
| `Notes` | One-line free text — anomalies, alarms, decisions worth flagging in the trace |

Diff: `Findings_Out = Findings_In - Dropped - Absorbed + new_findings_introduced_in_this_phase`. The math must balance.

## § Conservation Check (Phase 6e)

After Phase 6d (Report Quality Self-Review) completes, the orchestrator runs:

```
report_IDs              = count(report finding IDs in AUDIT_REPORT.md)
appendix_A_exclusions   = count(rows in AUDIT_REPORT.md Appendix A — Excluded Findings)
documented_absorptions  = sum(Absorbed column from initial-inventory phase to report)
initial_findings        = first Findings Out (Phase 4a.1-pre row)
extractions             = sum(new findings added by Phase 5.5 extraction + Phase 1.2 prior-report seeds promoted)

mass_balance = report_IDs + appendix_A_exclusions + documented_absorptions ≈ initial_findings + extractions
```

`≈` permits a tolerance of ±2 to account for off-by-one issues in subgrouping (a cluster split into A/B counts as one report ID per subgroup, not as one absorption + one new). If the deviation > 2 → `PIPELINE_TRACE_CONSERVATION_FAIL`.

## § Failure handling

If conservation fails:
- Write `PIPELINE_TRACE_CONSERVATION_FAIL` to `{scratchpad}/violations.md`.
- Update checklist row 50 to `FAILED_WITH_FALLBACK` ONLY IF `degradation_log.md` is written with the conservation deviation reason. Otherwise row 50 stays unfinished and Phase 6f embargo holds.

The fallback artifact (`degradation_log.md`) must include:
- Initial findings count.
- Final report IDs + Appendix A count + absorbed count.
- Computed deviation.
- Phase-by-phase breakdown of where the deviation arose.
- One-paragraph judgment of whether the deviation reflects a real absorption mistake or a subgrouping artifact.

## § Optional appendix

If the audit was launched with `--include-trace-in-report`, the trace table is appended to AUDIT_REPORT.md as `## Appendix B: Pipeline Trace`. Otherwise it stays in the scratchpad.

## Why mechanical

The trace is mechanical — orchestrator inline, no agent involved. This is deliberate: the trace is the audit's *ground truth* about what happened. If an agent wrote it, the trace would inherit the agent's confabulation tendency. Mechanical writes from artifact reads → drift-resistant.
