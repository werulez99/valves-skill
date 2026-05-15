<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Thorough Strict-Mode (v1.5)

Source-of-truth for Thorough's fail-closed semantics: the **Mandatory Step Checklist** (rows 01–73 as of v1.7-PATCH5; baseline rows 01–50 + v1.7-PATCH appended rows 51–73), the **Recovery Loop**, the **Phase 4a Sequencing Invariant**, the **Compliance Summary**, and the **Final Report Embargo**.

## Scope

Applies only when `MODE == thorough`. Light/Core use looser semantics (Rule 12 — see Plamen's CLAUDE.md). When this file says "BLOCK", it means the orchestrator does not advance phases until the row reaches a valid terminal state.

## Valid terminal states

A checklist row reaches a valid terminal state when its `status` is one of:

- **`COMPLETE`** — the named evidence artifact exists on disk with the expected non-empty content.
- **`FAILED_WITH_FALLBACK`** — the named fallback artifact exists on disk with the expected fallback marker (e.g., `COMPILATION_FAILED`, `MEDUSA_COMPILATION_FAILED`, `floor scores written + fallback chain logged`).
- **`NOT_APPLICABLE`** — has a non-trivial reason (not `""`, `"skipped"`, or `"n/a"`). Allowed reasons include language-mismatch, tool-not-installed, flag-not-detected, convergence-at-iter-N (for depth iter 3), no-eligible-entries (for specific conditional rows). **PROHIBITED NOT_APPLICABLE reasons (v1.7-PATCH10.3+PATCH11)**: `"Single-session audit"`, `"single session"`, `"ran in one session"`, `"no Session B"`, or any variant implying the Session A/B split was skipped. **ACTIVE ENFORCEMENT (v1.7-PATCH11)**: If the orchestrator is about to mark ANY Session-B-owned row (per § Session Ownership table below) as NOT_APPLICABLE with a session-bypass reason, the orchestrator MUST instead: (1) log `SINGLE_SESSION_THOROUGH_DRIFT` as a HIGH-severity violation to violations.md, (2) HALT immediately, (3) emit: `"HALTED: Thorough mode requires Session B. Rows {list} cannot be NOT_APPLICABLE in a single session. Start a new conversation from the COMPLETE_A checkpoint: /valves thorough"`. This is not advisory — the halt is unconditional.

Any other state (`PENDING`, `RUNNING`, `FAILED` without fallback, `SKIPPED` without reason) is BLOCKING.

## § Step Rows

Rows 01–73 (baseline 01–50 + v1.7-PATCH appended rows 51–73), all initialized to `PENDING` at Phase 1 Step 0.85a. Niche-agent rows (Row 23 placeholders) are dynamically appended at end of Phase 1 once `template_recommendations.md` is read. Rows 51–73 cover the v1.7-PATCH series additions (assumption-breaker, conditional analog seeding, COMPLETE_A handoff sub-step, canonical seed map, cleared-proof discipline, slack redistribution, reference manifest, family-diversity cap, rescue reserve, NR applicability strict-match, family saturation metric, final strongest-exploit sanity check, rescue-reserve diversity control, dominant-family override, NR evidence age/drift, reserve-to-final conversion metric).

| Row | Step | Phase | Evidence artifact | Fallback artifact |
|----|----|----|----|----|
| 01 | Recon agents 1A/1B/2/3 | 1 | recon_summary.md, template_recommendations.md, attack_surface.md, design_context.md | meta_buffer.md (RAG fallback) |
| 02 | Operational Implications gate | 1 | design_context.md § Operational Implications | — |
| 03 | Historical Prime ingest (if active) | 1.2 | historical_prime_seeds.md | violations.md HISTORICAL_PRIME_REQUESTED_NO_REPORTS |
| 04 | Reference Diff-Audit | 1.5 | diff_audit_tiers.md | diff_audit_log.md (parent unavailable) |
| 05 | Phase 3 Breadth | 3 | analysis_*.md per spawn_manifest.md | — |
| 06 | Phase 3b Re-Scan | 3b | analysis_rescan_*.md | NOT_APPLICABLE if Light/Core |
| 07 | Phase 3c Per-Contract | 3c | analysis_percontract_*.md | NOT_APPLICABLE if Light/Core |
| 08 | Initial Inventory (4a.1-pre) | 4a.1-pre | findings_inventory.md (initial) | — |
| 09 | Inventory Merge (4a.1-final) | 4a.1-final | findings_inventory.md with § Inventory Source Coverage | NOT_APPLICABLE if Light/Core |
| 10 | Strongest Exploit Gate | 4a.1.5 | strongest_exploit_cards.md | — |
| 11 | Classification (lite) | 4a.2-lite | finding_classification.md | — |
| 12 | Thesis v1 | 4a.3 | attack_thesis.md (v1) | — |
| 13 | Semantic Invariants Pass 1 | 4a.5.a | semantic_invariants.md | degradation_log.md (timeout) |
| 14 | Semantic Invariants Pass 2 (Thorough) | 4a.5.a | semantic_invariants.md (with Pass 2 sections) | degradation_log.md |
| 15 | System Breakpoints | 4a.5.b | system_breakpoints.md | degradation_log.md |
| 16 | Invariant Fuzz Campaign (EVM) | pre-Depth | invariant_fuzz_results.md | invariant_fuzz_results.md with COMPILATION_FAILED |
| 17 | Medusa Stateful Fuzz (EVM) | pre-Depth | medusa_fuzz_findings.md | medusa_fuzz_findings.md with MEDUSA_COMPILATION_FAILED |
| 18 | Propagation P1 | 4a.5.c | propagation_structural.md + symmetric_pairs.md + external_platform_limits.md + external_mutability_candidates.md | degradation_log.md per artifact |
| 19 | Structural Anomaly Harvester | 4a.5.d | candidate_seeds.md | degradation_log.md |
| 20 | Depth iter 1 (4 + 3 scanners + validation) | 4b iter1 | analysis_depth_*.md, analysis_scanner_*.md, validation_sweep.md | — |
| 21 | Economic iter 1 | 4b iter1 | economic_findings.md | — |
| 22 | Confidence Scoring (post iter 1) | 4b | confidence_scores.md | — |
| 23 | Niche agents (placeholder; expanded after Phase 1) | 4b iter1 | analysis_niche_*.md per niche row | NOT_APPLICABLE if niche not Required |
| 24 | Thesis Synthesis v2 | 4b post-iter1 | attack_thesis.md (v2) | — |
| 25 | Full Clustering (post-depth, 4a.2-full) | 4b 8b | root_cause_clusters.md | — |
| 26 | Propagation P2 | 4b 9 | propagated_*.md + propagation_summary.md | UNPROPAGATED_BUDGET stubs |
| 27 | Economic iter 2 (Thorough) | 4b iter2 | economic_findings.md (iter2 section) | — |
| 28 | Depth iter 2 DA | 4b iter2 | analysis_depth_da_*.md | — |
| 29 | Depth iter 3 (if needed) | 4b iter3 | adaptive_loop_log.md final pass | NOT_APPLICABLE if convergence reached at iter 2 |
| 30 | Design Stress Testing | 4b | design_stress.md | — |
| 31 | Chain Analysis iter 1 | 4c | hypotheses.md | — |
| 32 | Chain Analysis iter 2 (Thorough) | 4c | hypotheses.md (iter2 entries) | — |
| 33 | Verification Priority Queue | 4c.5 | verification_priority_queue.md | — |
| 34 | RAG Validation Sweep | 4b.5 | rag_validation.md | rag_validation.md w/ floor scores + fallback chain |
| 35 | Phase 5 batch A (Chain + High) | 5 | verify_*.md per ID | — |
| 36 | Phase 5 batch B (Medium half 1) | 5 | verify_*.md | — |
| 37 | Phase 5 batch C (Medium half 2) | 5 | verify_*.md | — |
| 38 | Phase 5 batch D (Low + Info) | 5 | verify_lowinfo.md | NOT_APPLICABLE per mode |
| 39 | Skeptic-Judge HIGH/CRIT | 5.1 | verify_skeptic_*.md | NOT_APPLICABLE if no HIGH/CRIT |
| 40 | Cross-Batch Consistency | 5.2 | cross_batch_consistency.md | — |
| 41 | Post-Verification Extraction | 5.5 | hypotheses.md updated with [VER-NEW-*] | — |
| 42 | Thesis v3 + Cluster Inheritance | 5.6.1–5.6.2 | attack_thesis.md (v3) + verification_inheritance.md | — |
| 43 | Negative Results capture (stub-ensure + appends) | 5.6.3 | audit_negative_results.md | — |
| 44 | BC-Class FP Calibration | 5.6.4-pre | ~/.valves/state/bc_class_calibration.md updated + snapshot | — |
| 45 | Promotion to global state | 5.6.4 | ~/.valves/state/negative_results.md + bug_class_registry.md updated | NOT_APPLICABLE if no eligible entries |
| 46 | Cluster → Report Mapping | 5.6.5 | cluster_instance_map.md | — |
| 47 | Report pipeline (Index → Tiers → Assembler) | 6a-c | AUDIT_REPORT.md | — |
| 48 | Report Quality Self-Review | 6d | report_review.md | — |
| 49 | Pipeline Trace Finalization | 6e | pipeline_trace.md w/ Conservation Check PASSED | degradation_log.md w/ conservation deviation reason |
| 50 | Conservation Check (final) | 6f | pipeline_trace.md PASSED + AUDIT_REPORT.md ready | embargo notice in compliance_summary.md |
| 51 | Assumption-Breaker Pass (v1.7-PATCH PATCH H) | 4a.5.e | assumption_breaker_seeds.md | degradation_log.md (timeout / agent fail) |
| 52 | Bounded Analog Seeding (v1.7-PATCH PATCH G) | 4a.5.f | analog_seeds.md (with § Source: line) | analog_seeds.md w/ § Source: NONE_AVAILABLE + degradation_log.md |
| 53 | Coverage Density Map (v1.7-PATCH PATCH A) | COMPLETE_A handoff sub-step | coverage_density.md | degradation_log.md (partial table acceptable) |
| 54 | Negative Space Scan (v1.7-PATCH PATCH E) | COMPLETE_A handoff sub-step | negative_space.md | degradation_log.md |
| 55 | Seed Outcomes Routing (v1.7-PATCH PATCH B) | COMPLETE_A handoff sub-step | seed_outcomes.md | degradation_log.md |
| 56 | Disagreement Queue (v1.7-PATCH PATCH C) | COMPLETE_A handoff sub-step | disagreement_queue.md | degradation_log.md |
| 57 | Session A -> B Handoff Build (v1.7-PATCH PATCH I, **HARD GATE**) | COMPLETE_A handoff sub-step | session_a_to_b_handoff.md | -> (HARD: re-spawn handoff build once; if still missing -> ABORT in Thorough) |
| 58 | Cross-Session Consensus (v1.7-PATCH PATCH J, **HARD GATE in Thorough**) | Session B post-rescore | cross_session_consensus.md | -> (HARD in Thorough; degrade-and-log only in Core/Light) |
| 59 | Seed Metrics (v1.7-PATCH PATCH K) | 6e tail | seed_metrics.md | degradation_log.md |
| 60 | Coverage Lift (v1.7-PATCH PATCH K) | 6e tail | coverage_lift.md | degradation_log.md |
| 61 | Canonical Seed Map (v1.7-PATCH2 PATCH 1; v1.7-PATCH3 adds Proof Records + Sibling Links sub-sections) | COMPLETE_A handoff sub-step (after seed_outcomes.md, before disagreement_queue.md) | canonical_seed_map.md | degradation_log.md (handoff § 2 falls back to raw seed_outcomes.md) |
| 62 | CLEARED Proof Discipline (v1.7-PATCH3 PATCH 1) | applies to seed_outcomes.md + canonical_seed_map.md + analysis_depth_*.md CLEARED outcomes | proof records sub-sections in seed_outcomes.md and canonical_seed_map.md | degradation_log.md `CLEARED_PROOF_GAP_DETECTED` (mechanical downgrade — no runtime block) |
| 63 | Handoff Slack Redistribution (v1.7-PATCH3 PATCH 2) | COMPLETE_A handoff sub-step #6 (session_a_to_b_handoff.md build) | session_a_to_b_handoff.md § 0 Redistribution Metadata (always emitted, even when slack_slots_used=0) | — (always succeeds; § 0 zeros are valid) |
| 64 | Reference Manifest (v1.7-PATCH3 PATCH 5; v1.7-PATCH4 PATCH 7 strict-format hardening) | Phase 1.5 reference resolution step 3 | ~/.valves/references/MANIFEST.md | NOT_APPLICABLE if MANIFEST.md absent (silent skip — bundled references are optional). v1.7-PATCH4: mandatory sha256 verification per entry; format errors logged to degradation_log.md and that entry skipped (other entries unaffected). |
| 65 | Family-Diversity Cap (v1.7-PATCH4 PATCH 3) | COMPLETE_A handoff sub-step #6 (handoff § 2 selection) | session_a_to_b_handoff.md § 0 fields family_diversity_cap_applied + families_capped + diversity_overflow_promoted | NOT_APPLICABLE if total FORWARD pool < 4 (exemption per § Family-diversity cap algorithm) |
| 66 | Rescue Reserve (v1.7-PATCH4 PATCH 4) | Phase 4c.5 verification queue construction | verification_priority_queue.md § Rescue Reserve | NOT_APPLICABLE if zero rescued-eligible findings (5 eligibility classes per § Rescue Reserve in verification-priority-queue.md) |
| 67 | NR Applicability Strict-Match (v1.7-PATCH4 PATCH 5) | Phase 5.6.1 attack_thesis.md v3 PRIOR_NEGATIVE handling | attack_thesis.md v3 PRIOR_NEGATIVE_INHERITED vs PRIOR_NEGATIVE_ADVISORY annotations | NOT_APPLICABLE if no NR-G matches OR all matched NR-G entries are pre-v1.7-PATCH4 (auto-downgrade to advisory) |
| 68 | Family Saturation Metric (v1.7-PATCH4 PATCH 6) | Phase 6e tail (seed_metrics.md write) | seed_metrics.md § Family saturation | degradation_log.md if Session B `analysis_depth_da_*.md` parsing fails (descriptive-only — never blocks) |
| 69 | Final Strongest-Exploit Sanity Check (v1.7-PATCH5 PATCH 1) | Phase 6d.5 (between Report Quality Self-Review and Pipeline Trace Finalization) | strongest_exploit_final_check.md | NOT_APPLICABLE if strongest_exploit_cards.md missing (Light mode); SOFT — surfaces warnings as advisory Report Quality Notes; never auto-rewrites AUDIT_REPORT.md |
| 70 | Rescue-Reserve Diversity Control (v1.7-PATCH5 PATCH 2) | Phase 4c.5 verification queue (within § Rescue Reserve construction) | seed_metrics.md § Rescue reserve diversity (rescue_diversity_applied + rescue_classes_capped + rescue_diversity_overflow_promoted) | NOT_APPLICABLE if eligible rescue pool < 4 (exemption per § Rescue-class diversity control) |
| 71 | Dominant-Family Override (v1.7-PATCH5 PATCH 3) | COMPLETE_A handoff sub-step #6 (after family-diversity cap walk) | session_a_to_b_handoff.md § 0 fields dominant_family_override_applied + dominant_family + override_score_gap + override_held_promoted | NOT_APPLICABLE if score gap < 0.25 OR overflow empty OR section_2 has no alternative-family entries |
| 72 | NR Evidence Age / Drift (v1.7-PATCH5 PATCH 6) | Phase 5.6.1 PRIOR_NEGATIVE handling (extends PATCH 5 strict-match) | NR-G entries' evidence_age_class derived per 6-month auto-demotion algorithm | NOT_APPLICABLE if no NR-G matches; STALE/UNKNOWN entries auto-downgrade to PRIOR_NEGATIVE_ADVISORY regardless of applicability |
| 73 | Reserve-to-Final Conversion Metric (v1.7-PATCH5 PATCH 5) | Phase 6e tail (seed_metrics.md § Reserve-to-final conversion) | seed_metrics.md § Reserve-to-final conversion (main queue / orphan / rescue conversion + per-rescue-class breakdown + override usage + sanity-check effectiveness) | degradation_log.md if cluster_instance_map.md or verify_*.md parsing fails (descriptive-only) |

## § Session Ownership (v1.7-PATCH10.3 — MANDATORY enforcement)

In Thorough mode, rows are owned by either Session A or Session B. Session A CANNOT mark Session-B-owned rows as NOT_APPLICABLE or COMPLETE — they remain PENDING until Session B runs in a fresh conversation.

| Session | Rows | Scope |
|---------|------|-------|
| **A** | 01–22, 51–57, 61–65, 71 | Recon → depth iter 1 + scoring + COMPLETE_A handoff build |
| **B** | 23–50, 58–60, 66–70, 72–73 | DA iter 2-3 → chain → verification → report → finalization |

**Enforcement**: The COMPLETE_A boundary halt (valves.md § COMPLETE_A boundary enforcement) fires after rows 01–22 + 51–57 + 61 + 63 + 65 + 71 reach terminal state. Rows owned by Session B MUST remain PENDING at the COMPLETE_A boundary — the Pre-Report Gate (Phase 5.99) and Final Embargo (Phase 6f) verify they reach terminal state before the report is accepted.

**Violation**: If the orchestrator marks a Session-B-owned row as `NOT_APPLICABLE: "Single-session audit"` or any variant implying Session B was skipped, this is a `COMPLETE_A_BOUNDARY_BYPASS` violation → the run is classified as INVALID FINALIZATION. There is no valid Thorough deliverable without Session B execution.

### § PARTIAL_B Resume Semantics (v1.7-PATCH11.1)

When Session B is interrupted and resumes, `run_state.json` has `checkpoint_level: "PARTIAL_B"`. This tells the orchestrator:

1. **Session B's own work products are legitimate** — do NOT delete hypotheses.md, chain_hypotheses.md, verify_*.md, report_*.md, or any other Session-B-produced artifact. The session-aware contamination check in `execution-state.md` § R9.1 uses `checkpoint_level` to distinguish legitimate Session B artifacts from leaked Session A artifacts.
2. **Resume from the first incomplete Session-B-owned row** — scan rows 23-50 + 58-60 + 66-70 + 72-73 in `mandatory_step_checklist.md`. The first non-terminal row is the resume point.
3. **Use the idempotent pre-spawn check** (Phase 0.9 § G) — before spawning any agent, check if its expected output already exists and is valid. Skip if already complete. This prevents duplicate verification, duplicate chain analysis, or duplicate report generation on resume.
4. **PARTIAL_B is NOT a valid completion state** — the run continues until COMPLETE_B is reached. The Phase 6f embargo requires `checkpoint_level == "COMPLETE_B"` for a VALID THOROUGH deliverable.
5. **(PATCH11.1) Session B startup is fail-closed** — before entering PARTIAL_B work, Step 0-pre verifies that `run_state.json`, `SESSION_B_READ_SCOPE.md`, `session_checkpoint.md`, and `session_a_to_b_handoff.md` all exist. Missing any one → `SESSION_B_MISSING_PREREQUISITES` → HALT. No silent improvisation.
6. **(PATCH11.1) Disk state is authoritative** — after compaction/interruption, the resume sweep reads `run_state.json` + `mandatory_step_checklist.md` + `session_checkpoint.md` from disk. Conversational momentum does not override disk state.

## § Phase 4a Sequencing Invariant

Phase 4a.1.5 (Strongest Exploit Gate) MUST NOT proceed until rows 06 and 07 are terminal AND `findings_inventory.md` contains the `## Inventory Source Coverage` section listing Phase 3, 3b, and 3c.

If any precondition fails → BLOCK Phase 4a.1.5. Do not proceed to Gate, Cluster, or Thesis.

In Core/Light, rows 06/07 are NOT_APPLICABLE; the invariant is satisfied trivially.

## § Recovery Loop

When the watchdog or an inline checkpoint finds a row in non-terminal state:

```
for iteration in 1..3:
  for row in blocking_rows:
    if row had a producing agent → re-spawn the agent ONCE
    if row was orchestrator-inline → re-execute the inline step
    if row needs an upstream artifact → spawn the upstream agent first
  re-evaluate all blocking_rows
  if blocking_rows empty → break

if still blocking after 3 iterations → emit Final Report Embargo
```

Each iteration logs `RECOVERY_ITERATION_{N}` in `violations.md` with the rows it touched and the outcome.

## § Compliance Summary

Always written by Phase 6f (Thorough). Contains the full row 01–50 (or 01–N+niche) status table at audit close, conservation check result, recovery iterations attempted, and the embargo verdict.

```markdown
# Compliance Summary — {project} — {ISO}

## Mode: thorough
## Outcome: COMPLETE | INCOMPLETE

## Step rows
| Row | Phase | Status | Evidence/Fallback artifact |
|---|---|---|---|

## Conservation Check
- Result: PASSED | FAILED
- Deviations: {if FAILED, list}

## Recovery iterations
- Attempted: {N} / 3
- Outcome: SUCCESS | FAILED

## Embargo verdict
- Held: {YES — list blocking rows / NO — clear}
```

## § Final Report Embargo (v1.7-PATCH10 — HARDENED)

The fail-closed terminal gate. Runs at Phase 6f for Thorough only. **Mechanically enforced** — orchestrator-inline check, no agent dependency, no watchdog dependency.

### Embargo conditions

`embargo_holds = true` if ANY of:
- Any row not in terminal state (`COMPLETE`/`FAILED_WITH_FALLBACK`/`NOT_APPLICABLE`).
- Any `COMPLETE` row whose evidence artifact does not exist on disk (synthetic completion).
- Any `COMPLETE` row whose evidence artifact has an illegal writer per `~/.valves/rules/artifact-ownership.md` § Control table (cross-check with `violations.md` `ILLEGAL_WRITER_*` entries).
- Any `FAILED_WITH_FALLBACK` row whose fallback artifact does not exist on disk.
- Any `NOT_APPLICABLE` row with empty / "skipped" / "n/a" reason.
- Conservation Check (row 50) != PASSED.
- (v1.7-PATCH10) `violations.md` contains any `SCOPE_VIOLATION_PERSISTENT`, `INVALID_FINALIZATION_*`, `COMPLETE_A_BOUNDARY_INTEGRITY_FAILURE`, or `PROTECTED_ARTIFACT_PRE_WRITE_GATE_BLOCKED` entry that was not resolved.
- (v1.7-PATCH10) `violations.md` contains any `ILLEGAL_WRITER_HP_OUT_OF_SCOPE` or `ILLEGAL_WRITER_ORCHESTRATOR_ARTIFACT_BY_AGENT` entry whose AUTO-DISCARD + re-spawn was not successful.
- (v1.7-PATCH10, Thorough only) `session_checkpoint.md` is missing OR status ≠ `COMPLETE_B` (Session B never properly closed). For Thorough, the boundary contract requires both COMPLETE_A and COMPLETE_B to be reached cleanly. The COMPLETE_B write is produced by **Phase 6e+1 Session B Closure** (`~/.valves/commands/valves.md` § Phase 6e+1: Session B Closure) — that step writes `CHECKPOINT_LEVEL: COMPLETE_B` only after a hard pre-write integrity check confirms Session B's substantive completion (verification per mode contract, cross-session consensus present, report pipeline complete, AUDIT_REPORT.md present with legal writer). The embargo here is the consumer; Phase 6e+1 is the producer. If Phase 6e+1 never wrote COMPLETE_B (its pre-write check failed), the checkpoint stays at COMPLETE_A and this embargo condition fires → INCOMPLETE THOROUGH or INVALID FINALIZATION.
- (v1.7-PATCH10, Thorough only) `cross_session_consensus.md` is missing (Session B independence was not verified). This is also confirmed by the `cross_session_consensus_present: YES` field in the COMPLETE_B checkpoint — both checks compose: the artifact must exist on disk AND the closure step must have verified it.

### Mechanical enforcement (orchestrator inline)

Before emitting any "THOROUGH RUN COMPLETE" banner, the orchestrator:

```
1. Read mandatory_step_checklist.md row-by-row.
2. Read violations.md and grep for unresolved enforcement violations:
     - SCOPE_VIOLATION_PERSISTENT
     - INVALID_FINALIZATION_*
     - COMPLETE_A_BOUNDARY_INTEGRITY_FAILURE
     - PROTECTED_ARTIFACT_PRE_WRITE_GATE_BLOCKED (if no subsequent resolution)
     - ILLEGAL_WRITER_* (if no subsequent successful re-spawn)
     - DRIFT_DETECTED_PENDING_WITH_COMPLETE_CONSUMER (if not cleared)
3. Verify session boundary integrity:
     - if MODE == THOROUGH: session_checkpoint.md status == COMPLETE_B (NOT just COMPLETE_A)
     - if MODE == THOROUGH: cross_session_consensus.md exists
4. Verify report integrity:
     - AUDIT_REPORT.md exists at PROJECT_ROOT
     - AUDIT_REPORT.md was written by Assembler Agent (per artifact-ownership.md § Control table)
     - report_index.md, report_critical_high.md, report_medium.md, report_low_info.md exist and were written by named producer agents
5. Compute embargo_holds.
```

### Completion states (v1.7-PATCH10 — explicit labeling)

The Phase 6f embargo emits ONE of three terminal states. The audit deliverable (if any) is labeled accordingly:

#### State 1: VALID THOROUGH DELIVERABLE
- All embargo conditions clear (`embargo_holds == false` and no unresolved violations).
- All mandatory rows terminal with valid evidence and legal writers.
- Session boundary respected (COMPLETE_A reached, Session B in fresh conversation, COMPLETE_B reached, cross_session_consensus.md present).
- Pre-Report Gate passed; full pipeline executed.

Banner:
```
====================================================================
THOROUGH RUN COMPLETE — VALID DELIVERABLE
====================================================================
Mode: thorough
Outcome: VALID
Total rows: {N} | COMPLETE: {C} | FAILED_WITH_FALLBACK: {F} | NOT_APPLICABLE: {NA}
Conservation Check: PASSED
Session boundary: respected (COMPLETE_A → COMPLETE_B)
Cross-Session Consensus: applied
Findings: {Critical}/{High}/{Medium}/{Low}/{Info}
Deliverable: {PROJECT_ROOT}/AUDIT_REPORT.md
====================================================================
```

#### State 2: INCOMPLETE THOROUGH (degraded)
- Some embargo conditions failed but the pipeline produced partial output.
- Recovery Loop attempted but did not fully clear blocking rows.
- Findings may be useful but the run does NOT meet the Thorough contract.

Banner:
```
====================================================================
THOROUGH RUN INCOMPLETE — DEGRADED OUTPUT (NOT a valid Thorough deliverable)
====================================================================
Mode: thorough
Outcome: INCOMPLETE
Blocking rows / artifacts:
{list each: row# | step | status | reason}

Recovery iterations attempted: {N} / 3
Recovery outcome: FAILED

The artifacts on disk represent EXPLORATORY OUTPUT only:
  - findings may be useful but were NOT verified through the
    full Thorough pipeline (no PoCs, no Skeptic-Judge, no
    Session B independence, etc.)
  - this run does NOT meet the Thorough contract
  - this run MUST NOT be presented as a Thorough audit
  - benchmark comparisons against valid Thorough runs are NOT
    apples-to-apples

If AUDIT_REPORT.md was generated (e.g., partial generation that
slipped through the Pre-Report Gate), prepend the disclaimer:
  ## NOTICE: This audit run is INCOMPLETE and was DEGRADED.
  ## See `compliance_summary.md` § Outcome.

Continue work in a fresh run with the architecture honored.
====================================================================
```

The orchestrator MUST also:
- Append the same NOTICE to AUDIT_REPORT.md (top of file)
- Set `Outcome: INCOMPLETE` in compliance_summary.md
- DO NOT delete AUDIT_REPORT.md (the user may still want to inspect findings) but DO NOT remove the NOTICE either

#### State 3: INVALID FINALIZATION
- Embargo conditions failed AND a HIGH-severity enforcement violation was logged AND not resolved.
- Specifically: `SCOPE_VIOLATION_PERSISTENT` (agent kept sub-orchestrating after re-spawn) OR
  `COMPLETE_A_BOUNDARY_INTEGRITY_FAILURE` (Session A claimed complete but bundle broken) OR
  `ILLEGAL_WRITER_HP_OUT_OF_SCOPE` unresolved (HP rogue spawn not contained).

Banner:
```
====================================================================
INVALID FINALIZATION — RUN HALTED FOR ARCHITECTURE INTEGRITY
====================================================================
Mode: thorough
Outcome: INVALID

Enforcement violation(s) that triggered halt:
{list each: violation code | timestamp | reason}

This run cannot produce a deliverable. The pipeline detected an
architecture integrity failure that the recovery system could not
contain. Specifically:
  - non-orchestrator agent sub-orchestrated and was unable to be
    re-spawned within scope, OR
  - Session A boundary was breached and the integrity check failed, OR
  - the orchestrator attempted to synthesize an agent-owned artifact
    that the pre-write gate could not allow.

Any artifacts on disk are NOT a deliverable. Do NOT publish, share,
or use this run's output.

Recommended action: restart the audit in a fresh project directory
or fresh conversation. If this is a recurring failure, the v1.7-PATCH
prompt may need additional hardening for the specific failure pattern.
====================================================================
```

The orchestrator MUST:
- DELETE or rename AUDIT_REPORT.md to `AUDIT_REPORT.INVALID.md` so it cannot be mistaken for a deliverable
- Set `Outcome: INVALID` in compliance_summary.md
- Halt the pipeline immediately (no further steps)

### When `embargo_holds == false` (clean run)

The orchestrator emits the State 1 banner. AUDIT_REPORT.md is the deliverable. compliance_summary.md records `Outcome: COMPLETE`.

### Recovery Loop (unchanged from v1.5, applies to embargo evaluation)

1. Try Recovery Loop (max 3 iterations) per § Recovery Loop above.
2. After each iteration, re-evaluate embargo conditions.
3. If recovery clears the embargo → State 1 (VALID).
4. If recovery does NOT clear AND no enforcement violations → State 2 (INCOMPLETE).
5. If recovery does NOT clear AND HIGH enforcement violations exist → State 3 (INVALID).

For Light/Core: Phase 6f is skipped. The pipeline ends after Phase 6e finalization without an embargo gate. Light/Core deliverables are inherently NOT Thorough — they're labeled by their mode at the top of the report (per Light mode disclaimer override #9).
