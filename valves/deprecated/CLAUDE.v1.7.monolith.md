<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Valves CLAUDE.md (v1.7.0, built on Plamen v1.1.8)

This document defines **Valves-specific orchestrator rules** that supplement Plamen's shared rules. The slash command at `~/.valves/commands/valves.md` is the orchestration source of truth. This file documents only the rule numbers it cites by reference.

When the slash command says "see Rule N in `~/.valves/CLAUDE.md`" or "per Rule N", look it up here. Rules not defined here (R1–R10, R12, R13, R16, R20–R27) are inherited from Plamen's `~/.claude/CLAUDE.md` and `~/.claude/prompts/{LANGUAGE}/generic-security-rules.md`.

---

## Rule 30 — COMPLETE_A Boundary Halt (v1.7-PATCH10.3 — HIGHEST PRIORITY)

> **This rule takes precedence over all other rules when they conflict. It is designed to survive context compaction.**

In **Thorough mode**, Session A MUST halt after depth iteration 1 + confidence scoring (row 22). The orchestrator:

1. Writes `{SCRATCHPAD}/HALT_AFTER_COMPLETE_A.md` (on-disk marker — compaction-proof ground truth)
2. Writes the COMPLETE_A handoff bundle (6 artifacts + session_checkpoint.md)
3. Emits the SESSION A COMPLETE banner
4. **STOPS. Does not proceed. Does not spawn any further agents. Does not generate reports.**

Session B (DA iter 2-3, chain analysis, verification, report) runs in a **FRESH Claude Code conversation**.

**Mechanical enforcement**: Phase 0.9 § E checks `file_exists("{SCRATCHPAD}/HALT_AFTER_COMPLETE_A.md")` at every phase boundary. If the marker exists and the orchestrator is still in Session A → HARD HALT regardless of what instructions are in the context window. The file on disk is the ground truth — it cannot be compacted away.

**Why this exists**: In long Thorough audits (3800+ lines of orchestration instructions), context compaction erases the halt instruction buried at line ~2200. The orchestrator then continues the pipeline in the same session, producing a single-session run that violates the Session A/B independence contract. Rule 30 makes the halt compaction-proof via the on-disk marker.

**Prohibited**: Marking Session-B-owned rows as `NOT_APPLICABLE: "Single-session audit"`. This is an INVALID FINALIZATION. There is no valid Thorough deliverable without Session B.

---

## Rule 31 — Physical Session Isolation (v1.7-PATCH11.3 — Thorough only)

At the COMPLETE_A boundary, Session A's scratchpad is physically rotated:
- `.audit_scratchpad` → `.audit_session_a` (archive, read-denied until consensus)
- Fresh `.audit_scratchpad` created with ONLY allowlisted handoff/factual artifacts

**Session B read denylist** (before cross-session consensus):
- `{PROJECT_ROOT}/.audit_session_a/*` — ALL files in the archive
- Any Session A analytical artifact (findings_inventory, hypotheses, attack_thesis, analysis_*, depth_*, verify_*, report_*, confidence_scores, rag_validation, etc.)

**Sole legal accessor**: The cross-session consensus step (Phase 5.6.1+) reads STRUCTURED FIELDS ONLY from the archive.

**Agent enforcement**: Phase 0.9 § A checks every agent's Read() targets against `.audit_session_a/`. First violation → AUTO-DISCARD + re-spawn. Second → SCOPE_VIOLATION_PERSISTENT → INVALID FINALIZATION.

**(v1.7-PATCH11.3) Post-rotation leak scan**: After physical rotation, the orchestrator scans the fresh scratchpad against a comprehensive denylist (~50 exact filenames + ~10 glob patterns) and deletes any leaked analytical artifacts. This catches: (1) allowlist copy bugs that included extra files, (2) race conditions where a background agent wrote to the old path after rotation, (3) symlink traversal that re-introduced archived files. The scan runs BEFORE Session B begins. See `valves.md` § COMPLETE_A boundary enforcement step 1.5 for the full denylist.

**(v1.7-PATCH11.3) Session B startup verification**: When Session B starts (Step 0-pre detects COMPLETE_A), the orchestrator re-runs the leak scan on the active scratchpad BEFORE spawning any Session B agents. If any analytical artifact is found, it is deleted and logged. This double-scan (post-rotation + pre-Session-B) ensures isolation even if files were introduced between conversations.

**Why physical, not logical**: Logical rules depend on the LLM following instructions. Physical rotation makes it impossible to read what isn't there — Session A analytical artifacts literally do not exist in Session B's workspace.

---

## Rule 32 — Agent-Owned Artifact Self-Synthesis Ban (v1.7-PATCH11.3)

When an agent reports "DONE" but its expected AGENT-OWNED artifact is missing from disk, the orchestrator MUST NOT write it. The orchestrator re-spawns the agent once; if it still fails, marks the row FAILED. The comprehensive denylist is in `~/.valves/commands/valves.md` Phase 0.9 § B `CRITICAL_AGENT_OWNED` (~40 entries covering report pipeline, clustering/chain, verification, inventory/scoring, analysis, recon, and thesis artifacts). Self-synthesis of ANY artifact on this list is a SCOPE_VIOLATION_PERSISTENT → INVALID FINALIZATION.

**(v1.7-PATCH11.3) Absolute ban**: The orchestrator MUST NOT write agent-owned artifacts under ANY justification — including "the agent returned its findings in the chat message so I'll persist them", "the output is small enough to reconstruct", "time pressure", "the agent almost wrote it", or "I'll write a stub and the next agent can extend it". The ONLY legal paths are: (1) the named producer agent writes its own file, or (2) the row is marked FAILED.

---

## Rule 33 — Crash-Safe Persisted State Machine (v1.7-PATCH11.2)

The orchestrator maintains `{SCRATCHPAD}/run_state.json` as a JSON execution state file that survives context compaction, usage exhaustion, and mid-run interruptions. The pipeline can be reconstructed from disk state alone.

**Core invariants**:
1. **JSON format**: `run_state.json` is a valid JSON object (not markdown). Parsed mechanically; never regex-scanned.
2. **Session + checkpoint tracking**: `session` field tracks A/A_RESUMED/B/B_RESUMED. `checkpoint_level` provides monotonic progression: NONE → PARTIAL_A → COMPLETE_A → PARTIAL_B → COMPLETE_B.
3. **PARTIAL_B on Session B entry**: When Session B starts (new conversation after COMPLETE_A), the orchestrator writes `checkpoint_level: "PARTIAL_B"`, `session: "B"` IMMEDIATELY — before any Session B agent spawn. This is a hard invariant; entering Session B without PARTIAL_B on disk is illegal.
4. **Write-ahead intent**: Before any agent spawn or multi-tool-call artifact write, update `run_state.json` with `write_ahead.interrupted: true`. After success, write `write_ahead.interrupted: false`. On resume, `interrupted: true` means the action needs re-attempt.
5. **Phase manifests**: Every multi-agent phase creates `manifest_{phase_id}.md` BEFORE spawning. On resume, re-spawn only agents whose output is missing.
6. **Three-way reconciliation**: At every phase boundary (Phase 0.9 § F), verify consistency between `run_state.json`, `mandatory_step_checklist.md`, and disk artifacts.
7. **Idempotent pre-spawn checks**: Before spawning any agent, check if expected output exists + valid + belongs to current session. Skip if already complete.
8. **Session-aware contamination check**: The old FORBIDDEN_IN_FRESH_SCRATCHPAD auto-delete is replaced by a check that reads `checkpoint_level` from `run_state.json` before acting. Session B's own work products (hypotheses.md, etc.) are NOT deleted when `checkpoint_level == "PARTIAL_B"`.
9. **Atomic writes**: `run_state.json` is always written as a complete file (Write tool, not Edit). Critical state files use full-file writes.
10. **No duplicate spawns**: Manifest-based resume checks disk for existing valid output before re-spawning.
11. **(PATCH11.1) Session B fail-closed startup**: Session B entry requires ALL four files: `run_state.json`, `SESSION_B_READ_SCOPE.md`, `session_checkpoint.md`, `session_a_to_b_handoff.md`. Missing any one → `SESSION_B_MISSING_PREREQUISITES` → HALT. No silent rebuilds.
12. **(PATCH11.1) COMPLETE_B triple-write**: Phase 6e+1 writes COMPLETE_B to `session_checkpoint.md`, `run_state.json`, AND `SESSION_B_COMPLETE.md`. Post-write consistency assertion verifies all three agree.
13. **(PATCH11.1) Disk state is authoritative**: After compaction/interruption, the orchestrator resumes from `run_state.json` + `mandatory_step_checklist.md` + `session_checkpoint.md`. Conversational momentum does not override on-disk state.

**Failure recovery hierarchy**:
- `run_state.json` exists + `write_ahead.interrupted == true` → crash recovery
- `run_state.json` exists + `phase_status == "DONE"` → clean resume
- `run_state.json` exists + `phase_status == "FAILED"` → retry (up to 3 attempts)
- `run_state.json` missing but `session_checkpoint.md` exists → legacy checkpoint routing
- Neither exists → fresh run

**Session isolation preserved**: `run_state.json` is in the ALLOWLIST for scratchpad rotation. At COMPLETE_A, it is copied to fresh scratchpad with `checkpoint_level: "COMPLETE_A"`. Session B entry transitions to `PARTIAL_B`.

**Checkpoint consistency**: If `SESSION_B_COMPLETE.md` exists but `session_checkpoint.md` ≠ COMPLETE_B → `SESSION_B_CHECKPOINT_INCONSISTENCY` → HALT. If `run_state.json` says COMPLETE_B but `session_checkpoint.md` disagrees → same violation. State must be consistent across all three files.

**(PATCH11.2) Additional hard invariants**:
14. **Post-hoc handoff synthesis banned**: If Session A is past row 22 but checkpoint_level ≠ COMPLETE_A, the run is INVALID. The orchestrator MUST NOT retroactively build the handoff bundle. Violation: `POST_HOC_HANDOFF_SYNTHESIS_BANNED` → HALT.
15. **Orchestrator self-synthesis banned**: The orchestrator MUST NOT write AGENT-OWNED artifacts directly. If the named producer agent failed, re-spawn ONCE per § B.1. If still missing, mark FAILED. Violation: `ORCHESTRATOR_SELF_SYNTHESIS_BANNED`.
16. **Disk over conversation**: At every phase boundary (§ F), disk state (`run_state.json` + `mandatory_step_checklist.md` + marker files) overrides whatever the orchestrator "remembers" from prior turns.
17. **Resume test harness**: `~/.valves/state/checkpoint_resume_test.sh` validates 12 checkpoint/resume + orchestration integrity state assertions mechanically (tests 1-6: PATCH11.2 checkpoint/resume; tests 7-12: PATCH11.3 artifact validation, self-synthesis ban, post-hoc ban, Session B isolation, stale artifact detection). Run against any project with a Valves scratchpad.

See `~/.valves/rules/execution-state.md` for full schemas (R1-R10) + § Acceptance Checks.

---

## Rule 11 — MCP Timeout Directive (MANDATORY)

Every agent prompt that makes MCP tool calls (recon, depth, chain, verifiers, RAG sweep) MUST include this directive at the end of its prompt:

> "When an MCP tool call returns a timeout error or fails, do NOT retry the same call. Record `[MCP: TIMEOUT]` and skip ALL remaining calls to that provider — switch immediately to fallback (code analysis, grep, WebSearch). Claude Code's tool timeout is set to 300s (5 min) via `MCP_TOOL_TIMEOUT` in settings.json to accommodate ChromaDB cold start. You cannot cancel a pending call — but you control what happens after the error returns."

**Enforcement**: orchestrator appends this text when composing prompts for MCP-calling agents. Agents that do not make MCP calls (pure code-analysis breadth agents, report writers) do not need it.

---

## Rule 14 — Operational Implications Quality Gate

After the recon agents return, read `{scratchpad}/design_context.md`. Verify it contains an `## Operational Implications` section with **at least one implication per documented Key Invariant**. If the section is missing or under-populated, re-prompt Agent 1B:

> "The Operational Implications section in design_context.md is incomplete. For each Key Invariant, state what it means for how the system's accounting works — not what it checks, but what it tells you about the system's model. Derive from invariant formulas and data structure signatures."

This gate prevents downstream agents from analyzing a protocol they don't understand.

---

## Rule 15 — Asymmetric Gate List

Not every artifact has the same gate strength. Valves splits artifacts into HARD gates (block the pipeline if missing) and SOFT gates (degrade and log).

**HARD gates** (orchestrator MUST block until present, retry the responsible agent):
- `findings_inventory.md` (Phase 4a.1, Plamen-style)
- `finding_classification.md` (Phase 4a.2-lite, Valves)
- `attack_thesis.md` v1 (Phase 4a.3, Valves)
- `strongest_exploit_cards.md` (Phase 4a.1.5, Valves, Rule 19)
- `root_cause_clusters.md` (post-depth, Phase 4b step 8b — NOT pre-depth)
- `verification_priority_queue.md` (Phase 4c.5, Valves)
- `verification_inheritance.md` (Phase 5, cluster inheritance)
- `attack_thesis.md` v3 (Phase 5.6.1)
- `cluster_instance_map.md` (Phase 5.6.5, gates Phase 6)
- **`session_a_to_b_handoff.md`** (v1.7-PATCH PATCH I — gates Session B start in Thorough; Step 0-pre integrity check appends this assertion alongside `findings_inventory.md` and `blind_spot_report.md`)
- **`cross_session_consensus.md`** (v1.7-PATCH PATCH J — gates Phase 5.6.1 Thesis v3 generation in Thorough; Core/Light degrade-and-log)

**SOFT gates** (Phase 4a.5 + COMPLETE_A handoff-build outputs — degrade and log to `degradation_log.md`):
- `semantic_invariants.md`
- `system_breakpoints.md`
- `propagation_structural.md`
- `candidate_seeds.md`
- `symmetric_pairs.md`, `external_platform_limits.md`, `external_mutability_candidates.md` (P1 expansion)
- `audit_negative_results.md` (stub-ensure rule applies)
- **v1.7-PATCH new SOFT artifacts** — soft-required at COMPLETE_A boundary; if missing, the Session A → B Handoff Build degrades but the audit proceeds:
  - `assumption_breaker_seeds.md` (Phase 4a.5.e — PATCH H)
  - `analog_seeds.md` (Phase 4a.5.f — PATCH G; v1.7-PATCH2 makes this conditional — `## Source: SKIPPED` with the trigger-evaluation table is a valid SOFT-fulfilled state, NOT a fault)
  - `coverage_density.md` (COMPLETE_A handoff sub-step — PATCH A)
  - `negative_space.md` (COMPLETE_A handoff sub-step — PATCH E)
  - `seed_outcomes.md` (COMPLETE_A handoff sub-step — PATCH B; **v1.7-PATCH3 PATCH 1**: extended with Proof Type column + § CLEARED Proof Records sub-section per `~/.valves/rules/cleared-proof-discipline.md`. CLEARED rows missing proof are MECHANICALLY DOWNGRADED to FORWARD_TO_SESSION_B by the orchestrator-inline build — not a runtime block, recovery-by-routing.)
  - `canonical_seed_map.md` (COMPLETE_A handoff sub-step — v1.7-PATCH2 PATCH 1; **v1.7-PATCH3**: extended with § CLEARED Proof Records (PATCH 1) + § Sibling Links (PATCH 3) sub-sections. If missing, `session_a_to_b_handoff.md` § 2 falls back to raw `seed_outcomes.md`)
  - `disagreement_queue.md` (COMPLETE_A handoff sub-step — PATCH C)
  - `session_a_to_b_handoff.md` already a HARD gate (above); v1.7-PATCH3 PATCH 2 extends with § 0 Redistribution Metadata (slack pool max 3 slots, score threshold 0.40) + § 2 Linked CS column.
  - `seed_metrics.md` (Phase 6e tail — PATCH K; **v1.7-PATCH3 PATCH 4**: extended with proof-quality, rescue-rate-by-section, trigger activation, slack usage, conversion rates, FP kill rate. All descriptive — no auto-retuning.)
  - `coverage_lift.md` (Phase 6e tail — PATCH K; **v1.7-PATCH3 PATCH 4**: extended with downgrade-rescue, slack-rescue, sibling-link-assist, cross-source-canonical-conversion lift indicators.)
  - `~/.valves/references/MANIFEST.md` (v1.7-PATCH3 PATCH 5 — minimal scaffold; consumed by Phase 1.5 reference resolution step 3; absent → skipped silently)
- **v1.7-PATCH3 new rule files (governing rules, NOT runtime artifacts)**:
  - `~/.valves/rules/cleared-proof-discipline.md` — defines the four required proof fields, six proof types, downgrade rule. Read by orchestrator + depth iter 1 agents.

- **v1.7-PATCH4 — schema/rule extensions to existing files** (NO new artifacts; surgical extensions):
  - `~/.valves/rules/session-a-to-b-handoff.md` § Family-diversity cap (PATCH 3): § 2 soft cap of 2 entries per Seed Family with overflow refill; metadata in handoff § 0.
  - `~/.valves/rules/verification-priority-queue.md` § Rescue Reserve (PATCH 4): 10-15% verification budget for rescued targets (proof-gap downgrade, slack redistribution, sibling-link assist, cross-source canonical, family-diversity overflow).
  - `~/.valves/rules/negative-results.md` § Applicability metadata + § PRIOR_NEGATIVE handling stricter matching (PATCH 5): NR-G entries gain Applicability {protocol_family, trust_model_class, external_dependency_model, exploit_precondition_class} + Generalizability scope (LOCAL/WIDE). Pre-PATCH4 entries downgrade to advisory until back-filled.
  - Slash command `valves.md` Phase 6e tail extends `seed_metrics.md` with § Family saturation (PATCH 6).
  - `~/.valves/references/MANIFEST.md` hardening (PATCH 7): mandatory sha256 verification, six new error codes, strict field formats.
  - All v1.7-PATCH4 changes are SOFT/HARD-gate-compatible — the existing gate list above is unchanged. Schema extensions are additive (new columns / new sub-sections); legacy consumers reading old fields continue to work.

- **v1.7-PATCH5 — final-quality + diversity-control + observability extensions** (1 new SOFT artifact; remainder are surgical extensions to existing rules/schemas):
  - **NEW SOFT artifact**: `{SCRATCHPAD}/strongest_exploit_final_check.md` (Phase 6d.5, orchestrator inline; surfaces STRONGEST_DROPPED_BEFORE_REPORT and STRONGEST_DISPLACED_BY_WEAKER warnings; advisory only — does NOT auto-rewrite AUDIT_REPORT.md). PATCH 1.
  - `~/.valves/rules/verification-priority-queue.md` § Rescue-class diversity control (PATCH 2): soft cap 2 per rescue class inside the rescue reserve, with overflow refill on underfill, exemption when pool < 4. Recorded in seed_metrics § Rescue reserve diversity.
  - `~/.valves/rules/session-a-to-b-handoff.md` § Dominant-family override (PATCH 3): allow +1 extra slot for a dominant family in § 2 when its top held-back candidate's score gap to next-best alternative-family >= 0.25. Bounded at +1; final_total_targets upper bound becomes 36.
  - `~/.valves/references/MANIFEST.md` § Recommended high-frequency parents to populate first (PATCH 4): scaffold placeholders for OpenZeppelin ERC4626, Uniswap V3 pool, Aave V3 pool, Compound Comet, Balancer V2 Vault. NO real hashes / versions / URLs committed; activation is manual.
  - Slash command `valves.md` Phase 6e tail extends `seed_metrics.md` with § Reserve-to-final conversion (PATCH 5): main queue / orphan / rescue reserve conversion rates; per-rescue-class breakdown; override + sanity-check usage tracking; key derived ratios (rescue-uplift-over-orphan, diversity-control-yield, override-yield, strongest-final-check-effectiveness).
  - `~/.valves/rules/negative-results.md` § Evidence age / drift awareness (PATCH 6): single new optional field `evidence_age_class` ∈ {CURRENT / STALE / UNKNOWN} with 6-month auto-demotion. Stale/unknown entries downgrade to advisory regardless of applicability match.
  - All v1.7-PATCH5 changes preserve existing gate semantics. Schema extensions are additive; legacy consumers reading old fields continue to work.

- **v1.7-PATCH6 — final cleanup + usability pass before benchmarking** (NO new artifacts, NO new mechanics; pure drift cleanup + actionable-output extension + operator-workflow improvement):
  - **PATCH 1 (drift cleanup)**: corrected stale "5 sweeps" reference in slash command (now "8 sweeps"); aligned handoff hard upper bound to 36 across rule + slash command (slack +3 plus dominant-family +1); removed stale `final_total_targets: {32..35}` block; updated thorough-strict-mode.md header from "Rows 01-50" to "Rows 01-73 (baseline 01-50 + v1.7-PATCH appended rows 51-73)"; added `6d.5` to phase trace row list at line 784.
  - **PATCH 2 (strongest_exploit_final_check.md actionable schema)**: extended the per-surface table with structured columns (`Mismatch type`, `Why_lost`, `Recommendation`, `Competing_finding`, `Competing_subgroup`, `Competing_cluster`); enumerated 6 mismatch types (SEVERITY_DOWNGRADE / SUBGROUP_COLLAPSE / INHERITANCE_SHADOWING / THESIS_DISPLACEMENT / REPORT_ID_CONSOLIDATION / OTHER) and 6 recommendations (REVIEW_ONLY / CONSIDER_RESTORE_PARENT / CONSIDER_SPLIT_SUBGROUP / CONSIDER_REWEIGHT_SEVERITY / CONSIDER_RESELECT_INHERITANCE_REP / CONSIDER_RESTORE_THESIS_PATH / OTHER); added per-warning evidence block with explicit suggested action and reviewer effort estimate. Still advisory only — does NOT auto-rewrite AUDIT_REPORT.md.
  - **PATCH 3 (MANIFEST.md operator workflow)**: added § Activation checklist with copy-paste-friendly bash workflow (kebab-case parent name, real version pin, real source URL, sha256 computation, ISO-8601 date), § Pass conditions table, § Common activation pitfalls table mapping each failure mode to the existing strict-format error code. Strict verification semantics from v1.7-PATCH4 PATCH 7 unchanged. Placeholders remain obviously placeholders (`<PINNED_TAG>`, `<SHA256_64_HEX>`, `<YYYY-MM-DD>`).
  - All v1.7-PATCH6 changes are documentation/schema extensions only. Zero new artifacts, zero new agents, zero new phases, zero new metrics, zero new rules. Existing v1.7-PATCH5 gate semantics unchanged.

- **v1.7-PATCH7 — reasoning-quality hardening (deep-thinking pass)** — surgical reasoning-quality patches focused on better adversarial questions, call-order pressure, and unanswered-question capture. NO new phases, NO new agents, NO new sweeps, NO new external sources, NO new big artifacts. One new compact rule file (`valves-doctrine.md`). Architecture contract (Session A = recall, Session B = precision) preserved.
  - **PATCH 1 (assumption-pressure upgrade)**: Phase 4a.5.e Assumption-Breaker extended Q1-Q6 → Q1-Q7 (added Q7 sequence-not-enforced — the call-order pressure question). Total seed cap unchanged (5 seeds; Q1-Q7 compete on the standard "specificity + parent-exploit category" tie-break). System Breakpoints `Family` enum extended with `OrderingViolation`. The Assumption-Breaker output table also gained two OPTIONAL columns `Open Question` / `Disputed Assumption` (shape mirrors PATCH 2 below) — populated when the seed text yields a derivable question / assumption, blank otherwise.
  - **PATCH 2 (Open Question + Disputed Assumption capture)**: `canonical_seed_map.md` schema extended with two OPTIONAL columns `Open Question` (≤25 words) and `Disputed Assumption` (≤20 words). Filled ONLY when derivable mechanically from member evidence; otherwise `-`. NEVER invented. Propagated to `session_a_to_b_handoff.md` § 2 (Top unresolved seeds) — Session B DA prompts read these as the primary adversarial probe per row. The COMPLETE_A handoff sub-step copies columns verbatim from canonical to handoff; orchestrator does NOT invent values.
  - **PATCH 3 (decision-lens prompt rephrasing)**: Depth iter 1 spawn directive (slash command Phase 4b) and Session B DA agent prompt (Session B Behavioral Rules § 1) gained a one-line directive to read `~/.valves/rules/valves-doctrine.md` § The 8 mandatory adversarial questions + § The decision lenses. The 4 depth domains (token_flow / state_trace / edge_case / external) are preserved as code-region scopes; the LENS rephrasing is in the doctrine file. No new agents, no new spawns.
  - **PATCH 4 (call-order / sequence pressure as first-class lens)**: `canonical_seed_map.md` § Equivalence classes extended E1-E10 → E1-E11 (added E11 SEQUENCE for unenforced call-order seeds). Distinct from E8 EMERGENCY (which is the more specific emergency-vs-normal-path framing). E8/E11 priority rule mirrors the existing Sweep 8 priority rule. Handoff § 2 ranking inserted E11 between E8 and E2: `E8 EMERGENCY > E11 SEQUENCE > E2 INTERFACE > E5 EXTERNAL-DEP > ...`. By-family count line in canonical_seed_map.md summary extended with `E11 {n11}`.
  - **PATCH 5 (kill-the-hypothesis verifier mindset)**: `~/.valves/rules/phase5-poc-execution.md` gained a new mandatory § Hypothesis-killing pre-check section with four structured questions (Q1 guard/invariant, Q2 state-precondition reachability, Q3 unenforced call-order dependence, Q4 expected-order survival), each with a `kills_hypothesis: YES/NO` field. Q1/Q2-YES with full Cleared-Proof Discipline fields can justify [POC-FAIL: GENUINE] without running a PoC. Q3-YES + Q4-NO re-classifies the finding as `class: sequence-violation` and the PoC tests the unexpected-order variant. Independent of (and composes with) the existing Skeptic-Judge step (Phase 5.1, HIGH/CRIT only). Slash command Phase 5 verifier spawn gained a Step 5.0.4 directive that appends the pre-check requirement to every verifier prompt.
  - **PATCH 6 (final strongest-exploit quality refinement)**: Phase 6d.5 sanity check `Mismatch type` enum extended with `SEQUENCE_DISPLACEMENT` (when a call-order parent is displaced by a narrower child symptom). `Recommendation` enum extended with `CONSIDER_RESTORE_SEQUENCE_PARENT`. Surface comparison logic unchanged — the new enum values capture an existing-but-unmodeled displacement mode.
  - **PATCH 7 (compact doctrine file)**: NEW file `~/.valves/rules/valves-doctrine.md` (~125 lines). Compact source-of-truth for reasoning style: § Audit thinking principles (the user's 13 principles), § The 8 mandatory adversarial questions (the user's question pack), § The decision lenses (per-domain threat focus), § Kill-the-hypothesis mindset (verifier four questions), § The call-order principle (first-class lens). Referenced from CLAUDE.md (this file's § Pointers), Phase 4a.5.e Assumption-Breaker prompt, Phase 4b iter 1 depth-agent directive, Session B DA agent prompt, Phase 5 verifier directive (Step 5.0.4), and `phase5-poc-execution.md` § Hypothesis-killing pre-check. Read-once doctrine; not a checklist; not a phase; no outputs / gates / spawns.
  - All v1.7-PATCH7 changes are reasoning-quality patches: prompt language, schema columns, enum extensions, one new doctrine file. Zero new agents, zero new phases, zero new sweeps, zero new external sources. Existing HARD/SOFT gate semantics (Rule 15) unchanged. Existing strongest-exploit preservation, correctness-winner preservation, and cleared-proof discipline unchanged. Hard upper bound on handoff total still 36 (32 default + 3 slack + 1 dominant-family override).

- **v1.7-PATCH8 — heuristic-pressure hardening (elite-auditor lens integration)** — surgical reasoning-quality patches that integrate a small set of elite-auditor heuristics (symmetry, invalid state transitions, big-vs-small, numeric extremes, non-existent identifiers, test-suite skepticism, dead state) into the existing Session A / Session B architecture. NO new phases, NO new agents (one Validation Sweep sub-check extension), NO new big artifacts. Zero new rule files (extends existing `valves-doctrine.md`). Architecture contract preserved.
  - **PATCH 1 (heuristic doctrine upgrade)**: `~/.valves/rules/valves-doctrine.md` extended with § Heuristic Lenses (~70 lines): SYMMETRY / STATE-TRANSITION / SEQUENCE (cross-ref to existing) / BIG-VS-SMALL / NUMERIC-EXTREME / NONEXISTENT-ID / TEST-SKEPTIC / DEAD-STATE. Each lens carries a short tag (used in canonical_seed_map.md / handoff § 2 Heuristic Lens column) and a concrete sub-question set. Also added § Fuzz interpretation note (small section): absence of fuzz counterexample is NOT proof of safety; lifecycle invariants matter as much as steady-state; tests / fuzzers with stricter setup than production do not clear hypotheses.
  - **PATCH 2 (Heuristic Lens column)**: `canonical_seed_map.md` schema gained one OPTIONAL column `Heuristic Lens` (short tag, fixed 8-value enum + `-`). Derivation is mechanical from member raw sources (Sweep N → matching lens; AB Q-N → matching lens; AS-N → derived from analog pattern; VS-TS-1 → TEST-SKEPTIC). When members disagree → `-`. Off-enum values rejected at COMPLETE_A handoff build. The orchestrator does NOT invent lens tags. Propagated verbatim to `session_a_to_b_handoff.md` § 2.
  - **PATCH 3 (no new family)**: Inspection found that state-machine concerns route cleanly through existing E1/E8/E11 + the new Heuristic Lens tag. No E12 added — family system unchanged. STATE-TRANSITION lives as a doctrine lens / Heuristic Lens tag, not as a new equivalence class.
  - **PATCH 4 (Session B DA prompt — heuristic lens routing)**: The Session B DA agent prompt (Session B Behavioral Rules § 1) gained a paragraph mapping each Heuristic Lens tag to its corresponding methodology (SYMMETRY → 7 sibling-pair aspects; STATE-TRANSITION → state-machine completeness; SEQUENCE → 7 call-order patterns; BIG-VS-SMALL → split/aggregate equivalence; NUMERIC-EXTREME → boundary pressure; NONEXISTENT-ID → attacker-controlled identifier paths; TEST-SKEPTIC → strict-setup / loose-production divergence; DEAD-STATE → write-without-read suspicion). DA agent applies the lens BEFORE general re-attack when § 2 row carries a tag. No new spawns, no broader scope.
  - **PATCH 5 (verifier hypothesis-killing pre-check Q5 test-skepticism)**: `~/.valves/rules/phase5-poc-execution.md` § Hypothesis-killing pre-check extended Q1-Q4 → Q1-Q5. Q5 asks: (a) does the test suite exercise this finding's failing path? (b) does test setUp() encode a stricter sequence than production? (c) do assertions validate post-state or only events / returns? Output `tests_imply_safety: YES / NO / PARTIAL / NO_TESTS`. Q5 is asymmetric — never KILLS a hypothesis; only contextualizes "tests pass" as evidence weight. When `tests_imply_safety: NO` (strict-setup / loose-production divergence) and Q1/Q2 don't kill, the verifier MUST NOT cite "tests pass" as evidence of safety. Slash command Step 5.0.4 verifier directive extended to mandate Q5 emission.
  - **PATCH 6 (Validation Sweep [VS-TS-1] test-skepticism sub-check)**: Phase 4b iter 1 Validation Sweep agent gained a third sub-check (test-skepticism) alongside admin-setter-validation (`[VS-AS-1]`) and variable-flow-attribution-audit (`[VS-AT-1]`). Methodology lives in `valves-doctrine.md` § Heuristic Lenses → TEST-SKEPTIC (4 mechanical sub-checks: state-transition coverage gaps, assertion-shape weakness, strict-setup / loose-production divergence, production-only paths). Output `[VS-TS-1]` consolidated multi-location table tagged `[CORRECTNESS-WINNER]`. Skips gracefully when no test directory is in scope (logs `VS_TS_SKIPPED_NO_TEST_DIR` to degradation_log.md). NO new rule file — methodology is in the doctrine.
  - **PATCH 7 (Phase 6d.5 mismatch type expansion)**: `Mismatch type` enum extended with `STATE_TRANSITION_DISPLACEMENT` (state-machine root cause displaced by narrower manifestation) and `ASYMMETRY_DISPLACEMENT` (asymmetry-rooted parent displaced by downstream symptom). `Recommendation` enum extended with `CONSIDER_RESTORE_STATE_TRANSITION_PARENT` and `CONSIDER_RESTORE_ASYMMETRY_PARENT`. Surface comparison logic unchanged — the new enum values capture existing-but-unmodeled displacement modes that complement SEQUENCE_DISPLACEMENT (PATCH7).
  - **PATCH 8 (fuzz interpretation alignment)**: Done in PATCH 1 above (one paragraph in `valves-doctrine.md` § Fuzz interpretation note). NO new fuzzing framework, NO new mechanics — just a doctrine reasoning note that "absence of counterexample ≠ proof of safety" and "lifecycle invariants matter as much as steady-state".
  - All v1.7-PATCH8 changes are reasoning-quality patches: doctrine extension, schema column extensions, enum extensions, prompt language. Zero new agents, zero new phases, zero new sweeps, zero new external sources, zero new rule files. Existing HARD/SOFT gate semantics (Rule 15) unchanged. Existing strongest-exploit preservation, correctness-winner preservation, and cleared-proof discipline unchanged. The Validation Sweep `[VS-TS-1]` sub-check extends an existing agent — does not add a new one. Hard upper bound on handoff total still 36 (32 default + 3 slack + 1 dominant-family override).

- **v1.7-PATCH9 — pre-benchmark stabilization** — surgical execution-quality patches before benchmarking. NO new phases, NO new agents, NO new artifacts, NO new families, NO new big mechanics. Five focused fixes: drift cleanup, VS-TS-1 tightening, operational-not-decorative compliance scans, lens precedence rule, displacement-type precedence rule.
  - **PATCH 1 (drift cleanup)**: Fixed three concrete drift items in `commands/valves.md`: (a) line 760 said "rows 01-50" — corrected to "rows 01-73 as of v1.7-PATCH5"; (b) canonical_seed_map.md description said "(E1-> E10)" — corrected to "(E1-E11; E11 SEQUENCE added v1.7-PATCH7)"; (c) the in-slash-command canonical_seed_map.md schema was missing the PATCH7+PATCH8 columns (Open Question / Disputed Assumption / Heuristic Lens) — schema now matches `~/.valves/rules/canonical-seed-map.md` § Schema; (d) Session B Behavioral Rules § 1 said "32-row total cap" (misleading) — corrected to "32-row default cap; up to 36 with slack + override". Producer derivation note added to canonical_seed_map.md slash-command description (orchestrator inline derives PATCH7+PATCH8 columns per the rule file's derivation rules; off-enum lens values rejected with `LENS_OFF_ENUM_REJECTED` log).
  - **PATCH 2 (VS-TS-1 scope tightening)**: Validation Sweep `[VS-TS-1]` sub-check tightened for benchmark fairness. Added priority filter: PRESSURE ONLY paths in custody / accounting / lifecycle / privileged-mutation / recovery surfaces (cross-reference with `strongest_exploit_cards.md` E1-E7 and `system_breakpoints.md` BP-NN). Explicit exclusions: do NOT report generic "this admin function lacks a test"; do NOT report missing tests for view functions / internal helpers / library wrappers; do NOT report assertion-shape weakness on out-of-scope paths. Added hard cap: max 6 `[VS-TS-1]` findings (overflow recorded in validation_sweep.md § VS-TS Overflow). Added quality gate: every finding MUST cite production path file:line + test file (or `no test`) + which sub-check fired (1/2/3/4) + surface category. Findings missing required fields are dropped at agent self-check; orchestrator-inline post-spawn audit logs `VS_TS_FIELD_GAP_DROPPED`. Added second graceful-skip case: `VS_TS_SKIPPED_NO_PRIORITY_SURFACE` when priority filter yields zero candidates (small-scope audits).
  - **PATCH 3 (operational compliance scans — make heuristic fields operational, not decorative)**: Two new orchestrator-inline mechanical scans, NO new agent, NO new artifact (uses existing `violations.md` and `seed_metrics.md`). (a) Post-Session-B compliance scan (Step 7 of Session B Behavioral Rules): for each `analysis_depth_da_*.md`, verify per-row blocks for handoff § 2 rows that carried Open Question / Disputed Assumption / Heuristic Lens (any populated field). Required block: `### CS-{N}` heading + `lens:` + `oq_addressed:` + `da_tested:` + `finding_or_clear:`. Missing block → log `HEURISTIC_FIELD_NOT_OPERATIONAL`. (b) Post-Phase-5 verifier compliance scan (Step 5.5.1): for each `verify_*.md`, check `## § Hypothesis-killing pre-check` heading + Q1-Q4 `kills_hypothesis:` lines + Q5 `tests_imply_safety:` line. Missing structure → log `VERIFIER_PRECHECK_MISSING`. Both scans are mechanical (grep-based), do NOT block, do NOT re-spawn — they are observability so the violation count surfaces in `seed_metrics.md` § Operational compliance and future audits can correlate non-compliance with recall regression. Session B DA prompt extended with mandatory output structure (per-row block) so the agent knows what the post-hoc scan checks.
  - **PATCH 4 (Heuristic Lens precedence rule)**: Added § Heuristic Lens precedence to `~/.valves/rules/canonical-seed-map.md`. Mechanical, deterministic precedence ordering: STATE-TRANSITION > SEQUENCE > SYMMETRY > BIG-VS-SMALL > NUMERIC-EXTREME > NONEXISTENT-ID > DEAD-STATE. TEST-SKEPTIC orthogonal — only when source is `[VS-TS-1]`. Includes a common-collision table (8 collision examples → resolved lens) so two orchestrator runs on identical evidence yield the same lens tag. Conservative bias: when tied at the same precedence level, prefer the lens whose evidence comes from the highest-priority source per Source Provenance; when still tied → leave `-`.
  - **PATCH 5 (Phase 6d.5 displacement-type precedence)**: Added precedence rule to slash command Phase 6d.5 mismatch-type field definitions. Same pattern as PATCH 4: STATE_TRANSITION_DISPLACEMENT > SEQUENCE_DISPLACEMENT > ASYMMETRY_DISPLACEMENT for structural displacement; mechanical types (SEVERITY_DOWNGRADE / SUBGROUP_COLLAPSE / INHERITANCE_SHADOWING / THESIS_DISPLACEMENT / REPORT_ID_CONSOLIDATION) only when no structural framing exists for the displaced parent. The `Recommendation` enum follows the same precedence (mismatch type uniquely determines recommendation).
  - All v1.7-PATCH9 changes are pre-benchmark stabilization: drift cleanup, scope tightening, operational compliance, precedence rules. Zero new agents, zero new phases, zero new artifacts (compliance scans use existing `violations.md` + `seed_metrics.md`), zero new sweeps, zero new external sources. Existing HARD/SOFT gate semantics (Rule 15) unchanged. Existing strongest-exploit preservation, correctness-winner preservation, and cleared-proof discipline unchanged. Hard upper bound on handoff total still 36. The `[VS-TS-1]` hard cap of 6 is consistent with admin-setter-validation `[VS-AS-1]` cap and attribution-audit `[VS-AT-1]` cap. Two orchestrator runs on identical inputs now yield deterministic lens tags + deterministic Phase 6d.5 mismatch types.

- **v1.7-PATCH10 — full mechanical enforcement / pre-benchmark integrity** — The most critical patch. Pre-PATCH10, the architecture was DESCRIBED (in rule files) but NOT MECHANICALLY ENFORCED (in the orchestrator's slash command). The Snuggle audit revealed: HP agent went off-script and used Bash `claude --print` to spawn 7 sub-agents impersonating the orchestrator; 50+ checklist rows remained PENDING while downstream report artifacts were synthesized by the orchestrator directly; the embargo never fired despite 50+ non-terminal rows; the COMPLETE_A → Session B boundary blurred because both ran in the same conversation. PATCH10 makes the architecture mechanical.
  - **NEW FILE**: `~/.valves/rules/artifact-ownership.md` (~150 lines, compact control table). Authoritative artifact-owner / allowed-writer / class (ORCHESTRATOR-INLINE / AGENT-OWNED / EITHER) / producing phase / hard-soft / prerequisites map for all ~70 Valves artifacts. Consumed by all four PATCH10 enforcement gates.
  - **PATCH 1+2 (Agent ownership + tool discipline)**: `~/.valves/rules/valves-doctrine.md` extended with § Agent tool discipline (~30 lines): forbidden Bash patterns (any `claude --print`, `claude -p`, `npx claude`, `bunx claude`, `yarn claude`, `exec claude`, `spawn claude`, `sh -c "claude...`, pipe TO claude). Hard prohibition on writing artifacts other than the agent's owned artifact(s). Rationale: quality of off-script output is irrelevant — process discipline is what makes the contract enforceable.
  - **PATCH 3 (Universal post-spawn integrity check)**: NEW `## Phase 0.9: Mechanical Architecture Enforcement` section in `~/.valves/commands/valves.md`. After every Task() returns, BEFORE accepting output, the orchestrator: (a) greps tool trace for forbidden Bash patterns; (b) checks Write/Edit targets against the ownership manifest; (c) if violation: AUTO-DISCARD outputs + log to violations.md + mark TAINTED in degradation_log.md + re-spawn ONCE with stricter prompt; (d) if second violation: halt the run with SCOPE_VIOLATION_PERSISTENT. NO user-prompt for accept-with-flag — the Snuggle "accept-with-flag" path is removed.
  - **PATCH 4 (Compact ownership manifest)**: see NEW FILE above.
  - **PATCH 5 (Protected-artifact pre-write gate)**: also in Phase 0.9 § B. Before any orchestrator-inline write: verify class allows orchestrator write, verify prerequisites in terminal state, verify orchestrator is in correct phase. If any check fails: REFUSE write + log + Recovery Loop. This catches Snuggle's failure mode where the orchestrator self-synthesized AGENT-OWNED artifacts (`report_*.md`, `cluster_instance_map.md`, `chain_hypotheses.md`, `attack_thesis_v3.md`) directly.
  - **PATCH 6 (Refined anti-self-synthesis rule)**: Rule 29 in this file. Forbids orchestrator self-synthesis of AGENT-OWNED artifacts; preserves legitimate ORCHESTRATOR-INLINE artifacts per the manifest. Scope is intentionally narrow.
  - **PATCH 7 (Mechanical row synchronization + drift detection)**: Phase 0.9 § C + § D. Rows update IMMEDIATELY after every Task() returns or every orchestrator-inline step completes — not in batches. Drift detection runs at every phase boundary: catches synthetic completion (COMPLETE row, missing artifact), illegal writer (COMPLETE row, illegal writer per manifest), fallback missing, weak NA reason, AND `DRIFT_DETECTED_PENDING_WITH_COMPLETE_CONSUMER` (the exact Snuggle failure pattern: row PENDING but downstream consumer COMPLETE).
  - **PATCH 8 (True COMPLETE_A boundary enforcement)**: Insertion in `~/.valves/commands/valves.md` § COMPLETE_A boundary enforcement (Thorough only). After the COMPLETE_A handoff bundle is written: integrity verification on all 6 handoff sub-step artifacts; row drift scan on rows 01-22; emit "SESSION A COMPLETE — STOP HERE" banner with explicit instruction to start a new conversation; **HARD HALT** — orchestrator MUST NOT spawn any Phase ≥ 4b iter 2 step in this conversation; anti-bypass refusal if user replies "continue" / "proceed".
  - **PATCH 9+10 (Hard fail-closed embargo + Pre-Report Gate)**: NEW Phase 5.99 PRE-REPORT GATE in `~/.valves/commands/valves.md` (mechanical scan before Phase 6a) + hardened Phase 6f embargo in `~/.valves/rules/thorough-strict-mode.md` § Final Report Embargo. Pre-Report Gate scans rows 01-46 + cross-checks mode-policy verification scope + cross-checks session boundary integrity. Phase 6f embargo additionally cross-checks `violations.md` for unresolved enforcement violations + verifies session_checkpoint.md status==COMPLETE_B + verifies cross_session_consensus.md presence.
  - **PATCH 11+13 (Three completion states)**: `~/.valves/rules/thorough-strict-mode.md` § Completion states (v1.7-PATCH10 — explicit labeling). Three states: VALID THOROUGH DELIVERABLE (all clear), INCOMPLETE THOROUGH (degraded — partial output, banner explicitly states "NOT a valid Thorough deliverable", NOTICE prepended to AUDIT_REPORT.md), INVALID FINALIZATION (HIGH-severity violation unresolved — AUDIT_REPORT.md renamed to `AUDIT_REPORT.INVALID.md` to prevent mistaking it for a deliverable).
  - **PATCH 12 (Observability)**: All enforcement violations log to existing `violations.md` with explicit codes: `ILLEGAL_WRITER_*`, `SCOPE_VIOLATION_PERSISTENT`, `INVALID_FINALIZATION_*`, `COMPLETE_A_BOUNDARY_INTEGRITY_FAILURE`, `PROTECTED_ARTIFACT_PRE_WRITE_GATE_BLOCKED`, `DRIFT_DETECTED_PENDING_WITH_COMPLETE_CONSUMER`, `PRE_REPORT_GATE_BLOCKED`, `SYNTHETIC_COMPLETION`, `WEAK_NA_REASON`, `FALLBACK_MISSING`, `UNREGISTERED_ARTIFACT_WRITTEN`. Tainted outputs marked in `degradation_log.md`. Run-state classification (VALID/INCOMPLETE/INVALID) recorded in `compliance_summary.md`. NO new observability framework — uses existing artifacts.
  - **HP-specific hardening**: Phase 1.2 HP agent prompt extended with hard-scope prohibitions block (~40 lines) appended verbatim to the HP spawn prompt. HP agent can only write `historical_prime_seeds.md`; explicit prohibition on `claude --print` / orchestrator-artifact writes / spawning breadth agents / acting as orchestrator. Special HP-specific post-spawn check: filesystem-state diff to detect ANY file written by HP other than `historical_prime_seeds.md` → ILLEGAL_WRITER_HP_OUT_OF_SCOPE → AUTO-DISCARD + re-spawn.
  - All v1.7-PATCH10 changes are mechanical enforcement: ownership manifest + post-spawn check + pre-write gate + row sync + drift detection + COMPLETE_A halt + Pre-Report Gate + hardened embargo + 3 completion states. Zero new agents. Zero new phases (Phase 0.9 is enforcement infrastructure, not a new pipeline phase). One new rule file (the ownership manifest). Existing strongest-exploit preservation, correctness-winner preservation, cleared-proof discipline, heuristic lens precedence, and Phase 6d.5 sanity check unchanged. Hard upper bound on handoff total still 36.
  - **What PATCH10 honestly cannot do** (limits):
    1. Cannot literally PREVENT an agent from running `claude --print` — that's a Bash tool capability the agent has. PATCH10 implements the strongest available approximation: post-hoc detection (grep tool trace) + AUTO-DISCARD + 1 re-spawn + halt on second violation. The agent can do the bad thing once, but its output is invalidated and its second attempt halts the run.
    2. Cannot literally PREVENT the orchestrator from writing AGENT-OWNED artifacts — the orchestrator has the Write tool. PATCH10's pre-write gate catches this inline by checking the artifact-ownership manifest before every write. The orchestrator must follow the gate logic; if it bypasses the gate, the row drift detection at the next phase boundary catches the synthetic completion.
    3. Cannot literally PREVENT the user from saying "continue" in the same conversation after COMPLETE_A. PATCH10's anti-bypass clause says the orchestrator MUST refuse, but the orchestrator must follow that instruction. If a future Claude version drifts on this, the gate is the orchestrator's prompt discipline.
    4. Cannot literally PREVENT the watchdog hook (`phase_gate.py`) from being uninstalled. PATCH10 makes the orchestrator-inline checks belt-and-suspenders to the watchdog so failure of one doesn't bypass enforcement.
    5. The orchestrator IS Claude. Claude follows instructions. PATCH10's principle: make the instructions MECHANICAL and NON-NEGOTIABLE, with explicit failure modes (AUTO-DISCARD, halt, INVALID FINALIZATION) so the orchestrator's discretion to "be helpful and continue" is removed. We cannot eliminate Claude's discretion, but we can make the structured response to violations the obvious right action at every check point.

**Why asymmetric**: HARD gates cover artifacts whose absence breaks downstream phases (clustering, verification, report). SOFT gates cover diagnostic / investigation aids — depth agents fall back to `state_variables.md` + classification hints when these are missing.

**Recovery**: HARD gate miss → re-spawn the producing agent ONCE; if it fails again, abort the pipeline (fail-closed in Thorough; degrade-and-log in Light/Core). SOFT gate miss → log + proceed; do NOT re-spawn.

---

## Rule 18 — Filtered Injection (Prompt-Length Discipline)

When the orchestrator composes an agent prompt that needs context from Valves artifacts (e.g., `system_breakpoints.md`, `attack_thesis.md`, `root_cause_clusters.md`, `propagation_structural.md`), it MUST inject FILTERED EXCERPTS only — never the full file.

**Limits per artifact, per agent prompt**:
- Max 40 lines or ~800 tokens, whichever comes first.
- Filter to entries relevant to this agent's domain / assigned BC class / assigned breakpoint.
- When no filtered view is possible, inject a **summary table** (ID + 1-line description) instead of the body.

**Why**: agents reliably execute up to ~300 lines of skill payload + small filtered context. Past that, attention degrades and methodology gets dropped. See `~/.valves/rules/prompt-injection-guard.md` for the WARN/COMPACT/HARD_LIMIT thresholds and the canonical summary-table formats.

---

## Rule 19 — Strongest Exploit Gate (Pre-Clustering)

Before the Cluster Agent runs (or before any synthesis that compresses N findings into M groups), the orchestrator MUST spawn the Strongest Exploit Gate Agent and produce `{scratchpad}/strongest_exploit_cards.md`. This commits the strongest exploit per high-signal surface to disk *before* compression, so downstream synthesis cannot silently replace a strong parent exploit (custody loss, recovery-path severance, asset orphaning, irreversible user lock) with a weaker adjacent finding (stale approval, CEI impurity, operational note, config awkwardness).

**Hard gate**: `strongest_exploit_cards.md` MUST exist before Phase 4a.2-lite (Classification) AND before Phase 4b step 8b (Full Clustering). If missing → re-spawn the Gate Agent.

**Model**: opus in Thorough (subtle judgment); sonnet in Core/Light (cost guardrail still on for custody-loss).

See `~/.valves/rules/strongest-exploit-preservation.md` for Card Eligibility Gate (E1–E7), Anti-Overcompression Rule, card cap (≤15 soft / ≤25 hard), `card_score` formula.

---

## Rule 29 — Mechanical Architecture Enforcement (v1.7-PATCH10)

The skill's quality contract (Strongest Exploit Preservation, Cleared-Proof Discipline, Cross-Session Consensus, fail-closed embargo, Pre-Report Gate) depends on agents staying within their assigned scope and the orchestrator NOT synthesizing agent-owned artifacts. Pre-PATCH10, these contracts were documented in rule files but not mechanically enforced — agents could go off-script, the orchestrator could self-synthesize, and the embargo could be bypassed.

PATCH10 makes the contract mechanical. The enforcement gates fire in Phase 0.9 of the slash command (`~/.valves/commands/valves.md` § Phase 0.9: Mechanical Architecture Enforcement). They consume the artifact-ownership control table at `~/.valves/rules/artifact-ownership.md` § Control table.

**Four enforcement gates** (all orchestrator-inline, no new agents, no new big artifacts):

### A. Universal post-spawn integrity check
After every `Task()` returns, BEFORE accepting output:
1. Grep agent's tool trace for forbidden Bash patterns (`claude --print`, `claude -p`, sub-orchestration via Bash).
2. Check Write/Edit targets against the ownership manifest: ORCHESTRATOR-INLINE artifacts written by an agent → `ILLEGAL_WRITER_ORCHESTRATOR_ARTIFACT_BY_AGENT` violation. AGENT-OWNED artifacts written by the wrong agent → `ILLEGAL_WRITER_WRONG_AGENT` violation.
3. Decision: First violation → AUTO-DISCARD outputs + log to violations.md + re-spawn ONCE with stricter prompt. Second violation → halt the run with `SCOPE_VIOLATION_PERSISTENT`. NO user-prompt for accept-with-flag override.

### B. Protected-artifact pre-write gate
Before any orchestrator-inline write:
1. Look up artifact in ownership manifest.
2. Verify class allows orchestrator write (ORCHESTRATOR-INLINE or EITHER with fallback path).
3. Verify all prerequisites are in terminal state.
4. Verify orchestrator is in correct phase.
5. If any check fails → REFUSE the write + `PROTECTED_ARTIFACT_PRE_WRITE_GATE_BLOCKED` violation + Recovery Loop.

This catches the failure mode observed in the Snuggle audit: orchestrator self-synthesized `report_*.md`, `cluster_instance_map.md`, `chain_hypotheses.md`, `attack_thesis_v3.md` directly without spawning the named producer agents. Those artifacts are AGENT-OWNED → orchestrator self-write is now mechanically refused.

### C. Row synchronization discipline
After every successful Task() returns + after every orchestrator-inline step:
- Update `mandatory_step_checklist.md` row IMMEDIATELY (not in batches).
- Status assignment is mechanical: COMPLETE if expected artifact present + integrity check passed; FAILED_WITH_FALLBACK if fallback path hit; NOT_APPLICABLE only with non-trivial reason.
- Row drift detection runs at every phase boundary: scans for COMPLETE rows with missing artifacts (synthetic completion), COMPLETE rows with illegal writers, FAILED_WITH_FALLBACK rows with missing fallback, NOT_APPLICABLE rows with weak reasons, AND `DRIFT_DETECTED_PENDING_WITH_COMPLETE_CONSUMER` (a row PENDING but a downstream consumer COMPLETE — the exact pattern of the Snuggle failure).

### D. COMPLETE_A boundary enforcement (Thorough only)
After Session A's COMPLETE_A handoff bundle is written:
1. Run integrity verification on all 6 handoff sub-step artifacts.
2. Run row drift detection on rows 01-22.
3. Emit terminal banner: "SESSION A COMPLETE — STOP HERE" with explicit instruction to start a new conversation for Session B.
4. HARD HALT — orchestrator MUST NOT spawn Phase 4b iter 2 DA agents, run RAG sweep, run chain analysis, spawn verifiers, generate report artifacts, OR proceed to ANY phase ≥ Phase 4b iter 2 in this conversation.
5. Anti-bypass: if user replies "continue" / "proceed" / "run session B", orchestrator MUST refuse + re-emit banner.

### E. Pre-Report Gate (Phase 5.99, Thorough only)
Before Phase 6a (Report Generation):
1. Mechanical scan of mandatory_step_checklist.md rows up to row 46.
2. Cross-check with mode-policy verification scope (Thorough verifies ALL severities; missing verify_*.md files block).
3. Cross-check session boundary integrity (COMPLETE_A and COMPLETE_B both reached, cross_session_consensus.md present).
4. If any blocking item → emit PRE_REPORT_GATE_BLOCKED banner + REFUSE Phase 6a spawn + Recovery Loop.

### F. Final embargo (Phase 6f, Thorough only) — three completion states
- **VALID THOROUGH DELIVERABLE**: all conditions clear → AUDIT_REPORT.md is the deliverable.
- **INCOMPLETE THOROUGH (degraded)**: some conditions failed but partial output exists → NOTICE prepended to AUDIT_REPORT.md, `Outcome: INCOMPLETE` in compliance_summary.md, banner explicitly states this run is NOT a valid Thorough deliverable.
- **INVALID FINALIZATION**: HIGH-severity enforcement violation unresolved → AUDIT_REPORT.md renamed to `AUDIT_REPORT.INVALID.md` so it cannot be mistaken for a deliverable, banner halts the pipeline.

**Rule 29 supersedes ambiguity in earlier rules**. Where a rule says "the orchestrator should..." or "the agent must NOT...", PATCH10 makes those statements MECHANICAL. Where Claude Code cannot literally prevent a behavior (e.g., true tool-call sandboxing for sub-spawned agents), PATCH10 implements the strongest available approximation: post-hoc detection + AUTO-DISCARD + re-spawn + halt-on-second-violation.

**What Rule 29 does NOT do**:
- Does NOT add new doctrines, heuristics, sweeps, or analytical layers.
- Does NOT weaken Strongest Exploit Preservation, Correctness-Winner Preservation, Cleared-Proof Discipline, or Final Strongest-Exploit Sanity Check.
- Does NOT prohibit legitimate orchestrator-inline artifacts (per `~/.valves/rules/artifact-ownership.md` § Control table where class=ORCHESTRATOR-INLINE).
- Does NOT change the architecture — it makes the existing architecture mechanically enforceable.

---

## Rule 28 — Watchdog Enforcement (Thorough mode)

In Thorough mode, the orchestrator initializes a Stop-hook watchdog at the start of Phase 1:

```bash
"$PY_CMD" ~/.claude/hooks/phase_gate.py --init "{scratchpad}" thorough "{PROJECT_PATH}"
```

The watchdog reads `{scratchpad}/mandatory_step_checklist.md` and, on every Stop event, verifies that:
1. Every row required for the current phase has reached a terminal state (`COMPLETE`, `FAILED_WITH_FALLBACK`, or `NOT_APPLICABLE`).
2. Every `COMPLETE` row has its named evidence artifact on disk.
3. Every `FAILED_WITH_FALLBACK` row has its named fallback artifact on disk.
4. Every `NOT_APPLICABLE` row has a non-trivial reason (not `""`, `"skipped"`, `"n/a"`).

If any check fails, the watchdog blocks the orchestrator's Stop and emits a directive to spawn the responsible agent (or enter the Recovery Loop in `~/.valves/rules/thorough-strict-mode.md`).

**Belt-and-suspenders**: the orchestrator ALSO performs the Phase 4b Post-Depth static manifest check inline. Both layers must pass.

**Failure modes**:
- Thorough + watchdog hook missing → ABORT before recon (the v1.5 fail-closed guarantee depends on it).
- Core/Light + hook missing → non-fatal; pipeline continues without enforcement.

---

## Rule 35 — Disk-Truth Supremacy (v1.7-PATCH11.3)

Disk state overrides in-memory beliefs, prior recap text, and conversational momentum — always, unconditionally, at every decision point.

**The three authoritative files**: `run_state.json`, `mandatory_step_checklist.md`, `session_checkpoint.md`. When any of these disagree with what the orchestrator "remembers" from earlier turns, compaction summaries, or conversational context, the file on disk wins. The orchestrator re-derives its position from disk, not from summarized prior context.

**Enforcement points**:
1. **Step 0-pre (resume)**: Read disk state FIRST. Route based on `checkpoint_level` and `session` fields. Do NOT trust "I was doing X" from compacted context.
2. **Phase 0.9 § F (reconciliation)**: Three-way reconciliation reads all three files. Disk values override in-memory variables.
3. **Every phase boundary**: Before advancing, re-read `run_state.json`. If `checkpoint_level` or `session` changed (e.g., another conversation wrote COMPLETE_A), halt immediately.
4. **After compaction**: The first action after any context compaction event is to read `run_state.json` and `mandatory_step_checklist.md`. All subsequent decisions derive from disk.

**What this means in practice**: If the orchestrator's in-memory state says "I'm in phase4b_iter1" but `run_state.json` says `current_phase: "complete_a"` and `checkpoint_level: "COMPLETE_A"`, the orchestrator halts — it does not continue phase4b. If the checklist says row 15 is PENDING but the orchestrator "remembers" completing it, row 15 is PENDING. If a compaction summary says "all breadth agents returned successfully" but `analysis_breadth_3.md` is missing from disk, the agent did NOT succeed.

**Anti-pattern**: "I know I already did this because I remember doing it earlier in this conversation" is NEVER a valid justification for skipping a disk check. Memory is fallible after compaction; disk is not.

---

## Rule 36 — Artifact Identity & Stale Detection (v1.7-PATCH11.3-CANTINA)

Every scratchpad artifact written by any agent MUST carry a producer header as its first line:

```
<!-- VALVES-ARTIFACT run_id:{RUN_ID} producer:{AGENT_ID} phase:{PHASE} session:{A|B} -->
```

**RUN_ID** is a unique identifier generated at audit start (Step 0.85c): `VALVES-{YYYYMMDD}-{HHMMSS}-{4hex}`. It is stored in `run_state.json` and injected into every agent prompt by the orchestrator. On resume, the existing RUN_ID is preserved (same run continues). On `fresh-run`, a new RUN_ID is generated.

**Stale detection**: `VALIDATE_STEP_COMPLETION()` (execution-state.md § R4.1) greps the first line of each artifact for `run_id:`. If the run_id mismatches the current `run_state.json` value → `ARTIFACT_STALE_RUNID` → artifact renamed to `{filename}.stale.{old_run_id}`, row downgraded to PENDING. This catches ghost artifacts from crashed/abandoned prior runs that would otherwise be mistaken for current output.

**Orchestrator responsibility**: Before composing any agent prompt, read `run_id` and `session` from `run_state.json`. Replace `{RUN_ID}` and `{SESSION}` in the artifact stamp directive. See Step 2c.2 in `valves.md`.

**Fail-closed for agent-owned artifacts**: The ~40 artifacts on the `CRITICAL_AGENT_OWNED` list (Phase 0.9 § B) REQUIRE the header — missing header = `ARTIFACT_HEADER_MISSING` = row downgraded to PENDING + re-spawn. Orchestrator-written files (run_state.json, session_checkpoint.md, pipeline_trace.md) do NOT require the header and fall back to mtime-based stale check.

---

## Rule 34 — Pattern Library Integration (v1.7-PATTERN + v1.7-CANTINA)

The pattern library at `~/.valves/patterns/` contains two layers:
- **Solodit corpus** (562 patterns, 19 clusters): extracted from 50,062 real audit findings. Files at `~/.valves/patterns/{slug}.md`.
- **Cantina corpus** (80 patterns, 13 clusters + 1 new): extracted from 279 confirmed HIGH/MEDIUM findings across 16 Cantina competitions. Files at `~/.valves/patterns/cantina/cantina-{slug}.md`. Index at `~/.valves/patterns/cantina/CANTINA_PATTERN_INDEX.md`.

The two layers are kept separate (not merged) so they can be A/B tested independently.

**Pattern cluster selection (Phase 2e, orchestrator inline)**:
After recon completes and before breadth agents spawn, the orchestrator selects relevant pattern clusters from BOTH layers using `~/.valves/patterns/PATTERN_INDEX.md` (Solodit) and `~/.valves/patterns/cantina/CANTINA_PATTERN_INDEX.md` (Cantina). Protocol type is derived from `design_context.md` + `template_recommendations.md` flags. The orchestrator writes `{SCRATCHPAD}/relevant_patterns.md` with compact detection checklists (pattern name + code shape + 1-line failure mode, ~40 lines per cluster). Cantina patterns are listed in a separate `## Cantina Detection Checklists` section.

**New recon trigger — REWARD_EMISSION**: When recon detects `rewardRate`, `rewardPerToken`, `earned`, `stake`/`unstake`, `slash`, `boost`, `epoch`, `accrue`, `distribute` in scope contracts, set `REWARD_EMISSION` flag. This triggers the new `reward-accounting` Cantina cluster (CANTINA-REWARD-001..007). No corresponding Solodit cluster exists.

**Breadth agent injection (Rule 18 compliant)**:
Each breadth agent's prompt receives a compact Solodit detection checklist under `## Pattern Detection Checklist` (unchanged). Additionally, a compact Cantina checklist is appended under `## Cantina Pattern Shortlist` — same format (ID | code shape | failure mode), max 20 lines per cluster, max 2 Cantina clusters per agent. Cantina patterns are framed as "additional coverage from competition findings" — they supplement, not replace, the Solodit checklist.

**Depth agent reference (iter 1 — post-methodology cross-check)**:
Depth agent prompts include a directive to `Read ~/.valves/patterns/{slug}.md` for their relevant Solodit cluster(s) during investigation (unchanged). Additionally, a post-methodology Cantina cross-check directive is appended: `"After completing your primary methodology AND Solodit pattern cross-check, read the Cantina pattern files listed below. For each CANTINA pattern whose Code Shape matches code in scope but was not covered by your primary analysis or Solodit cross-check, investigate and either produce a finding or note CLEARED(cantina-pattern) with reason. These patterns are derived from real competition findings — they represent failure modes that escaped initial auditor attention in live contests. Cantina files: {list from Cantina Depth Agent Pattern Map}."` This is a second-pass coverage amplifier, not methodology.

**DA iteration 2-3 (strongest integration point — adversarial alternative vectors)**:
DA agents in Session B receive the full relevant Cantina cluster file(s) for their domain, with this directive: `"Read the Cantina pattern files below. These describe concrete attack patterns from real DeFi competition findings. For each pattern whose Code Shape matches code in your assigned scope: (1) check whether Session A's iteration 1 explored this failure mode, (2) if NOT explored — investigate it as an alternative attack vector. Use Cantina patterns as a source of 'what else could go wrong here?' — they are adversarial hypotheses, not confirmations. Cantina files: {list from Cantina Depth Agent Pattern Map}."` This is the highest-value integration point: Cantina patterns give DA agents concrete alternative failure modes to pressure-test, directly supporting contrastive conditioning (AD-2).

**Chain analysis (light injection — failure mode extracts)**:
Chain Agent 2 receives a compact `## Cantina Failure Mode Extracts` section (max 30 lines) listing only Failure Mode fields from relevant Cantina patterns. These suggest postcondition→precondition matches the chain agent might otherwise miss. No full pattern files injected into chain agents.

**Depth domain → Cantina cluster mapping**:
- `token-flow`: cantina-vault-share-accounting, cantina-arithmetic-precision, cantina-reward-accounting (if REWARD_EMISSION)
- `state-trace`: cantina-access-control, cantina-reentrancy
- `edge-case`: cantina-logic-errors, cantina-denial-of-service, cantina-arithmetic-precision
- `external`: cantina-oracle-dependency, cantina-bridge-cross-chain, cantina-frontrunning-mev
- Protocol-specific: cantina-lending-liquidation, cantina-dex-amm-logic, cantina-signature-auth inject into whichever depth domain covers the protocol's primary surface.

**Anti-anchoring rule**: Cantina patterns are a COVERAGE AMPLIFIER, not methodology. The ordering is always: (1) primary skill methodology, (2) Solodit pattern cross-check, (3) Cantina pattern cross-check. Agents MUST NOT lead with pattern matching. If an agent's findings are dominated by pattern matches with no first-principles analysis, the orchestrator flags this in `degradation_log.md` as `PATTERN_ANCHORING_DETECTED`.

**Pattern files are READ-ONLY reference material, not methodology**. They tell agents WHAT code shapes to look for and WHAT failure modes exist — they do NOT replace skill templates, scanner checks, or depth heuristics. Methodology first, patterns second.

---

## Inherited from Plamen (not redefined here)

- **R1–R10**: generic security rules (severity matrix, side-effect tracing, etc.) — see `~/.claude/prompts/{LANGUAGE}/generic-security-rules.md`.
- **R10 (Worst-State Severity)**: severity is judged at the worst observable state, not the average.
- **R12 (REFUTED → Chain Required)**: a REFUTED verdict requires Phase 4c chain analysis to enumerate enablers before the finding is dropped.
- **R13 (Anti-Normalization)**: do not flatten distinct vulnerability classes into a generic label.
- **R16**: finding output format — see `~/.valves/rules/finding-output-format.md` (local copy; canonical source).
- **R17 (Severity Floor)**: applied by Strongest Exploit Gate and Validation Sweep — see `~/.valves/rules/strongest-exploit-preservation.md` for the floor table.

---

## Pointers (do not edit)

- Slash command: `~/.valves/commands/valves.md`
- Phase 1 rule files: `~/.valves/rules/`
- **Reasoning-quality doctrine** (v1.7-PATCH7): `~/.valves/rules/valves-doctrine.md` — compact source-of-truth for the reasoning style every Valves agent should follow. Read once. Not a phase, not a checklist; pure reasoning bias.
- **Architecture enforcement contract** (v1.7-PATCH10): `~/.valves/rules/artifact-ownership.md` — compact control table mapping every artifact to its allowed writer(s). Consumed by all four PATCH10 enforcement gates (post-spawn integrity check, protected-artifact pre-write gate, row drift detection, Pre-Report Gate, final embargo).
- **Crash-safe execution state** (v1.7-PATCH11): `~/.valves/rules/execution-state.md` — defines `run_state.json` schema (JSON format), phase manifest schema, validity checks, resume algorithm, session-aware contamination check, PARTIAL_B semantics. Consumed by Step 0-pre universal resume sweep and Phase 0.9 § F/G/H.
- Persistent global state: `~/.valves/state/`
- Bundled fork references: `~/.valves/references/`
- Plamen base CLAUDE.md: `~/.claude/CLAUDE.md` (between `<!-- PLAMEN:START -->` / `<!-- PLAMEN:END -->`)
- **Pattern detection library** (642 total patterns, two layers): `~/.valves/patterns/PATTERN_INDEX.md` — master index covering both layers. **Solodit layer** (562 patterns, 19 clusters): `~/.valves/patterns/{slug}.md`, extracted from 50,062 real Solodit findings. **Cantina layer** (80 patterns, 13 clusters + 1 new): `~/.valves/patterns/cantina/cantina-{slug}.md`, extracted from 279 confirmed HIGH/MEDIUM Cantina competition findings. Consumed by Phase 2e (cluster selection), breadth agents (compact detection checklists), depth iter 1 (post-methodology cross-check), DA iter 2-3 (adversarial alternative vectors), and chain analysis (failure mode extracts). See Rule 34 in this file.
- Plamen prompts/rules/skills: `~/.claude/prompts/`, `~/.claude/rules/`, `~/.claude/agents/skills/`
