# Initialization Patterns
> Extracted from 4,342 findings (500 sampled)
> Pattern count: 22

---

## INIT-001: unprotected_initializer_frontrun
- **Frequency**: ~28/500
- **Severity**: HIGH (Critical in proxy contexts)
- **Code Shape**: `function initialize(...) public { /* no access control, no initialized guard */ }` — any caller can invoke on deploy-race window
- **Detection Heuristic**:
  1. Search for `initialize(` or `init(` functions without `initializer` modifier (OZ) or equivalent re-entrancy/one-shot guard
  2. Check if the function is `public` or `external` with no `onlyOwner` / `onlyDeployer` guard
  3. Verify deployment scripts: is `initialize` called atomically in the same tx as deployment?
  4. If not atomic, flag as exploitable via mempool frontrun
- **Failure Mode**: Attacker frontruns deployment tx, calls `initialize` first with malicious parameters (owner, trusted addresses, fee recipients), taking control of the contract or poisoning its configuration before legitimate deployer
- **Common Contexts**: OpenZeppelin UUPS/TransparentProxy init functions, ERC20 upgradeable tokens, vault/pool initializers, cross-chain bridge configs, Solana program `Initialize` instructions without signer constraints (e.g., gorples-bridge, Convergent, NGL Bridge)

---

## INIT-002: proxy_implementation_uninitialized_selfdestruct
- **Frequency**: ~12/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: Implementation contract constructor does NOT call `_disableInitializers()` — raw implementation contract address reachable by anyone; `initialize()` can be called on it directly
- **Detection Heuristic**:
  1. Find upgradeable contracts (UUPS, Transparent Proxy)
  2. Check implementation contract's constructor: does it call `_disableInitializers()`?
  3. Check if `initialize()` on implementation would grant owner privileges or allow `selfdestruct` / `delegatecall` with arbitrary target
  4. Verify there is no `initializer` guard preventing re-entry on the implementation itself
- **Failure Mode**: Attacker calls `initialize()` on bare implementation, gains ownership, then calls a self-destruct path or sets a malicious implementation — bricking all proxy instances or draining funds routed through the now-destroyed implementation (e.g., Fuji Protocol, Stader Labs, Fractional, Biconomy SmartAccount, EnsoWallet, Notional UUPS)
- **Common Contexts**: UUPS proxy implementations, vault logic contracts, any implementation behind `ERC1967Proxy`; particularly dangerous when `selfdestruct` is reachable via owner-only function

---

## INIT-003: missing_role_grant_in_constructor_or_initializer
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Contract inherits `AccessControl` / `Ownable` but constructor / initializer does NOT call `_setupRole()` / `_grantRole()` / `transferOwnership()` — leaving roles unassigned and critical functions permanently locked
- **Detection Heuristic**:
  1. Find contracts inheriting `AccessControl` or `Ownable`
  2. Grep constructor/initializer for `_setupRole`, `_grantRole`, `transferOwnership`, `_setRoleAdmin`
  3. If any required role (DEFAULT_ADMIN_ROLE, KEEPER_ROLE, etc.) is absent, enumerate which functions require that role
  4. Check if those functions are permanently unusable (DOS) or if the role can be granted post-deploy by another privileged path
- **Failure Mode**: Critical protocol functions (claim, rebalance, emergency pause, keeperAction) revert because no address holds the required role; funds locked; protocol inoperable (e.g., AuraVault `AccessControl` with no `_setupRole`, Infrared missing `KEEPER_ROLE`, Canto `accountant` require statement blocks initialization)
- **Common Contexts**: Vault contracts inheriting AccessControl, reward distributors, keeper-driven liquidation bots, gauge factories

---

## INIT-004: state_variable_not_initialized_causes_zero_default_behavior
- **Frequency**: ~35/500
- **Severity**: HIGH
- **Code Shape**: Critical state variable (timestamp, address, index, price) left at Solidity default `0` / `address(0)` — no explicit initialization in constructor or initializer; logic that uses it treats zero as "unset" or as a valid sentinel incorrectly
- **Detection Heuristic**:
  1. Enumerate all state variables used in reward/fee/price calculations
  2. Check if each is explicitly set in constructor or initializer
  3. For timestamp-based logic: if `lastUpdatedTime == 0`, what does `block.timestamp - lastUpdatedTime` produce?
  4. For address variables: does `transfer` / `safeTransfer` to `address(0)` burn funds?
  5. Flag any case where uninitialized default produces incorrect math or routes funds to burn address
- **Failure Mode**: (a) `lastUpdatedDay` / `lastHarvestTime` zero causes enormous fee on first call (management fee for entire history), (b) `feeReceiver == address(0)` causes fees to be burned/lost, (c) zero price precision causes division by zero or inflated price, (d) zero timestamp causes incorrect IL protection duration (e.g., Vader Protocol `lastUpdatedDay`, TeaVault management fee, Mercydao `feeReceiver`, Synonym `pricePrecision`, Vader Router `timeForFullProtection = 1` instead of `8640000`)
- **Common Contexts**: Reward distribution contracts, fee-charging vaults, oracle contracts, staking protocols with epoch tracking

---

## INIT-005: init_if_needed_allows_reinit_by_attacker
- **Frequency**: ~8/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: Solana Anchor `init_if_needed` constraint on config/staking account — any caller can re-invoke the instruction after first init, overwriting staking params, bridge configs, or authority fields
- **Detection Heuristic**:
  1. Search Anchor programs for `init_if_needed` on any account that stores privileged configuration
  2. Verify that the instruction checks: (a) if account already initialized → reject, or (b) caller is authorized admin for re-initialization
  3. If neither check exists, flag as reinit vulnerability
  4. Confirm which fields would be overwritten (authority, fee, mint, threshold)
- **Failure Mode**: Attacker calls initialize instruction a second time, replacing admin authority with their own address or resetting staking parameters to extract rewards; bridge config can be pointed to malicious destination (e.g., Composable Vaults `init_if_needed` on staking params, Render Network `redeemer_config` reinit)
- **Common Contexts**: Solana staking programs, bridge config accounts, governance config accounts using Anchor `init_if_needed`

---

## INIT-006: pool_or_vault_first_depositor_inflation_attack
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: ERC4626-style vault or AMM pool initializes with zero total supply; first depositor can donate assets directly to contract, manipulating share price before any honest deposit
- **Detection Heuristic**:
  1. Find vault/pool contracts using formula `shares = assets * totalSupply / totalAssets`
  2. Check: does `totalSupply == 0` on first deposit? Does formula handle zero supply safely (e.g., with virtual offset)?
  3. Verify: can attacker atomically (a) make a tiny initial deposit to get 1 share, (b) donate large amount of tokens directly, (c) victim deposit yields 0 shares due to rounding?
  4. Check for minimum initial deposit or virtual liquidity protection (e.g., OpenZeppelin ERC4626 with `10**decimalsOffset`)
- **Failure Mode**: Attacker rounds victim's deposit to 0 shares; attacker redeems 1 share for victim's entire deposit; vault/pool becomes unusable or all future depositors lose funds to first depositor (e.g., BakerFi, InsureDAO, Maple Finance, Asymmetry `preDepositvPrice`, Radiant UniV3TokenizedLp, SOFA.org AAVE vault, RestakeFi)
- **Common Contexts**: ERC4626 vaults, LP token pools, any tokenized position system with share-based accounting at genesis

---

## INIT-007: pool_initialization_frontrun_price_manipulation
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Pool deployment and price initialization are separate transactions; attacker can initialize pool with manipulated price between deploy and legitimate init call
- **Detection Heuristic**:
  1. Find factory contracts that deploy pools without atomically setting initial price/state
  2. Check if the initialization function is permissionless (no `onlyOwner` / `onlyFactory`)
  3. Verify if pool can be initialized multiple times (no `initialized` flag)
  4. Check whether the initial price or interest rate affects user-facing accounting from the first block
- **Failure Mode**: Attacker sets initial pool price far from market, enabling immediate profitable arbitrage against first LP; or attacker sets initial interest rate that drains borrowers; in AMM contexts, LP receives incorrect tick-based fee accounting from block 0 (e.g., Algebra Finance pool init frontrun, Timeswap pool init with manipulated interest rate, Serious Market Uniswap pool init, Lambo.win createPair)
- **Common Contexts**: Uniswap V3 forks, custom AMMs with explicit price initialization, lending pools with permissionless initialization

---

## INIT-008: incorrect_initial_value_wrong_constant_or_unit
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: Hardcoded constant or initial value uses wrong scale (seconds vs. days, WAD vs. token decimals, bps vs. percentage), wrong comparison direction, or simply the wrong number entirely
- **Detection Heuristic**:
  1. Identify all hardcoded numeric literals in constructors and initializers
  2. Dimensional analysis: trace each constant through the formula that uses it — are units consistent?
  2a. Look for time constants: `1` when `86400` is intended, `100 days` when `1 second` is set
  2b. Look for fee constants: WAD (1e18) amounts stored where token-decimal amounts expected, or vice versa
  3. Cross-reference against spec/docs/natspec for intended values
  4. Check `minStake`, `maxSlippage`, staleness thresholds for oracle feeds
- **Failure Mode**: (a) IL protection lasts 1 second instead of 100 days, (b) LP fees in WAD instead of token decimals cause massive overcharging, (c) staleness period applies same value to all oracles causing DoS on feeds with different update frequencies, (d) hardcoded funding rate of 0 ignores market dynamics (e.g., Vader Protocol `timeForFullProtection`, Primitive LP fees in WAD, CAP Labs staleness period, Velar Artha hardcoded funding rate)
- **Common Contexts**: Oracle integrations, reward/fee rate initializations, time-lock or vesting period constants

---

## INIT-009: missing_input_validation_on_init_parameters
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Initializer / constructor accepts critical parameters (addresses, rates, limits) without zero-check or range-check; invalid values written to state are irrecoverable or require expensive migration
- **Detection Heuristic**:
  1. List all parameters accepted by constructor or `initialize()`
  2. For each address param: check for `require(param != address(0))`
  3. For each rate / amount param: check for range validation (e.g., `fee <= MAX_FEE`)
  4. For each address that receives funds: verify contract-existence check (`.code.length > 0`) for low-level calls
  5. Special case for Solana: verify PDA bump validation and canonical bump enforcement
- **Failure Mode**: (a) Zero-address fee recipient causes funds to be burned, (b) zero-address oracle causes downstream price queries to revert permanently, (c) out-of-range fee allows total fund drain, (d) missing validation of payment feed info allows invalid oracle configuration (e.g., Etherfuse Stablebond `PaymentFeedInfo`, Linea Token Bridge, TokenBridge initialization, Nord Finance missing address list, Atlendis zero-address checks)
- **Common Contexts**: Token bridge constructors, oracle registries, vault/pool factories, any contract where admin-set addresses are used for fund routing

---

## INIT-010: uninitialized_proxy_config_in_constructor_not_proxy_context
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: Upgradeable contract sets configuration (e.g., Blast yield mode, immutable variable) in the `constructor` body rather than in `initialize()` — constructor code runs on implementation, not on proxy storage
- **Detection Heuristic**:
  1. Find upgradeable contracts (UUPS, Transparent, Beacon)
  2. Check if the constructor sets any state variables or calls external protocol contracts (e.g., `Blast.configure(...)`)
  3. If yes and the contract is deployed behind a proxy, those constructor effects only apply to the implementation, not the proxy
  4. Verify `initialize()` replicates all configuration that needs to exist in the proxy's storage context
- **Failure Mode**: Configuration silently absent in proxy — e.g., Blast yield mode not set on proxy means yield never accrues; immutable variables set in constructor are accessible but state-variable-based config is zero in proxy context (e.g., Particle `ParticlePositionManager` Blast config in constructor, Kinetiq LST OracleManager, Infinigold TokenImpl)
- **Common Contexts**: Protocols integrating yield-bearing primitives (Blast L2), oracle managers, fee config contracts deployed via proxy

---

## INIT-011: reinitializable_controller_no_initialized_flag
- **Frequency**: ~9/500
- **Severity**: HIGH
- **Code Shape**: `initialize()` function does not set an `initialized` / `_initialized` boolean or use OZ `initializer` modifier; can be called repeatedly, resetting all state
- **Detection Heuristic**:
  1. Find `initialize` / `init` / `setup` functions that are `public` or `external`
  2. Verify the function checks `require(!initialized, "Already initialized")` or uses `Initializable.initializer` modifier
  3. If OZ `Initializable` is used, verify `_disableInitializers()` is called in the implementation constructor
  4. Check for the edge case in Coinbase Solady: overriding `_initializableSlot()` may flip disable semantics
- **Failure Mode**: Admin or attacker can call `initialize()` repeatedly to reset ownership, wipe access control state, or overwrite key parameters; equivalent to self-nuking the protocol (e.g., Lido Controller, Unmarshal `setInitialTimestamp` without flipping `isInitialized`, Rocketpool settings until "deployed" flag)
- **Common Contexts**: Custom initializable patterns without OZ library, governance contracts, staking contracts with epoch-reset logic

---

## INIT-012: missing_approval_or_allowance_in_initializer
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: Contract relies on another contract pulling tokens from it via `transferFrom`, but initializer / constructor never calls `approve()` or `safeApprove()` to grant that allowance
- **Detection Heuristic**:
  1. Find all `transferFrom(address(this), ...)` or `safeTransferFrom(address(this), ...)` calls in external contracts
  2. Trace back: does the contract holding tokens call `approve(target, type(uint256).max)` or equivalent in its setup path?
  3. Check that the approval covers the correct token for the correct spender
  4. Verify the approval is not accidentally set on the implementation address instead of the spender
- **Failure Mode**: Core protocol function (stake, vest, redeem) always reverts because the necessary token approval is missing from initialization — protocol main functionality is completely broken from deployment (e.g., ZeroLend `EarlyZEROVesting` missing approval, ZeroLend NFT stake missing approval, Mercydao claim reverts)
- **Common Contexts**: Vesting contracts, staking contracts that move tokens to external pools, auto-compounding vaults

---

## INIT-013: staking_or_reward_state_not_initialized_before_first_action
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: Users can stake / deposit before `notifyRewardAmount()` or equivalent initialization is called; early stakers receive disproportionate rewards because reward rate starts from genesis block (block 0 effectively) or reward per token is never updated for period before first notification
- **Detection Heuristic**:
  1. Find staking contracts with `rewardPerToken` / `lastUpdateTime` pattern
  2. Check: is there a check that `rewardsDuration > 0` or `periodFinish > 0` before `stake()` is allowed?
  3. Verify `lastUpdateTime` is initialized to `block.timestamp` when first `notifyRewardAmount()` is called, not at deployment
  4. Check `lastTimestamp = 0` in pool contracts: what does the first `updateDuration` produce with `block.timestamp - 0`?
- **Failure Mode**: (a) User stakes before `notifyRewardAmount`, then when rewards are added they accrue retroactively from time 0, capturing outsized share of rewards; (b) `lastTimestamp = 0` makes first LP receive rewards for entire history of the blockchain (e.g., Synthetix staking before `notifyRewardAmount`, Timeswap `lastTimestamp = 0`, Cosmos module `UpdateAccPerShare` initializing from block 0)
- **Common Contexts**: Synthetix-fork reward contracts, liquidity mining programs, time-weighted staking systems

---

## INIT-014: gauge_or_accumulator_variable_not_initialized_on_creation
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: New gauge / pool / market is created but a critical accumulator variable (`feeGrowthGlobal`, `cumulativeValue`, `specific_emissions_per_gauge`, `rewardPerTokenStored`) is not set to the current global value — new entity inherits incorrect baseline
- **Detection Heuristic**:
  1. Find factory functions that create new gauge/pool/market instances
  2. For each accumulator variable in the new instance, check: is it set to the current global accumulator value at creation time?
  3. Particularly check fork-based fee accounting (Uniswap V3 style): `feeGrowthInsideLast` must match global at position creation
  4. Check gauge additions in gauge controllers: does new gauge's `specific_emissions_per_gauge` get initialized to current epoch's value?
- **Failure Mode**: (a) Position minted at uninit tick accumulates phantom fees from tick inception, allowing theft of all taker collateral; (b) New gauge starts with emissions=0 and attacker backruns `add_gauge` to claim retroactive emissions; (c) `cumulativeValue` computed incorrectly on first liquidity addition, giving wrong share count (e.g., Ammplify uninitialized tick fees, Yield Basis `specific_emissions_per_gauge`, Burve `cumulativeValue` in addLiq, Canto gauge initial value)
- **Common Contexts**: Uniswap V3 forks (tick/position fee accounting), gauge controllers (Curve-style), concentrated liquidity managers

---

## INIT-015: configuration_address_not_updatable_or_wrong_target
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Initializer or constructor sets an address (oracle, fee recipient, router, governance) to the wrong target, or the address is immutable/non-upgradeable once set — no update path exists
- **Detection Heuristic**:
  1. Identify addresses set in constructor/initializer that control critical flows (fee routing, oracle, admin)
  2. Check if there is a setter function protected by appropriate access control to update each address
  3. If no setter: verify the initial address is validated (non-zero, correct contract, correct interface)
  4. For proxy upgrade scenarios: check if storage layout collision could reset addresses on upgrade
- **Failure Mode**: (a) Fee always routes to `address(0)` / wrong contract with no way to fix post-deploy; (b) Oracle points to wrong feed permanently; (c) `FathomProxyWalletOwner` config addresses not updatable — any misconfiguration is permanent; (d) `update_emergency_council` function actually updates nft manager field instead due to copy-paste error (e.g., Fathom Stablecoin, Superposition emergency council update bug, HypurrFi proxy tracking misconfiguration, GainsNetwork lost roles after upgrade)
- **Common Contexts**: Diamond proxy facets, protocol configuration modules, fee routing contracts

---

## INIT-016: storage_collision_or_slot_overwrite_in_upgradeable_contract
- **Frequency**: ~8/500
- **Severity**: HIGH / CRITICAL
- **Code Shape**: Upgraded implementation adds new storage variables at the beginning of the layout (instead of appending), colliding with existing proxy storage slots; or unstructured storage key is predictable/shared
- **Detection Heuristic**:
  1. Compare storage layout (slot order) between old and new implementation versions
  2. Check that new variables are added only at the END of the existing layout, or use EIP-1967 named slots
  3. For Diamond proxy: verify `DiamondInit` does not overwrite slots used by existing facets
  4. For Solady `_initializableSlot()`: check override doesn't inadvertently share slot with other state
- **Failure Mode**: New implementation reads wrong value from colliding slot — owner address corrupted, initialized flag reset, key parameter zeroed; leads to ownership takeover or protocol freeze (e.g., zkSync Layer 1 storage collision, Connext DiamondInit unauthorized access, Coinbase Solady `_initializableSlot` override)
- **Common Contexts**: Diamond proxy upgrades, UUPS upgrade paths with new variables, custom storage layout contracts

---

## INIT-017: solana_missing_account_seed_or_bump_validation
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Solana program initializes or accesses PDA accounts without validating that the provided bump is canonical, or without verifying that the account seeds match expected program-derived seeds
- **Detection Heuristic**:
  1. Find all PDA account usages in instruction handlers
  2. Check: does the instruction verify `bump == expected_canonical_bump` (from `find_program_address`)?
  3. Verify: are the seeds used for PDA derivation validated against expected values (e.g., user pubkey, mint, program ID)?
  4. Check for missing discriminator verification (`unpack_from_slice` without discriminator check)
- **Failure Mode**: Attacker supplies a non-canonical PDA or crafts seeds to collide with a legitimate PDA, allowing account substitution or spoofing of stake/position data; discriminator-less deserialization allows passing wrong account type (e.g., Adrena missing seed verification, Code Inc. missing canonical bump, Etherfuse Stablebond discriminator check bypass, Anchor single-byte discriminator conflict)
- **Common Contexts**: Solana staking programs, DeFi position managers, bridge programs, any Anchor-based protocol with PDAs

---

## INIT-018: first_deposit_or_epoch_ignored_due_to_accounting_start_condition
- **Frequency**: ~11/500
- **Severity**: HIGH
- **Code Shape**: Protocol's accounting only starts after a triggering event (first fee, first market trade, first epoch settlement), but users can deposit/stake/interact before that event — their activity is silently ignored or attributed to wrong epoch
- **Detection Heuristic**:
  1. Find `require(totalFeeReceived > 0)` or `require(lastMarketFeeTime > 0)` or equivalent state guards in accounting updates
  2. Check: can users deposit/stake BEFORE this guard condition is ever triggered?
  3. Verify: if yes, do deposited assets correctly accrue value, or are they attributed to epoch 0 with no corresponding reward?
  4. Look for `if (state == 0) return` patterns that skip accounting for early participants
- **Failure Mode**: First depositors lose their deposits or rewards because accounting hasn't started yet; their shares count toward supply but not toward rewards; or their deposit triggers a state machine branch that permanently ignores them (e.g., Part 2 protocol markets/vaults not updating until first fee, Berachain first deposit lost in block builder, Timeswap first LP increased duration reward)
- **Common Contexts**: Epoch-based reward systems, protocol-fee-activated vaults, market maker AMMs with fee-triggered accounting

---

## INIT-019: wrong_parameter_in_cross_chain_or_remote_call_initialization
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain message, remote transfer, or LayerZero/Wormhole integration passes the wrong address or parameter at initialization time — e.g., using `msg.sender` where `to` address should go, or wrong chain ID in peer config
- **Detection Heuristic**:
  1. Find all cross-chain message construction points (LayerZero `lzSend`, Wormhole `publishMessage`, etc.)
  2. Verify each parameter position against the interface spec: `from`, `to`, `amount`, `chainId` must be in correct order
  3. Check remote transfer initialization: does it use the right address variable for the recipient field?
  4. For Wormhole NTT: verify Transceiver instruction ordering matches expected array index
- **Failure Mode**: All USDO/token balances of users drained because wrong address is used as recipient in remote transfer — sends to attacker-controlled address; or cross-chain messages perpetually fail due to wrong peer setup (e.g., Tapioca wrong parameter in remote transfer, Wormhole Transceiver ordering, Axelar ITS Hub balance initialization)
- **Common Contexts**: LayerZero integrations, Wormhole NTT, cross-chain bridge initialization, omnichain token protocols

---

## INIT-020: deployment_race_condition_multi_contract_initialization
- **Frequency**: ~7/500
- **Severity**: HIGH
- **Code Shape**: Protocol requires N contracts to be deployed and cross-configured atomically, but deployment is multi-step; intermediate state window allows attacker to interact with partially-configured system
- **Detection Heuristic**:
  1. Map all contracts that must reference each other post-deployment (circular dependencies)
  2. Check if any contract is usable (non-reverts on critical functions) before the full cross-configuration is complete
  3. Look for initialization functions that set paired-contract addresses after deployment
  4. Verify deployment scripts: are all cross-references set atomically (same tx or in same deployer bundle)?
- **Failure Mode**: Attacker calls a function on a partially-initialized contract while its counterpart (oracle, collateral registry, gauge) is not yet set — causes permanent bad state, exploits misconfigured initial values, or front-runs the configuration with malicious parameters (e.g., Sai race conditions during multi-contract deployment, Nord Finance missing address verification, StationX cross-chain DAO deployment blocking)
- **Common Contexts**: Multi-contract DeFi systems (lending + oracle + collateral), DEX + gauge + voter systems, cross-chain factory deployments

---

## INIT-021: missing_two_step_ownership_or_no_transfer_guard_on_init
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Ownership or critical role is transferred in a single step during initialization without confirmation; or `transferOwnership()` is called to an unverified address — if target address is wrong, ownership is permanently lost
- **Detection Heuristic**:
  1. Find `transferOwnership`, `setOwner`, or admin-setting calls in initializers / deployment scripts
  2. Check if the pattern is two-step (propose + accept) or single-step
  3. For single-step: verify the target address is validated (non-zero, expected deployer)
  4. Flag `HypurrFi` style: `_deployUsdxl` deploys token but doesn't transfer ownership to `admin` — ownership stays with deployer contract that has no update path
- **Failure Mode**: (a) Ownership transferred to wrong address → permanently locked admin functions; (b) Ownership remains with factory/deployer contract that has no owner-action path → governance functions inaccessible; (c) Admin must wait for timelock but code omits wait — bypasses timelock entirely (e.g., HypurrFi ownership not transferred, Forgeries timelock bypass, Advanced Blockchain lack of two-step process)
- **Common Contexts**: Protocol deployers, vesting/treasury contracts, token launch factories

---

## INIT-022: incorrect_fee_growth_or_accumulator_initial_value_in_amm
- **Frequency**: ~9/500
- **Severity**: HIGH
- **Code Shape**: AMM fee accumulator (`feeGrowthGlobal`, `secondsPerLiquidityInsideX128`, `feeGrowthInside`) is initialized at the wrong global value when a position is minted or a tick is crossed, causing incorrect fee attribution going forward
- **Detection Heuristic**:
  1. Find all position-creation and tick-initialization code paths in Uniswap V3 forks
  2. For each tick initialization: verify `feeGrowthOutside` is set to current `feeGrowthGlobal` if tick is at or below current tick, and 0 if above (matching Uniswap V3 spec)
  3. For each position mint: verify `feeGrowthInsideLast` is snapshotted from current `feeGrowthInside` at the moment of mint
  4. Check `secondsPerLiquidityPeriodStartX128` initialization; underflow when current value < period start value
- **Failure Mode**: Position accumulates phantom fees from before it was created; or fees for legitimate LP are double-counted / zeroed; in extreme cases attacker mints position at wrong tick state to claim entire pool fee accumulation (e.g., Sushi `feeGrowthGlobal` at tick crossing, Ramses V3 `secondsPerLiquidityInsideX128` negative result, Ammplify uninitialized ticks stealing collateral, Sorella Angstrom fee growth initialization)
- **Common Contexts**: Uniswap V3 forks, concentrated liquidity managers, tick-based AMMs with per-position fee accounting
