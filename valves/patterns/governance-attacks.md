# Governance Attack Patterns
> Extracted from 6,020 findings (500 sampled)
> Pattern count: 38

---

## GOV-001: flash_loan_vote_manipulation
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `castVote()` / `propose()` called in same tx as flash loan borrow; voting weight computed from `balanceOf()` or `totalSupply()` at current block without snapshot
- **Detection Heuristic**:
  1. Locate vote-weight calculation — check if it uses `balanceOf(account)` directly rather than a checkpoint/snapshot at `proposal.startBlock`
  2. Check whether a `propose()` or `castVote()` entrypoint can be called in the same transaction as a large token borrow from any flash-loan provider
  3. For "Early Execution" voting modes, verify whether quorum can be reached within a single block
  4. Check if there is a minimum delay enforced between token acquisition and voting eligibility
  5. Look for `EarlyExecution` or equivalent flags in `Governor` config — these are highest risk
- **Failure Mode**: Attacker borrows large governance token balance via flash loan, reaches quorum and passes/blocks proposals within a single transaction, then repays the loan — governance outcome determined by a user who held tokens for 0 seconds
- **Common Contexts**: `Governor` + `ERC20Votes` without snapshot delay; Aragon DAO Gov Plugin `EarlyExecution` mode; compound-style governance with `balanceOf`-at-vote-time weight; veToken systems where tokens can be briefly borrowed

---

## GOV-002: vote_delegation_double_counting
- **Frequency**: ~18/500 findings
- **Severity**: HIGH
- **Code Shape**: `_moveDelegates()` called on both `from` and `to` on transfer/delegate; `numCheckpoints[delegatee]` updated in both old and new checkpoint slot; `tokenId` appended to delegate list without uniqueness check
- **Detection Heuristic**:
  1. Trace `_moveDelegates` / `_moveVotingPower` — verify it subtracts from old delegatee AND adds to new delegatee, not adds to both
  2. Check `_writeCheckpoint` — does same-block write update existing entry or append a new one? Appending creates duplicates
  3. For NFT-based voting (`ERC721Votes`), check if transferring a token to self then delegating, or delegating then delegating again, leaves stale entries
  4. Verify delegate list deduplication — search for `push` to an array of tokenIds without checking for existing membership
  5. Check `afterTokenTransfer` hook — does it move votes between token owner addresses or between *delegated* addresses?
- **Failure Mode**: Users accumulate votes beyond their actual token holdings; total tracked votes exceeds token supply; bribe/reward distribution based on inflated vote counts overpays attackers
- **Common Contexts**: `ERC721Checkpointable`; `VoteEscrowDelegation`; `ERC20Votes` forks; `VotingEscrow` NFT delegation; Nouns DAO / Golom / Velodrome-style veNFT systems

---

## GOV-003: expired_lock_voting_power_not_cleared
- **Frequency**: ~9/500 findings
- **Severity**: HIGH
- **Code Shape**: `veToken.balanceOf()` returns non-zero after lock expiry; `_checkpoint()` slope calculation assumes continuous linear decay but misses zero-floor; expired locks still counted in `totalSupply` checkpoints
- **Detection Heuristic**:
  1. Find the voting-power function — verify it returns 0 when `block.timestamp >= lock.end`
  2. Check `_checkpoint` / `_totalSupply`: does it subtract the decaying slope of expired locks, or does expired voting power persist in historical checkpoints?
  3. Verify `claim` / `getReward` functions check lock expiry before distributing
  4. Check `poke()` function — does it update voting power without verifying the lock is still active?
  5. Locate binary-search functions over checkpoint history — verify they correctly handle duplicate timestamps and boundary conditions
- **Failure Mode**: Expired lock holders continue to vote, earn rewards, and claim bribes they are no longer entitled to; `totalVoting` is inflated causing unfair bribe distribution
- **Common Contexts**: veALCX; Velodrome/Aerodrome `VotingEscrow`; Curve-style `ve` implementations; `RewardDistributor.claim()` loops; Alchemix `Bribe.sol`

---

## GOV-004: poke_function_unchecked_flux_minting
- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `Voter.poke(tokenId)` calls `_vote()` → `FluxToken.accrueFlux()` without checking `lastVoted[tokenId]`; no epoch guard on `poke`; callable unlimited times per epoch
- **Detection Heuristic**:
  1. Locate `poke()` in `Voter` contract — check if it validates `lastVoted[tokenId] < currentEpoch` before calling flux accrual
  2. Verify that the `poke` path calls `_vote` / `_updateFor` which updates FLUX balance — if so, unlimited calls = unlimited minting
  3. Check cooldown enforcement: is there a time gate (`require(block.timestamp > lastVoted + epochLength)`) before voting or flux accrual?
  4. Look for calls to `FluxToken.accrueFlux` or equivalent — ensure they are gated on epoch or `lastVoted`
  5. Check if `poke` resets the bribe epoch tracking, potentially freezing bribe tokens permanently
- **Failure Mode**: Attacker calls `poke()` in a loop within one transaction, accruing unlimited FLUX/governance tokens; also causes bribe epoch drift leading to permanent freeze of reward tokens for other users
- **Common Contexts**: Alchemix veALCX `Voter`; veToken systems with `FluxToken`; Velodrome-style gauge voters with poke mechanics

---

## GOV-005: proposal_cancellation_without_access_control
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `cancel(proposalId)` callable by anyone; no `msg.sender == proposer` check; veto path accessible without veto role; `_deleteProposal` indexing error deletes wrong proposal
- **Detection Heuristic**:
  1. Find `cancel()` / `veto()` / `deleteProposal()` — check if `msg.sender` is validated against `proposals[id].proposer` or a designated role
  2. Verify the veto mechanism: `council.veto()` or equivalent — can any party trigger it without the correct role?
  3. For `_deleteProposal` internal function, verify correct proposal ID is used as array index (off-by-one errors common)
  4. Check if cancellation is possible after proposal has passed or is in execution — some protocols allow post-pass cancellation that bypasses safeguards
  5. Search for governance bypass: does cancelling then recreating a proposal reset any critical timer or threshold?
- **Failure Mode**: Attacker cancels any active proposal at will — blocks legitimate governance; malicious actor recreates proposal after cancellation to steal eligibility rewards from other proposers; council veto protection is non-functional
- **Common Contexts**: `GovernorAlpha`; `DAO.sol`; Vader Protocol; Nouns DAO; MetaLeX `_deleteProposal`; Party Protocol `ArbitraryCallsProposal`

---

## GOV-006: voting_power_snapshot_missing_or_stale
- **Frequency**: ~11/500 findings
- **Severity**: HIGH
- **Code Shape**: `castVote()` uses `token.balanceOf(msg.sender)` at call time; no `getPastVotes(account, proposalSnapshot)` call; `totalVotesSupply` calculated at execution time not proposal creation
- **Detection Heuristic**:
  1. Find `_getVotes()` / `getVotesWithParams()` — check if it calls `getPastVotes(account, proposal.startBlock)` or current `balanceOf`
  2. Verify `quorumVotes()` uses supply snapshot at proposal start, not current supply
  3. For NFT-based voting, check if auctioned NFT's voting power is excluded from `totalVotesSupply` when calculating quorum
  4. Check `_totalCheckpoints` update path — is it called on mint/burn, or only on explicit checkpoint calls?
  5. Look for proposals that can reach quorum with 0 actual votes cast (total supply never checkpointed)
- **Failure Mode**: Users can buy tokens, vote, then sell in same block; quorum is incorrectly calculated; proposals pass without any real votes because `_totalCheckpoints` is always 0 (never populated on mints)
- **Common Contexts**: Custom `Governor` implementations; `CoreContracts`; `SnapshotRepERC20Guild`; `ArtPiece` quorum calculation; Anvil Protocol

---

## GOV-007: delegation_reentrancy_double_delegation
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `delegate()` calls external `token.transfer()` or hook before updating `_delegates` state; ERC20 `_afterTokenTransfer` hook fires into delegate update during reentrancy; `ERC20Pods` callback before state write
- **Detection Heuristic**:
  1. Trace `delegate()` execution order — is `_delegates[delegator]` updated before or after any external call / hook?
  2. Check ERC777 / ERC1363 / ERC20Pods token patterns — `tokensReceived` / `onTransferReceived` hooks fire during transfer and can reenter `delegate()`
  3. Look for CEI pattern violations in `delegate()` — state must be finalized before any external interaction
  4. In `burn()` with delegated tokens: verify delegated vote amount is subtracted before the burn executes any external calls
  5. Check `ERC20Pods._afterTokenTransfer` — if it calls `pod.updateBalances()` before delegation state is committed, reentrancy is possible
- **Failure Mode**: Attacker double-delegates the same token balance, doubling voting power permanently; or burns delegated tokens via reentrancy causing accounting desync; voting power inflated beyond token supply
- **Common Contexts**: `1Inch ERC20Pods`; Skale token delegation; veNFT systems with ERC721 callbacks; any `delegate()` that interacts with tokens before state finalization

---

## GOV-008: unrestricted_proposal_creation
- **Frequency**: ~7/500 findings
- **Severity**: HIGH
- **Code Shape**: `propose()` / `proposeBlock()` / `Proposal-Store.sol` callable by any address; no minimum token threshold or whitelist check; sender validation missing in proposal submission
- **Detection Heuristic**:
  1. Find `propose()` entrypoint — check `require(getVotes(msg.sender) >= proposalThreshold, "...")` or equivalent
  2. Verify `Proposal-Store.sol` or equivalent registry — does it restrict who may add proposals?
  3. Check for quorum bypass: can proposals reach execution threshold when created by an attacker who also controls the vote?
  4. Look for spam vector: unlimited proposals with no bond or threshold enables DoS of the election system
  5. Verify any bond/stake required to propose is actually escrowed and non-recoverable on cancellation
- **Failure Mode**: Attacker floods governance with malicious proposals; legitimate proposals are buried or quorum is split; spam proposals block finalization of valid proposals
- **Common Contexts**: `GovernorAlpha` forks; The Computable Protocol; Unigov `Proposal-Store.sol`; Layer N proposal submission; block proposer selection in L1/L2 rollup contracts

---

## GOV-009: delegatecall_to_unverified_address
- **Frequency**: ~10/500 findings
- **Severity**: HIGH
- **Code Shape**: `target.delegatecall(data)` where `target` is caller-supplied or from a registry without existence check; `VaultProxy`, `StaticHyVM`, `GuardCM` delegatecall without `extcodesize` check
- **Detection Heuristic**:
  1. Grep for `.delegatecall(` — for each occurrence, trace how `target` is determined
  2. Check if `extcodesize(target) > 0` is verified before delegatecall
  3. Look for caller-supplied module/helper addresses passed directly to delegatecall without whitelist validation
  4. For proxy patterns: verify implementation address is validated (non-zero, code exists) before delegatecall in fallback
  5. Check `GuardCM` or similar guard contracts — can they be bypassed by a delegatecall to an arbitrary address?
- **Failure Mode**: Delegatecall to zero address (no code) returns `true` with empty returndata — caller believes call succeeded; attacker-supplied implementation address can manipulate storage, drain funds, or bypass all access control
- **Common Contexts**: `VaultProxy`; `StaticHyVM`; Olas `GuardCM`; Biconomy `executeComposableDelegateCall`; Fuji Protocol proxy; Spool `withdraw()`; any upgradeable proxy fallback

---

## GOV-010: uninitialized_implementation_contract_selfdestructable
- **Frequency**: ~6/500 findings
- **Severity**: HIGH
- **Code Shape**: `initialize()` not called on implementation (logic) contract at deploy time; attacker calls `initialize()` then `selfdestruct()` via delegatecall from logic contract context; proxy points to destroyed implementation
- **Detection Heuristic**:
  1. Check deployment scripts — is `initialize()` called on the implementation contract itself (not just the proxy)?
  2. Verify implementation contract has `_disableInitializers()` in constructor or equivalent protection
  3. Look for `selfdestruct` in any function reachable via delegatecall from the implementation
  4. For UUPS: check that `upgradeTo()` requires authorization and the implementation being upgraded to is initialized
  5. Check for `SmartAccount`, `FujiVault`, `EasyTrack`, `Fractional` vaults — common targets for this pattern
- **Failure Mode**: Attacker initializes unprotected logic contract, calls selfdestruct through it, erasing the implementation code — all proxy instances point to empty address and are permanently bricked; all user funds locked forever
- **Common Contexts**: `UUPSUpgradeable` inheritors; Biconomy `SmartAccount`; Fuji Protocol; Lido `EasyTrack`; Fractional vaults; `Rio Vesting Escrow` (forged immutable args)

---

## GOV-011: initialization_frontrunning
- **Frequency**: ~6/500 findings
- **Severity**: HIGH
- **Code Shape**: `initialize(admin, ...)` callable by any address before legitimate deployer; `proxy.initialize()` unprotected in deployment transaction mempool; `elections_master` deployment with no ownership check
- **Detection Heuristic**:
  1. Check if `initialize()` has `msg.sender` validation or factory-only restriction
  2. Verify deployment is atomic — is `deployProxy` + `initialize` in a single transaction or two separate ones?
  3. For `DAO takeover during bootstrapping`: check initial admin/member assignment — is bootstrapping role open before the first legitimate call?
  4. Look for contracts that call `initialize` with hardcoded duration or parameters — these may always revert, permanently bricking the contract
  5. Check `elections_master` or equivalent governance module deployment — is ownership set in constructor or in a separate `init` call?
- **Failure Mode**: Attacker front-runs initialization, sets themselves as admin/owner; original deployer cannot re-initialize; attacker has full control over protocol governance
- **Common Contexts**: Hermez auction; `CrosslayerPortal`; XDAO `elections_master`; Rocketpool DAO bootstrapping; Geodefi `MiniGovernance`; any proxy with separate deployment + init transactions

---

## GOV-012: timelock_bypass_or_missing
- **Frequency**: ~7/500 findings
- **Severity**: HIGH
- **Code Shape**: `governor.execute()` callable immediately after `queue()` without delay; `timeLockPeriod` unset (defaults to 0); `GNTDeposit` timelock not reset on new deposit; `cancelQueued` not implemented
- **Detection Heuristic**:
  1. Find `TimelockController` or equivalent — verify `minDelay > 0` and it is set at construction
  2. Check contracts inheriting `TimeLockUpgrade` — is `timeLockPeriod` set in constructor/initializer or left at default (0)?
  3. Verify `queue()` + `execute()` flow enforces `block.timestamp >= eta` where `eta = block.timestamp + delay`
  4. Look for `cancelQueued` or equivalent — without it, malicious queued transactions cannot be stopped after passing
  5. Check if adding new deposits/stakes to a timelocked asset resets the lock period
- **Failure Mode**: Governance executes proposals instantly without community review window; emergency cancellation is impossible; malicious owner can drain protocol before community can react; timelocked tokens can be fully withdrawn immediately by re-depositing
- **Common Contexts**: Malt Finance; Origin Dollar; Set Protocol; Tally SafeGuard; `GovernorBravoDelegate` ETH lock; `GNTDeposit`; any protocol with pending governance upgrade queue

---

## GOV-013: gauge_kill_pause_token_stuck
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `killGauge()` / `pauseGauge()` sets `isAlive = false` but does not rescue FLOW/reward tokens; `voter.distribute()` skips dead gauges but tokens already sent remain trapped; voting power allocated to killed gauge lost
- **Detection Heuristic**:
  1. Find `killGauge()` — check if pending FLOW/emission tokens are rescued or if they remain in the voter/gauge contract
  2. Verify users who voted for a killed gauge can still recover their voting power (`_reset()` path)
  3. Check `distribute()` loop — does it skip dead gauges leaving tokens stuck in voter?
  4. For `h-4 pause/kill gauge` pattern: verify `FLOW` sent to voter before kill is recoverable
  5. Check `allocation` or `index` tracking — is the killed gauge's share of emissions properly zeroed or does it accumulate indefinitely?
- **Failure Mode**: FLOW/governance emission tokens permanently stuck in Voter contract; users who voted for killed gauge lose their voting weight permanently; bribe tokens for killed gauge become unclaimable
- **Common Contexts**: Velocimeter; Retro/Thena; Fenix Finance; `killGauge` / `pauseGauge` in veToken gauge systems; Velodrome-style emissions distribution

---

## GOV-014: ve_nft_transfer_voting_power_not_cleared
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `veNFT.transfer()` moves NFT but does not call `_checkpoint(tokenId, ...)` to reset voting; old owner retains vote allocation while new owner also gains votes; `tokenId` in delegate list not removed on transfer
- **Detection Heuristic**:
  1. Find `_transferFrom` in `VotingEscrow` — check if it calls `_moveTokenDelegates` or `_checkpoint` to reassign votes
  2. Verify that after transfer, `voted[tokenId]` mapping is reset so old gauge allocation is cleared
  3. Check if `poke` / `_vote` validates current NFT ownership before updating vote allocation
  4. For delegation lists: after transfer, verify old owner's delegate array no longer contains the tokenId
  5. Search for `attachToken` / `vote` patterns — can a user attach a token they no longer own to a gauge?
- **Failure Mode**: Transferred veNFT allows both old and new owner to vote with same token; attacker can vote, transfer NFT, vote again with new address, transfer back — multiply voting power or steal bribes
- **Common Contexts**: ZeroLend; Velodrome `VotingEscrow`; Alchemix veALCX; veNFT systems where NFT represents locked position

---

## GOV-015: checkpoint_binary_search_timestamp_bug
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `_findCheckpoint(tokenId, timestamp)` binary search returns wrong index when multiple checkpoints share same `timestamp`; `last_point.blk` calculated using shared memory struct modified in loop; `checkpointTotalSupply()` writes before current timestamp complete
- **Detection Heuristic**:
  1. Inspect binary search logic in checkpoint lookup — when `checkpoints[mid].timestamp == target`, does it return `mid`, `mid-1`, or `mid+1`? Test with duplicate timestamps
  2. Check `_checkpoint()` for shared memory / struct aliasing — does modifying `last_point` also modify `u_old` or `u_new` if they reference the same storage slot?
  3. Verify `checkpointTotalSupply()` — does it use `block.timestamp` as the epoch key, potentially writing before the current second has elapsed?
  4. For `VotingEscrow._checkpoint`, trace the `last_point.blk` calculation across iterations — check if block number is interpolated incorrectly due to stale values
  5. Test `getPastVotes(account, timestamp)` at timestamp boundaries — does returning wrong checkpoint cause vote inflation?
- **Failure Mode**: Historical voting power reads return wrong values; total supply checkpoint diverges from actual supply; checkpoint bug allows `last_point.blk` to be incorrect causing wrong block-based interpolation for all users; governance proposals use wrong historical weight
- **Common Contexts**: Curve-style `VotingEscrow._checkpoint`; Alchemix `checkpointTotalSupply`; `VoteEscrowDelegation._writeCheckpoint`; KittenSwap; `EscrowManager.getPastVotes()`

---

## GOV-016: reward_double_claim_or_re_entrant_claim
- **Frequency**: ~14/500 findings
- **Severity**: HIGH
- **Code Shape**: `claim()` / `distributeEx()` does not zero reward balance before external transfer; `RevenueHandler` counts unclaimed tokens as new revenue each epoch; `claimRewards()` with ERC721 reentrancy mints extra NFTs
- **Detection Heuristic**:
  1. Check reward accounting — does `claim()` set `rewards[user] = 0` before calling `token.transfer()`? Or after?
  2. Look for `distributeEx()` called twice in same block — does second call re-distribute already-distributed tokens?
  3. In `RevenueHandler`: verify that revenue accounting uses `newRevenue = currentBalance - previousBalance`, not `currentBalance` directly
  4. For ERC721 `claimRewards()`: check if the external NFT mint callback can reenter before `hasClaimed` is set
  5. Check `merge()` / `split()` operations — are rewards claimed before position is destroyed/merged?
- **Failure Mode**: Attacker claims rewards multiple times from same staking period; unclaimed revenue is double-counted as new revenue causing insolvency; reentrancy during reward claim mints unlimited governance NFTs; merging positions loses or duplicates rewards
- **Common Contexts**: Alchemix `RevenueHandler`; AI Arena `claimRewards`; ZeroLend `distributeEx`; RAAC `StabilityPool`; veALCX merge/split; `BaseGauge` staking rewards

---

## GOV-017: voting_power_arithmetic_error
- **Frequency**: ~12/500 findings
- **Severity**: HIGH
- **Code Shape**: `totalPower` set to 0 by attacker via integer manipulation; `_calculateVotingPower()` uses wrong unit scaling (UD60x18 vs raw); `veRAACToken.increase()` omits decay in bias calculation; slope not updated after nominee removal
- **Detection Heuristic**:
  1. Find `totalPower` / `totalVotingPower` update logic — check if any permissionless path can set it to 0 or a very small value
  2. For `UD60x18` or fixed-point math: verify that inputs are scaled to the same unit before arithmetic
  3. In `veRAACToken.increase()`: verify new bias = old_bias - (time_elapsed * slope) + new_bias_increment, not just old + increment
  4. After gauge/nominee removal: verify `pointsSum.slope` is decremented by the removed nominee's slope
  5. Check `unstake()` — does it reduce voting power by the same amount that was added by `stake()`? (check if power was snapshotted at stake time vs current)
- **Failure Mode**: Total voting power collapses to zero, making all proposals reach quorum instantly; voting power inflated allowing governance capture; unstake does not properly reduce voting power allowing phantom votes; wrong slope accounting corrupts all future checkpoints
- **Common Contexts**: Dexe `ERC721Power`; Pyth Governance max voter weight; `veRAACToken`; Olas `pointsSum`; FrankenDAO `Staking`; `_calculateVotingPower()` with scaling bugs

---

## GOV-018: bribe_reward_theft_via_frontrunning
- **Frequency**: ~9/500 findings
- **Severity**: HIGH
- **Code Shape**: `distribute()` / `pokeTokens()` / `addBribeFlywheel()` called in mempool visible to attacker; frontrunner calls `vote()` just before distribution claiming epoch allocation; bribe frontrunning via `addBribeFlywheel`
- **Detection Heuristic**:
  1. Check `notifyRewardAmount()` / `addBribeFlywheel()` — does it require prior voter registration, or can an attacker vote immediately before?
  2. Verify `pokeTokens()` sequence — if called publicly, can frontrunner observe and vote before bribe tokens are distributed?
  3. Look for epoch-end distribution logic — is there a snapshot of eligible voters taken before distribution, or is it computed at distribution time?
  4. Check `Bribe.withdraw()` — does it correctly update `totalVoting` or can a user withdraw bribe collateral after claiming?
  5. Verify `userGaugeProfitIndex` initialization — if unset for new users, can they claim rewards from prior periods they didn't participate in?
- **Failure Mode**: Attacker frontruns bribe distribution by voting with large balance just before epoch ends; claims disproportionate share of bribes; existing voters get less than their fair share; bribe tokens are permanently frozen or drained by attacker
- **Common Contexts**: Alchemix `Bribe.sol`; veToken gauge voting; MagicSea bribe rewarders; `userGaugeProfitIndex` in Ethereum Credit Guild; Alchemix `pokeTokens` frontrunning

---

## GOV-019: gauge_weight_accounting_broken_on_update
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `update_market()` / `GaugeController` weight calculation reads wrong epoch; `killGauge` / lower weight mid-epoch causes negative accounting in distribution; `notifyRewardAmount` overrides existing reward rate
- **Detection Heuristic**:
  1. In `update_market()` / gauge weight updates: verify the epoch index used to look up weight matches the current distribution epoch
  2. Check what happens when gauge weight is lowered below already-distributed amounts — is there an underflow guard?
  3. For `notifyRewardAmount()`: verify it does not overwrite `rewardRate` when called a second time but instead accumulates remaining + new rewards
  4. Check `GaugeController.distribute()` — does it send funds to `FeeCollector` or bypass it, causing accounting drift?
  5. Verify `lowering gauge weight` scenario: `totalDistributed` should never exceed `totalAllocated` * weight_fraction
- **Failure Mode**: Gauge receives more or less emissions than intended; lowering weight mid-epoch causes loss of funds or excess distribution; `notifyRewardAmount` called twice resets rate to zero for period remainder; FeeCollector receives no fees causing downstream accounting failure
- **Common Contexts**: Convergence; Canto `update_market()`; RAAC `BaseGauge`; Alchemix emissions distribution; `GaugeController` fee routing

---

## GOV-020: governance_role_single_point_of_failure
- **Frequency**: ~9/500 findings
- **Severity**: HIGH
- **Code Shape**: Single EOA/multisig `governance` role can upgrade, drain, pause all contracts; no timelock on `governance` role actions; `onlyOwner` functions without 2-step transfer; `setController()` allows arbitrary drain
- **Detection Heuristic**:
  1. Enumerate all `onlyGovernance` / `onlyOwner` / `onlyAdmin` functions — list what each can do (drain, pause, upgrade, mint)
  2. Check ownership transfer — is it a 1-step `transferOwnership()` (dangerous) or 2-step with `acceptOwnership()`?
  3. Verify any timelock between `governance` role actions and execution
  4. Look for `setController()` / `setVault()` / `setStrategy()` that replace core contract addresses — these allow draining with no delay
  5. Check if admin-only functions have excessive scope: e.g., `sweepInterest()` sweeps wrong amount, `withdraw()` drains entire balance
- **Failure Mode**: Compromised or malicious governance key can drain all protocol funds instantly; no community override possible; single private key controls entire protocol; admin can arbitrarily change reward rates, collateral ratios, or fee parameters post-deployment
- **Common Contexts**: Increment Finance; Reserve Protocol; InsureDAO; Shell Protocol; BadgerDAO `setGuardian`; Sharkswap owner reward rate; Bearcave admin; many DeFi protocols

---

## GOV-021: vetoken_merge_split_reward_loss
- **Frequency**: ~7/500 findings
- **Severity**: HIGH
- **Code Shape**: `merge(from, to)` burns `from` without calling `claim()` first; `split()` creates new locked position with arbitrary `amount` (no validation); `ALCX rewards` not claimed before merge burns token
- **Detection Heuristic**:
  1. In `merge()`: verify `_checkpoint(from)` and reward claim are called before burning the `from` token
  2. In `split()`: verify `split_amount <= lock.amount` and `split_amount > 0` enforced; check `locked.amount` accounting post-split
  3. Check `split` output: does the new token's `locked.amount` equal the expected fraction, or can an attacker create arbitrary amounts?
  4. Verify that merging does not skip unclaimed FLUX/ALCX/reward accrual for the `from` position
  5. For reward claiming: check that `_claimFees()` is accessible after merge, not gated by access control that breaks post-merge
- **Failure Mode**: Unclaimed ALCX/FLUX permanently frozen when `from` token is burned; attacker exploits `split()` to create locked positions with more tokens than they deposited (asset theft); claim permanently locked due to wrong access control modifier
- **Common Contexts**: Alchemix veALCX merge; KittenSwap `split`; Dynamo `_claim_fees`; Alchemix FLUX stealing via claim → merge → re-claim cycle

---

## GOV-022: delegated_vote_reduction_without_permission
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `delegator` can reduce delegatee's vote tally by re-delegating to a non-transcoder without first granting power; `delegatee` can block `delegator` from re-delegating by calling revert-inducing operations
- **Detection Heuristic**:
  1. Check delegation removal: when `A` delegates from `B` to `C`, verify B's vote count is properly decreased only for A's previously delegated amount
  2. For re-delegation: verify attacker cannot subtract another user's vote weight from a delegatee without first granting that user any power
  3. Check `delegatee` veto power: can delegatee call a function that blocks delegator's ability to transfer, re-delegate, or burn their tokens?
  4. Verify `_writeCheckpoint` on delegation change — does it update the correct (old) checkpoint index?
  5. Look for `malicious delegatee blocks redelegation` pattern: delegatee calling `attachToken` or similar to lock delegator's NFT
- **Failure Mode**: Attacker reduces a large voter's effective vote power by delegating away from them without permission; delegatee captures delegator's NFT permanently preventing redelegation or transfer; vote tallies become inconsistent
- **Common Contexts**: Livepeer; Collective; Golom `VoteEscrowDelegation`; veNFT systems with `attach` / `detach` mechanics

---

## GOV-023: proposal_execution_race_condition_parallel_ops
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `suggestNewPendingWork` and `handleJobRequest` both access shared proposal state without mutex; competing proposals in same block cause one to silently overwrite the other; `queued proposals with repeated actions` cannot execute due to Timelock hash collision
- **Detection Heuristic**:
  1. Check Timelock `queue()` — does it use `keccak256(target, value, signature, data, eta)` as key? If two identical actions are queued, second overwrites first
  2. For off-chain consensus nodes: check if proposal processing functions are called from multiple goroutines without synchronization
  3. Verify `GovernorAlpha` repeated-action proposals — can a proposal with the same action twice be executed? (Second execution reverts because first already consumed the queue entry)
  4. Look for state mutations shared between `suggestNewPendingWork` and related handlers without locks
  5. Check parallel block proposal finalization — can two valid proposals for the same slot race, leaving one in a stuck state?
- **Failure Mode**: Queued proposal with repeated actions can never execute; parallel node operations corrupt proposal state; governance deadlock where no new proposals can be activated after previous proposal execution failure
- **Common Contexts**: Consortium service proposals; `GovernorAlpha` with repeated actions; Olympus DAO `Governance.sol` stuck active proposal; Compound Alpha governance

---

## GOV-024: slashing_bypass_or_denial
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `verifyDoubleSigning()` vulnerable to gas griefing via large input array; `slashQueuedWithdrawal` `++i` placement causes loop to skip malicious strategy; `slashingWhitelist` / `slashingMap` mismatch after `removeSlasher`
- **Detection Heuristic**:
  1. In `slashQueuedWithdrawal`: verify `++i` is at top of loop body, not after `continue` — if after `continue`, some strategies are skipped
  2. Check `verifyDoubleSigning()` gas cost — can attacker pass large array to cause OOG, making honest calls always revert (griefing)?
  3. For `removeSlasher`: verify both `slashingWhitelist` and `slashingMap` are updated atomically — partial update leaves inconsistent state
  4. Check slash process bypass: can a validator front-run slash by unstaking / withdrawing before slash executes?
  5. Verify `slash()` accounting — does it correctly reduce total staked, or does it silently fail leaving stake intact?
- **Failure Mode**: Malicious operator evades slashing by griefing the gas, causing honest slash attempts to fail; slashable withdrawal contains a strategy that the loop always skips; removing a slasher leaves them functionally still able to slash (map/whitelist mismatch)
- **Common Contexts**: Ethos EVM `verifyDoubleSigning`; EigenLayer `slashQueuedWithdrawal`; Audius `slash process bypass`; Celo `removeSlasher`; staking protocol slashing queues

---

## GOV-025: vote_counting_inverted_logic
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `_voteSucceeded()` returns `true` when `againstVotes > forVotes`; `computeVote` loop exits before accumulating all votes; binary search returns wrong side of boundary
- **Detection Heuristic**:
  1. Find `_voteSucceeded()` or equivalent — verify comparison is `forVotes > againstVotes` not reversed
  2. Check `computeVote` loop bounds — does it iterate over all ballots or exit early (off-by-one)?
  3. For weighted voting: verify the summation correctly accumulates all ballots before comparing to quorum
  4. Check `argmaxBlockByStake` — does it update `highestVotingPower` variable on each iteration or does it miss updates, causing wrong block selection?
  5. Look for incorrect currency vote result: does the function return the correct index of the winning option?
- **Failure Mode**: Failed proposals execute; passed proposals are rejected; protocol runs on inverted governance outcomes; highest-stake block is never selected correctly for validation
- **Common Contexts**: Lybra Finance `_voteSucceeded`; Eco Contracts `CurrencyGovernance.computeVote`; Allora `argmaxBlockByStake`; custom Governor vote counting

---

## GOV-026: quorum_manipulation_via_supply_inflation
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `quorumVotes = totalSupply * quorumBps / 10000`; attacker mints tokens pre-proposal to inflate supply, making quorum harder to reach; extraordinary proposal steals excess AJNA above quorum threshold
- **Detection Heuristic**:
  1. Check if quorum is calculated from `totalSupply` at proposal creation time or at vote time — if at creation, large mints before proposal inflate quorum
  2. For extraordinary proposals: verify the amount claimable is capped at `treasury * (fundingBps / 10000)` and not the full excess supply
  3. Check if `proposalEligibilityQuorumBps` controlling actor can create multiple eligible proposals, diluting others' rewards
  4. Look for `quorum overflow` — can `quorumVotes` overflow uint type, causing it to wrap to 0 and letting any proposal pass?
  5. Verify extraordinary proposal: does "extraordinary amount" calculation correctly exclude already-committed funds?
- **Failure Mode**: Attacker uses inflated quorum to block all legitimate proposals indefinitely; extraordinary proposal drains treasury far beyond intended cap; quorum overflow causes any proposal to instantly reach quorum
- **Common Contexts**: Flayer `CollectionShutdown` quorum overflow; Ajna Protocol extraordinary proposal; Nouns DAO `proposalEligibilityQuorumBps`; any `quorumVotes = bps * totalSupply` pattern

---

## GOV-027: voting_cooldown_bypass
- **Frequency**: ~7/500 findings
- **Severity**: HIGH
- **Code Shape**: `veALCX` holders vote and withdraw during cooldown; `lock.end < block.timestamp` check missing before allowing vote; `multiplier` calculation uses `1 second remaining` to claim max multiplier
- **Detection Heuristic**:
  1. Find `vote()` entrypoint — verify `require(!cooldown[tokenId], "in cooldown")` or `require(block.timestamp > lastVoted[tokenId] + epoch, "...")`
  2. Check `withdraw()` / `reset()` path — can a user in cooldown still transfer tokens, withdraw, or receive rewards?
  3. For multiplier-based systems: verify the multiplier cannot be gamed by timing lock expiry to get max multiplier with minimal remaining time
  4. Check `poke()` during cooldown — does it enforce cooldown or bypass it?
  5. Verify quick buy-sell pattern: can a user acquire tokens, vote, sell tokens in same epoch, retaining vote influence?
- **Failure Mode**: Cooldown mechanism provides no actual protection; attacker votes, enters cooldown, but immediately exits and withdraws; multiplier gaming allows maximum reward extraction with minimum lock commitment
- **Common Contexts**: Alchemix veALCX; Goat Tech `multiplier`; The Computable Protocol quick buy/sell; veToken systems with lock duration multipliers

---

## GOV-028: staking_unstake_voting_power_desync
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `unstake()` calls `_removeVotes(msg.sender, ...)` but should call `_removeVotes(owner, ...)`; staking power snapshot captured at stake time but unstake uses current (different) power; `TokenStaking.recoverStake` allows instant undelegation bypassing delay
- **Detection Heuristic**:
  1. In `_unstake(msg.sender, owner, ...)`: verify vote removal is applied to `owner`, not `msg.sender`, when they differ
  2. Check voting power snapshot on stake — is the power value stored at stake time? If yes, does unstake reduce by exactly that stored value?
  3. For staking with delay (unbonding period): verify `recoverStake` / emergency withdrawal enforces the same delay as normal unstaking
  4. Check `decrease stake request` pending state — does reward calculation account for pending decrease or use full current stake?
  5. Verify `_migrateStake` — does migrated stake get counted twice (once in old system, once in new)?
- **Failure Mode**: Unstaking from wrong account leaves phantom voting power that can never be removed; voting power permanently inflated; instant undelegation via emergency path bypasses timelock governance protection; pending decrease not reflected in reward calculation causing overpayment
- **Common Contexts**: FrankenDAO `Staking._unstake`; tBTC/Keep `TokenStaking`; Audius stake decrease; Euler `_migrateStake`; any staking system with delegation separate from owner

---

## GOV-029: missing_quorum_or_timeout_enforcement
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: Elections with no quorum minimum proceed regardless of participation; candidate resolution has no timeout; `LACK OF QUORUM DEFINITION ON THE RELAYERS`; amendment vote proceeds even when quorum not reached
- **Detection Heuristic**:
  1. Find vote finalization logic — check if `require(totalVotes >= quorum, "quorum not met")` exists before executing outcome
  2. For multi-sig relay systems: verify minimum relayer threshold is defined and enforced
  3. Check amendment voting — does `voteOnMetaVesTAmendment` check quorum before applying amendment?
  4. Look for candidate election systems — is there a deadline after which unresolved candidates are automatically rejected?
  5. Verify that low participation does not default to "pass" for governance proposals
- **Failure Mode**: Low-turnout elections produce outcomes with minimal legitimacy; single relayer can process bridge messages without consensus; amendments applied without majority support; election spammed with candidates that never resolve
- **Common Contexts**: The Computable Protocol; Bridge Updates relayer; MetaLeX `voteOnMetaVesTAmendment`; Pyth Governance; Cosmos SDK groups module malicious proposal

---

## GOV-030: delegatecall_context_guard_bypass
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `onlySelf` / `onlyAtlasEnvironment` / `validControl` modifiers ineffective when called via `delegatecall`; `msg.sender` is the calling contract not the original caller; `GuardCM` bypassed via arbitrary delegatecall target
- **Detection Heuristic**:
  1. For each `onlySelf` / `onlyAtlasEnvironment` modifier: verify it checks `address(this)` in the context of the called contract, not the delegatecall initiator
  2. In proxy patterns with `delegatecall`: trace `msg.sender` — it will be the proxy, not the EOA — verify guards account for this
  3. Check `MsgValueSimulator` in zkSync — calling with non-zero `msg.value` redirects call to sender, bypassing `onlySelf`
  4. Look for `GuardCM.delegatecall()` path — can an attacker supply an arbitrary address to delegatecall from the guard, bypassing all checks?
  5. Verify that `validControl` checks work identically in both direct-call and delegatecall scenarios
- **Failure Mode**: Attacker bypasses all access control by routing through delegatecall context where guards check wrong address; `onlySelf` functions callable by any external actor through crafted delegatecall path; account abstraction paymasters drained
- **Common Contexts**: Fastlane Atlas; zkSync `MsgValueSimulator`; Olas `GuardCM`; Biconomy `executeComposableDelegateCall`; any proxy with context-dependent access control modifiers

---

## GOV-031: cross_chain_governance_message_replay_or_cancellation
- **Frequency**: ~5/500 findings
- **Severity**: HIGH
- **Code Shape**: `executeXChain()` callable by anyone to cancel cross-chain messages; lack of sender validation lets attacker execute foreign-chain governance calls; TON outbound tracker allows observer to steal funds
- **Detection Heuristic**:
  1. Find cross-chain message execution functions — verify `msg.sender` must be the authorized bridge/relayer, not any address
  2. Check cancellation: can any user cancel in-flight cross-chain governance messages, disrupting legitimate operations?
  3. For outbound trackers: verify only authorized observers can process outbound tracking data
  4. Check `lzReceive` / `ccipReceive` — does it verify the source chain and source address before executing governance actions?
  5. Verify nonce / replay protection on cross-chain governance messages
- **Failure Mode**: Attacker cancels legitimate cross-chain governance transactions causing fund loss on source chain (deducted but not applied on destination); malicious observer redirects outbound tracker to steal bridge funds; cross-chain governance messages executed by wrong parties
- **Common Contexts**: Derby; ZetaChain; Tapioca DAO cross-chain options; LayerZero governance; ZetaChain outbound tracker

---

## GOV-032: validator_set_consensus_manipulation
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `minority validators participate in consensus`; `VerifyIncomingBlock returns incorrect error status`; `ProcessProposal accepts incorrect proposals`; validator deposits not verified against deposit contract; missing `GetSigners` registration
- **Detection Heuristic**:
  1. Check validator set quorum calculation — is it based on `total_stake` or `validator_count`? Minority-by-stake but majority-by-count can pass blocks
  2. For `ProcessProposal` / `VerifyIncomingBlock`: verify all fields of the execution payload are validated (timestamp, gas limit, block number, parent hash)
  3. Check `validateNonGenesisDeposits` — does it check deposit proof against the actual deposit contract tree root?
  4. Verify `GetSigners()` registration for all message types in Cosmos SDK modules — unregistered messages may cause signature bypass
  5. For vote extensions: check `VerifyVoteExtensionHandler` is always called, not skipped under any code path
- **Failure Mode**: Invalid blocks pass validation and are finalized; chain halts due to unhandled malicious proposal; validator deposit forgery allows fake validators; consensus vote extensions skipped allowing arbitrary block data to be finalized
- **Common Contexts**: Berachain `ProcessProposal`; Elixir Protocol minority validators; SEDA Protocol malicious proposal chain halt; Fusaka proposer calculation; Allora `argmaxBlockByStake`

---

## GOV-033: dos_unbounded_loop_in_governance
- **Frequency**: ~8/500 findings
- **Severity**: HIGH
- **Code Shape**: `finalize()` iterates over unbounded `pendingRemovals` array; `getTotalVotingPower()` loops over all tokens; `VotingEscrow MAX_DELEGATES` array unbounded on some EVM chains; undelegation unbounded loop with unmetered token transfers
- **Detection Heuristic**:
  1. Find loops in governance functions (vote, finalize, distribute) — check if array length is bounded or can grow without limit
  2. For `_vote()` → `getTotalVotingPower()` chain: verify `getTotalVotingPower` does not iterate over all token holders
  3. Check `MAX_DELEGATES` constant — is it enforced? Can it be too large for target EVM chain's block gas limit?
  4. For Cosmos SDK `EndBlocker`: verify unbonding queue processing has gas metering per transfer, not just total loop count
  5. Check `RewardDistributor` — can attacker create excessive `userPoint` checkpoints to DoS claim operations?
- **Failure Mode**: Governance finalization permanently DoS'd when array grows large; chain halt from unmetered operations in EndBlocker; users unable to vote as `getTotalVotingPower` always OOG; RewardDistributor claims permanently revert for targeted users
- **Common Contexts**: BMX Deli Swap `Voter::finalize()`; Satin Exchange `_vote()`; MilkyWay `end_blocker`; Velocimeter `MAX_DELEGATES`; Alchemix `RewardDistributor` excess userPoints

---

## GOV-034: storage_slot_collision_in_upgradeable_proxy
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `_implementation` and `_owner` slots can be overwritten by inherited contract's state variables; `getStorage() NAMESPACE` pattern not used; `ProxyStorage` gap miscalculation; EIP-1967 slots not used
- **Detection Heuristic**:
  1. For each upgradeable contract, map storage layout of implementation vs proxy — check for any overlap in slot indices
  2. Verify implementation uses `EIP-1967` slots (`bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`) or equivalent namespace
  3. Check inherited contracts for state variable declarations that could land on reserved proxy slots
  4. For `Swapper` / `LI.FI` patterns: verify `getStorage()` with NAMESPACE is used instead of direct global variable storage
  5. Look for storage gaps (`uint256[50] __gap`) — verify gap size correctly accounts for all parent contract variables
- **Failure Mode**: Implementation contract's state variables overwrite proxy's `_implementation` pointer or `_owner`, bricking the proxy or transferring ownership to attacker; upgrade path permanently broken
- **Common Contexts**: LI.FI `Swapper`; Brink `ProxyStorage`; any OpenZeppelin `Upgradeable` inheritor with custom parent contracts; diamond proxy patterns

---

## GOV-035: insufficient_proposal_bond_or_challenge_validation
- **Frequency**: ~4/500 findings
- **Severity**: HIGH
- **Code Shape**: `computeRootFromWitness()` allows arbitrary path traversal; challenge mechanism can be manipulated to steal proposer's bond; upgraded contracts lock in-flight proposal bonds; `LPP metadata alterable after challenge period`
- **Detection Heuristic**:
  1. In dispute/challenge contracts: verify `computeRootFromWitness` / Merkle proof verification rejects crafted paths (check for path length validation, leaf node prefix)
  2. Check bond recovery after protocol upgrade — are bonds from pre-upgrade proposals still recoverable?
  3. Verify challenge period enforcement on `LPP metadata` — can metadata be altered after the dispute window closes?
  4. For proposals: check if bond is locked in a contract that might be upgraded/replaced, making bond irrecoverable
  5. Verify `dispute_bond` amount is enforced and disputer receives bond back on valid dispute
- **Failure Mode**: Attacker crafts false challenge proof via path traversal, stealing proposer's bond; legitimate proposal bonds permanently locked after protocol upgrade; incorrect metadata proven as correct after challenge period expires
- **Common Contexts**: Rocketpool challenge mechanism; Optimism `LPP metadata`; proposal bond systems with Merkle proof verification; any dispute game with challenger economics

---

## GOV-036: access_control_missing_on_critical_governance_functions
- **Frequency**: ~15/500 findings
- **Severity**: HIGH
- **Code Shape**: `assertGovernanceApproved()` no access control; `didTransferShares()` no role modifier; `proposeRemoveTransmitters()` missing sender check; `CLGaugeFactory` allows unauthorized pool creation; `sendCurrentOperatorsKeys()` permissionless
- **Detection Heuristic**:
  1. Grep for all `external` / `public` functions — for each, verify it has an appropriate modifier (`onlyGovernance`, `onlyOwner`, `onlyRole(...)`)
  2. Focus on functions that modify critical state: gauge creation, operator registration, key rotation, reward distribution triggers
  3. Check `assertGovernanceApproved` — if it can be called by anyone to lock funds, it needs access control
  4. Verify factory contracts — can anyone call `createGauge` / `createPool` without proper authorization?
  5. For `proposeRemoveTransmitters`: check if `MSCProposeHelper` validates `msg.sender` is authorized committee member
- **Failure Mode**: Anyone can trigger governance-gated operations (approve funds, create gauges, remove operators, rotate keys) without holding any governance power; fund lockup, unauthorized state changes, or theft of rewards
- **Common Contexts**: Behodler; Forta Delegated Staking; Photon Messaging; KittenSwap `CLGaugeFactory`; Tanssi `sendCurrentOperatorsKeys`; MetaLeX grant implants; Infrared `KEEPER_ROLE`

---

## GOV-037: two_step_ownership_transfer_missing
- **Frequency**: ~5/500 findings
- **Severity**: HIGH (commonly MEDIUM in isolation)
- **Code Shape**: `transferOwnership(newOwner)` immediately sets `owner = newOwner`; no `pendingOwner` / `acceptOwnership()` pattern; roles manager update logic broken (can never update); guardian set incorrectly
- **Detection Heuristic**:
  1. Find `transferOwnership()` — check if it uses two-step pattern (set `pendingOwner` → require `pendingOwner.acceptOwnership()`)
  2. Check `setGuardian()` / `setRolesManager()` — verify the new address is correctly written to storage (common bug: reads wrong variable, always sets to zero)
  3. For `Ownable` library version: verify the imported version matches the expected interface (wrong version may make all `onlyOwner` functions no-ops)
  4. Look for `rolesManager` update path — if the update requires the current `rolesManager` to call it, and they are compromised, can it ever be updated?
  5. Verify `setGuardian` writes to `_guardian` not to a local variable or wrong slot
- **Failure Mode**: Typo in `transferOwnership` → ownership transferred to wrong address → permanently lost; guardian set to zero (using wrong variable) locks all guardian-protected functions; roles manager can never be rotated if compromised
- **Common Contexts**: Beanstalk `OwnershipFacet`; BadgerDAO `setGuardian`; Atlendis Labs `Managed.rolesManager`; Covalent `Ownable` wrong version; any single-step ownership transfer

---

## GOV-038: reward_calculation_uses_current_not_staked_balance
- **Frequency**: ~9/500 findings
- **Severity**: HIGH
- **Code Shape**: `earned()` uses `veBalance[user]` (current ve balance) instead of `staked[user]` (amount actually staked in gauge); `rewardPerTokenStored` accrued before user stakes but new staker claims it; decay not applied in reward calculation
- **Detection Heuristic**:
  1. In `BaseGauge.earned()`: verify it uses staked balance (`_balances[account]`), not ve token balance (`veToken.balanceOf(account)`)
  2. Check `rewardPerTokenStored` initialization — is it set to 0 for new users, or do they inherit the current global value (allowing claiming past rewards)?
  3. Verify `notifyRewardAmount()` correctly computes remaining rewards when called multiple times: `newRate = (remaining + newAmount) / period`
  4. For `veRAACToken.increase()`: verify bias update applies current slope decay before adding new bias
  5. Check `_totalCheckpoints` — is total voting power updated on every mint/burn, or only on explicit snapshot calls?
- **Failure Mode**: Future stakers claim rewards accumulated before they joined; users claim rewards without staking (ve balance substituted for stake); reward rate overwritten to zero by second call; total voting power always zero allowing any proposal to pass
- **Common Contexts**: RAAC `BaseGauge`; Ethereum Credit Guild `userGaugeProfitIndex`; `veRAACToken.increase()`; Anvil Protocol `_totalCheckpoints`; any gauge with `rewardPerToken` accumulation

---

> ## Summary Table
>
> | Pattern ID | Name | ~Frequency | Severity |
> |-----------|------|-----------|---------|
> | GOV-001 | flash_loan_vote_manipulation | ~12/500 | HIGH |
> | GOV-002 | vote_delegation_double_counting | ~18/500 | HIGH |
> | GOV-003 | expired_lock_voting_power_not_cleared | ~9/500 | HIGH |
> | GOV-004 | poke_function_unchecked_flux_minting | ~10/500 | HIGH |
> | GOV-005 | proposal_cancellation_without_access_control | ~8/500 | HIGH |
> | GOV-006 | voting_power_snapshot_missing_or_stale | ~11/500 | HIGH |
> | GOV-007 | delegation_reentrancy_double_delegation | ~5/500 | HIGH |
> | GOV-008 | unrestricted_proposal_creation | ~7/500 | HIGH |
> | GOV-009 | delegatecall_to_unverified_address | ~10/500 | HIGH |
> | GOV-010 | uninitialized_implementation_contract_selfdestructable | ~6/500 | HIGH |
> | GOV-011 | initialization_frontrunning | ~6/500 | HIGH |
> | GOV-012 | timelock_bypass_or_missing | ~7/500 | HIGH |
> | GOV-013 | gauge_kill_pause_token_stuck | ~8/500 | HIGH |
> | GOV-014 | ve_nft_transfer_voting_power_not_cleared | ~8/500 | HIGH |
> | GOV-015 | checkpoint_binary_search_timestamp_bug | ~5/500 | HIGH |
> | GOV-016 | reward_double_claim_or_re_entrant_claim | ~14/500 | HIGH |
> | GOV-017 | voting_power_arithmetic_error | ~12/500 | HIGH |
> | GOV-018 | bribe_reward_theft_via_frontrunning | ~9/500 | HIGH |
> | GOV-019 | gauge_weight_accounting_broken_on_update | ~5/500 | HIGH |
> | GOV-020 | governance_role_single_point_of_failure | ~9/500 | HIGH |
> | GOV-021 | vetoken_merge_split_reward_loss | ~7/500 | HIGH |
> | GOV-022 | delegated_vote_reduction_without_permission | ~4/500 | HIGH |
> | GOV-023 | proposal_execution_race_condition_parallel_ops | ~4/500 | HIGH |
> | GOV-024 | slashing_bypass_or_denial | ~5/500 | HIGH |
> | GOV-025 | vote_counting_inverted_logic | ~4/500 | HIGH |
> | GOV-026 | quorum_manipulation_via_supply_inflation | ~5/500 | HIGH |
> | GOV-027 | voting_cooldown_bypass | ~7/500 | HIGH |
> | GOV-028 | staking_unstake_voting_power_desync | ~5/500 | HIGH |
> | GOV-029 | missing_quorum_or_timeout_enforcement | ~5/500 | HIGH |
> | GOV-030 | delegatecall_context_guard_bypass | ~4/500 | HIGH |
> | GOV-031 | cross_chain_governance_message_replay_or_cancellation | ~5/500 | HIGH |
> | GOV-032 | validator_set_consensus_manipulation | ~8/500 | HIGH |
> | GOV-033 | dos_unbounded_loop_in_governance | ~8/500 | HIGH |
> | GOV-034 | storage_slot_collision_in_upgradeable_proxy | ~4/500 | HIGH |
> | GOV-035 | insufficient_proposal_bond_or_challenge_validation | ~4/500 | HIGH |
> | GOV-036 | access_control_missing_on_critical_governance_functions | ~15/500 | HIGH |
> | GOV-037 | two_step_ownership_transfer_missing | ~5/500 | HIGH |
> | GOV-038 | reward_calculation_uses_current_not_staked_balance | ~9/500 | HIGH |
