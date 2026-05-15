<!-- RECONSTRUCTED FROM PROVIDED DESIGN — not original recovered file -->

# Reference Bundle Manifest (v1.7-PATCH3 — PATCH 5: minimal scaffold)

Index of canonical fork-reference source files bundled at `~/.valves/references/{parent_name}.{ext}`. Read by Phase 1.5 Reference Diff-Audit Agent (per `~/.valves/rules/reference-diff-audit.md` § Reference resolution) when neither a local vendored copy nor a fetchable URL is available.

> **STATE FILE — RECONSTRUCTED SCAFFOLDING.** This manifest starts empty. Reference files are added one at a time by the user (or by future explicit reference-bundle population work) when an audit hits a fork that can't be resolved otherwise. This patch deliberately does NOT fetch or invent reference files — only the schema. Adding entries is a manual, version-controlled act.

---

## § Schema

```markdown
| Parent name | File | Source | Version | Hash (sha256) | License | Last verified | Notes |
|---|---|---|---|---|---|---|---|
| openzeppelin-erc4626 | openzeppelin-erc4626.sol | github.com/OpenZeppelin/openzeppelin-contracts | v5.0.2 | abc123... | MIT | 2026-01-15 | Pinned to v5.0.2 mainline; if a fork targets 4.x, manually add openzeppelin-erc4626-4x.sol |
```

Field definitions:
- **Parent name** — canonical kebab-case identifier the diff-audit agent matches against (e.g., `openzeppelin-erc4626`, `aave-v3-pool`, `uniswap-v3-pool`, `compound-comet`, `balancer-v2-vault`). Must match `~/.valves/rules/reference-diff-audit.md` § Reference resolution lookup keys.
- **File** — filename relative to `~/.valves/references/`. Convention: `{parent-name}.{ext}` where ext is `sol` / `rs` / `move` / `cairo`.
- **Source** — origin URL (github.com path, etherscan-verified contract URL, or other authoritative source).
- **Version** — pinned version tag, commit hash, or release name. Required.
- **Hash (sha256)** — sha256 of the file's content, computed via `sha256sum {file}`. Required for tamper-evidence.
- **License** — SPDX identifier (`MIT`, `Apache-2.0`, `BUSL-1.1`, etc.). Required so audits don't accidentally embed restrictive code.
- **Last verified** — ISO date when the entry was last confirmed against its Source. Audits older than 6 months should re-verify.
- **Notes** — version-specific quirks, related variants, known-divergence audits.

## § Active reference entries

_(none — populated when references are bundled)_

## § Recommended high-frequency parents to populate first (v1.7-PATCH5 PATCH 4)

These five parents account for the majority of fork-shaped audits Valves typically encounters. Populating ANY of them unlocks Phase 1.5 Reference Diff-Audit in audits that fork these references and don't have a vendored copy or fetchable URL. Add them one at a time, manually, when an audit's diff-audit step would benefit.

The list below is a **scaffold of placeholders** — no real hashes, versions, or source URLs are committed here. Each placeholder shows the canonical parent name, expected file naming convention, and the typical canonical source. To activate any row, follow § Adding a reference: download the actual source file at a pinned version, compute its sha256, fill the placeholder fields, and move the row out of this scaffold section into § Active reference entries above.

```markdown
# Placeholders (commented out — fill and move to § Active reference entries above)

# | openzeppelin-erc4626 | openzeppelin-erc4626.sol | github.com/OpenZeppelin/openzeppelin-contracts/blob/<TAG>/contracts/token/ERC20/extensions/ERC4626.sol | <PINNED_TAG> | <SHA256_64_HEX> | MIT | <YYYY-MM-DD> | Vault standard. Most ERC4626 forks deviate at deposit/redeem rounding direction or fee accrual. Diff-audit catches share-inflation reintroduction. |
# | uniswap-v3-pool       | uniswap-v3-pool.sol      | github.com/Uniswap/v3-core/blob/<TAG>/contracts/UniswapV3Pool.sol                                            | <PINNED_TAG> | <SHA256_64_HEX> | BUSL-1.1 | <YYYY-MM-DD> | Concentrated-liquidity AMM core. Forks often modify swap routing, fee tiers, or position math. Diff-audit catches tick-math drift and fee-skim reintroduction. |
# | aave-v3-pool          | aave-v3-pool.sol         | github.com/aave/aave-v3-core/blob/<TAG>/contracts/protocol/pool/Pool.sol                                     | <PINNED_TAG> | <SHA256_64_HEX> | BUSL-1.1 | <YYYY-MM-DD> | Lending pool core. Forks often modify reserve config, e-mode logic, or liquidation. Diff-audit catches LTV / liquidationThreshold caching drift. |
# | compound-comet        | compound-comet.sol       | github.com/compound-finance/comet/blob/<TAG>/contracts/Comet.sol                                             | <PINNED_TAG> | <SHA256_64_HEX> | BSD-3-Clause-Clear | <YYYY-MM-DD> | Comet single-asset borrow market. Forks often modify accrual, supply caps, or governance. Diff-audit catches index-update sequencing changes. |
# | balancer-v2-vault     | balancer-v2-vault.sol    | github.com/balancer/balancer-v2-monorepo/blob/<TAG>/pkg/vault/contracts/Vault.sol                            | <PINNED_TAG> | <SHA256_64_HEX> | GPL-3.0-or-later | <YYYY-MM-DD> | Multi-pool Vault. Forks often modify joinPool/exitPool flows, pool registry, or asset management. Diff-audit catches reentrancy guard bypass and asset-swap-asymmetry. |
```

> **Strict verification semantics still apply**: when activating any of these, all field formats from § Required field formats are mandatory. Empty `<PINNED_TAG>`, `<SHA256_64_HEX>`, or `<YYYY-MM-DD>` will fail the orchestrator's parse-time validation and the entry will be skipped (per `MANIFEST_HASH_FORMAT_INVALID` / `MANIFEST_VERSION_MISSING` / etc. error codes).

> **No real hashes or version pins are committed in this scaffold**. Activation is a manual, version-controlled act per the workflow in § Adding a reference. The scaffold's purpose is to make activation cheap when an audit needs it — kebab-case names, file naming, source URL templates, and license guidance are all pre-populated.

### Why exactly these five

- **Frequency**: across DeFi audits, OpenZeppelin ERC4626, Uniswap V3, Aave V3, Compound Comet, and Balancer V2 are the most-forked references.
- **Diff-audit signal density**: each of these has well-documented attack surfaces (rounding direction, fee accrual, tick math, LTV caching, accrual sequencing, joinPool reentrancy) where forks reintroduce known bug shapes.
- **License compatibility for bundling**: MIT (OZ), BUSL-1.1 (UniV3, Aave V3 — source bundling permitted), BSD-3-Clause-Clear (Comet), GPL-3.0-or-later (Balancer V2 — bundle as source, no derivative-distribution issue for an audit reference). All five can be bundled as source for audit reference purposes; commercial redistribution issues do NOT apply when the bundle is consumed only by the diff-audit agent for comparison.
- **Maintenance signal**: these projects all have stable canonical contract addresses on Etherscan + tagged GitHub releases, so version pinning is reliable.

### What is NOT recommended for this scaffold

Do not add new parents to this scaffold without strong frequency justification. Adding a parent that's only forked rarely creates maintenance overhead (every release of the parent requires manifest re-verification or a `Last verified` staleness flag) without proportional diff-audit value. The five above are the practical Pareto frontier; everything beyond is per-audit on-demand.

## § Resolution priority (consumed by Phase 1.5 reference resolution)

When the diff-audit agent in Phase 1.5 looks up a parent reference, it tries sources in this order:

1. **Local vendored copy** in the audit's project tree (`lib/`, `vendor/`, or `node_modules/`).
2. **URL cited in `design_context.md`** (fetch via WebFetch when allowed).
3. **`~/.valves/references/{parent_name}.{ext}` per this manifest.**

If all three fail, the diff-audit agent logs `"reference unavailable for {parent}"` in `{scratchpad}/diff_audit_log.md` and skips that parent. This is graceful degradation — Phase 1.5 continues for other parents.

## § Adding a reference

To add a new reference (manual, version-controlled act):

1. Identify the canonical source (a verified contract on Etherscan, a tagged release on GitHub, an authoritative deployment).
2. Download the source file. Pin it to a specific version / commit / tag.
3. Verify license compatibility (must be permissive enough to bundle — MIT, Apache-2.0, BSD, BUSL-1.1 source, AGPL where audit uses are permitted).
4. Save to `~/.valves/references/{parent-name}.{ext}` using the kebab-case naming convention.
5. Compute the sha256 hash: `sha256sum ~/.valves/references/{parent-name}.{ext}`.
6. Append a row to the table above with all fields filled.
7. Commit the manifest change in version control (the references directory itself is git-tracked alongside the manifest).

## § Activation checklist (v1.7-PATCH6 PATCH 3 — copy this into your shell when activating a placeholder)

This is the practical operator workflow for activating any of the placeholder rows in § Recommended high-frequency parents to populate first. Copy / paste / fill in. Each step has an explicit pass condition.

```bash
# Set the parent you are activating (kebab-case)
PARENT=openzeppelin-erc4626      # CHANGE to one of: openzeppelin-erc4626 | uniswap-v3-pool | aave-v3-pool | compound-comet | balancer-v2-vault | <your-own>

# Set the file extension (no leading dot)
EXT=sol

# Set the pinned version (tag / commit / release name)
VERSION=v5.0.2                   # MUST be a real pinned version from the upstream project

# Set the source URL (must start with https:// or be 'etherscan-verified:0x...')
SOURCE=https://github.com/OpenZeppelin/openzeppelin-contracts/blob/${VERSION}/contracts/token/ERC20/extensions/ERC4626.sol

# Set the SPDX license identifier (must match the upstream project's actual license)
LICENSE=MIT                       # MUST be a real SPDX ID from https://spdx.org/licenses/

# === Step 1: Download to staging (do NOT overwrite ~/.valves/references/ yet) ===
mkdir -p /tmp/valves-ref-staging
curl -fsSL "${SOURCE/\/blob\//\/raw\/}" -o /tmp/valves-ref-staging/${PARENT}.${EXT}
test -s /tmp/valves-ref-staging/${PARENT}.${EXT} || { echo "DOWNLOAD FAILED — abort, do not activate"; exit 1; }

# === Step 2: License sanity check (verify SPDX in the file matches what you claim) ===
head -5 /tmp/valves-ref-staging/${PARENT}.${EXT} | grep -i "SPDX-License-Identifier" || echo "WARNING: file has no SPDX header — verify license claim manually before activating"

# === Step 3: Compute sha256 ===
HASH=$(sha256sum /tmp/valves-ref-staging/${PARENT}.${EXT} | awk '{print $1}')
echo "Computed sha256: ${HASH}"
# Pass condition: ${HASH} matches regex ^[0-9a-f]{64}$ — check it visually

# === Step 4: Move to active references directory ===
mv /tmp/valves-ref-staging/${PARENT}.${EXT} ~/.valves/references/${PARENT}.${EXT}

# === Step 5: Append the manifest row ===
TODAY=$(date -I)                  # ISO 8601 YYYY-MM-DD
NOTES="<one-line note about this version's quirks; required to be non-empty>"

# Then manually open ~/.valves/references/MANIFEST.md and add this row
# under the § Active reference entries section:
cat <<EOF

| ${PARENT} | ${PARENT}.${EXT} | ${SOURCE} | ${VERSION} | ${HASH} | ${LICENSE} | ${TODAY} | ${NOTES} |

EOF

# === Step 6: Commit version control ===
# git add ~/.valves/references/${PARENT}.${EXT} ~/.valves/references/MANIFEST.md
# git commit -m "Activate ${PARENT} reference at ${VERSION}"

# === Step 7: Validate (orchestrator-side check) ===
# Phase 1.5 Reference Diff-Audit at audit time will:
#   - re-compute sha256 of ~/.valves/references/${PARENT}.${EXT}
#   - compare against ${HASH} in MANIFEST.md
#   - skip with REFERENCE_TAMPER_DETECTED if mismatch
# So if you ever modify the file later WITHOUT updating the hash, diff-audit will refuse to use it.
# That is the integrity model. Do not bypass it.
```

### Pass conditions (each step must succeed before moving to the next)

| Step | Pass condition |
|---|---|
| 1. Download | file is non-empty AND `curl` returned 0 |
| 2. License | SPDX header found in file (advisory) OR you've manually verified the license against the upstream project |
| 3. sha256 | output is exactly 64 lowercase hex characters |
| 4. Move | file exists at `~/.valves/references/${PARENT}.${EXT}` |
| 5. Append | manifest row passes all § Required field formats |
| 6. Commit | git working tree is clean after commit |
| 7. Validate | orchestrator's audit-time sha256 verification passes (this is checked at the next audit run, not at activation time) |

### Common activation pitfalls (and how the strict-format gate catches them)

- **Pasted a placeholder hash like `<SHA256_64_HEX>`** -> regex fails `^[0-9a-f]{64}$` -> entry skipped with `MANIFEST_HASH_FORMAT_INVALID`.
- **Forgot to pin a version (`VERSION=main` or `VERSION=master`)** -> not technically a format error, but `Last verified` will quickly show stale; recompute the hash and re-pin to a tag the moment upstream cuts a release.
- **License is a free-form string, not SPDX** -> entry skipped with `MANIFEST_LICENSE_NOT_SPDX`.
- **File is in references/ but not in MANIFEST.md** -> entry skipped with `REFERENCE_UNREGISTERED`. Always update MANIFEST.md when adding files.
- **MANIFEST.md row exists but the file is missing** -> entry skipped with `REFERENCE_FILE_MISSING_FROM_MANIFEST`. Always commit both file + manifest together.

The 6 error codes (defined in § Hash verification) are surfaced to `degradation_log.md` at audit time. Activation failures don't break the pipeline — Phase 1.5 silently falls back to vendored copies and URL fetches per § Resolution priority.

## § Hash verification (consumed at audit time)

The diff-audit agent MUST compute the sha256 of `~/.valves/references/{parent_name}.{ext}` at read time and compare against this manifest's `Hash` column. **Verification is mandatory, not optional** (v1.7-PATCH4 PATCH 7 hardening).

### Verification outcomes

| Condition | Action |
|---|---|
| Hash MATCHES the manifest entry | Proceed: use the bundled reference for diff-audit. |
| Hash MISMATCHES the manifest entry | Log `REFERENCE_TAMPER_DETECTED` to `degradation_log.md` with both the expected hash and the computed hash. SKIP this reference (fall through to § Resolution priority step 3 = unavailable). |
| Manifest entry exists but file is MISSING from `~/.valves/references/` | Log `REFERENCE_FILE_MISSING_FROM_MANIFEST` to `degradation_log.md`. SKIP this reference. |
| File exists at `~/.valves/references/{parent_name}.{ext}` but NOT in manifest | Log `REFERENCE_UNREGISTERED` to `degradation_log.md`. **DO NOT use the file** — unregistered references defeat the integrity model. SKIP this reference. |
| Manifest itself is unreadable / malformed | Log `MANIFEST_PARSE_ERROR` to `degradation_log.md`. SKIP all bundled references for this audit. Phases 1.5 falls back to vendored copies + URL fetch. |
| Hash field in manifest is NOT a valid 64-hex-character sha256 string | Log `MANIFEST_HASH_FORMAT_INVALID` to `degradation_log.md` with the offending entry. SKIP that reference. |

This is a defense against (a) silent file corruption, (b) unauthorized modification of bundled references, (c) accidentally-shipped unregistered files, (d) manifest format errors that could quietly disable the integrity model.

### Required field formats (v1.7-PATCH4 hardening)

- **Parent name**: kebab-case, lowercase, ASCII letters / digits / hyphens only. Pattern: `^[a-z0-9]+(-[a-z0-9]+)*$`. No spaces, underscores, or capitals.
- **File**: must match `{parent_name}.{ext}` where ext is in `{sol, rs, move, cairo, vy}`. The orchestrator validates this filename against the parent name; mismatch -> `MANIFEST_FILENAME_MISMATCH` log + skip.
- **Source**: must be a valid URL (regex: `^https?://`) or a stable identifier (e.g., `etherscan-verified:0x...`). Empty -> skip with `MANIFEST_SOURCE_MISSING`.
- **Version**: REQUIRED non-empty string. A pinned tag (`v5.0.2`), commit hash (`abc123def...`), or release name (`Comet-Mainnet-1.4`). Empty -> skip with `MANIFEST_VERSION_MISSING`.
- **Hash (sha256)**: REQUIRED. Must match regex `^[0-9a-f]{64}$` (lowercase, exactly 64 hex chars). Compute with `sha256sum {file}` (or equivalent). Anything else -> skip with `MANIFEST_HASH_FORMAT_INVALID`.
- **License**: REQUIRED. SPDX identifier from the SPDX license list (`MIT`, `Apache-2.0`, `BSD-3-Clause`, `BUSL-1.1`, `GPL-2.0-or-later`, `AGPL-3.0-only`, `UNLICENSED`, `proprietary`, etc.). Free-form license text -> skip with `MANIFEST_LICENSE_NOT_SPDX`.
- **Last verified**: REQUIRED. ISO 8601 date (`YYYY-MM-DD`). Audits >= 6 months old SHOULD trigger a re-verification reminder (advisory only — not a skip).
- **Notes**: OPTIONAL free-form text. Only field that can be empty.

The orchestrator validates these formats at MANIFEST parse time. Any malformed entry is skipped with the corresponding error code; other valid entries continue to be usable.

## § Why minimal

This patch deliberately ships ONLY the schema. Pre-populating with copies of OpenZeppelin / Aave / Uniswap / Compound source would:
- Bloat the install with code that may not match the user's audit targets (which version? mainline or which release branch?).
- Create a maintenance treadmill (every reference upgrade requires a Valves install update).
- Make license tracking the user's responsibility on someone else's behalf.
- Risk shipping outdated references and creating false-positive diff results.

The right model is: the user populates references as audits demand them, with explicit version pinning and hash verification. This manifest is the structure that makes that practical.

## § Soft-required (Rule 15)

`MANIFEST.md` is a SOFT scaffold. If absent, the diff-audit agent skips § Resolution priority step 3 entirely and degrades gracefully (logs `manifest_absent_skipping_bundled_references`). Pipeline does not block. The slash command's existing `~/.valves/references/{parent_name}.sol` reference resolution behavior is unchanged when this manifest is empty — the directory is empty, so step 3 contributes nothing, and steps 1-2 still run.
