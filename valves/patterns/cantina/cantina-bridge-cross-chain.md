# Cantina Bridge & Cross-Chain Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 2
> NOTE: Supplements existing BRIDGE-001..045 from Solodit corpus

---

## CANTINA-BRIDGE-046: cross_chain_state_proof_asymmetry
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: Source chain constructs proof/message with fields `(user, amount, token, chainId)` but destination chain expects `(user, amount, chainId, token)` or omits a field; `bytes memory crossChainData` populated on source chain but not forwarded by intermediate hook; Merkle leaf on source uses `abi.encodePacked` while destination uses `abi.encode`; proof created with N fields but verification checks N-1 fields
- **Detection Heuristic**:
  1. Trace the complete lifecycle of a cross-chain message: construction on source chain, serialization, relay, deserialization on destination chain
  2. Compare the message struct field-by-field at construction vs consumption: same fields, same order, same encoding
  3. Identify all intermediate processors (hooks, relayers, bridges) that touch the message; verify each one forwards ALL fields without mutation or truncation
  4. Check for missing fields: if the source includes `chainId` or `nonce` in the leaf/message but the destination omits it from verification, an attacker can replay across chains
  5. Test: construct a valid proof on source chain, attempt to verify on destination; if verification fails for all valid proofs, the function is permanently DoS-ed; if verification passes with tampered fields, replay or forgery is possible
- **Failure Mode**: Source chain hook constructs cross-chain claim data with 5 fields but an intermediate hook overwrites the data buffer without including the cross-chain fields (sets them to zero or stale values). Destination chain receives the message but Merkle verification fails because the leaf does not match. All legitimate cross-chain claims are DoS-ed with no recovery path. Alternatively, if destination chain verification omits `chainId` from the leaf, a proof valid on chain A can be replayed on chain B to double-claim. Insufficient leaf construction on source chain (fewer fields than needed for uniqueness) allows proof collision between different users or different claim types
- **Common Contexts**: Cross-chain vault systems with claim-on-destination, bridge protocols with Merkle-based state proofs, multi-chain airdrop or reward distributors, composable hook systems that relay data across chains

---

## CANTINA-BRIDGE-047: hardcoded_slippage_in_cross_chain_swap
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `amountOutMin = amount * 95 / 100` hardcoded in bridge/swap call; `slippage = SLIPPAGE_BPS` as immutable constant; governor-settable slippage with no per-user override; `swap(tokenIn, tokenOut, amount, 0)` passing zero as minimum output
- **Detection Heuristic**:
  1. Locate all cross-chain swap, bridge, or DEX integration calls that include a minimum output or slippage parameter
  2. Check if the slippage tolerance is hardcoded (constant or immutable) vs user-supplied or dynamically calculated
  3. If governor-settable: check if changes take effect immediately (sandwichable) or with a timelock
  4. If hardcoded: evaluate whether the fixed tolerance is appropriate for all market conditions (high volatility, low liquidity, depeg events)
  5. Check for zero slippage (`amountOutMin = 0`): this accepts ANY output and is always exploitable via sandwich
  6. Verify that the slippage parameter actually reaches the external swap call (not overwritten or ignored in an intermediate function)
- **Failure Mode**: Protocol hardcodes 5% slippage tolerance for cross-chain swaps. During high volatility or low liquidity, legitimate swaps fail because actual slippage exceeds 5%, causing user transactions to revert and funds to be stuck in transit. Conversely, a governor-settable slippage that takes effect immediately can be sandwiched: attacker observes slippage increase in mempool, front-runs with liquidity removal, swap executes at worse rate, attacker back-runs with liquidity restoration. Zero slippage (`amountOutMin = 0`) allows MEV bots to extract the full swap value via sandwich attacks on every transaction
- **Common Contexts**: Yield aggregators that auto-compound via cross-chain swaps, bridge protocols with integrated DEX routing, any protocol that performs swaps on behalf of users without user-supplied slippage parameters

---
