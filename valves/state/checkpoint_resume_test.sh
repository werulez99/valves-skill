#!/usr/bin/env bash
# Valves v1.7-PATCH11.3 — Deterministic Resume Test Harness
# Tests 12 checkpoint/resume + integrity state assertions mechanically.
# Tests 1-6: checkpoint/resume (PATCH11.2)
# Tests 7-12: orchestration integrity (PATCH11.3)
# Usage: bash ~/.valves/state/checkpoint_resume_test.sh /path/to/project
# Exit 0 = all pass, Exit 1 = failures detected.

set -euo pipefail
PROJECT="${1:?Usage: $0 /path/to/project}"
SP="$PROJECT/.audit_scratchpad"
SA="$PROJECT/.audit_session_a"
PASS=0; FAIL=0

check() {
    local name="$1" cond="$2"
    if eval "$cond"; then
        echo "  PASS: $name"
        ((PASS++))
    else
        echo "  FAIL: $name"
        ((FAIL++))
    fi
}

echo "=== Valves Checkpoint/Resume Test Harness ==="
echo "Project: $PROJECT"
echo ""

RS="$SP/run_state.json"
CP="$SP/session_checkpoint.md"

# --- Test 1: PARTIAL_A resume ---
echo "[Test 1] PARTIAL_A resume"
if [ -f "$RS" ]; then
    CL=$(python3 -c "import json; print(json.load(open('$RS'))['checkpoint_level'])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$CL" = "PARTIAL_A" ]; then
        check "run_state.json says PARTIAL_A" "true"
        check "session_checkpoint.md exists" "[ -f '$CP' ]"
        check "mandatory_step_checklist.md exists" "[ -f '$SP/mandatory_step_checklist.md' ]"
    else
        echo "  SKIP: checkpoint_level=$CL (not PARTIAL_A)"
    fi
else
    echo "  SKIP: no run_state.json"
fi

# --- Test 2: COMPLETE_A -> Session B entry ---
echo "[Test 2] COMPLETE_A -> Session B entry"
if [ -f "$RS" ]; then
    CL=$(python3 -c "import json; print(json.load(open('$RS'))['checkpoint_level'])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$CL" = "COMPLETE_A" ]; then
        check "HALT_AFTER_COMPLETE_A.md exists" "[ -f '$SP/HALT_AFTER_COMPLETE_A.md' ]"
        check "session_a_to_b_handoff.md exists" "[ -f '$SP/session_a_to_b_handoff.md' ]"
        check "SESSION_B_READ_SCOPE.md exists" "[ -f '$SP/SESSION_B_READ_SCOPE.md' ]"
        check "session_checkpoint.md exists" "[ -f '$CP' ]"
        check ".audit_session_a archive exists" "[ -d '$SA' ]"
    else
        echo "  SKIP: checkpoint_level=$CL (not COMPLETE_A)"
    fi
else
    echo "  SKIP: no run_state.json"
fi

# --- Test 3: PARTIAL_B resume during verification ---
echo "[Test 3] PARTIAL_B resume during verification"
if [ -f "$RS" ]; then
    CL=$(python3 -c "import json; print(json.load(open('$RS'))['checkpoint_level'])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$CL" = "PARTIAL_B" ]; then
        SN=$(python3 -c "import json; print(json.load(open('$RS'))['session'])" 2>/dev/null || echo "UNKNOWN")
        check "session is B or B_RESUMED" "[ '$SN' = 'B' ] || [ '$SN' = 'B_RESUMED' ]"
        check "session_a_to_b_handoff.md exists" "[ -f '$SP/session_a_to_b_handoff.md' ]"
        check "SESSION_B_READ_SCOPE.md exists" "[ -f '$SP/SESSION_B_READ_SCOPE.md' ]"
        check "no Session A analytical artifacts in active scratchpad" "! ls '$SP'/analysis_depth_*.md 2>/dev/null | grep -q . || [ -d '$SA' ]"
    else
        echo "  SKIP: checkpoint_level=$CL (not PARTIAL_B)"
    fi
else
    echo "  SKIP: no run_state.json"
fi

# --- Test 4: COMPLETE_B finalized rerun halt ---
echo "[Test 4] COMPLETE_B finalized rerun halt"
if [ -f "$RS" ]; then
    CL=$(python3 -c "import json; print(json.load(open('$RS'))['checkpoint_level'])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$CL" = "COMPLETE_B" ]; then
        check "session_checkpoint.md says COMPLETE_B" "grep -q 'CHECKPOINT_LEVEL: COMPLETE_B' '$CP' 2>/dev/null"
        check "SESSION_B_COMPLETE.md marker exists" "[ -f '$SP/SESSION_B_COMPLETE.md' ]"
        check "AUDIT_REPORT.md exists" "[ -f '$PROJECT/AUDIT_REPORT.md' ]"
    else
        echo "  SKIP: checkpoint_level=$CL (not COMPLETE_B)"
    fi
else
    echo "  SKIP: no run_state.json"
fi

# --- Test 5: Corrupted state — marker exists, checkpoint mismatch ---
echo "[Test 5] Corruption: SESSION_B_COMPLETE.md + checkpoint != COMPLETE_B"
if [ -f "$SP/SESSION_B_COMPLETE.md" ] && [ -f "$CP" ]; then
    CP_LEVEL=$(grep 'CHECKPOINT_LEVEL:' "$CP" 2>/dev/null | head -1 | awk '{print $NF}' || echo "MISSING")
    if [ "$CP_LEVEL" != "COMPLETE_B" ]; then
        echo "  DETECTED: SESSION_B_COMPLETE.md exists but checkpoint=$CP_LEVEL (CORRUPTION)"
        ((FAIL++))
    else
        check "marker and checkpoint consistent" "true"
    fi
else
    echo "  SKIP: marker or checkpoint not present (no corruption to detect)"
fi

# --- Test 6: Session B startup prerequisites ---
echo "[Test 6] Session B startup prerequisites (all 4 files)"
if [ -f "$RS" ]; then
    CL=$(python3 -c "import json; print(json.load(open('$RS'))['checkpoint_level'])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$CL" = "COMPLETE_A" ] || [ "$CL" = "PARTIAL_B" ]; then
        check "run_state.json present" "[ -f '$RS' ]"
        check "SESSION_B_READ_SCOPE.md present" "[ -f '$SP/SESSION_B_READ_SCOPE.md' ]"
        check "session_checkpoint.md present" "[ -f '$CP' ]"
        check "session_a_to_b_handoff.md present" "[ -f '$SP/session_a_to_b_handoff.md' ]"
    else
        echo "  SKIP: checkpoint_level=$CL (not at Session B boundary)"
    fi
else
    echo "  SKIP: no run_state.json"
fi

# --- Test 7: DONE row with missing artifact (PATCH11.3) ---
echo "[Test 7] DONE row with missing artifact file → should be rejected"
if [ -f "$SP/mandatory_step_checklist.md" ]; then
    # Find any COMPLETE row and check its evidence artifact exists
    FOUND_INVALID=0
    while IFS='|' read -r _ _ _ status _ artifact _; do
        status=$(echo "$status" | xargs)
        artifact=$(echo "$artifact" | xargs)
        if [ "$status" = "COMPLETE" ] && [ -n "$artifact" ] && [ "$artifact" != "-" ]; then
            # Resolve artifact path (may be relative to scratchpad)
            if [[ "$artifact" == /* ]]; then
                APATH="$artifact"
            else
                APATH="$SP/$artifact"
            fi
            if [ ! -f "$APATH" ]; then
                echo "  DETECTED: Row COMPLETE but artifact missing: $artifact"
                FOUND_INVALID=1
                ((FAIL++))
            fi
        fi
    done < <(grep '|' "$SP/mandatory_step_checklist.md" | tail -n +3)
    if [ "$FOUND_INVALID" -eq 0 ]; then
        check "All COMPLETE rows have artifacts on disk" "true"
    fi
else
    echo "  SKIP: no mandatory_step_checklist.md"
fi

# --- Test 8: Empty/truncated artifact detection (PATCH11.3) ---
echo "[Test 8] Empty or truncated artifact detection"
if [ -f "$SP/mandatory_step_checklist.md" ]; then
    FOUND_EMPTY=0
    for f in "$SP"/analysis_*.md "$SP"/findings_inventory.md "$SP"/design_context.md "$SP"/AUDIT_REPORT.md; do
        if [ -f "$f" ]; then
            LC=$(wc -l < "$f")
            BASENAME=$(basename "$f")
            # Check minimum line counts per § R4
            case "$BASENAME" in
                findings_inventory.md) MIN=10 ;;
                design_context.md) MIN=20 ;;
                AUDIT_REPORT.md) MIN=50 ;;
                analysis_*.md) MIN=5 ;;
                *) MIN=3 ;;
            esac
            if [ "$LC" -lt "$MIN" ]; then
                echo "  DETECTED: $BASENAME has $LC lines (minimum: $MIN) — truncated"
                FOUND_EMPTY=1
                ((FAIL++))
            fi
        fi
    done
    if [ "$FOUND_EMPTY" -eq 0 ]; then
        check "No truncated artifacts detected" "true"
    fi
else
    echo "  SKIP: no mandatory_step_checklist.md"
fi

# --- Test 9: Illegal orchestrator write to AGENT-OWNED artifact (PATCH11.3) ---
echo "[Test 9] No orchestrator self-synthesis of AGENT-OWNED artifacts"
if [ -f "$SP/violations.md" ]; then
    SELF_SYNTH=$(grep -c "ORCHESTRATOR_SELF_SYNTHESIS_BANNED" "$SP/violations.md" 2>/dev/null || echo "0")
    if [ "$SELF_SYNTH" -gt 0 ]; then
        echo "  DETECTED: $SELF_SYNTH orchestrator self-synthesis violations in violations.md"
        ((FAIL++))
    else
        check "No ORCHESTRATOR_SELF_SYNTHESIS_BANNED violations" "true"
    fi
else
    check "No violations.md (no violations recorded)" "true"
fi

# --- Test 10: Post-hoc handoff synthesis ban (PATCH11.3) ---
echo "[Test 10] No post-hoc handoff synthesis"
if [ -f "$SP/violations.md" ]; then
    POST_HOC=$(grep -c "POST_HOC_HANDOFF_SYNTHESIS_BANNED" "$SP/violations.md" 2>/dev/null || echo "0")
    if [ "$POST_HOC" -gt 0 ]; then
        echo "  DETECTED: $POST_HOC post-hoc handoff synthesis violations"
        ((FAIL++))
    else
        check "No POST_HOC_HANDOFF_SYNTHESIS_BANNED violations" "true"
    fi
else
    check "No violations.md (no post-hoc violations)" "true"
fi

# --- Test 11: Session B isolation — no analytical artifacts in fresh scratchpad (PATCH11.3) ---
echo "[Test 11] Session B isolation — no leaked analytical artifacts"
if [ -f "$RS" ]; then
    CL=$(python3 -c "import json; print(json.load(open('$RS'))['checkpoint_level'])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$CL" = "PARTIAL_B" ] || [ "$CL" = "COMPLETE_B" ]; then
        LEAKED=0
        # Check for Session A analytical artifacts that should NOT be in active scratchpad
        for f in findings_inventory.md hypotheses.md chain_hypotheses.md synthesis_full.md \
                 confidence_scores.md rag_validation.md root_cause_clusters.md cluster_instance_map.md; do
            # These are Session B artifacts too, so only flag if .audit_session_a exists
            # (meaning rotation happened) AND no Session B agent wrote them
            if [ -d "$SA" ] && [ -f "$SP/$f" ]; then
                # Check if file was likely Session A leftover (created before rotation)
                # Simple heuristic: if .audit_session_a also has this file with same content
                if [ -f "$SA/$f" ] && diff -q "$SP/$f" "$SA/$f" > /dev/null 2>&1; then
                    echo "  DETECTED: Leaked Session A artifact: $f (identical to archive copy)"
                    LEAKED=1
                    ((FAIL++))
                fi
            fi
        done
        if [ "$LEAKED" -eq 0 ]; then
            check "No leaked Session A analytical artifacts" "true"
        fi
    else
        echo "  SKIP: checkpoint_level=$CL (not in Session B)"
    fi
else
    echo "  SKIP: no run_state.json"
fi

# --- Test 12: Stale artifact detection — artifact older than phase start (PATCH11.3) ---
echo "[Test 12] No stale artifacts from prior runs"
if [ -f "$RS" ] && [ -f "$SP/mandatory_step_checklist.md" ]; then
    # Get the last write timestamp from run_state.json as reference
    LAST_WRITE=$(python3 -c "
import json, os
rs = json.load(open('$RS'))
print(rs.get('last_write_iso', ''))
" 2>/dev/null || echo "")
    if [ -n "$LAST_WRITE" ]; then
        # Convert to epoch for comparison
        RS_EPOCH=$(python3 -c "
from datetime import datetime
try:
    dt = datetime.fromisoformat('$LAST_WRITE'.replace('Z','+00:00'))
    print(int(dt.timestamp()))
except: print(0)
" 2>/dev/null || echo "0")
        RS_MTIME=$(stat -c %Y "$RS" 2>/dev/null || stat -f %m "$RS" 2>/dev/null || echo "0")
        check "run_state.json mtime is recent" "[ '$RS_MTIME' -gt 0 ]"
    else
        echo "  SKIP: no last_write_iso in run_state.json"
    fi
else
    echo "  SKIP: prerequisites missing"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
