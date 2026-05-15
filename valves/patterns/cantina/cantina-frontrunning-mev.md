# Cantina Frontrunning & MEV Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 5
> NOTE: Supplements existing MEV-001..022 from Solodit corpus

---

## CANTINA-MEV-023: admin_parameter_change_sandwich
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `function setRate(uint256 newRate) external onlyOwner { rate = newRate; }` where rate affects swap/mint/redeem output; admin setter for fee/rate/reward parameter that takes effect immediately on storage write
- **Detection Heuristic**:
  1. Identify admin setter functions that modify economic parameters (rate, fee, reward multiplier, LSF, exchange coefficient)
  2. Confirm the new value takes effect immediately (no timelock, no gradual ramp, no snapshot)
  3. Check if any user-facing operation (swap, mint, redeem, claim) reads the parameter and produces a different output at the old vs new value
  4. Verify the parameter change is visible in the mempool (no commit-reveal, no private mempool enforcement)
  5. Confirm the output difference exceeds transaction costs, making a sandwich profitable
- **Failure Mode**: Admin submits a parameter change transaction. MEV bot observes it in the mempool, executes a favorable trade at the old parameter value, lets the admin tx land, then executes the reverse trade at the new value. The bot extracts the delta as risk-free profit. Value is leaked from the protocol or its LPs.
- **Common Contexts**: LSF/rate setters in term markets, reward rate changes in staking, fee parameter updates in AMMs, collateralization ratio changes in lending, rebalance incentive changes

---

## CANTINA-MEV-024: reward_start_time_frontrun
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `if (startTime < block.timestamp) { startTime = block.timestamp; }` missing; `rewardRate = reward / duration` computed from a start time already in the past; `setReward(amount, startTime)` where startTime can be < block.timestamp
- **Detection Heuristic**:
  1. Find reward distribution setup functions that accept a start time parameter
  2. Check if the function validates `startTime >= block.timestamp`
  3. If startTime < block.timestamp is accepted, compute how much reward is immediately claimable at the moment the tx lands (elapsed time * rewardRate)
  4. Confirm a frontrunner can stake just before the setup tx to capture the immediate reward
  5. Verify the frontrunner can unstake in the same or next block to extract the reward without real staking commitment
- **Failure Mode**: Admin calls setReward with a startTime in the past. The reward rate is computed over the full duration, but elapsed time already counts as distributable. A frontrunner stakes dust, captures the accumulated-but-undistributed rewards, and unstakes immediately. Intended reward recipients receive less than expected.
- **Common Contexts**: Staking reward campaigns, farming pool initialization, gauge reward distribution, vesting schedule start with retroactive accrual

---

## CANTINA-MEV-025: missing_slippage_protection
- **Frequency**: ~5/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `function mint(uint256 assets) returns (uint256 shares)` with no `minShares` parameter; `swap(tokenIn, amountIn)` with no `amountOutMin`; `vault.deposit(amount)` without checking returned shares against a minimum
- **Detection Heuristic**:
  1. Identify user-facing functions that convert between assets (mint, redeem, deposit, withdraw, swap, close position)
  2. Check if the function accepts a minimum output parameter (minShares, minAmountOut, maxSlippage)
  3. If no slippage parameter exists, check if an external wrapper or router enforces slippage
  4. Confirm the conversion rate can be manipulated between tx submission and execution (oracle update, large trade, rebalance, share price change)
  5. Verify the absence of a deadline parameter that would limit stale-tx execution
- **Failure Mode**: User submits a mint/swap/redeem without specifying minimum acceptable output. A sandwicher manipulates the pool state (large trade, donation, oracle manipulation) to worsen the conversion rate, lets the user's tx execute at the degraded rate, then reverses the manipulation. User receives fewer shares/tokens than expected. The attacker profits the difference.
- **Common Contexts**: Vault mint/redeem without minShares, AMM swaps without amountOutMin, leveraged position closures through DEX, claim-and-swap paths, redemption of yield-bearing tokens

---

## CANTINA-MEV-026: redemption_sandwich_evades_reduction
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `function claimRedemption(uint256 id)` that returns collateral proportional to user's debt share; `redeem()` that processes queued redemptions against CDP collateral; debt repay that reduces redemption exposure
- **Detection Heuristic**:
  1. Identify redemption or liquidation mechanisms that reduce collateral proportional to debt position
  2. Check if a user can reduce their exposure (repay debt, withdraw collateral, transfer position) before the redemption processes against them
  3. Confirm redemption target selection is predictable (largest position, sequential queue, sorted by ratio)
  4. Verify no lock period prevents position changes between redemption initiation and execution
  5. Check if the avoided reduction is redistributed to remaining participants (amplifying harm to others)
- **Failure Mode**: A redemption event is initiated against CDP holders. A targeted CDP owner sees the redemption tx in the mempool, front-runs it with a repay to minimize their debt share, lets the redemption execute (hitting other CDPs harder), then re-borrows. The front-runner evades their proportional collateral reduction, concentrating losses on non-frontrunning participants.
- **Common Contexts**: CDP redemption mechanisms (Liquity-style), proportional liquidation systems, queued withdrawal distributions, any system where reducing a position before a snapshot avoids a pro-rata cost

---

## CANTINA-MEV-027: forced_routing_through_adversarial_pool
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `pool = getPool(tokenIn, tokenOut)` where pool selection is manipulable; `router.swap(path)` where path is computed on-chain from mutable state; `pools[token] = newPool` settable by semi-trusted role
- **Detection Heuristic**:
  1. Identify swap or conversion paths that select a pool/route dynamically based on on-chain state
  2. Check if the pool selection mechanism can be influenced by an attacker (registering a pool, manipulating best-price ranking, governance proposal)
  3. Confirm a user's transaction will route through whichever pool the mechanism selects at execution time
  4. Verify the selected pool can offer arbitrarily bad rates or extract value from the routed user
  5. Check for whitelist or minimum-liquidity requirements that prevent adversarial pool registration
- **Failure Mode**: Attacker creates or manipulates a pool to become the selected route for a token pair. User transactions are routed through the adversarial pool, which applies extreme slippage, fees, or re-entrancy. The attacker extracts value from every user whose swap routes through their pool. This persists until the route is corrected.
- **Common Contexts**: DEX aggregator route selection, lending protocol swap paths for collateral conversion, leveraged position closure through pool lookup, any on-chain routing that trusts mutable pool state
