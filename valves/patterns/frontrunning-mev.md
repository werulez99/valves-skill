# Front-Running & MEV Patterns
> Extracted from 2,591 findings (500 sampled)
> Pattern count: 22

---

## MEV-001: missing_swap_slippage_protection
- **Frequency**: ~95/500
- **Severity**: HIGH
- **Code Shape**: `swap(tokenIn, tokenOut, amountIn, 0)` or `amountOutMin: 0` or `minAmountOut` param unused/hardcoded to zero; `exactInput`/`exactOutput` calls with no lower bound on output
- **Detection Heuristic**:
  1. Search for DEX router calls: `swap`, `exactInputSingle`, `exactInput`, `swapExactTokensForTokens`, `swapTokensForExactTokens`, `exchange`
  2. Inspect each call site for `amountOutMin` / `minReturn` / `minAmountOut` argument
  3. Flag if argument is literal `0`, a hardcoded constant, unchecked `type(uint).min`, or derived from manipulable on-chain state (slot0, spot price)
  4. Check whether caller can pass an arbitrary value — if so verify it is actually validated (not just passed through)
  5. Confirm the swap is executable by any user (not gated to trusted role that would reduce exploitation likelihood)
- **Failure Mode**: Sandwich attacker manipulates pool before and after target transaction, extracting the full price impact as profit. Victim receives far fewer tokens than expected with no revert.
- **Common Contexts**: Yield vault `harvest()` / `reinvest()` / `compound()`, collateral liquidation, reward-token-to-base-token swaps, protocol-owned treasury swaps, `rebalancePair()`, `_sellDsReserve()`, `closePositionFarm()`, `commitAndClose()`, multi-hop paths

---

## MEV-002: erc4626_first_depositor_inflation_attack
- **Frequency**: ~55/500
- **Severity**: HIGH
- **Code Shape**: ERC-4626 (or Compound-style) vault with `shares = assets * totalSupply / totalAssets`; no virtual offset (`EIP-4626` dead-shares mint or `10**decimalsOffset()` offset); first depositor can donate directly to vault before others
- **Detection Heuristic**:
  1. Locate `deposit()`/`mint()` share calculation: `shares = amount * totalSupply / totalAssets` (integer division)
  2. Check if `totalSupply == 0` path is specially handled (virtual shares, dead shares, offset)
  3. Check if `totalAssets` can be inflated by direct transfer (i.e., no `balanceOf` snapshotting) before second depositor
  4. Confirm `convertToShares()` and `convertToAssets()` exhibit the same rounding toward vault
  5. Verify no minimum deposit amount prevents dust-first-deposit attack
- **Failure Mode**: Attacker deposits 1 wei to become sole share holder, then donates large amount directly to vault, inflating share price. Second depositor's `amount * 1 / largeAmount` rounds to 0 shares — depositor loses funds.
- **Common Contexts**: All ERC-4626 vaults, Compound forks (`CToken`), staking vaults, insurance funds, liquidity pools without LP fee burn on first mint, `DIAExternalStaking`, `ggAVAX`, `StakedToken`, `AutoPxGmx`

---

## MEV-003: slot0_price_used_as_oracle
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: `IUniswapV3Pool(pool).slot0()` → `sqrtPriceX96` used directly as price reference for slippage limit, collateral valuation, or mint calculation; no TWAP fallback; no staleness check
- **Detection Heuristic**:
  1. Search for `.slot0()` calls in the codebase
  2. Trace `sqrtPriceX96` / `tick` output through calculations
  3. Flag any path that feeds slot0 data into `amountOutMin`, `minTokensReceived`, `liquidation threshold`, or `exchange rate`
  4. Verify whether a TWAP (e.g., `observe()`) or Chainlink price is used instead; if slot0 is combined with TWAP, confirm TWAP is the binding constraint
  5. Check if the slot0 consumer is callable within a flash-loan callback or single transaction
- **Failure Mode**: Attacker flash-manipulates pool price, which slot0 reflects immediately. Slippage check passes at manipulated price, so protocol executes at a disadvantageous rate. Attacker profits from the price difference.
- **Common Contexts**: `_calculatePriceFromLiquidity()`, `_getSwapPrice()`, on-chain slippage calculation helpers, Uniswap V3 position managers, cross-chain bridge oracle reads, `SponsorVault`

---

## MEV-004: initializer_frontrunning
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: `initialize()` / `init()` function with no `initializer` modifier or no deployer check; called in a separate transaction from deployment (not in constructor); proxy pattern where implementation is deployed uninitialized
- **Detection Heuristic**:
  1. Find all functions named `initialize`, `init`, `setUp`, or `__init`
  2. Check if they contain `require(!initialized)` or OpenZeppelin `initializer` modifier
  3. Verify they are called atomically in the deployment transaction (same tx as `create`/`create2`) or that the deployer address is checked
  4. For proxy patterns, confirm the implementation contract itself is also initialized (to prevent `delegatecall` hijack)
  5. Check if any critical state (owner, token address, fee recipient) is set in `initialize` — these become attacker-controlled if front-run
- **Failure Mode**: Attacker observes deployment tx in mempool, front-runs `initialize()` with their own parameters (arbitrary owner, fee recipient, or protocol config), seizing control before the legitimate deployer.
- **Common Contexts**: Upgradeable proxies, pool initialization (`Algebra`, `UniswapV3`), bridge program initializers (Solana `gorples-bridge`), wallet factories, `EasyTrack`, cross-layer portals, `NoteERC20`

---

## MEV-005: oracle_price_update_sandwich
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Protocol uses off-chain or admin-pushed price oracle; price update is a separate transaction visible in mempool; no cooldown, no TWAP smoothing, no per-block update limit between price update and user operations
- **Detection Heuristic**:
  1. Identify price setter function (e.g., `setPrice()`, `updateOracle()`, `postPrice()`)
  2. Check if function is publicly callable or easily observable (keeper, cron)
  3. Trace whether a deposit/withdraw/mint/redeem function uses the oracle price in the same block as the update
  4. Confirm there is no time-weighted mechanism or one-update-per-block guard
  5. Compute worst-case price deviation an attacker can exploit: `profit = (priceAfter - priceBefore) * attackerBalance`
- **Failure Mode**: Attacker monitors mempool for oracle price update, sandwiches it: (1) enters a position at stale price, (2) oracle updates, (3) exits at new price — capturing the full price movement risk-free.
- **Common Contexts**: Bancor V2 AMM, AFI Vault, RocketPool `rETH`, manual price feeds, ERC-4626 vaults with off-chain NAV updates, lending protocols with admin-set rates, `MontRewardManager` using `quoteExactInputSingle()`

---

## MEV-006: reward_distribution_deposit_frontrun
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: Reward token distributed to existing stakers via `distribute()` / `harvest()` / `poke()` / `compound()` in a single transaction; no snapshot mechanism; instant share credit on deposit; large staker can deposit just before distribution and withdraw after
- **Detection Heuristic**:
  1. Find reward distribution trigger: public/keeper-callable function that accrues reward to stakers proportionally
  2. Trace if new deposits made in same block receive the same reward ratio as long-term stakers
  3. Check for any lock period, anti-flash-deposit guard (e.g., `lastDepositTime + minStakePeriod`), or snapshotting that excludes fresh deposits
  4. Verify the deposit → distribution → withdrawal sequence can complete in 1 block / 1 tx
  5. Check staking pools: `_onDepositETH` sets `claimed[][]` to max without distributing pending rewards — new large depositor dilutes existing rewards
- **Failure Mode**: Attacker flash-deposits or deposits in the same block as reward distribution, captures a disproportionate share of rewards, then withdraws immediately. Honest stakers receive less than expected.
- **Common Contexts**: Staking vaults, `RocketRewardPool`, `GiantMevAndFeesPool`, `STK-1 Key Finance`, bribe distribution in ve-token systems, `pokeTokens()` in gauge systems, `stUSDC#poke`, `onUnderlyingBalanceUpdate()`

---

## MEV-007: sandwich_attack_on_amm_parameter_change
- **Frequency**: ~15/500
- **Severity**: HIGH
- **Code Shape**: Admin/governance function changes AMM parameters (fee, curve coefficient, pool width, price bounds) in a publicly visible transaction; no timelock; protocol's own liquidity is redeployed or rebalanced as direct consequence
- **Detection Heuristic**:
  1. Find admin setter for AMM economic parameters: `changeParameters()`, `setPositionWidth()`, `setFee()`, `rampA()`, `setAdiabatic()`
  2. Check if the setter triggers automatic rebalancing / liquidity redeployment in the same call
  3. Verify if there is a timelock or commit-reveal delay between parameter announcement and activation
  4. Trace whether liquidity redeployment involves external DEX swaps with no slippage protection
  5. Compute whether attacker can enter before parameter change, exit after, profiting from forced rebalance
- **Failure Mode**: Attacker sandwiches admin parameter change: (1) takes a directional position, (2) admin changes parameter causing forced protocol rebalance at market price, (3) attacker exits. Protocol funds drained or LPs suffer losses.
- **Common Contexts**: Primitive Hyper `changeParameters()`, Beefy Finance `setPositionWidth()+unpause()`, Perennial V2 market coordinator, Malt Protocol `livePrice` manipulation, AragonBlack fee changes, adiabatic fee markets

---

## MEV-008: commit_reveal_broken_or_missing
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Protocol relies on a commitment scheme for registration, name reservation, or NFT minting but: (a) commitment is missing entirely, (b) `block.timestamp` bounds check is inverted or off-by-one making the reveal window always valid, or (c) commitment does not cover all parameters (payer, salt, deadline)
- **Detection Heuristic**:
  1. Find registration/claim/mint functions that are supposed to be front-run protected
  2. Check for commit step: `commit(bytes32 hash)` before `reveal()`
  3. Verify the hash covers ALL relevant parameters (recipient, name, salt, nonce) — partial coverage still allows front-run by reusing valid commit
  4. Check time bounds: `block.timestamp >= commitTime + MIN_COMMITMENT_AGE && block.timestamp <= commitTime + MAX_COMMITMENT_AGE` — incorrect operator (`<=` vs `>=`) breaks the protection
  5. For NFT mint, confirm that the mint function checks `msg.sender == committer`
- **Failure Mode**: Attacker observes pending transaction in mempool, submits identical call with higher gas. Victim's transaction reverts or registers at wrong parameters. In broken commitment schemes, attacker reuses valid commitment from mempool.
- **Common Contexts**: ENS `ETHRegistrarController.register`, name services (BNS), NFT minting, `Hyperware` wallet registration, Sound.xyz `FixedPriceSignatureMinter`, fixed commitment scheme with inverted bounds

---

## MEV-009: signature_replay_and_frontrun
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: EIP-712 / ECDSA signature consumed in function that can be replayed; nonce on wrong party (e.g., nonce on privilege, not on account); `safeAddress` / `chainId` / `caller` not included in signed message; unsigned fee parameters; unsigned callback data
- **Detection Heuristic**:
  1. Find all `ecrecover` / `ECDSA.recover` / `isValidSignature` usage
  2. Inspect the signed struct fields: must include `nonce`, `deadline`, `chainId`, `target address`, and all parameters that affect execution outcome
  3. Verify the nonce is on the entity that should be protected (signer's account), not on a shared resource
  4. Check if the signature can be replayed before nonce invalidation (re-entrancy window, out-of-order nonce increment)
  5. For permit-style flows, verify `pullTokensWithPermit` cannot be called by third parties to consume approvals
- **Failure Mode**: Attacker extracts valid signature from mempool and submits it first (classic front-run), or replays it in a different context (cross-chain, different caller) not covered by the signed parameters. Victim's intended action is corrupted.
- **Common Contexts**: `refinanceFull`/`addNewTranche` (Gondi), `createArt` (Phi), SmartAccount `execTransaction`, session calls (Sequence), `pullTokensWithPermit` (BakerFi), `VVVVCTokenDistribution::claim`, `AgentDataOracle` credentials, `NFTSimpleAuction` purchase, `NativeTokenPaymentEnforcer`

---

## MEV-010: pool_initialization_price_frontrun
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Permissionless pool deployment or `initialize()` sets initial `sqrtPriceX96`; no bounds check or ownership check on the initialization call; attacker can initialize at arbitrary price before legitimate protocol action
- **Detection Heuristic**:
  1. Find pool `initialize(sqrtPriceX96)` — typically `IUniswapV3Pool.initialize()` or AMM-specific equivalent
  2. Check who can call it: if permissionless, any attacker can call it first
  3. Verify whether the deploying protocol enforces atomic deployment + initialization (in same tx)
  4. Check if an off-price initialization causes the first legitimate `addLiquidity` to fail or LP positions to be economically exploited
  5. For `create2`, verify that the predicted address is used and initialization is bundled
- **Failure Mode**: Attacker initializes pool at extremely skewed price. First legitimate LPs add liquidity at wrong price, suffering immediate impermanent loss. Protocol may also be unable to bootstrap the intended price range.
- **Common Contexts**: Algebra Finance pool creation, Uniswap V3-based protocols, Radiant V2 `UniswapPoolHelper`, Serious `SeriousMarket`, DAOfi pair creation, `DaosLive finalize()`

---

## MEV-011: jit_liquidity_and_anti_sandwich_bypass
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Hook-based JIT liquidity protection in Uniswap v4 (`AntiSandwichHook`, `LiquidityPenaltyHook`); bypass via: (a) JIT attack via existing in-range liquidity not covered by same-block check, (b) first-in-block asymmetric initialization leaving state stale, (c) incorrect `unspecifiedAmount` handling that breaks fee accounting, (d) integer underflow in `int128` cast
- **Detection Heuristic**:
  1. In Uniswap v4 hook, find where `beforeSwap` / `afterSwap` records "first swap in block" state
  2. Check if JIT liquidity added before the first swap (or in the same block via a different path) bypasses the hook check
  3. Verify `unspecifiedAmount` (exact-output swaps) is handled correctly — incorrect assumption that it equals `specifiedAmount` breaks anti-sandwich logic
  4. Check `int128` → `uint128` casts for underflow when delta is negative
  5. Confirm first-in-block initialization is symmetric for both swap directions
- **Failure Mode**: MEV bot bypasses hook protection: adds JIT liquidity, profits from the swap fees that the hook was supposed to penalize, removes liquidity — circumventing the anti-sandwich mechanism.
- **Common Contexts**: OpenZeppelin Uniswap Hooks v1 `AntiSandwichHook`, `LiquidityPenaltyHook`, `BaseCustomAccounting`, Uniswap Hooks Library `BaseCustomAccounting`

---

## MEV-012: liquidation_frontrun_and_dos
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: Liquidation is triggered by a public call; liquidatee or griever can front-run with: (a) small collateral top-up that momentarily heals position, (b) nonce increment invalidating liquidation tx, (c) dust deposit DOS preventing profitable execution, (d) `stopTrade()` call blocking liquidation
- **Detection Heuristic**:
  1. Identify liquidation function: `liquidate()`, `liquidatePosition()`, `flagShort()`, `liquidateSecondary()`
  2. Check if the position's health factor is re-evaluated after the mempool delay — if liquidatee can change collateral in a separate tx, they can heal the position
  3. Check if any user-controlled nonce or state used in liquidation can be incremented to invalidate the pending liquidation tx
  4. Verify whether dust positions below liquidation profit threshold can be used to block wholesale liquidation
  5. For challenges (e.g., Frankencoin): confirm challenged position cannot de-leverage between challenge creation and resolution
- **Failure Mode**: Borrower avoids liquidation by healing position in mempool, or griever blocks legitimate liquidations via DoS. Protocol accumulates bad debt. Liquidators lose gas.
- **Common Contexts**: Beedle, DittoETH, Narwhal Finance, Stella, Frankencoin, Symmetrical (nonce increment), Salty.IO (min deposit evasion), LoopFi `CDPVault`, Creditswap

---

## MEV-013: deadline_missing_or_ineffective
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Swap or liquidity operation uses `deadline` parameter but: (a) passes `block.timestamp` as deadline (always valid), (b) deadline is hardcoded to `type(uint256).max`, (c) deadline is checked against wrong timestamp, (d) deadline check exists but slippage param is unused so protection is still absent
- **Detection Heuristic**:
  1. Find all DEX interaction call sites
  2. Search for `deadline` argument; flag `block.timestamp` or `type(uint256).max` or `2**256-1` literals
  3. If a real deadline is passed, confirm slippage params are also set (deadline alone is insufficient without minimum output)
  4. Check if stale transactions can execute at outdated price despite deadline
  5. Grep for `swapExactTokensForTokens(..., block.timestamp)` patterns — canonical anti-pattern
- **Failure Mode**: Transaction sits in mempool during network congestion or validator manipulation. When eventually executed, market price has moved adversarially. Deadline check passes because it uses `block.timestamp`, leaving slippage as the only protection — which may also be absent.
- **Common Contexts**: Blueberry Update, USSD, protocol-managed swaps that copy `block.timestamp` as deadline, any swap wrapper that doesn't expose deadline to caller

---

## MEV-014: pending_allowance_exploit_erc20_approve_frontrun
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Classic ERC-20 `approve()` race: user increases allowance from non-zero to new value; spender front-runs `transferFrom` at old allowance, then again at new allowance; or protocol uses `approve(max)` without checking existing approval first
- **Detection Heuristic**:
  1. Find `approve()` calls not preceded by `approve(0)` reset
  2. Check for `increaseAllowance`/`decreaseAllowance` — absence of these helpers is a signal
  3. In protocols: find where `approve` is called for a router/spender and verify current allowance is zeroed first
  4. Trace `transferFrom` call sites: can spender consume approval in a front-run before the main operation?
  5. Check for open delegation patterns where `NativeTokenPaymentEnforcer` collects native tokens from pending approvals
- **Failure Mode**: Malicious spender observes `approve(newAmount)` in mempool, drains old allowance, then drains new allowance — double-spending the user's tokens.
- **Common Contexts**: Tapioca (H-14), Metamask Delegation Framework `NativeTokenPaymentEnforcer`, any protocol with non-atomic `approve` + `transferFrom`, `RollerPeriphery.approve()` DoS pattern

---

## MEV-015: frontrun_withdrawal_and_claim_dos
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Withdrawal/claim is a two-step process (request + finalize) or uses a queue; attacker can front-run the finalize step to: (a) add dust to change state before finalization, (b) cancel request from queue, (c) steal the withdrawal by calling `finishWithdrawal()` first, (d) block with forced revert via fake token tip
- **Detection Heuristic**:
  1. Find multi-step withdrawal flows: `requestWithdraw()` + `finishWithdrawal()` / `claimRefund()`
  2. Check if `finishWithdrawal()` or equivalent has `msg.sender == requester` check
  3. For queue-based withdrawals, verify queue entries cannot be cancelled by third parties
  4. Check if dust insertion (1 wei) into intermediate state causes queue processing to revert
  5. For EigenLayer-style validator unstaking, verify proof submission cannot be front-run to permanently block the unstake
- **Failure Mode**: Attacker front-runs withdrawal finalization, stealing funds or permanently locking the user's assets. Queue-based systems can be bricked by inserting cancellable entries that cause revert on processing.
- **Common Contexts**: Karak (`finishWithdrawal`), DYAD, SEDA Protocol, Casimir validator unstaking, Accountable `cancelRedeemRequest`, reNFT rental order, EigenLayer-based protocols, Forta Staking Vault undelegation

---

## MEV-016: staking_reward_snipe_before_epoch
- **Frequency**: ~14/500
- **Severity**: HIGH
- **Code Shape**: Staking reward distributed at epoch end or on oracle report; no minimum stake duration; large flash deposit just before epoch snapshot captures rewards proportional to balance at snapshot moment; `claimReward()` computes based on current stake without time-weighted average
- **Detection Heuristic**:
  1. Find staking reward distribution: `claimReward()`, `getReward()`, epoch-based emissions
  2. Check if reward calculation uses current balance vs. time-weighted balance
  3. Verify if `stake()` in the same block as `claimReward()` is possible and yields the same reward ratio as long-term stakers
  4. For Lido/RocketPool: check if `checkpointTotalSupply()` can snapshot before timestamp is final (mid-block)
  5. For `PoolTogether` pod: verify winning pod cannot be front-run with large deposit before random selection
- **Failure Mode**: Attacker deposits just before reward snapshot, receives disproportionate reward, withdraws immediately. Long-term stakers' yield is diluted. In worst case (lottery), attacker wins disproportionate jackpot share.
- **Common Contexts**: PoolTogether Pods, RocketPool `RocketRewardPool`, Stakehouse `GiantMevAndFeesPool`, Alchemix (bribe distribution), `BBRO rewards` (Brokkr), `Seconds*Liquidity` manipulation (Sushi), `checkpointTotalSupply()` (Alchemix)

---

## MEV-017: predictable_randomness_manipulation
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Randomness derived from `block.timestamp`, `block.number`, `blockhash`, or miner-influenceable fields; no VRF; or VRF output can be re-rolled by miner discarding block; on-chain pseudo-random used for NFT selection, lottery winner, or game outcome
- **Detection Heuristic**:
  1. Find `random` / `rand` / `_getRandom` / `keccak256(abi.encodePacked(block.*))` patterns
  2. Confirm if Chainlink VRF (or equivalent) is used; if not, flag
  3. For VRF: check if miners can re-roll by not publishing a block — PoolTogether H-02 pattern where miner discards unfavorable blocks
  4. Check if the randomness-dependent outcome (NFT, winner) can be predicted and timed within same block
  5. For games: verify if outcome is determined at time of request (vulnerable) or at time of fulfillment (safer)
- **Failure Mode**: Miner / validator selectively includes transactions to guarantee favorable randomness outcome. Attacker computes favorable seeds off-chain and submits only winning transactions.
- **Common Contexts**: PoolTogether (miner VRF re-roll), `PenguinManager` (block-based randomness), lottery contracts, NFT mints with `block.timestamp` seed, `apDAO_2024-10-03` auction NFT selection

---

## MEV-018: cross_chain_frontrun_and_message_manipulation
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: Cross-chain message relayer is permissionless; message can be observed in source chain mempool and front-run on destination chain; callback/payload does not include origin chain identifier; bridge NFT call can be front-run to deploy token at wrong address
- **Detection Heuristic**:
  1. Find cross-chain receive handlers: `lzReceive()`, `ccipReceive()`, `receiveWormholeMessages()`, `cross_chain_callback()`
  2. Check if the handler validates `msg.sender == trustedRelayer` AND that the source chain is part of the signed message
  3. Verify bridge transfer ID is checked to prevent replay of messages in different order
  4. For NFT bridges: confirm token deployment address is atomically locked before bridging (not predictable from public state alone)
  5. Check if the dual-transaction nature of OFT composed messages (send + compose) allows attacker to steal in the gap between steps
- **Failure Mode**: Attacker observes cross-chain message, front-runs execution on destination chain to steal funds, block the delivery, or manipulate recipient state before the legitimate relay arrives.
- **Common Contexts**: Chakra `cross_chain_callback`, Connext `NomadFacet`, Axelar `expressReceiveToken`, LayerZero V2 OFT composed messages (Canto H-02), Gains Trade `NFTMintingBridge`, Linea `finalizeBlocks`

---

## MEV-019: donate_attack_on_amm_or_vault
- **Frequency**: ~12/500
- **Severity**: HIGH
- **Code Shape**: `totalAssets()` or pool reserve count includes freely-transferable tokens (no `balanceOf` snapshot); attacker donates tokens directly (no `deposit()`) to inflate share price or manipulate AMM state; `NoopVault` strategy reads vault balance without accounting for donations separately
- **Detection Heuristic**:
  1. Find `totalAssets()` / `totalSupply()` / reserve-reading logic
  2. Check if it calls `token.balanceOf(address(this))` directly — this is inflatable by donation
  3. Verify if any protocol function relies on this balance in a way that can be exploited (e.g., exchange rate calculation, LP share minting)
  4. For AMM ticks (Curve): check if empty tick vaults issue shares based on inflated balance after 1-wei donation
  5. For Hyperdrive: confirm that 0-share-mint-for-LP scenario is prevented by minimum share threshold
- **Failure Mode**: Attacker donates a large amount to vault/pool, inflating the effective price. Subsequent depositors receive fewer shares (or zero shares) than expected. Attacker exits with disproportionate share of the inflated pool.
- **Common Contexts**: Burve `NoopVault` (H-7), Curve Finance empty tick inflation, Hyperdrive zero-shares mint (Critical), `TermMaxMarket.provideLiquidity`, `addLiquidity` 1-wei DoS (GTE launchpad graduation), Blend Capital price inflation

---

## MEV-020: governance_vote_and_proposal_frontrun
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Flash-loan or same-block deposit grants voting power before snapshot; `vestFor()` callable by anyone to grief user voting; reward claiming front-run in `pokeTokens()` gauge mechanics; no delay between token acquisition and voting power activation; governance proposal passes before first `VOTES` minted
- **Detection Heuristic**:
  1. Find governance token snapshot mechanism: `getPriorVotes()`, `getPastVotes()`, `balanceOfAt()`
  2. Check if snapshot is block-delayed (safe) or instantaneous (vulnerable to same-block manipulation)
  3. Verify `vestFor()` / `delegateTo()` / public functions that can inflate or deflate another user's vote count
  4. Check if lending market token (e.g., AUD) can be borrowed to influence governance outcome within a single tx
  5. Confirm proposals cannot pass with only one voter before quorum is established (Olympus DAO H-02 pattern — no `VOTES` minted yet)
- **Failure Mode**: Attacker acquires voting power via flash loan or front-runs token distribution, manipulates proposal outcome, then returns tokens in the same transaction. Governance decision is corrupted.
- **Common Contexts**: Olympus DAO (H-02 no votes minted), Audius (AUD borrow governance attack), Alchemix bribe checkpoint deflation, `vestFor` griefing (Vader Protocol), FIAT DAO delegation avoidance

---

## MEV-021: gas_fee_manipulation_and_block_stuffing_dos
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Protocol exposes a cheap public function that can be called repeatedly to fill block gas limit; gas refund logic reimburses full gas tip incentivizing attackers to submit high-priority spam; fixed fee undercharges the cost of block-stuffing; gas price spike causes slashing of legitimate operator who cannot respond in time
- **Detection Heuristic**:
  1. Find keeper/relayer functions with gas reimbursement: `execute()`, `relay()`, `fulfill()`
  2. Check if reimbursement covers full `tx.gasprice * gasUsed` — if yes, attacker can stuff block at zero net cost
  3. Verify fixed fee per transaction vs. variable block gas cost — can attacker profit from fee arbitrage?
  4. Find time-sensitive operator functions (e.g., `HolographOperator` selected operator window) and check if gas spike can cause slashing
  5. For L2/L3 sequencers: check if large data payloads can be submitted cheaply to bloat state without proportional cost
- **Failure Mode**: Attacker spams transactions to block legitimate protocol operations (DoS), or manipulates gas conditions to slash honest operators who cannot respond quickly enough during gas spikes.
- **Common Contexts**: MANTRA (full gas tip refund H-03), ALEO (split tx fixed fees), Holograph/Protocol (gas spike operator slashing), Tide Forwarder gas limit manipulation, SEDA (large invalid tx), Sei mempool overflow

---

## MEV-022: user_specified_slippage_frontrunnable
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: User supplies their own `minAmountOut` or `maxSlippagePct` parameter; protocol uses this user-defined value directly without bounding it against on-chain state; attacker front-runs to manipulate pool just enough to satisfy user's (possibly lenient) slippage tolerance
- **Detection Heuristic**:
  1. Find functions that accept user-provided slippage parameter: `minOut`, `minAmount`, `slippagePct`
  2. Check if there is a protocol-level maximum slippage cap enforced on top of user input
  3. Verify the user cannot specify `0` (unlimited slippage) without a protocol check rejecting it
  4. Check if user-defined slippage is calculated off-chain based on a stale price quote and submitted in a later block — by which point pool state may have changed
  5. For lending repayment: confirm dynamic slippage params are not derived from easily manipulable `slot0` (Real Wagmi H-4 pattern)
- **Failure Mode**: User sets lenient slippage (or system computes slippage from stale state). Attacker manipulates price to the exact boundary of user's tolerance, extracting maximum MEV while still satisfying the slippage check.
- **Common Contexts**: UXD Protocol H-6, Arkis DeFi (user-executed swaps bypass sandwiching protection), Real Wagmi (dynamic slippage from slot0), Illuminated PT redemption, `OptionTokenV4.exerciseLP` addLiquidity slippage
