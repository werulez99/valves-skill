<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Global Negative Results (NR-G)

Cross-audit "considered and cleared" memory. Read by Phase 4 Devil's Advocate (so prior cleared paths aren't re-litigated), Phase 4c chain analysis (refutation step), Phase 5.6.1 attack_thesis.md v3 generation (PRIOR_NEGATIVE handling). Appended to by Phase 5.6.4 § Promotion Protocol.

> **STATE FILE — RECONSTRUCTED SCAFFOLDING.** This file starts empty. Real NR-G entries are produced when audits run, eligible per-audit `audit_negative_results.md` rows are promoted under `~/.valves/rules/negative-results.md` § Promotion Protocol, and the entry meets the promotion criteria (HIGH confidence, generalizable, fragility envelope documented, concrete refutation artifact).

---

## § Promotion Protocol

See `~/.valves/rules/negative-results.md` § Promotion Protocol. Live behavior:

1. Phase 5.6.4 scans `{scratchpad}/audit_negative_results.md`.
2. For each entry meeting ALL criteria below, append a new NR-G block to this file:
   - **Confidence is HIGH** (the agent's verdict was strong, not LOW or MEDIUM).
   - **Generalizable: YES** (the path family applies beyond a single contract / project).
   - **Fragility envelope is non-empty and specific** (states the conditions under which the verdict would flip).
   - **Concrete refutation artifact** (specific code line, test failure, math constraint — not just "agent said no").
3. Snapshot the pre-update file to `~/.valves/state/negative_results_snapshots/{YYYY-MM-DD}_{project}.md` before each append. (Snapshot directory is created on first promotion if absent.)

Failed entries (any criterion missing) stay per-audit only and do NOT appear here.

---

## § PRIOR_NEGATIVE handling (Phase 5.6.1)

When the orchestrator generates `attack_thesis.md` v3, each path is matched against the entries below:

- **Path matches an NR-G AND no fresh evidence in this audit** → mark `PRIOR_NEGATIVE_INHERITED`, downgrade thesis path to REFUTED with citation `(NR-G-{N}, last reaffirmed {audit, date})`.
- **Path matches an NR-G AND this audit produced `[POC-PASS]` (or any verifier verdict that contradicts)** → mark `PRIOR_NEGATIVE_OVERRIDDEN`, increment the entry's `PRIOR_NEGATIVE_OVERRIDDEN count`, append a `CONTRADICTED` row to its audit history, AND move the entry to `~/.valves/state/negative_results_archive.md` per the archive protocol.
- **No match** → standard v3 status rules apply (see `~/.valves/rules/attack-thesis.md` § v3 Generation).

PRIOR_NEGATIVE annotations are carried verbatim into the report's `## Residual Risk Summary` section so reviewers can see what was reconsidered.

---

## § NR-G Entry Format (template — copy on each promotion)

```markdown
## NR-G-{N} — {short pattern name}
- First seen: {audit_name, date}
- Last reaffirmed: {audit_name, date}
- Pattern: {grep-able or one-sentence description of the path family}
- Why cleared (canonical): {refutation argument that has held — concrete: code line, math constraint, or invariant}
- Fragility envelope: {when does this flip — specific list of conditions: "if X is removed", "if Y becomes admin-mutable", "if Z exceeds N"}
- Generalizable: YES
- Audit history:
  | Audit | Date | Outcome |
  |---|---|---|
  | {audit_name} | {date} | REAFFIRMED |
- PRIOR_NEGATIVE_OVERRIDDEN count: 0
```

`Audit history` outcome values:
- **REAFFIRMED** — this audit looked at the path family and again found no real bug; the NR-G holds.
- **CONTRADICTED** — this audit found a real bug in the path family; the NR-G is moved to the archive.
- **N/A** — this audit's protocol type does not match the NR-G's typical scope, so the NR-G was not exercised.

---

## § Active NR-G entries

_(none — populated on first promotion)_

---

## § Numbering policy

NR-G IDs are stable forever. When an entry is moved to the archive (`negative_results_archive.md`), its NR-G-{N} ID does NOT get reused. New entries take the next free integer above the highest live or archived ID.
