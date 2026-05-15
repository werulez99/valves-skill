<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Negative Results — "considered and cleared" memory

Source-of-truth for `audit_negative_results.md` (per-audit) and `~/.valves/state/negative_results.md` (global, persistent).

## Purpose

Audits don't just find bugs — they also rule things out. Without a negative-results memory, every audit re-investigates the same paths the previous one cleared. The negative-results system records:
1. What was investigated and refuted, and why.
2. What conditions would change the verdict (the "fragility" envelope).
3. Which audits the negative result has held across.

The Phase 4 Devil's Advocate and Phase 4c chain analysis read these to avoid re-litigating cleared paths. The Phase 6 report cites them in its Residual Risk Summary when a current candidate matches a prior NR (PRIOR_NEGATIVE handling).

## Per-audit file: `audit_negative_results.md`

Three writer paths converge on this file. The orchestrator's stub-ensure rule (Step 5.6.3.a) creates a minimal stub with three section headers:

```markdown
# Audit Negative Results — {project}
> Per-audit "considered and cleared" memory. See `~/.valves/rules/negative-results.md`.

## Verification [POC-FAIL] Results
_(populated below)_

## Chain Analysis REFUTED Verdicts
_(populated below)_

## Thesis Paths Dropped
_(populated below)_
```

### Writer paths (all append-only into the file)

1. **Phase 4b depth iter 1** — collects "considered and cleared" notes from depth agents (CLEARED with reason).
2. **Phase 4c REFUTED chain append** — every REFUTED chain hypothesis writes a row.
3. **Phase 5.6.3.b** — verifier-driven appends ([POC-FAIL] GENUINE / chain REFUTED at this phase / thesis-drop from v3).
4. **Phase 5.6.3.a** — stub-ensure (creates the file if no earlier writer did).

## NR entry schema

```markdown
### NR-{N} — {one-line summary}
- Source: {Phase 4b depth | Phase 4c chain | Phase 5 verifier | Phase 5.6 thesis-drop}
- Path: {actor → entry → state → outcome}
- Confidence (HIGH/MEDIUM/LOW): {how confident are we this stays cleared}
- Refutation evidence:
  - {concrete artifact reference: code line, test failure, math constraint}
- Fragility envelope (would change the verdict):
  - {what would have to be true for this NR to flip — e.g., "if admin role is split", "if oracle delay > 5 minutes", "if pause flag added"}
- Generalizable: {YES/NO — can this NR apply to other audits or is it project-specific?}
```

## § Promotion Protocol (per-audit → global)

After Phase 5.6.4-pre (Bug-Class FP Calibration Update), the orchestrator scans `audit_negative_results.md` and promotes entries to the global `~/.valves/state/negative_results.md` when ALL of these hold:

1. Confidence is HIGH.
2. Generalizable is YES.
3. Fragility envelope is documented (non-empty, specific).
4. The NR has a concrete refutation artifact (not just "agent said no").

Failed entries stay per-audit only.

### Global file structure (`~/.valves/state/negative_results.md`)

```markdown
## NR-G-{N} — {short pattern name}
- First seen: {audit_name, date}
- Last reaffirmed: {audit_name, date}
- Pattern: {grep-able or one-sentence description of the path family}
- Why cleared (canonical): {refutation argument that has held}
- Fragility envelope: {when does this flip}
- Audit history: [{audit_name, date, outcome: REAFFIRMED / CONTRADICTED / N/A}]
- PRIOR_NEGATIVE_OVERRIDDEN count: {N — how many audits found a real bug despite the NR}

# v1.7-PATCH4 PATCH 5 — Applicability metadata (REQUIRED for all new NR-G; back-fill on next audit cycle for existing entries)
- Applicability: {
    protocol_family: {one of: amm-spot / amm-cl / lending-borrow / vault-erc4626 / staking / governance / bridge-msg / oracle / nft-marketplace / dex-aggregator / other},
    trust_model_class: {one of: untrusted-only / single-admin / multisig-no-timelock / multisig-with-timelock / fully-decentralized / other},
    external_dependency_model: {one of: chainlink-only / pyth-only / oracle-mixed / aave-pool / uniswap-v3 / curve / balancer / no-external / other},
    exploit_precondition_class: {one of: instant-unrestricted / requires-approval / requires-balance-N / requires-time-window / requires-admin-cooperation / requires-flash-loan / multi-tx / other}
  }
- Generalizability scope: {LOCAL / WIDE} - LOCAL = applies only when ALL four applicability fields match. WIDE = applies when 3 of 4 match (used sparingly, for mechanically-universal refutations like "constant-true-by-construction" or "EVM-level invariant").
```

## § PRIOR_NEGATIVE handling (Phase 5.6.1, attack_thesis.md v3) — STRICTER MATCHING per v1.7-PATCH4 PATCH 5

When generating attack_thesis.md v3, the orchestrator checks each path against `~/.valves/state/negative_results.md` using **structured applicability matching**, not pattern fuzzy-match alone.

**Applicability test for each NR-G candidate match**:

```
def is_applicable(nr_g, current_audit_context):
    # Pattern match required first (existing behavior)
    if not pattern_matches(nr_g.pattern, current_path):
        return False, None

    # v1.7-PATCH4 strict applicability
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

**Outcome routing**:

- **Path matches NR-G AND applicability test PASSES (all required fields align)** -> mark `PRIOR_NEGATIVE_INHERITED` and downgrade to REFUTED with citation. **This is the only path that produces clearance-strength evidence.**
- **Path matches NR-G BUT applicability test FAILS** -> the NR-G is **advisory only**. Annotate the path with `PRIOR_NEGATIVE_ADVISORY` (NOT inherited) and cite the NR-G with the mismatch reason ("protocol_family differs: NR-G says lending-borrow, this audit is amm-spot"). Path stays at its v2 status. Session B verifier may consider the advisory as context but MUST NOT treat it as clearance evidence.
- **Path matches NR-G AND this audit has [POC-PASS]** -> mark `PRIOR_NEGATIVE_OVERRIDDEN`, increment the count in the global file, cite the prior NR. (Unchanged from before — overrides apply regardless of applicability since real on-chain proof beats prior reasoning.)
- **No match** -> standard v3 status rules apply.

PRIOR_NEGATIVE annotations carry into the report's Residual Risk Summary. The new `PRIOR_NEGATIVE_ADVISORY` tag is reported separately so reviewers see "we considered this as context" vs "we cleared this on prior evidence".

## § Backward compatibility (existing NR-G entries without applicability metadata)

NR-G entries written before v1.7-PATCH4 lack applicability metadata. The orchestrator MUST treat them as **advisory only** until they are back-filled. Specifically:

- Entries without `Applicability:` block -> `is_applicable() returns False` -> route to `PRIOR_NEGATIVE_ADVISORY`. They cannot produce clearance-strength evidence under v1.7-PATCH4 rules.
- The Promotion Protocol (Phase 5.6.4) MUST emit `Applicability:` and `Generalizability scope:` for every newly-promoted NR-G. Promotion fails if either field is missing.
- Back-filling existing entries is a manual one-time act: the user opens `~/.valves/state/negative_results.md`, adds the four applicability fields and scope per existing canonical pattern. Until back-filled, those entries downgrade to advisory.

This conservative default prevents broad reuse of pre-v1.7-PATCH4 NRs that may not actually apply to a new audit's protocol family / trust model / etc.

## § Evidence age / drift awareness (v1.7-PATCH5 PATCH 6 — minimal)

Even with strict applicability matching (PATCH 5 / v1.7-PATCH4), an NR-G can still be stale because the EXTERNAL world it was cleared against has shifted: external dependencies upgraded, protocol idioms changed, security posture evolved. This is a separate axis from applicability — the audit context fields can match exactly while the NR is no longer trustworthy.

This patch adds one minimal field to the NR-G schema:

```markdown
- evidence_age_class: {CURRENT | STALE | UNKNOWN}
```

**Field semantics**:

- **CURRENT** — the refutation evidence has been verified within the last 6 months OR the most recent audit reaffirmation is within the last 6 months. The orchestrator MUST automatically demote `CURRENT` -> `STALE` when reading the entry if `Last reaffirmed` is older than 6 months OR `First seen` is older than 6 months and there is no later reaffirmation. This demotion is mechanical and deterministic.
- **STALE** — the entry has not been reaffirmed within the last 6 months. May be advisory only; cannot produce clearance-strength evidence even if applicability passes.
- **UNKNOWN** — not yet classified. Treated as STALE for matching purposes (conservative bias).

**Demotion algorithm (mechanical, orchestrator-inline at Phase 5.6.1)**:

```
def derive_age_class(nr_g, today):
    last_event = max(nr_g.first_seen, nr_g.last_reaffirmed) if nr_g.last_reaffirmed else nr_g.first_seen
    age_days = (today - last_event).days

    if age_days <= 180:  # 6 months
        return 'CURRENT'
    else:
        return 'STALE'

# Override: if entry has explicit evidence_age_class field, use it; ELSE compute from dates.
# This lets a maintainer manually mark UNKNOWN or STALE even within 6 months when external
# dependencies have changed (e.g., Aave V3 migrated to V3.1 — old V3-cleared NRs become STALE
# even if dates are recent).
```

**Outcome routing (extends PATCH 5 PRIOR_NEGATIVE handling)**:

| Applicability test | evidence_age_class | Outcome |
|---|---|---|
| PASS | CURRENT | `PRIOR_NEGATIVE_INHERITED` (clearance-strength) |
| PASS | STALE | `PRIOR_NEGATIVE_ADVISORY` with reason `STALE_NEEDS_REVALIDATION` (NOT clearance-strength) |
| PASS | UNKNOWN | `PRIOR_NEGATIVE_ADVISORY` with reason `UNKNOWN_AGE_TREATED_AS_STALE` |
| FAIL | any | `PRIOR_NEGATIVE_ADVISORY` (existing PATCH 5 behavior — applicability mismatch dominates) |
| matches NR-G AND audit has [POC-PASS] | any | `PRIOR_NEGATIVE_OVERRIDDEN` (real evidence beats prior reasoning regardless of age) |

**Revalidation workflow** (manual, per-audit):

When an audit reaffirms an NR-G that was STALE -> CURRENT:
1. The Promotion Protocol (Phase 5.6.4) updates the entry's `Last reaffirmed` field to today's date.
2. The orchestrator inline computes the new `evidence_age_class` and writes it back if the entry has an explicit field.
3. The reaffirmation is recorded in the entry's `Audit history` table.

**Hard rules**:

- The 6-month threshold is conservative-default. Stale NRs go to advisory automatically; no agent decides.
- `evidence_age_class` is OPTIONAL on existing entries (back-compat). If absent, derived from `Last reaffirmed` / `First seen` dates per the algorithm above. If dates are also missing, treated as UNKNOWN -> STALE-equivalent.
- This rule is OBSERVATIONAL and SAFE: it tightens which NR-Gs can clear, never loosens. Recall is preserved (advisory NR-Gs don't disappear; they just stop producing clearance-strength evidence).
- Adding this field to existing entries is back-fill (same workflow as applicability metadata). Until back-filled, the date-derived computation produces a sensible default.

**Why this is minimal**:

- ONE new optional field. No aging system, no temporal-machinery, no time-decay calculations beyond a 6-month-threshold check.
- Demotion is mechanical and deterministic.
- Existing PATCH 5 applicability matching is unchanged; this stacks on top as an additional gate.
- Backward-compatible: derives a sensible default when the field is missing.

**Why this is high-ROI**:

- The audit world moves fast. Aave V3 -> V3.1, Uniswap V3 -> V4, Compound V2 -> Comet, Balancer V2 -> V3 — all happened within 18 months. NR-Gs cleared against the older versions can become stale even when the protocol family + trust model nominally match.
- Without this, NR memory grows toward overconfidence. With this, NR memory ages gracefully without manual maintenance burden.
- Stale -> advisory routing means Session B verifier still investigates the path; the NR-G context is preserved for the reviewer.

## § Why stricter applicability improves trustworthiness (and doesn't reduce recall)

- **Trustworthiness**: clearance-strength evidence now requires structured field-level alignment, not pattern fuzz. A reviewer can see exactly why an NR-G applied (matches=4/4 LOCAL) or why it didn't (matches=2/4, two fields differ).
- **No recall loss**: NRs that don't apply now go to advisory rather than incorrectly clearing the path. Session B's verifier still investigates the path; the NR-G is just context, not refutation.
- **No FP risk**: stricter clearance reduces wrong dismissals. The trade-off is some advisory annotations in reports — they're explicit, low-noise.
- **Backward-compatible**: existing entries automatically downgrade to advisory until back-filled, so v1.7-PATCH4 doesn't silently change interpretation of historical state.

## Promotion archive

The user's manifest also includes `~/.valves/state/negative_results_archive.md` (Phase 3). When a global NR-G is contradicted (`CONTRADICTED` outcome in audit_history with verified PoC), it is moved to the archive with the contradicting audit cited. The archive is read-only documentation; live NR matching uses only `~/.valves/state/negative_results.md`.

## Why this matters

Without NR memory, audits become a treadmill of re-clearing the same paths. With NR memory, depth agents can spend budget on novel paths and the report can clearly distinguish "we considered this and cleared it" from "we didn't look".
