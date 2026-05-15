<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Correctness-Winner Preservation

Source-of-truth for the `[CORRECTNESS-WINNER]` flag emitted by the Validation Sweep Agent (Phase 4b iter 1) and the Classification Agent (Phase 4a.2-lite). Binding constraint on the Full Cluster Agent (4a.2-full) and the Report Index Agent (Phase 6).

## Purpose

Strongest-exploit preservation (`~/.valves/rules/strongest-exploit-preservation.md`) covers parent-exploit findings (custody loss, recovery severance, etc.). **Correctness winners are different.** They are findings whose value is in *being right* about a precise mechanical defect — even when the standalone severity is Medium or Low — and which would be lost if absorbed into a generic cluster.

Examples:
- A specific admin-setter validation gap (`[VS-AS-1]`) that exposes a unique parameter in a unique contract.
- A variable-flow attribution mismatch (`[VS-AT-1]`, BC-041) where two accumulators that should track the same quantity diverge under one specific branch.
- A symmetric-pair asymmetry where deposit checks `pause` but withdraw does not.
- An interface-mismatch seed (DEPENDENCY_SEED in candidate_seeds.md) that depth confirms.

These findings have **fix-distinctness**: their patch is different from any other cluster member's. Absorbing them removes the precise fix from the report.

## Eligibility (any one is sufficient)

- **C1 — Distinct fix**: the patch line/diff differs materially from other findings in the candidate cluster (different file, different function, different validation idiom).
- **C2 — Distinct invariant**: the finding violates a different invariant from cluster siblings (e.g., one violates "totalShares ≤ totalDeposits", another violates "rewardIndex monotone").
- **C3 — Distinct trigger surface**: the entry function and the actor type differ from siblings.
- **C4 — Mechanical scanner provenance**: emitted by Validation Sweep Agent (`[VS-AS-1]`, `[VS-AT-1]`) or Structural Anomaly Harvester with depth confirmation — these are by-construction precise.

## Tagging

Classification Agent (4a.2-lite) reads this file and tags qualifying findings with `[CORRECTNESS-WINNER]` in the Flags column of `finding_classification.md`.

Validation Sweep Agent emits `[CORRECTNESS-WINNER]` directly on findings it produces (Phase 4b iter 1).

## Binding constraint on Full Cluster Agent (4a.2-full)

For each cluster:
1. List all findings tagged `[CORRECTNESS-WINNER]`.
2. Apply the Anti-Absorption Axes from `~/.valves/rules/strongest-exploit-preservation.md`. If any axis differs from the cluster representative, the correctness winner gets its **own subgroup** (BC-NNN.A, BC-NNN.B, ...).
3. Record the subgroup decision in `cluster_instance_map.md` under § Subgroup Split Rules.

A correctness winner that ends up in the same subgroup as another finding MUST share its fix verbatim. If the fix differs even by one line, split the subgroup.

## Binding constraint on Report Index Agent (Phase 6)

When emitting report IDs from `cluster_instance_map.md`, every subgroup containing a correctness winner gets a **distinct report ID** with the correctness winner's exact fix in the Recommendation block.

The report MAY group multiple correctness winners under one cluster heading when their root cause is shared, but each gets its own row in the multi-location table and its own Recommendation diff.

## Why this matters

Correctness winners are how Valves finds the *unique* defect that a generic "missing input validation" cluster would otherwise hide. A report that says "10 places need validation" gives the team less actionable signal than a report that says "9 places need the standard zero-address check + 1 place needs a state-dependent bounds check that the others do not".
