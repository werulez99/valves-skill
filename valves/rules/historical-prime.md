<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Historical Prime (benchmark / rerun mode)

Source-of-truth for the **Prior-Report Ingest Agent** (Phase 1.2, sonnet, 1 spawn, in parallel with recon). Output: `{SCRATCHPAD}/historical_prime_seeds.md`. Triggered by `benchmark`, `rerun`, or `prime:{path}` in `$ARGUMENTS`.

## Purpose

When auditing a project that has been audited before (by us, by another firm, by a benchmark dataset), the prior report's findings are signal. Historical Prime ingests them as **regression-detection seeds**: each prior finding gets re-evaluated in the current code with one of three dispositions: `CONFIRMED` (still present), `CLEARED` (fixed), `DEFERRED` (not enough info to decide).

This is OFF by default (fresh audits don't need it). It activates when the user passes `benchmark` / `rerun` / `prime:{path}` to `/valves`, OR when the orchestrator's prior-report scan detects pre-existing audit reports and the user opts in via the AskUserQuestion prompt in Step 1.2.

## § Phase 1.2 (agent task)

**Inputs**:
- The detected prior-report paths (from the slash command's Step 1.2 `find` scan, or from `prime:{path}`).
- `{scratchpad}/findings_inventory.md` (initial — may be empty if Phase 1 still running).
- Source files (current codebase).
- `~/.valves/state/negative_results.md` (so prior NRs are recognized).
- `~/.valves/state/bug_class_registry.md` (for BC tagging).

**Methodology**:

1. Parse each prior report. For each finding in the prior report, extract:
   - Title
   - Severity
   - Location (file + line range or function)
   - One-paragraph description
   - Recommended fix (if present)
   - BC class (if the prior report uses one)

2. For each prior finding, run a localization pass against the current codebase:
   - Does the file still exist? Has the function been renamed?
   - Does the affected pattern still appear at that location?
   - Has the recommended fix been applied? (grep for the diff or invariant)

3. Assign one of three dispositions:
   - **`CONFIRMED`** — pattern still present, fix not applied. Record code location.
   - **`CLEARED`** — fix applied, pattern absent at the original location.
   - **`DEFERRED`** — codebase has shifted enough that localization is uncertain. Record what was checked.

4. Cross-check against `~/.valves/state/negative_results.md`: if a prior finding matches an existing global NR-G, prefer the NR-G judgment unless the current code shows divergence.

5. For each `CONFIRMED` seed, set the BC tag (from registry signature match or BC-NEW).

## § Output schema (`historical_prime_seeds.md`)

```markdown
# Historical Prime Seeds — {project} — {audit timestamp}

## Source reports
| Report path | Date | Findings parsed | CONFIRMED | CLEARED | DEFERRED |
|---|---|---|---|---|---|

## Seeds (prior findings re-evaluated in current code)

### HP-{N} — {prior finding title}
- Source report: {path + finding ID in source}
- Disposition: CONFIRMED | CLEARED | DEFERRED
- Original severity: {from source report}
- Current severity (if CONFIRMED): {after R10 worst-state}
- Original location: {file + lines from source}
- Current location: {file + lines today, or "not found"}
- Pattern check: {grep / signature / invariant cited}
- Fix check: {what was searched for; whether found}
- BC tag: BC-NNN (if matched)
- Recommended depth domain (if CONFIRMED): {token_flow / state_trace / edge_case / external}
- Notes: {one-line observation}

## NR-G citations
| Prior finding | Matched NR-G | Override? |
|---|---|---|
```

## § Downstream propagation (HARD rule)

Every seed must reach a disposition by Phase 6. The orchestrator's pipeline_trace.md must show seeds reaching one of:
- A finding ID in the report (CONFIRMED-style outcome).
- An entry in `audit_negative_results.md` § Thesis Paths Dropped or § Verification [POC-FAIL] Results (CLEARED-style).
- An explicit `DEFERRED` annotation in the Residual Risk Summary.

**Silent drops are forbidden.** If a seed's status is unknown at audit close, the orchestrator logs `PRIME_SEED_DROP` to `{scratchpad}/violations.md` with the seed ID and the last phase where it was last referenced.

## § benchmark-specific behavior

When `$ARGUMENTS` contains `benchmark`:

- Treat the prior report as the **ground truth**. The current run is being scored.
- `PROVEN_ONLY = true` is implicitly preferred (but the user may override).
- The Phase 6 report includes a `## Benchmark Results` section with: recall (CONFIRMED + new findings overlapping prior list / total prior findings), precision (CONFIRMED / total findings reported), and a per-prior-finding alignment table.
- `~/.claude/rules/post-audit-improvement-protocol.md` is read for the diff structure (this is the same protocol used by Step 0e Compare flow).

## § rerun-specific behavior

When `$ARGUMENTS` contains `rerun`:

- The prior report is treated as a **methodology check**, not a benchmark.
- The current audit is full-fresh. Historical Prime seeds inform priority but don't gate findings.
- The report includes a `## Regression Section` listing CONFIRMED prior findings as a quick-glance "still here" list.

## § prime:{path}

When `$ARGUMENTS` contains `prime:{path}`:

- ONLY that path is ingested as the prior report (no auto-discovery).
- Useful when the project has many old reports but the user wants only one as the historical signal.

## § Failure handling

- Zero prior reports found AND `benchmark`/`rerun` flag present → log `HISTORICAL_PRIME_REQUESTED_NO_REPORTS` to `{scratchpad}/violations.md`. Proceed with empty seeds (the audit still runs).
- Prior report parse fails (malformed markdown) → log the parse error per-report. Other reports continue.
- The Phase 1.2 agent times out → write a minimal `historical_prime_seeds.md` with the source-reports table populated and zero seeds. Proceed with degraded mode. Phase 6 report includes `Historical Prime: PARTIAL` in the executive summary.
