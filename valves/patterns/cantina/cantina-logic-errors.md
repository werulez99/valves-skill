# Cantina Logic Error Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 11
> NOTE: Supplements existing LOGIC-001..018 from Solodit corpus

---

## CANTINA-LOGIC-001: wrong_transfer_destination_or_source
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  token.safeTransfer(address(this), amount);    // should be externalReceiver
  token.safeTransferFrom(user, address(this), protocolFee); // should go to feeRecipient
  IERC20(underlying).transfer(msg.sender, fee); // should go to treasury or transmuter
  ```
- **Detection Heuristic**:
  1. Enumerate every `transfer`, `safeTransfer`, `transferFrom` call in the contract
  2. For each call, identify the semantic role of the destination: is it the user, the protocol treasury, a fee collector, or a third-party contract?
  3. Cross-check the destination against the function's stated purpose (repay -> creditor, liquidate -> liquidator, fee -> treasury)
  4. Flag any transfer where `address(this)` is used as destination in a function that should route funds externally (repay, fee distribution, liquidation payout)
  5. Check paired operations: if `deposit` sends to vault, does `withdraw`/`repay` send back to the correct counterparty?
- **Failure Mode**: Funds are sent to the contract itself (trapped) or to the wrong address. In repay/liquidation flows, the intended recipient (transmuter, fee collector, user) never receives funds. Tokens accumulate in the contract with no retrieval path.
- **Common Contexts**: Repay functions routing to self instead of lender/transmuter, protocol fee transfers going to contract instead of fee recipient, liquidation proceeds sent to wrong party, force-repay routing collateral incorrectly.

---

## CANTINA-LOGIC-002: wrong_accumulator_or_tracker_referenced
- **Frequency**: ~8/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Uses unadjusted debt instead of the adjusted-after-fee amount
  uint256 collateralToSeize = calculateCollateral(debtToBurn);  // should use adjustedDebtToBurn
  
  // Tracks collateral spent from wrong source
  spentCollateral += localAmount;  // should accumulate from the loop's running total
  
  // References stale cached value instead of live state
  uint256 fee = cachedAmount * feeRate / BASE;  // cachedAmount was derived incorrectly
  ```
- **Detection Heuristic**:
  1. In every multi-step arithmetic flow (liquidation, leverage, fee calculation), list each intermediate variable
  2. For each variable used as an operand, trace backward: was it computed from the correct base?
  3. Specifically check: does a post-adjustment value get used where a pre-adjustment one was intended, or vice versa?
  4. In loops that accumulate totals, verify the accumulator references the per-iteration delta, not a stale or cumulative value
  5. Check functions that cache amounts early then use them later: has any intervening operation invalidated the cached value?
- **Failure Mode**: Liquidation seizes collateral based on unadjusted debt (over-seizing or under-seizing), leverage tracking drifts from reality causing incorrect position accounting, fee calculations use wrong base producing over- or under-charging.
- **Common Contexts**: Liquidation flows with fee adjustments, leverage bundle creation with iterative loops, multi-step repay/borrow sequences, any function that caches an intermediate result and uses it after further mutations.

---

## CANTINA-LOGIC-003: fee_unit_or_base_mismatch
- **Frequency**: ~5/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Fee rate in basis points but divided by 1e18 (or vice versa)
  uint256 fee = amount * feeRate / 1e18;       // feeRate is in BPS (max 10000), should divide by 10000
  
  // Protocol fee calculated on gross instead of net (or vice versa)
  uint256 protocolFee = grossAmount * protocolFeeRate / BASE;  // should use netAmount after user fee
  
  // Fee transferred as rate instead of absolute amount
  token.transfer(treasury, feeRate);  // should be token.transfer(treasury, feeAmount)
  ```
- **Detection Heuristic**:
  1. For every fee calculation, identify the unit of the fee rate (BPS = /10000, WAD = /1e18, percentage = /100, raw amount)
  2. Verify the divisor matches the rate's unit system
  3. Check whether the fee is computed on the correct base amount: gross (pre-fee) vs net (post-fee) vs a completely different quantity
  4. Trace the fee value from computation to transfer: is the transferred amount the computed fee, or was the rate accidentally passed as the amount?
  5. In functions with multiple fee layers (user fee + protocol fee), verify each layer uses the correct post-deduction base
- **Failure Mode**: Fee in BPS divided by 1e18 produces near-zero fees, letting users transact fee-free. Fee computed on wrong base systematically over- or under-charges. Transferring the rate constant instead of the computed amount sends dust or reverts on insufficient balance.
- **Common Contexts**: Repay functions with protocol fees, liquidation penalty calculations, swap fee computation with multiple fee tiers, any system mixing BPS and WAD fee conventions.

---

## CANTINA-LOGIC-004: inverted_price_or_threshold_trigger
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Limit buy order triggers when price goes UP instead of DOWN
  if (currentPrice >= triggerPrice) { executeBuyOrder(); }  // should be <=
  
  // Uses spot price oracle when limit price should be compared to mark/index
  if (oraclePrice <= order.limitPrice) { execute(); }  // wrong oracle type for this order direction
  
  // Liquidation check inverted: liquidates healthy, spares unhealthy
  if (healthFactor > MIN_HEALTH) { liquidate(position); }  // should be <
  ```
- **Detection Heuristic**:
  1. Identify every price comparison that gates an execution (limit orders, stop-losses, liquidation triggers, collateral checks)
  2. For each comparison, determine the economic intent: buy-low triggers should fire when price drops BELOW threshold; sell-high when price rises ABOVE
  3. Verify the comparison operator matches the intent (buy: `<=`, sell: `>=`)
  4. Check which oracle/price feed is used: spot vs mark vs index vs TWAP — each has different semantics for order execution
  5. For liquidation health checks, verify the direction: unhealthy = below threshold should trigger, above threshold should be safe
- **Failure Mode**: Buy orders execute at price peaks instead of dips (user buys high). Sell orders execute at bottoms. Liquidation fires on healthy positions while leaving undercollateralized ones untouched. Systematic loss for users or protocol insolvency.
- **Common Contexts**: Limit order books, stop-loss mechanisms, price-dependent conditional execution, liquidation health factor checks, any threshold-gated trade or state transition.

---

## CANTINA-LOGIC-005: inverted_proof_or_eligibility_verification
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Merkle proof verification result inverted
  require(!MerkleProof.verify(proof, root, leaf), "invalid proof");  // should NOT negate
  
  // Accumulator zero-check bricks future operations
  if (P == 0) { revert; }  // P reaching zero is a valid steady-state, should handle gracefully
  ```
- **Detection Heuristic**:
  1. Find every `MerkleProof.verify`, `ECDSA.recover`, or custom proof verification call
  2. Check the boolean sense: `require(verify(...))` is correct; `require(!verify(...))` rejects valid proofs
  3. For accumulator/scaling factor checks, determine whether zero is a reachable steady-state or truly an error
  4. Trace what happens when the guard fires: does it block the intended population (malicious) or the unintended one (legitimate)?
- **Failure Mode**: Merkle proof inversion means only non-whitelisted addresses can claim (complete access control bypass). Accumulator zero-check permanently bricks deposits after a specific protocol state is reached.
- **Common Contexts**: Airdrop/vesting claim functions with Merkle proofs, whitelist verification, stability pool deposit scaling factors, any boolean verification result used in a require/if guard.

---

## CANTINA-LOGIC-006: stale_accounting_from_missing_sync
- **Frequency**: ~8/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Global accounting variable not updated after state-changing operation
  function claimRedemption() external {
      _transferOut(user, amount);
      // MISSING: totalSyntheticsIssued -= amount;  // causes bad debt accumulation
  }
  
  // Repeated calls between syncs produce compounding errors
  function redeem() external {
      debt -= redeemAmount;           // first call: correct
      // if called again before _sync(), earmarked state is stale
      earmarked -= redeemAmount;      // second call: uses stale earmarked value
  }
  
  // Interest/index not accrued before config change takes effect
  function updateFeeRate(uint256 newRate) external onlyAdmin {
      feeRate = newRate;  // MISSING: accrueInterest() first — existing positions not settled at old rate
  }
  ```
- **Detection Heuristic**:
  1. For every function that modifies balances, debt, or positions, list ALL global accounting variables that should change in tandem (totalSupply, totalDebt, totalSyntheticsIssued, earmarked, reserves)
  2. Verify each co-dependent variable is updated atomically in the same function
  3. Check re-entrancy between sync points: what happens if the same function is called twice before the next `_sync()` or `accrueInterest()`?
  4. For admin config changes (fee rates, interest models, reserve factors), verify that `accrueInterest()` or equivalent is called BEFORE the new config takes effect
  5. Check whether yield-bearing token balances in intermediary contracts (transmuters, vaults) are accounted for in the global state
- **Failure Mode**: Global totals drift from reality, causing: bad debt accumulation (synthetics issued but never decremented), compounding rounding errors on repeated operations between syncs, retroactive application of new rates to unsettled positions, phantom yield from unaccounted intermediary balances.
- **Common Contexts**: Synthetic asset redemption flows, transmuter/yield-bearing intermediaries, any protocol with a periodic `_sync()` pattern, admin parameter updates on lending/borrowing protocols, orderbook interest accrual.

---

## CANTINA-LOGIC-007: formula_variable_substitution_error
- **Frequency**: ~6/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // APR formula uses wrong term
  uint256 apr = (ptRate - 1) * YEAR / timeToMaturity;  // should use (1 - ptRate) or ln(ptRate)
  
  // Interest computed on wrong time delta
  uint256 interest = principal * rate * (block.timestamp - deployTime) / YEAR;
  // should use (block.timestamp - lastAccrualTime)
  
  // Loss calculation inverts the relationship
  uint256 loss = currentValue - initialValue;  // should be initialValue - currentValue when value dropped
  ```
- **Detection Heuristic**:
  1. For every financial formula (APR, interest, loss, exchange rate), write out the mathematical definition from documentation or standard finance
  2. Map each mathematical symbol to its code variable — verify 1:1 correspondence
  3. Check sign conventions: is `rate` annualized or per-second? Is `time` since deployment or since last accrual?
  4. Substitute concrete values and verify the result is economically sensible (APR should be positive for yield, loss should be positive when value decreased)
  5. For compound/iterative formulas, verify the recurrence relation matches the mathematical definition (especially log-space vs linear-space)
- **Failure Mode**: Incorrect APR display misleads users on expected returns. Interest over- or under-charged systematically. Loss calculation produces negative values or overflows. Exchange rates drift from fair value over time.
- **Common Contexts**: Fixed-rate markets (APR from PT/YT prices), lending interest accrual, loss socialization calculations, reward rate computations, any DeFi formula translating a financial concept to code.

---

## CANTINA-LOGIC-008: rounding_direction_in_intermediate_computation
- **Frequency**: ~6/279 findings
- **Severity**: MEDIUM
- **Code Shape**:
  ```solidity
  // Premium rounds down when protocol should round up to cover costs
  uint256 premiumBips = rawPremium * BPS / totalValue;  // truncates to 0 for small premiums
  
  // Query/preview function rounds differently than execution
  function queryRedemption() view returns (uint256) {
      return amount * exchangeRate / PRECISION;  // rounds UP here
  }
  function executeRedemption() external {
      uint256 payout = amount * exchangeRate / PRECISION;  // also rounds up — should round DOWN for execution
  }
  
  // User exploits rounding to eliminate fees
  // By splitting into many small transactions where fee rounds to 0
  uint256 fee = smallAmount * feeRate / BASE;  // 0 when smallAmount * feeRate < BASE
  ```
- **Detection Heuristic**:
  1. Identify every division in fee, premium, or exchange rate calculations
  2. Determine who benefits from truncation: if the protocol should receive the residual, use `ceilDiv`; if the user should, use floor division
  3. Compare view/preview functions against their execution counterparts: rounding MUST be consistent or the preview must be conservative (return less than actual payout)
  4. Check whether splitting a large operation into many small ones can zero out per-operation fees via truncation
  5. For basis-point conversions, verify that small absolute values do not truncate to zero prematurely
- **Failure Mode**: Protocol fees round to zero on small transactions — users split large operations to avoid fees entirely. Preview functions return higher values than execution, causing downstream accounting mismatches or integration failures. Premiums truncate to zero, leaving the protocol uncompensated for risk.
- **Common Contexts**: Swap fee calculations in AMMs, premium computation in lending/options, preview vs execute pairs in ERC4626 vaults, any fee computed as `amount * rate / BASE` where amount can be small.

---

## CANTINA-LOGIC-009: withheld_or_reserved_amount_ignored
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Withdrawal ignores already-withheld portion
  function withdraw(uint256 amount) external {
      uint256 available = address(this).balance;  // should subtract currentWithheldETH
      require(amount <= available);
      payable(msg.sender).transfer(amount);
  }
  
  // Credit calculation ignores deposit already reflected in missing assets
  uint256 credit = totalDeposits - totalBorrowed;  // should account for additionalCredit from missing asset changes
  
  // Reward decrease ignores already-locked portion
  uint256 decrease = totalWeight - newWeight;  // should be (totalWeight - lockedWeight) - newWeight
  ```
- **Detection Heuristic**:
  1. For every balance or availability check, list ALL reservations against that balance (withheld amounts, pending withdrawals, locked collateral, reserved fees)
  2. Verify the available amount subtracts ALL reservations, not just some
  3. Check state transitions: when a reservation category changes (e.g., deposited->missing->replenished), does the credit/availability calculation reflect the transition?
  4. For reward/weight calculations, verify that locked or committed portions are excluded from the freely-adjustable amount
- **Failure Mode**: Users withdraw reserved funds (double-spend of withheld ETH), credit calculations overstate availability leading to over-lending, reward weight adjustments undercount the decrease causing permanent weight inflation.
- **Common Contexts**: ETH staking withdrawals with withheld amounts, lending protocol credit calculations with missing asset accounting, unwinding/unlocking flows in staking or locking contracts.

---

## CANTINA-LOGIC-010: price_type_confusion_in_paired_operations
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**:
  ```solidity
  // Uses mid-price where bid/ask should apply
  uint256 entryValue = position.size * getMidPrice();   // should use getBidPrice() for longs
  uint256 exitValue  = position.size * getMidPrice();   // should use getAskPrice() for longs
  
  // Swap fee uses wrong parameter order for direction
  uint256 fee = calculateFee(tokenIn, tokenOut);  // parameters swapped for the sell direction
  
  // Leverage formula uses pre-fee price for one leg and post-fee for another
  uint256 openCost = amount * priceWithFee;
  uint256 closeValue = amount * priceWithoutFee;  // asymmetric pricing creates arbitrage
  ```
- **Detection Heuristic**:
  1. List every price retrieval call and classify its type: mid, bid, ask, oracle, spot, mark, index
  2. For each use site, determine the economic context: buying uses ask (or mid), selling uses bid (or mid), but the same function should not mix them
  3. In paired operations (open/close, deposit/withdraw, borrow/repay), verify both sides use the correct and symmetric price type
  4. Check parameter ordering in swap/fee functions: does `(tokenIn, tokenOut)` vs `(tokenOut, tokenIn)` matter for the calculation?
  5. Verify leverage calculations use consistent pricing across the numerator and denominator
- **Failure Mode**: Inconsistent price types create arbitrage: user opens position valued at bid but closes at mid (extracting the spread). Swapped fee parameters charge fees in the wrong direction. Asymmetric pricing in leverage calculations allows profit extraction from the spread.
- **Common Contexts**: Perpetual exchanges with bid/ask spreads, leveraged trading platforms, AMMs with directional fee computation, any protocol computing position value using oracle prices.

---

## CANTINA-LOGIC-011: leverage_or_loop_iterative_drift
- **Frequency**: ~4/279 findings
- **Severity**: MEDIUM
- **Code Shape**:
  ```solidity
  // Loop builds leverage but uses wrong running total
  for (uint i = 0; i < iterations; i++) {
      uint256 borrow = collateral * ltv / BASE;
      deposit(borrow);
      collateral = borrow;  // should accumulate: collateral += borrow
  }
  
  // Update formula for existing position uses open-position formula
  function updateLeverage(uint256 newTarget) external {
      uint256 delta = newTarget - currentLeverage;
      uint256 borrowMore = totalCollateral * delta / BASE;  // wrong: should use marginal formula
  }
  
  // Borrow amount in loop iteration calculated on initial instead of remaining
  uint256 toBorrow = initialAmount * leverageFactor;  // should decrease each iteration as available collateral shrinks
  ```
- **Detection Heuristic**:
  1. In any iterative leverage/deleverage loop, trace the running collateral and debt totals through 3 concrete iterations with real numbers
  2. Verify the borrow amount in each iteration is computed from the CURRENT available collateral, not the initial or a stale value
  3. For leverage update functions (adjusting an existing position), verify the formula accounts for already-borrowed amounts — the marginal formula differs from the open-position formula
  4. Check loop convergence: does each iteration bring the position closer to the target, or can it oscillate or diverge?
  5. Compare the final leverage ratio after N iterations against the mathematical closed-form: `totalCollateral = initial * (1 + ltv + ltv^2 + ... + ltv^N)`
- **Failure Mode**: Position ends up with wrong leverage ratio: under-leveraged (opportunity cost) or over-leveraged (liquidation risk). Update function borrows too much or too little, creating an immediate liquidation risk or leaving unused collateral. Loop diverges instead of converging to target.
- **Common Contexts**: Leveraged vault strategies (flash-loan-free iterative leverage), leverage bundle creation in lending protocols, auto-compound strategies with reinvestment loops.

---
