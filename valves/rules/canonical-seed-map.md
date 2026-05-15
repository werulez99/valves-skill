<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Canonical Seed Map (v1.7-PATCH2 — PATCH 1: dedup / normalization)

Source-of-truth for `{SCRATCHPAD}/canonical_seed_map.md`. Orchestrator-inline. Mechanical. Runs in the COMPLETE_A handoff sub-step **after** `seed_outcomes.md` (raw bookkeeping) and **before** `disagreement_queue.md` and `session_a_to_b_handoff.md` (canonical consumers).

## Purpose

Three Session A seed sources (Structural Anomaly Harvester sweeps 1–8, Assumption-Breaker Q1–Q6, Bounded Analog Seeds AS-1..AS-8) can produce up to ~38 raw seeds, several of which point at the same code location with the same root-cause family. Without a dedup layer, Session B spends DA budget on duplicates and seed metrics inflate.

This artifact collapses near-duplicate raw seeds into one canonical unresolved target while **preserving every source-seed ID** in the `Source Provenance` column. The raw `seed_outcomes.md` is unchanged (one row per raw seed, no information lost).

## § Schema

```
| Canonical Seed ID | Source Provenance | Primary Location | Domain | Seed Family | Likely BC / Sweep Link | Members | Normalized Outcome | Linked Finding ID or Why unresolved | Open Question | Disputed Assumption | Heuristic Lens |
```

(v1.7-PATCH9 schema-consistency fix: `Linked Finding ID or Why unresolved` was previously omitted from this descriptor but was always present in the output table. The two now match.)

- **Canonical Seed ID** — `CS-1`, `CS-2`, … assigned by orchestrator inline. Order: by `Members` descending, then by exploitability rank of the Seed Family, then by Primary Location.
- **Source Provenance** — a flat list of raw seed IDs, e.g. `harvester:Sweep-1:S-3, AB-2, AS-4`. Every member is cited.
- **Primary Location** — the most specific `file:line` (or `Contract.function` if line is unknown) across members. When members disagree, prefer the most specific.
- **Domain** — most-cited depth domain among members: `token_flow` / `state_trace` / `edge_case` / `external`.
- **Seed Family** — the equivalence class (see below). Pick the most specific family that fits all members.
- **Likely BC / Sweep Link** — best BC tag (BC-NNN) when present; else the harvester sweep (Sweep-N) the canonical seed maps to. When members disagree on BC tag → leave blank and emit `## BC alignment uncertain` line in the entry.
- **Members** — count of source seeds collapsed (≥ 1).
- **Normalized Outcome** — derived from members' raw outcomes per § Outcome derivation below.
- **Open Question** (v1.7-PATCH7, ≤ 25 words, OPTIONAL) — the exact unanswered adversarial question that Session A could not mechanically resolve. Filled ONLY when the question is derivable from a member's evidence (e.g., AB-7 seed text; harvester sweep description + concrete location; analog-pattern question phrasing). When the question would require Session A reasoning to invent → leave blank (`-`). NEVER paste prose. Examples (these are the SHAPE; do not copy literally): `"Can rewards be claimed before rewardIndex is updated?"`, `"Can strategy migration happen between deposit and withdrawal settlement?"`, `"Is this only safe if A() always happens before B(), but the code never enforces it?"`.
- **Disputed Assumption** (v1.7-PATCH7, ≤ 20 words, OPTIONAL) — the exact assumption Session A could not mechanically confirm. Filled ONLY when the assumption is derivable from a member's evidence (e.g., the trust statement the seed contradicts; the invariant the seed pressures; the call-order the seed says is unenforced). When the assumption would require Session A reasoning to invent → leave blank (`-`). Examples (SHAPE only): `"setStrategy() never fires while withdrawals are in flight"`, `"oracle.latestPrice() is fresh within 1 hour"`, `"emergencyExit() is only called after pause()"`.
- **Heuristic Lens** (v1.7-PATCH8, short tag, OPTIONAL) — names the elite-auditor lens this canonical's question / assumption maps to. Tag enum (one of, or `-` when no lens clearly applies): `SYMMETRY` / `STATE-TRANSITION` / `SEQUENCE` / `BIG-VS-SMALL` / `NUMERIC-EXTREME` / `NONEXISTENT-ID` / `TEST-SKEPTIC` / `DEAD-STATE`. See `~/.valves/rules/valves-doctrine.md` § Heuristic Lenses for the full lens semantics. Derivation is mechanical from member sources:
    - Sweep 1 SYMMETRIC → `SYMMETRY`. Sweep 8 EMERGENCY (when the seed is asymmetry-shaped) → `SYMMETRY`; (when sequence-shaped) → `SEQUENCE`.
    - Sweep 2 INTERFACE → `-` (no specific lens; interface mismatch is its own routing class E2, not a heuristic lens).
    - Sweep 3 CONFIG-DRIFT → `-` (config drift routes via E3; not a heuristic lens).
    - Sweep 4 PARITY → `-` (governance parity routes via E4).
    - Sweep 5 EXTERNAL-DEP → `-` (routes via E5; doctrine question 7 covers it without a lens tag).
    - Sweep 6 RECIPIENT → `-` (routes via E6; recipient correctness isn't a heuristic lens).
    - Sweep 7 MIRROR-ACCT → `STATE-TRANSITION` if the mirror gap is a state-machine completeness issue; otherwise `-`.
    - AB Q2 → `SYMMETRY`. AB Q5 → `SYMMETRY` (recovery-severs-custody is asymmetry-rooted) OR `SEQUENCE` (when the recovery is order-dependent). AB Q7 → `SEQUENCE`. AB Q1/Q3/Q4/Q6 → `-` (route via existing equivalence classes, no specific heuristic lens).
    - VS-TS-1 (Validation Sweep test-skepticism finding promoted to seed via depth) → `TEST-SKEPTIC`.
    - Harvester-emitted dead-state candidates (when surfaced from Sweep 7 mirror-acct or new dead-state-style sub-flag) → `DEAD-STATE`.
    - Analog seeds (AS-N) → derive from the analog pattern: when the pattern is "first-depositor inflation / decimal precision" → `NUMERIC-EXTREME`; when "split into N small ops" → `BIG-VS-SMALL`; when "non-existent tokenId / fake-pool" → `NONEXISTENT-ID`; otherwise `-`.

When ALL members of a canonical agree on a lens → the canonical carries that lens. When members disagree → leave `-` and let downstream routing read the family / question fields directly. The lens tag is a routing convenience, not a substantive claim — leaving it `-` is always safe.

## § Heuristic Lens precedence (v1.7-PATCH9)

When a single canonical's evidence fits multiple lenses, the orchestrator MUST pick exactly ONE lens via the precedence below. This prevents the same issue from bouncing across labels unpredictably across audits and ensures Session B's DA prompt receives a single primary lens.

**Precedence (strongest parent interpretation first; pick the first that applies)**:

1. **STATE-TRANSITION** — wins when the canonical's evidence describes a protocol-internal lifecycle / state-machine completeness gap (a transition that fires without predecessor validation; an accounting mirror that drifts because a write was skipped on one branch; a state reached that the developer believed unreachable). State-machine breaks are root causes that contain caller-controlled order issues + asymmetry as downstream manifestations.
2. **SEQUENCE** — wins (when STATE-TRANSITION does NOT fit) when the canonical's evidence describes caller-controlled call-order assumptions (skipped predecessor by an external actor; admin mutation interleaved between user steps; cross-contract reordering). Distinct from STATE-TRANSITION: SEQUENCE is the caller's view; STATE-TRANSITION is the protocol's view.
3. **SYMMETRY** — wins when the canonical's evidence describes asymmetric sibling paths (deposit/withdraw guards differ; claim/emergency-claim accounting differs; normal/skipped path divergence) AND the asymmetry is NOT itself a state-machine completeness gap (which would route to STATE-TRANSITION).
4. **BIG-VS-SMALL** — wins when the canonical's evidence describes split-vs-aggregate equivalence failure (rounding accumulation; fee-tier bypass via splitting; rate-limit bypass via N small ops).
5. **NUMERIC-EXTREME** — wins when the canonical's evidence describes boundary pressure (zero, type.max, decimal-precision, first-depositor inflation).
6. **NONEXISTENT-ID** — wins when the canonical's evidence describes attacker-chosen identifier paths (non-existent tokenId; attacker-controlled pool / market / vault).
7. **DEAD-STATE** — wins when the canonical's evidence describes write-without-meaningful-read or read-without-write (the missing read may hide a transition gap; the canonical is recorded under DEAD-STATE rather than STATE-TRANSITION because the underlying transition issue is unconfirmed).
8. **TEST-SKEPTIC** — ORTHOGONAL to the above. Assigned ONLY when the canonical's source includes `[VS-TS-1]` (Validation Sweep test-skepticism finding promoted to seed). TEST-SKEPTIC does NOT collide with structural lenses — a TEST-SKEPTIC canonical has its own surface and routing. When `[VS-TS-1]` is one of multiple sources for the same canonical (members from multiple sources), TEST-SKEPTIC wins ONLY if all non-VS-TS-1 members would otherwise route to `-`; otherwise the structural lens wins and TEST-SKEPTIC is recorded as a secondary annotation in the `Open Question` field (free-form).

**Common collision examples (deterministic resolution)**:

| Collision | Wins | Reason |
|---|---|---|
| Caller-controlled call-order that triggers an invalid state-machine transition | STATE-TRANSITION | Root cause is the missing transition validator, not the caller |
| Asymmetric write paths where one branch leaves accounting mirror un-updated | STATE-TRANSITION | Asymmetry is the symptom; mirror gap is the root cause |
| Asymmetric pause guards on deposit/withdraw with no state-machine implications | SYMMETRY | Pure guard divergence; no transition validity gap |
| Recovery path that severs custody (E8 EMERGENCY family) when the seed is sequence-shaped | SEQUENCE | Recovery-early is a call-order pattern |
| Recovery path that severs custody when the seed is asymmetry-shaped | SYMMETRY | Recovery vs normal-path divergence in guards / accounting |
| Mirror-accounting drift where read is missing from one branch | STATE-TRANSITION | Accounting mirror IS the state machine; missing read = missing transition validator |
| Split deposit creating share inflation at first-depositor boundary | NUMERIC-EXTREME | Boundary is the dominant lens; split is secondary |
| Test-skepticism finding sharing surface with an admin-setter validation gap | structural lens (likely SYMMETRY or STATE-TRANSITION) | TEST-SKEPTIC orthogonal; secondary annotation in Open Question |

**Hard rule**: precedence is mechanical and deterministic. Two orchestrator runs on identical evidence MUST yield the same lens tag. When multi-source members force a tie at the same precedence level, prefer the lens whose evidence comes from the highest-priority source per `Source Provenance` (Strongest Exploit Card-tagged > harvester Sweep > AB Q-N > AS-N > VS-TS-1). When still tied → leave `-` (conservative bias).

**Why this preserves stronger parent interpretations**: STATE-TRANSITION is at the top of the precedence because it is the most architecturally root-cause framing — a state-machine break contains caller-order and asymmetric-path issues as downstream manifestations. Choosing the deeper root cause as the lens tag means Session B's DA prompt routes to the broader pressure first, and the narrower symptom interpretations follow.

## § Equivalence classes

Two raw seeds are merge-eligible iff they share the same equivalence class AND the same Primary Location AND a compatible BC tag (same BC-NNN, OR one is BC-NEW and the other matches the same described pattern). When merging is uncertain → DO NOT MERGE (conservative bias).

| Class ID | Class name | Sources |
|---|---|---|
| **E1 SYMMETRIC** | symmetric-pair / branch-asymmetry | Sweep 1 + Sweep 8 + AB Q2 + analog with Sweep 1/8 link |
| **E2 INTERFACE** | cross-contract interface mismatch | Sweep 2 + analog with Sweep 2 link |
| **E3 CONFIG-DRIFT** | parameter desync / immutable-not | Sweep 3 + AB Q1 + analog with Sweep 3 link |
| **E4 PARITY** | governance parity gap | Sweep 4 + analog with Sweep 4 link |
| **E5 EXTERNAL-DEP** | hidden external dependency / trusted-external | Sweep 5 + AB Q3 + analog with Sweep 5 link |
| **E6 RECIPIENT** | recipient / beneficiary mismatch | Sweep 6 + analog with Sweep 6 link |
| **E7 MIRROR-ACCT** | mirror-accounting drift | Sweep 7 + analog with Sweep 7 link |
| **E8 EMERGENCY** | emergency-path asymmetry / recovery-severs-custody | Sweep 8 + AB Q5 + analog with Sweep 8 link |
| **E9 TRUST-MODEL** | actor assumed benign | AB Q6 + analog with trust-model link |
| **E10 ADMIN-LIVE-POINTER** | admin-no-migration / live-pointer replacement | AB Q4 + analog with admin-no-migration link |
| **E11 SEQUENCE** (v1.7-PATCH7) | unenforced call-order / sequence assumption (broader than E8) | AB Q7 + analog with sequence link + harvester Sweep 1/8 cross-reference when the asymmetry is specifically about ORDER (predecessor / repeat / interleave / cross-contract reordering), not just per-function aspect mismatch |

> **Sweep 8 priority**: when a seed could fit E1 SYMMETRIC OR E8 EMERGENCY, prefer E8 (emergency-path asymmetry is the more specific and higher-impact framing — escalates to Strongest Exploit Gate E2/E5 eligibility per `~/.valves/rules/strongest-exploit-preservation.md`).
>
> **E8 / E11 priority (v1.7-PATCH7)**: when a seed could fit E8 EMERGENCY OR E11 SEQUENCE, prefer E8 (emergency-path is the more specific framing of call-order). E11 captures the residual call-order cases that are NOT specifically about emergency vs normal path: skipped predecessor step in a normal workflow, repeated call within the same lifecycle, admin mutation inserted between two user actions, oracle update between snapshot and consumption, cross-contract sequencing reordered. Same conservative bias applies — when in doubt, do NOT MERGE across E8 and E11.

## § Merge predicate (binding)

For two raw seeds A and B, they merge into the same canonical entry iff **all three** hold:

1. **Same equivalence class** per the table above. If A is in E1 and B is in E8, they do NOT merge (different classes), even if they cite the same code line.
2. **Same Primary Location** — same `file:line` exact, OR same `Contract.function` AND lines within ≤ 5 of each other. Different functions → do NOT merge.
3. **Compatible BC tag** — same BC-NNN; OR one is BC-NEW with a pattern description that matches the other's BC pattern; OR both are BC-NEW with the same described pattern.

If any of the three is uncertain → keep as separate canonical entries. Conservative bias: a separate entry is cheap; a wrongly merged entry is silent miss.

## § Outcome derivation (Normalized Outcome from members' raw outcomes)

Read each member's raw outcome from `seed_outcomes.md`. Derive the canonical's `Normalized Outcome` by precedence:

1. If **≥ 1 member** has raw outcome `PROMOTED_TO_FINDING` → Normalized = **PROMOTED_TO_FINDING**. The canonical's "Linked Finding ID" cites the strongest-evidence promotion (highest composite or highest severity) and lists alternates if multiple.
2. Else if **all members** have raw outcome `CLEARED_PRE_DEPTH` AND at least one member carries a full proof record per `~/.valves/rules/cleared-proof-discipline.md` § Required minimum proof fields → Normalized = **CLEARED_PRE_DEPTH**. The canonical cites the strongest member's proof (most-specific file:line, highest-confidence proof type) in its proof record (see § CLEARED proof discipline below). Members without proof are listed in a `## Proof gaps (members)` annotation on the canonical entry.
3. Else if **all members** have raw outcome `CLEARED_PRE_DEPTH` AND **no member** carries a full proof record → Normalized = **FORWARD_TO_SESSION_B** with reason `INSUFFICIENT_CLEAR_PROOF` (PATCH 1 downgrade). All members listed in `## Proof gaps (members)`.
4. Else (any member is `FORWARD_TO_SESSION_B` and none are `PROMOTED_TO_FINDING`) → Normalized = **FORWARD_TO_SESSION_B**. The canonical's `Why unresolved` field is the union of member reasons, deduplicated.

This precedence reflects the recall priority: a single PROMOTED member proves the cluster is real; a single FORWARD member preserves the unresolved status; CLEARED requires real proof or it routes to FORWARD instead.

## § CLEARED proof discipline (v1.7-PATCH3 — PATCH 1)

When the canonical's Normalized Outcome is `CLEARED_PRE_DEPTH`, the orchestrator emits a **Proof Records** sub-section in `canonical_seed_map.md` after the main canonical table. Schema per `~/.valves/rules/cleared-proof-discipline.md` § Schema for proof records:

```markdown
## CLEARED Proof Records (v1.7-PATCH3)
| Canonical Seed ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (≤25 words) |
|---|---|---|---|---|
```

Required fields per row:
- **Proof Type**: one of `GUARD_PRESENT` / `INVARIANT_ENFORCED` / `TRUST_MODEL_EXPLICIT` / `STATE_UNREACHABLE` / `EXTERNAL_DEPENDENCY_SAFE` / `OTHER` (with specification).
- **file:line**: the specific anchor; not a contract name alone.
- **Guard / Invariant / State Condition**: the literal code expression OR named invariant ID OR documented trust statement.
- **Reason**: ≤ 25 words, must reference both the attacker action AND the blocking effect.

If a canonical has Normalized Outcome=CLEARED_PRE_DEPTH but no row in Proof Records → the orchestrator's COMPLETE_A handoff sub-step build emits `CLEARED_PROOF_GAP_DETECTED` to `degradation_log.md` and DOWNGRADES the canonical to FORWARD_TO_SESSION_B per `~/.valves/rules/cleared-proof-discipline.md` § Hard rule. The downgrade is mechanical and deterministic.

## § Sibling Links (v1.7-PATCH3 — PATCH 3)

A weaker adjacency relation than the merge predicate. Sibling Links are NOT merges — they keep canonicals separate but flag investigation neighborhoods for Session B. Two canonicals are linked iff they remain separate per § Merge predicate but satisfy any **one** of:

1. **Same function** (different lines within the function), OR
2. **Same `Contract.function` location within ≤ 20 lines** (vs ≤ 5 for merge), OR
3. **Same state tuple / accounting tuple** (e.g., both reference `totalShares` and `balanceOf` mapping; both reference `rewardIndex` and `userOwed`), OR
4. **Same external callee / integration point** (e.g., both depend on the same Aave Pool address; both call the same LayerZero endpoint), OR
5. **Same actor/victim pair** (e.g., both have actor=untrusted-depositor and victim=protocol-treasury), OR
6. **Same exploit family but cross-class** — when one canonical is in E1 SYMMETRIC and another in E8 EMERGENCY at the same `Contract.function`, the merge predicate forbids merging (different equivalence classes), but the surfaces are clearly adjacent and Session B should consider them together.

### Hard rules for Sibling Links

- **Symmetric relation**: if CS-3 ↔ CS-7 is a sibling link, both canonicals' rows record the link.
- **Max 3 sibling links per canonical**: prevents cluster bloat. When more than 3 candidates qualify, rank by adjacency strength: same-state-tuple > same-function > same-external-callee > same-actor/victim > cross-class-same-location > within-20-lines, and keep the top 3.
- **Sibling links do NOT merge canonicals**: they remain separate canonical entries with separate Normalized Outcomes. A sibling-linked CS-3 (FORWARD) and CS-7 (CLEARED) coexist; CS-7 is cleared, CS-3 is forwarded, and Session B sees the link.
- **Sibling links are NOT investigation requirements** — they are hints. Session B may investigate together or separately based on its own DA pass logic.

### Output format

```markdown
## Sibling Links (v1.7-PATCH3)
| Canonical Seed ID | Linked Canonicals | Link Type |
|---|---|---|
| CS-3 | CS-7, CS-12 | same-function (CS-7); same-state-tuple (CS-12) |
| CS-7 | CS-3 | same-function |
| CS-12 | CS-3 | same-state-tuple |
```

Sibling links are also surfaced in `session_a_to_b_handoff.md` § 2 (Top unresolved seeds) via a `Linked CS` column on each row. See `~/.valves/rules/session-a-to-b-handoff.md` § 2 schema.

### Why sibling links improve recall (and don't increase FP)

- **Investigation neighborhood signal**: when Session B investigates CS-3 and finds a real bug, the sibling link to CS-7 prompts the DA agent to reconfirm CS-7's CLEARED proof against the new evidence. This is the cheapest way to catch the case where a "cleared" sibling is actually exploitable via the same attack class.
- **Conservative**: sibling links don't merge anything, don't change any outcome, don't add slots. They're metadata. Session B's per-section caps and DA budget remain unchanged.
- **Bounded**: max 3 links per canonical limits noise. The ranking-by-adjacency-strength rule ensures the strongest links are surfaced.

## § Output (`canonical_seed_map.md`)

```markdown
# Canonical Seed Map — {project} — {ISO timestamp}

## Summary
- Raw seeds across all sources: {R}
- Canonical seeds (after dedup): {C}
- Compression ratio: {C}/{R}
- By outcome: PROMOTED {P_canon} / CLEARED {C_canon} / FORWARD {F_canon}
- By family (canonical): E1 {n1} / E2 {n2} / E3 {n3} / E4 {n4} / E5 {n5} / E6 {n6} / E7 {n7} / E8 {n8} / E9 {n9} / E10 {n10} / E11 {n11}
- Sibling-linked canonicals (v1.7-PATCH3): {SL} canonicals with ≥ 1 sibling link

## Canonical seeds
| Canonical Seed ID | Source Provenance | Primary Location | Domain | Seed Family | Likely BC / Sweep Link | Members | Normalized Outcome | Linked Finding ID or Why unresolved | Open Question (v1.7-PATCH7) | Disputed Assumption (v1.7-PATCH7) | Heuristic Lens (v1.7-PATCH8) |
|---|---|---|---|---|---|---|---|---|---|---|---|

## CLEARED Proof Records (v1.7-PATCH3 — required for every CLEARED canonical)
| Canonical Seed ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (≤25 words) |
|---|---|---|---|---|

## Sibling Links (v1.7-PATCH3 — investigation-neighborhood hints, NOT merges)
| Canonical Seed ID | Linked Canonicals | Link Type |
|---|---|---|

## Proof gaps (members) — for canonicals with mixed proof quality
| Canonical Seed ID | Members lacking proof | Action |
|---|---|---|
| CS-N | Sweep-1:S-7, AB-3 | Inherited proof from AS-2; gap members logged but not blocking |

## Hard rules
- Every raw seed in seed_outcomes.md MUST appear in exactly one canonical entry's Source Provenance.
- A canonical entry with Members=1 is normal and expected — most raw seeds are unique.
- Conservative bias: when in doubt, do NOT merge. Better two canonical entries than one wrong merge.
- Normalized Outcome is derived mechanically from members; agents do NOT decide it.
- (v1.7-PATCH3) Every CLEARED canonical MUST have a row in CLEARED Proof Records. Missing proof → DOWNGRADE to FORWARD_TO_SESSION_B per `~/.valves/rules/cleared-proof-discipline.md` § Hard rule.
- (v1.7-PATCH3) Sibling Links are bounded at max 3 per canonical and are symmetric (A↔B requires both rows).
- (v1.7-PATCH7) Open Question and Disputed Assumption columns are OPTIONAL. Empty values are written as `-` (never blank string, never `n/a`). Inventing fields when not derivable from member evidence is a violation; leave them empty instead. The orchestrator does NOT validate the prose — it only checks that empty values are normalized to `-`.
- (v1.7-PATCH8) Heuristic Lens column is OPTIONAL. Tag enum is fixed (`SYMMETRY` / `STATE-TRANSITION` / `SEQUENCE` / `BIG-VS-SMALL` / `NUMERIC-EXTREME` / `NONEXISTENT-ID` / `TEST-SKEPTIC` / `DEAD-STATE`); off-enum values are rejected at COMPLETE_A handoff build time. Empty value is `-`. Derivation is mechanical from member raw sources per § Schema. The orchestrator does not invent lens tags; if no member's source maps cleanly to a lens, the value is `-`.
```

## § Hard gate (SOFT)

`canonical_seed_map.md` is a SOFT gate. If the orchestrator-inline build fails (missing input files, parse errors), log `canonical_seed_map_INCOMPLETE` to `{SCRATCHPAD}/degradation_log.md`. The handoff fallback chain:
- `session_a_to_b_handoff.md` § 2 (Top unresolved seeds): if canonical_seed_map.md is missing → fall back to reading `seed_outcomes.md` directly WHERE Outcome=FORWARD_TO_SESSION_B (no dedup, but still works).
- `seed_metrics.md`: if canonical_seed_map.md is missing → emit only the raw counts row; mark canonical row as `n/a`.

## § Why this improves valid recall (and does not increase FP)

- **Recall**: deduplication concentrates Session B's DA budget on unique unresolved targets. A single canonical seed CS-3 (with 3 raw members) gets ONE handoff slot instead of three; the saved slots either expand Session B's reach to other unresolved canonicals OR remain unused (precision-positive).
- **No imported severity**: outcome is derived from members' raw outcomes. No new severity assignment, no new evidence claim.
- **No silent loss**: every raw seed appears in exactly one canonical entry's Source Provenance — verified by the hard rule. The audit trail is complete.
- **Conservative bias**: when in doubt the merge predicate keeps seeds separate. Wrong merges are silent misses; the predicate avoids them by demanding all three conditions (location + class + BC tag).
- **Cross-source enrichment signal**: a canonical with Members ≥ 2 across DIFFERENT sources (e.g., harvester Sweep 1 + AB Q2 + analog with Sweep 1 link all hitting the same location) is a high-signal target — three independent mechanisms converged. The canonical entry preserves the provenance so Session B can use it as a confidence boost.
