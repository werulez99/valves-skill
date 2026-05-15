# v1.7-PATCH11.3 — Orchestration Integrity + Resume Verification Hardening

**Date**: 2026-05-07
**Type**: Infrastructure hardening (zero impact on recall/precision)
**Files changed**: 4
**Tests added**: 6 (tests 7-12 in checkpoint_resume_test.sh)

---

## Diagnosis

PATCH11.2 introduced the crash-safe state machine (`run_state.json`), session isolation, and basic enforcement gates. However, several failure modes remained:

1. **Soft step-completion**: A row could be marked COMPLETE with a missing, empty, truncated, or stale artifact on disk.
2. **Background agent acceptance gap**: Agent returns "DONE" but its output fails structural validation — no systematic rejection.
3. **Incomplete self-synthesis denylist**: Only ~15 artifacts on the ban list; ~25 additional agent-owned artifacts could be self-synthesized.
4. **No disk-truth supremacy rule**: After context compaction, the orchestrator could rely on in-memory beliefs over disk state.
5. **Resume trusts COMPLETE rows**: On resume, rows marked COMPLETE were trusted without re-validation against disk.
6. **Session B leak scan incomplete**: Post-rotation scan checked ~14 files + 4 globs; missed ~40 additional analytical artifacts.

---

## Files Changed

### 1. `~/.valves/CLAUDE.md` (+75 lines)
- **Rule 35 (NEW)**: Disk-Truth Supremacy — disk state overrides in-memory beliefs at every decision point
- **Rule 31**: Extended with comprehensive post-rotation leak scan reference + Session B startup re-scan
- **Rule 32**: Extended with absolute ban language — no self-synthesis under ANY justification
- **Rule 33.17**: Updated test harness reference (6 → 12 tests)

### 2. `~/.valves/commands/valves.md` (+180 lines)
- **§ A.1 (NEW)**: `VALIDATE_STEP_COMPLETION()` — 7-point validation function (exists, non-empty, structural signature, min lines, legal owner, not stale, producer completed)
- **§ A step 6 (NEW)**: Output integrity gate — validates agent output before acceptance, rejects + re-spawns on failure
- **§ B CRITICAL_AGENT_OWNED**: Extended from ~15 to ~40 entries (added chain, recon, thesis, analysis, niche, verification artifacts)
- **COMPLETE_A boundary**: Added COMPLETE_A_INLINE_SEQUENCE mechanical checklist (C1-C9)
- **§ F.1**: Extended post-hoc ban to cover ALL bundle artifacts + partial reconstruction
- **Post-rotation cross-check**: Expanded from ~14+4 patterns to ~50 exact + ~10 globs
- **Step 0-pre CLEAN RESUME**: Added artifact re-validation — COMPLETE rows validated against disk, downgraded to PENDING on failure
- **SESSION_B_RESUME**: Added pre-spawn leak re-scan + Session B artifact validation

### 3. `~/.valves/rules/execution-state.md` (+20 lines)
- **§ R4.1 (NEW)**: Extended validation rules table (6 checks beyond basic header)
- **Acceptance checks 12-16**: Five new mechanical assertions covering step validation, output integrity, resume validation, Session B re-scan, extended post-hoc ban
- Header version bumped to PATCH11.3

### 4. `~/.valves/state/checkpoint_resume_test.sh` (+120 lines)
- **Test 7**: DONE row with missing artifact file → detected
- **Test 8**: Empty/truncated artifact (below § R4 minimums) → detected
- **Test 9**: ORCHESTRATOR_SELF_SYNTHESIS_BANNED violations → detected
- **Test 10**: POST_HOC_HANDOFF_SYNTHESIS_BANNED violations → detected
- **Test 11**: Session B isolation — leaked analytical artifacts → detected
- **Test 12**: Stale artifact detection (mtime check) → detected
- Header updated: 6 → 12 tests

---

## Why This Doesn't Change Recall/Precision

All changes are orchestration infrastructure:
- No new agents, phases, sweeps, heuristics, or analytical layers
- No changes to depth templates, scanner checks, skill files, or security rules
- No changes to breadth agent prompts, finding formats, or severity matrix
- No changes to chain analysis, verification, or report generation logic

The patch makes existing architecture mechanically enforceable. It catches failure modes where the pipeline CLAIMED completion but the artifact was missing/invalid/stale. This prevents false deliverables, not false findings.

---

## Failure Modes Fixed

| # | Failure Mode | Pre-PATCH11.3 | Post-PATCH11.3 |
|---|-------------|---------------|----------------|
| 1 | Row COMPLETE but artifact missing | Undetected until report assembly | `VALIDATE_STEP_COMPLETION` rejects at source; test 7 catches |
| 2 | Agent writes empty file, says DONE | Accepted as valid | § A step 6 rejects + re-spawns; test 8 catches |
| 3 | Orchestrator self-synthesizes 25+ agent-owned artifacts | Only 15 on denylist | 40+ on denylist; test 9 catches violations |
| 4 | Context compaction causes orchestrator to skip disk check | No explicit supremacy rule | Rule 35 mandates disk-first at all decision points |
| 5 | Resume trusts stale COMPLETE rows | Rows accepted at face value | Re-validation downgrades invalid rows to PENDING |
| 6 | Session B starts with leaked analytical artifacts | 14+4 pattern scan | 50+10 comprehensive scan, run twice (post-rotation + pre-Session-B) |
| 7 | Post-hoc partial handoff (3 of 6 artifacts) | Only full handoff banned | All partial reconstruction also banned |
| 8 | Agent output stale (from prior run) | Not checked | mtime vs phase_start comparison; test 12 catches |

---

## VERSION

```
1.7.0-PATCH11.3
```
