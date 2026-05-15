# Cantina Lending & Liquidation Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 12
> NOTE: Supplements existing LEND-001..050 from Solodit corpus

### Findings that reinforce existing Solodit patterns (not duplicated here):
- **LEND-003** (reentrancy in liquidation): Jigsaw cross-contract reentrancy during ElixirStrategy.withdraw() swaps
- **LEND-007** (bad debt not handled): Jigsaw LiquidationManager::liquidate() leaves bad debt; Alchemix totalSyntheticsIssued not updated
- **LEND-017** (liquidation frontrunning/griefing): Jigsaw liquidation DoS via 1 wei repayment frontrun; Alchemix liquidations DoSed by front-running with repay()
- **LEND-022** (paused state asymmetry): Jigsaw pausing mechanism exposes users to instant liquidations on unpause
- **LEND-002** (liquidation invariant math): Ammalgam incorrect rounding for premiumInBips; Alchemix incorrect debt calculation for _redemptionWeight
- **LEND-032** (incorrect interest/fee calculation): Ammalgam accruePenalties applies much more penalties; Alchemix fee unit mismatch
- **LEND-016** (state not updated after liquidation): Alchemix totalSyntheticsIssued not updated in claimRedemption
- **LEND-024** (dust position exploit): Avon liquidators can leave dust positions

---

## CANTINA-LEND-001: strategy_layer_withdrawal_accounting_mismatch
- **Frequency**: ~8/279 findings
- **Severity**: HIGH
- **Code Shape**: `strategy.withdraw(amount)` where actual withdrawn != requested; `balanceOf(address(this))` checked before/after external strategy call; `sharesRegistry.adjustCollateral()` using requested amount not actual; `pendleStrategy.withdraw()` or `elixirStrategy.withdraw()` with partial fill; `depositedAmount -= requestedAmount` instead of `depositedAmount -= actualWithdrawn`
- **Detection Heuristic**:
  1. Grep for external strategy/vault `withdraw()` or `redeem()` calls inside collateral management functions
  2. Check if the return value or balance delta is used for internal accounting vs. the requested amount
  3. Trace if the strategy can return fewer assets than requested (queue-based, partial fill, slippage)
  4. Verify that the collateral registry adjustment uses the ACTUAL amount received, not the requested amount
  5. Flag any strategy integration where `depositedAmount` is decremented by the input parameter rather than the output
- **Failure Mode**: User requests withdrawal of X from strategy-backed collateral; strategy returns X-delta due to queue/slippage/partial fill; protocol books the full X as withdrawn; collateral accounting diverges from reality; over time, system becomes undercollateralized because phantom collateral is counted; liquidation of the position cannot recover the booked amount
- **Common Contexts**: Lending protocols integrating yield strategies (Elixir, Pendle, Aave, Yearn) as collateral vaults; any collateral wrapper where the underlying has non-atomic withdrawal (request/claim pattern); multi-step withdrawal strategies with intermediate states

---

## CANTINA-LEND-002: negative_yield_unliquidatable_positions
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**: `collateralValue = shares * strategy.pricePerShare()` where `pricePerShare()` can decrease; `liquidate()` calls `strategy.withdraw(requiredCollateral)` but strategy has lost value so actual < required; `if (strategyBalance < debtValue) revert`; no fallback liquidation path when strategy is underwater
- **Detection Heuristic**:
  1. Grep for collateral valuation paths that read external `pricePerShare()`, `exchangeRate()`, or `convertToAssets()`
  2. Check if the liquidation routine assumes the strategy's share-to-asset ratio is >= the ratio at deposit time
  3. Verify there is a fallback liquidation path when the strategy has experienced negative yield (shares worth less than booked)
  4. Trace the liquidation flow: does it revert if `strategy.withdraw()` returns less than `debtToRepay`?
  5. Check if bad debt socialization handles the shortfall from strategy losses
- **Failure Mode**: Borrower deposits 100 tokens into strategy-backed collateral; strategy suffers loss, shares now worth 80; borrower's debt is 90; liquidator calls liquidate but strategy can only return 80; if liquidation requires full debt coverage it reverts; position becomes permanently unliquidatable; bad debt accumulates with no recovery mechanism
- **Common Contexts**: Lending protocols accepting yield-bearing collateral from external strategies; collateral wrappers around Pendle PT/YT, Elixir vaults, or restaking protocols that can experience slashing/negative yield; any vault collateral where the exchange rate is not monotonically increasing

---

## CANTINA-LEND-003: bad_debt_ratio_staleness_and_ordering
- **Frequency**: ~6/279 findings
- **Severity**: HIGH
- **Code Shape**: `badDebtRatio = totalBadDebt / totalDeposited` computed AFTER removing the yield token from the denominator; `claimRedemption()` charges `amount * badDebtRatio` but ratio was set at redemption request time and never updated; `badDebtRatio` calculated with stale `totalSyntheticsIssued`; ordering of operations: `removeYieldToken()` then `calculateBadDebtRatio()` instead of reverse
- **Detection Heuristic**:
  1. Grep for `badDebtRatio`, `badDebt`, `debtRatio`, `lossSocialization` calculation sites
  2. Check the ORDER of operations: is the ratio computed BEFORE or AFTER modifying the denominator (total deposits, total supply)?
  3. Verify that loss socialization ratios are recalculated at claim time, not just at event time
  4. Trace whether `totalDeposited` or `totalSyntheticsIssued` is updated BEFORE the ratio calculation that depends on it
  5. Flag any path where a ratio is stored once and applied repeatedly without refresh
- **Failure Mode**: Protocol removes a yield token (reducing denominator), THEN calculates bad debt ratio with the smaller denominator, producing a worse ratio than reality; OR bad debt ratio is computed once at redemption request time but applied at every claim, perpetually overcharging redeemers even after bad debt is resolved; users claiming redemption pay the same bad debt penalty forever regardless of protocol recovery
- **Common Contexts**: Synthetic asset protocols with redemption queues (Alchemix v3); CDP protocols that socialize bad debt across depositors; any protocol that snapshots a loss ratio and applies it to future operations without recalculation

---

## CANTINA-LEND-004: collateral_hiding_from_bad_debt_liquidation
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `holding.getCollateralAmount()` iterates only active strategies; user moves collateral to a strategy not enumerated by liquidation; `liquidateBadDebt()` calls `holding.withdraw()` but holding has assets in a strategy the function does not query; `registeredStrategies[]` vs. `activeStrategies[]` mismatch
- **Detection Heuristic**:
  1. Grep for bad debt liquidation functions and trace which collateral sources they enumerate
  2. Check if the user can deposit collateral into strategies/vaults that the liquidation function does not iterate
  3. Verify that `liquidateBadDebt()` or equivalent queries ALL possible collateral locations, not just a subset
  4. Compare the set of strategies a user can deposit into vs. the set the liquidation function withdraws from
  5. Flag discrepancies between `registeredStrategies` (user can deposit) and strategies iterated during liquidation
- **Failure Mode**: Holding owner deposits collateral into strategy A and strategy B; bad debt liquidation only queries strategy A; owner moves most collateral to strategy B before bad debt liquidation; liquidator can only seize the small amount in strategy A; majority of collateral is hidden from liquidation; protocol absorbs the unrecovered bad debt
- **Common Contexts**: Multi-strategy lending protocols where users can allocate collateral across multiple yield strategies; holding-based architectures where a holding contract manages user collateral across pluggable strategies; protocols where strategy registration and liquidation iteration lists diverge

---

## CANTINA-LEND-005: stablecoin_depeg_death_spiral
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `stablecoin.redeem()` returns collateral at oracle price but `stablecoin.mint()` uses peg assumption; liquidation bonus paid in protocol stablecoin that is depegging; `debtValue = stablecoinAmount * 1e18` (hardcoded peg); stability pool denominated in the depegging stablecoin; no circuit breaker when `stablecoinPrice < threshold`
- **Detection Heuristic**:
  1. Grep for hardcoded `1e18` or `1 * PRECISION` peg assumptions in debt valuation
  2. Check if the protocol's native stablecoin is used as the unit of account for debt AND liquidation incentives
  3. Verify there is a circuit breaker or oracle-based repricing when the stablecoin depegs
  4. Trace the feedback loop: depeg -> liquidations -> more stablecoin sold -> further depeg
  5. Check if the stability pool or liquidation mechanism creates net selling pressure on the depegging asset
- **Failure Mode**: Protocol stablecoin depegs to 0.95; liquidations trigger, selling seized collateral for the stablecoin; increased stablecoin supply further depresses price to 0.90; more positions become liquidatable; cascading liquidations create a death spiral; protocol becomes insolvent as collateral value drops faster than debt is cleared; stability pool holders suffer outsized losses
- **Common Contexts**: CDP-based stablecoin protocols (jUSD, LUSD-forks, alUSD); any protocol where the debt token is also the liquidation incentive token; lending protocols without external stablecoin liquidity backstops

---

## CANTINA-LEND-006: utilization_cliff_permanent_brick
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `if (utilization > MAX_UTILIZATION) revert()` in core lending functions; `repay()` or `withdraw()` also checks utilization creating a deadlock; `interestRate = f(utilization)` with discontinuity at boundary; no admin override to force repayment when utilization exceeds cap; `utilization = totalBorrows / totalDeposits` where a withdrawal can push utilization above max
- **Detection Heuristic**:
  1. Grep for `MAX_UTILIZATION`, `maxUtilization`, `utilizationCap` constants and where they are checked
  2. Verify that `repay()` does NOT check utilization (repayment should always be allowed)
  3. Check if `withdraw()` by a lender can push utilization above the cap, and whether that then blocks all subsequent operations
  4. Trace what happens when utilization is exactly at or 1 wei above the cap: can any function still execute?
  5. Flag if both deposit and borrow functions check utilization, creating a state where neither new deposits nor repayments can restore the system
- **Failure Mode**: Utilization reaches 100.01% due to interest accrual or a lender withdrawal; the utilization check in `repay()` or `borrow()` reverts; borrowers cannot repay their debt; lenders cannot withdraw; the pair is permanently bricked; all funds locked in the contract with no recovery path
- **Common Contexts**: Pair-based lending protocols (Ammalgam, Fraxlend-forks); isolated lending markets with per-pair utilization caps; protocols where interest accrual can push utilization above the configured maximum between transactions

---

## CANTINA-LEND-007: liquidation_fee_avoidance_via_alternative_exit
- **Frequency**: ~4/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `withdraw()` charges `withdrawalFee` but `liquidate()` does not; user self-liquidates or arranges friendly liquidation to bypass fees; `claimRewards()` through strategy charges fee but direct `strategy.claim()` does not; `liquidationBonus < withdrawalFee` making liquidation cheaper than voluntary exit
- **Detection Heuristic**:
  1. Grep for all exit paths from the protocol: `withdraw()`, `redeem()`, `liquidate()`, `claimRewards()`
  2. Compare fee structures across each path: which paths charge withdrawal fees and which do not?
  3. Check if a user can deliberately make their position marginally liquidatable to exit via liquidation
  4. Verify that reward claiming through the strategy applies the same fees as direct reward claiming
  5. Flag if `liquidationPenalty < withdrawalFee` for any collateral type
- **Failure Mode**: Protocol charges 2% withdrawal fee on normal exits; liquidation path charges 0% or 5% penalty but returns 95% to borrower as surplus; users intentionally let positions become barely liquidatable; friendly liquidator (alt account) liquidates them; user receives collateral minus small penalty, saving the withdrawal fee; protocol loses expected fee revenue; in extreme cases, withdrawal fee becomes unenforceable
- **Common Contexts**: Lending protocols with withdrawal fees on strategy-backed collateral; protocols where liquidation surplus is returned to the borrower; yield aggregators integrated into lending where fee application is inconsistent across exit paths

---

## CANTINA-LEND-008: force_repay_token_routing_error
- **Frequency**: ~5/279 findings
- **Severity**: HIGH
- **Code Shape**: `_forceRepay()` transfers tokens to `address(this)` instead of the transmuter/repayment target; `repayWithCollateral()` burns debt but sends collateral to wrong recipient; `liquidateBadDebt()` retrieves collateral but does not route it to cover the debt; `token.transferFrom(user, address(this), amount)` where `address(this)` should be `debtPool`
- **Detection Heuristic**:
  1. Grep for force repay, auto-repay, or repay-with-collateral functions
  2. Trace the token transfer destination: does it go to the debt holder / transmuter / pool, or to the contract itself?
  3. Check if tokens transferred to `address(this)` are subsequently forwarded to the correct destination (two-step transfer)
  4. Verify that in `liquidateBadDebt()`, seized collateral is converted and routed to actually cover the bad debt, not just moved
  5. Flag any repayment function where the transfer recipient is `address(this)` without a subsequent forwarding step
- **Failure Mode**: Protocol force-repays a user's debt by selling their collateral; tokens are sent to the lending contract itself instead of the transmuter or debt pool; debt is marked as repaid in accounting but the repayment tokens never reach the creditors; transmuter users cannot claim their redemptions; effectively a loss of funds equal to the force-repay amount
- **Common Contexts**: Synthetic asset protocols with transmuter mechanisms (Alchemix); lending protocols with auto-repay or liquidation-with-collateral-swap features; any two-token system where repayment requires routing through an intermediary contract

---

## CANTINA-LEND-009: depositor_dos_via_accounting_invariant_break
- **Frequency**: ~5/279 findings
- **Severity**: HIGH
- **Code Shape**: `totalDeposited += amount` on deposit but `totalDeposited -= shares` on withdrawal (unit mismatch); `increment = computeNewDeposits()` where `increment > total` causes underflow on subtraction; `balanceOf(address(this))` used alongside internal tracking creating divergence; any operation that makes `sum(individual_balances) > totalSupply`
- **Detection Heuristic**:
  1. Grep for global accounting variables: `totalDeposited`, `totalAssets`, `totalBorrow`, `totalSupply`
  2. Trace all increment and decrement paths: verify units are consistent (always assets or always shares, never mixed)
  3. Check if any code path can make `increment > total`, causing underflow on the next subtraction
  4. Verify that `balanceOf(address(this))` and internal tracking agree after every operation
  5. Flag paths where a single user's action can break the accounting invariant for ALL users
- **Failure Mode**: A single depositor's action causes `totalDeposited` to become inconsistent (e.g., increment exceeds total due to unit mismatch); subsequent operations underflow and revert; all deposits, withdrawals, borrows, and liquidations are permanently DoSed; entire protocol ceases to function until admin intervention
- **Common Contexts**: Lending protocols with complex deposit/withdrawal accounting; protocols tracking totals in both shares and assets with conversion between the two; synthetic asset protocols where multiple paths modify the same global counter

---

## CANTINA-LEND-010: grace_period_missing_after_parameter_change
- **Frequency**: ~5/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `setExternalLiquidity(newLower)` immediately makes existing positions undercollateralized; `unpause()` enables liquidations instantly for positions that became unhealthy during pause; `setCollateralFactor(newLower)` applies retroactively to all open positions; no `gracePeriod` or `adjustmentDelay` between parameter change and enforcement
- **Detection Heuristic**:
  1. Grep for admin setter functions that modify collateral factors, liquidation thresholds, external liquidity parameters, or pause states
  2. Check if the new parameter takes effect immediately or after a delay
  3. Verify that `unpause()` includes a grace period before liquidations are re-enabled
  4. Trace the impact: can a parameter change make previously healthy positions instantly liquidatable?
  5. Flag any setter where `oldParam -> newParam` can change position health status from HEALTHY to LIQUIDATABLE in the same block
- **Failure Mode**: Admin reduces collateral factor from 80% to 70%; all positions with LTV between 70-80% become instantly liquidatable; borrowers have zero time to add collateral or repay; MEV bots liquidate them in the same block as the parameter change; alternatively, protocol is unpaused and positions that drifted underwater during the pause are liquidated before users can react
- **Common Contexts**: Lending protocols with admin-adjustable risk parameters; pausable protocols where health can deteriorate during pause; any protocol where governance parameter changes apply retroactively to existing positions without a time-delayed transition

---

## CANTINA-LEND-011: collateral_wrapper_price_mismatch_on_liquidation
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**: `getQuote(wrappedNFT)` returns mid-point price during liquidation transfer instead of conservative price; `wrapperToken.unwrap()` can be blocked by owner making collateral worthless; `LP.removeLiquidity()` called during liquidation gets sandwiched; wrapped collateral valued at wrap-time price not current price
- **Detection Heuristic**:
  1. Grep for wrapped collateral types: ERC721 wrappers, LP position wrappers, receipt tokens used as collateral
  2. Check how the wrapper is priced during liquidation: is it using a mark-to-market price or a stale/manipulable price?
  3. Verify that wrapped collateral can always be unwrapped by the liquidator (no owner veto, no pause)
  4. Check if unwrapping during liquidation involves a DEX operation that can be sandwiched
  5. Flag any wrapper where the owner retains the ability to make the wrapper worthless post-collateralization
- **Failure Mode**: Borrower wraps an LP position as collateral; during liquidation, the wrapper's getQuote returns the mid-point (favorable) price instead of the conservative (unfavorable) price; liquidator pays more than the collateral is worth on the open market; alternatively, borrower retains control to remove liquidity from the underlying LP, making the wrapped collateral worthless while the wrapper still reports full value
- **Common Contexts**: NFT-collateral lending (VII Finance, Backed Protocol); LP-token-as-collateral protocols; any lending protocol accepting wrapped or receipt-token collateral where the wrapper introduces a pricing or control abstraction layer

---

## CANTINA-LEND-012: insolvent_position_liquidation_revert
- **Frequency**: ~6/279 findings
- **Severity**: HIGH
- **Code Shape**: `liquidate()` computes `seizedCollateral = debt * bonus / collateralPrice` which underflows when `collateralValue < debt * (1 - bonus)`; `require(collateral >= earmarkDebt + penalty)` reverts for deeply insolvent positions; `shares = convertToShares(debtAmount)` underflows when borrow index makes shares > available; no separate `liquidateInsolvent()` path
- **Detection Heuristic**:
  1. Grep for liquidation functions and test with `collateralValue < debtValue` (insolvent, not just undercollateralized)
  2. Check if the liquidation bonus calculation underflows or produces nonsensical results when LTV > 100%
  3. Verify there is a separate code path for insolvent positions (bad debt liquidation) vs. undercollateralized positions (normal liquidation)
  4. Trace `require` / `assert` statements in the liquidation path: which ones revert for deeply underwater positions?
  5. Flag if `liquidate()` assumes `collateralValue > debtValue * (1 + bonus)` without checking
- **Failure Mode**: Position becomes deeply insolvent (collateral worth 50% of debt); normal liquidation function tries to compute bonus-adjusted seizure amount; arithmetic underflows or a require statement fails; transaction reverts; position cannot be liquidated by anyone; bad debt grows as interest accrues; protocol lacks a fallback path to clear insolvent positions at a loss
- **Common Contexts**: Lending protocols without a dedicated bad debt liquidation mechanism; protocols where the standard liquidation path assumes profitable liquidation (collateral > debt + bonus); volatile collateral markets where positions can go deeply underwater between oracle updates
