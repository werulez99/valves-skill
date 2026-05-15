# Oracle Dependency Patterns
> Extracted from 4,576 findings (500 sampled)
> Pattern count: 24

---

## ORACLE-001: chainlink_no_staleness_check
- **Frequency**: ~35/500 findings
- **Severity**: HIGH
- **Code Shape**: `latestRoundData()` return values used without checking `updatedAt` against `block.timestamp`; no `require(block.timestamp - updatedAt <= heartbeat, ...)` guard; `getRateInQuote`, `getPrice`, `getPriceUSD` functions that call `latestRoundData` but discard `updatedAt`
- **Detection Heuristic**:
  1. Grep for `latestRoundData(` and collect all call sites
  2. For each call site, verify that `updatedAt` (the 3rd return value) is captured and compared against `block.timestamp` with a staleness threshold
  3. Check that `roundId` and `answeredInRound` are captured; verify `answeredInRound >= roundId` (detects incomplete rounds)
  4. Check that `answer` (price) is validated > 0
  5. Flag any call site where `updatedAt` is ignored (assigned to `_` or unused named variable)
  6. Cross-check the staleness threshold against the feed's documented heartbeat (e.g., ETH/USD = 1 hour; BTC/USD = 1 hour; some feeds = 24 hours)
- **Failure Mode**: Protocol consumes a price that was last updated hours or days ago. During market volatility (e.g., a depeg event, sudden crash), stale prices allow over-borrowing, under-collateralized minting, or blocked liquidations — since the on-chain price diverges from true market price.
- **Common Contexts**: Lending protocols (collateral valuation, borrow limits), stablecoin minting, perpetuals (funding rates, liquidation thresholds), vault share pricing

---

## ORACLE-002: uniswap_slot0_spot_price_manipulation
- **Frequency**: ~28/500 findings
- **Severity**: HIGH
- **Code Shape**: `pool.slot0()` returning `sqrtPriceX96`; `IUniswapV3Pool(pool).slot0()` used for price calculation; `_calculatePriceFromLiquidity()` calling `slot0`; `sqrtPriceLimitX96` derived from `slot0`; `slot0` used in slippage calculations; `getReserves()` from Uniswap V2 pools used as oracle
- **Detection Heuristic**:
  1. Grep for `.slot0()` and `pool.slot0(` — any usage in price-sensitive logic is suspect
  2. Grep for `getReserves()` on Uniswap V2 pairs used for pricing (not just routing)
  3. Verify whether the returned `sqrtPriceX96` is used for financial calculations (collateral value, swap limits, minting ratios) rather than just routing
  4. Check if there is a TWAP fallback or comparison — if not, flag as HIGH
  5. For IchiVault integrations: `IchiVault.getTotalAmounts()` uses spot reserves internally — flag as equivalent to `slot0` exposure
  6. Look for `checkDeviation` modifiers that compare slot0 to TWAP; absent = vulnerable
- **Failure Mode**: Attacker flash-loans large amounts to shift the Uniswap pool price within a single transaction, calls the vulnerable protocol function at the manipulated price (to over-borrow, mint at discount, or extract LP fees), then unwinds the flash loan. Single-block, low-cost attack with potentially unlimited upside.
- **Common Contexts**: Lending (collateral valuation using spot AMM price), LP token pricing, slippage protection in vaults, oracle-less perpetuals using `last_px`

---

## ORACLE-003: decimal_mismatch_in_price_calculation
- **Frequency**: ~45/500 findings
- **Severity**: HIGH
- **Code Shape**: Chainlink feeds returning 8-decimal prices used in 18-decimal math without scaling; price * amount without `/ 1e10` normalization; `decimals()` not called on feed; mixed `1e6` / `1e8` / `1e18` multipliers in same formula; `mulWad` applied to values that are not wad-scaled; price assumed 18 decimals when feed is 8; double-scaling (upscaling applied twice)
- **Detection Heuristic**:
  1. Identify all price feed calls (`latestRoundData`, `getPrice`, `price()`) and record the expected decimal precision of each feed
  2. Trace how the returned price is used in arithmetic — confirm that scaling factors (`* 1e10`, `/ 10**feedDecimals`) are applied before multiplication with token amounts
  3. Check for assumptions of fixed 18 decimals: `uint256 price = feed.getPrice(); value = price * amount / 1e18` — if feed returns 8 decimals, the result is 1e10x too small
  4. For composite oracles (Chainlink + another source), verify that decimal normalization happens at every combination step, not just at one end
  5. Check `mulWad`, `mulDiv`, `rayMul` usage — these assume specific precision (1e18, 1e27) and will silently produce wrong results if inputs are in different units
  6. Look for `incorrect decimal` in function names or comments — often a clue that a previous fix introduced a second mismatch
- **Failure Mode**: Price is orders of magnitude too large or too small. Users receive 1e10x fewer tokens than expected (understated price) or drain the protocol by borrowing against inflated collateral value (overstated price). Liquidations triggered at wrong thresholds.
- **Common Contexts**: Lending (collateral/borrow value), stablecoin oracles, vault share pricing, reward calculations, LP token valuation

---

## ORACLE-004: oracle_sandwich_frontrun_on_price_updates
- **Frequency**: ~22/500 findings
- **Severity**: HIGH
- **Code Shape**: `updatePrice()` or oracle push functions callable before `deposit()`/`withdraw()`/`swap()` in same block; no per-block price commit restriction; deposit/withdrawal using current price at time of execution with no delay; `gulp()` calls that update exchange rate sandwichable; `setPrice` + `trade` in same block; oracle update followed immediately by atomic exploitation
- **Detection Heuristic**:
  1. Identify when oracle prices are updated on-chain (push-based oracles, `storePrice`, keeper-driven updates)
  2. Check whether deposits, withdrawals, minting, and redemptions use the freshly-updated price with no time delay or commitment scheme
  3. Verify if price updates are restricted to once per block (prevents same-block sandwich)
  4. Check for commit-reveal schemes: user must commit to a trade before the price is known
  5. For keeper-settled perps: verify that the price used for settlement cannot be predicted/influenced by the settler
  6. Look for `performUpkeep` or automation callbacks that update prices — check if they can be front-run
- **Failure Mode**: Attacker observes a pending oracle update (e.g., ETH price rising 5%), front-runs with a deposit at the old (lower) price, gets shares at a discount, then redeems at the new higher price. Or attacker sandwiches a price update to extract risk-free profit from vaults, lending markets, or AMMs.
- **Common Contexts**: Push-based oracle protocols (manual keepers), vault deposit/withdrawal, stablecoin collateral, rebalancing mechanisms, price-sensitive minting

---

## ORACLE-005: twap_period_too_short_or_incorrect
- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `periodSize` hardcoded to small value (e.g., 10 minutes or fewer blocks); `TWAP_INTERVAL` or `twapInterval` variable set to an easily-manipulable window; incorrect interval passed (e.g., `getPositionValue` using wrong interval); `observationCardinality` not initialized before TWAP reading; `increaseObservationCardinalityNext` not called; `Oracle.periodCumulativesInside` computing wrong tick range
- **Detection Heuristic**:
  1. Find all TWAP queries: `observe()`, `consultTWAP()`, `OracleLibrary.consult()`, `TwapOracle.consult()`
  2. Extract the time window parameter — any window under 30 minutes on mainnet or under 1 hour for low-liquidity pools is suspect
  3. Check `observationCardinality` — if a pool has cardinality 1 (default), TWAP cannot look back further than 1 block; verify `increaseObservationCardinalityNext` was called
  4. For UniV3 TWAP: verify the tick range passed to `periodCumulativesInside` matches the actual price range intended
  5. Check for the `priceCumulative` overflow bug in UniV2 TWAP implementations (safe in Solidity <0.8.0 but reverts in >=0.8.0 without `unchecked`)
  6. Verify that `SwapManager.update()` or equivalent is actually called on every swap (missing update = TWAP drift)
- **Failure Mode**: Short TWAP windows allow attackers to manipulate the time-weighted price within the observation period by holding a large position in the pool. Longer manipulation is economically costly; short windows are cheap. Wrong interval causes incorrect position values, enabling overborrowing or improper settlement.
- **Common Contexts**: AMM-based price feeds, lending protocols using TWAP for liquidation, perpetual futures settlement, vault pricing using Uniswap TWAP

---

## ORACLE-006: hardcoded_stablecoin_peg_assumption
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `uint256 constant USDC_PRICE = 1e18;` or `return 1 ether;` for stablecoin price; `USDC` or `USDT` price hardcoded to 1:1 with USD; `stETH == ETH` assumed at 1:1; `wstETH` exchange rate assumed constant; no oracle query for stable assets; comment `// assume USDC = $1`
- **Detection Heuristic**:
  1. Search for hardcoded price constants: `1e18`, `1 ether`, `1000000` (for 6-decimal stablecoins) used as prices
  2. Identify all assets that are "pegged" tokens (USDC, USDT, DAI, FRAX, LUSD, stETH, cbETH) — check if their price is fetched from a live oracle or hardcoded
  3. For liquid staking tokens: verify that the exchange rate (e.g., wstETH/ETH ratio) is fetched from the staking contract dynamically, not assumed 1:1
  4. Check minting/redemption logic for stablecoins: if a user can mint with USDC at $1 when USDC is at $0.90, they receive free value
  5. Look for comments like `// pegged`, `// stable`, `// 1:1` near price assignment
- **Failure Mode**: During a depeg event (e.g., USDC trading at $0.90 or $1.10), the protocol allows users to exploit the difference — minting tokens worth less than the hardcoded peg, or draining protocol reserves via arbitrage against the hardcoded price.
- **Common Contexts**: Stablecoin-backed lending, CDP protocols, stablecoin minting, cross-asset swaps, options protocols with stable collateral

---

## ORACLE-007: lp_token_spot_price_manipulation
- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: LP token value calculated as `reserve0 * price0 + reserve1 * price1` using spot reserves; `IchiVault.getTotalAmounts()` used for LP pricing; `totalSupply()` used instead of virtual/invariant-based supply for BPT pricing; Curve LP priced using `get_virtual_price()` without reentrancy protection; `getUnderlyingBalances()` of Balancer used directly; Tricrypto LP math error
- **Detection Heuristic**:
  1. Identify all LP/BPT token pricing functions — check if they use spot reserves or AMM invariant math
  2. For Curve LP: verify `get_virtual_price()` is called, not raw reserve balances; also check if the Curve pool is guarded against read-only reentrancy (Balancer vault callback can corrupt `get_virtual_price` in some forks)
  3. For Balancer: verify that `totalSupply()` is NOT used — BPT uses `getActualSupply()` or `getVirtualSupply()` to exclude pre-minted BPT
  4. For Uniswap V2 LP: check if the fair-reserve formula is applied (`sqrt(reserve0 * reserve1) * 2 / totalSupply`) rather than spot reserves — spot reserves are manipulable
  5. For IchiVault / concentrated liquidity LP: verify the underlying price source for constituent tokens is TWAP-based, not slot0
  6. Check for decimal normalization when pool tokens have different decimal counts (USDC 6 vs WETH 18)
- **Failure Mode**: Attacker flash-loans to distort pool reserves, inflating LP token valuation. Uses inflated LP as collateral to over-borrow. After unwinding the flash loan, bad debt remains in the protocol.
- **Common Contexts**: Lending protocols accepting LP tokens as collateral, yield aggregators, vault strategies that hold LP positions

---

## ORACLE-008: inverted_price_feed_base_quote
- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `ETH/USD` feed price used where `USD/ETH` is needed (or vice versa); `1e36 / price` missing when inverting a rate; `token0/token1` pair fetched but protocol needs `token1/token0`; Chainlink ETH-denominated feed (e.g., DAI/ETH) used in USD context without inversion; `getPriceUSD` returning inverted base/rate tokens; wrong token order passed to Uniswap oracle
- **Detection Heuristic**:
  1. Map every oracle feed address to its documented base/quote pair (e.g., ETH/USD, BTC/ETH)
  2. Check the direction of price consumption: if the protocol needs "how many USD per ETH", ensure the feed is `ETH/USD` and not `USD/ETH`
  3. When a feed requires inversion, verify: `invertedPrice = 1e(feedDecimals + 18) / rawPrice` — check the exponent is correct
  4. For Uniswap-based oracles, verify that `token0` and `token1` ordering matches the expected price direction
  5. For Chainlink rates: check if the feed returns a ratio that needs to be divided rather than multiplied into the calculation
  6. Search for `StableOracleDAI`, `CTokenMultiOracle`, and similar named oracles — these have historically inverted base/quote
- **Failure Mode**: Prices are off by orders of magnitude (e.g., ETH worth $0.0003 instead of $3000). Collateral is massively undervalued (triggering spurious liquidations) or massively overvalued (allowing unlimited borrowing).
- **Common Contexts**: Multi-asset lending, stablecoin CDPs, cross-currency price aggregation, Chainlink DAI/ETH feed consumers

---

## ORACLE-009: no_price_outlier_filter_or_bounds_check
- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: Raw `answer` from `latestRoundData()` used without checking against `minAnswer`/`maxAnswer` circuit breakers; no `require(price > 0 && price < MAX_REASONABLE_PRICE)` guard; Chainlink aggregator's built-in min/max not validated; `PriceOracle` without outlier filtering; `_sanityCheck` function missing or ineffective; no check for slashing-related price anomalies
- **Detection Heuristic**:
  1. For every Chainlink price feed, check if the aggregator's `minAnswer` and `maxAnswer` are queried and validated against the returned `answer`
  2. Check whether the protocol has any secondary sanity check (e.g., compare Chainlink to Uniswap TWAP; reject if deviation > X%)
  3. Look for `AggregatorV3Interface` usage — verify `answer > minAnswer` and `answer < maxAnswer` before use
  4. For median aggregators: verify the sorting and selection algorithm is correct (incomplete sort = wrong median)
  5. For custom multi-source oracles: check if a single compromised feeder can skew the result (insufficient quorum threshold)
  6. Verify `_sanityCheck` in staking/validator contexts: a slashing event can cause a sudden large price drop that an effective sanity check should handle
- **Failure Mode**: Chainlink returns a stale/frozen price at the circuit breaker boundary (e.g., during the LUNA crash, BTC was stuck at $1 million). Protocol accepts this as valid, enabling massive under-collateralized borrowing. Or a single malicious oracle in an aggregator skews the median.
- **Common Contexts**: Any Chainlink consumer, custom multi-oracle aggregators, staking protocol price oracles

---

## ORACLE-010: oracle_frontrun_price_manipulation_amm
- **Frequency**: ~15/500 findings (partially overlaps with ORACLE-004 but distinct — specifically AMM-based oracle front-running, not push-based oracle updates)
- **Severity**: HIGH
- **Code Shape**: `PriceAware.updateCumulativePrice()` callable by anyone; `updatePhase()` callable prematurely changing oracle phase and `endRoundId`; `_setPricesFromPriceFeed` with multiple price fetches in same tx; `spot price` used for slippage protection that itself is derived from the AMM being traded against; permissionless price update function
- **Detection Heuristic**:
  1. Identify any oracle update function with no access control (callable by `msg.sender` without restriction)
  2. Check if price updates to the AMM oracle can be triggered atomically within the same transaction as a trade
  3. For phase-based oracles: verify that `endRoundId` captures the correct round and cannot be set prematurely
  4. When a function fetches price multiple times (e.g., at start and end of execution), check if intermediate state changes can cause price divergence between fetches
  5. Look for `updatePhase`, `updateCumulativePrice`, `updatePrice` functions — check their access control
  6. Verify that the oracle cannot be updated and consumed in the same block by the same actor
- **Failure Mode**: Attacker manipulates the on-chain oracle (by calling the update function at a favorable moment), then immediately exploits the skewed price in the same or next transaction. Unlike sandwich attacks on external oracle pushes, this is a self-contained manipulation.
- **Common Contexts**: Protocol-native price oracles, Divergence Protocol-style oracles, Bancor V2 AMM, Marginswap

---

## ORACLE-011: missing_slippage_protection_on_oracle_based_swaps
- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `swap(amountIn, 0, ...)` with `amountOutMin = 0`; `addLiquidity` without `minAmountOut`; `execute_dca_order` with no slippage bound; `fund` function in Arrakis without slippage control; no `minAmountOut` on vault rebalancing; `checkDeviation` modifier missing; missing `deadline` parameter; `amountOutMinimum: 0` in Uniswap swap call
- **Detection Heuristic**:
  1. Grep for Uniswap/Curve/Balancer swap calls: `exactInputSingle`, `exactInput`, `swap`, `exchange` — check the minimum output parameter
  2. For every swap call, verify that `amountOutMin` or `minOut` is non-zero and derived from a trusted price source (not the same pool being swapped)
  3. Check for `deadline` parameter — swaps without deadline can be held in mempool and executed at unfavorable prices
  4. For vault `deposit()`/`withdraw()` functions: verify that `minOut` parameter is accepted from the user or computed from an oracle
  5. For rebalancing functions: check whether the executor (keeper/bot) can set arbitrary slippage, enabling them to skim value
  6. Look for `pre_swap` checks that use spot price — if the spot price itself is manipulable, the slippage check is circular
- **Failure Mode**: Sandwich attack or MEV bot manipulates the pool before and after the protocol's swap. Protocol receives far less than expected. In vault rebalancing, malicious or negligent keeper extracts value by submitting at zero slippage.
- **Common Contexts**: DCA orders, vault rebalancing, reward harvesting, liquidation swaps, cross-chain bridging swaps

---

## ORACLE-012: pyth_oracle_misuse
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: Using `pyth.getPrice()` (cached) instead of `pyth.getPriceNoOlderThan()` or `pyth.getPriceUnsafe()`; using wrong price field (`price` field instead of `emaPrice`); ignoring `expo` field (negative exponent means price < 1); not calling `pyth.updatePriceFeeds()` before `getPrice()`; `PythPriceFeedUpdate` messages accepted without source validation; confidence interval ignored; `mismatch between stored and reported Pyth prices`
- **Detection Heuristic**:
  1. Identify all Pyth price accesses: `getPriceNoOlderThan`, `getPrice`, `getPriceUnsafe`, `getEmaPriceNoOlderThan`
  2. Check that `expo` is handled: when `expo` is negative, the price is `price * 10^expo` (can be < 1). Naive use of `price` field without `expo` adjustment inflates prices
  3. Verify `updatePriceFeeds()` is called with a valid, recent update message before `getPrice()` — otherwise stale cached price is used
  4. Confirm the confidence interval (`conf`) is checked — abnormally wide confidence = unreliable price
  5. For push-based Pyth implementations: verify the HTTP server or relay that submits `PythPriceFeedUpdate` has proper access control; unauthenticated submission allows price injection
  6. Check that `emaPrice` vs `price` selection is intentional — `price` is instantaneous (manipulable); `emaPrice` is exponentially smoothed
- **Failure Mode**: Negative `expo` ignored causes price off by 10^|expo| (e.g., a price of 0.5 becomes 5). Stale cached price causes the same issues as ORACLE-001. Unauthenticated update submission allows oracle injection attacks.
- **Common Contexts**: Solana DeFi protocols, cross-chain protocols using Pyth, any protocol on networks where Pyth is the primary oracle

---

## ORACLE-013: read_only_reentrancy_balancer_oracle
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `BPTOracle.bptPrice()` called after Balancer vault callback completes (ETH transfer triggers reentrancy); no `nonReentrant` on oracle read function that queries Balancer `getPoolTokens()`; `CurveV2CryptoEthOracle` with WETH re-entry path; `pool.getPoolTokens()` used for oracle pricing without Balancer reentrancy guard; `vault.getPoolTokens()` call inside a callback
- **Detection Heuristic**:
  1. Identify any oracle that reads Balancer pool state (`getPoolTokens`, `getActualSupply`, `getLastChangeBlock`) — these are vulnerable to read-only reentrancy via ETH transfer callbacks during Balancer flash loans
  2. Check if the oracle has a reentrancy guard that checks Balancer's internal lock: `IBalancerVault(vault).manageUserBalance()` with empty operations, or `BalancerVault._isUnlocked()` check
  3. For Curve pools: verify that `get_virtual_price()` is NOT called during a Curve pool callback (re-entrancy mid-withdraw distorts virtual price)
  4. Look for patterns where the same function (a) updates state and (b) reads oracle — if oracle can be queried mid-update via callback, flag
  5. Check `Wells::removeLiquidity` and similar Beanstalk patterns where the oracle read happens after ERC777/ERC1155 callbacks
- **Failure Mode**: During a Balancer flash loan or ETH transfer, an attacker re-enters the protocol while Balancer's internal state is inconsistent. The oracle returns a manipulated price, enabling over-borrowing, forced liquidation, or reserve drain.
- **Common Contexts**: Lending protocols using Balancer BPT as collateral, yield aggregators using Balancer or Curve LP pricing

---

## ORACLE-014: wrong_asset_price_used_for_different_asset
- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: `FrxETHOracle` returning ETH price instead of frxETH price; `_underlyingRefPerTok` using wrong exchange rate source (cbETH using ETH/USD instead of cbETH/ETH * ETH/USD); `exchangeRateStored` from wrong `bToken`; `updateRegisteredErc20()` updating wrong token's oracle; `LibUsdOracle` returning wrong price for Uniswap oracle path; debug code returning constant price `30_000e18` for all assets
- **Detection Heuristic**:
  1. For every oracle address stored in mappings (e.g., `tokenOracle[token]`), verify that updating one entry does not silently modify another (off-by-one indexing bugs)
  2. Trace multi-step price derivation: for wrapped or derivative tokens, verify that each conversion step uses the correct intermediate price
  3. For `frxETH`, `cbETH`, `ankrETH`, `rETH`: check whether the oracle returns the derivative token's price relative to ETH, or ETH's price in USD — these are different
  4. Search for any hardcoded or constant return values in oracle functions (debug code left in production)
  5. Check that `getExchangeRateBase` and similar functions use the correct base asset
  6. For token registry patterns: when `updateRegisteredErc20(address token)` updates a mapping, verify the index calculation correctly identifies `token`
- **Failure Mode**: Asset is systematically mispriced by a fixed ratio or entirely wrong asset's price is used. Attackers can exploit this predictably and repeatedly — e.g., borrowing against a collateral that is 100x overvalued.
- **Common Contexts**: Multi-collateral lending, registry-based oracle systems, wrapped token pricing, multi-step price derivation chains

---

## ORACLE-015: chainlink_vrf_misuse_or_subscription_drain
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `requestRandomWords()` called with `craftAmount = 0` consuming VRF without purpose; VRF request ID not tracked — same request can be fulfilled multiple times; `fulfillRandomWords()` does not verify `requestId` matches expected; `COORDINATOR.requestRandomWords()` callable in a loop without rate limiting; VRF subscription drainable by repeated zero-value crafting
- **Detection Heuristic**:
  1. Check `requestRandomWords()` call sites for input validation — verify that `amount > 0` or equivalent before consuming VRF
  2. Verify that each `requestId` is stored in a mapping and marked as fulfilled after `fulfillRandomWords()` executes — prevents double-fulfillment
  3. Check access control on functions that trigger VRF requests — ensure only authorized callers or a rate-limited caller can request
  4. Verify the VRF callback (`fulfillRandomWords`) validates `requestId` against the pending request set
  5. Check if multiple pending VRF requests can be outstanding simultaneously — race condition may allow manipulation
  6. For Chainlink Automation / `performUpkeep`: verify that the upkeep condition check and action cannot be front-run to drain VRF subscription
- **Failure Mode**: VRF subscription is drained (DoS for randomness-dependent features), or randomness is replayed/double-used to allow gaming of lottery/NFT outcomes.
- **Common Contexts**: GameFi, lottery protocols, NFT minting randomness, any Chainlink VRF consumer

---

## ORACLE-016: weak_on_chain_randomness_source
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `block.timestamp % N` for random number; `blockhash(block.number - 1)` as seed; `keccak256(abi.encodePacked(block.timestamp, msg.sender))` without VRF; `block.difficulty` / `prevrandao` used directly; `block.number` used as randomness; miner-influenceable on-chain values in prize selection
- **Detection Heuristic**:
  1. Search for `block.timestamp`, `blockhash`, `block.difficulty`, `block.prevrandao` used in any hashing or modulo operation for outcome selection
  2. Check `keccak256` inputs — if any input is a miner-controllable value (timestamp, gas, coinbase), flag
  3. For VRF-based protocols: check that the result is used ONLY in the `fulfillRandomWords` callback, not recomputed or cached
  4. Verify that game/lottery outcomes cannot be known before the transaction is mined (commit-reveal if no VRF)
  5. Look for re-entrancy paths that allow an attacker to inspect the "random" value before it is consumed
  6. Check `randao` / `prevrandao` usage on PoS Ethereum — validators can influence within a narrow range
- **Failure Mode**: Miners/validators front-run or manipulate block properties to select favorable outcomes. Users can predict results by simulating the transaction before submission.
- **Common Contexts**: GameFi, lottery/raffle contracts, NFT trait generation, any protocol requiring on-chain randomness

---

## ORACLE-017: composite_chained_oracle_decimal_propagation
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `ChainedPriceSource` accumulating precision through multiple hops without resetting; `DivReducerNode` with incorrect decimals in division; `ChainlinkCompositeOracleProvider` starting with 36-decimal accumulator and dividing incorrectly; `FraxETH = ETH/USD * frxETH/ETH` computed without normalizing intermediate result; `(priceA * priceB) / 1e8` when both prices are 8 decimals (should be `/ 1e16`)
- **Detection Heuristic**:
  1. Map every step in the oracle price chain: `tokenA/USD = tokenA/ETH * ETH/USD` — verify precision at each multiplication
  2. After each multiplication of two N-decimal numbers, confirm that the result is divided by `10**N` to restore the intended precision
  3. For divide/reduce nodes: verify the output decimal count = `inputA.decimals + inputB.decimals - divisionFactor.decimals`
  4. Check that precision is tracked through the chain — an accumulated 36-decimal number passed to code expecting 18-decimal will silently produce wrong results
  5. Look for `Uninitialized Price Precision` — a precision field left at zero in the `Price` struct means all division is by zero (or by 1 if unsigned)
  6. For Redstone oracle nodes: verify that each node's declared decimal count matches its actual output
- **Failure Mode**: Precision errors propagate multiplicatively through a chain. Final price can be off by `10^N` where N is the number of nodes that lost or doubled precision. In extreme cases, causes division by zero or integer overflow.
- **Common Contexts**: Multi-hop price aggregators, cross-currency oracles, protocols using Redstone or custom node-based oracle pipelines

---

## ORACLE-018: nft_floor_oracle_data_corruption
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `NFTFloorOracle.removeFeeder()` corrupting internal data structures (array swap-and-pop with wrong index); `_removeFeeder` leaving dangling references; feeder can prevent their own removal (blocks liquidation); asset/feeder struct indexed incorrectly after removal; `addAsset()` / `removeAsset()` with unchecked index operations
- **Detection Heuristic**:
  1. For oracle feeder arrays, verify that `swap-and-pop` removal correctly updates all cross-references (indices, mappings, linked lists)
  2. Check `removeFeeder` and `removeAsset` for off-by-one errors — the removed element's index must be cleared and the last element's index must be updated in the mapping
  3. Verify that feeder removal has access control — `removeFeeder` should NOT be callable by the feeder being removed (prevents avoiding liquidation)
  4. After simulating add/remove cycles, verify that `getPriceByAsset` returns correct results and doesn't use stale feeder data
  5. Check that `feeders.length` is updated correctly on every add/remove operation
  6. Verify array bounds when iterating feeders after removal — array.length may reflect stale count
- **Failure Mode**: Corrupted feeder data means the oracle returns prices from feeders who are no longer registered, or fails to include active feeders. In lending protocols, this can prevent liquidation (feeder removes self to avoid triggering liquidation of their own position).
- **Common Contexts**: NFT lending protocols using floor price oracles (ParaSpace pattern), any custom multi-feeder oracle with dynamic membership

---

## ORACLE-019: oracle_price_used_during_market_closure_or_invalid_version
- **Frequency**: ~6/500 findings
- **Severity**: HIGH
- **Code Shape**: `invalidOracleVersion` not checked before consuming price; Chainlink returning stale price during exchange closure (equities, forex feeds closed on weekends); Pyth price update with timestamp from the future; `oracleVersion.valid == false` used in perpetual settlement; Perennial's `commitPrice` requiring oracle version validity; `oracle.periodCumulativesInside` on a closed market
- **Detection Heuristic**:
  1. For any asset with non-24/7 trading (equities, forex, real-world assets), verify that the protocol detects and handles "market closed" conditions — Chainlink feeds return the last valid price, not an error
  2. Check perpetual protocol oracle version validation: `require(oracleVersion.valid, "invalid oracle version")` before using price for settlement or liquidation
  3. For Perennial-style protocols: verify that an invalid oracle version (outside the valid price commitment window) does not cause global/local position desync
  4. Check that `answeredInRound` < `roundId` is detected and rejected (Chainlink's way of indicating a round has not been completed)
  5. Verify behavior when oracle returns the same price across multiple consecutive rounds (Chainlink during circuit breaker) — does the protocol treat this as valid or stale?
  6. For GMX/Perennial keeper settlement: check that the keeper cannot choose an oracle version favorable to them (free look into the future via limit order timing)
- **Failure Mode**: Protocol uses a frozen/invalid price from a closed market, creating arbitrage between the stale on-chain price and real market price. Limit order exploits allow traders to observe price direction and selectively execute orders.
- **Common Contexts**: Perpetual futures with off-chain oracle settlement, protocols with real-world asset pricing, keeper-settled positions

---

## ORACLE-020: oracle_access_control_missing_or_permissionless_update
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `setPrice()` callable by anyone; `addOracle()` without role check; `feed_prices()` accepting delayed transactions from any sender; `setPriceFeed()` in `updateRegisteredErc20()` without restriction; `ReserveFeed` contract with no access control on write functions; `OracleSetConfigs` allowing authority to change signing key after verification; permissionless `updatePrice` functions
- **Detection Heuristic**:
  1. Search for all functions that write to oracle price storage: `setPrice`, `updatePrice`, `feed_prices`, `submitReport`, `setPriceFeed` — verify each has `onlyOwner`, `onlyRole`, or equivalent
  2. Check oracle feeder registration: `addFeeder`, `removeFeeder`, `setOracle` — unauthorized callers should not be able to add malicious price sources
  3. For Chainlink-integrated protocols: verify that `AutoRedemption::performUpkeep` has caller validation (only the Chainlink Automation DON, not arbitrary callers)
  4. Check `OracleSetConfigs` or equivalent setup instructions — the oracle authority should be immutable post-deployment, not changeable
  5. Verify that oracle addresses stored in registries cannot be swapped post-initialization without governance timelock
  6. For oracle systems with whitelisted feeders: confirm that the whitelist enforcement is on-chain, not off-chain
- **Failure Mode**: Attacker sets arbitrary prices by calling the unguarded price update function. Alternatively, drains the oracle subscription (VRF, Chainlink request) by triggering unmetered requests.
- **Common Contexts**: Custom oracle implementations, price registry contracts, any protocol that pushes prices on-chain

---

## ORACLE-021: self_referential_or_recursive_moving_average
- **Frequency**: ~3/500 findings
- **Severity**: HIGH
- **Code Shape**: `storePrice()` computing moving average from `movingAverage` field that itself contains a previous moving average (circular dependency); `OlympusPrice.v2.sol` using the computed MA as input to the next MA calculation; oracle using its own output as input; price oracle bootstrapped from itself
- **Detection Heuristic**:
  1. Trace the data flow in `storePrice()` or equivalent: identify the inputs to the moving average calculation
  2. Check if `movingAverage` or any cached price field appears on BOTH the left side (being updated) and right side (being read as input) of the same calculation
  3. Verify that the moving average uses a separate historical observation array, not the previously computed MA value
  4. For protocols with dual price mechanisms (spot + MA): ensure the MA is computed from raw price observations, not from the previous MA
  5. Check initialization: is the MA seeded from a trusted external source, or does it bootstrap from zero/hardcoded value?
  6. Look for comment patterns like `// update moving average using current price` — verify "current price" is an observation, not the previous output
- **Failure Mode**: Moving average converges to a stale or bootstrapped value and never reflects market reality. Or diverges exponentially due to recursive amplification. Protocol misprices assets persistently.
- **Common Contexts**: Protocol-native price smoothing (Olympus RBS, Beanstalk TWAP variants), governance-controlled price oracles

---

## ORACLE-022: oracle_dos_via_malformed_input_or_unbounded_request
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `LLMOracleCoordinator::finalizeValidation` underflow when `scoreRange = 0` (all scores equal); `FeedEvalRequest` division by zero when denominator is computed oracle value; `updateCumulativePrices()` in UniV2 reverting on overflow in Solidity >=0.8; `DoS of SPA Oracle Contract` via state manipulation; oracle blocked by malformed data structure; `Quex callback` congested by queue spam
- **Detection Heuristic**:
  1. Check oracle finalization functions for division-by-zero conditions: when scores are identical, range = 0 → division fails
  2. For UniV2 TWAP implementations in Solidity >=0.8.0: verify that `priceCumulative` addition uses `unchecked{}` block (intentional overflow is required by the protocol design)
  3. Check oracle request queues for unbounded growth — if anyone can submit oracle requests without cost or rate limiting, the queue can be congested to prevent legitimate oracle resolution
  4. Verify that oracle removal operations (`removeOracle`, `removeFeeder`) maintain queue/array integrity — corrupted state can permanently DoS the oracle
  5. For push-oracle receivers: check that malformed or delayed push messages cannot permanently block the oracle (idempotency, message ordering)
  6. Check that oracle callback functions cannot be permanently bricked by a single failed call (e.g., non-try/catch in a loop over oracle responses)
- **Failure Mode**: Oracle becomes permanently non-functional (DoS), blocking liquidations, settlements, or price updates. Or oracle processes garbage data that causes protocol-wide failures.
- **Common Contexts**: Custom oracle aggregators with mathematical finalization, UniV2 TWAP ports to Solidity >=0.8, AI oracle coordinators, queue-based oracle request systems

---

## ORACLE-023: liquid_staking_derivative_exchange_rate_assumption
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `wstETH` priced as `1:1` with ETH instead of using `wstETH.stEthPerToken()`; `stETH` assumed equal to ETH; `_underlyingRefPerTok()` returning 1e18 for LSTs; `WstEth` derivative assuming `~1=1 peg`; `_currentBalance` using Lido pool price directly (manipulable); `LidoEthStrategy._currentBalance` read from pool instead of from `wstETH.getStETHByWstETH`; exchange rate from `getStETHByWstETH` or `getPooledEthByShares` not used
- **Detection Heuristic**:
  1. Identify all liquid staking token interactions: wstETH, rETH, cbETH, stETH, ankrETH, swETH, frxETH
  2. For each LST, verify that the exchange rate is fetched from the token contract: `wstETH.stEthPerToken()`, `rETH.getExchangeRate()`, `cbETH.exchangeRate()`
  3. Check that the rate is NOT read from the liquidity pool (Curve wstETH/ETH pool, Balancer rETH/ETH pool) — pool spot prices are manipulable
  4. Verify that the rate is composed correctly: `wstETH_value_in_USD = wstETH_amount * stEthPerToken * ETH_USD_price / 1e18 / 1e18`
  5. For rebasing tokens (stETH): verify that balance-sensitive functions account for the rebase mechanism — a function using raw balances before and after will see different values
  6. Check that wstETH/stETH distinction is maintained — stETH rebases, wstETH does not; using stETH oracle for wstETH (or vice versa) produces wrong results
- **Failure Mode**: LST is valued at face ETH value rather than its actual ratio (which diverges during slashing events, queue congestion, or normal accrual). Over-borrowing against inflated LST collateral, or wrong liquidation thresholds.
- **Common Contexts**: Lending protocols accepting LSTs as collateral, yield strategies holding wstETH/rETH, stablecoin protocols with ETH-derivative collateral

---

## ORACLE-024: oracle_price_used_for_wrong_token_in_registry
- **Frequency**: ~6/500 findings
- **Severity**: HIGH
- **Code Shape**: `updateRegisteredErc20(address token)` updating mapping at wrong index (e.g., `tokenList[i-1]` instead of `tokenList[i]`); oracle address and LTV stored for wrong collateral token; `getCollateralBalances()` returning `address(0)` when user has no balance in a token; oracle registry with off-by-one indexing; oracle assigned to the wrong asset class during initialization
- **Detection Heuristic**:
  1. Audit oracle registry update functions: verify that the lookup key (token address or index) correctly identifies the intended token
  2. For array-indexed registries: check that `tokenList[index]` is the same token that `oracleList[index]` corresponds to, after any add/remove operations
  3. Simulate remove + re-add sequences: verify that oracle assignments remain consistent after the registry is modified
  4. Check `getCollateralBalances()` and similar view functions — if a token has zero balance, ensure the function returns zero, not `address(0)` as a token address
  5. For LTV and oracle paired assignments: if they are stored in separate arrays, verify that both arrays maintain the same ordering invariant
  6. Check initialization scripts and deployment order — oracle assignments during constructor must match the token registration order
- **Failure Mode**: Protocol uses Oracle A's price to value Token B. This is a systematic permanent mismatch — all operations involving Token B use wrong prices. Allows exploiting any price difference between the two tokens.
- **Common Contexts**: Multi-collateral lending with registry-based oracle assignment, protocols that support dynamic collateral addition/removal

---

## Pattern Frequency Summary

| Pattern ID | Name | Approx. Count | Severity |
|------------|------|---------------|----------|
| ORACLE-001 | chainlink_no_staleness_check | ~35 | HIGH |
| ORACLE-002 | uniswap_slot0_spot_price_manipulation | ~28 | HIGH |
| ORACLE-003 | decimal_mismatch_in_price_calculation | ~45 | HIGH |
| ORACLE-004 | oracle_sandwich_frontrun_on_price_updates | ~22 | HIGH |
| ORACLE-005 | twap_period_too_short_or_incorrect | ~18 | HIGH |
| ORACLE-006 | hardcoded_stablecoin_peg_assumption | ~12 | HIGH |
| ORACLE-007 | lp_token_spot_price_manipulation | ~18 | HIGH |
| ORACLE-008 | inverted_price_feed_base_quote | ~10 | HIGH |
| ORACLE-009 | no_price_outlier_filter_or_bounds_check | ~10 | HIGH |
| ORACLE-010 | oracle_frontrun_price_manipulation_amm | ~15 | HIGH |
| ORACLE-011 | missing_slippage_protection_on_oracle_based_swaps | ~18 | HIGH |
| ORACLE-012 | pyth_oracle_misuse | ~12 | HIGH |
| ORACLE-013 | read_only_reentrancy_balancer_oracle | ~8 | HIGH |
| ORACLE-014 | wrong_asset_price_used_for_different_asset | ~14 | HIGH |
| ORACLE-015 | chainlink_vrf_misuse_or_subscription_drain | ~8 | HIGH |
| ORACLE-016 | weak_on_chain_randomness_source | ~8 | HIGH |
| ORACLE-017 | composite_chained_oracle_decimal_propagation | ~12 | HIGH |
| ORACLE-018 | nft_floor_oracle_data_corruption | ~5 | HIGH |
| ORACLE-019 | oracle_price_used_during_market_closure_or_invalid_version | ~6 | HIGH |
| ORACLE-020 | oracle_access_control_missing_or_permissionless_update | ~8 | HIGH |
| ORACLE-021 | self_referential_or_recursive_moving_average | ~3 | HIGH |
| ORACLE-022 | oracle_dos_via_malformed_input_or_unbounded_request | ~8 | HIGH |
| ORACLE-023 | liquid_staking_derivative_exchange_rate_assumption | ~8 | HIGH |
| ORACLE-024 | oracle_price_used_for_wrong_token_in_registry | ~6 | HIGH |

**Total patterns: 24**
**Estimated coverage: ~380/500 findings mapped** (remaining ~120 are edge cases, context-specific logic errors, or findings from unrelated clusters that landed in this sample)
