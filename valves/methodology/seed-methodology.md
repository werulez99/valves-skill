# Seed Methodology — Canonical Seeds, Heuristic Lenses, and Analog Seeds

> Extracted from canonical-seed-map.md + analog-seeds.md (v1.7.0-PATCH12).
> Orchestration removed — methodology preserved for overlay injection.
> Used by: depth, breadth, attention_repair phases.

---

## Canonical Seed Map

Three seed sources (Structural Anomaly Harvester sweeps 1-8, Assumption-Breaker Q1-Q7, Bounded Analog Seeds AS-1..AS-8) can produce up to ~38 raw seeds, several of which point at the same code location with the same root-cause family. The canonical seed map collapses near-duplicate raw seeds into one canonical unresolved target while **preserving every source-seed ID** in the `Source Provenance` column.

---

## Canonical Seed Schema

```
| Canonical Seed ID | Source Provenance | Primary Location | Domain | Seed Family | Likely BC / Sweep Link | Members | Normalized Outcome | Linked Finding ID or Why unresolved | Open Question | Disputed Assumption | Heuristic Lens |
```

### Column Definitions

- **Canonical Seed ID** -- `CS-1`, `CS-2`, ... assigned sequentially. Order: by `Members` descending, then by exploitability rank of the Seed Family, then by Primary Location.
- **Source Provenance** -- a flat list of raw seed IDs, e.g. `harvester:Sweep-1:S-3, AB-2, AS-4`. Every member is cited.
- **Primary Location** -- the most specific `file:line` (or `Contract.function` if line is unknown) across members. When members disagree, prefer the most specific.
- **Domain** -- most-cited depth domain among members: `token_flow` / `state_trace` / `edge_case` / `external`.
- **Seed Family** -- the equivalence class (see below). Pick the most specific family that fits all members.
- **Likely BC / Sweep Link** -- best BC tag (BC-NNN) when present; else the harvester sweep (Sweep-N) the canonical seed maps to. When members disagree on BC tag, leave blank and emit `## BC alignment uncertain` line in the entry.
- **Members** -- count of source seeds collapsed (>= 1).
- **Normalized Outcome** -- derived from members' raw outcomes per Outcome Derivation Rules below.
- **Open Question** (<= 25 words, OPTIONAL) -- the exact unanswered adversarial question that could not be mechanically resolved. Filled ONLY when the question is derivable from a member's evidence (e.g., AB seed text; harvester sweep description + concrete location; analog-pattern question phrasing). When the question would require reasoning to invent, leave blank (`-`). NEVER paste prose. Examples (these are the SHAPE; do not copy literally): `"Can rewards be claimed before rewardIndex is updated?"`, `"Can strategy migration happen between deposit and withdrawal settlement?"`, `"Is this only safe if A() always happens before B(), but the code never enforces it?"`.
- **Disputed Assumption** (<= 20 words, OPTIONAL) -- the exact assumption that could not be mechanically confirmed. Filled ONLY when the assumption is derivable from a member's evidence (e.g., the trust statement the seed contradicts; the invariant the seed pressures; the call-order the seed says is unenforced). When the assumption would require reasoning to invent, leave blank (`-`). Examples (SHAPE only): `"setStrategy() never fires while withdrawals are in flight"`, `"oracle.latestPrice() is fresh within 1 hour"`, `"emergencyExit() is only called after pause()"`.
- **Heuristic Lens** (short tag, OPTIONAL) -- names the elite-auditor lens this canonical's question / assumption maps to. Tag enum (one of, or `-` when no lens clearly applies): `SYMMETRY` / `STATE-TRANSITION` / `SEQUENCE` / `BIG-VS-SMALL` / `NUMERIC-EXTREME` / `NONEXISTENT-ID` / `TEST-SKEPTIC` / `DEAD-STATE`. See Heuristic Lens Definitions below. Empty values are written as `-` (never blank string, never `n/a`). Inventing fields when not derivable from member evidence is a violation; leave them empty instead.

---

## Seed Family Enumeration (Equivalence Classes)

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
| **E11 SEQUENCE** | unenforced call-order / sequence assumption (broader than E8) | AB Q7 + analog with sequence link + harvester Sweep 1/8 cross-reference when the asymmetry is specifically about ORDER (predecessor / repeat / interleave / cross-contract reordering), not just per-function aspect mismatch |

### Family Priority Rules

- **Sweep 8 priority**: when a seed could fit E1 SYMMETRIC OR E8 EMERGENCY, prefer E8 (emergency-path asymmetry is the more specific and higher-impact framing).
- **E8 / E11 priority**: when a seed could fit E8 EMERGENCY OR E11 SEQUENCE, prefer E8 (emergency-path is the more specific framing of call-order). E11 captures the residual call-order cases that are NOT specifically about emergency vs normal path: skipped predecessor step in a normal workflow, repeated call within the same lifecycle, admin mutation inserted between two user actions, oracle update between snapshot and consumption, cross-contract sequencing reordered.
- **Conservative bias**: when in doubt, do NOT MERGE across E8 and E11.

---

## Merge Predicate (Binding)

Two raw seeds are merge-eligible iff they share the same equivalence class AND the same Primary Location AND a compatible BC tag. For two raw seeds A and B, they merge into the same canonical entry iff **all three** hold:

1. **Same equivalence class** per the table above. If A is in E1 and B is in E8, they do NOT merge (different classes), even if they cite the same code line.
2. **Same Primary Location** -- same `file:line` exact, OR same `Contract.function` AND lines within <= 5 of each other. Different functions -> do NOT merge.
3. **Compatible BC tag** -- same BC-NNN; OR one is BC-NEW with a pattern description that matches the other's BC pattern; OR both are BC-NEW with the same described pattern.

If any of the three is uncertain, keep as separate canonical entries. Conservative bias: a separate entry is cheap; a wrongly merged entry is a silent miss.

---

## Sibling Links

A weaker adjacency relation than the merge predicate. Sibling Links are NOT merges -- they keep canonicals separate but flag investigation neighborhoods. Two canonicals are linked iff they remain separate per the merge predicate but satisfy any **one** of:

1. **Same function** (different lines within the function), OR
2. **Same `Contract.function` location within <= 20 lines** (vs <= 5 for merge), OR
3. **Same state tuple / accounting tuple** (e.g., both reference `totalShares` and `balanceOf` mapping; both reference `rewardIndex` and `userOwed`), OR
4. **Same external callee / integration point** (e.g., both depend on the same Aave Pool address; both call the same LayerZero endpoint), OR
5. **Same actor/victim pair** (e.g., both have actor=untrusted-depositor and victim=protocol-treasury), OR
6. **Same exploit family but cross-class** -- when one canonical is in E1 SYMMETRIC and another in E8 EMERGENCY at the same `Contract.function`, the merge predicate forbids merging (different equivalence classes), but the surfaces are clearly adjacent and agents should consider them together.

### Sibling Link Rules

- **Symmetric relation**: if CS-3 <-> CS-7 is a sibling link, both canonicals' rows record the link.
- **Max 3 sibling links per canonical**: prevents cluster bloat. When more than 3 candidates qualify, rank by adjacency strength: same-state-tuple > same-function > same-external-callee > same-actor/victim > cross-class-same-location > within-20-lines, and keep the top 3.
- **Sibling links do NOT merge canonicals**: they remain separate canonical entries with separate Normalized Outcomes.
- **Sibling links are NOT investigation requirements** -- they are hints. Agents may investigate together or separately.

---

## Outcome Derivation Rules

Read each member's raw outcome. Derive the canonical's `Normalized Outcome` by precedence:

1. If **>= 1 member** has raw outcome `PROMOTED_TO_FINDING` -> Normalized = **PROMOTED_TO_FINDING**. The canonical's "Linked Finding ID" cites the strongest-evidence promotion (highest composite or highest severity) and lists alternates if multiple.
2. Else if **all members** have raw outcome `CLEARED_PRE_DEPTH` AND at least one member carries a full proof record -> Normalized = **CLEARED_PRE_DEPTH**. The canonical cites the strongest member's proof (most-specific file:line, highest-confidence proof type) in its proof record. Members without proof are listed in a `## Proof gaps (members)` annotation.
3. Else if **all members** have raw outcome `CLEARED_PRE_DEPTH` AND **no member** carries a full proof record -> Normalized = **FORWARD_TO_SESSION_B** with reason `INSUFFICIENT_CLEAR_PROOF` (downgrade). All members listed in `## Proof gaps (members)`.
4. Else (any member is `FORWARD_TO_SESSION_B` and none are `PROMOTED_TO_FINDING`) -> Normalized = **FORWARD_TO_SESSION_B**. The canonical's `Why unresolved` field is the union of member reasons, deduplicated.

This precedence reflects the recall priority: a single PROMOTED member proves the cluster is real; a single FORWARD member preserves the unresolved status; CLEARED requires real proof or it routes to FORWARD instead.

---

## CLEARED Proof Discipline

When the canonical's Normalized Outcome is `CLEARED_PRE_DEPTH`, a Proof Records section is required.

```markdown
## CLEARED Proof Records
| Canonical Seed ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (<=25 words) |
|---|---|---|---|---|
```

Required fields per row:
- **Proof Type**: one of `GUARD_PRESENT` / `INVARIANT_ENFORCED` / `TRUST_MODEL_EXPLICIT` / `STATE_UNREACHABLE` / `EXTERNAL_DEPENDENCY_SAFE` / `OTHER` (with specification).
- **file:line**: the specific anchor; not a contract name alone.
- **Guard / Invariant / State Condition**: the literal code expression OR named invariant ID OR documented trust statement.
- **Reason**: <= 25 words, must reference both the attacker action AND the blocking effect.

If a canonical has Normalized Outcome=CLEARED_PRE_DEPTH but no row in Proof Records, the canonical is DOWNGRADED to FORWARD_TO_SESSION_B. The downgrade is mechanical and deterministic.

---

## Heuristic Lens Definitions

Heuristic lenses route DA agent investigation. Derivation from member sources:

- Sweep 1 SYMMETRIC -> `SYMMETRY`. Sweep 8 EMERGENCY (when the seed is asymmetry-shaped) -> `SYMMETRY`; (when sequence-shaped) -> `SEQUENCE`.
- Sweep 2 INTERFACE -> `-` (no specific lens; interface mismatch is its own routing class E2).
- Sweep 3 CONFIG-DRIFT -> `-` (config drift routes via E3).
- Sweep 4 PARITY -> `-` (governance parity routes via E4).
- Sweep 5 EXTERNAL-DEP -> `-` (routes via E5).
- Sweep 6 RECIPIENT -> `-` (routes via E6).
- Sweep 7 MIRROR-ACCT -> `STATE-TRANSITION` if the mirror gap is a state-machine completeness issue; otherwise `-`.
- AB Q2 -> `SYMMETRY`. AB Q5 -> `SYMMETRY` (recovery-severs-custody is asymmetry-rooted) OR `SEQUENCE` (when the recovery is order-dependent). AB Q7 -> `SEQUENCE`. AB Q1/Q3/Q4/Q6 -> `-`.
- VS-TS-1 (Validation Sweep test-skepticism finding promoted to seed via depth) -> `TEST-SKEPTIC`.
- Dead-state candidates (from Sweep 7 mirror-acct or dead-state-style sub-flag) -> `DEAD-STATE`.
- Analog seeds (AS-N) -> derive from the analog pattern: when the pattern is "first-depositor inflation / decimal precision" -> `NUMERIC-EXTREME`; when "split into N small ops" -> `BIG-VS-SMALL`; when "non-existent tokenId / fake-pool" -> `NONEXISTENT-ID`; otherwise `-`.

When ALL members of a canonical agree on a lens, the canonical carries that lens. When members disagree, leave `-`. The lens tag is a routing convenience, not a substantive claim -- leaving it `-` is always safe.

---

## Heuristic Lens Precedence

When a single canonical's evidence fits multiple lenses, pick exactly ONE lens via the precedence below. This prevents the same issue from bouncing across labels unpredictably.

**Precedence (strongest parent interpretation first; pick the first that applies)**:

1. **STATE-TRANSITION** -- wins when the canonical's evidence describes a protocol-internal lifecycle / state-machine completeness gap (a transition that fires without predecessor validation; an accounting mirror that drifts because a write was skipped on one branch; a state reached that the developer believed unreachable). State-machine breaks are root causes that contain caller-controlled order issues + asymmetry as downstream manifestations.
2. **SEQUENCE** -- wins (when STATE-TRANSITION does NOT fit) when the canonical's evidence describes caller-controlled call-order assumptions (skipped predecessor by an external actor; admin mutation interleaved between user steps; cross-contract reordering). Distinct from STATE-TRANSITION: SEQUENCE is the caller's view; STATE-TRANSITION is the protocol's view.
3. **SYMMETRY** -- wins when the canonical's evidence describes asymmetric sibling paths (deposit/withdraw guards differ; claim/emergency-claim accounting differs; normal/skipped path divergence) AND the asymmetry is NOT itself a state-machine completeness gap (which would route to STATE-TRANSITION).
4. **BIG-VS-SMALL** -- wins when the canonical's evidence describes split-vs-aggregate equivalence failure (rounding accumulation; fee-tier bypass via splitting; rate-limit bypass via N small ops).
5. **NUMERIC-EXTREME** -- wins when the canonical's evidence describes boundary pressure (zero, type.max, decimal-precision, first-depositor inflation).
6. **NONEXISTENT-ID** -- wins when the canonical's evidence describes attacker-chosen identifier paths (non-existent tokenId; attacker-controlled pool / market / vault).
7. **DEAD-STATE** -- wins when the canonical's evidence describes write-without-meaningful-read or read-without-write (the missing read may hide a transition gap; recorded under DEAD-STATE rather than STATE-TRANSITION because the underlying transition issue is unconfirmed).
8. **TEST-SKEPTIC** -- ORTHOGONAL to the above. Assigned ONLY when the canonical's source includes `[VS-TS-1]` (Validation Sweep test-skepticism finding promoted to seed). TEST-SKEPTIC does NOT collide with structural lenses -- a TEST-SKEPTIC canonical has its own surface and routing. When `[VS-TS-1]` is one of multiple sources for the same canonical (members from multiple sources), TEST-SKEPTIC wins ONLY if all non-VS-TS-1 members would otherwise route to `-`; otherwise the structural lens wins and TEST-SKEPTIC is recorded as a secondary annotation in the `Open Question` field.

### Common Collision Examples (Deterministic Resolution)

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

**Hard rule**: precedence is mechanical and deterministic. Two runs on identical evidence MUST yield the same lens tag. When multi-source members force a tie at the same precedence level, prefer the lens whose evidence comes from the highest-priority source per `Source Provenance` (Strongest Exploit Card-tagged > harvester Sweep > AB Q-N > AS-N > VS-TS-1). When still tied, leave `-` (conservative bias).

**Why this preserves stronger parent interpretations**: STATE-TRANSITION is at the top of the precedence because it is the most architecturally root-cause framing -- a state-machine break contains caller-order and asymmetric-path issues as downstream manifestations. Choosing the deeper root cause as the lens tag means the DA prompt routes to the broader pressure first, and the narrower symptom interpretations follow.

---

## Assumption-Breaker Seeds (Q1-Q7)

These are adversarial questions applied to every audit target. Each generates seeds by pressuring a specific assumption class.

| Seed | Assumption-Breaker Question | Maps to Family |
|---|---|---|
| **Q1** | Can a config parameter be set to a value that breaks an invariant it was assumed to protect? | E3 CONFIG-DRIFT |
| **Q2** | Does the symmetric counterpart of an operation handle the same edge cases? | E1 SYMMETRIC |
| **Q3** | Can an external dependency behave differently than the code assumes? | E5 EXTERNAL-DEP |
| **Q4** | Can admin functions be called in a state that makes migration/upgrade unsafe? | E10 ADMIN-LIVE-POINTER |
| **Q5** | Does emergency/recovery path sever custody or accounting invariants? | E8 EMERGENCY |
| **Q6** | Is there an actor the code trusts that could act against user interests? | E9 TRUST-MODEL |
| **Q7** | Is there an unenforced call-order assumption (predecessor must happen before successor, but no code enforces it)? | E11 SEQUENCE |

---

## Analog Seeds (AS-1..AS-8)

Analog seeds use external vulnerability corpora as bounded pattern priors only -- never as direct findings, never as imported severity.

### Sources Allowed

- **Solodit** -- via RAG queries (pre-curated audit data).
- **Code4rena** -- via Solodit aggregator OR direct query.
- **Sherlock** -- via Solodit aggregator OR direct query.
- **CodeHawks** -- via Solodit aggregator OR direct query.
- **DeFiHackLabs** -- via RAG (already indexed).

### Hard Caps

- **<= 8 analog seeds total**.
- **<= 5 may flow into Session A investigation** (depth iter 1 + DA pass). The remaining (up to 3) are FORWARD_TO_SESSION_B candidates only.
- **Local mapping vague -> discard.** A seed that cannot point to a concrete local file/function is dropped, not weakened.
- **No imported severity.** The analog finding's original severity is recorded for context but does NOT flow into local scoring.
- **No copied report wording.** The seed's `Analog Pattern` field is a one-line abstraction (<= 25 words); do not paste verbatim from the source.
- **No direct findings.** An analog seed becomes a finding only via the standard depth + verification path. Until then it is investigation-direction signal.

### Local Mapping Requirement

Each analog seed MUST resolve to **all three**:

1. **Local Surface Match** -- a category match between the analog's pattern and a surface in the attack surface analysis (entry-point class, role-permission boundary, accounting accumulator, oracle read, cross-protocol integration).
2. **Candidate Location** -- a concrete `file:line` or `Contract.function` in scope where the pattern could plausibly land.
3. **Likely BC / Sweep Link** -- either (a) a known BC tag from the bug class registry or (b) the Structural Anomaly Harvester sweep family (Sweep 1 / 2 / 3 / 4 / 5 / 6 / 7 / 8) it most resembles.

If any of the three is missing or ambiguous, discard (do not weaken the seed; drop it).

### Analog Seed Schema

```markdown
## Seeds (Session A -- investigated this run)

| Analog Seed ID | Source | Analog Pattern (<=25 words) | Local Surface Match | Candidate Location | Likely BC / Sweep Link | Confidence |
|---|---|---|---|---|---|---|

## Seeds (Session B -- forward only, not investigated this run)

| Analog Seed ID | Source | Analog Pattern (<=25 words) | Local Surface Match | Candidate Location | Likely BC / Sweep Link | Confidence | Why deferred |
|---|---|---|---|---|---|---|---|
```

`Confidence` is qualitative (H / M / L) reflecting how cleanly the analog pattern maps to the local surface -- NOT severity. High confidence on a low-severity pattern is allowed and useful.

---

## Conditional Trigger Evaluation (T1-T6)

Analog seeding does NOT always run. Before doing any RAG / WebSearch query, evaluate six grounded triggers. If at least one trigger fires, analog seeding proceeds. If NONE fire, analog seeding is SKIPPED and the artifact records why.

| Trigger | Computation | Fires when |
|---|---|---|
| **T1 -- Low local high-signal seeds** | `count(Sweep 1 entries) + count(Sweep 2) + count(Sweep 5) + count(Sweep 6) + count(Sweep 8) + count(Q2 active) + count(Q3 active) + count(Q5 active) + count(Q7 active)` | < 5 high-signal local seeds total |
| **T2 -- High-risk surface, weak breadth coverage** | `count(attack_surface priority HIGH+) > 5` AND `total breadth findings / max(high_risk_surfaces, 1) < 0.5` | both conditions hold |
| **T3 -- Multiple zero-finding high-risk targets (pre-depth proxy)** | `count(contracts with >= 3 setters) - count(contracts cited by breadth)` | >= 3 contracts with high-risk setters but no breadth findings yet |
| **T4 -- Historical Prime active** | `HISTORICAL_PRIME_MODE` flag from launch state | flag is `true` |
| **T5 -- Novel architecture (no fork ancestry, no diff-audit)** | Fork Ancestry Analysis identifies no known parent AND diff-audit Tier A + Tier B row count == 0 | both conditions hold |
| **T6 -- Uncovered breakpoint** | At least one row in system breakpoints has empty `Reachability.findings` AND empty `Reachability.BC tags` | a documented breakpoint has no coverage |

**Decision**:
- If **any** trigger fires -> run analog seeding per Sources Allowed, Hard Caps, Local Mapping Requirement.
- If **no** trigger fires -> SKIP. Write the skip record with the trigger evaluation table.

### Why Conditional Triggers Improve Precision

SKIPPED is the correct outcome when local signal is sufficient. Analog corpora are a recall booster, not a coverage requirement. Running RAG / WebSearch when local signal is strong would only add noise + budget tax without recall gain.

---

## Dedup / Normalization Methodology

### Purpose

Collapse near-duplicate raw seeds into canonical entries while preserving every source-seed ID. The raw per-seed bookkeeping remains unchanged (one row per raw seed, no information lost).

### Canonical Seed Map Output Schema

```markdown
## Summary
- Raw seeds across all sources: {R}
- Canonical seeds (after dedup): {C}
- Compression ratio: {C}/{R}
- By outcome: PROMOTED {P} / CLEARED {C} / FORWARD {F}
- By family (canonical): E1 {n1} / E2 {n2} / ... / E11 {n11}
- Sibling-linked canonicals: {SL} canonicals with >= 1 sibling link

## Canonical seeds
| Canonical Seed ID | Source Provenance | Primary Location | Domain | Seed Family | Likely BC / Sweep Link | Members | Normalized Outcome | Linked Finding ID or Why unresolved | Open Question | Disputed Assumption | Heuristic Lens |
|---|---|---|---|---|---|---|---|---|---|---|---|

## CLEARED Proof Records (required for every CLEARED canonical)
| Canonical Seed ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (<=25 words) |
|---|---|---|---|---|

## Sibling Links (investigation-neighborhood hints, NOT merges)
| Canonical Seed ID | Linked Canonicals | Link Type |
|---|---|---|

## Proof gaps (members) -- for canonicals with mixed proof quality
| Canonical Seed ID | Members lacking proof | Action |
|---|---|---|
```

### Hard Rules

- Every raw seed MUST appear in exactly one canonical entry's Source Provenance.
- A canonical entry with Members=1 is normal and expected -- most raw seeds are unique.
- Conservative bias: when in doubt, do NOT merge. Better two canonical entries than one wrong merge.
- Normalized Outcome is derived mechanically from members; agents do NOT decide it.
- Every CLEARED canonical MUST have a row in CLEARED Proof Records. Missing proof -> DOWNGRADE to FORWARD_TO_SESSION_B.
- Sibling Links are bounded at max 3 per canonical and are symmetric (A<->B requires both rows).
- Open Question and Disputed Assumption columns are OPTIONAL. Empty values are written as `-`. Inventing fields when not derivable from member evidence is a violation.
- Heuristic Lens column is OPTIONAL. Tag enum is fixed; off-enum values are rejected. Empty value is `-`.

---

## Cross-Source Enrichment Signal

A canonical with Members >= 2 across DIFFERENT sources (e.g., harvester Sweep 1 + AB Q2 + analog with Sweep 1 link all hitting the same location) is a high-signal target -- three independent mechanisms converged. The canonical entry preserves the provenance so downstream phases can use it as a confidence boost.

---

## Why This Methodology Improves Recall Without Increasing FP

- **Recall**: deduplication concentrates DA budget on unique unresolved targets. A single canonical seed CS-3 (with 3 raw members) gets ONE target slot instead of three; the saved slots expand reach or remain unused (precision-positive).
- **No imported severity**: outcome is derived from members' raw outcomes. No new severity assignment, no new evidence claim.
- **No silent loss**: every raw seed appears in exactly one canonical entry's Source Provenance -- verified by the hard rule. The audit trail is complete.
- **Conservative bias**: when in doubt the merge predicate keeps seeds separate. Wrong merges are silent misses; the predicate avoids them by demanding all three conditions (location + class + BC tag).
- **Analog corpora are pre-curated audit / hack data** -- they encode real-world attack shapes the local agents may not have searched for.
- **Caps + the three-part local mapping requirement** ensure that only seeds with a concrete local landing point flow through.
- **No severity or wording is imported** from analogs; the seed only DIRECTS attention. The standard depth + verification gates still apply.
