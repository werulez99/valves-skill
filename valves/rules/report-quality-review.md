<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Report Quality Self-Review (Phase 6d)

Methodology for the **Report Quality Self-Review Agent** (haiku, 1 spawn, all modes). Output: `{scratchpad}/report_review.md` + inline edits to `AUDIT_REPORT.md`.

## Scope

Runs after the Assembler writes `AUDIT_REPORT.md`. The agent reads the *finished* report, runs 6 mechanical checks, applies trivial safe fixes inline, and flags everything else for human review (no rewrites of substantive content).

## Inputs

- `{PROJECT_ROOT}/AUDIT_REPORT.md` — the finished report.
- `{SCRATCHPAD}/findings_inventory.md`, `{SCRATCHPAD}/cluster_instance_map.md`, `{SCRATCHPAD}/verify_*.md` — to ground checks against source material.
- `{SCRATCHPAD}/attack_thesis.md` v3 — for residual-risk consistency.

## § The 6 Checks

### Check 1 — Critical/High specificity

For every Critical and High finding, verify the description names a concrete (victim, attacker, impact) triple. "Loss of funds is possible" is too vague; "An untrusted depositor can drain the vault by reentering withdraw via the strategy hook before the share burn" is specific.

If vague → flag with `CHECK1_VAGUE: <ID>`. Do NOT auto-rewrite. Note: copying a sharper sentence from the corresponding `verify_*.md` file IS allowed inline (trivial safe fix).

### Check 2 — Code snippet presence

Every finding must include a code snippet showing the defective line(s). If absent, paste the snippet from the `Code` section of the source `verify_*.md` or the original analysis file (trivial safe fix). If neither has it → flag `CHECK2_NO_SNIPPET: <ID>`.

### Check 3 — Recommendation actionability

The Recommendation block must propose a specific patch or invariant to add. "Add validation" is too vague; "Add `require(asset != address(0))` at line 142" is actionable.

If vague AND the corresponding verify file has a fix diff → paste the diff inline. If neither → flag `CHECK3_VAGUE_RECOMMENDATION: <ID>`.

### Check 4 — Severity-description coherence

If a finding is rated Critical but its description names "minor inconvenience" or its impact section says "no funds at risk", the severity contradicts the description. Likewise the inverse: a Low rated finding describing complete protocol drain is mis-scored.

When detected → flag `CHECK4_SEVERITY_DESC_MISMATCH: <ID>`. Do NOT auto-edit severity (severity is a Phase 4/5 verdict — Phase 6d is not authoritative on it).

### Check 5 — Executive summary ↔ finding list consistency

Count Critical/High/Medium/Low/Info in the finding list. Verify the executive summary's count matches. Verify every finding ID listed in the executive summary table appears in the body.

If counts mismatch → fix the executive summary inline (trivial safe fix). If an executive-summary ID has no body → flag `CHECK5_ORPHAN_ES_ID: <ID>`.

### Check 6 — Internal contradictions

Look for contradictions across findings:
- Two findings claim opposite verdicts about the same code path.
- Recommendations conflict (one says "add a guard", another says "remove that guard").
- Residual Risk Summary references a path that the finding list says is REFUTED.

When detected → flag `CHECK6_CONTRADICTION: <ID_a>↔<ID_b>` with a one-paragraph explanation.

## § Trivial Safe Fix vs Flag-Only

A fix is **trivial-safe** ONLY when:
- It pastes existing content from a verified source (`verify_*.md`, `analysis_*.md`, executive-summary count tally).
- It does not invent new prose.
- It does not change severity.
- It does not change the description's substantive claims.

Anything else (Description rewrites, Severity changes, Executive Summary rewrites beyond count tally, Recommendation rewrites without a source diff) → FLAG ONLY.

## § Output

`{SCRATCHPAD}/report_review.md` (full review):

```markdown
# Report Quality Review — {project} — {ISO}

## Issues found
| Issue ID | Check | Finding | Severity-of-issue | Auto-fixed? | Notes |
|----------|-------|---------|-------------------|-------------|-------|

## Auto-fixes applied to AUDIT_REPORT.md
| Finding | Section | What was pasted | Source artifact |
|---|---|---|---|

## Flagged for human review
| Finding | Check | Description |
|---|---|---|

## Summary
- Total issues: {N}
- Auto-fixed: {M}
- Flagged: {K}
```

Return: `'DONE: {N} issues found, {M} auto-fixed inline, {K} flagged for human review'`.

## § Integration With Phase 6 Flow

If `K > 0` (flagged-only issues), append a `## Report Quality Notes` section to `AUDIT_REPORT.md` listing the flagged items so reviewers see them at the top of the document, not buried in a scratchpad.

If `K == 0` and `M >= 0` → quality review reports cleanly; nothing appended to AUDIT_REPORT.md beyond the inline auto-fixes already applied.

## Why this is haiku

Mechanical 6-check sweep with explicit fix-source rules. No reasoning depth required. Haiku is fast enough that running this gate is cheap relative to the value of catching count mismatches and orphan IDs before the report ships.
