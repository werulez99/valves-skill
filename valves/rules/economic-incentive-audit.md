<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Economic Incentive Audit

Methodology for the **Economic Incentive Agent** (Phase 4b iter 1, opus; +1 opus iter 2 in Thorough). Models actor incentives and finds extractable value. Output: `{scratchpad}/economic_findings.md`.

## Purpose

Most security audits find code defects. Economic findings are different — the code may be working as written, but the **incentive structure** lets a rational actor extract value or destabilize the system. Examples:
- A reward function that pays an attacker more than it pays an honest user.
- A liquidation cascade that benefits the liquidator at the expense of unrelated depositors.
- A fee schedule that incentivizes wash trading or oracle manipulation.
- A staking mechanism where unbonding incentives misalign with security.

Code-level scanners cannot find these. The Economic Agent reads the protocol's *design* and asks: "Given this code, what does the math say a rational actor will do?"

## Inputs

- `{scratchpad}/design_context.md` (trust roles, monetary parameters, stated incentives)
- `{scratchpad}/attack_surface.md`
- `{scratchpad}/attack_thesis.md` v1
- `{scratchpad}/system_breakpoints.md` (especially Cascade and FirstLossExhaustion families)
- `~/.valves/state/negative_results.md` (so prior cleared paths aren't re-litigated)
- `{scratchpad}/findings_inventory.md` (so far populated)

## Output schema

```markdown
## E-{NN} — {one-line incentive issue}
- Tag: [EI-THEORY] | [EI-TRACE] | [EI-SIM]
- Actors: {attacker, victim — concrete roles, not abstract}
- Profit model:
    - Attacker cost:  {gas + capital + opportunity}
    - Attacker gain:  {extracted value, in same units}
    - Net:            {gain - cost — must be > 0 for the path to exist}
- Preconditions: {state required for the path to be live}
- Path (steps): {each step the attacker takes, with which functions are called}
- Severity (capped): {Critical/High/Medium for [EI-TRACE]/[EI-SIM]; Medium ceiling for [EI-THEORY]}
- Thesis path alignment: P-{N} (if any)
- Breakpoint refs: BP-{NN} (if path culminates at a breakpoint)
- Counterexample / refutation contract: {what evidence would refute this — kept for verifier}
```

## § Tag semantics

- **`[EI-THEORY]`** — argued from the math + design alone. No on-chain trace, no simulation. **Capped at Medium severity** to prevent over-claiming.
- **`[EI-TRACE]`** — backed by a concrete code-path trace through the codebase: function A → function B → state X → outcome Y. No simulation needed; the path is verifiable by reading code.
- **`[EI-SIM]`** — backed by a numerical simulation or fork test showing extractable value > 0 under stated preconditions. Strongest tag.

Verifiers in Phase 5 try to upgrade `[EI-THEORY]` → `[EI-TRACE]` or `[EI-SIM]` when budget allows.

## Iter 2 spawn (Thorough only)

A second Economic Incentive Agent runs in iteration 2 of Phase 4b with iter 1's CONFIRMED findings as additional context. Catches **compound-economic scenarios**: paths that only emerge when two confirmed mechanisms compose (e.g., reentrancy + reward distribution + flash loan).

The iter 2 agent does NOT re-derive iter 1 findings. It looks specifically for compositions among them.

## Methodology checklist (orchestrator hint to the agent)

For each documented incentive in `design_context.md`:
1. State the intended behavior in one sentence (what should the protocol incentivize?).
2. Compute the attacker's net under the most adversarial preconditions allowed by the trust model.
3. If net > 0, write an `[EI-TRACE]` finding (or `[EI-THEORY]` if a clean code path can't be drawn).
4. If a compound path with another finding is plausible, draft an `[EI-THEORY]` and pass it to iter 2.

Standard incentive families to sweep:
- **Reward distribution**: who can extract rewards beyond their stated entitlement?
- **Liquidation cycles**: can a liquidator engineer the conditions of liquidation?
- **Fee asymmetry**: does the fee schedule reward unwanted behavior (wash trading, MEV)?
- **Unbonding / withdrawal queue**: can ordering be gamed by an attacker?
- **Oracle-dependent payouts**: does the system pay before the oracle stabilizes?
- **First-deposit / share-rounding**: classic share-inflation patterns.
- **Token-flow asymmetries**: deposit and withdraw paths that compute the exchange rate differently.

## Severity rules

- `[EI-THEORY]` → Medium ceiling. Even if the path implies catastrophic loss, without a trace or sim it stays at Medium. The verifier upgrades it if it can.
- `[EI-TRACE]` and `[EI-SIM]` → standard severity matrix applies (R10 worst-state).
- PROVEN_ONLY mode: `[EI-THEORY]` becomes Low (downgraded one tier). `[EI-TRACE]` is unchanged. `[EI-SIM]` is unchanged.

## Hand-off to Phase 4c

Every economic finding is fed to chain analysis tagged with its thesis path (when one exists) and breakpoint ref (when the path culminates at a breakpoint). This lets Phase 4c group enablers across code findings + economic findings naturally.
