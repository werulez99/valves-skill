# Cantina Arithmetic Precision Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 5
> NOTE: Supplements existing ARITH-001..028 from Solodit corpus

---

## CANTINA-ARITH-029: rounding_direction_state_corruption
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**: `roundUp(debt / shares)` in repayment where cumulative round-ups cause `totalRepaid > totalDebt`; `increment += roundUp(x)` accumulated over many calls leads to `sum(increments) > total`; signed/unsigned underflow when `accounted > actual` due to accumulated rounding
- **Detection Heuristic**:
  1. Identify all arithmetic operations that accumulate rounded results over multiple calls (per-user repayments summed to a total, per-epoch rewards accumulated to a pool)
  2. For each: check rounding direction (roundUp vs roundDown)
  3. Compute: after N iterations with minimum amounts, can the accumulated rounded sum exceed the source total?
  4. Trace what happens when the accumulated value exceeds the invariant bound (underflow, revert, state corruption)
  5. Check if a `forceRepay` or `claim` path uses a different rounding direction than the normal path
- **Failure Mode**: Each individual repayment rounds up by 1 wei. After many small repayments, total repaid exceeds total debt. When the protocol tries to compute remaining debt (`totalDebt - totalRepaid`), it underflows. This corrupts accounting state, can lock remaining users' funds, or create phantom debt. Variant: increment rounding causes a counter to exceed its parent total, breaking `require(part <= whole)` invariants
- **Common Contexts**: Lending protocols with per-user debt accounting, reward distribution with per-epoch accumulation, any system where many small rounded operations are summed against a fixed total

---

## CANTINA-ARITH-030: fixed_point_overflow_at_utilization_boundary
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `rate = baseRate + (utilization * slope) / WAD` where `utilization` can reach or exceed `WAD` (100%); `mulWad(x, y)` where `x * y > type(uint256).max`; interest calculation overflow when utilization hits a configured ceiling
- **Detection Heuristic**:
  1. Locate all fixed-point multiplication chains in interest/fee/rate calculations
  2. Identify the maximum possible value of each input variable (utilization can reach 100%, rate can compound, time can be large)
  3. Compute: at maximum inputs, does the intermediate multiplication overflow uint256?
  4. Check if overflow leads to silent wraparound (Solidity < 0.8) or revert (Solidity >= 0.8)
  5. If revert: trace which user-facing function becomes permanently stuck
- **Failure Mode**: Utilization reaches or slightly exceeds 100% (possible via rounding, interest accrual, or withdrawal race). Interest calculation multiplies utilization by slope in fixed-point, intermediate result overflows. In Solidity >= 0.8 this reverts, permanently bricking the pair/pool. No user can interact (deposit, withdraw, liquidate, repay) because every path calls the interest accrual function. The protocol must be redeployed
- **Common Contexts**: Lending protocols with kink-based interest rate models, AMM-lending hybrids with utilization-based fees, any protocol with fixed-point math near 100% utilization

---

## CANTINA-ARITH-031: rounding_elimination_of_small_fees
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `fee = amount * feeRate / PRECISION` where `amount * feeRate < PRECISION` yields `fee = 0`; `protocolFee = fee * protocolShare / TOTAL` where small fee gets rounded to zero; repeated zero-fee transactions drain value
- **Detection Heuristic**:
  1. Locate all fee calculation expressions
  2. For each: compute the minimum `amount` that produces a non-zero fee given the current fee rate
  3. Check if users can transact below this minimum amount (no minimum transaction size enforced)
  4. Calculate cumulative impact: N zero-fee transactions of amount X vs 1 transaction of amount N*X
  5. Check if protocol fees specifically (as opposed to LP fees) are the rounded-to-zero victim
- **Failure Mode**: Fee rate is 30 bips (0.3%). Any transaction below ~3333 units of the fee denomination pays zero fee. Attacker splits large swap into many small swaps, each paying zero fee. Over time, LPs collect no fees despite pool utilization. Variant: LP fee is non-zero but protocol fee (a fraction of LP fee) rounds to zero, so protocol collects nothing while LPs are paid
- **Common Contexts**: AMMs with basis-point fees, lending protocols with small interest spreads, any fee system where fee = amount * rate / large_denominator without minimum fee enforcement

---

## CANTINA-ARITH-032: timestamp_first_action_overcharge
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `lastUpdateTimestamp = block.timestamp` set on pool creation but `rewardRate` set later; `interestAccrued = rate * (block.timestamp - lastUpdate)` where `lastUpdate` is stale from deployment; first `accrueInterest()` call covers the entire period since deployment
- **Detection Heuristic**:
  1. Identify all time-based accrual mechanisms (interest, rewards, fees)
  2. Check when `lastUpdateTimestamp` is first set vs when the rate/reward becomes non-zero
  3. If timestamp is set at deployment/creation but rate is set later: the first accrual covers the gap
  4. Verify if the first borrower/depositor absorbs the entire accumulated amount
  5. Check if `accrueInterest()` is called in the same transaction as the first user action
- **Failure Mode**: Pool is created at time T0 with `lastUpdateTimestamp = T0`. First borrower enters at T1 (hours or days later). `accrueInterest()` computes interest for the entire T0-to-T1 period, charging the first borrower for time before they existed. Alternatively, the first reward distributor call distributes zero rewards because the rate was calculated using the inflated time delta
- **Common Contexts**: Lending pools with lazy interest accrual, reward distribution contracts with time-weighted rates, any protocol where timestamp initialization and rate activation are separate transactions

---

## CANTINA-ARITH-033: precision_loss_in_weighted_calculation
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `weight = amount * multiplier / total` where intermediate division truncates before subsequent multiplication; `rewardWeight = lockDuration * amount / totalLocked / MAX_DURATION` (divide-before-multiply); weighted average with low-precision intermediate
- **Detection Heuristic**:
  1. Identify all weighted calculations (vote weight, reward weight, penalty multiplier, redemption weight)
  2. Check operation ordering: does any division occur before a subsequent multiplication?
  3. Compute precision loss: for the smallest meaningful input, how many bits of precision are lost?
  4. Trace downstream impact: is the imprecise weight used for access control (voting quorum), fund distribution, or penalty assessment?
  5. Check if precision loss is amplified by iteration (weight computed per-epoch, accumulated over many epochs)
- **Failure Mode**: Lock duration weight is computed as `duration / MAX_DURATION * amount` instead of `duration * amount / MAX_DURATION`. For short durations, the first division truncates to zero, giving zero weight regardless of amount. Users with short locks get no voting power or rewards. Variant: precision loss in redemption weight calculation causes overflow when the weight exceeds a threshold constant, as the imprecise value can fall on the wrong side of a boundary check
- **Common Contexts**: Governance systems with time-weighted voting, staking with lock duration multipliers, reward distribution with multi-factor weighting, any protocol computing proportional shares with intermediate fixed-point steps

---
