# DEX & AMM Logic Patterns
> Extracted from 5,324 findings (500 sampled)
> Pattern count: 32

---

## DEX-001: Missing or Ineffective Slippage Protection
- **Frequency**: ~38/500
- **Severity**: HIGH
- **Code Shape**: `swap(...)` / `addLiquidity(...)` / `removeLiquidity(...)` with `amountOutMin = 0` hardcoded, or slippage parameter accepted from user but never enforced (checked then discarded), or `sqrtPriceLimitX96 = 0` passed to UniswapV3, or `minTokenAmounts_` computed from stale/manipulable data
- **Detection Heuristic**:
  1. Find all swap/liquidity entry points that accept a `minAmountOut` or slippage bound
  2. Trace whether that bound is actually passed to the DEX call (not just validated locally then dropped)
  3. Check for `amountOutMin = 0` literals or computed as `0` from percentages (e.g. `amount * 0 / 100`)
  4. For UniswapV3: check `sqrtPriceLimitX96`—if it's `0` or `TickMath.MIN_SQRT_RATIO`/`MAX_SQRT_RATIO` it allows full price movement
  5. For multi-hop swaps, verify each hop has its own bound, not just the final output
  6. Check if a declared `slippageTolerance` variable is used in the actual call or is a dead variable
- **Failure Mode**: Sandwich attack extracts value between user transaction submission and execution; MEV bots manipulate pool price before the swap executes, returning far fewer tokens than expected
- **Common Contexts**: Protocol-internal swaps (rebalance, reward liquidation, fee collection), ERC-2612 permit-based swaps, emergency exits, leverage/deleverage operations, cross-chain swap bridges

---

## DEX-002: Spot Price Oracle Manipulation (Uniswap slot0 / reserve-ratio abuse)
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: `IUniswapV3Pool(pool).slot0()` used for pricing; `reserve0/reserve1` ratio used without TWAP; `token.balanceOf(pool)` used to derive price; `getReserves()` result used for price-sensitive operations
- **Detection Heuristic**:
  1. Search for `slot0()`, `getReserves()`, `balanceOf(pool)` in price-calculation paths
  2. Check if result feeds into: collateral valuation, liquidation threshold, borrow limit, reward calculation, minting ratio
  3. Determine whether a flash loan can move the spot price in the same block as the dependent operation
  4. If the spot price feeds a `consult()` oracle rather than a TWAP oracle, flag it
  5. Check if `sqrtPriceX96` from `slot0` is used for liquidity math (should use TWAP equivalent)
- **Failure Mode**: Attacker flash-borrows large amount, moves pool price, exploits the distorted price (cheap collateral, inflated rewards, unfair liquidation), returns flash loan in same transaction
- **Common Contexts**: Lending protocols using UniV2/V3 as price oracle, collateral valuation for CDP, reward rate calculation, bonding curves that read pool price, oracle-free perpetuals using last traded price

---

## DEX-003: Sandwich Attack on Protocol-Owned Swaps
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: Protocol calls `swap()` or `swapExactTokensForTokens()` with no deadline or `deadline = block.timestamp`; `swapBack()` function callable by anyone or triggered automatically; rebalance/reinvest logic that swaps large amounts without slippage guard
- **Detection Heuristic**:
  1. Identify all swap calls made by the protocol itself (not by users passing their own params)
  2. Check for missing or trivially-satisfied `deadline` (e.g., `block.timestamp`)
  3. Check for `amountOutMin = 0` or slippage computed from stale state
  4. Determine whether these swaps can be triggered by an unprivileged caller
  5. Check if swap amount is predictable (e.g., entire token balance), making front-run easy
- **Failure Mode**: Attacker front-runs protocol swap by moving pool price, then back-runs to profit; protocol receives far fewer tokens than market rate; sandwich is risk-free for attacker when `amountOutMin = 0`
- **Common Contexts**: Treasury rebalancing, reward token liquidation (`swapBack`), auto-compounding vaults, fee collection swaps, emergency withdrawal mechanisms

---

## DEX-004: First Depositor / Vault Inflation Attack
- **Frequency**: ~18/500
- **Severity**: HIGH (often CRITICAL)
- **Code Shape**: ERC4626 or custom vault where `totalSupply == 0` on first deposit; shares minted via `deposit * totalSupply / totalAssets`; no minimum deposit or virtual shares offset; `depositNative()` or `deposit()` with `totalShares = 0` guard absent
- **Detection Heuristic**:
  1. Find `convertToShares()` or equivalent: check if `totalSupply == 0` path mints 1:1 or fixed amount
  2. Check if attacker can deposit 1 wei, receive 1 share, then donate large amount to inflate `totalAssets`
  3. Verify if subsequent depositor's shares round down to 0 due to inflated exchange rate
  4. Check for OZ `_initialConvertToShares` virtual share offset (1000 shares) as mitigation
  5. For Compound forks: check `exchangeRateStored()` initialization and `mintFresh` guard
- **Failure Mode**: Attacker mints 1 share with 1 wei, donates `X` tokens directly, next depositor's `Y` tokens yield `Y * 1 / (X + 1) = 0` shares (rounds to 0), attacker then redeems 1 share for `X + Y` tokens
- **Common Contexts**: Any ERC4626 vault, Compound CToken forks, LP token vaults, staking contracts that track shares

---

## DEX-005: TWAP Oracle Implementation Errors
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: `priceCumulativeLast` addition that overflows without `unchecked`; wrong token order in `TWAPOracle` (token0/token1 swapped); incorrect TWAP interval (too short = manipulable, hardcoded wrong value); `currentCumulativePrices()` reverts on overflow in checked arithmetic
- **Detection Heuristic**:
  1. Find `cumulativePrice` arithmetic: check if it uses `unchecked` (UniV2 intentionally wraps)
  2. Verify `token0` vs `token1` order matches the pair contract's storage layout
  3. Check TWAP period: less than 30 minutes on mainnet is manipulable; hardcoded blocks-per-year constant may be wrong for the target chain
  4. For UniV3: check `OracleLibrary.consult()` cardinality—if pool has only 1 observation, TWAP is spot price
  5. Check if TWAP is used on L2 without sequencer uptime check (stale prices during downtime)
  6. Verify `tickCumulatives` division uses the right interval (signed integer arithmetic required)
- **Failure Mode**: Wrong token order returns inverted price; overflow revert breaks oracle permanently; insufficient TWAP period allows manipulation via sustained position; L2 sequencer downtime yields stale price
- **Common Contexts**: On-chain TWAP oracles for lending, governance, synthetic asset pricing, UniV2/V3-based oracles

---

## DEX-006: Reentrancy in AMM/DEX Functions
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: State update after external call in `swap()`, `mint()`, `burn()`; callback pattern (UniV3 `uniswapV3MintCallback`, `uniswapV3SwapCallback`) with no sender validation; `onERC721Received` that modifies pool state; `borrow()` or `lend()` that calls `msg.sender` before updating state
- **Detection Heuristic**:
  1. Find all external calls (`.call`, token transfers, NFT callbacks) in swap/liquidity functions
  2. Check if state variables (balances, reserves, totalSupply) are updated BEFORE the external call (CEI pattern)
  3. For UniV3 callback functions: verify `msg.sender` is validated against `factory.getPool()`
  4. Check for read-only reentrancy: even view functions reading AMM state during callback can be exploited
  5. Look for `uniswapV3MintCallback` / `uniswapV3SwapCallback` accessible without factory check
- **Failure Mode**: Attacker reenters during callback to observe or manipulate state before it's updated; callback-based drain of approved tokens; read-only reentrancy enables price manipulation at snapshot
- **Common Contexts**: UniswapV3 position managers, flash swap callbacks, ERC777 token interactions in AMM, custom DEX swap implementations with callbacks

---

## DEX-007: Incorrect Fee Calculation or Fee Accounting
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `feeGrowthInside` calculation that uses uninitialized tick data; fees computed with wrong base (APY used as per-second rate); fee variable overwritten instead of accumulated; `tokensOwed0`/`tokensOwed1` read from cached (pre-liquidation) state; uplift fee applied to total instead of increment
- **Detection Heuristic**:
  1. For UniV3 forks: verify `feeGrowthInsideLast` is initialized when tick crosses (not left at 0)
  2. Check fee rate unit: confirm whether it's basis points, per-second, per-block, or APY—wrong unit causes massive over/undercharge
  3. Find reward/fee accumulator variables: check if they're added to (+=) or overwritten (=)
  4. Check `getOwedFee` for underflow when `feeGrowthInside < feeGrowthInsideLast` (should wrap in unchecked per Uni spec)
  5. For position value queries: verify fees-pending (`tokensOwed`) are included in valuation
- **Failure Mode**: LPs receive zero or wrong fees; fee underflow causes `getOwedFee` to return 0; position is under-valued because pending fees are excluded; incorrect APY-as-rate causes extreme overcharging
- **Common Contexts**: Concentrated liquidity AMMs (UniV3 forks), staking reward contracts, perpetual fee accounting, gauge reward distribution

---

## DEX-008: Incorrect Liquidity / Reserve Accounting After Operations
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `reserve` or `totalLiquidity` not decremented on withdrawal; `withdrawalPool.raBalance` not updated on redemption; `lockedAmount` not decreased when position is closed; accounting tracks both user assets and collected fees in the same variable
- **Detection Heuristic**:
  1. For every state-decreasing operation (withdraw, redeem, burn, close): verify ALL related accounting variables are updated
  2. Check for asymmetric pairs: if `deposit` increments `X`, does `withdraw` decrement `X`?
  3. Search for variables updated conditionally (`if success`) that should always update
  4. Check if fee variables are separate from principal variables (commingling causes misaccounting)
  5. Look for "saved" or "stored" totals that are updated lazily—stale values can diverge from actual state
- **Failure Mode**: Protocol believes it has more (or fewer) assets than it does; subsequent operations use wrong reserve ratios; users can withdraw more than their share by exploiting the discrepancy
- **Common Contexts**: Vault withdrawal pools, LP position managers, perpetual funding accounting, locked token contracts, DCA order processing

---

## DEX-009: Pool Initialization Frontrunning
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `pool.initialize(sqrtPriceX96)` called in a separate transaction from pool creation; `createPool` followed by `initialize` in different txs; `startSqrtPriceX96` set permissionlessly; factory deployment address predictable via CREATE2
- **Detection Heuristic**:
  1. Find protocol flows where pool creation and initialization are separate transactions
  2. Check if `initialize()` is permissionless (no `onlyOwner` or factory guard)
  3. For CREATE2 pools: verify if the salt is predictable and whether pool can be pre-initialized by attacker
  4. Check if initial price validation exists (`require(initialPrice within bounds)`)
  5. Verify `addLiquidity` or `deposit` after initialization checks price hasn't been manipulated
- **Failure Mode**: Attacker initializes pool at extreme price; protocol's subsequent `addLiquidity` at "fair price" gets sandwiched; first LP loses most funds; initial price sets a manipulated baseline for TWAP
- **Common Contexts**: UniV3-based launchpads, protocol-owned liquidity deployment, token launches with bonding curves, TWAMM initialization

---

## DEX-010: Wrong Token Order / Reserve Mapping
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `getReserves()` returns `(reserve0, reserve1)` but code uses `(reserveA, reserveB)` where A/B ≠ token0/token1 based on address sort; `token0` vs `token1` hardcoded assumption without checking pair ordering; price computed as `reserve0/reserve1` when correct is `reserveQuote/reserveBase`
- **Detection Heuristic**:
  1. Find all `getReserves()` calls: trace which return value is assigned to which token variable
  2. Verify the assignment matches the actual sort order (UniV2: token0 < token1 by address)
  3. For price feeds: check if `priceFeed.latestAnswer()` returns base/quote or quote/base vs what the code assumes
  4. Search for hardcoded assumptions like "WETH is always token1" in multi-pool contracts
  5. For Curve tricrypto: verify WETH/BTC position is not assumed to always be at a specific index
- **Failure Mode**: Price is inverted (or wildly wrong); swaps execute at wrong rate; collateral values are inverted, causing immediate liquidations or bad debt
- **Common Contexts**: UniV2 price oracles, cross-protocol adapters, Curve LP price calculation, Chainlink rate inversion bugs, multi-token pool index assumptions

---

## DEX-011: Decimal Scaling / Unit Mismatch in Price or Amount Calculations
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: Token amount used without scaling to 18 decimals before division; price from Chainlink (8 decimals) multiplied by token amount (6 decimals) without normalization; `sqrtPriceX96` decoded without accounting for token decimal difference; double conversion (integer cast applied twice)
- **Detection Heuristic**:
  1. Find all cross-token arithmetic (price × amount): check that both operands use consistent decimal bases
  2. For Chainlink prices: verify `10 ** decimals()` scaling is applied when tokens have non-18 decimals
  3. For UniV3 `sqrtPriceX96`: check if decimal difference between token0/token1 is applied during price reconstruction (`price = sqrtP^2 / 2^192 * 10^(d0-d1)`)
  4. Search for `/ 1e18` or `* 1e18` followed immediately by another scaling operation—double-scaling bug
  5. For stableswap with mixed decimals: check if amounts are normalized before the invariant calculation
- **Failure Mode**: Token amounts are off by `10^N` factor; massive over/under pricing; LP shares computed incorrectly; users receive 10^12x more or fewer tokens than expected
- **Common Contexts**: Stableswap pools with 6-decimal USDC, UniV3 position valuation, Chainlink-based price feeds, cross-chain bridged token price feeds, any oracle consumer

---

## DEX-012: Flash Loan Price Manipulation
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `calculateLoss()`, `purchasePyroFlan()`, `getPrice(CurveOracle)` or any price-sensitive function that reads from a pool that can be manipulated within a single transaction; `balanceOf(pool)` used for price; spot-price-derived collateral check before flash loan repayment
- **Detection Heuristic**:
  1. Identify functions that compute price from on-chain DEX state (not Chainlink/TWAP)
  2. Check whether a flash loan can temporarily change that state in the same transaction
  3. Look for: `balanceOf`, `getReserves`, `slot0`, `totalSupply` of LP tokens used in price formulas
  4. Check `get_virtual_price()` in Curve—can be manipulated by direct token donation
  5. Verify if the price-reading function and the action dependent on it are in the same tx (flash loan window)
- **Failure Mode**: Attacker flash-borrows to distort pool ratio, triggers price-sensitive protocol action at manipulated price, repays flash loan, profits from the distortion
- **Common Contexts**: Impermanent loss calculations, synth minting based on pool ratio, collateral-to-debt ratio checks, insurance fund pricing, oracle contracts using on-chain liquidity

---

## DEX-013: Rounding Direction Inconsistency (Favoring Attacker over Protocol)
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `addLiquidity` rounds UP shares issued (favoring user); `removeLiquidity` rounds UP tokens returned (also favoring user); invariant computation uses different rounding in deposit vs withdrawal path; integer division truncates in attacker's favor
- **Detection Heuristic**:
  1. Find paired deposit/withdrawal functions: check rounding direction for shares calculation in each
  2. Rule: deposit should round DOWN shares minted (protect protocol); withdrawal should round DOWN assets returned (protect protocol)
  3. For stableswap invariant: check if `D` is computed with ceiling or floor in mint vs burn
  4. Look for `(a + b - 1) / b` (ceiling) vs `a / b` (floor) and verify which path each is in
  5. Check if rounding differences compound over many deposits/withdrawals (e.g., round-trip gain)
- **Failure Mode**: Users can gain tokens through round-trip deposit+withdraw; over time, LP fund is drained through accumulated rounding errors; attacker performs many small round-trips to extract value
- **Common Contexts**: ERC4626 vaults, stableswap pools, bonding curves, any protocol with inverse token/share conversion functions

---

## DEX-014: Invariant Violation During AMM State Transitions
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `I` (ideal price parameter in DODO-style AMMs) manipulated via rounding error accumulation; `D` invariant not preserved across swap; `k = x * y` invariant not verified after fee deduction; protocol fails to re-check invariant after parameter changes (e.g., `setCurvePoint`)
- **Detection Heuristic**:
  1. After every state-modifying function (swap, add/remove liquidity), check if the invariant is explicitly verified
  2. For Curve: verify Newton-Raphson convergence check and that `D` is consistent pre/post
  3. For DODO: track `I` parameter—can it drift from the ideal price through rounding?
  4. Check parameter update functions (`setCurvePoint`, `changeParameters`): do they recalculate derived state?
  5. For AMMs with A parameter: verify amplification coefficient encoding (A vs A*N^N^(N-1) bug)
- **Failure Mode**: Pool price diverges from intended invariant; arbitrageurs extract value at cost of LPs; malicious pricing enables buying at below-market rates; protocol accounting breaks silently
- **Common Contexts**: Stableswap (Curve forks), DODO AMM, custom constant-function AMMs, bonding curves with mutable parameters

---

## DEX-015: Tick / Range Calculation Errors in Concentrated Liquidity
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `nearestTick` used where `currentTick` is required in fee growth calculation; `feeGrowthOutside` not initialized when tick is first crossed; `secondsPerLiquidity` not updated on liquidity change; current tick misaligned with spacing causing infinite loop in tick iteration; tick range not validated against `TickMath.MIN_TICK`/`MAX_TICK`
- **Detection Heuristic**:
  1. For UniV3 fork fee accounting: verify `feeGrowthOutside` is set to `feeGrowthGlobal` (not 0) when a tick is first initialized below current price
  2. Check tick iteration loops for termination: can `currentTick` ever equal `nextTick` (same-tick infinite loop)?
  3. Verify `secondsPerLiquidity` update is triggered on EVERY liquidity change, not just swaps
  4. Check `initialPrice` validation: must be within `[MIN_SQRT_RATIO, MAX_SQRT_RATIO]`
  5. For fee growth: verify the formula uses `feeGrowthGlobal - feeGrowthOutside(lower) - feeGrowthOutside(upper)` correctly when position is in range vs out of range
- **Failure Mode**: LP positions earn 0 fees or inflated fees; LP funds locked because burn/mint revert; fee growth underflow causes position to be permanently stuck; price manipulation outside full-range causes DoS
- **Common Contexts**: UniswapV3 forks, concentrated liquidity AMMs, position managers, gauge contracts on top of CL pools

---

## DEX-016: Missing Input Validation on AMM Configuration
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `AMM::instantiate` accepts `quote_decimals`, `base_decimals`, `market_id` without validation; `poolConfig.Invert` field set incorrectly inverting base/quote; gauge version check based on fragile call probes; wrong interface imported for chain (e.g., `ISwapRouter` for V2 on Base)
- **Detection Heuristic**:
  1. Audit all constructor/initializer/config-setter functions: verify each critical parameter has a `require(param != 0)` or range check
  2. Check pool config structs for boolean flags that invert behavior (e.g., `invert`, `isReversed`)—trace all consumers
  3. For cross-chain deployments: verify the correct interface is imported for the target network's DEX version
  4. Check gauge/pool compatibility probes: are they stable or can they give false positives for incompatible contracts?
  5. Verify decimal parameters are validated against `1 <= decimals <= 18`
- **Failure Mode**: AMM operates with inverted price; entirely wrong swap interface causes silent failures; misconfigured pool causes permanent loss on all trades
- **Common Contexts**: Multi-chain deployments, gauge factory contracts, adapter contracts wrapping external DEXes, protocol initialization flows

---

## DEX-017: Missing Deadline / Transaction Expiry Check
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `swap(deadline=block.timestamp)` always passes; no `deadline` parameter in swap/liquidity functions; `deadline = type(uint256).max` used; transaction sitting in mempool executed at unfavorable time
- **Detection Heuristic**:
  1. Find all swap and liquidity functions: check for a `deadline` parameter
  2. If `deadline` exists: check that `require(block.timestamp <= deadline)` is present and not trivially satisfied (i.e., `deadline != block.timestamp`)
  3. Check DEX router calls: does the contract pass a user-supplied deadline or hardcode one?
  4. Look for `permit`-based swap flows—these particularly need deadlines since permit itself has expiry but swap may not
- **Failure Mode**: Stale transaction executes when market has moved significantly; MEV bots can hold transactions and execute at the worst block for the user; no way for user to cancel a pending but not-yet-executed swap
- **Common Contexts**: Any protocol that calls Uniswap/SushiSwap router, DCA protocols, limit order protocols, auto-rebalance mechanisms

---

## DEX-018: Frontrunning of Protocol State Changes (Parameter Sandwich)
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `changeParameters()` or `setPositionWidth()` or `unpause()` modifies pool pricing parameters; attacker can observe pending tx and sandwich the parameter change; bonding curve adjustment can be exploited between old and new parameters
- **Detection Heuristic**:
  1. Identify admin functions that change AMM pricing parameters (`A`, `fee`, `weight`, `width`, `scale`)
  2. Check if attacker can: (a) observe the pending tx, (b) buy before it, (c) profit from parameter change, (d) sell after
  3. Verify if parameter changes include a slippage guard or minimum-out for any auto-triggered rebalance
  4. Check timelock: is there a delay between parameter announcement and execution that allows users to exit?
  5. Look for `changeParameters` that adjusts reserves only on the next trade (not immediately)—vulnerable window
- **Failure Mode**: Attacker profits from predictable price impact of configuration changes; LPs suffer loss from forced rebalance at manipulated price; protocol treasury is sandwiched during routine maintenance
- **Common Contexts**: Primitive Hyper-style AMMs, QuantAMM weight updates, Balancer weight changes, amplification factor ramps in Curve

---

## DEX-019: Incorrect LP Token Price Calculation
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: LP price computed as `(reserve0 + reserve1) / totalSupply` (vulnerable to manipulation via direct donation); Curve LP price hardcodes token count (always "3 PTs" regardless of actual balance); `getPositionValue()` omits `tokensOwed0`/`tokensOwed1` (pending fees); BPT price for stable pools computed with wrong formula
- **Detection Heuristic**:
  1. Find LP token valuation functions: check if they use `balanceOf(pool)` or `getReserves()` (manipulable) vs a manipulation-resistant formula
  2. For Curve LP: use `get_virtual_price()` but verify it's protected against donation manipulation (some Curve versions are not)
  3. For UniV3 positions: verify the valuation includes `tokensOwed0 + tokensOwed1` (accrued fees not yet collected)
  4. Check Balancer stable pool BPT pricing: must use the `StableMath.calculateInvariant` approach, not spot ratio
  5. Verify CurveV2/tricrypto: LP price derivation must use geometric mean, not arithmetic
- **Failure Mode**: Collateral valued at inflated price enables undercollateralized borrowing; deflated LP price causes unnecessary liquidations; wrong BPT price causes protocol insolvency
- **Common Contexts**: Lending protocols accepting LP tokens as collateral, yield aggregators, treasury management protocols, any oracle consuming LP token value

---

## DEX-020: Unbounded Loop / Gas DoS in DEX Operations
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `tickTracking_` array grows unboundedly via attacker spamming; `voter.finalize()` iterates over all pending removals; reward distribution loop over all positions; `processBatchOrders()` over attacker-supplied array
- **Detection Heuristic**:
  1. Find all loops over user-controlled or user-grown arrays in core AMM functions
  2. Check if array length is capped—if not, can attacker call a cheap function many times to extend the array?
  3. For tick tracking: can an attacker repeatedly cross a tick to grow `tickTracking_` beyond gas limit?
  4. Check vote/gauge finalization loops: is there a batch size limit?
  5. Verify that DoS via 1-wei donations (inflating array or triggering edge conditions) is handled
- **Failure Mode**: Core function (mint, burn, claim rewards) reverts for all users due to out-of-gas; protocol permanently frozen; griefing attack allows cheap DoS of expensive operations
- **Common Contexts**: Canto AMM (tick tracking DoS), vote/gauge finalization, position reward loops, launchpad graduation (1-wei donation DoS), UniV3 staker NFT spam

---

## DEX-021: Access Control Missing on Swap/Liquidity Callbacks
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `uniswapV3MintCallback()` external with no `msg.sender` check against factory; `flashRepayFromColl()` callable by anyone for any loan; `reBalance()` accepting arbitrary call data; `auto_redemption::performUpkeep()` callable by unauthorized parties; `depositSwap` router determined by caller
- **Detection Heuristic**:
  1. Find all external callback functions (`uniswapV3MintCallback`, `uniswapV3SwapCallback`, `sgReceive`, `onFlashLoan`)
  2. Verify `msg.sender` is validated against a trusted source (factory, pool, known contract)
  3. Check if the function can be called with attacker-controlled parameters to drain approved tokens
  4. For cross-protocol calls: verify the initiating contract's address is stored and validated in callback
  5. Check `receive()` and `fallback()` for unexpected ETH handling that could be exploited
- **Failure Mode**: Attacker calls callback directly, draining tokens the contract has approved; unauthorized flash repayment on victim's loan; arbitrary code execution via unsanitized call data
- **Common Contexts**: UniV3 periphery contracts, flash loan receivers, cross-chain message handlers, DEX router callbacks, staking/unstaking callbacks

---

## DEX-022: Reward Calculation Race Condition / Snapshot Timing
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `flashMint` sets `_shortCircuitRewards = 1` before reward snapshot; reward index updated after transfer (CEI violated); `rewardsPerToken` not incremented when supply is 0 (rewards lost); YT swap and index update race in same block; staking rewards miscalculated when `lastRewardBlock` not updated
- **Detection Heuristic**:
  1. For reward-per-token patterns: verify index is updated BEFORE any transfer or balance change
  2. Check for flash loan / flash mint interactions with reward snapshots: can `totalSupply` be transiently changed to distort reward rate?
  3. Check `rewardsPerToken` update: what happens when `totalSupply == 0`? Rewards should accumulate (not be lost) or be explicitly excluded
  4. For multi-message protocols: check if reward index update and action dependent on it can be reordered across messages
  5. Verify `lastUpdateTime` or `lastRewardBlock` is set before state changes that affect reward rate
- **Failure Mode**: Attacker steals accumulated rewards by exploiting snapshot timing; legitimate stakers lose rewards when supply temporarily hits 0; flash loan inflates supply to dilute per-token rewards
- **Common Contexts**: Staking reward contracts, gauge reward distribution, yield tokenization (YT/PT), flash mint protocols, liquidity mining

---

## DEX-023: Share/Token Inflation via Direct Transfer (Donation Attack)
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `get_virtual_price()` reads `token.balanceOf(pool)`; `totalAssets()` uses `balanceOf` instead of tracked internal balance; LP share price computed from pool's actual token balance; `InsuranceFund` share price uses `IERC20.balanceOf(self)` without tracking
- **Detection Heuristic**:
  1. Find `balanceOf(address(this))` or `balanceOf(pool)` in share price or exchange rate calculations
  2. Verify the protocol maintains an internal accounting variable that tracks deposited amounts (not relying on actual token balance)
  3. Check if an attacker can send tokens directly to the contract to inflate the denominator in share calculation
  4. For ERC4626: check if `totalAssets()` is based on `asset.balanceOf(address(this))` without isolation of protocol-owned vs user-deposited
- **Failure Mode**: Attacker inflates `totalAssets` with a direct transfer, making subsequent depositors receive fewer shares; early LPs can be priced out; first depositor receives bonus from attacker's donation
- **Common Contexts**: ERC4626 vaults, Curve pools (`get_virtual_price`), insurance funds, stableswap liquidity pools

---

## DEX-024: Chainlink Oracle Misuse
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `latestAnswer()` used without staleness check; negative `expo` in Pyth not handled (price can be malformed when price < 1); base/rate tokens inverted in price calculation; `getRoundData()` used with cached round ID; no check for `answeredInRound < roundId`
- **Detection Heuristic**:
  1. Find all `latestRoundData()` calls: verify `updatedAt` is checked against a staleness threshold
  2. Check `answer > 0` validation: must also handle sequences where answer is 0 (circuit breaker)
  3. For Pyth: check handling of negative `expo`—when `price.expo < 0`, the price is `price.price * 10^price.expo` which requires proper decimal handling
  4. Verify base vs quote token order in price feeds (e.g., ETH/USD vs USD/ETH)
  5. Check for `answeredInRound >= roundId` to detect incomplete rounds
  6. For L2: verify sequencer uptime feed is checked before using oracle
- **Failure Mode**: Stale price used during oracle downtime; inverted price causes wrong direction for all trades; Pyth negative expo causes incorrect price magnitude; zero price bypasses liquidation guards
- **Common Contexts**: Lending protocol price feeds, stable/peg oracles, perpetual mark price calculation, option pricing

---

## DEX-025: Wrong Init Code Hash / Library Pair Address Calculation
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: `UniswapV2Library.pairFor()` with hardcoded `INIT_CODE_PAIR_HASH` that doesn't match actual deployment; `keccak256(bytecode)` computed from wrong version of factory; pair address mismatch breaks `UniswapV2Oracle`, `SushiRoll`, router
- **Detection Heuristic**:
  1. Find `pairFor` function using `keccak256` of init code to compute pair address
  2. Verify the hash matches the actual deployed factory's `INIT_CODE_PAIR_HASH` (check against factory source)
  3. For forks: confirm the factory bytecode hash has been updated to match the fork's bytecode
  4. Cross-check with `IUniswapV2Factory(factory).getPair(token0, token1)` for a known pair
- **Failure Mode**: Oracle reads from wrong address (returns 0 or reverts); router sends tokens to wrong pair; fund loss or permanent DoS
- **Common Contexts**: UniV2 forks on alternative chains/networks, Canto's zeroswap fork, SushiSwap forks with modified factory

---

## DEX-026: Incorrect Bonding Curve Logic
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Bonding curve buy formula exploitable by splitting order into multiple small buys (less total price); inverse operation wrong (`V/(1+delta)` used instead of `V*(1/(1+delta))`); fee not applied to correct portion (`trueOrderSize` vs full amount); utilization rate computed from sum of bull+bear (allows manipulation)
- **Detection Heuristic**:
  1. Verify buy and sell formulas are exact mathematical inverses of each other
  2. Check if batch buys of size X have the same total cost as a single buy of X (price path-independence test)
  3. For fee calculation: verify fee is applied before or after the curve calculation consistently with spec
  4. Check utilization rate inputs: can either bull or bear side be inflated independently to manipulate the combined rate?
  5. Verify exponential/power functions use the correct inverse (common: using `x^n` when `x^(1/n)` is needed)
- **Failure Mode**: Attacker buys at below-market price by splitting orders; fee is charged on wrong amount (either overcharging or undercharging); bonding curve invariant broken leading to protocol insolvency
- **Common Contexts**: Social token bonding curves, AMO (algorithmic market operations), Smilee Finance utilization-based pricing, custom bonding curves for token launches

---

## DEX-027: AMM Weight / Index Calculation Error
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `_getNormalizedWeights()` uses wrong token index causing off-by-one; multiplier applied in wrong order causing `weight * multiplier` vs `multiplier * weight` mismatch; weight update applied to wrong array index; gradient-based weight update overflows for N >= 4 assets
- **Detection Heuristic**:
  1. Find weight normalization functions: verify each token's weight maps to the correct index in the weight array
  2. Check matrix/vector operations: verify multiplier is applied at the right position (before vs after accumulation)
  3. For weighted pools: verify `sum(weights) == 1e18` after each update
  4. Check numerical stability: for multi-asset pools (N >= 4), verify vector operations don't overflow uint256
  5. Cross-check: if `weights[i]` is updated, verify the consumer of `weights[i]` uses the same `i` definition
- **Failure Mode**: All pool asset allocations are wrong; one token is systematically over/under-weighted; weight updates cause pool imbalance; N >= 4 asset pools always revert
- **Common Contexts**: QuantAMM weighted pools, Balancer weighted pools, gradient-based dynamic AMMs, index rebalancing protocols

---

## DEX-028: Missing Token Identity / Duplicate Pool Checks
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `swap(fromToken, toToken)` with no `require(fromToken != toToken)`; pool created for same token twice (duplicate pool attack); `createPool` permissionless for any listed token allowing shadow pools; reward routing uses duplicate pool to steal rewards
- **Detection Heuristic**:
  1. Find all swap entry points: verify `require(tokenIn != tokenOut, "same token")`
  2. Find all pool creation functions: verify uniqueness check (factory mapping lookup before creation)
  3. For reward pool systems: verify pools are deduplicated by canonical pair address, not user-supplied addresses
  4. Check if `fromToken == toToken` path leads to arithmetic issue (e.g., double-counts the same balance)
- **Failure Mode**: Same-token swap drains fees without any actual exchange; duplicate pool diverts protocol rewards; attacker creates shadow pool for listed token and steals emissions
- **Common Contexts**: MarginSwap, DCA protocols, reward distribution systems, permissionless pool factories

---

## DEX-029: Stale / Outdated Liability / State Used in Critical Operations
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `modify()`, `liquidate()`, `warn()` use stored (cached) account liabilities instead of computing fresh; `yToken` exchange rate only calculated during withdrawal (stale during other operations); `savedTotalUnderlying` tracks withdrawn funds incorrectly; `last_tvl` not updated after pair removal
- **Detection Heuristic**:
  1. For liquidation/modify functions: verify they call `accrueInterest()` or equivalent before reading balances
  2. Check if exchange rates / share prices are computed lazily (only on specific actions) vs eagerly (on every operation)
  3. Look for "saved" or "cached" state variables: check what triggers their update and whether update can be skipped
  4. For operations that depend on total TVL or total assets: verify these reflect post-operation state, not pre-operation
- **Failure Mode**: User can become undercollateralized without triggering liquidation because stored value is stale; liquidation botched because it acts on outdated liability; user gets wrong exchange rate on redemption
- **Common Contexts**: Lending protocols (Aloe, WiseLending), yield vaults (Yearn, yAxis), perpetual protocols (Elfi), protocol accounting after market closure

---

## DEX-030: Protocol Fee / Royalty Accounting Errors
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `protocolFee0`/`protocolFee1` included in `addLiquidity` call (double-counted); royalty conditionally applied (some paths skip it); fee variable overwritten not accumulated (`treasuryShare = X` instead of `+=`); protocol fee withdrawn multiple times (no flag after first withdrawal); fee stuck in contract with no retrieval function
- **Detection Heuristic**:
  1. Find fee accumulation variables: verify they use `+=` not `=`
  2. For fee withdrawal: check if there's a guard preventing double-withdrawal (e.g., `claimed` flag or `delete` of fee record)
  3. Check LP add/remove functions: verify protocol fee tokens are excluded from the amounts passed to underlying DEX
  4. For royalty calculations: check all exit paths (sell, cancel, redeem)—does each path apply royalties consistently?
  5. Check for fee tokens sent to wrong address (e.g., sent to `address(this)` instead of `treasury`)
- **Failure Mode**: Protocol collects less fee than intended (royalty skipped on some paths); treasury receives double fees; fee accumulator resets instead of accumulates; fee funds permanently locked with no withdrawal function
- **Common Contexts**: NFT AMMs (Sudoswap), gauge reward distribution, DEX fee collection, yield protocol fee structures

---

## DEX-031: Unsafe ERC20 Interactions (Non-Standard Token Edge Cases)
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `token.approve(spender, newAmount)` when previous allowance is non-zero (USDT-style revert); `transfer()` return value unchecked; `safeApprove` blocking when current allowance > 0; ERC777 token reentrancy in `transferFrom`; certain tokens don't return bool from `approve`
- **Detection Heuristic**:
  1. Find all `approve()` calls: check if current allowance is zeroed before setting new amount (USDT compatibility)
  2. Search for `transfer()` / `transferFrom()` without `SafeERC20` wrapper—many tokens don't return bool
  3. Check for ERC777 `tokensReceived` hook: any `transferFrom` of ERC777 token can reenter
  4. For `safeApprove`: check if it's called multiple times without intervening `approve(0)` (blocks on second call)
  5. Check return value of low-level `.call()` in token-related functions
- **Failure Mode**: Protocol bricked for USDT-like tokens; silent failure on non-returning `transfer()`; reentrancy via ERC777 hook allows balance manipulation before accounting update
- **Common Contexts**: Any protocol accepting arbitrary ERC20 tokens, DEX routers, collateral managers, cross-chain bridging

---

## DEX-032: Liquidity Position NFT / Ownership Tracking Errors
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Island shares ownership not updated on `Burve` token transfer; UniV3 NFT position `nftId` reassigned to wrong collection; anyone can increase liquidity on victim's NFT via `NPM.increaseLiquidity`; `V3Utils.execute()` lacks caller validation; ERC721 sent directly to pool claimed as NTokens by anyone
- **Detection Heuristic**:
  1. Find all ERC721 transfer paths for LP position NFTs: check if downstream accounting (shares, rewards, ownership) is updated on transfer
  2. For NFT-backed positions: verify that `onERC721Received` validates the sender is the expected pool/manager
  3. Check if `NPM.increaseLiquidity()` can be called by anyone for a position ID (it can in UniV3)—verify this doesn't break protocol's position accounting
  4. Find `V3Utils` or position manager execute functions: verify `msg.sender` is the NFT owner
  5. Check if position closure requires the position to have exactly 0 liquidity (attacker can block by adding 1 wei)
- **Failure Mode**: Ownership desync between LP NFT and protocol's accounting; attacker donates liquidity to victim's position to prevent closure; wrong user receives rewards for a position
- **Common Contexts**: UniV3 position managers, Gamma Hypervisor, NFT collateral protocols, CL gauge staking, Burve/Kodiak island wrappers

---

## DEX-033: Incorrect Price Representation / Calculation in Perps/Options
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: TWAP interval too short (`getPositionValue` uses wrong interval); open price lacks rounding protection; settlement calculation uses live price for expired instruments; mark price uses `last_px` (spot) instead of TWAP for oracle-free perps; negative tick delta not rounded up in `_getReferencePoolPriceX96`
- **Detection Heuristic**:
  1. For perpetual protocols: verify mark price source (TWAP not spot), and that the TWAP period is sufficient
  2. For options: verify expired board prices are locked at expiry (not live); check `getSettlementState` uses correct snapshot price
  3. For concentrated liquidity oracles: verify negative tick delta uses ceiling division (signed integer rounding in Solidity truncates toward zero, which is wrong for negative values)
  4. Check `getPositionValue` TWAP interval constant: verify it matches the documented/intended interval
  5. For rounding in price: check `roundingDirection` enum is correctly applied in both open and close paths
- **Failure Mode**: Positions settled at wrong price causing massive over/under-payment; mark price manipulation enables unfair liquidations on oracle-free markets; rounding error in open price compounds over many operations
- **Common Contexts**: GMX, Perennial, Layer N, Deriverse, perpetual protocols using AMM prices for mark/settlement

---

## Appendix: Pattern Frequency Summary

| Pattern ID | Name | ~Frequency |
|------------|------|-----------|
| DEX-001 | Missing/Ineffective Slippage | 38 |
| DEX-002 | Spot Price Oracle Manipulation | 28 |
| DEX-003 | Sandwich on Protocol Swaps | 22 |
| DEX-004 | First Depositor / Vault Inflation | 18 |
| DEX-005 | TWAP Implementation Errors | 16 |
| DEX-006 | Reentrancy in AMM Functions | 14 |
| DEX-007 | Incorrect Fee Calculation | 14 |
| DEX-008 | Reserve Accounting Errors | 14 |
| DEX-011 | Decimal Scaling / Unit Mismatch | 14 |
| DEX-015 | Tick / Range Calculation Errors | 12 |
| DEX-012 | Flash Loan Price Manipulation | 12 |
| DEX-019 | Incorrect LP Token Price | 10 |
| DEX-013 | Rounding Direction Inconsistency | 10 |
| DEX-010 | Wrong Token Order / Reserve Mapping | 10 |
| DEX-009 | Pool Initialization Frontrunning | 10 |
| DEX-024 | Chainlink Oracle Misuse | 10 |
| DEX-014 | Invariant Violation | 10 |
| DEX-020 | Unbounded Loop / Gas DoS | 8 |
| DEX-021 | Access Control on Callbacks | 8 |
| DEX-022 | Reward Calculation Race Condition | 8 |
| DEX-023 | Share Inflation via Donation | 8 |
| DEX-030 | Fee / Royalty Accounting Errors | 8 |
| DEX-032 | NFT / Ownership Tracking | 8 |
| DEX-017 | Missing Deadline Check | 8 |
| DEX-018 | Parameter Change Sandwich | 8 |
| DEX-016 | Missing AMM Config Validation | 8 |
| DEX-026 | Incorrect Bonding Curve Logic | 8 |
| DEX-029 | Stale State in Critical Operations | 6 |
| DEX-031 | Unsafe ERC20 Interactions | 6 |
| DEX-028 | Missing Token Identity Checks | 6 |
| DEX-027 | AMM Weight / Index Error | 6 |
| DEX-033 | Perp/Option Price Representation | 6 |
| DEX-025 | Wrong Init Code Hash | 4 |
