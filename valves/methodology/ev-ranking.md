# EV-Ranked Verification -- Prioritization Methodology

> Extracted from verification-priority-queue.md (v1.7.0-PATCH12).
> Orchestration removed -- methodology preserved for overlay injection.
> Used by: chain, verification, skeptic phases.

---

## Why EV-ranked

Verification budget is finite. Severity-ranked spawning verifies a HIGH that's already obvious before a Medium that would be the audit's most informative result. EV ranking spends budget on the findings whose verifier outcome maximizes information gain * impact * actual leverage on the cluster, not on findings that are already pre-confirmed by their evidence chain.

## EV formula

```
EV(F) = impact_weight(severity)
      x thesis_alignment(F, attack_thesis.md)
      x cluster_leverage(F, root_cause_clusters.md)
      x poc_cost_factor(F)          // bucketed 0.30-1.00
      x information_gain(F)
```

### Term definitions

- **`impact_weight(severity)`**: Critical=1.0, High=0.8, Medium=0.5, Low=0.2, Info=0.05.
- **`thesis_alignment(F)`**: 1.5 if F is referenced as supporting evidence in `attack_thesis.md` v2 (CANDIDATE or WEAKENED path); 1.0 otherwise.
- **`cluster_leverage(F)`**: bonus when verifying F lets the cluster inherit. = 1.0 + 0.1 x (cluster_size - 1), capped at 1.5. F must be a cluster representative for the bonus to apply.
- **`poc_cost_factor(F)`**: bucketed 0.30 / 0.50 / 0.75 / 1.00 by estimated effort (high effort -> low factor -> de-prioritized; low effort -> high factor -> prioritized when other terms are equal).
  - 1.00 = pure code trace, no harness needed
  - 0.75 = unit-test PoC, no fork
  - 0.50 = fork test, single network state
  - 0.30 = fuzz / multi-block / multi-actor / Medusa-style
- **`information_gain(F)`**: 1.0 when the verifier outcome is genuinely uncertain (depth confidence 0.4-0.7); 0.7 if confidence >= 0.7 (already mostly known); 0.5 if confidence < 0.4 (likely refuted regardless).

## EV bonuses (additive after multiplicative formula)

- **+2 EV** for findings at Tier A diff-audit locations.
- **+3 EV** for Chain Hypotheses (CH-* IDs). Chains are higher-signal than individual findings.
- **+1 EV** for findings in the Reality-HIGH / Report-LOW quadrant (high real-world impact, weak in-report evidence so far).

## Cluster Inheritance

When a cluster representative returns `[POC-PASS]`, non-representative instances inherit a `[POC-PASS:BC-NNN-INHERITED]` tag and **skip** their own verifier spawn -- IF AND ONLY IF every condition holds:

1. Same access control as the representative (untrusted vs admin-only).
2. Same fix verbatim (same diff, same modifier added).
3. Same severity tier after R17 floor.
4. Same exploit path family (token_flow / state_trace / edge_case / external).
5. Same trust assumption from `design_context.md`.

If ANY condition fails, inheritance does NOT apply, and the instance must be verified independently.

When a cluster representative returns `[POC-FAIL]` or `CONTESTED`, **inheritance does NOT apply at all**. Each cluster member is verified independently or remains at its scoring-derived verdict. Failure does not propagate.

## Orphan Reserve

10-15% of verification budget is pre-allocated to "orphan" findings -- those without a strong cluster, thesis, or chain. Without the reserve, EV ranking would crowd out singletons that could be the audit's only Critical. Orphans are EV-ranked among themselves; their reserve runs after the main queue's mode-policy scope is met.

## Rescue Reserve

10-15% of verification budget is pre-allocated to **rescued targets** -- findings whose discovery path went through a rescue mechanism. These are findings the audit would have missed without the rescue layer; they need representation in verification or the rescue mechanism's value is invisible.

### Eligibility (a finding qualifies for rescue reserve iff it matches ANY ONE of):

1. **Proof-gap downgrade rescue** -- the finding originated from a seed whose outcome was DOWNGRADED from CLEARED_PRE_DEPTH to FORWARD_TO_SESSION_B with reason `INSUFFICIENT_CLEAR_PROOF`, AND Session B's DA pass promoted that seed to a finding.
2. **Slack redistribution rescue** -- the finding originated from a handoff row marked `[REDISTRIBUTED]`, AND Session B's DA / chain / verifier path promoted that row to a finding.
3. **Sibling-link assist** -- the finding's depth or verifier output cites a linked canonical seed as a contributing investigation hint.
4. **Cross-source canonical rescue** -- the finding originated from a canonical seed entry with Members >= 2 from >= 2 different sources (harvester + AB, harvester + analog, AB + analog) AND the canonical was Normalized Outcome=FORWARD_TO_SESSION_B at COMPLETE_A AND was promoted in Session B.
5. **Family-diversity overflow promoted to finding** -- the finding originated from a family-cap overflow list refill row AND Session B promoted it.

### Reserve sizing and routing

- **Reserve size**: 10-15% of total verification budget, equal to the orphan reserve. The two reserves are SEPARATE -- a finding qualifies for AT MOST ONE reserve.
- **Priority within reserve**: rescued targets are EV-ranked using the existing EV formula PLUS a +1 EV bonus per rescue source matched (a finding hitting categories 1+3+4 gets +3 EV). Tie-break by severity descending.
- **Eligibility precedence (a finding can claim only one reserve)**: rescue reserve > orphan reserve > main queue. A rescued finding that's also an orphan goes to rescue reserve (rescue is the higher-signal classification).
- **Spawn order**: main queue first (mode-policy scope met) -> rescue reserve -> orphan reserve. Rescue runs ahead of orphans because rescued targets have multi-mechanism evidence; orphans are by definition uncited.

### Hard rules

- This is a RESERVE, not a second queue system.
- A weak rescued target (EV < 0.30 even with the +1 bonus) does NOT bypass strong main-queue findings. The reserve is a budget allocation, not a priority elevation.
- Eligibility classification is mechanical: scan seed outcomes (DOWNGRADED column), handoff redistributions, depth/verifier linked CS citations, and canonical seed member counts. No agent decides eligibility.

### Rescue-class diversity control

**Goal**: prevent the rescue reserve itself from being dominated by one rescue class. Without this, an audit with 12 proof-gap downgrade rescues and 1 cross-source canonical rescue would fill all reserve slots with proof-gap-class entries, blinding verification to the cross-source signal.

**Cap**: soft cap of **1-2 entries per rescue class** in the rescue reserve, applied AFTER EV ranking + bonus.

**Algorithm (mechanical, deterministic)**:

```
# Inputs:
#   eligible_pool = all findings matching Eligibility (post EV-with-rescue-bonus ranking)
#   reserve_size = 10-15% of total verification budget (existing)
#   class_cap = 2  # soft cap per rescue class

# Step 1: exemption check (preserve recall on small pools)
if len(eligible_pool) < 4:
    # Tiny pool -- diversity control NOT applied; preserve full reserve allocation
    reserve = top_N_by_EV(eligible_pool, n=reserve_size)
    diversity_applied = False
    return reserve

diversity_applied = True

# Step 2: walk EV-ranked pool top-down, applying soft cap per rescue class
reserve = []
overflow = []
class_count = {}  # rescue_class -> count in reserve

for cand in eligible_pool:
    if len(reserve) >= reserve_size:
        break
    # A finding may match multiple rescue classes. The "primary class" is the
    # highest-priority class it matches, by this fixed precedence:
    #   proof-gap downgrade > slack redistribution > sibling-link assist
    #   > cross-source canonical > family-diversity overflow
    primary_class = cand.primary_rescue_class

    if class_count.get(primary_class, 0) >= class_cap:
        # Class cap reached -- hold candidate in overflow
        overflow.append(cand)
        continue
    reserve.append(cand)
    class_count[primary_class] = class_count.get(primary_class, 0) + 1

# Step 3: refill from overflow if reserve underfilled
# Preserves recall: when only 2 distinct rescue classes exist, refill from
# overflow in EV-rank order to fill remaining reserve slots.
i = 0
while len(reserve) < reserve_size and i < len(overflow):
    reserve.append(overflow[i])
    i += 1

return reserve, diversity_applied, overflow_promoted=i
```

**Hard rules for diversity control**:

- The cap is **soft** -- when the reserve underfills, overflow refills it in EV-rank order. We never lose recall to enforce diversity.
- **Primary-class assignment is deterministic**: when a finding matches multiple rescue classes, it counts toward the highest-priority class only. The +1 EV bonus per matched class still applies in the EV computation.
- **Exemption when pool < 4**: diversity is meaningless on tiny pools and forcing it would suppress real signal. Reserve goes to top_N_by_EV without filtering.
- **EV ranking is preserved within class**: the cap only filters across classes; within a class, top-EV candidates win. Strong rescued targets do not lose to weak ones from a different class.

## Mode policy

- Light: verifier scope = ALL Medium+
- Core: verifier scope = ALL Medium+
- Thorough: verifier scope = ALL severities + fuzz variants

## Batched Spawning (>8 verifiers)

| Batch | Contains | Model | Max parallel |
|---|---|---|---|
| A | Chain hypotheses (CH-*) + High standalone | opus | all (typically 7-10) |
| B | Medium first half (<=6) | sonnet | 6 |
| C | Medium second half (<=6) | sonnet | 6 |
| D | Low + Info | sonnet | 1 (single agent covers all) |

If a tier has <= 6, it fits in one batch. If > 6, split into <=6 sub-batches. Chains + High always batch together (both opus).

## Verifier short-return convention

```
Return: '{HYPOTHESIS_ID}: {VERDICT} | {evidence_tag} | {1-sentence justification}'
```

Full output goes to the verify file. Return messages stay ~50 tokens to keep context light.
