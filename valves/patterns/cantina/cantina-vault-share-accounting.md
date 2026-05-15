# Cantina Vault Share Accounting Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 8
> NOTE: Supplements existing VAULT-001..028 from Solodit corpus

---

## CANTINA-VAULT-029: inflation_attack_with_residual_exposure
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**: `shares = assets * totalSupply / totalAssets` without virtual offset; `totalAssets()` includes `balanceOf(address(this))`; no `_decimalsOffset()` or dead shares in constructor; `deposit()` has no minimum first-deposit check
- **Detection Heuristic**:
  1. Locate vault share minting formula (assets-to-shares conversion)
  2. Check if the formula uses virtual assets/shares offset (ERC4626 `_decimalsOffset`)
  3. Check if `totalAssets()` reads live token balance or only tracked deposits
  4. If no virtual offset AND live balance used: test the classic inflation sequence (deposit 1 wei, donate large amount, front-run victim deposit)
  5. Verify if existing mitigations (dead shares, minimum deposit, internal balance tracking) are actually enforced on ALL entry paths
- **Failure Mode**: Attacker is first depositor, deposits 1 wei to get 1 share, donates large amount directly to vault, inflating share price. Victim deposits but receives 0 shares due to rounding. Attacker redeems their 1 share for victim's deposit + donation. Variant: even with partial mitigation, some entry paths (direct `mint()`, or vault-wrapper reuse) bypass the protection
- **Common Contexts**: ERC4626 vaults, lending pool share tokens, any vault where shares represent proportional claim on a growing balance, vault wrappers that create pools permissionlessly using existing vault addresses

---

## CANTINA-VAULT-030: first_deposit_zero_price_initialization
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `if (totalSupply == 0) { shares = assets }` or `price = totalAssets / totalSupply` with no guard for `totalSupply == 0`; initial share price set to 1:1 regardless of underlying token decimals
- **Detection Heuristic**:
  1. Locate the first-deposit branch in the share minting function
  2. Check if the initial share price accounts for decimal differences between share token and underlying
  3. Verify if a malicious first depositor can set an arbitrary price by depositing dust
  4. Check if the first deposit creates dead shares or enforces a minimum meaningful amount
- **Failure Mode**: First depositor deposits 1 wei, establishing a 1:1 price. If underlying has 18 decimals but share has 6, the price is set at an absurdly low granularity. Subsequent depositors either get rounded-down shares or the vault operates at a precision where meaningful fractions are lost. Validator/LP who is first gets exploited by second user when no slippage check exists
- **Common Contexts**: Vault AMMs, lending pools with share tokens, any pool where first deposit sets the baseline exchange rate

---

## CANTINA-VAULT-031: dust_rounding_over_seizure
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `seizeAmount = roundUp(debt * price / collateralPrice)` or `shares = roundUp(assets / exchangeRate)` where rounding direction favors the seizer/protocol; small position liquidation where rounding exceeds actual debt
- **Detection Heuristic**:
  1. Identify all liquidation/seizure paths that convert debt amounts to collateral amounts
  2. Check rounding direction in the conversion (roundUp vs roundDown)
  3. Calculate: for the smallest possible debt position, does the seized collateral exceed the actual debt value?
  4. Check if residual dust positions can be created and then liquidated at a profit due to rounding
  5. Verify if remaining debt after partial seizure can underflow
- **Failure Mode**: With small (dust-level) supply positions, rounding in seizure calculations causes more collateral to be seized than the debt is worth. Attacker creates many dust positions, each gets over-seized by rounding, accumulated over-seizure becomes the excess debt socialized to remaining suppliers. The remaining bad debt is absorbed by the protocol or other users
- **Common Contexts**: Lending protocols with liquidation, vault systems with collateral seizure, any protocol converting between two unit systems with rounding at small values

---

## CANTINA-VAULT-032: balance_of_accounting_contamination
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `totalAssets = token.balanceOf(address(this))` instead of internal `_totalDeposited` tracking; `_getTotalUnderlyingValue()` uses `balanceOf`; vault accepts direct transfers that inflate `totalAssets` without minting shares
- **Detection Heuristic**:
  1. Identify how the vault computes total assets or total underlying value
  2. Check if it uses `balanceOf(address(this))` vs an internally tracked deposit sum
  3. If `balanceOf` is used, check if direct token transfers (without calling deposit) affect share pricing
  4. Test: transfer tokens directly to vault, verify share price changes
  5. Check if yield/rewards/rebasing tokens accumulate in balance without share accounting update
- **Failure Mode**: External tokens arrive in the vault via airdrop, rebasing, direct transfer, or reward distribution. `balanceOf` increases but no new shares are minted. Existing shareholders' claim inflates. New depositors after the balance increase get fewer shares than they should (donation attack vector). Alternatively, the inflated balance is used in health factor calculations, enabling under-collateralized borrowing
- **Common Contexts**: ERC4626 vaults wrapping yield-bearing tokens, lending pools using balance-based accounting, any vault where external balance changes are possible (rebasing, airdrops, fee-on-transfer tokens)

---

## CANTINA-VAULT-033: erc4626_maxdeposit_maxredeem_noncompliance
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `maxDeposit() returns type(uint256).max` during insolvency; `maxRedeem()` does not account for withdrawal locks or cooldowns; `maxWithdraw` ignores strategy-level withdrawal caps
- **Detection Heuristic**:
  1. Read ERC4626 spec requirements for `maxDeposit`, `maxWithdraw`, `maxRedeem`, `maxMint`
  2. Check if each function accounts for ALL constraints: pause state, cooldown, insolvency, strategy caps, per-user limits
  3. Verify: calling `deposit(maxDeposit())` or `redeem(maxRedeem())` must not revert
  4. Test edge cases: vault at zero assets, vault insolvent (assets < liabilities), vault paused, user with active cooldown
  5. Check if integrators using these functions as pre-flight checks would get incorrect results
- **Failure Mode**: `maxDeposit` returns `uint256.max` during insolvency, integrator deposits based on this, deposit fails or funds are trapped. `maxRedeem` ignores cooldown period, integrator calls `redeem(maxRedeem())`, transaction reverts. Third-party protocols building on the vault use max* functions for safety checks, incorrect values cascade into their logic
- **Common Contexts**: ERC4626 vaults with complex withdrawal logic, vaults with strategies that have withdrawal caps, any vault intended for composability where integrators rely on EIP-4626 view functions

---

## CANTINA-VAULT-034: vault_loss_withdrawal_deadlock
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `require(assets <= availableAssets)` in withdraw where `availableAssets` can decrease below total shares value; strategy reports loss but vault has no loss socialization; `withdraw` reverts when `convertToAssets(shares) > strategy.totalAssets()`
- **Detection Heuristic**:
  1. Identify how the vault handles underlying strategy losses (realized or unrealized)
  2. Check if withdrawal function reverts when total assets drop below total shares value
  3. Trace: strategy reports loss -> vault totalAssets decreases -> can users still withdraw proportionally?
  4. Verify if loss socialization mechanism exists (pro-rata loss, loss queue, insurance)
  5. Test: simulate strategy loss of 10%, attempt full withdrawal of all depositors
- **Failure Mode**: Strategy suffers a loss (hack, slippage, bad debt). Vault's `totalAssets` drops. Withdrawal function computes assets-per-share at the new lower rate but reverts because the underlying strategy cannot fulfill the redemption (insufficient liquid assets). All depositors are locked out. First-to-withdraw gets full value, later withdrawers get nothing (bank run without pro-rata enforcement)
- **Common Contexts**: Yield vaults with external strategies (Morpho, Yearn-style), lending protocols where underlying loans can default, any vault where the underlying asset amount can decrease independently

---

## CANTINA-VAULT-035: permissionless_vault_wrapper_hijack
- **Frequency**: ~2/279 findings
- **Severity**: HIGH
- **Code Shape**: `createPool(vaultAddress, ...)` where `vaultAddress` is user-supplied and not validated against a registry; vault wrapper shares minted based on existing vault's exchange rate; no ownership check on the wrapped vault
- **Detection Heuristic**:
  1. Identify pool/market creation functions that accept vault or strategy addresses as parameters
  2. Check if the provided vault address is validated (registry lookup, ownership check, interface verification)
  3. Verify if a malicious user can create a pool wrapping someone else's vault
  4. Trace: what happens when multiple pools wrap the same underlying vault
  5. Check if yield from the vault is correctly attributed when multiple wrappers exist
- **Failure Mode**: Attacker creates a new pool/market using an existing vault wrapper address as the underlying. The pool inherits the vault's yield without contributing deposits. Attacker deposits into their pool, the pool deposits into the existing vault, yield from all vault depositors is proportionally shared with the attacker's pool. Effectively stealing yield from existing vault depositors
- **Common Contexts**: Lending protocols with permissionless market creation, vault aggregators, any system that allows wrapping arbitrary vault addresses without access control

---

## CANTINA-VAULT-036: shares_inflation_dos
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `shares = assets * totalSupply / totalAssets` where `totalAssets` can be externally inflated; `deposit(1 wei)` followed by `donate(largeAmount)` creates 1 share worth `largeAmount + 1`; subsequent `deposit(X)` yields 0 shares when `X < totalAssets / totalSupply`
- **Detection Heuristic**:
  1. Confirm vault is vulnerable to classic inflation (no virtual offset, uses live balance)
  2. Check the specific DoS variant: after inflation, can legitimate deposits still mint non-zero shares?
  3. Calculate minimum viable deposit after inflation: `minDeposit = ceil(totalAssets / totalSupply)`
  4. If `minDeposit` exceeds a reasonable user deposit amount, DoS is confirmed
  5. Check if this persists (attacker must maintain the inflated state) or is permanent
- **Failure Mode**: Attacker inflates share price to extreme value (e.g., 1 share = 1M tokens). All subsequent deposits below 1M tokens mint 0 shares due to integer division. The vault becomes unusable for normal users. Unlike the theft variant, the attacker may not profit directly but permanently bricks the vault for others. This can target competing protocols' vaults
- **Common Contexts**: New vaults with zero initial deposits, vault factories where anyone can be first depositor, lending pool share tokens without minimum deposit enforcement

---
