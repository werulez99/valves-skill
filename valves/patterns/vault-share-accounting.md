# Vault Share Accounting Patterns
> Extracted from 993 findings (500 sampled)
> Pattern count: 28

---

## VAULT-001: first_depositor_inflation_attack

- **Frequency**: ~95/500 findings
- **Severity**: HIGH
- **Code Shape**: `totalSupply() == 0` check absent before `convertToShares()` or `mulDiv(assets, totalSupply, totalAssets)`; no `MINIMUM_LIQUIDITY` constant burned; no virtual shares offset (`_decimalsOffset`)
- **Detection Heuristic**:
  1. Find the `deposit()` / `mint()` function and locate the shares-calculation expression.
  2. Check whether `totalSupply == 0` produces `shares = assets` (1:1 first mint) while `totalAssets` can be independently inflated.
  3. Confirm the vault uses `balanceOf(address(this))` or `totalAssets()` reading actual token balance without a virtual offset.
  4. Check whether the protocol burns a `MINIMUM_LIQUIDITY` amount (e.g., `1000`) to address(dead) on first deposit.
  5. Check whether OpenZeppelin's `_decimalsOffset()` virtual shares mitigation (10**offset added to denominator) is present.
  6. If none of the above mitigations exist → CONFIRMED. Calculate attack cost: attacker deposits 1 wei, donates N assets, next victim loses `N * victimDeposit / (N + 1)` assets.
- **Failure Mode**: Attacker deposits 1 wei first (gets 1 share), then donates large amount of underlying directly to vault. Next depositor's share calculation rounds down to 0 (or a drastically reduced amount), attacker redeems 1 share for near-total vault assets.
- **Common Contexts**: ERC4626 vaults, liquid staking (ggAVAX, stETH wrappers, rsETH), insurance funds, LP token systems, lending markets (Compound forks, cToken minting), backstop pools, AMM liquidity provision

---

## VAULT-002: donation_attack_balance_of_dependency

- **Frequency**: ~38/500 findings
- **Severity**: HIGH
- **Code Shape**: `totalAssets()` returns `IERC20(asset).balanceOf(address(this))` or `aToken.balanceOf(address(this))` without internal accounting; no `_totalAssets` storage variable tracking actual deposits separately from arbitrary transfers
- **Detection Heuristic**:
  1. Find `totalAssets()` implementation — does it call `token.balanceOf(address(this))` directly?
  2. Confirm there is no separate internal accounting variable (e.g., `_totalDeposited`, `virtualReserves`) that tracks actual deposited amounts independently.
  3. Verify that an external actor can call `token.transfer(vault, X)` to increase `totalAssets()` without minting shares.
  4. Trace effect on `convertToShares()` / `convertToAssets()`: does a donation change the exchange rate mid-block?
  5. Check if any function re-reads `balanceOf` after a user action that already changed it (enabling within-transaction manipulation).
  6. Confirm whether the vault is currently empty (totalSupply == 0), making share price fully controllable by a donation.
- **Failure Mode**: Direct token transfer to vault (not via deposit) inflates `totalAssets` without minting shares, raising the share price and either (a) zeroing out the next depositor's shares via rounding or (b) allowing the attacker to inflate their own position by depositing before the donation is noticed.
- **Common Contexts**: ERC4626 vaults, Aave/Compound adapter vaults (using aToken.balanceOf), AMM vaults, staking reward vaults, UniV3 tokenized LPs

---

## VAULT-003: rounding_direction_violation_erc4626

- **Frequency**: ~22/500 findings
- **Severity**: MEDIUM
- **Code Shape**: `previewWithdraw()` or `previewRedeem()` using `mulDiv(assets, totalSupply, totalAssets)` (round down) instead of `mulDiv(assets, totalSupply, totalAssets, CEIL)`; `previewMint()` rounding down when it should round up
- **Detection Heuristic**:
  1. Locate `previewWithdraw()`, `previewRedeem()`, `previewMint()`, `previewDeposit()` functions.
  2. Apply EIP-4626 rounding rules: `deposit`/`mint` → round DOWN shares minted (favor vault); `withdraw`/`redeem` → round UP shares burned (favor vault). Equivalently: functions that give assets to user round UP required shares; functions that give shares to user round DOWN shares received.
  3. Check each `mulDiv` call: does it use `Math.Rounding.Up` / `Math.Rounding.Ceil` or `ROUND_UP` where the rule requires it?
  4. Identify if `previewWithdraw` rounds DOWN (wrong: user gets more than entitled).
  5. Check whether `mint()` uses `previewMint()` result directly or re-computes — inconsistency between preview and actual creates arbitrage.
  6. Flag any division-before-multiplication pattern that loses precision systematically in user's favor.
- **Failure Mode**: Incorrect rounding allows users to withdraw slightly more than entitled per operation; in high-frequency or large-volume scenarios this drains the vault incrementally. Also enables `mint()` reverts when `previewMint` under-estimates required assets.
- **Common Contexts**: ERC4626 standard implementations, lending vaults, PoolTogether prize vaults, Astrolab strategy vaults

---

## VAULT-004: stale_share_price_in_async_withdraw

- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `initiateWithdrawal()` stores `sharesToBurn` based on current share price, then `completeWithdrawal()` uses stored value without re-checking current price; or vice versa — assets locked at old rate but settled at new rate
- **Detection Heuristic**:
  1. Identify two-step withdrawal patterns: `requestWithdraw()`/`initiateWithdraw()` → `completeWithdraw()`/`fulfillRedeem()`.
  2. Check what is stored at request time: (a) share amount, (b) asset amount, or (c) share price.
  3. If asset amount is stored at request time but shares are burned at fulfillment time at current price → share price increase between steps means user burns more shares than expected.
  4. If shares are stored at request time and redeemed at fulfillment price → share price decrease means user receives fewer assets.
  5. Check whether the `processingMode` (manual vs. queue) bypasses the stored price and uses `currentPrice` directly.
  6. Verify if pending withdrawal tokens are double-counted in `totalAssets()` during the interim period.
- **Failure Mode**: Users locked into a withdrawal at a favorable price can lose value if price moves against them between request and fulfillment. Conversely, users initiating early get better rates than current holders. Also enables sandwich attacks around share price change events.
- **Common Contexts**: ERC4626 async redemption vaults, restaking protocols (EigenLayer, Karak, Rio), liquid staking with unbonding periods, cross-chain vault bridges

---

## VAULT-005: totalassets_excludes_in_transit_or_deployed_funds

- **Frequency**: ~20/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `totalAssets()` only reads local token balance (`balanceOf(address(this))`), ignoring funds sent to strategies, bridged cross-chain, or in pending withdrawal queues; or `tvl()` function missing `inFlight` USDC
- **Detection Heuristic**:
  1. Find `totalAssets()` implementation.
  2. List ALL places where vault assets can go: (a) deployed to external strategies, (b) bridged to L2/L1, (c) in pending redemption queues, (d) in transit via async bridges.
  3. For each destination, check whether the corresponding value is added back to `totalAssets()`.
  4. Check whether `requestRedeem()` / `requestWithdraw()` deducts pending withdrawal from `totalAssets` (to avoid double-counting assets that are logically already owed to withdrawers).
  5. Verify the `totalAssets()` accounts for slippage-adjusted values if deployed to yield strategies.
  6. Flag if `totalAssets()` double-counts: e.g., counting both the strategy position and the tokens returned from strategy in the same block.
- **Failure Mode**: Share price appears higher than reality (counting deployed assets that are no longer fully accessible), enabling depositors to mint more shares than warranted. Or share price appears lower, allowing redeeming depositors to extract proportionally more underlying.
- **Common Contexts**: Multi-strategy ERC4626 vaults, cross-chain vaults (EVM↔L1 bridging), liquid staking with validator queues, restaking protocols with withdrawal delays

---

## VAULT-006: fee_on_transfer_token_accounting_break

- **Frequency**: ~14/500 findings
- **Severity**: MEDIUM/HIGH
- **Code Shape**: `deposit(amount)` → `safeTransferFrom(user, vault, amount)` → `_mint(user, shares_based_on_amount)` where `amount` is pre-transfer value but actual received is `amount - fee`; no balance-delta check
- **Detection Heuristic**:
  1. Identify the token type accepted by the vault — is it a known fee-on-transfer token (USDT in fee mode, PAXG, etc.) or does the vault claim to support any ERC20?
  2. In `deposit()`, check if shares are minted based on the `amount` parameter or based on the actual balance delta (`balanceAfter - balanceBefore`).
  3. If `amount` is used directly without a balance-delta measurement → vault over-mints shares relative to received assets.
  4. Check `withdraw()` / `redeem()` symmetrically: if assets sent out suffer a fee, user receives less than `assets` computed from shares.
  5. Look for any documentation claiming fee-on-transfer support without corresponding balance-delta logic.
  6. Confirm whether `totalAssets()` can drift from actual balance over time due to cumulative fee leakage.
- **Failure Mode**: Each deposit over-mints shares (vault records more assets than received), diluting existing shareholders. Accumulated drift eventually makes the vault insolvent — later redeemers cannot withdraw their full entitled share.
- **Common Contexts**: Generic ERC4626 vaults claiming multi-token support, Superform meta-vaults, Astrolab strategy vaults, Beedle lending

---

## VAULT-007: rebasing_token_share_price_manipulation

- **Frequency**: ~16/500 findings
- **Severity**: HIGH
- **Code Shape**: Vault holds rebasing tokens (stETH, AMPL) and `totalAssets()` = `stETH.balanceOf(address(this))`; rebase events silently change totalAssets without any mint/burn of shares; or negative rebase (slashing) not handled
- **Detection Heuristic**:
  1. Identify whether the vault underlying is a rebasing token (stETH, wstETH wrapper exposing raw stETH balance, AMPL, aTokens).
  2. Check if `totalAssets()` reads raw rebasing balance vs. a normalized (wrapped) form.
  3. For positive rebase: does yield accrue proportionally to all shareholders automatically? Or does it create an exploitable window?
  4. For negative rebase (slashing): does the `rebase()` function handle share price reduction? Look for `rebase()` that only applies upward APR without a slashing floor.
  5. Check if the deposit/withdraw flow uses the pre-rebase or post-rebase price when a rebase occurs in the same block.
  6. Verify whether `rebase()` applies APR as a multiplier to total supply (wrong) vs. to price-per-share (correct).
- **Failure Mode**: Positive rebases create JIT deposit opportunities (deposit before rebase, redeem after, capturing yield without duration exposure). Negative rebases (slashing) are ignored — vault becomes insolvent as share price doesn't reflect the loss. Wrong APR formula in `rebase()` compounds incorrectly.
- **Common Contexts**: Liquid staking (Rivus, Kelp DAO, Puffer Finance, ynETH), stETH wrapper vaults, EigenLayer restaking, Lido integration vaults

---

## VAULT-008: decimal_scaling_mismatch

- **Frequency**: ~18/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `convertToShares(assets)` using `mulDiv(assets, totalSupply, totalAssets)` where asset decimals ≠ share decimals (e.g., USDC 6 decimals vs. 18-decimal shares); or `_decimalsOffset()` computed dynamically as `18 - asset.decimals()` leading to weak inflation protection
- **Detection Heuristic**:
  1. Read `asset.decimals()` and `decimals()` (share token). If they differ, flag for scaling audit.
  2. Check every `mulDiv` in `convertToShares`, `convertToAssets`, fee calculations, reward calculations for unscaled operands.
  3. Verify `_decimalsOffset` in ERC4626 implementations: if it's `18 - asset.decimals()`, a 6-decimal asset gets offset=12 (strong protection); a 18-decimal asset gets offset=0 (no protection). Is this intentional?
  4. Check reward/fee formulas that divide by `1e18` when the underlying variable is denominated in `1e6`.
  5. Look for hardcoded `1e18` denominators where the actual asset uses different precision.
  6. Verify decimal normalization in `computeNAV()` or equivalent valuation functions that sum positions across tokens with different decimals.
- **Failure Mode**: Share minting gives dramatically wrong amounts (10^12 too many or too few shares) for non-18-decimal assets. Fee calculations overcharge or undercharge by orders of magnitude. NAV computations are wrong, leading to unfair deposit/withdrawal rates.
- **Common Contexts**: ERC4626 vaults with USDC/USDT (6 decimal) underlying, multi-asset vaults, hToken/wrapped token systems, BakerFi strategy vaults, Maia DAO, Royco ERC4626i

---

## VAULT-009: high_watermark_and_performance_fee_accounting_error

- **Frequency**: ~15/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `highWaterMark` updated on every `deposit()`/`withdraw()`/`mint()` instead of only on `harvest()`; or performance fee calculated on gross assets including principal (not just yield above watermark); or `lastHarvestManagementFeeTime` initialized to `block.timestamp` at deployment rather than zero
- **Detection Heuristic**:
  1. Locate the high watermark variable and the events that update it.
  2. Check if `highWaterMark` is updated inside `deposit()`, `withdraw()`, or `mint()` — if so, each user action resets the watermark, eliminating performance fee accrual.
  3. Find the performance fee formula: is it `(currentNAV - highWaterMark) * feeRate` (correct) or `currentNAV * feeRate` (charges fee on principal)?
  4. Check `lastHarvestManagementFeeTime` initialization: if set to `block.timestamp` at contract deploy, the first harvest charges a full period of management fee retroactively from time 0.
  5. Verify fee recipient: does `_mint(feeRecipient, feeShares)` correctly increase total supply, diluting all shareholders proportionally?
  6. Check that fee shares are not double-counted in `totalAssets()`.
- **Failure Mode**: Watermark reset on each deposit causes protocol to never charge performance fees (revenue loss). Fee on principal causes users to pay fees on their own capital. Incorrect initialization causes first-harvest overcharge. Fee misrouted to vault contract instead of recipient.
- **Common Contexts**: Yearn-style strategy vaults, Popcorn vaults, multi-strategy ERC4626, Harmonixfinance fund contracts

---

## VAULT-010: missing_slippage_protection_on_vault_entry_exit

- **Frequency**: ~20/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `deposit(assets)` or `redeem(shares)` with no `minSharesOut` / `minAssetsOut` parameter; or parameter exists but is not validated against actual output; `addLiquidity()` depositing into ERC4626 vault without slippage check on shares received
- **Detection Heuristic**:
  1. Inspect `deposit()`, `mint()`, `withdraw()`, `redeem()` function signatures — do they accept min/max bounds parameters?
  2. If bounds parameters exist, verify they are checked: `require(sharesOut >= minShares, "slippage")`.
  3. Check for cases where slippage parameter is accepted but compared against wrong value (e.g., `minShares` compared to `assets` not `shares`).
  4. Identify multi-step operations (e.g., swap → deposit, or deposit → add liquidity) where slippage is checked on the outer operation but not on the inner ERC4626 vault deposit.
  5. Check ERC4626 `maxDeposit()` / `maxWithdraw()` / `maxMint()` / `maxRedeem()` — if they return `type(uint256).max` or incorrect values, the EIP4626 standard is violated and integrators cannot safely guard against slippage.
  6. Flag if `rebalance()` or `harvest()` operations interact with external vaults without slippage protection.
- **Failure Mode**: Sandwich attacks extract value from depositors/withdrawers by manipulating share price between tx submission and execution. In cross-protocol interactions, share price changes in the underlying vault cause users to receive significantly fewer shares or assets than expected.
- **Common Contexts**: ERC4626 vault routers, meta-vaults (Superform, Morpho Meta-Morpho), AMM-adjacent vaults (Bunni, Arrakis), rebalancing managers, LoopFi AuraVault

---

## VAULT-011: erc4626_standard_noncompliance

- **Frequency**: ~16/500 findings
- **Severity**: MEDIUM
- **Code Shape**: `maxWithdraw()` reverts instead of returning 0 on error; `maxDeposit()` returns `type(uint256).max` ignoring actual capacity constraints; `previewRedeem()` / `previewWithdraw()` return values inconsistent with actual `redeem()` / `withdraw()` outputs; `Tranche::redeem` calling `super.withdraw` instead of `super.redeem`
- **Detection Heuristic**:
  1. For each ERC4626 view function (`maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem`, `previewDeposit`, `previewMint`, `previewWithdraw`, `previewRedeem`), check EIP-4626 invariants.
  2. `maxWithdraw` / `maxRedeem` MUST NOT revert — check for any revert paths (division by zero when totalSupply=0, external call failures).
  3. `previewDeposit(X)` must return the same value as the actual `deposit(X)` in the same block (no slippage model).
  4. `previewWithdraw(X)` must return the minimum shares needed to withdraw X assets — verify rounding direction.
  5. Check if `deposit()` and `mint()` have different behavior on first deposit (ERC4626Cloned bug).
  6. Verify `convertToShares()` and `convertToAssets()` are inverses of each other within rounding.
- **Failure Mode**: Integrators (aggregators, routers, liquidators) relying on standard view functions receive incorrect data, leading to wrong share calculations, failed transactions, or fund loss when the view-to-execution gap is exploitable.
- **Common Contexts**: Custom ERC4626 implementations (Revert Lend, Y2K Finance, Astaria, Opus, PoolTogether, Isle Finance), vaults inheriting incorrectly from base contracts

---

## VAULT-012: reward_accumulator_precision_loss

- **Frequency**: ~20/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `accRewardPerShare += reward * PRECISION / totalShares` where `totalShares` is very large, causing `reward * PRECISION < totalShares` → zero addition; or `rewardPerTokenStored` computed with insufficient precision when `totalSupply` is large; or `lastUpdateBlock` updated incorrectly
- **Detection Heuristic**:
  1. Find the reward-per-share accumulation formula: `accRewardPerShare += rewardDelta * PRECISION / totalSupply`.
  2. Check `PRECISION` constant — is it `1e12`, `1e18`, or `1e36`? Larger totalSupply requires larger precision multiplier.
  3. Simulate: if `totalSupply = 1e24` and `PRECISION = 1e12`, then `reward * 1e12 / 1e24 = reward / 1e12` → loses all precision for reward < 1e12.
  4. Look for division before multiplication: `(reward / totalSupply) * userBalance` instead of `reward * userBalance / totalSupply`.
  5. Check `lastUpdateBlock` update timing — if updated before computing the reward for the current block, rewards for that block are lost.
  6. Verify the `accPnlPerToken` scaling in PnL settlement functions — does it match the expected precision used downstream?
- **Failure Mode**: Users lose rewards to rounding, proportional to `totalSupply / PRECISION`. In extreme cases (large totalSupply, small PRECISION), 100% of rewards round to zero and are permanently lost. Also enables DoS by accumulating a single large stake.
- **Common Contexts**: MasterChef-style reward distributors, gauge systems, staking rewards (Biconomy, Derby, Tokemak, Ostium), farming contracts, liquid staking reward accounting

---

## VAULT-013: share_transfer_breaks_per_user_accounting

- **Frequency**: ~12/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: Per-user state variables (e.g., `depositedAmount[user]`, `userCostBasis[user]`, `totalDeposit[addr]`) are tracked at deposit time and not updated on ERC20 share token transfer; reward index snapshots tied to depositor address not following the share
- **Detection Heuristic**:
  1. Identify all per-user accounting variables that are set in `deposit()` / `mint()` (e.g., `depositTimestamp`, `userDeposited`, `rewardDebt`, `costBasis`).
  2. Check whether the vault's share token is a standard ERC20 (transferable).
  3. If shares are transferable, look for overrides of `_beforeTokenTransfer()` / `_afterTokenTransfer()` that update per-user accounting on transfer.
  4. If no transfer hook updates per-user variables → transferring shares to a new address breaks accounting for both sender and receiver.
  5. Check if `withdraw()` uses `userDeposit[msg.sender]` which is stale after transfer.
  6. Verify deposit cap enforcement: `totalDepositedAmountPerUser[user]` increased on deposit but not decreased on withdrawal — enables cap bypass by depositing, withdrawing, and depositing again.
- **Failure Mode**: Share holder after transfer cannot withdraw or receives wrong amounts. Sender retains inflated accounting values enabling double-withdrawal. Per-address deposit caps are bypassable. Reward calculations for transferred shares are corrupted.
- **Common Contexts**: NativeVault (Karak), staked tokens with per-user state, deposit-capped protocols (zkSync bridge), ERC20 shares in DeFi positions, SuperVault share transfer exploits

---

## VAULT-014: first_depositor_rewards_permanently_lost

- **Frequency**: ~12/500 findings
- **Severity**: MEDIUM
- **Code Shape**: `if (totalSupply == 0) return` in reward distribution function; `rewardPerToken()` skips update when `_totalSupply == 0`; rewards sent to gauge/pool before any LP deposits accumulate with no claim mechanism
- **Detection Heuristic**:
  1. Find reward distribution functions — check for `if (totalShares == 0) { return; }` guard.
  2. Trace what happens to rewards that arrive when `totalShares == 0`: are they pushed to a buffer, added to `pendingRewards`, or silently discarded?
  3. Check if `_rewardPerTokenStored` is updated before the zero-totalSupply guard — if not updated, rewards distributed during the zero-supply period are lost forever.
  4. Look for scenarios where totalSupply transitions from nonzero to zero and back (all stakers exit then new staker enters) — rewards distributed during the zero-supply window are lost.
  5. Verify `LiquidityGauge.totalSupply == 0` handling in gauge reward loops.
  6. Check staking rewards initialization: is `rewardPerTokenStored` set to current accrued value before the first deposit arrives?
- **Failure Mode**: All rewards distributed to a pool/gauge during the period when `totalSupply == 0` are permanently locked and unclaimable by any future depositor. Protocols lose reward budget silently.
- **Common Contexts**: Liquidity gauges (Curve-style), staking reward contracts, Velocimeter gauges, LiquidityGauge with zero-supply periods, farming contracts before first LP

---

## VAULT-015: rebase_function_incorrect_apr_application

- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `rebase()` sets `totalShares = totalShares * (1 + dailyAPR)` (modifying supply, not price) instead of `pricePerShare = pricePerShare * (1 + dailyAPR)`; or applies `APR` in basis points as if it's a daily rate when it's an annual rate
- **Detection Heuristic**:
  1. Find `rebase()` or `applyAPR()` function.
  2. Check what variable is modified: `totalShares`? `pricePerShare`? `totalAssets`?
  3. If modifying `totalShares` upward while supply stays constant → users receive more shares but price stays same (dilution, not yield).
  4. Check APR unit: is `APR` in basis points (10000 = 100%)? Divided by `365` for daily? Divided by `86400` for per-second?
  5. Verify the rebasing formula handles slashing: can `rebase()` be called with a negative delta? If only positive APR handled → vault becomes insolvent after slashing events.
  6. Check `rebase()` access control — can any user trigger it, enabling griefing?
- **Failure Mode**: Wrong APR application either inflates shares (distributes imaginary yield) or applies the wrong multiplier (e.g., 86400x discounted issuance when `currentMultiplier` is miscalculated). Slashing events ignored cause vault insolvency.
- **Common Contexts**: Rebasing token vaults (Rivus stTAO, RivusTAO), liquid staking protocols, Alongside AMKT, yield token wrappers

---

## VAULT-016: sandwich_attack_on_share_price_update

- **Frequency**: ~14/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `harvest()` / `earn()` / oracle update increases `totalAssets` atomically and in a publicly observable transaction; no surge fee or anti-sandwich delay; MEV bot can deposit just before and redeem just after the yield-accrual transaction
- **Detection Heuristic**:
  1. Identify events that cause discrete share price jumps: `harvest()`, `earn()`, oracle price updates, cross-chain yield settlements, checkpoint functions.
  2. Check if these events are publicly callable (permissionless) or predictably timed.
  3. Verify whether deposits and withdrawals in the same block as the yield event are allowed.
  4. Look for surge fee mechanisms that temporarily increase withdrawal costs after large share price increases — if absent or bypassable (e.g., via withdrawal queue pre-enqueuing), sandwich is possible.
  5. Check if Pyth/Chainlink price updates can be used with two different prices in the same transaction to bracket the vault's state.
  6. Verify withdrawal delay / cooldown: can users queue withdrawal before the yield event and claim after?
- **Failure Mode**: JIT depositors capture disproportionate yield without providing capital during the risk period. Systematic extraction drains yield from long-term depositors. Pyth two-price attack allows extracting LP pool value.
- **Common Contexts**: Yield harvesting vaults, Hyperdrive checkpoint system, Perpetual finance LP pools, Bunni surge fee mechanism, Ostium PnL epoch settlement, AFI Vault oracle updates

---

## VAULT-017: incomplete_state_update_on_vault_operations

- **Frequency**: ~22/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `liquidatePosition()` updates collateral but forgets to update `vaultDebt`; `scaleVariables()` scales some but not all related variables (e.g., `accPnlPerToken` missed); `removeToken()` breaks vault accounting; `earnResults` decreasing share price; inconsistent `totalAssets` during deposit/withdraw
- **Detection Heuristic**:
  1. List all state variables that must remain consistent with each other (e.g., `totalShares`, `totalAssets`, `vaultDebt`, `vaultCollateral`, `accPnlPerToken`, `lastUpdateTimestamp`).
  2. For each vault operation (deposit, withdraw, liquidate, rebalance, claim), enumerate which state variables it modifies.
  3. Check for missing updates: does `liquidate()` update both collateral AND debt? Does `earn()` correctly update share price?
  4. Look for `scaleVariables()` functions — enumerate all variables that need scaling and verify each one is included.
  5. Check async withdrawal patterns: does `requestRedeem()` immediately update `totalAssets` to reflect the earmarked assets?
  6. Verify `removeToken()` in multi-asset vaults: does removing an asset correctly zero out its contribution to share price?
- **Failure Mode**: Inconsistent state between related variables leads to incorrect share price, allowing over-minting or under-burning of shares. Liquidated positions leave phantom debt. Scaling functions that miss variables produce permanently corrupted accounting.
- **Common Contexts**: Multi-strategy vaults (yAxis), PnL settlement vaults (Ostium, Part2 market-vault), liquidation engines, Karak NativeVault, Maia DAO ecosystem

---

## VAULT-018: reentrancy_in_vault_deposit_withdraw

- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `deposit()` mints shares before transferring tokens (CEI violated); `openShort()` with stETH calls external contract before state update; `redeemNative()` calls external yield strategy mid-execution; missing reentrancy guard on vault entry points
- **Detection Heuristic**:
  1. Check CEI (Checks-Effects-Interactions) order in `deposit()`, `mint()`, `withdraw()`, `redeem()`.
  2. Flag if `_mint(shares)` or state update happens BEFORE `safeTransferFrom(assets)`.
  3. Identify external calls within vault entry points: token transfers, oracle reads, strategy calls, stETH interactions.
  4. Check for reentrancy guards (`nonReentrant` modifier or equivalent) on all state-changing vault functions.
  5. Verify cross-function reentrancy: does `withdraw()` guard against reentrant `deposit()` calls?
  6. For native ETH vaults: check if `receive()` / `fallback()` can be exploited to reenter the vault mid-operation.
- **Failure Mode**: Attacker calls vault function, which calls external contract, which calls back into vault before state is updated. Results in double-minting shares, double-withdrawal of assets, or corrupted accounting (NativeVault state corruption, permanent fund freeze).
- **Common Contexts**: ERC4626 with ERC777 underlying, stETH-based hyperdrive, yield strategy vaults calling external protocols, PoolTogether Yearn integration

---

## VAULT-019: incorrect_shares_arithmetic_in_complex_flows

- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `redeem(convertToShares(collateralAmountIn))` where `convertToShares` is called redundantly on already-share-denominated input; `burnSharesToWithdrawEarnings` burns before computing math causing share price to artificially increase; `addPrincipalToCommitmentGroup` using wrong share formula
- **Detection Heuristic**:
  1. Trace the full data flow from user input to share mint/burn: identify whether each intermediate value is in asset units or share units.
  2. Look for double-conversion bugs: `convertToShares(convertToShares(x))` or `convertToAssets(convertToAssets(x))`.
  3. Verify the order of burn vs. math: in `burnAndWithdraw()`, are shares burned before or after computing the asset amount? Burning first changes the exchange rate used for the withdrawal calculation.
  4. Check `assets deposited before shares calculated` pattern: if deposit is received before `totalAssets()` snapshot, the new depositor's own assets inflate the denominator, minting fewer shares than entitled.
  5. In multicall/batch operations, verify each sub-operation sees a consistent state.
  6. Check router contracts passing wrong parameters (wrong owner, wrong amount) to underlying vault functions.
- **Failure Mode**: Users receive systematically fewer/more shares than entitled. Early depositors of a strategy can have all their liquidity sent to a vault manager. Share burndown incorrectly inflates share price, harming remaining holders.
- **Common Contexts**: Complex redemption flows (Tapioca DAO, Asymmetry Finance, Swivel), commitment group vaults (Teller Finance), tokenized LP vaults, YToken withdrawal flows (YieldFi)

---

## VAULT-020: emergency_withdrawal_and_migration_vulnerability

- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `emergencyWithdraw()` does not prevent subsequent `deposit()` calls; migration from old vault to new vault allows front-running (deposit just before migration snapshot, receive proportional share of both pools); migration doesn't transfer underlying assets
- **Detection Heuristic**:
  1. Find `emergencyWithdraw()` or `pauseDeposits()` functions — check if they set a flag preventing future deposits.
  2. In migration scenarios: identify the snapshot point (block, timestamp) and check if it's publicly known in advance.
  3. Verify if deposits between the migration announcement and execution are treated fairly vs. legacy depositors.
  4. Check `rescue()` / `migrate()` functions: do they transfer the actual underlying tokens to the new contract?
  5. Look for state carried forward during migration: is `pricePerShare` / `totalAssets` correctly initialized in the new contract?
  6. Verify access control on migration functions — can anyone trigger a migration to a malicious contract?
- **Failure Mode**: Emergency withdrawal allows users to re-deposit and re-withdraw multiple times (mass withdrawal fails). Migration front-running allows an attacker to deposit just before the snapshot and receive proportional claim on both the old pool's assets and new pool incentives.
- **Common Contexts**: Gro Protocol GSquared, Tapioca DAO emergency mechanics, Persistence liquid stake, Balmy strategy migration, Morpho Vaults v2

---

## VAULT-021: cross_vault_misattribution_and_double_counting

- **Frequency**: ~8/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `OmoVault.totalAssets()` counting assets from multiple vaults without deduplication; `computeNAV()` including underlying token position counted from both vault and pool; `totalAssets_deposited` tracking pre-slippage values; `directDepositIntoVault` incorrectly treated as revenue
- **Detection Heuristic**:
  1. In multi-vault aggregator contracts, trace how `totalAssets()` sums up contributions from sub-vaults.
  2. Verify there is no overlap: if sub-vault A holds token X and sub-vault B also holds token X as underlying, is X counted once or twice?
  3. Check NAV computation functions — enumerate all asset sources and verify each is counted exactly once.
  4. For meta-vaults receiving direct deposits (not through standard entry points), check if the deposit is classified as yield/revenue or as a liability (new shares needed).
  5. Verify `_harvestAndReport()` does not include underlying assets in yield calculation when they are simply returned capital.
  6. Check cross-vault share tracking: does `PublicAllocator` track shares consistently with `EulerEarn` to avoid allocation mismatches?
- **Failure Mode**: NAV is systematically overstated, allowing vault shares to be minted at incorrect rates. Direct deposits classified as revenue inflate share price, draining other depositors' principal. Cross-vault inconsistency causes reallocation operations to fail or send wrong amounts.
- **Common Contexts**: OmoVault multi-agent system, Panoptic vault NAV, Alchemix transmuter harvest, EulerEarn with PublicAllocator, Tenbin collateral manager

---

## VAULT-022: access_control_bypass_on_restricted_vault_actions

- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `FULL_RESTRICTED_STAKER_ROLE` check missing in `deposit()` but present in `mint()`; `StakedToken` restriction bypassable via ERC20 `approve` + third-party `transferFrom`; malicious staking contract deployed by attacker used to drain vault
- **Detection Heuristic**:
  1. Identify restriction flags: `FULL_RESTRICTED`, `KYC_REQUIRED`, `WHITELISTED_ONLY`.
  2. For each restriction, check ALL entry points: `deposit()`, `mint()`, `transfer()`, `transferFrom()`, `approve()` — is the restriction enforced consistently across all paths?
  3. Check if restriction checks use `msg.sender` vs. `from` — if `transferFrom` is called by a non-restricted third party on behalf of a restricted user, is the underlying holder's restriction still enforced?
  4. Verify malicious external contract injection: can an attacker deploy a vault-compatible contract (staking, strategy) and register it to receive legitimate vault deposits?
  5. Check `_verifyCreatorOrOwner()` modifier logic for edge cases where neither condition triggers the revert.
  6. Verify that KYC/NFT ownership checks use `ownerOf()` properly — can a contract that cannot hold NFTs (wrong interface) be used in a vault that requires NFT ownership?
- **Failure Mode**: Restricted users bypass KYC/restriction by using alternative entry points. Malicious staking contracts receive vault funding through legitimate allocation paths. ERC4626KYCDaoForm cannot hold NFT → breaks core flow entirely.
- **Common Contexts**: ManifestFinance restricted staker roles, infiniFi StakedToken, ERC4626KYCDaoForm (Superform), Popcorn vault malicious staking

---

## VAULT-023: initial_deposit_zero_shares_or_wrong_initialization

- **Frequency**: ~14/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `deposit()` not checking `shares == 0` return before minting; `initialize()` function setting wrong initial share price; initial LP deposit impossible due to miscalculation in `_depositNoPull()`; `MIN_INITIAL_DEPOSIT` enforcement bypassable
- **Detection Heuristic**:
  1. Check `deposit()` for a `require(shares > 0)` guard — if absent, a deposit can silently mint 0 shares and lose the assets.
  2. Check `initialize()` / constructor: is the initial share-to-asset ratio explicitly set, and is it set correctly?
  3. Look for `MIN_INITIAL_DEPOSIT` constants: verify they are checked in the deposit flow and not bypassable (e.g., via a path that sets `aegisTotalSupply` before the check).
  4. For AMM-style first liquidity: verify the initial liquidity computation handles the zero-supply case (no division by zero, correct geometric mean initialization).
  5. Check if `deposit()` and `mint()` have different first-deposit behavior — inconsistency indicates incomplete implementation.
  6. Verify `_depositNoPull()` in BaseStrategy: does it correctly handle the case where `totalSupply == 0`?
- **Failure Mode**: First depositor loses all deposited assets (mints 0 shares). Initial share price set incorrectly causes permanent mispricing. `MIN_INITIAL_DEPOSIT` bypass allows attacker to reenter the initialization race window. Initial LP deposit impossible → protocol DOA.
- **Common Contexts**: Hybra Finance GovernanceHYBR, ManifestFinance StakedUSH, Berachain block builders, AegisVault, Core/Strategies BaseStrategy

---

## VAULT-024: pending_withdrawal_totalassets_double_counting

- **Frequency**: ~10/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `requestRedeem()` queues withdrawal but does not reduce `totalAssets()`; both the queued assets AND their backing positions are counted in `totalAssets()` during the interim period; or `pendingWithdrawalTokens` included in share price calculation
- **Detection Heuristic**:
  1. In async redemption vaults, trace `requestRedeem()`: does it immediately earmark assets (reducing `totalAssets`) or only record the request?
  2. Compute `totalAssets()` at time T (after request, before fulfillment): does it include the assets owed to the withdrawer?
  3. If yes → share price is inflated during the pending window, harming new depositors who mint at inflated price.
  4. In `redeem()` for standard vaults: check if `_pendingRedeemAmount` is excluded from the exchange rate calculation.
  5. Verify `requestWithdrawal` in Harmonixfinance: does `initiateWithdrawal()` lock in the share price, and does `completeWithdrawal()` respect that locked price?
  6. For multi-step batch processing: check if `_withdraw()` reserves liquidity correctly for pending and immediate redemptions.
- **Failure Mode**: New depositors during the pending withdrawal window receive fewer shares than entitled (share price inflated by assets already owed to withdrawers). Or the pending redemption can be exploited via sandwich — depositing between request and fulfillment to capture yield that should go to the withdrawer.
- **Common Contexts**: Blueberry HyperEvmVault, Harmonixfinance FundContract, Centrifuge BatchRequestManager, Strata pUSDeVault, Omo_2025

---

## VAULT-025: bad_debt_and_insolvency_from_market_state

- **Frequency**: ~12/500 findings
- **Severity**: MEDIUM/HIGH
- **Code Shape**: `earningsAccumulator` insufficient to cover bad debt in `clearBadDebt()`; slashing event reduces backing assets below total share liabilities; `rebalanceBadDebt()` decreases share price below liquidation threshold; super pool overflows from bad debt
- **Detection Heuristic**:
  1. Identify the protocol's bad debt mechanism: how are undercollateralized positions handled?
  2. Check if losses are socialized (reducing share price for all LPs) or absorbed by a specific buffer (`earningsAccumulator`, insurance fund).
  3. Verify the buffer size: can it absorb realistic bad debt? What happens when it's exhausted?
  4. Check `rebalanceBadDebt()`: does it decrease share price? Can this push the share price below the threshold required for liquidation, creating non-liquidateable positions?
  5. For Lido/EigenLayer integrations: verify that slashing events (sudden balance decrease) are handled — does `totalAssets()` correctly reflect post-slash balance immediately?
  6. Check super pool share overflow: does accumulated bad debt cause arithmetic overflow in share calculations?
- **Failure Mode**: Bad debt exceeds buffer capacity → direct socialized loss to all LPs. Share price drop creates non-liquidateable zombie positions. Slashing event causes immediate insolvency as share price drops below outstanding liability. Super pool overflow enables share inflation.
- **Common Contexts**: Exactly Protocol, Sentiment V2 super pool, Puffer Finance (Lido slashing), Nexus staking (slashing), Pareto USP, Mellow LRTs

---

## VAULT-026: cross_chain_share_accounting_inconsistency

- **Frequency**: ~10/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `inflationMultiplier` on L1 bridge becomes stale after ECO rebase; EVM-to-L1 transfer period exploited to inflate TVL; vault token transferred cross-chain loses original chain accounting; share price on primary chain diverges from secondary chain during round rolls
- **Detection Heuristic**:
  1. Identify all points where vault share price or `totalAssets` information crosses chain boundaries.
  2. Check if the cross-chain message carries a point-in-time snapshot vs. a live query.
  3. Verify `inflationMultiplier` on bridge contracts: is it updated on every rebase, or only manually?
  4. For cross-chain yield vaults: check if withdrawals are restricted to the primary chain after yield accrual — if secondary chain LPs cannot withdraw, it's a DoS.
  5. Verify that ERC20 vault token transfers across chains correctly translate share values at the correct exchange rate on both ends.
  6. Check for TVL inflation during bridge transit: are in-flight tokens counted on both chains simultaneously?
- **Failure Mode**: Stale `inflationMultiplier` causes bridge to credit wrong token amounts. In-flight token double-counting inflates TVL → share price manipulation window. Cross-chain share tokens lose value during transit if exchange rates diverge. Secondary chain depositors permanently locked out.
- **Common Contexts**: ECO L1ECOBridge, Blueberry EVM-to-L1 transfer, Sherpa multi-chain yield vaults, D cross-chain ERC4626, Superform cross-chain deposits

---

## VAULT-027: governance_weight_and_vote_inflation_via_share_manipulation

- **Frequency**: ~8/500 findings
- **Severity**: HIGH/MEDIUM
- **Code Shape**: `moveVotes()` without checking voting status allows vote power inflation; `exitPosition()` in TapiocaOptionBroker removes weight prematurely for large stakes; `computeVote()` contains loop logic error producing wrong currency vote result; `removeBoostDelegation()` leaves boost permanently inflated
- **Detection Heuristic**:
  1. Identify governance weight derived from vault shares (vote weight = shares held).
  2. Check `moveVotes()` / `delegate()` / `transfer()` — do they validate that the sender actually has the voting power being moved?
  3. Look for `exitPosition()` in option broker: does weight removal happen atomically with stake removal, or can timing allow premature weight removal?
  4. In `computeVote()` loops: verify the accumulation logic handles edge cases (zero votes, single voter) correctly.
  5. Check `removeBoostDelegation()`: does it correctly reduce the delegator's boost balance, or only remove the delegation record?
  6. Verify that staked NFT accounting correctly reflects hidden/removed NFTs vs. visible stakes (stETH/EaseDeFi pattern).
- **Failure Mode**: Vote inflation allows governance manipulation with lower economic cost. Premature weight removal inflates remaining weight for existing positions. Permanent boost inflation extracts governance power without corresponding economic stake.
- **Common Contexts**: EYWA voting contracts, TapiocaOptionBroker, Eco Contracts governance, BoostController, stETH/EaseDeFi NFT staking, Vader Protocol weight system

---

## VAULT-028: erc4626_inflation_protection_insufficient_or_misconfigured

- **Frequency**: ~12/500 findings
- **Severity**: MEDIUM/HIGH
- **Code Shape**: `_decimalsOffset()` returns 0 for 18-decimal tokens (no virtual shares protection); `INFLATION_PROTECTION_TIME` hardcoded to a unix timestamp instead of a duration; `decimalOffset` computed dynamically as `18 - asset.decimals()` making protection weaker for tokens with fewer decimals; virtual shares offset present but insufficient against flash-loan-assisted attacks
- **Detection Heuristic**:
  1. Check `_decimalsOffset()` return value: is it a constant (e.g., 6, 9, 18) or dynamically computed from `asset.decimals()`?
  2. If dynamic: `offset = 18 - asset.decimals()` → for 18-decimal tokens, offset=0 → no protection. Flag.
  3. Verify `INFLATION_PROTECTION_TIME`: is it a duration (e.g., `365 days`) or a specific timestamp? If timestamp, it expires and leaves vaults unprotected after that date.
  4. Calculate the minimum cost to perform an inflation attack given the decimal offset: cost ≈ `10^offset` tokens. Is this economically sufficient to deter attackers for the token's value?
  5. Check whether the offset is applied to both numerator AND denominator consistently in all share math functions.
  6. Verify virtual shares are not counted in `totalSupply()` externally (they should be internal accounting only).
- **Failure Mode**: Inflation protection appears to exist but is ineffective for specific token decimals or after a hardcoded timestamp expires. Weak offset (e.g., 6 for a high-value token) requires only $1 to inflate beyond protection. Inconsistent application of virtual shares produces wrong exchange rates.
- **Common Contexts**: ERC4626 implementations with `_decimalsOffset()`, LoopFi (INFLATION_PROTECTION_TIME hardcoded), Yield Basis LiquidityGauge (0 decimals offset), ZeroLend CuratedVaults, f(x) v2 fxSAVE, Bunni-August pools

