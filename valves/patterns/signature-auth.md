# Signature & Authentication Patterns
> Extracted from 4,380 findings (500 sampled)
> Pattern count: 32

---

## SIG-001: signature_replay_no_nonce
- **Frequency**: ~38/500
- **Severity**: HIGH
- **Code Shape**: `ecrecover(hash, v, r, s)` or `ECDSA.recover(hash, sig)` with no `usedNonces[nonce]` mapping or nonce-increment, or nonce tracked globally not per-address
- **Detection Heuristic**:
  1. Find all `ecrecover` / `ECDSA.recover` / `isValidSignature` call sites
  2. Check whether the recovered signer is validated against a nonce that is stored and invalidated after use
  3. If no `nonces[signer]++` or `usedSignatures[hash] = true` guard exists → CONFIRMED
  4. Also check: nonces stored per-signature globally (not per-address) → partial protection only
  5. Check failed-tx paths: if the function can revert after signature consumption but before state commit, the signature is reusable on retry
- **Failure Mode**: Attacker replays a previously valid signature to re-execute a privileged action (claim, withdraw, mint, stake, redeem) an unlimited number of times, draining funds or minting unbounded tokens
- **Common Contexts**: Airdrop/claim contracts, off-chain-signed minting, reward distribution, meta-transactions, cross-chain bridges, certificate controllers, staking-with-backend-signer

---

## SIG-002: cross_chain_replay_missing_chain_id
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: Signed message hash does not include `block.chainid` / `chainId` / `CHAIN_ID`; or domain separator is hardcoded / not recomputed after a fork
- **Detection Heuristic**:
  1. Locate hash construction for signed messages (EIP-712 `encode`, manual `keccak256(abi.encode(...))`)
  2. Check whether `block.chainid` or an equivalent chain identifier is part of the signed payload or the domain separator
  3. Verify the domain separator is computed at runtime (not in the constructor only and cached)
  4. For EIP-2612 permit: confirm `DOMAIN_SEPARATOR()` uses `block.chainid` and recomputes after fork
  5. If chain ID is absent or hardcoded → CONFIRMED replay across chains/forks
- **Failure Mode**: A signature produced on one chain (or before a fork) is valid on another chain, enabling replay-based unauthorized transfers, borrows, or fund extraction
- **Common Contexts**: ERC20Permit / EIP-2612, bridge relayer auth, cross-chain borrow/swap, meta-transactions, oracle signatures

---

## SIG-003: cross_contract_cross_context_replay
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Signed message hash omits the verifying contract address, or the same `domainSeparator` / salt is shared across multiple deployed instances of the same contract
- **Detection Heuristic**:
  1. Extract the hash construction for all user-signed operations
  2. Verify the signing domain includes `verifyingContract: address(this)` (EIP-712) or equivalent
  3. Check whether multiple contract instances (e.g., multiple distribution contracts, multiple staking pools) share the same verifying address or omit it entirely
  4. For ERC-7739: verify `verifyingContract` in rehashing scheme points to the correct address, not a proxy implementation
  5. Cross-org scenarios: verify organization ID or context ID is included in the signed payload
- **Failure Mode**: A signature valid for contract A is replayed against contract B, or used across different organizations / deployment instances, allowing unauthorized operations
- **Common Contexts**: NFT staking multi-instance, cross-org badge/NFT minting, ERC1271 smart accounts, Gnosis Safe modules, distribution contracts

---

## SIG-004: ecrecover_zero_address_unchecked
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: `address signer = ecrecover(hash, v, r, s)` with no subsequent `require(signer != address(0))` check
- **Detection Heuristic**:
  1. Find every call to the raw EVM `ecrecover` precompile (not OpenZeppelin's `ECDSA.recover`)
  2. Check the line immediately after for `require(signer != address(0), ...)` or equivalent
  3. Also check: is the recovered address compared to a whitelist? If `address(0)` is accidentally in the whitelist, crafted invalid sigs pass
  4. Check `TradeValid()` / trade-matching patterns where address(0) maker is treated as valid unminted NFT owner
- **Failure Mode**: A malformed or crafted signature returns `address(0)` from `ecrecover`. If unchecked, a contract that maps `address(0)` to unlimited unminted tokens, or skips ownership checks, can be exploited to forge arbitrary trades or authorizations
- **Common Contexts**: NFT marketplace trade validation, bridge oracles, smart-wallet signature verification, on-chain order books

---

## SIG-005: ecdsa_signature_malleability
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Raw `ecrecover` or signature verification that accepts both `(v, r, s)` and `(v', r, -s mod n)` as valid for the same message; `s` upper-half check absent; EIP-2098 compact signatures not restricted
- **Detection Heuristic**:
  1. Find `ecrecover` usages not wrapped by OpenZeppelin `ECDSA.recover` (which enforces `s` in lower half)
  2. Check whether `s <= secp256k1_N/2` is enforced (EIP-2 / low-S requirement)
  3. Check for EIP-2098 compact signature support (`vs` encoding) — ensure `s` is correctly extracted and validated
  4. For systems that use signature hash as a nonce/tracking key: two malleable variants bypass single-use tracking
  5. Kakarot finding: three valid signatures for same message (extra edge case)
- **Failure Mode**: Attacker takes a valid signature and produces a second valid signature for the same message with different bytes, bypassing nonce-based replay protection or forging authorizations
- **Common Contexts**: Bridge validators, oracle signature schemes, EVM-level signature validation, off-chain order systems

---

## SIG-006: duplicate_signer_in_multisig
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: Multisig / threshold verification loop that increments a counter without checking if a signer address was already counted; no `signers[addr] = true` dedup set
- **Detection Heuristic**:
  1. Find threshold-check loops: `for sig in signatures { signer = recover(sig); validCount++ }`
  2. Check whether each recovered `signer` address is tested against a set of already-seen addresses before incrementing the count
  3. Inspect whether the function accepts a `signatures` array that the caller controls (ordering and duplication possible)
  4. Check whether the array is checked for minimum length — a single signer submitting N copies of the same sig could reach threshold
  5. Also check: MultiSigGenVerifier, BLS threshold checks, HatsSignerGate patterns
- **Failure Mode**: A single malicious signer submits the same signature multiple times, reaching the threshold unilaterally and approving arbitrary transactions
- **Common Contexts**: Oracle aggregators (Muon, Switchboard, Crouton), L2 bridge validators, multisig wallets, consensus vote validation, HatsProtocol Safe guards

---

## SIG-007: eip712_domain_separator_incorrect_construction
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: EIP-712 `domainSeparator` or typed struct hash misses a field, uses wrong type encoding, or `hashStruct` incorrectly encodes dynamic types (array, bytes, string hashed without inner keccak)
- **Detection Heuristic**:
  1. Extract the `DOMAIN_SEPARATOR` and all `TYPE_HASH` constants
  2. Compare type strings against EIP-712 spec: `uint256`, `address`, `bytes32` must be exact; dynamic types (string, bytes) must be inner-keccak'd
  3. Check whether `BatchCompact` / `MultichainCompact` struct hashes match EIP-712 array-hashing rules
  4. Verify `verifyingContract` is included and points to `address(this)` at time of verification (not constructor)
  5. Check whether `salt` or `version` fields expected by the spec are present
- **Failure Mode**: Incorrectly constructed struct hashes produce hash collisions across different message types, or signatures verified against the wrong domain become exploitable
- **Common Contexts**: EIP-712 meta-transactions, permit2 integrations, NFT marketplace order structs, bridge cross-chain message auth, compact order books

---

## SIG-008: untyped_raw_bytes_signing
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Signing `keccak256(abi.encodePacked(param1, param2, ...))` without EIP-712 type prefix; or signing concatenated raw bytes that could collide with another message format
- **Detection Heuristic**:
  1. Find `abi.encodePacked` inside hash construction passed to `ecrecover` or sign()
  2. Check whether the packed encoding could produce the same bytes for different semantic inputs (hash collision via different field lengths/types)
  3. Verify whether `"\x19\x01"` prefix (EIP-191/712) or equivalent domain separation is applied
  4. Look for `bytes memory` parameters that allow arbitrary-length injection into signed payload
- **Failure Mode**: Attacker crafts a message with different semantic content but identical bytes to a legitimate signed message, forging authorization for an unintended operation
- **Common Contexts**: Community escrow signatures, multisig typed data, NFT auction bids, meta-transactions without EIP-712

---

## SIG-009: signed_data_missing_critical_parameters
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: Signature covers only a subset of the transaction parameters; mutable fields (fee multiplier, gas price factor, token amount, slippage, offset, expiry) are excluded from the signed hash
- **Detection Heuristic**:
  1. Enumerate all parameters used in the function call
  2. Find the hash construction for signature verification
  3. For each parameter, verify it is included in the signed payload
  4. Pay special attention to: fee parameters, gas price factors, slippage bounds, nonce, expiry/deadline, token amounts
  5. Check whether array offsets or lengths are verified but not their contents (ABI-decode injection)
- **Failure Mode**: A submitter (relayer, executor) modifies unsigned parameters after the user signed, extracting fees or substituting unfavorable amounts/tokens. User receives less than expected or pays more.
- **Common Contexts**: Meta-transaction relayers, smart wallet executors, DEX order relayers, off-chain oracle submitters, SGX instance registration

---

## SIG-010: signature_front_running_griefing
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: A function accepting a user-provided signature can be called by any `msg.sender`; the signature itself is visible in the mempool; no binding between signature and calling address
- **Detection Heuristic**:
  1. Find `external`/`public` functions that accept a signature as a parameter and execute on behalf of the signer
  2. Check whether `msg.sender` must equal the recovered signer, or whether anyone can submit the signature
  3. Check whether the signed payload includes `msg.sender` or a designated recipient/beneficiary
  4. For fixed-price mint signatures: verify the claim ticket is consumed atomically and not reusable
  5. Look for front-running vectors: DoS (waste the claim), hijack (redirect benefit to attacker), replay after revert
- **Failure Mode**: Attacker sees a valid signature in the mempool, front-runs the transaction, wastes the one-time claim ticket (DoS) or redirects the benefit to themselves
- **Common Contexts**: Fixed-price NFT minting, airdrop claiming, whitelist registration, meta-tx relayers, off-chain oracle message submission

---

## SIG-011: failed_transaction_signature_reuse
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Nonce is consumed / incremented only on success; if the function reverts after signature recovery but before nonce storage, the same nonce + signature is valid on retry
- **Detection Heuristic**:
  1. Find signature-validated functions with multi-step execution that can revert mid-way
  2. Check whether nonce invalidation happens at the START of execution (before any revertible logic) or at the END
  3. Check EIP712MetaTransaction patterns: `executeMetaTransaction` that marks tx as used only on success
  4. Check authentication token patterns that mark tokens as used only on success
  5. Look for conditions that may change between retries, making the reverted tx eventually succeed
- **Failure Mode**: A transaction that failed due to a temporary condition (price moved, liquidity insufficient) can be replayed with the same signature once the condition resolves, executing unintended repeated operations
- **Common Contexts**: Meta-transactions, EIP-712 execute flows, term finance authentication tokens, cross-chain message relaying

---

## SIG-012: nonce_not_per_address
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `mapping(uint256 => bool) usedNonces` (global) instead of `mapping(address => uint256) nonces` (per-user sequential) or `mapping(address => mapping(uint256 => bool))`
- **Detection Heuristic**:
  1. Find nonce storage declarations
  2. Check if the mapping key includes the signer address as a dimension
  3. If `usedNonces[nonce]` is global: two different users can cancel each other's nonces, or a nonce used by user A blocks user B from using the same nonce value
  4. Verify counter-style nonces increment per signer: `nonces[signer]++`
  5. Check for the `authenticate()` pattern where nonces are tracked globally per transaction but not per originating address
- **Failure Mode**: User B can block user A's transaction by using the same nonce first; or attacker can DoS the system by exhausting nonce space; or one user's replay protection fails to isolate from another user's nonces
- **Common Contexts**: Authentication systems, off-chain oracle nonces, meta-transaction managers, settlement contracts

---

## SIG-013: bls_rogue_key_attack
- **Frequency**: ~4/500
- **Severity**: HIGH (CRITICAL in some instances)
- **Code Shape**: BLS public key aggregation without proof-of-possession (PoP) or subgroup membership check; `G1.Add(keys)` without verifying each key is well-formed and the submitter owns the private key
- **Detection Heuristic**:
  1. Find BLS signature aggregation code: `G1.Add`, `bn254.DeserializeG1`, aggregate key construction
  2. Check whether each submitted public key is validated with a proof-of-possession signature
  3. Verify subgroup membership checks are performed (point is on curve and in the correct subgroup)
  4. Check minimum byte length enforcement before deserialization (panics on short inputs)
  5. Look for `processBundle()` patterns that allow key registration during bundle processing
- **Failure Mode**: Attacker registers a crafted public key that, when aggregated with honest keys, produces a combined key the attacker controls, allowing execution of arbitrary transactions without threshold consent
- **Common Contexts**: BLS wallet systems, BLS-based multisig, threshold signature schemes, BLS aggregate oracle validators

---

## SIG-014: mpc_tss_output_validation_missing
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: MPC / TSS output signature or share used without verifying it matches the expected threshold scheme output; no duplicate signer check in TSS round
- **Detection Heuristic**:
  1. Find TSS/MPC signature assembly code
  2. Verify each participant's partial signature is verified against their known public key before aggregation
  3. Check whether duplicate participant shares can be submitted
  4. Verify the final assembled signature is validated against the protocol's public key before use
  5. Look for lack of slashing/penalty mechanism enabling equivocation
- **Failure Mode**: Double-spending attack via forged MPC output; malicious node submits the same share multiple times passing threshold; or assembled signature is used without final verification
- **Common Contexts**: Threshold signature schemes (TSS), cross-chain bridge MPC, Dragonboat consensus, Shardeum shard coordination

---

## SIG-015: initializer_frontrun_no_access_control
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: `initialize()` / `init()` function is `public` or `external` with no deployer-only modifier and no `initializer` guard that ties to `msg.sender == deployer`
- **Detection Heuristic**:
  1. Find `initialize` / `init` functions in proxy-compatible contracts
  2. Verify OpenZeppelin `initializer` modifier or equivalent `initialized` flag with deployer check
  3. Check whether the initializer can be called again after first invocation (re-initialization)
  4. Check whether `swapProxy`, `RocketStorage`, or similar bootstrap contracts allow arbitrary callers before first initialization
  5. Grep for `constructor()` absence in upgradeable contracts (missing `_disableInitializers()`)
- **Failure Mode**: Attacker calls `initialize()` before the legitimate deployer, sets themselves as owner, and gains full control of the contract and all assets it manages
- **Common Contexts**: UUPS/transparent proxies, beacon proxies, Gnosis Safe module initializers, diamond facet initializers

---

## SIG-016: access_control_modifier_bypassed_by_logic_error
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Access control check exists but is bypassed due to: incorrect selector parsing, wrong `calldata` offset, missing modifier on a secondary entry point, `tx.origin` used instead of `msg.sender`, logic gate error (e.g., `||` instead of `&&`)
- **Detection Heuristic**:
  1. List all privileged functions and their access control modifiers
  2. Verify there is no alternative entry point (fallback, low-level call, delegatecall) that bypasses the modifier
  3. Check `calldata` parsing for selector-based dispatch: ABI-decode offset math must be exact
  4. Verify `tx.origin` is NOT used as the sole authentication mechanism
  5. For `_checkSender` style patterns: verify the function selector parsed from calldata matches the actual called function and does not have off-by-one issues
  6. Check misleading modifiers (e.g., `onlyPermit` that also allows `owner`)
- **Failure Mode**: Attacker calls a function through an unexpected path (alternative entry point, crafted calldata) that passes the guard check while performing unauthorized operations
- **Common Contexts**: Smart wallet execute functions, proxy-based access control, meta-tx forwarders, LayerZero message handlers, Magnetar/multicall contracts

---

## SIG-017: role_separation_insufficient_centralization
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: Single owner/admin address controls all privileged operations; no timelock; functions like `destroyAndSend`, `mint`, `burn`, `setPool`, `drain` are callable by a single key
- **Detection Heuristic**:
  1. Find all `onlyOwner` / `onlyAdmin` functions in the contract
  2. Check whether any single role can: (a) change critical parameters AND (b) withdraw/transfer funds AND (c) pause/unpause
  3. Verify timelock enforcements for parameter changes
  4. Check for `tx.origin`-based auth that extends trust to any called contract in the same call chain
  5. Assess whether governance role controls are on a single EOA vs. multisig
- **Failure Mode**: Compromised or malicious owner/admin drains all user funds, mints unlimited tokens, or permanently disables the protocol
- **Common Contexts**: Protocol treasuries, staking contracts, lending pools, bridge operators, NFT minting contracts

---

## SIG-018: governance_proposal_replay_or_bypass
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Proposal ID derived from hash that is wrong/incomplete; cancel function accessible to any signer; timelock admin changeable via proposals without guardian protection; proposals with duplicate actions cannot execute (DoS)
- **Detection Heuristic**:
  1. Find proposal ID generation: verify all proposal fields (targets, values, calldatas, description) are included in the hash
  2. Check whether the cancel function requires the proposer or guardian role, not any signer
  3. Verify proposals with repeated actions (same target+calldata) are handled distinctly (unique IDs per submission)
  4. Check whether a governance proposal can change the `Timelock.admin` to an attacker-controlled address
  5. Verify veto / cancel logic uses the correct hash matching the execution data
- **Failure Mode**: Attacker prevents legitimate proposals from executing (DoS via hash mismatch), vetoes proposals illegitimately, or uses governance to take over Timelock admin
- **Common Contexts**: Governor contracts, Nouns DAO, Compound Governor Alpha, Origin Dollar timelock, ZKsync L1 governance

---

## SIG-019: session_key_impersonation_cross_wallet
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Session key validation does not bind the key to a specific smart wallet address; `SessionProof` structure can be manipulated to change the session role; session key valid for wallet A works against wallet B with same owner
- **Detection Heuristic**:
  1. Find session key registration and validation logic in account abstraction / smart wallet code
  2. Check whether the session key is bound to `address(this)` (the specific smart wallet)
  3. Verify `SessionProof` structure fields that determine role cannot be manipulated by a front-runner
  4. Check whether `validateUserOp` verifies that `userOpHash` matches the actual `userOp` contents
  5. Verify `sender` field in userOp is validated as the expected smart wallet address
- **Failure Mode**: Attacker front-runs session creation to assign a different role, or reuses a session key across different smart wallets, gaining unauthorized execution permissions
- **Common Contexts**: ERC-4337 smart accounts (Biconomy, Etherspot), Infinex session management, Coinbase session keys, SmartSession modules

---

## SIG-020: erc1271_isvalidsignature_replay
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `isValidSignature(bytes32 hash, bytes signature)` implementation does not include the contract address or a per-session/per-account identifier; shared owners can replay across multiple accounts
- **Detection Heuristic**:
  1. Find `isValidSignature` implementations in smart accounts
  2. Check whether the hash passed to `isValidSignature` is domain-separated with `address(this)`
  3. For ERC-7739 rehashing: verify `verifyingContract` in the nested domain is `address(this)`, not the implementation address
  4. Check multi-owner accounts: if two accounts share the same owner set, a sig valid for one is valid for the other
  5. Verify the function returns `0x1626ba7e` ONLY for hashes that were intended for this specific account
- **Failure Mode**: A signature produced for smart account A is replayed against smart account B that shares the same owner(s), authorizing unintended operations on B
- **Common Contexts**: Clave, Safe, Biconomy Nexus, ERC-1271 implementations with shared ownership

---

## SIG-021: enable_mode_signature_ignores_module_type
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Enable mode / module installation signature covers the module address but not the module type; allows installing a validator as an executor or vice versa
- **Detection Heuristic**:
  1. Find `enableMode` / module installation signature verification
  2. Check whether the signed payload includes the module type (validator, executor, hook, fallback)
  3. Verify that a policy registered for `permissionId` A cannot be applied to a different `permissionId` via front-running
  4. Check `SmartSession::enable` patterns where policies are indexed by `permissionId` not `(permissionId, moduleType)`
- **Failure Mode**: Attacker installs a malicious module as a different type (e.g., a hook as a validator), bypassing type-based restrictions and gaining unintended execution or validation power
- **Common Contexts**: Biconomy Nexus modular account, ERC-7579 account module management

---

## SIG-022: kyc_whitelist_validation_bypass
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: KYC/whitelist check is performed off-chain and only the signature is verified on-chain; the signed payload does not bind to the specific operation/beneficiary/amount; whitelist payload covers insufficient fields
- **Detection Heuristic**:
  1. Find whitelist / KYC gating: `_validateWhitelist(sig)`, `verifyKYC(sig)` patterns
  2. Check whether the signed payload includes: caller address, target operation, amount, deadline, chain ID
  3. Check `_validateWhitelist` and `_validateFreeWhitelist` payload calculation: verify actual bytes used match the full expected payload
  4. Look for country restriction bypass via broken identity-to-wallet binding (multiple identity accounts for same user)
  5. Verify that KYC signatures cannot be reused across protocols or campaigns
- **Failure Mode**: User bypasses KYC/geographic restrictions by reusing a KYC signature obtained for a different context, or by exploiting incomplete payload coverage
- **Common Contexts**: Fantium minter, Securitize onramp, Kinto KYC wallet, name service registrars, token sale whitelists

---

## SIG-023: certificate_chain_crl_bypass
- **Frequency**: ~3/500
- **Severity**: HIGH
- **Code Shape**: Certificate chain verification skips CRL (Certificate Revocation List) check under certain path conditions; revoked certificates remain usable
- **Detection Heuristic**:
  1. Find `verifyCertChain` / `verifyCRL` implementations
  2. Verify that the CRL check is enforced for ALL certificate chain positions, not only the leaf
  3. Check conditional logic: are there code paths that skip the CRL check (e.g., when intermediate cert is missing)?
  4. Verify root certificate CRL checks specifically (often forgotten)
- **Failure Mode**: An attacker uses a revoked certificate to authenticate SGX/TLS-based operations, bypassing revocation-based trust controls
- **Common Contexts**: SGX attestation (Automata DCAP), TLS-based bridge authentication, hardware attestation systems

---

## SIG-024: proof_forgery_merkle_weak_construction
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Merkle proof verification uses `keccak256(left ++ right)` without leaf/node domain separation; attacker can craft a valid proof for an arbitrary key/value by constructing a subtree whose hash collides with an internal node
- **Detection Heuristic**:
  1. Find Merkle proof verification code
  2. Check whether leaf nodes and internal nodes use different hash prefixes (e.g., `0x00` vs `0x01` prefix)
  3. Verify that a submitted "leaf" cannot be the same byte length as an internal node, enabling second-preimage attacks
  4. Check proof length validation: minimum depth enforcement
- **Failure Mode**: Attacker presents a forged Merkle proof demonstrating inclusion of an arbitrary key/value pair, bypassing inclusion proofs used for withdrawals or state claims
- **Common Contexts**: Merk proof systems, rollup state proofs, bridge inclusion proofs, airdrop Merkle trees

---

## SIG-025: weak_prng_predictable_randomness
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Randomness derived from `block.timestamp`, `block.number`, `blockhash`, `block.difficulty` / `block.prevrandao` alone, or from user-controllable inputs; VRF output re-rollable by miners
- **Detection Heuristic**:
  1. Find all randomness sources: `block.timestamp`, `blockhash(block.number - 1)`, `keccak256(abi.encodePacked(block.timestamp, msg.sender))`
  2. Check whether a miner or block proposer can influence the output by choosing which block to include the transaction in
  3. For VRF: verify the output cannot be re-rolled by having a miner discard unfavorable blocks
  4. Check whether the random seed is deterministic from public chain state at the time of the reveal transaction
- **Failure Mode**: Attacker (or miner) predicts or manipulates the random outcome to win lotteries, game randomized drops, or manipulate pseudo-random selection mechanisms
- **Common Contexts**: Lottery/jackpot contracts, NFT trait randomization, game outcome determination, settlement coordinate selection

---

## SIG-026: layerzero_gas_channel_block
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: No minimum gas validation for cross-chain messages; `adapterParams` gas value not checked against a minimum; variable gas cost of payload storage not accounted for; blocking the NonBlockingLzApp channel
- **Detection Heuristic**:
  1. Find LayerZero / cross-chain message send functions
  2. Check whether `adapterParams` is validated for minimum gas before sending
  3. Verify the receiving side cannot be blocked: if `lzReceive` reverts, does it properly store in `failedMessages` without blocking the channel?
  4. Check variable-length payload storage: if gas cost depends on payload size, a large payload with minimum gas will always fail, blocking the channel
  5. Verify `NonBlockingLzApp` is correctly inherited and the try/catch pattern is in place
- **Failure Mode**: Attacker sends a cross-chain message with insufficient gas (or large payload), causing permanent revert on the destination, blocking all subsequent messages on that channel
- **Common Contexts**: Tapioca DAO, Decent, LayerZero-based bridges and omnichain protocols

---

## SIG-027: reentrancy_bypass_auth_state
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: State that controls authorization (cooldown, nonce, used-flag, signer status) is updated AFTER an external call to an untrusted contract; no `nonReentrant` modifier; CEI pattern violated
- **Detection Heuristic**:
  1. Find external calls (`transfer`, `safeTransferFrom`, `call`, `_safeMint`) in functions that also update auth state
  2. Check whether the auth-state update (mark signature used, increment nonce, update cooldown) happens BEFORE the external call
  3. Look for ERC-721 `onERC721Received`, ERC-777 `tokensReceived`, ERC-1155 `onERC1155Received` hooks that can re-enter
  4. Check cross-contract reentrancy: contract A calls contract B which calls back into contract C, using stale state in A
  5. Verify `nonReentrant` is present on all paths that modify auth state and make external calls
- **Failure Mode**: Attacker re-enters a function before the authentication state (nonce, cooldown, balance) is updated, performing multiple authorized actions in a single transaction (double-mint, double-claim, flash-loan bypass of cooldown)
- **Common Contexts**: NFT minting with callbacks, staking reward distribution, collateral management, lending repay/remove-collateral

---

## SIG-028: arbitrary_external_call_token_theft
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: A function accepts a user-supplied `target` address and `data` payload and executes `target.call(data)` or `delegatecall` without restricting the target to a whitelist; no selector/target validation
- **Detection Heuristic**:
  1. Find `target.call(data)` patterns where both `target` and `data` are user-controlled
  2. Check whether the target is validated against a whitelist of approved contracts
  3. Verify the function selector in `data` is not restricted (e.g., `approve`, `transfer`, `transferFrom` must be blocked)
  4. Check callback patterns: `IFulfiller::sourceConsideration` callable from within pre/post hooks
  5. For `delegatecall`: verify the target cannot be a user-supplied address
- **Failure Mode**: Attacker supplies a call to `token.approve(attacker, MAX)` or `token.transfer(attacker, balance)` as the payload, draining tokens approved to the contract or owned by the contract
- **Common Contexts**: DEX aggregators (LI.FI, 1inch), meta-tx forwarders, collateral swap contracts, generic bridge facets, Tapioca Magnetar, GuardCM

---

## SIG-029: permit2_integration_errors
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Wrong nonce passed to `Permit2.permit`; `permit2.transferFrom` called without prior `permit2.permit`; incorrect allowance amount or spender set in permit call; ETH stranded because permit2 flow assumes ERC20 only
- **Detection Heuristic**:
  1. Find all `IPermit2.permit(...)` and `IPermit2.transferFrom(...)` calls
  2. Verify the nonce passed to `permit` matches the nonce obtained from `permit2.nonceBitmap` for the user
  3. Check that the `spender` in the permit equals the contract that will call `transferFrom`
  4. Verify ETH-handling code paths are separately handled (permit2 does not support native ETH)
  5. For `addLiquidityPermit2` patterns: ensure ETH is forwarded correctly, not stranded
- **Failure Mode**: Nonce mismatch causes permit calls to fail; wrong spender means `transferFrom` reverts; ETH sent alongside a permit2 call is permanently locked in the router
- **Common Contexts**: DEX routers (Arrakis, Starbase, StarBaseLimitOrder), liquidity management protocols, zap contracts

---

## SIG-030: hash_collision_untyped_multisig
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: Multisig message hash constructed with `abi.encodePacked` of variable-length fields without type separators; different transaction types can produce the same hash; colliding function selector (4-byte) overlap
- **Detection Heuristic**:
  1. Find hash construction in multisig approval flows
  2. Check for `abi.encodePacked` with variable-length arguments (string, bytes, arrays) — these can collide
  3. Look for type tags or domain separators that distinguish different operation types (swap vs. transfer vs. govern)
  4. Check Muon-style `LibMuon` hash schemes: verify each operation type has a unique type-string prefix
  5. Verify 4-byte function selectors used as message IDs are not colliding with other registered functions
- **Failure Mode**: Attacker crafts a message of type A that produces the same hash as an authorized message of type B, forging authorization for an unintended operation type
- **Common Contexts**: Muon oracle (LibMuon), multisig wallets, cross-chain settlement hash schemes, plugin systems (PRBProxy)

---

## SIG-031: signature_bypass_via_chained_sig_checkpoint_disabled
- **Frequency**: ~3/500
- **Severity**: HIGH
- **Code Shape**: Chained signature validation that allows a signer to disable a checkpoint module, then the chained signature skips all checkpoint-based validation while still being accepted
- **Detection Heuristic**:
  1. Find chained / nested signature validation (e.g., Sequence's checkpoint system)
  2. Check whether disabling a checkpoint module via signature exempts that specific transaction from all other checkpoints
  3. Verify that bypassing checkpoints requires explicit approval from ALL required signers, not just one
  4. Check whether the bypass flag is part of the signed payload or set independently
- **Failure Mode**: A signer with partial permissions disables checkpoint validation and executes arbitrary transactions without the usual multi-party approval, bypassing the entire validation stack
- **Common Contexts**: Sequence wallet checkpoint system, advanced multi-layer signature schemes

---

## SIG-032: csrf_missing_on_api_endpoints
- **Frequency**: ~3/500
- **Severity**: HIGH (web2 boundary)
- **Code Shape**: `@csrf_exempt` decorator applied to POST endpoints that execute privileged actions; no CSRF token validation; no `SameSite=Strict` cookie policy
- **Detection Heuristic**:
  1. Find `@csrf_exempt` decorators on POST/PUT/DELETE API endpoints in off-chain infrastructure
  2. Check whether the endpoint performs state-changing operations (trade execution, order submission, withdrawal)
  3. Verify CSRF token is validated for all non-idempotent requests
  4. Check `SameSite` cookie attribute for session tokens
- **Failure Mode**: Attacker hosts a malicious website that triggers a cross-site request to the API endpoint using the victim's authenticated session, executing unauthorized trades or withdrawals
- **Common Contexts**: Off-chain API servers for perp DEXes, order management systems, off-chain governance backends (Hlos)

---

## SIG-033: tx_origin_authentication
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**: `require(tx.origin == authorizedAddress)` used as the sole or primary authentication mechanism; `msg.sender` not checked independently
- **Detection Heuristic**:
  1. Grep for `tx.origin` in require/if conditions
  2. Check whether `tx.origin` is used as the only check (vs. combined with `msg.sender == tx.origin`)
  3. Verify whether any contract can call the protected function through the authorized EOA's transaction
  4. RocketStorage pattern: contracts registered in storage can change any setting because tx.origin is the guardian
- **Failure Mode**: Any contract called by the authorized EOA can invoke the protected function (phishing attack via `tx.origin`); an attacker tricks the authorized user into calling a malicious contract that then calls the protected function
- **Common Contexts**: RocketPool RocketStorage, meta-tx forwarders, admin bootstrap flows

---

## SIG-034: bridge_message_source_validation_missing
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain message receiver does not verify: (a) the sending chain is whitelisted, (b) the sender contract on the source chain is the expected peer, (c) `contract_chain_name` matches the receiver's own chain
- **Detection Heuristic**:
  1. Find cross-chain message receive functions (`lzReceive`, `anyExecute`, `receive_cross_chain_msg`, `completeValidatorChange`)
  2. Check whether the source chain ID is validated against a whitelist
  3. Verify the `_srcAddress` / `from_chain` / sender contract is checked against a known-good peer address
  4. Check whether the receiver verifies its own chain name / chain ID matches what the message expects
  5. Look for missing `from_chain` in validator signature: allows replaying a callback from chain A as if from chain B
- **Failure Mode**: Attacker sends a forged cross-chain message from an arbitrary chain or spoofs the source address, triggering unauthorized token minting, staking manipulation, or bridge state corruption
- **Common Contexts**: Chakra settlement, Olas GnosisTargetDispenserL2, Taiko bridge, FCHAIN warp messages, LayerZero receivers

---

## Pattern Summary Table

| ID | Pattern | Frequency | Severity |
|----|---------|-----------|----------|
| SIG-001 | signature_replay_no_nonce | ~38 | HIGH |
| SIG-002 | cross_chain_replay_missing_chain_id | ~22 | HIGH |
| SIG-003 | cross_contract_cross_context_replay | ~18 | HIGH |
| SIG-004 | ecrecover_zero_address_unchecked | ~14 | HIGH |
| SIG-005 | ecdsa_signature_malleability | ~12 | HIGH |
| SIG-006 | duplicate_signer_in_multisig | ~14 | HIGH |
| SIG-007 | eip712_domain_separator_incorrect_construction | ~12 | HIGH |
| SIG-008 | untyped_raw_bytes_signing | ~8 | HIGH |
| SIG-009 | signed_data_missing_critical_parameters | ~16 | HIGH |
| SIG-010 | signature_front_running_griefing | ~14 | HIGH |
| SIG-011 | failed_transaction_signature_reuse | ~8 | HIGH |
| SIG-012 | nonce_not_per_address | ~6 | HIGH |
| SIG-013 | bls_rogue_key_attack | ~4 | HIGH/CRIT |
| SIG-014 | mpc_tss_output_validation_missing | ~4 | HIGH |
| SIG-015 | initializer_frontrun_no_access_control | ~10 | HIGH |
| SIG-016 | access_control_modifier_bypassed_by_logic_error | ~20 | HIGH |
| SIG-017 | role_separation_insufficient_centralization | ~14 | HIGH |
| SIG-018 | governance_proposal_replay_or_bypass | ~12 | HIGH |
| SIG-019 | session_key_impersonation_cross_wallet | ~8 | HIGH |
| SIG-020 | erc1271_isvalidsignature_replay | ~6 | HIGH |
| SIG-021 | enable_mode_signature_ignores_module_type | ~4 | HIGH |
| SIG-022 | kyc_whitelist_validation_bypass | ~6 | HIGH |
| SIG-023 | certificate_chain_crl_bypass | ~3 | HIGH |
| SIG-024 | proof_forgery_merkle_weak_construction | ~4 | HIGH |
| SIG-025 | weak_prng_predictable_randomness | ~6 | HIGH |
| SIG-026 | layerzero_gas_channel_block | ~6 | HIGH |
| SIG-027 | reentrancy_bypass_auth_state | ~18 | HIGH |
| SIG-028 | arbitrary_external_call_token_theft | ~12 | HIGH |
| SIG-029 | permit2_integration_errors | ~6 | HIGH |
| SIG-030 | hash_collision_untyped_multisig | ~5 | HIGH |
| SIG-031 | signature_bypass_via_chained_sig_checkpoint_disabled | ~3 | HIGH |
| SIG-032 | csrf_missing_on_api_endpoints | ~3 | HIGH |
| SIG-033 | tx_origin_authentication | ~5 | HIGH |
| SIG-034 | bridge_message_source_validation_missing | ~10 | HIGH |
