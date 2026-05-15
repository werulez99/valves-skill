# Cantina Reentrancy Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 2
> NOTE: Supplements existing REENTRY-001..018 from Solodit corpus

---

## CANTINA-REENTRY-019: cross_contract_reentrancy_via_external_swap
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `strategy.withdraw(amount)` that calls external DEX `swap()` mid-execution; Contract A writes to shared state, calls Contract B which triggers an external call (swap/transfer), callback re-enters Contract A before Contract A's state update completes; `nonReentrant` on individual contracts but no cross-contract reentrancy guard across the protocol
- **Detection Heuristic**:
  1. Identify all functions that perform external calls to untrusted or semi-trusted contracts (DEX routers, lending pools, strategy vaults) mid-execution
  2. Check if the calling contract has updated ALL its state variables before the external call (checks-effects-interactions within the contract)
  3. Trace whether the external call can trigger a callback to ANY other contract in the same protocol that reads the not-yet-updated state
  4. Verify reentrancy guards: per-contract `nonReentrant` does NOT protect against cross-contract reentrancy; look for protocol-wide reentrancy locks or shared mutex
  5. Test: craft a malicious token or DEX pool that calls back into Contract A's deposit/accounting function during Contract B's swap execution; verify whether stale state allows double-counting
- **Failure Mode**: Contract A initiates a withdrawal that calls Strategy Contract B. Contract B swaps tokens via a DEX, which triggers a callback (e.g., via a malicious token's `transfer` hook or a flash-swap callback). The callback re-enters Contract A's deposit function. Contract A's balance/share state was not yet updated (the withdrawal is still in progress), so the deposit reads stale state and credits the attacker with shares based on pre-withdrawal balances. After the callback completes, the original withdrawal also completes, and the attacker has shares reflecting both the deposit and the un-withdrawn balance. **NOTE**: This reinforces REENTRY-005 (cross-function reentrancy) and REENTRY-012 (read-only reentrancy via callback) from the Solodit corpus, but specifically targets the swap-in-withdrawal pattern where the external call is to a DEX router rather than a token transfer
- **Common Contexts**: Vault strategies that rebalance via DEX swaps during withdraw, lending protocols that liquidate by swapping collateral, any multi-contract system where an intermediate external call can re-enter a sibling contract

---

## CANTINA-REENTRY-020: chain_reorg_state_replay
- **Frequency**: ~1/279 findings
- **Severity**: MEDIUM
- **Code Shape**: State-changing transaction with no replay protection beyond transaction hash; `deposit()` that credits user based on `msg.value` without a user-supplied nonce; cross-chain message without source-chain finality verification; no `block.number` or `block.hash` anchor in state commitment
- **Detection Heuristic**:
  1. Identify the target chain's reorg characteristics (L2 sequencer reorgs, bridge finality delays, PoS reorg depth)
  2. Locate deposit, bridge, or commitment functions that change user balances based on a single transaction
  3. Check if the protocol has replay protection beyond the native transaction nonce (user-supplied nonce, commit-reveal, finality oracle)
  4. Verify cross-chain message handling: does the destination chain verify source-chain finality before processing
  5. Test: simulate a reorg where a deposit transaction is included in block N, reorged out, then re-included in block N+2; verify whether the user is credited once or twice
- **Failure Mode**: User deposits on a chain susceptible to reorgs. The deposit transaction is included in block N and the protocol credits the user. A reorg removes block N. The user's funds are returned to their wallet (transaction reverted), but the credit in the protocol persists if it was already bridged or committed to another chain. The user re-submits the deposit and receives a second credit. **NOTE**: This is a specialization of REENTRY-015 (state inconsistency across async boundaries). The Cantina finding specifically targets L2 chains and bridge message finality rather than same-chain reentrancy
- **Common Contexts**: L2 protocols before sequencer finality, bridge protocols without finality oracles, any cross-chain system where source-chain state can be reorganized after the destination chain has acted on it

---
