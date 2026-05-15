# Valves Methodology Overlay (v1.8.0)

> **Architecture**: Plamen V2 = deterministic execution engine (Python driver).
> Valves = analytical methodology overlay (injected into V2 subprocesses).
> Disk state is authoritative. No LLM routing. No monolithic orchestrator.

---

## What Valves Is (v1.8.0)

Valves provides analytical methodology that makes Plamen V2 agents reason
more adversarially, prove more rigorously, and avoid overcompression. It does
NOT orchestrate phases, manage state machines, or gate artifacts — Plamen V2
owns all of that.

## What Valves Is NOT

- NOT an orchestrator (retired in v1.8.0; see `deprecated/`)
- NOT a replacement for `/plamen` — it supplements it
- NOT a standalone audit system — it requires Plamen V2

---

## 3-Layer Injection Architecture

### Layer 1 — CLAUDE.md Phase Router (~25 lines)

Location: `~/.claude/CLAUDE.md` inside `<!-- VALVES:START -->` / `<!-- VALVES:END -->`

Maps V2 phase names to scratchpad methodology files. Every `claude -p`
subprocess reads CLAUDE.md on spawn, so this routing table is universally
visible. Contains no methodology — only file references.

### Layer 2 — Always-Loaded Rules (3 files, ~500 lines)

Symlinks in `~/.claude/rules/` auto-loaded into every subprocess:

| Symlink | Source | Content |
|---------|--------|---------|
| `valves-doctrine.md` | `~/.valves/rules/valves-doctrine.md` | Adversarial questions, decision lenses, 8 heuristic lenses |
| `valves-proof-discipline.md` | `~/.valves/rules/cleared-proof-discipline.md` | CLEARED proof requirements, evidence standards |
| `valves-exploit-preservation.md` | `~/.valves/rules/strongest-exploit-preservation.md` | Anti-overcompression, strongest-exploit preservation |

### Layer 3 — Phase-Targeted Methodology (23 files, ~3K lines)

Injected to `{SCRATCHPAD}/_valves_methodology/` before audit starts.
V2 subprocesses read specific files based on the Layer 1 phase table.

See `~/.valves/phase-map.md` for the full V2 phase → methodology mapping.

---

## Running an Audit

```bash
# Start a fresh audit (creates config, injects methodology, launches driver):
~/.valves/bin/valves-plamen core          # or: light, thorough

# Resume an interrupted audit:
~/.valves/bin/valves-plamen resume

# Inject methodology only (then use /plamen-wizard in Claude Code):
~/.valves/bin/valves-plamen inject-only
```

For docs/scope/proven-only options, use `/plamen-wizard` inside Claude Code.

---

## Session A/B Cognitive Framing

| Session | V2 Phases | Bias |
|---------|-----------|------|
| A (Recall) | recon → breadth → depth iter 1 → scoring | Maximize discovery |
| Boundary | After confidence scoring checkpoint | `session-b-doctrine.md` handoff |
| B (Precision) | depth iter 2-3 → verify → skeptic → report | Devil's Advocate pruning |

---

## Key Methodology Components

| Component | Layer | Files |
|-----------|-------|-------|
| Adversarial doctrine | 2 | `valves-doctrine.md` |
| Proof discipline | 2 | `valves-proof-discipline.md` |
| Exploit preservation | 2 | `valves-exploit-preservation.md` |
| Seed system | 3 | `seed-methodology.md` |
| EV-ranked verification | 3 | `ev-ranking.md` |
| Attack thesis | 3 | `attack-thesis-methodology.md` |
| Confidence scoring | 3 | `confidence-scoring-overlay.md` |
| Session B handoff | 3 | `session-b-doctrine.md` |
| Bug class taxonomy | 3 | `bug-class-registry.md`, `bug-class-propagation.md` |
| Pattern library | disk | 642 patterns (562 Solodit + 80 Cantina) |

---

## Pattern Library

- **Index**: `~/.valves/patterns/PATTERN_INDEX.md` (181 lines)
- **Solodit**: 562 patterns across 20 cluster files
- **Cantina**: 80 patterns across 14 files in `cantina/`
- **Anti-anchoring**: Patterns are detection aids, not finding sources

---

## Validation

```bash
bash ~/.valves/adapter/smoke_test.sh
```

---

## Backend Support

| Backend | Status | Notes |
|---------|--------|-------|
| Claude Code (`claude -p`) | Validated | Full Layer 1-3 injection works |
| Codex CLI | Unvalidated | `codex_adapter.py` does not map `~/.valves/` paths; needs follow-up wiring |

---

## Directory Structure

```
~/.valves/
  VERSION                         # 1.8.0
  CLAUDE.md                       # This file
  phase-map.md                    # V2 phase → methodology mapping
  VALVES_ON_PLAMEN_V2_DESIGN.md   # Architecture document
  methodology/                    # 28 files — extracted pure methodology
  patterns/                       # 642 patterns (Solodit + Cantina)
  rules/                          # 33 original rule files (Layer 2 sources)
  adapter/                        # install, inject, smoke test
  bin/                            # valves-plamen wrapper
  commands/valves.md              # Info-only /valves skill
  deprecated/                     # Archived v1.7 orchestration
  references/                     # Reference material
  state/                          # Runtime state
```

---

## Deprecated in v1.8.0

The following v1.7 artifacts are archived in `~/.valves/deprecated/`:

| File | Lines | Replaced By |
|------|-------|-------------|
| `valves-v1.7-orchestrator.md` | 5,443 | Plamen V2 `plamen_driver.py` |
| `CLAUDE.v1.7.monolith.md` | 445 | This file |
| `execution-state.md` | 502 | V2 checkpoint system |
| `thorough-strict-mode.md` | 337 | V2 phase validators |
| `artifact-ownership.md` | 149 | V2 artifact gates |
| `pipeline-trace.md` | 86 | V2 checkpoint + adaptive loop log |

---

## References

- Architecture: `~/.valves/VALVES_ON_PLAMEN_V2_DESIGN.md`
- Migration: `~/.valves/VALVES_ON_PLAMEN_V2_MIGRATION_REPORT.md`
- Phase map: `~/.valves/phase-map.md`
- Plamen V2: `~/.plamen/scripts/plamen_driver.py` (read-only)
