<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Phase 5 PoC Execution

Companion methodology to `~/.claude/prompts/{LANGUAGE}/phase5-verification-prompt.md`. Defines verifier semantics, PoC harness expectations, evidence tags, and inheritance behavior. The slash command's Phase 5 step reads BOTH files.

## Verifier model selection

| Tier | Model |
|---|---|
| Chain hypotheses (CH-*) | opus |
| High standalone | opus |
| Medium | sonnet |
| Low + Info (Thorough only) | sonnet (single agent for the whole tier) |

## Harness expectations per language

| Language | Build / Test runner | PoC idiom |
|---|---|---|
| EVM | Foundry | `forge test --match-contract <PoC>` with optional `--fork-url` |
| Solana | Anchor + cargo | `anchor test` (or raw cargo + `solana-program-test`) |
| Aptos Move | aptos CLI | `aptos move test` against module |
| Sui Move | sui CLI | `sui move test` |
| Soroban | stellar CLI | `cargo test` with `soroban-sdk` test harness |

The verifier writes the PoC into the project's test directory using the project's standard idiom. For findings where a fork test is needed (Phase 1 RPC_URL set), pass `--fork-url $RPC_URL`.

## § Hypothesis-killing pre-check (v1.7-PATCH7 — MANDATORY before any PoC)

The verifier's job is not to confirm a finding. It is to find the strongest reason the finding fails, and only declare CONFIRMED when the finding survives that pressure. See `~/.valves/rules/valves-doctrine.md` § Kill-the-hypothesis mindset for the principle; this section is the mechanical check.

Before writing any PoC, the verifier MUST emit a § Hypothesis-killing pre-check sub-section in `verify_{id}.md` BEFORE any test code. Each answer is one short paragraph (≤ 4 sentences) plus an explicit `kills_hypothesis: YES/NO` field per question.

```markdown
## § Hypothesis-killing pre-check

### Q1 — Guard / invariant / trust assumption
- What guard, runtime check, modifier, named invariant, or stated trust assumption could block this attack at the alleged actor + entry point?
- Cite specific code (file:line) or invariant ID. If no candidate guard exists, state explicitly: `no candidate guard identified at the entry point`.
- kills_hypothesis: YES / NO

### Q2 — State precondition reachability
- What state precondition is required for the attack to fire?
- Is that precondition actually reachable by the alleged actor under the documented trust model in `design_context.md`? Cite the trust statement.
- kills_hypothesis: YES / NO

### Q3 — Unenforced call-order dependence
- Does the attack succeed only when an unenforced call-order assumption holds (i.e., the developer expected F1 before F2 but neither code nor invariant enforces that order)?
- If YES → a successful PoC is real-world reachable; verdict survives. If NO → state which guard or invariant DOES enforce the order.
- kills_hypothesis: YES / NO

### Q4 — Expected-order survival
- If you assume the developer's expected order (the order the docs / comments / function naming imply), does the attack still work?
- If YES → finding is order-independent and survives expected-order analysis.
- If NO → the attack only fires under unexpected-order conditions; this is a sequence-violation finding, NOT a generic class — record this in the verdict notes.
- kills_hypothesis: YES / NO

### Q5 — Test-suite false comfort (v1.7-PATCH8)
- (a) Does the test suite exercise this finding's specific failing path? Cite the test file:test_function or `none`.
- (b) If a test exists, does the test's `setUp()` or pre-conditions enforce a stricter sequence / state machine than production code enforces? (Example: test calls `initialize()` before `deposit()`, but production allows `deposit()` to be called pre-initialize.)
- (c) If a test exists, do its assertions validate POST-STATE (storage variables, mappings, accounting fields) or only EVENT EMISSION / RETURN VALUE / "does not revert"?
- Output `tests_imply_safety:` one of:
    - `NO_TESTS` — no test exercises this path; tests carry zero evidence weight either way
    - `NO` — tests exist but encode strict-setup / loose-production divergence; tests passing is NOT evidence of production safety
    - `PARTIAL` — tests exist with event-only or return-only assertions; tests don't validate state correctness
    - `YES` — tests exercise the path, assert post-state, and the test setup matches production's reachable preconditions
- kills_hypothesis: NO  *(Q5 never kills a hypothesis — it only contextualizes "tests pass" as evidence weight)*
```

**Interpretation**:

- If ANY of Q1 / Q2 has `kills_hypothesis: YES` with a concrete guard / unreachability proof at file:line → the verifier MAY skip the PoC and emit verdict `[POC-FAIL: GENUINE]` with evidence tag `[CODE-TRACE]` + cite the killing argument inline. The Cleared-Proof Discipline (`~/.valves/rules/cleared-proof-discipline.md`) applies — the killing argument MUST carry the full four proof fields (file:line + guard/invariant + reason + Proof Type). A vague "looks safe" is NOT a valid kill.
- If Q3 is `YES` (attack depends on unenforced order) AND Q4 is `NO` (does not survive expected order) → finding is a SEQUENCE-VIOLATION class. The verdict notes MUST cite `class: sequence-violation` and the PoC tests the unexpected-order variant. This sharpens the framing without weakening the finding.
- If Q3 is `YES` AND Q4 is `YES` → finding is order-independent. Proceed with the standard PoC.
- **Q5 is asymmetric** (v1.7-PATCH8): it can never KILL a hypothesis, only weaken or strengthen "tests pass" as evidence. When `tests_imply_safety: NO` (strict-setup / loose-production divergence) and Q1/Q2 don't kill → the verifier MUST NOT cite "tests pass" as evidence the path is safe. When `tests_imply_safety: NO_TESTS` and Q1/Q2 don't kill → the path is UNDER-TESTED; the verifier's PoC carries the only evidence weight. When `tests_imply_safety: YES` AND Q1/Q2 do not kill → tests provide weak corroboration but the verifier's PoC remains the primary evidence.
- If all five are non-killing → proceed to PoC with the normal flow (§ Execution Protocol below). The pre-check is recorded in `verify_{id}.md` but did not eliminate the hypothesis.

This pre-check is NOT a replacement for Skeptic-Judge (§ Skeptic-Judge below) — Skeptic-Judge runs AFTER the verifier on HIGH/CRIT findings. The pre-check runs on EVERY finding (all severities) and is mechanically structured. The two layers compose: the pre-check biases the verifier toward honest refutation; Skeptic-Judge re-pressures HIGH/CRIT after the verifier's verdict.

**Why this is precision-positive (does not reduce recall)**:
- Q1/Q2 only kill the hypothesis when a concrete guard / unreachability is named at file:line; vague clears are blocked by Cleared-Proof Discipline.
- Q3/Q4 do NOT kill the hypothesis — they re-classify a generic finding as a sequence-violation finding. The hypothesis survives; only its framing sharpens.
- Recording the pre-check in `verify_{id}.md` lets Skeptic-Judge / Cross-Batch Consistency / Phase 6d.5 sanity check inspect the killing argument and challenge it.

## Verdict vocabulary

| Verdict | Meaning |
|---|---|
| `[POC-PASS]` | The PoC executed successfully and demonstrates the exploit |
| `[POC-PASS:BC-NNN-INHERITED]` | This instance inherits the cluster representative's [POC-PASS] (no per-instance run) |
| `[POC-FAIL: GENUINE]` | The PoC ran but the exploit did NOT succeed; finding is REFUTED on its merits |
| `[POC-FAIL: SETUP_ERROR]` | The PoC ran but a harness/setup defect (not the protocol) caused failure — try one variant |
| `[CODE-TRACE]` | Light/code-trace verification only (no executable PoC); used for Low/Info in Light mode |
| `CONTESTED` | The PoC produced ambiguous output; depth re-investigation needed (AD-6) |

## § GENUINE vs SETUP_ERROR classification

`[POC-FAIL]` is classified GENUINE only when:
1. The harness compiled and the test ran to completion.
2. The exploit step of the PoC executed (not a setup transaction that reverted).
3. The expected post-state did NOT manifest, AND
4. The expected revert/event/balance change is missing for a *protocol* reason (a guard, a modifier, an invariant), not a harness reason (wrong account, wrong calldata encoding).

If unsure → mark SETUP_ERROR and exhaust ONE variant before classifying GENUINE. Variants explored:
- Reorder setup transactions.
- Adjust block timestamp / number.
- Change actor address (cap at 3 fresh actors).
- Disable mocked dependencies (use the real protocol address on a fork).

If after one variant SETUP_ERROR persists, escalate to CONTESTED (depth re-investigation queued for AD-6 or skipped to next batch).

GENUINE [POC-FAIL] verdicts are appended to `audit_negative_results.md` per `~/.valves/rules/negative-results.md`.

## § PROVEN_ONLY mode

When `PROVEN_ONLY=true`:
- `[CODE-TRACE]`-only findings are capped at Low severity in the report regardless of the original severity.
- `[POC-PASS]`, `[POC-PASS:BC-NNN-INHERITED]`, and verifiable fuzz counterexamples are unchanged.
- `[POC-FAIL: GENUINE]` is unchanged (already a refutation).
- `[EI-THEORY]` (economic) is downgraded one tier (Medium → Low; was already capped at Medium per economic-incentive-audit.md).

This mode is used for benchmark comparisons where the audit must publish only what it can prove on a harness.

## § Cluster Inheritance application

When a cluster representative returns `[POC-PASS]`:
1. Read inheritance conditions from `~/.valves/rules/verification-priority-queue.md` § Cluster Inheritance.
2. For each non-representative instance where conditions hold, tag `[POC-PASS:BC-NNN-INHERITED]` in `findings_inventory.md`.
3. Skip per-instance verifier spawn for those tagged instances. Other instances (failing inheritance) are spawned separately.
4. Record the inheritance map in `{scratchpad}/verification_inheritance.md`:

```markdown
| Cluster | Representative | Verdict | Inheriting instances | Skipped spawns | Independent verifications |
|---|---|---|---|---|---|
| BC-014 | F-12 | [POC-PASS] | F-44, F-67 | 2 | F-89 (different access ctrl) |
```

Failures (`[POC-FAIL]`, `CONTESTED`) do NOT inherit. Each instance verified independently.

## § Verifier output

Two outputs per verifier:
1. **On disk (full)**: `{scratchpad}/verify_{id}.md` — header (`## Scope:`, `### H-XX`), full PoC code, run output, post-state, evidence tag, ## New Observations section for `[VER-NEW-*]`.
2. **Return message (short)**: `{HYPOTHESIS_ID}: {VERDICT} | {evidence_tag} | {1-sentence justification}`.

The return message must NOT include the PoC body, run logs, or full reasoning. Those live on disk and the orchestrator reads them at Phase 5.5/6 only.

## § Skeptic-Judge (Phase 5.1, Thorough HIGH/CRIT only)

After every standard Phase 5 verifier completes, every HIGH/CRIT finding gets a skeptic agent (sonnet) with INVERSION MANDATE:
> "Your job is to prove this is NOT exploitable. Construct the most plausible refutation harness. Pass any guard you can find. Cite specific lines."

If the skeptic AGREES with the standard verdict → final verdict = standard verdict (high confidence).

If the skeptic DISAGREES → spawn a haiku judge with the rule "prove it or lose it":
- The judge weighs both PoCs by mechanical evidence (does the test compile? does it run? does the post-state match what the PoC claimed?).
- Stronger mechanical evidence wins.
- Tie → the finding is marked CONTESTED.

## § Phase 5.5 New Observations

After all verifiers complete, the orchestrator scans verify files for `[VER-NEW-*]` observations in their `## New Observations` sections. Any not covered by an existing hypothesis is added to `hypotheses.md` with severity from the standard matrix. These do NOT require re-verification — the discovery happened during a passing/failing PoC, the observation has its own evidence.
