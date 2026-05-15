<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Global Negative Results — Archive

Read-only archive of NR-G entries that have been **CONTRADICTED** (a later audit produced a verified PoC against the path the NR-G said was cleared) or **superseded** (the underlying invariant changed and the NR-G no longer applies).

> **STATE FILE — RECONSTRUCTED SCAFFOLDING.** This file starts empty. Entries arrive only when a live entry in `~/.valves/state/negative_results.md` is moved here under the rules below.

---

## § What lives here

- **CONTRADICTED entries**: an NR-G that previously held was overridden by a verified `[POC-PASS]` in a later audit. Per `~/.valves/rules/negative-results.md` § PRIOR_NEGATIVE handling, the entry is appended here with the contradicting audit cited.
- **Superseded entries**: an NR-G whose underlying invariant changed (refactor / upgrade / protocol fork) such that the cleared path family no longer exists in the form the NR-G described. The entry is moved here with a one-paragraph supersession note.

## § What does NOT live here

- The live NR-G file (`~/.valves/state/negative_results.md`) — that is read at audit time.
- Per-audit `audit_negative_results.md` files — those are scratchpad-local and stay with the audit's scratchpad.

---

## § Archive protocol

When Phase 5.6.1 detects a `PRIOR_NEGATIVE_OVERRIDDEN` case OR an audit explicitly retires an NR-G (supersession):

1. Snapshot the pre-move live file to `~/.valves/state/negative_results_snapshots/{YYYY-MM-DD}_{project}.md`.
2. Remove the NR-G block from `~/.valves/state/negative_results.md`.
3. Append the block to this archive (preserving its NR-G-{N} number — IDs are stable forever).
4. Add a trailing `## Archive note` sub-section to the moved block:

```markdown
## Archive note
- Moved on: {ISO date} from `negative_results.md`.
- Reason: CONTRADICTED | SUPERSEDED
- Triggering audit: {audit_name}, {date}
- Triggering finding ID (if CONTRADICTED): {report ID + scratchpad finding ID}
- One-paragraph context: {what changed, why the NR-G no longer holds}
```

The original `Audit history` table is preserved in the moved block — this records every prior reaffirmation up to the contradicting / superseding audit.

## § Read behavior

Phase 5.6.1 PRIOR_NEGATIVE matching reads ONLY `~/.valves/state/negative_results.md` (live). The archive is reference-only — useful when a reviewer asks "did we ever consider this and clear it?", since the archive shows the path was once cleared but is no longer treated as cleared.

The Phase 6 report does NOT cite archived NR-G entries by default. If an audit explicitly wants to surface "this was previously cleared and is now confirmed", it does so via the `PRIOR_NEGATIVE_OVERRIDDEN` annotation on the report's residual-risk path, citing the live NR-G entry's last-known state at the time of override (which becomes its first archive entry).

---

## § Archived entries

_(none — populated on first archive event)_
