# Proxy & Upgrade Safety Patterns
> Extracted from 5,138 findings (500 sampled)
> Pattern count: 22

---

## PROXY-001: Unprotected initialize() — Front-Run Attack
- **Frequency**: ~18/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  function initialize(...) public initializer { ... }  // no access control
  // deployed without atomically calling initialize in same tx
  ```
- **Detection Heuristic**:
  1. Find all functions named `initialize`, `init`, or decorated with `initializer` modifier
  2. Check whether the function has `onlyOwner`, `onlyDeployer`, or equivalent caller guard
  3. Check deployment scripts — is the constructor or factory `deploy()` in the same transaction as `initialize()`?
  4. If `initialize()` is public/external AND not called atomically in deployment → flag
  5. Confirm the initializer sets critical state (owner, admin, trusted address, etc.)
- **Failure Mode**: Attacker front-runs the legitimate `initialize()` call right after the implementation or proxy contract is deployed, claiming ownership or injecting malicious state before the legitimate owner does. Protocol then operates under attacker control.
- **Common Contexts**: UUPS proxies, Transparent proxies, Beacon proxies, clones (`ClonesUpgradeable`), `WellUpgradeable`, `SwapImpl`, wallet contracts (`SmartAccount`, `EnsoWallet`), Solana/Anchor programs with `Initialize` instruction without payer restriction

---

## PROXY-002: Uninitialized Implementation Contract — Self-Destruct / Takeover
- **Frequency**: ~12/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  // Implementation deployed standalone, initialize() never called on it
  // implementation.selfdestruct() or delegatecall to selfdestruct path still open
  contract Impl is UUPSUpgradeable {
      function initialize() public initializer { ... }
      function destroy() external { selfdestruct(payable(msg.sender)); }
  }
  ```
- **Detection Heuristic**:
  1. Find all implementation contracts for proxies
  2. Check if the implementation itself has `initialize()` called during deployment (separate from proxy initialization)
  3. Look for `selfdestruct`, `SELFDESTRUCT` opcode, or `upgradeTo` calls accessible without auth on the bare implementation
  4. Look for `_disableInitializers()` in the constructor — if absent, implementation is vulnerable
  5. Check for modules or sub-contracts that can be called via `delegatecall` and contain selfdestruct paths (TOFT modules)
- **Failure Mode**: Attacker calls `initialize()` directly on the implementation contract (not via proxy), takes ownership, then calls a function that triggers `selfdestruct`. The proxy is now bricked because its implementation address points to dead code. All user funds locked or lost.
- **Common Contexts**: Biconomy `SmartAccount`, Fractional vaults, Fuji Protocol `FujiVault`, Stader Labs `VaultProxy`, Enso `EnsoWallet`, `LootBox` implementation, Tapioca DAO TOFT/USDO modules, Rio Vesting Escrow clones (forged immutable args)

---

## PROXY-003: Storage Collision — Proxy vs Implementation (No EIP-1967)
- **Frequency**: ~8/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  // Proxy stores admin at slot 0
  contract Proxy { address admin; ... }
  // Implementation also has state at slot 0
  contract Implementation { address owner; ... }
  // admin slot in proxy is overwritten by owner writes in impl
  ```
- **Detection Heuristic**:
  1. Identify proxy contract and implementation contract storage layouts
  2. Check whether proxy uses EIP-1967 slots (`keccak256("eip1967.proxy.implementation") - 1`) or an unstructured storage approach
  3. If proxy stores admin/owner/logic at fixed slots (0, 1, 2...) → compare against implementation's first N storage variables
  4. Check for `Corruptible storage upgradeability pattern` (Ribbon Finance pattern: no gap in base, child adds storage before base)
  5. In ink! / Substrate contracts, check for unstructured storage overlap
- **Failure Mode**: Write to implementation storage variable silently overwrites proxy's admin/implementation-address slot (or vice versa). Can allow anyone to hijack admin, point implementation to arbitrary address, or corrupt critical accounting variables.
- **Common Contexts**: Early OpenZeppelin proxies without EIP-1967, `RibbonThetaVault`, Joyn contracts, ink! upgradeable contracts, `AdminUpgradeabilityProxy` variants

---

## PROXY-004: Delegatecall to Unverified / Non-Existent Address
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  function execute(address target, bytes calldata data) external {
      (bool success,) = target.delegatecall(data);  // no existence check
      require(success);
  }
  ```
- **Detection Heuristic**:
  1. Find all `delegatecall` usages in the codebase
  2. For each, check whether the target address is validated: (a) non-zero check, (b) `target.code.length > 0` check, (c) whitelist membership check
  3. If target is user-supplied or comes from storage that can be set to a non-existent address → flag
  4. Confirm: does a `delegatecall` to an address with no code return `success=true` in Solidity? (Yes — EVM returns success with empty returndata when calling EOA/zero-code address)
  5. Check what state the `delegatecall` modifies in the caller's context
- **Failure Mode**: `delegatecall` to an address with no deployed code returns `success=true` (EVM behavior). The caller proceeds as if the operation succeeded, but no logic ran. State changes expected from the delegate never happen. Or if target is attacker-controlled, arbitrary code executes in caller's storage context.
- **Common Contexts**: `RocketMinipool` delegatecall pattern, Rocket Pool `VaultControlUpgradeable`, Fuji Protocol `Proxy`, Aragon Voting (Frax Finance), Yield V2 `Ladle`, ForceDAO `VaultProxy`, Mass contracts, Maple Labs `ERC20Helper`, Primitive, Tokemak liquidation path, TermMaxRouter flash loan callback

---

## PROXY-005: Delegatecall in Payable Function Inside Loop — ETH Duplication
- **Frequency**: ~3/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  function batch(bytes[] calldata calls) external payable {
      for (uint i; i < calls.length; i++) {
          address(this).delegatecall(calls[i]);  // msg.value reused each iteration
      }
  }
  ```
- **Detection Heuristic**:
  1. Find `delegatecall` calls inside loops
  2. Check if the containing function or any delegated function is `payable`
  3. Verify whether `msg.value` is consumed exactly once or re-read each iteration
  4. Check if any inner call treats `msg.value` as new ETH deposited
- **Failure Mode**: `msg.value` is the same across all loop iterations. Each delegatecalled function that reads `msg.value` sees the full original ETH amount, allowing a caller to appear to have deposited N×ETH with only 1×ETH, draining the contract.
- **Common Contexts**: Yield V2 `Ladle.batch()`, multicall/batch patterns in DeFi protocols

---

## PROXY-006: Access Control Not Enforced in delegatecall Context
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  modifier onlyAtlasEnvironment() {
      require(msg.sender == ATLAS, "not atlas");  // checks msg.sender
      _;
  }
  // When called via delegatecall, msg.sender is NOT the proxy caller
  // it's the original EOA — guard passes incorrectly or fails incorrectly
  ```
- **Detection Heuristic**:
  1. Find access control modifiers that check `msg.sender`, `address(this)`, or `tx.origin`
  2. Identify all paths where these guarded functions can be reached via `delegatecall`
  3. Assess whether the guard semantics change under `delegatecall` (address(this) = caller, not callee; msg.sender = original caller passes through)
  4. Look for `validControl`/`onlyAtlasEnvironment` style patterns in Atlas/hook architectures
  5. In Marmo / PRBProxy: check whether `execute()` / `relay()` allows arbitrary delegatecall target
- **Failure Mode**: Guards that appear to protect functions are bypassed or behave unexpectedly when the function is invoked via `delegatecall` instead of a direct call. An unauthorized caller can satisfy the guard through the execution context change, or a legitimate guard fails, bricking the system.
- **Common Contexts**: Fastlane Atlas `DAppControl`, PRBProxy (`execute()` allows arbitrary delegatecall), Marmo Contracts `relay()`, Olas `GuardCM`, Convex Platform `VoterProxy`, Kakarot zkEVM precompile authorization

---

## PROXY-007: Diamond / Facet Upgrade — Arbitrary Actions During Cut
- **Frequency**: ~4/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata calldata_) external {
      // `init` can be any address; `calldata_` is delegatecalled during upgrade
      _delegatecall(init, calldata_);  // arbitrary execution during upgrade
  }
  ```
- **Detection Heuristic**:
  1. Find `diamondCut` or equivalent upgrade function in Diamond proxy contracts
  2. Check whether the `init` address and `calldata_` parameters are validated/whitelisted before the delegatecall
  3. Verify who controls the upgrade call — is it behind a timelock or multisig?
  4. Look for gaps between `removeFacet` and `addFacet` steps where state is inconsistent
  5. In `GNSMultiCollatDiamond`: check if role-based access control state survives an upgrade cycle
- **Failure Mode**: During a Diamond cut, the `init` address receives a delegatecall that executes arbitrary code in the diamond's storage context. Attacker can manipulate balances, permissions, or state mid-upgrade. Alternatively, roles and access control mappings are cleared/reset after upgrade (GainsNetwork pattern).
- **Common Contexts**: Nayms Diamond, GainsNetwork `GNSMultiCollatDiamond`, any EIP-2535 Diamond implementation

---

## PROXY-008: UUPS — `_authorizeUpgrade()` Missing or Misconfigured (Anyone Can Upgrade)
- **Frequency**: ~7/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  contract WellUpgradeable is UUPSUpgradeable, OwnableUpgradeable {
      function _authorizeUpgrade(address) internal override {}
      // Empty body — no restriction! Anyone can call upgradeTo()
  }
  ```
  or:
  ```solidity
  // EXPO contract — _authorizeUpgrade never overridden, defaults to open
  ```
- **Detection Heuristic**:
  1. Find all contracts inheriting `UUPSUpgradeable`
  2. Check `_authorizeUpgrade(address newImplementation)` — is it overridden?
  3. If overridden, does it contain a meaningful access check (`onlyOwner`, `onlyGovernance`, etc.)?
  4. If empty or has a trivially-bypassable guard → flag Critical
  5. Check `upgradeTo()` and `upgradeToAndCall()` for direct external callers
- **Failure Mode**: Any external caller can invoke `upgradeTo(attackerImpl)`, replacing the implementation with malicious code that drains all funds, steals ownership, or bricks the contract.
- **Common Contexts**: Basin `WellUpgradeable`, EXPO (Made For Gamers), StageZero `StakeManager`/`ethwBTC`, Notional `UUPSUpgradeable` inheritors (potential DoS)

---

## PROXY-009: Initialization on Declaration / Constructor State Not Carried to Proxy
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  contract ParticlePositionManager is Initializable {
      // Blast yield config set in constructor — only runs on implementation, NOT proxy
      constructor() {
          BLAST.configure(YieldMode.AUTOMATIC);  // ← affects impl storage, not proxy
      }
  }
  ```
  or:
  ```solidity
  contract OracleManager {
      uint256 public constant FEE = 5e17;  // initialized at declaration — OK
      address public owner = msg.sender;   // ← set in constructor, not proxy's storage
  }
  ```
- **Detection Heuristic**:
  1. Find upgradeable/proxy contracts with non-`initializer` constructors that set state variables
  2. Identify state set in constructor (not `initialize()`) — this only affects the implementation's own storage, not the proxy's
  3. Look for external protocol configurations (yield modes, oracle registrations) called in constructors
  4. Check `immutable` variables — these are fine (embedded in bytecode), but `immutable` args in clone patterns (CWIA) need separate validation
  5. Flag any `initialize()` call during declaration (`uint x = foo()`) in upgradeable contracts
- **Failure Mode**: The proxy delegates all calls to the implementation, but the proxy's storage slot for the variable was never initialized (constructor only ran on implementation). The system operates with zero/default values for critical parameters (fee = 0, Blast yield not configured, owner = address(0)).
- **Common Contexts**: Particle `ParticlePositionManager` (Blast config in constructor), Kinetiq LST `OracleManager`, Infinigold `TokenImpl` (name/symbol/decimals not set in proxy context)

---

## PROXY-010: Upgrade Breaks Storage Layout — Incompatible New Implementation
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // V1
  contract StorageV1 { uint256 a; uint256 b; }
  // V2 — inserted new var before existing ones
  contract StorageV2 { address newVar; uint256 a; uint256 b; }
  // After upgrade: proxy's slot0 (was `a`) is now read as `newVar`
  ```
- **Detection Heuristic**:
  1. Diff storage layouts between old and new implementation versions
  2. Check for: new variables inserted before existing ones, removed variables (leaves gap), changed types at same slot, changed inheritance order
  3. For Diamond proxies: check facet storage structs use unique storage slots (`bytes32 constant POSITION = keccak256("...")`)
  4. In Notional `CurveConvexLib` migration: check if `migrateRewardPool` assumes a storage layout that changed
  5. Verify `withdrawalDelayBlocks` and similar variables are properly initialized post-upgrade (EigenLayer M2 pattern)
- **Failure Mode**: After upgrade, storage reads return garbage values because the new implementation maps different semantics onto the same slots. Critical state (balances, roles, limits) is corrupted silently. May not be immediately apparent until an affected code path is exercised.
- **Common Contexts**: EigenLayer M2 `withdrawalDelayBlocks` uninitialized, Notional `CurveConvexLib` incompatible storage design, GainsNetwork lost roles post-upgrade, Ribbon Finance corruptible storage, NuCypher `verifyState` memory layout check

---

## PROXY-011: Blacklisted Implementation Still Reachable via Migration Path
- **Frequency**: ~2/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  function blacklistImplementation(address impl) external onlyAdmin {
      blacklisted[impl] = true;
  }
  function migrate(address from, address to) external {
      // migrates from one impl to another — does NOT check if `to` is blacklisted
      _setImplementation(to);
  }
  ```
- **Detection Heuristic**:
  1. Find contracts with both a blacklisting mechanism and a migration/upgrade path
  2. Trace every code path that calls `_setImplementation()` or equivalent
  3. Verify that EACH path checks the blacklist, not just the primary `upgradeTo()` entry point
  4. Look for indirect routes: migrate from V1→V2 where V2 is not blacklisted, then V2→V3 (blacklisted)
- **Failure Mode**: Blacklisting prevents direct upgrade to a vulnerable implementation, but the migration path bypasses the check. Attacker or admin migrates through the blacklisted version, reintroducing vulnerabilities the blacklist was designed to prevent.
- **Common Contexts**: Suzaku Core `VaultFactory`

---

## PROXY-012: Proxy Ownership — Single-Step Transfer, No Two-Step Process
- **Frequency**: ~8/500
- **Severity**: HIGH (operational risk)
- **Code Shape**:
  ```solidity
  function transferOwnership(address newOwner) external onlyOwner {
      owner = newOwner;  // immediately effective, no confirmation from newOwner
  }
  ```
- **Detection Heuristic**:
  1. Find `transferOwnership`, `setOwner`, `setAdmin` functions in proxy and implementation contracts
  2. Check whether the pattern is two-step: `pendingOwner` set first, then `acceptOwnership()` called by new owner
  3. Confirm whether OpenZeppelin's `Ownable2Step` or equivalent is used
  4. Special attention to `OwnableUpgradeable` — default single-step — vs `Ownable2StepUpgradeable`
  5. Also check if `renounceOwnership()` is available and unconstrained (can lock upgrade forever)
- **Failure Mode**: Typo in new owner address or key compromise causes irreversible loss of contract control. Since no confirmation from new owner is required, the transfer happens immediately — the new owner may be an uncontrolled address, a contract that cannot call `acceptOwnership`, or the zero address.
- **Common Contexts**: Beanstalk `OwnershipFacet`, Reserve `Main`, Advanced Blockchain contracts, `OwnableUpgradeable` inheritors (Rocket Pool, Connext `WatcherClient`), Liquistake `StWSX` (update breaks proxy)

---

## PROXY-013: Proxy Pattern — Owner/Admin Has Excessive Unchecked Powers
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // UberOwner / admin can call arbitrary functions
  function adminExec(address target, bytes calldata data) external onlyAdmin {
      target.call(data);  // no restriction on what can be called
  }
  // Or: owner can withdraw any token without guard
  function withdraw(address token, uint amount) external onlyOwner { ... }
  ```
- **Detection Heuristic**:
  1. Enumerate all `onlyOwner`/`onlyAdmin` functions
  2. For each, assess whether the action is bounded (e.g., withdraw fees) vs. unbounded (withdraw any token, arbitrary call)
  3. Check `Ownable` pattern vs. role-based access: is a single key the sole controller?
  4. Look for `delegate` or `execute` functions that allow the owner to call arbitrary contracts
  5. Assess whether a timelock, multisig, or DAO governs the admin key
- **Failure Mode**: Malicious or compromised owner/admin can drain funds, alter critical parameters, or execute arbitrary transactions through the proxy. Even without compromise, overly privileged owner keys represent single points of failure.
- **Common Contexts**: Reality Cards `UberOwner`, Thetanuts `OwnerProxy_V1` (withdraw any balance), Bitcorn arbitrary minting, Hubii Token (token creator controls emission), Fathom Proxy misconfiguration risk

---

## PROXY-014: Clone / Minimal Proxy — Uninitialized or Front-Runnable Clones
- **Frequency**: ~5/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  function createGauge() external returns (address gauge) {
      gauge = Clones.clone(implementation);
      // initialize() not called in same tx — window for frontrun
      emit GaugeCreated(gauge);
  }
  // Attacker watches mempool, calls gauge.initialize(attacker) before factory does
  ```
- **Detection Heuristic**:
  1. Find `Clones.clone()`, `Clones.cloneDeterministic()`, or `new MinimalProxy(...)` calls
  2. Check whether `initialize()` is called on the clone in the same transaction as the clone creation
  3. If not atomic → front-run window exists
  4. For `cloneDeterministic`: check if attacker can predict the clone address and pre-initialize it
  5. Check `ClonesWithImmutableArgs` (CWIA): verify immutable args cannot be forged to redirect calls to a different implementation
- **Failure Mode**: Attacker front-runs the factory's initialize call, taking ownership of the clone. The factory may continue operating with attacker-controlled clones, or the subGauge/clone is permanently bricked for the legitimate user.
- **Common Contexts**: PoolTogether `TokenDrop`, Vetenet `subGauge` (cloning without atomic init), Florence Finance (staker/depositor front-run), Kinto account front-run, Gorples Bridge program

---

## PROXY-015: Implementation Can Be Self-Destructed via Forged / Exploitable Path
- **Frequency**: ~5/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**:
  ```solidity
  // Compounder contract:
  function shutdown(address beneficiary) external onlyOwner {
      selfdestruct(payable(beneficiary));
  }
  // If ownership can be transferred to attacker first → selfdestruct
  ```
  or UUPS implementation directly callable:
  ```solidity
  // No _disableInitializers() in constructor → attackable
  ```
- **Detection Heuristic**:
  1. Search for `selfdestruct` keyword in all contracts (including implementation contracts)
  2. For each, check: (a) is the containing contract used as a UUPS/Transparent implementation? (b) can `selfdestruct` be reached without going through the proxy?
  3. Check Tapioca DAO module pattern: modules are delegatecalled, can the module itself be selfdestructed?
  4. Post-EIP-6780 (Cancun): `selfdestruct` only works if contract was created in same transaction — check EVM version
  5. For Escher pattern: `selfdestruct` accessible to any caller due to missing access control
- **Failure Mode**: Implementation's `selfdestruct` is triggered, setting the implementation code to empty. The proxy now delegatecalls to a dead address, returning empty success. All protocol functionality breaks. Funds in the proxy (if any) are not automatically moved.
- **Common Contexts**: Entangle `Compounder`, Tapioca DAO TOFT/USDO modules, Escher `selfdestruct`, Rio Vesting Escrow (forged immutable args path), LootBox (unprotected selfdestruct in proxy implementation)

---

## PROXY-016: Proxy Forwards Wrong Encoded Call Data (ABI Encoding Mismatch)
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // LendingPoolConfigurator:
  bytes memory encodedCall = abi.encodeWithSignature("updateAToken(...)");
  // Missing or wrong parameter in encoded call — proxy passes it through unchanged
  proxy.upgradeToAndCall(newImpl, encodedCall);
  // newImpl receives malformed calldata → state corrupted or call fails silently
  ```
- **Detection Heuristic**:
  1. Find `abi.encodeWithSignature`, `abi.encodeWithSelector`, `abi.encode` used to construct upgrade calldata
  2. Verify function signature string exactly matches the target implementation's function (name + param types)
  3. Check parameter order and types for off-by-one or missing parameters
  4. In `updateAToken`/`updateVariableDebtToken` (Aave-fork pattern): confirm the encoded call includes ALL required params
  5. Look for proxy execute functions that pass user-controlled calldata without validation
- **Failure Mode**: Implementation receives malformed calldata. The call either silently fails (returns false, proxy ignores return value) or executes wrong logic (e.g., parsing an address as a uint256). Critical upgrade state transition goes wrong, potentially leaving protocol in broken state.
- **Common Contexts**: Astera/Cod3x Lend `LendingPoolConfigurator` (updateAToken/updateVariableDebtToken wrong encoded call), StarBase `ArgumentsDecoder` incorrect decoding, 1inch `_makeCall` inconsistent data

---

## PROXY-017: Proxy Does Not Track Upgrade Block Number / Version Metadata
- **Frequency**: ~3/500
- **Severity**: HIGH (operational / correctness)
- **Code Shape**:
  ```solidity
  // zkSync L2 upgrade:
  function processL2Upgrade(...) external {
      _upgrade(newImpl);
      // l2SystemContractsUpgradeBlockNumber never set
      // Future upgrades may re-apply already-applied changes
  }
  ```
- **Detection Heuristic**:
  1. Find upgrade processing functions that apply L2/L1 upgrades
  2. Check whether the upgrade block number, nonce, or version identifier is written to storage after upgrade completes
  3. Verify this identifier is checked before re-applying an upgrade (prevents replay)
  4. For Sei DB `LoadVersionAndUpgrade`: check if version argument is actually used or ignored
- **Failure Mode**: No record of which block/version an upgrade was applied at. Future upgrade transactions may be re-applied (replay), or the system cannot determine whether a historical version should be loaded (Sei DB). May prevent future upgrades entirely.
- **Common Contexts**: zkSync Upgrade System (`l2SystemContractsUpgradeBlockNumber` not set), Sei DB `LoadVersionAndUpgrade` ignores version argument, EigenLayer (`withdrawalDelayBlocks` not initialized after M2 upgrade)

---

## PROXY-018: Proxy Plugin / Module Collision — Signature or Address Collision
- **Frequency**: ~3/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // PRBProxy plugin registry:
  function installPlugin(address plugin) external {
      bytes4[] memory sigs = IPlugin(plugin).methodList();
      for (uint i; i < sigs.length; i++) {
          plugins[sigs[i]] = plugin;  // overwrites any existing plugin for that selector
      }
  }
  // Malicious plugin with selector that collides with existing plugin → overrides it
  ```
- **Detection Heuristic**:
  1. Find proxy registries that map function selectors → implementation/plugin addresses
  2. Check whether installing a new plugin/module can overwrite an existing selector mapping
  3. Verify whether the registry enforces uniqueness or raises an error on collision
  4. For Dojo namespace pattern: check if namespace ID is derived from name hash and whether collisions are possible (different names → same hash)
  5. Check Mysten Labs Sui `move_package` module digest collision
- **Failure Mode**: A malicious or accidentally-colliding plugin overwrites a critical function selector. Calls to the critical function are now silently routed to the attacker's plugin. Can lead to arbitrary code execution in proxy storage context.
- **Common Contexts**: Sablier PRBProxy plugins (malicious override via colliding signatures), Dojo namespace ID collision, Mysten Labs Sui modules digest collision

---

## PROXY-019: Proxy Inherits Wrong / Non-Upgradeable Base Contract
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Wrong: inheriting non-upgradeable Ownable in upgradeable contract
  contract MyProxy is UUPSUpgradeable, Ownable { ... }
  // Correct: should be OwnableUpgradeable
  // Result: Ownable constructor sets owner in implementation storage, not proxy storage
  ```
  or:
  ```solidity
  // Inherits upgradeable contract but doesn't call parent __init() in initialize()
  contract Child is ParentUpgradeable {
      function initialize() public initializer {
          // forgot: __ParentUpgradeable_init();
      }
  }
  ```
- **Detection Heuristic**:
  1. Find all contracts in the upgradeable inheritance chain
  2. For each base contract, verify whether it's the `*Upgradeable` version (from OpenZeppelin `contracts-upgradeable`)
  3. Check `initialize()` calls all required `__Parent_init()` / `__Parent_init_unchained()` functions
  4. Verify no storage-initializing constructor logic is inherited from non-upgradeable bases
  5. Look for `ERC20VotesUpgradeable` removed from inheritance chain (DIMO pattern) — check what functionality was lost
- **Failure Mode**: Non-upgradeable base contracts run constructors that only affect implementation storage. The proxy's corresponding state is never initialized. Critical functionality (voting power, access control) is silently broken or missing.
- **Common Contexts**: Itrust Finance (wrong OZ contracts-upgradeable), Covalent (wrong Ownable version breaks `onlyOwner`), DIMO (removal of `ERC20VotesUpgradeable` allows double voting), Fyde May `YieldToken` (functions cannot be called), MembershipERC1155 (proxy cannot be upgraded)

---

## PROXY-020: Proxy State Shared Across Upgrade — Stale / Broken Cache Post-Upgrade
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // AaveStrategy changes swapper address
  function setSwapper(address newSwapper) external onlyOwner {
      swapper = newSwapper;
      // BUT: cached approvals, initialized state in swapper, or downstream contracts
      // still reference old swapper address
  }
  ```
- **Detection Heuristic**:
  1. Find setter functions that change critical addresses (swapper, oracle, token, strategy)
  2. For each, check whether changing the address invalidates any cached state: approvals, allowances, pre-computed values, registry entries
  3. Look for "registry cache not verified when registry address is updated" (Yearn v2 pattern)
  4. Check `PaymentSettler` vs `RemoraToken` stablecoin mismatch: if one contract can change a shared reference that another cannot → state diverges
  5. In Liquistake: check if updating WSX/StakingProxy/Validator invalidates dependent state
- **Failure Mode**: After changing a critical address reference, the old address is still embedded in cached state elsewhere. Protocol uses the new address in some paths but the old address in others, creating accounting inconsistencies, failed transfers, or incorrect calculations.
- **Common Contexts**: Tapioca DAO `AaveStrategy` swapper change, Yearn v2 registry cache, Remora `PaymentSettler`/`RemoraToken` stablecoin mismatch, Liquistake WSX/StakingProxy update

---

## PROXY-021: Private Key / Secret Exposed in Upgrade/Deployment Script
- **Frequency**: ~3/500
- **Severity**: HIGH (operational security)
- **Code Shape**:
  ```solidity
  // Foundry broadcast script:
  uint256 deployerPrivateKey = 0xDEADBEEF...;  // hardcoded
  vm.startBroadcast(deployerPrivateKey);
  // Script committed to public repo → key exposed
  ```
- **Detection Heuristic**:
  1. Scan deployment and upgrade scripts (`.s.sol`, `.js`, `.ts`) for hardcoded private keys, mnemonics, or seed phrases
  2. Check environment variable usage — are keys loaded from `.env` or hardcoded as literals?
  3. Review version control history for accidentally committed secrets
  4. Check build/CI scripts for key leakage in logs
- **Failure Mode**: Attacker extracts the deployer private key from the repository. Can deploy malicious implementations, call upgrade functions, or drain admin-controlled funds. Trilogy: key → implementation swap → full protocol drain.
- **Common Contexts**: Trillion Network upgrade script (private key exposed), Desktop Wallet (hardcoded mnemonics), Anatha Wallet (leaked GitHub token with write:packages)

---

## PROXY-022: Inadequate Proxy Implementation — Upgrade Mechanism Permanently Broken
- **Frequency**: ~5/500
- **Severity**: HIGH
- **Code Shape**:
  ```solidity
  // Proxy requires specific state in implementation that was never set
  contract TokenImpl {
      address public owner;
      // upgrade() requires owner != address(0) to authorize
      function upgrade(address newImpl) external {
          require(owner != address(0), "not initialized");
          require(msg.sender == owner, "not owner");
          // But owner is NEVER set because initialize() not called
      }
  }
  ```
  or:
  ```solidity
  // MembershipERC1155: incorrect execution flow prevents proxy from calling upgrade
  ```
- **Detection Heuristic**:
  1. Trace the upgrade authorization path end-to-end: who can call upgrade, what checks are performed, what state must be set
  2. Verify that all required state (owner, admin, authorized upgrader) is correctly initialized in the proxy's storage context
  3. Check for circular dependencies: upgrade requires X to be set, but X is only set during upgrade
  4. For `ArkProject NFT Bridge`: check if the bridge contract has the admin function to transfer ownership on bridged contracts
  5. For Infinigold `TokenImpl`: confirm constructor params are propagated to proxy
- **Failure Mode**: The upgrade mechanism is permanently locked because a precondition for upgrade is unsatisfied and cannot be satisfied without upgrading first. Protocol is stuck on the current implementation forever, unable to patch vulnerabilities.
- **Common Contexts**: Infinigold `TokenImpl` (upgrade impossible without initialized owner), MembershipERC1155 (incorrect execution flow), ArkProject NFT Bridge (missing admin function to manage bridged contracts), Fyde May `YieldToken` (functions cannot be called post-deployment)
