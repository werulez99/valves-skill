# Cantina Access Control Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 5
> NOTE: Supplements existing AC-001..032 from Solodit corpus

---

## CANTINA-AC-033: missing_caller_validation_on_sensitive_restake
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `function restake(address user) external { _unstake(user); _stake(user, amount); }` without `require(msg.sender == user)` or role check; `function operateOnBehalf(address from, uint256 amount) public` missing authorization
- **Detection Heuristic**:
  1. Find functions that accept an address parameter (user, from, account, owner) and operate on that address's funds or position
  2. Check if the function validates that msg.sender is the address parameter, or has an explicit allowance/approval, or is a whitelisted role
  3. Confirm the function modifies state for the target address (moves funds, changes position, resets timers)
  4. Verify no delegatecall or proxy context provides implicit authorization
  5. Check if the function is inherited from a base and the override dropped the access check
- **Failure Mode**: Attacker calls a function passing a victim's address as the user parameter. Without authorization checks, the function executes on the victim's position: restaking their unlocked funds back into a locked state, moving their tokens to an attacker-controlled destination, or resetting their cooldown timer. Victim loses control over their own assets or position timing.
- **Common Contexts**: Restake/compound functions, "for" variants (depositFor, stakeFor, claimFor), liquidation-adjacent operations that accept arbitrary target, batch operation helpers

---

## CANTINA-AC-034: forged_from_parameter_drains_tokens
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `function transfer(address from, address to, uint256 amount) external { balances[from] -= amount; balances[to] += amount; }` without `require(msg.sender == from || allowance[from][msg.sender] >= amount)`
- **Detection Heuristic**:
  1. Identify functions that move tokens or value and accept a `from`/`sender`/`owner` parameter
  2. Check if the function validates msg.sender against the from parameter (direct equality, allowance check, or operator approval)
  3. Trace all code paths: if there are multiple branches (internal vs external call, different token types), check EACH branch for the authorization
  4. Confirm a caller can pass any arbitrary address as `from` and drain that address's balance to their own address
- **Failure Mode**: Attacker calls the transfer/move function with victim's address as `from` and attacker's address as `to`. Without authorization validation, the contract debits the victim and credits the attacker. Complete drain of any user's balance in a single transaction.
- **Common Contexts**: Custom token transfer functions, vault share transfers, internal accounting moves, multi-token batch transfers, bridged token relay functions

---

## CANTINA-AC-035: unvalidated_callback_delegatecall_target
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `function executeOperation(address asset, uint256 amount, bytes calldata params) external { address target = abi.decode(params); target.delegatecall(data); }` without `require(whitelist[target])`; flash loan callback that delegatecalls user-supplied address
- **Detection Heuristic**:
  1. Find callback functions (executeOperation, onFlashLoan, uniswapV3SwapCallback, hook functions) that process user-supplied data
  2. Check if the callback extracts an address from the callback data and calls or delegatecalls to it
  3. Verify whether the extracted address is validated against a whitelist or known set
  4. Confirm the callback is invocable by triggering the parent operation (flash loan, swap, hook)
  5. For delegatecall specifically: verify the target cannot modify the caller's storage arbitrarily
- **Failure Mode**: Attacker triggers a flash loan or swap that invokes the protocol's callback. The callback decodes attacker-controlled data to extract a target address and delegatecalls to it. Since delegatecall executes in the protocol's storage context, the attacker's contract can drain all approved tokens, modify critical storage slots, or brick the protocol.
- **Common Contexts**: Flash loan callbacks (Aave executeOperation, Uniswap flash), swap callbacks, ERC777 tokensReceived hooks, adapter pattern with pluggable targets, router execution callbacks

---

## CANTINA-AC-036: fee_bypass_through_hook_or_wrapper_path
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `function claim() external { uint256 fee = amount * feeRate / 1e18; token.transfer(msg.sender, amount - fee); }` but alternate path via hook/executor/module skips fee deduction; `executeFromExecutor()` path that bypasses `withHook` modifier
- **Detection Heuristic**:
  1. Identify all paths to the same terminal action (claim, withdraw, transfer) -- direct call, hook path, executor path, module path, batch path
  2. For each path, check if fee deduction, access control modifier, or validation hook is applied
  3. Compare modifiers and fee logic across paths: does the hook/executor/batch path skip any check present in the direct path
  4. Confirm a user can access the alternative path (is the executor/module user-installable, is the hook user-configurable)
  5. Verify the fee difference is material (not just rounding)
- **Failure Mode**: User discovers that the direct call path charges a fee or enforces a hook, but an alternative path (through an executor module, batch operation, or different entry point) reaches the same state change without the fee deduction or hook enforcement. User routes all operations through the bypass path, permanently avoiding protocol fees. Protocol revenue is zeroed.
- **Common Contexts**: ERC7579 modular accounts with hook/executor separation, claim paths with multiple entry points, deposit/withdraw through router vs direct, batch operations that skip per-item hooks

---

## CANTINA-AC-037: deposit_cap_bypass_through_alternate_entry
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `function deposit(uint256 assets) { require(totalAssets() + assets <= depositCap); }` but `mint(uint256 shares)` converts shares to assets differently or skips the cap check; collateral withdrawal path that resets accrual interval enforcement
- **Detection Heuristic**:
  1. Identify deposit caps, rate limits, or interval enforcement on user-facing entry points
  2. Enumerate ALL entry points that achieve the same economic effect (deposit/mint, supply/supplyShares, stake/stakeFor)
  3. Check if each entry point applies the same cap/limit validation
  4. For interval enforcement: check if any operation resets the interval counter without consuming a rate-limited action (withdraw-and-redeposit, collateral shuffle)
  5. Confirm the bypass allows exceeding the intended limit by a material amount
- **Failure Mode**: Protocol enforces a deposit cap on the `deposit()` function. User calls `mint()` instead, which converts share amount to assets differently or lacks the cap check entirely. User deposits beyond the intended cap. Alternatively, a user repeatedly triggers an interval reset (via free collateral withdrawals) to bypass rate-limited accrual, compounding faster than intended.
- **Common Contexts**: ERC4626 deposit vs mint paths, lending pool supply vs supplyShares, rate-limited operations with resettable counters, timelocked parameter changes with multiple scheduling paths
