#!/bin/bash
# Valves Overlay Installer — one-time setup for Valves-on-Plamen-V2
# Creates symlinks in ~/.claude/rules/ and adds VALVES block to CLAUDE.md

set -euo pipefail

CLAUDE_RULES="$HOME/.claude/rules"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
VALVES_RULES="$HOME/.valves/rules"

echo "=== Valves Overlay Installer ==="

# Step 1: Create symlinks
echo "--- Creating symlinks in $CLAUDE_RULES ---"

ln -sf "$VALVES_RULES/valves-doctrine.md" "$CLAUDE_RULES/valves-doctrine.md"
echo "  Created: valves-doctrine.md"

ln -sf "$VALVES_RULES/cleared-proof-discipline.md" "$CLAUDE_RULES/valves-proof-discipline.md"
echo "  Created: valves-proof-discipline.md"

ln -sf "$VALVES_RULES/strongest-exploit-preservation.md" "$CLAUDE_RULES/valves-exploit-preservation.md"
echo "  Created: valves-exploit-preservation.md"

# Step 2: Add VALVES block to CLAUDE.md (if not already present)
echo "--- Updating CLAUDE.md ---"

if grep -q "VALVES:START" "$CLAUDE_MD"; then
    echo "  VALVES block already present in CLAUDE.md — skipping"
else
    cat >> "$CLAUDE_MD" << 'VALVESBLOCK'

<!-- VALVES:START — managed by valves overlay, do not edit -->
## Valves Methodology Overlay (v1.8.0)

Always-loaded (via ~/.claude/rules/): doctrine, proof-discipline, exploit-preservation.

### Phase-Targeted Methodology
When `{SCRATCHPAD}/_valves_methodology/` exists, Read listed files at phase start:

| Phase Pattern | Scratchpad Files |
|---------------|-----------------|
| recon | pattern-integration.md |
| breadth, rescan* | pattern-integration.md |
| depth, attention* | seed-methodology.md, confidence-scoring-overlay.md |
| inventory*, dedup | bug-class-registry.md, bug-class-propagation.md |
| chain* | ev-ranking.md, attack-thesis-methodology.md |
| verify*, sc_verify* | ev-ranking.md |
| skeptic | (Layer 2 sufficient) |
| report* | report-quality.md |
| crossbatch | cross-session-consensus.md |

### Pattern Library
Index: `~/.valves/patterns/PATTERN_INDEX.md`. Breadth/depth agents Read relevant
cluster files. Anti-anchoring: patterns inform WHAT to look for, not WHAT to find.
<!-- VALVES:END -->
VALVESBLOCK
    echo "  Appended VALVES block to CLAUDE.md"
fi

# Step 3: Verify
LINES=$(wc -l < "$CLAUDE_MD")
echo "--- Verification ---"
echo "  CLAUDE.md: $LINES lines (cap: 500)"

if [ "$LINES" -gt 500 ]; then
    echo "  WARNING: CLAUDE.md exceeds 500-line cap!"
fi

# Step 4: Run smoke test
echo ""
echo "--- Running smoke test ---"
SMOKE="$HOME/.valves/adapter/smoke_test.sh"
if [ -x "$SMOKE" ]; then
    bash "$SMOKE"
else
    echo "  Smoke test not found or not executable: $SMOKE"
fi
