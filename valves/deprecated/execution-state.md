# Execution State Machine (v1.7-PATCH11.3 — Orchestration Integrity + Resume Verification Hardening)

> **Principle**: The orchestrator reconstructs execution state from disk alone. `run_state.json` is the single source of truth for pipeline position, session identity, and phase status. It survives context compaction, usage exhaustion, and mid-run interruption.
>
> **Format**: JSON (not markdown). Parsed mechanically; no regex/header scanning needed.
>
> **Consumed by**: Step 0-pre (universal resume sweep), Phase 0.9 §F (reconciliation), every multi-agent phase (manifest creation), COMPLETE_A boundary, Session B entry, Phase 5/6 (mid-run recovery).

---

## § R1: `run_state.json` — Single Execution State File

Written to `{SCRATCHPAD}/run_state.json`. JSON format. Written BEFORE and AFTER every major step using the Write tool (atomic full-file write, never Edit).

### Schema

```json
{
  "version": "PATCH11",
  "project_name": "{project_name}",
  "last_write_iso": "{ISO 8601 timestamp}",

  "mode": "Light | Core | Thorough",
  "session": "A | A_RESUMED | B | B_RESUMED",
  "checkpoint_level": "NONE | PARTIAL_A | COMPLETE_A | PARTIAL_B | COMPLETE_B",
  "language": "evm | solana | aptos | sui | soroban",
  "project_root": "{absolute path}",
  "scratchpad": "{absolute path}",
  "valves_ver": "{version}",
  "plamen_ver": "{version}",

  "current_row": null,
  "current_phase": "{phase ID}",
  "phase_status": "INTENT | RUNNING | DONE | FAILED",
  "active_manifest": null,
  "last_completed_phase": null,
  "last_completed_timestamp": null,

  "expected_outputs": [],
  "completed_outputs": [],
  "pending_outputs": [],

  "spawned_agents": 0,
  "interrupted_agents": [],

  "last_transition": {
    "from_phase": null,
    "to_phase": null,
    "timestamp": null
  },

  "halt_reason": null,

  "write_ahead": {
    "action": null,
    "action_type": null,
    "targets": [],
    "timestamp": null,
    "interrupted": false
  },

  "resume_metadata": {
    "total_spawns_this_session": 0,
    "total_failures_this_session": 0,
    "last_agent_spawned": null,
    "recovery_attempts": 0
  }
}
```

### Field semantics

| Field | Type | Meaning |
|-------|------|---------|
| `mode` | enum | Audit mode. Immutable after init. |
| `session` | enum | `A` = Session A active. `A_RESUMED` = Session A resumed from interruption. `B` = Session B active (fresh conversation). `B_RESUMED` = Session B resumed from interruption. |
| `checkpoint_level` | enum | Monotonic progression: `NONE` → `PARTIAL_A` → `COMPLETE_A` → `PARTIAL_B` → `COMPLETE_B`. Never goes backward. |
| `current_row` | int/null | Current checklist row being worked on. Null between phases. |
| `current_phase` | string | Phase ID from the pipeline (e.g., `phase1`, `phase4b_iter1`, `complete_a`). |
| `phase_status` | enum | `INTENT` = about to start. `RUNNING` = in progress. `DONE` = completed. `FAILED` = error. |
| `expected_outputs` | array[string] | File paths the current phase/step should produce. |
| `completed_outputs` | array[string] | Subset of expected that exist and passed validity check. |
| `pending_outputs` | array[string] | Subset of expected that are missing or invalid. |
| `spawned_agents` | int | Count of agents spawned in current phase. |
| `interrupted_agents` | array[string] | Agent names whose output is missing (crash recovery). |
| `last_transition` | object | Records the most recent phase transition for audit trail. |
| `halt_reason` | string/null | Non-null when the orchestrator halted. Values: `COMPLETE_A_BOUNDARY`, `COMPLETE_B_FINAL`, `RECOVERY_EXHAUSTED`, `SCOPE_VIOLATION_PERSISTENT`, `INVALID_FINALIZATION`, `RUN_STATE_CORRUPT`, `ILLEGAL_LEGACY_FALLTHROUGH`. |
| `write_ahead` | object | Write-ahead intent (§ R2). `interrupted=true` means an action started but did not complete. |
| `resume_metadata` | object | Session-scoped counters for observability. |

### Checkpoint level semantics

| Level | When written | Meaning |
|-------|-------------|---------|
| `NONE` | Step 0.85c init | Fresh run, no progress. |
| `PARTIAL_A` | After every major Session A phase transition | Session A in progress. Resume from `current_phase`. |
| `COMPLETE_A` | COMPLETE_A boundary (after handoff bundle) | Session A done. Halt. Start Session B in fresh conversation. |
| `PARTIAL_B` | Immediately on Session B entry + after every major Session B phase transition | Session B in progress. Resume from `current_phase`. |
| `COMPLETE_B` | Phase 6e+1 Session B Closure | Full audit done. |

### Write protocol

1. **Before any major action** (agent spawn, orchestrator-inline write, phase transition): set `phase_status: "INTENT"`, fill `write_ahead` with `interrupted: true`, update `expected_outputs`.
2. **After action succeeds**: set `phase_status: "DONE"`, move targets from `pending_outputs` to `completed_outputs`, set `write_ahead.interrupted: false`, update `last_completed_phase`.
3. **On action failure**: set `phase_status: "FAILED"`, preserve `write_ahead` for diagnosis, increment `resume_metadata.recovery_attempts`.
4. **On phase transition**: update `current_phase`, `last_transition`, reset `recovery_attempts`, advance `checkpoint_level` if crossing a checkpoint boundary.
5. **On Session B entry**: set `session: "B"`, `checkpoint_level: "PARTIAL_B"` immediately (before any Session B work).

### Atomic write rule

`run_state.json` is ALWAYS written as a complete file (Write tool, never Edit). JSON must be valid — partial writes corrupt resume. The orchestrator serializes the full state object and writes it in one tool call.

---

## § R2: Write-Ahead Intent

Before ANY action that spawns agents or writes artifacts, the orchestrator logs what it is ABOUT to do in `run_state.json` → `write_ahead`:

```json
"write_ahead": {
  "action": "Spawn 5 breadth agents for phase3",
  "action_type": "SPAWN_AGENTS | ORCHESTRATOR_INLINE | CHECKPOINT_WRITE | PHASE_TRANSITION",
  "targets": ["analysis_breadth_1.md", "analysis_breadth_2.md", ...],
  "timestamp": "2026-05-06T12:00:00Z",
  "interrupted": true
}
```

### Intent lifecycle

```
write_ahead.interrupted=true → action begins → succeeds → interrupted=false, phase_status=DONE
                                             → fails → phase_status=FAILED (intent preserved)
                                             → crash → interrupted stays true on disk
```

On resume: if `write_ahead.interrupted == true`:
- `phase_status == "INTENT"` → action never started (safe to retry)
- `phase_status == "RUNNING"` → action started, check outputs on disk
- Check `expected_outputs` vs disk: if all valid → advance; if partial → re-spawn missing

---

## § R3: Phase Manifests

Unchanged from prior version. Manifest files remain markdown (`manifest_{phase_id}.md`) — they are multi-agent tracking artifacts, not state machines. Schema per prior spec. See `~/.valves/rules/artifact-ownership.md` for ownership.

Resume from manifest: parse `active_manifest` path from `run_state.json`, read the manifest, re-spawn agents whose output is missing.

---

## § R4: Validity Checks

File existence alone is insufficient. Each artifact class has a minimal validity check. Table unchanged from prior version.

| Artifact Class | Min Lines | Required Header/Section | Check Type |
|---|---|---|---|
| `findings_inventory.md` | 10 | `## Finding Inventory` OR `\| ID \|` header row | HEADER + LINE_COUNT |
| `analysis_*.md` | 5 | `## Finding [` (at least one finding section) | HEADER |
| `design_context.md` | 20 | `## Operational Implications` | HEADER |
| `attack_surface.md` | 10 | `## ` (any H2) | HEADER |
| `confidence_scores.md` | 5 | `\| Finding` OR `\| ID` header row | HEADER |
| `root_cause_clusters.md` | 10 | `## Cluster` OR `## BC-` | HEADER |
| `hypotheses.md` | 5 | `## ` (any H2 section) | HEADER |
| `chain_hypotheses.md` | 3 | `## Chain` OR `\| Chain` | HEADER |
| `verify_*.md` | 5 | `### Execution Result` OR `### Verdict` | HEADER |
| `report_index.md` | 10 | `## Master Finding Index` | HEADER |
| `report_critical_high.md` | 3 | `## Critical` OR `## High` | HEADER |
| `report_medium.md` | 3 | `## Medium` | HEADER |
| `report_low_info.md` | 3 | `## Low` OR `## Informational` | HEADER |
| `AUDIT_REPORT.md` | 50 | `# Security Audit Report` | HEADER + LINE_COUNT |
| `session_checkpoint.md` | 5 | `CHECKPOINT_LEVEL:` | HEADER |
| `session_a_to_b_handoff.md` | 10 | `## §` (any section) | HEADER |
| `run_state.json` | 3 | valid JSON with `"version"` key | JSON_PARSE |
| `manifest_*.md` | 5 | `## Agent Table` | HEADER |
| All other `.md` artifacts | 3 | — (non-empty) | LINE_COUNT only |

### § R4.1: Extended validation rules (v1.7-PATCH11.3)

File existence + header check is necessary but not sufficient. Phase 0.9 § A.1 `VALIDATE_STEP_COMPLETION()` enforces ALL of:

| Check | What it catches | How |
|-------|----------------|-----|
| Non-empty | Agent wrote empty file | `count_lines > 0` |
| Min lines | Agent wrote stub/truncated output | Per-class minimum from table above |
| Structural signature | Agent wrote wrong format | Required header grep |
| Legal owner | Orchestrator self-synthesized | `artifact-ownership.md` lookup |
| Not stale (mtime) | Pre-existing artifact from prior run | `mtime > phase_start_time` |
| Not stale (run_id) | Ghost artifact from a different run | Grep first line for `run_id:{CURRENT_RUN_ID}`. If header present but run_id mismatches → `ARTIFACT_STALE_RUNID`. If header absent: check if artifact is on `CRITICAL_AGENT_OWNED` list → if YES: `ARTIFACT_HEADER_MISSING` (fail-closed). If NOT on list → fall back to mtime check only (orchestrator-written file). |
| Producer completed | Agent timed out but file exists from prior run | Manifest status check |

A step is COMPLETE only when ALL seven checks pass (six original + run_id check). Any failure → row stays PENDING or downgrades to FAILED.

**Run_id stale detection (v1.7-PATCH11.3-CANTINA, Rule 36)**:
```
stale_check_run_id(artifact_path, current_run_id, is_agent_owned):
    first_line = read_first_line(artifact_path)
    if first_line starts with "<!-- VALVES-ARTIFACT":
        match = extract("run_id:([^ ]+)", first_line)
        if match and match != current_run_id:
            return ARTIFACT_STALE_RUNID  // ghost from prior run
        if match and match == current_run_id:
            return CURRENT_RUN  // confirmed current
    // No header found
    if is_agent_owned:
        return ARTIFACT_HEADER_MISSING  // fail-closed for agent-owned artifacts
    return NO_HEADER  // orchestrator-written file, fall back to mtime
```

**Fail-closed for agent-owned artifacts (v1.7-CANTINA-RUNID)**:
The `is_agent_owned` flag is `true` when `artifact_path` basename matches any entry in `CRITICAL_AGENT_OWNED` (Phase 0.9 § B). For these ~40 artifacts, a missing `<!-- VALVES-ARTIFACT ... -->` header is treated as `ARTIFACT_HEADER_MISSING` → row downgraded to PENDING, artifact renamed to `{filename}.noheader`, agent re-spawned once. This is fail-closed: an agent that does not stamp its output is assumed to have produced a ghost artifact, not a legitimate one. Orchestrator-written files (run_state.json, session_checkpoint.md, pipeline_trace.md, etc.) do NOT require the header — they are not on the agent-owned list.

The orchestrator reads `current_run_id` from `{SCRATCHPAD}/run_state.json`. On `ARTIFACT_STALE_RUNID`, the artifact is renamed to `{filename}.stale.{old_run_id}` and the row is downgraded to PENDING for re-spawn.

### `run_state.json` validity check (specific)

```
validity_check_run_state(path):
    if not file_exists(path): return MISSING
    content = read(path)
    try: obj = JSON.parse(content)
    catch: return MALFORMED
    if "version" not in obj: return MALFORMED
    if "session" not in obj: return MALFORMED
    if "checkpoint_level" not in obj: return MALFORMED
    if "current_phase" not in obj: return MALFORMED
    // run_id is optional for backward compat (pre-Rule-36 runs)
    // but if present, it must be a non-empty string
    if "run_id" in obj and (obj.run_id == "" or obj.run_id == null): return MALFORMED
    return VALID
```

---

## § R5: Universal Resume Sweep (Step 0-pre Enhancement)

On every `/valves` invocation, BEFORE the wizard or any pipeline logic:

```
UNIVERSAL_RESUME_SWEEP(project_path):

  scratchpad = "{project_path}/.audit_scratchpad"
  run_state_path = "{scratchpad}/run_state.json"

  // === TIER 1: run_state.json exists (preferred recovery path) ===
  if file_exists(run_state_path):
      // PATCH11-F: existence assertion BEFORE read
      content = read(run_state_path)
      try:
          state = JSON.parse(content)
      catch:
          // FAIL-CLOSED (v1.7-PATCH12): corrupt JSON halts instead of legacy fallback
          HALT with halt_reason = "RUN_STATE_CORRUPT"
          // Manual recovery: fix JSON, delete file, or /valves --legacy-resume

      // Structural integrity check
      if state.version == null OR state.session == null OR state.current_phase == null:
          // FAIL-CLOSED (v1.7-PATCH12): missing fields halts instead of legacy fallback
          HALT with halt_reason = "RUN_STATE_CORRUPT"
          // Manual recovery: fix JSON, delete file, or /valves --legacy-resume

      // === SESSION-AWARE ROUTING ===
      if state.checkpoint_level == "COMPLETE_A":
          // Session A finished. This is a Session B entry or resume.
          // PATCH11-I: Session B writes PARTIAL_B immediately on entry
          if state.session in ["A", "A_RESUMED"]:
              // Fresh Session B entry (new conversation after COMPLETE_A)
              state.session = "B"
              state.checkpoint_level = "PARTIAL_B"
              state.phase_status = "DONE"
              state.write_ahead.interrupted = false
              state.halt_reason = null
              write_run_state(state)
              goto SESSION_B_ENTRY
          elif state.session in ["B", "B_RESUMED"]:
              // Session B resume
              state.session = "B_RESUMED"
              write_run_state(state)
              goto SESSION_B_RESUME(state)

      elif state.checkpoint_level == "PARTIAL_B":
          // Session B was interrupted mid-run
          state.session = "B_RESUMED"
          write_run_state(state)
          goto SESSION_B_RESUME(state)

      elif state.checkpoint_level == "COMPLETE_B":
          // Audit fully done. Show completion banner and halt.
          goto AUDIT_COMPLETE_BANNER

      // === CRASH RECOVERY (write_ahead.interrupted == true) ===
      if state.write_ahead.interrupted == true:
          print: "CRASH RECOVERY — resuming from {state.current_phase}"
          // Restore context from state
          MODE = state.mode; SESSION = state.session; LANGUAGE = state.language
          PROJECT_ROOT = state.project_root; SCRATCHPAD = state.scratchpad

          // Check if interrupted action completed (outputs on disk)
          if state.active_manifest != null AND file_exists(state.active_manifest):
              needs_respawn = reconcile_manifest_with_disk(state.active_manifest)
              if len(needs_respawn) == 0:
                  advance_state(state, "DONE")
                  goto RESUME_AT(state.current_phase, next_step)
              else:
                  goto RESPAWN_MISSING(state.current_phase, needs_respawn)

          elif len(state.expected_outputs) > 0:
              all_valid = all(file_exists(t) AND validity_check(t) for t in state.expected_outputs)
              if all_valid:
                  advance_state(state, "DONE")
                  goto RESUME_AT(state.current_phase, next_step)
              else:
                  if state.resume_metadata.recovery_attempts >= 3:
                      HALT("RECOVERY_EXHAUSTED")
                  goto RETRY(state.current_phase)
          else:
              if state.resume_metadata.recovery_attempts >= 3:
                  HALT("RECOVERY_EXHAUSTED")
              goto RETRY(state.current_phase)

      // === CLEAN RESUME (phase_status == "DONE") ===
      elif state.phase_status == "DONE":
          MODE = state.mode; SESSION = state.session; LANGUAGE = state.language
          PROJECT_ROOT = state.project_root; SCRATCHPAD = state.scratchpad
          goto RESUME_AT(state.current_phase, next_step)

      // === FAILED STATE ===
      elif state.phase_status == "FAILED":
          MODE = state.mode; SESSION = state.session; LANGUAGE = state.language
          if state.resume_metadata.recovery_attempts >= 3:
              HALT("RECOVERY_EXHAUSTED")
          goto RETRY(state.current_phase)

  // === TIER 2: No run_state.json but checkpoint exists (legacy) ===
  elif file_exists("{scratchpad}/session_checkpoint.md"):
      goto EXISTING_CHECKPOINT_ROUTING

  // === TIER 3: No state files — fresh run ===
  else:
      goto WIZARD

// === SESSION B RESUME (PATCH11-B: session-aware, no contamination deletion) ===
SESSION_B_RESUME(state):
    MODE = state.mode; SESSION = state.session; LANGUAGE = state.language
    PROJECT_ROOT = state.project_root; SCRATCHPAD = state.scratchpad
    // Scan checklist + run_state.json + existing outputs
    // Continue from first incomplete row owned by Session B
    // DO NOT delete Session B artifacts (they are legitimate work products)
    if state.write_ahead.interrupted:
        goto CRASH_RECOVERY_WITHIN_SESSION_B(state)
    else:
        goto RESUME_AT(state.current_phase, next_step)
```

---

## § R6: Phase-Boundary Reconciliation

At every phase boundary, three-way consistency check between:
1. `run_state.json` (orchestrator's position)
2. `mandatory_step_checklist.md` (row statuses)
3. Manifest files + disk artifacts (ground truth)

Algorithm unchanged from prior version. The only change: read/write `run_state.json` (JSON parse/serialize) instead of `run_state.md` (markdown parse).

---

## § R7: Mid-Run Interruption Recovery

For phases with multiple sequential batches (Phase 5 verification, Phase 6 report), use manifests to resume from the exact interruption point. Algorithm unchanged from prior version.

---

## § R8: Session Isolation Survives Resume

`run_state.json` persists `session` and `checkpoint_level` fields:
- `session: "B"` + `.audit_session_a/` missing → `SCRATCHPAD_ROTATION_MISSING` violation. Recovery: check if pre-rotation scratchpad exists; perform deferred rotation.
- `session: "A"` + `.audit_session_a/` exists → stale archive from prior run or bug. Check timestamps; if archive newer than `run_state.json` → `CONSISTENCY_VIOLATION`.
- `checkpoint_level: "PARTIAL_B"` → Session B in progress. DO NOT delete Session B artifacts. Resume from `current_phase`.
- `checkpoint_level: "COMPLETE_A"` + `session: "A"` → Session A halted at boundary. Next invocation transitions to Session B.

---

## § R9: PARTIAL_B Semantics

`PARTIAL_B` is written:
1. **Immediately** when Session B starts (before any Session B work). This is the first write after the `COMPLETE_A` → `B` session transition.
2. **After every major Session B phase transition** (DA iter 2, chain analysis, verification batches, report pipeline stages).

`PARTIAL_B` enables Session B resume:
- On resume, `checkpoint_level == "PARTIAL_B"` tells the orchestrator: "Session B started but did not finish. The artifacts in `.audit_scratchpad/` are Session B's own work products. Do NOT delete them."
- The contamination check (§ R9.1) uses `checkpoint_level` to distinguish:
  - `COMPLETE_A` + Session B artifacts present → these are from a PREVIOUS Session B attempt. Valid.
  - `PARTIAL_B` + Session B artifacts present → these are from the CURRENT Session B attempt. Valid.
  - `PARTIAL_A` + Session B artifacts present → impossible under correct operation. `CONSISTENCY_VIOLATION`.

### § R9.1: Session-Aware Contamination Check (replaces FORBIDDEN_IN_FRESH_SCRATCHPAD)

The old contamination check deleted Session B artifacts unconditionally. The new check is session-aware:

```
SESSION_AWARE_CONTAMINATION_CHECK(scratchpad, run_state):
    SESSION_B_WORK_PRODUCTS = [
        "hypotheses.md", "chain_hypotheses.md", "synthesis_full.md",
        "rag_validation.md", "root_cause_clusters.md", "cluster_instance_map.md",
        "report_index.md", "report_critical_high.md", "report_medium.md",
        "report_low_info.md", "AUDIT_REPORT.md", "verification_verdicts_summary.md",
        "cross_session_consensus.md", "cross_batch_consistency.md"
    ]

    if run_state.checkpoint_level in ["PARTIAL_B", "COMPLETE_B"]:
        // Session B has started or completed. These artifacts are legitimate.
        // DO NOT DELETE. They are Session B's own work products.
        return  // no action

    if run_state.checkpoint_level == "COMPLETE_A" AND run_state.session in ["A", "A_RESUMED"]:
        // Session A just finished, Session B hasn't started yet.
        // These artifacts should NOT exist in the fresh scratchpad.
        contaminated = [f for f in SESSION_B_WORK_PRODUCTS if file_exists("{scratchpad}/{f}")]
        if len(contaminated) > 0:
            // Genuine contamination: Session A analytical artifacts leaked into fresh scratchpad
            log "SESSION_B_SCRATCHPAD_CONTAMINATED: {contaminated}"
            for f in contaminated:
                delete "{scratchpad}/{f}"

    if run_state.checkpoint_level in ["NONE", "PARTIAL_A"]:
        // Session A is in progress. Session B artifacts should not exist.
        contaminated = [f for f in SESSION_B_WORK_PRODUCTS if file_exists("{scratchpad}/{f}")]
        if len(contaminated) > 0:
            log "CONSISTENCY_VIOLATION: Session B artifacts found during Session A"
            // Do NOT auto-delete — this is a serious state inconsistency
            // HALT and ask for manual intervention or fresh-run
```

---

## § R10: Atomic Writes for Critical State Files

Critical state files use full-file Write (never Edit):

| File | Format | Reason |
|------|--------|--------|
| `run_state.json` | JSON | Primary state — partial corruption = lost resume |
| `manifest_*.md` | Markdown | Agent tracking — partial = duplicate spawns |
| `session_checkpoint.md` | Markdown | Session boundary — partial = incorrect routing |
| `mandatory_step_checklist.md` | Markdown | Progress tracking — partial = drift false positives |

---

## § Interaction with Existing Mechanisms

| Existing Mechanism | PATCH11 Interaction |
|---|---|
| Phase 0.9 § D (drift detection) | Runs AFTER reconciliation (§ R6). Unchanged. |
| Phase 0.9 § E (halt marker) | Unchanged. Halt marker checked independently of `run_state.json`. |
| COMPLETE_A boundary | `run_state.json` records `checkpoint_level: "COMPLETE_A"`. Scratchpad rotation copies `run_state.json` to fresh scratchpad (ALLOWLIST updated). |
| Session B entry | `run_state.json` transitions: `session: "B"`, `checkpoint_level: "PARTIAL_B"`. Written BEFORE any Session B agent spawn. |
| Pipeline trace | `pipeline_trace.md` remains the mass-balance ledger. `run_state.json` is the position/intent record. Different purposes. |
| Watchdog | Watchdog reads checklist. PATCH11 ensures checklist stays current via reconciliation. |

---

## § Failure modes and guarantees

| Failure | Recovery |
|---|---|
| Context compaction mid-phase | `run_state.json` + manifest → reconstruct position, re-spawn missing |
| Usage exhaustion mid-phase | Same as compaction. New session reads `run_state.json` on resume. |
| Agent crash | Manifest marks FAILED, existing re-spawn logic applies |
| Crash before writing DONE | `write_ahead.interrupted=true` preserved, tells next session what to re-attempt |
| Crash after agents return but before checklist update | Manifest has DONE status, reconciliation catches drift |
| Duplicate spawns on resume | Output existence + validity check → skip re-spawn |
| Session B resume deletes own artifacts | **FIXED**: session-aware contamination check (§ R9.1) checks `checkpoint_level` before acting |
| Partial scratchpad rotation | `session` + `checkpoint_level` + `.audit_session_a/` existence → detect and complete rotation |
| SESSION_B_COMPLETE.md exists but checkpoint ≠ COMPLETE_B | **ABORT**: Step 0-pre + legacy routing detect inconsistency, emit `SESSION_B_CHECKPOINT_INCONSISTENCY`, halt |
| Session B entered without PARTIAL_B on disk | **ABORT**: legacy path writes PARTIAL_B inline + verifies; run_state.json path writes PARTIAL_B before any work |
| COMPLETE_B rerun attempts to continue work | **HALT**: run_state.json and legacy routing both detect COMPLETE_B → show finalization banner, refuse to proceed |

---

## § Acceptance Checks (v1.7-PATCH11.1 — Mechanical Validation)

These checks are enforced by the pipeline at the locations noted. They are not advisory.

| # | Assertion | Enforced At | Violation Code |
|---|---|---|---|
| 1 | Session B cannot start if `run_state.json`, `SESSION_B_READ_SCOPE.md`, `session_checkpoint.md`, or `session_a_to_b_handoff.md` is missing | Step 0-pre CHECK 3 (legacy path) | `SESSION_B_MISSING_PREREQUISITES` |
| 2 | Session B writes `checkpoint_level: "PARTIAL_B"` to `run_state.json` before any work | Step 0-pre (run_state.json path line 534, legacy path PARTIAL_B gate) | `SESSION_B_PARTIAL_B_WRITE_FAILED` |
| 3 | Session B writes `checkpoint_level: "COMPLETE_B"` to `run_state.json` + `session_checkpoint.md` + `SESSION_B_COMPLETE.md` on valid finish | Phase 6e+1 post-checkpoint writes | `COMPLETE_B_CONSISTENCY_FAILURE` |
| 4 | COMPLETE_B rerun halts immediately, does not continue work | Step 0-pre (run_state.json line 565, legacy line 900) | N/A (shows AUDIT_COMPLETE_BANNER) |
| 5 | `SESSION_B_COMPLETE.md` exists + `session_checkpoint.md` ≠ COMPLETE_B → abort as corruption | Step 0-pre CHECK 3b, run_state.json COMPLETE_B routing | `SESSION_B_CHECKPOINT_INCONSISTENCY` |
| 6 | Resume after interruption in mid-verification continues from saved state, not from scratch | `SESSION_B_RESUME_FROM_RUN_STATE` reads `current_phase` + manifest; idempotent pre-spawn checks | N/A (mechanical — skip-if-exists) |
| 7 | Session B agents cannot read `.audit_session_a/` analytical artifacts beyond handoff/isolation files | Phase 0.9 § A.2.5 (Read + Bash inspection + realpath) | `SESSION_B_ISOLATION_BREACH_READ`, `SESSION_B_ISOLATION_BREACH_BASH` |
| 8 | (PATCH11.2) Session A past row 22 without COMPLETE_A checkpoint → INVALID, no post-hoc handoff | Phase 0.9 § F.1 (every phase boundary) | `POST_HOC_HANDOFF_SYNTHESIS_BANNED` |
| 9 | (PATCH11.2) Orchestrator cannot write AGENT-OWNED artifacts directly | Phase 0.9 § B CRITICAL_AGENT_OWNED list + § B.1 | `ORCHESTRATOR_SELF_SYNTHESIS_BANNED` |
| 10 | (PATCH11.2) Physical scratchpad rotation leaves no Session A analytical artifacts in fresh scratchpad | COMPLETE_A boundary step 1.5 post-rotation cross-check | `ROTATION_LEAK_DETECTED` |
| 11 | (PATCH11.2) Disk state overrides conversational momentum after compaction | Phase 0.9 § F DISK STATE PRIORITY RULE | N/A (mechanical — read-then-route) |
| 12 | (PATCH11.3) Step completion requires 7-point validation (exists + non-empty + header + min-lines + legal-owner + not-stale + producer-complete) | Phase 0.9 § A.1 VALIDATE_STEP_COMPLETION | `ARTIFACT_MISSING`, `ARTIFACT_EMPTY`, `ARTIFACT_INVALID`, `ARTIFACT_TRUNCATED`, `ILLEGAL_OWNER`, `ARTIFACT_STALE`, `PRODUCER_INCOMPLETE` |
| 13 | (PATCH11.3) Background agent output validated before acceptance (freshness + integrity + ownership) | Phase 0.9 § A step 6 OUTPUT INTEGRITY GATE | `AGENT_OUTPUT_INTEGRITY_FAIL` |
| 14 | (PATCH11.3) Resume validates ALL COMPLETE rows on disk before continuing | Step 0-pre CLEAN RESUME path | N/A (rows downgraded to PENDING if invalid) |
| 15 | (PATCH11.3) Session B re-runs leak scan before first agent spawn | Step 0-pre SESSION_B_RESUME path | `ROTATION_LEAK_DETECTED` |
| 16 | (PATCH11.3) Post-hoc handoff ban covers ALL bundle artifacts + partial reconstruction | Phase 0.9 § F.1 EXTENDED BAN | `POST_HOC_HANDOFF_SYNTHESIS_BANNED` |
