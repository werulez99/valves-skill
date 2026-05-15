# Lending & Liquidation Patterns
> Extracted from 3,460 findings (500 sampled)
> Pattern count: 47

---

## LEND-001: oracle_spot_price_manipulation
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: `price = oracle.getPrice()` or `price = pool.slot0()` or `price = quoter.quoteExactInput()` used in collateral valuation, LTV checks, or liquidation triggers without TWAP, without staleness guard, or on AMM spot
- **Detection Heuristic**:
  1. Find all calls to `slot0()`, `quoteExactInput/Output()`, or single-source oracle reads in health/solvency/liquidation paths
  2. Check if price is used directly without TWAP or median
  3. Check if the oracle source is a low-liquidity AMM (Uniswap V3 spot, Curve spot) rather than Chainlink/Pyth
  4. Check if `observationCardinality` is sufficient for TWAP window
  5. Verify no staleness check (`block.timestamp - updatedAt <= maxStaleness`)
- **Failure Mode**: Attacker flash-loans to temporarily move spot price, triggering liquidations of healthy positions or preventing liquidations of unhealthy ones; or price is stale/manipulated causing wrong collateral valuation
- **Common Contexts**: CoreSaltyFeed using Chainlink spot, Oracle.sol using Uniswap V3 slot0, wstETH-ETH Curve LP oracle, Balancer BPT oracle using totalSupply(), Perpetual mark price vs spot price discrepancy

---

## LEND-002: liquidation_invariant_math_error
- **Frequency**: ~35/500
- **Severity**: HIGH
- **Code Shape**: `closingFactor = debt / (collateral * collateralizationRate)` or `liquidationBonus` computed with wrong operand order; `_amountOut` used as both assets and shares; share vs. amount conflation in solvency check
- **Detection Heuristic**:
  1. Find `computeClosingFactor`, `_computeAssetAmountToSolvency`, `_isSolvent`, `liquidationThreshold` functions
  2. Check unit consistency: are shares multiplied where amounts should be, or vice versa?
  3. Verify collateralizationRate is applied to numerator vs. denominator consistently
  4. Check if liquidation bonus calculation uses current LTV vs. collateral value
  5. Verify the closing factor caps at 1.0 and does not undercount debt
- **Failure Mode**: Protocol removes more/less debt than collateral seized; liquidation is not profitable so never executed; bad-debt accumulates silently
- **Common Contexts**: Tapioca BigBang `computeClosingFactor`, PoolTogether liquidate `_amountOut`, Tapioca `_isSolvent` shares vs amounts, Wise Lending partial collateral liquidation underpayment

---

## LEND-003: reentrancy_in_liquidation_flow
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: External call (transfer/safeTransfer/ERC721.safeTransferFrom/onERC721Received callback) before state update in `removeCollateral`, `startLiquidationAuction`, `purchaseLiquidationAuction`; double `nonReentrant` modifier across two calls in same call stack
- **Detection Heuristic**:
  1. Find all external calls in liquidation functions (token transfers, NFT callbacks, flash loan callbacks)
  2. Check if state (collateral balances, debt balances, auction state) is updated BEFORE or AFTER the external call
  3. Search for `onERC721Received` callbacks in the liquidation code path
  4. Check for double `nonReentrant` on functions that call each other (will deadlock rather than protect)
  5. Verify CEI (Checks-Effects-Interactions) pattern is followed throughout
- **Failure Mode**: Attacker re-enters `removeCollateral` to drain collateral before it is marked as seized; position owner reverts NFT callback to block liquidation; double nonReentrant causes legitimate liquidation to revert
- **Common Contexts**: Backed Protocol removeCollateral/startLiquidationAuction/purchaseLiquidationAuction, Revert Lend onERC721Received callback block, August double nonReentrant deadlock

---

## LEND-004: flashloan_health_check_bypass
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Health check (`hf >= 1`) evaluated in same transaction as flashloan repayment; auction recovery check uses live balance inflated by flash loan; governance early-execution voting power inflated by flash loan
- **Detection Heuristic**:
  1. Find all `healthFactor`, `isHealthy`, `_isSolvent` calls
  2. Check if any of these can be satisfied transiently within a single transaction
  3. Look for flashloan entry points (ERC3156, `onFlashLoan`, AAVE `executeOperation`) adjacent to health/collateral checks
  4. Verify that auction-recovery checks use time-weighted or committed state, not snapshot at function call time
- **Failure Mode**: Borrower takes flashloan, passes health check, exits loan and returns flash funds — net effect: unhealthy position cleared without repaying
- **Common Contexts**: ParaSpace auction recovery health check, Frankencoin challenge frontrun with de-leveraging, Aloe self-liquidation with high strain value, Aragon EarlyExecution voting

---

## LEND-005: liquidation_dos_via_collateral_transfer_failure
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: `liquidate()` calls `token.transfer(liquidator, amount)` or `safeTransferFrom` where token is blacklistable (USDC), reverts on zero-balance, or recipient is a reverting contract; liquidator must supply all tokens at once when pool is empty
- **Detection Heuristic**:
  1. Find all token transfers inside liquidation functions
  2. Check if the token is blacklistable (USDC/USDT) — does the blacklisting of borrower/liquidator block the call?
  3. Check if liquidity pool must have sufficient idle funds at liquidation time
  4. Check if `LendingPair.liquidateAccount` requires tokens not currently in pool (lent out)
  5. Verify that NFT collateral transfer cannot be blocked by recipient implementing reverting `onERC721Received`
- **Failure Mode**: Liquidation reverts for all healthy liquidators because borrower is blacklisted or pool is fully utilized; entire class of collateral becomes non-liquidatable
- **Common Contexts**: Wild Credit LendingPair.liquidateAccount (tokens lent out), Particle Protocol borrower on USDC blacklist, ZeroLend One liquidity shortage, Core Contracts StabilityPool lacking crvUSD

---

## LEND-006: interest_accrual_missing_in_liquidation
- **Frequency**: ~11/500
- **Severity**: HIGH
- **Code Shape**: `liquidate()` does not call `accrueInterest()` or `updateCumulativeInterestRate()` before computing debt; debt tokens transferred before interest rate recalculated; `lastUpdate` timestamp stale at point of liquidation
- **Detection Heuristic**:
  1. Find `liquidate` / `liquidateAccount` entry points
  2. Check the first few lines for `accrueInterest()`, `updateInterest()`, `syncInterest()` call — if absent, flag
  3. Verify `cumulativeInterestRate` is updated before debt math is performed
  4. Check if interest snapshots are reset/overwritten in edge cases (position increase resets accrued interest)
- **Failure Mode**: Liquidation uses stale debt amount — liquidated borrower pays less than owed; accrued interest is permanently lost; protocol becomes insolvent gradually
- **Common Contexts**: Wild Credit LendingPair.liquidateAccount (two separate audits), ParaSpace interest rates post debt-transfer, Adrena cumulative_interest_snapshot reset

---

## LEND-007: bad_debt_not_socialized_or_handled
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: After liquidation where `collateralValue < debtValue`, remaining debt is neither cleared nor distributed; `liquidate()` sets debt to 0 without marking bad debt in accounting; `_badDebtMapping` overwritten instead of accumulated
- **Detection Heuristic**:
  1. Find liquidation completion logic — what happens when `seized collateral < full debt`?
  2. Check if residual debt is zeroed out in borrower state but not reflected in pool total debt
  3. Verify `totalBorrow` / `outstandingDebt` is decremented by full debt amount even when collateral only covers partial
  4. Check `_badDebtMapping` update — is it `=` (overwrite) or `+=` (accumulate)?
  5. Look for "last to withdraw loses" scenarios where suppliers cannot withdraw due to accumulated hidden losses
- **Failure Mode**: Protocol appears solvent but suppliers cannot withdraw; bad debt accumulates off-books; last supplier absorbs all losses; `_badDebtMapping` is reset and earlier bad debt forgotten
- **Common Contexts**: BendDAO bad debt never handled, Frax Finance liquidate() missing bad debt mark, Core Contracts debt not cleared after liquidation, Term Structure _badDebtMapping overwrite, ZeroLend One last-supplier loss

---

## LEND-008: collateral_double_spend_post_liquidation
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: After liquidation, collateral mapping is not set to zero; liquidated borrower can call `withdraw` on same collateral that was seized; `collateralToken.transferFrom` not removing token from user's account
- **Detection Heuristic**:
  1. Find `liquidate` functions — check if `collateralBalance[user]` or equivalent mapping is zeroed
  2. After liquidation, verify the borrower cannot call `withdrawCollateral` or `removeCollateral` for the same tokens
  3. Check if NFT/ERC1155 token ID tracking is cleared post-liquidation
  4. Verify auction state is cleaned up on `liquidatorNFTClaim`
- **Failure Mode**: Borrower receives liquidation but can still withdraw the collateral that was seized; effectively receives full collateral + clears debt
- **Common Contexts**: Lumin collateral double-spend, Autonomint withdrawing liquidated collateral, Astaria liquidatorNFTClaim not clearing LienToken state

---

## LEND-009: liquidation_access_control_missing_or_broken
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: `liquidate()` has `public` visibility with no caller restrictions when `autoLiquidation = false`; `liquidateFrom()` is public; collateral commitment callable by anyone; `CommitCollateral` callable by any address
- **Detection Heuristic**:
  1. Find all liquidation entry points — check `msg.sender` guards
  2. Check if `autoLiquidation` flag disables but code path still executes
  3. Verify that only authorized parties can call collateral seizure / auction start
  4. Check if any liquidation helper that should be internal has `public`/`external` visibility
  5. Verify `updateSystemSnapshots_excludeCollRemainder` and similar state-update functions have access control
- **Failure Mode**: Anyone can liquidate any position without supplying repayment tokens; unauthorized parties can trigger collateral seizure; attacker drains protocol by calling privileged liquidation helpers
- **Common Contexts**: Sublime anyone-can-liquidate without autoLiquidation, MCDEX liquidateFrom public, Teller CollateralManager.commitCollateral, Apollon updateSystemSnapshots open

---

## LEND-010: ltv_collateral_ratio_calculation_error
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: LTV = `loanAmount * 1e18 / collateralValue` with wrong decimal normalization; `minterCollateral` calculated with wrong denominator; `userCollateralRatioMantissa` precision loss for non-18-decimal tokens; max LTV uses wrong variable
- **Detection Heuristic**:
  1. Find all LTV/collateral ratio computation sites
  2. Verify decimal normalization: collateral amount must be scaled to 18 decimals before division
  3. Check if `1e18` scaling is applied consistently on both sides of the inequality
  4. Verify `collateralizationRate` is applied to correct operand (numerator or denominator)
  5. Check for integer truncation that consistently favors borrower over protocol
- **Failure Mode**: Borrowers can borrow more than collateral value; positions pass health check when actually undercollateralized; users can mint more stablecoins than permitted
- **Common Contexts**: Folks Finance getLoanLiquidity wrong calculation, KRP-CDP max LTV calculation, SOFA minterCollateral, Surge userCollateralRatioMantissa, DittoETH mint without sufficient collateral

---

## LEND-011: liquidation_threshold_equals_borrow_ltv
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `borrowLTV == liquidationThreshold` with no buffer; position is liquidatable immediately after maximal borrow; `minOpeningMargin == liquidationThreshold`
- **Detection Heuristic**:
  1. Find `maxBorrow` / `borrowLTV` and `liquidationThreshold` / `minCollateralRatio` definitions
  2. Check if there is a gap: `liquidationThreshold > borrowLTV` must hold
  3. For perpetuals/margin: verify `initialMarginRatio > maintenanceMarginRatio`
  4. Test: after max borrow, can the position be liquidated in the next block without any price movement?
- **Failure Mode**: Borrowers can be liquidated immediately after legitimate max borrow; creates toxic user experience and potential for sandwich attacks; keepers open already-liquidatable positions
- **Common Contexts**: Backed Protocol H-04, Euler Vault Kit missing gap, Elfi H-1 keepers open already-liquidatable positions, Backed immediate liquidation after max debt

---

## LEND-012: partial_liquidation_not_possible_or_DoS
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `liquidate()` requires seizing all collateral at once; array of positions unbounded — iterating full list reverts out-of-gas; `liquidateAccount` fails when pool is partially utilized; `maxLiquidatable` wrong in cross-chain
- **Detection Heuristic**:
  1. Find liquidation functions — check if they force full liquidation or support partial
  2. Check unbounded loops over `positionIdList`, `creditLines`, `debtList` inside liquidation
  3. Verify partial liquidation correctly updates remaining debt and remaining collateral
  4. For cross-chain: verify `maxLiquidatable` uses correct local debt balance not stale remote state
- **Failure Mode**: Liquidators cannot liquidate large positions profitably; gas limit prevents liquidation of accounts with many positions; cross-chain liquidation blocked by wrong limit
- **Common Contexts**: Notional V3 partial liquidations impossible, Panoptic unbounded positionIdList, LEND cross-chain maxLiquidatable, Debt DAO ids array unbounded

---

## LEND-013: price_decimal_normalization_error
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: `price * amount` where price is 8-decimal Chainlink feed and amount is 18-decimal token; `liquidationReward` computed without dividing by `10**collateralDecimals`; `startingPrice` on Seaport wrong for sub-18-decimal tokens
- **Detection Heuristic**:
  1. Find all oracle price multiplications in collateral value / liquidation reward calculations
  2. Check oracle feed decimal (`decimals()` return) vs. token decimal
  3. Verify normalization: `(price * amount) / 10**oracleDecimals / 10**tokenDecimals` or equivalent
  4. Check if protocol hardcodes `1e18` when token might be `1e6` (USDC) or `1e8` (WBTC)
  5. Identify any `double denormalization` where normalizer is applied twice
- **Failure Mode**: Collateral value over/under-stated by factor of 10^N; liquidation rewards wrong by same factor; attackers exploit mispricing to borrow far more than allowed
- **Common Contexts**: Cryptex liquidationReward missing decimal, Zaros withdrawMarginUsd sub-18 tokens, Astaria wrong starting price for sub-18, Yieldoor liquidation fee decimal handling, Synonym double denormalization

---

## LEND-014: stale_oracle_data_no_staleness_check
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `(, int256 price,,,) = feed.latestRoundData()` without checking `updatedAt`; `staleness > maxStaleness` check absent; circuit-breaker price used after circuit-breaker trips; excessive staleness buffer (hours instead of minutes)
- **Detection Heuristic**:
  1. Find all `latestRoundData()` calls
  2. Check if `updatedAt` is stored and compared to `block.timestamp`
  3. Verify `maxStaleness` constant is reasonable for asset volatility (e.g., ≤ 1 hour for crypto)
  4. Check if Pyth price confidence/exponent is validated
  5. Verify price is positive (not zero or negative)
- **Failure Mode**: Protocol uses hours-old price during market volatility; positions that should be liquidated are treated as healthy; stale Pyth price used in LP pool attack
- **Common Contexts**: Bima excessive staleness buffer, Ion Protocol ineffective exchange rate bound, Sublime PriceOracle no outlier filter, Perpetual two-Pyth-price attack

---

## LEND-015: liquidation_bonus_zero_or_inverted
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `liquidationBonus = 0` when `currentLTV > 1e18`; bonus calculated as negative when position is deep underwater; discount profile returns 0 for non-zero discounts; liquidationInitialAsk set too low making auction unprofitable
- **Detection Heuristic**:
  1. Find liquidation bonus / incentive calculation
  2. Test with LTV at 1.0 and LTV > 1.0: does bonus remain positive?
  3. Check if discount is subtracted from or added to the correct side
  4. Verify `liquidationInitialAsk` lower bound is strictly enforced during loan creation
  5. Check if bonus can be zero when 0% discount profile is used
- **Failure Mode**: No liquidator will liquidate because it is not profitable; undercollateralized positions persist indefinitely; protocol becomes insolvent
- **Common Contexts**: Cedro Finance bonus 0% at LTV > 1, Mochi discount profile bug, Astaria liquidationInitialAsk too low, Size liquidator profit calculation wrong

---

## LEND-016: state_not_updated_after_liquidation
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: `totalBorrow` not decremented after BigBang liquidation; `totalCdsDepositedAmount` not updated after CDS liquidation; global position state not synced after Synthetix position close; `outstandingValues` mis-accounted after fee distribution
- **Detection Heuristic**:
  1. Find all post-liquidation state update steps
  2. Verify `totalBorrow`, `totalDebt`, `totalCollateral`, `outstandingValues` are all decremented by correct amounts
  3. Check if pending fees / accrued interest are cleared from state
  4. Look for cross-chain state sync — does the liquidation on chain A update chain B's global state?
  5. Check if fee accounting variables are updated atomically with the liquidation
- **Failure Mode**: Protocol over-reports outstanding debt; subsequent calculations use stale totals; solvency checks become inaccurate; interest rates miscalculated
- **Common Contexts**: Tapioca totalBorrow not updated, Autonomint global state not updated after Synthetix close, Gondi outstandingValues hardcoded to 0, Autonomous cross-chain sync overwrite

---

## LEND-017: liquidation_frontrunning_or_griefing
- **Frequency**: ~15/500
- **Severity**: HIGH
- **Code Shape**: Borrower frontruns `liquidate()` with `deposit(minAmount)` to reset health; borrower frontruns with `transferAccount` to move unhealthy account to new owner; borrower increments nonce before liquidation arrives; borrower self-liquidates with high strain to clear warning flag
- **Detection Heuristic**:
  1. Find what action a borrower can take in the same block as a liquidation call
  2. Check if depositing dust (minimum amount) resets the liquidation eligibility timer
  3. Check if account transfer is permissioned/delayed
  4. Verify nonce invalidation does not cancel a pending liquidation signature
  5. Check if self-liquidation (as the liquidator) is restricted
- **Failure Mode**: Undercollateralized positions never actually get liquidated despite liquidators trying; borrowers exploit griefing window to drain collateral; protocol insolvency accumulates
- **Common Contexts**: Salty.IO dust deposit evasion, Gearbox account transfer to new address, Frankencoin challenge frontrun, DittoETH last-short-record avoidance, Symmetrical nonce invalidation

---

## LEND-018: auction_state_management_error
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Auction cannot be terminated after full liquidation (stuck state); no-bid auction does not clear LienToken state; `liquidationAccountant` claimed at any time before auction ends; auction ends in wrong epoch; `_isLiquidation` mapping not deleted after reserve
- **Detection Heuristic**:
  1. Find all auction terminal states — what clears the auction struct/mapping?
  2. Check if the auction can become permanently stuck (no bidder, full liquidation, no-bid termination path)
  3. Verify `liquidatorNFTClaim` always clears the corresponding LienToken state
  4. Check epoch boundary conditions — can auction span epochs incorrectly?
  5. Verify `_isLiquidation` / auction flags are reset on every exit path (bid, cancel, no-bid)
- **Failure Mode**: Collateral permanently locked in contract; LienToken state inconsistency prevents future loans on same collateral; tax incorrectly assessed on future sales
- **Common Contexts**: Lyra Finance / Derive stuck auctions, Astaria no-bid auction state not cleared, Flayer _isLiquidation not deleted, Astaria liquidatorNFTClaim epoch error

---

## LEND-019: wrong_collateral_recipient_in_liquidation
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `liquidateDefaultedLoanWithIncentive` sends collateral to `borrower` instead of `liquidator`; ETH refund sent to wrong recipient; kerosene collateral not transferred to liquidator; wrong `srcToken` used in cross-chain liquidation
- **Detection Heuristic**:
  1. Find all `transfer`/`safeTransfer` calls inside liquidation functions
  2. Verify each transfer recipient: collateral → liquidator, surplus collateral → borrower
  3. For cross-chain: verify token address used for cross-chain message matches local token
  4. Check ETH refund path in Type 1 liquidation flows
- **Failure Mode**: Liquidator spends repayment tokens but receives no collateral (loses money); surplus collateral sent to wrong address; ETH refund locked in contract
- **Common Contexts**: Teller liquidateDefaultedLoanWithIncentive, Autonomint Ether refund wrong address, DYAD kerosene not moved, LEND wrong srcToken cross-chain

---

## LEND-020: shares_vs_assets_confusion_in_collateral_accounting
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `_amountOut` used as both shares and assets in `liquidate()`; `exchangeRateStored()` not called before using cToken as collateral; yieldFeeBalance in shares passed where assets expected; reward calculation uses shares where LP amount needed
- **Detection Heuristic**:
  1. Find all conversions between shares and assets in liquidation/collateral functions
  2. Check if ERC-4626 `convertToAssets` / `convertToShares` is called before using a vault token in collateral math
  3. Verify `exchangeRateStored` is fresh (up-to-date) when cToken is collateral
  4. Search for parameter named `_amount` that is both used for assets and shares without explicit conversion
- **Failure Mode**: Collateral valued at wrong amount (1:1 share:asset assumption incorrect post-yield); liquidation seizes too much or too little; vault math diverges from actual balances
- **Common Contexts**: PoolTogether _amountOut dual-use, dForce iETH.exchangeRateStored stale, BendDAO yield share mismatch, Aries Markets share settlement wrong

---

## LEND-021: cross_chain_liquidation_desync
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain borrow ignores debt on other chain in collateral check; LayerZero messages can arrive out of order overwriting global state; cross-chain liquidation uses seize amount for debt reduction instead of repay amount; wrong lToken address in cross-chain message
- **Detection Heuristic**:
  1. Find all cross-chain messaging points in borrow/liquidation flows
  2. Check if collateral health is computed with knowledge of all chains' debt or only local debt
  3. Verify message sequencing: can a later message overwrite a correct earlier state?
  4. Check if liquidation sends `collateralSeized` or `debtRepaid` as the debt reduction amount — must be repaid amount
  5. Verify token address mapping across chains is correct and bidirectional
- **Failure Mode**: Borrower borrows on chain A without chain B debt counted → undercollateralized; liquidation reduces wrong amount of debt; cross-chain state permanently desynced
- **Common Contexts**: LEND cross-chain ignores existing debt, Autonomint LayerZero global state overwrite, LEND cross-chain seize vs repay, LEND wrong lToken address

---

## LEND-022: missing_gap_or_paused_state_asymmetry
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `repay()` is paused but `liquidate()` is active, trapping borrowers; `pause()` on ReserveFund callable by anyone; shutdown vault allows new lien commitments; recovery mode triggers liquidation of positions that passed pre-recovery health check
- **Detection Heuristic**:
  1. Check every paused state: is the pause symmetric (liquidate off when repay off)?
  2. Verify `pause()` / `unpause()` are access-controlled
  3. Check if shutdown/killed state prevents new borrows and liquidations consistently
  4. Verify recovery mode cannot liquidate positions that were healthy before recovery mode activated
- **Failure Mode**: Borrowers cannot repay but can be liquidated; anyone freezes protocol liquidity coverage; new debt created after shutdown; recovery mode weaponized to liquidate healthy troves
- **Common Contexts**: Cedro Finance repay-paused/liquidate-active, Secured Finance anyone-can-pause, Astaria shutdown vault still accepting liens, Opus recovery mode weaponized

---

## LEND-023: liquidation_profit_distribution_error
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: CDS depositors never receive liquidation profit; liquidation profit directly added to `totalCdsDepositedAmount` instead of profit pool; StabilityPool depositor rewards stolen by attacker who deposits before liquidation and withdraws after
- **Detection Heuristic**:
  1. Find liquidation profit distribution logic
  2. Verify profit goes to correct recipient (stability pool vs. individual liquidator vs. CDS depositors)
  3. Check for timing attack: can an attacker deposit into StabilityPool just before a liquidation and withdraw after to steal profit?
  4. Verify `abond` holders receive proportional share based on time of deposit
  5. Check for front-running opportunity on liquidation profit claim
- **Failure Mode**: Intended beneficiaries receive no liquidation rewards; attacker steals stability pool profit; late depositors steal from early depositors
- **Common Contexts**: Autonomint CDS profit not distributed, Threshold StabilityPool profit theft, Autonomint Type 1 CDS profit added wrong, Autonomint late abond holders steal

---

## LEND-024: dust_position_exploit_and_minimum_size
- **Frequency**: ~6/500
- **Severity**: HIGH/MEDIUM
- **Code Shape**: No minimum CDP size check; dust CDPs unprofitable to liquidate (gas > bonus); borrower creates array of 1-debt credit IDs to prevent `liquidateAll` from iterating; liquidationInitialAsk set at 1 wei to block future borrowers via array slot
- **Detection Heuristic**:
  1. Find CDP / borrow creation functions — is there a minimum collateral/debt requirement?
  2. Check if liquidation is still profitable at minimum position size after gas costs
  3. Look for arrays of open credit lines — can borrower fill them to prevent new liquidatable entries?
  4. Verify liquidationInitialAsk has a realistic lower bound (not just > 0)
- **Failure Mode**: Protocol accumulates many dust positions that are uneconomical to liquidate; attacker creates dust CDPs to prevent redemptions; unbounded array prevents system operation
- **Common Contexts**: BadgerDAO dust CDPs, Astaria liquidationInitialAsk block future borrowers, Debt DAO ids array filled to block new borrows

---

## LEND-025: position_health_check_uses_wrong_price_or_wrong_token
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Health check uses `tokenB.price` when it should use `tokenA.price`; health check uses oracle spot price instead of perpetual mark price; Uniswap V3 NFT LP position valued by wrong tick/wrong formula
- **Detection Heuristic**:
  1. Find `healthFactor`, `isHealthy`, `isLiquidatable` computations
  2. Trace the price variable back to its source — is it the correct asset?
  3. For perps: verify mark price (not index/spot) is used for liquidation trigger
  4. For LP tokens: verify the LP token value formula accounts for impermanent loss, concentrated liquidity range, and correct token ordering
  5. Check if the Uniswap V3 NFT valuation correctly handles out-of-range positions
- **Failure Mode**: Healthy positions liquidated; undercollateralized positions pass health check; wrong token price used results in wrong LTV
- **Common Contexts**: Wild Credit tokenB vs tokenA, Dipcoin Vault NAV spot vs mark price, ParaSpace wrong Uniswap V3 NFT valuation, BlueB pending CRV not counted

---

## LEND-026: incomplete_liquidation_implementation
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `liquidate()` exists but does not clear debt; does not transfer collateral; does not update borrow balance; liquidation function never assigns `orderStore`; incomplete state machine (`LIQUIDATION_IN_PROGRESS` unreachable)
- **Detection Heuristic**:
  1. Find `liquidate` function — trace all state changes it makes
  2. Verify: (a) debt zeroed for borrower, (b) collateral transferred to liquidator, (c) global totals updated, (d) any required events emitted
  3. Check if liquidation handler initializes all required references (e.g., orderStore)
  4. Verify state machine: all states reachable? All transitions valid?
- **Failure Mode**: Liquidation function runs but leaves protocol in inconsistent state; collateral not transferred; debt persists post-liquidation
- **Common Contexts**: Pike incomplete liquidation, GMX LIQH-1 uninitialized orderStore, tBTC unreachable LIQUIDATION_IN_PROGRESS, Argo liquidation remarking

---

## LEND-027: insolvency_via_donation_or_inflation_attack
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: First depositor mints 1 share, donates large amount, inflates share price — subsequent depositors lose precision; vault tracks assets via internal storage not actual balance — attacker donates to inflate `effectiveCollateralValue`; Uniswap V4 empty tick inflation
- **Detection Heuristic**:
  1. Find vault share minting on first deposit — check if virtual shares / dead shares are used
  2. Check if collateral value is read from actual token.balanceOf() or from internal accounting
  3. Verify no `effectiveCollateralValue` can be inflated by external donations
  4. Check if AMM tick shares are priced from total supply (manipulable) or from invariant (safe)
- **Failure Mode**: New depositors lose funds due to share price inflation; borrowers inflate collateral value to borrow more; liquidation cannot recover correct collateral amount
- **Common Contexts**: Narwhal Finance first-depositor share inflation, Folks Finance effectiveCollateralValue inflation, Curve empty tick inflation, TermMax donation attack

---

## LEND-028: missing_collateral_flag_or_misclassification
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Deposit not marked as collateral but still subject to liquidation; `registerAsset()` overwrites existing `_assetClass` for different asset; `updateRegisteredErc20()` updates wrong token's oracle and LTV; eMode `isInEMode` logic broken — wrong price source used
- **Detection Heuristic**:
  1. Find collateral registration / enablement functions
  2. Verify that `enterMarket` / collateral flag is required before an asset can be liquidated
  3. Check if `registerAsset` / `updateRegisteredErc20` uses a unique key per asset (not a shared index)
  4. For eMode: verify `priceSource != address(0)` before using eMode price
- **Failure Mode**: Non-collateral deposits seized in liquidation; wrong token's oracle used for LTV check; eMode asset misconfigured → protocol uses zero address price
- **Common Contexts**: Aave deposits not marked as collateral, Mochi registerAsset overwrite, Interest Protocol wrong token update, Morpho eMode address(0) price

---

## LEND-029: liquidation_block_via_reverting_recipient
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Collateral sent to borrower's contract address that can revert `receive()` / `fallback()`; `payable.transfer` used (2300 gas limit) to smart contract borrowers; reward address that always reverts blocks WETH distribution; lien buyer transfers lien to reverting address
- **Detection Heuristic**:
  1. Find all `transfer()` / `send()` / low-level `.call{value:}` in liquidation paths
  2. Check if `.transfer()` (2300 gas) is used instead of `.call{value: }` — fails for smart contract recipients
  3. Verify there is a pull-payment pattern for ETH distribution (not push)
  4. Check if any callback-triggering transfer (ERC777 `tokensReceived`, ERC721 `onReceived`) is in the liquidation hot path
- **Failure Mode**: Liquidation permanently reverts for borrowers using smart contract accounts; DoS on liquidation system; WETH stuck in collector contract
- **Common Contexts**: OpenLeverage payable.transfer, Stader malicious reward address, Gearbox reverting CreditAccount, Astaria malicious lien buyer DoS

---

## LEND-030: nonce_or_signature_replay_in_liquidation
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: `liquidatePartyA` signature lacks nonce — replayable; authentication token reusable after transaction reverts; nonce not incremented during liquidation functions; commitment can be combined with self-registered vault to steal funds
- **Detection Heuristic**:
  1. Find all signatures / authentication tokens used in liquidation flows
  2. Verify each signature includes a nonce that is consumed on use
  3. Check if nonce is incremented in the liquidation function itself (not just in normal operations)
  4. Verify failed transactions invalidate their authentication tokens
  5. Check if any vault/commitment combination can be replayed by third parties
- **Failure Mode**: Liquidation signature replayed to liquidate same position multiple times; attacker uses stale auth token to authorize unauthorized actions; unfair liquidation with replayed old price signature
- **Common Contexts**: Symmetrical liquidatePartyA no nonce, Term Finance auth token reuse, Symmetrical nonce not incremented in liquidation, Astaria commitment replay

---

## LEND-031: overcollateralization_check_bypass_via_configuration
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `_requireValidAdjustmentInCurrentMode` skipped for non-mintList users; owner can bypass time checks on market operations; `withdrawTo` checks margin without syncing position first; swaps available during active liquidation allowing collateral removal
- **Detection Heuristic**:
  1. Find all modifier/check bypass paths in borrower operation functions
  2. Check if `mintList` / whitelist status affects which invariants are enforced
  3. Verify `withdrawTo` / `adjustPosition` syncs position before checking margin
  4. Check if positions under active liquidation can still trade/withdraw
- **Failure Mode**: Users bypass collateral requirements by exploiting list membership; margin check uses stale data allowing overleveraged withdrawal; position drained during its own liquidation
- **Common Contexts**: Threshold _requireValidAdjustmentInCurrentMode bypass, Holdefi owner bypass time checks, Perennial withdrawTo no sync, Sharwafinance swaps during liquidation

---

## LEND-032: incorrect_interest_rate_or_fee_calculation
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: Interest amplified by 1000x due to wrong constant; fee precision loss (integer division before multiplication); APR calculated incorrectly on every swap execution; interest calculated as 0 due to rounding; stable borrow rate critical bug resetting global rates
- **Detection Heuristic**:
  1. Find `_debt_interest_since_last_update` / `calculateInterest` / `getInterestRate` functions
  2. Check constants: is there a spurious `* 1000` or `/ 1000` that should not be there?
  3. Verify order of operations: multiplication before division to preserve precision
  4. Check if interest can round to 0 for small positions over short time windows
  5. Verify the formula uses seconds-based time delta (not block-based for EVM)
- **Failure Mode**: Borrowers pay 1000x too much or too little interest; fees never accrue; protocol revenue stolen via fee precision exploits; stable rate global reset destabilizes market
- **Common Contexts**: Unstoppable 1000x amplification, Velar fee precision loss, TermMax APR calculation, Filament interest rounds to 0, AAVE stable rate critical bug

---

## LEND-033: liquidatable_position_cannot_be_created_due_to_bug
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Notional Curve vault liquidation impossible for some pool types; CErc721 liquidation always reverts if interest state up-to-date; vault positions created ineligible for liquidation (no mechanism to set claimable factor); Junior Bond liquidation at purchase time always reverts
- **Detection Heuristic**:
  1. Find `liquidate` logic for each collateral type — are there code paths that always revert?
  2. For multi-asset protocols: test each collateral type independently in liquidation
  3. Check if there is a required precondition (config flag, claimable factor, ordering constraint) that has no setter
  4. Verify interest-accrual-up-to-date does not cause division by zero or invariant violation in liquidation
- **Failure Mode**: Entire class of positions can never be liquidated regardless of health; protocol accumulates unrecoverable bad debt for specific collateral types
- **Common Contexts**: Notional Curve pools, Fungify CErc721, GMX claimable factor no setter, BarnBridge Junior Bond

---

## LEND-034: slippage_protection_absent_in_collateral_swap
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `autoRedemption` / repayment swap uses `amountOutMin = 0`; slippage params derived from manipulable `slot0()` at call time; ADL operations no slippage protection; swap in open/close/reduce position sandwichable
- **Detection Heuristic**:
  1. Find all DEX swap calls in liquidation / collateral redemption / repayment flows
  2. Check `amountOutMin` parameter — is it 0, or derived from a manipulable on-chain source?
  3. Verify slippage bounds are set by protocol or by user input validated at submission time (not at execution time)
  4. Check if swap parameters can be influenced by the caller to extract value
- **Failure Mode**: Liquidation swap MEV-sandwiched; protocol pays maximum slippage on every auto-redemption; vaults made erroneously liquidatable via incorrect swap path quoting
- **Common Contexts**: The Standard autoRedemption, Real Wagmi repayment slot0 slippage, GMX ADL no slippage, Cork Protocol H-1 lack of slippage

---

## LEND-035: unchecked_array_length_or_loop_bounds_in_liquidation
- **Frequency**: ~6/500
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `checkLiquidatableAccounts()` for-loop with wrong index bounds causes out-of-bounds access; liquidation arrays passed as input with no length validation; `removeProviderLiquidation` removes value but not array element causing unbounded growth
- **Detection Heuristic**:
  1. Find all loops in liquidation functions
  2. Verify loop bounds use `.length` of the correct array
  3. Check if user-supplied arrays are length-validated before iteration
  4. Find delete operations on arrays — verify element is swapped-and-popped, not just zeroed (otherwise array grows unboundedly)
- **Failure Mode**: Out-of-bounds array access reverts all liquidation calls; unbounded array growth causes eventual DoS; missing length check allows malformed input to corrupt state
- **Common Contexts**: Zaros LiquidationBranch wrong loop bounds, Synonym missing length check, Eqifi array grows without element removal

---

## LEND-036: emode_or_isolation_mode_misconfiguration
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: eMode implementation broken — wrong LTV tiers applied; Morpho enters isolation mode incorrectly; Morpho LTV=0 collateral enables DoS on supply/borrow/liquidate; minipools borrow from non-borrowable reserves
- **Detection Heuristic**:
  1. Find eMode / isolation mode entry conditions
  2. Verify correct LTV and liquidation threshold are used in each mode
  3. Check if enabling a LTV=0 asset as collateral is gated
  4. Verify reserve borrowable flag is checked before allowing borrow against that reserve
  5. Check if isolation mode debt ceiling is enforced correctly
- **Failure Mode**: Users borrow against wrong LTV; protocol enters isolation mode unexpectedly breaking other operations; entire lending market DoS via LTV=0 collateral injection
- **Common Contexts**: Index eMode broken, Morpho isolation mode, Morpho LTV=0 DoS, Astera/Cod3x non-borrowable reserve

---

## LEND-037: liquidation_prevented_by_position_state_inconsistency
- **Frequency**: ~9/500
- **Severity**: HIGH
- **Code Shape**: Short record that is partially filled without a short order cannot be liquidated or exited; position in wrong state (non-existent, closedByLiquidation) causes strategy malfunction; `maturity` cleared prematurely on secondary debt shares; position list mapping not deleted on reserve
- **Detection Heuristic**:
  1. Find all position state enums and transitions
  2. Check if any combination of partial-fill + status creates an unliquidatable state
  3. Verify position can be liquidated from every state where it should be (not just `active`)
  4. Check if storage is correctly cleaned when position changes state
- **Failure Mode**: Positions stuck in inconsistent state — cannot be liquidated, cannot be exited; funds permanently locked
- **Common Contexts**: DittoETH partially filled Short Records, Yearn malfunction on liquidated trove, Notional V3 maturity premature clear, Flayer listing not deleted

---

## LEND-038: collateral_value_overestimation_via_pending_state
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: TVL calculation includes pending withdrawal assets as available collateral; collateral deposited in external vaults (Gamma, Hypervisor) not counted in liquidation value; pending position fees not included in net value computation; collateral double-counted via vault licensing
- **Detection Heuristic**:
  1. Find TVL / `getTotalAssetTVL` / `getAccountYieldBalance` functions
  2. Check if pending withdrawals are subtracted from available collateral
  3. Verify collateral in external protocols (Gamma, Yearn, Convex) is included in health calculation
  4. Check for double-counting when vault licenses are re-used or stacked
  5. Verify pending fees / PnL are included in margin/health calculation before liquidation check
- **Failure Mode**: Borrower appears overcollateralized due to overstated TVL; true collateral value is lower; protocol becomes undercollateralized before liquidation triggers
- **Common Contexts**: Elytra TVL includes pending withdrawals, The Standard Gamma vault collateral not counted, Stella pending liquidity fees, DYAD kerosine double-counting

---

## LEND-039: liquidation_price_feed_using_wrong_invariant
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: BPT price uses `totalSupply()` instead of invariant-based price; Balancer composable pool uses wrong invariant formula; Pendle SY token assumed 1:1 with yield token; Stable BPT valuation incorrect allowing insolvency exploit
- **Detection Heuristic**:
  1. Find LP/BPT token pricing functions
  2. For Balancer: verify weighted pool vs. composable pool invariant is used correctly
  3. Check if `totalSupply()` is used to price pool shares — this is manipulable via minting
  4. For Pendle: check if SY→PT conversion rate is properly fetched, not assumed 1:1
  5. For Curve: verify the Newton-Raphson `get_y` / `get_d` implementation matches canonical Curve
- **Failure Mode**: LP token collateral mispriced → wrong liquidation threshold; attacker borrows against inflated LP value causing bad debt
- **Common Contexts**: OpalProtocol BPT totalSupply(), Notional Balancer composable invariant, Blueberry Stable BPT, Notional Exponent Pendle SY assumption

---

## LEND-040: debt_ceiling_or_borrowing_limit_bypass
- **Frequency**: ~9/500
- **Severity**: HIGH
- **Code Shape**: `buyLoan()` bypasses `maxLoanRatio` check; user borrows → deposits → borrows more (circular); collateral of previous position used for new borrow without clearing; `getLoanLiquidity` health calculation wrong allowing unlimited borrow
- **Detection Heuristic**:
  1. Find all paths to increase borrow beyond normal `borrow()` function (buyLoan, flash, leveraged position)
  2. Verify `maxLoanRatio` / debt ceiling is checked on every debt-increasing path
  3. Check if depositing borrowed assets back into the protocol inflates collateral
  4. Verify leveraged position opening does not incorrectly count previous collateral
- **Failure Mode**: Attacker borrows far beyond collateral value; protocol depleted; self-referential borrowing creates phantom collateral
- **Common Contexts**: Beedle buyLoan bypass, DeFiner circular borrow, Rubicon previous position collateral, Folks Finance getLoanLiquidity wrong

---

## LEND-041: liquidation_accounting_rounding_errors
- **Frequency**: ~10/500
- **Severity**: HIGH/MEDIUM
- **Code Shape**: Port Finance liquidate rounds up collateral given to liquidator (excess collateral liquidated); LTV rounded in wrong direction causing systematic overborrowing; interest rounds to 0 for small/short positions; collateral remainder cap calculation wrong
- **Detection Heuristic**:
  1. Find all division operations in liquidation and collateral calculation paths
  2. Verify rounding direction: amounts owed to protocol should round UP, amounts given to users should round DOWN
  3. Check if small positions / short intervals produce zero interest due to integer truncation
  4. Verify `remainderCap` calculation correctly limits how much collateral can be retained post-liquidation
- **Failure Mode**: Liquidator receives more collateral than justified; borrower can retain collateral beyond the permitted remainder; systematic underpayment of interest
- **Common Contexts**: Port Finance excess collateral rounding, Size collateral remainder cap, Filament interest rounds to 0, Foundry DeFi Stablecoin liquidation arithmetic

---

## LEND-042: p2p_rate_or_pool_rate_snapshot_manipulation
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: P2P rate is a lazy-updated snapshot manipulable by executing operations to shift it; `poolAPR` or `market.apr` recalculated on every swap allowing manipulation; interest rate manipulated via deposit-borrow-withdraw cycle
- **Detection Heuristic**:
  1. Find interest rate update triggers — is the rate updated lazily or on demand?
  2. Check if a single transaction can move the rate significantly (large deposit + borrow + withdraw)
  3. Verify rate updates are time-weighted or use checkpointing that resists single-block manipulation
  4. For P2P: check if the rate snapshot lags reality and can be exploited in arbitrage
- **Failure Mode**: Attacker manipulates interest rate to pay near-zero for large borrows; protocol loses interest revenue; other users subsidize the attack
- **Common Contexts**: Morpho P2P rate lazy snapshot, TermMax APR per-swap recalculation, Teller Finance interest rate manipulation via deposit/borrow/withdraw

---

## LEND-043: collateral_locked_due_to_underflow_or_overflow
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Underflow in `payOff()` permanently locks assets; overflow in `liquidationInitialAsk > 2**88-1` causes revert; underflow in `_splitWithdrawRequest` creates invalid withdraw requests; Astaria deadlock when underlying token has < 18 decimals
- **Detection Heuristic**:
  1. Find arithmetic operations in liquidation/auction functions that could underflow (Solidity < 0.8) or overflow
  2. Check for explicit type casts that truncate: `uint88(value)` where value may exceed uint88
  3. Verify subtraction is protected: `a - b` where b could > a in edge cases
  4. For < 18 decimal tokens: trace all fixed-point math for precision loss that creates irrecoverable states
- **Failure Mode**: Transaction reverts leaving collateral permanently locked in contract; state machine stuck; users cannot exit or be liquidated
- **Common Contexts**: Astaria liquidationInitialAsk uint88 overflow, Hyperhyper payOff underflow, Notional _splitWithdrawRequest, Astaria sub-18-decimal deadlock

---

## LEND-044: self_referential_or_proxy_liquidation_creating_bad_debt
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Proxy-based self-liquidation — borrower acts as their own liquidator, pays themselves collateral without actual debt repayment; borrower calls `seize` on own account through a proxy; Argo hot-potato `LiquidateIOU` returned without ability requirement
- **Detection Heuristic**:
  1. Find if liquidator and borrower can be the same entity or controlled entities
  2. Check if `msg.sender == borrower` is prohibited in the liquidation function
  3. For Sui/Move: verify liquidation hot-potato has `store` ability preventing the attacker from dropping it
  4. Check if borrower can front-run liquidation to make themselves profitable liquidator of their own position
- **Failure Mode**: Borrower liquidates themselves, clears debt, retains collateral, leaves bad debt for lenders
- **Common Contexts**: Licredity proxy self-liquidation, Argo broken liquidation access control (hot potato no abilities)

---

## LEND-045: stale_position_fees_or_pending_pnl_not_accounted
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Intent fees not counted in collateral when user withdraws; pending position fees from Uniswap V3 read from stale storage; position net value uses outdated fees; funding fees applied to wrong market scope; `claimAccountRewards` missing param check
- **Detection Heuristic**:
  1. Find all health / margin check computations
  2. Verify that pending unclaimed fees, funding fees, and PnL are included (or conservatively excluded) in health calculation
  3. Check if Uniswap V3 fee accumulators are updated before reading tokensOwed
  4. Verify funding rate is calculated over correct market scope (not just Oracle Maker skew)
- **Failure Mode**: User withdraws all collateral ignoring pending fees → position becomes undercollateralized; protocol pays more funding than collected; position fees go to wrong party
- **Common Contexts**: Perennial pending fees in intent orders, Stella pending liquidity fees stale, Elfi position net value outdated fees, Perennial funding rate scope

---

## LEND-046: liquidation_collateral_priority_order_corruption
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: `removeCollateralFromLiquidationPriority` leaves gap in priority array without re-indexing; collateral type removed from middle of array but index references still point at wrong position; liquidation seizes wrong asset first
- **Detection Heuristic**:
  1. Find functions that modify the collateral liquidation priority array
  2. Check if remove operations shift subsequent elements or leave gaps
  3. Verify that after removal, remaining indices are still consecutive and point to correct collateral
  4. Test: remove middle element → is the last element now accessible at its original index?
- **Failure Mode**: Wrong collateral type seized in liquidation (lower-value first when higher-value should be first); some collateral types permanently inaccessible; liquidation reverts due to index out of bounds
- **Common Contexts**: Zaros GlobalConfiguration.removeCollateralFromLiquidationPriority

---

## LEND-047: permit_or_approval_not_checked_in_collateral_operations
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: `multiHopBuyCollateral` allows anyone to buy collateral on behalf of user without allowance; `approvedCreditor` not reset after account transfer enabling theft; `V3Vault` permit does not validate receiving token is the expected token; `_repayCredit()` publicly accessible
- **Detection Heuristic**:
  1. Find `buyCollateral` / `on-behalf-of` functions — check `msg.sender` vs. allowance
  2. Verify `approvedCreditor` / `allowance` mappings are cleared on account state transitions (transfer, liquidation)
  3. Check permit validation: does it verify the token address being permitted matches the expected token?
  4. Verify internal helper functions used in collateral operations have `internal` visibility
- **Failure Mode**: Attacker buys user's collateral without authorization; approved creditor retains access after account transfer and steals liquidation proceeds; anyone repays credit on behalf of others manipulating debt state
- **Common Contexts**: Tapioca multiHopBuyCollateral, Arcadia approvedCreditor not reset, Revert Lend V3Vault permit, Archi Finance _repayCredit public

---

## LEND-048: governance_or_admin_parameter_enabling_collateral_theft
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Malicious oracle supplied at loan creation time allows borrower to avoid liquidation; lender changes loan parameters mid-term to trigger liquidation and seize collateral; admin sets arbitrary swap fees to extract arbitrage; vault manager drains all user deposits
- **Detection Heuristic**:
  1. Find all admin-settable parameters that affect collateral value or liquidation conditions
  2. Check if oracle address is user-supplied at creation time with no whitelist validation
  3. Verify lender cannot unilaterally change loan terms after creation
  4. Check if admin can set fee parameters to 100% or negative values
  5. Verify `sweep` / admin withdrawal cannot remove pool's BPT or core liquidity tokens
- **Failure Mode**: Malicious lender forces liquidation by changing terms; malicious admin drains deposits; user supplies malicious oracle that always returns safe price for their position
- **Common Contexts**: Abracadabra malicious oracle, Abracadabra lender parameter change, Gauntlet sweep BPT, Gauntlet admin swap fees, Orbital Finance malicious operator

---

## LEND-049: cross_chain_state_used_for_local_liquidation
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Liquidation uses cross-chain oracle price that arrived via LayerZero and may be outdated; `setSymbolsPrice()` accepts old price signature; two prices from different blocks used in same transaction to exploit LP pools
- **Detection Heuristic**:
  1. Find where cross-chain price or state messages are stored and consumed in liquidation
  2. Check if the cross-chain message has a timestamp/sequence number that prevents replay
  3. Verify that the most recent message is always preferred and old ones cannot overwrite new ones
  4. Check if two valid price attestations from different times can be used simultaneously
- **Failure Mode**: Attacker uses stale price from old cross-chain message to trigger unfair liquidation; old price signature replayed to destabilize market; two-price attack exploits LP pool assumptions
- **Common Contexts**: Symmetrical setSymbolsPrice old priceSig, Perpetual two-Pyth-price LP attack, Autonomint LayerZero state overwrite

---

## LEND-050: accumulated_rewards_or_fees_missing_from_liquidation
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Pending CRV/Aura/Convex rewards not counted in collateral value → unfair liquidation; WETH stuck in OperatorRewardsCollector during liquidation; liquidation fees permanently frozen on Penrose YB account; trigger fee stolen from other auctions
- **Detection Heuristic**:
  1. Find protocols where collateral earns external rewards (Convex, Aura, Curve, Aave)
  2. Check if unclaimed rewards are included in collateral value for health calculation
  3. Verify liquidation correctly processes and routes reward tokens (not left stuck)
  4. Check if liquidation fee accounting is isolated per-auction or shared (allowing cross-auction theft)
- **Failure Mode**: Position liquidated prematurely because unclaimed rewards would have made it healthy; rewards locked in contract after liquidation; fees stolen from unrelated auctions
- **Common Contexts**: Blueberry pending CRV rewards, Stader WETH stuck, Tapioca frozen fees on Penrose, Gondi triggerFee stolen
