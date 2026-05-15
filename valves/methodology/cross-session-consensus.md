# Cross-Session Consensus Methodology

> Extracted from cross-session-consensus.md (v1.7.0-PATCH12).
> Used by: crossbatch phase.

## Purpose

Records — for every Session A finding — whether Session B confirms, refutes, upgrades, or reframes the verdict, with structured fields only (no Session A reasoning prose injected into Session B context).

## Schema

```markdown
| Finding ID | Session A View | Session B View | Verdict Match? | Root Cause Match? | Severity Match? | Consensus Bonus Eligible? | Notes |
|---|---|---|---|---|---|---|---|
```

### Field Definitions

- **Finding ID** — the `[F-N]` identifier from `findings_inventory.md`.
- **Session A View** — a *structured* triple: `{verdict, severity, root-cause-tag}`. Verdict in {CONFIRMED, PARTIAL, REFUTED, CONTESTED, LOW_CONFIDENCE}. Root-cause-tag is the BC-NNN classification (or BC-NEW-N).
- **Session B View** — the same triple, computed fresh by Session B from depth iter 2/3 + Session B re-scoring + Session B verifier verdicts where available.
- **Verdict Match?** — `Y` / `N` / `PARTIAL`.
- **Root Cause Match?** — `Y` / `N`. `Y` requires matching variable / function / invariant — not just matching the BC tag.
- **Severity Match?** — `Y` / `N`. Severity is post-modifier. Severity drift of one tier counts as `N`.
- **Consensus Bonus Eligible?** — one of:
  - `+0.15` — Verdict Match=Y AND Root Cause Match=Y.
  - `+0.10` — Verdict Match=Y AND Root Cause Match=N (same verdict, different analytical path).
  - `+0.0`  — Verdict Match=N OR Verdict Match=PARTIAL OR Session B was a label-only inheritance (no independent code-level work).
  - `INCOMPLETE` — Session B did not exercise this finding (DA pass skipped it because not in Session B targets).
- **Notes** — one short structured line. Allowed contents: severity-tier-delta (e.g. `B-1` for Session B downgrades by 1), verdict-flip type (e.g. `A=CONFIRMED -> B=REFUTED`), or `INCOMPLETE: not in B targets`. NO reasoning prose. NO "we believe" language.

## Hard Rule — No Session A Reasoning Leaks into Session B

The producer of this artifact is the orchestrator (inline) — NOT a Session B agent. The orchestrator reads structured fields only:
- From session_checkpoint.md: ID, Title, Location, Severity, Evidence Type, Bug-Class, Strongest Exploit, Correctness Winner, Contested, Confidence (and structured metadata: Surface, Actor, Victim, State Domain, Cross-Contract?, Economic?, Seed-Origin?, Thesis-Linked?, Historical-Prime-Linked?, Low-Coverage-Module-Linked?, Disputed?).
- From Session B artifacts: verdict, severity, root-cause-tag.

The orchestrator does NOT inject Session A's depth-prose into the Session B re-scoring agent's prompt. That is the architectural quality mechanism — preserving it is non-negotiable.

## Application — Feeds Bonus Calculation, Not Direct Severity Edit

The `Consensus Bonus Eligible?` column is **input** to Session B's existing cross-session consensus bonus (capped at 1.0). It does NOT itself modify confidence scores.

### Downstream Consumers

- **Session B re-scoring rolling pass** — applies +0.15 / +0.10 / +0.0 to Session B's composite before final write.
- **Bug-Class FP Calibration update** — uses `Verdict Match? x Severity Match?` as a per-BC consistency signal.
- **Report Residual Risk Summary** — flags any `Verdict Match=N` with `Severity Match=N` as a "cross-session contested" entry, surfaced for reviewer attention. Findings ending CONTESTED at this stage carry the strongest "needs human review" signal in the report.

## Hard Gate

`cross_session_consensus.md` is a HARD gate before Phase 5.6.1 (Thesis v3 generation). The Thesis v3 status rules need verdict-pair data to apply correctly to PRIOR_NEGATIVE_OVERRIDDEN handling. If missing on first attempt -> orchestrator retries once; if still missing -> degrade-and-log only (do NOT block) in Core/Light, BLOCK in Thorough.

## Why This Is Precision-Positive (Does Not Increase FP)

- The artifact is structured-fields-only; no narrative invention.
- It does NOT modify any score directly — it parameterizes the existing bonus and records contradictions for human review.
- It strengthens cross-session consensus detection (which down-weights label-only parroting and rewards real code-level agreement) — directly improving precision.
- It exposes contradictions explicitly so neither session's verdict is silently accepted.
