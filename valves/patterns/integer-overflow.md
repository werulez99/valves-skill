# Integer Overflow Patterns
> Extracted from 3,478 findings (500 sampled)
> Pattern count: 28

---

## INT-001: unchecked_subtraction_state_underflow
- **Frequency**: ~52/500
- **Severity**: HIGH
- **Code Shape**: `a - b` where `b` can exceed `a` under legitimate protocol conditions (not just attacker-controlled); state variables tracking balances, totals, or counters decremented without guard; often in withdrawal, repayment, or unstaking paths
- **Detection Heuristic**:
  1. Enumerate all `-` operations on state variables (balances, totalDeposited, totalBorrowed, points, lockedStake, etc.)
  2. For each, ask: can the subtracted value ever exceed the minuend through normal operation sequencing (partial fills, liquidations, slash events, multi-path updates)?
  3. Check whether the function is called in an epoch/round context where the state may have already been decremented by another code path
  4. Verify that pre-conditions (`require(a >= b)`) exist and are correctly placed BEFORE the subtraction
  5. In Solidity <0.8: explicit underflow wrapping produces huge positive values; in ≥0.8: reverts — both are bugs
  6. Trace multi-transaction sequences: deposit → slash/loss event → withdraw to identify sequences that make `a < b`
- **Failure Mode**: Revert (DoS) in Solidity ≥0.8; catastrophically large value (fund theft or phantom rewards) in Solidity <0.8 or `unchecked` blocks
- **Common Contexts**: Staking/unstaking (`lpPosition.points`, `totalStaked`), withdrawal queues (`totalDeposited`, `pendingWithdrawalAmount`), reward accounting (`rewardDebt`, `accruedRewards`), liquidation accounting, partial order matching (`v.amount -= filled`)

---

## INT-002: unsafe_type_downcast_truncation
- **Frequency**: ~38/500
- **Severity**: HIGH
- **Code Shape**: Explicit cast `uint256 → uint128/uint96/uint64/uint32/int64/int128`; `int256 → int64`; `int128 → uint`; values computed in a wider type then stored/passed in narrower type; common in DeFi math intermediate results
- **Detection Heuristic**:
  1. Search for explicit casts: `uint128(x)`, `uint96(x)`, `uint32(x)`, `int64(x)`, `SafeCast.toUint128()` absence
  2. For each cast, derive the maximum value of the expression being cast using worst-case inputs (large token amounts, high prices, many decimals, large timestamps)
  3. Check whether the maximum value fits in the target type's range (uint128 max ~3.4×10^38; uint96 max ~7.9×10^28; uint32 max ~4.3×10^9; uint64 max ~1.8×10^19)
  4. Flag casts of: `amount * price`, `shares * exchangeRate`, `timestamp * rate`, `balance * 1e18`
  5. Check if the narrowed value is later used in arithmetic — truncation silently corrupts calculations
  6. Look for `int → uint` casts on values that could legitimately be negative (prices going down, net PnL)
- **Failure Mode**: Silent value truncation producing corrupted accounting (wrong balances, incorrect collateral ratios, false position values); fund theft via inflated shares; DoS via unexpected reverts
- **Common Contexts**: Share/price calculations in vaults (ERC4626), position accounting in perps/options, fee calculations, TWAP accumulators, reward-per-share indices, bridge amount encoding

---

## INT-003: multiplication_overflow_before_division
- **Frequency**: ~35/500
- **Severity**: HIGH
- **Code Shape**: `(a * b) / c` where intermediate `a * b` overflows before division reduces it; large precision multipliers like `1e18 * 1e18`, `1e12 * 1e18 * 1e32`; accumulator updates `accTokenPerShare += reward * 1e12 / totalStaked`
- **Detection Heuristic**:
  1. Find all multiplication expressions: `a * b`, `a * b * c`
  2. For each, estimate maximum values of operands from token amounts (up to `totalSupply`), precision constants (1e6 to 1e32), prices (up to 1e8 with 18 decimals)
  3. Check if product can exceed `type(uint256).max` (~1.15×10^77) — key: two 1e18 values multiplied = 1e36, fine; 1e18 * 1e18 * 1e18 = 1e54, fine; 1e62 (as in finding [206]) will overflow
  4. Verify the division happens BEFORE overflow can occur (use MulDiv libraries: `mulDiv(a, b, c)`)
  5. Check for presence of `unchecked {}` blocks that wrap multiplication — pre-0.8 overflow behavior is INTENTIONAL there
  6. Look for `accTokenPerShare` patterns: `reward * PRECISION / totalStaked` — verify PRECISION magnitude vs token decimals
- **Failure Mode**: Overflow wraps to small value → reward per share drastically underestimated; or wraps to huge value → immediate DoS or fund theft when used as index
- **Common Contexts**: Reward-per-share accumulators (MasterChef-style), price calculations using oracle feeds × precision, fee calculations, liquidity math in AMMs

---

## INT-004: intentional_overflow_missing_in_fee_growth_tick_math
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Fee growth subtraction in Uniswap-style tick math: `feeGrowthInside = feeGrowthGlobal - feeGrowthOutsideLower - feeGrowthOutsideUpper`; `secondsPerLiquidity - secondsPerLiquidityPeriodStart`; operations in Solidity ≥0.8 that MUST be `unchecked` to allow wrapping by design
- **Detection Heuristic**:
  1. Identify fee growth, seconds-per-liquidity, or cumulative price subtraction expressions derived from Uniswap V2/V3 math
  2. Verify the Solidity version — in ≥0.8, these MUST be inside `unchecked {}` blocks to allow intentional underflow
  3. Check if the code is ported from V2/V3 (which runs under 0.7 implicit overflow semantics) but compiled under ≥0.8
  4. Look for the pattern: `feeGrowthAbove = feeGrowthGlobal - feeGrowthOutside` — if not `unchecked`, will revert when global resets
  5. Confirm the contract's Solidity version pragma — ≥0.8 without `unchecked` is the bug
  6. Cross-reference with `FullMath.sol`, `TickMath.sol` — these libraries rely on wrapping; if imported into ≥0.8 context, they need `unchecked`
- **Failure Mode**: Reverts in fee/reward collection and position operations, permanently locking LP positions and fees; incorrect fee calculation when subtraction produces negative intermediate that is silently truncated
- **Common Contexts**: Concentrated liquidity AMMs (Uniswap V3 forks), staking rewards using epoch-based accumulators, Ramses, Superposition, Sushi CLP, Particle, Sorella

---

## INT-005: division_before_multiplication_precision_loss
- **Frequency**: ~22/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `(a / b) * c` where division truncates before multiplication amplifies; common in fee calculations, price formulas, reserve calculations; `totalSupply * curveFactor / PRECISION` followed by another multiplication
- **Detection Heuristic**:
  1. Search for division operators `/` followed by multiplication `*` on the same value
  2. Trace the order of operations: if `a / b * c`, rewrite as `a * c / b` and compare results — if different, there's precision loss
  3. Quantify magnitude: if `a/b` rounds down by 1, and then multiplied by `c`, loss is `c` units (not 1)
  4. Check for bonding curve formulas, share-to-asset conversions, and fee calculations
  5. Look for integer division of small values: `1 / 2 = 0` — all subsequent multiplication produces 0
  6. Verify precision recovery: does the code use `mulDiv(a, c, b)` (one operation with full intermediate precision)?
- **Failure Mode**: Systematic rounding down that either rounds fees/prices to zero (loss of revenue) or creates precision-exploitable arbitrage; in extreme cases, all calculations return 0
- **Common Contexts**: Bonding curves (Sofamon, Juicebox), AMM price calculations, fee rate computations, share/asset conversions in vaults

---

## INT-006: uint_overflow_in_counter_or_accumulator_variable
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: `counter++` or `counter += N` on `uint32`, `uint64`, `uint96` types that may wrap; batch nonce counters; message count fields; UTXO accumulators; tree commitment indices that wrap to 0
- **Detection Heuristic**:
  1. Find all increment operations on non-uint256 types: `uint32 counter; counter++;`
  2. Estimate the realistic maximum value of the counter — for batch nonces, message counts, block heights
  3. Check whether wrapping has security implications: a nonce wrapping to 0 enables replay; a tree index wrapping overwrites existing entries
  4. Look for `++s_batchNonce` on uint96: 2^96 ≈ 7.9×10^28 — safe for most cases, but confirm
  5. For UTXO/ZK commitment trees: verify index cannot wrap to overwrite earlier commitments
  6. Check whether the type was chosen for storage packing and whether the maximum is actually reachable by a DoS vector
- **Failure Mode**: Counter wraps to 0 enabling nonce replay attacks; tree index wraps to overwrite prior commitments; batch processing halts; network-level DoS when validators process malformed counter values
- **Common Contexts**: ZK commitment trees (Hinkal), cross-chain message batches (Recall, FIL subnet), batch nonce counters (Notional), transaction limit counters in mempools (Sei EVM)

---

## INT-007: negative_int_cast_to_uint_produces_large_value
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `uint(negativeInt)` or `uint256(int256Value)` where the int can be negative; `int256` funding rate cast to `uint256`; `int128 → uint128`; implicit cast in arithmetic `uint + int` where int is negative; `newStake` is a negative number cast to `uint`
- **Detection Heuristic**:
  1. Search for explicit casts from signed to unsigned types: `uint256(x)` where `x` is `int256/int128`
  2. Find all places where signed values are read from external sources (oracles, user inputs) and then cast to uint
  3. Check arithmetic expressions mixing signed and unsigned: `uint256(a) + int256(b)` — if `b` is negative, this overflows
  4. Look for oracle price feeds returning signed integers (Chainlink returns `int256`) cast directly to `uint256`
  5. Verify `require(value >= 0)` guard exists before every `int → uint` cast
  6. In Rust/Move: check `as u64` on values that could underflow the i64/i128 domain
- **Failure Mode**: Negative number cast to uint produces `type(uint256).max - |value| + 1` — astronomically large value; used as amount → catastrophic over-transfer; used as index → out-of-bounds array access; used as price → protocol-wide miscalculation
- **Common Contexts**: Funding rate calculations (Liquorice, Tracer), oracle price consumption, staking delta calculations (Lido), price diff computations (Derby), integer underflow from `int` price subtraction

---

## INT-008: accumulator_not_updated_symmetrically_in_all_paths
- **Frequency**: ~42/500
- **Severity**: HIGH
- **Code Shape**: State variable updated on path A but not path B when both paths should mirror each other; `totalBorrowed` updated on borrow but not on pay; `cdsPoolValue` reset by deposit but not preserved on withdraw; missing update in `emergency` / `recovery` / `cancel` / `pause` code paths
- **Detection Heuristic**:
  1. Identify paired operations: (deposit/withdraw), (borrow/repay), (stake/unstake), (mint/burn), (lock/unlock), (add/remove)
  2. For each pair, list all state variables modified in one direction
  3. Verify each variable is also modified (in reverse) in the paired operation
  4. Check special-case paths: emergency exits, migration functions, admin overrides, pause handlers — these often miss updates
  5. Search for state variables that grow monotonically but never decrease (accumulator stuck), or decrease without growing (underflow trap)
  6. Trace cross-chain accounting: value added on one chain but wrong amount subtracted on another
- **Failure Mode**: Accounting diverges from actual balances; impossible to reach desired final state (can't fully repay debt, can't withdraw all funds); stuck funds; inflated or deflated TVL
- **Common Contexts**: Lending protocols (totalBorrowed, totalDeposited), CDS pools (Autonomint), staking (userTotalStaked), cross-chain bridges (subnet circulating supply), migration contracts

---

## INT-009: wrong_arithmetic_operator_sign_or_direction
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: `+` used where `-` is required or vice versa; `>` used where `<` is required; addition of premium when subtraction is needed (`SettleLongPremium`); incorrect formula sign in financial calculations; adding to `fromBalance` when it should be subtracted
- **Detection Heuristic**:
  1. For every financial formula, derive the expected direction mathematically from protocol documentation
  2. Check: fees should reduce amounts → look for fee being added instead of subtracted
  3. Check: premium paid by long → should deduct from long's balance, not add to it
  4. Verify invariants: total after operation = total before ± expected delta (not ± wrong delta)
  5. Look for copy-paste errors: similar functions where one correctly uses `+` and another incorrectly uses `+` in a context that requires `-`
  6. Test boundary case: does the formula produce a sensible result when input is at maximum?
- **Failure Mode**: Balances increase when they should decrease (fund theft or phantom liquidity); positions become solvent when they should be insolvent; rewards paid out of the wrong pool
- **Common Contexts**: Premium settlement in options (Panoptic SettleLongPremium), funding fee direction (Elfi fromBalance), vault share formulas, CDS accounting (Autonomint), reward distribution sign errors

---

## INT-010: precision_constant_magnitude_mismatch
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Using `540` instead of `540 days`; WAD (1e18) used where token decimals (1e6 for USDC) are needed; `1e12` precision multiplier in reward calculation where `1e6` would be correct; using APY directly as per-second rate (off by 365×24×3600 = 31.5M×)
- **Detection Heuristic**:
  1. Search for numeric literals in financial formulas: `540`, `1e12`, `1e18`, `1e6`, `1e8`
  2. For time constants: verify units — `540 days` vs `540` differ by 86400×
  3. For token decimals: check each token's decimal() value and confirm precision constants match
  4. For rate calculations: identify whether a rate is annual, per-epoch, per-second — verify denominator matches rate period
  5. Annotate each expression with units (e.g., `[token_units / 1e18]` or `[seconds]`) and check dimensional consistency
  6. Compare with reference implementations (Uniswap, Compound, Aave) for equivalent operations
- **Failure Mode**: Percentage calculation produces >100% (unlock entire amount immediately); fee calculation returns amount 10× too high or too low; interest charged at APY per second (31.5M× overcollection)
- **Common Contexts**: Vesting/unlock percentage (Superfluid), reward rate (Penguin Karts, Graviton Zero), fee divisors (Astaria, Ammplify borrow fee), LP fee unit mismatch (Primitive WAD vs token units)

---

## INT-011: missing_overflow_check_in_flash_loan_amount
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `totalSupply + amount` in ERC20 flash mint can overflow; `totalBorrow + flashAmount` can overflow uint256; `ERC20FlashMintUpgradeable.flashLoan()` mints without checking overflow; flash loan amount controlled by caller
- **Detection Heuristic**:
  1. Find `flashLoan` implementations that mint tokens temporarily
  2. Check: `totalSupply + amount` — if `amount` is user-supplied and large, can overflow uint256
  3. Verify whether the contract is pre-0.8 (wraps silently) or ≥0.8 (reverts — still a DoS)
  4. Look for `maxFlashLoan()` return value — if it returns `type(uint256).max - totalSupply`, check whether that value is actually safe
  5. Verify that the minted amount is checked against a real capacity limit, not just `type(uint256).max`
  6. Check whether flash loan fee addition `amount + fee` can also overflow
- **Failure Mode**: Overflow wraps totalSupply to small value (Solidity <0.8) enabling collateral theft; overflow revert DoS prevents legitimate flash loans (Solidity ≥0.8)
- **Common Contexts**: ERC20 flash mint (NFTX), lending pool flash loans, integrated flash loan protocols

---

## INT-012: array_index_off_by_one_or_wrong_bound
- **Frequency**: ~15/500
- **Severity**: HIGH
- **Code Shape**: Loop `i < length` vs `i <= length`; starting array at index 1 but treating 0 as valid; `lastQueueIndex` not cleared; misplaced `++i` inside condition instead of increment; bid sort algorithm using wrong index
- **Detection Heuristic**:
  1. Enumerate all array/loop bounds: `for (i = 0; i < n; i++)` — verify `<` vs `<=` is correct for the inclusive/exclusive semantics needed
  2. Check whether arrays are 0-indexed or 1-indexed; find all accesses and verify consistency
  3. Look for `++i` or `i++` placement inside `if/while` conditions rather than loop increments
  4. Verify cleanup of last-element references: when removing last item, is `lastIndex` cleared?
  5. For sorted data structures: verify comparator direction and boundary conditions at array edges
  6. Check: is `length - 1` computed on empty array (length=0)? → underflow to maxUint
- **Failure Mode**: Array out-of-bounds access reverts the function; infinite loops gas-drain the block; skipped elements in iteration create functional gaps; sorted invariant broken leads to incorrect matching
- **Common Contexts**: Withdrawal queues (EigenLayer slashQueuedWithdrawal ++i bug), bid sorting (Fastlane Atlas), nonce increment placement (Polygon zkEVM), LiquidationBranch for-loop bounds (Zaros)

---

## INT-013: uint_overflow_in_price_or_oracle_computation
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: `price * decimalFactor` overflows; `oraclePrice * amount / 1e18` where oraclePrice is from Chainlink (up to 1e18 range) and amount is large; `priceX8 = price * 10^8` intermediate overflow; cumulative price addition in TWAP
- **Detection Heuristic**:
  1. Find all oracle price consumption sites: `latestRoundData()`, `getPrice()`, `getPriceInUSD()`
  2. For each, determine the oracle's return magnitude (Chainlink ETH/USD: ~2000e8; token prices can be 1e8 to 1e36)
  3. Multiply oracle price by the largest plausible amount to check if intermediate exceeds uint256
  4. Check cumulative price fields in TWAP: `priceCumulative += price * timeElapsed` — over long periods, can overflow in intended wrapping manner; verify `unchecked` is present
  5. Look for `price * 10^decimals` where decimals is user-settable or comes from external token
  6. Verify `mulDiv` (not `*` then `/`) is used for `price × amount / precision`
- **Failure Mode**: Oracle price overflow causes DoS on all price-dependent operations; cumulative price overflow without unchecked causes revert in TWAP; incorrect price used for collateral valuation
- **Common Contexts**: Chainlink-integrated protocols, TWAP oracles (Uniswap V2 cumulative, UniswapV2PriceOracle), DEX price calculations (Good Entry priceX8), oracle composite aggregators (NUTS Finance)

---

## INT-014: vm_or_zk_circuit_arithmetic_missing_range_constraint
- **Frequency**: ~22/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: Missing range check in ZK circuit gadget (`MulDivGadget`, `shr` opcode constraint); VM arithmetic without bounds check causes panic; Rust `as u64` cast without range validation in blockchain node; shift amount exceeds limb size in big integer library
- **Detection Heuristic**:
  1. For ZK circuits: every arithmetic gadget must constrain its outputs to valid field element ranges — find all `MulDivRelation`, `BinopRelation`, reduction gates without range checks
  2. For VM implementations (EVM emulators, zkVM): verify all opcode handlers check that inputs are within valid ranges before computation
  3. For Rust blockchain nodes: find `as u64`, `as u32` casts on external data — these panic on overflow in debug, silently truncate in release
  4. For big integer libraries: verify shift operations check `shift_amount < limb_bits` before performing `>>` or `<<`
  5. Test with: shift amount = word_size (e.g., shift by 64 bits in 64-bit limb) — undefined behavior in many languages
  6. For ZK: verify that reduction gates prove the quotient is within bounds, not just that remainder is valid
- **Failure Mode**: Underspecified circuits admit invalid proofs (malicious prover wins); VM panics crash nodes causing network-wide DoS; incorrect opcode execution corrupts execution state; zkEVM produces wrong trace accepted by verifier
- **Common Contexts**: zkSync circuits (shr/div/binop), zkEVM (Polygon zkEVM, DeGate), OpenVM (ZK), Solana ZK Token right shift, Stylus big integer library, Monad EVM emulator

---

## INT-015: first_depositor_share_inflation_via_zero_division_edge
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: First deposit into empty vault when `totalSupply = 0`; share calculation `amount * totalShares / totalAssets` with `totalAssets = 0`; first LP inflates price by sending tiny amount then making huge deposit; attacker donates dust before first deposit
- **Detection Heuristic**:
  1. Find share minting functions: `deposit()`, `mint()`, `addLiquidity()`
  2. Check the branch when `totalShares == 0` or `totalAssets == 0` — what is `sharesOut`?
  3. Verify virtual offset protection: OpenZeppelin ERC4626 uses `+1` virtual share offset; check if protocol uses equivalent
  4. Check for minimum liquidity lock (Uniswap V2 burns MINIMUM_LIQUIDITY to address(0))
  5. Simulate: attacker deposits 1 wei → gets 1 share; attacker donates 1e18 tokens → share price = 1e18; victim deposits 1e18-1 → gets 0 shares
  6. Verify `previewDeposit` and `previewMint` round in the correct direction
- **Failure Mode**: Subsequent depositors receive 0 shares or drastically fewer shares than entitled; share price becomes astronomically high locking out smaller depositors; victim's assets absorbed into attacker's single share
- **Common Contexts**: ERC4626 vaults (Velodrome first LP), reward pools (XDEFI, Biconomy), concentrated liquidity pools (Sushi), AMM pools with share-based LP tokens

---

## INT-016: timestamp_or_block_number_overflow
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `timestamp` field in ZK VM overflows field modulus (BabyBear prime ~2^31); `uint32` timestamp wrapping in 2038; `block.number * someRate` overflows uint64; `_expiration = type(uint256).max` used as sentinel causing arithmetic with it to overflow
- **Detection Heuristic**:
  1. Check the type of timestamp storage: `uint32` overflows in 2038; `uint64` is safe for millennia; `uint40` overflows in ~34,000 years
  2. For ZK VMs using small field elements (BabyBear = 2^31 - 2^27 + 1): verify timestamp is taken modulo field size or saturated
  3. Search for `type(uint256).max` or `type(uint64).max` passed as expiration — verify all arithmetic using it is guarded
  4. Check `endTime - startTime` computations when `endTime` could be max uint
  5. For `block.number * rate`: estimate maximum block number × rate and verify it fits in the target type
  6. Look for time-based unlock percentage calculations: `elapsed / totalDuration` where `totalDuration = max_uint` → percentage = 0 or arithmetic reverts
- **Failure Mode**: Lock/expiration logic inverted (everything locked forever or unlocked immediately); ZK VM produces invalid execution traces; depositor locks funds indefinitely (DoS by setting max expiration)
- **Common Contexts**: Vesting contracts (VTVL, Superfluid 540 vs 540 days), ZK VMs (OpenVM timestamp field overflow), deposit expiration (OpenQ max uint lock), lock duration arithmetic

---

## INT-017: mapping_counter_not_reset_enabling_repeated_execution
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Boolean or counter in mapping not cleared after use: `_isLiquidation[id]` not deleted after reserve(); `stakedAt` not reset after irrevocable prime token; `mintCounter` for NFT sales incremented but not cleared between rounds; VIP quota not reset on level change
- **Detection Heuristic**:
  1. Find all mappings that track state of individual entities: `mapping(address => bool)`, `mapping(uint => uint)`
  2. For each, trace the full lifecycle: set → use → reset? Verify reset happens in all exit paths
  3. Check multi-round or multi-epoch operations: is the state reset between rounds?
  4. Look for `delete mapping[key]` — if absent in the "completion" path, it's a candidate bug
  5. Verify that re-entry into the same state machine (second time through a multi-step flow) doesn't see stale state
  6. Check governance/voting: is vote weight reset after proposal execution?
- **Failure Mode**: Users can exploit stale state to receive discounts/benefits they no longer qualify for; NFT mints can be bricked by stale counter; VIP quotas underflow; protocol stuck in phantom state
- **Common Contexts**: NFT minting rounds (NextGen), liquidation state (Flayer `_isLiquidation`), prime token issuance (Venus stakedAt), VIP discount quotas (Flooring Protocol)

---

## INT-018: incorrect_scaling_for_token_decimal_differences
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Protocol assumes 18 decimals but token has 6 (USDC) or 8 (WBTC); `amount * 1e18 / price` where price is in 8 decimals but amount is in 18 decimals; `reward * 1e12` accumulator breaks for tokens with >18 decimals; `scaledAmount / 1e18` for USDC produces 0
- **Detection Heuristic**:
  1. Find all hardcoded precision constants: `1e18`, `1e12`, `WAD`, `RAY`
  2. For each, trace which token's decimals it should match
  3. Check: `token.decimals()` called dynamically vs hardcoded constant — flag hardcoded
  4. Verify cross-token arithmetic: `amountA * priceAinB / precisionFactor` — confirm `precisionFactor` accounts for both tokens' decimals
  5. Test with USDC (6), WBTC (8), USDT (6), DAI (18), some tokens (>18) — at least spot check
  6. Look for `>18 decimals` paths: tokens with 20+ decimals will overflow `amount * 1e18` if amount is already scaled
- **Failure Mode**: USDC amounts treated as 1e12 times smaller → massive loss of precision; >18 decimal tokens overflow; incorrect collateral valuation; wrong interest rates; revert-on-withdrawal due to arithmetic mismatch
- **Common Contexts**: Lending protocols (Core Contracts debt token), reward calculators (RewardsController Cod3x lend), LP fee accounting (Primitive WAD vs token unit), oracle price scaling (Cryptex interest)

---

## INT-019: signed_integer_domain_violated_by_external_input
- **Failure Mode**: Underflow into large positive, or overflow into large negative; wrong branch taken in signed comparison
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `int` variables decremented below zero when unsigned semantics assumed; funding rate from oracle can be negative; `netPnL` used in unsigned context; `int256 - uint256` implicit conversion; Rust `i64` subtraction wrapping in release builds
- **Detection Heuristic**:
  1. Find signed integer variables (`int256`, `int128`, `int64`) and their subtraction operations
  2. Check: does the computation ever expect a result that crosses zero? If `int x; x -= y;` where y > x → correctly negative or underflow?
  3. Verify all comparisons: `if (int_value >= 0)` before using as index/count/amount
  4. For external oracle data returning signed values: verify sign handling before downstream arithmetic
  5. In Rust: arithmetic on signed integers panics in debug on overflow but wraps in release — check `--release` build behavior
  6. Look for `liquidation_amount = collateral - debt` as signed, then used in unsigned context
- **Common Contexts**: Perpetual DEX P&L accounting (Symmetrical, Stella), funding rate calculation (Liquorice), validator balance tracking (Lido), liquidation credit/debit accounting

---

## INT-020: gas_or_resource_limit_arithmetic_overflow
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Loop iterating over unbounded array growing without limit; gas calculation accumulator overflows native int type; `nuisanceGas` budget arithmetic; transaction count exceeds configured `uint32` field; block gas limit computation misconfigured
- **Detection Heuristic**:
  1. Find all loop-based state accumulation: does the loop bound grow unboundedly (number of active positions, number of claimants, number of plugins)?
  2. For gas calculators: check that gas accumulators use the full native word size, not smaller types
  3. For Cosmos SDK / Substrate: verify that gas consumption per extrinsic is bounded and doesn't overflow `u64`
  4. Check `block_gas_limit` configuration inputs — are they validated against `uint` max?
  5. Look for functions callable by anyone that extend arrays used in iteration (griefing vectors)
  6. Trace: maximum realistic array size × gas per element vs block gas limit
- **Failure Mode**: Unbounded loop hits block gas limit → DoS of critical protocol function; gas counter overflow causes accounting errors; network-level liveness failure when validators process oversized blocks
- **Common Contexts**: Carapace protection pool (too many active protections), Cowri Labs Shell (>256 slices), PieDAO gas overflow in loop, Cosmos SDK unchecked gas, Monad block size validation

---

## INT-021: big_number_library_arithmetic_error
- **Frequency**: ~8/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: `BigNumber.innerAdd()` carry propagation bug; custom `sqrt()` with incorrect exponent adjustment; multi-word limb shift overflow in `shr_assign`/`shl_assign`; incorrect `pow` implementation returning integer only; `FullMath` library used with wrong version
- **Detection Heuristic**:
  1. Find all uses of custom big number or fixed-point math libraries
  2. Verify library version compatibility with the Solidity/Rust version in use
  3. For `sqrt`: check digit adjustment timing — early vs late 72-digit adjustment changes result exponent
  4. For multi-limb shift: verify `shift_amount < LIMB_BIT_SIZE` guard; check carry handling across limbs
  5. For `pow`: verify it handles fractional exponents if protocol requires them
  6. Cross-reference with the reference implementation (e.g., Uniswap's FullMath must run under <0.8 semantics)
- **Failure Mode**: Incorrect calculation results silently corrupted; funds computed with wrong BigNumber sent to wrong addresses; sqrt used in pricing produces wrong exchange rate
- **Common Contexts**: ZK proof systems (Eco Contracts BigNumber), AMM pricing math (Forte sqrt), Stylus library (limb shift), zkSync full math, Superposition pow function

---

## INT-022: reward_index_manipulation_via_share_price_inflation
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `accTokenPerShare` or `rewardPerShare` index reaches `type(uint104).max` when totalSupply is dust; index overflows when reward amount is large relative to tiny liquidity; reward per share index used in `uint104` or `uint128` storage slot
- **Detection Heuristic**:
  1. Find reward index storage variables and their types: `uint104 accTokenPerShare`, `uint128 rewardPerToken`
  2. Compute maximum value: `maxReward * PRECISION / minTotalSupply` — does it fit in the storage type?
  3. Check: if totalSupply can become dust (e.g., 1 wei), what is max reward index increment?
  4. Look for where the index is consumed: `pendingReward = (balance * rewardPerShare) / PRECISION - rewardDebt` — can `balance * rewardPerShare` overflow before division?
  5. Trace donation attack: attacker sends tiny deposit, protocol adds large reward → rewardPerShare = large_reward / 1_wei = massive
  6. Verify that transfers of reward-index-tracking tokens correctly update the stored debt
- **Failure Mode**: Index overflow saturates to max → all subsequent users get zero rewards (DoS); or index is used in further multiplication that overflows → reverts on all transfers and claims
- **Common Contexts**: AToken rewards (Cod3x lend RewardsDistributor), staking reward pools (MasterChef-style), gauge rewards, ERC20 reward trackers

---

## INT-023: cross_chain_message_value_overflow_or_underflow
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Child subnet circulating supply inflated when xnet messages with value > 0 not correctly accounted; amount transferred on source chain doesn't match amount received on destination due to truncation in encoding; `msg.value` reused across multiple calls in loop
- **Detection Heuristic**:
  1. Find all cross-chain bridge/message encoding: amount serialized into fixed-width fields (uint32, uint64, uint96)
  2. Check: can the source amount exceed the target field's max value? If so, truncation on encode
  3. Verify: symmetric encode/decode — amount encoded as uint64 on source must be decoded as uint64 on destination, not uint256
  4. Find `msg.value` usage in loops — `msg.value` is fixed per transaction but loop may expect it to multiply
  5. Check circulating supply accounting on subnet spawn/kill: minted ≠ burned → supply inflation
  6. For Wormhole/LayerZero: verify transceiver instruction ordering doesn't corrupt amount field
- **Failure Mode**: Circulating supply on L2/subnet inflated enabling unbacked minting; amounts lost in transit (burned on source, not credited on destination); msg.value reuse in loops funds only first iteration
- **Common Contexts**: FIL subnet messages (Recall), Wormhole NTT, LayerZero cross-chain, apDAO ERC20 DAO creation loop, Optimistic Finality amount trimming

---

## INT-024: memory_pointer_arithmetic_overflow
- **Frequency**: ~8/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: Heap/stack pointer arithmetic in low-level VM memory allocator; `ptr + offset` overflows native word size causing pointer to wrap to protected memory region; `FIX_MEMOFFSET` macro overflow; Vyper `concat` builtin corrupts adjacent memory slots
- **Detection Heuristic**:
  1. Find all raw pointer arithmetic in low-level VM/runtime code: `ptr + len`, `base + offset`
  2. Verify: `ptr + len` is checked against the memory region boundary BEFORE dereferencing
  3. For Vyper compiler builtins: verify `concat` length computation doesn't exceed allocated buffer
  4. Check: does `offset` come from user-controlled data? If so, overflow enables write-to-arbitrary-address
  5. For ZK VMs: verify memory syscalls (memset, memcpy) check that `addr + len` doesn't cross memory region boundaries
  6. Look for: can attacker craft input that makes pointer wrap past protected region?
- **Failure Mode**: Attacker writes arbitrary content to protected memory overwriting security-critical data; heap pointer corruption crashes the VM; arbitrary code execution in worst case; ZK proof validity compromised
- **Common Contexts**: OpenVM heap allocator, Mass FIX_MEMOFFSET, Vyper concat builtin, Solana memory syscalls, EVM emulators

---

## INT-025: unchecked_block_wrapping_in_wrong_scope
- **Frequency**: ~14/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `unchecked { index++ }` applied to loop counter also wraps other arithmetic inside the block; seller share calculated inside unchecked causing underflow to produce huge value; `unchecked` used to save gas but wraps security-critical subtraction
- **Detection Heuristic**:
  1. Find all `unchecked {}` blocks
  2. For each, list all arithmetic operations inside: which are safe (counter increment) vs unsafe (balance subtraction)?
  3. Ask: if any `unchecked` subtraction underflows, what is the security impact?
  4. Check: is the `unchecked` block broader than necessary (wrapping too many operations)?
  5. For loop counter increments in `unchecked`: verify no other arithmetic in the same block can underflow maliciously
  6. Compare: was the developer's intent only to skip the counter overflow check, or did they accidentally wrap other operations?
- **Failure Mode**: Underflow produces `type(uint256).max - |x| + 1` — used as share/amount creates massive value (fund theft); attacker triggers underflow path in `unchecked` to steal assets
- **Common Contexts**: Unicrow split calculation (seller share in unchecked), Fractal treasury (duplicate index++ in unchecked), gas optimization patterns in DeFi that accidentally expand scope

---

## INT-026: off_by_one_in_epoch_or_period_calculation
- **Frequency**: ~15/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `epoch - 1` computed during epoch 0; `currentMonth - lastMonth` where periods not yet elapsed; `monthPassed` calculation missing year boundary; `startDrawId - 1` when draw has been erased; period index off by one in reward throttle check
- **Detection Heuristic**:
  1. Find all `epoch - 1`, `period - N`, `round - 1` arithmetic
  2. Check: what is the value when the variable is at its minimum (0, 1)? Does the subtraction underflow?
  3. Trace epoch/period initialization: does the protocol correctly handle the genesis state (epoch 0, period 0)?
  4. Check boundary conditions: `if (epoch > 0) { use epoch - 1 }` — is this guard present?
  5. Verify `currentYear * 12 + currentMonth` arithmetic for multi-year period tracking
  6. For circular/windowed storage: verify that oldest period index is not confused with newest
- **Failure Mode**: Revert in epoch 0 / genesis state prevents any protocol activity; incorrect period selection causes rewards from wrong epoch; stale price data used in calculations
- **Common Contexts**: Options protocols (Thetanuts epoch 0 revert), staking reward epochs (SCProtection monthPassed), TWAP windows (Ramses periodCumulativesInside), prize pools (PoolTogether startDrawId)

---

## INT-027: reserve_or_pool_balance_not_updated_on_fee_collection
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Fee collected from pool/vault but `reserve` or `totalAssets` not reduced; `collectFee()` transfers tokens out but doesn't update the internal accounting variable; vault's reserve diverges from actual balance enabling drain
- **Detection Heuristic**:
  1. Find all fee collection functions: `collectFees()`, `claimFees()`, `withdrawProtocolFees()`
  2. For each, trace: (a) tokens transferred out AND (b) internal accounting variable updated?
  3. Verify that `totalReserves -= fees` or equivalent occurs in same transaction as `transfer(fees)`
  4. Check for time-delayed fee collection: are reserves updated at accrual time or at withdrawal time? Mismatch creates exploit window
  5. Verify Uniswap V3 fork fee collection: `reserve0`, `reserve1` updated after `collect()`?
  6. Test: after fee collection, does `totalAssets()` still equal actual token balance?
- **Failure Mode**: Stale reserves inflate reported liquidity; attackers can drain the discrepancy between reported and actual reserves; subsequent operations (swaps, withdrawals) use wrong reserve values leading to incorrect pricing
- **Common Contexts**: Balancer V3 (reserve not updated on fee collect), Uniswap forks (Sushi ConcentratedLP burn), vault protocols (Tenbin revenue vs deposit confusion), TokenisableRange (Good Entry fee accounting)

---

## INT-028: integer_overflow_in_non_evm_runtime_node_crash
- **Frequency**: ~15/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: Rust `checked_add` not used; `u64::MAX + 1` panic in debug mode or silent wrap in release; Go integer overflow in consensus calculation; `check_total_coins` arithmetic overflow crashes RPC node; BitmapToQuorumIds panic on malformed bitmap
- **Detection Heuristic**:
  1. For Rust blockchain nodes: search for arithmetic on values derived from network messages without `checked_add`, `checked_mul`, `saturating_add`
  2. For Go: search for `int` arithmetic on external data without bounds checking (Go uses machine-word int, platform-dependent)
  3. Find all parsing functions that accept external byte arrays and convert to integers — overflow in parsing crashes the parser
  4. Check: are there any `unwrap()` calls on arithmetic results from untrusted network data?
  5. For Cosmos SDK: find all `sdk.Int` or `math.Int` operations on IBC/governance data — SDK has its own overflow behavior
  6. Test with fuzzed large integers from network peers — is the node crash reproducible?
- **Failure Mode**: RPC node crashes → network-level DoS; validator crash → consensus failure; attacker sends crafted transactions to crash competing validators; chain halt
- **Common Contexts**: Sui RPC (check_total_coins), Umee oracle ballot, Shardeum P2P, Sei EVM mempool, EigenDA (BitmapToQuorumIds), Advanced Blockchain Substrate (force_unreserve weight)
