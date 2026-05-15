#!/bin/bash
# Valves Methodology Injection — copies phase-targeted files to scratchpad
# Usage: ~/.valves/adapter/inject_methodology.sh <scratchpad_path>

set -euo pipefail

SCRATCHPAD="${1:?Usage: inject_methodology.sh <scratchpad_path>}"
METH_DIR="$HOME/.valves/methodology"
TARGET="$SCRATCHPAD/_valves_methodology"

if [ ! -d "$METH_DIR" ]; then
    echo "ERROR: Methodology directory not found: $METH_DIR"
    exit 1
fi

mkdir -p "$TARGET"

LAYER3_FILES=(
    "pattern-integration.md"
    "seed-methodology.md"
    "confidence-scoring-overlay.md"
    "ev-ranking.md"
    "attack-thesis-methodology.md"
    "session-b-doctrine.md"
    "negative-results-methodology.md"
    "coverage-density.md"
    "cross-session-consensus.md"
    "attribution-methodology.md"
    "bug-class-registry.md"
    "bug-class-propagation.md"
    "report-quality.md"
    "admin-setter-validation.md"
    "symmetric-pairs.md"
    "system-breakpoints.md"
    "historical-prime.md"
    "economic-incentive-audit.md"
    "external-protocol-limits.md"
    "external-state-mutability.md"
    "correctness-winner.md"
    "reference-diff-audit.md"
    "prompt-injection-guard.md"
    "attacker-objective-matrix.md"
    "exploit-composition.md"
    "pattern-candidate-schema.md"
    "exploit-attempt-logging.md"
)

COPIED=0
SKIPPED=0

for f in "${LAYER3_FILES[@]}"; do
    src="$METH_DIR/$f"
    if [ -f "$src" ] || [ -L "$src" ]; then
        cp -L "$src" "$TARGET/$f"
        COPIED=$((COPIED + 1))
    else
        echo "WARN: Missing methodology file: $f"
        SKIPPED=$((SKIPPED + 1))
    fi
done

cat > "$TARGET/README.md" << 'HEREDOC'
# Valves Methodology (Injected)

Phase-targeted methodology files for Valves overlay on Plamen V2.
See ~/.valves/phase-map.md for which files to read per phase.

Layer 2 (always loaded via ~/.claude/rules/): doctrine, proof-discipline, exploit-preservation.
Layer 3 (this directory): phase-specific methodology read on demand.
HEREDOC

echo "Injected $COPIED methodology files to $TARGET ($SKIPPED skipped)"
