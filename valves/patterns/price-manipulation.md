# Price Manipulation Patterns
> Extracted from 404 findings (404 sampled — full cluster)
> Pattern count: 28

---

## PRICE-001: uniswap_slot0_spot_price_usage
- **Frequency**: ~38/404
- **Severity**: HIGH
- **Code Shape**: `pool.slot0()` → `sqrtPriceX96` used directly for pricing, collateral valuation, slippage limits, or oracle reads; `IUniswapV3Pool(pool).slot0()` without TWAP; `sqrtPriceX96 * sqrtPriceX96` arithmetic for price
- **Detection Heuristic**:
  1. Search for `.slot0()` calls in the codebase
  2. Check if the returned `sqrtPriceX96` is used to derive token prices or ratios (not just as a range check)
  3. Check if the derived price feeds into: collateral valuation, liquidation triggers, slippage bounds, mint/burn calculations, or LP token pricing
  4. Confirm no TWAP is used as a cross-check or alternative — if only `slot0` is used for a value-sensitive path, flag as HIGH
  5. Check if the function is callable in the same block as a large swap (flash loan context)
- **Failure Mode**: Attacker uses a flash loan to move the pool price in `slot0` within a single transaction block; the manipulated price is read by the protocol, allowing under-collateralized borrows, forced unfair liquidations, distorted slippage caps, or theft of LP fees
- **Common Contexts**: Uniswap V3 LP position oracles, collateral pricing in lending protocols, slippage limit calculation for swaps, position rebalance triggers, domain/NFT pricing from AMM pools

---

## PRICE-002: erc4626_first_depositor_share_inflation
- **Frequency**: ~22/404
- **Severity**: HIGH (often escalates to Critical in context)
- **Code Shape**: ERC4626 vault with `totalSupply == 0` path; `shares = assets * totalSupply / totalAssets` where `totalAssets` can be manipulated by direct token transfer (donation); no minimum liquidity lock at deployment; `convertToShares` / `convertToAssets` derived from manipulable `totalAssets()`
- **Detection Heuristic**:
  1. Find ERC4626 or vault contracts with `deposit`/`mint` functions
  2. Check whether `totalSupply == 0` case is specially handled (virtual shares, initial share price lock)
  3. Check whether `totalAssets()` reads from `balanceOf(address(this))` (donation-vulnerable) vs. internal accounting variable
  4. Simulate: attacker deposits 1 wei (gets 1 share), donates large amount of underlying, second depositor gets 0 shares due to rounding
  5. Check for minimum deposit requirement or initial liquidity seeding at deployment
- **Failure Mode**: First depositor mints 1 share, then donates large underlying balance to inflate `totalAssets`. Second depositor's shares round down to 0 while they pay the full deposit. Attacker redeems the inflated single share for both deposits.
- **Common Contexts**: ERC4626 vaults, staking receipt token vaults, LST wrappers, Autopool/strategy vaults, new low-TVL pools

---

## PRICE-003: missing_slippage_protection_on_swap
- **Frequency**: ~35/404
- **Severity**: HIGH (critical when large amounts)
- **Code Shape**: `amountOutMinimum: 0` in swap params; `minOut` hardcoded to 0 or unchecked; `ISwapRouter.exactInputSingle({..., amountOutMinimum: 0})`; swap helper with no caller-controlled `minAmountOut`; `convertTokens` with `minAmount = 0`
- **Detection Heuristic**:
  1. Search for swap calls to Uniswap/Curve/Balancer routers
  2. Check the `amountOutMinimum`, `minAmountOut`, or `minOut` parameter — is it 0? Derived from spot price? Hardcoded?
  3. Check if the caller can pass their own slippage tolerance or if it is protocol-set
  4. If protocol-set, check that it uses a TWAP or oracle price, not the spot price derived from the same pool
  5. Check `reinvest()`, `harvest()`, `rebalance()`, `commitAndClose()`, and fee conversion functions — these are often forgotten
- **Failure Mode**: Sandwich attack: MEV bot manipulates pool price before the protocol's swap, executes the swap at the worst price, then restores price. Protocol loses the slippage difference. In automated functions (reinvest, harvest), loss is guaranteed profit for the attacker.
- **Common Contexts**: Harvest/reinvest functions in yield protocols, rebalance operations, fee collection and conversion, strategy investment/divestiture, AMO rebalances

---

## PRICE-004: twap_period_too_short_or_zero
- **Frequency**: ~18/404
- **Severity**: MEDIUM
- **Code Shape**: `secondsAgo = 30` or less in `observe()` call; `_updatePeriod` configurable down to 0; TWAP period under 10–30 minutes for Uniswap V3; `lookback = 30` seconds hardcoded; no minimum enforced on TWAP window
- **Detection Heuristic**:
  1. Find all TWAP oracle implementations — search for `observe()`, `OracleLibrary.consult()`, TWAP-related contracts
  2. Extract the `secondsAgo` / `lookback` / `period` value used
  3. Check if this value is hardcoded, configurable, or user-supplied
  4. Check the minimum bound: anything under 10 minutes (600 seconds) is manipulatable within a single block on L2 or within a few blocks on L1
  5. Check if the period is enforced as a minimum in the constructor or setter
- **Failure Mode**: A short TWAP window (e.g., 30 seconds) can be moved significantly by a well-capitalized attacker trading repeatedly over a small time window. On L2s where sequencer controls ordering, even a 10-minute TWAP may be manipulatable.
- **Common Contexts**: Custom TWAP oracle contracts, Uniswap V3 TWAP integrations, price references for minting/redemption, option pricing oracles

---

## PRICE-005: chainlink_stale_price_no_staleness_check
- **Frequency**: ~20/404
- **Severity**: MEDIUM (HIGH during volatility events)
- **Code Shape**: `latestRoundData()` called without checking `updatedAt`; no `block.timestamp - updatedAt > heartbeat` check; `answeredInRound < roundId` not verified; no sequencer uptime check on L2; `latestAnswer()` (deprecated) used instead of `latestRoundData()`
- **Detection Heuristic**:
  1. Find all `latestRoundData()` or `latestAnswer()` calls
  2. Check what fields are extracted — if only `answer`/`price` is used and `updatedAt` or `answeredInRound` is ignored, flag it
  3. Check for a heartbeat-based staleness check: `require(block.timestamp - updatedAt <= HEARTBEAT_DURATION)`
  4. On L2 deployments: check for sequencer uptime feed validation before trusting Chainlink prices
  5. Check what the downstream action is — lending/liquidation = HIGH impact, analytics = LOW impact
- **Failure Mode**: During sequencer downtime or Chainlink oracle lag, protocol uses price data that may be hours old. Stale prices enable under-collateralized borrows, prevent necessary liquidations, or allow borrowers to avoid liquidation while collateral value has dropped.
- **Common Contexts**: Lending protocol collateral pricing, liquidation trigger evaluation, stablecoin peg mechanisms, options settlement

---

## PRICE-006: wbtc_btc_price_feed_depeg_risk
- **Frequency**: ~4/404
- **Severity**: MEDIUM
- **Code Shape**: `AggregatorV3Interface(BTC_USD_FEED).latestRoundData()` used to price WBTC; no separate WBTC/BTC ratio check; assumes WBTC == BTC at 1:1; no fallback for WBTC depeg scenario
- **Detection Heuristic**:
  1. Search for Chainlink BTC/USD feed usage in the codebase
  2. Check if the asset being priced is WBTC (not BTC) — WBTC is a wrapped token with custodian risk
  3. Check if there is any WBTC/BTC peg check or secondary oracle
  4. If WBTC == BTC assumption, flag as MEDIUM: during depeg events, oracles report wrong collateral value
- **Failure Mode**: If WBTC depegs from BTC (custodian compromise, regulatory action), the BTC/USD Chainlink feed continues reporting BTC prices. WBTC collateral is overvalued, enabling over-borrowing against depreciating collateral.
- **Common Contexts**: Lending protocols accepting WBTC as collateral, WBTC-denominated vaults, stablecoin AMOs

---

## PRICE-007: curve_get_virtual_price_manipulation
- **Frequency**: ~12/404
- **Severity**: HIGH
- **Code Shape**: `ICurvePool(pool).get_virtual_price()` used for LP token pricing; `calc_withdraw_one_coin` used as price oracle; `virtual_price` multiplied by LP balance for collateral/TVL; no read-only reentrancy guard on pools with ETH
- **Detection Heuristic**:
  1. Search for `get_virtual_price()` and `calc_withdraw_one_coin()` calls used in value-sensitive paths
  2. Check if the Curve pool has ETH as one of its assets — ETH-containing pools can be reentered during `raw_call` in old base pools
  3. Check if the protocol uses the virtual price for: LP token collateral valuation, TVL calculation, share price determination, liquidation triggers
  4. For read-only reentrancy: check if the protocol has a reentrancy guard that reads Curve's `get_virtual_price()` inside the guard — the guard must cover the Curve callback
  5. Check whether `get_virtual_price()` is being double-multiplied with LP balance (LP balance × virtual_price = double-counting)
- **Failure Mode**: Direct token donation to Curve pool inflates `get_virtual_price()` without changing pool state atomically. Read-only reentrancy on ETH-containing pools allows attacker to re-enter protocol during Curve's ETH transfer and read an inflated virtual price.
- **Common Contexts**: Curve LP token collateral pricing in lending, treasury/AMO contracts using Curve LP, stability mechanisms using Curve pools

---

## PRICE-008: uniswap_low_liquidity_pool_twap_manipulation
- **Frequency**: ~8/404
- **Severity**: HIGH (conditional on pool TVL)
- **Code Shape**: `quoteAllAvailablePoolsWithTimePeriod` including all liquidity tiers; TWAP oracle on pools with < $100k TVL; no minimum liquidity threshold before accepting TWAP; fallback oracle using spot from thin pool
- **Detection Heuristic**:
  1. Identify TWAP oracles using Uniswap V3 pools
  2. Check if there is a minimum TVL or liquidity threshold guard before accepting the price
  3. Look for `quoteAllAvailablePoolsWithTimePeriod` — this aggregates all fee tiers and thin pools can dominate if weighted equally
  4. Estimate the capital required to manipulate the TWAP over the configured window: lower TVL = lower manipulation cost
  5. Check for multi-pool aggregation with safeguards (e.g., median price, outlier rejection)
- **Failure Mode**: Thin pool TWAP can be moved by a relatively small capital injection over the observation window. Attacker gradually shifts the TWAP price over multiple blocks, then exploits the manipulated price in a final transaction.
- **Common Contexts**: Domain/ENS pricing from AMM pools, token launch price oracles, cross-protocol price references for low-cap tokens

---

## PRICE-009: incorrect_spot_price_scaling_or_decimal_handling
- **Frequency**: ~18/404
- **Severity**: HIGH
- **Code Shape**: `getRate()` ignoring `szDecimals`; `sqrtPriceX96` overflow from `uint256(sqrtPrice) * sqrtPrice` without `mulDiv`; token decimal mismatch in price calculation (`decimals = 18` hardcoded for non-18-decimal tokens); price scaled up twice; negative tick rounding direction wrong for Uniswap V3
- **Detection Heuristic**:
  1. Find price calculation functions: `getRate()`, `getPrice()`, `_getSpotPrice()`, `_calculatePrice()`
  2. Check for hardcoded decimal assumptions (e.g., `1e18` scaling when the token has 6 or 8 decimals)
  3. For Uniswap V3 price calculations: check that `sqrtPriceX96 * sqrtPriceX96` uses `mulDiv` to avoid overflow; check rounding direction for negative ticks (must round up, not down)
  4. For multi-pool interactions: trace how decimals flow through the formula — check that no intermediate step scales by a factor already applied
  5. For precompile-sourced prices: verify that `szDecimals` or the equivalent decimal normalization is applied
- **Failure Mode**: Price returned is off by a constant factor (e.g., 1e12×), causing massive over- or under-collateralization. For negative tick scenarios, rounding in the wrong direction consistently underprices one side. Overflow causes arithmetic revert, blocking liquidations.
- **Common Contexts**: Precompile-based oracle adapters (HyperEVM), Uniswap V3 tick-based price calculations, multi-pool aggregator oracles, cross-token vault share price formulas

---

## PRICE-010: missing_twap_for_liquidation_or_collateral_valuation
- **Frequency**: ~15/404
- **Severity**: HIGH
- **Code Shape**: `pool.slot0()` used in `_isLiquidatable()`, `_checkHealth()`, or collateral value computation; Chainlink spot feed (not TWAP) for liquidation decision; `lastPx` from order book used as oracle for perpetual margin checks
- **Detection Heuristic**:
  1. Find liquidation eligibility checks and collateral ratio calculations
  2. Trace the price source used in these checks — is it a spot price (slot0, lastPx, instantaneous oracle) or a time-averaged price?
  3. Check whether the protocol documentation specifies TWAP or spot for these decisions
  4. If spot price is used for liquidation: evaluate if an attacker can flash-move the spot price to trigger/prevent liquidation profitably
  5. Check the absence of a TWAP fallback — if the primary oracle returns spot, is there a secondary TWAP source?
- **Failure Mode**: Attacker manipulates AMM spot price within a single transaction to push a target position below the health ratio, triggering an unfair liquidation, or to push their own over-leveraged position above the health ratio, avoiding deserved liquidation.
- **Common Contexts**: Perpetual DEX margin systems, lending protocol health checks, CDP liquidation engines, NFT lending (floor price liquidation)

---

## PRICE-011: bonding_curve_or_amm_price_manipulation_first_mint
- **Frequency**: ~10/404
- **Severity**: HIGH
- **Code Shape**: When `ps == 0` (pool is empty), first LP sets the price implicitly; bonding curve with no reserve floor; `getPrice()` from AMM called before any liquidity is added; `buy votes` function with manipulable bonding curve input; `initPrice` derived from pool ratio at first deposit
- **Detection Heuristic**:
  1. Find bonding curve price functions and check behavior when reserve is 0 or `totalSupply == 0`
  2. Check if the first depositor controls the initial price ratio (e.g., by providing any ratio of assets)
  3. Check if there is a minimum liquidity lock or price floor constraint for pool initialization
  4. For graduated bonding curves (e.g., Virtuals Protocol): check if a flash loan can force premature graduation by briefly inflating reserves above the threshold
  5. Check `deployNewPool()` or factory functions for spot price reliance at initialization time
- **Failure Mode**: First LP provides an extreme ratio (e.g., 1 wei of tokenA, large tokenB), setting a manipulated initial price. All subsequent users trade against this skewed price. Or: attacker uses flash loan to trigger graduation early, manipulating reward distribution cutoffs.
- **Common Contexts**: Protocol token launch bonding curves, Uniswap V3 pool initialization, Panoptic-style option pool deployment, social token pricing (votes, keys)

---

## PRICE-012: sandwich_attack_on_deposit_or_withdrawal
- **Frequency**: ~20/404
- **Severity**: HIGH (especially on vault deposit/withdraw)
- **Code Shape**: `deposit()` and `withdraw()` use current spot NAV with no slippage parameter; `rebalance()` callable by anyone with no MEV protection; `commitAndClose()` with Uniswap swap and no `minOut`; `addLiquidity/removeLiquidity` with no deadline or minAmounts
- **Detection Heuristic**:
  1. Find deposit/withdrawal/rebalance functions that swap tokens internally
  2. Check for user-controlled slippage parameter — `minSharesOut`, `minAmountOut`, `deadline`
  3. Check for time-delay mechanisms that could decouple price at request vs. execution
  4. Check for permissioned callers on rebalance/reinvest — public access = easier to sandwich
  5. Evaluate whether the same transaction that manipulates the pool price can also call the target function
- **Failure Mode**: Attacker observes a large pending deposit/withdraw transaction. They front-run with a large swap to shift the price, allowing the victim's transaction to execute at the worst price, then back-run to restore the price and pocket the difference.
- **Common Contexts**: Vault deposit/withdrawal, LP management strategies, AMO rebalance operations, liquidity provision to Uniswap V3 from protocol contracts

---

## PRICE-013: pyth_oracle_timestamp_manipulation
- **Frequency**: ~5/404
- **Severity**: HIGH
- **Code Shape**: `pyth.updatePriceFeeds(updateData)` not validated for publish timestamp ordering; Pyth price commit without requiring `publishTime > previousCommitPublishTime`; anyone can call `updatePriceFeeds` with old data; `getPriceUnsafe()` used instead of `getPrice()`
- **Detection Heuristic**:
  1. Find Pyth oracle integration — `IPyth.updatePriceFeeds()`, `IPyth.getPriceNoOlderThan()`, `IPyth.getPriceUnsafe()`
  2. Check if `updatePriceFeeds` is access-controlled or callable by anyone
  3. Check whether the protocol enforces that the new price's `publishTime` is strictly greater than the previous price's `publishTime`
  4. Check for `getPriceUnsafe()` usage — this returns potentially stale prices without checking the confidence interval
  5. Check confidence interval handling — is the Pyth confidence interval used to bound the acceptable price range?
- **Failure Mode**: Attacker submits an old (time-traveling) Pyth price update that was valid in the past, setting the protocol's price to a manipulated historical value. This enables borrowing against overvalued collateral or forcing liquidations at stale prices.
- **Common Contexts**: Vault execution functions with Pyth-sourced prices, DeFi protocols on Solana/Aptos/EVM using Pyth, cross-chain price transmission using Pyth

---

## PRICE-014: lp_token_incorrect_pricing_formula
- **Frequency**: ~14/404
- **Severity**: HIGH
- **Code Shape**: LP token priced as `reserve0 * price0 / totalSupply` (uses only one reserve); LP token priced via `get_virtual_price()` without secondary validation; Curve v2 LP priced incorrectly using token ratio instead of invariant; Balancer LP using deprecated oracle; Curve composable pool using wrong invariant formula
- **Detection Heuristic**:
  1. Find LP token pricing functions in oracles or collateral managers
  2. For Uniswap V2 LP: check if the fair LP pricing formula is used (geometric mean of reserves × price), not simple ratio
  3. For Curve LP: check which method is used — `get_virtual_price()` alone is manipulable via donation; prefer `lp_price()` or the safe pricing approach
  4. For Balancer LP: check if the oracle is deprecated and if the token price formula accounts for the invariant, not just spot balances
  5. For Curve V2/Crypto pools: verify the correct invariant (gamma-based, not StableSwap) is used; check decimal normalization across tokens with different precisions
- **Failure Mode**: LP token is mispriced (over or under). Overpricing enables borrowing more than the LP's true value. Underpricing triggers false liquidations. Wrong invariant formula produces incorrect LP token values that diverge as pool composition changes.
- **Common Contexts**: Lending protocols accepting LP tokens as collateral, treasury contracts holding Curve/Balancer LP positions, vault TVL calculations using LP prices

---

## PRICE-015: incorrect_twap_implementation
- **Frequency**: ~10/404
- **Severity**: HIGH
- **Code Shape**: `sumNative / sumUSD` TWAP averages computed with incorrect accumulation logic; TWAP oracle array of 4 observations with insufficient time spread; `_BASE_PRICE_CUMULATIVE_LAST_` in MagicLP updated incorrectly; TWAP period calculation ignoring time-to-maturity; Chainlink TWAP used with wrong delta between rounds
- **Detection Heuristic**:
  1. Find custom TWAP implementations (not using Uniswap's built-in TWAP)
  2. Check the accumulation logic: is `sumPrice` divided by `count` or by `timeDelta`? These produce different results
  3. Check that the observation array is properly initialized before use — newly registered assets with 0 observations can skew results
  4. Check whether the TWAP correctly accounts for the arithmetic: cumulative prices must be divided by elapsed seconds, not observation count
  5. For option pricing: verify that `period` in the Black-Scholes formula is the time-to-maturity, not a TWAP lookback window
- **Failure Mode**: TWAP returns wrong price due to accumulation bug. Incorrect TWAP enables systematic over/under pricing that compounds over time and can be exploited to extract protocol funds or avoid proper liquidations.
- **Common Contexts**: Custom TWAP oracle implementations, AMM internal price tracking, Vader Protocol-style liquidity pool oracles, option protocol period calculations

---

## PRICE-016: reentrancy_through_oracle_read
- **Frequency**: ~7/404
- **Severity**: HIGH
- **Code Shape**: `get_virtual_price()` called inside or after ETH transfer in same call stack; no reentrancy guard on oracle-reading function; `CurveV2CryptoEthOracle` readable during WETH unwrap callback; read-only view function used to calculate collateral during a reentrant state
- **Detection Heuristic**:
  1. Find functions that both (a) make ETH transfers or external calls and (b) read Curve/external oracle prices
  2. Check if there is a reentrancy guard covering the entire function including the oracle read
  3. For Curve crypto pools with WETH: check if `get_virtual_price()` is called after any token transfer that could trigger a WETH receive hook
  4. Check for the classic pattern: `nonReentrant` only on the outer function but oracle is called from an inner function that is not guarded
  5. Check if read-only view functions that read oracle prices are used by guarded write functions — view functions are not protected by `nonReentrant`
- **Failure Mode**: Attacker re-enters the protocol during an ETH/WETH transfer, reads an inflated `get_virtual_price()` (since the pool's reserves are mid-state during the callback), and uses this to over-borrow or steal value.
- **Common Contexts**: Curve ETH-containing pool oracles, protocols using raw ETH transfers with Curve V2 oracles, lending vaults using Curve LP as collateral

---

## PRICE-017: flash_loan_price_manipulation_single_tx
- **Frequency**: ~18/404
- **Severity**: HIGH
- **Code Shape**: Price oracle read in same transaction as flash loan without a time lock; `price = reserve1 / reserve0` computed from AMM state that can be changed by flash borrowing; no `_minLockPeriod` or lock on the oracle; `isFlashLoanProtected()` check bypassable via self-liquidation
- **Detection Heuristic**:
  1. Find price functions reading from AMM reserves: `reserve0`, `reserve1`, pool balances
  2. Check if a flash loan to the same pool can move the price in the same block
  3. Check for flash loan protection mechanisms (lock period, block number check, TWAP) and verify they cannot be bypassed
  4. For lending protocols: check if the anti-flash loan mechanism (block check) can be bypassed via self-liquidation or other indirect paths
  5. Check `purchasePyroFlan()`, `realise()`, `exitEarly()` and similar functions that read spot price from AMM and are callable in a single transaction
- **Failure Mode**: Attacker takes a flash loan, moves the AMM price, executes the exploitable function (over-borrows, gets inflated tokens, triggers wrong settlement), then repays flash loan — all in one transaction.
- **Common Contexts**: Synth protocols, AMO mechanisms, redemption functions, liquidation bypass scenarios, protocol-owned liquidity systems

---

## PRICE-018: missing_price_deviation_check_between_oracles
- **Frequency**: ~8/404
- **Severity**: MEDIUM
- **Code Shape**: Only one oracle source used without cross-checking; two oracle sources where either one failing falls through to no validation; `maxDeviation` too large (e.g., 50%); deviation check using asymmetric formula; Chainlink vs. TWAP discrepancy not validated
- **Detection Heuristic**:
  1. Count oracle sources used in the protocol — single source = no cross-validation
  2. If multiple sources: find the deviation check logic — `abs(priceA - priceB) / priceA <= MAX_DEVIATION`
  3. Check `MAX_DEVIATION` parameter — is it hardcoded? Configurable? Is the configured value reasonable (< 5% for stablecoins, < 20% for volatile assets)?
  4. For asymmetric deviation checks: verify that `|A-B|/A` and `|A-B|/B` are both checked, or that the formula uses the correct reference denominator
  5. Check what happens when one oracle fails: does the protocol fall back to the other source without deviation check, or does it revert?
- **Failure Mode**: A compromised or manipulated single oracle feeds wrong prices without detection. Or the deviation threshold is so large that a significantly manipulated price passes the check, enabling exploitation.
- **Common Contexts**: Dual-oracle lending protocols (Chainlink + TWAP), stablecoin stability mechanisms, protocols using Redstone + Chainlink, frame oracle implementations using median

---

## PRICE-019: insufficient_price_freshness_check
- **Frequency**: ~12/404
- **Severity**: MEDIUM
- **Code Shape**: Oracle result cached in storage and read without freshness check; `MaltDataLab.getPrice()` returning stale MovingAverage results; `perp_spot_price_for_withdrawal` not updated on withdrawals; `rsETHPrice` read directly without calling update function first; price cached with no expiry TTL
- **Detection Heuristic**:
  1. Find state variables storing oracle prices or exchange rates
  2. Check when these cached values are updated — is the update called before every read, or only periodically?
  3. Check for staleness TTL: `require(block.timestamp - lastUpdateTime <= maxAge)` or equivalent
  4. Check for functions that perform actions using a cached price without first refreshing it (e.g., `withdraw()` reading `rsETHPrice` without calling `updateRSETHPrice()`)
  5. For moving average oracles: check the update frequency relative to the observation window — infrequent updates mean the moving average lags significantly
- **Failure Mode**: Protocol uses an arbitrarily old cached price. During market movements, this creates exploitable arbitrage: borrow against stale high price collateral when actual value has dropped, or redeem at stale favorable rate.
- **Common Contexts**: LST/LRT protocols with periodic price updates, moving average oracle integrations, withdrawal-rate caching in DeFi protocols, cross-chain price relay systems

---

## PRICE-020: uniswap_pool_initialization_frontrun
- **Frequency**: ~5/404
- **Severity**: MEDIUM
- **Code Shape**: `Router.getOrCreatePoolAndAddLiquidity()` callable by anyone before protocol deployment; `deployNewPool()` using spot price at time of call; pool initialized with first-provided ratio setting the price; no TWAP available for newly created pool
- **Detection Heuristic**:
  1. Find factory or router functions that create new pools
  2. Check if pool creation is access-controlled or permissionless
  3. Check if the initial price/ratio is supplied by the caller or hardcoded — caller-supplied initial price is front-runnable
  4. For protocols reading TWAP from a newly created pool: verify there is a check that the pool has existed long enough for TWAP to be reliable
  5. Check `deployNewPool()` for Panoptic-style protocols — spot price at creation can be sandwiched
- **Failure Mode**: Attacker front-runs pool creation, setting an extreme initial price. Protocol mints shares at the wrong ratio, causing loss to subsequent liquidity providers or enabling extraction via the manipulated price.
- **Common Contexts**: Permissionless pool creation in DeFi, option market initialization, ILO (Initial Liquidity Offering) launch mechanics, automated LP management protocol setup

---

## PRICE-021: incorrect_balancer_amplification_or_stable_invariant
- **Frequency**: ~6/404
- **Severity**: HIGH
- **Code Shape**: Balancer amplification parameter `A` used without `A * N^(N-1)` encoding; `getAmplificationParameter()` precision divisor not applied; StableSwap invariant computed for Balancer composable pools using wrong formula; Curve-forked protocol using wrong Newton-Raphson convergence
- **Detection Heuristic**:
  1. Find Balancer StablePool or composable pool integrations — specifically `getAmplificationParameter()` calls
  2. Check if the returned value accounts for Balancer's precision scaling (returned value is `A * 1000`, must divide before use)
  3. For Curve forks: check that `get_D` / `get_y` Newton-Raphson implementation converges correctly and uses same precision as reference
  4. Check the invariant formula for composable stable pools: uses BPT total supply differently than regular stable pools
  5. Verify that decimal normalization is applied when pool tokens have different precisions
- **Failure Mode**: Wrong amplification parameter produces systematically wrong prices from the invariant. This causes LP token mispricing, incorrect swap amounts, and wrong collateral valuations for all positions in the affected pool.
- **Common Contexts**: Balancer MetaStable and Composable pool integrations in lending protocols, Curve fork deployments (StableSwap compliance), Notional Finance-style rate calculations using Balancer pools

---

## PRICE-022: missing_ltv_gap_between_borrow_and_liquidation
- **Frequency**: ~5/404
- **Severity**: HIGH
- **Code Shape**: `borrowLTV == liquidationThreshold` (no buffer); `isMarginCall()` using wrong threshold (liquidation threshold instead of margin call threshold); LTV buffer of less than 2–5%; self-liquidation profitable because liquidation bonus > LTV gap
- **Detection Heuristic**:
  1. Find LTV (loan-to-value) and liquidation threshold parameters
  2. Check if `maxBorrowLTV < liquidationThreshold` with a meaningful gap (at least 2–5%)
  3. Check the margin call / health check functions — do they use the correct threshold (margin call ≠ liquidation threshold)?
  4. Simulate: if a user borrows at max LTV and price drops 1%, can they self-liquidate profitably?
  5. Check liquidation bonus: `liquidationBonus > (liquidationThreshold - borrowLTV)` → self-liquidation is profitable
- **Failure Mode**: User borrows at max LTV which equals liquidation threshold. Any tiny price drop makes them instantly liquidatable with no buffer. Alternatively, user borrows and immediately self-liquidates if the liquidation bonus exceeds the nonexistent LTV gap.
- **Common Contexts**: Lending protocols (CDP, isolated markets), perpetual trading margin systems, NFT lending protocols

---

## PRICE-023: oracle_price_update_ordering_vulnerability
- **Frequency**: ~6/404
- **Severity**: MEDIUM
- **Code Shape**: `updatePhase()` callable before current phase ends, recording wrong `endRoundId`; `addFundsAndFulfillRedeem()` order-dependent state updates; oracle update accepting prices from different symbols interchangeably; price committed using wrong round reference
- **Detection Heuristic**:
  1. Find oracle update functions — `updatePhase()`, `commit()`, `recordPrice()`
  2. Check if there are ordering constraints: can the function be called before its designated time?
  3. Check if the symbol/asset parameter is validated — can an attacker supply a different asset's price feed?
  4. For multi-step settlement flows: check if price capture and settlement happen atomically or can be split across blocks
  5. Check what round ID is recorded and whether it corresponds to the correct price point in time
- **Failure Mode**: Premature phase update records wrong `endRoundId`, allowing attacker to influence which historical price is used for settlement. Cross-symbol update uses a different asset's price, causing systematic mispricing for options or structured products.
- **Common Contexts**: Options settlement oracles (Divergence Protocol), structured product price recording, periodic price checkpoint systems

---

## PRICE-024: off_chain_oracle_centralization_or_signature_weakness
- **Frequency**: ~6/404
- **Severity**: MEDIUM
- **Code Shape**: Single `priceOracleSigner` whose compromise enables arbitrary price setting; ECDSA signature validation without nonce replay protection; oracle signature without expiry timestamp; weak signature check allowing multiple mispricing vectors
- **Detection Heuristic**:
  1. Find off-chain price oracle patterns: `ecrecover`, ECDSA.recover with a signer address
  2. Check if there is more than one required signer (threshold signature scheme)
  3. Check for replay protection: nonce in the signed message? Unique-per-price-update commitment?
  4. Check signature expiry: is the signed price only valid for a time window?
  5. Check for cross-chain replay: is the chain ID included in the signed message?
- **Failure Mode**: Compromised oracle signer key allows setting arbitrary prices. Replayed valid signatures from past (higher/lower) prices can be submitted at strategic moments. Without expiry, attacker can hold valid signatures and submit them when most advantageous.
- **Common Contexts**: Off-chain price oracle protocols, option pricing systems with signed prices, NFT appraisal oracles with admin signers

---

## PRICE-025: missing_minimum_sample_size_for_oracle_aggregation
- **Frequency**: ~4/404
- **Severity**: MEDIUM
- **Code Shape**: `process()` accepting price from single oracle node of a type; median price with 2 reporters (1 vs 1 tie); `MaltDataLab` with too-few samples in MovingAverage; oracle accepting 1 of N reporters without threshold; newly added asset with 0 historical observations skewing TWAP result
- **Detection Heuristic**:
  1. Find oracle aggregation logic: `median()`, `average()`, price consultation
  2. Check the minimum number of independent reporters required before publishing a price
  3. Check for newly registered assets — are they allowed to influence the aggregate price with 0 observations?
  4. For median oracles: verify that the process function rejects duplicate oracle nodes of the same type
  5. Check the TWAP observation array initialization: uninitialized entries default to 0, which skews averages
- **Failure Mode**: With too few samples (e.g., 2 reporters), a single manipulated submission can control the median. A newly added asset with 0 observations skews cumulative averages toward incorrect values.
- **Common Contexts**: Compound Open Oracle, multi-node DAO oracle systems, TWAP implementations with observation arrays, on-chain price aggregators

---

## PRICE-026: incorrect_rounding_direction_in_price_calculation
- **Frequency**: ~8/404
- **Severity**: MEDIUM
- **Code Shape**: Division rounding toward zero when it should round up (or vice versa) in price computation; `mulDiv` used with `Rounding.Down` when protocol should round against the user; put option rounding in same direction as call option (should be opposite); precision loss in `setMaxSpotOffsetBps`
- **Detection Heuristic**:
  1. Find price-sensitive division operations in collateral, fee, and share calculations
  2. Determine the favoring direction: operations that calculate how many tokens to send OUT should round down; operations calculating how many tokens to take IN should round up
  3. For option protocols: put and call options have opposite rounding requirements — verify they are not both using the same direction
  4. Check `mulDiv` calls for the `rounding` parameter — is it `Rounding.Up` or `Rounding.Down`? Does this match the intended behavior?
  5. Check tick-based price functions for negative ticks — Uniswap V3 tick prices must round up for negative ticks, not down
- **Failure Mode**: Systematic rounding in favor of the protocol (or attacker) causes small losses per transaction that compound. Incorrect put/call rounding reduces the safety margin of options. Tick rounding error produces consistently wrong prices for negative-tick pools.
- **Common Contexts**: ERC4626 share conversions, option premium calculations, AMM tick price calculations, fee calculations in basis points

---

## PRICE-027: l2_sequencer_downtime_oracle_vulnerability
- **Frequency**: ~3/404
- **Severity**: MEDIUM
- **Code Shape**: Uniswap V3 TWAP on L2 without sequencer uptime check; Chainlink oracle on Arbitrum/Optimism without `sequencerUptimeFeed`; TWAP accumulates no observations during sequencer downtime but reports stale price after restart
- **Detection Heuristic**:
  1. Check the deployment chain: is this an L2 (Arbitrum, Optimism, Base, etc.)?
  2. Find Chainlink oracle usage — check for `sequencerUptimeFeed` validation before using oracle price
  3. For Uniswap V3 TWAP on L2: during sequencer downtime, the oracle accumulates no ticks, so after restart the TWAP reflects a period with no data — check if this is handled
  4. Check for a grace period after sequencer restart before price consumption resumes
  5. Check whether the L2 sequencer can reorder transactions to manipulate TWAP observations
- **Failure Mode**: After sequencer downtime, stale prices from before the downtime continue to be used. Market prices may have moved significantly during downtime, enabling borrowing against overvalued collateral or bypassing liquidations at the restart.
- **Common Contexts**: Any DeFi protocol deployed on L2 chains using Chainlink or Uniswap V3 TWAP oracles

---

## PRICE-028: spot_price_used_for_domain_nft_or_vote_pricing
- **Frequency**: ~5/404
- **Severity**: HIGH
- **Code Shape**: `getDomainPrice()` calling AMM spot price; NFT floor price from on-chain pool's current tick; vote/key pricing from bonding curve whose reserve can be flash-manipulated; `book_price` derived from order book state
- **Detection Heuristic**:
  1. Find non-financial pricing functions that determine the cost of protocol actions (domain registration, governance votes, NFT purchases)
  2. Check whether the underlying price source is an on-chain AMM spot price
  3. Check if a flash loan or large trade can move this price within one transaction and then trigger the priced action
  4. Check for minimum time locks between price reads and action execution
  5. Evaluate the economic incentive: what is the gain from a cheap domain/vote vs. the cost of manipulating the pool?
- **Failure Mode**: Attacker flash-manipulates the AMM price downward to buy domains/votes/NFTs at a fraction of their intended cost, then restores the price. Or manipulates upward to block others from buying.
- **Common Contexts**: ENS-style domain pricing from AMM pools (Initia), social token voting (Ethos Network), bonding curve-based governance, NFT marketplace pricing, DeFi protocol fee tiers priced by token ratio

---

## PRICE-029: perp_market_price_used_as_spot_oracle
- **Frequency**: ~4/404
- **Severity**: LOW-MEDIUM
- **Code Shape**: Perp oracle using `mark_price` or `last_px` from perpetual market as spot reference; NAV calculated using perpetual mark price instead of underlying spot price; instruments without oracle feed falling back to spot market's last traded price
- **Detection Heuristic**:
  1. Find oracle modules in perpetual trading protocols
  2. Check which price is used for NAV calculation: mark price (funding-rate-adjusted) vs. underlying spot price
  3. Check fallback behavior when a configured oracle feed is absent — does it use the perpetual's internal last price?
  4. Assess the divergence risk: during high funding rates, mark price can significantly deviate from spot
  5. Check if the NAV mismatch enables arbitrage between NAV-based deposits/withdrawals and the true market value
- **Failure Mode**: Vault NAV is calculated using perp mark price during periods of large funding rate divergence. Users can deposit when mark is below spot (get more shares) or redeem when mark is above spot (get more assets), draining the vault.
- **Common Contexts**: Perpetual DEX vaults, delta-neutral yield strategies, perp-integrated structured products

---

## PRICE-030: donation_attack_on_totalassets_or_reserve
- **Frequency**: ~8/404
- **Severity**: HIGH
- **Code Shape**: `totalAssets()` returns `token.balanceOf(address(this))`; `getVirtualPrice()` or share price derivable from contract's raw token balance; `pocketUSDC` balance accessible by direct ERC20 transfer; `totalFunds()` not accounting for pending external positions
- **Detection Heuristic**:
  1. Find `totalAssets()`, `totalFunds()`, `getPrice()` implementations that use `balanceOf(address(this))`
  2. Check if an external party can transfer tokens directly to the contract (permissionless ERC20 transfer) without going through the deposit function
  3. Check whether the affected calculation feeds into share price, collateral value, or TVL reporting
  4. Calculate if donation-based inflation produces a rounding attack (single-share inflation) or a price manipulation (general inflated price for all shares)
  5. Check for token standards with transfer hooks (ERC777, ERC677) that could be triggered during the attack
- **Failure Mode**: Attacker donates tokens to the contract, inflating `totalAssets()`. Depending on context: (a) share price inflates, later depositors receive fewer shares per dollar; (b) TVL-based metrics are wrong, enabling wrong fee calculations or circuit breaker bypasses; (c) first-depositor shares are worth more than they should be.
- **Common Contexts**: ERC4626 vaults, Curve pool virtual price, PSM (Peg Stability Module) balance calculations, any contract using raw balance for valuation

---

> **Pattern Summary**
>
> | # | Pattern | Severity | Count |
> |---|---------|----------|-------|
> | PRICE-001 | Uniswap slot0 spot price usage | HIGH | ~38 |
> | PRICE-002 | ERC4626 first depositor share inflation | HIGH | ~22 |
> | PRICE-003 | Missing slippage protection on swap | HIGH | ~35 |
> | PRICE-004 | TWAP period too short or zero | MEDIUM | ~18 |
> | PRICE-005 | Chainlink stale price no staleness check | MEDIUM | ~20 |
> | PRICE-006 | WBTC/BTC price feed depeg risk | MEDIUM | ~4 |
> | PRICE-007 | Curve get_virtual_price manipulation | HIGH | ~12 |
> | PRICE-008 | Uniswap low liquidity pool TWAP manipulation | HIGH | ~8 |
> | PRICE-009 | Incorrect spot price scaling or decimal handling | HIGH | ~18 |
> | PRICE-010 | Missing TWAP for liquidation or collateral valuation | HIGH | ~15 |
> | PRICE-011 | Bonding curve or AMM price manipulation at first mint | HIGH | ~10 |
> | PRICE-012 | Sandwich attack on deposit or withdrawal | HIGH | ~20 |
> | PRICE-013 | Pyth oracle timestamp manipulation | HIGH | ~5 |
> | PRICE-014 | LP token incorrect pricing formula | HIGH | ~14 |
> | PRICE-015 | Incorrect TWAP implementation | HIGH | ~10 |
> | PRICE-016 | Reentrancy through oracle read | HIGH | ~7 |
> | PRICE-017 | Flash loan price manipulation single tx | HIGH | ~18 |
> | PRICE-018 | Missing price deviation check between oracles | MEDIUM | ~8 |
> | PRICE-019 | Insufficient price freshness check | MEDIUM | ~12 |
> | PRICE-020 | Uniswap pool initialization frontrun | MEDIUM | ~5 |
> | PRICE-021 | Incorrect Balancer amplification or stable invariant | HIGH | ~6 |
> | PRICE-022 | Missing LTV gap between borrow and liquidation | HIGH | ~5 |
> | PRICE-023 | Oracle price update ordering vulnerability | MEDIUM | ~6 |
> | PRICE-024 | Off-chain oracle centralization or signature weakness | MEDIUM | ~6 |
> | PRICE-025 | Missing minimum sample size for oracle aggregation | MEDIUM | ~4 |
> | PRICE-026 | Incorrect rounding direction in price calculation | MEDIUM | ~8 |
> | PRICE-027 | L2 sequencer downtime oracle vulnerability | MEDIUM | ~3 |
> | PRICE-028 | Spot price used for domain/NFT/vote pricing | HIGH | ~5 |
> | PRICE-029 | Perp market price used as spot oracle | LOW-MEDIUM | ~4 |
> | PRICE-030 | Donation attack on totalAssets or reserve | HIGH | ~8 |
