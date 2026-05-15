#!/bin/bash
# Valves v1.8.3 Installer
# Installs the Valves methodology overlay for Plamen V2.
#
# Prerequisites: Plamen V2 installed at ~/.plamen/
# Usage: git clone https://github.com/werulez99/valves-skill && cd valves-skill && ./install.sh

set -euo pipefail

VALVES_HOME="$HOME/.valves"
CLAUDE_RULES="$HOME/.claude/rules"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

die()  { echo "ERROR: $1" >&2; exit 1; }
info() { echo "  + $1"; }

echo "=== Valves v1.8.3 Installer ==="
echo ""

[ -f "$HOME/.plamen/scripts/plamen_driver.py" ] || die "Plamen V2 not found at ~/.plamen/. Install Plamen V2 first."

if [ -d "$VALVES_HOME" ]; then
    BACKUP="$VALVES_HOME.bak.$(date +%Y%m%d-%H%M%S)"
    echo "Existing ~/.valves/ found — backing up to $BACKUP"
    cp -r "$VALVES_HOME" "$BACKUP"
fi

echo "Installing Valves files..."
mkdir -p "$VALVES_HOME"
rsync -a --delete valves/ "$VALVES_HOME/"
chmod +x "$VALVES_HOME/adapter/inject_methodology.sh"
chmod +x "$VALVES_HOME/adapter/install_overlay.sh"
chmod +x "$VALVES_HOME/adapter/smoke_test.sh"
chmod +x "$VALVES_HOME/bin/valves-plamen"
chmod +x "$VALVES_HOME/bin/summarize-exploit-attempts"
info "Valves tree installed to $VALVES_HOME"

echo "Installing Layer 2 rules..."
mkdir -p "$CLAUDE_RULES"
ln -sf "$VALVES_HOME/rules/valves-doctrine.md" "$CLAUDE_RULES/valves-doctrine.md"
ln -sf "$VALVES_HOME/rules/cleared-proof-discipline.md" "$CLAUDE_RULES/valves-proof-discipline.md"
ln -sf "$VALVES_HOME/rules/strongest-exploit-preservation.md" "$CLAUDE_RULES/valves-exploit-preservation.md"
info "3 Layer 2 symlinks created in $CLAUDE_RULES"

echo "Installing Layer 1 phase router..."
mkdir -p "$(dirname "$CLAUDE_MD")"
touch "$CLAUDE_MD"

if grep -q "VALVES:START" "$CLAUDE_MD" 2>/dev/null; then
    info "VALVES block already present in CLAUDE.md (skipped)"
else
    cat >> "$CLAUDE_MD" << 'VALVESBLOCK'

<!-- VALVES:START — managed by valves overlay, do not edit -->
## Valves Methodology Overlay (v1.8.3)

Always-loaded (via ~/.claude/rules/): doctrine, proof-discipline, exploit-preservation.

### Phase-Targeted Methodology
When `{SCRATCHPAD}/_valves_methodology/` exists, Read listed files at phase start:

| Phase Pattern | Scratchpad Files |
|---------------|-----------------|
| recon | pattern-integration.md |
| breadth, rescan* | pattern-integration.md, attacker-objective-matrix.md, exploit-attempt-logging.md |
| depth, attention* | seed-methodology.md, confidence-scoring-overlay.md, attacker-objective-matrix.md, exploit-attempt-logging.md |
| inventory*, dedup | bug-class-registry.md, bug-class-propagation.md |
| chain* | ev-ranking.md, attack-thesis-methodology.md, exploit-composition.md, attacker-objective-matrix.md |
| verify*, sc_verify* | ev-ranking.md |
| skeptic | (Layer 2 sufficient) |
| report* | report-quality.md |
| crossbatch | cross-session-consensus.md |

### Pattern Library
Index: `~/.valves/patterns/PATTERN_INDEX.md`. Breadth/depth agents Read relevant
cluster files. Anti-anchoring: patterns inform WHAT to look for, not WHAT to find.
<!-- VALVES:END -->
VALVESBLOCK
    info "VALVES block appended to $CLAUDE_MD"
fi

echo ""
echo "Running smoke test..."
echo ""
if bash "$VALVES_HOME/adapter/smoke_test.sh"; then
    echo ""
    echo "=== Installation Complete ==="
    echo ""
    echo "Usage:"
    echo "  cd <your-project>"
    echo "  ~/.valves/bin/valves-plamen core    # start an audit"
    echo "  ~/.valves/bin/valves-plamen resume   # resume interrupted audit"
else
    echo ""
    echo "WARNING: Smoke test had failures — check output above."
fi
