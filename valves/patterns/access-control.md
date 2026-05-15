# Access Control Patterns
> Extracted from 3,557 findings (500 sampled)
> Pattern count: 32

---

## AC-001: missing_function_modifier
- **Frequency**: ~85/500 findings
- **Severity**: HIGH
- **Code Shape**: Public/external function with no `onlyOwner`, `onlyRole`, `onlyAdmin`, or equivalent modifier; function name implies restricted operation (e.g., `setX`, `updateX`, `withdrawX`, `burnX`, `mintX`)
- **Detection Heuristic**:
  1. Enumerate all `public` and `external` functions in scope
  2. For each function, check whether a modifier or `require(msg.sender == ...)` guard is present
  3. Classify function intent: does the name/body imply state-changing admin action (fee setting, token minting, config update, fund withdrawal)?
  4. Cross-reference with docs or comments claiming the function is restricted
  5. If no guard exists on a function that controls assets, roles, or config → CONFIRMED
- **Failure Mode**: Any caller can invoke privileged operations — drain funds, change fees, mint tokens, destroy protocol state
- **Common Contexts**: Token contracts (mint/burn), DeFi protocols (fee setters, reward distributors, staking), bridge contracts (config setters), lending (rate setters)

---

## AC-002: broken_modifier_logic
- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: Modifier exists but contains wrong condition — e.g., `require(msg.sender != owner)` instead of `==`, `||` where `&&` required, always-true tautology, wrong variable compared, wrong role constant
- **Detection Heuristic**:
  1. Read every custom modifier definition (`modifier onlyX(...)`)
  2. For each modifier: evaluate the condition — does it restrict correctly (allowlist) or invert (denylist by mistake)?
  3. Check for `||` in multi-role checks where `&&` would mean "must be both" — `||` means "either OR" which is usually correct but sometimes wrong
  4. Look for `onlyOwnerOrAdmin` modifiers that allow each party to override the other's settings
  5. Test the modifier condition with `msg.sender = attacker_address` — does it pass?
  6. Check modifier is actually applied to intended functions (not just defined)
- **Failure Mode**: Modifier passes for all callers, effectively making the function public, or the wrong logic creates unexpected permission inheritance
- **Common Contexts**: Multi-owner contracts, contracts with admin/operator splits, custom RBAC implementations

---

## AC-003: unprotected_initializer
- **Frequency**: ~22/500 findings
- **Severity**: HIGH
- **Code Shape**: `initialize()`, `init()`, `__init()` function without `initializer` modifier (OZ) or equivalent one-time call guard; upgradeable contracts where implementation contract `initialize()` is callable by anyone
- **Detection Heuristic**:
  1. Search for functions named `initialize`, `init`, `setUp`, `__init` in upgradeable/proxy contracts
  2. Check whether OZ `initializer` modifier is applied OR a boolean flag (`initialized`) is checked
  3. For proxy contracts: verify the IMPLEMENTATION contract's `initialize()` is also protected (not just the proxy's)
  4. Check if `_disableInitializers()` is called in the implementation constructor
  5. Verify no re-initialization path exists (missing `isInitialized` flag reset)
- **Failure Mode**: Attacker calls `initialize()` on the implementation contract, sets themselves as owner, then self-destructs it (UUPS) causing DOS; or takes ownership of proxy
- **Common Contexts**: UUPS proxies, TransparentProxy, BeaconProxy, any upgradeable contract pattern

---

## AC-004: missing_role_setup_in_constructor
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: Contract inherits `AccessControl` or uses `Ownable` but constructor never calls `_setupRole()`, `_grantRole()`, or `_transferOwnership()` with the deployer/admin; role variable left as zero-bytes default
- **Detection Heuristic**:
  1. Find all contracts inheriting `AccessControl`, `AccessControlEnumerable`, or similar
  2. Read the constructor — is `_grantRole(ROLE, msg.sender)` or `_setupRole(ROLE, msg.sender)` called for each defined role?
  3. Check if `DEFAULT_ADMIN_ROLE` is granted — without it, no one can grant other roles
  4. For `Ownable`: verify `_transferOwnership(msg.sender)` or that OZ version auto-assigns in constructor
  5. If any `onlyRole(X)` function exists and `X` was never granted → permanent DOS on that function
- **Failure Mode**: Critical admin functions become permanently uncallable (DOS); no one can manage roles, pause the contract, or collect fees
- **Common Contexts**: Protocol governance, vaults with role-gated withdrawals, staking contracts with admin reward management

---

## AC-005: tx_origin_authentication
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `require(tx.origin == owner)` or `tx.origin == trustedAddress` used as access control; ERC-2771 trusted forwarder pattern where `_msgSender()` is not used instead of `msg.sender`
- **Detection Heuristic**:
  1. Grep for `tx.origin` in all access control checks
  2. Identify if `tx.origin` is used in a security-sensitive context (not just anti-contract guard)
  3. For ERC-2771 contracts: verify all access control uses `_msgSender()` not `msg.sender`
  4. Check if a trusted forwarder can set arbitrary `msg.sender` values allowing impersonation
- **Failure Mode**: Phishing attack: victim signs a malicious tx, attacker's contract is the intermediary; `tx.origin` passes for victim but `msg.sender` would not; full account takeover
- **Common Contexts**: Meta-transaction systems, ERC-2771 relayers, gas station networks

---

## AC-006: single_step_ownership_transfer
- **Frequency**: ~12/500 findings
- **Severity**: HIGH (frequently treated as Medium in practice)
- **Code Shape**: `transferOwnership(address newOwner)` with no pending-owner confirmation step; immediate ownership change without `acceptOwnership()` call by the new owner
- **Detection Heuristic**:
  1. Find all ownership/admin transfer functions (`transferOwnership`, `setAdmin`, `setOwner`)
  2. Check if the pattern is two-step: set `pendingOwner` then require new owner to call `acceptOwnership()`
  3. If single-step: assess risk — can an incorrect address be passed? Is there governance risk?
  4. Verify OZ version used: `Ownable2Step` vs `Ownable` (single-step)
- **Failure Mode**: Typo or social engineering causes ownership to be transferred to wrong/zero address; protocol becomes permanently unmanageable; attacker tricks admin into setting wrong owner
- **Common Contexts**: All protocols with admin functions, particularly high-value vaults and bridges

---

## AC-007: signature_replay_across_contexts
- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: Signature validation missing chain ID, contract address, nonce, function selector, or expiry in signed message hash; same signature reusable in different contract instances or functions
- **Detection Heuristic**:
  1. Find all `ecrecover`, `ECDSA.recover`, `SignatureChecker.isValidSignatureNow` calls
  2. Reconstruct the signed message hash — what fields are included?
  3. Check for: `chainId`, `address(this)`, `nonce[signer]`, `deadline/expiry`, `functionSelector`
  4. If `chainId` missing: cross-chain replay possible
  5. If `address(this)` missing: replay across contract instances
  6. If nonce missing: same signature reusable multiple times
  7. If function selector missing: signature for function A valid for function B
  8. Verify nonce is incremented AFTER successful use
- **Failure Mode**: Attacker replays a legitimate signature to claim rewards multiple times, execute unauthorized actions, or use a signature intended for one function in another
- **Common Contexts**: Permit functions, reward claiming, off-chain order books, governance voting, session key systems

---

## AC-008: callback_receiver_missing_caller_check
- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: `notionalCallback()`, `onERC721Received()`, `flashLoan()` callback, `_lzCompose()`, `receiveMessage()` — functions designed to be called only by a specific trusted contract but missing `require(msg.sender == trustedContract)` check
- **Detection Heuristic**:
  1. Find all callback-style functions: `*Callback`, `*Received`, `*Execute`, `onFlashLoan`, `receiveMessage`, `_lzCompose`
  2. For each: check if there is an `msg.sender` whitelist check against the expected caller (e.g., the lending pool, the bridge contract)
  3. Verify the trusted address is set and cannot be set by an attacker
  4. Check if the callback function has any access restriction at all
  5. Assess what state changes the callback performs — can an attacker trigger them by calling directly?
- **Failure Mode**: Attacker calls the callback directly without going through the expected flow, bypassing precondition checks and manipulating protocol state or draining funds
- **Common Contexts**: Flash loan callbacks, cross-chain message receivers, NFT receiver hooks, LayerZero/Wormhole message handlers

---

## AC-009: incorrect_delegatecall_access_control
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `delegatecall` to arbitrary or attacker-controlled address; `execute(address target, bytes data)` without whitelist validation; precompile authorization bypassed via `delegatecall`
- **Detection Heuristic**:
  1. Find all `delegatecall` usages
  2. Check if the target address is validated against a whitelist or is hardcoded
  3. If target comes from user input: is there a guard? (`require(isApprovedTarget[target])`)
  4. For proxy patterns: verify `_authorizeUpgrade` is protected
  5. Check if `delegatecall` preserves `msg.sender` and what security assumptions that breaks
- **Failure Mode**: Attacker calls execute with malicious contract as target; delegatecall executes in context of the victim contract's storage, draining it or granting the attacker ownership
- **Common Contexts**: Proxy contracts, smart wallets (ERC-4337, ERC-7579), multisig modules, strategy executors

---

## AC-010: permissionless_critical_state_setter
- **Frequency**: ~45/500 findings
- **Severity**: HIGH
- **Code Shape**: `setX(value)`, `updateX(value)`, `configureX(value)` functions that modify protocol-critical parameters (rates, addresses, thresholds, limits) with no access control; function name clearly implies admin-only intent
- **Detection Heuristic**:
  1. List all setter functions (`setX`, `updateX`, `configureX`, `changeX`)
  2. For each: does the function modify a state variable that affects fund safety or protocol economics?
  3. Check: is there ANY access modifier or `require` check on the caller?
  4. If no check: is this by design (e.g., permissionless oracle update) or a bug?
  5. Cross-reference with docs/comments for stated caller restrictions
  6. Compute worst-case impact if an attacker sets the value to min/max
- **Failure Mode**: Anyone can set fee to 100%, set oracle address to attacker contract, set withdrawal threshold to zero, or poison any shared config
- **Common Contexts**: Fee controllers, oracle feed setters, rate parameters, bridge configuration, AMM pool settings

---

## AC-011: role_based_privilege_escalation
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: A role can grant itself higher roles, call `grantRole(ADMIN_ROLE, self)`, or a compromised role can call `setOwner(attacker)` / `addModule(maliciousModule)`; factory/registry admin can steal from user vaults
- **Detection Heuristic**:
  1. Map all roles and their permissions
  2. For each role: can it grant other roles? Can it call `grantRole`? Can it modify its own permissions?
  3. Check: can ROLE_A call any function that ROLE_B (higher privilege) can call?
  4. Look for admin functions that can modify other users' state (withdraw from user accounts, change user settings)
  5. Assess whether a compromised semi-trusted role can escalate to full control
- **Failure Mode**: Compromised operator role grants itself admin, then drains protocol; factory admin calls user-scoped functions to steal assets
- **Common Contexts**: Insurance protocols, vaults with manager roles, factory patterns, DAOs with tiered governance

---

## AC-012: unprotected_upgrade_function
- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `upgradeTo()`, `upgradeToAndCall()`, `diamondCut()` without `onlyOwner`/`onlyAdmin`; `_authorizeUpgrade()` override with empty body; UUPS upgrade callable by anyone
- **Detection Heuristic**:
  1. Find all contracts using `UUPSUpgradeable`, `TransparentUpgradeableProxy`, `Diamond`
  2. For UUPS: verify `_authorizeUpgrade()` is overridden with a non-empty restriction
  3. For Diamond: verify `diamondCut()` has `onlyOwner` or equivalent
  4. For TransparentProxy: verify ProxyAdmin ownership is correctly assigned
  5. Check whether upgrade functions can be called before proxy is initialized
- **Failure Mode**: Attacker upgrades contract to malicious implementation, taking full control of all protocol funds and state
- **Common Contexts**: UUPS proxies, Diamond pattern contracts, any upgradeable protocol

---

## AC-013: missing_access_control_on_burn
- **Frequency**: ~15/500 findings
- **Severity**: HIGH
- **Code Shape**: `burn(address account, uint256 amount)` or `burnFrom(address, amount)` callable by any external address without allowance check or access modifier; token `burn()` without `msg.sender == account` validation
- **Detection Heuristic**:
  1. Find all `burn`, `burnFrom`, `_burn` wrapper functions
  2. Check: does the function require `msg.sender == account` OR `allowance[account][msg.sender] >= amount` OR an admin modifier?
  3. For ERC20Burnable: verify `burnFrom` checks allowance via `_spendAllowance`
  4. For custom tokens: verify the burn caller restriction is correct and complete
  5. Test: can an external address burn tokens belonging to another user?
- **Failure Mode**: Attacker burns tokens of any user, destroying their balance without consent; can be used to grief, manipulate supply, or destroy collateral
- **Common Contexts**: Custom token contracts, stablecoin systems, receipt tokens, bridge tokens

---

## AC-014: permissionless_mint
- **Frequency**: ~20/500 findings
- **Severity**: HIGH
- **Code Shape**: `mint(address to, uint256 amount)` callable by any address; `mintFungible()`, `mintSynth()`, `mintStableCoin()` without caller validation; token minting gated only by collateral check that can be bypassed
- **Detection Heuristic**:
  1. Find all mint functions (`mint`, `mintTo`, `mintFungible`, `mintWithBudget`)
  2. Check: is there a role check (`onlyMinter`, `onlyOwner`) OR a valid collateral/backing check?
  3. If backed by collateral: is the collateral validation sound or bypassable (e.g., fake token address)?
  4. For stablecoins: can a fake CW20/ERC20 token be provided as collateral to mint real stablecoins?
  5. Verify the minter role is correctly implemented (see AC-002 for broken modifier patterns)
- **Failure Mode**: Arbitrary inflation of token supply; attacker mints infinite tokens and dumps them; stablecoin loses backing
- **Common Contexts**: Stablecoins, synthetic assets, receipt tokens, NFT platforms, reward tokens

---

## AC-015: cross_chain_sender_spoofing
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: Cross-chain message handler extracts origin/sender from message payload rather than from transport layer; `msg.sender` preserved through ZkSync aliasing; LayerZero `srcAddress` not validated; `setPeer`/`setTrustedRemote` callable by anyone
- **Detection Heuristic**:
  1. Find all cross-chain message handlers (`receiveMessage`, `_lzReceive`, `ccipReceive`, `receiveWormholeMessages`)
  2. Check: is the sender/origin validated against a stored trusted address?
  3. Verify the trusted address comes from the transport layer (not user-supplied payload)
  4. For LayerZero: check `trustedRemoteLookup` is set and validated in `_lzReceive`
  5. For ZkSync: check if `msg.sender` aliasing behavior breaks trust assumptions
  6. Verify `setPeer`/`setTrustedRemote` has access control
- **Failure Mode**: Attacker sends cross-chain message with forged origin, triggering token mints, state changes, or fund releases on the destination chain
- **Common Contexts**: Cross-chain bridges, LayerZero/CCIP/Wormhole integrations, omnichain NFTs

---

## AC-016: front_runnable_initialization
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: Deployment script or factory does NOT atomically initialize after deployment; `initialize()` called in a separate transaction; bridge/program initializer callable by any first caller
- **Detection Heuristic**:
  1. Check deployment scripts: is `initialize()` called in the same transaction as deployment?
  2. Search for patterns where contract is deployed and initialized in separate txs with a gap
  3. For Solana: check if `Initialize` instruction validates the caller or is open to anyone
  4. Verify `_disableInitializers()` is in implementation constructor for UUPS proxies
  5. Check if any important state is set post-deployment without initialization guards
- **Failure Mode**: Attacker front-runs the `initialize()` call, setting themselves as owner with full control over the protocol
- **Common Contexts**: Factory-deployed contracts, UUPS implementation contracts, bridge programs, any multi-tx deployment

---

## AC-017: unprotected_role_revocation
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `revokeRole(role, account)` callable by anyone (missing `onlyRole(ADMIN_ROLE)`); role removal allows self-removal or removal of other users' roles without governance
- **Detection Heuristic**:
  1. Find `revokeRole`, `renounceRole`, `removeRole`, `revokeApprover` functions
  2. Check: is `revokeRole` restricted to `DEFAULT_ADMIN_ROLE` or equivalent?
  3. For custom role systems: verify the revocation caller is the correct authority
  4. Check if a role holder can prevent their own revocation (by blocking the admin function)
  5. Assess: if an attacker revokes a key role, what breaks?
- **Failure Mode**: Attacker revokes all admin roles (rendering protocol ungovernable) or revokes validator/operator roles to manipulate the system
- **Common Contexts**: DAO contracts, staking systems, validator registries, multisig

---

## AC-018: permissionless_vote_delegation
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `delegate(address to, uint256 amount)` callable by anyone without validating the delegator is `msg.sender`; vote balance can be inflated or redirected by third party
- **Detection Heuristic**:
  1. Find all delegation functions in governance/voting contracts
  2. Check: does `delegate(to)` require `msg.sender` to own the tokens being delegated?
  3. Verify there is no path to delegate someone else's votes without their approval
  4. Check if votes are cleared when a voter is removed from a whitelist/registry
  5. Look for infinite delegation loops or vote-inflation via merge/reset
- **Failure Mode**: Attacker inflates their own vote balance by delegating others' votes to themselves; governance outcome manipulation
- **Common Contexts**: veToken systems, DAO governance, vote-escrow contracts

---

## AC-019: order_update_missing_owner_check
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `updateOrder(orderId, params)`, `cancelOrder(orderId)`, `amendOrder(orderId)` — functions that modify or cancel an order without verifying `msg.sender == order.owner`
- **Detection Heuristic**:
  1. Find all order management functions (update, cancel, amend, close)
  2. For each: extract the order struct and check if `order.owner == msg.sender` is validated
  3. Check if order ID can be passed arbitrarily — can caller specify any orderId?
  4. Verify the function fetches order by ID and validates ownership before modifying
- **Failure Mode**: Attacker cancels or modifies other users' orders; malicious lender retrieves funds early; denial of service on victim's positions
- **Common Contexts**: Perpetuals, order books, lending markets (Maple, Beedle), NFT marketplaces

---

## AC-020: nft_position_missing_owner_check
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `withdrawNft(positionId)`, `closePosition(tokenId)`, `claimNftCollateral(auctionId)` without checking `ownerOf(tokenId) == msg.sender`; NFT position actions usable by any caller
- **Detection Heuristic**:
  1. Find all functions taking a position/token ID that lead to asset transfer
  2. Verify the function checks `ownerOf(tokenId) == msg.sender` or equivalent approval
  3. Check auction completion — is claiming restricted to the winning bidder?
  4. Verify `onERC721Received` doesn't create unauthorized liens or positions
- **Failure Mode**: Attacker steals NFT collateral, claims auction prizes without bidding, takes over Uniswap V3 positions
- **Common Contexts**: NFT-collateralized lending, perp protocols with NFT positions, NFT auctions

---

## AC-021: erc2771_trusted_forwarder_takeover
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: ERC-2771 forwarder set via `setTrustedForwarder(address)` callable by anyone; `_msgSender()` returns arbitrary value from appended calldata; factory contract controlled by trusted forwarder
- **Detection Heuristic**:
  1. Find contracts implementing ERC-2771 (`isTrustedForwarder`, `_msgSender()` override)
  2. Verify `setTrustedForwarder` has access control
  3. Check: can the trusted forwarder append arbitrary bytes to make `_msgSender()` return any address?
  4. Verify all access control in ERC-2771 contracts uses `_msgSender()` not `msg.sender`
  5. Check factory contracts for `msg.sender` vs `_msgSender()` confusion
- **Failure Mode**: Attacker sets themselves as trusted forwarder and impersonates any address, taking over admin functions
- **Common Contexts**: Meta-transaction systems, gas relay networks, ERC-2771 compatible contracts

---

## AC-022: session_key_cross_wallet_reuse
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: Session key enabled without binding it to a specific wallet; `enableSessionKey(key)` doesn't check whether key is already bound to another smart wallet; session key permissions stored in global mapping without wallet prefix
- **Detection Heuristic**:
  1. Find session key management functions (`enableSessionKey`, `addSessionKey`)
  2. Check: is the session key stored in a mapping keyed by `(wallet, sessionKey)` or just `sessionKey`?
  3. Verify the session key validation includes the smart wallet address in the signed message
  4. Check for key reuse across different wallets in the same system
- **Failure Mode**: Attacker enables a key for their own wallet that is already enabled for victim's wallet; then executes transactions as if from victim's wallet
- **Common Contexts**: ERC-4337 account abstraction, modular smart wallets, session key modules

---

## AC-023: unprotected_strategy_migration
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `setYieldStrategy(address)`, `updateStrategy(address)`, `swapYieldSource(address)` callable by owner/admin without timelock or withdrawal protection; old strategy not drained before replacement
- **Detection Heuristic**:
  1. Find strategy/controller replacement functions
  2. Check: is there a timelock or governance delay?
  3. Verify: are user funds withdrawn from old strategy before switching?
  4. Assess: can owner rug-pull by swapping strategy to zero-yield or malicious contract?
  5. Check if `onlyOwnerOrAssetManager` modifier creates unexpected rug risk
- **Failure Mode**: Owner instantly swaps to malicious strategy, stealing all deposited funds; or old strategy tokens become stranded
- **Common Contexts**: Yield aggregators, vaults with pluggable strategies, ERC-4626 vaults

---

## AC-024: missing_allowance_check_in_withdraw
- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: ERC4626 `redeem(shares, receiver, owner)` / `withdraw(assets, receiver, owner)` — when `owner != msg.sender`, `_spendAllowance(owner, msg.sender, shares)` is skipped; Pool `withdraw` doesn't check allowance
- **Detection Heuristic**:
  1. Find `redeem`, `withdraw`, `transferFrom`-style functions with a separate `owner`/`from` parameter
  2. Check: when `owner != msg.sender`, is `allowance[owner][msg.sender]` checked and decremented?
  3. For ERC4626: verify `_spendAllowance` is called in `_withdraw` helper when appropriate
  4. Check if attacker can set `receiver = attacker` and `owner = victim` to steal funds
- **Failure Mode**: Any caller can withdraw anyone's vault shares/assets without approval
- **Common Contexts**: ERC4626 vaults, lending pools, any protocol with ERC20-style share accounting

---

## AC-025: deterministic_address_cross_chain_collision
- **Frequency**: ~3/500 findings
- **Severity**: HIGH
- **Code Shape**: `CREATE2` deployed contracts at predictable addresses; cross-chain deployment assumes same address = same controller; malicious token deployed at deterministic address on different chain
- **Detection Heuristic**:
  1. Find `CREATE2` deployments with fixed or predictable salts
  2. Assess: is the same address on chain A trusted to be controlled by the same entity on chain B?
  3. Check if bridge authentication relies on address matching across chains
  4. Verify `msg.sender` preservation semantics on ZkSync vs other chains
- **Failure Mode**: Attacker pre-deploys malicious contract at the same deterministic address on target chain and exploits cross-chain trust assumption
- **Common Contexts**: Cross-chain protocols, bridges, omnichain deployments using CREATE2

---

## AC-026: permissionless_nonce_manipulation
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `incrementNonce(address account)` or `invalidateNonce(account, nonce)` callable by anyone; nonce can be advanced for arbitrary accounts without their consent
- **Detection Heuristic**:
  1. Find nonce management functions
  2. Check: can an external caller modify another account's nonce?
  3. If yes: what happens to pending signed messages when nonce is advanced?
  4. Verify nonce can only be incremented by the account owner or through an authorized flow
- **Failure Mode**: Attacker invalidates victim's signed orders or permits by advancing their nonce, causing DOS or forcing re-signing
- **Common Contexts**: Settlement contracts, permit systems, off-chain order books

---

## AC-027: paused_contract_bypass
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: Contract has `pause()` mechanism but critical functions lack `whenNotPaused` modifier; `Pausable` inherited but `_pause()` never called or missing on key functions; `SimpleShares` executes during pause
- **Detection Heuristic**:
  1. Find contracts inheriting `Pausable` or implementing a paused state
  2. List all state-changing functions — does each have `whenNotPaused` where appropriate?
  3. Check: can tokens be locked forever if pause is triggered (no recovery path)?
  4. Verify pause doesn't create a one-way door (no withdraw path while paused)
- **Failure Mode**: Attacker or malicious admin pauses contract while maintaining a backdoor execution path; or pausing permanently traps user funds
- **Common Contexts**: Emergency systems, token contracts, lending markets

---

## AC-028: shared_storage_namespace_collision
- **Frequency**: ~6/500 findings
- **Severity**: HIGH
- **Code Shape**: Diamond/proxy pattern with multiple facets sharing storage slots; namespace identifiers derived from insecure hashes; EternalStorage pattern allows any registered contract to write any key
- **Detection Heuristic**:
  1. For Diamond/proxy: check if storage structs use EIP-2535 namespaced storage (`bytes32 constant STORAGE_SLOT`)
  2. Verify storage slot computation is collision-resistant
  3. For EternalStorage: check if ANY registered contract can write to ANY storage key
  4. Check namespace separation for game/world contracts — can contracts write to each other's namespaces?
  5. Look for global variable usage in upgradeable contracts (use `getStorage()` pattern instead)
- **Failure Mode**: Facet A overwrites Facet B's storage; attacker contract writes to admin storage slot; namespace collision corrupts protocol state
- **Common Contexts**: Diamond pattern protocols, EternalStorage patterns, on-chain games (MUD), upgradeable systems

---

## AC-029: missing_access_control_on_critical_process_trigger
- **Frequency**: ~20/500 findings
- **Severity**: HIGH
- **Code Shape**: `distribute()`, `harvest()`, `rebase()`, `drawRandomNumber()`, `epochEmission()`, `cleanUpOrders()` — accounting/settlement functions intended for internal use but callable by anyone, causing accounting corruption
- **Detection Heuristic**:
  1. Find functions that update internal accounting, distribute rewards, or trigger settlement
  2. Check: is there an access modifier or caller restriction?
  3. Assess idempotency: can calling the function at wrong time or repeatedly corrupt accounting?
  4. Check if the function can be front-run to disrupt protocol state before legitimate calls
  5. Verify functions that trigger randomness or epochs have appropriate caller restrictions
- **Failure Mode**: Attacker calls `distribute()` at wrong time, spamming with zero amount to corrupt accounting; `rebase()` called repeatedly drains buffer; `drawRandomNumber()` manipulates lottery
- **Common Contexts**: Reward distributors, rebase tokens, epoch-based systems, lottery contracts, lending order management

---

## AC-030: excessive_owner_privileges
- **Frequency**: ~20/500 findings
- **Severity**: HIGH (often Medium in practice due to trust assumptions)
- **Code Shape**: Owner can call arbitrary `execute(target, data)`, set protocol addresses to attacker contracts, withdraw all reserves, bypass time locks, or unilaterally change config without governance; single EOA controls entire protocol
- **Detection Heuristic**:
  1. Map all `onlyOwner` functions
  2. Assess blast radius: what is the worst-case owner action?
  3. Check: can owner steal user funds directly (withdraw, transfer, drain)?
  4. Can owner set addresses to malicious contracts (strategy, oracle, controller)?
  5. Is there a timelock or multisig? If single EOA with private key risk → centralization finding
  6. Check for undocumented/backdoor functions that owner can call
- **Failure Mode**: Malicious or compromised owner drains all funds, upgrades to malicious contract, or freezes user withdrawals permanently
- **Common Contexts**: All protocols, especially early-stage; vaults; bridges; token contracts

---

## AC-031: hardcoded_private_key_or_credential
- **Frequency**: ~3/500 findings
- **Severity**: HIGH
- **Code Shape**: `PRIVATE_KEY=0xabc...` in Makefile, `.env`, deployment scripts committed to repository; sensitive data exposed in logs via `console.error`, `print`, or stdout
- **Detection Heuristic**:
  1. Search repository for common secret patterns: `PRIVATE_KEY`, `SECRET`, `PASSWORD`, `MNEMONIC` in non-`.gitignore`d files
  2. Check Makefile, deployment scripts, `.env.example` for embedded secrets
  3. Review logging/error handling for sensitive data output
  4. Check if mobile/desktop wallet stores keys in memory longer than necessary
- **Failure Mode**: Attacker extracts private key from public repo; signs transactions on behalf of protocol deployer; steals all controlled funds
- **Common Contexts**: Deployment infrastructure, wallet implementations, backend services

---

## AC-032: pda_or_account_validation_missing_solana
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: Solana instruction accepts account without validating it is the correct PDA (missing `seeds`, `bump` constraints); sysvar account passed without `check_id()`; `staking_info` PDA seeded only by user pubkey (spoofable)
- **Detection Heuristic**:
  1. For each Solana instruction, enumerate all account parameters
  2. For each account: is it validated as the expected PDA with correct seeds and bump?
  3. Check sysvar accounts: is `check_id(SYSVAR_INSTRUCTIONS_PUBKEY)` called?
  4. For Anchor: check `#[account(seeds=[...], bump)]` constraints are present
  5. Verify PDA seeds cannot be controlled by attacker to produce a collision
  6. Check if `staking_info` or similar accounts are seeded with user-controlled values only
- **Failure Mode**: Attacker passes a forged PDA or incorrect account; program operates on attacker-controlled data instead of legitimate program state; allows account spoofing for staking/reward manipulation
- **Common Contexts**: Solana staking programs, bridge validators, composable vaults, any Solana program with PDA accounts
