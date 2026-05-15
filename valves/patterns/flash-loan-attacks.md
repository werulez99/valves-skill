# Flash Loan Attack Patterns
> Extracted from 664 findings (500 sampled)
> Pattern count: 32

---

## FLASH-001: spot_price_oracle_manipulation
- **Frequency**: ~62/500
- **Severity**: HIGH
- **Code Shape**: `pool.slot0()`, `getAmountsOut()`, `getReserves()`, `getPricePerFullShare()`, `getVirtualPrice()` used directly for pricing decisions without TWAP or multi-block smoothing
- **Detection Heuristic**:
  1. Search for `slot0`, `sqrtPriceX96`, `getAmountsOut`, `getReserves`, `getPrice`, `latestAnswer` calls
  2. Trace the returned value — is it used in a pricing, collateral valuation, or mint/burn calculation in the same transaction?
  3. Check if there is any TWAP (`observe`, `consult`), multi-block check, or secondary oracle cross-reference before use
  4. If the value flows directly from spot to a financial decision with no smoothing: CONFIRMED
- **Failure Mode**: Attacker flash-loans large liquidity, swaps to shift pool spot price, then calls the vulnerable function at the artificial price, then reverses the swap — extracting value through arbitrage, under-collateralized borrowing, or inflated LP token pricing
- **Common Contexts**: Uniswap V2/V3 pool-based oracles (Spartan Protocol, Vader Protocol, Marginswap, Malt Protocol, Blueberry, Zivoe, Cover Protocol, Frax, Initia, Good Entry, Panoptic, Astaria, Geodefi); Curve virtual price (Brahma Fi, Sandclock); Compound exchange rate (Notional V3)

---

## FLASH-002: reward_distribution_jit_deposit
- **Frequency**: ~38/500
- **Severity**: HIGH
- **Code Shape**: `deposit()` / `stake()` followed by `claimRewards()` / `harvest()` in the same block; reward calculation based on current snapshot balance rather than time-weighted balance; no lock or minimum stake duration enforced
- **Detection Heuristic**:
  1. Identify reward distribution functions (`distributeRewards`, `harvest`, `getReward`, `claimReward`)
  2. Check whether rewards are allocated proportionally to current balance at distribution time
  3. Check for minimum stake time, block lock, or snapshot mechanism
  4. If rewards are claimable in the same block as deposit with no cooldown: CONFIRMED
  5. Check if `flashLoan` / `flashMint` entry points allow token acquisition without commitment
- **Failure Mode**: Attacker flash-borrows governance/staking tokens, stakes, waits for reward trigger (or triggers it themselves), claims disproportionate share of rewards, unstakes, repays loan — all in one transaction. Legitimate stakers receive reduced rewards.
- **Common Contexts**: LP staking (NFTX NFTXLPStaking, Rubicon BathBuddy, Sperax Farms, Derby, Telcoin, Rush Trading); yield farming (GrowthDeFi WHEAT, Merit Circle, Origin Dollar); protocol fee distribution (Spartan feePool, QuantAMM, TermMax); coupon/bond rewards (Plaza Finance); bribe rewards (Maia DAO, Debita Finance)

---

## FLASH-003: governance_voting_power_inflation
- **Frequency**: ~22/500
- **Severity**: HIGH
- **Code Shape**: `castVote()` uses `balanceOf(msg.sender)` at vote time; no snapshot at proposal creation; `veToken.balanceOfNFT()` reads current balance; voting power derived from transferable/borrowable token
- **Detection Heuristic**:
  1. Find voting power calculation — does it call `balanceOf` or `balanceOfNFT` at the moment of voting?
  2. Check if governance token is transferable or borrowable (flash-loanable)
  3. Confirm there is no `getPriorVotes`, `getPastVotes`, or checkpoint-at-proposal-creation mechanism
  4. Check for EarlyExecution mode or any path where votes in a single block can determine outcome
  5. If voting power = current balance and token is loanable: CONFIRMED
- **Failure Mode**: Attacker borrows/flash-mints governance tokens, casts a decisive vote, returns tokens — all in one block. Allows minority holder to pass/block any proposal with zero capital commitment.
- **Common Contexts**: DAO voting (Vader Protocol DAO, FIAT DAO, Dexe, Aragon DAO Gov Plugin, Alchemix veALCX, yAxis YAxisVotePower, FairSide fShareRatio, Derby allocations); crowdfund governance (PartyDAO ETH crowdfund); ve-token systems (Velodrome, KittenSwap VotingEscrow)

---

## FLASH-004: flash_loan_callback_missing_initiator_check
- **Frequency**: ~28/500
- **Severity**: HIGH
- **Code Shape**: `executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address initiator, bytes calldata params)` or `receiveFlashLoan(...)` or `onFlashLoan(...)` with no check that `initiator == address(this)` or `msg.sender == trustedLender`
- **Detection Heuristic**:
  1. Find all flash loan callback functions (`executeOperation`, `receiveFlashLoan`, `onFlashLoan`, `flashCallback`, `uniswapV3FlashCallback`, `pancakeCall`)
  2. Check if `initiator` parameter is validated against `address(this)` or a stored trusted address
  3. Check if `msg.sender` is validated against the known flash loan provider address
  4. If either check is missing: CONFIRMED
  5. Assess what state-changing operations the callback can perform (open trade, close trade, transfer funds)
- **Failure Mode**: Any external caller can trigger the callback with arbitrary parameters, opening/closing positions on behalf of the vault/contract, stealing funds by directing the protocol to execute an operation it should not.
- **Common Contexts**: Aave executeOperation integrations (DODO Margin Trading MarginTrading.sol, Mimo MIMOEmptyVault, Stakewise STAKE-6, Bold Balancer flashloan zapper, Fuji FlasherFTM CREAM auth bypass, Wido WidoCollateralSwap, Aave Protocol V2 griefing)

---

## FLASH-005: lp_token_price_manipulation_via_reserve_imbalance
- **Frequency**: ~18/500
- **Severity**: HIGH
- **Code Shape**: LP token price = `totalAssets / totalSupply` or `reserve0 * reserve1` or Curve `get_virtual_price()` evaluated at spot; used in collateral valuation, liquidation checks, or bonding curve pricing
- **Detection Heuristic**:
  1. Find LP token pricing functions in oracles or collateral calculators
  2. Check whether price uses current pool balances/reserves directly
  3. For Curve: check if `calc_withdraw_one_coin` or `get_virtual_price` is used for pricing (Curve virtual price IS resistant to same-block manipulation, but only via read-only reentrancy if callback exists)
  4. For Uniswap V2/V3: any direct `getReserves`/`slot0` for LP pricing is manipulable
  5. Confirm whether pricing is used to determine mint amounts, collateral ratios, or liquidation thresholds
- **Failure Mode**: Flash loan shifts pool reserves → LP token price spikes or crashes → attacker borrows against inflated LP collateral OR triggers wrongful liquidation / forces system into IFFY/DISABLED state.
- **Common Contexts**: Collateral oracles (Reserve CurveVolatileCollateral, Contracts V1 BondSteerOracle, Sense, Behodler LP pricing, Notional liquidity token, DYAD domain pricing, Abracadabra, ParaSpace)

---

## FLASH-006: share_inflation_first_depositor
- **Frequency**: ~14/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: ERC4626 or share-based vault where `totalShares == 0` and `totalAssets` can be inflated via direct token transfer; `shares = amount * totalShares / totalAssets` rounds down to zero for small deposits after inflation
- **Detection Heuristic**:
  1. Find vault deposit function — does it use `totalAssets()` in share calculation?
  2. Check if `totalAssets()` includes raw token balance (susceptible to donation)
  3. Verify whether the contract has virtual offset mitigation (e.g., initial dead shares minted to address(0))
  4. Check if first depositor can be front-run before any protective deposit
  5. If shares = `deposit * totalShares / totalAssets` with no virtual offset: CONFIRMED
- **Failure Mode**: First depositor mints 1 share, donates large amount to inflate `totalAssets`, subsequent depositors receive 0 shares for small deposits, attacker redeems inflated share for all assets.
- **Common Contexts**: ERC4626 vaults (BakerFi, MetaStreet Labs, DODO GSP, Spectra deflation attack via flash loan, Blueberry share price crash via MEV)

---

## FLASH-007: staking_token_same_block_entry_exit
- **Frequency**: ~15/500
- **Severity**: HIGH
- **Code Shape**: `stake()` → `claim()` → `unstake()` in same transaction; block-number check present but bypassable via `block.number` == `block.number` (same block); or `_shortCircuitRewards` flag manipulated by `flashMint`
- **Detection Heuristic**:
  1. Find staking functions — do they record `block.number` or `block.timestamp` at stake time?
  2. Check if rewards are claimable immediately after staking (same block)
  3. Look for `flashMint` or `flashLoan` functions on the staking token itself that set a flag disabling reward accrual
  4. Check if `checkLastBlockAction` modifier is bypassable (e.g., applies only to one of stake/unstake but not the other)
  5. Assess cost of flash-stake attack vs reward captured
- **Failure Mode**: Attacker flash-borrows staking token (or flash-mints it), stakes it for one block to appear as a large stakeholder, claims artificially inflated rewards, exits — zero capital risk.
- **Common Contexts**: Telcoin TEL staking, Peapods flashMint shortCircuitRewards, NFTX inventory staking, Radiant eligibility manipulation, Rush Trading RushERC20 launch fee bypass, Rocketpool reward distribution

---

## FLASH-008: cooldown_or_block_lock_bypass
- **Frequency**: ~16/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `modifier checkLastBlockAction` on deposit/withdraw but not on all entry points; `block.number == lastBlock` check bypassable via intermediate contract; `transferFrom` block lock on ERC20 but transferable via alternate path; self-liquidation bypass of flash-proof
- **Detection Heuristic**:
  1. Find all anti-flash-loan guards (block number locks, `flashProof` modifiers, same-block withdrawal restrictions)
  2. Enumerate ALL functions that can move funds or claim rewards — does every one have the guard?
  3. Check for indirect entry points: self-liquidation, `quitLock`, secondary transfer methods, delegate calls
  4. Verify the guard uses `block.number` consistently, not `block.timestamp` (which can match across transactions)
  5. If any path bypasses the guard: CONFIRMED
- **Failure Mode**: Protocol believes it is protected against same-block manipulation, but attacker routes through an unguarded function to perform the same economic attack the guard was designed to prevent.
- **Common Contexts**: DYAD self-liquidation bypass (H-10), Vader Protocol flashProof bypass (M-04), BadgerDAO SettV3 transferFrom bypass (M-01), Gearbox debt increase + close same block, Notional cooldown/redeem bypass, Radiant checkLastBlockAction bypass, Boot Finance NFT flashloan bypass

---

## FLASH-009: flash_loan_fee_accounting_error
- **Frequency**: ~24/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Flash loan repayment check uses `balance >= borrowed` instead of `balance >= borrowed + fee`; fee calculation rounds down to zero; fee deducted from principal before transfer; `receiveFlashLoan` checks `amount` instead of `amount + fee`
- **Detection Heuristic**:
  1. Find the balance check in the flash loan repayment path
  2. Verify: is the check `balance >= principal + fee` or just `balance >= principal`?
  3. Confirm the fee is calculated AFTER the callback returns, not before
  4. Check for off-by-one: `flashFee()` rounds down — does repayment check use `>=` or `>`?
  5. For `receiveFlashLoan(tokens, amounts, feeAmounts, userData)` — does the callback validate `amounts[i] + feeAmounts[i]` is available to repay?
- **Failure Mode**: Attacker executes a "flash loan" and repays only principal without fee (fee check missing), or the protocol itself cannot complete its own flash loan because it checks the wrong balance (DoS), or the fee is incorrectly computed (protocol loses fee revenue or flash loan always reverts).
- **Common Contexts**: Astrolab wrong balance check (H-02, H-03), Lindy Labs receiveFlashLoan fee (H), Streaming Protocol excess calculation (H-01), LoopFi onCreditFlashLoan fee handling (M-01, M-17), BakerFi harvest flash fee (M-03), Napier receiveFlashLoan (M-6), RamsesV3 flash fee calculation (M-02), Caviar flash fee wrong address (M-16), Iron Bank USDT fee (M)

---

## FLASH-010: reentrancy_in_flash_loan_callback
- **Frequency**: ~20/500
- **Severity**: HIGH
- **Code Shape**: Flash loan callback (`executeOperation`, `flashCallback`, `onFlashLoan`) invokes external token transfer or call before updating internal state; no `nonReentrant` on collateral withdrawal / liquidation / staking functions called from callback
- **Detection Heuristic**:
  1. Map all functions called from or during a flash loan callback
  2. Check if any of those functions: transfer tokens, update balances, or check health factor
  3. Verify each such function has `nonReentrant` or follows CEI (checks-effects-interactions) pattern
  4. Look for ERC721/ERC1155 hooks (`onERC721Received`, `safeTransferFrom`) within the flash loan path
  5. If state is read-then-modified with an external call in between: CONFIRMED
- **Failure Mode**: Attacker re-enters the protocol during the flash loan callback to read stale state (e.g., pre-withdrawal balance), draining more than entitled.
- **Common Contexts**: Arcadia flashAction reentrancy (H-2), Backed Protocol removeCollateral + liquidation reentrancy (H-02), Sushi stakeToken reentrancy (H-11), reNFT ERC1155 reentrancy (H-03), Phi Creds reentrancy + cooldown bypass (H-06), CNumaToken leverageStrategy re-entry (H-1), Gamma re-entrancy + flash loan price check (H)

---

## FLASH-011: amm_spot_price_used_for_minting_or_burning
- **Frequency**: ~16/500
- **Severity**: HIGH
- **Code Shape**: `Pool.mint(synth)` or `Pool.burn(synth)` calculates amount based on `getPoolShareWeight`, `baseValueLP`, `baseValueSynth` derived from current pool balances; `token_amount` and `sparta_amount` read at transaction time
- **Detection Heuristic**:
  1. Find synth mint/burn functions
  2. Trace the pricing formula — does it read current pool balances for collateral valuation?
  3. Check if `baseValueLP` / `baseValueSynth` are computed from spot reserves
  4. Verify there is no TWAP or committed liquidity snapshot for collateral calculation
  5. If mint amount = `f(current_reserves)` with no protection: CONFIRMED
- **Failure Mode**: Attacker flash-loans into AMM pool, shifts `baseValueLP >> baseValueSynth`, calls `realise()` to claim IL compensation or mints excess synth at artificial price, repays loan — extracting protocol reserves.
- **Common Contexts**: Spartan Protocol (H-05 synth realise, H-09 arbitrary synth mint, H-11 AMM model misuse, H-13 getPoolShareWeight, H-10 calculateLoss), Vader Protocol synth over-mint (H-23)

---

## FLASH-012: interest_rate_manipulation_via_utilization
- **Frequency**: ~12/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Interest rate = `f(totalBorrows / totalSupply)` recalculated in same block; `BasePiReserveRateStrategy` uses current balances; stable borrow rate calculated from utilization at borrow time; `accrueRate()` and `getTRate()` computed differently
- **Detection Heuristic**:
  1. Find interest rate model — does it call `totalBorrows()` and `totalSupply()` for live calculation?
  2. Check if a large single-block borrow can spike utilization to 100%
  3. Verify if the spiked rate persists after the flash borrower repays (some models update monotonically)
  4. Check Aave stable rate: can an attacker manipulate victim's stable rate upward by temporarily spiking utilization?
  5. For Pi-model: does it use instantaneous utilization without EMA smoothing?
- **Failure Mode**: Attacker borrows large amount → utilization spikes → interest rate spikes → attacker repays (rate does not drop for victim's stable loan) → victim is permanently stuck with artificially high rate. Or: attacker earns interest-free loan by borrowing and repaying in same block before rate accrues.
- **Common Contexts**: Aave stable borrow rate (Folks Finance, Revert Lend M-04 interest-free loans), Pi interest rate (Astera, Cod3x lend), Based Loans reward rate manipulation (M-01), Union Finance exchangeRateStored front-running (M-5)

---

## FLASH-013: twap_duration_too_short_for_manipulation_resistance
- **Frequency**: ~10/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Uniswap V3 TWAP with `secondsAgo < 1800` (30 minutes); Tellor oracle with low update frequency (hours); `previousPrices` never updated (stale TWAP accumulator); TWAP window manipulable within single block on low-liquidity pools
- **Detection Heuristic**:
  1. Find TWAP observation call: `pool.observe([secondsAgo, 0])` — read `secondsAgo`
  2. If `secondsAgo < 1800` (30 min) on low-liquidity pool: HIGH RISK
  3. Check if TWAP accumulator (`previousPrices`, `cumulativePriceLast`) is updated every time price is read
  4. For Tellor: check `getDataBefore` timestamp vs current block — can attacker stale the feed for hours at low cost?
  5. Check Maverick / Balancer oracles for similar short-window vulnerabilities
- **Failure Mode**: On low-liquidity pools, short TWAP windows can be bent over multiple blocks by a determined attacker with moderate capital. Stale accumulator means TWAP never advances, locking the protocol into an old price.
- **Common Contexts**: Tapioca TapOracle <30 min TWAP (M-10), Tokemak Maverick oracle (H-15), Blueberry CurveOracle (H-4), Ethos Reserve Tellor low frequency (M-01), Vader Protocol previousPrices never updated (H-10/H-179), Panoptic oracle manipulation (M-11)

---

## FLASH-014: sandwich_attack_on_permissionless_reward_distribution
- **Frequency**: ~18/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Permissionless `distribute()`, `harvest()`, `melt()`, `distributeMochi()`, `poke()` functions that swap tokens or distribute rewards; no caller restriction; no slippage parameter; no minimum output check
- **Detection Heuristic**:
  1. Find permissionless state-changing distribution functions
  2. Check if they perform swaps with `amountOutMin = 0` or no slippage protection
  3. Verify if the timing of calling the function (before/after a large trade) changes the distribution outcome
  4. Check for MEV extraction via front-running `distribute()` → depositing → calling distribute → withdrawing
  5. If any public swap within distribution path lacks slippage control: CONFIRMED
- **Failure Mode**: MEV bot front-runs `distribute()` call: deposits into pool, triggers distribution (which swaps/donates at favorable price), withdraws with extra value — extracting yield meant for long-term LPs.
- **Common Contexts**: Spartan feePool (H-12), Archi Finance MEV (H), stUSDC poke MEV (H-05), Malt Protocol profit theft (M-16), Reserve Furnace melt sandwich (M-15), Yield Ninja harvest sandwich (M-01), Connext reimburseLiquidityFees (M-20), Alchemix RevenueHandler (H), QuantAMM donations sandwich

---

## FLASH-015: flash_loan_used_to_bypass_auction_health_check
- **Frequency**: ~8/500
- **Severity**: HIGH
- **Code Shape**: Auction recovery / health check evaluates `collateral / debt` at transaction time; no time-lock between check and conclusion; health check can be temporarily satisfied by borrowing collateral
- **Detection Heuristic**:
  1. Find liquidation / auction recovery functions with an on-chain health check
  2. Check if the health check reads current balances that can be temporarily inflated
  3. Verify if time elapses between health check pass and auction benefit claim
  4. Look for `checkUnstakeParam`, `isHealthy`, `getSolvencyRatio` called before liquidation eligibility
  5. If health = `f(current_collateral)` with no commitment period: CONFIRMED
- **Failure Mode**: Attacker flash-loans collateral → temporarily appears healthy → passes auction recovery check → withdraws collateral → repays loan → avoids rightful liquidation. Or: uses flash loan to pass health check in order to claim auction discounts on otherwise ineligible collateral.
- **Common Contexts**: ParaSpace auction recovery H-07, DYAD frontrun withdrawal + auction H-04, Carapace leverage factor H-7, Flooring Marketplace liquidation design (H-28), Opus shrine recovery mode weaponization (H-04)

---

## FLASH-016: missing_slippage_protection_in_leverage_operations
- **Frequency**: ~20/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `increaseLever()` / `decreaseLever()` / `leverageStrategy()` calls swap without `amountOutMin` parameter or with `amountOutMin = 0`; `closePositionFarm` removes liquidity without slippage bounds; `removeCollateral` swaps without price limit
- **Detection Heuristic**:
  1. Find all leverage entry/exit functions
  2. Trace swap calls within them — what is `amountOutMin` / `sqrtPriceLimitX96`?
  3. Check if user can supply slippage parameter or if it is hardcoded to 0
  4. Verify if the swap is on a low-liquidity pool (higher manipulation surface)
  5. For `slot0`-based slippage: is `sqrtPriceLimitX96` derived from `pool.slot0()`? (manipulable)
- **Failure Mode**: MEV bot sandwiches the leverage transaction — front-runs with a large swap to shift price, the leverage operation executes at unfavorable rate, bot back-runs for profit. User suffers slippage loss equivalent to the sandwich profit.
- **Common Contexts**: Blueberry ConvexSpell closePositionFarm (H-5), Primex slippage vulnerability (H), JOJO Exchange JOJOFlashLoan no slippage (M-9), Stakewise STAKE-7 deposit slippage (H), Maia DAO slot0 sqrtPriceLimitX96 (H-02), Ion Protocol flashswap no deadline (M), Numa leverageStrategy (M-11)

---

## FLASH-017: flash_loan_functionality_broken_by_implementation_bug
- **Frequency**: ~18/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `flashLoan()` calls `transferFrom(msg.sender, ...)` instead of `transfer(receiver, ...)`; `d_supply` updated incorrectly after execution; `maxFlashLoan()` returns wrong amount when combined with capped token; flash loan disabled by anyone via manipulation
- **Detection Heuristic**:
  1. Read the flash loan implementation end-to-end
  2. Verify: does the protocol transfer funds TO the receiver before the callback, not FROM?
  3. Check repayment pull: does it pull from `receiver` or from `msg.sender`?
  4. Verify `d_supply` / internal accounting is updated only AFTER repayment confirmed
  5. Check if `flashLoansPaused` flag is respected in `flashFee()` and `maxFlashLoan()`
  6. Verify `availableLiquidity` in `flashLoan()` does not double-count already-loaned amount
- **Failure Mode**: Flash loan function is completely non-operational (DoS), or the protocol can be permanently disabled by anyone by triggering a specific state through the broken accounting.
- **Common Contexts**: Astrolab transferFrom issue (H-03), Blend d_supply incorrect update (H-01), f(x) v2 flashLoan blocked (H), Aave disable flash loan (H02), Aave availableLiquidity miscalculation (L), EIP-3156 non-compliance on paused flag (BadgerDAO M)

---

## FLASH-018: erc3156_standard_noncompliance
- **Frequency**: ~8/500
- **Severity**: MEDIUM
- **Code Shape**: `flashFee()` does not check `flashLoansPaused`; `maxFlashLoan()` does not account for PSP22Capped limit; `flashLoan` does not pass `initiator` to recipient; fee taken from `msg.sender` instead of `receiver`; fee not distributed to factory
- **Detection Heuristic**:
  1. Verify `flashFee(token, amount)` returns 0 when flash loans are paused (per ERC-3156 spec)
  2. Verify `maxFlashLoan(token)` returns 0 when paused and respects any supply cap
  3. Check that callback receives `initiator` as the actual flash loan caller (not zero address)
  4. Check that fee is pulled from the callback recipient, not from `msg.sender`
  5. Check fee routing: protocol fee should flow to fee collector, not get stuck
- **Failure Mode**: Integrators that rely on ERC-3156 interface receive incorrect data, leading to failed integrations or unexpected behavior. Flash loan fee may go to wrong address or be bypassed entirely.
- **Common Contexts**: f(x) v2 ERC-3156 noncompliance (M), BadgerDAO flashFee/maxFlashLoan paused flag (M), Caviar fee wrong address (M-16), Caviar fee not distributed to factory (M-06), Astaria FlashAuction missing initiator (M-24), OpenBrush PSP22Capped maxFlashLoan (M), QuickSwap/StellaSwap fee manipulation (M-01)

---

## FLASH-019: flash_mint_manipulation
- **Frequency**: ~10/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `flashMint()` on a token with uncapped or very large mint ceiling; minted tokens affect share ratios, fee calculations, or TVL snapshots before repayment; `fShareRatio` or similar ratio read mid-mint
- **Detection Heuristic**:
  1. Find `flashMint` or `mint` functions with same-block burn requirement
  2. Check if any ratio (`fShareRatio`, `sharePrice`, `totalSupply`-dependent rate) is read during the mint-and-burn window
  3. Verify if minted tokens can be used to call other protocol functions before repayment
  4. Check for uncapped mint amounts: `maxFlashLoan` returning `type(uint256).max` or very large number
  5. If protocol ratio is readable during flash mint window and affects a financial calculation: CONFIRMED
- **Failure Mode**: Attacker flash-mints large supply → `totalSupply` spikes → ratio `fShareRatio = balance / totalSupply` crashes → attacker purchases membership / opens cost-share at artificially reduced fee → burns minted supply → profit.
- **Common Contexts**: FairSide fShareRatio flash mint (M-11, L-06), Sablier flash mint steal (H), Optimism Interop flash mint breaking expectations (M), FairSide membership fee reduction, Yield fyDAI flash mint redemption (M)

---

## FLASH-020: arbitrary_swap_path_in_flash_callback
- **Frequency**: ~8/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `_swap(swapPath, ...)` inside flash loan callback accepts user-controlled `swapPath` or `routerData`; `executeSwap()` allows arbitrary target address; no whitelist of approved routers or tokens
- **Detection Heuristic**:
  1. Find swap calls within flash loan callback or leverage functions
  2. Check if `swapPath`, `router`, or `calldata` is user-supplied without validation
  3. Verify there is a whitelist of approved DEX routers
  4. Check if `calldata` to external contracts is sanitized (no arbitrary calls)
  5. If user controls both swap target and calldata within a privileged context: CONFIRMED
- **Failure Mode**: Attacker supplies crafted swap path that calls into the protocol itself or approved token contracts with malicious calldata, draining collateral or bypassing approval checks.
- **Common Contexts**: Wido Comet unrestricted `_swap` (H), Wido unexpected entry point impersonation (H), UniV3LpVault arbitrary `swapPath` (M-05), TeaVaultAmbient arbitrary executeSwap (H), Paribus lack of swap sanitization (M)

---

## FLASH-021: liquidation_stability_pool_profit_theft
- **Frequency**: ~10/500
- **Severity**: HIGH
- **Code Shape**: Liquidation calls `StabilityPool.offset()` distributing collateral gain to depositors; attacker flash-deposits into stability pool just before liquidation trigger; no snapshot of depositors at liquidation initiation
- **Detection Heuristic**:
  1. Find stability pool / liquidation pool deposit function
  2. Check if deposits are immediately eligible for liquidation collateral gain
  3. Verify there is no lock between deposit and gain eligibility
  4. Check if liquidation can be atomically sequenced: deposit → trigger liquidation → claim gain → withdraw
  5. If collateral gain = `deposit / totalPool * collateral` with no time lock: CONFIRMED
- **Failure Mode**: Attacker flash-loans stablecoin, deposits into stability pool, front-runs or triggers liquidation, claims disproportionate collateral gain at a discount, withdraws stablecoin, repays loan — stealing collateral from existing depositors.
- **Common Contexts**: Threshold Network StabilityPool (H), Prisma Finance StabilityPool (H), Ethereum Reserve Dollar (ERD) flash loan liquidation siphon (H), ERD oracle manipulation → liquidation (H)

---

## FLASH-022: accumulator_or_tvl_snapshot_not_updated_before_read
- **Frequency**: ~12/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `totalBonded`, `totalStaked`, `totalReserves`, `internalCash` read for ratio calculation but not updated after fee collection, rebasing, or external yield accrual; Aave aToken rebasing balance not reflected in TVL; `receiptToken balance-tracking` uses stale snapshot
- **Detection Heuristic**:
  1. Find ratio calculations that use `totalAssets`, `totalReserves`, or `totalBonded`
  2. Check if those values are updated in ALL state-changing functions (deposit, withdraw, collectFees, rebase)
  3. Specifically check fee collection: does `collectFees()` update `totalReserves` before or after distributing?
  4. For rebasing tokens: does TVL tracking account for aToken balance growth?
  5. If any update path skips the accumulator refresh: CONFIRMED
- **Failure Mode**: Fee collection without reserve update → attacker drains vault by treating un-accounted fees as free liquidity. Stale TVL allows draining via share price discrepancy.
- **Common Contexts**: Balancer v3 lack of reserve updates on fee collection (H-44), Mellow Protocol AaveVault TVL not updated (H-04), Thala Labs improper accumulator updates (H-93), C.R.E.A.M. suspicious totalReserves manipulation (M), Blend d_supply incorrect update (H-01)

---

## FLASH-023: funding_rate_or_skew_manipulation
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Funding rate = `f(oracle_maker_skew)` applied market-wide; attacker can shift skew cheaply on oracle maker while real market skew differs; fee rate based on order book imbalance readable in same block
- **Detection Heuristic**:
  1. Find funding rate calculation function
  2. Check if skew is sourced from a single maker (oracle maker) rather than aggregate market
  3. Verify cost to shift skew vs funding rate gain for other market participants
  4. Check if funding rate is applied immediately after calculation (no smoothing)
  5. If skew manipulation cost < funding extraction from others: CONFIRMED
- **Failure Mode**: Attacker opens small position on oracle maker to shift skew → extreme funding rate imposed on all market participants → other traders pay excessive funding → attacker collects funding on their large offsetting position.
- **Common Contexts**: Perpetual Protocol funding fee rate (H-2), Perpetual Pyth two-price attack (H-1), Zaros negative makerFee risk-free trade (H), Velar Artha sandwich position close (H-2)

---

## FLASH-024: flash_loan_bypassing_frozen_pool_or_access_control
- **Frequency**: ~6/500
- **Severity**: MEDIUM
- **Code Shape**: `flashLoan()` path does not check `isFrozen()` / `isPaused()` / `isActive()` flags; sanctioned addresses blocked from normal borrow but allowed through flash loan path; `flashLoan` on deprecated market still operational
- **Detection Heuristic**:
  1. Find flash loan entry point
  2. Check if it validates the same pool/market state flags as `borrow()` does
  3. Check if KYC/sanctions screening applies to `flashLoan` callers
  4. Verify if deprecated or frozen pools are excluded from flash loan availability
  5. If flash loan has fewer checks than normal borrow: CONFIRMED
- **Failure Mode**: Attacker borrows from frozen pool via flash loan, violating the intended security control. Sanctioned entity accesses protocol funds. Deprecated market allows extraction of remaining liquidity.
- **Common Contexts**: Blend flash loan from frozen pools (M-01), Coinbase Verified Pools sanctioned accounts (M), Numa deprecated market exploitation (M-5)

---

## FLASH-025: pyth_dual_price_intra_transaction_attack
- **Frequency**: ~4/500
- **Severity**: HIGH
- **Code Shape**: Protocol accepts two Pyth price updates in a single transaction; Pyth `updatePriceFeeds()` callable multiple times per block; attacker publishes low price then high price (or vice versa) within same tx to create arbitrage
- **Detection Heuristic**:
  1. Find Pyth price consumption: `pyth.getPriceNoOlderThan()`, `pyth.getPrice()`
  2. Check if `updatePriceFeeds()` can be called multiple times in the same transaction
  3. Verify if the protocol uses prices from two consecutive Pyth updates (different confidence intervals)
  4. Check if there is any restriction on using multiple price updates per block
  5. If two Pyth prices can coexist in same tx: CONFIRMED
- **Failure Mode**: Attacker submits Pyth update with price P1, executes a profitable operation, then submits another update with price P2 in same transaction, executes a second profitable operation — extracting value from the price delta.
- **Common Contexts**: Perpetual Protocol H-1 (two Pyth prices in same transaction attacking LP pools)

---

## FLASH-026: cross_chain_liquidity_manipulation
- **Frequency**: ~6/500
- **Severity**: MEDIUM
- **Code Shape**: `_swapAndSendERC20Tokens()` on cross-chain path uses spot liquidity; cross-chain message triggers swap on L2 based on L1 price; no slippage protection on cross-chain swap leg; bridge adapter trusts provided price
- **Detection Heuristic**:
  1. Find cross-chain swap/bridge functions that execute a swap on the destination
  2. Check if the swap amount is calculated based on source chain price while execution is on destination chain
  3. Verify there is no minimum output protection for the destination chain swap
  4. Check if the cross-chain message can be MEV'd at the destination
  5. If destination swap has no slippage protection: CONFIRMED
- **Failure Mode**: Attacker observes pending cross-chain message, front-runs on destination chain to manipulate pool price, cross-chain swap executes at unfavorable rate, attacker back-runs for profit.
- **Common Contexts**: DODO Cross-Chain DEX M-12 (cross-chain swap liquidity manipulation), Lyra Finance GMX minPrice/maxPrice trust (TRST-M-3), Connext swap without slippage (M-20)

---

## FLASH-027: bribe_or_gauge_allocation_flash_manipulation
- **Frequency**: ~8/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: Bribe allocation = `f(current_votes)` callable in same block as voting; gauge weight calculated from spot `balanceOf`; `addBribeFlywheel` front-runnable; allocation game manipulable via flash loan vote
- **Detection Heuristic**:
  1. Find bribe reward distribution or gauge weight calculation
  2. Check if votes / allocations are read at the moment of distribution (not snapshotted)
  3. Verify if `addBribeFlywheel` or similar functions can be front-run to capture newly added bribes
  4. Check if flash voting power (from flash-borrowed governance tokens) affects gauge weights
  5. If gauge weight = current votes without epoch-start snapshot: CONFIRMED
- **Failure Mode**: Attacker flash-borrows voting tokens → votes to maximize allocation to their pool → claims bribe/gauge rewards → returns tokens. Or: front-runs `addBribeFlywheel` to steal all newly added bribe funds.
- **Common Contexts**: Maia DAO bribe flywheel front-run (H-29), Derby allocations flash manipulation (M-24, M-19), Yield Basis gauge get_adjustment() (H), Debita Finance epoch bribe theft (M-19)

---

## FLASH-028: collateral_swap_with_unvalidated_callback_data
- **Frequency**: ~6/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `onCreditFlashLoan(address initiator, address lender, address token, uint256 amount, uint256 fee, bytes calldata data)` — `data` not validated against expected swap parameters; `originalCallData` not checked in `receiveFlashLoan`; arbitrary call possible through swap router
- **Detection Heuristic**:
  1. Find credit flash loan or collateral swap callbacks
  2. Check if `data` / `params` / `originalCallData` is validated against what was originally sent
  3. Verify there is no replay protection or nonce on callback data
  4. Check if the callback can be triggered with arbitrary `data` by an external actor
  5. If callback data is unvalidated and allows state changes: CONFIRMED
- **Failure Mode**: Attacker calls `receiveFlashLoan` or `onCreditFlashLoan` with crafted `data`, causing the protocol to execute an unintended swap or collateral transfer on behalf of a victim.
- **Common Contexts**: BakerFi BalancerFlashLender originalCallData not validated (M-06), LoopFi onCreditFlashLoan stuck funds (M-05, M-02, M-33, M-07), LoopFi poolAction wrong token out (M-08)

---

## FLASH-029: flash_loan_used_for_governance_crowdfund_attack
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: Crowdfund contribution tracked by `msg.value` / `amount` at contribution time; governance power = contribution share; no lock between contribution and governance action; ETH crowdfund accepts flash-borrowed ETH
- **Detection Heuristic**:
  1. Find crowdfund participation function
  2. Check if governance power (voting weight, authority, NFT control) is determined by contribution size
  3. Verify if contribution can be made with borrowed/flash-loaned assets
  4. Check if there is a lock between contribution and governance exercise
  5. If governance power tracks real-time contributions without time lock: CONFIRMED
- **Failure Mode**: Attacker flash-loans ETH, contributes to crowdfund, gains majority governance power, takes hostile action (forces NFT buy, controls party), withdraws contribution, repays loan.
- **Common Contexts**: PartyDAO ETH crowdfund flash loan control (H-02), Party Protocol 51% arbitrary call proposal (H-01)

---

## FLASH-030: flash_loan_fee_bypass_via_cheaper_path
- **Frequency**: ~6/500
- **Severity**: MEDIUM
- **Code Shape**: `buy()` function implicitly enables flash loan at lower fee than `flashLoan()` fee; fee not charged on zero-amount flash; flash loan fee uninitialized (`flashFeeFactor = 0` by default); protocol serves as unintentional flash loan pool
- **Detection Heuristic**:
  1. Find all paths that allow same-transaction borrow-and-repay
  2. Compute effective fee for each path
  3. Compare against the declared `flashFee()` — is there a cheaper path?
  4. Check initialization: is `flashFeeFactor` set in constructor or left at zero?
  5. Verify if zero-amount flash loan call is allowed (earns zero fee)
- **Failure Mode**: Sophisticated user routes flash borrowing through the cheaper path (e.g., `buy()` instead of `flashLoan()`), paying less than the intended fee — reducing protocol revenue and undermining fee economics.
- **Common Contexts**: Caviar `buy()` cheaper flash loan path (M-01), Yield flashFeeFactor uninitialized (L-07), C.R.E.A.M. zero flashLoan allowed (M), Putty free flash loan (M-09), Sharwafinance free flash loans (M-13)

---

## FLASH-031: price_impact_from_bonding_curve_or_genesis_period
- **Frequency**: ~6/500
- **Severity**: HIGH
- **Code Shape**: `GenesisGroup.maxGenesisPrice` reachable with flash loan → profit from genesis; `BondingCurve` introduction creates volatility window; bonding curve price determined by total supply at moment of purchase; launch fee bypassable via flash-stake
- **Detection Heuristic**:
  1. Find genesis / launch / bonding curve pricing functions
  2. Check if price is a function of current pool state reachable in one transaction
  3. Verify if reaching `maxGenesisPrice` allows guaranteed profit extraction
  4. Check for front-running protection during bonding curve introduction
  5. If genesis price logic has exploitable monotone region with flash capital: CONFIRMED
- **Failure Mode**: Attacker flash-loans capital to push pool to genesis price boundary, extracting guaranteed profit from genesis mechanics or exploiting the volatility window during bonding curve introduction.
- **Common Contexts**: Fei Protocol GenesisGroup C05 (H), Fei Protocol BondingCurve introduction H02 (H), Rush Trading RushERC20 launch fee bypass (H), Virtuals Protocol forced graduation (M-04)

---

## FLASH-032: utilization_or_capacity_dos_via_flash_loan
- **Frequency**: ~8/500
- **Severity**: HIGH / MEDIUM
- **Code Shape**: `supply cap` reachable via flash loan → redirects deposits to idle market; `maxContractBalance` checkable by attacker to deny deposits; `flashLoan` increases pool utilization transiently → triggers rate limiter or vault rehypothecation DoS
- **Detection Heuristic**:
  1. Find capacity checks (supply cap, max contract balance, utilization threshold) used to route or block operations
  2. Check if those checks use current state (includng flash loan in-flight balance)
  3. Verify if flash borrowing to cap or threshold blocks legitimate users during repayment window
  4. Check vault rehypothecation: does `AToken.flashLoan()` count against the rehypothecation pool capacity?
  5. If a flash loan can trigger a capacity check that blocks others: CONFIRMED
- **Failure Mode**: Attacker flash-borrows to push supply cap → deposits from legitimate users routed to idle market at zero yield. Or: flash borrow spikes utilization → rehypothecation blocked → vault functionality degraded for all users.
- **Common Contexts**: Morpho MetaMorpho supply cap DoS via flash loan (M), Cod3x lend / Astera vault rehypothecation DoS (H), Reality Cards maxContractBalance abuse (M-16), f(x) v2 flashLoan blocked (H), Blend invalid utilization check blocking flash loan (M-02)
