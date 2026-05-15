<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Symmetric Pairs

Source-of-truth for the **Symmetric-Pairs Binding Table** produced by Propagation P1 Agent (Phase 4a.5.c, Task 2). Output: `{scratchpad}/symmetric_pairs.md`.

## Purpose

Many bugs arise where one half of a sibling pair (deposit/withdraw, stake/unstake, lock/unlock, claim/emergency-claim, normal-path/skipped-path) does something the other half does not, in a way that lets an actor exploit the asymmetry. This rule defines the seven aspects to enumerate per pair and the conditions under which an asymmetry counts as `ASYMMETRY_FLAG` — a mandatory depth target.

## § Sibling pair categories (enumerate all that exist in the codebase)

- **deposit / withdraw** — the canonical fund-flow pair.
- **single-sided / two-sided** — paths that operate on one token vs both legs of a pair.
- **normal / skipped** — full-execution paths vs paths with a fast-exit (e.g., emergency, no-rewards, no-events).
- **paused-gated / ungated** — functions guarded by a pause flag vs sibling functions that are not.
- **stake / unstake** — locking and releasing.
- **claim / emergency-claim** — designed reward path vs emergency exit.
- **lock / unlock**, **add / remove**, **create / destroy**, **open / close**, **enter / exit** — generic pair patterns.
- **update-path-A / update-path-B** — two functions that reach the same state through different update paths.

## § Seven aspects to enumerate per pair

For each pair (A, B):

| Aspect | What to record |
|---|---|
| **1. Guards** | Modifiers, `require()` checks, role/role-check at entry. List separately for A and B. |
| **2. Validation** | Input validation: zero-address checks, bounds, format. Per side. |
| **3. State writes** | Storage variables modified by the function. Per side. |
| **4. External calls** | Calls to external contracts (token transfers, oracle reads, hooks). Per side. |
| **5. Accounting** | Internal accounting math: balance updates, share math, reward accrual. Per side. |
| **6. Fee routing** | Where fees go, how they're computed, whether they're charged on this side. |
| **7. Events** | Which events are emitted, with which fields. Per side. |

## § Output schema (`symmetric_pairs.md`)

```markdown
# Symmetric Pairs Binding Table

## P-{N} — {pair name, e.g., "deposit / withdraw in Vault.sol"}

| Aspect | A: {function A name} | B: {function B name} | Match? | Asymmetry note |
|---|---|---|---|---|
| Guards | {list} | {list} | YES / NO | {only when NO} |
| Validation | {list} | {list} | YES / NO | {only when NO} |
| State writes | {list} | {list} | YES / NO | {only when NO} |
| External calls | {list} | {list} | YES / NO | {only when NO — and explain whether direction-justified} |
| Accounting | {list} | {list} | YES / NO | {only when NO} |
| Fee routing | {list} | {list} | YES / NO | {only when NO} |
| Events | {list} | {list} | YES / NO | {only when NO} |

ASYMMETRY_FLAG: {YES if any aspect differs in a NON-direction-justified way / NO}
Severity hint: {if YES — Critical/High/Medium based on which aspect}
Mandatory depth domain: {token_flow / state_trace / edge_case / external}

### ...next pair
```

## § Direction-justified asymmetries (NOT flagged)

Some asymmetry is intrinsic to the operation:
- deposit pulls tokens via `transferFrom`; withdraw sends via `transfer` — the External Calls list MUST differ.
- deposit increases balance; withdraw decreases — the Accounting list MUST differ in sign.
- create emits a Created event; destroy emits a Destroyed event — Events MUST differ.

These are **direction-justified**. Mark `Match? = N/A (directional)` and do NOT raise `ASYMMETRY_FLAG`.

## § What IS flagged

`ASYMMETRY_FLAG: YES` when the asymmetry is NOT direction-justified. Examples:
- deposit checks `whenNotPaused` modifier; withdraw does NOT.
- deposit validates `require(asset != address(0))`; withdraw does NOT.
- deposit emits `Deposit(user, amount, shares)`; withdraw emits only `Withdraw(user)` without amount/shares.
- claim updates `lastRewardTime`; emergency-claim does NOT (stale lastRewardTime → next claim mis-attributes).
- stake calls `_updateRewards(user)`; unstake does NOT.

For each flagged pair, the depth agent in Phase 4b iter 1 MUST investigate. The flag is a mandatory target — silent drops are forbidden.

## § Hard rule (Propagation P1)

Every `ASYMMETRY_FLAG: YES` row is a mandatory depth target. If the depth agent in iter 1 does not return either a finding or a `CLEARED(depth)` with a specific reason, the pair is escalated as a structural-coverage gap and re-investigated in iter 2 (Thorough) or carried as a residual-risk note (Core).

This means: there is no path where a non-direction-justified asymmetry is silently dropped. Either it produces a finding, or the depth agent commits to a refutation argument that depth iter 2 / verification can later test.
