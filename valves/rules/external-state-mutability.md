<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# External-State Mutability

Source-of-truth for the **External-State Mutability Recon** run by Propagation P1 Agent (Phase 4a.5.c, Task 4). Output: `{scratchpad}/external_mutability_candidates.md`. Flags `MUTABILITY_DRIFT_CANDIDATE` for locally-cached external values whose upstream is admin-mutable.

## Purpose

Many integrations cache external values locally — fee rates, oracle decimals, vault address, governance address, threshold parameters. When the local cache is treated as immutable but the upstream protocol can mutate it, the audited contract operates on stale data after upstream changes. Common consequences: mis-priced operations, stale price feeds, lost ownership, missed pause events.

This scan checks each cached external value against the upstream protocol's known mutability profile.

## § Reference Table (selected protocols)

| Protocol | Mutable parameters (admin-settable) | Local cache risk |
|---|---|---|
| **Uniswap V3 Pool** | `setFeeProtocol(uint8 fee0, uint8 fee1)` (factory); `initialize` only once | Cached fee tier is fixed per pool; pool-level mutability is in factory governance only |
| **Uniswap V3 Factory** | `setOwner`, `enableFeeAmount` (adds new fee tiers) | Cached factory address: usually safe; cached fee tiers list grows but does not shrink |
| **Aave V3 PoolAddressesProvider** | `setACLAdmin`, `setPoolDataProvider`, `setPoolImpl` | Cached `provider.getPool()` can change; CACHE_RISK |
| **Aave V3 Pool** | `setReserveConfiguration` (ltv, liqThreshold, ...) | LTV / threshold cached locally → mis-liquidations on change |
| **Compound V3** | `proposeNewOwner`, governance-controlled config | Cached config can drift |
| **Chainlink AggregatorProxy** | `proposeAggregator`, `confirmAggregator` (re-points to new feed) | Cached aggregator: SAFE (proxy still works); cached `decimals()`: RISK if new feed has different decimals |
| **Chainlink VRF Coordinator** | `setConfig`, `setLINKBalance` | Cached gas-lane / minimum confirmations: RISK |
| **Curve StableSwap pool** | `commit_new_parameters`, `apply_new_parameters` (A, fees) | Cached A or fee → mis-priced swaps post-update |
| **Balancer V2 Vault** | `setRelayerApproval`, `setProtocolFeesCollector` | Cached fees collector: RISK |
| **OpenZeppelin ProxyAdmin** | `upgradeAndCall` | Cached implementation address: SAFE for proxy callers; RISK for tools that read storage by slot |
| **Gnosis Safe** | `addOwnerWithThreshold`, `removeOwner`, `swapOwner`, `changeThreshold` | Cached owner-list / threshold → trust-assumption drift |
| **EIP-1271 signer** | upstream may rotate underlying signer | Cached signer address: RISK |
| **LayerZero OApp config** | `setPeer`, `setSendLibrary`, `setReceiveLibrary` | Cached peer addresses: RISK |
| **Chainlink CCIP Router** | `applyRampUpdates`, `applyAllowListUpdates` | Cached destination ramp / allow-list: RISK |
| **ERC4626 vault** | `setStrategy`, `setFee` (depends on impl) | Cached share-price / strategy: RISK |
| **Generic ERC20** | rebases / fee-on-transfer / blacklists (depends on token impl) | Cached `balanceOf` between reads: RISK |

> The agent should treat this table as a starting point and look up the actual upstream contract's setters at audit-time when an integrated protocol is unfamiliar.

## § Detection methodology

For each external protocol integrated in the codebase (identified from imports, `IExternal` interface usage, dependency manifests):

1. Enumerate every value the audited contract caches locally that originates from this protocol.
2. Look up the upstream protocol's setters (use the Reference Table; otherwise fetch the upstream contract).
3. For each cached value, determine: is the upstream parameter admin-mutable, governance-mutable, or immutable?
4. If admin/governance-mutable AND the local cache has no refresh / event-listener / staleness check → flag `MUTABILITY_DRIFT_CANDIDATE`.

## § Output schema (`external_mutability_candidates.md`)

```markdown
## MUTABILITY_DRIFT_CANDIDATE — {ContractName}.{cacheVariable}
- Upstream protocol: {protocol name + version}
- Upstream mutability: {admin / governance / time-locked / immutable}
- Cached value: {what it represents — fee rate, address, decimals, threshold}
- Cache refresh mechanism: {NONE / on-event / on-call / oracle-refresh / time-bounded}
- Consumers (functions that read the cache): {list}
- Drift impact: {what goes wrong when upstream changes and local cache stays}
- Trust model: {is the upstream admin trusted in this contract's design?}
- Severity: {Critical/High/Medium/Low}
- Mandatory depth domain: external
```

## § Severity guidance

- **Critical**: cached value is a guard (slippage threshold, liquidation factor, pause flag) and upstream change immediately enables custody loss.
- **High**: cached value is an accounting input (fee, share rate, oracle decimals) and drift mis-prices user-fund operations.
- **Medium**: cached value is a non-fund-flow parameter (governance address, metadata) but its drift could be exploited or causes operational pain.
- **Low**: cached value is informational.

R10 worst-state severity applies. If the upstream admin is the same as the audited contract's admin (single trust domain), the severity floor is the trust model the docs commit to — not lower.

## § Hard rule

Every MUTABILITY_DRIFT_CANDIDATE row is a mandatory depth target. The depth agent in iter 1 (external domain) MUST either produce a finding or `CLEARED(depth)` with one of:
- The cache is refreshed by an on-event mechanism the agent verified.
- The trust model in `design_context.md` explicitly delegates the parameter to the upstream admin (e.g., "we accept Aave governance changes").
- The cached value is operationally inconsequential after a documented re-init step.

## § Cross-references

- Pairs naturally with `~/.valves/rules/symmetric-pairs.md` Sweep 5 (Hidden External Dependency) and `~/.valves/rules/admin-setter-validation.md` Check 4 (Active-Flag Desync).
- Findings in this category often feed `BP-FAMILY-IBC` breakpoints in `~/.valves/rules/system-breakpoints.md` when the drift makes the cached value the absorber for an upstream change.
