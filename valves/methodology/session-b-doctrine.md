# Session B Doctrine — Adversarial Verification Methodology

> Extracted from session-a-to-b-handoff.md (v1.7.0-PATCH12).
> Orchestration removed — methodology preserved for overlay injection.
> Used by: depth iter 2-3 (DA role), verification, skeptic phases.

---

## Ranked Target Sheet Schema

The handoff target sheet has EXACTLY six top-level sections, in fixed order. This stability makes the read deterministic. Ranking within each section is by exploitability-weighted score.

### Section 1: Top Dangerous Blind Spots (capped 5)

| Rank | Target | Type | Why dangerous | Risky-fn ratio | Coverage Score | Recommended depth domain |
|---|---|---|---|---|---|---|

Selection rule: Coverage Score <= 0.30 AND Risky Functions >= 3, deduplicated, top 5.

### Section 2: Top Unresolved Seeds (capped 6, eligible for slack expansion; family-diversity capped)

| Rank | Canonical Seed ID | Source Provenance | Primary Location | Seed Family | Why unresolved | Linked CS | Open Question | Disputed Assumption | Heuristic Lens | Recommended depth domain |
|---|---|---|---|---|---|---|---|---|---|---|

Source rows: canonical seed map WHERE Normalized Outcome = FORWARD_TO_SESSION_B, ranked.

**Ranking inside this section** by Seed Family priority:
E8 EMERGENCY (custody/recovery) > E11 SEQUENCE (call-order) > E2 INTERFACE > E5 EXTERNAL-DEP > E7 MIRROR-ACCT > E6 RECIPIENT > E1 SYMMETRIC > E10 ADMIN-LIVE-POINTER > E3 CONFIG-DRIFT > E4 PARITY > E9 TRUST-MODEL.

Tie-break by Members count descending -- canonicals with multi-source provenance (>= 2 different sources hitting same target) outrank single-source canonicals.

**Open Question and Disputed Assumption columns**: pasted verbatim from the canonical seed map. Empty values normalized to `-`. DA agents MUST attempt to answer the question or refute the assumption before falling back to general re-attack. These fields are never invented; if the canonical's row has `-`, this row has `-`.

**Heuristic Lens column**: pasted verbatim from the canonical seed map. Tag enum: `SYMMETRY` / `STATE-TRANSITION` / `SEQUENCE` / `BIG-VS-SMALL` / `NUMERIC-EXTREME` / `NONEXISTENT-ID` / `TEST-SKEPTIC` / `DEAD-STATE` / `-`. DA agents route through the lens: when present, apply the corresponding lens methodology BEFORE general re-attack -- e.g., a `STATE-TRANSITION` row prompts the DA to test invalid state-machine transitions; a `BIG-VS-SMALL` row prompts split/aggregate equivalence testing; a `NONEXISTENT-ID` row prompts attacker-controlled identifier paths.

Fallback: if the canonical seed map is missing, fall back to raw seed outcomes WHERE Outcome=FORWARD_TO_SESSION_B with legacy ranking; the Linked CS / Open Question / Disputed Assumption / Heuristic Lens columns read `-`; the family-diversity cap is NOT applied.

### Section 3: Top Disagreements (capped 5)

| Rank | Queue ID | Related IDs | Location | Disagreement type | Why it matters | Session B owner |
|---|---|---|---|---|---|---|

Sorted by exploitability impact.

### Section 4: Top Negative-Space Targets (capped 5)

| Rank | Target | Type | Why dangerous | Recommended Session B domain |
|---|---|---|---|---|

Sorted by danger class: zero-finding emergency path > governance/pause/upgrade > reward/accounting > cross-contract.

### Section 5: Top Uncertain Findings Requiring DA Re-Investigation (capped 6)

| Rank | Location | Evidence gap | Investigation question | Recommended depth domain |
|---|---|---|---|---|

Source: confidence scores where severity >= Medium AND composite < 0.70.
Ranking: by evidence gap severity (least evidence first).

**Redaction rule**: Session A finding IDs, severity labels, and composite confidence scores are STRIPPED. These leak Session A framing and bias fresh-eyes analysis. Agents see ONLY: Location, Evidence gap (what specific evidence is missing), Investigation question (what to explore), and Recommended depth domain. The finding ID column is replaced by rank order.

### Section 6: Top Orphan Investigation Targets (capped 5)

| Rank | Location | Gap description | Recommended depth domain |
|---|---|---|---|

Source: findings inventory entries that (a) are NOT cited as supporting evidence in the attack thesis, (b) have no cluster representative role, (c) are severity >= Medium.

Hard cap of 5 -- orphans expand fast and Session B is precision-focused.

**Redaction rule**: Session A finding IDs and severity labels are STRIPPED. Agents see Location + Gap description + Recommended depth domain.

---

## Exploitability Score Formula

For every row in every section, compute:

```
score = 0.40 * severity_weight       // Critical=1.0, High=0.8, Medium=0.5, Low=0.2
      + 0.20 * thesis_alignment      // 1.0 if path-aligned (v1/v2), else 0.0
      + 0.20 * cluster_leverage      // 1.0 if cluster representative, scales with cluster size
      + 0.10 * coverage_lift_signal  // 1.0 if from a Coverage Score <= 0.30 contract
      + 0.10 * disagreement_signal   // 1.0 if also present in disagreement queue
```

Higher score = higher rank within its section. Section order itself is fixed (1-6); ranking is intra-section.

**Section-specific overrides**:
- For section 2 (unresolved seeds) and section 4 (negative space): `severity_weight` is replaced by `risk_density_weight` (proportion of R-* flagged functions in the targeted contract).
- For section 3 (disagreements): `severity_weight` is the higher of the two disagreeing verdicts.

---

## Session B Behavioral Rules

Session B reads the target sheet as a **target sheet**, not a justification. It carries:
- WHAT to prioritize (the table rows).
- WHY in one line (the table cells).
- NO Session A prose, NO Session A confidence justifications, NO "we believe X" language.

The columns are mechanical. If a column would require Session A reasoning to fill, the field is blank or `-`.

Verifier independence, DA contrastive conditioning, and fresh re-scoring still apply unchanged.

---

## Caps and Totals

| Section | Default cap | Slack-eligible recipient |
|---|---|---|
| 1. Top dangerous blind spots | 5 | YES |
| 2. Top unresolved seeds | 6 | YES |
| 3. Top disagreements | 5 | NO |
| 4. Top negative-space targets | 5 | YES |
| 5. Top uncertain Medium+ findings | 6 | YES |
| 6. Top orphan / non-thesis candidates | 5 | NO |
| **Default total max rows** | **32** | |
| **Max additional slack slots** | **+3** | |
| **Max additional dominant-family override slot** | **+1** | |
| **Hard upper bound on final total** | **36** | |

Session B has a finite DA budget (Thorough: 8-12 DA agent slots across iter 2-3). The target sheet cannot exceed what Session B can act on.

---

## Slack Redistribution

**Goal**: when one section underfills (fewer qualified candidates than its cap allows) and another slack-eligible section has strong unresolved candidates above its cap, allow controlled overflow up to **+3 redistributed slots total** across the entire handoff.

**Slack-eligible recipient sections**:
- Section 1: Top dangerous blind spots
- Section 2: Top unresolved seeds
- Section 4: Top negative-space targets
- Section 5: Top uncertain Medium+ findings

Sections 3 (disagreements) and 6 (orphans) are NOT slack-eligible. Disagreements are inherently bounded by an analyst-curated list; orphans are precision-risk surface -- extra orphan slots reward weak signal.

### Slack Pool Computation

```
slack_pool = 0
for section in [S1, S2, S3, S4, S5, S6]:
  if section.actual_rows < section.default_cap:
    slack_pool += (section.default_cap - section.actual_rows)
slack_pool = min(slack_pool, 3)   # hard cap at 3 redistributed slots
```

Slack accumulates from ANY underfilling section (including S3 and S6 -- they contribute to the pool but cannot receive from it).

### Distribution Algorithm

```
# Surplus candidates per slack-eligible recipient section
for section in [S1, S2, S4, S5]:
  surplus_candidates = candidates_passing_section_filter MINUS already-included rows
  rank surplus_candidates by exploitability score

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

# Append redistributed rows to their target sections, marked with [REDISTRIBUTED]
for row in redistribution_queue:
  append row to row.target_section with annotation [REDISTRIBUTED]
```

### Slack Hard Rules

- Slack flow is CAPPED at +3 total. If 4 sections underfill by 2 each (8 unused slots), still only 3 are redistributed.
- Slack does NOT flow to section 3 (disagreements) or section 6 (orphans) -- those caps are absolute.
- Slack candidate score must clear the **0.40 threshold** (mid-Medium baseline). Below threshold, slack stays unused -- no weak orphan spam, even with capacity available.
- Redistribution is deterministic: ranked by the exploitability score formula; ties broken by section priority (S2 > S1 > S4 > S5 -- unresolved seeds outrank blind spots outrank negative-space outrank uncertain findings).
- Redistributed rows are **annotated** `[REDISTRIBUTED from section underfill]` in their final row, so Session B sees that they came via slack.

### Redistribution Metadata

```markdown
## 0. Redistribution Metadata
- redistributed_from: [{section_id, slots_donated}, ...]
- redistributed_to: [{section_id, slots_received, candidate_ids}, ...]
- slack_slots_used: {0..3}
- final_total_targets: {32..36}
- threshold_blocked: {true/false}
```

If `slack_slots_used == 0`, this section is still emitted with the explicit zeros -- silence is not a valid state.

---

## Family-Diversity Cap for Section 2

**Goal**: prevent section 2 (Top unresolved seeds) from being dominated by one Seed Family. Without a diversity cap, an audit with 12 unresolved E1 SYMMETRIC canonicals and 1 each of E2/E5/E6/E8 would fill all 6 slots with E1 SYMMETRIC, blinding Session B to cross-surface signals.

**Cap**: soft cap of **2 entries per Seed Family** in section 2.

### Algorithm

```
# Inputs:
#   ranked_pool = canonical FORWARD entries, ranked by (family priority, Members desc, score)
#   total_pool_size = len(ranked_pool)

# Step 1: exemption check
if total_pool_size < 4:
    # Tiny audit -- diversity cap NOT applied; preserves recall on small candidate pools
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
i = 0
while len(section_2) < 6 and i < len(overflow):
    section_2.append(overflow[i])
    i += 1

return section_2, family_diversity_cap_applied, overflow_held = i
```

### Family-Diversity Hard Rules

- The cap is **soft** -- when section 2 underfills, overflow refills it. Recall is never lost to enforce diversity.
- The cap applies **after** family-priority ranking, so highest-priority families (E8 EMERGENCY etc.) still get 2 slots before others compete for the remaining 4.
- Tie-break inside a family: Members count descending. The strongest 2 entries from the dominant family get the slots; weaker entries go to overflow.
- The cap applies ONLY to section 2 (canonical unresolved seeds). Other sections do NOT use family-diversity caps.
- The cap is bypassed when the FORWARD pool has < 4 entries -- diversity is meaningless on a tiny pool.

### Why This Increases Target Diversity

- Diversity exposes Session B to multiple attack surfaces in parallel. A high-recall E1 SYMMETRIC family doesn't drown out a single-but-real E5 EXTERNAL-DEP signal.
- The soft cap with overflow refill preserves total recall -- section 2 still fills to 6 entries when candidates exist.
- No additional slots are added; this is pure routing improvement at fixed budget.
- Deterministic and observable in metadata.

---

## Dominant-Family Override

**Problem**: the family-diversity cap (2 per family) sometimes underfeeds the real center of risk. When one family genuinely dominates the audit's attack surface, the strict 2-per-family cap can hold back a third candidate that materially outranks every alternative-family candidate.

**Goal**: allow at most **+1 extra slot for a dominant family** when its top held-back candidate materially outranks the next best alternative-family candidate.

### Override Algorithm

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
next_best_alt = max_by_score(
    [c for c in section_2 if c.seed_family != dominant_family]
)

if next_best_alt is None:
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

### Override Hard Rules

- **Maximum +1 extra slot** for the dominant family. Never adds 2+ extra slots, never fires for non-dominant families.
- **Score gap threshold = 0.25** (deterministic, absolute on the ranking score scale where severity_weight maxes at 1.0). A gap of 0.25 is roughly the difference between a Critical-severity candidate and a Medium-severity candidate, OR between a multi-source canonical and a single-source canonical at the same severity. Conservative -- small gaps do NOT trigger the override.
- **Override does NOT bypass the diversity cap as the default**: only fires when the gap is genuinely large.
- **Section 2 final size** can be at most: default cap (6) + slack (up to +3) + override (+1) = 10. Hard upper bound on total moves from 35 to 36.
- **Override interacts cleanly with slack redistribution**: slack runs first (total up to 35), THEN family-diversity cap applies (within section 2), THEN dominant-family override (one final +1 if eligible). Order is fixed and deterministic.

### Why This Preserves Diversity Without Starving Real Risk

- The cap stays the default. Override only fires when genuinely justified by a large score gap.
- Bounded at +1 -- cannot turn into "dominant family always wins".
- Conservative threshold (0.25 absolute) prevents marginal cases from escalating.
- A dominant family might genuinely BE the audit (e.g., an AMM where mirror-accounting is the central risk). The override expresses that without weakening diversity for non-dominant cases.

---

## What Makes a Good DA Target

A good DA target row carries:
- WHAT to prioritize (the row data).
- WHY in one line (the table cells).
- NO prior-analysis prose, NO confidence justifications, NO "we believe X" language.

All columns are mechanical. If a column would require prior reasoning to fill, the field is blank or `-`. The target sheet is a **target sheet**, not a justification.
