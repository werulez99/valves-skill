---
description: "Valves methodology status and info (v1.8.1). Audit runs use /plamen with Valves overlay."
---

# Valves Methodology Overlay — v1.8.1

Valves v1.8.1 methodology is active as an overlay on Plamen V2.
Orchestration has been retired — Plamen V2's Python driver handles phase routing, checkpointing, and artifact gates.

## Status

Read `~/.valves/VERSION` for current version.

### Integration Check
1. `~/.claude/rules/valves-doctrine.md` — Layer 2 symlink (always loaded)
2. `~/.claude/rules/valves-proof-discipline.md` — Layer 2 symlink (always loaded)
3. `~/.claude/rules/valves-exploit-preservation.md` — Layer 2 symlink (always loaded)
4. `~/.claude/CLAUDE.md` — contains `<!-- VALVES:START -->` block
5. `~/.valves/methodology/` — 29 methodology files (includes 3 adversarial modules added in v1.8.1)
6. `~/.valves/patterns/` — 642 patterns (562 Solodit + 80 Cantina)

### Quick Validation
```bash
bash ~/.valves/adapter/smoke_test.sh
```

## To Run an Audit

```bash
# Start a fresh audit (auto-detects language, injects methodology, launches driver):
~/.valves/bin/valves-plamen core

# Resume an interrupted audit:
~/.valves/bin/valves-plamen resume

# Inject methodology only (then use /plamen-wizard or /plamen in Claude Code):
~/.valves/bin/valves-plamen inject-only

# Show status and next steps:
~/.valves/bin/valves-plamen
```

Modes: `light` | `core` | `thorough`

For docs/scope/proven-only options, use `/plamen-wizard` inside Claude Code instead.

Valves methodology is delivered via:
- **Layer 2**: 3 core rules auto-loaded into every V2 subprocess
- **Layer 3**: Phase-targeted methodology injected to scratchpad

## Architecture

See `~/.valves/phase-map.md` for the complete V2 phase → Valves methodology mapping.
See `~/.valves/VALVES_ON_PLAMEN_V2_DESIGN.md` for the integration architecture.

## Methodology Files

| Directory | Content | Count |
|-----------|---------|-------|
| `~/.valves/methodology/` | Extracted pure methodology + adversarial modules | 29 files |
| `~/.valves/patterns/` | Vulnerability pattern library | 33 files (642 patterns) |
| `~/.valves/rules/` | Original rules (preserved for reference) | 33 files |

## Deprecated (v1.7 → v1.8)

The following have been retired (archived in `~/.valves/deprecated/`):
- `valves-v1.7-orchestrator.md` — Original 5,443-line monolithic orchestrator
- `execution-state.md` — run_state.json state machine (V2 checkpoint replaces)
- `thorough-strict-mode.md` — Checklist row enforcement (V2 validators replace)
- `artifact-ownership.md` — Phase 0.9 artifact gates (V2 artifact gates replace)
- `pipeline-trace.md` — Pipeline trace logging (V2 checkpoint replaces)
