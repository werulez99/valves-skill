<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# External Protocol Limits

Source-of-truth for the **External Platform Limit Scan** run by Propagation P1 Agent (Phase 4a.5.c, Task 3). Output: `{scratchpad}/external_platform_limits.md`. Flags `OVERFLOW_CANDIDATE` for unbounded payload-aggregation paths.

## Purpose

Cross-protocol and off-chain integrations have hard payload / size / cost limits. When an in-scope function aggregates user-controlled data into a payload that is then handed to a keeper / relayer / bridge, that function CAN block itself if the aggregated payload exceeds the platform's limit. The result: griefing, DoS, or a permanent block on the affected state path.

This scan computes the maximum encoded payload size symbolically and compares it to the platform limit.

## § In-scope function patterns

Any function whose output (return value, emitted event, or stored payload) feeds an off-chain process bounded by a platform limit:

- **Chainlink Automation**: `checkUpkeep(bytes calldata)` returns `(bool, bytes)` — the bytes ride into `performUpkeep`.
- **LayerZero**: `lzReceive(...)` and any function building the encoded message to `_lzSend`.
- **Chainlink CCIP**: `ccipReceive(...)` and any function building a message to `IRouterClient.ccipSend`.
- **Wormhole**: `publishMessage(uint32 nonce, bytes payload, uint8 consistencyLevel)`.
- **Axelar**: `_executeWithToken` / payload to gateway.
- **Hyperlane**: `dispatch(...)` payload bytes.
- **EIP-712 / multisig batches**: `execTransaction` calldata size.
- **Custom keeper integrations**: any function whose output a documented keeper consumes.

## § Reference Table (limits)

| Platform | Field | Practical limit | Source |
|---|---|---|---|
| Chainlink Automation | `performData` (returned by checkUpkeep) | ~5,000 bytes (varies by network) | Chainlink Automation docs § Limits |
| LayerZero v2 | `_message` payload | depends on dvn config / executor; ~10 KB practical, hard limit per OApp | LZ messaging tutorial |
| Chainlink CCIP | `EVM2AnyMessage.data` | 50,000 bytes (Mainnet); `tokenAmounts` ≤ 5 | Chainlink CCIP service limits |
| Wormhole | `payload` in publishMessage | bounded by guardian relay; no fixed per-message limit but VAA size practical limit ~30 KB | Wormhole design doc |
| Axelar | gateway `payload` | varies per chain; 100 KB practical | Axelar gateway docs |
| Hyperlane | `_messageBody` | ~2 KB practical (consumer-defined) | Hyperlane mailbox |
| EIP-712 / Safe batches | `execTransaction` calldata | block gas-limited (~30M gas → ~50 KB practical) | derived |

> Numbers above are practical guidance for symbolic comparison. The agent may consult upstream docs at audit-time if the codebase pins a specific protocol version.

## § Symbolic max-payload computation

For each in-scope function:

1. Identify every input that participates in the encoded payload (function args, storage variables read into the payload, loop iterands).
2. For each loop that appends to the payload, identify the **iterand bound**: is it a constant, a storage variable, a function arg, or unbounded?
3. For each unbounded iterand, attempt to find a runtime cap (`require(N <= MAX)`, modifier-enforced bound).
4. Compute the symbolic maximum: `payload_bytes = sum(per_iter_size × max_iter_count)` for each loop, plus fixed-size headers/footers.
5. Compare to the platform limit from the Reference Table.

## § OVERFLOW_CANDIDATE flag

Flag when ANY of:

- The symbolic max payload exceeds the platform limit.
- The symbolic max is unbounded (no runtime cap on at least one iterand).
- The function's caller can enlarge the payload via a state mutation (e.g., adding subscribers to an array that's later iterated into the payload).

For each flagged location, write:

```markdown
## OVERFLOW_CANDIDATE — {ContractName}.{functionName}
- Platform: {Chainlink Automation / LayerZero / CCIP / Wormhole / ...}
- Platform limit: {N bytes from Reference Table}
- Symbolic max: {bytes — or UNBOUNDED with iterand identified}
- Iterand source: {storage var / function arg / loop bound source}
- Runtime cap: {one of: NONE / require at line N / governance can change}
- Attacker model: {who can enlarge the payload — untrusted / restricted / admin / time-based}
- Consequence: {DoS on path, griefing, custody-state stuck}
- Severity: {Critical/High/Medium}
- Mandatory depth domain: external
```

## § Output ordering

Write `{scratchpad}/external_platform_limits.md` with:

1. `## Summary` — count of OVERFLOW_CANDIDATE per platform.
2. `## Findings (highest severity first)` — full per-flag block above.
3. `## Cleared (with reasons)` — functions that have a documented cap matching or below the platform limit.
4. `## Inapplicable` — platforms not used in this codebase.

## § Hard rule

Every OVERFLOW_CANDIDATE row is a mandatory depth target in Phase 4b iter 1 (external domain). The depth agent must produce either a finding or `CLEARED(depth)` with a specific argument (e.g., "iterand is bounded by `MAX_SUBSCRIBERS = 100` and per-iter size is 64 bytes → 6,400 bytes < 50,000 byte CCIP limit").

## § Severity guidance

- Unbounded iterand on a path that gates user fund recovery (claim, withdraw) → **High**.
- Bounded but the bound is admin-mutable to exceed the platform limit → **Medium** (governance bug, not adversarial).
- Bounded under the limit, but the bound was set after a contract upgrade and historical state already exceeds it → **High** (immediate brick risk).
- Bounded by an attacker-controllable state mutation (e.g., spam-creating subscribers) → **High** (griefing / DoS).
