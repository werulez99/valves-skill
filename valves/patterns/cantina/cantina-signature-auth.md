# Cantina Signature & Auth Patterns
> Extracted from 279 Cantina confirmed HIGH/MEDIUM findings (16 contests)
> Pattern count: 3
> NOTE: Supplements existing SIG-001..035 from Solodit corpus

---

## CANTINA-SIG-036: hook_data_decoding_mismatch
- **Frequency**: ~6/279 findings
- **Severity**: HIGH
- **Code Shape**: `abi.decode(hookData, (address, uint256, bool))` where encoder uses different type ordering or packing; `_decodeTokenOut(data)` that reads bytes at wrong offset; `usePrevHookAmount` flag decoded but not applied to the correct field in the re-encoded call; chained hooks where hook N's output encoding does not match hook N+1's input decoding
- **Detection Heuristic**:
  1. Identify all hook or callback functions that receive opaque `bytes` data and decode it with `abi.decode`
  2. Trace the encoding site: find where `abi.encode` produces the data that this hook consumes
  3. Compare type lists field-by-field: same types, same order, same packing (packed vs padded)
  4. For chained/composable hooks, trace the output of hook N to the input of hook N+1; verify the encoding format is preserved or correctly transformed at each handoff
  5. Check conditional paths: if a flag like `usePrevHookAmount` changes which fields are populated, verify the decoder handles both paths
- **Failure Mode**: Hook receives data encoded with `(address, uint256, bool)` but decodes as `(uint256, address, bool)`, reading the address as a uint and vice versa. The decoded values are nonsensical: wrong token address causes revert or sends to wrong recipient, wrong amount causes over/under-payment. In chained hooks, hook N outputs data with field X at offset 32 but hook N+1 reads field X at offset 64, silently using stale or zero data. Partial repay hooks that decode the full repay struct receive truncated data and revert
- **Common Contexts**: DeFi aggregator hook systems (Superform-style), composable action frameworks, cross-protocol router hooks, any system where opaque bytes are passed between independently-developed components

---

## CANTINA-SIG-037: merkle_proof_leaf_construction_mismatch
- **Frequency**: ~3/279 findings
- **Severity**: HIGH
- **Code Shape**: `leaf = keccak256(abi.encodePacked(account, amount))` on one chain but `leaf = keccak256(abi.encode(account, amount))` on another; `MerkleProof.verify(proof, root, leaf)` where `leaf` is double-hashed on one side (`keccak256(abi.encodePacked(keccak256(...)))`) and single-hashed on the other; inverted proof verification `require(!MerkleProof.verify(...))` instead of `require(MerkleProof.verify(...))`
- **Detection Heuristic**:
  1. Locate all Merkle proof verification calls (`MerkleProof.verify`, `MerkleProof.verifyCalldata`)
  2. Trace the leaf construction: identify every field included in the leaf hash, the encoding method (`encode` vs `encodePacked`), and the hashing rounds (single vs double keccak256)
  3. Find the corresponding leaf construction on the proof-generation side (off-chain script, source chain contract, oracle)
  4. Compare field-by-field: same fields, same order, same encoding, same hash rounds
  5. Check the boolean polarity of the verification: `require(verify(...))` not `require(!verify(...))`
- **Failure Mode**: Source chain constructs Merkle leaf with `abi.encodePacked(user, amount, chainId)` but destination chain constructs leaf with `abi.encode(user, amount)` (missing chainId, different encoding). Every proof fails verification, permanently DoS-ing the claim function. Alternatively, inverted verification logic (`!verify`) causes every invalid proof to pass and every valid proof to fail, allowing arbitrary claims. Cross-chain airdrop or reward claims become permanently broken with no recovery path
- **Common Contexts**: Cross-chain claim systems, airdrop distributors, governance vote verification, any protocol using Merkle proofs for state verification between two independently-deployed components

---

## CANTINA-SIG-038: permit_nonce_and_validity_edge_cases
- **Frequency**: ~3/279 findings
- **Severity**: MEDIUM
- **Code Shape**: `Permit2.permitTransferFrom(permit, transferDetails, owner, signature)` where `permit.nonce` uses sequential nonces but Permit2 expects bitmap nonces; `validUntil == 0` treated as expired instead of infinite validity; `batch.length` != actual transfer count causing array mismatch
- **Detection Heuristic**:
  1. Identify all Permit2 or EIP-2612 permit integrations
  2. For Permit2: verify nonce type matches (sequential `SignatureTransfer` vs bitmap `AllowanceTransfer`); check that `nonce` is not reused or skipped across batch operations
  3. Check validity window handling: does `validUntil == 0` mean "no expiry" (ERC-4337 convention) or "already expired" (timestamp comparison `block.timestamp <= 0`)
  4. For batch permits: verify the declared batch size matches the actual number of transfers; check that token addresses in the permit match the actual tokens being transferred
  5. Test: submit permit with `validUntil = 0`, verify it is accepted (infinite validity) not rejected
- **Failure Mode**: Protocol uses sequential nonces for Permit2 `SignatureTransfer` but constructs the wrong nonce value, causing every permit after the first to fail with "invalid nonce." Signatures with `validUntil = 0` (intended as infinite validity per ERC-4337) are rejected because the validator compares `block.timestamp <= 0` which is always false. Batch permit declares 3 transfers but only 2 token approvals exist, causing an array out-of-bounds revert on the third transfer
- **Common Contexts**: DeFi protocols integrating Uniswap Permit2, meta-transaction relayers, account abstraction validators, any protocol accepting third-party-signed approvals

---
