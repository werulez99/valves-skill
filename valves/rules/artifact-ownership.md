# Artifact Ownership Contract (v1.7-PATCH10)

> Compact source-of-truth for **who can write what artifact**. Used by:
> - Universal post-spawn integrity check (orchestrator inline, after every Task() returns)
> - Protected-artifact pre-write gate (orchestrator inline, before any orchestrator-inline write)
> - Row synchronization (every COMPLETE row in `mandatory_step_checklist.md` must cite an allowed writer)
> - Pre-Report Gate (Phase 6 entry — refuses if artifacts have illegal writers)
> - Final embargo (Phase 6f — refuses VALID THOROUGH banner if any artifact has an illegal writer logged in `violations.md`)
>
> This file is mechanical contract, not doctrine. The control table below is the authoritative ownership map.

## § Ownership classes

- **AGENT-OWNED**: only the named producer agent may write this artifact. Orchestrator MUST NOT synthesize directly. If the producer fails, mark the row FAILED_WITH_FALLBACK with a non-trivial reason and emit the fallback artifact (if defined). Self-synthesis is an `ILLEGAL_WRITER` violation.
- **ORCHESTRATOR-INLINE**: the orchestrator writes this directly per its slash-command logic. No agent is spawned. These are mechanical / state / tracking artifacts.
- **EITHER**: producer agent normally writes; orchestrator may write only as explicit fallback per the artifact's rule file.

## § Forbidden patterns (any artifact)

- Non-orchestrator agents MAY NOT write any artifact in the ORCHESTRATOR-INLINE class.
- Non-orchestrator agents MAY NOT write any AGENT-OWNED artifact whose owner ≠ themselves.
- Non-orchestrator agents MAY NOT spawn nested Claude / LLM subprocesses (`claude --print`, `claude -p`, `npx claude`, `bunx claude`, `yarn claude`, `exec claude`, `spawn claude`, `sh -c "claude...`, equivalent). See `~/.valves/rules/valves-doctrine.md` § Agent tool discipline.

## § Control table — authoritative ownership map

| Artifact | Class | Owner / Allowed Writer(s) | Producing Phase | Hard/Soft | Prerequisites |
|---|---|---|---|---|---|
| `mandatory_step_checklist.md` | ORCHESTRATOR-INLINE | orchestrator | Phase 1 init + every phase update | HARD | — |
| `pipeline_trace.md` | ORCHESTRATOR-INLINE | orchestrator | every phase transition | HARD | — |
| `violations.md` | ORCHESTRATOR-INLINE | orchestrator | on violation | HARD (auto-created) | — |
| `degradation_log.md` | ORCHESTRATOR-INLINE | orchestrator | on degradation | SOFT | — |
| `compliance_summary.md` | ORCHESTRATOR-INLINE | orchestrator | Phase 6f only | HARD (Thorough) | row 50 terminal |
| `session_checkpoint.md` (PARTIAL_A / COMPLETE_A / COMPLETE_B) | ORCHESTRATOR-INLINE | orchestrator | PARTIAL_A: every major Session A phase | COMPLETE_A: COMPLETE_A handoff bundle (Session A close) | COMPLETE_B: Phase 6e+1 Session B Closure (v1.7-PATCH10, mode=Thorough+session=B only) | HARD | per state |
| `HALT_AFTER_COMPLETE_A.md` (v1.7-PATCH10.3) | ORCHESTRATOR-INLINE | orchestrator | COMPLETE_A boundary enforcement (first action, before bundle integrity check) | HARD | row 22 COMPLETE (confidence scoring done). Deleted on `fresh-run` override. Consumed by Phase 0.9 § E at every phase boundary. |
| `SESSION_B_READ_SCOPE.md` (v1.7-PATCH11) | ORCHESTRATOR-INLINE | orchestrator | COMPLETE_A step 1.5 scratchpad rotation (written into fresh scratchpad) | HARD | scratchpad rotation completed. Consumed by Session B § 0 isolation contract + Phase 0.9 § A agent read-target check. |
| `SESSION_B_COMPLETE.md` (v1.7-PATCH11.1) | ORCHESTRATOR-INLINE | orchestrator | Phase 6e+1 Session B Closure (written alongside COMPLETE_B checkpoint) | HARD | All COMPLETE_B preconditions met. Consumed by Step 0-pre consistency check. |
| `.audit_session_a/` directory (v1.7-PATCH11) | ORCHESTRATOR-INLINE | orchestrator (rename) | COMPLETE_A step 1.5 scratchpad rotation | HARD | Entire Session A scratchpad archived here. Read-denied to Session B until cross-session consensus (Phase 5.6.1+). |
| `recon_summary.md` | AGENT-OWNED | Recon Agent 2 (sonnet) | Phase 1 | HARD | — |
| `template_recommendations.md` | AGENT-OWNED | Recon Agent 3 (opus) | Phase 1 | HARD | — |
| `attack_surface.md` | AGENT-OWNED | Recon Agent 3 | Phase 1 | HARD | — |
| `design_context.md` | AGENT-OWNED | Recon Agent 1B (opus) | Phase 1 | HARD | — |
| `meta_buffer.md` | AGENT-OWNED | Recon Agent 1A (background) | Phase 1 | SOFT | — |
| `historical_prime_seeds.md` | AGENT-OWNED | Historical Prime Agent (sonnet) — **OWNER, sole writer** | Phase 1.2 | HARD when HP=ON | — |
| `spawn_manifest.md` | ORCHESTRATOR-INLINE | orchestrator (Phase 2) | Phase 2 | HARD | template_recommendations.md COMPLETE |
| `diff_audit_*.md` | AGENT-OWNED | Diff-Audit Agent (per-parent, opus) | Phase 1.5 | SOFT | meta_buffer.md fork ancestry |
| `diff_audit_tiers.md` | ORCHESTRATOR-INLINE | orchestrator (merge) | post-1.5 | SOFT | diff_audit_*.md |
| `analysis_*.md` (breadth) | AGENT-OWNED | Phase 3 breadth agents (1 per template) | Phase 3 | HARD | spawn_manifest.md |
| `analysis_rescan_*.md` | AGENT-OWNED | Phase 3b re-scan agents | Phase 3b (Thorough) | HARD (Thorough) | findings_inventory.md (initial) |
| `analysis_percontract_*.md` | AGENT-OWNED | Phase 3c per-contract agents | Phase 3c (Thorough) | HARD (Thorough) | contract_inventory.md |
| `findings_inventory.md` | AGENT-OWNED | Initial Inventory Agent (Phase 4a.1-pre) + Inventory Merge Agent (4a.1-final) | Phase 4a.1 | HARD | analysis_*.md |
| `strongest_exploit_cards.md` | AGENT-OWNED | Strongest Exploit Gate Agent (opus) | Phase 4a.1.5 | HARD | findings_inventory.md final |
| `finding_classification.md` | AGENT-OWNED | Classification Agent (sonnet) | Phase 4a.2-lite | HARD | strongest_exploit_cards.md |
| `attack_thesis.md` (v1) | AGENT-OWNED | Thesis v1 Agent (sonnet) | Phase 4a.3 | HARD | finding_classification.md, strongest_exploit_cards.md |
| `attack_thesis.md` (v2) | AGENT-OWNED | Thesis Synthesis Agent (sonnet) | Phase 4b post-iter1 | HARD | confidence_scores.md, economic_findings.md |
| `attack_thesis.md` (v3) | EITHER | Thesis v3 (orchestrator-inline per attack-thesis.md § v3 Generation) OR designated Thesis v3 agent | Phase 5.6.1 | HARD | verify_*.md, verification_inheritance.md |
| `semantic_invariants.md` | AGENT-OWNED | Semantic Invariants Agent (sonnet) | Phase 4a.5.a | SOFT | — |
| `system_breakpoints.md` | AGENT-OWNED | System Breakpoints Agent (sonnet) | Phase 4a.5.b | SOFT | design_context.md |
| `propagation_structural.md` | AGENT-OWNED | Propagation P1 Agent (sonnet) | Phase 4a.5.c | SOFT | finding_classification.md |
| `symmetric_pairs.md` | AGENT-OWNED | Propagation P1 Agent | Phase 4a.5.c | SOFT | — |
| `external_platform_limits.md` | AGENT-OWNED | Propagation P1 Agent | Phase 4a.5.c | SOFT | — |
| `external_mutability_candidates.md` | AGENT-OWNED | Propagation P1 Agent | Phase 4a.5.c | SOFT | — |
| `candidate_seeds.md` | AGENT-OWNED | Structural Anomaly Harvester (sonnet) | Phase 4a.5.d | SOFT | — |
| `assumption_breaker_seeds.md` | AGENT-OWNED | Assumption-Breaker Agent (sonnet) | Phase 4a.5.e | SOFT | candidate_seeds.md |
| `analog_seeds.md` | ORCHESTRATOR-INLINE | orchestrator (per analog-seeds.md § Skip protocol or active path) | Phase 4a.5.f | SOFT | — |
| `invariant_fuzz_results.md` | AGENT-OWNED | Invariant Fuzz Agent | pre-Depth | HARD (Thorough EVM) | — |
| `medusa_fuzz_findings.md` | AGENT-OWNED | Medusa Agent | pre-Depth | HARD (Thorough EVM, Medusa available) | — |
| `analysis_depth_*.md` | AGENT-OWNED | Phase 4b iter 1 depth agents (4: token_flow, state_trace, edge_case, external) | Phase 4b iter 1 | HARD | findings_inventory.md, finding_classification.md |
| `analysis_scanner_*.md` | AGENT-OWNED | Blind-Spot Scanners A/B/C | Phase 4b iter 1 | HARD | findings_inventory.md |
| `validation_sweep.md` | AGENT-OWNED | Validation Sweep Agent | Phase 4b iter 1 | HARD | findings_inventory.md, system_breakpoints.md, strongest_exploit_cards.md |
| `economic_findings.md` | AGENT-OWNED | Economic Incentive Agent (opus) | Phase 4b iter 1 (+iter 2 Thorough) | HARD | design_context.md, attack_surface.md |
| `niche_*_findings.md` | AGENT-OWNED | Niche agents (per template_recommendations.md) | Phase 4b iter 1 | per-niche | template_recommendations.md |
| `confidence_scores.md` | AGENT-OWNED | Scoring Agent (haiku) | Phase 4b post-iter1 | HARD (Core/Thorough) | analysis_depth_*.md, analysis_scanner_*.md, validation_sweep.md |
| `analysis_depth_da_*.md` | AGENT-OWNED | Phase 4b iter 2-3 DA agents (Session B) | Phase 4b iter 2-3 | HARD (Thorough) | confidence_scores.md, session_a_to_b_handoff.md |
| `coverage_density.md` | ORCHESTRATOR-INLINE | orchestrator (COMPLETE_A handoff sub-step #1) | COMPLETE_A boundary | HARD (Thorough) | findings_inventory.md, attack_surface.md |
| `negative_space.md` | ORCHESTRATOR-INLINE | orchestrator (COMPLETE_A handoff sub-step #2) | COMPLETE_A boundary | HARD (Thorough) | coverage_density.md |
| `seed_outcomes.md` | ORCHESTRATOR-INLINE | orchestrator (COMPLETE_A handoff sub-step #3) | COMPLETE_A boundary | HARD (Thorough) | candidate_seeds.md, assumption_breaker_seeds.md, analog_seeds.md |
| `canonical_seed_map.md` | ORCHESTRATOR-INLINE | orchestrator (COMPLETE_A handoff sub-step #4) | COMPLETE_A boundary | HARD (Thorough) | seed_outcomes.md |
| `disagreement_queue.md` | ORCHESTRATOR-INLINE | orchestrator (COMPLETE_A handoff sub-step #5) | COMPLETE_A boundary | HARD (Thorough) | analysis_*.md, validation_sweep.md |
| `session_a_to_b_handoff.md` | ORCHESTRATOR-INLINE | orchestrator (COMPLETE_A handoff sub-step #6) | COMPLETE_A boundary | HARD (Thorough — gates Session B start) | sub-steps #1-#5, confidence_scores.md, findings_inventory.md, attack_thesis.md v1/v2 |
| `blind_spot_report.md` | ORCHESTRATOR-INLINE | orchestrator (back-compat) | COMPLETE_A boundary | SOFT (back-compat only) | — |
| `cross_session_consensus.md` | ORCHESTRATOR-INLINE | orchestrator (post-Session-B re-scoring) | post-Session-B | HARD (Thorough) | session_checkpoint.md COMPLETE_A, Session B confidence_scores.md, analysis_depth_da_*.md |
| `rag_validation.md` | AGENT-OWNED | RAG Sweep Agent (sonnet) | Phase 4b.5 | HARD (Core/Thorough) | findings_inventory.md |
| `root_cause_clusters.md` | EITHER | (initial write) Full Cluster Agent (sonnet) at Phase 4b 8b | (instance-append only) orchestrator inline at Phase 4b 9 P2 — appends propagated instances per cluster, MUST NOT rewrite analytical content from initial write | Phase 4b 8b initial + Phase 4b 9 P2 append | HARD | findings_inventory.md, finding_classification.md, confidence_scores.md, attack_thesis.md v2, strongest_exploit_cards.md |
| `propagated_*.md` | AGENT-OWNED | P2 Propagation Agents (sonnet, one per cluster) | Phase 4b 9 | HARD | root_cause_clusters.md |
| `propagation_manifest.md` (v1.7-PATCH10.2 — added to manifest) | ORCHESTRATOR-INLINE | orchestrator (lists spawned vs stubbed clusters) | Phase 4b 9 | HARD | root_cause_clusters.md |
| `propagation_summary.md` (v1.7-PATCH10.2 — corrected from AGENT-OWNED) | ORCHESTRATOR-INLINE | orchestrator (merges propagated_*.md into a summary table — mechanical concatenation, no analysis) | Phase 4b 9 | HARD | propagated_*.md |
| `hypotheses.md` | AGENT-OWNED | Chain Analysis Agents | Phase 4c | HARD | findings_inventory.md, root_cause_clusters.md |
| `chain_hypotheses.md` | AGENT-OWNED | Chain Analysis Agents | Phase 4c | HARD | findings_inventory.md, root_cause_clusters.md |
| `verification_priority_queue.md` | ORCHESTRATOR-INLINE | orchestrator (Phase 4c.5, EV-ranking inline) | Phase 4c.5 | HARD | hypotheses.md, root_cause_clusters.md, attack_thesis.md v2 |
| `verify_*.md` | AGENT-OWNED | Phase 5 Verifier Agents (one per finding) | Phase 5 | HARD (per Mode policy) | verification_priority_queue.md |
| `verify_skeptic_*.md` | AGENT-OWNED | Skeptic-Judge Agents | Phase 5.1 (Thorough HIGH/CRIT) | HARD if HIGH/CRIT exist | verify_*.md for matching finding |
| `cross_batch_consistency.md` | AGENT-OWNED | Cross-Batch Consistency Agent (haiku) | Phase 5.2 | HARD (Core/Thorough) | verify_*.md |
| `verification_inheritance.md` | ORCHESTRATOR-INLINE | orchestrator (Phase 5.6.2 inline) | Phase 5.6.2 | HARD | verify_*.md, root_cause_clusters.md |
| `audit_negative_results.md` | EITHER | orchestrator inline stub-ensure (Phase 5.6.3.a); appends from Phase 4b depth, Phase 4c chain REFUTED, Phase 5 [POC-FAIL: GENUINE] | Phase 5.6.3 | HARD | — |
| `cluster_instance_map.md` | AGENT-OWNED | Cluster Instance Map Agent (sonnet) | Phase 5.6.5 | HARD | root_cause_clusters.md, verify_*.md, verification_inheritance.md, attack_thesis.md v3 |
| `report_index.md` | AGENT-OWNED | Report Index Agent (haiku) | Phase 6a | HARD | cluster_instance_map.md, all upstream COMPLETE |
| `report_critical_high.md` | AGENT-OWNED | Tier Writer (Critical+High, opus) | Phase 6b | HARD | report_index.md |
| `report_medium.md` | AGENT-OWNED | Tier Writer (Medium, sonnet) | Phase 6b | HARD | report_index.md |
| `report_low_info.md` | AGENT-OWNED | Tier Writer (Low+Info, sonnet) | Phase 6b | HARD | report_index.md |
| `AUDIT_REPORT.md` | AGENT-OWNED | Assembler Agent (haiku/sonnet) | Phase 6c | HARD | report_index.md, report_critical_high.md, report_medium.md, report_low_info.md, all upstream COMPLETE |
| `report_review.md` | AGENT-OWNED | Report Quality Self-Review Agent (haiku) | Phase 6d | HARD | AUDIT_REPORT.md |
| `report_quality.md` | EITHER | Report Quality Self-Review Agent OR orchestrator-inline summary | Phase 6d | SOFT | report_review.md |
| `strongest_exploit_final_check.md` | ORCHESTRATOR-INLINE | orchestrator (Phase 6d.5 inline per v1.7-PATCH5 PATCH 1) | Phase 6d.5 | HARD (when strongest_exploit_cards.md exists) | strongest_exploit_cards.md, findings_inventory.md, cluster_instance_map.md, AUDIT_REPORT.md |
| `seed_metrics.md` | ORCHESTRATOR-INLINE | orchestrator (Phase 6e tail) | Phase 6e | SOFT | seed_outcomes.md, canonical_seed_map.md |
| `coverage_lift.md` | ORCHESTRATOR-INLINE | orchestrator (Phase 6e tail) | Phase 6e | SOFT | findings_inventory.md, session_a_to_b_handoff.md |
| `run_state.json` (v1.7-PATCH11) | ORCHESTRATOR-INLINE | orchestrator (every phase transition + before/after every action) | Step 0.85c init + continuous | HARD | — (self-bootstrapping) |
| `manifest_*.md` (v1.7-PATCH11) | ORCHESTRATOR-INLINE | orchestrator (Phase 0.9 § G, before every multi-agent spawn) | Per-phase (see § G manifest table) | HARD | run_state.json |

## § Allowed-writer enforcement

The orchestrator runs three checks against this manifest:

### 1. Universal post-spawn integrity check (after every Task() returns)

After every `Task()` call returns, BEFORE accepting the agent's output:
1. Read the agent's tool trace.
2. For each Bash command in the trace, grep against the forbidden-patterns list (`~/.valves/rules/valves-doctrine.md` § Agent tool discipline).
3. For each `Write` / `Edit` tool call, check the target path against this manifest's control table:
   - If the target is ORCHESTRATOR-INLINE → `ILLEGAL_WRITER_ORCHESTRATOR_ARTIFACT_BY_AGENT` violation.
   - If the target is AGENT-OWNED but the producer ≠ this agent → `ILLEGAL_WRITER_WRONG_AGENT` violation.
   - If the target is not in the manifest → `UNREGISTERED_ARTIFACT_WRITTEN` (informational warning, not a violation).
4. If any violation fires → log to `violations.md` with severity HIGH; mark the agent's outputs TAINTED in `degradation_log.md`; re-spawn ONCE with stricter prompt (forbidden patterns + scope explicit). If re-spawn also violates → halt the run via the embargo (Phase 6f) and emit `INVALID_FINALIZATION_AGENT_SCOPE_PERSISTENT`.

### 2. Protected-artifact pre-write gate (before any orchestrator-inline write)

Before the orchestrator writes ANY ORCHESTRATOR-INLINE artifact:
1. Look up the artifact in this control table.
2. Verify the orchestrator is in the correct phase (matches `Producing Phase` column).
3. Verify all `Prerequisites` rows are in terminal state in `mandatory_step_checklist.md`.
4. If any check fails → log `PROTECTED_ARTIFACT_PRE_WRITE_GATE_BLOCKED` to `violations.md` with the artifact name and missing prerequisite. Refuse the write. Halt the current step and trigger Recovery Loop per `~/.valves/rules/thorough-strict-mode.md` § Recovery Loop.

### 3. Pre-Report Gate (before Phase 6a)

Before spawning the Report Index Agent (Phase 6a):
1. Verify every row in `mandatory_step_checklist.md` for phases ≤ 5.6.5 is in {COMPLETE, FAILED_WITH_FALLBACK, NOT_APPLICABLE} per `~/.valves/rules/thorough-strict-mode.md` § Valid terminal states.
2. Verify every COMPLETE row has its named evidence artifact ON DISK and the artifact's writer (per this manifest) is the named producer for that row.
3. If any row is non-terminal OR any artifact is missing OR any writer is illegal → emit the PRE_REPORT_GATE_BLOCKED banner and HALT. Do NOT spawn the Report Index Agent. Trigger Recovery Loop. If recovery fails 3 times → final embargo blocks finalization.

## § Why this is mechanical

- The control table is a flat data structure (artifact → owner / producer / class).
- All three checks are mechanical (string matching against the table, status checks against the checklist).
- No reasoning required — orchestrator either passes or fails the check.
- Violations are logged to existing `violations.md` / `degradation_log.md`. No new artifact required.
- Failure modes are explicit (TAINTED outputs, BLOCKED writes, BLOCKED report) and feed into the existing embargo logic.

## § Hard rule

Any artifact in this manifest that is found on disk with an illegal writer (per `violations.md` `ILLEGAL_WRITER_*` entries) AND not subsequently re-spawned successfully → the run cannot be marked VALID THOROUGH. The Phase 6f embargo refuses VALID THOROUGH finalization and emits INCOMPLETE THOROUGH or INVALID FINALIZATION (per `~/.valves/rules/thorough-strict-mode.md` § Final Report Embargo + § Completion states).
