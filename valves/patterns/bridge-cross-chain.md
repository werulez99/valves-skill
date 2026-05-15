# Bridge & Cross-Chain Patterns
> Extracted from 2,634 findings (500 sampled)
> Pattern count: 42

---

## BRIDGE-001: cross_chain_signature_replay
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: `ecrecover(hash, v, r, s)` or `ECDSA.recover(hash, sig)` where `hash` does not include `block.chainid`, `address(this)`, or expiry/deadline. User-supplied `domainSeparator`. No nonce binding to chain.
- **Detection Heuristic**:
  1. Grep for `ecrecover` / `ECDSA.recover` / `isValidSignature` in bridge/settlement contracts.
  2. For each call, check what fields are hashed: confirm `chainId` AND `contractAddress` AND `nonce` are all present.
  3. Check whether `domainSeparator` is caller-supplied vs. protocol-computed.
  4. If EIP-712: verify `DOMAIN_SEPARATOR` includes `chainId` and is immutable/correctly recomputed on upgrade.
  5. Check for deadline/expiry field in the signed message.
- **Failure Mode**: A valid signature produced on chain A is replayed on chain B (or on a different contract instance on the same chain), allowing double-spending, unauthorized minting, or theft of funds. Also exploitable across contract instances during migrations.
- **Common Contexts**: Token bridge finalization, cross-chain borrow/repay authorization (`borrowAsset()`, `swapToBorrow()`), settlement contracts, omnichain NFT claim, peer signature schemes (Polkaswap `prepareForMigration`), ERC-1271 handlers, cross-chain governance execution.

---

## BRIDGE-002: missing_message_replay_protection
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `receive_cross_chain_msg()` or `postIncomingMessages()` without a `processedMessages[msgHash]` or `executedNonces[nonce]` guard. Re-submitted Starknet messages. Reentrancy during message receipt enabling replay.
- **Detection Heuristic**:
  1. Find all message-receive entry points (e.g., `receive_cross_chain_msg`, `postIncomingMessages`, `executeMessages`, `sgReceive`, `anyExecute`).
  2. Check for a nonce/hash mapping that marks messages as consumed before processing.
  3. Verify the guard is set BEFORE any external calls (CEI pattern).
  4. Check for reentrancy: if the receive function calls an external contract before marking as processed, reentrancy enables replay.
  5. On Starknet/Cairo: verify that already-processed message IDs cannot be re-submitted by anyone.
- **Failure Mode**: An attacker re-submits an already-executed cross-chain message (burn, mint, unlock), causing double-minting or double-withdrawal. Reentrancy during `postIncomingMessages` also enables replay within the same transaction.
- **Common Contexts**: Settlement contracts (`receive_cross_chain_msg`), LayerZero `lzReceive`/`anyExecute`, Axelar `execute`, Wormhole VAA processing, Hyperlane message handlers, IBC handlers.

---

## BRIDGE-003: missing_source_chain_sender_validation
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: Message handler calls (e.g., `sgReceive`, `lzReceive`, `_executeTransaction`, `ccipReceive`, `xReceive`) that check `msg.sender` equals the bridge/router but do NOT validate `srcChainId` or `srcAddress` (the originating chain and contract). Also: unverified `_srcChainSender` parameter passed by caller.
- **Detection Heuristic**:
  1. Locate all inbound message handlers.
  2. Check that `msg.sender` is validated as the trusted bridge endpoint (e.g., LayerZero endpoint, Wormhole core, CCIP router).
  3. Additionally check that `srcChainId` is in an allowlist of trusted chains.
  4. Additionally check that `srcAddress` (the source-chain contract) equals the registered peer/trusted remote for that chain.
  5. Flag any handler where `_srcChainSender` / `srcAddress` is passed as a calldata parameter without being cross-verified against a stored trusted mapping.
- **Failure Mode**: Attacker deploys a malicious contract on any chain that sends forged messages, bypassing the bridge's trust model. Allows unauthorized minting, vault state manipulation, or governance hijacking without spending bridge fees.
- **Common Contexts**: CCIP `ccipReceive` (YieldFi), Wormhole `receiveWormholeMessages`, LayerZero `lzReceive`, Axelar `_execute`, Chainlink bridge receivers, cross-chain lending (LEND protocol srcEid checks), settlement contracts (ChakraSettlement `contract_chain_name` not checked).

---

## BRIDGE-004: incorrect_gas_estimation_layerzero
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: `_lzSend(dstChainId, payload, refundAddress, zroPaymentAddress, adapterParams, msg.value)` where `adapterParams` encodes an insufficient or zero gas limit. Hard-coded gas values that don't account for variable payload cost. `MIN_FALLBACK_RESERVE` calculations that undercount actual gas consumption.
- **Detection Heuristic**:
  1. Find all `_lzSend` / `lzSend` / `send` calls to LayerZero endpoints.
  2. Check if `adapterParams` is user-supplied (risk: attacker can pass gas=0 or gas below execution minimum).
  3. Check if there is a minimum gas enforcement (`require(gasLimit >= MIN_GAS_LIMIT)`).
  4. For contracts that calculate gas internally: verify `TRANSFER_OVERHEAD` constant against actual execution cost.
  5. Check `_payExecutionGas` and similar functions: is `gasLeft - gasAfterTransfer > TRANSFER_OVERHEAD` consistently true?
  6. Check if the LayerZero channel can be permanently blocked if a low-gas message triggers the blocking mechanism in `NonBlockingLzApp`.
- **Failure Mode**: (a) Under-gas: message fails on destination chain, potentially blocking the LayerZero channel permanently. (b) Over-gas: excess ETH is sent to refundAddress instead of user. (c) Attacker passes max possible gas limit to force channel block.
- **Common Contexts**: OFT tokens (Tapioca, UXD, Holograph), LayerZero-integrated lending (LEND), cross-chain NFT bridges, `NonBlockingLzApp` inheritors, fee calculation for Stargate `participate()`.

---

## BRIDGE-005: unhandled_failed_cross_chain_message_no_refund
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain call sequence where tokens are burnt/locked on source chain before confirmation from destination. No `try/catch` around destination execution. No fallback/retry mechanism when destination reverts. `xReceive()` not handling reverts. Missing `retrieveDeposit()` functionality.
- **Detection Heuristic**:
  1. Trace every cross-chain flow: find where tokens are debited on source (burn/lock/escrow).
  2. Find where the matching credit happens on destination.
  3. Check: if destination execution reverts, is source-chain debit rolled back? If not: is there a `retrieveDeposit()`/`claimRefund()` path?
  4. Check `try/catch` usage on destination calls; missing catch = stuck tokens.
  5. Check if failed message state can be queried and replayed.
  6. Check `retrySettlement()` and `retrieveDeposit()` implementations for correctness (nonce validation, re-entrancy, return-value handling).
- **Failure Mode**: User's tokens are permanently burnt on source chain while destination chain mint/execution silently fails. No recovery path. Funds locked indefinitely.
- **Common Contexts**: Axelar cross-chain calls (tokens burnt before callback confirmed), LayerZero OFT (Tapioca, Renzo), deposit fallback modules, bridge migration flows, Maia DAO `BranchBridgeAgent`, cross-chain lending repayment.

---

## BRIDGE-006: reentrancy_in_bridge_token_accounting
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Bridge contracts with ERC-777 / callback-bearing tokens, `receive()` / `fallback()` functions, or `sgReceive` callbacks where state (balances, nonces, TVL) is updated AFTER external transfer calls. Also: `dividends` updated after external payment in bridge dividend contracts.
- **Detection Heuristic**:
  1. Find all external calls in bridge inbound/outbound paths (token `transfer`, `safeTransfer`, ETH send).
  2. Check if protocol state (balances, nonces, TVL, depositAmount) is updated before or after the external call.
  3. For ERC-777 or similar: check if `tokensReceived` hook can reenter the bridge's deposit or withdraw function.
  4. Check `expressReceiveToken`: if it calls external hook before recording the express delivery.
  5. Flag patterns: `transfer(to, amount)` followed by `balances[to] -= amount` (should be reversed).
- **Failure Mode**: Attacker exploits callback (ERC-777 `tokensReceived`, ETH receive hook) to reenter the bridge before accounting is updated, draining pool by double-counting deposits or bypassing withdrawal limits. PolygonZkEvmBridge ERC-777 reentrancy, Linea `TokenBridge` reentrancy corrupting token accounting.
- **Common Contexts**: ERC-777 tokens sent to bridge contracts, L1/L2 token bridges with ETH receive, express delivery in Axelar ITS, dividend distribution in bridge token contracts.

---

## BRIDGE-007: missing_access_control_on_privileged_bridge_functions
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: Functions like `registerTokenOnL2()`, `setBridge()`, `proposeBurnAndBridge()`, `proposeUpdateTransmitters()`, `proposeRemoveTransmitters()`, `proposeSetConsensusTargetRate()`, `sendCurrentOperatorsKeys()`, `receiveMessage()`, `transferAll()`, `proposeSellForLp()` lack `onlyOwner`/`onlyRole`/`onlyBridge` modifier.
- **Detection Heuristic**:
  1. Enumerate all state-mutating functions in bridge, settlement, and handler contracts.
  2. For each function: is there an access control modifier?
  3. Specifically check: token registration functions, transmitter/relayer management, bridge address setters, cross-chain message dispatch, initialization functions.
  4. Check `initialize()` functions: are they front-runnable (no `msg.sender == deployer` check at construction time)?
  5. Check Solana `init_if_needed`: can it be called by an attacker before the protocol?
- **Failure Mode**: Attacker calls unguarded registration function to set malicious L2 token address, draining bridge reserves. Attacker calls unguarded transmitter update to install malicious relayers. Bridge initializer front-run to take control. Unauthorized consensus rate manipulation.
- **Common Contexts**: tSQD `registerTokenOnL2`, Arbitrum token bridge `setBridge()`, Photon Messaging `proposeUpdateTransmitters`, Entangle `proposeBurnAndBridge`, Gorples Bridge `Initialize`, NGL Bridge initializer, Composable Bridge withdraw, MegaETH `LaunchBridge` transition functions, Tanssi `sendCurrentOperatorsKeys`.

---

## BRIDGE-008: incorrect_token_address_or_parameter_in_cross_chain_call
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain function calls where `token`, `srcToken`, `lToken`, `hToken`, `destEid`, `srcEid`, `refundAddress`, or `receiver` address is hardcoded incorrectly, derived from wrong variable, or not validated against expected mapping. Wrong offset when reading ABI-encoded payload bytes.
- **Detection Heuristic**:
  1. Trace each cross-chain call's parameter construction — especially `token` addresses and endpoint IDs.
  2. For LayerZero: verify `srcEid` checks in `borrowWithInterest()`, `lzReceive` routing.
  3. For cross-chain liquidations: verify `srcToken` passed to remote chain matches the actual collateral token, not a wrong local alias.
  4. For payload decoding: verify byte offsets are correct for each flag value (especially in `anyExecute` / `anyFallback`).
  5. Check receiver address derivation: is it `msg.sender`, `tx.origin`, or a parameter? Does it alias correctly cross-chain?
- **Failure Mode**: (a) Wrong token address causes debit from/to incorrect account or revert. (b) Incorrect `srcEid`/`destEid` routes message to wrong chain. (c) Off-by-one in payload offset causes wrong nonce to be marked executed, leading to DoS. (d) Wrong liquidation token prevents debt repayment.
- **Common Contexts**: Tapioca TOFT `debit` (`H-05`), LEND `borrowWithInterest` srcEid, cross-chain liquidation token parameter (LEND H-14, H-19, H-25, H-4), Maia DAO payload offset bugs, `DecentBridgeExecutor.execute` fallback receiver, `CelerIMFacet` receiver.

---

## BRIDGE-009: decimal_precision_mismatch_cross_chain
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Token amount passed cross-chain without normalization for destination chain decimal difference. `ld2sd_rate` (local-to-shared decimal) miscalculated. `hToken` / underlying amount conversion missing decimal scaling. Cross-layer amount uses wrong precision (e.g., 18 vs. 6 decimals).
- **Detection Heuristic**:
  1. Find all cross-chain amount transfer/mint/burn calls.
  2. For each: does the source chain normalize the amount to a shared decimal before sending?
  3. Does the destination chain denormalize correctly using the same rate?
  4. Check `ld2sd_rate` initialization: can it be manipulated (e.g., via `MintCloseAuthority` closing the mint changes decimal count)?
  5. Check fee calculations that combine amounts from chains with different decimals.
  6. For ERC-4626 vault tokens: verify `shares` vs. `assets` conversion is done using destination-chain exchange rate, not source-chain rate.
- **Failure Mode**: (a) Amount is 1000x too large or too small on destination chain, leading to over-minting or permanent value loss. (b) `ld2sd_rate` manipulation allows artificial inflation. (c) ERC-4626 vault token cross-chain transfer destroys value due to exchange rate divergence.
- **Common Contexts**: Maia DAO hToken/underlying scaling (H-05), Fuel decimal oversight, LEND H-11 token decimal mismatches, LayerZero OFT `ld2sd_rate` (LayerZero-September M-01, Kanpaipandas C-01), ERC-4626 cross-chain transfers (D protocol), Connext `_slippageTol` decimal adjustment.

---

## BRIDGE-010: block_reorg_double_spend
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Bridge finalization based on transaction inclusion proof without waiting for sufficient block confirmations on the source chain. Fast bridge designs that unlock funds before source-chain finality. Bridge that accepts proof of any block without checking depth/finality.
- **Detection Heuristic**:
  1. Find finalization functions that accept a block hash or transaction proof.
  2. Check if there is a minimum confirmation count enforced before accepting the proof.
  3. For L2->L1 withdrawals: verify the challenge period / finality window is respected.
  4. For fast bridge designs: check if there is a race between unlock time and proof verification window.
  5. Check whether the off-chain relayer/oracle uses a single data source (single point of failure for reorg detection).
- **Failure Mode**: Source chain reorgs after bridge finalization: deposit disappears from source but withdrawal already released on destination, enabling double-spending. Also: race condition between unlock time and proof verification.
- **Common Contexts**: Polkaswap Ethereum bridge (no reorg handling), Aurora Fast Bridge (block reorg double spend, race condition), Optimism legacy withdrawal relaying (double spend H-2), zkSync priority operation re-execution during GW→L1 migration.

---

## BRIDGE-011: arbitrary_cross_chain_call_execution
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `Executor.execute(calldata)` or `GenericBridgeFacet` / `GenericCrossChainFacet` that forward arbitrary calldata to arbitrary addresses without allowlist validation. `xcall()` that does not validate target contract. `stargate` callback that executes user-supplied calls in shared contract context.
- **Detection Heuristic**:
  1. Find `execute()`, `executeCall()`, or equivalent functions that make `.call(data)` to an address.
  2. Check if the target address is validated against an allowlist/whitelist.
  3. Check if the call is made in the context of the bridge contract (enabling token theft via `approve`/`transfer`).
  4. Check if calldata can be user-supplied without sanitization.
  5. For `xcall()`: verify that destination contract and calldata are validated before fee payment.
- **Failure Mode**: Attacker crafts malicious calldata that calls `token.approve(attacker, MAX)` or `token.transfer(attacker, balance)` on tokens held by the bridge executor contract, stealing all accumulated unclaimed tokens or bridge reserves.
- **Common Contexts**: Connext `GenericBridgeFacet` (too-generic calls), LI.FI `Executor` (malicious calldata), Rubic `GenericCrossChainFacet` (arbitrary calls in shared context), LI.FI Axelar bridge (malicious external call), Connext `xcall()` (insufficient checks).

---

## BRIDGE-012: stale_exchange_rate_or_price_in_cross_chain_accounting
- **Frequency**: ~15/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain mint/accounting that uses a cached or periodically-updated exchange rate (`inflationMultiplier`, `stUSDC` shares/assets ratio, LP price) rather than a live on-chain rate. LayerZero-synchronized global state that can be overwritten by stale message. `slot0` used for slippage calculation.
- **Detection Heuristic**:
  1. Find all places where an exchange rate, price, or multiplier is stored in cross-chain context.
  2. Check how frequently it is updated and whether updates are atomic with usage.
  3. For ERC-4626 vault tokens bridged cross-chain: verify `convertToShares()` uses destination-chain rate.
  4. For L1-L2 rate synchronization: check if stale messages can overwrite a newer rate (e.g., LZ message ordering).
  5. Check `slot0`-derived prices used for bridge slippage or fee calculations.
- **Failure Mode**: (a) Stale `inflationMultiplier` allows attacker to rebase to old rate and extract value. (b) Out-of-order LZ messages overwrite current global state with older state. (c) `slot0` manipulation via flash loan inflates slippage calculation, enabling sandwich attacks.
- **Common Contexts**: Eco Protocol `inflationMultiplier` (H-1, H-2), stUSDC cross-chain share rate (H-06), Mozaic Archimedes LP price manipulation (TRST-H-1), Connext portal debt repayment with spot DEX price, Autonomint cross-chain global state overwrite (H-26), Tensorplex delayed exchange rate.

---

## BRIDGE-013: native_token_eth_stuck_or_mishandled
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: `payable` bridge functions that receive `msg.value` for fees but forward wrong amount. Native token left in intermediate contracts (`ASDRouter`, `RootBridgeAgent`). `sweep()` missing unwrap of WETH before sending ETH. `_handleExecuteTransaction()` not handling native assets in the ETH branch. `msg.value` not compared to bridged amount.
- **Detection Heuristic**:
  1. Find all `payable` bridge functions that receive ETH.
  2. For each: trace where `msg.value` goes — is it forwarded in full to the bridge endpoint or split?
  3. Check intermediate contract ETH balances: can ETH accumulate without a withdrawal path?
  4. Check `sweep()` / `withdrawFees()` implementations: do they handle both ETH and WETH?
  5. Verify `msg.value >= bridgeFee + bridgedAmount` check exists when both are payable in ETH.
  6. Check `receive()` / `fallback()` in executor contracts: do they accept ETH and can ETH get trapped?
- **Failure Mode**: ETH permanently stuck in router/bridge contract with no recovery path. Fee underpayment causes transaction failure on destination. Entire `msg.value` goes to blackhole when called by contract wallet. Native token sent to refund address instead of user.
- **Common Contexts**: Maia DAO `RootBridgeAgent.sweep()` missing unwrap (H-21), Canto `ASDRouter` ETH stuck (H-01), Connext `_handleExecuteTransaction` native asset handling, Connext executor reverts on ETH receive (H-132), LI.FI `ArbitrumBridgeFacet` fee check, Scroll bridge ETH stuck on failed deposit, Camp `bridgeOut()` missing msg.value check.

---

## BRIDGE-014: duplicate_validator_or_signature_missing_dedup_check
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Multisig/threshold signature verification that iterates a signer list without checking for duplicate addresses. `verifyECDSA()` or `check_chakra_signatures()` accumulating signature weight without deduplication. Attacker passes same validator signature N times to satisfy N-of-M threshold.
- **Detection Heuristic**:
  1. Find threshold/multisig verification functions in bridge validators/settlement contracts.
  2. Check the loop that counts valid signatures: is there a `require(signers[i] != signers[i-1])` or a `usedSigners` set?
  3. Verify that signers array is sorted + deduplicated before counting.
  4. Check that the validator set update is atomic and the new set cannot be replayed.
  5. For SEDA: check that consensus threshold cannot be bypassed by submitting same data from different "validators" that are the same key.
- **Failure Mode**: Single compromised validator key satisfies the full multisig threshold by submitting its signature multiple times, completely bypassing the security model with just one key.
- **Common Contexts**: Chakra `SettlementSignatureVerifier` (H-03), SEDA cross-chain data verification (H-2), Sui Bridge epoch ending (validator public key reuse), Aligned Layer cross-chain signatures, Polkaswap ecrecover misuse.

---

## BRIDGE-015: cross_chain_message_channel_blocking_dos
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: LayerZero `NonBlockingLzApp` / blocking mode channel where a revert in `lzReceive` permanently blocks the channel. Attacker sends message with payload that will always revert on destination (huge `_toAddress`, non-UTF8 token names, gas below minimum, large validator set update). Large ERC20 metadata that causes log parsing failure.
- **Detection Heuristic**:
  1. Find all `lzReceive` or equivalent message handlers.
  2. Check if the bridge uses blocking mode: if `lzReceive` reverts, is the channel permanently blocked?
  3. Check input validation: is `_toAddress` length bounded? Is token metadata length bounded?
  4. For `NonBlockingLzApp`: check if `_blockingLzReceive` can be triggered by invalid payload.
  5. Check rate limiters: can they be abused to block all outbound messages?
- **Failure Mode**: Attacker sends a single malformed message that permanently blocks the LayerZero channel, preventing all future cross-chain communication. Rate limiter exhaustion causes DoS. Unbounded loop over validator set causes OOG.
- **Common Contexts**: UXD Protocol `OFTCore#sendFrom` large `_toAddress` (H-2), Tapioca LayerZero channel blocking (H-16, H-17, H-241), Althea Gravity Bridge large ERC20 names/denoms (H-03, H-04), HoneyJar ONFT channel block (C-01), LayerZero Aptos `Freeze Bridge with Invalid Sender`.

---

## BRIDGE-016: frontrun_bridge_initialization_or_deployment
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `initialize()` functions without deployer-only guard callable by anyone before protocol setup. `create` opcode used to deploy bridge components at predictable addresses that attacker can race to deploy malicious contracts at. Wormhole NFT bridge `nft-wrapped` subcontract deployment raceable.
- **Detection Heuristic**:
  1. Find all `initialize()` / `init()` functions in bridge contracts.
  2. Check if protected by `initializer` modifier AND whether the deployer is the only caller able to call before anyone else.
  3. For `create` opcode deployments of bridge components: can attacker precompute and preemptively deploy at the same address?
  4. For Solana `init_if_needed`: can a third party call `Initialize` before the protocol?
  5. For bridge NFT wrapping: is the wrapped contract deployment atomic with initialization?
- **Failure Mode**: Attacker front-runs initialization to control bridge config (admin keys, fee recipient, token mappings). Attacker deploys malicious contract at predicted address, hijacking bridge component.
- **Common Contexts**: Advanced Blockchain CrosslayerPortal initializer front-run, Gorples Bridge Initialize front-run, Wormhole Near NFT wrapped contract race condition, Gains Trade `bridgeNft()` front-run, Optimism Interop deterministic address token deployment attack.

---

## BRIDGE-017: missing_or_incorrect_fee_validation
- **Frequency**: ~16/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `msg.value` not compared to required bridge fee. Fee calculated on total `msg.value` instead of just bridged amount. Stargate fee underpaid/overpaid. Wormhole fee not included in bridge call. LayerZero fee sent to wrong address. Bridge fee bypassable by using alternate function path. `minAmount` DoS via dust deposit.
- **Detection Heuristic**:
  1. Identify all fee-paying bridge entry points.
  2. For each: verify `msg.value >= bridgeFee` check exists and uses correct fee quote.
  3. Check fee calculation: does it use `msg.value` (total) or `msg.value - bridgedAmount` (net fee)?
  4. Check for fee bypass paths: alternative functions that skip fee checks.
  5. For Wormhole: check if native fee is passed through to `IWormhole.publishMessage{value: fee}`.
  6. Check RDNT/OFT bridgeFee: can it be bypassed by constructing malicious adapter params?
- **Failure Mode**: (a) Zero-fee bridging depletes protocol reserves. (b) Wrong fee calculation causes undercharge or overcharge. (c) User deposit insufficient to cover fee, causing stuck transaction. (d) Malicious `minAmount` dust causes DoS on batch release.
- **Common Contexts**: Lido Wormhole fee (H-216), RDNT fee bypass (H-62), Tapioca Stargate fee (H-07, H-166), Camp `bridgeOut()` msg.value, Omni X OmniXMultisender fee, Camp user deposit fee coverage, Pike `initiateBorrow`/`initiateRepay` fee checks.

---

## BRIDGE-018: improper_l1_l2_address_aliasing
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: L1 contract address not aliased when calling L2 (Arbitrum L1→L2 aliasing adds `0x1111000000000000000000000000000000001111`). L2 address not un-aliased when expected to be the L1 contract's original address. zkSync `msg.sender` preservation breaking trust assumptions. ZkSync `MsgValueSimulator` aliasing bypass.
- **Detection Heuristic**:
  1. Find all L1→L2 message passing functions.
  2. Check if the receiving L2 contract validates `msg.sender` == L1 contract address: this will fail unless aliasing is accounted for.
  3. For Arbitrum: verify `AddressAliasHelper.undoL1ToL2Alias(msg.sender)` is called when un-aliasing is needed.
  4. For zkSync: check if `msg.sender` == bridge contract assumption is broken by zkSync's `msg.sender` preservation.
  5. Check `L2BlastBridge.finalizeBridgeETHDirect()`: is `msg.sender` un-aliased before comparison?
- **Failure Mode**: L2 contract rejects legitimate L1 messages because aliased address != expected L1 address (DoS). Or L2 contract accepts spoofed messages from attacker with the aliased address of a legitimate L1 contract it does not control.
- **Common Contexts**: Thanos L2 Native Token Bridge L1 contract aliasing evasion (H-1), zkSync `MsgValueSimulator` `onlySelf` bypass (H-01), Connext zkSync `msg.sender` trust assumption break, L2BlastBridge `finalizeBridgeETHDirect` un-aliasing.

---

## BRIDGE-019: unchecked_transferfrom_return_value_in_bridge
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: `token.transfer()` or `token.transferFrom()` called without checking return value (non-reverting ERC20 tokens return `false` on failure). `transferFrom()` return value not checked in bridge deposit. `shutDownAndMigrate()` not checking transfer result.
- **Detection Heuristic**:
  1. Find all `token.transfer()` / `token.transferFrom()` calls in bridge contracts.
  2. Check if return value is checked or `safeTransfer`/`safeTransferFrom` is used.
  3. For `shutdown`/`migrate` functions: specifically check every token movement.
  4. For Solana: check SPL token transfer error handling.
- **Failure Mode**: Non-reverting ERC20 token silently fails to transfer (returns false), but bridge proceeds as if transfer succeeded — bridge credits tokens that were never received, or releases tokens without actually receiving collateral.
- **Common Contexts**: Polkaswap Ethereum bridge `shutDownAndMigrate` unchecked transfer (H-129), Polkaswap `transferFrom` return value (H-248), Optimism `L2StandardBridge` unhandled transfer failures (H-386), ZetaChain cross-chain EVM dirty state not committed (H-150).

---

## BRIDGE-020: wrong_selector_or_interface_function_identifier
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Wrong function selector used when calling ERC-1155 `onERC1155Received` vs. `onERC1155BatchReceived`. Incorrect ABI-encoded function call in cross-chain message. Wrong Cosmos address format passed to bridge. `abi.encodePacked()` used for multi-parameter hashing (hash collision risk).
- **Detection Heuristic**:
  1. Find all `selector` usages and external calls in bridge token handling.
  2. For ERC-1155 bridging: verify correct selector (`0xf23a6e61` for single, `0xbc197c81` for batch).
  3. For EVM→Cosmos bridges: verify address encoding format (Bech32 vs. hex).
  4. Find all `abi.encodePacked()` with multiple dynamic or same-type arguments — flag for hash collision potential.
  5. Check `ERC-7683` `originData` and `fillDeadline` encoding.
- **Failure Mode**: (a) Wrong ERC-1155 selector causes token loss during bridge (token transferred but callback fails). (b) Cosmos address in wrong format causes permanent bridge failure. (c) `abi.encodePacked()` hash collision allows forged withdrawal proofs or signature reuse.
- **Common Contexts**: Boba Bridge ERC-1155 wrong selector (H-34), Pheasant Network `abi.encodePacked()` hash collision (H-176), Entangle Trillion Cosmos address (H-169), Eco Inc `ERC-7683` incorrectly encoded address (H-373) and originData (M-491).

---

## BRIDGE-021: cross_chain_token_accounting_invariant_broken
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: `xezETH` total supply not 1:1 with `ezETH` backing. `stETH` minted on L2 without corresponding `wstETH`. `hToken` supply can be inflated by attacker. Cross-chain borrow allows same collateral to be used multiple times. `tvl()` not counting in-flight amounts. `totalSlashableAmount` invariant not enforced. Share price manipulation via LP.
- **Detection Heuristic**:
  1. Identify cross-chain peg/invariant: token A on chain X should equal token B on chain Y.
  2. Verify all mint paths on destination credit against a matching burn/lock on source.
  3. Check if in-flight bridge amounts are included in TVL/collateral calculations.
  4. For cross-chain lending: verify same collateral cannot be used as collateral on multiple chains simultaneously (H-214: multiple borrows with same collateral).
  5. Check `totalProcessed` / `totalSlashableAmount` / `lockedAmountInBond` invariants in code, not just docs.
- **Failure Mode**: (a) Attacker mints arbitrary tokens by exploiting mint path without corresponding lock. (b) Protocol becomes insolvent because TVL calculation excludes in-flight amounts. (c) User borrows against same collateral on multiple chains simultaneously.
- **Common Contexts**: Renzo `xezETH` not 1:1 (H-56), Lido `stETH` L2 mint (H-21), Maia DAO `hToken` inflation (H-1), Blueberry `tvl()` missing in-flight (H-37, H-426), LEND multiple borrows same collateral (H-214), Pheasant Network invariant (H-90), Coinbase `totalProcessed` (H-353).

---

## BRIDGE-022: gas_griefing_cross_chain_operator_mev
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Operator selection mechanism where selected operator must execute within a gas price window. Gas price spikes allow attacker to front-run the selected operator's execution, causing them to be slashed. Gas limit set by user in cross-chain job (Holograph operator model) allows attacker to set block-gas-limit-exceeding value, bricking operator.
- **Detection Heuristic**:
  1. Find operator/relayer selection with economic bond/slash.
  2. Check if the gas price at execution time can differ from gas price at selection time.
  3. Check if user-supplied gas limit is bounded by destination chain block gas limit.
  4. Check if attacker can set gas limit above block gas limit to lock operator out of pod.
  5. Check `_gasLimit` validation: `require(_gasLimit <= BLOCK_GAS_LIMIT)`.
- **Failure Mode**: Gas price MEV: attacker bribes miner to spike gas price after operator is selected, then front-runs the operator's execution. Operator is forced to execute at a loss or be slashed. Gas limit > block gas limit: operator cannot execute the job and is permanently locked out.
- **Common Contexts**: Holograph Operator gas price spike (H-26, H-36, H-279), Holograph gas limit > block gas limit (H-162), Holograph gas limit check inaccuracy (H-172), Holograph failed job no recovery (H-104).

---

## BRIDGE-023: missing_mint_cap_check_cross_chain
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Inbound cross-chain transfer minting function that does not check `totalSupply + amount <= mintCap` before minting. Hyperlane message reuse allowing unlimited minting. `outboundTransferShares` missing `mintCap` check. Cross-chain transfer reverts on destination when mintCap is reached without recovery path.
- **Detection Heuristic**:
  1. Find all `mint()` calls triggered by inbound cross-chain messages.
  2. Check if `totalSupply + mintAmount <= cap` is verified before mint.
  3. Check if failed mint due to cap reversion has a recovery path (refund on source chain).
  4. For Hyperlane: check if message IDs are tracked to prevent reuse.
- **Failure Mode**: (a) Unlimited minting via replayed failed Hyperlane messages. (b) Cross-chain transfer reverts on destination due to mint cap with no source-chain refund. (c) `outboundTransferShares` bypasses cap check causing over-issuance.
- **Common Contexts**: LMCV `dPrimeConnectorHyperlane` unlimited minting from failed messages (H-186), dForce `outboundTransferShares` missing cap (H-153), dForce cross-chain mintCap revert (M-460).

---

## BRIDGE-024: smart_contract_wallet_cross_chain_incompatibility
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain operations that use `msg.sender` as the recipient on destination chain, where the caller is a smart contract wallet that may not be deployed at the same address on destination. Multisig wallets incompatible with OFT `send()`. `L1GraphTokenGateway.outboundTransfer()` by contract blackholes `msg.value`. `StargateLbpHelper.participate()` by multisig leaks tokens.
- **Detection Heuristic**:
  1. Find cross-chain functions that use `msg.sender` as destination recipient.
  2. Check if the function is callable by smart contract wallets (no `require(msg.sender == tx.origin)`).
  3. If callable by contracts: verify recipient address on destination is explicitly specified, not derived from `msg.sender`.
  4. Check `tx.origin` vs. `msg.sender` usage for refund addresses.
  5. For OFT `send()`: verify the `toAddress` parameter is not derived from `msg.sender` of a contract caller.
- **Failure Mode**: Smart contract wallet at address X on chain A calls bridge with `msg.sender` as recipient. Address X on chain B is either not deployed, or is a different contract. Tokens sent to wrong address and permanently lost.
- **Common Contexts**: StationX `H-10` virtual account owner cross-chain, TempleGold `send()` multisig incompatibility, Tapiocadao `StargateLbpHelper.participate()` multisig token theft (H-03, H-385), The Graph `L1GraphTokenGateway` contract caller blackhole (M-496), Olas `refundAccount` tx.origin vs msg.sender (M-468).

---

## BRIDGE-025: centralization_single_point_of_failure_relayer
- **Frequency**: ~10/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Single relayer/coordinator with no failover. Bridge operation entirely dependent on off-chain process that uses `panic` on error. No permissionless message relay path. Relayer can censor. Relayer role conflated with owner role (can modify own bond manager).
- **Detection Heuristic**:
  1. Count relayer/operator roles: is there exactly one privileged relayer address?
  2. Check error handling in off-chain bridge components: does a single RPC failure / `panic` halt the bridge?
  3. Check if users can relay their own messages as a fallback.
  4. Check if relayer role separation from admin/owner exists.
  5. Check single Ethereum data source dependence in oracle/listener.
- **Failure Mode**: Relayer goes offline → bridge halted. Relayer is compromised → all bridge transactions can be censored or manipulated. Single RPC source → reorg blindness or data corruption. Relayer front-runs own slash evidence.
- **Common Contexts**: Advanced Blockchain CrosslayerPortal single relayer (H-221), Polkaswap off-chain single Ethereum data source (H-269), Solana Poller panic (H-278), Pheasant Network relayer/owner role conflation (H-433), Pheasant Network relayer self-serving evidence (H-331, H-335, H-296).

---

## BRIDGE-026: cross_chain_debt_state_accounting_error
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain borrow/repay/liquidation operations that update wrong state variable, update same-chain borrow balance instead of cross-chain borrow balance, fail to accrue interest before recording new principal, or use wrong amount (collateral seized vs. repayment amount) for state update.
- **Detection Heuristic**:
  1. Find cross-chain borrow/repay/liquidation state update functions.
  2. For repayment: verify `crossChainDebt` is decremented, NOT `sameChainDebt`.
  3. For liquidation: verify the amount used for debt reduction is the `repayAmount`, not the `seizeAmount`.
  4. For additional borrows: verify `accrueInterest()` is called before adding new principal to existing debt.
  5. Verify `maxLiquidatable` calculation is based on current outstanding debt including cross-chain portion.
- **Failure Mode**: (a) Cross-chain repayment does not reduce the correct debt, leaving position permanently over-indebted or under-indebted. (b) Liquidation uses wrong amount, leading to under-repayment or protocol insolvency. (c) Interest not accrued before new borrow → existing debt grows without accrual, causing interest loss.
- **Common Contexts**: LEND protocol (H-26, H-24, H-244, H-246, H-406, H-413, H-419, H-432), Folks Finance incorrect repayment accounting (H-321), cross-chain liquidation bugs (LEND H-8, H-14, H-19, H-22, H-414, H-417), Pike incomplete liquidation.

---

## BRIDGE-027: transceiver_ordering_dependency_stuck_transfer
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Multi-transceiver Wormhole NTT design where `TransceiverInstruction` array must be in exact transceiver index order. Adding/removing transceivers changes index order, causing queued in-flight transfers to use wrong transceiver index. Queued transfers with stale transceiver set cannot be completed.
- **Detection Heuristic**:
  1. Find multi-transceiver systems (Wormhole NTT or similar).
  2. Check `TransceiverInstruction` encoding: is there an index field? Is it validated against current transceiver array?
  3. Check: what happens to queued transfers if transceivers are added/removed after queuing?
  4. Verify transceiver instructions are matched by ID not by array position.
- **Failure Mode**: User queues a transfer with 2 transceivers; admin adds a third transceiver at index 0, shifting existing transceivers. Queued transfer's instruction now points to wrong transceiver, causing permanent failure of the queued transfer.
- **Common Contexts**: Wormhole EVM NTT queued transfer stuck due to transceiver ordering (H-147), Wormhole EVM NTT transfer stuck when transceivers modified before completion (H-281).

---

## BRIDGE-028: privilege_escalation_via_cross_chain_allowance
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain functions that use the caller's allowance over another user's tokens to perform operations on their behalf without requiring separate approval for the cross-chain context. `removeCollateral()`, `retrieveFromStrategy()`, `leverageDownInternal()`, `exerciseOption()` using `msg.sender` as source but operating on a specified `user` address.
- **Detection Heuristic**:
  1. Find cross-chain functions that take a `user` address as parameter distinct from `msg.sender`.
  2. Check if these functions verify that `msg.sender` has allowance over `user`'s position/tokens.
  3. Check if the allowance check is on the source chain, not bypassed by cross-chain initiation.
  4. For OFT allowance: verify cross-chain `exerciseOption`, `removeCollateral`, `retrieveFromStrategy` check approval before debiting from owner.
- **Failure Mode**: Attacker with any allowance (even 1 wei) calls cross-chain function specifying victim as user, draining victim's full position. Or attacker with zero allowance exploits missing check entirely.
- **Common Contexts**: Tapioca `BaseTOFT.removeCollateral` missing approval check (H-35, H-92), `BaseTOFT.retrieveFromStrategy` missing approval (H-34, H-182), `TOFT.exerciseOption` stealing ERC-20 (H-11, H-305), `multiHopBuyCollateral` missing allowance (H-07, H-54), `triggerSendFrom` missing auth (H-13, H-440).

---

## BRIDGE-029: token_lock_on_failed_swap_at_destination
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Bridge + swap combos where tokens are delivered to the bridge aggregator on destination chain, but the subsequent swap call fails (insufficient liquidity, wrong token, slippage exceeded). No fallback to deliver the pre-swap tokens to the user. Tokens remain in `Executor` or bridge contract indefinitely.
- **Detection Heuristic**:
  1. Find bridge functions that include an optional/mandatory swap on destination.
  2. Check what happens if the `swap()` call reverts: is there a `try/catch`?
  3. If swap fails: are the received tokens forwarded to the user as-is, or do they remain in the contract?
  4. Check `sgReceive()` implementations: permanent error paths where tokens are stuck.
  5. Check `execute()` fallback: when `_callData` execution fails, does it revert the token transfer?
- **Failure Mode**: User's tokens arrive at destination bridge contract, but swap fails (e.g., pool dry, deadline passed, wrong address). Tokens stay in contract with no user-accessible claim mechanism. Permanently lost.
- **Common Contexts**: LI.FI Amarok bridge swap failure (H-137), Tapioca `StargateLbpHelper.sgReceive()` permanent error (H-02, H-324), Connext tokens stuck when destination router lacks WETH reserves (H-274), Connext reconcile process portal (H-234).

---

## BRIDGE-030: erc4337_paymaster_cross_chain_gas_accounting
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Paymaster that does not correctly calculate the gas used by cross-chain execution. User escapes paying for tx gas by exploiting accounting gap. Smart contract wallet that paid tokens for an invoice cannot get refund on cancellation (payment locked in cross-chain flow).
- **Detection Heuristic**:
  1. Find `validatePaymasterUserOp` and `postOp` implementations.
  2. Verify `actualGasCost` accounting includes cross-chain execution overhead.
  3. Check refund paths: if cross-chain execution fails, can the smart wallet recover its payment?
  4. Check if `userOpHash` includes `entryPoint` address (replay across different EntryPoint instances).
- **Failure Mode**: User pays zero or partial gas for cross-chain execution, depleting paymaster balance. Smart contract wallet pays for cancelled invoice but payment is non-refundable in cross-chain context.
- **Common Contexts**: Etherspot Gastankpaymaster user escapes gas (H-03, H-158), Etherspot smart wallet refund on invoice cancel (H-02, H-63), Metamask DelegationFramework EntryPoint missing from hash (H-398).

---

## BRIDGE-031: bridge_rate_limiter_dos_abuse
- **Frequency**: ~5/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Rate limiter that enforces a per-window transfer cap. Attacker repeatedly triggers small withdrawals to fill the rate limit bucket, preventing legitimate users from bridging. Rate limiter not reset correctly between windows. ETH withdrawal within allowed limit fails due to implementation bug.
- **Detection Heuristic**:
  1. Find rate limiter contracts in bridge architecture.
  2. Check: can an attacker repeatedly trigger the rate limiter at low cost to themselves?
  3. Check: is the rate limiter bucket filled by attacker actions that cost less than the DoS impact?
  4. Check `ETH` withdrawal logic: does the limit check use current window correctly?
  5. Check rate limiter reset: is the window rolling or fixed?
- **Failure Mode**: Attacker fills rate limit bucket with dust transfers, blocking all subsequent withdrawals for the entire rate-limit window. Legitimate users unable to withdraw. Alternatively, implementation bug allows limit to be incorrectly reached even for valid amounts.
- **Common Contexts**: Linea Bridge rate limiter DoS (H-33), Scroll `ScrollOwner` rate limiter abuse (H-446), zkSync ETH withdrawal within limit fails (H-301), Datachain IBC channel close due to gas limit differences (H-397).

---

## BRIDGE-032: stale_tvl_calculation_missing_inflight
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: `tvl()` function that sums vault balances on current chain but excludes amounts currently in transit (sent cross-chain, not yet received/confirmed). `inFlightBridgeAmounts` not decremented when bridge completes. Escrow TVL calculation missing in-flight USDC.
- **Detection Heuristic**:
  1. Find `tvl()` / `totalAssets()` functions in cross-chain vault/escrow contracts.
  2. Check if an `inFlight` tracking variable exists and is included in TVL.
  3. Verify `inFlightBridgeAmounts` is incremented on send AND decremented on receipt/confirmation.
  4. Check if `inFlightBridgeAmounts` can become stale (never decremented after bridge completes).
- **Failure Mode**: TVL understates true protocol assets by excluding in-flight amounts, causing incorrect yield calculations, collateral ratios, or share prices. Or overstates TVL if `inFlight` is never decremented after completion, creating phantom assets.
- **Common Contexts**: Blueberry `Escrow.tvl()` missing in-flight USDC (H-37), Blueberry stale `inFlightBridgeAmounts` (H-426), Chainport bridge appearing out of funds (H-46).

---

## BRIDGE-033: cross_chain_nonce_management_error
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Nonce not incremented on failed cross-chain withdrawal attempt. Wrong nonce read from ABI-encoded payload (byte offset bug). Attacker can manipulate user's nonce in settlement contract. `depositNonce` incorrectly marked as executed for wrong nonces.
- **Detection Heuristic**:
  1. Find all nonce management in cross-chain message send/receive.
  2. For Solana: check if `nonce` is incremented even when the withdrawal transaction fails.
  3. Check ABI decode byte offsets for nonce extraction in `anyExecute`/`anyFallback`.
  4. Check if nonce storage is user-specific or shared (can attacker increment another user's nonce?).
  5. Verify `nonce_manager` write access control in settlement contracts.
- **Failure Mode**: (a) Failed withdrawal reuses same nonce → second attempt rejected as replay. (b) Wrong nonce offset marks legitimate nonce as executed → user's future deposits blocked. (c) Attacker increments victim's nonce to block their next valid cross-chain message.
- **Common Contexts**: ZetaChain Solana nonce not incremented on failure (M-492), Maia DAO payload offset nonce (H-254, H-265, H-32), Chakra `nonce_manager` anyone can manipulate (H-245), Coinbase remove-owner replay with same index (H-229).

---

## BRIDGE-034: missing_chain_id_whitelist_validation
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Bridge contracts that accept messages or deposits from any chain ID without maintaining an allowlist of supported chains. Wormhole destination chain ID not validated. `srcChainId` / `dstChainId` set to attacker-controlled value.
- **Detection Heuristic**:
  1. Find all cross-chain message receive and send functions.
  2. Check if `srcChainId` is validated against a `supportedChains` mapping.
  3. Check if `dstChainId` is validated before forwarding.
  4. For Wormhole: `require(toChainId == wormholeChainId)` in destination handler.
  5. Check for same-chain source/destination ID: can attacker route message from chain A back to chain A (H-142)?
- **Failure Mode**: Attacker sends messages from unsupported/malicious chains to trigger unauthorized state changes. Tokens routed to wrong chain. Same chain ID used for source and destination causes tokens to be stuck.
- **Common Contexts**: Bridge Updates chain ID whitelist (H-28), Multiplyr Wormhole destination chain not validated (M-469), Bridge Updates same chain ID causes token stuck (H-142), Axelar ITS bridge DoS via undeployed chain (H-351).

---

## BRIDGE-035: merkle_proof_forgery_or_reconstruction_flaw
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: Merkle tree implementations where proof length is not validated, allowing forged proofs. Ambiguous node encoding (leaf vs. internal node) enables proof forging. Competing implementations of Merkle tree produce different roots for same data. Withdrawal root crafted to allow multiple withdrawals. Poseidon2 batch opcode verification bug.
- **Detection Heuristic**:
  1. Find Merkle proof verification functions.
  2. Check: is proof length validated (not too short, not too long)?
  3. Check: are leaf nodes distinguished from internal nodes (e.g., leaf prefix byte)?
  4. Check: are there two competing Merkle implementations that can produce different roots?
  5. Check withdrawal root construction: can a crafted root allow multiple claims?
- **Failure Mode**: Attacker constructs forged Merkle proof that passes verification, claiming arbitrary key/value inclusion. Multiple withdrawals from single deposit. Bridge accepts false inclusion proof for non-existent transaction.
- **Common Contexts**: Orga and Merk forged Merkle proofs (H-167), Succinct Labs Telepathy Merkle proof length forgery (H-445), Layer N withdrawal root forgery (H-363), Matter Labs zkEVM Merkle path inconsistency (M-490), Era Merkle proof bypass (M-490).

---

## BRIDGE-036: cross_chain_callback_status_always_success
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Callback processing that marks cross-chain message status as `SUCCESS` regardless of actual execution outcome. `receive_cross_chain_msg` sets `Status::SUCCESS` unconditionally before checking result. `CrossChainMsgStatus` updated to `SETTLED` even when destination execution failed.
- **Detection Heuristic**:
  1. Find all callback/settlement status update code paths.
  2. Check: is status updated BEFORE or AFTER evaluating the callback result?
  3. Check: is there a `try/catch` around callback execution that conditionally sets status?
  4. For Cairo: verify `receive_cross_chain_msg` checks return value of inner call before setting SUCCESS.
  5. Check `receive_cross_chain_callback`: does it differentiate between successful and failed destination execution?
- **Failure Mode**: Failed cross-chain messages are recorded as successful. Source chain burns tokens (MintBurn mode) and records SUCCESS even when destination chain rejected the message. Protocol cannot detect failed settlements, leading to persistent accounting errors.
- **Common Contexts**: Chakra `settlement.cairo receive_cross_chain_msg` always SUCCESS (H-04, H-17), Chakra `receive_cross_chain_callback` always SETTLED (H-12, H-165), Chakra handler inconsistent callback validation (H-09, H-332).

---

## BRIDGE-037: validator_key_reuse_epoch_transition
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Validator/relayer registration that allows reusing a previously-used public key (`bridge_pubkey_bytes`) without invalidating the old key's signatures. Inability to end an epoch if duplicate validator key exists. Validator set update freezing bridge.
- **Detection Heuristic**:
  1. Find validator registration functions.
  2. Check: is there a `usedKeys` set that prevents registration of already-used keys?
  3. Check epoch-ending logic: does it validate all validators have unique keys before closing epoch?
  4. Check validator set update size: does a very large update exceed gas/storage limits?
- **Failure Mode**: Attacker registers validator with a previously-used key, creating duplicate. Epoch cannot be ended, permanently freezing the bridge. Or: old key signatures remain valid after validator is removed, undermining slashing.
- **Common Contexts**: Sui Bridge inability to end epoch (H-83), Althea Gravity Bridge large validator set freeze (H-233), Chakra duplicate validator signatures (H-03).

---

## BRIDGE-038: payload_type_user_controlled_confusion
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain message handling where `payload_type` or message flag byte is taken directly from user-supplied calldata without validation. Off-chain systems parse the type field to determine processing path, leading to confusion between on-chain and off-chain interpretation.
- **Detection Heuristic**:
  1. Find cross-chain message dispatch/receive functions with a `type`/`flag`/`action` field.
  2. Check if this field is validated against a protocol-defined enum before use.
  3. Check if the field is used for off-chain routing in addition to on-chain execution.
  4. Verify that user cannot inject arbitrary type values that confuse off-chain indexers.
- **Failure Mode**: Attacker passes arbitrary `payload_type` in `receive_cross_chain_msg`, causing off-chain systems to misroute or misinterpret the message. Could disrupt accounting, monitoring, or multi-chain settlement systems.
- **Common Contexts**: Chakra `settlement.cairo receive_cross_chain_msg` user-controlled payload_type (H-08, H-401), Olympus DAO `replyNeeded` unsafe messaging (H-50).

---

## BRIDGE-039: integer_overflow_underflow_bridge_amounts
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Unchecked arithmetic in UTXO accumulation, fee calculation, or amount normalization. Pre-Solidity-0.8 unchecked arithmetic in bridge deposit functions. Integer overflow in incentive calculation (token transfer incentives). `uint256` overflow in `appendUtxos` accumulator.
- **Detection Heuristic**:
  1. Find arithmetic operations in bridge amount/fee calculations.
  2. Check Solidity version: pre-0.8 requires explicit SafeMath.
  3. Check `appendUtxos` and similar accumulator functions for overflow in off-chain bridge components.
  4. Check fee calculation: can `fee * amount` overflow?
  5. Check `restoreBridgeTransaction` amount addition for precision/overflow.
- **Failure Mode**: Integer overflow wraps amount to near-zero, allowing attacker to bridge for free or extract excess tokens. Underflow reverts legitimate transactions. Fee calculation produces incorrect result, enabling free bridging.
- **Common Contexts**: Bridge Updates UTXO integer overflow (H-51), Bridge Updates integer overflow in fee (H-282), Bridge Updates deposit underflow (H-99), SYMMIO `restoreBridgeTransaction` wrong precision (H-105), Render Network token transfer incentive overflow (H-73), BarnBridge unchecked calculations (H-203).

---

## BRIDGE-040: cross_chain_liquidity_pool_accounting_race
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Concurrent bridge relays depleting pool reserves beyond what was checked. LP share price manipulation via first-depositor attack. Bridge LP cap exceeded on drawing settlement. No check for available liquidity before initiating cross-chain transfer. Hub missing available liquidity check.
- **Detection Heuristic**:
  1. Find functions that check and then consume bridge liquidity pool reserves.
  2. Check for TOCTOU: can concurrent transactions both pass the liquidity check?
  3. Check first-depositor / zero-share-supply path: can share price be manipulated?
  4. Check LP pool cap enforcement in bridge settlement.
  5. Check Hub for available liquidity validation before allowing withdrawal.
- **Failure Mode**: Multiple relays simultaneously deplete pool below minimum, causing subsequent relay to fail or overdraw. First depositor inflates share price to steal future depositor funds. Hub locks funds and pushes utilization ratio above 100%.
- **Common Contexts**: UMA L2 Bridges concurrent relays (H-355), Biconomy LP share price manipulation (H-198, H-211), Megapot LP pool cap exceeded (H-251), Folks Finance Hub missing liquidity check (H-53), Folks Finance first deposit inflation (H-135, H-145).

---

## BRIDGE-041: off_by_one_payload_deserialization
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Message payload decoded with wrong byte offset for a specific opcode/flag value. `depositNonce` read from incorrect position when flag is `0x06`. `anyFallback()` reading nonce from wrong offset. Recipient bytes truncated when non-20-byte payload passes validation.
- **Detection Heuristic**:
  1. Find all ABI `decode` / manual byte-slicing operations on cross-chain payloads.
  2. For each flag/opcode value: manually verify the byte offset table against the encoding function.
  3. Check encoding functions on source chain: verify alignment with decoding functions on destination.
  4. For non-EVM chains: verify address length is validated (must be exactly 20 bytes for EVM).
  5. Check `PostUnlock` payload format vs. `Unlock` payload format for consistency.
- **Failure Mode**: Wrong nonce extracted from payload causes wrong nonce to be marked executed, potentially blocking legitimate future transactions or double-crediting wrong account. Recipient address truncated/padded incorrectly causes silent burn.
- **Common Contexts**: Maia DAO wrong offset nonce (H-254, H-265, H-32), Toki Bridge non-20-byte recipient silent burn (H-35), Mayan Solana PostUnlock/Unlock payload inconsistency (H-266), Mayan EVM `postBatch` length check (H-400).

---

## BRIDGE-042: cross_chain_token_metadata_poisoning
- **Frequency**: ~6/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: L2 standard ERC-20 deployed with metadata fetched from L1 token at first bridge. Metadata (name, symbol, decimals) can be set arbitrarily if token is not yet deployed on L1. ERC-20 metadata overwritten on subsequent bridges of tokens sharing L1/L2 addresses. Token name/symbol containing non-UTF8 bytes crashes bridge log parser.
- **Detection Heuristic**:
  1. Find L2 token deployment triggered by first bridge deposit.
  2. Check where name/symbol/decimals are sourced: are they validated?
  3. Check: can non-UTF8 bytes be included in token name/symbol?
  4. Check: can tokens sharing an address on L1 and L2 trigger metadata overwrite?
  5. Check: are there bounds on metadata length that would prevent log parsing DoS?
- **Failure Mode**: Attacker deploys fake ERC-20 at an address not yet taken on L1, bridges it to L2 to set poisoned metadata. Future legitimate token at that address inherits wrong metadata. Non-UTF8 metadata crashes off-chain log parser, freezing bridge.
- **Common Contexts**: Scroll L2 standard ERC-20 arbitrary metadata (H-195), Althea Gravity Bridge non-UTF8 freeze (H-136), Linea token sharing address (H-222), Scroll/December Diff ERC-20 metadata overwrite (M-483).

---

## BRIDGE-043: missing_quorum_or_threshold_definition
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Relayer/validator governance where the quorum threshold is not defined or enforced in the contract, allowing a single relayer to sign for the entire set. `threshold` variable not initialized or not checked in signature counting. No minimum relayer count enforced.
- **Detection Heuristic**:
  1. Find relayer/validator set definitions and quorum threshold storage.
  2. Check: is `threshold` set to a non-zero value at initialization?
  3. Check: is `threshold` enforced in message processing (validSignatures >= threshold)?
  4. Check: can threshold be set to 1 (or 0) by admin, defeating multi-party security?
- **Failure Mode**: Single relayer controls entire bridge with no multi-party safety. Or threshold initialized to zero, meaning any message (including forged ones) is accepted without any signature.
- **Common Contexts**: Bridge Updates lack of quorum definition (H-387), Pheasant Network lack of threshold enforcement, Chakra `SettlementSignatureVerifier` duplicate signatures (H-03).

---

## BRIDGE-044: cross_chain_erc4626_share_rate_divergence
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: ERC-4626 vault tokens bridged cross-chain where `convertToShares()` / `convertToAssets()` on source and destination chains use independently-updating exchange rates. Share value on destination chain diverges from source after yield accrual. `stUSDC` cross-chain share transfer using source-chain rate applied on destination.
- **Detection Heuristic**:
  1. Find ERC-4626 tokens that are cross-chain transferable.
  2. Check: is the amount bridged in `shares` or `assets`?
  3. If `shares`: verify that destination chain correctly interprets the share amount using its own current exchange rate.
  4. If `assets`: verify that source chain correctly converts to `assets` before bridging.
  5. Check if a synchronization mechanism exists for exchange rates across chains.
- **Failure Mode**: User bridges shares when source-chain rate is 1:1.2. Destination chain has 1:1.1 rate. User receives fewer assets than they deposited. Or vice versa — user exploits rate divergence to arbitrage the bridge.
- **Common Contexts**: stUSDC/Bloom cross-chain share rate divergence (H-06, H-360), D protocol ERC-4626 vault token value loss (H-188), Tensorplex delayed exchange rate (H-377).

---

## Notes on Pattern Distribution

**Severity breakdown of 500 sampled findings**: ~452 HIGH, ~48 MEDIUM (ratio reflects this cluster is dominated by HIGH findings from competitive audit platforms).

**Most impactful pattern clusters**:
1. **Access control gaps** (BRIDGE-007, BRIDGE-028): ~38 findings — most common root cause
2. **Cross-chain debt/accounting errors** (BRIDGE-021, BRIDGE-026, BRIDGE-032): ~38 findings — endemic to cross-chain lending protocols
3. **Message authentication failures** (BRIDGE-001, BRIDGE-002, BRIDGE-003, BRIDGE-014): ~60 findings — signature/replay/source-validation triad
4. **Gas and fee handling** (BRIDGE-004, BRIDGE-013, BRIDGE-017, BRIDGE-022): ~52 findings — pervasive across all bridge types
5. **Failed message recovery** (BRIDGE-005, BRIDGE-029): ~28 findings — critical UX and fund safety issue
