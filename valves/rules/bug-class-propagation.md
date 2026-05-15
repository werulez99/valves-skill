<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Bug-Class Propagation (P1 + P2)

Two-pass propagation: **P1** is a structural sweep run pre-depth (Phase 4a.5.c), seeding hints. **P2** runs after Full Clustering (Phase 4b step 8b → 9), cluster-scoped, budget-aware, with rich propagation per qualifying cluster.

## § Pass 1 (P1, Phase 4a.5.c, sonnet)

**Trigger**: Phase 4a.5 four-agent parallel split. Read `finding_classification.md` (flat BC tags), `~/.valves/state/bug_class_registry.md`.

**Goal**: For each BC-NNN tag appearing in this audit's classification, run ALL grep patterns (multi-pattern per class) from the registry across the codebase. Surface every match as a `STRUCTURAL_CANDIDATE` location for depth-agent investigation.

**Output file**: `{scratchpad}/propagation_structural.md` with sections:

```markdown
## BC-{NNN} — {class name}
- Patterns run: {N total}
- Locations: {file:line ...}
- Per-domain hints (for depth agent injection):
  - token_flow: {locations relevant to value flow}
  - state_trace: {locations relevant to mutation order}
  - edge_case: {locations relevant to boundary conditions}
  - external: {locations relevant to external dependencies}
- Already-found: {locations matching findings_inventory.md (excluded as candidates)}
- Net candidates: {locations remaining after exclusion}
```

P1 in v1.3 also produces THREE additional artifacts in the same spawn:
- `symmetric_pairs.md` — see `~/.valves/rules/symmetric-pairs.md`.
- `external_platform_limits.md` — see `~/.valves/rules/external-protocol-limits.md`.
- `external_mutability_candidates.md` — see `~/.valves/rules/external-state-mutability.md`.

## § Bug-Class Execution Audit (alarms)

After all patterns run, P1 self-audits its grep coverage:

- **BUG_CLASS_ZERO_CANDIDATE_ALARM**: a BC class whose registry `Typical scope` matches this codebase's protocol type but produced ZERO candidates. Record the alarm with an explicit reason: (a) all instances were already in `findings_inventory.md` (legitimate exclusion), (b) the registry signatures are out of date for this idiom, (c) no instances exist (legitimate negative result), (d) grep failed mechanically.

- **ASYMMETRY_FLAG / OVERFLOW_CANDIDATE / MUTABILITY_DRIFT_CANDIDATE**: each row from the auxiliary tables (symmetric pairs, platform limits, mutability) is a **mandatory depth target** that cannot be silently dropped.

Alarms go in a trailing `## Alarms & Coverage Audit` section of `propagation_structural.md`.

## § Pass 2 (P2, Phase 4b step 9, cluster-scoped)

**Trigger**: After Full Clustering (8b) completes — only confirmed clusters propagate.

**Selection rules**:
- **Tier 1 (mandatory within budget)**: CONFIRMED/PARTIAL Medium+ clusters with `cluster_size ≥ 2`.
- **Tier 2 (opportunistic)**: singleton Medium+ clusters, EV-ranked until cap is exhausted.

**Mode caps**:
- Core: up to 5 P2 agents (sonnet).
- Thorough: up to 10 P2 agents (sonnet).

**UNPROPAGATED_BUDGET stubs**: clusters beyond the cap get a marker file `{scratchpad}/propagated_{BC-NNN}.md` with header `STATUS: UNPROPAGATED_BUDGET` and a one-paragraph note pointing at the underlying cluster + reason for de-prioritization. NO agent is spawned for stubs.

**P2 agent inputs (per spawn)**:
- The cluster's full `BC-NNN` block from `root_cause_clusters.md`.
- The relevant rows from `propagation_structural.md` (P1 candidates for this BC).
- `~/.valves/state/bug_class_registry.md` (signatures + audit history priors).
- Source files for every candidate location.

**P2 agent task**:
1. For each P1 candidate location not already in this cluster, decide: PROPAGATE (add to cluster), CLEAR (with one-line reason), or ESCALATE (different cluster needed).
2. For PROPAGATE locations, write a per-finding entry with location + variant notes + recommended depth-agent reading.
3. Write to `{scratchpad}/propagated_{BC-NNN}.md` with sections: `## Cluster context`, `## P1 candidates evaluated`, `## Propagated instances`, `## Cleared (with reasons)`, `## Escalations (new cluster proposals)`.

**Manifest**: orchestrator writes `{scratchpad}/propagation_manifest.md` listing every spawned vs stubbed cluster, then merges spawned outputs into `{scratchpad}/propagation_summary.md` and updates `root_cause_clusters.md` with new instances.

## § Trigger + Budget Reconciliation

P2 ordering rule:
- Runs **AFTER** Full Clustering (8b) — so only confirmed clusters propagate.
- Runs **BEFORE** depth iteration 2 — so devil's advocate agents can re-evaluate propagated instances in their domain.
- Cluster-scoped, NOT finding-scoped — one agent per qualifying cluster regardless of how many findings are in it.

If the per-mode cap is exhausted before all Tier 1 clusters are spawned, that is logged as `P2_TIER1_OVERFLOW` in `violations.md` and Tier 1 clusters that didn't get an agent are marked `UNPROPAGATED_BUDGET`.

## § Why two passes

- **P1 (pre-depth)** is mechanical structural matching — wide-but-shallow. Catches "this pattern looks similar to a known BC" candidates so depth agents have a starting list per domain.
- **P2 (post-depth)** is rich semantic propagation — narrow-but-deep. Only fires for clusters with confirmed evidence, so the budget is spent where the signal is real. Avoids the iter-1 problem of "propagate every BC tag and waste budget on classes that depth refutes anyway".
