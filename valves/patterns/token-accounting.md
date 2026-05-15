# Token Accounting Patterns
> Extracted from 751 findings (500 sampled)
> Pattern count: 22

---

## TOKEN-001: fee_on_transfer_balance_assumption
- **Frequency**: ~155/500
- **Severity**: MEDIUM (occasionally HIGH when enabling free minting or draining)
- **Code Shape**:
  ```solidity
  // Records `amount` parameter, not actual tokens received
  function deposit(uint256 amount) external {
      token.transferFrom(msg.sender, address(this), amount);
      balances[msg.sender] += amount;          // BUG: should be post - pre balance
      totalDeposited += amount;
  }
  ```
- **Detection Heuristic**:
  1. Find every `transferFrom(sender, contract, amount)` call
  2. Check whether the storage update after the call uses `amount` directly vs. measuring `balanceAfter - balanceBefore`
  3. If `amount` is used for shares/credits/internal balance without a balance-delta check → flag
  4. Look for `balances[user] += amount` or `shares = amount * rate` patterns following transferFrom
  5. Confirm token is not an immutable deploy-time constant (if FOT is genuinely out of scope, document)
- **Failure Mode**: Internal accounting records more tokens than actually arrived. In vaults this inflates share prices for later depositors; in lending it allows borrowing against phantom collateral; in escrow the last withdrawer cannot be paid.
- **Common Contexts**: ERC4626 vaults, staking contracts, lending pool deposits, bridge escrows, DEX pool liquidity additions, airdrop factories, reward distributors

---

## TOKEN-002: rebasing_token_stored_balance_staleness
- **Frequency**: ~52/500
- **Severity**: HIGH (positive rebases cause stuck rewards; negative rebases cause insolvency)
- **Code Shape**:
  ```solidity
  // Protocol stores snapshot of balance at deposit time
  mapping(address => uint256) public storedBalance;

  function deposit(uint256 amount) external {
      token.transferFrom(msg.sender, address(this), amount);
      storedBalance[msg.sender] = amount;   // BUG: rebases change actual balance later
  }

  function withdraw() external {
      uint256 amt = storedBalance[msg.sender];
      token.transfer(msg.sender, amt);      // May revert (negative rebase) or underpay (positive)
  }
  ```
- **Detection Heuristic**:
  1. Identify tokens that can rebase: stETH, AMPL, aTokens, OUSD, OHM, elastic tokens
  2. Find any state variable updated once on deposit but used unchanged later for withdrawal/reward calculation
  3. Check whether the protocol calls `balanceOf(address(this))` at withdrawal time vs. relying on stored snapshot
  4. Look for `stored_balances`, `lastBalance`, `totalDeposited` variables not refreshed on rebase
  5. Check if reward distribution divides a fixed stored amount by elapsed time without accounting for balance growth
- **Failure Mode**: With positive rebase (yield): extra tokens accumulate in contract unreachable by anyone (stuck). With negative rebase (slash): stored balance > actual balance → last withdrawers cannot withdraw; protocol becomes insolvent.
- **Common Contexts**: Yield-bearing token vaults (stETH, aTokens), liquidity gauges, staking contracts with rebasing reward tokens, cross-chain bridges holding rebase tokens, vesting contracts

---

## TOKEN-003: erc777_reentrancy_hook_exploitation
- **Frequency**: ~24/500
- **Severity**: HIGH (fund theft, double accounting)
- **Code Shape**:
  ```solidity
  // tokensToSend / tokensReceived hook fires before/after transfer
  function buy(uint256 amount) external {
      token.transferFrom(msg.sender, address(this), amount);
      // ERC777 tokensReceived hook fires HERE if this contract is registered
      balances[msg.sender] += amount;   // Hook can re-enter buy() before this line
      _mintReceipt(msg.sender, amount);
  }
  ```
- **Detection Heuristic**:
  1. Find all `transferFrom` / `transfer` calls in non-view functions
  2. Determine whether the token is or could be ERC777 (check interface, `send()` function, `ITokensRecipient`)
  3. Check if state updates (`balances`, `totalSupply`, reward accumulators) occur AFTER the transfer
  4. Verify whether a reentrancy guard covers the entire function
  5. Look for patterns where external callbacks are registered: `ERC1820Registry`, `isOperator`, `authorizeOperator`
- **Failure Mode**: Attacker registers as `tokensReceived` recipient, re-enters the function during token transfer, double-spends or double-mints before state updates commit. Results in buying tokens at steep discount or draining contract.
- **Common Contexts**: Token sale contracts, vault deposits, staking entry points, bridge receive handlers, rental contracts

---

## TOKEN-004: share_inflation_first_depositor_attack
- **Frequency**: ~18/500
- **Severity**: HIGH (victim loses almost all deposited funds)
- **Code Shape**:
  ```solidity
  // ERC4626-style vault with no virtual shares / decimal offset
  function convertToShares(uint256 assets) public view returns (uint256) {
      uint256 supply = totalSupply();
      return supply == 0 ? assets : assets * supply / totalAssets();
  }
  // Attacker: deposit 1 wei → get 1 share → donate large amount
  // totalAssets inflates → victim's 1000 assets → 0 shares (rounds down)
  ```
- **Detection Heuristic**:
  1. Find ERC4626-style vaults: `convertToShares`, `convertToAssets`, `deposit`, `mint`, `totalAssets`
  2. Check if `_decimalsOffset()` returns 0 and no virtual shares are burned at initialization
  3. Check whether the first deposit path can result in 1 share for 1 asset (no minimum)
  4. Look for donation paths: direct `transfer` to vault that increases `totalAssets()` without minting shares
  5. Confirm whether any `assert(totalSupply() > 0)` or donation guard exists
- **Failure Mode**: Attacker deposits 1 wei (1 share), donates large token amount directly to vault, inflating the price/share so victim's deposit rounds to 0 shares and they receive nothing on withdrawal.
- **Common Contexts**: ERC4626 vaults, LP token vaults, staking receipt token vaults, liquid staking derivatives, any shares-based accounting without a virtual offset

---

## TOKEN-005: incorrect_shares_math_scale_mismatch
- **Frequency**: ~28/500
- **Severity**: HIGH (systematic over/under payment, potential drain)
- **Code Shape**:
  ```solidity
  // Mixing scaled (ray/wad) and unscaled values
  function _afterTokenTransfer(address from, address to, uint256 amount) internal {
      // amount is unscaled, but _updateBalance expects scaled (ray)
      _updateBalance(from, amount);        // BUG: should be amount.rayDiv(index)
      _updateBalance(to, amount);          // or amount in wrong units
  }
  ```
- **Detection Heuristic**:
  1. Identify rebasing tokens that use a `scalingFactor`, `index`, `creditPerToken` or `rebasingCreditsPerToken`
  2. Find all arithmetic operations mixing scaled and unscaled values without explicit conversion
  3. Check transfer hooks (`_afterTokenTransfer`, `_beforeTokenTransfer`) for unit consistency
  4. Verify `balanceOf` return value: does it divide stored credits by `creditsPerToken`? Is that factor up-to-date?
  5. Look for subtraction/addition across variables with different units (e.g., `underlying` amount stored alongside `shares` amount)
- **Failure Mode**: Transfer sends correct tokens but internal credit/share accounting is updated with wrong magnitude, leading to balance divergence. Users may over-spend approvals, under-receive on withdrawal, or inflate total supply.
- **Common Contexts**: Rebasing token implementations (OUSD, aTokens, stETH), wrapped rebasing tokens, lending pool token transfers, index-scaled ERC20s

---

## TOKEN-006: reward_double_claim_missing_state_reset
- **Frequency**: ~14/500
- **Severity**: HIGH (infinite reward drain)
- **Code Shape**:
  ```solidity
  function claimRewards() external {
      uint256 reward = pendingRewards[msg.sender];
      rewardToken.transfer(msg.sender, reward);
      // BUG: pendingRewards[msg.sender] never zeroed
      // or epoch counter never advanced
  }
  ```
- **Detection Heuristic**:
  1. Find `claim` / `claimRewards` / `harvest` functions
  2. Check that every storage variable tracking claimable amount (`pendingRewards`, `rewardDebt`, `lastClaimedEpoch`) is reset or updated BEFORE or atomically with the transfer
  3. Look for missing `pendingRewards[user] = 0` after transfer
  4. Check epoch/round tracking: is `lastStakedEpoch` or `lastClaimedEpoch` updated to current epoch, or only incremented?
  5. Verify pull-over-push pattern: rewards should reflect state at call time and be wiped immediately
- **Failure Mode**: User can call `claimRewards()` repeatedly in a loop or across blocks, draining the entire reward pool because claimed state is never cleared.
- **Common Contexts**: Staking rewards, gauge bribe claims, epoch-based reward distribution, liquidity mining, veToken reward claim

---

## TOKEN-007: decimal_mismatch_in_arithmetic
- **Frequency**: ~20/500
- **Severity**: MEDIUM–HIGH (systematic miscalculation of amounts, oracle/rate errors)
- **Code Shape**:
  ```solidity
  // Token A: 6 decimals, Token B: 18 decimals; price in 8 decimals
  uint256 value = (amount * price) / 1e18;   // BUG: should normalize to same base first
  // Results in 1e4 magnitude error for 6-decimal token
  ```
- **Detection Heuristic**:
  1. Identify all tokens in the system and their decimal counts
  2. Find cross-token arithmetic: price * amount, share calculations, exchange rate applications
  3. Check if `token.decimals()` is fetched dynamically and used in normalization before arithmetic
  4. Look for hardcoded `1e18` in formulas that touch tokens which might have `1e6` (USDC, USDT) or `1e8` decimals
  5. Check oracle return decimals vs. expected precision in the formula
- **Failure Mode**: Users receive wrong amounts — e.g., 1e12x too few or too many tokens when decimal bases differ by 12. Rate calculations return zero or overflow. Share prices completely wrong for non-18-decimal assets.
- **Common Contexts**: Cross-asset lending (USDC collateral for WETH), oracle price feeds (Chainlink returns 8 decimals), share token vaults with non-18-decimal underlying, cross-chain token bridges, option pricing

---

## TOKEN-008: fee_on_transfer_double_fee_application
- **Frequency**: ~8/500
- **Severity**: MEDIUM (user overpays, incorrect amounts transferred)
- **Code Shape**:
  ```solidity
  // Fee applied twice: once by token and once by protocol
  function transferFee(address token, uint256 amount, address recipient) {
      uint256 fee = amount * FEE_RATE / 10000;
      // Token already deducted its own fee on the transferFrom
      IERC20(token).transferFrom(msg.sender, address(this), amount - fee);
      // Protocol then deducts fee again from the already-reduced amount
      _recordFee(fee);
  }
  ```
- **Detection Heuristic**:
  1. Find functions that calculate protocol fees AND transfer tokens
  2. Check if protocol fee is subtracted from the `amount` parameter BEFORE passing to `transferFrom`
  3. Check if the token itself is a FOT token (fee deducted inside transfer)
  4. Trace the final received amount: `actualReceived = amount - tokenFee - protocolFee` vs. intended
  5. Look for `EXTERNAL_INTERNAL` transfer mode logic that calls `transferFrom` then records a separate fee deduction
- **Failure Mode**: Fee-on-transfer token deducts its own fee during the transfer; then the calling protocol also deducts a protocol fee from the same `amount`, resulting in double-counting that either reverts on insufficient balance or sends incorrect amounts to recipients.
- **Common Contexts**: DEX routers with protocol fees, bridge fee handlers, yield strategy fee extraction, Beanstalk-style transfer library modes

---

## TOKEN-009: missing_approval_reset_leftover_allowance
- **Frequency**: ~10/500
- **Severity**: HIGH (entire contract balance can be drained by approved contract)
- **Code Shape**:
  ```solidity
  function swap(address router, uint256 amount) external {
      token.approve(router, amount);
      router.swap(token, amount, ...);
      // BUG: if only partial amount swapped, leftover approval remains
      // malicious router can spend remaining allowance later
      // no token.approve(router, 0) after the call
  }
  ```
- **Detection Heuristic**:
  1. Find `approve(spender, amount)` calls where `spender` is an external contract
  2. Check if approval is reset to 0 after the interaction (`approve(spender, 0)` or `safeApprove(spender, 0)`)
  3. Check if `type(uint256).max` approval is granted — leftover is permanent until explicitly revoked
  4. Verify that partial fills are handled: if router only uses part of the allowance, is the remainder cleared?
  5. Look for `safeApprove` on USDT-like tokens (non-zero to non-zero reverts) — incorrect reset order
- **Failure Mode**: Unspent approval allows the approved contract (or attacker who gains control) to drain the full remaining allowance in a subsequent call, emptying the contract's balance.
- **Common Contexts**: DEX integration wrappers, yield strategy adapters, zap contracts, any single-use approval pattern

---

## TOKEN-010: unsafe_erc20_transfer_missing_return_check
- **Frequency**: ~16/500
- **Severity**: MEDIUM (silent transfer failure treated as success)
- **Code Shape**:
  ```solidity
  // Using raw transfer() instead of SafeERC20
  function withdraw(uint256 amount) external {
      IERC20(token).transfer(msg.sender, amount);  // BUG: non-compliant tokens return false
      // No check on return value; state already updated
  }
  ```
- **Detection Heuristic**:
  1. Search for direct `IERC20(token).transfer(` and `IERC20(token).transferFrom(` without wrapping in `SafeERC20`
  2. Check if return value is assigned and checked: `bool success = token.transfer(...)` plus `require(success)`
  3. Identify tokens that return false on failure instead of reverting: BNB, USDT (on some chains), others
  4. Look for `address.call(abi.encodeWithSelector(...))` patterns for low-level token calls
  5. Verify `safeTransfer` / `safeTransferFrom` from OpenZeppelin SafeERC20 is used throughout
- **Failure Mode**: Transfer fails silently (returns `false` but does not revert). The protocol continues as if transfer succeeded, leading to accounting discrepancies where state records a payout that never occurred.
- **Common Contexts**: Legacy contracts, custom ERC20 integrations, NFT marketplaces, staking reward payouts, bridge withdrawal handlers

---

## TOKEN-011: read_only_reentrancy_stale_oracle_via_balanceof
- **Frequency**: ~8/500
- **Severity**: HIGH (price manipulation, oracle exploitation)
- **Code Shape**:
  ```solidity
  // External view call reads pool state mid-reentrant execution
  function getPrice() external view returns (uint256) {
      // Called from attacker's tokensReceived hook while pool state is mid-update
      return pool.getReserves();   // Reads stale/transitional state
  }
  // Lending protocol reads this price during the reentrant call
  ```
- **Detection Heuristic**:
  1. Find protocols that read price/reserve data from external AMMs or pools
  2. Check if the external pool uses Curve/Balancer-style reentrancy locks that do NOT protect `view` functions
  3. Identify where an ERC777/callback token transfer can nest inside a critical function that reads pool state
  4. Look for `getVirtualPrice()`, `get_dy()`, `getReserves()` called after a transfer but before all state finalization
  5. Check whether the price-reading function is called inside the same call graph as a token transfer
- **Failure Mode**: Attacker triggers a read-only reentrancy where the price oracle is read while the pool's internal state is in a transitional (incorrect) state, allowing manipulation of collateral values without modifying state themselves.
- **Common Contexts**: Curve pool integrations, Balancer vault interactions, Uniswap V2/V3 price reads, any protocol using AMM spot price as an oracle

---

## TOKEN-012: vesting_release_rate_calculation_error
- **Frequency**: ~8/500
- **Severity**: HIGH (recipient can unlock more than their allocation)
- **Code Shape**:
  ```solidity
  function transferVesting(address newOwner, uint256 amount) external {
      VestingSchedule storage v = vestings[msg.sender];
      // Calculates new release rate for grantor AFTER subtracting amount
      // but stepsClaimed from original schedule is copied to new owner
      vestings[newOwner] = VestingSchedule({
          amount: amount,
          stepsClaimed: v.stepsClaimed,   // BUG: new owner inherits already-claimed steps
          releaseRate: amount / (v.totalSteps - v.stepsClaimed)  // BUG: grantor math applied to recipient
      });
  }
  ```
- **Detection Heuristic**:
  1. Find vesting transfer / splitting functions: `transferVesting`, `splitVesting`, `delegate`
  2. Check if `stepsClaimed`, `claimedAmount`, or `startTime` are copied from sender to recipient unchanged
  3. Verify release rate is recalculated from scratch for the new schedule vs. inherited from old one
  4. Check that the total allocatable amount equals grantor's remaining (not original) allocation
  5. Confirm the grantor's record is reduced by exactly the transferred amount
- **Failure Mode**: New vesting recipient can claim tokens that have already been claimed by the original holder (inherited `stepsClaimed` skips ahead too far) or the rate is miscalculated such that they unlock more than their entitled share.
- **Common Contexts**: Vesting token markets (e.g., SecondSwap), DAO token vesting transfers, options-like vesting split mechanics

---

## TOKEN-013: reward_manipulation_via_large_flash_deposit_withdraw
- **Frequency**: ~10/500
- **Severity**: MEDIUM–HIGH (reward theft through timing manipulation)
- **Code Shape**:
  ```solidity
  function distributeRewards() external {
      uint256 totalStaked = stakingToken.balanceOf(address(this));
      // Attacker deposits huge amount before this call
      rewardPerToken = totalRewards / totalStaked;  // BUG: attacker dilutes rewards for others
      // then immediately withdraws
  }
  ```
- **Detection Heuristic**:
  1. Find reward distribution functions that snapshot `totalStaked` / `totalSupply` at distribution time
  2. Check if deposit and distribution can occur in the same transaction or same block
  3. Look for lack of minimum staking duration requirement
  4. Check if withdraw is callable immediately after deposit with no delay
  5. Verify whether rewards per share are updated BEFORE allowing new deposits to affect the denominator
- **Failure Mode**: Attacker flash-deposits a large amount immediately before reward distribution, diluting other stakers' share of rewards to near zero, then withdraws. No capital at risk beyond gas.
- **Common Contexts**: Staking reward contracts, liquidity mining, bribe distribution, epoch-based reward pools

---

## TOKEN-014: incorrect_total_assets_inflation_via_pending_tokens
- **Frequency**: ~8/500
- **Severity**: MEDIUM (share price manipulation, incorrect redemption amounts)
- **Code Shape**:
  ```solidity
  function totalAssets() public view override returns (uint256) {
      // Includes tokens not yet deposited into underlying strategy
      return underlyingToken.balanceOf(address(this))  // idle balance counted twice
           + strategyBalance                             // strategy balance already includes idle
           + pendingDeposits;                            // pending amount double-counted
  }
  ```
- **Detection Heuristic**:
  1. Find `totalAssets()` overrides in ERC4626 or custom vault implementations
  2. Check each addend: is idle balance counted AND included in strategy balance?
  3. Look for `pendingDeposits`, `queuedDeposits`, or `pendingRedemptions` variables added to `totalAssets`
  4. Verify the harvest/report function: does it update `totalAssets` before or after accounting for yield?
  5. Cross-check with `_harvestAndReport()` — does it double-count harvested amounts?
- **Failure Mode**: `totalAssets()` returns inflated value, making each share worth more than reality. Depositors receive fewer shares. When strategy returns actual (lower) assets, some holders cannot redeem.
- **Common Contexts**: Yearn-style strategy vaults, Alchemix transmuter strategies, ERC4626 adapters with yield compounding, any vault with a harvest-and-reinvest loop

---

## TOKEN-015: unclaimed_revenue_double_counted_as_new_revenue
- **Frequency**: ~4/500
- **Severity**: HIGH (infinite phantom revenue, share price manipulation)
- **Code Shape**:
  ```solidity
  function updateRevenue() external {
      uint256 currentBalance = revenueToken.balanceOf(address(this));
      // BUG: does not subtract already-recorded but unclaimed revenue
      uint256 newRevenue = currentBalance - lastBalance;
      totalRevenue += newRevenue;  // Already-claimed tokens counted again
      lastBalance = currentBalance;
  }
  ```
- **Detection Heuristic**:
  1. Find revenue tracking functions that compare current balance to a stored `lastBalance`
  2. Check if `lastBalance` is updated whenever tokens are claimed/distributed, not just on deposit
  3. Verify that the balance snapshot excludes already-accounted-for tokens
  4. Look for `distributeRevenue` → `claimRevenue` flows where `lastBalance` is not reset post-distribution
  5. Check if idle balance from prior unclaimed periods gets added as "new" revenue each call
- **Failure Mode**: Each call to `updateRevenue` counts previously-recorded unclaimed tokens as new revenue, inflating the tracked total unboundedly. Affects share price and allows attackers to claim more than their proportional share.
- **Common Contexts**: Fee distributor contracts, revenue spigot systems, protocol treasury revenue tracking

---

## TOKEN-016: cross_chain_decimal_normalization_failure
- **Frequency**: ~6/500
- **Severity**: HIGH (users receive far more or far less tokens than expected)
- **Code Shape**:
  ```solidity
  // Bridge sends `amount` from chain A (USDC: 6 decimals)
  // Chain B interprets `amount` as 18-decimal token
  function receiveTokens(address token, uint256 amount) external {
      // amount = 1,000,000 (1 USDC on L1)
      // Minted as 1,000,000 of 18-decimal token = 0.000000000001 token (BUG)
      _mint(recipient, amount);  // Should be amount * 1e12 to normalize
  }
  ```
- **Detection Heuristic**:
  1. Find cross-chain token bridge mint/burn functions
  2. Check if source chain decimal count is encoded in the cross-chain message
  3. Verify that destination chain normalizes `amount` by `10**(destDecimals - srcDecimals)` before minting
  4. Look for hardcoded assumptions that `amount` is always in 18-decimal units
  5. Check that the same token on different chains might have different decimal representations
- **Failure Mode**: Amount decoded on destination chain is off by `10^(decimal_diff)`. Users lose most of their value (if src has more decimals) or receive orders of magnitude more than intended (if src has fewer decimals).
- **Common Contexts**: Cross-chain token bridges, LayerZero/Wormhole/Axelar bridge adapters, cross-chain lending protocols (LEND protocol), wrapped asset bridges

---

## TOKEN-017: erc4626_share_accounting_incompatible_with_rebase_underlying
- **Frequency**: ~14/500
- **Severity**: HIGH (insolvency or locked funds)
- **Code Shape**:
  ```solidity
  // ERC4626 vault holding stETH/aToken
  function totalAssets() public view override returns (uint256) {
      return stETH.balanceOf(address(this));  // Correct: rebases are reflected in balanceOf
  }
  // But: deposit records `assets` not balanceOf-delta
  function deposit(uint256 assets, address receiver) public override {
      _asset.transferFrom(msg.sender, address(this), assets);
      // stETH may transfer 1-2 wei less due to rounding
      uint256 shares = previewDeposit(assets);   // Uses `assets` not actual received
      _mint(receiver, shares);                    // Over-mints shares
  }
  ```
- **Detection Heuristic**:
  1. Find ERC4626 implementations where the underlying asset is stETH, aToken, or other rebasing token
  2. Check if `deposit()` uses the `assets` parameter directly vs. measuring `balanceOf(this)` delta
  3. Look for strict equality checks on transfer amounts that will fail for stETH 1-2 wei rounding
  4. Verify `withdraw()` and `redeem()` paths: do they request exact amounts that might exceed available balance?
  5. Check if `totalAssets()` is updated before or after the rebase event affects the balance
- **Failure Mode**: stETH transfers 1-2 wei less than requested due to rounding; strict amount checks revert. Alternatively, shares are minted against `assets` parameter but actual tokens received are less, creating an undercollateralized share.
- **Common Contexts**: stETH/wstETH vaults, aToken ERC4626 wrappers, Notional wfCash ERC4626, any yield-bearing token vault

---

## TOKEN-018: msg_value_reuse_in_loop_eth_drain
- **Frequency**: ~4/500
- **Severity**: HIGH (drains ETH from contract)
- **Code Shape**:
  ```solidity
  function batchDeposit(address[] calldata recipients, uint256 amount) external payable {
      for (uint256 i = 0; i < recipients.length; i++) {
          // BUG: msg.value is the same for every iteration
          _deposit{value: msg.value}(recipients[i], amount);
      }
      // Actual ETH spent: msg.value * recipients.length
      // Attacker sends 1 ETH, registers N recipients → drains N-1 ETH
  }
  ```
- **Detection Heuristic**:
  1. Find `payable` functions containing loops
  2. Check if `msg.value` is used inside the loop body (passed to subcall or used in arithmetic)
  3. Verify total ETH consumed matches `msg.value` exactly, not `msg.value * iterations`
  4. Look for `{value: msg.value}` inside for-loops
  5. Check for accumulator pattern: `totalSent += msg.value` inside loop vs. `require(msg.value == totalSent)` after
- **Failure Mode**: Each loop iteration consumes `msg.value` from the contract's ETH balance (not the user's), effectively draining contract ETH by `(N-1) * msg.value` per call where N is attacker-controlled.
- **Common Contexts**: THORChain routers, batch airdrop contracts, multi-recipient ETH distribution, cross-chain batch send

---

## TOKEN-019: double_entrypoint_token_bypass_collateral_check
- **Frequency**: ~4/500
- **Severity**: HIGH (collateral stolen without repaying debt)
- **Code Shape**:
  ```solidity
  // Token has two entry points (e.g., Compound cDAI → DAI via two contracts)
  function withdraw(address collateralToken, uint256 amount) external {
      require(position.collateral != collateralToken, "can't withdraw collateral");
      // Attacker calls with the alternate entry point address
      // which resolves to the same underlying — bypasses the check
      IERC20(collateralToken).transfer(msg.sender, amount);
  }
  ```
- **Detection Heuristic**:
  1. Identify tokens with multiple entry point contracts (legacy Compound cTokens, proxied tokens, multi-address tokens)
  2. Find `require(address != collateralAddress)` or similar blocklist checks using a single stored address
  3. Check if the alternate entry point can be used to transfer the same underlying
  4. Look for `transfer` / `transferFrom` using a caller-supplied `collateralToken` address
  5. Verify that all equivalent addresses for the same underlying are blocked, not just one canonical address
- **Failure Mode**: Attacker calls withdrawal with the "other" contract address for a double-entrypoint token, bypassing the collateral protection check and draining collateral without repaying their debt.
- **Common Contexts**: CDP / collateral systems (Frankencoin, etc.), lending protocols accepting compound tokens, any protocol with allowlist/blocklist for collateral tokens

---

## TOKEN-020: noncompliant_return_value_approval_revert
- **Frequency**: ~8/500
- **Severity**: MEDIUM (DoS for specific token, stuck funds)
- **Code Shape**:
  ```solidity
  // safeApprove fails for USDT: must reset to 0 before setting non-zero
  function _setupApproval(address token, address spender, uint256 amount) internal {
      IERC20(token).safeApprove(spender, amount);  // Reverts if current allowance != 0 and amount != 0
      // Should be: safeApprove(spender, 0); safeApprove(spender, amount);
      // or use safeIncreaseAllowance
  }
  ```
- **Detection Heuristic**:
  1. Search for `safeApprove(spender, nonZeroAmount)` calls
  2. Check if the approval is called on tokens that do not allow non-zero-to-non-zero approval changes (USDT, BNB)
  3. Verify whether the current allowance is always 0 before each call (e.g., always resets to 0 after use)
  4. Look for `safeApprove` in loops or functions called multiple times without intermediate reset
  5. Prefer `forceApprove` or `safeIncreaseAllowance` patterns from modern SafeERC20
- **Failure Mode**: Entire function reverts because USDT-style tokens require the allowance to be zero before setting a new value. Users cannot deposit, withdraw, or interact with the protocol for those specific tokens.
- **Common Contexts**: AAVE yield managers using USDT, strategy adapters, any integration expecting to repeatedly approve a spender

---

## TOKEN-021: residual_eth_not_returned_to_caller
- **Frequency**: ~8/500
- **Severity**: HIGH (ETH permanently locked or stolen by contract)
- **Code Shape**:
  ```solidity
  function mintWithETH(uint256 minTokens) external payable {
      uint256 tokensBought = _buyTokens{value: msg.value}(...);
      // BUG: if actual cost < msg.value, difference stays in contract
      // No refund of msg.value - actualCost to msg.sender
  }
  ```
- **Detection Heuristic**:
  1. Find `payable` functions that forward `msg.value` to internal or external calls
  2. Check if the entire `msg.value` is consumed or if partial amounts are possible
  3. Look for missing refund logic: `msg.sender.call{value: excess}("")`
  4. Check `address(this).balance` growth across the function: should be zero net change for pure swap
  5. Verify WETH wrap/unwrap paths: if ETH is converted to WETH for internal processing, is unconverted ETH returned?
- **Failure Mode**: ETH in excess of actual transaction cost is kept by the contract and not returned to the user. Over time, protocol accumulates ETH dust that is inaccessible unless there is a sweep function (which may itself be a centralization risk).
- **Common Contexts**: DEX routers with ETH input (wfCash, batchBalanceAndTradeAction), NFT mint functions with dynamic pricing, any function accepting ETH but using an internal quote

---

## TOKEN-022: unauthorized_transferfrom_arbitrary_sender
- **Frequency**: ~8/500
- **Severity**: HIGH (theft of user funds via approved allowance)
- **Code Shape**:
  ```solidity
  // Function accepts `from` parameter without validating it equals msg.sender
  function repayLoan(address borrower, uint256 amount) external {
      // Anyone can call this and pull funds from `borrower`'s account
      // as long as this contract has approval from `borrower`
      loanToken.transferFrom(borrower, address(this), amount);
      loans[borrower].outstanding -= amount;
  }
  ```
- **Detection Heuristic**:
  1. Find `transferFrom(userAddress, ...)` where `userAddress` is a parameter, not `msg.sender`
  2. Check if the caller is validated to be the owner of `userAddress`
  3. Look for `depositFor`, `stakeFor`, `repayFor` patterns without access control on the `from` address
  4. Verify that the function cannot be used to drain any address that has approved the contract
  5. Check `V3Utils.execute()` and similar multicall executors — do they validate that the token sender is the caller?
- **Failure Mode**: Any user who has granted approval to the contract can have their tokens pulled by an attacker calling the permissionless function with the victim's address as the `from` parameter. Results in theft proportional to the victim's outstanding approval.
- **Common Contexts**: P2P lending repayment, staking-on-behalf functions, DEX fill functions, router aggregators with user-specified from address

---

## TOKEN-023: variable_balance_token_direct_transfer_griefing
- **Frequency**: ~6/500
- **Severity**: MEDIUM (DoS or permanent accounting corruption)
- **Code Shape**:
  ```solidity
  // Protocol uses balanceOf(this) as the canonical source of truth
  function _processDeposit(uint256 amount) internal {
      totalBalance += amount;
      // Attacker can directly transfer tokens to contract
      // making totalBalance < balanceOf(this), corrupting the invariant
  }

  function emergencyWithdraw() external {
      uint256 toWithdraw = totalBalance;  // Does not reflect donated tokens
      token.transfer(owner, toWithdraw);  // May revert if totalBalance > actual balance after negative rebase
  }
  ```
- **Detection Heuristic**:
  1. Find contracts that track a `totalBalance` / `totalDeposited` accumulator separately from `balanceOf(this)`
  2. Check if direct token transfers (not via deposit function) can cause `balanceOf(this) != totalBalance`
  3. Look for `totalBalance` used in `require(totalBalance >= amount)` checks where `balanceOf` might be lower
  4. Verify whether a griefing-by-donation attack (sending tokens directly to break ratio) is possible
  5. Check if `totalBalance` is ever reconciled with `balanceOf(this)` in a sync function
- **Failure Mode**: Direct token transfer to contract increases `balanceOf(this)` without updating internal accounting, causing discrepancy. This can be exploited to manipulate share prices, break accounting invariants, or cause legitimate operations to revert.
- **Common Contexts**: Staking contracts, liquidity pools, reward distributor contracts using `balanceOf` vs. stored balance discrepancy

---

## Summary Statistics

| # | Pattern | Approx Count | Typical Severity |
|---|---------|-------------|------------------|
| TOKEN-001 | fee_on_transfer_balance_assumption | ~155 | MEDIUM |
| TOKEN-002 | rebasing_token_stored_balance_staleness | ~52 | HIGH |
| TOKEN-003 | erc777_reentrancy_hook_exploitation | ~24 | HIGH |
| TOKEN-004 | share_inflation_first_depositor_attack | ~18 | HIGH |
| TOKEN-005 | incorrect_shares_math_scale_mismatch | ~28 | HIGH |
| TOKEN-006 | reward_double_claim_missing_state_reset | ~14 | HIGH |
| TOKEN-007 | decimal_mismatch_in_arithmetic | ~20 | MEDIUM–HIGH |
| TOKEN-008 | fee_on_transfer_double_fee_application | ~8 | MEDIUM |
| TOKEN-009 | missing_approval_reset_leftover_allowance | ~10 | HIGH |
| TOKEN-010 | unsafe_erc20_transfer_missing_return_check | ~16 | MEDIUM |
| TOKEN-011 | read_only_reentrancy_stale_oracle_via_balanceof | ~8 | HIGH |
| TOKEN-012 | vesting_release_rate_calculation_error | ~8 | HIGH |
| TOKEN-013 | reward_manipulation_via_large_flash_deposit_withdraw | ~10 | MEDIUM–HIGH |
| TOKEN-014 | incorrect_total_assets_inflation_via_pending_tokens | ~8 | MEDIUM |
| TOKEN-015 | unclaimed_revenue_double_counted_as_new_revenue | ~4 | HIGH |
| TOKEN-016 | cross_chain_decimal_normalization_failure | ~6 | HIGH |
| TOKEN-017 | erc4626_share_accounting_incompatible_with_rebase_underlying | ~14 | HIGH |
| TOKEN-018 | msg_value_reuse_in_loop_eth_drain | ~4 | HIGH |
| TOKEN-019 | double_entrypoint_token_bypass_collateral_check | ~4 | HIGH |
| TOKEN-020 | noncompliant_return_value_approval_revert | ~8 | MEDIUM |
| TOKEN-021 | residual_eth_not_returned_to_caller | ~8 | HIGH |
| TOKEN-022 | unauthorized_transferfrom_arbitrary_sender | ~8 | HIGH |
| TOKEN-023 | variable_balance_token_direct_transfer_griefing | ~6 | MEDIUM |

> Note: Counts overlap — several findings involve multiple patterns simultaneously. Total sampled = 500 findings covering 23 distinct root-cause vulnerability classes.
