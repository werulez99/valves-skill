# Confidence Scoring Overlay -- Valves Extensions

> Extracted from phase4-confidence-scoring.md (v1.7.0-PATCH12).
> Supplements Plamen V2's 4-axis scoring with Valves-specific extensions.
> Used by: depth, scoring phases.

---

## What Plamen already provides (not repeated here)

Plamen V2's 4-axis model (`Evidence x 0.25 + Consensus x 0.25 + AnalysisQuality x 0.30 + RAGMatch x 0.20`) with verdict bands (CONFIDENT >= 0.7, UNCERTAIN 0.4-0.7, LOW < 0.4), anti-dilution rules AD-1 through AD-6, convergence criteria, severity-weighted spawn priority, and the RAG Validation Sweep are defined in Plamen's `phase4-confidence-scoring.md`. The Valves file's treatment of these is identical; this overlay documents only what Valves ADDS.

## Valves Extension: Reality / Report Split

In addition to the legacy composite, Valves emits two parallel scores per finding:

- **`composite_reality`**: how likely is this finding to be REAL on-chain under the documented trust model. Uses the same axis weights but RAGMatch is gated on protocol-class match (not just text similarity).
- **`composite_report`**: how clearly the report can communicate this finding to the client. Penalizes findings whose explanation requires evidence the audit has not produced.

### Quadrant routing for iter 2

| Reality | Report | Iter 2 priority |
|---|---|---|
| HIGH | HIGH | none -- keep |
| HIGH | LOW | **+1 EV bonus in verification queue** + iter 2 spawns a "report-evidence" depth pass |
| LOW | HIGH | iter 2 Devil's Advocate to either confirm or REFUTE -- over-claiming risk |
| LOW | LOW | drop unless thesis path requires it |

## Valves Extension: Core mode 2-axis variant

For Core mode (when the full 4-axis model is not warranted), Valves uses a simplified 2-axis composite:

```
composite = 0.5 x Evidence + 0.5 x AnalysisQuality
```

- **Evidence (0-1)**: depth agent's evidence tag strength. `[BOUNDARY]` + `[TRACE]` >= 0.85; `[CODE-TRACE]` only ~ 0.55; `[INFER]` <= 0.40.
- **AnalysisQuality (0-1)**: did the agent execute the methodology? Cite-density of code references, completeness of trace, presence of refutation contract.

The verdict bands remain identical to the 4-axis model.

## Valves Extension: Loop dynamics classification

After iter 2 scoring, classify the loop state:

- **CONTRACTIVE** -- uncertainty distribution is shrinking (more findings reach CONFIDENT, none drift to LOW). Continue or exit.
- **OSCILLATORY** -- the same findings flip between CONFIDENT and UNCERTAIN across iterations. Force CONTESTED on the oscillating findings and exit.
- **EXPLORATORY** -- iter 2 surfaced material new evidence/paths. Run iter 3 in Thorough; in Core, skip and proceed to chain.

## Output schema extension

The `confidence_scores.md` output gains two columns beyond Plamen's standard schema:

```markdown
| Finding | Severity | Evidence | Consensus | Quality | RAG | composite | composite_reality | composite_report | Verdict | Iter 2 needed? |
|---|---|---|---|---|---|---|---|---|---|---|
| F-12 | High | 0.85 | 0.70 | 0.80 | 0.55 | 0.745 | 0.70 | 0.65 | CONFIDENT | no |
| F-44 | Medium | 0.55 | 0.40 | 0.60 | 0.30 | 0.46 | 0.50 | 0.30 | UNCERTAIN | yes (HIGH-LOW quadrant) |
```

The `composite_reality` and `composite_report` columns are the Valves-specific additions.
