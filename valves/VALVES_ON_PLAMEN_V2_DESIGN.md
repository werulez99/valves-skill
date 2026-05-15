# Valves-on-Plamen-V2 Architecture

Version: 1.8.1 | Date: 2026-05-14

## 1. Overview & Goals

Valves was a 5,443-line monolithic LLM orchestrator that managed audit phases, state machines, and artifact gates alongside its analytical methodology. Plamen V2 replaced the orchestration layer with a Python driver (~6K lines, ~47 phases) that owns phase routing, checkpoint/resume, crash recovery, artifact gates, and rate-limit handling.

Valves v1.8.0 retains its analytical methodology as a passive overlay on Plamen V2. The restructuring achieves three goals:

1. **No dual orchestration** -- V2's Python driver is the single phase authority.
2. **No monolithic prompt** -- methodology is split across 3 injection layers.
3. **No Plamen modification** -- `~/.plamen/` is untouched; Valves injects via `~/.claude/` and scratchpad.

## 2. Architecture: 3-Layer Injection

### Layer 1 -- CLAUDE.md Phase Router (25 lines)

Location: `~/.claude/CLAUDE.md` inside `<!-- VALVES:START -->` / `<!-- VALVES:END -->` markers.

Maps V2 phase names to scratchpad methodology files via a lookup table. Every V2 subprocess reads CLAUDE.md on spawn, so this table is universally visible. Contains no methodology -- only routing instructions.

### Layer 2 -- Always-Loaded Rules (446 lines, 3 files)

Symlinks in `~/.claude/rules/` pointing to `~/.valves/rules/`:

| Symlink | Source | Lines | Content |
|---------|--------|-------|---------|
| `valves-doctrine.md` | `valves-doctrine.md` | 322 | Adversarial questions, decision lenses, 13 heuristic lenses |
| `valves-proof-discipline.md` | `cleared-proof-discipline.md` | 90 | CLEARED proof requirements, evidence standards |
| `valves-exploit-preservation.md` | `strongest-exploit-preservation.md` | 106 | Anti-overcompression, strongest-exploit preservation |

These load into every `claude -p` subprocess automatically. They carry the core analytical posture: recall-biased discovery (Session A), adversarial precision (Session B), and proof rigor (always).

### Layer 3 -- Phase-Targeted Methodology (26 files, ~3.4K lines)

Injected to `{SCRATCHPAD}/_valves_methodology/` by `inject_methodology.sh` before the audit starts. V2 subprocesses read specific files based on the Layer 1 phase table. Files are only read when relevant -- a verification agent never reads seed-methodology.md.

## 3. Component Map

```
~/.valves/                          # Valves root
  VERSION                           # 1.8.1
  CLAUDE.md                         # Overlay doc (~150 lines, replaces v1.7 monolith)
  phase-map.md                      # V2 phase -> methodology mapping reference
  VALVES_ON_PLAMEN_V2_DESIGN.md     # This document
  methodology/                      # 29 files, ~3.4K lines -- extracted pure methodology
  patterns/                         # 21 files + cantina/ (14 files) = 642 patterns + learned/
    PATTERN_INDEX.md                #   ~175-line index for agent cluster selection
    learned/                        #   Curator-approved patterns (empty at v1.8.1)
  rules/                            # 33 original rule files (preserved, Layer 2 sources)
  adapter/                          # 3 scripts
    install_overlay.sh              #   One-time Layer 1+2 setup
    inject_methodology.sh           #   Per-audit Layer 3 injection
    smoke_test.sh                   #   Integration validation (expanded in fix1)
  bin/                              # Wrapper scripts
    valves-plamen                   #   Auto-inject + launch Plamen V2
  commands/valves.md                # Info-only skill file
  deprecated/                       # 6 archived orchestration files
  references/                       # Reference material
  state/                            # Runtime state directory

~/.claude/CLAUDE.md                 # Layer 1: VALVES block (25 lines within 71-line file)
~/.claude/rules/valves-*.md         # Layer 2: 3 symlinks -> ~/.valves/rules/
```

## 4. Execution Flow

### Pre-Audit Setup

1. `install_overlay.sh` (one-time): creates Layer 2 symlinks, appends Layer 1 block to CLAUDE.md.
2. `inject_methodology.sh <scratchpad>` (per-audit): copies 23 Layer 3 files to `{SCRATCHPAD}/_valves_methodology/`.

### During Audit (V2 drives)

1. V2 Python driver spawns `claude -p` for each phase.
2. Subprocess reads `~/.claude/CLAUDE.md` (Layer 1 router) and `~/.claude/rules/valves-*.md` (Layer 2 doctrine).
3. Subprocess matches its phase name against the Layer 1 table.
4. If matched, reads the listed files from `{SCRATCHPAD}/_valves_methodology/`.
5. Methodology influences agent behavior within that phase -- no state written back to Valves.

### Post-Audit

No Valves-specific teardown. Scratchpad methodology files persist with audit artifacts.

## 5. Session A/B Mapping

Valves structures audits as two analytical sessions with different cognitive biases.

| Session | V2 Phases | Analytical Bias | Mechanism |
|---------|-----------|-----------------|-----------|
| **A (Recall)** | recon, breadth, rescan, depth iter 1, scoring | Maximize discovery, accept false positives | Layer 2 doctrine recall bias |
| **Boundary** | After V2 confidence scoring checkpoint | Handoff | `session-b-doctrine.md` written to scratchpad |
| **B (Precision/DA)** | depth iter 2-3, verify, skeptic, report | Devil's Advocate, prune false positives | Layer 2 doctrine + `session-b-doctrine.md` |

The boundary aligns with V2's confidence scoring checkpoint. Session B agents receive the DA role framing from Plamen's anti-dilution rules (AD-2), reinforced by Valves doctrine.

## 6. Pattern Library Access

642 vulnerability patterns organized in two corpora:

| Corpus | Files | Patterns | Source |
|--------|-------|----------|--------|
| Solodit | 20 cluster files | 562 | Solodit database |
| Cantina | 14 files in `cantina/` | 80 | Cantina contest findings |

**Access protocol**: Breadth and depth agents read `PATTERN_INDEX.md` (181 lines), select 1-3 relevant cluster files based on protocol type, then read those clusters. Agents never load all 642 patterns.

**Anti-anchoring rule**: Patterns inform WHAT classes of vulnerability to look for, not WHAT specific bugs to find. An agent that reports a pattern match without independent code-level evidence is producing an anchored false positive.

## 7. Adversarial Modules (v1.8.1)

Three new methodology modules strengthen goal-directed adversarial analysis:

### Attacker Objective Matrix (`attacker-objective-matrix.md`, 108 lines)

14 attacker objectives (drain, freeze, insolvency, governance capture, stuck state, ...) crossed with 15 actor capabilities (normal user through MEV searcher). Agents identify which (actor, objective) cells are live for the protocol and trace backward to find enabling paths. Used in breadth (framing), depth (pressure-test), and chain analysis (composition targets).

### Multi-Step Exploit Composer (`exploit-composition.md`, 168 lines)

6-step protocol for composing isolated low/medium signals into high-impact exploit paths. Adds goal-directed composition on top of Phase 4c's mechanical postcondition-to-precondition matching. Five composition patterns (state drift, admin action, external update, privilege sequencing, grief-to-freeze). Anti-speculation rule: every step must cite specific code at file:line.

### Pattern Candidate Schema (`pattern-candidate-schema.md`, 89 lines)

Post-audit artifact format for proposing learned patterns. Agents propose to `{SCRATCHPAD}/pattern_candidates.md` during audits; a human curator reviews after audit completion. Patterns live in `~/.valves/patterns/learned/` only after promotion. Anti-anchoring: agents NEVER auto-promote patterns.

### Heuristic Lenses (13 total)

The doctrine (Layer 2) now carries 13 heuristic lenses, up from 8:

| Lens | Added In | Focus |
|------|----------|-------|
| SYMMETRY | v1.7 | Sibling pair divergence |
| STATE-TRANSITION | v1.7 | Protocol lifecycle |
| SEQUENCE | v1.7 | Unenforced call-order |
| BIG-VS-SMALL | v1.7 | Operation splitting |
| NUMERIC-EXTREME | v1.7 | Zero/max boundary |
| NONEXISTENT-ID | v1.7 | Attacker-chosen identifiers |
| TEST-SKEPTIC | v1.7 | Test-suite false comfort |
| DEAD-STATE | v1.7 | Written-never-read variables |
| ROUNDING-DRIFT | v1.8.1 | Compounding per-operation rounding |
| TX-ORDERING | v1.8.1 | Transaction ordering exploitation (chain-specific) |
| TEMPORAL-WINDOW | v1.8.1 | Commitment-execution time gaps |
| CALLBACK-CONTROL | v1.8.1 | External control flow transfer |
| INCENTIVE-DIVERGENCE | v1.8.1 | Rational actor misbehavior |

## 8. What Valves Owns vs. What V2 Owns

| Concern | Owner |
|---------|-------|
| Phase routing, ordering, scheduling | V2 Python driver |
| Checkpoint, resume, crash recovery | V2 Python driver |
| Artifact gates (file existence checks) | V2 Python driver |
| Rate-limit handling, model routing | V2 Python driver |
| Agent prompt templates | Plamen (`~/.plamen/`) |
| Adversarial doctrine, 13 heuristic lenses | Valves Layer 2 |
| Attacker objective matrix, exploit composer | Valves Layer 3 |
| Learned pattern candidates (post-audit) | Valves Layer 3 + patterns/learned/ |
| Seed system (Canonical, Assumption-Breaker, Analog) | Valves Layer 3 |
| EV-ranked verification ordering | Valves Layer 3 |
| Proof discipline (CLEARED standard) | Valves Layer 2 |
| Exploit preservation / anti-overcompression | Valves Layer 2 |
| Pattern library (642 patterns) | Valves patterns/ |
| Session A/B cognitive framing | Valves Layer 2 + 3 |
| Bug class taxonomy and propagation | Valves Layer 3 |
| Report quality standards | Valves Layer 3 |

## 9. Constraints & Risks

| Constraint | Status | Mitigation |
|------------|--------|------------|
| `~/.plamen/` untouched | Met | All injection via `~/.claude/` and scratchpad |
| CLAUDE.md under 500 lines | Met (71 lines) | VALVES block is 25 lines; Plamen block is 46 |
| No dual orchestration | Met | Valves `commands/valves.md` is info-only |
| Layer 3 depends on scratchpad path | Acceptable | `valves-plamen` wrapper auto-detects; manual injection available |
| Symlink breakage | Low risk | `smoke_test.sh` validates all 3 symlinks |
| V2 phase name changes | Medium risk | Layer 1 table uses pattern matching, not exact names |
| Context budget pressure | Low | Layer 2 adds ~500 lines to every subprocess; within budget |
| Codex backend | Unvalidated | `codex_adapter.py` does not map `~/.valves/` paths; Claude-only for now |

## 10. Adapter Scripts Reference

### `install_overlay.sh`

One-time setup. Creates 3 symlinks in `~/.claude/rules/`, appends the VALVES block to CLAUDE.md (idempotent -- skips if block exists), runs smoke test.

### `inject_methodology.sh <scratchpad_path>`

Per-audit injection. Copies 26 methodology files from `~/.valves/methodology/` to `{SCRATCHPAD}/_valves_methodology/`, resolving symlinks. Writes a README.md to the target directory. Reports copy/skip counts.

### `smoke_test.sh`

Validates integration state: core files, methodology files (accepts both symlinks and regular files), Layer 2 rules, CLAUDE.md block, missing reference detection, deprecated archives, wrapper executable, methodology injection on temp scratchpad, version consistency. Run after install or when debugging integration.

### `bin/valves-plamen`

Wrapper that auto-injects Valves methodology into the project scratchpad then launches the Plamen V2 driver. Verifies Plamen V2 is installed, creates/locates the scratchpad, runs `inject_methodology.sh`, and hands off to `plamen_driver.py`.
