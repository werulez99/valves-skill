# Valves Pattern Library — Master Index

> **Solodit corpus**: 562 patterns from 50,062 real audit findings (9,354 sampled across 19 clusters)
> **Cantina corpus**: 80 patterns from 279 confirmed HIGH/MEDIUM competition findings (16 contests, 13 clusters + 1 new)
> **Total patterns**: 642
> **Extracted**: 2026-05-07 (Solodit), 2026-05-07 (Cantina)
> **Method**: Per-cluster deep extraction via LLM analysis
> **Format**: Each pattern includes code shape, detection heuristic, failure mode, and frequency data

---

## How Agents Use This Library

During an audit, the orchestrator:
1. **Phase 1 (Recon)**: Identifies which clusters are relevant based on protocol type and code patterns
2. **Phase 3 (Breadth)**: Injects relevant pattern files into agent prompts as detection checklists
3. **Phase 4b (Depth)**: Depth agents reference patterns for systematic investigation of specific vulnerability classes

Agents read pattern files via: `Read ~/.valves/patterns/{slug}.md`

Each pattern entry provides:
- **Code Shape**: What to grep/look for in source code (function names, operators, patterns)
- **Detection Heuristic**: Step-by-step check methodology (HOW to detect, not WHAT to find)
- **Failure Mode**: What breaks and how the exploit works
- **Frequency**: How common this pattern is in real audits (from 50k finding corpus)

---

## Cluster Index

| Cluster | File | Patterns | Findings Basis | Primary Trigger |
|---------|------|----------|----------------|-----------------|
| Lending & Liquidation | `lending-liquidation.md` | 50 | 3,460 | `liquidate`, `borrow`, `repay`, `healthFactor`, `collateral` |
| Bridge & Cross-Chain | `bridge-cross-chain.md` | 45 | 2,634 | `lzReceive`, `ccipReceive`, `bridge`, `crossChain`, `relayer` |
| Governance Attacks | `governance-attacks.md` | 38 | 6,020 | `Governor`, `vote`, `propose`, `quorum`, `delegate`, `timelock` |
| Signature & Auth | `signature-auth.md` | 35 | 4,380 | `ecrecover`, `ECDSA`, `permit`, `EIP712`, `nonce`, `signature` |
| DEX & AMM Logic | `dex-amm-logic.md` | 34 | 5,324 | `swap`, `addLiquidity`, `pool`, `AMM`, `sqrtPrice`, `tick` |
| Access Control | `access-control.md` | 32 | 3,557 | `onlyOwner`, `onlyRole`, `modifier`, `AccessControl`, `auth` |
| Flash Loan Attacks | `flash-loan-attacks.md` | 32 | 664 | `flashLoan`, `flashMint`, `IERC3156`, `executeOperation` |
| Denial of Service | `denial-of-service.md` | 30 | 3,071 | unbounded loops, `push` payments, `blacklist`, batch operations |
| Price Manipulation | `price-manipulation.md` | 30 | 404 | `slot0`, `getReserves`, `balanceOf(pool)`, `virtual_price` |
| Arithmetic Precision | `arithmetic-precision.md` | 28 | 2,814 | `mulDiv`, `WAD`, `RAY`, `decimals()`, division, rounding |
| Integer Overflow | `integer-overflow.md` | 28 | 3,478 | `unchecked`, `uint128`, `int256`, type casts, `<<`, `>>` |
| Vault Share Accounting | `vault-share-accounting.md` | 28 | 993 | `ERC4626`, `totalAssets`, `convertToShares`, `deposit`, `redeem` |
| Oracle Dependency | `oracle-dependency.md` | 25 | 4,576 | `latestRoundData`, `Chainlink`, `TWAP`, `Pyth`, `oracle` |
| Token Accounting | `token-accounting.md` | 24 | 751 | `balanceOf`, `transferFrom`, fee-on-transfer, `rebase`, `ERC777` |
| Frontrunning & MEV | `frontrunning-mev.md` | 22 | 2,591 | `amountOutMin`, `deadline`, `slot0`, sandwich, `commit-reveal` |
| Initialization | `initialization.md` | 22 | 4,342 | `initialize`, `initializer`, `constructor`, `_disableInitializers` |
| Proxy & Upgrade | `proxy-upgrade.md` | 22 | 5,138 | `delegatecall`, `upgradeTo`, `EIP1967`, `beacon`, `diamond` |
| Logic Errors | `logic-errors.md` | 19 | 50 | `&&` vs `||`, off-by-one, wrong variable, inverted condition |
| Reentrancy | `reentrancy.md` | 18 | 3,088 | `call{value}`, `safeTransfer`, `onERC721Received`, `CEI` |

---

## Pattern Distribution

```
lending-liquidation    ██████████████████████████████████████████████████  50
bridge-cross-chain     █████████████████████████████████████████████       45
governance-attacks     ██████████████████████████████████████              38
signature-auth         ███████████████████████████████████                 35
dex-amm-logic          ██████████████████████████████████                  34
access-control         ████████████████████████████████                    32
flash-loan-attacks     ████████████████████████████████                    32
denial-of-service      ██████████████████████████████                      30
price-manipulation     ██████████████████████████████                      30
arithmetic-precision   ████████████████████████████                        28
integer-overflow       ████████████████████████████                        28
vault-share-accounting ████████████████████████████                        28
oracle-dependency      █████████████████████████                           25
token-accounting       ████████████████████████                            24
frontrunning-mev       ██████████████████████                              22
initialization         ██████████████████████                              22
proxy-upgrade          ██████████████████████                              22
logic-errors           ███████████████████                                 19
reentrancy             ██████████████████                                  18
```

## Cross-Cluster Pattern Mapping (for multi-domain audits)

When a protocol touches multiple domains, load ALL relevant pattern files:

| Protocol Type | Primary Clusters | Secondary Clusters |
|---------------|------------------|--------------------|
| Lending | lending-liquidation, oracle-dependency | flash-loan-attacks, price-manipulation, access-control |
| DEX/AMM | dex-amm-logic, price-manipulation | flash-loan-attacks, frontrunning-mev, arithmetic-precision |
| Vault/Yield | vault-share-accounting, arithmetic-precision | flash-loan-attacks, token-accounting, reentrancy |
| Bridge | bridge-cross-chain, signature-auth | access-control, denial-of-service, initialization |
| Governance | governance-attacks, access-control | flash-loan-attacks, proxy-upgrade, signature-auth |
| NFT/Gaming | access-control, reentrancy | token-accounting, logic-errors, frontrunning-mev |
| Staking | vault-share-accounting, arithmetic-precision | flash-loan-attacks, denial-of-service, access-control |
| Reward Emission | (none in Solodit) | arithmetic-precision, access-control |

---

## Cantina Pattern Library (v1.7-CANTINA)

> **Source**: 279 confirmed HIGH/MEDIUM findings from 16 Cantina competitions
> **Total patterns**: 80 (48 HIGH, 32 MEDIUM)
> **Location**: `~/.valves/patterns/cantina/cantina-{slug}.md`
> **Index**: `~/.valves/patterns/cantina/CANTINA_PATTERN_INDEX.md`
> **New cluster**: reward-accounting (7 patterns, no Solodit equivalent)

Cantina patterns supplement Solodit patterns — they are NOT merged into Solodit files. This separation enables A/B testing (run with/without Cantina layer, compare recall).

### Cantina Cluster Index

| Cluster | File | Patterns | ID Range |
|---------|------|----------|----------|
| Lending & Liquidation | `cantina/cantina-lending-liquidation.md` | 12 | CANTINA-LEND-001..012 |
| Logic Errors | `cantina/cantina-logic-errors.md` | 11 | CANTINA-LOGIC-001..011 |
| DEX & AMM Logic | `cantina/cantina-dex-amm-logic.md` | 9 | CANTINA-DEX-035..043 |
| Vault & Share Accounting | `cantina/cantina-vault-share-accounting.md` | 8 | CANTINA-VAULT-029..036 |
| Reward Accounting (NEW) | `cantina/cantina-reward-accounting.md` | 7 | CANTINA-REWARD-001..007 |
| Denial of Service | `cantina/cantina-denial-of-service.md` | 7 | CANTINA-DOS-031..037 |
| Access Control | `cantina/cantina-access-control.md` | 5 | CANTINA-AC-033..037 |
| Arithmetic & Precision | `cantina/cantina-arithmetic-precision.md` | 5 | CANTINA-ARITH-029..033 |
| Frontrunning & MEV | `cantina/cantina-frontrunning-mev.md` | 5 | CANTINA-MEV-023..027 |
| Oracle Dependency | `cantina/cantina-oracle-dependency.md` | 4 | CANTINA-ORACLE-026..029 |
| Signature & Auth | `cantina/cantina-signature-auth.md` | 3 | CANTINA-SIG-036..038 |
| Reentrancy | `cantina/cantina-reentrancy.md` | 2 | CANTINA-REENTRY-019..020 |
| Bridge & Cross-Chain | `cantina/cantina-bridge-cross-chain.md` | 2 | CANTINA-BRIDGE-046..047 |

### Cantina Cross-Cluster Pattern Mapping

| Protocol Type | Cantina Primary Clusters | Cantina Secondary Clusters |
|---------------|--------------------------|---------------------------|
| Lending | cantina-lending-liquidation, cantina-logic-errors | cantina-arithmetic-precision, cantina-denial-of-service |
| DEX/AMM | cantina-dex-amm-logic, cantina-frontrunning-mev | cantina-arithmetic-precision, cantina-logic-errors |
| Vault/Yield | cantina-vault-share-accounting, cantina-arithmetic-precision | cantina-logic-errors, cantina-denial-of-service |
| Bridge | cantina-bridge-cross-chain, cantina-access-control | cantina-signature-auth |
| Staking | cantina-reward-accounting, cantina-access-control | cantina-denial-of-service, cantina-arithmetic-precision |
| Reward Emission | cantina-reward-accounting (ALWAYS) | cantina-access-control, cantina-arithmetic-precision |
| Baseline (any) | cantina-access-control, cantina-logic-errors | cantina-denial-of-service |

### Integration Points (see Rule 34 in `~/.valves/CLAUDE.md`)

| Stage | Session | Role | Injection Format |
|-------|---------|------|-----------------|
| Breadth | A | Coverage shortlist | Compact table (max 20 lines/cluster, max 2 clusters/agent) |
| Depth iter 1 | A | Post-methodology cross-check | Full file Read directive (after Solodit cross-check) |
| DA iter 2-3 | B (Session A in Core) | Adversarial alternative vectors | Full file Read directive + adversarial framing |
| Chain analysis | B (or A in Core) | Failure mode extracts | Compact failure modes only (max 30 lines total) |
| Verification | B | None | — |
| Report | B | None | — |

**Anti-anchoring rule**: Methodology first, Solodit patterns second, Cantina patterns third. Cantina patterns are a coverage amplifier, not the methodology.

---

## Learned Patterns (v1.8-PATCH1)

> **Source**: Promoted from post-audit `pattern_candidates.md` via curator review
> **Location**: `~/.valves/patterns/learned/{slug}.md`
> **Schema**: `~/.valves/methodology/pattern-candidate-schema.md`
> **Status**: Empty — populated as audits produce verified novel patterns

Learned patterns follow the same anti-anchoring rule as Solodit and Cantina patterns.
Agents propose candidates to `{SCRATCHPAD}/pattern_candidates.md` during verification.
Only the post-audit curator promotes candidates to this directory.

| Pattern ID | File | Cluster | Chains | Source Audit |
|------------|------|---------|--------|-------------|
| (none yet) | | | | |

### Promotion Rules (summary)
1. Only verified High/Medium findings (or novel Low with [POC-PASS]/[MEDUSA-PASS])
2. Must pass RC-AGENT Exclusion Test + anti-bloat gates
3. Must include false-positive filters and "where this does NOT apply"
4. No proprietary code, no client-specific identifiers
5. Abstract code shape, not specific bug instance
