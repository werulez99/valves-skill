<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Attack Thesis (`attack_thesis.md`)

The audit's running commitment to a small, concrete set of attack paths. Three versions are produced through the pipeline: **v1** (post-classification, pre-depth), **v2** (post-depth iter 1 + Economic + Propagation), **v3** (post-verification).

## File location

`{scratchpad}/attack_thesis.md`. Each version overwrites the file but preserves prior versions as appendices.

## § v1 Generation (Phase 4a.3, sonnet)

**Inputs**: `findings_inventory.md`, `strongest_exploit_cards.md` (MANDATORY — custody-loss card winners become candidate thesis paths unless refuted), `finding_classification.md` (flat BC tags per finding, NOT clusters), `design_context.md`, `attack_surface.md`.

**Output**: 3–5 concrete attack paths. Each path is a record:

```markdown
## P-{N} — {one-line attack name}
- Status: CANDIDATE
- Triple: (victim={role/actor}, attacker={role/actor}, entry_point={function or external trigger})
- Strongest Exploit Card Ref: SEC-{N}, SEC-{M}  ← which cards this path covers
- Supporting findings: [F-12], [F-23], ...      ← individual finding IDs (NOT cluster IDs)
- Testable precondition: {one-sentence falsifiable predicate}
- Required state: {what must be true on-chain for this to fire}
- Confidence: low / medium / high (initial guess)
- v1 commit: {ISO timestamp}
```

**Rules for v1**:
- Use BC tags from `finding_classification.md` to *identify* related findings (same BC-NNN tag = likely same class), but do NOT assume they are the same bug — depth has not confirmed yet.
- Reference **individual finding IDs** in Supporting evidence, not cluster IDs.
- Custody-loss card winners (E1 in Card Eligibility) MUST become candidate thesis paths unless refuted by an existing finding.
- Emit ONLY v1. Do NOT anticipate v2/v3 analysis.

**Status values**: only `CANDIDATE` in v1. Never `CONFIRMED` or `REFUTED` here.

## § v2 Generation (Phase 4b post-iter-1, sonnet)

**Trigger**: after iteration 1 scoring completes AND the Economic Incentive Agent returns.

**Inputs**: previous `attack_thesis.md` (v1), all depth/economic/propagation/diff-audit outputs, `confidence_scores.md`.

**Updates**:
1. For each existing v1 path, re-evaluate against new evidence:
   - Strengthen → keep status CANDIDATE but note new supporting findings.
   - Weaken → mark `WEAKENED` with the depth/scoring evidence that softened it.
   - Refute → mark `REFUTED` with the specific contradicting evidence.
2. Merge convergent paths (two v1 paths reaching the same victim via overlapping enablers → one v2 path).
3. Add newly-surfaced paths from depth or economic findings (status `CANDIDATE`).
4. Preserve v1 verbatim as `## Appendix: v1` at the bottom of the file.

**Output schema** (per path):

```markdown
## P-{N} — {title}
- Status: CANDIDATE | WEAKENED | REFUTED
- Triple: (victim, attacker, entry_point)
- Supporting evidence: [F-12 (CONFIRMED, depth)], [F-44 (PARTIAL, scoring 0.55)], ...
- Refutation evidence: {if WEAKENED/REFUTED — concrete artifact references}
- Confidence: 0.00–1.00 (composite — see phase4-confidence-scoring.md)
- v1 commit: {timestamp}
- v2 commit: {timestamp}
```

## § v3 Generation (Phase 5.6.1, orchestrator inline)

**Trigger**: after Phase 5 verification + Phase 5.5 extraction complete.

**Inputs**: previous `attack_thesis.md` (v2), Phase 5 verifier verdicts (`verify_*.md`), `verification_inheritance.md`, `audit_negative_results.md`.

**v3 status rules** (apply per path):

| v2 status | Phase 5 outcome on supporting findings | v3 status |
|---|---|---|
| CANDIDATE | ≥1 supporting finding → `[POC-PASS]` (or inherited via cluster) | `CONFIRMED` |
| CANDIDATE | ALL supporting findings → `[POC-FAIL: GENUINE]` | `REFUTED` |
| CANDIDATE | mixed / inconclusive (some POC-PASS, some POC-FAIL, some skipped) | remains `CANDIDATE` (carried as residual risk) |
| WEAKENED | any `[POC-PASS]` supporting | `CONFIRMED` (rehabilitated) |
| WEAKENED | no `[POC-PASS]` | `REFUTED` |
| REFUTED | any `[POC-PASS]` (from a cluster representative) | `CONFIRMED` (rare — flag for review) |
| REFUTED | all `[POC-FAIL]` or no verification | remains `REFUTED` |

**PRIOR_NEGATIVE handling**: if a path was refuted in a prior audit (recorded in `~/.valves/state/negative_results.md`) but Phase 5 in this audit produced `[POC-PASS]`, mark `PRIOR_NEGATIVE_OVERRIDDEN` and cite the prior NR entry. Conversely, if a v2 CANDIDATE path matches a prior NR entry verbatim and no fresh evidence exists, mark `PRIOR_NEGATIVE_INHERITED` and downgrade to REFUTED with the citation.

**Output**: v3 written to `{scratchpad}/attack_thesis.md`, with v2 preserved as `## Appendix: v2` and v1 still in `## Appendix: v1`.

## Use in the report (Phase 6)

The v3 file is included **verbatim** as the report's `## Residual Risk Summary` section, including any PRIOR_NEGATIVE annotations and citations. CONFIRMED paths get cross-referenced to their report IDs. REFUTED paths are listed with a one-sentence refutation summary. CANDIDATE paths (residual) are listed with their confidence and the open evidence question.

## Why three versions

- **v1** commits early so depth iter 1 can be steered by named attack paths instead of agents drifting.
- **v2** absorbs depth + economic evidence and lets the loop dynamics reflect "what we now believe".
- **v3** is the final adjudication, locked to verifier verdicts so the report's residual-risk story matches the executed PoCs.
