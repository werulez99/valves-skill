# Valves Phase-to-Methodology Map

> Maps Plamen V2 phases to Valves methodology files.
> Layer 2 files are always loaded via `~/.claude/rules/` symlinks.
> Layer 3 files are read from `{SCRATCHPAD}/_valves_methodology/` when present.

## Layer 2 — Always Loaded (via ~/.claude/rules/)

| Symlink | Target | Lines | Content |
|---------|--------|-------|---------|
| `valves-doctrine.md` | `~/.valves/rules/valves-doctrine.md` | 290 | Adversarial questions, decision lenses, 10 heuristic lenses (incl. ROUNDING-DRIFT, TX-ORDERING) |
| `valves-proof-discipline.md` | `~/.valves/rules/cleared-proof-discipline.md` | 162 | CLEARED proof requirements, evidence standards |
| `valves-exploit-preservation.md` | `~/.valves/rules/strongest-exploit-preservation.md` | 106 | Anti-overcompression, strongest-exploit preservation |

## Layer 3 — Phase-Targeted (from scratchpad)

| V2 Phase Pattern | Scratchpad Methodology Files | Reasoning |
|------------------|------------------------------|-----------|
| `recon` | `pattern-integration.md` | Pattern library awareness from the start |
| `breadth`, `rescan*` | `pattern-integration.md`, `attacker-objective-matrix.md`, `exploit-attempt-logging.md` | Pattern-guided discovery + objective-driven framing + coverage logging |
| `inventory*`, `sc_semantic_dedup` | `bug-class-registry.md`, `bug-class-propagation.md`, `attribution-methodology.md` | Bug class taxonomy for grouping |
| `depth`, `attention_repair` | `seed-methodology.md`, `confidence-scoring-overlay.md`, `attacker-objective-matrix.md`, `exploit-attempt-logging.md` | Seeds + lenses + objective pressure-test + coverage logging |
| `chain*` | `ev-ranking.md`, `attack-thesis-methodology.md`, `exploit-composition.md`, `attacker-objective-matrix.md` | EV-ranked chain + goal-directed composition |
| `sc_verify*`, `verify*` | `ev-ranking.md` | EV-ranked verification queue |
| `skeptic` | (Layer 2 sufficient) | Doctrine covers adversarial reasoning |
| `report*` | `report-quality.md` | Report quality standards |
| `crossbatch` | `cross-session-consensus.md` | Cross-pass consensus protocol |

## Session A/B Boundary Mapping

| Valves Session | V2 Phase Range | Methodology Bias |
|----------------|----------------|-----------------|
| Session A (recall) | recon → breadth → depth iter 1 → scoring | Doctrine "recall bias" via Layer 2 |
| Boundary | After confidence scoring checkpoint | `session-b-doctrine.md` handoff data |
| Session B (precision) | depth iter 2-3 (DA) → verify → skeptic | Doctrine + `session-b-doctrine.md` |

## Pattern Library Access

- **Index**: `~/.valves/patterns/PATTERN_INDEX.md` (181 lines)
- **Cluster files**: `~/.valves/patterns/{category}.md` (20 files)
- **Cantina corpus**: `~/.valves/patterns/cantina/` (13 files)
- **Access rule**: Breadth/depth agents Read index, select 1-3 relevant clusters
- **Anti-anchoring**: Patterns are detection aids, not finding sources
