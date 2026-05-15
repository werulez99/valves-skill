<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Bug-Class Registry & Clustering

Source-of-truth for the BC-NNN classification system used by:
- **Classification Agent** (Phase 4a.2-lite) — pre-depth flat tagging.
- **Full Cluster Agent** (Phase 4b step 8b, post-depth) — evidence-aware merging.
- **Cluster → Report Mapping** (Phase 5.6.5) — subgroup splitting for report IDs.

## File locations

- Per-audit, pre-depth: `{scratchpad}/finding_classification.md` (FLAT — one row per finding, no clustering).
- Per-audit, post-depth: `{scratchpad}/root_cause_clusters.md` (clusters, with subgroup splits).
- Per-audit, post-Phase-5.6: `{scratchpad}/cluster_instance_map.md` (cluster → report-ID decisions).
- Global persistent: `~/.valves/state/bug_class_registry.md` (BC-NNN definitions across audits).

## § v1 Generation (Full Cluster Agent — post-depth)

The Cluster Agent runs AFTER depth iter 1 + scoring + Thesis v2, with depth evidence and confidence scores in hand. It groups findings sharing the same BC-NNN tag, with these binding rules:

**Inputs**: `findings_inventory.md` (with depth findings), `finding_classification.md` (pre-depth BC tags), `strongest_exploit_cards.md` (card winners cannot be absorbed), `confidence_scores.md`, `attack_thesis.md` v2, `~/.valves/state/bug_class_registry.md`, `design_context.md`.

**Steps**:
1. Group findings sharing the same BC-NNN tag into a candidate cluster.
2. Verify the common fix pattern (now informed by depth analysis). If the fix differs across instances → **split into subgroups**.
3. Apply the **Strongest Exploit Preservation Hard Rule** — card winners get distinct clusters/subgroups (see `~/.valves/rules/strongest-exploit-preservation.md`).
4. Apply **Correctness-Winner Preservation** — `[CORRECTNESS-WINNER]` findings get subgroups when fix differs (see `~/.valves/rules/correctness-winner-preservation.md`).
5. Apply **Anti-Absorption Axes** (access control, victim, severity, exploit path, fix pattern).
6. Apply **Anti-Overcompression Rule** (parent custody/recovery > child permission/symptom).

### Evidence-Aware Clustering Rules (v1.7)

These rules use depth evidence that pre-depth clustering didn't have:

- **Different verdicts at decent confidence ≠ same bug**: do NOT merge findings where BOTH have confidence ≥ 0.5 but reach DIFFERENT verdicts (one CONFIRMED, one PARTIAL/REFUTED).
- **Don't lose low-confidence singletons**: do NOT merge a CONFIRMED finding with a LOW_CONFIDENCE finding if they have different locations AND different depth evidence tags. The low-confidence finding may be a distinct bug — preserving it gives chain analysis a candidate.
- **Thesis-aligned findings preserved**: findings referenced by `attack_thesis.md` v2 as supporting evidence CANNOT be absorbed where they lose individual traceability. Each thesis-supporting finding must be identifiable in the cluster's instance list.

### Output (`root_cause_clusters.md`)

```markdown
## BC-{NNN} — {short class name}
- Common fix: {one-sentence canonical patch}
- Severity: {after R17 floor}
- Verification target: {primary instance to verify; others inherit}
- Thesis path refs: P-{N}, P-{M}, ...
- Card refs: SEC-{N}, ...
- Instances:
  | Finding ID | Location | Variant note | Confidence | Verdict so-far |
  |---|---|---|---|---|
  | [F-12] | Vault.sol:142 | base case | 0.81 | CONFIRMED |
  | [F-44] | Vault.sol:198 | second occurrence, identical fix | 0.75 | PARTIAL |

### Subgroups (when material differences exist)
- BC-{NNN}.A — {differentiator}: instances [F-12]
- BC-{NNN}.B — {differentiator}: instances [F-44]
```

## § Subgroup Split Rules

A cluster splits into subgroups when ANY of these material differences exist between instances:

1. **Access control** differs (untrusted vs admin-only vs self-only).
2. **Victim** differs (depositor vs LP vs treasury vs governance).
3. **Severity (after modifiers)** differs (post R17 floor / post PROVEN_ONLY).
4. **Exploit path** differs (different functions, different state machine path).
5. **Fix pattern** differs (different files, different idiom, different invariant added).

Each subgroup gets its own report ID (BC-NNN.A, BC-NNN.B, ...). Within a subgroup, all instances share fix verbatim.

## § New Class Promotion Protocol

For each `BC-NEW-???` cluster from this audit with **≥1 finding verdict `[POC-PASS]`** in Phase 5:

1. Assign a new BC-NNN number (next free in `~/.valves/state/bug_class_registry.md`).
2. Append a registry entry:
   ```markdown
   ## BC-{NNN} — {class name}
   - First seen: {audit name + date}
   - Pattern: {grep-able structural signature, ≥3 patterns when possible}
   - Typical scope: {what kinds of contracts/protocols this applies to}
   - Common fix: {canonical patch}
   - Severity priors: Critical/High/Medium/Low (count from this & future audits)
   - Audit history: [{audit_name, date, instance_count, confirmed, false_positive}]
   ```
3. Snapshot the pre-promotion registry to `~/.valves/state/bug_class_registry_snapshots/{YYYY-MM-DD}_{project}.md`.

Promotion is gated on a confirmed PoC. BC-NEW classes without verification stay per-audit only.

## § Cluster Inheritance (Phase 5)

When a cluster representative returns `[POC-PASS]`:
1. Tag non-representative instances with `[POC-PASS:BC-NNN-INHERITED]` in `findings_inventory.md`.
2. Skip per-instance verifier spawns where inheritance conditions hold (see `~/.valves/rules/verification-priority-queue.md` § Cluster Inheritance for the conditions).

When a cluster representative returns `[POC-FAIL]` or `CONTESTED`:
- Inheritance does NOT apply. Each instance must be verified independently or remain at its scoring-derived verdict.

## § Registry signature greps (used by Propagation P1)

Each registry entry SHOULD list ≥3 grep patterns covering the BC's structural signature. Propagation P1 (Phase 4a.5.c) runs ALL patterns per BC, not just one — single-pattern matching causes BUG_CLASS_ZERO_CANDIDATE_ALARM false-negatives. See `~/.valves/rules/bug-class-propagation.md` § Bug-Class Execution Audit.
