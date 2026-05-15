<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Session A → B Handoff (PATCH I)

Source-of-truth for `{SCRATCHPAD}/session_a_to_b_handoff.md`. Single best-effort, ranked target sheet for Session B. Replaces `blind_spot_report.md` as the **authoritative input** Session B reads when prioritizing its DA pass; `blind_spot_report.md` continues to be written for back-compat (and is one of the inputs here).

## Where it runs

Inside the existing COMPLETE_A boundary, in the new Session A → B Handoff Build sub-step. Written after `coverage_density.md`, `negative_space.md`, `seed_outcomes.md`, `disagreement_queue.md`, and `blind_spot_report.md`. Written BEFORE the final rewrite of `session_checkpoint.md`.

**v1.7-PATCH11 physical isolation**: After the handoff bundle is built, the entire `.audit_scratchpad` is renamed to `.audit_session_a` and a fresh `.audit_scratchpad` is created containing ONLY this file and other allowlisted handoff artifacts. Session B reads this file from the fresh scratchpad — it NEVER reads it from the archive. The handoff is the ONLY analytical bridge between sessions; everything else (findings, hypotheses, depth analysis, verdicts) is physically inaccessible until cross-session consensus.

## Inputs (read-only; this artifact synthesizes — it does not duplicate)

- `{SCRATCHPAD}/blind_spot_report.md` — coverage-gap data (existing, back-compat).
- `{SCRATCHPAD}/coverage_density.md` — risky-but-underexplored map (PATCH A).
- `{SCRATCHPAD}/canonical_seed_map.md` — canonical (deduplicated) seed clusters (v1.7-PATCH2 PATCH 1). **Authoritative source for § 2 of the handoff.**
- `{SCRATCHPAD}/seed_outcomes.md` — raw per-seed bookkeeping (PATCH B). Used as fallback only when canonical_seed_map.md is missing (SOFT gate degraded).
- `{SCRATCHPAD}/disagreement_queue.md` — high-signal contradictions (PATCH C).
- `{SCRATCHPAD}/negative_space.md` — explicit zero-finding high-risk areas (PATCH E).
- `{SCRATCHPAD}/confidence_scores.md` — uncertain Medium+ findings (UNCERTAIN/LOW band).
- `{SCRATCHPAD}/findings_inventory.md` — to detect orphan / non-thesis candidates.
- `{SCRATCHPAD}/attack_thesis.md` v1 → v2 — to mark which findings are thesis-aligned vs orphan.

> Note (v1.7-PATCH2): `analog_seeds.md` and `assumption_breaker_seeds.md` are NO LONGER read directly here. Their unresolved seeds reach this handoff via `canonical_seed_map.md` (after dedup). This eliminates duplicate seeds across § 2 and prevents source-mix bias in the Top unresolved seeds list.

## § Output (`session_a_to_b_handoff.md`) — fixed six-section schema

The output has EXACTLY these six top-level sections, in this order. Do not add, reorder, or rename. This stability is what makes Session B's read deterministic.

```markdown
# Session A → B Handoff — {project} — {ISO timestamp}

> Single ranked target sheet for Session B's DA pass. Read by Session B BEFORE chain analysis,
> verification, or any depth iter 2/3 spawn. Section order is fixed; ranking inside each section
> is by exploitability-weighted score (see § Ranking).

## 1. Top dangerous blind spots (capped 5)
| Rank | Target | Type | Why dangerous | Risky-fn ratio | Coverage Score | Recommended depth domain |
|---|---|---|---|---|---|---|
| 1 | Vault.sol | low-coverage module | 8 risky fns, 0 findings, depth never touched | 8/12 | 0.05 | edge_case |
| ... |

(Source rows: coverage_density.md priorities + blind_spot_report.md § Low-Coverage Modules.
 Selection rule: Coverage Score ≤ 0.30 AND Risky Functions ≥ 3, deduplicated, top 5.)

## 2. Top unresolved seeds (capped 6, eligible for slack expansion per § Slack redistribution; family-diversity capped per v1.7-PATCH4 § Family-diversity cap)
| Rank | Canonical Seed ID | Source Provenance | Primary Location | Seed Family | Why unresolved | Linked CS (v1.7-PATCH3) | Open Question (v1.7-PATCH7) | Disputed Assumption (v1.7-PATCH7) | Heuristic Lens (v1.7-PATCH8) | Recommended depth domain |
|---|---|---|---|---|---|---|---|---|---|---|

(Source rows (v1.7-PATCH2): **`canonical_seed_map.md` WHERE Normalized Outcome = FORWARD_TO_SESSION_B**, ranked.
 Ranking inside this section by Seed Family: E8 EMERGENCY (custody/recovery) > E11 SEQUENCE (call-order, v1.7-PATCH7) > E2 INTERFACE > E5 EXTERNAL-DEP > E7 MIRROR-ACCT > E6 RECIPIENT > E1 SYMMETRIC > E10 ADMIN-LIVE-POINTER > E3 CONFIG-DRIFT > E4 PARITY > E9 TRUST-MODEL.
 Tie-break by Members count descending — canonicals with multi-source provenance (>= 2 different sources hitting same target) outrank single-source canonicals.
 **Family-diversity cap (v1.7-PATCH4 PATCH 3)**: soft cap of 2 entries per Seed Family. After applying the family rank + Members tie-break, walk the ranked list top-down and DROP any row that would push a Seed Family above 2 entries — that row is held in a per-section overflow list. Continue walking until § 2 has 6 entries OR all candidates are exhausted. **Exemption**: if the total candidate pool (canonical_seed_map.md FORWARD entries) has fewer than 4 unique entries, the diversity cap is NOT applied (so we don't suppress real signal in tiny audits). After the diversity walk completes, if § 2 has < 6 entries AND the overflow list is non-empty, refill from the overflow list in original rank order until the cap is reached or overflow is exhausted (this preserves recall while maintaining family spread).
 v1.7-PATCH3: `Linked CS` column displays sibling canonicals (max 3 per row) from `canonical_seed_map.md` § Sibling Links. Format: `CS-N (link-type)` comma-separated. Empty if no sibling links.
 v1.7-PATCH7: `Open Question` and `Disputed Assumption` columns are pasted verbatim from `canonical_seed_map.md` (see § Schema in that file). Empty values are normalized to `-`. Session B's DA agent prompts read these columns to bias its adversarial probe — when present, the DA agent MUST attempt to answer the question or refute the assumption before falling back to general re-attack. The orchestrator does NOT invent these fields; if the canonical's row has `-`, this row has `-`.
 v1.7-PATCH8: `Heuristic Lens` column is pasted verbatim from `canonical_seed_map.md`. Tag enum: `SYMMETRY` / `STATE-TRANSITION` / `SEQUENCE` / `BIG-VS-SMALL` / `NUMERIC-EXTREME` / `NONEXISTENT-ID` / `TEST-SKEPTIC` / `DEAD-STATE` / `-`. Session B's DA agent prompt routes through the lens: when present, the DA agent applies the corresponding lens methodology from `~/.valves/rules/valves-doctrine.md` § Heuristic Lenses BEFORE general re-attack — e.g., a `STATE-TRANSITION` row prompts the DA to test invalid state-machine transitions; a `BIG-VS-SMALL` row prompts split/aggregate equivalence testing; a `NONEXISTENT-ID` row prompts attacker-controlled identifier paths.
 Fallback: if `canonical_seed_map.md` is missing (SOFT gate degraded), fall back to `seed_outcomes.md` Outcome=FORWARD_TO_SESSION_B with the legacy ranking; the Linked CS / Open Question / Disputed Assumption / Heuristic Lens columns read `-`; the family-diversity cap is NOT applied (raw bookkeeping has no Seed Family column); this is documented in `seed_outcomes_FALLBACK_USED` in `degradation_log.md`.)

## 3. Top disagreements (capped 5)
| Rank | Queue ID | Related IDs | Location | Disagreement type | Why it matters | Session B owner |
|---|---|---|---|---|---|---|

(Source rows: disagreement_queue.md, sorted by exploitability impact.)

## 4. Top negative-space targets (capped 5)
| Rank | Target | Type | Why dangerous | Recommended Session B domain |
|---|---|---|---|---|

(Source rows: negative_space.md, sorted by danger class:
 zero-finding emergency path > governance/pause/upgrade > reward/accounting > cross-contract.)

## 5. Top uncertain findings requiring DA re-investigation (capped 6)
| Rank | Location | Evidence gap | Investigation question | Recommended depth domain |
|---|---|---|---|---|

(Source rows: confidence_scores.md where severity ≥ Medium AND composite < 0.70.
 Ranking: by evidence gap severity (least evidence first).
 v1.7-PATCH11 REDACTION: Session A finding IDs, severity labels, and composite
 confidence scores are STRIPPED from the agent-visible schema. These leak Session A
 framing and bias Session B's fresh-eyes analysis. The orchestrator records the
 mapping internally in run_state.json but agents see ONLY: Location, Evidence gap
 (what specific evidence is missing), Investigation question (what to explore),
 and Recommended depth domain. The finding ID column is replaced by rank order.)

## 6. Top orphan investigation targets (capped 5)
| Rank | Location | Gap description | Recommended depth domain |
|---|---|---|---|

(Source rows: findings_inventory.md entries that
   (a) are NOT cited as supporting evidence in attack_thesis.md (any version),
   (b) have no cluster representative role in finding_classification.md,
   (c) are severity ≥ Medium.
 Hard cap of 5 — orphans expand fast and Session B is precision-focused.
 v1.7-PATCH11 REDACTION: Session A finding IDs and severity labels are STRIPPED.
 Agents see Location + Gap description + Recommended depth domain.
 The orchestrator maps ranks to internal IDs for cross-referencing.)
```

## § Ranking — exploitability score, not coverage sparseness

For every row in every section, the orchestrator computes:

```
score = 0.40 × severity_weight       // Critical=1.0, High=0.8, Medium=0.5, Low=0.2
      + 0.20 × thesis_alignment      // 1.0 if path-aligned (v1/v2), else 0.0
      + 0.20 × cluster_leverage      // 1.0 if cluster representative, scales with cluster size
      + 0.10 × coverage_lift_signal  // 1.0 if from a Coverage Score ≤ 0.30 contract
      + 0.10 × disagreement_signal   // 1.0 if also present in disagreement_queue.md
```

Higher score = higher rank within its section. Section order itself is fixed (1 → 6); ranking is intra-section.

For § 2 (unresolved seeds) and § 4 (negative space), severity_weight is replaced by `risk_density_weight` (proportion of R-* flagged functions in the targeted contract).

For § 3 (disagreements), severity_weight is the higher of the two disagreeing verdicts.

## § Hard rule — Session B reads this, NOT Session A's reasoning

Session B's behavioral rules are unchanged: verifier independence + DA contrastive conditioning + fresh re-scoring still apply. The handoff is a **target sheet**, not a justification. It carries:
- WHAT to prioritize (rows above).
- WHY in one line (the table cells).
- NO Session A prose, NO Session A confidence justifications, NO "we believe X" language.

The §§ headings and the columns are mechanical. If a column would require Session A reasoning to fill, the field is blank or `-`.

## § Caps and totals

| Section | Default cap | Slack-eligible recipient (v1.7-PATCH3) |
|---|---|---|
| 1. Top dangerous blind spots | 5 | YES |
| 2. Top unresolved seeds | 6 | YES |
| 3. Top disagreements | 5 | NO |
| 4. Top negative-space targets | 5 | YES |
| 5. Top uncertain Medium+ findings | 6 | YES |
| 6. Top orphan / non-thesis candidates | 5 | NO |
| **Default total max rows** | **32** | |
| **Max additional slack slots (v1.7-PATCH3)** | **+3** | |
| **Max additional dominant-family override slot (v1.7-PATCH5)** | **+1** | |
| **Hard upper bound on final total** | **36** | |

The 32-row default cap remains the discipline. Session B has a finite DA budget (Thorough: 8–12 DA agent slots across iter 2-3). The handoff cannot exceed what Session B can act on.

## § Slack redistribution (v1.7-PATCH3 — PATCH 2)

**Goal**: when one section underfills (fewer qualified candidates than its cap allows) and another slack-eligible section has strong unresolved candidates above its cap, allow controlled overflow up to **+3 redistributed slots total** across the entire handoff.

**Slack-eligible recipient sections** (per the table above):
- § 1. Top dangerous blind spots
- § 2. Top unresolved seeds
- § 4. Top negative-space targets
- § 5. Top uncertain Medium+ findings

Sections § 3 (disagreements) and § 6 (orphans) are NOT slack-eligible. Disagreements are inherently bounded by the disagreement_queue.md analyst-curated list; orphans are precision-risk surface — extra orphan slots reward weak signal.

**Slack pool computation (mechanical, deterministic)**:

```
slack_pool = 0
for section in [§1, §2, §3, §4, §5, §6]:
  if section.actual_rows < section.default_cap:
    slack_pool += (section.default_cap - section.actual_rows)
slack_pool = min(slack_pool, 3)   # hard cap at 3 redistributed slots
```

Slack accumulates from ANY underfilling section (including § 3 and § 6 — they contribute to the pool but cannot receive from it).

**Distribution algorithm**:

```
# Surplus candidates per slack-eligible recipient section
for section in [§1, §2, §4, §5]:
  surplus_candidates = candidates_passing_section_filter MINUS already-included rows
  rank surplus_candidates by exploitability score (the existing § Ranking formula)

# Global redistribution queue: take the top surplus candidate per recipient section,
# rank across sections, fill slack pool deterministically.
redistribution_queue = []
while slack_pool > 0:
  best_candidate = highest-scored surplus candidate across all 4 slack-eligible sections
  if best_candidate.score < threshold:  # threshold = 0.40 (mid Medium severity baseline)
    break  # don't redistribute weak candidates even when slack is available
  redistribution_queue.append(best_candidate)
  remove best_candidate from its section's surplus list
  slack_pool -= 1

# Append redistributed rows to their target sections, marked with `*redistributed`
for row in redistribution_queue:
  append row to row.target_section with annotation [REDISTRIBUTED]
```

**Hard rules**:
- Slack flow is CAPPED at +3 total. If 4 sections underfill by 2 each (8 unused slots), still only 3 are redistributed.
- Slack does NOT flow to § 3 (disagreements) or § 6 (orphans) — those caps are absolute.
- Slack candidate score must clear the **0.40 threshold** (mid-Medium baseline). Below threshold, slack stays unused — no weak orphan spam, even with capacity available.
- Redistribution is deterministic: ranked by the existing § Ranking formula; ties broken by section priority (§ 2 > § 1 > § 4 > § 5 — unresolved seeds outrank blind spots outrank negative-space outrank uncertain findings).
- Redistributed rows are **annotated** `[REDISTRIBUTED from section underfill]` in their final row, so Session B sees that they came via slack — not via the section's primary source.

**Output: redistribution metadata section in `session_a_to_b_handoff.md`**:

The handoff artifact gains a new top section (between the title block and § 1) that records the redistribution mechanics:

```markdown
## 0. Redistribution Metadata (v1.7-PATCH3)
- redistributed_from: [{section_id, slots_donated}, ...]
- redistributed_to: [{section_id, slots_received, candidate_ids}, ...]
- slack_slots_used: {0..3}
- final_total_targets: {32..36}   # 32 default + up to 3 slack (v1.7-PATCH3) + up to 1 dominant-family override (v1.7-PATCH5)
- threshold_blocked: {true/false} — whether slack went unused because all surplus candidates fell below 0.40 score threshold
```

If `slack_slots_used == 0` (no underfill, OR all underfills compensated by no surplus, OR threshold blocked), this section is still emitted with the explicit zeros — silence is not a valid state.

**Why this improves Session B without blurring the boundary**:

- Session B gets a little more reach (+3 slots, +9% capacity at most) without losing structure.
- The 0.40 threshold prevents weak-signal expansion: slack only flows to candidates that would have been worth investigating even at the section's primary cap.
- Slack flows ONLY to high-signal recipient sections (canonical unresolved seeds, blind spots, negative-space, uncertain Medium+). Orphans and disagreements remain hard-capped.
- The mechanism is mechanical — no agent decides what gets redistributed. The orchestrator-inline build computes the ranking deterministically.
- Redistribution metadata is preserved so Session B and post-audit calibration can see what was redistributed and why.

## § Family-diversity cap (v1.7-PATCH4 — PATCH 3)

**Goal**: prevent § 2 (Top unresolved seeds) from being dominated by one Seed Family. Without a diversity cap, an audit with 12 unresolved E1 SYMMETRIC canonicals and 1 each of E2/E5/E6/E8 would fill all 6 § 2 slots with E1 SYMMETRIC, blinding Session B to the cross-surface signals.

**Cap**: soft cap of **2 entries per Seed Family** in § 2.

**Algorithm (mechanical, deterministic — orchestrator inline)**:

```
# Inputs:
#   ranked_pool = canonical_seed_map.md FORWARD entries, ranked by (family priority, Members desc, score)
#   total_pool_size = len(ranked_pool)

# Step 1: exemption check
if total_pool_size < 4:
    # Tiny audit — diversity cap NOT applied; preserves recall on small candidate pools
    section_2 = ranked_pool[:6]
    family_diversity_cap_applied = False
    return section_2

family_diversity_cap_applied = True

# Step 2: walk ranked pool top-down, applying soft cap
section_2 = []
overflow = []
family_count = {}  # family_id -> count in section_2

for cand in ranked_pool:
    if len(section_2) >= 6:
        break
    fam = cand.seed_family
    if family_count.get(fam, 0) >= 2:
        # Cap reached for this family - hold candidate in overflow
        overflow.append(cand)
        continue
    section_2.append(cand)
    family_count[fam] = family_count.get(fam, 0) + 1

# Step 3: refill from overflow if section_2 is short
# This preserves recall: when the diversity walk underfills (e.g., audit has only 2 distinct families),
# we refill from overflow in original rank order so we don't waste section_2 slots.
i = 0
while len(section_2) < 6 and i < len(overflow):
    section_2.append(overflow[i])
    i += 1

return section_2, family_diversity_cap_applied, overflow_held = i  # i = how many overflow candidates were promoted back
```

**Recorded in handoff § 0 Redistribution Metadata** (v1.7-PATCH4 extension):

```
- family_diversity_cap_applied: {true/false}
- families_capped: [{family_id, candidates_held: N}, ...]
- diversity_overflow_promoted: {N}   # how many overflow candidates were refilled back to fill empty slots
```

**Hard rules**:

- The cap is **soft** — when § 2 underfills, overflow refills it. We never lose recall to enforce diversity.
- The cap applies **after** family-priority ranking, so highest-priority families (E8 EMERGENCY etc.) still get 2 slots before others compete for the remaining 4.
- Tie-break inside a family: Members count descending. The strongest 2 entries from the dominant family get the slots; weaker entries from the same family go to overflow.
- The cap applies ONLY to § 2 (canonical unresolved seeds). § 1, § 3, § 4, § 5, § 6 do NOT use family-diversity caps — their input pools don't have a Seed Family taxonomy.
- The cap is bypassed when the FORWARD pool has < 4 entries — diversity is meaningless on a tiny pool, and forcing it would suppress real signal.

**Why this increases Session B target diversity (and not FP risk)**:

- Diversity exposes Session B to multiple attack surfaces in parallel. A high-recall E1 SYMMETRIC family doesn't drown out a single-but-real E5 EXTERNAL-DEP signal.
- The soft cap with overflow refill preserves total recall — § 2 still fills to 6 entries when candidates exist.
- No additional slots are added; this is pure routing improvement at fixed Session B budget.
- Tied to existing canonical merge predicate (Seed Family is already assigned by canonical_seed_map.md based on equivalence classes E1-E11; v1.7-PATCH7 added E11 SEQUENCE).
- Deterministic and observable in handoff § 0 metadata — auditors can see when the cap fired and which families were held.

## § Dominant-family override (v1.7-PATCH5 PATCH 3)

**Problem the override solves**: the family-diversity cap (2 per family) sometimes underfeeds the real center of risk. When one family genuinely dominates the audit's attack surface — e.g., an AMM whose biggest risks are mostly E7 MIRROR-ACCT — the strict 2-per-family cap can hold back a third E7 candidate that materially outranks every alternative-family candidate.

**Goal**: allow at most **+1 extra slot for a dominant family** when its top held-back candidate materially outranks the next best alternative-family candidate. Bounded, deterministic, observable.

**Override eligibility (mechanical)**:

After the diversity walk produces the initial section_2 + overflow:

```
# Step A: identify the dominant family in overflow (if any)
if len(overflow) == 0:
    return  # no override possible

# The dominant family is the one with the most held-back candidates AND
# whose top held-back candidate has the highest EV among ALL held-back candidates.
overflow_by_family = group_by(overflow, key=lambda c: c.seed_family)
dominant_family = max(overflow_by_family, key=lambda fam: (
    len(overflow_by_family[fam]),  # most held-back
    max(c.score for c in overflow_by_family[fam])  # highest top score
))

top_dominant_held = max_by_score(overflow_by_family[dominant_family])

# Step B: identify the next-best alternative family in section_2 (NOT the dominant)
# This is the highest-scoring entry in section_2 from a family OTHER than dominant_family.
next_best_alt = max_by_score(
    [c for c in section_2 if c.seed_family != dominant_family]
)

if next_best_alt is None:
    # Edge case: section_2 has only entries from dominant_family. Should be impossible
    # under the 2-per-family cap unless len(section_2) <= 2.
    return  # no override

# Step C: compute the score gap
score_gap = top_dominant_held.score - next_best_alt.score

# Step D: the override fires iff the gap is materially large
OVERRIDE_THRESHOLD = 0.25  # absolute score-gap threshold (deterministic)

if score_gap >= OVERRIDE_THRESHOLD:
    # Override fires. Add ONE extra slot for the dominant family.
    section_2.append(top_dominant_held)
    overflow.remove(top_dominant_held)
    override_applied = {
        family: dominant_family,
        score_gap: score_gap,
        threshold: OVERRIDE_THRESHOLD,
        held_promoted: top_dominant_held.canonical_seed_id,
        next_best_alt: next_best_alt.canonical_seed_id,
        new_section_2_size: len(section_2)
    }
else:
    override_applied = None  # gap too small; cap holds

return section_2, family_diversity_cap_applied, overflow_promoted, override_applied
```

**Hard rules**:

- **Maximum +1 extra slot** for the dominant family. The override never adds 2+ extra slots, and never fires for non-dominant families.
- **Score gap threshold = 0.25** (deterministic, absolute on the existing § Ranking score scale where severity_weight maxes at 1.0). A gap of 0.25 is roughly the difference between a Critical-severity candidate and a Medium-severity candidate, OR between a multi-source canonical and a single-source canonical at the same severity. This threshold is conservative — small gaps do NOT trigger the override.
- **Override does NOT bypass the diversity cap as the default**: only fires when the gap is genuinely large. If two families both have strong candidates in overflow, the override does NOT fire (the dominant family's top is not materially ahead of the alternative).
- **§ 2 final size** can be at most: default cap (6) + slack (up to +3) + override (+1) = 10. The hard upper bound on the handoff total moves from 35 to 36.
- **Override interacts cleanly with slack redistribution**: slack runs first (handoff total up to 35), THEN family-diversity cap applies (within § 2), THEN dominant-family override (one final +1 if eligible). Order is fixed and deterministic.
- **Recorded in handoff § 0 Redistribution Metadata** (v1.7-PATCH5 extension):

```
# v1.7-PATCH5 PATCH 3 - dominant-family override
- dominant_family_override_applied: {true/false}
- dominant_family: {family_id or null}
- override_score_gap: {decimal or null}
- override_threshold: 0.25
- override_held_promoted: {canonical_seed_id or null}
- override_next_best_alt: {canonical_seed_id or null}
- final_total_targets: {32..36}   # upper bound bumped from 35 to 36
```

**Why this preserves diversity without starving real risk**:

- The cap stays the default. Override only fires when genuinely justified by a large score gap.
- Bounded at +1 — cannot turn into "dominant family always wins".
- Conservative threshold (0.25 absolute) prevents marginal cases from escalating.
- Deterministic and observable; auditors can see when the override fired and the score gap that justified it.
- A dominant family might genuinely BE the audit (an AMM where mirror-accounting is the central risk). The override expresses that without weakening diversity for non-dominant cases.

## § Hard gate

`session_a_to_b_handoff.md` MUST exist before Session B begins (Phase 4b iter 2 in Thorough; or the start of any post-COMPLETE_A resume). The Step 0-pre integrity check appends this file's existence to the assertion list at the COMPLETE_A resume branch.

If missing on a fresh COMPLETE_A write → re-spawn the Handoff Build (orchestrator inline, retry once). If still missing → ABORT with `SESSION_A_TO_B_HANDOFF_MISSING` violation.

## Why this improves Session B precision (and does not blur the boundary)

- Session B is **target-sharpened**, not target-broadened. The 32-row cap and per-section caps prevent the handoff from being a mini-breadth phase.
- The fixed schema makes Session B's read cost-bounded — Session B always knows what it is reading.
- The exploitability-weighted score routes DA budget to where Session A's gaps ARE most likely to harbor a real bug, not just where coverage is sparse on benign code.
- All inputs are Session A artifacts that already exist for back-compat reasons. No new agent spawn.
