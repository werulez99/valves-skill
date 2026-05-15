# Valves v1.8.3

Adversarial methodology overlay for [Plamen V2](https://github.com/PashovAuditGroup) security auditor.

Plamen V2 runs the engine (phases, checkpoints, artifact gates). Valves injects the analytical methodology (adversarial doctrine, heuristic lenses, exploit composition, proof discipline, pattern library, exploit attempt logging).

## Prerequisites

- **Plamen V2** installed at `~/.plamen/` with `plamen_driver.py`
- **Claude Code** CLI available in PATH

## Install

```bash
git clone https://github.com/werulez99/valves-skill.git
cd valves-skill
./install.sh
```

The installer copies to `~/.valves/`, creates Layer 2 symlinks, appends the phase router to `~/.claude/CLAUDE.md`, and runs the smoke test. Backs up existing `~/.valves/` if present.

## Usage

```bash
cd <your-project>
~/.valves/bin/valves-plamen core       # start audit (light | core | thorough)
~/.valves/bin/valves-plamen resume     # resume interrupted audit
~/.valves/bin/valves-plamen inject-only # inject methodology, then use /plamen in Claude Code
```

## Architecture

| Layer | Location | Loaded | Content |
|-------|----------|--------|---------|
| **1** | `~/.claude/CLAUDE.md` | Every subprocess | Phase-to-methodology routing table |
| **2** | `~/.claude/rules/valves-*.md` | Every subprocess | Core doctrine, proof discipline, exploit preservation (~520 lines) |
| **3** | `{SCRATCHPAD}/_valves_methodology/` | Per-phase | 27 phase-targeted methodology files |

## What's Inside

- **13 Heuristic Lenses** — SYMMETRY, STATE-TRANSITION, SEQUENCE, BIG-VS-SMALL, NUMERIC-EXTREME, NONEXISTENT-ID, TEST-SKEPTIC, DEAD-STATE, ROUNDING-DRIFT, TX-ORDERING, TEMPORAL-WINDOW, CALLBACK-CONTROL, INCENTIVE-DIVERGENCE
- **Attacker Objective Matrix** — 14 objectives x 15 actor capabilities
- **Multi-Step Exploit Composer** — 6-step protocol for composing isolated signals into exploit paths
- **Exploit Attempt Logging** — makes RC-AGENT misses visible by logging what agents tested vs skipped
- **Coverage Summary Parser** — deterministic bash script extracts UNTESTED/CONFIRMED/REFUTED/PARTIAL from agent outputs (no LLM, no usage)
- **642 Vulnerability Patterns** — 562 Solodit + 80 Cantina
- **Learned Pattern System** — post-audit curator-approved pattern promotion

## Post-Analysis Coverage

After breadth/depth phases complete, run the coverage parser:

```bash
~/.valves/bin/summarize-exploit-attempts .scratchpad
```

Outputs `.scratchpad/exploit_attempt_coverage.md` — shows which attacker objectives agents tested, refuted, or left UNTESTED. No agents spawned, no usage burned.

## Validate

```bash
bash ~/.valves/adapter/smoke_test.sh
```

## Docs

- [Architecture](valves/VALVES_ON_PLAMEN_V2_DESIGN.md)
- [Migration Report](valves/VALVES_ON_PLAMEN_V2_MIGRATION_REPORT.md)
