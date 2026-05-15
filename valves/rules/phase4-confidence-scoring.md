<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Phase 4 Confidence Scoring (Plamen + Valves extensions)

Source-of-truth for the **Scoring Agent** (haiku, runs after Phase 4b iter 1 — Core/Thorough only) and the convergence logic of the adaptive depth loop. Output: `{scratchpad}/confidence_scores.md`.

## Two scoring axes for Plamen, four for Valves Thorough

### Core mode — 2-axis (legacy composite)

```
composite = 0.5 × Evidence + 0.5 × AnalysisQuality
```

- **Evidence (0–1)**: depth agent's evidence tag strength. `[BOUNDARY]` + `[TRACE]` ≥ 0.85; `[CODE-TRACE]` only ≈ 0.55; `[INFER]` ≤ 0.40.
- **AnalysisQuality (0–1)**: did the agent execute the methodology? Cite-density of code references, completeness of trace, presence of refutation contract.

### Thorough mode — 4-axis

```
composite = 0.25 × Evidence + 0.25 × Consensus + 0.30 × AnalysisQuality + 0.20 × RAGMatch
```

- **Evidence**: as above.
- **Consensus**: did multiple depth agents (or scanners) converge on this finding? Independent confirmation from token_flow + edge_case = high consensus.
- **AnalysisQuality**: as above.
- **RAGMatch**: similarity score from `~/.valves/rules/phase4-confidence-scoring.md` § Phase 4b.5 RAG Sweep (read by the RAG sweep agent — falls back to floor 0.3 when RAG isn't available).

## Verdict bands

| Composite | Band | Iter 2 routing |
|---|---|---|
| ≥ 0.7 | CONFIDENT | no more depth needed |
| 0.4 – 0.7 | UNCERTAIN | targeted depth |
| < 0.4 | LOW CONFIDENCE | targeted depth + production verification + RAG deep search |

## § Reality / Report Split (Valves)

In addition to the legacy composite, Valves emits two parallel scores per finding:

- **`composite_reality`**: how likely is this finding to be REAL on-chain under the documented trust model. Uses the same axis weights but RAGMatch is gated on protocol-class match (not just text similarity).
- **`composite_report`**: how clearly the report can communicate this finding to the client. Penalizes findings whose explanation requires evidence the audit has not produced.

Quadrant routing for iter 2:

| Reality | Report | Iter 2 priority |
|---|---|---|
| HIGH | HIGH | none — keep |
| HIGH | LOW | **+1 EV bonus in Phase 4c.5** + iter 2 spawns a "report-evidence" depth pass |
| LOW | HIGH | iter 2 Devil's Advocate to either confirm or REFUTE — over-claiming risk |
| LOW | LOW | drop unless thesis path requires it |

## § Adversarial routing rules (AD-1 through AD-6)

- **AD-1 — Hard DA role**: iter 2 agents are *structurally* adversarial. Prompt explicitly: "Your job is to find why this is NOT a bug. Confirmation is allowed only if you genuinely cannot break it."
- **AD-2 — Contrastive conditioning**: iter 2 agents see *cards* (evidence-only) from iter 1, not iter 1's prose. They form fresh conclusions from code + cards.
- **AD-3 — Severity-weighted budget**: `spawn_priority = (1 - confidence) × severity_weight`. Spend iter 2 budget on the highest-uncertainty highest-severity findings.
- **AD-4 — Anti-dilution**: max 5 evidence-only finding cards per iter 2 agent. Larger packets dilute attention.
- **AD-5 — New-evidence-only re-scoring**: iter 2 re-scoring may only INCORPORATE evidence iter 2 produced. Iter 1 evidence already counted; double-counting forbidden.
- **AD-6 — Post-verification feedback**: if Phase 5 returns CONTESTED with error traces AND budget remains, spawn targeted depth with the error traces as investigation questions.

## § Loop dynamics

After iter 2 scoring, classify the loop state:
- **CONTRACTIVE** — uncertainty distribution is shrinking (more findings reach CONFIDENT, none drift to LOW). Continue or exit.
- **OSCILLATORY** — the same findings flip between CONFIDENT and UNCERTAIN across iterations. Force CONTESTED on the oscillating findings and exit.
- **EXPLORATORY** — iter 2 surfaced material new evidence/paths. Run iter 3 in Thorough; in Core, skip and proceed to chain.

## § Convergence

- Hard cap: 3 iterations (Core: 1, Light: 1 with no scoring).
- Dynamic budget cap: `min(max(12, ceil(findings/5) + 7), 20)`.
- Progress check after each iteration: if no finding moved between bands, treat the loop as CONVERGED and exit.

## § Phase 4b.5 RAG Validation Sweep

After scoring (Core/Thorough), spawn a sonnet RAG sweep agent. For each finding above Info severity, query the unified-vuln-db MCP for similar known patterns. Write `{scratchpad}/rag_validation.md` with per-finding similarity scores.

If RAG is unavailable (MCP down or DB not built):
- Fall back to WebSearch via the agent (this is the template-defined fallback).
- If both fail, write floor scores (0.3) per finding and log the fallback chain in the agent's return.

Status mapping for checklist row 34 (RAG Validation Sweep):
- `rag_validation.md` exists with real RAG scores → `COMPLETE`.
- `rag_validation.md` exists with floor scores AND fallback chain logged → `FAILED_WITH_FALLBACK`.
- Agent fails entirely AND orchestrator inline writes floor-scores artifact → `FAILED_WITH_FALLBACK`.
- Otherwise → row stays unfinished; watchdog blocks Phase 4c advancement (Thorough strict-mode).

In Thorough, "writing floor scores without attempting" is a VIOLATION (logged) AND blocks the gate.

## § Output (`confidence_scores.md`)

```markdown
| Finding | Severity | Evidence | Consensus | Quality | RAG | composite | composite_reality | composite_report | Verdict | Iter 2 needed? |
|---|---|---|---|---|---|---|---|---|---|---|
| F-12 | High | 0.85 | 0.70 | 0.80 | 0.55 | 0.745 | 0.70 | 0.65 | CONFIDENT | no |
| F-44 | Medium | 0.55 | 0.40 | 0.60 | 0.30 | 0.46 | 0.50 | 0.30 | UNCERTAIN | yes (HIGH-LOW quadrant) |

## Summary
- CONFIDENT: {count}
- UNCERTAIN: {count}
- LOW CONFIDENCE: {count}
- Iter 2 spawn budget: {N}
- Iter 2 targets: {ID list}
```
