# Valves Migration Report: v1.7.0-PATCH12 to v1.8.0

**Date**: 2026-05-14 (fix1 applied same day)
**Scope**: Migrate Valves overlay from monolithic V1 orchestrator to Plamen V2 subprocess architecture
**Status**: Complete (fix1 applied)

---

## Overview

Valves v1.7.0 operated as a monolithic 5,443-line orchestrator (`valves.md`) that ran inside a single Claude Code conversation. Plamen V2 replaced the single-conversation model with a Python-driven subprocess architecture (`plamen_driver.py`) that executes one phase per `claude -p` invocation, with automatic checkpointing and crash recovery.

This migration restructures Valves from an orchestrator replacement into a methodology overlay that injects into Plamen V2 phases. The monolithic orchestrator is deprecated. Valves methodology is preserved in full and delivered to agents through a three-layer injection system: always-loaded rules (Layer 2, via `~/.claude/rules/` symlinks), per-phase methodology files (Layer 3, via `~/.valves/methodology/`), and the existing pattern library (Layer 4, unchanged).

---

## Changes Summary

### Created (~3,400 lines)

| Component | Files | Lines | Description |
|-----------|-------|-------|-------------|
| `~/.valves/methodology/` | 26 (10 extracted, 16 symlinked) | 3,089 | Phase-injectable methodology modules |
| `~/.valves/adapter/` | 3 scripts | 269 | `inject_methodology.sh`, `install_overlay.sh`, `smoke_test.sh` |
| `~/.valves/phase-map.md` | 1 | 43 | Maps Plamen V2 phases to Valves methodology files |
| `~/.valves/deprecated/` | 5 | 6,517 | Archived V1 artifacts (see Deprecated section) |
| `~/.claude/rules/` symlinks | 3 new | -- | `valves-doctrine.md`, `valves-proof-discipline.md`, `valves-exploit-preservation.md` |

### Modified

| File | Before | After | Change |
|------|--------|-------|--------|
| `~/.claude/CLAUDE.md` | 46 lines | 71 lines | Appended VALVES integration block |
| `~/.valves/commands/valves.md` | 5,443 lines | 58 lines | Replaced orchestrator with info-only redirect to `/plamen` |

### Deprecated (moved to `~/.valves/deprecated/`)

| File | Lines | Replacement |
|------|-------|-------------|
| `valves-v1.7-orchestrator.md` | 5,443 | Plamen V2 `plamen_driver.py` + phase-map injection |
| `execution-state.md` | 502 | V2 `pipeline_checkpoint.md` (automatic per-phase) |
| `thorough-strict-mode.md` | 337 | V2 phase validators + `VALIDATE_STEP_COMPLETION()` |
| `artifact-ownership.md` | 149 | V2 artifact gates (per-phase output contracts) |
| `pipeline-trace.md` | 86 | V2 checkpoint + `adaptive_loop_log.md` |

### Unchanged

| Component | Files | Lines | Notes |
|-----------|-------|-------|-------|
| `~/.valves/rules/` | 33 | 4,809 | All methodology rules preserved |
| `~/.valves/patterns/` | 21 dirs | 642 patterns | Solodit (562) + Cantina (80) pattern library |
| `~/.valves/state/` | 6 | -- | Bug class calibration, negative results archive |
| `~/.valves/references/` | 1 | -- | MANIFEST.md |

### Net Delta

- Removed: ~6,962 lines (monolithic orchestrator + 4 deprecated state-tracking files + v1.7 CLAUDE.md monolith)
- Added: ~3,550 lines (methodology modules + adapter scripts + phase-map + docs + wrapper)
- Net reduction: **~3,400 lines**

---

## Fix1 Changes (same day)

| Change | Description |
|--------|-------------|
| `~/.valves/CLAUDE.md` replaced | 445-line v1.7 monolith → ~150-line v1.8 overlay doc |
| `bug-class-methodology.md` refs fixed | 3 locations updated to reference `bug-class-registry.md` + `bug-class-propagation.md` |
| `~/.valves/bin/valves-plamen` created | Auto-inject wrapper for Plamen V2 |
| `smoke_test.sh` expanded | Accepts symlinks+files, checks v1.8 CLAUDE.md, missing refs, injection test, version consistency |
| Codex status clarified | Claude backend validated; Codex backend unvalidated (needs `~/.valves/` path wiring) |
| Design doc updated | Added wrapper, Codex constraint, fix1 version |
| Old CLAUDE.md archived | `~/.valves/deprecated/CLAUDE.v1.7.monolith.md` |

---

## v1.8.1 Changes (Adversarial Methodology Expansion)

| Change | Description |
|--------|-------------|
| `valves-doctrine.md` expanded | 250 → 322 lines. Added 5 heuristic lenses: ROUNDING-DRIFT, TX-ORDERING, TEMPORAL-WINDOW, CALLBACK-CONTROL, INCENTIVE-DIVERGENCE. Version bumped to v1.8-PATCH1. |
| `attacker-objective-matrix.md` created | 108 lines. 14 attacker objectives × 15 actor capabilities. Goal-directed framing for breadth, depth, and chain phases. |
| `exploit-composition.md` created | 168 lines. 6-step multi-signal composition protocol. 5 composition patterns. Enriches Phase 4c chain analysis. |
| `pattern-candidate-schema.md` created | 89 lines. Post-audit learned-pattern proposal format. Anti-anchoring: agents propose, never promote. |
| `patterns/learned/` created | Empty directory with README. Curator-approved patterns promoted post-audit. |
| `PATTERN_INDEX.md` updated | Added Learned Patterns section with promotion rules summary. |
| `inject_methodology.sh` updated | 23 → 26 Layer 3 files (added 3 adversarial modules). |
| `smoke_test.sh` rewritten | v1.8.1 comprehensive validation: adversarial modules, doctrine lenses, learned patterns, inject coverage, reference resolution, wrapper checks. |
| `phase-map.md` updated | Added matrix to breadth/depth rows, composer+matrix to chain row. |
| `~/.claude/CLAUDE.md` updated | Phase table adds matrix (breadth, depth, chain) and composer (chain). |
| `VERSION` bumped | 1.8.0 → 1.8.1 |

**v1.8.1 delta**: +365 lines methodology (3 new modules), +72 lines doctrine (5 lenses), smoke test rewritten. Net: ~+500 lines.

---

## Architecture

```
Before (v1.7.0):
  Claude Code session -> valves.md (5,443-line orchestrator) -> agents

After (v1.8.0):
  plamen_driver.py -> claude -p (per phase) -> Plamen V2 phase prompt
                                                  + Layer 2: ~/.claude/rules/valves-*.md (always loaded)
                                                  + Layer 3: methodology/*.md (injected per phase)
                                                  + Layer 4: patterns/ (unchanged)
```

Layer 2 (3 symlinks in `~/.claude/rules/`) loads automatically in every subprocess. Layer 3 methodology files are injected into the agent scratchpad by `inject_methodology.sh` at phase boundaries, guided by `phase-map.md`. Layer 4 pattern integration is unchanged.

---

## Backward Compatibility

- `/valves` command remains functional as an info-only status/help redirect (58 lines).
- All 33 rules files and 642 patterns are unchanged and fully operational.
- Audit runs now use `/plamen` (which loads Valves overlay automatically via CLAUDE.md).
- Existing scratchpad artifacts from prior audits are not affected.

---

## Rollback Procedure

A complete pre-migration backup exists at `~/.valves.bak.pre-v2-integration/`.

To rollback:

```bash
# 1. Remove new components
rm -rf ~/.valves/methodology/ ~/.valves/adapter/ ~/.valves/deprecated/ ~/.valves/phase-map.md

# 2. Restore from backup
cp -r ~/.valves.bak.pre-v2-integration/* ~/.valves/

# 3. Remove Layer 2 symlinks added in v1.8.0
rm ~/.claude/rules/valves-doctrine.md
rm ~/.claude/rules/valves-proof-discipline.md
rm ~/.claude/rules/valves-exploit-preservation.md

# 4. Restore original CLAUDE.md
cp ~/.valves.bak.pre-v2-integration/CLAUDE.md ~/.claude/CLAUDE.md
```

---

## Smoke Test Results

All 38 structural validation checks passed:

| Category | Checks | Result |
|----------|--------|--------|
| Methodology files exist and are readable | 10 | PASS |
| Symlinks resolve to valid targets | 16 | PASS |
| Adapter scripts are executable | 3 | PASS |
| Phase-map references valid methodology files | 3 | PASS |
| Deprecated files archived with correct line counts | 5 | PASS |
| CLAUDE.md contains VALVES block | 1 | PASS |
| **Total** | **38** | **38/38 PASS** |

---

## Version

```
v1.7.0-PATCH12 -> v1.8.0 -> v1.8.1
```
