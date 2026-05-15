# Attacker Objective Matrix (v1.8-PATCH1)

> Used by: breadth agents (framing), depth agents (pressure-test), chain analysis (composition targets).
> Injected via Layer 3 to `{SCRATCHPAD}/_valves_methodology/`.
> This is a reasoning framework, not a checklist. Agents identify which cells are
> relevant to the protocol, not enumerate all 100.

## Purpose

Patterns and lenses ask "what could go wrong in this code?" The objective matrix
asks "what does the attacker WANT?" This inverts the analysis direction: instead
of finding bugs and assessing impact, agents start from concrete attacker goals
and work backward to find enabling paths.

The matrix is a cross-product of attacker objectives × actor capabilities.
For a given protocol, most cells are irrelevant. The agent's job is to identify
which cells are live — which (actor, objective) pairs are reachable — and then
trace backward through the code to find enabling paths.

## Attacker Objectives (rows)

| ID | Objective | What It Means |
|----|-----------|---------------|
| O1 | **Drain protocol funds** | Extract tokens/ETH beyond the attacker's fair entitlement |
| O2 | **Steal or redirect rewards** | Claim rewards earned by others, or redirect reward flow to attacker |
| O3 | **Freeze deposits** | Prevent users from depositing into the protocol |
| O4 | **Freeze withdrawals** | Make user funds temporarily or permanently inaccessible |
| O5 | **Make accounting insolvent** | Create a state where total claims > total assets (implicit or explicit) |
| O6 | **Corrupt share/debt/reward indexes** | Silently drift an accumulator, index, or ratio so future operations are mispriced |
| O7 | **Grief users (no profit)** | Cause loss or inconvenience to others without direct attacker profit |
| O8 | **Block governance** | Prevent proposals from being created, voted on, or executed |
| O9 | **Capture governance** | Seize permanent control of governance process or parameters |
| O10 | **Force bad pricing** | Make the protocol consume a stale, manipulated, or fabricated price |
| O11 | **Break emergency recovery** | Ensure the protocol's fallback/emergency/pause path doesn't work when needed |
| O12 | **Exploit admin/keeper sequencing** | Use the timing or ordering of privileged operations to extract value or cause harm |
| O13 | **Create permanent stuck state** | Put the protocol into a state from which no function can recover — bricked contract, unreachable funds, deadlocked governance |
| O14 | **DoS via malicious external dependency** | Cause denial of service by exploiting an external token, oracle, adapter, or callback that the protocol trusts |

## Actor Capabilities (columns)

| ID | Actor | What They Can Do |
|----|-------|------------------|
| A1 | **Normal user** | Call public functions, deposit/withdraw, interact with UI |
| A2 | **Whale** | Same as A1 but with large capital — can move prices, dominate pools, exhaust limits |
| A3 | **Depositor** | Can time deposits around state changes, epoch boundaries, reward updates |
| A4 | **Withdrawer** | Can time withdrawals to maximize extracted value or grief remaining users |
| A5 | **Borrower** | Can manipulate health factors, open/close positions strategically |
| A6 | **Liquidator** | Can race liquidations, choose which positions to liquidate, delay for profit |
| A7 | **Keeper/relayer** | Semi-trusted: can delay, reorder, batch, or selectively execute maintenance operations |
| A8 | **Proposer** | Can create governance proposals, including malicious or self-serving ones |
| A9 | **Governance voter** | Can vote, delegate, flash-borrow governance tokens, time votes around snapshots |
| A10 | **Malicious token** | Deploys a token with callbacks, rebasing, fee-on-transfer, or custom transfer logic |
| A11 | **Malicious oracle/feed** | Controls or manipulates an external data source the protocol trusts |
| A12 | **External adapter/router** | An attacker-controlled contract posing as a legitimate integration (vault adapter, swap router, bridge endpoint) |
| A13 | **Bridge/cross-chain actor** | Can send crafted cross-chain messages, replay, or withhold relay |
| A14 | **Compromised semi-trusted role** | Admin/operator acting within their stated permissions but with malicious intent |
| A15 | **Sequencer / MEV searcher** | Controls transaction ordering (fully for sequencers, partially for MEV bots) |

## How Agents Use This Matrix

### Phase 3 (Breadth) — Protocol Relevance Scan

After reading `design_context.md` and `attack_surface.md`, the breadth agent:

1. Marks which objectives are relevant (a pure NFT marketplace has no O5/O6;
   a lending protocol has most of the 14)
2. Marks which actors are relevant (no A5/A6 if no borrowing; no A8/A9 if no governance)
3. Identifies the 10-25 live (actor, objective) cells
4. For each live cell, asks: "Is there a code path from this actor's capabilities
   to this objective?" This becomes a seed for investigation.

### Phase 4b (Depth) — Finding Pressure-Test

For each finding under investigation, the depth agent checks:

1. Which objective does this finding serve? (If none — is it really a security finding?)
2. Which actor can reach this finding? (Constrains likelihood assessment)
3. Is this the terminal step, or does the attacker need additional enablers?
4. Does the same actor have a path to a STRONGER objective through the same entry point?

### Phase 4c (Chain Analysis) — Composition Targets

Chain Agent 2 uses the matrix to direct composition:

1. For each unmatched postcondition, ask: "Which objective does this state enable?"
2. For each low-severity isolated finding, ask: "Is this a step toward O1/O4/O5?"
3. Priority: compositions that reach O1 (drain) or O4 (freeze withdrawals) get highest chain severity.

## Relationship to Existing Methodology

- **Attack thesis** (`attack-thesis-methodology.md`): The thesis uses (victim, attacker, entry_point)
  triples. The objective matrix feeds thesis formation — each live (actor, objective) cell
  is a candidate thesis path.
- **8 adversarial questions** (`valves-doctrine.md`): The questions pressure-test individual
  code surfaces. The matrix provides the WHY — "pressure-test this surface because
  actor A3 might use it to achieve O4."
- **Strongest exploit cards** (`strongest-exploit-preservation.md`): Card eligibility rules
  (E1-E7) map to objectives — E1=O1, E2=O4, E3=O4/O13, E4=O4, E5=O1/O6, E6=any, E7=floor.
  The matrix makes this mapping explicit.
- **Enabler enumeration** (Phase 4c Agent 1): The 5-actor-category table maps to actors
  A1-A7. The matrix extends this to A8-A15.

## Anti-Anchoring Rule

The matrix is a FRAMING TOOL, not a finding generator. An agent that reports
"O1 is possible via A2" without independent code-level evidence is producing
speculation, not a finding. Every (actor, objective) claim must trace to specific
code paths with file:line references.
