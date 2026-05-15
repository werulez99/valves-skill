<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Bug-Class FP Calibration (cross-audit priors)

Per-BC false-positive calibration data, aggregated across audits. Read by future audits to inform Phase 4c.5 EV ranking and verifier prioritization. Updated by **Phase 5.6.4-pre § Bug-Class FP Calibration Update** (orchestrator inline; no agent spawn).

> **STATE FILE — RECONSTRUCTED SCAFFOLDING.** This file starts with the protocol section + an empty calibration table. Rows arrive only when audits run and the Phase 5.6.4-pre update fires for clusters that have at least one finding with a verifier verdict (CONFIRMED, [POC-PASS], [POC-PASS:BC-NNN-INHERITED], FALSE_POSITIVE, or [POC-FAIL:GENUINE]).

---

## § Update Protocol

The orchestrator runs this inline at Phase 5.6.4-pre, immediately after Phase 5.6.3 (Negative Results capture) and before Phase 5.6.4 (Promotion to global state):

```
For each cluster BC-NNN in {scratchpad}/root_cause_clusters.md:
  Surfaced[BC-NNN]      = 0
  Confirmed[BC-NNN]     = 0
  FalsePositive[BC-NNN] = 0

  For each finding F with cluster tag BC-NNN:
    Surfaced[BC-NNN] += 1
    If F.verdict in {CONFIRMED, [POC-PASS], [POC-PASS:BC-NNN-INHERITED]}:
      Confirmed[BC-NNN] += 1
    elif F.verdict in {FALSE_POSITIVE, [POC-FAIL:GENUINE]}:
      FalsePositive[BC-NNN] += 1
    # other verdicts (CONTESTED, [POC-FAIL: SETUP_ERROR], [CODE-TRACE] only) do NOT increment either counter

  Append-or-update row in this file (one row per touched BC).
```

For each touched BC-NNN, the orchestrator either:
1. **Appends a new row** if the BC has no prior calibration entry, OR
2. **Updates the existing row** by incrementing `Surfaced` / `Confirmed` / `FalsePositive` by this audit's per-cluster counts and appending an audit reference to the BC's audit log.

**Snapshot rule**: snapshot the pre-update file to `~/.valves/state/bc_class_calibration_snapshots/{YYYY-MM-DD}_{project}.md` before any update. The snapshot directory is the curated history; this file is the live aggregate.

**No severity changes here.** This step only updates cross-audit priors. Severity adjustments based on these priors happen at Phase 4c.5 (EV ranking) of FUTURE audits, when this file is read.

---

## § Read behavior (future audits)

Phase 4c.5 reads this file when computing the Verification Priority Queue. For each finding in a candidate cluster BC-NNN:

- **High `Confirmed / Surfaced` ratio** (≥ 0.7 across ≥ 3 audits) → boost `information_gain` term — the class is reliably real.
- **High `FalsePositive / Surfaced` ratio** (≥ 0.5 across ≥ 3 audits) → reduce `information_gain` — the class produces noisy candidates more often than not.
- **Surfaced count < 3** → no calibration signal yet; default `information_gain` from `~/.valves/rules/phase4-confidence-scoring.md` applies.

Calibration influences ranking, not severity. A class with high FP priors still produces findings when the depth + verification evidence is solid for THIS instance.

---

## § Calibration Table

| BC | Name | Surfaced | Confirmed | FalsePositive | Confirm rate | FP rate | Audits | Last updated |
|---|---|---:|---:|---:|---:|---:|---:|---|
| _(empty — populated by Phase 5.6.4-pre on each audit)_ |  |  |  |  |  |  |  |  |

`Confirm rate` = Confirmed / max(Surfaced, 1). `FP rate` = FalsePositive / max(Surfaced, 1). The remainder (1 − Confirm − FP) covers CONTESTED / SETUP_ERROR / CODE-TRACE-only verdicts.

---

## § Per-BC Audit Log (appended below as audits accumulate)

Each touched BC also gets an audit-log block. This preserves the per-audit provenance of each `Surfaced` count so the aggregate can be reconstructed if a snapshot is corrupted.

```markdown
### BC-{NNN} audit log
| Audit | Date | Surfaced | Confirmed | FalsePositive | Verdict notes |
|---|---|---:|---:|---:|---|
| {audit_name} | {date} | {N} | {C} | {FP} | {one-line, e.g. "1 cluster, all instances inheritied [POC-PASS]"} |
```

_(no audit logs yet)_

---

## § Compatibility with `~/.valves/state/bc_class_calibration_snapshots/`

The snapshots directory is created (empty) at the parent level. The first Phase 5.6.4-pre update writes its snapshot there. The directory must exist BEFORE the first update — the orchestrator's snapshot step does NOT create the parent directory itself; it only writes the file.

The directory was provisioned at install time (Phase 1 reconstruction) and is the same one referenced by the slash command at:

```
Snapshot the pre-update file to ~/.valves/state/bc_class_calibration_snapshots/{YYYY-MM-DD}_{project}.md.
```

> **DIR-ONLY by intent**: `~/.valves/state/bc_class_calibration_snapshots/` is correctly empty until the first audit fires Phase 5.6.4-pre.

---

## § Numbering / lifecycle

- BC-NNN identifiers in this file are STABLE — they match `~/.valves/state/bug_class_registry.md` exactly.
- A BC entry in the registry without any rows here means: the class exists but no audit has yet calibrated it.
- A BC with rows here but missing from the registry should never occur — that would mean a calibration update fired before promotion, which violates the Phase 5.6.4 ordering (promotion runs immediately after calibration update). If detected, log `BC_CALIBRATION_REGISTRY_DESYNC` to the next audit's `violations.md`.
