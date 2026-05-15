<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Bounded Analog Seeds (PATCH G)

Source-of-truth for `{SCRATCHPAD}/analog_seeds.md`. Use external vulnerability corpora as bounded pattern priors only — never as direct findings, never as imported severity.

## Where it runs

Phase 4a.5.f — orchestrator-inline (no new agent spawn). Runs after the 4a.5 four-agent split + assumption-breaker (4a.5.e), before depth iter 1. Output feeds the candidate-seed flow that depth agents read in iter 1.

**Conditional execution (v1.7-PATCH2 — PATCH 2)**: Phase 4a.5.f does NOT always run. Before doing any RAG / WebSearch query, the orchestrator evaluates six grounded triggers (§ Conditional triggers below). If at least one trigger fires, analog seeding proceeds with the existing methodology. If NONE fire, analog seeding is SKIPPED and the artifact records why. This makes analog seeding a targeted recall booster, not a constant network-and-budget tax.

## § Conditional triggers (v1.7-PATCH2)

The orchestrator evaluates these triggers using only artifacts available at Phase 4a.5.f time (post-recon, post-Phase 3 breadth, post-4a.5 four-agent split, post-4a.5.e assumption-breaker — but pre-depth-iter-1, so no `findings_inventory.md` yet, only `analysis_*.md` breadth output).

| Trigger | Computation | Fires when |
|---|---|---|
| **T1 — Low local high-signal seeds** | `count(candidate_seeds.md Sweep 1 entries) + count(Sweep 2) + count(Sweep 5) + count(Sweep 6) + count(Sweep 8) + count(assumption_breaker_seeds.md Q2 active) + count(Q3 active) + count(Q5 active) + count(Q7 active)` (Q7 added v1.7-PATCH7 — sequence-not-enforced) | < 5 high-signal local seeds total |
| **T2 — High-risk surface, weak breadth coverage** | `count(attack_surface.md priority HIGH+) > 5` AND `total breadth findings (analysis_*.md) / max(high_risk_surfaces, 1) < 0.5` | both conditions hold |
| **T3 — Multiple zero-finding high-risk targets (pre-depth proxy)** | `count(contracts in setter_list.md with ≥ 3 setters) − count(contracts cited by analysis_*.md)` | ≥ 3 contracts with high-risk setters but no breadth findings yet |
| **T4 — Historical Prime active** | `HISTORICAL_PRIME_MODE` flag from launch state | flag is `true` |
| **T5 — Novel architecture (no fork ancestry, no diff-audit)** | `meta_buffer.md` § Fork Ancestry Analysis identifies no known parent AND `diff_audit_tiers.md` Tier A + Tier B row count == 0 | both conditions hold |
| **T6 — Uncovered breakpoint** | At least one row in `system_breakpoints.md` has empty `Reachability.findings` AND empty `Reachability.BC tags` | a documented breakpoint has no Session A coverage |

**Decision**:
- If **any** trigger fires → run analog seeding per § Sources allowed, § Hard caps, § Local mapping requirement, § Output schema.
- If **no** trigger fires → SKIP. Write `analog_seeds.md` with `## Source: SKIPPED — no triggers fired` + the trigger evaluation table (§ Skip protocol below).

## § Skip protocol (when no triggers fire)

The orchestrator still writes `analog_seeds.md`, but the file is structured as a SKIP record:

```markdown
# Bounded Analog Seeds — {project} — {ISO timestamp}

## Source: SKIPPED — no triggers fired

## Trigger evaluation (v1.7-PATCH2)
| Trigger | Computed value | Threshold | Fired? |
|---|---|---|---|
| T1 Low local high-signal seeds | {N} | < 5 | NO |
| T2 High-risk surface, weak breadth | hi-risk={H}, ratio={R} | H>5 AND R<0.5 | NO |
| T3 Zero-finding high-risk targets | {Z} | ≥ 3 | NO |
| T4 Historical Prime active | {true/false} | true | NO |
| T5 Novel architecture | fork-known={true/false}, tiers={T} | both NO/0 | NO |
| T6 Uncovered breakpoint | {0 / N} | ≥ 1 | NO |

## Effect on downstream artifacts
- `seed_outcomes.md` Per-source counters: analog row reads `0/0/0`.
- `canonical_seed_map.md`: zero canonical entries from analog source.
- `seed_metrics.md`: Analog rows show 0 created, SKIPPED row reads as active.
- `session_a_to_b_handoff.md` § 2: zero analog-source rows; canonical map contributions from harvester + assumption-breaker only.

## Why this matters
SKIPPED is the correct outcome when local Session A signal is sufficient. Analog corpora are a recall booster, not a coverage requirement; this audit had ≥ 5 high-signal local seeds AND ≤ 5 high-risk surfaces with healthy breadth coverage AND zero novel-architecture or breakpoint-coverage flags AND no Historical Prime context. Running RAG / WebSearch in this state would only add noise + budget tax without recall gain.

The orchestrator logs `analog_seeding_SKIPPED_NO_TRIGGER` to `{SCRATCHPAD}/degradation_log.md` for observability — this is NOT a degradation in the negative sense; it's a successful skip. Tracked separately from `analog_seeds_UNAVAILABLE` (which means RAG + Tavily both failed).
```

When triggers DO fire, the file's first line is `## Source: {RAG / Tavily / Combined}` and the body is the standard schema in § Output schema below — followed by a `## Triggers fired (v1.7-PATCH2)` section listing which triggers fired (so future audits can correlate analog-seed hit rate to trigger pattern).

## Sources allowed

- **Solodit** — via `mcp__unified-vuln-db__*` MCP queries (already wired by Plamen install).
- **Code4rena** — via Solodit aggregator OR direct query if Tavily / WebSearch is available.
- **Sherlock** — via Solodit aggregator OR direct query.
- **CodeHawks** — via Solodit aggregator OR direct query.
- **DeFiHackLabs** — via `mcp__unified-vuln-db__*` (DefiHackLabs source already indexed).

If the unified-vuln-db RAG is built, the orchestrator pulls a top-K (K ≤ 16) candidate list using `protocol_category`, `attack_surface_type`, and `quality_score ≥ 3` filters. If RAG is not built, fall back to Tavily / WebSearch with the same filters; if both fail, write an empty `analog_seeds.md` with `## Source: NONE_AVAILABLE` and proceed.

## § Hard caps

- **≤ 8 analog seeds total** in `analog_seeds.md`.
- **≤ 5 may flow into Session A investigation** (depth iter 1 + DA pass). The remaining (up to 3) are FORWARD_TO_SESSION_B candidates only; Session B may consider them when ranking unresolved targets in `session_a_to_b_handoff.md`.
- **Local mapping vague → discard.** A seed that cannot point to a concrete local file/function is dropped, not weakened.
- **No imported severity.** The analog finding's original severity is recorded in the table for context but does NOT flow into local scoring.
- **No copied report wording.** The seed's `Analog Pattern` field is a one-line abstraction (≤ 25 words); the seed agent / orchestrator does not paste verbatim from the source.
- **No direct findings.** An analog seed becomes a finding only via the standard depth + verification path. Until then it is investigation-direction signal.

## § Local mapping requirement

Each analog seed MUST resolve to **all three**:

1. **Local Surface Match** — a category match between the analog's pattern and a surface in `attack_surface.md` (entry-point class, role-permission boundary, accounting accumulator, oracle read, cross-protocol integration).
2. **Candidate Location** — a concrete `file:line` or `Contract.function` in scope where the pattern could plausibly land.
3. **Likely BC / Sweep Link** — either (a) a known BC tag from `~/.valves/state/bug_class_registry.md` or (b) the Structural Anomaly Harvester sweep family (Sweep 1 / 2 / 3 / 4 / 5 / 6 / 7 / 8) it most resembles.

If any of the three is missing or ambiguous → discard (do not weaken the seed; drop it).

## § Output schema (`analog_seeds.md`)

```markdown
# Bounded Analog Seeds — {project} — {ISO timestamp}

## Source health
- RAG (unified-vuln-db) reachable: YES | NO
- Fallback (Tavily / WebSearch) used: YES | NO
- Total candidates evaluated: {N}
- Total accepted (after caps + local-mapping requirement): {M ≤ 8}
- Routed to Session A (depth iter 1): {≤ 5}
- Routed to Session B (forward-only): {M − 5}

## Seeds (Session A — investigated this run)

| Analog Seed ID | Source | Analog Pattern (≤25 words) | Local Surface Match | Candidate Location | Likely BC / Sweep Link | Confidence |
|---|---|---|---|---|---|---|
| AS-1 | Solodit#... | ... | accounting accumulator on rebase | Vault.sol:142 _accruePending() | BC-041 / Sweep 7 (mirror-acct-drift) | M |
| ... |

## Seeds (Session B — forward only, not investigated this run)

| Analog Seed ID | Source | Analog Pattern (≤25 words) | Local Surface Match | Candidate Location | Likely BC / Sweep Link | Confidence | Why deferred |
|---|---|---|---|---|---|---|---|
| AS-6 | DefiHackLabs#... | ... | reentrancy via fallback callback | Strategy.sol:88 harvest() | BC-007 / Sweep 1 | M | over Session A cap |
| ... |
```

`Confidence` is qualitative (H / M / L) reflecting how cleanly the analog pattern maps to the local surface — NOT severity. High confidence on a low-severity pattern is allowed and useful.

## § Routing into the candidate-seed flow

For Session A (≤ 5 routed): the orchestrator merges these seeds into the Phase 4b iter 1 depth-agent prompts as **additional investigation hints**, in the SAME slot as `candidate_seeds.md` § Seeds by Depth Domain. They are tagged with their AS-{N} IDs so depth agents can cite "CLEARED via AS-3" or "promoted via AS-3" in their output.

For Session B (forward only): they are recorded in `seed_outcomes.md` with outcome `FORWARD_TO_SESSION_B` and consumed by `session_a_to_b_handoff.md` § Top unresolved seeds. Session B's DA agents may investigate them; they are NOT a Session B coverage floor (the floor is `session_a_to_b_handoff.md`'s Recommended Targets list, capped per its own rules).

## Soft-required (Rule 15)

If the analog-seed step fails entirely (no RAG, no fallback), write `analog_seeds.md` with `## Source: NONE_AVAILABLE`, log `analog_seeds_UNAVAILABLE` to `{SCRATCHPAD}/degradation_log.md`, and continue. Pipeline does not block.

## Why this improves recall (and does not increase FP)

- Analog corpora are pre-curated audit / hack data — they encode real-world attack shapes the local agents may not have searched for.
- Caps + the three-part local mapping requirement ensure that only seeds with a concrete local landing point flow through.
- No severity or wording is imported; the seed only DIRECTS attention. The standard depth + verification gates still apply, so a poorly-mapped analog cannot escape into the report.
- The Session B forward-only sub-cap (≤ 3) prevents Session A from blowing budget chasing analogs that may not be relevant to this protocol.
