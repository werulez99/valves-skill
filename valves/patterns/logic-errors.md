# Logic Error Patterns
> Extracted from 50 findings (50 sampled — full cluster)
> Pattern count: 18

---

## LOGIC-001: wrong_comparison_operator
- **Frequency**: ~8/50
- **Severity**: HIGH (3× HIGH, 3× MEDIUM, 2× LOW)
- **Code Shape**:
  ```solidity
  // Uses && when || is needed (or vice versa), or < when <= is needed
  if (conditionA && conditionB) { ... }   // should be ||
  if (value < MAX) { ... }                // should be <=
  if (!hasFlag || !hasOtherFlag) { ... }  // should be && between negations
  ```
- **Detection Heuristic**:
  1. Enumerate every `if`/`require`/`assert` guard in the contract.
  2. For each guard, write out the truth table: enumerate all input combinations.
  3. Check whether edge cases (both-true, both-false, one-true) produce the intended outcome.
  4. Pay special attention to boundary comparisons (`<` vs `<=`, `>` vs `>=`) on index, cap, and range checks.
  5. Cross-check with the spec or NatDoc: what states is the guard supposed to reject?
  6. Flag any guard where De Morgan's law inversion would change behaviour.
- **Failure Mode**: Guard admits inputs it should reject (or rejects inputs it should admit); results in bypass of caps, incorrect branching, or reversed eligibility checks.
- **Common Contexts**: reserve-ratio validation, tranche-range validation, whitelist/access-control modifiers, pool-cap enforcement, constructor invariant checks, facet-freezability checks, bond/price calculations.
- **Evidence**: [3] Radiant wrong comparison; [15] Incorrect Logical Operator In Tranche Validation; [25] reserve ratio && vs ||; [28] onlyAdminOrOperator() modifier; [33] whitelist validation &&/||; [39] RevenueHandler constructor BPS; [49] isFacetFreezable wrong keyword; [37] calculateSharesInGivenBondsOutDerivativeSafe.

---

## LOGIC-002: wrong_conditional_branch_chosen
- **Frequency**: ~7/50
- **Severity**: HIGH (5×), MEDIUM (2×)
- **Code Shape**:
  ```solidity
  // Fee subtracted in wrong branch (e.g., on expiry instead of exercise)
  if (isExpired) {
      _deductFee(amount);   // should only happen in the exercise branch
  }

  // State reset applied to wrong entity
  if (someCondition) {
      delete userRecord[wrongAddress];   // should be msg.sender, not a parameter
  }
  ```
- **Detection Heuristic**:
  1. Identify every `if/else` that routes to a side-effecting operation (fee deduction, burn, transfer, state reset).
  2. For each branch, manually trace: which user action leads here? Is that the correct triggering event?
  3. Confirm that the predicate is the right discriminant (e.g., "expired" vs "exercised" are mutually exclusive states).
  4. Verify that the subject of mutation (the address/struct being modified) is the correct one for the branch.
  5. Trace the alternative branch: confirm the symmetric operation also happens correctly.
- **Failure Mode**: Side effect (fee, burn, state change) fires for the wrong event, causing fund loss or state corruption for uninvolved parties.
- **Common Contexts**: options/put settlement (expire vs exercise), flash-governance asset locking/unlocking, queue-length computation, reward accrual.
- **Evidence**: [5] Fee on expiry not exercise (Putty); [14]/[17] burnFlashGovernanceAsset resets wrong user; [16] deal tokens burned for all fiat accounts; [8] incorrect queue length branch; [22] emergency resolver targets wrong epoch; [26] AVM owner resolution wrong branch.

---

## LOGIC-003: inverted_condition_negation
- **Frequency**: ~5/50
- **Severity**: HIGH (3×), MEDIUM (2×)
- **Code Shape**:
  ```solidity
  // Condition is negated when it should not be, or vice versa
  require(!isAllowed, "must not be allowed"); // should be require(isAllowed, ...)
  if (!flag) { doProtectedAction(); }         // should be if (flag)
  ```
- **Detection Heuristic**:
  1. For every `!` in a guard or conditional, confirm the intent by reading the surrounding context and NatDoc.
  2. Ask: "what happens when this flag/state is TRUE?" — verify the branch taken makes sense.
  3. Write a concrete counter-example: set flag=true and flag=false, trace the code for each.
  4. Look for `require(!condition)` patterns where `condition` sounds like a prerequisite for the action.
- **Failure Mode**: Logic is inverted — protected actions execute when they should be blocked, or benign actions are blocked when they should proceed.
- **Common Contexts**: cap checks, whitelist gates, modifier guards, rescue/admin functions, game-end conditions.
- **Evidence**: [2] endGame wrong logical check (Curio); [20] PARENT_CANNOT_CONTROL unwrap/rewrap bypass (ENS); [24] dead-hero recovery conflicting validation; [34] rescueTokens checks wrong condition for muteToken; [35] wrong conditions in mint (Fantium).

---

## LOGIC-004: off_by_one_in_cap_or_index_check
- **Frequency**: ~4/50
- **Severity**: HIGH (2×), MEDIUM (1×), LOW (1×)
- **Code Shape**:
  ```solidity
  // Cap intended to be inclusive but uses strict inequality
  require(total < cap);          // should be total + amount <= cap or total <= cap
  if (index < array.length - 1) // off-by-one in ring-buffer head/tail
  ```
- **Detection Heuristic**:
  1. Find every comparison against a limit variable (cap, maxStake, maxLength, arrayLength).
  2. Test the boundary: substitute `total = cap - 1`, `total = cap`, `total = cap + 1`.
  3. Verify whether the inclusive boundary is handled correctly.
  4. For ring/circular queues, also trace wrap-around scenarios.
- **Failure Mode**: Cap can be exceeded by exactly 1 unit, or a valid boundary value is incorrectly rejected/accepted, causing incorrect pool limits, incorrect queue-length reporting, or bypassed constraints.
- **Common Contexts**: staking pool caps, LP pool caps, ring/circular queue indices, deposit caps.
- **Evidence**: [0] set cap breaks vault balance (yAxis); [8] incorrect queue length (Elusiv ring queue); [30] insufficient staking cap logic (Blastoff); [44] lpPoolCap bypass (Megapot).

---

## LOGIC-005: wrong_variable_or_address_used_in_computation
- **Frequency**: ~5/50
- **Severity**: HIGH (3×), MEDIUM (2×)
- **Code Shape**:
  ```solidity
  // Uses a local copy or a different mapping key instead of the intended one
  uint256 refund = totalAmount * taxRate / BASE;   // should use netAmount, not totalAmount
  rewardShares[tokenA] -= amount;                  // should be tokenB after unlock
  mapping[wrongKey] = value;                        // copy-paste error on key
  ```
- **Detection Heuristic**:
  1. For each arithmetic expression, confirm every operand variable matches the semantic intent (gross vs net, pre-fee vs post-fee, shares vs assets).
  2. Check assignment targets in mappings: trace which key is constructed and whether it aligns with the conceptual entity being updated.
  3. Cross-reference variable names used in symmetric functions (deposit/withdraw, lock/unlock) — confirm both sides touch the same state variable.
  4. Look for "also found by N auditors" patterns: multiple finders often indicate a subtle but consequential wrong-variable substitution.
- **Failure Mode**: Calculations use incorrect inputs, producing wrong refunds, incorrect reward share accounting, or corruption of a different entity's state.
- **Common Contexts**: tax/fee refund calculations, reward share accounting after unlock, AVM/ownership resolution, constructor variable assignment.
- **Evidence**: [6] tax refund uses wrong amount (Zap Protocol); [7] total reward shares reach zero after unlock (GTE); [18] fee subtraction uses wrong variable (Tracer); [21] incorrect variable assignment in constructor (GaugeV2); [26] AVM owner resolution wrong variable.

---

## LOGIC-006: missing_or_skipped_operation_step
- **Frequency**: ~4/50
- **Severity**: HIGH (2×), MEDIUM (2×)
- **Code Shape**:
  ```solidity
  // Function that should perform two operations only performs one
  function openPositionFarm(...) external {
      _deposit(token, amount);
      // MISSING: joinPool(poolId, ...) — tokens deposited but never joined
  }

  function mint(shares) external {
      _mint(shares);
      // MISSING: updateIndex() or _burnAndMint() sync
  }
  ```
- **Detection Heuristic**:
  1. Read the protocol documentation/spec for what a function is supposed to accomplish end-to-end.
  2. Enumerate every expected sub-operation (transfer, deposit, join, sync, emit, burn/mint pair).
  3. Trace the actual function call graph: is any expected step absent?
  4. Check symmetric functions (open/close, deposit/withdraw): confirm complementary steps exist in both.
- **Failure Mode**: Partial execution leaves protocol in an inconsistent state — assets deposited but not deployed, tokens minted without corresponding burn, state updated without downstream notification.
- **Common Contexts**: farming position opening, LP join operations, mint/burn pairs, reward queuing.
- **Evidence**: [9] incorrect logic burning and minting tokens (PieDAO); [11] queueNewRewards transfers more than needed (Tokemak); [32] AuraSpell openPositionFarm doesn't join pool (Blueberry); [27] RToken mint/burn multiple errors.

---

## LOGIC-007: incorrect_loop_termination_or_iteration_logic
- **Frequency**: ~3/50
- **Severity**: HIGH (2×), MEDIUM (1×)
- **Code Shape**:
  ```solidity
  // Loop continues past the intended termination point
  while (batch.startIndex < batch.endIndex) {
      if (batch.burned) continue;   // should break, not continue
      // ... never removes burned batch, iterates forever or skips incorrectly
  }

  // Loop counts wrong because of misplaced increment/decrement
  for (uint i = 0; i < length; ) {
      total += arr[i];
      unchecked { i += 2; }   // should be i += 1
  }
  ```
- **Detection Heuristic**:
  1. For every loop, identify the termination condition and the mutation that drives toward it.
  2. Trace one iteration manually with a concrete example: does the mutation bring the loop closer to termination?
  3. Check `continue` vs `break` usage: `continue` restarts the loop body, `break` exits — confirm intent.
  4. For cleanup/removal loops, verify that the removal actually reduces the iteration scope.
- **Failure Mode**: Loop never terminates (DoS), skips entries that should be processed, or processes entries that should have been skipped; in cleanup scenarios, burned/invalid entries remain.
- **Common Contexts**: batch cleanup, queue traversal, index removal, while-loop with conditional breaks.
- **Evidence**: [19] incorrect logic in while loop removing burned batches (Realize); [29] unbond_public loop logic prevents partial withdrawals (ALEO); [12] getPegDeltaFrequency wrong loop implementation (Malt Finance).

---

## LOGIC-008: permission_check_targets_wrong_caller_or_role
- **Frequency**: ~3/50
- **Severity**: MEDIUM (3×)
- **Code Shape**:
  ```solidity
  // Modifier checks the wrong address or role
  modifier onlyAdminOrOperator() {
      require(admins[msg.sender] || msg.sender == owner());   // misses operators mapping
      _;
  }

  // Access control allows bypass through role overlap
  require(hasRole(ADMIN_ROLE, msg.sender) && hasRole(OPERATOR_ROLE, msg.sender));
      // should be ||
  ```
- **Detection Heuristic**:
  1. For every access-control modifier, enumerate the roles it is supposed to allow.
  2. Verify each role is checked against the correct mapping or role registry.
  3. Confirm boolean operators (`&&`/`||`) match the intended multi-role policy (AND = must have all, OR = any one suffices).
  4. Test with an address that holds only one of the intended roles: does it pass?
- **Failure Mode**: Legitimate callers (operators, admins) are incorrectly blocked, or unauthorized callers gain access because the check is too permissive or targets the wrong registry.
- **Common Contexts**: admin/operator modifiers, multi-role access functions, emergency resolvers, governance functions.
- **Evidence**: [28] onlyAdminOrOperator uses wrong logic (Realize); [31] lock update logic on secondary chains exploited (stake.link); [23] no way to revert setInvestorLiquidateOnly (one-way state toggle).

---

## LOGIC-009: irreversible_one_way_state_toggle
- **Frequency**: ~2/50
- **Severity**: MEDIUM (2×)
- **Code Shape**:
  ```solidity
  // State can only be set in one direction; no reset function provided
  function setInvestorLiquidateOnly(address investor) external onlyAdmin {
      liquidateOnly[investor] = true;
      // No corresponding unset function
  }

  // Flag set permanently without a way to clear it
  isEmergency = true;   // no setEmergency(false) path exists
  ```
- **Detection Heuristic**:
  1. For every function that sets a boolean or enum flag, search for a corresponding function that can reverse it.
  2. If none exists, determine whether the flag being permanent is intentional.
  3. Check NatDoc and specs: does the spec mention a reset/revocation path?
  4. Verify whether admin error scenarios (mistakenly flagging a user) are recoverable.
- **Failure Mode**: Admin mistakes cannot be corrected, users are permanently locked into restricted modes, or protocol cannot return to normal operation after emergency states.
- **Common Contexts**: investor/liquidation-mode flags, emergency toggles, whitelist entries, pause mechanisms.
- **Evidence**: [23] setInvestorLiquidateOnly cannot be reverted (Securitize); [24] dead-hero recovery conflicting validation makes recovery impossible (Onchainheroes).

---

## LOGIC-010: race_condition_via_shared_state_manipulation
- **Frequency**: ~3/50
- **Severity**: HIGH (3×)
- **Code Shape**:
  ```solidity
  // Attacker front-runs a pending deposit to mint tokens for themselves
  function mint(uint256 shares) external {
      uint256 assetsNeeded = convertToAssets(shares);
      // Assets already transferred by victim before mint() called
      _mint(msg.sender, shares);   // attacker calls with victim's deposited assets
  }

  // Voting boost not reset between epochs, allowing reuse
  uint256 boost = user.boost;   // stale boost carried over, never cleared
  ```
- **Detection Heuristic**:
  1. Identify functions that consume shared state (balances, deposited assets, boost state) that was created by a prior transaction.
  2. Ask: can a third party observe that pending state and call the consuming function before the legitimate user?
  3. Check whether state is cleared atomically after consumption, or whether it persists across calls.
  4. For voting/reward mechanisms, verify that per-epoch or per-period state resets occur.
- **Failure Mode**: Attacker hijacks assets deposited by victims; stale boost/reward state allows unlimited amplification across cooldown periods.
- **Common Contexts**: multi-step deposit→mint flows, ve-voting boosters, reward accrual, governance asset locking.
- **Evidence**: [4] IndexLogic attacker mints with other users' assets (Phuture); [1] ve voting unlimited boost / cooldown bypass (Alchemix); [14]/[17] burnFlashGovernanceAsset locked asset theft (Behodler).

---

## LOGIC-011: incorrect_frequency_or_counter_accumulation
- **Frequency**: ~2/50
- **Severity**: HIGH (2×)
- **Code Shape**:
  ```solidity
  // Accumulator counts events in the wrong direction or double-counts
  function getPegDeltaFrequency() public view returns (uint256) {
      uint256 freq = 0;
      for (uint i = 0; i < window; i++) {
          if (pegDelta[i] > 0) freq++;   // should count when < 0 (below peg)
      }
      return freq;   // wrong direction, triggers wrong auction logic
  }
  ```
- **Detection Heuristic**:
  1. Locate all counter/accumulator variables.
  2. Verify the increment condition: does it fire on the exact events the downstream consumer expects?
  3. Trace what the counter value is used for: does a higher count mean more or fewer events of type X?
  4. Run a concrete scenario: simulate 5 above-peg and 5 below-peg events; verify the counter value is correct.
- **Failure Mode**: Frequency/count is inverted or includes wrong events, causing downstream logic (auction sizing, liquidity extension, reward distribution) to behave inversely to design intent.
- **Common Contexts**: peg-stability mechanisms, auction frequency calculation, time-window event counting.
- **Evidence**: [12] getPegDeltaFrequency wrong counting direction (Malt Finance); [36] wrong condition in price calculation (Biconomy LiquidityProviders).

---

## LOGIC-012: debt_or_balance_reset_without_asset_recovery
- **Frequency**: ~2/50
- **Severity**: HIGH (2×)
- **Code Shape**:
  ```solidity
  // Debt reset to zero but collateral not seized; attacker keeps assets
  function redistribute(uint256 troveId) internal {
      troveDebt[troveId] = 0;    // debt wiped
      // yangs (collateral) NOT removed — attacker retains collateral
  }

  // Burn logic clears record for wrong set of accounts
  for (address acct : allFiatAccounts) {
      _burn(acct, dealTokens[acct]);   // burns for ALL, should only be redeemers
  }
  ```
- **Detection Heuristic**:
  1. Find every debt-reset or burn operation.
  2. Verify that the complementary asset movement (collateral seizure, token deduction) happens atomically in the same transaction.
  3. Check loop scope: if iterating over account sets, confirm the set is correctly scoped to affected parties only.
  4. Simulate the post-reset state: does the user retain assets they should have lost?
- **Failure Mode**: Protocol absorbs debt/loss while the borrower/attacker retains collateral or tokens, resulting in direct fund loss or theft.
- **Common Contexts**: liquidation/redistribution logic, trove/CDP debt mechanics, principal payout burn logic.
- **Evidence**: [10] Opus trove debt reset but yangs kept; [16] deal tokens burned for all fiat accounts (Tradable).

---

## LOGIC-013: transfer_amount_exceeds_intent_due_to_wrong_variable
- **Frequency**: ~2/50
- **Severity**: HIGH (2×)
- **Code Shape**:
  ```solidity
  // Transfers total queued amount instead of only the new addition
  function queueNewRewards(uint256 newRewards) external {
      uint256 toTransfer = newRewards + existingQueue;   // should be newRewards only
      token.transferFrom(msg.sender, address(this), toTransfer);
  }

  // Validation uses post-operation value instead of pre-operation value
  require(creditCapacity >= 0, "...");   // should check before applying delta
  ```
- **Detection Heuristic**:
  1. For every `transferFrom` call, confirm the amount argument represents only the incremental amount being added, not a cumulative total.
  2. Check whether any accumulated/running-total variable is mistakenly passed as the transfer amount.
  3. Verify ordering: is the capability/credit check performed before or after the state mutation that changes the variable?
- **Failure Mode**: Caller is charged for more tokens than intended; accumulated state is drained from the caller or the protocol accepts an over-capacity deposit.
- **Common Contexts**: reward queuing, deposit functions, credit-capacity validation in redemption flows.
- **Evidence**: [11] queueNewRewards over-charges caller (Tokemak); [13] credit capacity validation post-mutation (VaultRouterBranch).

---

## LOGIC-014: cross_chain_or_multi_instance_state_sync_exploit
- **Frequency**: ~2/50
- **Severity**: MEDIUM (2×)
- **Code Shape**:
  ```solidity
  // Secondary chain lock state can be manipulated independently from primary
  function updateLock(uint256 chainId, uint256 amount) external {
      lockState[chainId] = amount;   // no verification from primary chain
  }
  // Attacker submits inflated amount to secondary chain to increase reward allocation
  ```
- **Detection Heuristic**:
  1. Identify all cross-chain or cross-instance state writes.
  2. Verify that secondary/satellite chain state changes are gated by a message from the primary/authoritative chain.
  3. Check whether an attacker can call the secondary-chain update function directly without a primary-chain proof.
  4. Trace how the secondary-chain state influences reward or token distributions back to the primary chain.
- **Failure Mode**: Attacker inflates secondary-chain state (lock amounts, balances) to divert disproportionate rewards to a chain they control.
- **Common Contexts**: cross-chain staking/rewards bridges, multi-chain governance, secondary-chain lock accounting.
- **Evidence**: [31] stake.link lock update on secondary chains exploited; [38] lzCompose revert due to transfer() gas limit in cross-chain context.

---

## LOGIC-015: incorrect_credit_or_redemption_validation_ordering
- **Frequency**: ~2/50
- **Severity**: HIGH (2×)
- **Code Shape**:
  ```solidity
  // Validation check occurs after the state mutation that invalidates it
  function redeem(uint256 amount) external {
      vault.withdraw(amount);             // modifies creditCapacity
      require(creditCapacity >= 0, "insufficient credit");  // too late: already negative
  }
  ```
- **Detection Heuristic**:
  1. Enumerate all state-modifying functions with a post-condition check.
  2. Determine whether the check variable is modified earlier in the same function body.
  3. If yes, move the mental model: run the check on the pre-mutation value and verify intent.
  4. Check patterns: `withdraw → check`, `burn → check`, `deduct → require` — all are ordering risks.
- **Failure Mode**: The guard that should prevent an invalid operation runs after the damage is done; protocol ends up with locked or drained collateral.
- **Common Contexts**: vault redemption, collateral credit validation, borrow/repay sequences.
- **Evidence**: [13] VaultRouterBranch redeem credit check after withdrawal; [5] fee deducted on expiry branch rather than exercise branch (ordering of condition evaluation).

---

## LOGIC-016: missing_payable_on_value_receiving_function
- **Frequency**: ~1/50
- **Severity**: LOW (1×)
- **Code Shape**:
  ```solidity
  function executeBatch(Call[] calldata calls) external /* no payable */ {
      for (uint i = 0; i < calls.length; i++) {
          (bool ok,) = calls[i].target.call{value: calls[i].value}("");
          require(ok);
      }
  }
  // ETH sent with the outer call is rejected at the function boundary
  ```
- **Detection Heuristic**:
  1. Find all functions that forward or use `msg.value` or ETH internally.
  2. Verify the function declaration includes `payable`.
  3. Check batch/multi-call wrappers specifically: the outer wrapper must be `payable` if any inner call involves ETH.
- **Failure Mode**: Function reverts when called with ETH, making ETH-inclusive batch operations impossible.
- **Common Contexts**: batch executors, multi-call wrappers, meta-transaction relayers.
- **Evidence**: [41] executeBatch lacks payable (Alchemix).

---

## LOGIC-017: input_parsing_silent_failure_returns_zero
- **Frequency**: ~1/50
- **Severity**: LOW (1×)
- **Code Shape**:
  ```solidity
  function stringToUint(string memory s) internal pure returns (uint256) {
      if (bytes(s).length == 0) return 0;   // should revert on empty input
      // ...
  }
  // Caller receives 0 and treats it as valid parsed value
  ```
- **Detection Heuristic**:
  1. Find all input-parsing or conversion utilities (string→uint, bytes→address, etc.).
  2. Verify what happens on empty or malformed input: does the function revert or return a sentinel?
  3. Check every call site: does the caller validate the return value against the sentinel?
  4. Determine whether 0 (or the sentinel) is a valid value in the calling context — if so, the sentinel is ambiguous.
- **Failure Mode**: Invalid/empty input silently converts to 0, which may be interpreted as a valid value by downstream logic, causing incorrect behaviour without a revert signal.
- **Common Contexts**: on-chain string utilities, metadata parsers, user-supplied parameter decoding.
- **Evidence**: [48] stringToUint("") returns 0 instead of reverting (RegnumAurum).

---

## LOGIC-018: binary_search_or_index_lookup_wrong_boundary
- **Frequency**: ~2/50
- **Severity**: LOW (2×)
- **Code Shape**:
  ```solidity
  // getPriorBalanceIndex uses incorrect logic for boundary return
  function getPriorBalanceIndex(address account, uint256 blockNumber)
      external view returns (uint256) {
      uint256 nCheckpoints = numCheckpoints[account];
      if (nCheckpoints == 0) return 0;
      // Documentation says "return latest if blockNumber >= last checkpoint"
      // Implementation returns index instead of value, or uses wrong comparison
      if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber)
          return nCheckpoints - 1;   // off-by-one or semantically wrong
  }
  ```
- **Detection Heuristic**:
  1. For every binary search or checkpoint lookup, write the expected return value for: empty array, single-element array, blockNumber before first checkpoint, blockNumber after last checkpoint, blockNumber exactly equal to a checkpoint.
  2. Compare actual return values from the implementation against expected.
  3. Verify whether the function returns an INDEX or a VALUE — confirm callers expect the same.
  4. Cross-check NatDoc description with implementation.
- **Failure Mode**: Historical balance lookups return incorrect indices or values, corrupting gauge voting calculations, reward snapshots, or any checkpoint-based accounting.
- **Common Contexts**: Gauge checkpoints, governance vote-weight lookups, ERC20 snapshot balances.
- **Evidence**: [46]/[47] getPriorBalanceIndex incorrect logic and documentation (KittenSwap Gauge).

---

## Notes on Non-Pattern Entries
The following findings were categorised as quality/tooling issues rather than distinct logic error patterns; they are noted for completeness but not assigned separate pattern IDs:
- [40]/[42]/[43] — Insufficient test coverage (informational quality issue, not a logic error pattern).
- [45] — Use of `public` instead of `external` (gas optimisation, not logic error).
- [38] — `transfer()` gas limit causing cross-chain revert (interaction-hazard variant of LOGIC-014, counted there).
