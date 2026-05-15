# Cantina Reward Accounting Patterns (NEW CLUSTER)
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 7
> Cluster slug: reward-accounting
> Primary triggers: rewardRate, rewardPerToken, earned, stake, unstake, slash, boost, epoch, accrue, distribute

---

## CANTINA-REWARD-001: retroactive_boost_weight_manipulation
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**: `rewardPerTokenStored` updated using current `boost` or `weight` without snapshotting at modification time; `earned(user) = balance * (rewardPerToken - userRewardPerTokenPaid)` where `balance` reflects boosted/weighted shares; `setBoost(user, newBoost)` or `updateWeight(user, newWeight)` that modifies effective balance without settling accrued rewards first
- **Detection Heuristic**:
  1. Identify all functions that modify a user's effective stake weight, boost multiplier, or voting power
  2. Check if the modifier function calls `updateReward(user)` or equivalent accrual settlement BEFORE changing the weight
  3. Trace the `earned()` formula: does it multiply current weight by the full historical rewardPerToken delta, or only by the delta accrued since the weight change
  4. Test: user stakes at 1x weight, rewards accrue for 10 epochs, user boosts to 3x, then claims; compare claimed amount to what a user staked at 3x from epoch 1 would receive
  5. Check if weight reduction can be blocked or delayed by the user (e.g., by not calling claim, by reverting in a callback)
- **Failure Mode**: User stakes with low boost, waits for rewards to accumulate, then increases boost. The new boost is applied retroactively to the entire rewardPerToken delta, crediting the user with boosted rewards for periods when they were unboosted. Alternatively, user indefinitely blocks earning power reduction by refusing to trigger the update, continuing to earn at an inflated rate while other stakers' shares are diluted
- **Common Contexts**: Gauge-boosted staking (ve-model), NFT-boosted yield farming, any reward system where a user's effective share can change independently of deposit/withdraw

---

## CANTINA-REWARD-002: emission_to_empty_pool_token_lock
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `rewardRate = reward / duration` set unconditionally; `rewardPerToken += rewardRate * elapsed / totalSupply` where `totalSupply` can be zero; no guard `if (totalSupply == 0) return` before accumulation; reward tokens transferred to distributor regardless of staker count
- **Detection Heuristic**:
  1. Locate the reward notification or distribution function that sets `rewardRate` or queues emissions
  2. Check what happens to `rewardPerTokenStored` updates when `totalSupply == 0` or `totalStaked == 0`
  3. Trace reward tokens: are they transferred into the contract on notification regardless of whether stakers exist
  4. Test: notify rewards with zero stakers, wait half the period, then stake; verify whether the first-half emissions are claimable or permanently locked
  5. Check for a sweep/recovery function for unclaimed emissions
- **Failure Mode**: Rewards are emitted at a constant rate but no stakers are present to receive them. The `rewardPerToken` accumulator either reverts on division by zero (DoS), skips the update (tokens locked in contract with no claimant), or overflows. Emissions for the empty period are permanently unrecoverable unless the contract has an admin sweep function
- **Common Contexts**: Synthetix-style StakingRewards, gauge emission systems, any pool where reward rate is set independently of staker presence

---

## CANTINA-REWARD-003: slash_propagation_to_future_rewards
- **Frequency**: ~5/279 findings
- **Severity**: HIGH
- **Code Shape**: `slash(user, amount)` that reduces `user.shares` or `user.stake` without settling `earned(user)` first; `totalAssets -= slashAmount` applied globally affecting `rewardPerToken` denominator; `rewardWeight` or `farmTotalAssets` calculated using post-slash values for pre-slash reward periods
- **Detection Heuristic**:
  1. Identify all slashing or penalty functions that reduce a user's effective stake, shares, or reward weight
  2. Check if accrued-but-unclaimed rewards are settled before the slash modifies the user's balance
  3. Trace whether the slash amount is deducted from already-vested rewards (double penalty) or only from future earning power
  4. Check if a global slash (reducing `totalAssets`) retroactively changes the reward distribution ratio for users who were not slashed
  5. Test: user accrues 100 reward tokens over 10 epochs, gets slashed at epoch 10; verify claimed amount equals 100 (pre-slash accrual) minus only the intended penalty, not 100 * (post-slash-weight / pre-slash-weight)
- **Failure Mode**: Slash reduces a user's reward weight or shares without first checkpointing accrued rewards. The user's `earned()` calculation applies the reduced weight retroactively to all prior epochs, effectively slashing already-vested rewards on top of the intended penalty. Alternatively, global slash on `totalAssets` distorts the `rewardPerToken` for uninvolved users, causing incorrect farm total asset calculations and cascading accounting errors
- **Common Contexts**: Restaking protocols with slashing, liquid staking with validator penalties, any staking system that combines reward accrual with punitive balance reduction

---

## CANTINA-REWARD-004: reward_rate_manipulation_via_dust_or_timing
- **Frequency**: ~4/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `rewardRate = (remaining + newReward) / duration` where `remaining` is computed from stale `rewardRate * timeLeft`; `notifyRewardAmount(amount)` callable with dust amounts; no minimum reward amount check; `if (block.timestamp >= periodFinish) { rewardRate = reward / duration } else { rewardRate = (reward + leftover) / duration }`
- **Detection Heuristic**:
  1. Locate the reward notification function and its `rewardRate` recalculation formula
  2. Check if calling `notifyRewardAmount` with a tiny amount (1 wei) resets the reward duration
  3. Test: notify 1000 tokens for 7 days, wait 6 days, notify 1 wei; verify the remaining ~143 tokens are now spread over a new 7-day period (effective rate drops from ~143/day to ~20/day)
  4. Check access control on the notification function (permissionless = critical, admin-only = lower risk)
  5. Verify if `startTime < block.timestamp` allows front-running the reward start to claim rewards for a fabricated past period
- **Failure Mode**: Attacker repeatedly calls `notifyRewardAmount` with dust amounts, each call extending the reward period while diluting the rate. Legitimate rewards are stretched over an ever-extending horizon, approaching zero emission rate. Alternatively, setting `startTime` in the past allows a front-runner to stake just before the call and claim rewards for the backdated period
- **Common Contexts**: Synthetix-style reward distributors, gauge reward contracts, any reward system where notification resets or extends the emission period

---

## CANTINA-REWARD-005: epoch_timestamp_boundary_errors
- **Frequency**: ~5/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `epochStart = block.timestamp - (block.timestamp % epochDuration)` with off-by-one; `if (timestamp >= epochEnd)` vs `if (timestamp > epochEnd)` inconsistency; `rewardPerEpoch[currentEpoch]` updated but `currentEpoch` uses stale timestamp; `userUnwindingTimestamp` or `unlockTime` calculated with wrong epoch alignment
- **Detection Heuristic**:
  1. Enumerate all epoch/period boundary calculations (start, end, current epoch index)
  2. Check for off-by-one errors at boundaries: does `epochEnd` use `>=` or `>`, and is this consistent across all callers
  3. Trace state transitions at epoch boundaries: verify that exactly one epoch receives each reward unit (no double-counting or gap)
  4. Test: execute a stake/unstake/claim at exactly `epochEnd` timestamp; verify the action is attributed to the correct epoch
  5. Check if epoch duration validation allows zero or unreasonably small values that break the modular arithmetic
  6. Verify that unwinding/unlock timestamps align correctly with epoch boundaries (no premature unlock or unfair delay)
- **Failure Mode**: Epoch boundary calculation is off-by-one: reward for the final second of epoch N is attributed to epoch N+1, or a user's unwinding timestamp falls between epochs causing a revert. With incorrect epoch duration validation, an admin can set duration to zero (division by zero DoS) or to a value that causes reward periods to misalign with voting/lock periods. Users at epoch boundaries experience reverts, incorrect reward attribution, or unfair maturity delays
- **Common Contexts**: Staking protocols with discrete epochs, voting systems with period-based weight, any reward or lock system using modular timestamp arithmetic

---

## CANTINA-REWARD-006: rewards_stuck_after_state_transition
- **Frequency**: ~5/279 findings
- **Severity**: HIGH
- **Code Shape**: `closePosition(id)` or `liquidate(user)` that deletes position state without calling `claimRewards(user)` first; `lock.endTime` checked before `getReward()` is callable; `onlyActive` modifier on `claim()` that prevents claiming after position closes; `delete positions[id]` clearing reward checkpoint data
- **Detection Heuristic**:
  1. Identify all terminal state transitions: position close, liquidation, lock expiry, emergency withdraw, protocol migration
  2. For each transition, check if accrued rewards are claimed or forwarded before the position state is deleted
  3. Trace the claim function's prerequisites: can a user claim after their position is closed, liquidated, or expired
  4. Check if `delete` or state zeroing clears the reward checkpoint data (`userRewardPerTokenPaid`, `rewards[user]`)
  5. Test: accrue rewards for 10 periods, then close/liquidate the position; attempt to claim; verify whether accrued rewards are recoverable
- **Failure Mode**: User's position is closed, liquidated, or lock period expires. The terminal transition deletes the position data (including reward checkpoints) without first settling accrued rewards. The user's unclaimed rewards become permanently locked in the contract with no claim path. Alternatively, the claim function has an `onlyActive` guard that becomes unreachable after the state transition, creating a logical deadlock where rewards exist but cannot be withdrawn
- **Common Contexts**: Staking with lock periods, lending protocols with liquidation, gauge positions with expiry, any system where position lifecycle has a terminal state that clears accounting data

---

## CANTINA-REWARD-007: credit_state_monotonicity_violation
- **Frequency**: ~4/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `creditLimit[vault] += repayAmount` in `repay()` instead of restoring to original; `updateReward()` called on every block/transaction resetting `rewardRate` denominator; `gaugeBalance` updated on `updateGauge()` without settling prior gauge rewards; `totalShares` modified without proportional adjustment to per-share accumulators
- **Detection Heuristic**:
  1. Identify all state variables that function as accumulators or credit limits (credit, debt ceiling, reward index, gauge weight)
  2. Trace every write site for each accumulator; verify that additive operations (+=) and restorative operations (= original) are not confused
  3. Check for functions that are safe to call once but break accounting when called repeatedly (e.g., `updateReward` resetting a time delta, `repay` incrementing credit limit)
  4. Test: call the function N times in sequence; verify the accumulator value matches the expected result (not N * delta)
  5. Check if gauge/reward migration functions properly settle one gauge's rewards before transferring stake to another
- **Failure Mode**: A credit limit or reward accumulator grows monotonically when it should be idempotent or bounded. Each `repay()` call adds the repay amount to the credit limit instead of restoring the original limit, allowing unlimited credit expansion. Each `updateReward()` call when `totalSupply` has changed recomputes the rate with a stale denominator, causing rounding errors that compound over thousands of calls. Gauge migration updates balance in the new gauge without settling rewards in the old, causing reward loss or double-counting
- **Common Contexts**: Vault credit/debt systems, frequently-updated reward accumulators, gauge migration flows, any protocol where a state variable is updated by multiple independent callers

---
