# Arithmetic Precision Patterns
> Extracted from 2,814 findings (500 sampled)
> Pattern count: 28

---

## ARITH-001: First Depositor / Empty Vault Share Inflation Attack

- **Frequency**: ~42/500 findings
- **Severity**: HIGH
- **Code Shape**: `totalSupply == 0` path in ERC4626-style `deposit()`/`mint()` without minimum liquidity lock; `shares = assets * totalSupply / totalAssets()` with no floor; `pricePerShare` or `pricePerFullShare` writable when supply is zero
- **Detection Heuristic**:
  1. Find all `deposit`, `mint`, or equivalent entry points in vault/staking contracts.
  2. Check the share minting formula: if `totalSupply == 0`, does it default to `assets` as shares (1:1)?
  3. Trace whether an attacker can donate tokens directly to the vault (bypassing the accounting) AFTER minting 1 share but BEFORE other depositors arrive, inflating `totalAssets` without inflating `totalSupply`.
  4. Calculate the rounding consequence: with inflated `pricePerShare`, the next depositor's assets round down to 0 shares.
  5. Verify whether a minimum liquidity amount is burned on first deposit (like Uniswap V2's `MINIMUM_LIQUIDITY`).
- **Failure Mode**: Attacker deposits 1 wei, donates a large amount to inflate `totalAssets`, making `pricePerShare` enormous. Subsequent depositors receive 0 shares (all assets stolen by first depositor), or the pool is DoS'd because any reasonable deposit rounds to 0 shares.
- **Common Contexts**: ERC4626 vaults, lending pools, staking vaults, LP token issuance, restaking, any vault implementing share-based accounting without virtual share offset.

---

## ARITH-002: Rounding Direction Favors Attacker Over Protocol

- **Frequency**: ~38/500 findings
- **Severity**: HIGH
- **Code Shape**: `withdraw`/`redeem` uses `assets * totalSupply / totalAssets` (rounds down shares burned, user gets too many assets); `mint` uses `assets * totalSupply / totalAssets` (rounds down shares minted, user pays fewer assets); absence of `Math.ceilDiv` or `FullMath.mulDivRoundingUp` in protocol-favoring paths
- **Detection Heuristic**:
  1. For every shares-to-assets and assets-to-shares conversion, identify which direction Solidity's integer division rounds (always toward zero = floor).
  2. Map who benefits from floor rounding at each operation: deposit (round shares DOWN → user loses), withdraw (round assets DOWN → protocol loses), mint (round assets UP → user pays more), redeem (round shares UP → user burns more).
  3. Check that deposit/mint round in FAVOR of the vault (user gets fewer shares or pays more assets) and withdraw/redeem also round in favor of the vault (user gets fewer assets or burns more shares).
  4. Specifically check if the same formula is used for both `previewDeposit` and actual execution — inconsistency here creates arbitrage.
  5. Verify if the protocol has a pattern where a user can "round trip" (deposit then immediately withdraw) to extract dust profit repeatedly.
- **Failure Mode**: With incorrect rounding direction on withdrawals, each operation extracts a small amount from the pool. At scale or with repeated transactions, attacker can drain the pool one rounding error at a time. In loan protocols, round-down on debt calculation means borrowers pay slightly less than owed, accumulating bad debt.
- **Common Contexts**: Lending protocols, ERC4626 vaults, stableswap pools, any protocol with bidirectional asset↔share conversion.

---

## ARITH-003: Decimal / Token Precision Mismatch (Non-18 Decimal Tokens)

- **Frequency**: ~35/500 findings
- **Severity**: HIGH
- **Code Shape**: Hardcoded `1e18` or `1e8` as precision denominator when token decimals are dynamic; `token.decimals()` never called; `amount * 1e18 / price` without normalizing `price` to 18 decimals; `IERC20(token).decimals()` result ignored after query
- **Detection Heuristic**:
  1. List all tokens accepted by the protocol; identify which have non-18 decimals (USDC=6, WBTC=8, etc.).
  2. Search for hardcoded `1e18`, `10**18`, `WAD`, `RAY` in arithmetic that touches token amounts.
  3. For each hardcoded precision: trace whether the token amount being scaled has already been normalized to 18 decimals, or if it's raw token units.
  4. Check oracle price feeds: Chainlink returns 8-decimal prices; if combined with 18-decimal token amounts without scaling, result is off by 1e10.
  5. Check that `previewDeposit`/`previewMint`/`previewWithdraw`/`previewRedeem` all use the same decimal normalization as the actual operations.
- **Failure Mode**: A 6-decimal token treated as 18-decimal inflates value by 1e12. User can deposit 1 USDC (1e6 raw units) and receive shares worth $1,000,000. Or: collateral value is underestimated by 1e12, making healthy positions look undercollateralized and triggering unnecessary liquidations.
- **Common Contexts**: Multi-token lending (USDC, WBTC collateral), token sale contracts, oracle integrations, cross-chain bridging, collateral valuation in CDP systems.

---

## ARITH-004: Division-Before-Multiplication (Premature Precision Loss)

- **Frequency**: ~28/500 findings
- **Severity**: HIGH
- **Code Shape**: `(a / b) * c` where `a < b` yields 0; `amount / PRECISION * rate` where PRECISION=1e18 kills small amounts; `shares = (assets / exchangeRate) * multiplier` ordering; reward accumulators of form `reward = (balance / totalBalance) * rewardRate`
- **Detection Heuristic**:
  1. Search for division operations (`/`) followed by multiplication (`*`) on the same variable within a single expression or across sequential statements in the same function.
  2. For each `x = a / b; result = x * c` pattern: compute the minimum value of `a` where the intermediate `x` is non-zero (`a >= b`). Determine if protocol inputs can be smaller than `b`.
  3. Check reward-per-token calculations: `rewardPerToken += rewardRate * deltaTime / totalSupply` — if `rewardRate * deltaTime < totalSupply`, the increment is 0. How often is this called?
  4. Verify that `mulDiv` (multiply then divide) is used instead of `div` then `mul` for all precision-sensitive paths.
  5. Look specifically at fee calculations where amounts might be small: `fee = amount / FEE_DENOMINATOR * FEE_RATE` loses precision for small amounts.
- **Failure Mode**: Intermediate division produces 0 when operand is below the divisor. Multiplying 0 by anything gives 0. Users receive 0 rewards, 0 fees are charged, or 0 collateral is credited when they should receive nonzero amounts. If exploitable, attacker can trigger the zero-result path to bypass fees or accumulate without cost.
- **Common Contexts**: Reward accumulators, fee calculations, interest rate computations, liquidity mining, bribe distribution, staking rewards with small per-second rates.

---

## ARITH-005: Precision Multiplier Rounds to Zero for Low-Decimal Tokens

- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `customPrecisionMultipliers[i] = 10**(18 - token.decimals())` where result is used in division before multiplication; `tokenPrecisionMultipliers` computed as `10**(MAX_DECIMALS - tokenDecimals)` but then divided into a small number; stableswap pool initialization with tokens whose decimal difference causes `multiplier = 0`
- **Detection Heuristic**:
  1. Find all `precisionMultiplier` or `scalingFactor` computations in AMM/stableswap pools.
  2. For each multiplier: check the formula — if it's `1 / (10**(decimals - 18))` for a token with MORE than 18 decimals, the integer result is 0.
  3. Verify that the multiplier is used as a multiplicand (not divisor) when applied to token amounts.
  4. Check pool initialization: are multipliers validated to be >= 1 after computation?
  5. For stableswap: trace the full flow from `amounts[]` → normalized amounts → invariant calculation to ensure no multiplier rounds a normalized amount to 0.
- **Failure Mode**: Pool breaks entirely — any swap or LP operation produces 0 output or reverts. If the multiplier of 0 appears only for one token, that token's balance is effectively erased from invariant calculations, breaking the AMM pricing model completely.
- **Common Contexts**: Stableswap (Curve-style) pools, multi-token AMMs supporting tokens with varying decimals, Boot Finance-style custom pools.

---

## ARITH-006: Unsafe Integer Downcast (Truncation Without Bounds Check)

- **Frequency**: ~22/500 findings
- **Severity**: HIGH
- **Code Shape**: `uint128(largeUint256)`, `int64(largeInt256)`, `uint32(timestamp)` without prior `require(value <= type(uintN).max)`; implicit Solidity casts in assignments; `uint96(block.timestamp)` (overflows in year 2038+); negative `int256` cast to `uint256`
- **Detection Heuristic**:
  1. Search for explicit casts: `uint128(`, `uint96(`, `uint64(`, `uint32(`, `int64(`, `int32(` applied to variables that could exceed the target type's max.
  2. For each cast: determine the maximum possible value of the expression being cast. If `type(uintN).max` can be exceeded, the cast truncates silently (pre-0.8) or reverts (post-0.8 with checked arithmetic enabled only if using safe cast libraries).
  3. Specifically check `rewardPerTokenStored` downcasts — reward accumulators grow unboundedly and are commonly downcast to `uint128` or `uint96`.
  4. Check all timestamp-related downcasts. `block.timestamp` as `uint32` overflows in year 2038; as `uint40` it overflows around 2106.
  5. Check `int256` to `int64` casts in financial contexts (position P&L, margin). A large positive profit truncated produces a negative or very small number.
- **Failure Mode**: Large accumulated values silently wrap to small values. Reward accumulators wrap to 0, causing all token holders to lose accrued rewards. Timestamp wraps to past, causing time-based checks to pass or fail unexpectedly. P&L wraps to opposite sign, causing incorrect liquidation decisions.
- **Common Contexts**: Reward distribution contracts, staking with long-running accumulator, lending protocols with interest indexes, timestamp-gated operations, position accounting in perpetuals.

---

## ARITH-007: Stale / Incorrect Exchange Rate or Price Used in Critical Path

- **Frequency**: ~20/500 findings
- **Severity**: HIGH
- **Code Shape**: `exchangeRate` stored at last interaction, not fetched fresh; `pricePerShare` read before a state-changing operation that affects it; `spotPrice` used instead of TWAP for liquidation check; using cached `totalAssets()` that excludes pending accruals
- **Detection Heuristic**:
  1. Identify all functions that both READ and UPDATE exchange rates or prices. Check if the read happens before or after state updates that would affect the rate.
  2. For liquidation functions: verify the price/rate used is fetched live (not from storage written during a prior block).
  3. For vault exchange rates: trace whether `totalAssets()` includes ALL assets (including unrealized yield, accrued fees, pending deposits/withdrawals). If any component is excluded, the rate is stale.
  4. Check NAV (Net Asset Value) update logic: is NAV recalculated before every withdrawal, or only periodically?
  5. Look for the pattern where `exchangeRate` is set in one function and read in another that executes later without recalculation.
- **Failure Mode**: Users transact at incorrect prices. Depositors receive too many or too few shares based on a stale rate. Liquidations trigger at wrong thresholds. Profitable traders exploit the stale price by front-running the rate update.
- **Common Contexts**: Yield vaults with external strategies, perpetuals/derivatives with funding rates, lending protocols with interest accrual, oracle-dependent liquidation systems.

---

## ARITH-008: Interest / Reward Accumulator Not Updated Before State Change

- **Frequency**: ~30/500 findings
- **Severity**: HIGH
- **Code Shape**: `totalBorrow` or `totalSupply` updated before calling `_accrueInterest()`; `rewardDebt` not updated synchronously with balance changes; `rewardPerToken` calculated AFTER `totalSupply` has changed; `checkpoint()` called after balance modification not before
- **Detection Heuristic**:
  1. Find all state-changing functions (deposit, withdraw, transfer, liquidate, stake, unstake).
  2. For each: check if `accrueInterest()`, `_updateRewards()`, `_checkpoint()`, or equivalent is called AS THE FIRST OPERATION (before any balance mutation).
  3. Specifically look at transfer functions — when a user transfers shares/tokens, both sender and receiver balances change. Are both checkpointed before the transfer executes?
  4. Check that `rewardDebt` (or equivalent per-user reward offset) is recalculated after EVERY balance change, not just on claim.
  5. Look for missing `_writeCheckpoint` calls — in vote-escrow systems, any balance-affecting action must write a checkpoint for historical vote power integrity.
- **Failure Mode**: Rewards are calculated based on a wrong balance or totalSupply. A user who deposits just before a reward snapshot claims proportionally more than their fair share. A user who receives tokens via transfer without checkpoint update cannot claim rewards that accrued during their balance tenure. In lending: interest accrual uses stale rates, underpaying or overpaying lenders.
- **Common Contexts**: MasterChef/SushiSwap-style farms, vote-escrow staking (Velodrome, Curve), lending protocols (Compound-style), reward distribution with checkpointing (Stakehouse, gauge-weighted rewards).

---

## ARITH-009: Wrong Rounding Direction in Share Mint (Favors User Over Protocol)

- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `shares = assets * totalSupply / totalAssets` (floor division) used in `deposit()` without an offset; queued deposit shares minted using `ceiling` when they should use `floor`; `previewDeposit` and actual deposit use different rounding; `mint` path uses `floor(assets/exchangeRate)` instead of `ceil`
- **Detection Heuristic**:
  1. In deposit/mint flows: the protocol should receive at least as many assets as the shares it issues are worth. This means shares must round DOWN (user gets fewer), or equivalently assets required must round UP (user pays more).
  2. Check specifically the "queued deposit" pattern: shares are pre-committed at one block's exchange rate but minted later at a different rate — which rate is used and how is rounding applied?
  3. Verify ERC4626 compliance: `previewDeposit` must return <= actual shares minted; `previewMint` must return >= actual assets required. Any deviation is a rounding bug.
  4. Check if shares mint uses `mulDiv(assets, totalSupply, totalAssets, ROUNDING.UP)` vs `ROUNDING.DOWN` — verify the direction matches the intended flow direction.
  5. Look for places where the ceiling is applied when floor should be, specifically in `processDeposit`, `fulfillDeposit`, or batch deposit processing.
- **Failure Mode**: Protocol issues more shares than assets are worth. Each deposit extracts a tiny fraction from the pool. Sophisticated users can repeatedly deposit tiny amounts to drain the pool rounding by rounding.
- **Common Contexts**: ERC4626 vaults with batch/queued processing, any vault with two-step deposit (queue → fulfill), options vaults, yield aggregators.

---

## ARITH-010: Incorrect Fee Calculation (Wrong Base, Missing Division, Double Counting)

- **Frequency**: ~28/500 findings
- **Severity**: HIGH
- **Code Shape**: `fee = amount * feeRate` where `feeRate` should be `/ FEE_DENOMINATOR` but the division is missing or uses wrong denominator; fee on fee (fee calculated on gross amount when net is correct); `makerFee + takerFee` double-counted; `protocolFee` subtracted from borrower then added back; basis points used as raw decimals (1000 bps = 10% but treated as 100x)
- **Detection Heuristic**:
  1. Find all fee calculation expressions. For each: verify the denominator matches the numerator's scale (e.g., if fee rate is stored as basis points, denominator should be 10000).
  2. Check for off-by-one in basis point math: `feeRate * amount / 10000` (correct for bps) vs `feeRate * amount / 1000` (wrong, 10x fee).
  3. Verify fee is applied to the CORRECT base amount: gross (before fee) vs net (after fee). In a fee-on-transfer scenario, the fee base changes depending on interpretation.
  4. Check for double application: protocol fee AND maker fee both deducted from the same pool in the same transaction.
  5. Trace the full fee flow: is fee collected from sender, and does the receiver get `amount - fee` or `amount`? Is the fee actually transferred to the treasury?
- **Failure Mode**: Fees are 10x, 100x, or 0x what was intended. Users overpay enormously (DoS their own transactions). Or fees are never collected (protocol insolvency). Or double-charging causes fund shortfall that prevents last withdrawals.
- **Common Contexts**: DEX trading fees, lending origination/borrowing fees, vault management/performance fees, NFT royalties, options protocols, protocol revenue extraction.

---

## ARITH-011: Reward-Per-Token Precision Loss (Too-Large Total Supply Kills Small Rewards)

- **Frequency**: ~15/500 findings
- **Severity**: HIGH
- **Code Shape**: `rewardPerToken += rewardRate * deltaTime / totalSupply` where `totalSupply` is so large that the numerator is always < denominator; `rewardPerTokenStored` uses insufficient scaling factor (e.g., `1e12` instead of `1e18`); `SCALE_FACTOR` in accumulator too small for high-supply tokens
- **Detection Heuristic**:
  1. Find `rewardPerToken` accumulator update formulas. Identify the scaling factor (should be `1e18` for most ERC20 tokens).
  2. Compute the minimum `rewardRate * deltaTime` that would produce a non-zero increment given the maximum plausible `totalSupply`. If the typical per-block increment rounds to 0, users lose rewards.
  3. Check: for a token with 18 decimals and 1 billion total supply (`1e27`), is `rewardRate * deltaTime` ever large enough to produce non-zero `/ totalSupply` before multiplying by user balance?
  4. Verify the SCALE_FACTOR used in the accumulator: `1e12` means rewards are only tracked with 12 decimal places of precision, which is inadequate for high-supply tokens.
  5. Check whether `rewardPerToken` uses `mulDiv` with 1e18 precision or simple integer division.
- **Failure Mode**: Entire reward emission rounds to 0 per update cycle. All reward tokens become permanently locked in the contract because `earned(user) = balance * rewardPerToken - rewardDebt` accumulates to 0 for all users. Only very large holders (or nobody) ever claims non-zero rewards.
- **Common Contexts**: Staking rewards (MasterChef clones), gauge incentives, bribe distributions, any per-second reward emission to a large staker base.

---

## ARITH-012: Interest Rate Calculation Frequency Dependency (APY Applied as Per-Second Rate)

- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `interestPerSecond = APY / SECONDS_PER_YEAR` but APY was already annualized and multiplication is `balance * APY * delta_seconds` without `/SECONDS_PER_YEAR`; compound interest linearized incorrectly; `borrow_rate_per_second * SECONDS_PER_YEAR` as effective rate when it should be `(1 + rate)^N - 1`
- **Detection Heuristic**:
  1. Find interest accrual functions. Identify the stated rate unit (APY, APR, per-second, per-block).
  2. Check whether the rate is divided by the correct time denominator before multiplying by elapsed time: `rate / SECONDS_IN_YEAR * seconds_elapsed` — if `rate` is APY expressed as `1e18 = 100%`, and `SECONDS_IN_YEAR` is missing, interest is 31.5 million times too high.
  3. Verify compounding: simple interest is `principal * rate * time`; compound is `principal * (1 + rate)^time`. Using simple interest formula for a system designed for compound interest understates (or overstates) owed amounts over time.
  4. Check `calculateCompoundedFactor()` if present: does it correctly implement `(1 + dailyRate)^days` or does it linearize as `1 + dailyRate * days`?
  5. Look for the Beanstalk/Alchemix pattern: rate stored as `per_epoch` multiplied by wrong epoch count.
- **Failure Mode**: Borrowers pay interest 1000x too high (immediate insolvency, liquidation on next block). Or borrowers pay essentially 0 interest (protocol insolvency from unpaid debt). In some cases, the protocol's claimed APY is unachievable because the rate is applied in the wrong time unit.
- **Common Contexts**: Lending protocols, bond protocols, yield vaults with time-weighted accrual, perpetuals with funding rates, anything with time-weighted interest accumulation.

---

## ARITH-013: Oracle Price Scaling / Decimal Normalization Error

- **Frequency**: ~22/500 findings
- **Severity**: HIGH
- **Code Shape**: Chainlink price returned as 8 decimals used in computation expecting 18 decimals without `* 1e10` scaling; composite oracle multiplies two 8-decimal prices without intermediate normalization producing 16-decimal result; `getTokenPrice` in UniswapV3 using `slot0.sqrtPriceX96` without adjusting for token decimal difference; `price * 10**36 / tokenDecimals` when `tokenDecimals` should be `10**tokenDecimals`
- **Detection Heuristic**:
  1. Identify all oracle integrations. For each: record the output precision (Chainlink = 8, custom = varies).
  2. Trace where oracle output is used in arithmetic. Verify it's scaled to the protocol's internal precision before any multiplication or comparison.
  3. For composite oracles (A/B * B/C = A/C): check that intermediate results are at the correct precision after each step. Two 8-decimal prices multiplied give a 16-decimal result, not 8.
  4. For UniswapV3 TWAP: `sqrtPriceX96` has Q64.96 format. Converting to a human price requires: `(sqrtPriceX96 / 2**96)^2 * 10**token0Decimals / 10**token1Decimals`. Any missing step causes massive price errors.
  5. Check that prices are validated to be non-zero and within plausible range AFTER scaling (a bug in scaling might make a valid price appear 0 or MAX_UINT).
- **Failure Mode**: Price is inflated 1e10 (8-decimal feed used as 18-decimal) or deflated 1e10. Collateral is worth 10 billion times real value (unlimited borrowing). Or collateral is worth 0 (all positions immediately liquidatable). Can cause total protocol drain in one transaction.
- **Common Contexts**: Lending protocols with multiple collateral types, options protocols, perpetuals, cross-chain protocols using composite pricing, any protocol integrating Chainlink alongside custom oracles.

---

## ARITH-014: Shares / Assets Confusion (Using Both Interchangeably)

- **Frequency**: ~15/500 findings
- **Severity**: HIGH
- **Code Shape**: Function parameter typed as `assets` but passed as `shares` to a function expecting assets; `_amountOut` representing sometimes assets, sometimes shares, depending on context; `totalBorrow` in shares used where total borrow in assets expected; `collateralAmount` in shares compared against value denominated in assets
- **Detection Heuristic**:
  1. Map every variable in the protocol to its unit: is it in shares (of the vault) or underlying assets?
  2. For functions with parameters named `amount`, `value`, or generic names: trace what callers pass and whether the callee treats it consistently.
  3. Check liquidation functions specifically: the input specifying how much to liquidate — is it in shares or assets? Does the function correctly convert?
  4. Look for arithmetic on two quantities without conversion where one is in shares and one in assets (they are only equal when `pricePerShare == 1`).
  5. Review ERC4626-like interfaces for correctness: `redeem(shares)` should convert shares→assets internally; `withdraw(assets)` should convert assets→shares internally. Check that these conversions are actually applied.
- **Failure Mode**: Liquidator receives far more or far fewer assets than expected. Borrower's collateral is incorrectly valued, leading to wrong LTV calculation. Users who request withdrawal in assets receive shares worth a different amount. Protocol insolvency when share/asset mismatch accumulates.
- **Common Contexts**: ERC4626 vaults, lending protocols with tokenized debt/collateral positions, liquidation engines, any system mixing share and asset denominations in the same function call chain.

---

## ARITH-015: Invariant / State Variable Not Updated Atomically With Dependent State

- **Frequency**: ~25/500 findings
- **Severity**: HIGH
- **Code Shape**: `totalBorrow` not updated after partial liquidation; `totalSupply` incremented but `totalAssets` not; `fundingFees` balance updated without adjusting pool value; `utilization` computed without including accrued interest; `highWaterMark` updated on every deposit/withdraw instead of only on profit
- **Detection Heuristic**:
  1. Identify all "total" or "global" state variables (`totalBorrow`, `totalSupply`, `totalAssets`, `reserves`, `poolValue`).
  2. For each operation that changes one: find ALL other state variables that must change in concert. Verify they ALL change in the same transaction.
  3. Look for partial liquidation paths: after a partial liquidation, does `totalBorrow` decrease by exactly the amount repaid? Does the position's `collateralBalance` decrease by the correct collateral removed?
  4. Check fee accounting: are protocol fees stored in the same pool they affect the valuation of? If yes, is the fee extracted from the pool's accounting simultaneously with its accrual?
  5. Use symbolic tracking: pick any "total" variable T. Find every function that modifies any component of T. Verify T is updated in ALL those functions.
- **Failure Mode**: Protocol accounting becomes inconsistent. Solvency checks pass based on stale totals. Users can borrow against already-spent collateral. Rewards are distributed from a pot that doesn't reflect actual holdings. Liquidations fail because `totalBorrow` exceeds actual outstanding debt, causing underflow.
- **Common Contexts**: Lending (BigBang/Tapioca patterns), CDP systems, liquidity pools with external yield, reward distribution contracts, multi-tranche lending.

---

## ARITH-016: Overflow / Underflow in Arithmetic Without SafeMath or Checked Arithmetic

- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: Solidity <0.8 contract using `+`, `-`, `*` without SafeMath; `unchecked {}` block with subtraction that can underflow; `a - b` where `b` might exceed `a` due to rounding; reward debt underflow when `cumulativeRewards` decreases (due to slashing or rounding)
- **Detection Heuristic**:
  1. For Solidity <0.8: every arithmetic operation is a potential overflow/underflow unless SafeMath is used. Check import and usage of SafeMath on all arithmetic-heavy functions.
  2. For Solidity >=0.8 with `unchecked {}` blocks: audit each subtraction and multiplication inside the block for plausible overflow/underflow scenarios.
  3. Look for user-controlled values fed into subtraction: `userDebt - totalPaid` where attacker can make `totalPaid` exceed `userDebt` through rounding.
  4. Check FullMath.sol version: the 0.7.x version of FullMath has a known overflow bug in `mulDiv` for certain inputs; 0.8.x with unchecked arithmetic in FullMath can also revert when intermediate 512-bit result overflows.
  5. Check timestamp arithmetic: `endTime - startTime` where `endTime` might be 0 if uninitialized, producing massive underflow.
- **Failure Mode**: Overflow wraps large values to small (attacker bypasses limits). Underflow wraps to MAX_UINT (user's balance or debt becomes astronomically large). Can cause permanent DoS if a required subtraction always reverts, or unlimited minting if overflow bypasses a supply cap.
- **Common Contexts**: Token transfer accounting, reward debt calculations, time-based math, any Solidity <0.8 contract, contracts with `unchecked` blocks, LP math libraries (FullMath, PRBMath).

---

## ARITH-017: TWAP / Time-Weighted Metric Incorrectly Computed

- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `periodCumulativesInside` reads stale checkpoint rather than current tick; TWAP seconds-per-liquidity accumulated incorrectly; TWAP price at beginning and end of period use different spot prices; Uniswap V3 `observe()` called with wrong secondsAgo; accumulated TWAP not reset after long pause
- **Detection Heuristic**:
  1. Find all TWAP or time-weighted metric computations. Identify the start and end observations used.
  2. Check whether both observations are fetched from the same source consistently (e.g., both from the same Uniswap pool contract). Mixing spot price from one source with cumulative from another produces wrong results.
  3. For UniswapV3 TWAP: verify `secondsAgo` is correct. `[period, 0]` gives a period-long TWAP ending now; `[0]` is spot. Confusion between these is common.
  4. Check sequencer downtime handling: if the L2 sequencer was down, accumulated TWAP during downtime is stale and usable for manipulation.
  5. Verify that cumulative tick/liquidity accumulators are actually updated (some pools require manual `poke()` or `burn(0)` to sync accumulators).
- **Failure Mode**: TWAP reports wrong price, allowing liquidations at incorrect thresholds or enabling oracle-price-manipulation attacks. Debt added instead of subtracted in position tracking causes positions to appear healthier than they are.
- **Common Contexts**: DEX oracles (Uniswap V2/V3), lending protocols using on-chain TWAP, options protocols, perp DEXs on L2 with sequencer risk.

---

## ARITH-018: Incorrect Scaling Between Fixed-Point Systems (e.g., RAY vs WAD vs Plain)

- **Frequency**: ~15/500 findings
- **Severity**: HIGH
- **Code Shape**: `rayMul` result passed to `wadMul` without conversion; `1e27` (RAY) used as `1e18` (WAD) denominator; borrow rate in RAY multiplied against balance in WAD producing result in `1e45` scale; Compound-style `mantissa` (`1e18`) mixed with Aave-style `ray` (`1e27`)
- **Detection Heuristic**:
  1. Identify all fixed-point systems in use: WAD (`1e18`), RAY (`1e27`), basis points (`1e4`), percentage (`1e2`), custom (`1e8`, `1e6`).
  2. For every arithmetic operation, verify both operands are in the same scale before the operation, OR that the operation explicitly normalizes (e.g., `rayMul` handles `1e27` scaling internally).
  3. Check interfaces between protocol components that may use different scales: a strategy might report in WAD while the vault expects RAY.
  4. Verify that intermediate results of sequential multiplications are renormalized: `(a * b) / 1e18 * c / 1e18` is correct; `a * b * c / 1e18` accumulates to wrong scale.
  5. Look for ZAROS-style pattern: `UD60x18` values must be unwrapped to raw uint before sending to contracts expecting raw amounts. Failure to unwrap sends `1e18 * amount` instead of `amount`.
- **Failure Mode**: Amounts are off by factors of 1e9, 1e18, etc. Users receive or pay orders of magnitude more or less than expected. Protocol may appear functional with small amounts but catastrophically fail with realistic amounts due to overflow in intermediate calculations.
- **Common Contexts**: Aave forks (RAY precision), Compound forks (WAD precision), multi-protocol integrations, cross-chain bridges normalizing amounts, yield aggregators spanning multiple lending platforms.

---

## ARITH-019: Spot Price Manipulation via Single-Block Transactions (Not TWAP Protected)

- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: `getPrice()` using `slot0.sqrtPriceX96` (spot) rather than TWAP; `getAmountsOut` on UniV2 using current reserves as price oracle; oracle using `balanceOf(pool)` / `totalSupply` as price which can be flash-loan manipulated; single-block Chainlink price used without staleness check
- **Detection Heuristic**:
  1. Identify all price oracle calls within the protocol. For each: determine if the price is SPOT or TIME-WEIGHTED.
  2. For SPOT prices: ask whether a flash loan or single-block large trade can meaningfully move the price and benefit the attacker within the same transaction.
  3. Check Chainlink usage: is `latestRoundData()` return value validated for staleness (`updatedAt + heartbeat > block.timestamp`)? Is `answeredInRound >= roundId` checked? Is the answer validated > 0?
  4. For on-chain TWAP (Uniswap): is the TWAP period long enough to make manipulation economically infeasible (typically >= 30 minutes)?
  5. Check the specific context where price is used: liquidation and collateral valuation are highest risk; swap pricing is lower risk since manipulation is its own cost.
- **Failure Mode**: Attacker flash-loans large amounts, moves pool spot price, triggers liquidations of healthy positions (or prevents liquidations of unhealthy ones), profits from the manipulated price, repays flash loan in same block. Can drain the entire protocol in one transaction.
- **Common Contexts**: Lending protocols, perp DEXs, options protocols, any protocol using on-chain price sources for collateral valuation or liquidation triggers.

---

## ARITH-020: Asymmetric Rounding in Paired Operations (Deposit/Withdraw or Lock/Unlock)

- **Frequency**: ~16/500 findings
- **Severity**: HIGH
- **Code Shape**: `addLiquidity` rounds token amounts in one direction, `removeLiquidity` rounds in the opposite; `lend` converts assets→shares with floor, `redeem` converts shares→assets with floor (protocol always loses); create/claim or lock/unlock of the same value producing different amounts due to inconsistent rounding
- **Detection Heuristic**:
  1. Identify all paired inverse operations in the protocol (deposit↔withdraw, lock↔unlock, mint↔burn, buy↔sell).
  2. For each pair: trace the mathematical inverse path. If `deposit(X)` gives N shares, does `withdraw(N shares)` give back exactly X assets? Or slightly less/more?
  3. Check rounding consistency: if `addLiquidity` uses `floor(a)` and `removeLiquidity` uses `floor(b)`, the round-trip might be `X → X-1` (dust loss) or `X → X+1` (protocol loss). Both are bugs.
  4. Specifically test the invariant: for any amount A, `deposit(A); withdraw(shares_received) <= A` (the protocol should never give back more than received).
  5. Check `previewDeposit` vs `previewWithdraw` for the same share amount — they should be inverses of each other within rounding.
- **Failure Mode**: Round-trip extracts value from the pool. Users can cycle deposits and withdrawals to incrementally drain the protocol. Or users receive slightly less on withdrawal than they deposited, creating a systematic loss that compounds to significant amounts over many users.
- **Common Contexts**: AMMs (addLiquidity/removeLiquidity), ERC4626 vaults, lending protocols (supply/redeem), stableswap pools, any bidirectional asset exchange.

---

## ARITH-021: Precision Loss When Total Supply Is Zero or Near-Zero (DoS)

- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `rewardPerToken = accumulatedReward / totalSupply` when `totalSupply == 0` reverts or produces division by zero; `index = rewards / totalStaked` when `totalStaked` approaches 0 causes `index` to reach `type(uint104).max`; snapshot creation when denominator rounds to 0
- **Detection Heuristic**:
  1. Find all division operations where the denominator is derived from total supply, total staked, or total shares.
  2. Check if there's an explicit guard: `if (totalSupply == 0) return 0;` or similar before the division.
  3. Evaluate the "dust state": after most users leave, if `totalSupply = 1 wei` and `rewardRate` is still active, `rewardPerToken` accumulates enormous values each second. Does this overflow `uint104`?
  4. Check what happens when `totalStaked` becomes 1 wei through a DoS attack: attacker sends 1 wei to set totalStaked to minimum, causing `index` to shoot to max.
  5. Verify DoS vectors: can an attacker deliberately bring `totalSupply` to 0 (by burning dust) then re-deposit to exploit the zero-supply first-depositor conditions?
- **Failure Mode**: When supply is dust or zero, index/per-token values reach type max, causing overflow on the next interaction and permanently DoS-ing all deposits/transfers for that aToken or reward token.
- **Common Contexts**: Reward distribution contracts (Aave-style RewardsDistributor), staking contracts with removable stakers, vaults that allow full redemption, any contract where totalSupply can reach 0.

---

## ARITH-022: Incorrect Invariant in Stableswap / Constant Product AMM

- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: Stableswap `get_d()` Newton-Raphson convergence not verified to terminate; swap result checked against wrong invariant (`lp_value` before != after); `D` invariant computation uses wrong `A` parameter encoding (A vs A*N^(N-1)); `K` not recomputed after fee deduction before invariant check
- **Detection Heuristic**:
  1. For stableswap (Curve forks): verify the invariant `D` is computed correctly including the amplification factor encoding. Curve uses `A * N^N` where some forks incorrectly use `A * N` or just `A`.
  2. For constant-product (Uniswap forks): after swap, verify `reserve0 * reserve1 >= k` (or `>=` k minus fees). Check the inequality direction — some implementations use `>` instead of `>=` causing off-by-one reverts.
  3. For disjoint swaps (two independent half-swaps instead of atomic): verify that splitting the swap preserves the aggregate invariant. Disjoint swaps can break the invariant even when each half appears valid.
  4. Check the `get_y()` function in stableswap: it solves for the output amount given the invariant. Verify that the Newton-Raphson iteration converges and is using the current `D` (not stale).
  5. Verify fee handling: does the fee come OUT of the invariant calculation or is the invariant checked on amounts BEFORE fee deduction?
- **Failure Mode**: Swap produces incorrect output, allowing arbitrage that drains the pool. Non-converging Newton-Raphson can revert (DoS) or return garbage values. Wrong A parameter makes the stableswap behave like constant-product with no stability benefit, causing excessive slippage.
- **Common Contexts**: Curve forks, stableswap pools (MANTRA, Boot Finance, Pontem Liquidswap), constant-product DEX forks, hybrid AMMs.

---

## ARITH-023: Timestamp Rounding / Epoch Boundary Precision Loss

- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `lock_end = (block.timestamp + duration) / WEEK * WEEK` — vote-escrow rounding that creates inconsistency between recording and reading; rewards calculated `floor(deltaTime / EPOCH_LENGTH)` losing fractional epochs; staking duration `< 1 day` produces 0 reward due to integer truncation; two different functions using different rounding for the same lock end time
- **Detection Heuristic**:
  1. Find all time calculations involving epoch/week/day alignment: `timestamp / WEEK * WEEK`, `timestamp / DAY * DAY`.
  2. Check if the same rounding is applied consistently when both WRITING a timestamp and READING it for comparison.
  3. For vote-escrow contracts: is lock end time rounded down to the nearest week at creation? Is it also rounded down during power calculation? If one path rounds and another doesn't, voting power math breaks.
  4. Verify reward calculations with fractional periods: if a user stakes for 23 hours in a 24-hour epoch, do they receive 0 rewards? Is this intended?
  5. Check `block.timestamp` division for edge cases: blocks exactly at epoch boundary, and blocks 1 second before boundary, should behave consistently.
- **Failure Mode**: Users who stake for almost a full epoch receive 0 rewards (losing up to 24 hours of staking). Vote power is computed differently in mint vs transfer paths, allowing double-counting. Lock extension can inconsistently extend or fail to extend lock periods.
- **Common Contexts**: Vote-escrow systems (Velodrome, Curve veCRV), gauge reward epochs, time-weighted staking, subscription/vesting contracts.

---

## ARITH-024: Cross-Layer / Cross-Chain Precision Mismatch

- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: L1 uses 18 decimals, L2 uses 8 decimals for the same token; bridge mints 1:1 but source has 6 decimals and destination has 18 decimals; `restoreBridgeTransaction` adds balance without applying precision conversion factor; cross-chain message encodes amount in wrong scale
- **Detection Heuristic**:
  1. For cross-chain/bridge protocols: enumerate all tokens that cross the bridge. For each: verify source and destination decimal counts.
  2. Check the message encoding: is the token amount encoded as raw units (decimal-dependent) or as a normalized value (e.g., always in 1e18 units)?
  3. On the receiving side: is the incoming amount decoded and then scaled to the destination token's decimals BEFORE any arithmetic?
  4. Look for hardcoded precision constants in bridge/cross-chain functions that may not apply to all token types.
  5. Check the SYMMIO pattern: if a bridge transaction can be "restored" (replayed), does the restoration path apply the same precision conversion as the original path?
- **Failure Mode**: User bridges 1 USDC (1e6 units). Receiving side treats it as 1e6 units of an 18-decimal token, minting 1,000,000,000,000 tokens on the other side. Or inverse: user tries to bridge 1 ETH (1e18 units) but the receiving side expects 8-decimal units and creates a 1e10 shortfall.
- **Common Contexts**: Cross-chain bridges, L1↔L2 token bridging (SYMMIO, Fuel), cross-chain lending, any protocol that moves token amounts across chains with different precision conventions.

---

## ARITH-025: Weighted Average / TWAP Incorrect When Window Spans Boundary Conditions

- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `timeWeightedAverage = sum(price * deltaTime) / totalTime` but `totalTime` is computed incorrectly when observation window spans a rebase, slash, or liquidity migration; Pyth confidence interval used incorrectly causing wild swings; `prevRatios` index off-by-one during `addLiquidity` when pool already has liquidity
- **Detection Heuristic**:
  1. Find all time-weighted average computations. Check if the observation window correctly handles protocol state transitions (pauses, resets, migrations).
  2. For protocols that reset or migrate state: are historical observations invalidated? Does the TWAP correctly start fresh after migration rather than including pre-migration data?
  3. For Pyth-specific: check that `price`, `conf`, `expo` are all read consistently. Expo is negative (e.g., -8 means 1e-8 scale). Forgetting to apply expo inflates/deflates price by 1e8.
  4. Check `prevRatios` or previous-period tracking arrays: are they indexed correctly when the first addLiquidity after pool creation uses index 0 vs 1?
  5. Verify that the weighted average computation handles the edge case where `totalTime == 0` (same-block observation).
- **Failure Mode**: TWAP reports wrong price for the entire observation period if even one bad data point is included. Incorrect Pyth expo application causes price to be off by 1e8. First liquidity provider gets wrong LP token allocation, either losing funds or stealing from the pool.
- **Common Contexts**: Pyth oracle consumers, on-chain TWAP computation, any protocol that tracks historical state with rolling windows.

---

## ARITH-026: Incorrect Scaling of Wrapped / Rebasing Token Balances

- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `wstETH` amount used where `stETH` (rebased) amount expected; `rETH.getEthValue()` not called, using raw rETH balance as ETH equivalent; `pricePerShare * shares` without division by scale factor; rebase token transferred as if static amount but actual transfer may be `amount ± 1` wei due to rounding
- **Detection Heuristic**:
  1. List all rebasing or yield-bearing wrapped tokens in scope (wstETH, rETH, aTokens, cTokens, ERC4626 shares).
  2. For each: identify where raw token amounts are used vs value-adjusted amounts.
  3. Check `transfer` calls with rebasing tokens: the actual transferred amount may differ from the requested amount by 1 wei due to internal rounding. Does the protocol account for this?
  4. Look for `balanceOf` calls on rebasing tokens that will return different values each block — is the code checking current balance or stored balance?
  5. Verify that price calculations for wstETH vs stETH use the correct conversion: `wstETH.stEthPerToken()` or `stETH.getPooledEthByShares()`.
- **Failure Mode**: Protocol attempts to transfer slightly more stETH than the contract holds (off-by-1 wei due to rounding), causing revert. Or protocol values wstETH at 1:1 with ETH instead of at the actual staking rate, mispricing collateral by ~5-15%.
- **Common Contexts**: Liquid staking integrations (Notional, Blueberry, Asymmetry Finance), ERC4626 vault strategies using rebasing tokens, any protocol mixing wrapped and unwrapped yield-bearing tokens.

---

## ARITH-027: Borrow / Collateral Ratio Using Wrong Variable (Shares vs Amount, Before vs After Fee)

- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: LTV calculation uses `collateralShares * collateralizationRate` when it should use `collateralAmount * collateralizationRate`; `isSolvent()` uses `totalCollateralShares` not `totalCollateralAssets`; health factor computed using gross debt when net (post-fee) should be used; `liquidationThreshold` applied to shares amount instead of underlying asset value
- **Detection Heuristic**:
  1. Identify the solvency/health check function. Trace every variable used in the final comparison.
  2. For each variable: determine its unit (shares vs underlying assets). Ensure both sides of the comparison use the same unit.
  3. Check the `collateralizationRate` multiplier: it should multiply asset value, not share count (unless share price == 1).
  4. Verify that interest accrual has been applied before solvency check: if `totalBorrow` in shares doesn't include newly accrued interest, the debt is understated.
  5. Look for `computeMaxBorrowableAmount` or equivalent — if it overestimates collateral value by confusing shares with assets, users can borrow more than the protocol can support.
- **Failure Mode**: Protocol believes positions are solvent when they are not (cannot liquidate bad debt, accumulating protocol loss). Or protocol believes positions are insolvent when they are (healthy users get liquidated). In worst case, protocol is drained because users borrow against overstated collateral.
- **Common Contexts**: CDP systems, lending protocols (Tapioca/BigBang, Ajna, WISE), collateralized debt positions, any protocol where collateral value is computed from a shares→assets conversion.

---

## ARITH-028: Missing or Incorrect Minimum Liquidity / Dust Protection

- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: No `MINIMUM_LIQUIDITY` burned on first LP mint; `minAmount` check using `<=` instead of `<` (allows zero); pool allows creation of "dust" positions that are uneconomical to liquidate; `if (amount == 0) revert` is present but executed AFTER state changes; small-amount conditions bypass fee checks
- **Detection Heuristic**:
  1. Check first LP deposit: is any amount permanently locked (burned to address(0)) to prevent future inflation attacks? UniswapV2 burns 1000 wei minimum.
  2. Find all minimum amount checks: are they `> 0` (exclusive), `>= MIN_AMOUNT` (inclusive with floor), or `!= 0`? Ensure they prevent both 0 and dust amounts that make math degenerate.
  3. Look for "dust CDP" creation: can a user create a position so small that the gas cost of liquidating it exceeds the liquidation bonus? This blocks bad debt resolution.
  4. Check that minimum amount validation happens BEFORE any state changes (not after, where a partial state update has already occurred if it reverts).
  5. For batchRelease or bulk processing functions: can a single 0-amount entry DoS the entire batch?
- **Failure Mode**: Attacker uses 1-wei positions to lock funds in DoS state, inflate price per share, or create unliquidatable dust positions that accumulate as bad debt. Batch processing reverts permanently due to one dust entry.
- **Common Contexts**: AMM initialization, lending position creation, batch processing systems, vault deposits, any protocol that processes arbitrary user-specified amounts.

---

*Note: All 500 sampled findings map to one or more of these 28 patterns. The most prevalent patterns are:*
- *ARITH-001 (First Depositor Inflation): ~42 findings*
- *ARITH-002 (Wrong Rounding Direction): ~38 findings*
- *ARITH-010 (Incorrect Fee Calculation): ~28 findings*
- *ARITH-008 (Accumulator Not Updated Before State Change): ~30 findings*
- *ARITH-003 (Decimal Mismatch): ~35 findings*
