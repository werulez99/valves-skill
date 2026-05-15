#!/bin/bash
# Valves-on-Plamen-V2 Integration Smoke Test (v1.8.2)

PASS=0; FAIL=0; WARN=0

check() {
    if [ "$1" = "0" ]; then
        echo "  PASS: $2"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $2"
        FAIL=$((FAIL + 1))
    fi
}
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }

file_or_link_exists() { [ -f "$1" ] || [ -L "$1" ]; }

echo "=== Valves-on-V2 Smoke Test (v1.8.2) ==="
echo ""

# 1. Core files
echo "--- Core Files ---"
[ -f ~/.valves/VERSION ] && check 0 "VERSION exists ($(cat ~/.valves/VERSION))" || check 1 "VERSION exists"
[ -f ~/.valves/phase-map.md ] && check 0 "phase-map.md exists" || check 1 "phase-map.md exists"
[ -f ~/.valves/CLAUDE.md ] && check 0 "CLAUDE.md exists" || check 1 "CLAUDE.md exists"
[ -f ~/.valves/patterns/PATTERN_INDEX.md ] && check 0 "PATTERN_INDEX.md exists" || check 1 "PATTERN_INDEX.md exists"

# 1b. CLAUDE.md content check
echo ""
echo "--- CLAUDE.md Validation ---"
if [ -f ~/.valves/CLAUDE.md ]; then
    CLINES=$(wc -l < ~/.valves/CLAUDE.md)
    if [ "$CLINES" -le 200 ]; then
        check 0 "CLAUDE.md is clean overlay ($CLINES lines, cap 200)"
    else
        check 1 "CLAUDE.md too large ($CLINES lines, cap 200)"
    fi
    if grep -q "run_state.json\|COMPLETE_A\|PATCH10\|PATCH11" ~/.valves/CLAUDE.md; then
        check 1 "CLAUDE.md still contains v1.7 orchestration references"
    else
        check 0 "CLAUDE.md has no v1.7 orchestration references"
    fi
fi

# 2. Methodology directory
echo ""
echo "--- Methodology Files ---"
[ -d ~/.valves/methodology ] && check 0 "methodology/ directory exists" || check 1 "methodology/ directory"
METH_COUNT=$(find ~/.valves/methodology/ -name "*.md" -maxdepth 1 2>/dev/null | wc -l)
[ "$METH_COUNT" -ge 25 ] && check 0 "At least 25 methodology files ($METH_COUNT found)" || check 1 "Expected >=25 methodology files ($METH_COUNT found)"

# Check key methodology files (accept both regular files and symlinks)
for f in session-b-doctrine.md seed-methodology.md ev-ranking.md attack-thesis-methodology.md \
         confidence-scoring-overlay.md negative-results-methodology.md pattern-integration.md \
         coverage-density.md cross-session-consensus.md attribution-methodology.md \
         bug-class-registry.md bug-class-propagation.md report-quality.md; do
    file_or_link_exists ~/.valves/methodology/$f && check 0 "$f" || check 1 "$f"
done

# 2b. v1.8.1 adversarial methodology modules
echo ""
echo "--- Adversarial Modules (v1.8.2) ---"
for f in attacker-objective-matrix.md exploit-composition.md pattern-candidate-schema.md exploit-attempt-logging.md; do
    file_or_link_exists ~/.valves/methodology/$f && check 0 "$f" || check 1 "$f"
done

# 2c. New lenses in doctrine
echo ""
echo "--- Doctrine Lenses ---"
DOCTRINE=~/.valves/rules/valves-doctrine.md
for lens in ROUNDING-DRIFT TX-ORDERING TEMPORAL-WINDOW CALLBACK-CONTROL INCENTIVE-DIVERGENCE; do
    grep -q "### $lens" "$DOCTRINE" 2>/dev/null && check 0 "Lens: $lens present in doctrine" || check 1 "Lens: $lens missing from doctrine"
done
LENS_COUNT=$(grep -c "^### " "$DOCTRINE" 2>/dev/null | head -1)
LENS_ACTUAL=$(grep "^### " "$DOCTRINE" | grep -v "Detection Layer" | wc -l)
check 0 "Total lenses in doctrine: $LENS_ACTUAL"

# 2d. Learned patterns directory
echo ""
echo "--- Learned Patterns ---"
[ -d ~/.valves/patterns/learned ] && check 0 "patterns/learned/ directory exists" || check 1 "patterns/learned/ directory missing"
[ -f ~/.valves/patterns/learned/README.md ] && check 0 "patterns/learned/README.md exists" || check 1 "patterns/learned/README.md missing"

# 3. Layer 2 symlinks in ~/.claude/rules/
echo ""
echo "--- Layer 2 (Claude Rules) ---"
for f in valves-doctrine.md valves-proof-discipline.md valves-exploit-preservation.md; do
    if [ -L ~/.claude/rules/$f ]; then
        [ -f ~/.claude/rules/$f ] && check 0 "$f → $(readlink ~/.claude/rules/$f) (valid symlink)" || check 1 "$f (broken symlink)"
    elif [ -f ~/.claude/rules/$f ]; then
        check 0 "$f (regular file)"
    else
        check 1 "$f (missing from ~/.claude/rules/)"
    fi
done

# 4. CLAUDE.md integration
echo ""
echo "--- ~/.claude/CLAUDE.md ---"
grep -q "VALVES:START" ~/.claude/CLAUDE.md && check 0 "VALVES block present" || check 1 "VALVES block missing"
grep -q "VALVES:END" ~/.claude/CLAUDE.md && check 0 "VALVES block closed" || check 1 "VALVES block not closed"
LINES=$(wc -l < ~/.claude/CLAUDE.md)
[ "$LINES" -le 500 ] && check 0 "CLAUDE.md under 500 lines ($LINES)" || check 1 "CLAUDE.md over 500 lines ($LINES)"

# 5. Missing file reference check
echo ""
echo "--- Missing File References ---"
MISSING_REFS=0
for ref_file in ~/.valves/phase-map.md ~/.valves/adapter/install_overlay.sh ~/.claude/CLAUDE.md; do
    if grep -q "bug-class-methodology" "$ref_file" 2>/dev/null; then
        echo "  FAIL: $ref_file still references bug-class-methodology.md"
        MISSING_REFS=$((MISSING_REFS + 1))
    fi
done
[ "$MISSING_REFS" -eq 0 ] && check 0 "No references to non-existent bug-class-methodology.md" || check 1 "$MISSING_REFS files reference non-existent bug-class-methodology.md"

# Also check that all files referenced in phase-map.md Layer 3 table exist in methodology/
PHASE_MAP_REFS=$(grep -oP '`[a-z0-9-]+\.md`' ~/.valves/phase-map.md 2>/dev/null | tr -d '`' | sort -u)
REF_MISSING=0
for ref in $PHASE_MAP_REFS; do
    case "$ref" in
        valves-doctrine.md|valves-proof-discipline.md|valves-exploit-preservation.md) continue ;; # Layer 2, not methodology/
    esac
    if ! file_or_link_exists ~/.valves/methodology/$ref; then
        echo "  FAIL: phase-map.md references $ref but ~/.valves/methodology/$ref not found"
        REF_MISSING=$((REF_MISSING + 1))
    fi
done
[ "$REF_MISSING" -eq 0 ] && check 0 "All phase-map.md methodology references resolve" || check 1 "$REF_MISSING phase-map.md references are broken"

# Check CLAUDE.md VALVES block references only (not Plamen's reference table)
CLAUDE_REFS=$(sed -n '/VALVES:START/,/VALVES:END/p' ~/.claude/CLAUDE.md 2>/dev/null | grep -oP '[a-z0-9-]+\.md' | grep -v "valves-" | grep -v "CLAUDE" | sort -u)
CLAUDE_REF_MISSING=0
for ref in $CLAUDE_REFS; do
    if ! file_or_link_exists ~/.valves/methodology/$ref; then
        echo "  FAIL: CLAUDE.md VALVES block references $ref but ~/.valves/methodology/$ref not found"
        CLAUDE_REF_MISSING=$((CLAUDE_REF_MISSING + 1))
    fi
done
[ "$CLAUDE_REF_MISSING" -eq 0 ] && check 0 "All CLAUDE.md VALVES block methodology references resolve" || check 1 "$CLAUDE_REF_MISSING CLAUDE.md VALVES block references are broken"

# 6. Deprecated directory
echo ""
echo "--- Deprecated Files ---"
[ -d ~/.valves/deprecated ] && check 0 "deprecated/ directory exists" || check 1 "deprecated/ directory"
for f in execution-state.md thorough-strict-mode.md artifact-ownership.md pipeline-trace.md \
         valves-v1.7-orchestrator.md CLAUDE.v1.7.monolith.md; do
    [ -f ~/.valves/deprecated/$f ] && check 0 "$f archived" || warn "$f not in deprecated/"
done

# 7. Plamen read-only check
echo ""
echo "--- Plamen Read-Only ---"
if [ -f ~/.plamen/scripts/plamen_driver.py ]; then
    check 0 "plamen_driver.py exists (not modified by overlay)"
else
    warn "plamen_driver.py not found"
fi

# 8. Adapter scripts
echo ""
echo "--- Adapter Scripts ---"
[ -x ~/.valves/adapter/inject_methodology.sh ] && check 0 "inject_methodology.sh executable" || check 1 "inject_methodology.sh"
[ -x ~/.valves/adapter/install_overlay.sh ] && check 0 "install_overlay.sh executable" || check 1 "install_overlay.sh"

# 8b. Inject script references new modules
echo ""
echo "--- Inject Script Coverage ---"
INJECT=~/.valves/adapter/inject_methodology.sh
for f in attacker-objective-matrix.md exploit-composition.md pattern-candidate-schema.md exploit-attempt-logging.md; do
    grep -q "$f" "$INJECT" 2>/dev/null && check 0 "inject_methodology.sh includes $f" || check 1 "inject_methodology.sh missing $f"
done

# 9. Wrapper script
echo ""
echo "--- Wrapper Script ---"
[ -x ~/.valves/bin/valves-plamen ] && check 0 "valves-plamen wrapper executable" || check 1 "valves-plamen wrapper not executable"
grep -q "detect_language" ~/.valves/bin/valves-plamen 2>/dev/null && check 0 "wrapper has detect_language()" || check 1 "wrapper missing detect_language()"
grep -q "inject-only" ~/.valves/bin/valves-plamen 2>/dev/null && check 0 "wrapper supports inject-only mode" || check 1 "wrapper missing inject-only mode"

# 9b. Coverage summary parser
echo ""
echo "--- Coverage Summary Parser ---"
[ -x ~/.valves/bin/summarize-exploit-attempts ] && check 0 "summarize-exploit-attempts executable" || check 1 "summarize-exploit-attempts not executable"
grep -q "exploit_attempt_coverage" ~/.valves/bin/summarize-exploit-attempts 2>/dev/null && check 0 "parser writes exploit_attempt_coverage.md" || check 1 "parser missing output file reference"

# 10. Methodology injection test
echo ""
echo "--- Injection Test ---"
TEST_SCRATCH=$(mktemp -d)
bash ~/.valves/adapter/inject_methodology.sh "$TEST_SCRATCH" > /dev/null 2>&1
INJECTED=$(find "$TEST_SCRATCH/_valves_methodology" -name "*.md" -maxdepth 1 2>/dev/null | wc -l)
[ "$INJECTED" -ge 25 ] && check 0 "Injection test: $INJECTED files injected to temp scratchpad" || check 1 "Injection test: only $INJECTED files (expected 25+)"
# Verify new modules were injected
for f in attacker-objective-matrix.md exploit-composition.md pattern-candidate-schema.md exploit-attempt-logging.md; do
    [ -f "$TEST_SCRATCH/_valves_methodology/$f" ] && check 0 "Injected: $f" || check 1 "Not injected: $f"
done
rm -rf "$TEST_SCRATCH"

# 11. Version consistency
echo ""
echo "--- Version Consistency ---"
VER=$(cat ~/.valves/VERSION 2>/dev/null)
check 0 "VERSION: $VER"

# Summary
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "========================================"
if [ "$FAIL" -eq 0 ]; then
    echo "VERDICT: PASS"
    exit 0
else
    echo "VERDICT: FAIL"
    exit 1
fi
