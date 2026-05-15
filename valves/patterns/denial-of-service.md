# Denial of Service Patterns
> Extracted from 3,071 findings (500 sampled)
> Pattern count: 30

---

## DOS-001: unbounded_loop_gas_exhaustion
- **Frequency**: ~52/500
- **Severity**: HIGH
- **Code Shape**: `for (uint i = 0; i < array.length; i++) { ... }` where `array` is an unbounded storage array (delegations, positions, locks, rewards, NFTs) iterated on every user call or in a state-transition function
- **Detection Heuristic**:
  1. Grep for `for` loops where the bound is a `.length` call on a storage array, mapping key-set, or linked list
  2. Confirm the array can be grown by any user or third party (no cap enforced)
  3. Confirm the loop body performs storage reads/writes, external calls, or complex computation per iteration
  4. Estimate worst-case gas: `N × cost_per_iter > block_gas_limit` at plausible N
  5. Check whether any removal mechanism shrinks the array; if absent or asymmetric, confirm finding
- **Failure Mode**: When the array reaches sufficient length, the gas cost of the loop exceeds the block gas limit, permanently reverting every call to that function; affected funds/rewards become permanently inaccessible
- **Common Contexts**: VotingEscrow delegate arrays (`MAX_DELEGATES`), staking position lists (`positionIdList`), reward distribution (`claimReward` over all user predictions), withdrawal queues, liquidity tick arrays, governance voter arrays, NFT holder arrays, orderbook linked lists, per-user lock history

---

## DOS-002: push_payment_revert_grief
- **Frequency**: ~38/500
- **Severity**: HIGH
- **Code Shape**: `recipient.call{value: amount}("")` or `token.transfer(recipient, amount)` inside a loop or queue-processing function with no pull-based fallback; a single failing transfer aborts the entire batch
- **Detection Heuristic**:
  1. Locate functions that iterate over a list of recipients and push ETH or tokens to each
  2. Check whether a revert from one transfer causes the enclosing transaction to revert (no try/catch, no skip-on-fail)
  3. Identify whether any recipient address is attacker-controlled or can be a contract with a reverting `receive()`/`fallback()`
  4. Confirm there is no pull-withdrawal fallback for failed transfers
  5. If one reverting recipient blocks all others, confirm finding
- **Failure Mode**: Attacker places a reverting contract as one of many recipients; the entire distribution (auction claim, reward payout, fund return) reverts permanently, locking funds for all parties
- **Common Contexts**: Auction bid-return loops (`claimAuction`), multi-recipient reward distribution, ETH unstaking fulfillment, batch bond distribution, escrow settlement, cross-chain message delivery callbacks

---

## DOS-003: blacklisted_token_holder_blocking
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: `IERC20(token).transfer(user, amount)` inside a shared-path function (withdraw, distribute, liquidate) where `user` may be blacklisted by a compliance-enforcing token (USDC, USDT)
- **Detection Heuristic**:
  1. Identify all functions that push tokens (especially USDC/USDT/regulated ERC-20) to caller-controlled addresses
  2. Confirm that a revert from `transfer` propagates to abort the outer function
  3. Check whether the token is a blacklistable type (USDC, USDT have `blacklist` function)
  4. Confirm there is no per-user isolation (pull pattern, wrapped accounting)
  5. Determine whether the blocked user's position can prevent other users from withdrawing
- **Failure Mode**: A blacklisted user (or attacker who engineers a blacklisting) makes any shared exit path revert; the entire queue or pool becomes locked; liquidations, withdrawals, and reward claims all fail for all users
- **Common Contexts**: Order-book settlement (CLOBER), lending liquidation, reward withdrawal queues, staking exit paths, collateral-return on repayment

---

## DOS-004: array_inflation_by_attacker
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: `array.push(item)` in a permissionless or low-cost function with no upper-bound check; the array is later iterated in a state-critical path
- **Detection Heuristic**:
  1. Find `push` operations on storage arrays callable by arbitrary users
  2. Confirm no maximum-length guard (e.g., `require(array.length < MAX)`) exists
  3. Trace where that array is read in loops (especially in reward claim, liquidation, or withdrawal logic)
  4. Estimate the cost to inflate the array to unusable size relative to attacker profit/loss
  5. Confirm no clean-up mechanism prevents regrowth
- **Failure Mode**: Attacker cheaply inflates an array (e.g., by spamming dust deposits, positions, lock items, or NFT transfers) until the looping function exceeds block gas; legitimate users can no longer claim rewards or withdraw
- **Common Contexts**: dMute lock arrays, position NFT spam (Ajna), tick-tracking arrays (Canto), proceeds arrays (Gondi), delegation arrays, deposit queues, NFT holder arrays

---

## DOS-005: division_by_zero_state_corruption
- **Frequency**: ~15/500
- **Severity**: HIGH
- **Code Shape**: `amount / denominator` where `denominator` is a state variable that can be driven to zero by user action (e.g., total supply, total liquidity, share count) without a zero-guard
- **Detection Heuristic**:
  1. Grep for division operations (`/`, `divWadDown`, `mulDiv`) in state-critical paths
  2. Trace each divisor to its source; check whether it can reach zero through legitimate protocol operations (full withdrawal, donation, rounding)
  3. Check for `require(denominator != 0)` or equivalent guard
  4. Verify attacker can trigger the zero state at low cost (e.g., dust donation, first depositor attack)
  5. Confirm the function is called frequently and its revert blocks core functionality
- **Failure Mode**: Protocol enters a permanently broken state where all operations revert on division-by-zero; funds are locked inside the contract with no recovery path
- **Common Contexts**: KangarooVault share math, auction reward computation (Nouns Builder), share-per-token calculations, AMM liquidity math, fee distribution, PRST liquid-stake share conversion

---

## DOS-006: front_run_initialization_grief
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `function initialize(...) external` (not `initializer` guarded) deployed via a predictable address (CREATE2, deterministic factory) that can be called by anyone before the legitimate deployer
- **Detection Heuristic**:
  1. Find `initialize` functions without `initializer` modifier from OpenZeppelin Initializable or equivalent single-call guard
  2. Check whether contract address is predictable (CREATE2, factory with deterministic salt, proxy)
  3. Confirm that a successful attacker-controlled initialization permanently bricks the contract (wrong owner, wrong parameters, wrong state)
  4. Check whether a re-initialization path exists (usually absent by design)
  5. If no re-deployment or re-initialization is possible, confirm permanent DoS
- **Failure Mode**: Attacker calls `initialize` before the deployer, setting malicious parameters (zero fee recipient, attacker-owned admin); the legitimate system can never be initialized; protocol is dead on arrival
- **Common Contexts**: Proxy contract initialization (Notional, NoteERC20), token initialization, bridge initialization, vault factory deployment

---

## DOS-007: gas_limit_miscalculation_cross_chain
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain message dispatch that hardcodes or underestimates gas: `lzSend{value: fee}(dstChainId, payload, refundAddr, address(0), adapterParams, value)` where `adapterParams` encodes insufficient gas for the destination execution
- **Detection Heuristic**:
  1. Identify all cross-chain message sends (LayerZero, Wormhole, Axelar, IBC, AnyCall, Stargate)
  2. Check how the destination gas limit is computed (hardcoded constant, caller-supplied, formula)
  3. Compare the estimate against worst-case execution cost on the destination (with dynamic gas prices, large payload, complex logic)
  4. Confirm whether a failed destination execution is retryable or channels/queues are permanently blocked
  5. Check for `MIN_FALLBACK_RESERVE` / gas-buffer patterns and whether they account for actual overhead
- **Failure Mode**: Destination call runs out of gas, fails silently or permanently blocks the channel; bridged assets become stuck; the cross-chain path cannot be used again (LayerZero non-retryable failure)
- **Common Contexts**: LayerZero OFT (UXD, Velodrome, Connext), AnyCall (Maia DAO), IBC (Datachain), Holograph operator job execution, bridge relay gas estimation

---

## DOS-008: rebase_token_transfer_off_by_one
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `require(IERC20(rebaseToken).transferFrom(msg.sender, address(this), amount))` followed by internal accounting assuming exactly `amount` received; rebase tokens (stETH, aTokens) deliver `amount - 1` or `amount - 2` wei
- **Detection Heuristic**:
  1. Identify protocols integrating rebasing or fee-on-transfer tokens (stETH, wstETH, aTokens, elastic supply tokens)
  2. Locate functions that record the nominal transfer amount without checking actual received balance (`balanceAfter - balanceBefore`)
  3. Find downstream functions that expect the full nominal amount and revert if balance falls short
  4. Verify that the 1-2 wei discrepancy is sufficient to trigger the revert path
  5. Confirm this is systematically reproducible (not a one-off rounding)
- **Failure Mode**: Every withdrawal or transfer fails because the contract records N tokens but holds N-1 or N-2; `_initiateWithdrawImpl` always reverts; users permanently cannot exit
- **Common Contexts**: Notional Leveraged Vaults (EtherFi, Kelp), stETH-integrated lending, Sophon farming with stETH

---

## DOS-009: queue_desync_permanent_blockage
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Withdrawal or processing queue where head/tail pointers, `lastFinalizedRequestId`, or batch indices become mismatched; often caused by a cancel/fulfill function that updates one side of the accounting but not the other
- **Detection Heuristic**:
  1. Identify queue-based withdrawal or redemption systems (request IDs, epoch counters, linked lists)
  2. Find all state-modifying paths that touch queue indices: enqueue, cancel, fulfill, finalize, skip
  3. For each path check that ALL related accounting variables are updated atomically
  4. Look for cancel flows that remove an item but leave the queue pointer pointing past it
  5. Confirm that a desync causes subsequent `processWithdrawal` / `claimWithdraw` to always revert
- **Failure Mode**: Queue pointer skips over valid requests or points to deleted entries; the entire queue processing loop reverts permanently; all pending withdrawals are frozen
- **Common Contexts**: Withdrawal queues (Hubble Exchange, EEtherAdapter), burn-withdrawal-ticket processing (Jito Restaking), fulfillCancelRedeemRequest (Accountable), KangarooVault QueuedWithdraw

---

## DOS-010: single_reverting_item_in_batch
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: `for (uint i = 0; i < queue.length; i++) { processItem(queue[i]); }` where any item's processing can revert (e.g., external call, zero check, underflow) and there is no per-item error handling
- **Detection Heuristic**:
  1. Find batch-processing or queue-draining loops that execute each item's full logic inside the loop body
  2. Check whether any individual item's logic can revert (missing balance, external call failure, arithmetic underflow)
  3. Confirm that a revert inside the loop propagates to abort the entire batch (no try/catch per item)
  4. Determine whether the reverting item can be injected or caused by an attacker (e.g., a withdrawal with a bad callback address)
  5. Confirm the queue cannot be drained by skipping the bad item
- **Failure Mode**: One crafted or naturally occurring bad item permanently stalls the queue; all subsequent items (from legitimate users) are blocked until the bad item is removed, which may not be possible
- **Common Contexts**: BasisTradeVault withdrawal queue, processWithdrawals (Hubble Exchange), batch release, distribution loops, Liquiditypool QueuedWithdrawals (Polynomial)

---

## DOS-011: unbounded_loop_in_node_consensus
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: Cosmos SDK `EndBlocker` / `BeginBlocker` or equivalent node-side code that iterates over an unbounded collection (reward plans, undelegations, validators, reputer payloads) per block
- **Detection Heuristic**:
  1. Identify `EndBlocker`/`BeginBlocker` hooks and other per-block execution paths in Cosmos/IBC modules
  2. Find any linear iteration over a collection (`for _, item := range store.GetAll(...)`) without a configurable batch limit
  3. Confirm the collection can grow unboundedly through permissionless transactions
  4. Estimate when iteration time or gas exceeds block timeout (consensus halt threshold)
  5. Check for metering or per-block limits; if absent, confirm finding
- **Failure Mode**: When the collection grows large enough, block processing takes too long or uses too much gas, halting consensus entirely; the chain stops producing blocks permanently
- **Common Contexts**: MilkyWay (undelegation iteration, reward plans), Allora (InsertBulkReputerPayload), Velodrome (MAX_DELEGATES = 1024), MANTRA (farm manager loop), Connext RootManager (inbound roots)

---

## DOS-012: improper_input_validation_node_crash
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Off-chain node code (Go, Rust, C++) that processes user-supplied binary data (JSON, EVM transaction, WASM, protobuf) without length/type bounds, causing panic or crash on malformed input
- **Detection Heuristic**:
  1. Identify node-side message handlers that deserialize user-supplied data (JSON-RPC, P2P message, transaction payload)
  2. Look for array accesses without bounds checks, integer type casts that can overflow, `unwrap()`/`expect()` calls on user-controlled data in Rust
  3. In Go, look for nil pointer dereference on fields from unvalidated structs
  4. Confirm the handler runs in the critical path (per-block, per-transaction) without crash isolation
  5. If a single malformed packet can crash the node process, confirm chain-halt severity
- **Failure Mode**: A single crafted transaction or message crashes the node process; on a Cosmos chain this halts the entire chain; on a P2P network this takes validators offline one by one
- **Common Contexts**: Shardeum (fixDeserializedWrappedEVMAccount, repair_oos_accounts, safeJsonParse), SEDA (verifyBatchSignatures, bn254.DeserializeG1), EigenDA (getBlobFromRequest, DisperseBlobAuthenticated), Berachain BeaconKit

---

## DOS-013: fee_underpricing_resource_drain
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Transaction or operation whose gas/fee is computed by a formula that does not account for all computational work; attacker constructs maximally expensive operations at near-zero cost
- **Detection Heuristic**:
  1. Identify fee-computation functions for user-submitted operations (WASM execution, split transactions, access list, calldata)
  2. Determine the actual computational cost of the most expensive valid operation
  3. Compare against the fee charged for that operation; check for missing cost components
  4. Confirm a user can repeatedly submit maximally expensive operations at near-zero out-of-pocket cost
  5. Estimate the resource exhaustion timeline on validators
- **Failure Mode**: Attackers submit cheap but computationally expensive operations, exhausting validator CPU/memory/bandwidth; block times increase until consensus halts; legitimate transactions are crowded out
- **Common Contexts**: SEDA (WASM instruction gas pricing, request gas_price = 1), Aleo (split proof fees), Initia (intrinsic gas costs, precompile gas on error), Optimism (nuisance gas), Monad (txpool affordability checks, EIP-7623 data floor gas)

---

## DOS-014: reentrancy_state_corruption_dos
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: External call before state update in a function that modifies an array or counter; attacker uses callback (onERC721Received, receive(), onFlashLoan) to re-enter and corrupt the state, leaving the contract in a stuck configuration
- **Detection Heuristic**:
  1. Find functions that make external calls (token transfer, ETH send, ERC721 callback) before completing all state updates (CEI violation)
  2. Identify whether the external call recipient is attacker-controlled (NFT owner, token holder, flash loan initiator)
  3. Confirm that re-entering the function or a related function during the callback corrupts shared state (wrong share count, duplicate entries, pointer corruption)
  4. Verify the corruption persists after the transaction, not just within it
  5. Check whether the corrupted state blocks future calls (not just over-claims)
- **Failure Mode**: Share counts, token configs, or accounting variables are corrupted in a way that causes future calls to always revert or produce wrong results; vault/lending protocol becomes permanently unusable
- **Common Contexts**: Revert Lend (onERC721Received share manipulation), Visor (_removeNft unbounded loop via callback), PartyDAO (voting power front-run), DXdao withdrawTokens

---

## DOS-015: oracle_staleness_misconfiguration
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `require(block.timestamp - lastUpdate <= STALENESS_PERIOD)` where `STALENESS_PERIOD` is a single value applied to all feeds, but some feeds update less frequently (e.g., illiquid asset oracles update hourly, not every minute)
- **Detection Heuristic**:
  1. Find oracle-freshness checks and extract the staleness threshold constant
  2. List all price feeds used by the protocol and their typical update frequencies
  3. Identify any feed whose update interval is larger than the staleness threshold
  4. Confirm that when that feed fails to update within the threshold, all oracle-dependent operations revert
  5. Check whether markets can close or oracles go offline predictably (weekends, low-volume periods)
- **Failure Mode**: A single misconfigured staleness period causes all price-feed reads to revert during periods when a slower feed does not update; liquidations, borrows, and swaps are all frozen until the feed updates
- **Common Contexts**: CAP Labs (single staleness period for all feeds), GainsNetwork oracle during market closures, Morpho P2P rate lazy snapshot

---

## DOS-016: donation_invariant_break
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `token.balanceOf(address(this))` used as the source of truth for internal accounting; attacker sends tokens directly (not through the protocol's deposit path) to shift the balance, triggering `require` failures or division-by-zero in subsequent accounting
- **Detection Heuristic**:
  1. Find contracts that use `token.balanceOf(address(this))` for accounting rather than internal balance trackers
  2. Identify functions where this balance feeds into division, ratio computation, or invariant checks
  3. Confirm that sending tokens directly to the contract (without calling the deposit function) shifts the balance in a way that breaks the invariant
  4. Check whether the invariant check is in a path called before every user operation (not just on settlement)
  5. Assess whether the attack cost (donated amount) is recoverable
- **Failure Mode**: Direct token/ETH donation shifts the internal price/ratio/balance invariant; all subsequent buys, sells, mints, or redemptions fail their sanity checks; the market is frozen
- **Common Contexts**: MarketMaker donation freeze (Ubet), bonding curve SOL escrow (PumpScience), AMM sqrt price manipulation, StUSR inflation attack, WETHGateway griefing (Lenft), Morpho LTV=0 collateral attack

---

## DOS-017: access_control_griefing
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: `function criticalOperation() external` without `onlyOwner` / `onlyRole` modifier; any caller can invoke it to reset, cancel, or corrupt protocol state at will
- **Detection Heuristic**:
  1. Identify functions that modify critical state (acceptanceDelay, fee parameters, pool active status, validator keys, curve configurations, delegate arrays)
  2. Check for missing access control modifiers (`onlyOwner`, `onlyRole`, `require(msg.sender == admin)`)
  3. Confirm that the function can be called by any external account (EOA or contract)
  4. Determine whether repeated or single unauthorized calls permanently disrupt protocol operation
  5. Assess whether the attacker gains financially or only griefs
- **Failure Mode**: Unauthorized caller repeatedly invokes the function to reset state, cancel proposals, overwrite configurations, or front-run legitimate operations; protocol is griefed into non-function with zero cost to attacker
- **Common Contexts**: RFPSimpleStrategy.setPoolActive (Allo V2), AcceptanceDelay (Connext), BoostController.updateUserBoost, setCurves (Curves Protocol), CLGaugeFactory (KittenSwap), FeeController setters (Octodefi), BatchRequests.removeAddress

---

## DOS-018: lock_extension_grief
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `function lockOnBehalf(address target, uint256 duration) external` that extends target's lock period without target's consent; any caller can repeatedly call to keep the lock perpetually extended
- **Detection Heuristic**:
  1. Find functions that modify another user's lock state and accept an arbitrary `target` address
  2. Confirm there is no approval or consent mechanism (`require(msg.sender == target || approved[target][msg.sender])`)
  3. Verify the function can extend (not just set) the lock duration, enabling repeated calls
  4. Confirm the victim cannot withdraw while the lock is active
  5. Assess the cost to the attacker (often near-zero gas cost per extension)
- **Failure Mode**: Attacker calls `lockOnBehalf` in a loop (possibly automated) to keep a victim's funds locked indefinitely; victim cannot withdraw previously locked tokens as long as the attacker continues griefing
- **Common Contexts**: Munchables (lockOnBehalf), timestamp-extension patterns in veToken protocols

---

## DOS-019: wasm_resource_exhaustion
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: WASM module execution environment that does not cap memory allocation, stdout/stderr output size, or execution time; a crafted WASM program can exhaust node resources
- **Detection Heuristic**:
  1. Identify WASM execution environments run by validators or nodes (e.g., SEDA Tally VM, CosmWasm, Arbitrum Stylus, Elys Modules)
  2. Check whether memory limits, output size caps, and execution timeouts are enforced
  3. Look for WASM imports that can panic the host (`call_result_write`, `panic!` in WASM, unbounded `malloc`)
  4. Confirm that a malicious WASM binary can be submitted by any participant at low cost
  5. Test whether panicking or OOM-ing the WASM runtime crashes the validator process
- **Failure Mode**: A malicious WASM program exhausts validator memory or crashes the WASM runtime; affected validators drop out of consensus; if enough validators are hit simultaneously, chain halts
- **Common Contexts**: SEDA Protocol (stdout/stderr unbounded, call_result_write panic), Elys (large WASM files), CosmWasm (memory exhaustion), Arbitrum Stylus

---

## DOS-020: rate_limiter_abuse
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `require(currentEpochVolume + amount <= epochLimit)` style rate limiter on deposit/withdrawal; an attacker makes many small transactions to fill the epoch limit, blocking legitimate large transfers for the epoch duration
- **Detection Heuristic**:
  1. Find rate-limiting checks on bridge, deposit, or withdrawal functions (epoch volume limits, per-block limits)
  2. Confirm that an attacker can fill the limit with dust transactions at low cost
  3. Check whether the limit resets automatically (per epoch/block) or requires admin action
  4. Determine whether the attacker loses money (e.g., pays fees for each dust tx) or profits (e.g., MEV)
  5. Confirm legitimate large transfers are blocked for the duration of the limit period
- **Failure Mode**: Attacker saturates the epoch deposit/withdrawal limit with many small transactions; legitimate users attempting to bridge large amounts are rejected for the entire epoch; attacker can sustain this cheaply each epoch
- **Common Contexts**: Ondo Finance (MONO rate limits), Linea Bridge (rate limiters), Scroll rate limiter, bridge volume limits

---

## DOS-021: incorrect_linked_list_management
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Doubly/singly linked list where insert/remove operations fail to update `prevOrderId`/`nextOrderId`/`head`/`tail` atomically; a single malformed insertion breaks list traversal for all subsequent operations
- **Detection Heuristic**:
  1. Find linked-list data structures (order books, maturity lists, delegation chains)
  2. For each insert/remove operation, verify that both `prev` and `next` pointers are updated
  3. Check for edge cases: inserting at head, inserting at tail, removing the only element, inserting with a duplicate key
  4. Confirm whether a broken list causes all traversals to revert (infinite loop, wrong element accessed, OOB access)
  5. Assess whether the breakage is permanent (no repair function)
- **Failure Mode**: A single insertion with a boundary-condition edge case corrupts the list structure; all subsequent list traversals enter an infinite loop or access wrong elements; entire order book or maturity schedule is permanently broken
- **Common Contexts**: Term Structure (maturity = _recentestMaturity), GTE (order prevOrderId not persisted), Passage (autoMatch no-next-node), NFTFloorOracle feeder array corruption (ParaSpace)

---

## DOS-022: integer_overflow_underflow_dos
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Arithmetic operation on a value derived from user input or accumulated state that overflows/underflows without Solidity 0.8 overflow protection (pre-0.8) or with unchecked blocks; causes revert or wraps to corrupt state
- **Detection Heuristic**:
  1. Identify arithmetic in `unchecked` blocks or Solidity < 0.8 that operates on user-controlled quantities
  2. Check for subtraction of two values where the subtrahend can exceed the minuend (underflow in balance tracking, reward delta)
  3. Look for multiplication of large accumulator values that can overflow uint256
  4. Confirm the overflow/underflow causes a revert (in Solidity 0.8 without unchecked) blocking normal operation, or wraps to produce an absurdly large value that breaks downstream logic
  5. Verify the triggering condition is reachable by a normal user
- **Failure Mode**: A transaction causes arithmetic overflow/underflow; in post-0.8 code this reverts the call, permanently blocking the function if the corrupt state is written before the overflow point; in pre-0.8 it wraps, corrupting state
- **Common Contexts**: Archimedes Finance (createLeveragedPosition underflow), MagicSea (overflow blocking votes), FluidLocker (540 instead of 540 days), Passage (PARTIAL MATCH underflow), Render Network incentive overflow

---

## DOS-023: front_run_task_submission_grief
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `function submitTask(bytes32 merkleRoot) external` or similar permissionless submission function that uses the submitted value as a unique key; attacker front-runs with same or conflicting value to invalidate the legitimate submission
- **Detection Heuristic**:
  1. Find functions that accept user-submitted commitments, task hashes, or Merkle roots that are stored as unique keys
  2. Check whether the key includes `msg.sender` or a nonce (if not, collisions are possible)
  3. Confirm that a front-runner submitting the same key blocks the legitimate caller (duplicate key rejected or state overwritten)
  4. Verify the attacker can systematically monitor the mempool and front-run every legitimate submission
  5. Assess whether the griefed submission can be resubmitted with a new key
- **Failure Mode**: Every legitimate batch root / task submission is front-run by the attacker; the system can never advance to the next state; relayers/provers are permanently blocked from finalizing
- **Common Contexts**: Aligned Layer (createNewTask front-run), Arbitrum challenge protocol (validator front-run), Tessera OptimisticListing low-cost DoS, Winnables (cancelRaffle before admin starts)

---

## DOS-024: layerzero_channel_block
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `lzReceive` execution path that can revert (missing interface implementation, bad data, OOG) with no stored procedure, leaving the LayerZero channel in a permanently blocked state that prevents all subsequent messages
- **Detection Heuristic**:
  1. Find all `lzReceive` / `sgReceive` / cross-chain message handler functions
  2. Check whether the handler can revert on attacker-controlled input (malformed payload, large `_toAddress`, bad calldata)
  3. Confirm whether LayerZero (or the relevant bridge) blocks the channel on failed delivery (default behavior: yes, unless retry or non-blocking mode is used)
  4. Check whether retry / non-blocking adapter patterns are used to skip failed messages
  5. Verify attacker cost to permanently block the channel is low
- **Failure Mode**: Attacker sends a crafted cross-chain message that causes `lzReceive` to revert; the LayerZero channel is permanently blocked; all subsequent legitimate messages in the queue are also blocked; bridge becomes unusable
- **Common Contexts**: Velodrome (lzReceive channel block), UXD Protocol (large _toAddress), Wormhole NTT (transceiver instruction ordering, config modification), IBC Datachain (gas limit difference between chains)

---

## DOS-025: no_rate_limiting_on_rpc_or_server
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Public API endpoint (JSON-RPC `eth_getLogs`, gRPC server, in3-server, P2P handler) that accepts unbounded query parameters or request size without rate limiting or input size caps
- **Detection Heuristic**:
  1. Review public-facing API endpoints for absence of rate limiting middleware
  2. Check input parameters that control response size: `FilterCriteria.Addresses` (unbounded), `blockRange`, `limit` fields
  3. Confirm the endpoint performs expensive work proportional to input size (DB queries, computation)
  4. Assess whether requests require authentication or payment (if not, cost to attacker is near-zero)
  5. Confirm a single request or sustained flood can degrade service for all users
- **Failure Mode**: Unauthenticated attackers send large or frequent requests that consume all server CPU/memory/bandwidth; legitimate users receive timeout errors; node operators must take the service offline
- **Common Contexts**: Initia JSON-RPC (FilterCriteria.Addresses), EigenDA (dispersal stream exhaustion), NuCypher (no rate limiting), Slock.it Incubed3 (sign requests), ChainPro (gRPC malformed data), SEDA (commit/reveal flood)

---

## DOS-026: gas_buffer_insufficient_cross_message
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `MIN_FALLBACK_RESERVE` or similar constant gas buffer added before a cross-contract or cross-chain call, computed without accounting for actual overhead (calldata cost, opcode changes, AnyCall overhead)
- **Detection Heuristic**:
  1. Find gas-forwarding patterns (`gasleft() - BUFFER`) in bridge and relay code
  2. Extract the buffer constant and compare against actual gas consumed by the destination call in worst case
  3. Check whether EIP-1559 base fee, calldata floor gas (EIP-7623), or AnyCall overhead is excluded from the buffer
  4. Confirm that a malicious relayer can set the gas limit to `minRequired - 1` causing the target to OOG
  5. Verify the transaction does not revert atomically (allowing retry) but silently fails, losing funds
- **Failure Mode**: Destination call consistently runs out of gas with the computed minimum; relayers can intentionally fail XMsgs by providing just below the minimum; bridged assets are lost or channels are silently blocked
- **Common Contexts**: Omni Network (gas buffer before external call), Maia DAO (MIN_FALLBACK_RESERVE, gas unit calculation), Holograph (gas limit check inaccuracy), Linea Plonk Verifier (staticcall gas)

---

## DOS-027: storage_layout_instance_vs_persistent
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Soroban/CosmWasm contract using instance/temporary storage (evictable) for data that should persist; when storage is evicted due to low rent balance, the contract becomes permanently inaccessible
- **Detection Heuristic**:
  1. In Soroban contracts, find `env.storage().instance().set(...)` or `env.storage().temporary().set(...)` calls for data that must survive across many transactions
  2. Verify that the stored data includes critical state (all token pairs, user balances, configuration)
  3. Check whether the contract has a rent-renewal mechanism that keeps instance storage alive
  4. Confirm that eviction of instance storage causes all subsequent reads to return default values or panic
  5. Assess whether an adversary can deliberately fail to pay rent to evict competitor's data
- **Failure Mode**: Instance storage holding all protocol data (token pairs, liquidity positions) is evicted due to insufficient rent; the contract returns empty results or panics on all reads; the protocol is permanently unusable unless state is recovered from off-chain sources
- **Common Contexts**: Soroswap (all token pairs in instance storage), Soroban dexes and vaults

---

## DOS-028: proposal_bond_lock_on_upgrade
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Governance system where proposal bonds or dispute collateral are held by a contract address that becomes invalid or upgradeable mid-flight; an upgrade changes the address or logic, making the bonded funds permanently unclaimable
- **Detection Heuristic**:
  1. Identify governance or challenge systems where users deposit bonds tied to a specific contract address
  2. Verify that the bond-holding contract can be upgraded or replaced while bonds are in flight
  3. Check whether the old contract retains funds and whether a migration path transfers them
  4. Confirm that the new contract (or new address) cannot release bonds held by the old contract
  5. Assess whether this affects all in-flight bonds simultaneously (systemic) or only concurrent proposals
- **Failure Mode**: A protocol upgrade during an active proposal leaves all proposer/challenger bonds locked in the old contract with no release mechanism; affected users permanently lose their collateral
- **Common Contexts**: Rocketpool (proposal bond lock on upgrade), Augur (dispute bonds in forking universe), Rocketpool DAO challenge process

---

## DOS-029: dust_deposit_grief_queue
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Deposit or commitment queue processed in FIFO order where an attacker can insert many dust entries (often on behalf of a victim) that must be processed before reaching legitimate entries
- **Detection Heuristic**:
  1. Find functions that allow depositing on behalf of another address (`depositFor(address victim, amount)`)
  2. Confirm there is no minimum deposit amount or per-address deposit cap
  3. Verify the queue is processed sequentially (later entries blocked until earlier ones clear)
  4. Estimate attacker cost to fill the queue with enough entries to prevent legitimate processing within a reasonable timeframe
  5. Check whether the victim can skip or cancel attacker-inserted entries
- **Failure Mode**: Attacker creates thousands of dust deposits targeting a victim; victim's legitimate operations are delayed indefinitely as the queue must drain in order; in some cases the victim pays gas for each dust withdrawal
- **Common Contexts**: Starter (many small deposits on behalf of victim), Tracer (Leveraged Pool multiple commits), Opyn Crab Netting (many deposits/withdraws then removal), Y2K (rollover queue griefing)

---

## DOS-030: token_factory_malicious_denom_lock
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Cosmos `x/tokenfactory` module where LP reward tokens can be set to attacker-created denoms; when the contract tries to send or receive these custom denoms, the transfer fails or applies attacker-controlled `BeforeSend` hooks that revert
- **Detection Heuristic**:
  1. Find protocols that accept arbitrary token denoms for rewards or LP tokens (Cosmos-based DEXes)
  2. Check whether the denom can be a `x/tokenfactory` denom with a custom `BeforeSendHook` registered
  3. Verify that the hook can revert the transfer (e.g., always revert, block certain addresses)
  4. Confirm this causes the reward distribution or pool interaction to permanently fail
  5. Assess whether the attacker needs any special permission to create the malicious denom
- **Failure Mode**: Attacker creates a tokenfactory denom with a malicious `BeforeSendHook` that always reverts; sets it as a reward token for a gauge or pool; all future reward distributions fail; rewards are permanently locked
- **Common Contexts**: MANTRA (x/tokenfactory denom rewards stuck), MANTRA (BlockBeforeSend hook exploit), Cosmos-based DEXes accepting arbitrary reward tokens
