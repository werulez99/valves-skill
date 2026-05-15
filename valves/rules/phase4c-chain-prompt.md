<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Phase 4c Chain Analysis

Prompt and methodology for the **Chain Analysis Agent** (Phase 4c). Cluster-scoped, thesis-tagged, breakpoint-tagged. Output: `{scratchpad}/hypotheses.md` (and `{scratchpad}/chain_hypotheses.md` for chain-level entries).

## Mode topology

| Mode | Spawn |
|---|---|
| Light | 1 sonnet (merged enabler enumeration + chain matching in one pass) |
| Core | 2 agents (1 enabler enumeration + 1 chain matching) |
| Thorough | 2 agents iter 1 + 2 agents iter 2 (post-DA pass with new evidence) |

## Inputs

- `{scratchpad}/findings_inventory.md`
- `{scratchpad}/finding_classification.md` and `{scratchpad}/root_cause_clusters.md` (post-depth)
- `{scratchpad}/attack_thesis.md` (latest version available)
- `{scratchpad}/system_breakpoints.md` (breakpoint tags)
- `{scratchpad}/diff_audit_tiers.md` (Tier A/B targets that may chain)
- `{scratchpad}/economic_findings.md` (Phase 4b)
- `{scratchpad}/propagated_*.md` (Phase 4b P2 propagation outputs)
- Source files
- `~/.valves/state/negative_results.md` (so prior cleared chains don't repeat)
- `{scratchpad}/relevant_patterns.md` § Cantina Failure Mode Extracts (v1.7-CANTINA — light injection for chain composition)

## Per-agent task

### Step 1 — Enumerate enablers

For each cluster (or finding without a cluster), list:
- **Direct enablers**: state, role, or precondition required to fire the finding.
- **Compound enablers**: combinations of two or more findings/clusters whose composition is the actual exploit.
- **External enablers**: properties of integrated protocols (oracle freshness, governance state, fee schedule) required.

Output to `{scratchpad}/enablers.md` (or as a top section in `hypotheses.md`).

### Step 1.5 — Cantina failure mode cross-reference (v1.7-CANTINA)

Read `{scratchpad}/relevant_patterns.md` § Cantina Failure Mode Extracts (~30 lines of compact failure modes from real DeFi competition findings). For each enabler enumerated in Step 1, scan the Cantina failure modes for matching postcondition→precondition patterns. Cantina failure modes describe concrete exploit sequences that combined multiple bugs in real protocols — they suggest chain compositions the agent might not derive from first principles alone. This is a LIGHT cross-reference, not a replacement for Step 2's systematic matching.

### Step 2 — Match chains

A chain is an ordered sequence (E1 → E2 → … → Ek → finding(s)) ending at a real impact. For each candidate chain:

```markdown
## CH-{NN} — {one-line chain name}
- Status: CANDIDATE | CONFIRMED | REFUTED
- Trigger: {entry function or external event}
- Path:
  1. {Step 1 — actor + action + state change}
  2. {Step 2 — ...}
  ...
  k. {Step k — terminal impact}
- Findings used: [F-12], [F-44], [E-3 (economic)]
- Cluster refs: BC-NNN, BC-MMM
- Thesis path alignment: P-{N} (if any)
- Breakpoint refs: BP-{NN} (if path culminates at a breakpoint)
- Diff Tier refs: A | B (if any step lands on a diff-audit Tier A/B function)
- Worst-state severity: {Critical/High/Medium}
- Confidence: 0.00–1.00
- Refutation contract: {what would refute this chain — kept for verifier}
```

### Step 3 — Refutation pass

For each chain, attempt to refute by:
- Checking guards / modifiers along the path that would block the actor.
- Checking trust model assumptions in `design_context.md`.
- Checking `~/.valves/state/negative_results.md` for prior NR-G entries that cover this chain.

If refuted → set Status = REFUTED, write a one-paragraph refutation, append the entry to `audit_negative_results.md` under § Chain Analysis REFUTED Verdicts.

## § Cluster-scoped grouping

The agent groups by cluster, not by finding. A cluster representative's chain inherits to non-representative instances IF the inheritance conditions in `~/.valves/rules/verification-priority-queue.md` § Cluster Inheritance hold. Inherited chains are noted on the non-rep instance with `CHAIN-INHERITED:CH-NN`.

## § Thesis-tagged

Every chain that aligns with an `attack_thesis.md` v1/v2 path records the path ID under `Thesis path alignment`. This is read by Phase 4c.5 EV ranking to apply the thesis_alignment multiplier.

## § Breakpoint-tagged

Every chain that culminates at a system breakpoint (insolvency, cascade, first-loss exhaustion, oracle drift) records the BP-NN tag. Read by Phase 4c.5 EV (chains hitting breakpoints get +3 EV) and by the report's Residual Risk Summary.

## Iter 2 (Thorough only)

After DA depth iterations 2-3 and the Full Cluster Agent (post-depth), spawn a second pair of chain agents with:
- Updated `findings_inventory.md` (DA findings included).
- Updated `root_cause_clusters.md` (post-DA reclustering).
- Updated `attack_thesis.md` v2 (post-DA synthesis).

The iter 2 agents look specifically for chains that compose iter 1 + iter 2 evidence. They do NOT re-derive iter 1 chains.

## Output gates

`hypotheses.md` MUST exist before Phase 4c.5 (Verification Priority Queue Construction) reads it. `chain_hypotheses.md` is optional — chain entries can live in the same file.

## Light-mode merge

Light mode runs ONE sonnet agent that does enabler enumeration + chain matching + refutation in one pass. Output is the same — single `hypotheses.md`.
