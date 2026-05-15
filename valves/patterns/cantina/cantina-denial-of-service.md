# Cantina Denial of Service Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 7
> NOTE: Supplements existing DOS-001..030 from Solodit corpus

---

## CANTINA-DOS-031: unbounded_array_growth_via_user_action
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `array.push(element)` inside user-callable function with no `array.length` cap; `for (uint i = 0; i < array.length; i++)` in withdrawal/unstake path
- **Detection Heuristic**:
  1. Identify storage arrays that grow via user-triggered calls (stake, lock, deposit, queue)
  2. Check whether any length cap or garbage-collection mechanism exists for that array
  3. Trace all iteration loops over the same array (withdraw, claim, unstake, getReward)
  4. Confirm an attacker can cheaply push entries (dust deposits, micro-locks) to inflate length
  5. Verify the iteration path has no early-exit or pagination and will hit block gas limit
- **Failure Mode**: Attacker floods a per-user or global array with dust entries. Subsequent operations that iterate the full array (unstake, withdraw, claim) revert with OutOfGas. Victim funds are permanently locked.
- **Common Contexts**: Staking lock arrays, withdrawal request queues, reward distribution loops, validator sets, order book entries

---

## CANTINA-DOS-032: zero_balance_rebalance_revert
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `uint256 balance = token.balanceOf(address(this)); require(balance > 0)` or `amount = balance * share / totalShares` where balance can be zero; rebalance/unstake path that divides by or requires nonzero contract balance
- **Detection Heuristic**:
  1. Find internal rebalance, redistribute, or reallocation functions called during unstake/withdraw
  2. Check if they read contract's own token balance and use it as a divisor or require it nonzero
  3. Determine if a preceding operation (withdrawal, emergency action, strategy loss) can drain the balance to zero
  4. Confirm the rebalance call is not guarded by a balance-check bypass
- **Failure Mode**: A prior withdrawal or strategy loss drains the contract balance to zero. Subsequent unstake/withdraw calls invoke rebalance, which reverts on zero-balance division or require. All queued withdrawals are permanently blocked.
- **Common Contexts**: Vault rebalancing, strategy allocation, liquid staking rebalance on unstake, yield aggregator harvest paths

---

## CANTINA-DOS-033: cooldown_extension_on_new_action
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `cooldownEnd = block.timestamp + COOLDOWN_PERIOD` inside unstake/requestWithdraw without per-request tracking; single `withdrawableAfter` timestamp for all queued amounts
- **Detection Heuristic**:
  1. Identify cooldown or timelock mechanisms for withdrawals/unstaking
  2. Check whether the cooldown timestamp is per-request or a single global/per-user value
  3. Confirm that initiating a new unstake/withdraw request resets the cooldown for ALL pending requests
  4. Verify an attacker (or the user themselves via repeated small unstakes) can perpetually extend the cooldown
- **Failure Mode**: Each new unstake request resets a shared cooldown timer. An attacker (or griefing user) repeatedly submits dust unstake requests, pushing the cooldown deadline forward indefinitely. Previously queued withdrawals never become claimable.
- **Common Contexts**: Liquid staking cooldowns, governance unlock periods, vesting cliff resets, withdrawal queue timers

---

## CANTINA-DOS-034: hardcoded_bound_blocks_operation
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `require(value >= MIN_BOUND && value <= MAX_BOUND)` where MIN_BOUND/MAX_BOUND are immutable constants; `require(sharePrice >= minSharePrice)` with hardcoded minSharePrice
- **Detection Heuristic**:
  1. Find hardcoded minimum or maximum bounds used in require/assert on dynamic values (share price, exchange rate, utilization ratio)
  2. Determine if the bounded value can legitimately move outside the hardcoded range under normal market conditions (depeg, slashing, high utilization)
  3. Confirm no governance or admin mechanism exists to update the bounds
  4. Verify that breaching the bound blocks a critical path (deposit, withdraw, mint, redeem)
- **Failure Mode**: A hardcoded price/rate bound is set for "normal" conditions. Market stress (depeg, slashing event, extreme utilization) pushes the dynamic value outside the bound. Core operations (deposit, withdraw, stake, unstake) revert. Protocol is frozen until market recovers -- if it ever does.
- **Common Contexts**: Share price sanity checks, utilization caps without graceful degradation, oracle price floor/ceiling, collateral ratio bounds

---

## CANTINA-DOS-035: accounting_overflow_blocks_operations
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `totalX += amount` then later `require(totalX >= subtracted)` or `totalX -= subtracted` where totalX can become inconsistent; `totalDebt` incremented on deposit but not decremented symmetrically on burn/repay
- **Detection Heuristic**:
  1. Identify global accounting accumulators (totalDebt, totalLocked, totalSupply, totalBorrowed)
  2. Trace all increment sites and all decrement sites for each accumulator
  3. Check for asymmetry: can increments exceed the logical cap, or can decrements attempt to subtract more than the current value
  4. Confirm the accumulator is used in a require or subtraction on a critical path (claim, redeem, repay, withdraw)
  5. Verify no overflow/underflow guard gracefully handles the edge case
- **Failure Mode**: An accounting variable drifts from its expected relationship (increment > total, or decrement underflows). Subsequent operations that rely on the accumulator revert on underflow or fail a require check. Functions like claim, redeem, or repay become permanently blocked.
- **Common Contexts**: Debt tracking (totalDebt vs per-user debt), locked amount accounting, redemption state machines, collateral trackers with multiple modification paths

---

## CANTINA-DOS-036: direct_transfer_inflates_accounting
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `uint256 assets = token.balanceOf(address(this))` used in share calculation; `totalAssets()` reads live balance rather than internal accounting; deposit path uses `balanceOf` delta as deposited amount
- **Detection Heuristic**:
  1. Find functions that compute shares, rates, or limits using `balanceOf(address(this))` or equivalent live balance reads
  2. Check if any path allows tokens to enter the contract without updating internal accounting (direct transfer, selfdestruct, rebasing token)
  3. Confirm the inflated balance causes a critical function to revert (division by zero on zero shares, exceeding a max deposit cap, breaking a require on expected ratios)
  4. Verify no donation-guard or dead-share mechanism neutralizes the attack
- **Failure Mode**: Attacker sends tokens directly to the contract (or triggers a rebase). Functions that use `balanceOf` for accounting now see an inflated value. This can exceed caps (DoSing deposits), distort share pricing (DoSing withdrawals due to rounding), or create impossible require conditions. Alternatively, deposit/withdraw cycling inflates internal totals vs actual balance.
- **Common Contexts**: ERC4626 vaults, lending pool deposit caps, transmuter locked totals, any protocol reading own balance for accounting decisions

---

## CANTINA-DOS-037: removal_or_pause_blocks_dependent_operations
- **Frequency**: ~4/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `require(!paused)` in liquidation/repay path; pool removal from orderbook without migrating open positions; `require(pool.isActive())` in time-critical operations
- **Detection Heuristic**:
  1. Identify admin actions that disable, remove, or pause a component (pool removal, market pause, strategy deactivation)
  2. Trace all operations that depend on the disabled component being active
  3. Check whether time-critical or loss-preventing operations (liquidation, repayment, claim) are blocked by the pause/removal
  4. Confirm no emergency bypass exists for critical operations during pause state
  5. Verify that interest/fees continue accruing during the blocked period (amplifying harm)
- **Failure Mode**: Admin pauses a pool or removes it from an orderbook. Liquidations, repayments, or claims that route through that pool are blocked. Meanwhile, interest continues accruing on borrower positions, or scheduled values expire unused. Users cannot protect themselves from growing debt or expiring rights during the blocked period.
- **Common Contexts**: Orderbook pool removal, protocol-wide pause affecting liquidations, timelocked parameter changes blocking re-submission, strategy removal blocking vault withdrawals
