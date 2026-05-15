# Negative Results Methodology

> Extracted from negative-results.md (v1.7.0-PATCH12).
> Used by: depth, verification phases.

## Purpose

Audits don't just find bugs — they also rule things out. Without a negative-results memory, every audit re-investigates the same paths the previous one cleared. The negative-results system records:
1. What was investigated and refuted, and why.
2. What conditions would change the verdict (the "fragility" envelope).
3. Which audits the negative result has held across.

The Phase 4 Devil's Advocate and Phase 4c chain analysis read these to avoid re-litigating cleared paths. The Phase 6 report cites them in its Residual Risk Summary when a current candidate matches a prior NR (PRIOR_NEGATIVE handling).

## NR Entry Schema

```markdown
### NR-{N} — {one-line summary}
- Source: {Phase 4b depth | Phase 4c chain | Phase 5 verifier | Phase 5.6 thesis-drop}
- Path: {actor -> entry -> state -> outcome}
- Confidence (HIGH/MEDIUM/LOW): {how confident are we this stays cleared}
- Refutation evidence:
  - {concrete artifact reference: code line, test failure, math constraint}
- Fragility envelope (would change the verdict):
  - {what would have to be true for this NR to flip — e.g., "if admin role is split", "if oracle delay > 5 minutes", "if pause flag added"}
- Generalizable: {YES/NO — can this NR apply to other audits or is it project-specific?}
```

## Promotion Protocol (per-audit to global)

After Phase 5.6.4-pre (Bug-Class FP Calibration Update), the orchestrator scans `audit_negative_results.md` and promotes entries to the global store when ALL of these hold:

1. Confidence is HIGH.
2. Generalizable is YES.
3. Fragility envelope is documented (non-empty, specific).
4. The NR has a concrete refutation artifact (not just "agent said no").

Failed entries stay per-audit only.

### Global NR-G Schema

```markdown
## NR-G-{N} — {short pattern name}
- First seen: {audit_name, date}
- Last reaffirmed: {audit_name, date}
- Pattern: {grep-able or one-sentence description of the path family}
- Why cleared (canonical): {refutation argument that has held}
- Fragility envelope: {when does this flip}
- Audit history: [{audit_name, date, outcome: REAFFIRMED / CONTRADICTED / N/A}]
- PRIOR_NEGATIVE_OVERRIDDEN count: {N — how many audits found a real bug despite the NR}
- Applicability: {
    protocol_family: {one of: amm-spot / amm-cl / lending-borrow / vault-erc4626 / staking / governance / bridge-msg / oracle / nft-marketplace / dex-aggregator / other},
    trust_model_class: {one of: untrusted-only / single-admin / multisig-no-timelock / multisig-with-timelock / fully-decentralized / other},
    external_dependency_model: {one of: chainlink-only / pyth-only / oracle-mixed / aave-pool / uniswap-v3 / curve / balancer / no-external / other},
    exploit_precondition_class: {one of: instant-unrestricted / requires-approval / requires-balance-N / requires-time-window / requires-admin-cooperation / requires-flash-loan / multi-tx / other}
  }
- Generalizability scope: {LOCAL / WIDE} - LOCAL = applies only when ALL four applicability fields match. WIDE = applies when 3 of 4 match (used sparingly, for mechanically-universal refutations like "constant-true-by-construction" or "EVM-level invariant").
- evidence_age_class: {CURRENT | STALE | UNKNOWN}
```

## PRIOR_NEGATIVE Handling — Strict Applicability Matching

When generating attack_thesis.md v3, each path is checked against global NR-G entries using **structured applicability matching**, not pattern fuzzy-match alone.

### Applicability Test

```
def is_applicable(nr_g, current_audit_context):
    # Pattern match required first (existing behavior)
    if not pattern_matches(nr_g.pattern, current_path):
        return False, None

    # Strict applicability
    matches = 0
    for field in [protocol_family, trust_model_class, external_dependency_model, exploit_precondition_class]:
        if nr_g.applicability[field] == current_audit_context[field]:
            matches += 1
        elif nr_g.applicability[field] == 'other' or current_audit_context[field] == 'other':
            # 'other' is a wildcard but does NOT count as a match
            pass

    if nr_g.generalizability_scope == 'LOCAL':
        return matches == 4, f"matches={matches}/4 LOCAL"
    elif nr_g.generalizability_scope == 'WIDE':
        return matches >= 3, f"matches={matches}/4 WIDE"
    else:
        return False, "missing scope"
```

### Outcome Routing

- **Path matches NR-G AND applicability test PASSES (all required fields align)** -> mark `PRIOR_NEGATIVE_INHERITED` and downgrade to REFUTED with citation. **This is the only path that produces clearance-strength evidence.**
- **Path matches NR-G BUT applicability test FAILS** -> the NR-G is **advisory only**. Annotate the path with `PRIOR_NEGATIVE_ADVISORY` (NOT inherited) and cite the NR-G with the mismatch reason ("protocol_family differs: NR-G says lending-borrow, this audit is amm-spot"). Path stays at its v2 status. Session B verifier may consider the advisory as context but MUST NOT treat it as clearance evidence.
- **Path matches NR-G AND this audit has [POC-PASS]** -> mark `PRIOR_NEGATIVE_OVERRIDDEN`, increment the count in the global file, cite the prior NR. Overrides apply regardless of applicability since real on-chain proof beats prior reasoning.
- **No match** -> standard v3 status rules apply.

### Backward Compatibility (entries without applicability metadata)

NR-G entries written before v1.7-PATCH4 lack applicability metadata. They are treated as **advisory only** until back-filled:
- Entries without `Applicability:` block -> `is_applicable() returns False` -> route to `PRIOR_NEGATIVE_ADVISORY`. They cannot produce clearance-strength evidence.
- The Promotion Protocol MUST emit `Applicability:` and `Generalizability scope:` for every newly-promoted NR-G. Promotion fails if either field is missing.

## Evidence Age / Drift Awareness

Even with strict applicability matching, an NR-G can be stale because the EXTERNAL world it was cleared against has shifted.

### evidence_age_class Semantics

- **CURRENT** — the refutation evidence has been verified within the last 6 months OR the most recent audit reaffirmation is within the last 6 months. Automatically demoted to STALE when `Last reaffirmed` is older than 6 months.
- **STALE** — the entry has not been reaffirmed within the last 6 months. May be advisory only; cannot produce clearance-strength evidence even if applicability passes.
- **UNKNOWN** — not yet classified. Treated as STALE for matching purposes (conservative bias).

### Demotion Algorithm (mechanical)

```
def derive_age_class(nr_g, today):
    last_event = max(nr_g.first_seen, nr_g.last_reaffirmed) if nr_g.last_reaffirmed else nr_g.first_seen
    age_days = (today - last_event).days

    if age_days <= 180:  # 6 months
        return 'CURRENT'
    else:
        return 'STALE'

# Override: if entry has explicit evidence_age_class field, use it; ELSE compute from dates.
```

### Age-Aware Outcome Routing

| Applicability test | evidence_age_class | Outcome |
|---|---|---|
| PASS | CURRENT | `PRIOR_NEGATIVE_INHERITED` (clearance-strength) |
| PASS | STALE | `PRIOR_NEGATIVE_ADVISORY` with reason `STALE_NEEDS_REVALIDATION` (NOT clearance-strength) |
| PASS | UNKNOWN | `PRIOR_NEGATIVE_ADVISORY` with reason `UNKNOWN_AGE_TREATED_AS_STALE` |
| FAIL | any | `PRIOR_NEGATIVE_ADVISORY` (applicability mismatch dominates) |
| matches NR-G AND audit has [POC-PASS] | any | `PRIOR_NEGATIVE_OVERRIDDEN` (real evidence beats prior reasoning regardless of age) |

### Hard Rules

- The 6-month threshold is conservative-default. Stale NRs go to advisory automatically; no agent decides.
- `evidence_age_class` is OPTIONAL on existing entries (back-compat). If absent, derived from `Last reaffirmed` / `First seen` dates. If dates are also missing, treated as UNKNOWN -> STALE-equivalent.
- This rule is OBSERVATIONAL and SAFE: it tightens which NR-Gs can clear, never loosens.

## Promotion Archive

When a global NR-G is contradicted (`CONTRADICTED` outcome in audit_history with verified PoC), it is moved to the archive with the contradicting audit cited. The archive is read-only documentation; live NR matching uses only the active global store.

## Why This Matters

Without NR memory, audits become a treadmill of re-clearing the same paths. With NR memory, depth agents can spend budget on novel paths and the report can clearly distinguish "we considered this and cleared it" from "we didn't look".
