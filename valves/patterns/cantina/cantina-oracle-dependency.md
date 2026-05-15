# Cantina Oracle Dependency Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 4
> NOTE: Supplements existing ORACLE-001..025 from Solodit corpus

---

## CANTINA-ORACLE-026: decimal_mismatch_in_price_computation
- **Frequency**: ~4/279 findings
- **Severity**: HIGH
- **Code Shape**: `uint256 price = oracle.getPrice(token) * amount / 1e18` where token.decimals() != 18; `sqrtRatioX96 = sqrt(priceA / priceB)` without normalizing decimals; `getQuote()` assumes both tokens share the same decimal precision
- **Detection Heuristic**:
  1. Find price computation functions that combine values from different sources (oracle price, token amount, exchange rate)
  2. Check if each input's decimal precision is explicitly normalized before arithmetic (scaling to a common base like 1e18 or 1e27)
  3. Identify hardcoded divisors (1e18, 1e8, 1e6) and verify they match the actual decimals of the token or oracle feed involved
  4. Test with concrete mismatched decimals: compute output for (18,18), (18,6), (6,18), (8,18) decimal pairs and check for off-by-orders-of-magnitude results
  5. Trace the mispriced value to its consumer (collateral valuation, liquidation threshold, swap amount) to confirm impact
- **Failure Mode**: A price function assumes 18-decimal inputs but receives a 6-decimal token amount (USDC) or an 8-decimal oracle price (Chainlink USD). The resulting valuation is off by 10^10 or 10^12. Collateral is massively overvalued (allowing undercollateralized borrowing) or undervalued (triggering false liquidations). Depending on direction, attacker either borrows against phantom collateral or liquidates healthy positions.
- **Common Contexts**: Multi-collateral vaults with mixed-decimal tokens, NFT wrapper valuation (ERC721 pricing), cross-token sqrtPriceX96 computation, Chainlink + custom oracle combination, any protocol supporting both USDC (6) and WETH (18)

---

## CANTINA-ORACLE-027: inconsistent_price_type_selection
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `uint256 midPrice = (bid + ask) / 2` used in liquidation path; `getPrice()` returns mid-price but `getSqrtRatio()` returns bid; one function uses `oracle.latestAnswer()` while another uses `oracle.getRoundData()` for the same feed
- **Detection Heuristic**:
  1. Identify all oracle read sites across the codebase (getPrice, getQuote, getSqrtRatio, latestAnswer, getRoundData)
  2. Classify each read by price type: bid, ask, mid, last, TWAP
  3. Map price type to usage context: is the read used for deposits, withdrawals, liquidations, or transfers
  4. Check for inconsistency: the same logical operation using different price types in different code paths, or a price type inappropriate for its context (mid-price for liquidation, bid for minting)
  5. Verify the spread between price types is material (>10bps for liquid pairs, >100bps for illiquid)
- **Failure Mode**: Protocol uses mid-price (average of bid and ask) during liquidation transfers, but bid-price during collateral valuation. An attacker exploits the spread: their collateral is valued at bid (lower), triggering liquidation, but the liquidation transfer uses mid (higher), leaving the protocol with less collateral than expected. Alternatively, mid-price for NFT transfers during liquidation overpays the liquidator vs the true executable price, creating a subsidy that can be farmed.
- **Common Contexts**: NFT lending with bid/ask spreads, concentrated liquidity position valuation, dual oracle systems (Chainlink + Uniswap TWAP), lending liquidation vs borrowing paths using different feeds

---

## CANTINA-ORACLE-028: missing_staleness_check_on_oracle_price
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `(, int256 price, , ,) = feed.latestRoundData(); return uint256(price);` without checking `updatedAt` or `answeredInRound`; `oracle.getMedianPrice()` without timestamp validation
- **Detection Heuristic**:
  1. Find all oracle price consumption sites (latestRoundData, latestAnswer, getMedianPrice, consult)
  2. For each site, check if the returned timestamp (updatedAt, observationTimestamp, medianTimestamp) is validated against a maximum acceptable age
  3. If a staleness check exists, verify the threshold is appropriate for the asset's volatility (not 24h for a volatile asset)
  4. Confirm that a stale price being used would cause material harm (using yesterday's price for a 10% daily mover)
  5. Check if the same oracle has both staleness-checked and unchecked consumption sites (inconsistency)
- **Failure Mode**: Oracle feed stops updating (sequencer downtime, feed deprecation, data provider failure). Protocol continues using the last reported price, which may be hours or days old. Stale price enables arbitrage: if real price dropped 20% but stale price shows old value, attacker deposits overvalued collateral and borrows against it. Alternatively, stale price prevents liquidations of underwater positions.
- **Common Contexts**: Chainlink latestRoundData without updatedAt check, custom oracle adapters without timestamp passthrough, median price aggregators, any L2 deployment (sequencer downtime risk amplifies staleness)

---

## CANTINA-ORACLE-029: identical_oracle_calls_defeat_deviation_check
- **Frequency**: ~2/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `uint256 price1 = oracle.getPrice(token); uint256 price2 = oracle.getPrice(token); require(abs(price1 - price2) < maxDeviation)` -- same oracle, same block, same result; deviation check comparing a price source against itself
- **Detection Heuristic**:
  1. Find price deviation or sanity check mechanisms that compare two price values
  2. Verify the two values come from genuinely independent sources (different oracles, different time windows, different calculation methods)
  3. Check if both reads hit the same oracle with the same parameters in the same transaction (guaranteed identical result)
  4. If the "second source" is derived from the first (e.g., TWAP computed from the same spot feed), assess whether the derivation provides meaningful independence
  5. Confirm the deviation check is the sole defense against price manipulation for a critical operation
- **Failure Mode**: Protocol implements a price deviation check comparing primary and secondary prices, but both reads query the same oracle contract in the same block. The values are always identical, making the deviation check a no-op. An attacker manipulates the single oracle source (flash loan pool manipulation, donation attack) and the deviation check does not detect it. The manipulated price is used for collateral valuation, liquidation, or swap pricing.
- **Common Contexts**: Dual-oracle systems where both sources resolve to the same underlying feed, TWAP vs spot comparison where TWAP window is 0 or 1 block, sanity checks comparing Chainlink price to a Chainlink-derived value
