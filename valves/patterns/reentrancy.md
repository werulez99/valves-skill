# Reentrancy Patterns
> Extracted from 3,088 findings (500 sampled)
> Pattern count: 18

---

## REENT-001: classic_eth_withdrawal_reentrancy

- **Frequency**: ~55/500 findings
- **Severity**: HIGH
- **Code Shape**: `call{value:}()` or `.transfer()` or `.send()` before state update; `balances[msg.sender] = 0` or `delete pending[msg.sender]` or `totalWithdrawn +=` placed AFTER the ETH send; no `nonReentrant` on withdraw/claim/emergencyWithdraw function
- **Detection Heuristic**:
  1. Grep for `function (withdraw|claim|emergencyWithdraw|sellETH|sendFunds)` in contract
  2. Inside each function, extract the ordering of: (a) any `call{value:}` / `transfer` / `send`, (b) state mutations (balance zeroing, mapping deletes, counter decrements)
  3. If (a) precedes (b) → CONFIRMED violation of CEI
  4. Check whether `nonReentrant` modifier is present; if absent → HIGH
  5. Verify there is no callback-safe wrapper (e.g., push-pull pattern)
  6. Confirm caller-controlled recipient address (e.g., `msg.sender`, `recipient`) so attacker can inject malicious fallback
- **Failure Mode**: Attacker deploys contract with `receive()` / `fallback()` that re-calls the withdraw function before the balance mapping is zeroed, draining the vault in one transaction. Classic fund drainage.
- **Common Contexts**: ETH staking/liquid staking (Stakehouse, Lybra, Rocket Pool), auction settlement, dividend/reward distribution, vesting contract ETH claims, NFT marketplace ETH payouts

---

## REENT-002: erc777_tokensToSend_hook_reentrancy

- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `IERC20(token).transfer(user, amount)` or `safeTransfer` where `token` could be ERC777; state (e.g., `balances[user]`, `totalSupply`, distributor accounting) updated AFTER the transfer; no check that `token` is not ERC777; `ERC1820Registry` lookup absent
- **Detection Heuristic**:
  1. Identify all `transfer` / `safeTransfer` / `transferFrom` calls in the contract
  2. For each, check whether the token address is user-supplied or set by governance (i.e., arbitrary or semi-trusted)
  3. Check if the state (user balance, epoch accounting, fee ledger) is updated AFTER the ERC20 transfer — CEI order violation
  4. Determine if there is an ERC777 token deployed at the address (or if the token whitelist allows ERC777)
  5. Confirm `tokensToSend` / `tokensReceived` hooks exist on the ERC777 standard and that the hook can call back into the vulnerable contract
  6. No `nonReentrant` guard on the outer function → CONFIRMED
- **Failure Mode**: ERC777 token fires `tokensToSend` hook before transfer completes; hook calls back into the protocol (claim, buy, distribute) before balance is decremented, allowing double-spend or full drain. Seen draining SFPM fees, token distributors, staking reward contracts.
- **Common Contexts**: Token distributors (PartyDAO), NFT marketplaces (SFPM/Panoptic), staking reward contracts, DEX pools with permissioned token lists

---

## REENT-003: erc721_onERC721Received_reentrancy

- **Frequency**: ~28/500 findings
- **Severity**: HIGH
- **Code Shape**: `safeTransferFrom(from, to, tokenId)` or `safeMint(to, tokenId)` before critical state update; minting counter (`totalMinted`, `collectionSize`) or whitelist flag (`hasMinted[msg.sender]`) updated AFTER the safe call; callback = `onERC721Received` executed on recipient contract before state settles
- **Detection Heuristic**:
  1. Grep for `_safeMint` / `safeTransferFrom` in mint/purchase/claim functions
  2. Identify state that LIMITS minting (supply cap, per-wallet limit, whitelist flag, price paid flag)
  3. Check if that state is updated BEFORE or AFTER the `_safeMint` call
  4. If AFTER → attacker's `onERC721Received` can re-enter the mint function while cap is still not hit
  5. Verify the mint function has no `nonReentrant` modifier
  6. Simulate: deposit malicious contract → call mint → callback re-enters → supply cap bypassed
- **Failure Mode**: Attacker bypasses `maxCollectionPurchases` / `maxTokensPerUser` / whitelist limits, minting unlimited NFTs in a single transaction by re-entering before the counter is incremented. Seen in NextGen, Vallarok, Joyn, SeaDrop, reNFT.
- **Common Contexts**: NFT minting (whitelist mint, FCFS mint), NFT rental protocols (ERC1155 hijack in reNFT), NFT-backed lending collateral callbacks, ERC721 gauge/reward collateral

---

## REENT-004: cross_function_shared_state_reentrancy

- **Frequency**: ~35/500 findings
- **Severity**: HIGH
- **Code Shape**: Function A makes external call → callback enters Function B (not A) which reads/modifies shared state variable (e.g., `totalDeposits`, `shares`, `exchangeRate`) that A has not yet updated; both A and B guarded by separate `nonReentrant` OR neither is; no cross-function mutex
- **Detection Heuristic**:
  1. Map all shared state variables (balances, totals, share prices, ratios)
  2. For each external call site, identify which shared variables are NOT yet updated at the call point
  3. Enumerate all OTHER functions that READ those same shared variables
  4. Check if those other functions can be invoked during the callback window
  5. Confirm that a single `nonReentrant` on function A does NOT protect function B from being called during A's execution
  6. Severity: if B can be used to extract value based on stale shared state → HIGH
- **Failure Mode**: During Function A's external call, attacker calls Function B which relies on the same accounting state (e.g., `totalAssets`, `sharePrice`, `exchangeRate`) that A has not yet committed. B grants advantage (overvalued shares, inflated collateral, skipped fees) based on stale data.
- **Common Contexts**: Vault deposit/withdraw pairs (Sandclock, Gamma, yVault), AMM addLiquidity/removeLiquidity, lending protocol borrow/repay, staking claim/stake, rebalance hook pairs (Bunni)

---

## REENT-005: read_only_reentrancy_oracle_price_manipulation

- **Frequency**: ~15/500 findings
- **Severity**: HIGH
- **Code Shape**: Protocol reads `balanceOf` / `get_virtual_price()` / `getRate()` / `totalAssets()` from Balancer/Curve/external pool as an oracle price; that read happens DURING a Balancer/Curve callback (e.g., inside `beforeSwap`, `receive` callback, `flashLoan` callback) before the pool's internal state is finalized; no reentrancy lock on the oracle read path; `nonReentrant` on the pool does not protect callers
- **Detection Heuristic**:
  1. Identify any price/rate oracle reads: `IBalancerVault.getPoolTokens()`, `ICurvePool.get_virtual_price()`, LP token price formulas using `totalSupply` + `balanceOf`
  2. Check if those reads are inside a function that can be invoked as a callback FROM the Balancer/Curve pool (e.g., flashLoan callback, `receiveFlashLoan`, Curve remove_liquidity callback)
  3. Verify that Balancer's reentrancy guard on the vault does NOT apply to read functions — read-only functions are not locked
  4. Confirm attacker can call the price-reading function while the pool's state is mid-update (e.g., during a flashLoan, mid-exit)
  5. Price read returns stale/mid-transaction value → protocol makes incorrect decision (overvalued collateral, incorrect liquidation threshold)
- **Failure Mode**: While Balancer/Curve pool state is mid-update (during a flash loan or exit), attacker forces the target protocol to read an inflated/deflated price. Protocol mints excess tokens, allows overborrowing, or blocks correct liquidations. Seen in Blueberry Update, OpalProtocol, XPress, Cron Finance.
- **Common Contexts**: Lending protocols using BPT/CRV LP as collateral oracle, oracle aggregators reading Balancer pool reserves, protocols pricing assets via DEX spot price during callbacks

---

## REENT-006: callback_auth_bypass_flashloan_initiator

- **Frequency**: ~22/500 findings
- **Severity**: HIGH
- **Code Shape**: Flash loan callback function (e.g., `flashLoan`, `executeOperation`, `receiveFlashLoan`, `onFlashLoan`) checks `msg.sender` is the flash loan PROVIDER but NOT whether the flash loan was initiated by the expected initiator; `initiator` parameter ignored or not validated against a stored address; arbitrary caller can trigger callback with malicious data
- **Detection Heuristic**:
  1. Find all flash loan callback implementations: `executeOperation`, `onFlashLoan`, `receiveFlashLoan`, `uniswapV3FlashCallback`, `pancakeV3FlashCallback`
  2. Check access control: does the function verify `msg.sender == lendingPool/vault`? Does it also verify `initiator == address(this)` or a trusted address?
  3. If `initiator` check is absent → anyone can call the flash loan pool with `receiver=VulnerableContract` and inject arbitrary calldata into the callback
  4. Trace what the callback does with the injected data (arbitrary function call, address parameter, asset selection)
  5. Determine if the action in the callback can drain, manipulate, or bypass access control
- **Failure Mode**: Attacker triggers a flash loan from the lending pool specifying the target contract as receiver. Target's callback executes with attacker-controlled calldata, bypassing normal access control. Used to operate on other users' positions, drain internal balances, or bypass authorization. Seen in Stakewise (LeverageStrategy), Wido Comet, Fuji Protocol.
- **Common Contexts**: Flash loan wrapper contracts, leveraged yield strategies, collateral swap helpers, bridge adapters using flash loans as funding mechanism

---

## REENT-007: reentrancy_via_nft_safe_transfer_during_liquidation

- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: Liquidation function calls `safeTransferFrom(collateralNFT, borrower, liquidator)` or triggers marketplace purchase before updating debt state; borrower is an ERC721-receiving contract with `onERC721Received` hook; protocol state (debt, collateral balance, liquidation flag) is not committed before NFT transfer; no `nonReentrant` on liquidation path
- **Detection Heuristic**:
  1. Find liquidation/auction-settlement functions that transfer NFT collateral
  2. Check if `safeTransferFrom` or `safeMint` is used (triggers `onERC721Received`)
  3. Verify that all debt/collateral accounting is updated BEFORE the NFT transfer
  4. Check if the borrower's contract (as NFT recipient) could re-enter: call `removeCollateral`, `borrow` again, or invoke another liquidation
  5. Confirm no `nonReentrant` guard on the outer function or on the functions accessible during the callback
  6. Map attacker-controlled state that can be read during the re-entry window
- **Failure Mode**: Borrower's contract receives NFT callback during liquidation, re-enters to remove remaining collateral or take over another vault's debt before the liquidation accounting settles. Combined effect: collateral stolen, bad debt created. Seen in Backed Protocol, Lyra Finance, Astaria.
- **Common Contexts**: NFT-backed lending (Backed, Particle, Astaria), NFT rental/escrow protocols, NFT auction settlement systems

---

## REENT-008: signature_replay_via_nonce_update_after_callback

- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: Signature nonce incremented AFTER external call in signed operation execution; `nonces[msg.sender]++` or `usedNonces[hash] = true` placed after `target.call(data)` or token transfer; same signature can be reused within the callback window; applies to EIP-712, permit, session-based signatures
- **Detection Heuristic**:
  1. Find functions that consume a signature (verify ECDSA signature against nonce/hash)
  2. Locate where the nonce/hash is marked as used: `nonces[signer]++`, `usedHashes[hash] = true`
  3. Identify any external call or token transfer that happens BEFORE that nonce update
  4. If external call precedes nonce invalidation → re-entrancy during callback can replay the same signature
  5. Check if callback recipient is attacker-controlled (msg.sender, user-provided address)
  6. Demonstrate: sign once, call, during callback call again with same signature → nonce still valid → second execution
- **Failure Mode**: Attacker crafts a signed operation (withdraw, execute, session call) that has a callback. During callback execution, replays the same signature (nonce not yet consumed). Result: double-execution, double-withdrawal, unauthorized repeated operation. Seen in BLS Wallet, Sequence (session calls), SKALE (cross-chain message replay).
- **Common Contexts**: Meta-transaction relayers, session-key wallet contracts, cross-chain message bridges, NFT marketplace signed orders, permit-based protocols

---

## REENT-009: reentrancy_during_auction_settlement

- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: `settleAuction()` / `settleVault()` / `purchaseLiquidationAuctionNFT()` sends ETH or tokens to winner/bidder before marking auction as settled (`auctionSettled[id] = true`, deleting `auctions[id]`); external ETH send triggers fallback; no mutex protecting the settlement state; auctionId reuse possible
- **Detection Heuristic**:
  1. Find auction settlement functions: `settle`, `settleAuction`, `purchaseLiquidation`, `claimAuction`
  2. Map state transitions: what sets the auction as "done" (delete mapping, set boolean, clear struct)
  3. Verify that state transition happens BEFORE any ETH/token sends to winner or seller
  4. Check if the winner is a malicious contract that can re-enter `settle` with same auctionId
  5. Identify whether re-entry can double-claim tokens, drain trigger fees, bypass timelock injection (publisher re-entering to inject malicious index)
  6. Look specifically for the pattern: approval given to auction contract + `settleAuction` draining approved funds via re-entry
- **Failure Mode**: Attacker as winning bidder (or malicious publisher) re-enters settlement before the auction state is cleared, double-claiming tokens, stealing trigger fees from other auctions, or injecting a malicious index bypassing timelock. Seen in Kuiper (index manipulation), DCS/Cega (vault settlement), Gondi (triggerFee theft), Backed Protocol.
- **Common Contexts**: NFT auction protocols, structured product vaults (DCS), lending protocol collateral auctions, basket/index rebalancing auctions

---

## REENT-010: cross_contract_reentrancy_multi_pool_accounting

- **Frequency**: ~20/500 findings
- **Severity**: HIGH
- **Code Shape**: Protocol calls external contract (pool, strategy, bridge) → external contract calls BACK into a DIFFERENT function on the SAME or RELATED protocol contract; the re-entered function reads shared accounting state (total deposits, global debt, reserve ratio) that is inconsistent mid-transaction; cross-contract reentrancy guard absent (guards only protect within a single contract's storage slot)
- **Detection Heuristic**:
  1. Identify all external contract calls in the protocol (strategy deposits, bridge sends, pool liquidity calls)
  2. For each, trace if the called contract can call back into ANY function of the protocol
  3. List ALL state variables shared across the two contracts (via global storage, proxy pattern, or direct reference)
  4. Check if those shared variables are in an inconsistent intermediate state at the call point
  5. A single `nonReentrant` on one contract's function does NOT prevent re-entry into a sibling contract → verify cross-contract isolation
  6. Severity: can re-entry manipulate totalAssets, borrowingPower, or settlement outcome? → HIGH/CRIT
- **Failure Mode**: Protocol A calls Strategy B → Strategy B calls Protocol C (related) or back into Protocol A's sibling contract → reads corrupted shared state → creates inflated collateral, double-counts assets, manipulates settlement. Seen in Autonomint CDS withdrawal (H-24), Notional Exponent GenericERC4626 withdrawal (H-1), YakSwapCell cross-function reentrancy.
- **Common Contexts**: Multi-pool lending (cross-CDS, cross-vault), yield aggregator strategies, cross-contract bridge accounting, staking pools that delegate to external reward contracts

---

## REENT-011: vyper_compiler_reentrancy_guard_bypass

- **Frequency**: ~3/500 findings
- **Severity**: HIGH (Critical)
- **Code Shape**: Vyper contracts using compiler version 0.2.15, 0.2.16, or 0.3.0 with `@nonreentrant` decorator; the decorator's lock is NOT correctly reset after exceptions in certain call patterns; Curve pools using old Vyper versions; `meta_pool` composed with old `base_pool` where Vyper bug is triggered
- **Detection Heuristic**:
  1. Check Vyper compiler version in `@version` pragma at top of `.vy` files
  2. Flag versions 0.2.15, 0.2.16, 0.3.0 as vulnerable to the known reentrancy guard bypass
  3. Check if the contract uses `@nonreentrant("lock")` — the decorator in these versions can be bypassed
  4. For Curve: check if `meta_pool` references a `base_pool` compiled with vulnerable Vyper
  5. Verify the contract is deployed (check on-chain bytecode matches vulnerable compiler output)
  6. Report even if no obvious attacker entry point — the guard provides zero protection
- **Failure Mode**: Reentrancy guard decorator silently fails to prevent re-entry. Any function marked `@nonreentrant` can be re-entered via callbacks. In Curve meta-pools, the base pool's guard failure exposes the meta-pool to read-only reentrancy as well. Seen in Vetenet (C-02), Curve Finance meta_pool with old base_pool.
- **Common Contexts**: Curve Finance forks, Vyper-based stableswap pools, any Vyper DeFi primitive from 2021-2022 era using these compiler versions

---

## REENT-012: reentrancy_during_nft_mint_bypassing_supply_cap

- **Frequency**: ~20/500 findings  
- **Severity**: HIGH
- **Code Shape**: NFT mint function: (1) checks `totalMinted < maxSupply` or `minted[user] < limit`, (2) calls `_safeMint(to, tokenId)` which invokes `onERC721Received`, (3) increments `totalMinted++` or `minted[user]++` AFTER the safe mint; `to` is attacker-controlled contract; no `nonReentrant` on mint function
- **Detection Heuristic**:
  1. Find all `_safeMint` / `safeTransferFrom` in minting functions
  2. Identify the supply/wallet cap check that precedes the mint call
  3. Determine where the counter is incremented: before or after `_safeMint`?
  4. If after → during `onERC721Received` callback, counter is still at pre-mint value → cap check still passes
  5. Attacker loop: contract receives NFT → callback calls mint again → counter still 0 → loops until supply exhausted
  6. No `nonReentrant` modifier → CONFIRMED
- **Failure Mode**: Attacker mints entire NFT collection supply in one transaction, bypassing per-wallet limits or total supply caps, because the counter is incremented after `_safeMint` which already calls back into the mint function. Seen in NextGen (H-01), Vallarok (H-01), Babylon (BAB-3), SeaDrop, Trugly Labs MEME404, Honeyjar (H-02).
- **Common Contexts**: NFT minting contracts (whitelistMint, FCFSMint, partnerFreeMint), limited-edition NFT collections, NFT-gated protocols

---

## REENT-013: reentrancy_guard_conflict_dos

- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: Two functions both marked `nonReentrant` where Function A calls Function B internally or via a helper; the `nonReentrant` guard's storage slot is already set when A calls B → B's `nonReentrant` check reverts; legitimate protocol operations (liquidation, reward distribution) permanently broken; OR a receive() function marked `nonReentrant` prevents ETH withdrawal callbacks from completing
- **Detection Heuristic**:
  1. Map all `nonReentrant` (or `noReentrant`)-decorated functions
  2. Find internal call chains where a `nonReentrant` function (A) calls ANOTHER `nonReentrant` function (B) through the same reentrancy guard storage slot
  3. OpenZeppelin `ReentrancyGuard`: `_status = ENTERED` → B checks `_status != ENTERED` → reverts
  4. Also check: `receive()` marked `nonReentrant` — any contract sending ETH via `call` that triggers `receive()` while the calling function also holds the lock will be permanently rejected
  5. Verify this blocks critical operations like `liquidate()` (August protocol), ETH withdrawals from EigenLayer (Renzo H-03)
  6. Flag where `nonReentrant` is applied to a `receive()` or `fallback()` that must be callable during withdrawal flows
- **Failure Mode**: Protocol's own `nonReentrant` guards collide, causing a legitimate operation (liquidation, withdrawal, ETH receipt) to always revert. The vulnerability IS the guard, misapplied. Seen in August ("Two nonReentrancy Modifiers Prevent liquidate()"), Renzo (ETH withdrawals from EigenLayer always fail), Gorples EVM (Reentrancy Protection Leading to DoS).
- **Common Contexts**: Complex protocol flows where liquidation calls sub-functions, yield vault harvest → liquidate chains, EigenLayer withdrawal with ETH receive hooks

---

## REENT-014: reentrancy_via_erc1155_safe_batch_transfer

- **Frequency**: ~6/500 findings
- **Severity**: HIGH
- **Code Shape**: `safeBatchTransferFrom` or `safeTransferFrom` of ERC1155 tokens triggers `onERC1155Received` / `onERC1155BatchReceived` on recipient contract; state (NFT tier mapping, rental status, escrow balance) not finalized before ERC1155 callback; `isApprovedForAll` or specific transfer permissions allow re-entry into stake/rent/distribute function
- **Detection Heuristic**:
  1. Find all ERC1155 `safeTransferFrom` / `safeBatchTransferFrom` in the contract
  2. Determine what state is read by re-enterable functions at the time of the callback
  3. Check if the recipient (`to`) is attacker-controlled or user-supplied
  4. Identify what `onERC1155Received` can do during re-entry: claim same reward, hijack rental, update tier
  5. No `nonReentrant` on the outer function or on the re-enterable functions accessible during callback
  6. Trace: does re-entry during the callback violate any invariant (double-tier assignment, double-claim)?
- **Failure Mode**: Attacker's `onERC1155Received` re-enters the protocol to hijack rental terms, duplicate NFT tier assignments, or double-claim rewards before the ERC1155 transfer finalizes. Seen in reNFT (H-03, ERC1155 hijack), Bridge Mutual (ERC1155 re-entrancy), Trugly Labs (_mintTier reentrancy).
- **Common Contexts**: NFT rental protocols, multi-asset farming contracts, ERC1155-based reward systems, gaming item systems

---

## REENT-015: initialization_function_reentrancy_frontrun

- **Frequency**: ~7/500 findings
- **Severity**: HIGH
- **Code Shape**: `initialize()` function lacks `initializer` modifier OR uses Vyper-era `initialized` flag checked after setting state; factory deploys contract → attacker front-runs initialization with different parameters; proxy pattern where `initialize()` is callable by anyone until first call; no `initializer` / `onlyOwner` or equivalent protection on `initialize`
- **Detection Heuristic**:
  1. Find all `initialize()` / `init()` functions in proxy/upgradeable contracts
  2. Check for `initializer` modifier (OpenZeppelin Initializable) or equivalent one-time execution guard
  3. Verify: is `initialize()` permissionless (no `onlyOwner`, no factory-only check)?
  4. Between contract DEPLOYMENT and first `initialize()` call, can attacker call `initialize()` first with their own parameters (owner, fee recipient, strategy address)?
  5. Also check: can `initialize()` itself be re-entered if it calls an external contract before setting `initialized = true`?
  6. Cross-layer: is the initialization state checked correctly in the implementation vs. proxy storage slot?
- **Failure Mode**: Attacker front-runs `initialize()` to set themselves as owner, set malicious strategy addresses, or misconfigure the protocol. Combined with reentrancy: if `initialize()` makes an external call before setting `initialized = true`, it can be re-initialized. Seen in Hubble (H-01), Hermez, Advanced Blockchain (CrosslayerPortal), Morpho Protocol V1 (implementation destroyed via unprotected initialize).
- **Common Contexts**: Upgradeable proxy deployments, factory-deployed pool contracts, Layer 2 bridge contracts, any protocol using the proxy+initializer pattern

---

## REENT-016: cross_chain_callback_reentrancy

- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: Cross-chain message handler (e.g., `postIncomingMessages`, `receive_cross_chain_callback`, `onReceive`, `lzReceive`) processes a message and makes an external call (token transfer, contract invocation) BEFORE marking the message as processed or updating the cross-chain nonce; same message can be replayed; OR the callback itself triggers a secondary cross-chain message that re-enters the handler before the first completes
- **Detection Heuristic**:
  1. Find cross-chain message handler functions (LayerZero `lzReceive`, Axelar `_execute`, bridge `onReceive`, Chakra `receive_cross_chain_callback`)
  2. Locate where the message ID / nonce is marked as "processed" or "delivered"
  3. Check if that marking happens BEFORE or AFTER the execution of the message payload
  4. If after → during the payload execution, an attacker can send the same message again → double processing
  5. For bridges: check if a message can invoke a contract that sends another cross-chain message back, re-entering the handler
  6. Verify: does `CrossChainMsgStatus` get set to SUCCESS before or after execution? (Chakra H-05 pattern)
- **Failure Mode**: Same cross-chain message processed twice (double-mint, double-transfer), or cross-chain callback re-enters message handling to replay operations. Also: callback marks SUCCESS even if execution failed, locking user funds. Seen in SKALE (MessageProxy replay via reentrancy), Axelar (expressReceiveToken reentry), Chakra (receive_cross_chain_callback setting SUCCESS before execution confirmed), Maia DAO (forceRevert redeposit).
- **Common Contexts**: LayerZero OFT bridges, Axelar GMP handlers, cross-chain settlement protocols (Chakra), L1-L2 bridge contracts, omnichain lending protocols

---

## REENT-017: reentrancy_bypassing_cooldown_or_limit_check

- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: Function enforces rate limit, cooldown period, or per-period cap (`lastClaim[user]`, `epochClaimed[user][epoch]`, `mintedThisRound[user]`) using a check BEFORE external call; the external call (ETH send, ERC777 hook, safe transfer callback) allows re-entry before the limit is updated; attacker bypasses cooldown by re-entering during the callback window
- **Detection Heuristic**:
  1. Find functions with temporal/rate limiting: `require(block.timestamp >= lastClaim[user] + cooldown)`, `require(minted[user] < maxPerWallet)`, `require(!claimed[user])`
  2. Locate the external call in the function (ETH send, token transfer, safe transfer)
  3. Determine if the rate-limit state is set BEFORE or AFTER the external call
  4. If after → re-entry during the call bypasses the limit (limit state still shows "not yet claimed/minted/cooled")
  5. Flash loan variant: attacker borrows tokens, claims rewards at inflated rate, repays — all within one TX
  6. Confirm by tracing: cooldown check → external call (without update) → callback re-enters → cooldown check passes again → duplicate claim
- **Failure Mode**: Attacker bypasses cooldown periods, per-epoch claim limits, or per-wallet minting caps by re-entering during an external call callback. In Phi protocol: reentrancy + flash loan bypasses distribute cooldown, enabling unfair reward extraction. In Boot Finance (H-05): repeated airdrop claims. In AI Arena (H-08): extra fighter NFTs minted during reward claim.
- **Common Contexts**: Airdrop claim contracts, reward distribution (epoch-based), NFT minting with cooldown, flash-loan-integrated reward bypasses, staking reward cooldown mechanisms

---

## REENT-018: reentrancy_in_governance_safe_module_bypass

- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: Safe/Gnosis module or governance contract makes external call (via `execTransactionFromModule`, arbitrary `call`, or `delegatecall`) as part of a guarded operation; the external call recipient can re-enter the Safe to add modules, change signers, or execute transactions BEFORE the original operation's state/checks are finalized; `nonReentrant` absent on module management functions; checks like `moduleEnabled` performed before the call
- **Detection Heuristic**:
  1. Find governance or Safe-related code: `execTransactionFromModule`, `enableModule`, `disableModule`, Safe guard callbacks
  2. Identify external calls made DURING a transaction that has not yet completed its own state updates (module list not yet updated, guard not yet set)
  3. Check if the external call recipient can call back into `enableModule` or similar functions
  4. Verify that module-enabling checks happen before the external call allows re-entry
  5. In Hats protocol: signers trigger transaction → callback → add module before signature-validity check completes
  6. In BLS Wallet: operations re-entered via reentrancy to bypass signature replay protection
- **Failure Mode**: Attacker uses module callback to add a malicious module or modify Safe configuration before the original transaction's authorization checks complete. In Hats (H-3, H-7): signers bypass checks to add unauthorized modules via reentrancy during Safe transaction execution. In BLS Wallet: signature replay via reentrancy.
- **Common Contexts**: Gnosis Safe-based protocol governance, multi-sig module management, DAO treasury execution contracts, on-chain automation bots (Brahma, DeFi Saver)
