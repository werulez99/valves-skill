# Cantina DEX & AMM Logic Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 9
> NOTE: Supplements existing DEX-001..034 from Solodit corpus

---

## CANTINA-DEX-035: swap_fee_parameter_ordering
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `calculateFee(reserveA, reserveB, ...)` where parameter order differs from documented spec; `getSwapFee(currentReserve, referenceReserve)` vs `getSwapFee(referenceReserve, currentReserve)`
- **Detection Heuristic**:
  1. Identify all fee calculation functions that take reserve/balance pairs as inputs
  2. Trace each call site and compare argument ordering against the function signature
  3. Check if swapping the parameter order changes the fee magnitude (asymmetric formula)
  4. Verify reference/current reserve distinction is consistent across all callers
- **Failure Mode**: Attacker calls swap when reserves are out-of-sync (e.g., after interest accrual or donation), fee computed on wrong base yields zero or near-zero fee, draining fee revenue from LPs
- **Common Contexts**: AMMs with dynamic fee curves, concentrated liquidity with fee tiers, protocols that separate reference reserves from current reserves

---

## CANTINA-DEX-036: position_transfer_penalty_bypass
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `transfer(to, amount)` on LP/borrow/position tokens without recalculating penalty state; `penaltyOf[msg.sender]` checked but `penaltyOf[to]` not updated on transfer
- **Detection Heuristic**:
  1. Identify positions or accounts that carry penalty/fee multiplier state (over-utilization, over-saturation, health factor penalties)
  2. Check if the position token is transferable (ERC20/ERC721 transfer, or internal transfer function)
  3. Verify that transfer hooks recalculate or migrate penalty state to the recipient
  4. Test: user with penalty transfers position to fresh address, confirm penalty resets to zero
- **Failure Mode**: User with over-saturated or penalized position transfers borrow/LP tokens to a clean address, receiving address holds same position without penalty, penalty system becomes unenforceable
- **Common Contexts**: Lending protocols with utilization penalties, AMMs with over-leverage penalties, any system where position tokens carry implicit state beyond balance

---

## CANTINA-DEX-037: lp_withdrawal_splitting_arbitrage
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `removeLiquidity(shares)` where per-unit output depends on withdrawal size; non-linear fee/slippage curve applied to LP exit; `fee = f(amount)` where `f(a) + f(b) < f(a+b)` or `f(a) + f(b) > f(a+b)`
- **Detection Heuristic**:
  1. Locate LP withdrawal/burn functions that compute output amounts
  2. Check if the output-per-share varies with the withdrawal amount (non-linear pricing)
  3. Test: compare `withdraw(100)` output vs `withdraw(50) + withdraw(50)` output
  4. If outputs differ, determine which direction is exploitable (splitting vs aggregating)
  5. Check for sandwich protection (minimum output, deadline, single-block restrictions)
- **Failure Mode**: LP splits a large withdrawal into multiple smaller ones within the same block, each getting a more favorable rate due to non-linear fee/slippage curve, extracting more tokens than a single withdrawal would yield
- **Common Contexts**: AMMs with concentrated liquidity, curve-based pools with non-linear withdrawal fees, protocols where withdrawal fee depends on pool utilization ratio

---

## CANTINA-DEX-038: parameter_update_sandwich
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `setFee(newFee)` or `setSpread(newSpread)` callable by admin/governance without timelock; LP-affecting parameter change observable in mempool; no `block.number` guard between parameter change and user action
- **Detection Heuristic**:
  1. Enumerate all admin/governance setter functions that modify swap fee, spread, or pricing parameters
  2. Check if parameter changes take effect immediately (same block) vs with delay (timelock)
  3. Verify if LPs/swappers can observe the pending change and front-run or back-run it
  4. Test: sandwich sequence where attacker deposits before favorable parameter change, withdraws after
- **Failure Mode**: Admin calls `setLsf()` or `setFee()` in mempool, attacker front-runs with deposit at old rate, parameter updates, attacker back-runs with withdrawal at new rate, capturing the value delta at other participants' expense
- **Common Contexts**: AMMs with governance-adjustable fee parameters, lending protocols with admin-settable interest rate curves, any protocol where on-chain parameter changes affect existing position value

---

## CANTINA-DEX-039: donation_attack_on_lp_pricing
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `balanceOf(address(this))` or `token.balanceOf(pool)` used in share price calculation; `provideLiquidity` uses spot balance rather than tracked reserves; no `sync()` guard before mint
- **Detection Heuristic**:
  1. Identify share/LP token minting functions that compute exchange rate
  2. Check if the rate uses live token balance (`balanceOf`) vs internally tracked reserves
  3. If `balanceOf` is used, verify a donation (direct transfer without calling deposit) inflates the rate
  4. Test: donate tokens to pool address, then call `provideLiquidity` with small amount, verify share price is inflated
- **Failure Mode**: Attacker donates tokens directly to pool contract, inflating the per-share price. Next LP depositor receives fewer shares than expected. Attacker then withdraws, capturing the donated amount plus a portion of the victim's deposit. Variant: first depositor inflates price to make subsequent deposits round down to zero shares
- **Common Contexts**: ERC4626-like LP vaults, AMM pools that use spot balance for pricing, any share-based pool without reserve tracking separate from token balance

---

## CANTINA-DEX-040: fee_theft_via_reserve_desync
- **Frequency**: ~4/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `accruedFees` or `pendingInterest` not incorporated into reserve state before swap; `getReserves()` returns stale values; fee calculation uses `reserve` while actual balance includes unclaimed fees
- **Detection Heuristic**:
  1. Identify all sources of reserve growth outside of swaps (interest accrual, lending fees, protocol fees)
  2. Check if swap fee calculation uses reserves that include or exclude these accruals
  3. Trace the timing: when are fees accrued vs when are reserves updated
  4. Test: accrue interest, then swap before reserves sync, compare fee to expected value
  5. Check if LP burn in the same block as fee accrual grants excess fees to the burner
- **Failure Mode**: Interest accrues but reserves are not updated. Swapper executes swap using stale reserves, paying incorrect fee (zero fee when reserves are below reference, or excessive fee). Alternatively, LP burns shares in the same block as fee accrual, receiving a disproportionate share of freshly accrued fees
- **Common Contexts**: Lending-AMM hybrids (Ammalgam-style), AMMs with external yield, pools where reserves serve dual purpose (swap pricing + fee accounting)

---

## CANTINA-DEX-041: quadratic_fee_boundary_error
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `if (fee > THRESHOLD) { fee = base + (fee - THRESHOLD) ** 2 }` with incorrect boundary arithmetic; piecewise fee function with discontinuity at boundary; `bipsQ64` or fixed-point fee with overflow near boundary
- **Detection Heuristic**:
  1. Locate piecewise or non-linear fee functions (quadratic growth, exponential, tiered)
  2. Check boundary arithmetic at each tier transition point
  3. Verify the fee is continuous at boundaries (no jump or gap)
  4. Test with values at, just below, and just above each boundary threshold
  5. Check for overflow in fixed-point multiplication when fee approaches maximum tier
- **Failure Mode**: Fee function has incorrect boundary constant (e.g., quadratic growth applied past 4000 bips uses wrong base), creating a discontinuity or incorrect growth rate. Swappers can target the boundary to pay less than intended, or the fee overflows to zero at extreme utilization
- **Common Contexts**: AMMs with utilization-based dynamic fees, protocols with progressive penalty curves, any fee function with multiple tiers or non-linear segments

---

## CANTINA-DEX-042: stableswap_operation_when_paused
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `killSwap()` or `pause()` that disables `swap()` but not `addLiquidity()`/`removeLiquidity()`; asymmetric pause scope; `whenNotPaused` modifier on swap but not on deposit/withdraw
- **Detection Heuristic**:
  1. Identify all pause/kill mechanisms and which functions they gate
  2. Check if adding or removing liquidity in a single token is still possible when swaps are killed
  3. Verify that single-sided liquidity operations cannot be used to achieve an implicit swap
  4. Test: pause swaps, then add liquidity in token A and immediately remove in token B
- **Failure Mode**: Admin kills swaps to protect the pool (during depeg or exploit), but single-sided add/remove liquidity remains open. Attacker uses add-tokenA then remove-tokenB sequence to achieve an effective swap, circumventing the pause. Pool price moves despite "killed" swap state
- **Common Contexts**: Stableswap pools (Curve-style), multi-asset pools with single-sided operations, any AMM where pause is per-operation rather than per-contract

---

## CANTINA-DEX-043: trading_limit_fee_inclusion
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `require(amount <= tradingLimit)` where `amount` includes fees; `netAmount = amount - fee` computed after limit check; limit check on gross amount but economic exposure is net amount
- **Detection Heuristic**:
  1. Locate all trading limit or rate limit checks (per-transaction caps, daily volume limits)
  2. Determine whether the limit is checked on gross amount (before fees) or net amount (after fees)
  3. Check if fee deduction happens before or after the limit comparison
  4. Verify consistency: if the limit is meant to cap economic exposure, fees should be excluded
  5. Test: with high fee rate, verify effective trading capacity is reduced below intended limit
- **Failure Mode**: Trading limits are checked on gross amounts including fees. With a 5% fee, a 1M limit only allows ~950K of actual trading. When fee parameters change, the effective trading limit shifts unexpectedly. If fee + protocol fee approach the limit threshold, users cannot trade at all despite having room under the intended economic limit
- **Common Contexts**: Exchange protocols with daily/per-trade volume caps, stablecoin AMMs with configurable fee + trading limits, any protocol combining fee deduction with position/volume limits

---
