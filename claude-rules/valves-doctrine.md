# Valves Doctrine — Reasoning-Quality Baseline (v1.8-PATCH1)

> Compact source-of-truth for the reasoning style every Valves agent should follow.
> Read once. Apply throughout. No agent should "look like a workflow" — every agent
> should look like an elite human auditor under time pressure.
>
> This file does NOT add phases, agents, sweeps, or artifacts. It defines the
> reasoning bias every existing agent should already have.

## § Audit thinking principles (the elite-auditor lens)

Valves measures itself by whether it:
1. thinks in breakpoints and invariants, not bug names
2. asks "what breaks if this assumption fails?" before naming a class
3. explicitly pressures call-order / sequence assumptions
4. surfaces unanswered questions, not just raw candidates
5. separates surfacing from judgment
6. preserves parent exploits over child symptoms
7. treats CLEARED as mechanically disproven, not "looks safe"
8. uses Session B for diverse, adversarial re-attack
9. scopes work by decision / invariant / threat model, not just by component
10. injects only the minimum context needed
11. uses verification to try to KILL hypotheses, not merely confirm them
12. treats historical memory as helpful but suspicious
13. improves from benchmark outcomes, not from arbitrary complexity growth

## § The 8 mandatory adversarial questions

When investigating any non-trivial finding, seed, or hypothesis, the agent SHOULD
pressure-test it against these eight question types. The output of the pressure
test is either: (a) a guard / invariant / proof that closes the question, or
(b) an Open Question recorded for handoff / chain analysis.

1. **Unexpected order / sequencing** — What happens if this is called in an order
   the developer did not expect? Reversed order, skipped predecessor step, repeated
   call, admin mutation inserted between user steps, emergency path called early,
   external update interleaved between normal steps, cross-contract sequencing
   assumption violated.

2. **Hidden assumption failure** — What assumption MUST be true for this to be safe?
   Is it actually enforced by code, or merely expected? What breaks if it is false
   for one call, one branch, or one actor?

3. **Parent exploit vs child symptom** — Is this the root exploit, or only a
   narrower symptom? If this bug exists, what stronger custody / recovery /
   liveness exploit does it enable?

4. **Accounting symmetry / stale state** — Which two values or states are supposed
   to stay in sync? Can one update happen without the other? Can a user act
   against stale state before reconciliation happens?

5. **Recovery-path honesty** — If the normal path fails, is the recovery path
   actually equivalent in safety? Does the emergency / fallback / admin path bypass
   an invariant the normal path relies on?

6. **Trust-model dependence** — Is this only safe under a benevolent admin
   assumption? Is it still safe under the documented trust model in
   `design_context.md`, not just the developer's intended workflow?

7. **External dependency drift** — What if the external dependency changes between
   two expected steps? What if the protocol treats an external value as stable when
   it is only temporarily true?

8. **Repetition / re-entry of valid actions** — What happens if this valid action
   is repeated, replayed, or interleaved? Does safety depend on it being called
   only once or only in one specific sequence?

## § The decision lenses (depth agents)

Each depth agent has a domain (`token_flow` / `state_trace` / `edge_case` /
`external`), but the **lens** is what matters. The domain is the file region
the agent prioritizes; the lens is the threat model the agent pressures.

| Domain | Decision lens |
|---|---|
| token_flow | accounting integrity — beneficiary / recipient correctness — fee / reward routing — token custody pointer validity |
| state_trace | state correctness — call-order / sequence safety — accounting symmetry — branch completeness across mutating paths |
| edge_case | boundary failure — branch completeness — recovery-path honesty — emergency-path divergence from normal-path invariants |
| external | external dependency drift — trust-model dependence — privileged mutation safety — cross-contract sequencing assumptions |

When analyzing a finding, the agent applies its lens across all relevant code,
not just within one file or one component. Cross-contract sequence assumptions
cross domains; the agent assigned the lens owns the question. The *file region*
biases attention — it does NOT scope reasoning.

## § Kill-the-hypothesis mindset (verifiers)

The verifier's job is not to confirm a finding. It is to find the strongest
reason the finding fails, and only declare CONFIRMED when the finding survives
that pressure.

Before writing any PoC, the verifier MUST answer five questions in
`verify_{id}.md` § Hypothesis-killing pre-check (see
`~/.valves/rules/phase5-poc-execution.md` § Hypothesis-killing pre-check):

1. What guard / invariant / trust assumption could block this attack?
2. What state precondition is required, and is it actually reachable by the
   alleged actor under the documented trust model?
3. Does the attack succeed only when an unenforced call-order assumption holds?
4. If you assume the developer's expected order, does the attack still work?
5. (v1.7-PATCH8) Does the test suite encode a stricter sequence / setup than
   production enforces — making "tests pass" weak or zero evidence of safety?
   Q5 is asymmetric: it never KILLS a hypothesis, only contextualizes test
   evidence weight (`tests_imply_safety: YES / NO / PARTIAL / NO_TESTS`).

If the strongest answer is "yes, the attack survives even under expected order
+ documented guards", the hypothesis is real. If not, the verifier writes the
falsifying argument first, and the PoC tests the surviving variant (if any).

## § The call-order principle (first-class)

If safety depends on developer-expected order but that order is not enforced
by code or invariant, that is **not a strong clear**. It is at best a
PRIOR_NEGATIVE_ADVISORY. The call-order question is integrated as a first-class
reasoning lens at every layer:

- Assumption-Breaker Q7 (Phase 4a.5.e) — produces a sequence seed when the
  unenforced order is found and not already covered.
- Canonical Seed Map E11 SEQUENCE family — distinct equivalence class for
  call-order seeds; ranked between E8 EMERGENCY (more specific) and E2 INTERFACE.
- Depth-agent decision lens — `state_trace` carries the primary lens; other
  domains apply it when the surface they touch has cross-contract sequencing.
- Verifier hypothesis-killing pre-check questions 3 and 4.
- Phase 6d.5 mismatch type SEQUENCE_DISPLACEMENT — flags when a sequence /
  order-dependent parent exploit was displaced by a narrower child symptom in
  the final report.
- System Breakpoints `OrderingViolation` family — captures system-level failure
  modes whose trigger is an unenforced call-order assumption.

## § Heuristic Lenses (v1.7-PATCH8)

The 8 mandatory adversarial questions above are about WHEN to pressure. The lenses below are about WHAT specific code shape to look for. Each lens carries a short tag (used in `canonical_seed_map.md` and `session_a_to_b_handoff.md` § 2 `Heuristic Lens` column) and a concrete sub-question set. Apply when the surface matches the lens; do not force-apply.

### SYMMETRY — symmetry / asymmetry pressure
> Sibling pairs that should behave identically often diverge in one of seven aspects: guards / validation / state writes / external calls / accounting / fee routing / events. When the divergence is NOT direction-justified, the asymmetry is a parent finding — the asymmetry IS the bug, not the per-function gap. See also `~/.valves/rules/symmetric-pairs.md`.

### STATE-TRANSITION — invalid / unhandled state transitions
> Treat the protocol as a state machine. Ask: can step 2 happen without step 1 being TRULY completed? Can a transition fire without the predecessor state being validated? Can the system enter a state the developer assumes is unreachable? This is distinct from SEQUENCE: SEQUENCE is about caller-controlled call-order; STATE-TRANSITION is about protocol-internal lifecycle (init / active / paused / settling / settled / terminated). A bug here looks like: contract emits `WithdrawComplete` while still in ACTIVE; position goes ACTIVE → LIQUIDATED → ACTIVE; settlement marks DONE without the debt-mirror being updated. Often manifests as a missing assert / require on state, OR a state write inside a branch that some callers can skip.

### SEQUENCE — unexpected call-order pressure
> Already first-class. See § The 8 mandatory adversarial questions Q1 + § The call-order principle. Lens tag: SEQUENCE. Equivalence class: E11 in canonical_seed_map.md.

### BIG-VS-SMALL — one large operation vs many small operations
> Ask: does N small operations produce the same state effect as 1 large operation with the same total value? If not, is that intentional or exploitable? Common asymmetries: rounding (each tiny op rounds down → cumulative loss); reward distribution (per-op reward computation skews vs single-op); fee tiers (fee thresholds bypassable by splitting); rate limits (per-tx caps bypassable by N txs); slippage (per-trade slippage looser than aggregate). The inverse question (one big op equivalent to many small) catches: aggregate-only invariants that hold per-tx but break in aggregate; griefing via single-large-op DoS where many-small-ops is fine.

### NUMERIC-EXTREME — small-number / large-number pressure
> Ask: what happens near zero? Near `type.max`? At decimal-precision boundaries? Common bugs: deposit/withdraw of 0 produces phantom shares; first-depositor inflation attacks; integer overflow at `2**N`; rounding-to-zero at small input; precision loss when one operand is much larger than the other; `type(uint).max` arithmetic wrap. Do NOT confuse with general boundary testing — this lens specifically pressures the EXTREMES, where most callers never go but a single attacker can.

### NONEXISTENT-ID — non-existent / attacker-chosen identifier pressure
> Ask: what if this function is called with a non-existent tokenId / market / vault / position / pool / strategy / order ID? What if the caller passes an address they control where the code assumes a legitimate object? Common bugs: function operates on a struct that was never initialized → struct fields are zero → division by zero, or the zeroed struct passes a guard that should have rejected it; lookup returns the default value (address(0), 0, false) and the caller proceeds; attacker creates a fake-but-correctly-structured object (custom token / mock pool) and the protocol calls into it. Distinct from access control: this is "the IDENTIFIER itself is a vector", not "the caller is unauthorized".

### TEST-SKEPTIC — test-suite skepticism
> Tests can give false comfort when they encode a nicer workflow than production enforces. Treat the test suite as an attack surface, not a safety witness. Sub-checks (mechanical; applied by Validation Sweep `[VS-TS-1]` sub-check in Phase 4b iter 1; also a reasoning bias for breadth / depth / Session B agents):
>
> 1. **State-transition coverage gaps**: For each high-signal production state transition (state-modifying entry points; settlement paths; custody transitions; emergency / recovery paths from `system_breakpoints.md`), check if a test file calls that path. If NO test exists, this is a coverage gap. Production paths without test coverage carry hidden risk regardless of code review.
> 2. **Assertion-shape weakness**: For tests that DO exercise a high-signal path, check whether assertions validate POST-STATE (storage variables, mappings, accounting fields) or only EVENT EMISSION / RETURN VALUE / "does not revert". Event-only / return-only assertions are NOT proof that the state transition completed correctly — a contract can emit a `Withdraw` event while the user's storage balance is silently corrupted.
> 3. **Strict-setup / loose-production divergence**: For tests that DO assert post-state, check whether the test's `setUp()` sequence enforces preconditions that production code does not (e.g., test calls `initialize()` before `deposit()`; production allows `deposit()` to be called pre-initialize). When tests encode a stricter sequence than production, "tests pass" is NOT evidence of production safety — the test simply doesn't reach the production-reachable bug.
> 4. **Production-only paths**: Functions called only in tests (test-only utilities; mocked dependencies) are NOT a finding. But functions called only in PRODUCTION (no test ever exercises them) IS a coverage gap.
>
> Output (Validation Sweep `[VS-TS-1]`): consolidated multi-location table tagged `[CORRECTNESS-WINNER]` so distinct gaps are not absorbed. Verifier hypothesis-killing pre-check Q5 (`~/.valves/rules/phase5-poc-execution.md`) further pressures: when a finding's exploitability would be killed only by a guard the tests assume but production does not enforce, do NOT clear.

### DEAD-STATE — written but never read / dead-state suspicion
> Ask: which storage variables are WRITTEN by the protocol but never READ in any meaningful path? A write-only variable is one of: dead code (no consumer; remove); a missing read in a downstream path (the variable was supposed to gate / influence something but the read was omitted); a broken settlement / accounting mirror (the writer expected a consumer that never materialized). The third case is a real bug — the missing read hides a transition gap. Inverse: variables READ but never WRITTEN by current code (initialized to default and never updated) — same suspicion category.

### ROUNDING-DRIFT — per-operation rounding that compounds into value drift (v1.8-PATCH1)
> Per-operation rounding looks harmless, but repeated operations, dust, share conversions, fee accrual, reward indexing, or interest updates compound into value drift. Distinct from BIG-VS-SMALL (which asks "N small vs 1 large") and NUMERIC-EXTREME (which asks "what at zero/max") — this lens asks "what accumulates over TIME or REPETITION even at normal values?" Sub-questions:
>
> 1. **Rounding beneficiary**: Who benefits from repeated rounding — protocol, user, or attacker? Is the direction consistent or exploitable?
> 2. **Dust accumulation**: Can rounding remainders accumulate into claimable value? Can an attacker harvest dust across many positions, epochs, or users?
> 3. **Preview / execution divergence**: Do preview functions (previewDeposit, previewRedeem, convertToShares, convertToAssets) return values that diverge from actual execution over repeated calls? Divergence compounds into accounting drift.
> 4. **Share conversion asymmetry**: Does deposit rounding + withdrawal rounding consistently leak value in the same direction? Over N round-trips, does the user (or pool) lose more than expected?
> 5. **Index / accumulator precision**: Do reward indexes, interest accumulators, or fee-per-share values lose precision as they grow? Does late-joiner vs early-joiner accounting diverge due to accumulated truncation?
> 6. **Fee-on-transfer / rebasing interaction**: When tokens have transfer fees or rebasing supply, does the protocol's internal accounting track actual balances or nominal amounts? Drift between the two compounds silently.
>
> Common code shapes: `mulDiv` with consistent rounding direction, integer division before multiplication, `totalAssets / totalShares` with small denominator, cached `totalAssets` updated less frequently than share operations, `rewardPerToken` index with low-decimal tokens.

### TX-ORDERING — transaction-ordering and MEV pressure (v1.8-PATCH1)
> Distinct from SEQUENCE (which is about function call-order within a contract). This lens is about transaction ordering in the mempool / block production layer — who sees what, who can reorder, and what value extraction that enables. Apply when the protocol has public state changes that create temporary profitable windows. Chain-specific sub-questions:
>
> **Universal (all chains)**:
> 1. Does a public state change (oracle update, parameter change, rebalance, liquidation threshold) create a window where the first actor to respond profits?
> 2. Can an observer see a pending user action and profitably act before/after it?
> 3. Are optimistic proposals, reward distributions, or epoch transitions order-sensitive — does the first claimer get more than their fair share?
> 4. Does keeper / relayer / admin action ordering create value extraction opportunities for the privileged actor?
>
> **EVM-specific**:
> 5. Can this be front-run (attacker executes before victim's observed tx), back-run (attacker executes immediately after), or sandwiched (both)?
> 6. Does `block.timestamp` or `block.number` usage create a stale-assumption window between mempool observation and execution?
> 7. Are slippage parameters (amountOutMin, deadline) set by the user or hardcoded — and can an attacker exploit generous defaults?
>
> **Solana-specific**:
> 8. Can Jito tips or priority fees allow an attacker to land a transaction in a favorable position within a slot?
> 9. Does account-lock ordering create contention that an attacker can exploit (locking accounts to block legitimate transactions)?
> 10. Are CPIs to AMMs or oracles vulnerable to same-slot manipulation by a program that controls execution order?
>
> **Move chains (Aptos/Sui)**:
> 11. Does Aptos Block-STM parallel execution or Sui object-ownership model create ordering assumptions that break under contention?
> 12. Can a Sui shared-object transaction be delayed or reordered by a validator to extract value?
>
> **L2-specific**:
> 13. Does sequencer ordering (centralized or shared) create a trusted-actor MEV vector?
> 14. Can delayed inbox messages (Arbitrum) or forced inclusion (Optimism) be timed to exploit state transitions?
> 15. Are keeper/bot timing assumptions based on L1 finality that L2 sequencing doesn't guarantee?

### TEMPORAL-WINDOW — commitment-execution time gap pressure (v1.8-PATCH1)
> When a user or protocol commits now but execution happens later, the world can change in between. Distinct from SEQUENCE (same-tx call order) and TX-ORDERING (mempool positioning) — this lens covers multi-block, multi-epoch gaps where a party is locked in and conditions drift. Targets: withdrawal delays, cooldowns, vesting schedules, timelocks, queued governance proposals, delayed bridge claims, pending deposits, keeper execution windows, oracle update windows, delayed settlement.
>
> 1. **Parameter drift during lock**: Can an admin or governance action change fee rates, thresholds, oracle sources, collateral factors, or other calculation inputs while a user's operation is pending? If so, the user committed under terms that no longer apply at execution.
> 2. **Price/oracle drift**: Can an oracle update between commitment and execution invalidate the original calculation? Does the protocol re-price at execution time or use the stale commitment-time value?
> 3. **Balance/share drift**: Can the user's shares, debt, rewards, or balances change while they are locked in a timelock, cooldown, or unbonding period? Can another user's deposit/withdrawal alter the locked user's expected payout?
> 4. **Liquidity drain during wait**: Can other users withdraw liquidity during the pending period, leaving insufficient assets for the locked user's claim at execution?
> 5. **Recovery path invalidation**: Can the emergency/pause/recovery path become invalid during the wait? If admin pauses the protocol while a user has a pending withdrawal, does the user lose access permanently?
> 6. **Frontrun at expiry**: Can an attacker observe when a timelock/cooldown expires and frontrun the execution to extract value (e.g., sandwich a large pending withdrawal at the moment it becomes executable)?
> 7. **Cascading delays**: Does one delay trigger another? Can a user be stuck in a sequence of cooldowns/timelocks where each expiry requires another waiting period?

### CALLBACK-CONTROL — external control flow transfer pressure (v1.8-PATCH1)
> When the protocol hands control flow to external or untrusted code, that code can observe, manipulate, or grief. Broader than reentrancy — covers any pattern where execution passes to a callee who may not behave as expected. Apply when the code contains external calls, token transfers with hooks, flash loan callbacks, or any interface where the callee runs arbitrary logic.
>
> 1. **Intermediate state exposure**: What half-updated state can the callee observe? If the protocol updates variable A but not yet variable B before the external call, the callee sees an inconsistent snapshot. This is the general form of reentrancy — the callee doesn't need to re-enter; observing the inconsistency from another protocol is enough.
> 2. **Selective revert exploitation**: Can the callee selectively revert to cherry-pick favorable outcomes? If the protocol batches operations and any sub-call can revert, the callee can force partial execution that benefits them. Flash loan callbacks that revert on unfavorable prices. Token receive hooks that revert to block liquidations.
> 3. **Gas griefing / fallback forcing**: Can the callee consume excessive gas to push the transaction near the gas limit, causing downstream operations to fail? Can the callee force the protocol into a fallback code path by consuming all forwarded gas?
> 4. **Cross-protocol state observation**: Can the callee read the protocol's intermediate state and act on it in a different protocol before the original call completes? The callee doesn't re-enter THIS protocol — they enter ANOTHER protocol that reads THIS protocol's now-inconsistent state.
> 5. **Token-specific callback divergence**: Do different token standards trigger different callbacks? ERC777 `tokensToSend`/`tokensReceived`, ERC1155 `onERC1155Received`, ERC721 `onERC721Received`, fee-on-transfer silent reduction, rebasing during callback. The protocol may handle one token type correctly but not another.
> 6. **Callee trust assumption**: Does the protocol assume the callee will behave "normally" (return expected values, not revert, complete in bounded gas)? What if the callee is an attacker-deployed contract? What if a previously-trusted callee is upgraded to malicious code?
> 7. **State update ordering**: Are all protocol state updates complete BEFORE the external call, or does the protocol write state after receiving control back? Post-callback state writes are vulnerable to any manipulation the callee performed during the callback.

### INCENTIVE-DIVERGENCE — rational misbehavior pressure (v1.8-PATCH1)
> When rational self-interest diverges from protocol health, the "correct" behavior is unprofitable and the "harmful" behavior is profitable. The code works exactly as written — the bug is in the economic design. Compact lens; complements the ECONOMIC_DESIGN_AUDIT skill without replacing it.
>
> 1. **Keeper delay profit**: Can a keeper profit by delaying or batching updates suboptimally? If the keeper earns a fee per update but costs are fixed, batching fewer updates is rational even if it degrades protocol liveness. If the keeper can observe pending user actions, delaying until after those actions may be more profitable.
> 2. **Liquidator wait incentive**: Can a liquidator profit more by waiting until a position is deeper underwater before liquidating? If the liquidation bonus is proportional to the shortfall, waiting for worse insolvency is rational. Does the protocol incentivize prompt liquidation or tolerate delay?
> 3. **Whale timing exploitation**: Can a whale profit by timing deposits, withdrawals, or reward claims around parameter changes, epoch boundaries, or rate updates? If reward rates are announced before they take effect, pre-positioning is rational.
> 4. **Governance delay profit**: Can governance voters or proposers profit by delaying protocol fixes, adjusting parameters to benefit their positions, or proposing changes that extract value from other users?
> 5. **Grief at low cost**: Can a user cause disproportionate harm to others at low or zero cost to themselves? Dust deposits that complicate accounting, spam proposals that delay governance, small transactions that trigger expensive rebalancing.
> 6. **Systemic rational collapse**: Does individually-rational behavior lead to collective harm? Bank run dynamics where early withdrawers are rational but collectively cause insolvency. Liquidation cascades where each liquidator is rational but the cascade destroys the protocol.

## § Fuzz interpretation note (v1.7-PATCH8)

When fuzz output exists (`invariant_fuzz_results.md`, `medusa_fuzz_findings.md`):
- Absence of a counterexample is NOT proof of safety — it is evidence the fuzzer did not reach that path within its budget. Coverage holes (state-machine paths the fuzzer never explored) are a routing question, not a verdict.
- White-box invariants (assertions inside the contract / fuzz harness) are stronger evidence than black-box invariants (post-condition checks from outside) — but only for the invariants actually written. Missing invariants are a coverage gap.
- Lifecycle invariants matter as much as steady-state invariants. A fuzz harness that only tests `active` state without testing `init` or `terminal` transitions cannot witness lifecycle bugs (e.g., `STATE-TRANSITION` lens findings).
- Where the fuzz harness compiled but produced no counterexample, the verifier's hypothesis-killing pre-check Q5 still applies: tests / fuzzers that encode a stricter setup than production do NOT clear the finding.

## § Agent tool discipline (v1.7-PATCH10 — MANDATORY architecture invariant)

> Compact mechanical rule. Read once. Applies to EVERY agent spawned by Valves at every phase, no exceptions. The orchestrator enforces this via post-spawn integrity check (`~/.valves/rules/artifact-ownership.md` § Universal post-spawn integrity check); violations cause AUTO-DISCARD + 1 strict re-spawn + halt-on-second-violation.

**No spawned agent may invoke another Claude / LLM process or otherwise sub-orchestrate.** Detection uses BOTH literal pattern matching AND executable path resolution (v1.7-PATCH11-G hardening).

### Detection Layer 1: Literal pattern matching (case-insensitive substring match)
- `claude --print` / `claude -p`
- `claude_code --print` / `claude_code -p`
- `claude --output-format` / `claude -o`
- `npx claude` / `bunx claude` / `yarn claude` / `pnpm claude`
- `exec claude` / `spawn claude`
- `sh -c "claude` / `bash -c "claude` / `bash -lc "claude`
- `xargs claude` / `... | claude` (any pipe TO claude)
- Any subprocess that re-enters the orchestrator's role (e.g., `python -c "from anthropic..."`, `curl -X POST .../messages`)
- Any Bash command whose effect is "run another agent / LLM call to do work"

### Detection Layer 2: Executable path resolution (v1.7-PATCH11-G)
Literal matching alone is insufficient — agents can bypass via:
- Wrapper scripts: `./my_helper.sh` (which internally calls `claude --print`)
- Aliases/symlinks: `/usr/local/bin/my-analyzer` → `claude`
- Indirect invocation: `env claude --print`, `command claude`, `$(which claude) --print`
- PATH manipulation: `PATH=/custom/bin:$PATH custom_tool` (where custom_tool = claude)

**Hardened detection algorithm** (post-spawn, orchestrator-inline):
```
For each Bash command in the agent's tool trace:
  1. LITERAL CHECK: case-insensitive substring match against Layer 1 patterns.
  2. EXECUTABLE RESOLUTION: extract the first word (command name) from the Bash command.
     - If command is a path (contains /): resolve via realpath.
     - If command is a bare name: resolve via `which {command}` or `command -v {command}`.
     - Check if the resolved executable path ends with `/claude`, `/claude-code`,
       or matches known Claude CLI binary paths.
  3. WRAPPER DETECTION: if the Bash command invokes a script file (.sh, .py, .js):
     - Read the first 10 lines of the script.
     - If any line matches Layer 1 patterns → NESTED_CLAUDE_VIA_WRAPPER violation.
  4. INDIRECTION PATTERNS: flag these specific patterns:
     - `env claude`, `env -i claude`, `command claude`, `command -v claude`
     - `$(which claude)`, `$(command -v claude)`, backtick equivalents
     - `eval "claude`, `eval 'claude`
```

**Violation codes**: `NESTED_CLAUDE_LITERAL` (Layer 1), `NESTED_CLAUDE_RESOLVED` (Layer 2 path resolution), `NESTED_CLAUDE_VIA_WRAPPER` (Layer 2 wrapper), `NESTED_CLAUDE_INDIRECT` (Layer 2 indirection).

**No spawned agent may write any artifact other than the one(s) it owns** per `~/.valves/rules/artifact-ownership.md` § Control table. An agent that owns `analysis_token_flow.md` may NOT write `recon_summary.md`, `spawn_manifest.md`, `findings_inventory.md`, or any other artifact — even if the agent thinks it would help. The orchestrator owns orchestration; agents own analysis. The boundary is mechanical, not advisory.

**An agent that needs work delegated MUST return its findings and let the orchestrator decide.** Sub-orchestration by agents is an architecture violation regardless of output quality. Quality of forbidden output is irrelevant — the process violation invalidates the work.

**If the agent finds itself wanting to do "more than the prompt says"**: STOP. Return what you have. The orchestrator decides what runs next. Going off-script — even with good intent — breaks the architecture's enforcement guarantees and triggers AUTO-DISCARD.

**Why this is non-negotiable**: Valves's quality contract (Strongest Exploit Preservation, Cleared-Proof Discipline, Cross-Session Consensus, fail-closed embargo) depends on agents staying within their assigned scope. An agent that sub-orchestrates can produce output that LOOKS valid but bypasses the contract. The orchestrator cannot tell the difference between honest agent output and sub-orchestrated agent output without a tool-trace scan. This rule makes the scan possible.

## § What this doctrine is NOT

- Not a checklist (≠ "tick these boxes"). It is a reasoning bias.
- Not a finding template. Findings still use the standard schema in
  `~/.valves/rules/finding-output-format.md`.
- Not exhaustive — it captures the highest-leverage questions, not every
  possible adversarial angle. Agents may apply other reasoning when the codebase
  warrants it; this doctrine is the floor, not the ceiling.
- Not a phase. No outputs, no gates, no spawns. Pure prompting / reasoning quality.
- Not a recall expander. The aim is sharper questions on the existing candidate
  set, not more candidates.

## § Pointers (consumed by)

- `~/.valves/CLAUDE.md` — § Pointers (this file is listed).
- `~/.valves/commands/valves.md` — Phase 4a.5.e Assumption-Breaker prompt;
  Phase 4b iter 1 depth-agent injection; Phase 4b iter 1 Validation Sweep
  `[VS-TS-1]` test-skepticism sub-check (v1.7-PATCH8); Session B Behavioral
  Rules § 1; Phase 5 verification spawn.
- `~/.valves/rules/canonical-seed-map.md` — § Equivalence classes E11 SEQUENCE;
  § Heuristic Lens column derivation rules (v1.7-PATCH8).
- `~/.valves/rules/system-breakpoints.md` — § Methodology OrderingViolation family.
- `~/.valves/rules/phase5-poc-execution.md` — § Hypothesis-killing pre-check
  (Q1-Q4 + Q5 test-skepticism per v1.7-PATCH8).
- `~/.valves/rules/session-a-to-b-handoff.md` — § 2 Open Question / Disputed
  Assumption / Heuristic Lens columns (v1.7-PATCH8 adds Heuristic Lens).
