<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# CLEARED Proof Discipline (v1.7-PATCH3 — PATCH 1)

Source-of-truth for the **proof-quality requirement** that applies to every CLEARED / refuted outcome anywhere in the Valves seed-routing pipeline. CLEARED without proof is not CLEARED — it routes to FORWARD_TO_SESSION_B instead.

## Purpose

Valves is strong at preserving candidates. To beat Plamen on **valid final issues**, it must also be strong at honest, explicit refutation. A vague CLEARED ("looks safe", "no exploit", "guard exists somewhere") weakens audit trust, corrupts cross-audit calibration in `~/.valves/state/bc_class_calibration.md`, and silently hides soft false negatives that would later resurface as missed bugs.

This rule mandates that every CLEARED outcome carry mechanically reviewable proof. If proof is missing, the orchestrator does NOT mark the outcome CLEARED — it routes to an unresolved state.

## § Scope — outcomes governed by this rule

Every one of these outcomes must include the proof fields below:

1. **`CLEARED_PRE_DEPTH`** in `{SCRATCHPAD}/seed_outcomes.md` (Outcome column).
2. **`CLEARED(depth)`** emitted by depth iter 1 / iter 2/3 agents on a seed they investigated (`analysis_depth_*.md` and `analysis_depth_da_*.md`).
3. **Normalized Outcome `CLEARED_PRE_DEPTH`** in `{SCRATCHPAD}/canonical_seed_map.md` — must inherit proof from at least one member raw seed (when ALL members are CLEARED with proof, the canonical entry cites the strongest proof).
4. **Excluded as already-known** rows in `candidate_seeds.md`, `assumption_breaker_seeds.md`, `analog_seeds.md` — these are CLEARED-by-exclusion and must cite the existing finding ID or rule that excluded them (proof_type = OTHER, with the citation).
5. **`[POC-FAIL: GENUINE]`** verdicts at Phase 5 — the verifier already produces a structured PoC + post-state mismatch; this rule applies retroactively in that the verifier's harness output IS the proof artifact (file:line + actual post-state condition + reason). Already covered by `~/.valves/rules/phase5-poc-execution.md` § GENUINE vs SETUP_ERROR; this rule formalizes the proof-field equivalence.
6. **Chain analysis REFUTED** verdicts in `chain_hypotheses.md` — the chain agent's refutation argument must cite a guard / invariant / state condition along the chain.

## § Required minimum proof fields

Every CLEARED outcome MUST carry **all four** fields:

1. **Exact `file:line`** — the specific code location where the proof anchor lives. Not a contract name, not a function name alone, not a "see somewhere in this module".
2. **Exact guard / invariant / fallback / state condition** — the literal code expression OR named invariant OR documented trust statement that blocks exploitability. Must be quotable: a `require()` line, a modifier name, an invariant ID from `semantic_invariants.md`, a Key Invariant from `design_context.md`, or a stated trust assumption.
3. **One-line reason exploitability fails** — a single sentence (≤ 25 words) stating why the proof anchor blocks the exploit path. Must reference both the attacker's intended action AND the guard's blocking effect.
4. **Proof Type** — exactly one of:
   - **`GUARD_PRESENT`** — a `require()`, `revert()`, `if (...) revert`, modifier check, or equivalent runtime check at the file:line blocks the attacker action.
   - **`INVARIANT_ENFORCED`** — a documented invariant from `semantic_invariants.md` § Mirror Variable Pairs / § Main Table OR `design_context.md` § Key Invariants holds at the file:line, and the orchestrator can cite the invariant's enforcement mechanism (validator function, test case, fuzz harness reference).
   - **`TRUST_MODEL_EXPLICIT`** — `design_context.md` § Trust Model explicitly delegates the protected action to the actor at the file:line. The trust statement is a direct match (not a stretch interpretation). `[CORRECTNESS-WINNER]` and Strongest Exploit Card escalations override this — if a card winner depends on this surface, TRUST_MODEL_EXPLICIT does NOT clear it.
   - **`STATE_UNREACHABLE`** — the state required for the exploit cannot be reached because of a Phase 4a.5.a Pass 2 cluster-coverage check, an integer-overflow boundary, an enforced lifecycle order, or an equivalent reachability proof. Must cite the specific state-machine evidence.
   - **`EXTERNAL_DEPENDENCY_SAFE`** — the external value flagged as a risk in `external_mutability_candidates.md` or `external_platform_limits.md` or candidate_seeds.md Sweep 5/8 has a documented staleness-check / circuit-breaker / version-pin AND the staleness-check is enforced (cited at file:line).
   - **`OTHER`** — any other proof type. **Must specify** the type in the proof record (free-form ≤ 10 words). OTHER is permitted but tracked separately in `seed_metrics.md` as `proof_type_other_pct` — high OTHER rate indicates the rule's enumeration is missing a category, not that audits are passing without proof.

## § Hard rule — no proof, no CLEARED

If a candidate CLEARED outcome cannot meet **all four** required fields, the orchestrator MUST NOT mark it CLEARED. The downgrade routing is:

- For raw seeds in `seed_outcomes.md`: route to `FORWARD_TO_SESSION_B` instead of `CLEARED_PRE_DEPTH`. The "Why unresolved" reason becomes `INSUFFICIENT_CLEAR_PROOF` with the partial fields the agent did produce.
- For canonical entries in `canonical_seed_map.md`: when ALL members fail proof, Normalized Outcome becomes `FORWARD_TO_SESSION_B` (not CLEARED). When AT LEAST ONE member has full proof, that member's proof is inherited; the canonical is CLEARED_PRE_DEPTH with the inherited proof; remaining no-proof members are listed in a `## Proof gaps (members)` annotation.
- For depth `CLEARED(depth)` outputs: when the depth agent emits CLEARED without proof fields, the orchestrator's post-iter-1 sanity pass DOWNGRADES the seed to CONTESTED (per Phase 4-confidence-scoring.md AD-1 Hard DA role) and queues the seed for iter 2 DA in Thorough mode (or marks it `INSUFFICIENT_CLEAR_PROOF` and forwards to Session B in Core).
- For analog/AB/harvester exclusions: when the "already-known" citation cannot resolve to a real finding ID or rule reference, the seed is NOT excluded. It is admitted into the depth iter 1 candidate list as a normal seed.

## § Schema for proof records

Where this rule applies, the consuming artifact emits a **Proof Records** sub-section after the main table:

```markdown
## CLEARED Proof Records (v1.7-PATCH3)
| Source ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (≤25 words) |
|---|---|---|---|---|
| Sweep-1:S-3 | GUARD_PRESENT | Vault.sol:142 | `require(asset != address(0))` | Zero-address check blocks the dangling-token-class-replay path the seed described |
| AB-2 | INVARIANT_ENFORCED | Vault.sol:88 | INV-12 (totalShares ≤ totalDeposits) | Pass 2 cluster-coverage shows _redeemShares always co-updates totalDeposits |
| AS-4 | TRUST_MODEL_EXPLICIT | design_context.md L42 | "treasury rotation requires governance multisig" | Multisig timelock blocks unilateral admin pointer-swap in 24h window |
```

Source ID is the raw seed ID (or canonical seed ID for canonical_seed_map.md). The Proof Records sub-section is mandatory; absence of CLEARED rows with empty Proof Records → orchestrator violation.

## § Soft-cap on OTHER proof type

`OTHER` is permitted but the orchestrator tracks `proof_type_other_pct` in `seed_metrics.md` § Proof quality. When `OTHER` proportion exceeds 30% across a single audit's CLEARED outcomes, the orchestrator emits a `PROOF_TYPE_OTHER_HIGH` warning to `degradation_log.md` — this is a calibration signal that the enumeration is too narrow, not a runtime block.

## § Cross-audit calibration

`~/.valves/state/bc_class_calibration.md` gains a per-BC `clear_proof_quality_pct` column over time. When a BC class consistently has weak proof on its CLEARED outcomes (< 70% with full proof fields), it's a calibration signal that this BC family needs sharper detection rules — not a blocker. The calibration update protocol in `~/.valves/state/bc_class_calibration.md` § Update Protocol is extended (mechanical orchestrator-inline append; no rule change needed for the protocol itself, only the column added).

## § Hard gate (SOFT)

This rule is enforced via consuming-artifact validation. There is no separate gate file. If `seed_outcomes.md` or `canonical_seed_map.md` has CLEARED rows with missing proof:

- The orchestrator inline check at COMPLETE_A handoff sub-step build emits `CLEARED_PROOF_GAP_DETECTED` to `degradation_log.md` and DOWNGRADES the affected rows to FORWARD_TO_SESSION_B per § Hard rule above. The pipeline does NOT block — this is recovery-by-routing, not abort.
- Phase 6f embargo (Thorough only) reads the proof gap log; a non-empty `CLEARED_PROOF_GAP_DETECTED` count ≥ 5 across the audit is a quality flag in `compliance_summary.md` (not an embargo block).

## § Why this improves valid final issues (and doesn't increase FP)

- **Forces honest refutation**: CLEARED outcomes that can't meet the four-field bar were silent false negatives in earlier versions. Now they route to Session B, where adversarial DA + verifier independence give them a second look. Valid total → valid final yields more.
- **Stronger calibration over time**: `clear_proof_quality_pct` per BC class lets future audits see which BC families have weakest refutation hygiene → sharper detection rules → fewer missed bugs.
- **No FP risk**: this rule does NOT generate findings. It only constrains how a seed routes. A seed that previously CLEARED without proof now becomes FORWARD_TO_SESSION_B; Session B's DA + verifier path applies the standard evidence gates. False positives are blocked by the existing depth + verification pipeline, not by this rule.
- **No silent loss**: every previously-CLEARED-without-proof outcome is preserved (as FORWARD_TO_SESSION_B with `INSUFFICIENT_CLEAR_PROOF` reason). The audit trail is complete.

## § Compliance with existing architecture

- Strongest Exploit Preservation: TRUST_MODEL_EXPLICIT proof type explicitly defers to `[CORRECTNESS-WINNER]` and Strongest Exploit Card winners — they are NOT cleared by trust assertions even when the trust statement is direct. The Strongest Exploit Gate's anti-overcompression rule remains binding.
- Correctness-Winner Preservation: a finding flagged `[CORRECTNESS-WINNER]` cannot be CLEARED via this rule. Correctness winners go through their own preservation path; CLEARED proof discipline does not interact with them.
- Deferred Clustering: clustering happens post-depth (Phase 4b step 8b). The CLEARED proof rule applies BEFORE clustering, so cluster decisions consume already-validated outcome rows.
- Anti-Absorption Axes: unchanged. Different proof types on different members of the same canonical entry are tracked in the proof record but do NOT prevent canonical merging (the merge predicate already requires location + class + BC tag alignment; proof type is metadata).
