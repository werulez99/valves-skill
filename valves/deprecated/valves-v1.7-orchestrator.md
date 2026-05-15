---
description: "Launch Valves security audit pipeline (v1.7.0). Deferred clustering, structural anomaly harvester, enriched blind spots, planned session split, strongest-exploit + correctness-winner preservation, historical prime mode (benchmark/rerun), mechanical correctness scanners. Usage: /valves [light|core|thorough|compare] [benchmark|rerun]"
---

# Valves Audit Pipeline

> **CRITICAL RULE 1 — COMPLETE_A BOUNDARY (Thorough mode, compaction-proof)**
>
> In Thorough mode, after depth iteration 1 + confidence scoring completes (row 22), the orchestrator writes the COMPLETE_A handoff bundle, rotates the scratchpad (`.audit_scratchpad` → `.audit_session_a`), creates a fresh `.audit_scratchpad` with only allowlisted handoff files, writes `HALT_AFTER_COMPLETE_A.md`, and **STOPS THE RUN**. No Phase 4b iter 2, no chain analysis, no verification, no report generation — NOTHING past row 22 executes in Session A. Session B runs in a FRESH conversation. This rule is NON-NEGOTIABLE and survives context compaction. Before advancing to ANY phase after confidence scoring, check: `if file_exists("{SCRATCHPAD}/HALT_AFTER_COMPLETE_A.md") → HALT IMMEDIATELY, re-emit the SESSION A COMPLETE banner, do NOT proceed`.

> **CRITICAL RULE 2 — SESSION B ISOLATION (Thorough mode, physical enforcement)**
>
> In Session B (before cross-session consensus), the orchestrator and ALL agents MUST NOT read any file under `{PROJECT_ROOT}/.audit_session_a/`. This directory contains Session A's analytical artifacts (findings, hypotheses, attack thesis, depth analysis, verdicts, confidence scores, reports). Reading them before consensus defeats the fresh-eyes architecture. The ONLY files Session B may read are those in `{SCRATCHPAD}/SESSION_B_READ_SCOPE.md` allowlist + source code. Violation = `SESSION_B_ISOLATION_BREACH` → INVALID FINALIZATION. The cross-session consensus step (Phase 5.6.1+) is the SOLE legal accessor of `.audit_session_a/` artifacts.

Valves is an extended audit pipeline built on Plamen. It inherits Plamen's phases and adds architectural artifacts and agents that drive the pipeline toward convergence rather than volume.

## Valves additions

**Agents**:
- **Reference Diff-Audit Agent** (Phase 1.5): triggered by fork-ancestry, diffs the fork against its reference function-by-function and emits a Tier A/B/C global prioritization table. See `~/.valves/rules/reference-diff-audit.md`.
- **Economic Incentive Agent** (Phase 4b): models actor incentives and finds extractable value. Emits `[EI-THEORY]`, `[EI-TRACE]`, `[EI-SIM]` tagged findings. See `~/.valves/rules/economic-incentive-audit.md`.
- **Bug-Class Propagation** (two passes): P1 structural sweep in Phase 4a.5 (pre-depth hints), P2 rich propagation in Phase 4b (post-confirm, cluster-scoped). See `~/.valves/rules/bug-class-propagation.md`.
- **Thesis Synthesis Agent** (Phase 4b post-iter-1): updates `attack_thesis.md` v1 -> v2. See `~/.valves/rules/attack-thesis.md`.

**Mandatory new artifacts**:
- `attack_thesis.md` (v1/v2/v3) -> committed attack paths, updated through the pipeline. See `~/.valves/rules/attack-thesis.md`.
- `bug_class_registry.md` (global, persistent) + `finding_classification.md` (pre-depth, per-audit) + `root_cause_clusters.md` (post-depth, per-audit) -> finding canonicalization with deferred clustering (v1.7). See `~/.valves/rules/bug-class-registry.md`.
- `candidate_seeds.md` (per-audit) -> mechanical structural anomaly seeds from 8 sweeps (v1.7-PATCH expanded the original 5 sweeps to 8: added Sweep 6 RECIPIENT, Sweep 7 MIRROR-ACCT, Sweep 8 EMERGENCY).
- `system_breakpoints.md` -> system-level failure modes + first-loss paths. See `~/.valves/rules/system-breakpoints.md`.
- `diff_audit_tiers.md` -> Tier A/B/C global table from diff-audit agents.
- `verification_priority_queue.md` -> EV-ranked Phase 5 queue. See `~/.valves/rules/verification-priority-queue.md`.
- `audit_negative_results.md` (per-audit) + `negative_results.md` (global, persistent) -> "considered and cleared" memory. See `~/.valves/rules/negative-results.md`.
- `verification_inheritance.md` -> cluster PoC inheritance tracking.

**Modified scoring**: Phase 4 now emits both `composite_reality` and `composite_report` alongside the legacy composite. Quadrant routing drives iteration 2 decisions. See `~/.valves/rules/phase4-confidence-scoring.md`.

All other Plamen behavior is preserved. When this document references files at `~/.claude/rules/` or `~/.plamen/rules/`, those are Plamen's shared references. Valves' additions live at `~/.valves/rules/`.

## Step 0: Interactive Setup Wizard

**Shortcut handling**: Parse `$ARGUMENTS` for pre-filled values:
- If it contains "light", "core", or "thorough", set `MODE` accordingly.
- If it contains an absolute path (e.g., `D:\...` or `/home/...`), set `PROJECT_PATH` to that path. Otherwise use cwd.
- If it contains `docs:` followed by a path or URL, set `DOCS_PATH` to that value and skip Step 0c.
- If it contains `nodocs`, set `DOCS_PATH` to empty and skip Step 0c.
- If it contains `network:` followed by a network name (e.g., `ethereum`, `arbitrum`, `optimism`, `base`, `polygon`, `bsc`, `avalanche`, or an RPC URL), set `NETWORK` to that value. Used for production verification and fork testing.
- If it contains `scope:` followed by a file path, set `SCOPE_FILE` to that path. The file should list in-scope contracts/files.
- If it contains `notes:` followed by text (up to end of arguments or next known prefix), set `SCOPE_NOTES` to that text. Passed to recon as additional audit context (e.g., "focus on vault module, ignore governance").
- If it contains `proven-only:` followed by `true` (or just `proven-only: true`), set `PROVEN_ONLY = true`. When enabled, findings whose best evidence is `[CODE-TRACE]` (no executed PoC or fuzzer counterexample) are capped at Low severity in the report. Default: false.
- If it contains `wrapper-launch`, set `LAUNCHED_FROM_WRAPPER = true`. The user already confirmed the launch in the terminal wrapper -> skip Step 0d (cost estimate + confirmation) entirely and jump directly to Step 1 (language detection). Do NOT show a second confirmation prompt.
- If MODE, PROJECT_PATH, DOCS_PATH (or nodocs), AND `proven-only:` are all resolved AND `wrapper-launch` is present, skip the ENTIRE wizard -> jump directly to Step 1 (language detection). No cost estimate, no confirmation.
- If MODE, PROJECT_PATH, DOCS_PATH (or nodocs), AND `proven-only:` are all resolved but NO `wrapper-launch`, skip the wizard -> jump to "Step 0d: Cost Estimate + Launch Confirmation".
- If MODE, PROJECT_PATH, and DOCS_PATH (or nodocs) are resolved but `scope:` and `proven-only:` are NOT specified, skip to Step 0c.5 (scope selection).
- If MODE is set but docs status is unknown (no `docs:` and no `nodocs`), skip to Step 0c only.
- If `$ARGUMENTS` contains "compare", jump directly to the compare flow (Step 0e). If it also contains `report:` followed by a file path, set `REPORT_PATH`. If it contains `ground_truth:` followed by a file path, set `GROUND_TRUTH_PATH`. If both are set, skip the interactive file selection in Step 0e and proceed directly.
- If `$ARGUMENTS` contains `benchmark` or `rerun`, set `HISTORICAL_PRIME_MODE = true`. Historical Prime mode ingests prior audit reports from `AUDIT_REPORTS/`, `reports/`, `audits/`, or project-root `*audit*.md` / `*report*.md` / `*final*.md` files, and seeds the current run with their findings as regression-detection inputs. See `~/.valves/rules/historical-prime.md`. Default: OFF.
- If `$ARGUMENTS` contains `prime:` followed by a path, set `HISTORICAL_PRIME_MODE = true` AND `PRIME_PATH = {path}` -> only the specified path is ingested.
- If `$ARGUMENTS` contains `fresh-run` or `ignore-checkpoint`, set `FORCE_SESSION_A = true`. This bypasses Session B resume even if `session_checkpoint.md` exists (see Step 0-pre).
- If `$ARGUMENTS` contains `legacy-resume`, set `FORCE_LEGACY_RESUME = true`. This bypasses run_state.json and uses legacy checkpoint routing. Manual escape hatch for corrupt run_state.json recovery (see Step 0-pre, Patch 2).
- If `$ARGUMENTS` is empty, run the full interactive wizard starting at Step 0a.

### Step 0a: Banner + Toolchain Check + Mode Selection

First, output the banner as text (no tool calls):

```
===   === ====== ===     ===   ===================
===   ==============     ===   ===================
===   ==============     ===   =========  ========
==== ===============     ==== ==========  ========
 ======= ===  =========== ======= ================
  =====  ===  ===========  =====  ================
```

**Valves Web3 Security Auditor** v1.7.0 (built on Plamen v1.1.8)

### Version Check (MANDATORY -> run before toolchain probe)

Read both VERSION files and compare against the version in your CLAUDE.md context:

```bash
VALVES_VER=$(cat ~/.valves/VERSION 2>/dev/null || echo "unknown")
PLAMEN_VER=$(cat ~/.plamen/VERSION 2>/dev/null || cat ~/.claude/VERSION 2>/dev/null || echo "unknown")
echo "Valves: $VALVES_VER  |  Plamen base: $PLAMEN_VER"
```

The header of this prompt says `Valves v1.7.0 (built on Plamen v1.1.8)`. If either version differs from what you see on disk, warn the user:

> **Version mismatch detected.** This prompt claims Valves v1.7.0 / Plamen v1.1.8 but your installed versions are Valves v{valves_ver} / Plamen v{plamen_ver}. Run `cd ~/.valves && git pull && valves install` (or the Plamen equivalent) to update. Proceeding with stale rules may cause wrong agent counts or skipped pipeline steps.

**Do NOT skip this check.** A version mismatch between Valves and its Plamen base means the orchestrator rules in CLAUDE.md are out of sync with the prompts, skills, and templates on disk.

Then run a quick toolchain probe (via Bash, all in one command):

```bash
export PATH="$HOME/.foundry/bin:$HOME/.local/share/solana/install/active_release/bin:$HOME/.avm/bin:$HOME/.cargo/bin:$HOME/.aptoscli/bin:$HOME/.local/bin:$HOME/go/bin:$PATH" && \
echo "Toolchain:" && \
echo -n "  Required: " && \
(command -v claude >/dev/null 2>&1 && echo -n "->claude " || echo -n "->claude ") && \
(command -v python >/dev/null 2>&1 && echo -n "->python " || (command -v python3 >/dev/null 2>&1 && echo -n "->python " || echo -n "->python ")) && \
(command -v npx >/dev/null 2>&1 && echo -n "->npx " || echo -n "->npx ") && \
(command -v git >/dev/null 2>&1 && echo -n "->git" || echo -n "->git") && echo "" && \
echo -n "  EVM:      " && \
(command -v forge >/dev/null 2>&1 && echo -n "->forge " || echo -n "->forge ") && \
(command -v slither >/dev/null 2>&1 && echo -n "->slither " || echo -n "->slither ") && \
(command -v medusa >/dev/null 2>&1 && echo -n "->medusa" || echo -n "->medusa") && echo "" && \
echo -n "  Solana:   " && \
(command -v solana >/dev/null 2>&1 && echo -n "->solana " || echo -n "->solana ") && \
(command -v anchor >/dev/null 2>&1 && echo -n "->anchor " || echo -n "->anchor ") && \
(command -v trident >/dev/null 2>&1 && echo -n "->trident" || echo -n "->trident") && echo "" && \
echo -n "  Move:     " && \
(command -v aptos >/dev/null 2>&1 && echo -n "->aptos " || echo -n "->aptos ") && \
(command -v sui >/dev/null 2>&1 && echo -n "->sui" || echo -n "->sui") && echo "" && \
echo -n "  Soroban:  " && \
(command -v stellar >/dev/null 2>&1 && echo -n "->stellar " || echo -n "->stellar ") && \
(cargo scout-audit --version >/dev/null 2>&1 && echo -n "->scout" || echo -n "->scout") && echo ""
```

Display the output to the user. If any required tools (claude, python, npx, git) show ->, warn:
> **Warning**: Missing required tools. Run `plamen setup` in your terminal to install them.

If optional tools are missing, note briefly:
> Optional tools with -> are not installed -> the pipeline degrades gracefully but coverage may be reduced. Run `plamen setup` to install.

> **Recommendation**: For production Valves Security audits, use **Thorough**. Light/Core are retained for smoke tests, triage, and budget-limited runs. For lightweight audits without strict enforcement, use Plamen directly.

Then proceed to mode selection using `AskUserQuestion` with previews:

```
AskUserQuestion(questions=[{
  question: "Which audit mode would you like to run?",
  header: "Mode",
  multiSelect: false,
  options: [
    {
      label: "Light (Pro plan)",
      description: "Lightweight audit -> all Sonnet agents, fits Pro rate limits",
      preview: "~22-26 agents (all Sonnet/Haiku -> no Opus)\n\nPipeline:\n  Recon (2) -> Breadth (3-4)\n  -> Inventory + Classification + Thesis v1 (3 sonnet)\n  -> Depth (4 merged) -> Chain (1)\n  -> Verification Priority Queue (EV-ranked)\n  -> Verify Medium+ w/ orphan reserve\n  -> Full Clustering (post-depth) -> Thesis v3 + cluster_instance_map\n  -> Report ALL (2)\n\nReports all severities. PoC verification targets Medium+.\n\nSkips:\n  · RAG meta-buffer + fork ancestry\n  · Phase 4a.5 breakpoints + P1 propagation + Structural Anomaly Harvester\n  · Semantic invariants (use Core for complex state)\n  · Niche agents\n  · Confidence scoring + RAG Sweep\n  · Economic Incentive + Thesis v2 + P2 propagation\n  · Invariant/Medusa fuzz\n\nBest for: Pro plan, codebases < 3000 lines"
    },
    {
      label: "Core (Recommended)",
      description: "Standard audit -> reports all severities, PoC-verifies Medium+",
      preview: "~38-58 agents (requires Max plan)\n\nPipeline:\n  Recon (4, RAG) -> Diff-Audit Tier A/B/C\n  -> Breadth (5-9)\n  -> Inventory + Classification + Thesis v1 (3 sonnet)\n  -> Semantic Invariants + Breakpoints + P1 + Harvester (4 parallel)\n  -> Depth iter 1 + Full Clustering (post-depth)\n  -> Economic + Thesis v2 + P2 propagation\n  -> Chain (cluster-scoped)\n  -> Verification Priority Queue (EV w/ orphan reserve)\n  -> Verify Medium+ w/ cluster inheritance\n  -> Thesis v3 + negative-result promotion\n  -> cluster_instance_map -> Report ALL\n\nReports all severities (Low/Info included).\nPoC verification targets Medium+ findings.\n\nSkips:\n  · Breadth re-scan (3b/3c)\n  · Depth iterations 2-3\n  · Design stress testing\n  · Invariant fuzz campaign\n  · Fuzz variants in verification\n\nScoring: 2-axis (legacy composite) + reality/report split (Valves)"
    },
    {
      label: "Thorough",
      description: "Deep audit -> iterative depth, fuzz variants, re-scan",
      preview: "~53-118 agents (requires Max plan)\n\nPipeline:\n  Recon (4, full RAG) -> Diff-Audit Tier A/B/C\n  -> Breadth (5-9) -> Inventory (1 sonnet)\n  -> Re-scan (2 iters) -> Per-contract -> Inventory Merge (haiku)\n  -> Gate + Classification + Thesis v1 (3 agents, after merge)\n  -> Semantic Invariants (Pass 1+2) + Breakpoints + P1 + Harvester (4 parallel)\n  -> Depth iter 1-3 (Devil's Advocate) + Full Clustering (post-depth)\n  -> Economic (2 opus) + Thesis v2 + P2 propagation (up to 10)\n  -> Niche agents (up to 8) -> Chain (cluster-scoped, iter 2)\n  -> Verification Priority Queue (EV w/ orphan reserve)\n  -> Verify ALL severities w/ cluster inheritance + fuzz\n  -> Skeptic-Judge for HIGH/CRIT\n  -> Thesis v3 + negative-result promotion\n  -> cluster_instance_map -> Report ALL\n\nIncludes:\n  · Breadth re-scan + per-contract analysis (interleaved after initial inventory)\n  · Structural Anomaly Harvester (8 mechanical code sweeps, v1.7-PATCH)\n  · Deferred clustering (post-depth, evidence-aware)\n  · Invariant fuzz campaign (EVM)\n  · Medusa stateful fuzzing (EVM, if installed)\n  · Design stress testing (unconditional)\n  · Skeptic-Judge adversarial verification (HIGH/CRIT)\n  · Fuzz variants in verification\n  · Low/Info findings verified\n  · Cross-batch consistency check\n\nScoring: 4-axis (Evidence, Consensus, Quality, RAG) + reality/report split"
    },
    {
      label: "Compare",
      description: "Diff a past Valves/Plamen report against a ground truth report",
      preview: "Post-audit improvement mode\n\nYou provide:\n  · Your Valves or Plamen audit report\n  · A ground truth / reference report\n\nOutputs:\n  · Finding alignment matrix\n  · Recall & precision metrics\n  · Root cause classification\n  · Targeted methodology improvements"
    }
  ]
}])
```

Set `MODE` based on the user's selection. If "Compare" is selected, jump to Step 0e.

### Step 0b: Target Project

Use `AskUserQuestion` to confirm the project directory:

```
AskUserQuestion(questions=[{
  question: "Is this the project you want to audit?",
  header: "Target",
  multiSelect: false,
  options: [
    {
      label: "Yes, use {cwd}",
      description: "Audit the current working directory"
    },
    {
      label: "No, let me specify",
      description: "I'll provide a different project path"
    }
  ]
}])
```

If the user selects "No" or "Other", ask them to type the path. Set `PROJECT_PATH` accordingly.

### Step 0c: Documentation

Use `AskUserQuestion` to ask about documentation:

```
AskUserQuestion(questions=[{
  question: "Do you have project docs that describe trust roles or actor permissions? (used to calibrate finding severity -> e.g., 'admin is a 5/7 multisig with timelock')",
  header: "Docs",
  multiSelect: false,
  options: [
    {
      label: "No docs",
      description: "Trust roles will be inferred from code patterns (onlyOwner, role modifiers, etc.)"
    },
    {
      label: "Yes, local files",
      description: "Whitepaper, spec, or design doc with trust/role information"
    },
    {
      label: "Yes, a URL",
      description: "Link to docs describing trust model or actor permissions"
    }
  ]
}])
```

If the user selects local files or URL, ask them to provide the path or URL. Store as `DOCS_PATH`.

### Step 0c.5: Scope

Use `AskUserQuestion` to ask about scope constraints:

```
AskUserQuestion(questions=[{
  question: "Do you want to limit the audit scope?",
  header: "Scope",
  multiSelect: false,
  options: [
    {
      label: "Full project",
      description: "Audit everything in the target directory"
    },
    {
      label: "Scope file",
      description: "I have a scope.txt listing specific files/contracts"
    },
    {
      label: "Scope notes",
      description: "I'll describe the focus areas in plain text"
    }
  ]
}])
```

If the user selects "Scope file", ask them to provide the path. Store as `SCOPE_FILE`.
If the user selects "Scope notes", ask them to describe the focus. Store as `SCOPE_NOTES`.
If "Full project", leave both empty.

### Step 0c.6: Proven-Only Mode

Use `AskUserQuestion` to ask about severity strictness:

```
AskUserQuestion(questions=[{
  question: "Enable proven-only mode? (findings without executed PoC evidence are capped at Low severity -> useful for benchmark comparisons)",
  header: "Proven-Only",
  multiSelect: false,
  options: [
    {
      label: "No (default)",
      description: "Standard severity rules -> manual code traces can support any severity"
    },
    {
      label: "Yes",
      description: "Unproven findings ([CODE-TRACE] only) capped at Low"
    }
  ]
}])
```

If "Yes", set `PROVEN_ONLY = true`.

### Step 0d: Cost Estimate + Launch Confirmation

Before starting the pipeline, get a cost estimate by calling `plamen.py`'s `estimate_cost()` function directly via Bash. Do NOT calculate costs manually -> the Python function is the single source of truth.

#### Step 0d.1: Get Estimate

Run via Bash:

```bash
PY_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null) && "$PY_CMD" ~/.claude/plamen.py --estimate "{PROJECT_PATH}" {MODE} {SCOPE_ARGS}
```

Where `{SCOPE_ARGS}` is:
- `--scope "{SCOPE_FILE}"` if SCOPE_FILE is set
- `--scope-notes "{SCOPE_NOTES}"` if SCOPE_NOTES is set (and no scope file)
- omitted if neither is set

If `plamen.py --estimate` is not available (old version), use this fallback:

```bash
PY_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null) && "$PY_CMD" -c "
import sys; sys.path.insert(0, '$HOME/.claude')
from plamen import estimate_cost
import json
r = estimate_cost('{PROJECT_PATH}', '{MODE}', scope_file='{SCOPE_FILE}', scope_notes='{SCOPE_NOTES}')
print(json.dumps(r))
"
```

Parse the JSON output to get: `files`, `lines`, `agents`, `input_mtok`, `output_mtok`, `api_cost`, `pct_pro`, `pct_x5`, `pct_x20`, `scoped`.

#### Step 0d.2: Display Summary + Warnings

Output as a formatted markdown block:

```
**Launch Summary**

| | |
|---|---|
| **Mode** | {Light/Core/Thorough} Audit |
| **Target** | `{PROJECT_PATH}` |
| **Network** | {NETWORK} |  -> only if set
| **Docs** | {docs status or "none"} |
| **Scope** | {SCOPE_FILE basename or "full project"} |  -> only if set
| **Notes** | {SCOPE_NOTES} |  -> only if set
| **Proven-only** | ON -> unproven findings capped at Low |  -> only if true
| **Codebase** | ~{lines} lines, {files} files{" (scoped)" if scoped} |
| **Agents** | ~{agents} |
| **Tokens** | ~{input_mtok}M in / ~{output_mtok}M out |
| **API cost** | ~${api_cost} USD |
| **Pro** | ~{pct_pro}% of weekly allowance |  -> with severity indicator
| **Max x5** | ~{pct_x5}% of weekly allowance |  -> with severity indicator
| **Max x20** | ~{pct_x20}% of weekly allowance |  -> with severity indicator
```

**Severity indicators for plan usage %:**
- **<= 40%**: append `(ok)` -> comfortable headroom
- **41-80%**: append `(!)` -> significant usage, warn the user
- **> 80%**: append `(!!)` -> may exceed weekly allowance, strongly warn

**Warnings** (output after the table):
- If `pct_pro > 80` AND MODE is not "light": `> **Warning**: This audit may exceed your Pro plan's weekly allowance. Consider using Light mode or upgrading to Max.`
- If `pct_x5 > 80`: `> **Warning**: This audit may consume most of your Max x5 weekly allowance. Consider scoping to fewer files or using Core mode.`
- If `pct_pro > 40` AND MODE == "light": `> **Note**: This audit will use a significant portion of your Pro weekly allowance.`
- Always: `> *Rough estimates only. Actual usage varies with protocol complexity and findings count.*`

#### Step 0d.3: Session Capacity Check

Claude Code has no API to query session usage programmatically. The orchestrator asks the user for two values, then computes whether the audit can complete without hitting a session wall.

**Step 0d.3.1**: Ask the user:

```
AskUserQuestion(questions=[
  {
    question: "What is your current session usage %? (check Settings -> Usage)",
    header: "Session Capacity Check",
    multiSelect: false,
    options: [
      { label: "0-10%", description: "Fresh session" },
      { label: "10-30%", description: "Lightly used" },
      { label: "30-50%", description: "Moderate use" },
      { label: "50-70%", description: "Heavy use" },
      { label: "70%+", description: "Near limit" },
      { label: "Skip", description: "Don't check, just launch" }
    ]
  }
])
```

If "Skip" -> proceed to Step 0d.4.

**Step 0d.3.2**: If not skipped, ask for reset time:

```
AskUserQuestion(questions=[
  {
    question: "How long until your current session resets? (shown under 'Current session' in Usage)",
    header: "Session Reset Timer",
    multiSelect: false,
    options: [
      { label: "< 30 min", description: "Resets very soon" },
      { label: "30 min - 1 hr", description: "" },
      { label: "1 - 2 hr", description: "" },
      { label: "2 - 3 hr", description: "" },
      { label: "3 - 4 hr", description: "Nearly full window" },
      { label: "4+ hr", description: "Just reset" }
    ]
  }
])
```

**Step 0d.3.3**: Compute capacity verdict.

Estimated session consumption per mode (% of one full session window):

| Mode | Est. Duration | Est. Session % | Can Survive 1 Reset? |
|------|--------------|----------------|---------------------|
| Light | 30-60 min | 15-25% | Rarely needed |
| Core | 1-2 hr | 40-60% | Sometimes |
| Thorough | 2-4 hr | 70-120% | Usually needed |

Map user's answers to midpoint values:
- Session %: 0-10->5, 10-30->20, 30-50->40, 50-70->60, 70+->80
- Reset time: <30min->0.4h, 30min-1hr->0.75h, 1-2hr->1.5h, 2-3hr->2.5h, 3-4hr->3.5h, 4+hr->4.5h

Compute:

```
session_remaining = 100 - session_pct_midpoint
mode_duration_hr = {light: 0.75, core: 1.5, thorough: 3.0}[MODE]
mode_session_cost = {light: 20, core: 50, thorough: 95}[MODE]
session_window_hr = 5.0  # Max plan session window

# How many resets occur during the audit?
resets_during_run = floor((mode_duration_hr) / max(reset_time_hr, 0.1))

# Total available capacity = current remaining + (resets Ã 100%)
total_available = session_remaining + (resets_during_run * 100)

# Verdict
if total_available >= mode_session_cost * 1.2:
    verdict = "GO"
elif total_available >= mode_session_cost:
    verdict = "TIGHT"
else:
    deficit = mode_session_cost - total_available
    # How long to wait for enough capacity?
    wait_minutes = ceil((deficit / 100) * session_window_hr * 60)
    verdict = "WAIT"
```

**Step 0d.3.4**: Display result:

- **GO**: `> **Session capacity: OK.** ~{session_remaining}% remaining now + {resets_during_run} reset(s) during run = ~{total_available}% total available. Estimated need: ~{mode_session_cost}%. Comfortable headroom.`
- **TIGHT**: `> **Session capacity: TIGHT.** ~{total_available}% available vs ~{mode_session_cost}% needed. The audit may slow down near the end if usage exceeds estimate. Consider waiting {wait_minutes} minutes for more headroom, or proceed and accept possible throttling.`
- **WAIT**: `> **Session capacity: INSUFFICIENT.** ~{total_available}% available vs ~{mode_session_cost}% needed. Recommend waiting ~{wait_minutes} minutes for session reset, or downgrade to {lower_mode} mode (~{lower_cost}% needed).`

If verdict is WAIT, add a "Wait" option to the Step 0d.4 confirmation menu:
```
{ label: "Wait and retry", description: "Wait ~{wait_minutes} min, then re-check" }
```

**Important**: These are rough estimates. Session cost varies significantly with codebase size, findings count, and agent complexity. The check prevents obviously doomed runs, not edge cases. When in doubt, the user decides.

#### Step 0d.4: Confirm

Use `AskUserQuestion` to let the user confirm, go back, or cancel. If the session capacity verdict from Step 0d.3 is WAIT, add a fourth option.

```
options = [
    {
      label: "Yes, launch",
      description: "Start the audit pipeline"
    },
    {
      label: "Go back",
      description: "Change settings"
    },
    {
      label: "Cancel",
      description: "Abort the audit"
    }
]

# Add wait option if session capacity is insufficient
if session_verdict == "WAIT":
    options.insert(2, {
      label: "Wait and retry",
      description: "Wait ~{wait_minutes} min for session reset, then re-check capacity"
    })

AskUserQuestion(questions=[{
  question: "Proceed with the audit?",
  header: "Confirm",
  multiSelect: false,
  options: options
}])
```

- If "Yes, launch" -> proceed to Step 1.
- If "Wait and retry" -> output `Waiting ~{wait_minutes} minutes for session capacity...` and loop back to Step 0d.3 (re-ask session usage and reset time, recompute verdict). Do NOT auto-sleep -> tell the user to come back and re-run when ready.
- If "Go back" -> return to Step 0c.6 (Proven-Only).
- If "Cancel" -> stop, output `Cancelled.` and do not proceed.

### Step 0e: Compare Flow

If the user selected "Compare":
1. If `REPORT_PATH` and `GROUND_TRUTH_PATH` are both set from `$ARGUMENTS`, skip to step 3.
2. Otherwise, use `AskUserQuestion` to ask for both report paths (both must be `.md` files -> PDFs cannot be diffed).
3. Read both files and follow the Post-Audit Improvement Protocol from `~/.claude/rules/post-audit-improvement-protocol.md`.

Do NOT proceed to Step 1.

---

## Step 0-pre: Session Resume Check (v1.7)

Before the wizard runs, check if a prior session's checkpoint exists. This enables the **Planned Session Split**: Session A handles discovery (recon -> depth iter 1 + scoring), Session B handles quality (adversarial depth -> chain -> verification -> report) with genuine independence.

```
// Resolve PROJECT_PATH from $ARGUMENTS or cwd (same logic as shortcut handling)
project_path = resolve_project_path($ARGUMENTS)
checkpoint_file = "{project_path}/.audit_scratchpad/session_checkpoint.md"

// Check for fresh-run override BEFORE checkpoint detection
if $ARGUMENTS contains "fresh-run" or "ignore-checkpoint":
    SESSION = "A"
    // Delete stale halt marker if doing a fresh run
    if file_exists("{project_path}/.audit_scratchpad/HALT_AFTER_COMPLETE_A.md"):
        delete "{project_path}/.audit_scratchpad/HALT_AFTER_COMPLETE_A.md"
    // v1.7-PATCH11: Remove stale session archive if doing a fresh run
    if dir_exists("{project_path}/.audit_session_a"):
        rename("{project_path}/.audit_session_a", "{project_path}/.audit_session_a.bak.{timestamp}")
        // Don't delete — rename to .bak in case user wants to inspect old run
    // Proceed to wizard normally -> checkpoint is ignored, not deleted
    // v1.7-PATCH11: Also delete stale run_state.json on fresh-run
    if file_exists("{project_path}/.audit_scratchpad/run_state.json"):
        delete "{project_path}/.audit_scratchpad/run_state.json"
    goto WIZARD

// === UNIVERSAL RESUME SWEEP (v1.7-PATCH11.1 — Session-B Isolation + Resume Hardening) ===
// Priority: run_state.json > halt marker > checkpoint. run_state.json is the most
// granular state record — it knows the exact step, session, checkpoint_level, and intent.
// See ~/.valves/rules/execution-state.md § R5 for full algorithm.
//
// DISK STATE IS AUTHORITATIVE (v1.7-PATCH11.1):
// run_state.json + mandatory_step_checklist.md + session_checkpoint.md are the source
// of truth for pipeline position, session identity, and checkpoint level. After context
// compaction, session interruption, or usage exhaustion, the orchestrator resumes from
// disk state ONLY. Conversational momentum, remembered prose, and prior-turn context
// do NOT override on-disk state. If disk says COMPLETE_B, the run is done — regardless
// of what the orchestrator "remembers" from earlier in the conversation.

run_state_path = "{project_path}/.audit_scratchpad/run_state.json"
if file_exists(run_state_path):
    // PATCH11-F: existence assertion passed; now read and parse
    run_state_content = read(run_state_path)
    try:
        rs = JSON.parse(run_state_content)
    catch:
        log "FATAL: run_state.json exists but is not valid JSON. State file is corrupt."
        log "Manual recovery options:"
        log "  1. Inspect and fix the JSON manually: {run_state_path}"
        log "  2. Delete run_state.json and restart: rm {run_state_path} && /valves"
        log "  3. Force legacy checkpoint routing (escape hatch): /valves --legacy-resume"
        HALT with halt_reason = "RUN_STATE_CORRUPT"

    // Structural integrity (PATCH11-F: validate required fields before access)
    if rs.version == null OR rs.session == null OR rs.current_phase == null OR rs.checkpoint_level == null:
        log "FATAL: run_state.json missing required fields (version/session/current_phase/checkpoint_level)."
        log "Manual recovery options:"
        log "  1. Inspect and fix the JSON manually: {run_state_path}"
        log "  2. Delete run_state.json and restart: rm {run_state_path} && /valves"
        log "  3. Force legacy checkpoint routing (escape hatch): /valves --legacy-resume"
        HALT with halt_reason = "RUN_STATE_CORRUPT"

    // === SESSION-AWARE ROUTING (PATCH11-A/B/I) ===
    // checkpoint_level drives session routing — not just INTERRUPTED flag
    if rs.checkpoint_level == "COMPLETE_A":
        if rs.session in ["A", "A_RESUMED"]:
            // Fresh Session B entry. Transition session identity BEFORE any work.
            rs.session = "B"
            rs.checkpoint_level = "PARTIAL_B"
            rs.phase_status = "DONE"
            rs.write_ahead.interrupted = false
            rs.halt_reason = null
            rs.last_write_iso = now_iso()
            Write "{project_path}/.audit_scratchpad/run_state.json" (full JSON)
            // Fall through to Session B entry (checkpoint routing below handles this)
            goto SESSION_B_CHECKPOINT_ENTRY

        elif rs.session in ["B", "B_RESUMED"]:
            // Session B resume (was at COMPLETE_A checkpoint but session already B)
            rs.session = "B_RESUMED"
            rs.last_write_iso = now_iso()
            Write "{project_path}/.audit_scratchpad/run_state.json" (full JSON)
            goto SESSION_B_RESUME_FROM_RUN_STATE(rs)

    elif rs.checkpoint_level == "PARTIAL_B":
        // Session B was interrupted. Resume without deleting Session B artifacts.
        rs.session = "B_RESUMED"
        rs.last_write_iso = now_iso()
        Write "{project_path}/.audit_scratchpad/run_state.json" (full JSON)
        goto SESSION_B_RESUME_FROM_RUN_STATE(rs)

    elif rs.checkpoint_level == "COMPLETE_B":
        // Audit fully done. Reruns MUST halt — not continue work.
        // (v1.7-PATCH11.1) Also verify SESSION_B_COMPLETE.md consistency.
        scratchpad = rs.scratchpad or "{project_path}/.audit_scratchpad"
        marker = scratchpad + "/SESSION_B_COMPLETE.md"
        cp_file = scratchpad + "/session_checkpoint.md"
        if file_exists(cp_file):
            cp = Read(cp_file)
            if cp.CHECKPOINT_LEVEL != "COMPLETE_B":
                log "SESSION_B_CHECKPOINT_INCONSISTENCY: run_state.json=COMPLETE_B but session_checkpoint.md={cp.CHECKPOINT_LEVEL}" to violations.md
                HALT: "Inconsistent state: run_state.json and session_checkpoint.md disagree on checkpoint level."
        goto AUDIT_COMPLETE_BANNER

    // === CRASH RECOVERY (write_ahead.interrupted == true) ===
    if rs.write_ahead != null AND rs.write_ahead.interrupted == true:
        print:
        ====================================================================
        CRASH RECOVERY — RESUMING FROM PERSISTED STATE
        ====================================================================
        Last action: {rs.write_ahead.action}
        Phase: {rs.current_phase}
        Status: {rs.phase_status}
        Session: {rs.session}
        Checkpoint: {rs.checkpoint_level}
        ====================================================================

        MODE = rs.mode; SESSION = rs.session; LANGUAGE = rs.language
        PROJECT_ROOT = rs.project_root; SCRATCHPAD = rs.scratchpad

        // Check if interrupted action completed (outputs on disk)
        if rs.active_manifest != null AND file_exists(rs.active_manifest):
            manifest = parse(rs.active_manifest)
            needs_respawn = reconcile_manifest_with_disk(manifest)
            if len(needs_respawn) == 0:
                rs.phase_status = "DONE"; rs.write_ahead.interrupted = false
                rs.last_write_iso = now_iso()
                Write run_state.json (full JSON)
                goto RESUME_AT(rs.current_phase, next_step)
            else:
                print: "Partial: re-spawning {len(needs_respawn)} agents."
                goto RESPAWN_MISSING(rs.current_phase, needs_respawn)

        elif len(rs.expected_outputs) > 0:
            all_valid = true
            for target in rs.expected_outputs:
                if NOT file_exists(target) OR validity_check(target) != VALID:
                    all_valid = false; break
            if all_valid:
                rs.phase_status = "DONE"; rs.write_ahead.interrupted = false
                rs.last_write_iso = now_iso()
                Write run_state.json (full JSON)
                goto RESUME_AT(rs.current_phase, next_step)
            else:
                if rs.resume_metadata.recovery_attempts >= 3:
                    print: "RECOVERY EXHAUSTED: {rs.current_phase}"
                    HALT
                goto RETRY(rs.current_phase)
        else:
            if rs.resume_metadata.recovery_attempts >= 3:
                print: "RECOVERY EXHAUSTED after 3 attempts."
                HALT
            goto RETRY(rs.current_phase)

    // === CLEAN RESUME (phase_status == "DONE") — v1.7-PATCH11.3 HARDENED ===
    elif rs.phase_status == "DONE":
        MODE = rs.mode; SESSION = rs.session; LANGUAGE = rs.language
        PROJECT_ROOT = rs.project_root; SCRATCHPAD = rs.scratchpad

        // (v1.7-PATCH11.3) RESUME ARTIFACT VALIDATION
        // Before resuming, validate artifacts for ALL completed phases.
        // The checklist is the source of truth — re-scan it mechanically.
        checklist_path = "{SCRATCHPAD}/mandatory_step_checklist.md"
        if file_exists(checklist_path):
            checklist = read(checklist_path)
            invalid_rows = []
            for row in parse_checklist(checklist):
                if row.status == "COMPLETE":
                    result = VALIDATE_STEP_COMPLETION(row, row.evidence_artifact, row.producer)
                    if result == FAIL:
                        invalid_rows.append({row: row.id, reason: result.reason})
                        // Downgrade row from COMPLETE to PENDING
                        row.status = "PENDING"
                        row.notes = "RESUME_VALIDATION_FAIL: {result.reason}"

            if len(invalid_rows) > 0:
                print:
                ====================================================================
                RESUME VALIDATION — {len(invalid_rows)} ROW(S) DOWNGRADED
                ====================================================================
                The following rows were marked COMPLETE but failed artifact
                validation on resume (disk-truth supremacy):
                {for r in invalid_rows: "  Row {r.row}: {r.reason}"}

                Resuming from the FIRST invalid row instead of the last phase.
                ====================================================================
                // Find the earliest invalid row and resume from there
                first_invalid = min(r.row for r in invalid_rows)
                rs.current_phase = get_phase_for_row(first_invalid)
                rs.phase_status = "INTENT"
                rs.last_write_iso = now_iso()
                Write "{SCRATCHPAD}/run_state.json" (full JSON)
                // Update checklist with downgraded rows
                Write checklist_path (full file with updated statuses)
                goto RESUME_AT(rs.current_phase, first_invalid)

        print: "Resuming from {rs.current_phase} (last completed: {rs.last_completed_phase})"
        goto RESUME_AT(rs.current_phase, next_step)

    // === FAILED STATE ===
    elif rs.phase_status == "FAILED":
        MODE = rs.mode; SESSION = rs.session; LANGUAGE = rs.language
        PROJECT_ROOT = rs.project_root; SCRATCHPAD = rs.scratchpad
        if rs.resume_metadata.recovery_attempts >= 3:
            print: "RECOVERY EXHAUSTED: {rs.current_phase}"
            HALT
        goto RETRY(rs.current_phase)

// === SESSION B RESUME (PATCH11-B + PATCH11.3: session-aware, preserves Session B artifacts) ===
SESSION_B_RESUME_FROM_RUN_STATE(rs):
    MODE = rs.mode; SESSION = rs.session; LANGUAGE = rs.language
    PROJECT_ROOT = rs.project_root; SCRATCHPAD = rs.scratchpad

    // (v1.7-PATCH11.3) SESSION B ISOLATION RE-SCAN
    // Re-run the leak scan (same denylist as post-rotation) to catch
    // analytical artifacts introduced between conversations.
    // This is the second barrier (post-rotation scan was the first).
    run_session_b_leak_scan(SCRATCHPAD)  // same logic as COMPLETE_A step 1.5 post-rotation cross-check

    // DO NOT delete Session B artifacts — they are legitimate work products.
    // Scan checklist for first incomplete Session-B-owned row.
    // (v1.7-PATCH11.3) Validate existing Session B artifacts on disk
    checklist_path = "{SCRATCHPAD}/mandatory_step_checklist.md"
    if file_exists(checklist_path):
        checklist = read(checklist_path)
        for row in parse_checklist(checklist):
            if row.status == "COMPLETE" AND row.session == "B":
                result = VALIDATE_STEP_COMPLETION(row, row.evidence_artifact, row.producer)
                if result == FAIL:
                    row.status = "PENDING"
                    row.notes = "SESSION_B_RESUME_VALIDATION_FAIL: {result.reason}"
        Write checklist_path (full file)

    // Resume from rs.current_phase (or first incomplete row if current_phase is DONE).
    if rs.write_ahead != null AND rs.write_ahead.interrupted:
        goto CRASH_RECOVERY  // handled above
    else:
        goto RESUME_AT(rs.current_phase, next_step)

// === END PATCH11 RESUME SWEEP — fall through to legacy routing ===

:LEGACY_CHECKPOINT_ROUTING
// === LEGACY CHECKPOINT ROUTING (manual escape hatch only for corrupt run_state.json) ===
// This section is reachable in two cases:
//   (a) run_state.json does NOT exist (pre-PATCH11 run or truly fresh start — legitimate)
//   (b) FORCE_LEGACY_RESUME = true (user explicitly passed --legacy-resume to recover from corrupt state)
// It is NO LONGER reachable via automatic fallback from malformed run_state.json (Patch 2: fail-closed).
if file_exists(run_state_path) AND NOT FORCE_LEGACY_RESUME:
    // run_state.json exists but we somehow reached legacy routing without --legacy-resume.
    // This should not happen after Patch 2 (corrupt state halts). Safety net.
    log "FATAL: Unexpected legacy routing with existing run_state.json. Use --legacy-resume to force."
    HALT with halt_reason = "ILLEGAL_LEGACY_FALLTHROUGH"

// === HALT MARKER DETECTION (v1.7-PATCH10.3 — compaction-proof boundary) ===
// This fires BEFORE checkpoint routing. If the marker exists, Session A reached
// COMPLETE_A but may have failed to halt (context compaction lost the instruction).
// The marker on disk is the ground truth — the orchestrator MUST NOT continue.
halt_marker = "{project_path}/.audit_scratchpad/HALT_AFTER_COMPLETE_A.md"
if file_exists(halt_marker) AND NOT ($ARGUMENTS contains "fresh-run" or "ignore-checkpoint"):
    // Two cases: (a) same conversation that wrote it (compaction recovery),
    //            (b) new conversation (normal Session B entry via checkpoint below)
    // In both cases, if checkpoint == COMPLETE_A → route to Session B (normal path below).
    // If checkpoint is MISSING or PARTIAL_A → Session A failed to write checkpoint after
    // writing the halt marker. Recover: check if handoff bundle is on disk.
    checkpoint_exists = file_exists("{project_path}/.audit_scratchpad/session_checkpoint.md")
    if NOT checkpoint_exists:
        // RECOVERY: halt marker exists but no checkpoint → boundary was reached but
        // checkpoint write failed. Check handoff bundle integrity.
        scratchpad_path = "{project_path}/.audit_scratchpad"
        bundle_ok = file_exists("{scratchpad_path}/coverage_density.md") AND
                    file_exists("{scratchpad_path}/negative_space.md") AND
                    file_exists("{scratchpad_path}/seed_outcomes.md") AND
                    file_exists("{scratchpad_path}/canonical_seed_map.md") AND
                    file_exists("{scratchpad_path}/disagreement_queue.md") AND
                    file_exists("{scratchpad_path}/session_a_to_b_handoff.md")
        if bundle_ok:
            // Bundle is complete — write the missing checkpoint and halt
            Write session_checkpoint.md with status=COMPLETE_A (recovery write)
            print "RECOVERY: HALT_AFTER_COMPLETE_A.md found, handoff bundle present, checkpoint written."
            // Fall through to COMPLETE_A routing below (checkpoint now exists)
        else:
            // Bundle incomplete — Session A hit the boundary but handoff build failed
            print:
            ====================================================================
            HALT MARKER DETECTED — SESSION A INCOMPLETE
            ====================================================================
            HALT_AFTER_COMPLETE_A.md exists but the handoff bundle is incomplete.
            Session A reached the COMPLETE_A boundary but failed to write all artifacts.

            Options:
              /valves thorough fresh-run   # discard and restart entirely

            HALTING. Do NOT proceed.
            ====================================================================
            HALT. Do NOT spawn agents. End the conversation.
    // If checkpoint exists, fall through to normal checkpoint routing below

if file_exists(checkpoint_file):
    checkpoint = Read(checkpoint_file)
    level = checkpoint.CHECKPOINT_LEVEL  // PARTIAL_A | COMPLETE_A | COMPLETE_B (v1.7-PATCH10)

    // === MINIMAL PREFLIGHT (runs for BOTH resume modes) ===
    MODE = checkpoint.MODE
    LANGUAGE = checkpoint.LANGUAGE
    SCRATCHPAD = checkpoint.SCRATCHPAD
    PROJECT_ROOT = checkpoint.PROJECT_ROOT

    // Restore launch-state fields (audit contract from Session A wizard)
    DOCS_PATH = checkpoint.DOCS_PATH
    NETWORK = checkpoint.NETWORK
    RPC_URL = checkpoint.RPC_URL
    SCOPE_FILE = checkpoint.SCOPE_FILE
    SCOPE_NOTES = checkpoint.SCOPE_NOTES
    PROVEN_ONLY = checkpoint.PROVEN_ONLY
    HISTORICAL_PRIME_MODE = checkpoint.HISTORICAL_PRIME_MODE

    // 1. Version check (same as Step 0a)
    VALVES_VER = read(~/.valves/VERSION)
    PLAMEN_VER = read(~/.plamen/VERSION)
    if version_mismatch -> warn user (same logic as Step 0a § Version Check)

    // 2. Toolchain probe (same as Step 0a)
    run toolchain probe (same bash command as Step 0a)

    // 3. Watchdog init (same as Step 0.9)
    if MODE == THOROUGH:
        initialize phase_gate.py watchdog
        if watchdog init fails -> ABORT (same rule as Step 0.9)

    // 4. Verify scratchpad integrity
    ASSERT: mandatory_step_checklist.md exists in SCRATCHPAD
    ASSERT: pipeline_trace.md exists in SCRATCHPAD
    if any missing -> ABORT: "Session A artifacts corrupted. Run fresh: /valves thorough fresh-run"

    // === ROUTE BY CHECKPOINT LEVEL ===

    if level == "PARTIAL_A":
        // Session A is incomplete -> continue discovery, not quality pass
        SESSION = "A_RESUMED"

        print:
        ===   === ====== ===     ===   ===================
        ===   ==============     ===   ===================
        ===   ==============     ===   =========  ========
        ==== ===============     ==== ==========  ========
         ======= ===  =========== ======= ================
          =====  ===  ===========  =====  ================
           SESSION A -> Resuming discovery from {checkpoint.CHECKPOINT_PHASE}

        print: "Last phase completed: {checkpoint.CHECKPOINT_PHASE}"
        print: "Next phase: {checkpoint.NEXT_PHASE}"
        print completed/pending phase list from checkpoint

        // Skip wizard, skip completed phases, resume Session A at NEXT_PHASE
        // Session A behavioral rules apply (normal pipeline, not quality pass)
        goto NEXT_PHASE

    elif level == "COMPLETE_A":
        // Session A finished discovery -> enter quality pass
        SESSION = "B"

        // v1.7-PATCH10.3: HALT_AFTER_COMPLETE_A.md should exist (Session A wrote it).
        // Session B does NOT delete it — § E only fires when SESSION == "A".
        // Its presence is expected and harmless in Session B (SESSION == "B" bypasses § E).

        // === v1.7-PATCH11: Strict Session B Resume Contract ===
        SESSION_A_ARCHIVE = "{PROJECT_ROOT}/.audit_session_a"

        // CHECK 1: Session A archive must exist (scratchpad rotation happened)
        if NOT dir_exists(SESSION_A_ARCHIVE):
            // Scratchpad rotation did NOT happen. This means Session A halted
            // BEFORE step 1.5 (rotation) completed. Two scenarios:
            // (a) Old-format run before PATCH11 — scratchpad was never rotated
            // (b) Rotation failed mid-way
            // RECOVERY: perform the rotation now, inline
            print "SESSION_A_ARCHIVE_MISSING: Performing deferred scratchpad rotation..."
            // Execute the same rotation logic as COMPLETE_A step 1.5
            rename(SCRATCHPAD, SESSION_A_ARCHIVE)
            mkdir(SCRATCHPAD)
            // Copy allowlisted files
            ALLOWLIST = ["session_checkpoint.md", "session_a_to_b_handoff.md",
                         "coverage_density.md", "negative_space.md", "seed_outcomes.md",
                         "canonical_seed_map.md", "disagreement_queue.md",
                         "HALT_AFTER_COMPLETE_A.md", "build_status.md",
                         "contract_inventory.md", "function_list.md", "state_variables.md",
                         "template_recommendations.md", "mandatory_step_checklist.md",
                         "pipeline_trace.md", "blind_spot_report.md",
                         "design_context.md", "attack_surface.md", "spawn_manifest.md",
                         "run_state.json"]
            for file in ALLOWLIST:
                if file_exists("{SESSION_A_ARCHIVE}/{file}"):
                    copy("{SESSION_A_ARCHIVE}/{file}", "{SCRATCHPAD}/{file}")
            // Write SESSION_B_READ_SCOPE.md (same content as step 1.5)
            Write "{SCRATCHPAD}/SESSION_B_READ_SCOPE.md" (per step 1.5 schema)
            print "Deferred rotation complete. Session A archive: {SESSION_A_ARCHIVE}"

        // CHECK 2: Session-aware contamination check (v1.7-PATCH11 — FIXES the bug
        // where legitimate Session B work products were deleted on resume).
        // See ~/.valves/rules/execution-state.md § R9.1 for full semantics.
        //
        // Key insight: These files are ONLY contamination if Session B has NOT
        // started yet (checkpoint_level == COMPLETE_A, session still A/A_RESUMED).
        // If checkpoint_level == PARTIAL_B or COMPLETE_B, these are Session B's
        // OWN work products from a prior run in this session — do NOT delete.
        SESSION_B_WORK_PRODUCTS = [
            "hypotheses.md", "chain_hypotheses.md", "synthesis_full.md",
            "rag_validation.md", "root_cause_clusters.md", "cluster_instance_map.md",
            "report_index.md", "report_critical_high.md", "report_medium.md",
            "report_low_info.md", "AUDIT_REPORT.md", "verification_verdicts_summary.md",
            "cross_session_consensus.md", "cross_batch_consistency.md"
        ]

        // Read run_state.json to determine session context
        run_state_path = "{SCRATCHPAD}/run_state.json"
        if file_exists(run_state_path):
            rs = JSON.parse(read(run_state_path))
            rs_checkpoint = rs.checkpoint_level
        else:
            rs_checkpoint = "COMPLETE_A"  // conservative: assume fresh Session B entry

        if rs_checkpoint in ["PARTIAL_B", "COMPLETE_B"]:
            // Session B has started or completed. These are legitimate work products.
            // DO NOT DELETE. This is the fix for the Session B resume bug.
            pass  // no contamination action
        else:
            // Session B has NOT started yet. These artifacts should not be here.
            contaminated = [f for f in SESSION_B_WORK_PRODUCTS if file_exists("{SCRATCHPAD}/{f}")]
            if len(contaminated) > 0:
                print:
                ====================================================================
                SESSION_B_SCRATCHPAD_CONTAMINATED
                ====================================================================
                The fresh Session B scratchpad contains Session A analytical artifacts
                that should have been removed during scratchpad rotation:
                  {contaminated}

                These files defeat Session B's fresh-eyes guarantee.
                Removing contaminating files and proceeding...
                ====================================================================
                for f in contaminated:
                    delete "{SCRATCHPAD}/{f}"
                log "SESSION_B_SCRATCHPAD_CONTAMINATED: auto-cleaned {len(contaminated)} files" to violations.md

        // CHECK 3 (v1.7-PATCH11.1): FAIL-CLOSED Session B startup gate
        // ALL four artifacts must exist. If ANY is missing, abort immediately.
        // Do NOT silently rebuild, improvise, or proceed with partial state.
        SESSION_B_REQUIRED_FILES = [
            "{SCRATCHPAD}/run_state.json",
            "{SCRATCHPAD}/SESSION_B_READ_SCOPE.md",
            "{SCRATCHPAD}/session_checkpoint.md",
            "{SCRATCHPAD}/session_a_to_b_handoff.md"
        ]
        missing_files = [f for f in SESSION_B_REQUIRED_FILES if NOT file_exists(f)]
        if len(missing_files) > 0:
            print:
            ====================================================================
            SESSION_B_STARTUP_GATE_FAILED
            ====================================================================
            Session B cannot start. The following required artifacts are missing:
            {for f in missing_files: "  - MISSING: " + f}

            These artifacts are produced by Session A's COMPLETE_A boundary.
            Their absence means Session A did not finish correctly.

            Violation: SESSION_B_MISSING_PREREQUISITES
            Action:   Run fresh: /valves thorough fresh-run
            ====================================================================
            log "SESSION_B_MISSING_PREREQUISITES: missing {missing_files}" to violations.md
            HALT

        // Verify content integrity (files exist but could be empty/corrupt)
        handoff = Read("{SCRATCHPAD}/session_a_to_b_handoff.md")
        if handoff is empty OR handoff does not contain "## §":
            log "SESSION_B_CORRUPT_HANDOFF: session_a_to_b_handoff.md exists but is empty/malformed" to violations.md
            HALT: "Session B handoff file is corrupt. Run fresh: /valves thorough fresh-run"

        // CHECK 3b (v1.7-PATCH11.1): SESSION_B_COMPLETE.md consistency gate
        // If the completion marker exists but checkpoint ≠ COMPLETE_B, state is inconsistent.
        if file_exists("{SCRATCHPAD}/SESSION_B_COMPLETE.md"):
            cp = Read("{SCRATCHPAD}/session_checkpoint.md")
            if cp.CHECKPOINT_LEVEL != "COMPLETE_B":
                print:
                ====================================================================
                SESSION_B_CHECKPOINT_INCONSISTENCY
                ====================================================================
                SESSION_B_COMPLETE.md marker exists, but session_checkpoint.md
                shows CHECKPOINT_LEVEL: {cp.CHECKPOINT_LEVEL} (expected: COMPLETE_B).
                This is an inconsistent state — Session B closure wrote the marker
                but checkpoint was not updated, or the checkpoint was corrupted.

                Violation: SESSION_B_CHECKPOINT_INCONSISTENCY
                Action:   Inspect scratchpad manually or run fresh.
                ====================================================================
                log "SESSION_B_CHECKPOINT_INCONSISTENCY: marker exists, checkpoint={cp.CHECKPOINT_LEVEL}" to violations.md
                HALT

        print:
        ===   === ====== ===     ===   ===================
        ===   ==============     ===   ===================
        ===   ==============     ===   =========  ========
        ==== ===============     ==== ==========  ========
         ======= ===  =========== ======= ================
          =====  ===  ===========  =====  ================
           SESSION B -> Quality Pass (resuming from checkpoint)

        print: "Completed: {N} phases | Pending: {M} phases | Findings: {F} | Blind spots: {B}"
        print completed/pending phase list

        // (v1.7-PATCH11.1) PARTIAL_B gate: Session B MUST write PARTIAL_B before any work.
        // If entering via legacy checkpoint path (run_state.json may or may not exist),
        // create or update run_state.json to record PARTIAL_B. This is a hard invariant:
        // entering Session B without PARTIAL_B on disk is illegal.
        rs_path = "{SCRATCHPAD}/run_state.json"
        if file_exists(rs_path):
            rs = JSON.parse(read(rs_path))
            if rs.checkpoint_level != "PARTIAL_B":
                rs.session = "B"
                rs.checkpoint_level = "PARTIAL_B"
                rs.phase_status = "DONE"
                rs.halt_reason = null
                rs.last_write_iso = now_iso()
                Write rs_path (full JSON)
        else:
            // Legacy run without run_state.json — create it now
            Write rs_path: {
                "version": "PATCH11.1",
                "project_name": "{PROJECT_ROOT}",
                "last_write_iso": now_iso(),
                "mode": "{MODE}", "session": "B",
                "checkpoint_level": "PARTIAL_B",
                "language": "{LANGUAGE}",
                "project_root": "{PROJECT_ROOT}",
                "scratchpad": "{SCRATCHPAD}",
                "current_phase": "session_b_entry",
                "phase_status": "DONE",
                "halt_reason": null,
                "write_ahead": { "action": null, "interrupted": false },
                "resume_metadata": { "recovery_attempts": 0 }
            }

        // ASSERT: PARTIAL_B is now on disk (fail-closed verification)
        rs_verify = JSON.parse(read(rs_path))
        if rs_verify.checkpoint_level != "PARTIAL_B":
            log "SESSION_B_PARTIAL_B_WRITE_FAILED: checkpoint_level={rs_verify.checkpoint_level}" to violations.md
            HALT: "PARTIAL_B write failed. Cannot enter Session B."

        // Skip wizard, apply Session B behavioral rules (§ Session B Behavioral Rules)
        goto NEXT_PHASE

    elif level == "COMPLETE_B":
        // Session B has finalized cleanly. The audit deliverable is on disk.
        // Re-running /valves on a finalized checkpoint must NOT re-execute the pipeline.
        SESSION = "FINALIZED"

        // (v1.7-PATCH11.1) Consistency check: if run_state.json exists, verify agreement
        rs_path = "{SCRATCHPAD}/run_state.json"
        if file_exists(rs_path):
            rs = JSON.parse(read(rs_path))
            if rs.checkpoint_level != "COMPLETE_B":
                log "SESSION_B_CHECKPOINT_INCONSISTENCY: session_checkpoint=COMPLETE_B but run_state.json={rs.checkpoint_level}" to violations.md
                HALT: "Inconsistent state: session_checkpoint.md and run_state.json disagree."

        print:
        ====================================================================
        VALVES — RUN ALREADY FINALIZED (COMPLETE_B)
        ====================================================================
        This project has a completed Valves run on disk:
          - session_checkpoint.md   status: COMPLETE_B
          - Session B finalized at: {checkpoint.TIMESTAMP}
          - Final phase reached:    {checkpoint.CHECKPOINT_PHASE}
          - Audit deliverable:      {PROJECT_ROOT}/AUDIT_REPORT.md
                                    (or AUDIT_REPORT.INVALID.md if INVALID FINALIZATION)
          - Compliance summary:     {SCRATCHPAD}/compliance_summary.md

        To re-audit this project:
          /valves thorough fresh-run     # discards the existing checkpoint, starts new
          /valves thorough ignore-checkpoint  # same as fresh-run

        To inspect the existing run:
          - read {PROJECT_ROOT}/AUDIT_REPORT.md
          - read {SCRATCHPAD}/compliance_summary.md for run outcome (VALID/INCOMPLETE/INVALID)

        Halting. Pass `fresh-run` to re-audit.
        ====================================================================

        HALT. Do NOT spawn agents. Do NOT modify the scratchpad. End the conversation.

else:
    WIZARD:
    // === SESSION A: Fresh start ===
    SESSION = "A"
    // Proceed to wizard normally
```

### RESUME_AT Routing Table (v1.7-PATCH11.1 — deterministic phase entry points)

When the universal resume sweep (above) determines the exact phase/step to resume at, it uses this table to jump to the correct code path. Each phase in the pipeline has a labeled entry point.

```
RESUME_AT(phase, step):
    // Restore all preflight state (MODE, LANGUAGE, SCRATCHPAD, etc.) from run_state.json
    // Run minimal preflight: version check + toolchain probe + watchdog init (if Thorough)
    // Then jump to the labeled phase entry:

    match phase:
        "phase1"         → goto PHASE_1_ENTRY (recon agents)
        "phase1.2"       → goto PHASE_1_2_ENTRY (historical prime)
        "phase1.5"       → goto PHASE_1_5_ENTRY (diff audit)
        "phase2"         → goto PHASE_2_ENTRY (instantiation)
        "phase3"         → goto PHASE_3_ENTRY (breadth)
        "phase3b"        → goto PHASE_3B_ENTRY (re-scan)
        "phase3c"        → goto PHASE_3C_ENTRY (per-contract)
        "phase4a"        → goto PHASE_4A_ENTRY (inventory + classification)
        "phase4a.5"      → goto PHASE_4A5_ENTRY (semantic invariants + harvester)
        "phase4b_iter1"  → goto PHASE_4B_ITER1_ENTRY (depth loop iter 1)
        "phase4b_scoring"→ goto PHASE_4B_SCORING_ENTRY (confidence scoring)
        "complete_a"     → goto COMPLETE_A_BOUNDARY
        "phase4b_iter2"  → goto PHASE_4B_ITER2_ENTRY (DA iter 2, Session B)
        "phase4b_iter3"  → goto PHASE_4B_ITER3_ENTRY (DA iter 3, Session B)
        "phase4b.5"      → goto PHASE_4B5_ENTRY (RAG sweep)
        "phase4c"        → goto PHASE_4C_ENTRY (chain analysis)
        "phase5"         → goto PHASE_5_ENTRY (verification)
        "phase5.1"       → goto PHASE_5_1_ENTRY (skeptic-judge)
        "phase5.6"       → goto PHASE_5_6_ENTRY (thesis v3 + inheritance)
        "phase6"         → goto PHASE_6_ENTRY (report)
        "phase6f"        → goto PHASE_6F_ENTRY (embargo)
        _                → ABORT: "Unknown phase '{phase}' in run_state.json"

RESPAWN_MISSING(phase, needs_respawn):
    // Read manifest for the phase
    // For each agent in needs_respawn:
    //   - Rebuild agent prompt (from template_recommendations + scratchpad state)
    //   - Spawn with same model as original
    //   - Update manifest row on return
    // After all re-spawns complete:
    //   - Run Phase 0.9 § A on each returned agent
    //   - Update manifest Completion Summary
    //   - Write run_state.json STEP_STATUS=DONE, INTERRUPTED=false
    //   - Advance to next step via RESUME_AT

RETRY(phase, step):
    // Increment run_state.RECOVERY_ATTEMPTS
    // Write run_state.json with STEP_STATUS=INTENT (re-attempt)
    // Jump to the step's entry point
    goto RESUME_AT(phase, step)
```

The orchestrator resolves each labeled entry point to the corresponding section in this slash command. Each phase section begins with a comment `// PHASE_X_ENTRY:` (added by PATCH11) that the resume sweep targets.

**PARTIAL_A resume** continues Session A normally -> same pipeline rules, same agent models, same reasoning carry-forward. It is a recovery, not a quality split. The orchestrator reads the checklist to skip completed phases and picks up where Session A left off.

**COMPLETE_A resume** enters Session B quality-pass mode -> evidence-only carry-forward, blind-spot-driven DA, verifier independence, fresh confidence scoring. This is the quality improvement.

**Fresh-run override**: Pass `fresh-run` or `ignore-checkpoint` in arguments (e.g., `/valves thorough fresh-run`) to force a fresh Session A even if a checkpoint exists. The checkpoint file is NOT deleted -> it is simply ignored.

### PARTIAL_A Checkpoint Write (v1.7 -> incremental, reusable)

The orchestrator calls this write at every major phase boundary during Session A. It is a lightweight state snapshot -> no finding cards, no blind spot analysis, just enough for recovery.

**When to write**: After EACH of these phases completes:
1. Recon (Phase 1 complete)
2. Breadth (Phase 3 complete)
3. Phase 3b Re-Scan complete
4. Phase 3c Per-Contract complete
5. Inventory Merge (Phase 4a.1-final complete)
6. Gate + Classification + Thesis v1 (Phase 4a complete -> produces finding_classification.md, NOT root_cause_clusters.md)
7. Phase 4a.5 full parallel split complete (Semantic Invariants + System Breakpoints + P1 Propagation + Structural Anomaly Harvester -> all 4 agents)

**How to write**: Orchestrator inline, single Write call (~10 lines). Overwrites the previous PARTIAL_A checkpoint each time (latest state wins).

```
// PARTIAL_A checkpoint write -> call at each phase boundary listed above
Write {SCRATCHPAD}/session_checkpoint.md:

# Session Checkpoint (Valves v1.7)
## Pipeline State
- CHECKPOINT_LEVEL: PARTIAL_A
- MODE: {MODE}
- LANGUAGE: {LANGUAGE}
- SCRATCHPAD: {SCRATCHPAD}
- PROJECT_ROOT: {PROJECT_ROOT}
- CHECKPOINT_PHASE: {phase that just completed, e.g., "Phase 4a.5 full parallel split"}
- NEXT_PHASE: {next phase to run, e.g., "Phase 4b Depth iter 1"}
- TIMESTAMP: {ISO 8601}

## Launch-State Fields (audit contract -> must match across sessions)
- DOCS_PATH: {DOCS_PATH or "none"}
- NETWORK: {NETWORK or "none"}
- RPC_URL: {RPC_URL or "none"}
- SCOPE_FILE: {SCOPE_FILE or "none"}
- SCOPE_NOTES: {SCOPE_NOTES or "none"}
- PROVEN_ONLY: {true/false}
- HISTORICAL_PRIME_MODE: {true/false}

## Checklist State
{paste ALL rows from mandatory_step_checklist.md -> same format as COMPLETE_A}

## Active Flags
{from template_recommendations.md: detected flags, niche agents, injectable skills}
```

**What PARTIAL_A deliberately excludes**: finding cards, blind spot report, verification queue, open contradictions. These are only computed at the COMPLETE_A boundary (post-depth checkpoint) when Session A has finished discovery and the full evidence picture is available.

The post-depth checkpoint (§ Session Checkpoint Write below) upgrades this file from PARTIAL_A to COMPLETE_A by rewriting it with the full evidence-only packet.

---

## Mode Isolation Rule (v1.7.0)

Once MODE is resolved, the orchestrator MUST ignore skip/override logic from other modes. Specifically:
- If `MODE == thorough`: Light/Core skip behavior is irrelevant and MUST NOT be used as justification for skipping, deferring, or simplifying any step. Do not cite "Skip in Light/Core" wording when deciding whether a Thorough step is applicable.
- If `MODE == core`: Light skip behavior is irrelevant. Core's own skip list is authoritative.
- If `MODE == light`: Light's own skip list is authoritative.

The ONLY valid reasons to skip a step are: (1) the step's own applicability condition is not met (language, tool availability, flag not detected), or (2) the mode's explicit skip list names that step. Cross-mode reasoning is prohibited.

---

## Step 1: Language Detection

Detect the target language before anything else:

| Indicator | Language | `LANGUAGE` value |
|-----------|----------|-----------------|
| `*.sol` files + `foundry.toml` or `hardhat.config.*` | **EVM/Solidity** | `evm` |
| `*.rs` files + `Anchor.toml` or `Cargo.toml` with `solana-program`/`anchor-lang` | **Solana/Anchor** | `solana` |
| `*.rs` files + `Cargo.toml` WITHOUT `solana-program`/`anchor-lang` | **Native Solana (no Anchor)** | `solana` (with `ANCHOR=false` flag) |
| `*.move` files + `Move.toml` with `aptos_framework`/`aptos_std`/`aptos_token`/`fungible_asset` | **Aptos Move** | `aptos` |
| `*.move` files + `Move.toml` with `sui::object`/`sui::transfer`/`sui::tx_context`/`sui::coin` | **Sui Move** | `sui` |
| `*.rs` files + `Cargo.toml` with `soroban-sdk` | **Soroban/Stellar** | `soroban` |

**Detection procedure**:
1. `ls` project root for `foundry.toml`, `hardhat.config.*`, `Anchor.toml`, `Move.toml`, `Cargo.toml`
2. If `Move.toml` found: grep dependencies for Aptos indicators (`AptosFramework`, `aptos_framework`, `AptosStdlib`, `aptos_std`, `AptosToken`, `aptos_token`) or Sui indicators (`Sui`, `sui::object`, `sui::transfer`, `sui::tx_context`, `sui::coin`)
3. If ambiguous Move: grep `*.move` for `use aptos_framework::` (Aptos) or `use sui::` (Sui)
4. If `*.rs` files + `Cargo.toml`: grep `Cargo.toml` for `soroban-sdk` -> if found, set `LANGUAGE=soroban`
5. If `*.rs` files + NOT soroban: grep `Cargo.toml` for `anchor-lang` or `solana-program`
6. If still ambiguous Rust: grep `*.rs` for `#[program]` or `#[derive(Accounts)]` (Anchor markers)
7. Set `LANGUAGE` variable: `evm`, `solana`, `aptos`, `sui`, or `soroban`
8. Set `ANCHOR` variable: `true` or `false` (Solana only)

**Tree architecture -> path resolution**:
- **Language-specific prompts**: `~/.claude/prompts/{LANGUAGE}/`
- **Shared rules**: `~/.claude/rules/`
- **Skills**: `~/.claude/agents/skills/{LANGUAGE}/`
- **Injectable skills**: `~/.claude/agents/skills/injectable/`
- **Niche agents**: `~/.claude/agents/skills/niche/`
- **Depth agents**: `~/.claude/agents/depth-*.md`

---

## Step 1.1: Network Resolution (EVM only)

If `NETWORK` is set and `LANGUAGE` is `evm`, resolve to an RPC URL for production verification and fork testing:

| Network | RPC URL |
|---------|---------|
| `ethereum` | `https://eth.llamarpc.com` or `$ETH_RPC_URL` env var |
| `arbitrum` | `https://arb1.arbitrum.io/rpc` or `$ARBITRUM_RPC_URL` env var |
| `optimism` | `https://mainnet.optimism.io` or `$OPTIMISM_RPC_URL` env var |
| `base` | `https://mainnet.base.org` or `$BASE_RPC_URL` env var |
| `polygon` | `https://polygon-rpc.com` or `$POLYGON_RPC_URL` env var |
| `bsc` | `https://bsc-dataseed1.binance.org` or `$BSC_RPC_URL` env var |
| `avalanche` | `https://api.avax.network/ext/bc/C/rpc` or `$AVALANCHE_RPC_URL` env var |
| Other (URL) | Use as-is |

**Priority**: Environment variable > default public RPC. Store resolved URL as `RPC_URL` -> used by Phase 1 TASK 11 (production verification) and Phase 5 (fork testing with `--fork-url`).

If `NETWORK` is not set: orchestrator infers from codebase (chainId constants, deployment configs, foundry.toml `[rpc_endpoints]`). If inference fails, production verification runs without fork testing.

---

## WORKFLOW OVERVIEW

> **ARCHITECTURE (v1.7-PATCH5)**: Recon -> Diff-Audit Tier A/B/C (Valves) -> Instantiation -> Parallel Breadth -> **Inventory (4a.1)** -> [Thorough: Re-Scan (3b) + Per-Contract (3c) -> Inventory Merge] -> **[Gate -> Classification (lite) -> Thesis v1]** (Valves v1.7, no clustering yet) -> **[Semantic Invariants | System Breakpoints | Propagation P1 | Structural Anomaly Harvester (8 sweeps)]** 4-agent parallel split -> **Assumption-Breaker (4a.5.e, <=5 seeds) -> Conditional Analog Seeding (4a.5.f, gated on 6 triggers per v1.7-PATCH2)** -> Adaptive Depth Loop iter 1 + Economic + Thesis v2 + **Full Clustering (post-depth)** + P2 Propagation (Valves, budget-aware) -> **COMPLETE_A Handoff Build (coverage_density + negative_space + seed_outcomes + canonical_seed_map [w/ proof records + sibling links per v1.7-PATCH3] + disagreement_queue -> session_a_to_b_handoff [w/ slack redistribution + family-diversity cap per v1.7-PATCH4 + dominant-family override per v1.7-PATCH5])** -> [Session B: DA iter 2-3 -> Cross-Session Consensus ->] Chain Analysis (cluster-scoped) -> Verification Priority Queue (EV-ranked + orphan reserve + **rescue reserve [w/ rescue-class diversity control per v1.7-PATCH5] per v1.7-PATCH4**) -> Verification (cluster inheritance) -> Thesis v3 (**stricter NR applicability per v1.7-PATCH4 + evidence age/drift per v1.7-PATCH5**) + Cluster Instance Map + Negative Results Promotion -> Report (cluster -> subgroup -> report-ID) -> **6d.5 final strongest-exploit sanity check (v1.7-PATCH5)** -> **6e measurement (seed_metrics + coverage_lift, with family-saturation per v1.7-PATCH4 + reserve-to-final conversion per v1.7-PATCH5)**

| Phase | Agent(s) | Output | Light | Core | Thorough |
|-------|----------|--------|-------|------|----------|
| **Phase 1** | Recon Agent(s) | Artifacts + templates | 2 sonnet (no RAG/fork) | 4 agents | 4 agents |
| **Phase 1.5 (Valves)** | Reference Diff-Audit | Diff report per parent + Tier A/B/C global table | Skip | Up to 4 opus | Up to 4 opus |
| **Phase 2** | Orchestrator | Instantiated prompts (w/ Tier A injection) | All | All | All |
| **Phase 3** | Breadth Agents | Findings files | 3-4 sonnet | 5-9 opus | 5-9 opus |
| **Phase 3b** | Re-Scan + Per-Contract | Masked findings | Skip | Skip | Thorough only (after 4a.1, before 4a.1.5) |
| **Phase 4a.1** | Initial Inventory | findings_inventory.md | 1 sonnet | 1 sonnet | 1 sonnet |
| **Phase 4a.1-final (Thorough)** | Inventory Merge / Refresh (post-3b/3c) | findings_inventory.md (merged, w/ Inventory Source Coverage) | Skip | Skip | 1 haiku |
| **Phase 4a.1.5->4a.3 (Valves v1.7)** | Gate + Classification + Thesis v1 | strongest_exploit_cards.md + finding_classification.md + attack_thesis.md v1 | 3 sonnet (sequential) | 3 sonnet | 1 opus (Gate) + 2 sonnet (Classification+Thesis), after merge |
| **Phase 1.2 (Valves v1.3, opt-in)** | Prior-Report Ingest Agent (benchmark/rerun mode only) | historical_prime_seeds.md | Skip | Skip unless flag | Skip unless flag |
| **Phase 4a.5 (Valves v1.7 expanded)** | Semantic Invariant + System Breakpoints + Propagation P1 + Structural Anomaly Harvester (4 parallel agents) | semantic_invariants.md + system_breakpoints.md + propagation_structural.md + candidate_seeds.md + symmetric_pairs.md + external_platform_limits.md + external_mutability_candidates.md | Skip breakpoints/P1/harvester | 4 sonnet parallel | 4 sonnet parallel (+Pass 2) |
| **Phase 4b** | Depth Loop (filtered-excerpt injection of P1 hints, Tier A targets, thesis path) | Deep analysis | 4 merged sonnet, no scoring | 8+ agents, 2-axis scoring | 8+ agents, 4-axis scoring + reality/report split |
| **Phase 4b (Valves: Economic)** | Economic Incentive Agent | economic_findings.md (EI-THEORY/TRACE/SIM tags) | Skip | 1 opus | 2 opus (iter 1 + iter 2) |
| **Phase 4b (Valves: Thesis v2)** | Thesis Synthesis Agent | attack_thesis.md v2 | Skip | 1 sonnet | 1 sonnet |
| **Phase 4b (Valves: Propagation P2)** | Bug-Class Propagation (cluster-scoped, budget-aware) | propagated_{BC-NNN}.md per Tier 1/2 cluster + UNPROPAGATED_BUDGET stubs | Skip | Up to 5 sonnet | Up to 10 sonnet |
| **Phase 4c** | Chain Analysis (cluster-scoped, thesis-tagged, breakpoint-tagged) | Hypotheses + chains | 1 sonnet (merged) | 2 agents | 2 agents + iter 2 |
| **Phase 4c.5 (Valves)** | Orchestrator inline | verification_priority_queue.md (EV w/ bucketed poc_cost_factor + orphan reserve) | All | All | All |
| **Phase 5** | Verifiers (EV-ranked, cluster inheritance, orphan reserve) | PoC tests + verification_inheritance.md | Medium+ (sonnet) | Medium+ | ALL severities + fuzz |
| **Phase 5.1** | Skeptic-Judge | Adversarial re-verify | Skip | Skip | HIGH/CRIT |
| **Phase 5.2** | Cross-batch consistency | Contradiction check | Skip | 1 haiku | 1 haiku |
| **Phase 5.6 (Valves)** | Orchestrator inline | attack_thesis.md v3 (PRIOR_NEGATIVE handling) + NR promotion + cluster_instance_map.md | All | All | All |
| **Phase 6** | Report pipeline (cluster -> subgroup -> report-ID via cluster_instance_map.md; thesis v3 as residual risk summary) | AUDIT_REPORT.md | 2 agents (sonnet+haiku) | 5 agents | 5 agents |
| **Phase 6d (Valves v1.4)** | Report Quality Self-Review | report_review.md + inline auto-fixes | 1 haiku | 1 haiku | 1 haiku |
| **Phase 6e (Valves v1.4)** | Pipeline Trace Finalization | pipeline_trace.md (conservation check) | Inline | Inline | Inline |
| **Phase 6f (Valves v1.5, Thorough only)** | Final Report Embargo (FAIL-CLOSED) | compliance_summary.md + terminal embargo print | Skip | Skip | **Inline (always-on for Thorough)** |

### Light Mode Orchestration

When `MODE == light`, the orchestrator applies these overrides:

1. **All agents use Sonnet or Haiku** -> no Opus spawns. Use `model="sonnet"` for all analysis/verification agents, `model="haiku"` for assembler only.
2. **Recon**: Spawn 2 sonnet agents (not 4). Agent L1 = build + static analysis + tests (Tasks 1,2,8,9). Agent L2 = docs + patterns + surface + templates (Tasks 3,4,5,6,7,10). Skip RAG meta-buffer (Task 0) and fork ancestry entirely.
3. **Breadth**: Cap at 3-4 sonnet agents (not 5-9 opus). Use same merge hierarchy.
4. **Semantic Invariants**: Skip entirely. Depth agents read `state_variables.md` directly.
5. **Depth Loop**: Spawn 4 merged sonnet agents -> (a) combined token-flow + state-trace, (b) combined edge-case + external, (c) combined scanner A+B+C, (d) validation sweep. No niche agents, no injectable investigation agents. Iteration 1 only, no confidence scoring. **Note**: Merges (a) and (c) are deliberate exceptions to the standard merge hierarchy -> token-flow + state-trace and 3-scanner compression reduce agent count at the cost of per-domain attention depth. This is a known tradeoff accepted for Pro plan rate limit compliance.
6. **Chain Analysis**: Single sonnet agent performs both enabler enumeration and chain matching in one pass.
7. **Verification**: ALL Medium+ (same scope as Core), but all verifiers are sonnet.
8. **Report**: 1 sonnet writer (all tiers) + 1 haiku assembler. No separate index agent -> writer handles ID assignment inline.
9. **Report disclaimer**: Include at the top of the report: *"This audit was performed in Light mode (all Sonnet agents). For maximum coverage, use Core or Thorough mode with a Max plan."*

---

## Phase 0.9: Mechanical Architecture Enforcement (v1.7-PATCH10 — ALWAYS-ON, ALL MODES)

> Orchestrator-inline architecture invariants that fire for every agent spawn, every protected-artifact write, and every phase boundary. NO new agent. NO new artifact (uses existing `violations.md` + `degradation_log.md` + `mandatory_step_checklist.md`). Fail-closed semantics in Thorough; degrade-and-log in Core/Light.

These enforcement gates are read once and applied throughout the run:

### § A. Universal post-spawn integrity check (after EVERY Task() returns)

After EVERY `Task()` agent return, BEFORE accepting the agent's output, the orchestrator MUST run this check inline:

```
1. Read the agent's tool trace (Bash commands + Read/Write/Edit targets).
2. For each Bash command, grep against the forbidden-patterns list in
   `~/.valves/rules/valves-doctrine.md` § Agent tool discipline:
     - claude --print | claude -p | claude_code (any flag)
     - npx claude | bunx claude | yarn claude | pnpm claude
     - exec claude | spawn claude | sh -c "claude... | bash -c "claude...
     - any pipe TO claude (... | claude)
     - any subprocess that re-enters orchestrator role
2.5 (v1.7-PATCH11) SESSION B ISOLATION CHECK:
   if SESSION == "B" AND cross_session_consensus_step_NOT_yet_reached:
     // Check BOTH Read() targets AND Bash file accesses (PATCH11-C fix)
     For each Read() target in the agent's tool trace:
       resolved = realpath(target)  // resolve symlinks + traversal
       - if resolved contains ".audit_session_a/" → SESSION_B_ISOLATION_BREACH_READ violation
       - if resolved matches any FORBIDDEN file listed in SESSION_B_READ_SCOPE.md § DENIED
         → SESSION_B_ISOLATION_BREACH_READ violation
     For each Bash command in the agent's tool trace:
       // Extract file paths from cat/head/tail/less/more/grep/find/ls/cp/mv/sed/awk args
       extracted_paths = extract_file_paths_from_bash_cmd(bash_cmd)
       for path in extracted_paths:
         resolved = realpath(path)  // resolve symlinks + .. traversal
         - if resolved contains ".audit_session_a/" → SESSION_B_ISOLATION_BREACH_BASH violation
         - if resolved matches any FORBIDDEN file in SESSION_B_READ_SCOPE.md § DENIED
           → SESSION_B_ISOLATION_BREACH_BASH violation
     // Violation codes: SESSION_B_ISOLATION_BREACH_READ, SESSION_B_ISOLATION_BREACH_BASH
     Same decision matrix as step 4 below (first → discard+re-spawn, second → halt)
3. For each Write/Edit target, look up the path in
   `~/.valves/rules/artifact-ownership.md` § Control table:
     - if class=ORCHESTRATOR-INLINE → ILLEGAL_WRITER_ORCHESTRATOR_ARTIFACT_BY_AGENT
     - if class=AGENT-OWNED but producer ≠ this agent → ILLEGAL_WRITER_WRONG_AGENT
     - if class=EITHER and producer is "either path" → allowed
     - if not in manifest → UNREGISTERED_ARTIFACT_WRITTEN (informational)
4. Decision matrix (mechanical):
   ┌──────────────────────────────────┬──────────────────────────────────────┐
   │ First violation                  │ Second violation (after re-spawn)    │
   ├──────────────────────────────────┼──────────────────────────────────────┤
   │ - Log violation to violations.md │ - Log SCOPE_VIOLATION_PERSISTENT     │
   │ - Mark output TAINTED in         │ - Halt the run (no further spawns)   │
   │   degradation_log.md             │ - Final embargo refuses VALID        │
   │ - AUTO-DISCARD output (delete or │   THOROUGH and emits                 │
   │   ignore agent's artifacts)     │   INVALID_FINALIZATION_AGENT_SCOPE_  │
   │ - Re-spawn agent ONCE with      │   PERSISTENT to compliance_summary.md│
   │   stricter prompt (forbidden    │                                      │
   │   patterns + scope explicit)    │                                      │
   └──────────────────────────────────┴──────────────────────────────────────┘
5. Do NOT prompt the user for "accept-with-flag" override. Process discipline
   is mechanical; output quality is irrelevant when the agent went off-script.
6. (v1.7-PATCH11.3) OUTPUT INTEGRITY GATE — after steps 1-5 pass, validate
   the agent's expected output artifact(s):
   a. For each expected output path:
      result = VALIDATE_STEP_COMPLETION(row, path, agent.name)  // § A.1
      if result == FAIL:
          log "AGENT_OUTPUT_INTEGRITY_FAIL: {agent.name} → {path}: {result.reason}" to violations.md
          // Same decision matrix as step 4: first failure → discard + re-spawn once;
          // second failure → mark FAILED, do NOT self-synthesize.
   b. Reject + log + re-spawn on:
      - Output file missing (agent said DONE but didn't write)
      - Output file empty (0 lines)
      - Output file missing required structural header (per § R4)
      - Output file below minimum line count (truncated)
      - Output file written by wrong producer (ownership mismatch)
      - Output file stale (mtime before phase start — leftover from prior run)
   c. On re-spawn, append to agent prompt:
      "CRITICAL: Your previous run returned success but output validation
       failed: {result.reason}. You MUST write {path} with valid content
       matching the required format before returning."
```

This check applies to EVERY agent spawn — recon, breadth, depth, scanners, validation sweep, niche, economic, thesis, cluster, chain, verifier, skeptic, report tier writers, assembler, quality review, ingest. No exceptions.

**Special HP-specific check**: when `HP_AGENT_RETURNED == true`, the orchestrator additionally verifies that NO files other than `historical_prime_seeds.md` were written by the HP agent during its run. This is a mechanical filesystem-state diff: list scratchpad files modified during the HP agent's execution window; if any path ≠ `historical_prime_seeds.md` → `ILLEGAL_WRITER_HP_OUT_OF_SCOPE` (HIGH severity). AUTO-DISCARD all such files (move to `{SCRATCHPAD}/.tainted/`), re-spawn HP once with stricter prompt.

### § A.1. Step-completion validation function (v1.7-PATCH11.3 — called by § A, § C, § F)

A step is DONE only when ALL of the following pass. This function is called wherever the orchestrator would mark a checklist row COMPLETE.

```
VALIDATE_STEP_COMPLETION(row, artifact_path, producer_agent_name):
    // 1. ARTIFACT EXISTS
    if NOT file_exists(artifact_path):
        return FAIL("ARTIFACT_MISSING: {artifact_path} does not exist on disk")

    // 2. ARTIFACT NON-EMPTY
    line_count = count_lines(artifact_path)
    if line_count == 0:
        return FAIL("ARTIFACT_EMPTY: {artifact_path} is 0 lines")

    // 3. STRUCTURAL SIGNATURE (per § R4 validity table)
    validity = validity_check(artifact_path)
    if validity != VALID:
        return FAIL("ARTIFACT_INVALID: {artifact_path} failed validity check: {validity}")

    // 4. MIN LINE COUNT (per § R4 table)
    min_lines = get_min_lines_for_class(artifact_path)
    if min_lines != null AND line_count < min_lines:
        return FAIL("ARTIFACT_TRUNCATED: {artifact_path} has {line_count} lines, minimum is {min_lines}")

    // 5. LEGAL OWNER
    ownership = lookup_owner(artifact_path)  // from artifact-ownership.md § Control table
    if ownership.class == "AGENT-OWNED" AND producer_agent_name == "orchestrator":
        return FAIL("ILLEGAL_OWNER: {artifact_path} is AGENT-OWNED but writer is orchestrator")
    if ownership.class == "AGENT-OWNED" AND ownership.producer != producer_agent_name:
        return FAIL("WRONG_PRODUCER: {artifact_path} owned by {ownership.producer}, written by {producer_agent_name}")

    // 6. NOT STALE (artifact modified after phase start)
    artifact_mtime = file_mtime(artifact_path)
    phase_start = get_phase_start_time()  // from run_state.json last_transition.timestamp
    if phase_start != null AND artifact_mtime < phase_start:
        return FAIL("ARTIFACT_STALE: {artifact_path} last modified {artifact_mtime}, phase started {phase_start}")

    // 7. PRODUCER AGENT COMPLETED (not timed out or crashed)
    if producer_agent_name != "orchestrator":
        agent_status = get_manifest_agent_status(producer_agent_name)
        if agent_status not in ["DONE", "SKIP_ALREADY_COMPLETE"]:
            return FAIL("PRODUCER_INCOMPLETE: agent {producer_agent_name} status is {agent_status}")

    return PASS

// Usage in § A (post-spawn):
//   result = VALIDATE_STEP_COMPLETION(row, agent.expected_output, agent.name)
//   if result == FAIL → do NOT mark COMPLETE; log reason; re-spawn per § B.1
// Usage in § C (row sync):
//   result = VALIDATE_STEP_COMPLETION(row, row.evidence_artifact, row.producer)
//   if result == FAIL → mark FAILED (not COMPLETE)
// Usage in § F (reconciliation):
//   For each COMPLETE row, re-validate with VALIDATE_STEP_COMPLETION
//   if result == FAIL → RECONCILIATION_DRIFT + downgrade row
```

### § B. Protected-artifact pre-write gate (before EVERY orchestrator-inline write)

Before the orchestrator writes ANY artifact (orchestrator-inline OR fallback path), it MUST run this check inline:

```
1. Look up target artifact in `~/.valves/rules/artifact-ownership.md` § Control table.
2. Verify class:
   - if class=ORCHESTRATOR-INLINE → orchestrator may write IF prerequisites pass (step 3)
   - if class=AGENT-OWNED → orchestrator may NOT write directly; only the named producer agent can
   - if class=EITHER → allowed if the artifact's rule file lists orchestrator-inline as a fallback
3. Verify all `Prerequisites` rows in the control table are in terminal state
   (COMPLETE / FAILED_WITH_FALLBACK / NOT_APPLICABLE) per
   `~/.valves/rules/thorough-strict-mode.md` § Valid terminal states.
4. Verify the orchestrator is in the correct phase per the `Producing Phase` column.
5. If ANY check fails:
   - Log PROTECTED_ARTIFACT_PRE_WRITE_GATE_BLOCKED to violations.md
     with: artifact name, attempted phase, failed prerequisite (if any), illegal-class reason (if any)
   - REFUSE the write
   - Halt the current step
   - Trigger Recovery Loop per `~/.valves/rules/thorough-strict-mode.md` § Recovery Loop
   - If recovery exhausted → Phase 6f embargo blocks finalization
```

This gate applies to: `coverage_density.md`, `negative_space.md`, `seed_outcomes.md`, `canonical_seed_map.md`, `disagreement_queue.md`, `session_a_to_b_handoff.md`, `cross_session_consensus.md`, `verification_priority_queue.md`, `verification_inheritance.md`, `strongest_exploit_final_check.md`, `seed_metrics.md`, `coverage_lift.md`, `compliance_summary.md`, `analog_seeds.md`, `diff_audit_tiers.md`, and any future ORCHESTRATOR-INLINE artifact added to the manifest.

**It also applies to AGENT-OWNED artifacts** when the orchestrator is tempted to self-synthesize as a substitute for missing phases (the failure observed in the Snuggle run: orchestrator wrote `report_*.md`, `cluster_instance_map.md`, `chain_hypotheses.md`, `attack_thesis_v3.md` directly without spawning the named producer agents). For AGENT-OWNED artifacts, step 2 fails → write is REFUSED. The orchestrator must spawn the named producer or mark the row FAILED with non-trivial reason.

**(v1.7-PATCH11.2) CRITICAL_AGENT_OWNED hard list — orchestrator MUST NEVER write these directly:**

```
CRITICAL_AGENT_OWNED = [
    // === REPORT PIPELINE ===
    "report_index.md",           // Report Index Agent (haiku)
    "report_critical_high.md",   // Tier Writer (opus)
    "report_medium.md",          // Tier Writer (sonnet)
    "report_low_info.md",        // Tier Writer (sonnet)
    "AUDIT_REPORT.md",           // Assembler Agent (haiku/sonnet)
    "AUDIT_REPORT_SESSION_B.md", // Session B Assembler (v1.7-PATCH11.3)
    "report_review.md",          // Report Quality Self-Review Agent (haiku)
    // === CLUSTERING + CHAIN ===
    "cluster_instance_map.md",   // Cluster Instance Map Agent (sonnet)
    "root_cause_clusters.md",    // Full Cluster Agent (sonnet) — initial write
    "hypotheses.md",             // Chain Analysis Agents
    "chain_hypotheses.md",       // Chain Analysis Agents
    "synthesis_full.md",         // Chain Agent 2 (v1.7-PATCH11.3)
    "composition_coverage.md",   // Chain Agent 2 (v1.7-PATCH11.3)
    "enabler_results.md",        // Chain Agent 1 (v1.7-PATCH11.3)
    "finding_mapping.md",        // Chain Agent 1 (v1.7-PATCH11.3)
    // === VERIFICATION ===
    "verify_*.md",               // Verifier Agents (one per finding)
    "cross_session_consensus.md",// Cross-session consensus agent (v1.7-PATCH11.3)
    "cross_batch_consistency.md",// Cross-batch consistency agent (v1.7-PATCH11.3)
    // === INVENTORY + SCORING ===
    "findings_inventory.md",     // Inventory Agent (sonnet)
    "finding_classification.md", // Classification Agent (v1.7-PATCH11.3)
    "confidence_scores.md",      // Scoring Agent (haiku)
    "rag_validation.md",         // RAG Sweep Agent (sonnet)
    // === ANALYSIS ===
    "analysis_*.md",             // Breadth/depth/rescan/percontract agents
    "blind_spot_*.md",           // Blind spot agents (v1.7-PATCH11.3)
    "niche_*.md",                // Niche agents (v1.7-PATCH11.3)
    "design_stress_findings.md", // Design Stress Testing agent (v1.7-PATCH11.3)
    "validation_sweep_findings.md", // Validation Sweep agent (v1.7-PATCH11.3)
    "sibling_propagation_findings.md", // Sibling Propagation agent (v1.7-PATCH11.3)
    // === RECON ===
    "design_context.md",         // Recon Agent 1B (v1.7-PATCH11.3)
    "attack_surface.md",         // Recon Agent 3 (v1.7-PATCH11.3)
    "meta_buffer.md",            // Recon Agent 1A RAG (v1.7-PATCH11.3)
    "historical_prime_seeds.md", // HP Agent (v1.7-PATCH11.3)
    // === THESIS ===
    "attack_thesis.md",          // Thesis Agent — all versions (v1.7-PATCH11.3)
    "strongest_exploit_cards.md",// Strongest Exploit Gate Agent (v1.7-PATCH11.3)
]

// Mechanical enforcement (runs inside § B step 2):
if target_artifact matches any CRITICAL_AGENT_OWNED pattern:
    if writer == "orchestrator":
        log "ORCHESTRATOR_SELF_SYNTHESIS_BANNED: attempted to write {target_artifact}" to violations.md (HIGH)
        print:
        ====================================================================
        ORCHESTRATOR_SELF_SYNTHESIS_BANNED
        ====================================================================
        The orchestrator attempted to directly write an AGENT-OWNED artifact:
          {target_artifact}
        This artifact MUST be produced by its named agent. The orchestrator
        may re-spawn the agent ONCE. If still missing, mark the row FAILED.
        ====================================================================
        REFUSE the write.
        // Re-spawn the named producer agent ONCE per § B.1 protocol.
        // If second spawn also fails → mark row FAILED per existing mechanics.
```

This list is a mechanical denylist, not advisory prose. The § B gate checks it before any orchestrator Write call. Cross-reference: `~/.valves/rules/artifact-ownership.md` § Control table is the authoritative source; this list is a fast-path subset for the most critical artifacts.

### § B.1. Agent-done-but-artifact-missing enforcement (v1.7-PATCH11 — HARD RULE)

When an agent returns "DONE" (or any success message) but its expected AGENT-OWNED artifact is NOT on disk:

```
STEP-LOCAL ENFORCEMENT (mechanical, no exceptions):

1. Check: does the AGENT-OWNED artifact file exist at the expected path?
   - if YES → proceed normally (§ A integrity check still applies)
   - if NO → ARTIFACT_MISSING_AFTER_AGENT_SUCCESS

2. On ARTIFACT_MISSING_AFTER_AGENT_SUCCESS:
   a. The orchestrator MUST NOT synthesize the artifact itself.
      - Writing it directly = ILLEGAL_WRITER violation (§ B catches this)
      - Summarizing the agent's output into the artifact = same violation
      - "The agent reported its findings in the return message so I'll
        write them to disk" = PROHIBITED. The agent must write its own file.
   b. Re-spawn the agent ONCE with explicit instruction:
      "Your previous run reported success but did NOT write {artifact_path}.
       You MUST write this file before returning. Write your output to
       {artifact_path} and then return DONE."
   c. If second spawn also fails to write → mark row FAILED_WITH_FALLBACK
      (if a fallback artifact is defined) or FAILED (if no fallback).
      Do NOT halt the entire run for non-HARD-gate artifacts.
      For HARD-gate artifacts: trigger Recovery Loop.

3. SPECIFICALLY PROTECTED report-pipeline artifacts (PATCH11 emphasis):
   These artifacts are ALWAYS AGENT-OWNED and NEVER orchestrator-synthesized:
   - report_index.md (Index Agent)
   - report_critical_high.md (Critical+High Tier Writer)
   - report_medium.md (Medium Tier Writer)
   - report_low_info.md (Low+Info Tier Writer)
   - AUDIT_REPORT.md / AUDIT_REPORT_SESSION_B.md (Assembler Agent)
   - cluster_instance_map.md (Cluster Agent)
   - chain_hypotheses.md (Chain Agent 2)
   - root_cause_clusters.md (Cluster Agent)
   - hypotheses.md (Chain Agent 1)
   - attack_thesis.md v2/v3 (Thesis Synthesis Agent)
   - verify_*.md (Verifier agents)

   If ANY of these is missing after agent success → the agent MUST be
   re-spawned. The orchestrator writing these itself is a
   SCOPE_VIOLATION_PERSISTENT-level offense that triggers INVALID FINALIZATION.
```

This closes the loophole where the orchestrator says "the agent reported success and I have its output in my context, so I'll write it to disk myself." That behavior produced the single-session Snuggle failure and the Reserve Governor single-session run. The agent writes its own files or the step fails.

### § C. Row synchronization discipline (after EVERY phase change)

The orchestrator MUST update `mandatory_step_checklist.md` after every phase transition, NOT in batches:

```
After every Task() returns successfully:
  1. Identify which checklist row(s) the Task corresponds to (by matching
     row.evidence_artifact against the agent's output paths).
  2. Update row.status:
       - if expected artifacts exist on disk + post-spawn integrity check passed
         → COMPLETE
       - if expected artifacts missing AND fallback artifact exists with valid
         fallback marker (e.g., COMPILATION_FAILED) → FAILED_WITH_FALLBACK
       - if all attempts exhausted (re-spawn cap hit) → FAILED (non-terminal)
  3. Update row.notes with: agent ID, spawn timestamp, key counts/metrics.

After every orchestrator-inline step completes:
  1. Identify the corresponding row.
  2. Update status as above.
  3. If the orchestrator legitimately skips per design (e.g., Light mode skips Phase 3b/3c)
     → mark NOT_APPLICABLE with non-trivial reason (per `~/.valves/rules/thorough-strict-mode.md` § Valid terminal states).

If a phase is compressed or substituted (e.g., the previous Snuggle run where
HP rogue subprocess agents produced Phase 3 output instead of properly-spawned
breadth agents):
  - DO NOT mark the substituted row COMPLETE based on the substituted output.
  - The legitimate path is: mark FAILED_WITH_FALLBACK with reason citing
    "substituted by [violation citation]; outputs accepted-with-flag" — but
    the row is NOT a clean COMPLETE.
  - Drift detection (§ D below) catches rows incorrectly marked COMPLETE
    despite illegal-writer entries in violations.md.
```

### § D. Row drift detection (at every phase boundary)

At every phase boundary (before advancing to the next phase), the orchestrator runs a mechanical drift scan on `mandatory_step_checklist.md`:

```
For each row in the checklist:
  - if row.status == COMPLETE:
      - check evidence_artifact exists on disk → else SYNTHETIC_COMPLETION violation
      - check writer matches manifest § Control table → else ILLEGAL_WRITER_DRIFT violation
  - if row.status == FAILED_WITH_FALLBACK:
      - check fallback_artifact exists on disk → else FALLBACK_MISSING violation
  - if row.status == NOT_APPLICABLE:
      - check reason is non-trivial → else WEAK_NA_REASON violation
  - if row.status == PENDING but the row's downstream consumer is COMPLETE:
      - DRIFT_DETECTED_PENDING_WITH_COMPLETE_CONSUMER violation
        (this catches the Snuggle case: row 20 PENDING but report rows COMPLETE)

Any drift violation → log to violations.md (HIGH severity); does NOT advance
the phase; triggers Recovery Loop. If recovery exhausted → Phase 6f embargo
blocks finalization.
```

This gate is the mechanical defense against the failure observed in the Snuggle run: it would have caught row 20 PENDING (Phase 4b iter 1 never ran) AND row 47 COMPLETE (report files synthesized) at the SAME time — `DRIFT_DETECTED_PENDING_WITH_COMPLETE_CONSUMER` would have fired before the report was generated.

### § E. COMPLETE_A halt marker check (at EVERY phase boundary, Thorough only) (v1.7-PATCH10.3)

At EVERY phase boundary — the same point where § D runs — the orchestrator MUST also check:

```
if MODE == THOROUGH AND SESSION == "A":
    if file_exists("{SCRATCHPAD}/HALT_AFTER_COMPLETE_A.md"):
        // The halt marker is on disk. Session A MUST NOT continue past this point.
        // This catches the case where context compaction erased the halt instruction
        // but the marker file persists on disk as ground truth.
        print:
        ====================================================================
        HALT — COMPLETE_A BOUNDARY ENFORCED (marker detected)
        ====================================================================
        The file HALT_AFTER_COMPLETE_A.md exists in the scratchpad.
        Session A has reached the COMPLETE_A boundary and MUST stop.

        To run Session B: start a NEW Claude Code conversation and run /valves thorough
        ====================================================================

        HARD HALT. Do NOT spawn any further agents. Do NOT advance to the next phase.
        Do NOT generate report artifacts. The orchestrator's job in this conversation is DONE.
```

This check is the compaction-proof enforcement layer. The original COMPLETE_A halt instruction at line ~2200 can be lost to context compaction in long conversations. The on-disk marker file CANNOT be lost — `file_exists()` is a mechanical check that does not depend on the LLM remembering instructions. By running this check at every phase boundary, the orchestrator is guaranteed to halt within one phase transition of the boundary, even after arbitrary context compaction.

**Why every phase boundary**: If compaction erases the halt, the orchestrator may begin the next phase. The § E check fires at the START of that phase (before any agents spawn), catching the drift before any Session-B-only work executes in Session A.

### § F. Phase-boundary reconciliation + run_state.json update (v1.7-PATCH11.2)

At every phase boundary — the same point where § D and § E run — the orchestrator MUST also:

**(v1.7-PATCH11.2) DISK STATE PRIORITY RULE**: The reconciliation below reads three disk files and reconciles them. If the disk state conflicts with whatever the orchestrator "remembers" from earlier in the conversation, DISK WINS. Specifically: (1) `run_state.json` `checkpoint_level` overrides any in-memory session variable, (2) `mandatory_step_checklist.md` row statuses override any "I already did that" belief, (3) if `HALT_AFTER_COMPLETE_A.md` exists on disk, the run is halted regardless of what the orchestrator planned next. This rule is the mechanical implementation of "disk over conversation" — it makes resume after compaction/interruption/exhaustion deterministic because the LLM re-derives its position from files, not from summarized prior context.

```
// === PATCH11: THREE-WAY RECONCILIATION ===
// Runs AFTER § D (drift detection) and § E (halt marker check)
// Three sources of truth must agree:
//   1. run_state.json (orchestrator's position/intent/session)
//   2. mandatory_step_checklist.md (row statuses)
//   3. manifest files + disk artifacts (ground truth)

rs_path = "{SCRATCHPAD}/run_state.json"
// PATCH11-F: existence assertion before read
if file_exists(rs_path):
    rs = JSON.parse(read(rs_path))

    // Check 1: run_state says last phase done → checklist rows must be terminal
    if rs.last_completed_phase != null:
        phase_rows = get_checklist_rows_for_phase(rs.last_completed_phase)
        for row in phase_rows:
            if row.status not in {COMPLETE, FAILED_WITH_FALLBACK, NOT_APPLICABLE}:
                if file_exists(row.evidence_artifact) AND validity_check(row.evidence_artifact) == VALID:
                    update row.status = COMPLETE
                    log "RECONCILIATION_FIX: row {N} updated to COMPLETE (artifact valid on disk)"
                else:
                    log "RECONCILIATION_DRIFT: run_state says {phase} done but row {N} is {status}"

    // Check 2: active manifest consistency
    if rs.active_manifest != null AND file_exists(rs.active_manifest):
        manifest = parse(rs.active_manifest)
        for row in manifest where Status == "DONE":
            if NOT file_exists(row.Expected_Output) OR validity_check(row.Expected_Output) != VALID:
                log "RECONCILIATION_DRIFT: manifest says {agent} DONE but output invalid/missing"
                row.Status = "FAILED"

// === PATCH11: UPDATE run_state.json for phase transition ===
// Advance checkpoint_level based on session context
new_checkpoint = rs.checkpoint_level
if rs.session in ["A", "A_RESUMED"] AND rs.checkpoint_level == "NONE":
    new_checkpoint = "PARTIAL_A"
elif rs.session in ["B", "B_RESUMED"] AND rs.checkpoint_level in ["COMPLETE_A", "PARTIAL_B"]:
    new_checkpoint = "PARTIAL_B"

// Write full JSON (atomic, never Edit)
rs.current_phase = {new_phase_id}
rs.current_row = null
rs.phase_status = "DONE"
rs.active_manifest = null
rs.last_completed_phase = {phase_just_completed}
rs.last_completed_timestamp = now_iso()
rs.checkpoint_level = new_checkpoint
rs.last_transition = { from_phase: {phase_just_completed}, to_phase: {new_phase_id}, timestamp: now_iso() }
rs.write_ahead = { action: null, action_type: null, targets: [], timestamp: null, interrupted: false }
rs.expected_outputs = []; rs.completed_outputs = []; rs.pending_outputs = []
rs.resume_metadata.recovery_attempts = 0  // Reset on phase transition (documented in execution-state.md § R1)
rs.last_write_iso = now_iso()
Write rs_path (full JSON)
```

This reconciliation runs AFTER § D drift detection (which catches logical drift). § F catches mechanical drift between the three state sources and fixes it where possible. It also updates `run_state.json` for the phase transition — the persistent record that the next session can use to resume. The `checkpoint_level` field advances monotonically with each phase transition, providing a compaction-proof cursor.

### § F.1. Post-hoc handoff synthesis ban (v1.7-PATCH11.3 — Thorough only)

If the orchestrator is in Session A and has advanced past the COMPLETE_A boundary (row 22) WITHOUT having written a valid COMPLETE_A checkpoint + handoff bundle, the run is INVALID for Session B resume. The orchestrator MUST NOT retroactively build the handoff.

**(v1.7-PATCH11.3) EXTENDED BAN**: This ban applies to ALL handoff-related artifacts, not just the six bundle files. The orchestrator MUST NOT retroactively generate ANY of: `session_checkpoint.md` (COMPLETE_A version), `session_a_to_b_handoff.md`, `canonical_seed_map.md`, `coverage_density.md`, `negative_space.md`, `seed_outcomes.md`, `disagreement_queue.md`, `HALT_AFTER_COMPLETE_A.md`, `SESSION_B_READ_SCOPE.md`, `blind_spot_report.md` (when used as handoff substitute). The ban also covers partial reconstruction — writing 3 of 6 bundle artifacts and claiming "partial handoff" is equally prohibited. Either the COMPLETE_A_INLINE_SEQUENCE (§ above) ran to completion at the correct pipeline position, or the run is INVALID.

```
// Runs inside § F, after three-way reconciliation, BEFORE run_state.json update.
if MODE == THOROUGH AND rs.session in ["A", "A_RESUMED"]:
    POST_COMPLETE_A_PHASES = [
        "phase4b_iter2", "phase4b_da", "phase4b_p2", "phase4b_thesis_v2",
        "phase4c", "phase4c_iter2", "phase4c5", "phase5", "phase5_1",
        "phase5_2", "phase5_6", "phase6", "phase6a", "phase6b", "phase6c",
        "phase6d", "phase6e", "phase6e1", "phase6f"
    ]
    if rs.current_phase in POST_COMPLETE_A_PHASES AND rs.checkpoint_level != "COMPLETE_A":
        // Session A advanced past row 22 without halting. This is a boundary skip.
        // The handoff bundle does NOT exist or was never properly written.
        // BAN: do NOT build it now from contaminated state.
        BANNED_ARTIFACTS = [
            "session_checkpoint.md (COMPLETE_A version)",
            "session_a_to_b_handoff.md",
            "canonical_seed_map.md",
            "coverage_density.md",
            "negative_space.md",
            "seed_outcomes.md",
            "disagreement_queue.md"
        ]
        print:
        ====================================================================
        POST_HOC_HANDOFF_SYNTHESIS_BANNED
        ====================================================================
        Session A is at phase {rs.current_phase} but checkpoint_level is
        {rs.checkpoint_level} (expected: COMPLETE_A).

        The orchestrator skipped the COMPLETE_A halt boundary (likely due to
        context compaction). The following artifacts MUST NOT be synthesized
        retroactively from this contaminated single-session state:
          {BANNED_ARTIFACTS}

        This run is INVALID for Session B resume.
        Recovery: /valves thorough fresh-run
        ====================================================================
        log "POST_HOC_HANDOFF_SYNTHESIS_BANNED: at {rs.current_phase} with checkpoint={rs.checkpoint_level}" to violations.md (HIGH)
        HALT
```

**Why this is separate from § E**: § E catches the halt marker on disk. § F.1 catches the case where the halt marker was NEVER written (boundary code was compacted before execution). § E is the primary defense; § F.1 is the backstop for when § E has nothing to check.

### § G. Manifest creation protocol (v1.7-PATCH11 — before EVERY multi-agent spawn)

Before spawning any batch of parallel agents, the orchestrator MUST:
1. Run the **idempotent pre-spawn check** (PATCH11-E) — skip already-complete work.
2. Create a **phase manifest** — the durable record of what was planned, spawned, and completed.

```
// === IDEMPOTENT PRE-SPAWN CHECK (v1.7-PATCH11-E — ALL phases, ALL modes) ===
// Before spawning ANY work unit (agent or orchestrator-inline), check:
//   1. Does the expected output already exist on disk?
//   2. Does it pass the validity check (§ R4)?
//   3. Does it belong to the current session (check run_state.json session field)?
// If all three pass → mark COMPLETE and SKIP the spawn. Do NOT re-run.
// This makes every phase resumable without duplicate work.

IDEMPOTENT_PRE_SPAWN_CHECK(expected_output_path, artifact_class, current_session):
    if NOT file_exists(expected_output_path):
        return SPAWN_NEEDED  // output missing, must spawn

    validity = validity_check(expected_output_path, artifact_class)
    if validity != VALID:
        return SPAWN_NEEDED  // output exists but invalid/malformed

    // Session ownership check: in Session B, verify the artifact was not
    // left over from a PREVIOUS run's Session A (pre-rotation leak).
    // Artifacts in the ALLOWLIST (factual data) are always valid regardless
    // of which session produced them.
    if current_session in ["B", "B_RESUMED"]:
        rs = JSON.parse(read("{SCRATCHPAD}/run_state.json"))
        if rs.checkpoint_level in ["PARTIAL_B", "COMPLETE_B"]:
            // Session B is active, artifact was produced by this session. Valid.
            return SKIP_ALREADY_COMPLETE
        elif rs.checkpoint_level == "COMPLETE_A":
            // Session B hasn't started yet. This artifact is pre-existing.
            // For Session-B-only artifacts, this is suspicious.
            return SPAWN_NEEDED
    else:
        return SKIP_ALREADY_COMPLETE

// Apply to EVERY agent in the manifest before spawning:
CREATE_MANIFEST(phase_id, agents_list):
    // Pre-filter: remove agents whose output is already valid
    agents_to_spawn = []
    for agent in agents_list:
        result = IDEMPOTENT_PRE_SPAWN_CHECK(agent.expected_output, agent.artifact_class, SESSION)
        if result == SKIP_ALREADY_COMPLETE:
            log "IDEMPOTENT_SKIP: {agent.name} — output {agent.expected_output} already valid"
            // Pre-mark DONE in manifest (created below)
        else:
            agents_to_spawn.append(agent)

    if len(agents_to_spawn) == 0:
        // All outputs exist and are valid. Skip entire phase.
        log "IDEMPOTENT_PHASE_SKIP: {phase_id} — all outputs present"
        // Write manifest with all DONE, advance phase
        // ... (continue to manifest creation with pre-marked statuses)

// === MANIFEST CREATION (before spawning agents) ===
// Called by the orchestrator INLINE before each multi-agent phase

CREATE_MANIFEST(phase_id, agents_list):
    manifest_path = "{SCRATCHPAD}/manifest_{phase_id}.md"

    // 1. Write-ahead: update run_state.json with intent
    rs = JSON.parse(read("{SCRATCHPAD}/run_state.json"))
    rs.phase_status = "INTENT"
    rs.write_ahead = {
        action: "Spawn {len(agents_list)} agents for {phase_id}",
        action_type: "SPAWN_AGENTS",
        targets: [agent.expected_output for agent in agents_list],
        timestamp: now_iso(),
        interrupted: true
    }
    rs.active_manifest = manifest_path
    rs.expected_outputs = [agent.expected_output for agent in agents_list]
    rs.pending_outputs = rs.expected_outputs
    rs.completed_outputs = []
    rs.last_write_iso = now_iso()
    Write "{SCRATCHPAD}/run_state.json" (full JSON)

    // 2. Create manifest with all agents in PENDING status
    Write manifest_path:
        # Phase Manifest — {phase_id} — {ISO timestamp}
        ## Phase Context
        - Phase: {phase_id}
        - Mode: {MODE}
        - Session: {SESSION}
        - Total agents planned: {len(agents_list)}
        - Budget slot cost: {sum of slots}

        ## Agent Table
        | # | Agent Name | Model | Expected Output | Status | Spawn Time | Return Time | Notes |
        |---|---|---|---|---|---|---|---|
        {for i, agent in agents_list:}
        | {i} | {agent.name} | {agent.model} | {agent.expected_output} | PENDING | - | - | - |

    // 3. Spawn all agents (parallel or sequential per phase design)
    // 4. On each agent return: update manifest row (Status, Return Time)
    // 5. After all agents: write Completion Summary, update run_state.json

ON_AGENT_RETURN(manifest_path, agent_index, success, output_valid):
    // Update single row in manifest
    manifest = read(manifest_path)
    if success AND output_valid:
        manifest.rows[agent_index].Status = "DONE"
    elif success AND NOT output_valid:
        manifest.rows[agent_index].Status = "EMPTY_OUTPUT"
    else:
        manifest.rows[agent_index].Status = "FAILED"
    manifest.rows[agent_index].Return_Time = {ISO now}
    Write manifest_path (atomic)

ON_ALL_AGENTS_COMPLETE(manifest_path):
    // Write Completion Summary section
    manifest = read(manifest_path)
    done_count = count(rows where Status == "DONE")
    failed_count = count(rows where Status == "FAILED")
    empty_count = count(rows where Status == "EMPTY_OUTPUT")
    tainted_count = count(rows where Status == "TAINTED")
    total = len(rows)

    outcome = "COMPLETE" if done_count == total
              else "PARTIAL" if done_count > 0
              else "FAILED"

    Append to manifest_path:
        ## Completion Summary
        - Agents completed: {done_count}/{total}
        - Agents failed: {failed_count}
        - Agents with empty output: {empty_count}
        - Agents tainted: {tainted_count}
        - Phase outcome: {outcome}

    // Update run_state.json
    rs = JSON.parse(read("{SCRATCHPAD}/run_state.json"))
    rs.phase_status = "DONE"
    rs.write_ahead.interrupted = false
    rs.resume_metadata.total_spawns_this_session += total
    rs.resume_metadata.total_failures_this_session += failed_count
    rs.completed_outputs = [row.Expected_Output for row in manifest where Status == "DONE"]
    rs.pending_outputs = [row.Expected_Output for row in manifest where Status != "DONE"]
    rs.last_write_iso = now_iso()
    Write "{SCRATCHPAD}/run_state.json" (full JSON)
```

**Which phases create manifests** (non-exhaustive — the orchestrator creates manifests for ANY phase that spawns 2+ agents in parallel):

| Phase | Manifest File | Agents Tracked |
|-------|--------------|----------------|
| Phase 1 (recon) | `manifest_phase1.md` | 1A, 1B, 2, 3 |
| Phase 3 (breadth) | `manifest_phase3.md` | All breadth agents |
| Phase 3b (re-scan) | `manifest_phase3b.md` | Re-scan agents per iteration |
| Phase 3c (per-contract) | `manifest_phase3c.md` | Per-contract agents |
| Phase 4a.5 (sem inv + harvester) | `manifest_phase4a5.md` | Sem inv + breakpoints + P1 + harvester + assumption-breaker |
| Phase 4b iter 1 (depth) | `manifest_phase4b_iter1.md` | 4 depth + 3 scanners + validation sweep + niche + injectable + DST |
| Phase 4b iter 2 (DA) | `manifest_phase4b_iter2.md` | DA agents (Session B) |
| Phase 4b P2 (propagation) | `manifest_phase4b_p2.md` | Per-cluster propagation agents |
| Phase 4c (chain) | `manifest_phase4c.md` | Chain agent 1 + 2 (sequential but tracked) |
| Phase 5 (verification) | `manifest_phase5_batch_{A/B/C/D}.md` | Verifier agents per batch |
| Phase 6 (report) | `manifest_phase6.md` | Index + 3 tier writers + assembler |

**Resume from manifest**: On resume, the universal resume sweep (Step 0-pre) reads `rs.active_manifest` from `run_state.json`, parses the manifest, and re-spawns only agents with Status ≠ DONE. See `~/.valves/rules/execution-state.md` § R3 for manifest schema and resume algorithm.

### § H. Write-ahead intent protocol (v1.7-PATCH11 — before EVERY orchestrator action)

For non-manifest actions (orchestrator-inline writes, checkpoint writes, phase transitions), the orchestrator writes a lightweight intent to `run_state.json` before acting:

```
WRITE_AHEAD_INTENT(action_desc, action_type, target_files):
    rs = JSON.parse(read("{SCRATCHPAD}/run_state.json"))
    rs.phase_status = "INTENT"
    rs.write_ahead = {
        action: action_desc,
        action_type: action_type,  // ORCHESTRATOR_INLINE | CHECKPOINT_WRITE | PHASE_TRANSITION
        targets: target_files,
        timestamp: now_iso(),
        interrupted: true
    }
    rs.expected_outputs = target_files
    rs.pending_outputs = target_files
    rs.completed_outputs = []
    rs.last_write_iso = now_iso()
    Write "{SCRATCHPAD}/run_state.json" (full JSON)

    // Execute the action...

    // On success:
    rs.phase_status = "DONE"
    rs.write_ahead.interrupted = false
    rs.write_ahead.action = null
    rs.completed_outputs = target_files
    rs.pending_outputs = []
    rs.last_write_iso = now_iso()
    Write "{SCRATCHPAD}/run_state.json" (full JSON)
```

This applies to: PARTIAL_A checkpoint writes, COMPLETE_A boundary, scratchpad rotation, handoff bundle writes, pipeline trace appends, checklist updates (when writing large batches), and any orchestrator-inline artifact write that takes >1 tool call.

**Single-tool-call actions** (e.g., appending one line to pipeline_trace.md) do NOT require write-ahead intent — the overhead exceeds the crash risk. The threshold: if the action requires ≥2 sequential Write/Edit calls to produce a valid artifact, use write-ahead intent.

---

## Phase 1: Reconnaissance

### Step 0.85a: Initialize Mandatory Step Checklist (VALVES v1.5, Thorough only)

Orchestrator inline. ALWAYS-ON when `MODE == THOROUGH`. SKIPPED for Light/Core (those use the looser Rule 12 semantics).

Create `{scratchpad}/mandatory_step_checklist.md` with all rows initialized to `PENDING`. The base row list is defined in `~/.valves/rules/thorough-strict-mode.md` § Step Rows (rows 01-73 as of v1.7-PATCH5; baseline rows 01-50 + v1.7-PATCH appended rows 51-73). Niche-agent rows (Row 23) are placeholders at this point -> they get DYNAMICALLY APPENDED at end of Phase 1 once `template_recommendations.md` is read and Required niche agents are known.

This checklist becomes the watchdog's named-step input. Every phase gate from now on checks BOTH artifacts AND named-step status from this file. See Rule 28 in `~/.valves/CLAUDE.md`.

### Step 0.85b: Initialize Pipeline Trace (VALVES v1.4)

Orchestrator inline, ALWAYS-ON. Create `{scratchpad}/pipeline_trace.md` with the header:

```markdown
# Pipeline Trace -> {project} -> {ISO timestamp}

## Configuration
- Mode: {Light / Core / Thorough}
- Historical Prime: {ON / OFF}
- Benchmark: {ON / OFF}
- PROVEN_ONLY: {true / false}
- Total budget: (computed at Phase 2)

## Phase Trace

| Phase | Agents Spawned | Findings In | Findings Out | Dropped | Absorbed | Escalated | Demoted | Notes |
|-------|----------------|------------:|-------------:|--------:|---------:|----------:|--------:|-------|
```

The orchestrator APPENDS one row after every phase transition (Phase 1, 1.2, 1.5, 3, 4a.1-pre, 3b, 3c, 4a.1-final, 4a.1.5, 4a.2, 4a.3, 4a.5.a, 4a.5.b, 4a.5.c, **4a.5.d, 4a.5.e, 4a.5.f**, 4b iter 1, 4b thesis v2, 4b P2, 4b iter 2, 4c.1, 4c.2, 4c.5, 5, 5.1, 5.2, 5.5, 5.6, 5.6.5, 6a, 6b, 6c, 6d, **6d.5**, 6e, **6e-PATCH**) PLUS the COMPLETE_A handoff sub-step transition `A2B-handoff-build` (v1.7-PATCH -> writes coverage_density / negative_space / seed_outcomes / canonical_seed_map / disagreement_queue / session_a_to_b_handoff in one bundle). Note: `4a.1-pre` = initial inventory (exclusion list), `4a.1-final` = inventory merge/refresh after 3b/3c, `4a.5.d` = Structural Anomaly Harvester (8 sweeps), `4a.5.e` = Assumption-Breaker Pass (PATCH H), `4a.5.f` = Bounded Analog Seeding (PATCH G, conditional per v1.7-PATCH2), `A2B-handoff-build` = COMPLETE_A pre-checkpoint sub-step (PATCH A/B/C/E/I + canonical_seed_map per v1.7-PATCH2), **`6d.5` = Final Strongest-Exploit Sanity Check (v1.7-PATCH5 PATCH 1) — produces strongest_exploit_final_check.md**, `6e-PATCH` = Phase 6e measurement-artifact tail (PATCH K).

Row population is mechanical -> read the relevant scratchpad artifact's output, count findings, compare to prior phase's output. See `~/.valves/rules/pipeline-trace.md` § Orchestrator Write Protocol.

### Step 0.85c: Initialize Run State (v1.7-PATCH11.1 — ALL MODES)

Orchestrator inline, ALWAYS-ON. Create `{scratchpad}/run_state.json` as a JSON file. This is the orchestrator's durable memory of pipeline position, session identity, and checkpoint level. It survives context compaction and session boundaries.

**RUN_ID generation (v1.7-PATCH11.3-CANTINA)**:
Generate a unique run identifier: `RUN_ID = "VALVES-{YYYYMMDD}-{HHMMSS}-{4 random hex chars}"` (e.g., `VALVES-20260508-143022-a7f3`). Use Bash: `date +%Y%m%d-%H%M%S` + `openssl rand -hex 2` (or Python equivalent). This RUN_ID is:
- Written into `run_state.json` as the `run_id` field
- Passed to every agent prompt via the scope directive (see § Agent Artifact Stamping below)
- Used by `VALIDATE_STEP_COMPLETION()` to detect stale artifacts from prior runs
- Preserved on resume (read from existing `run_state.json`), regenerated only on `fresh-run`

```
Write "{SCRATCHPAD}/run_state.json":

{
  "version": "PATCH11.1",
  "run_id": "{RUN_ID}",
  "project_name": "{project_name}",
  "last_write_iso": "{ISO timestamp}",

  "mode": "{MODE}",
  "session": "A",
  "checkpoint_level": "NONE",
  "language": "{LANGUAGE}",
  "project_root": "{PROJECT_ROOT}",
  "scratchpad": "{SCRATCHPAD}",
  "valves_ver": "{VALVES_VER}",
  "plamen_ver": "{PLAMEN_VER}",

  "current_row": null,
  "current_phase": "phase1",
  "phase_status": "DONE",
  "active_manifest": null,
  "last_completed_phase": null,
  "last_completed_timestamp": "{ISO timestamp}",

  "expected_outputs": [],
  "completed_outputs": [],
  "pending_outputs": [],

  "spawned_agents": 0,
  "interrupted_agents": [],

  "last_transition": {
    "from_phase": null,
    "to_phase": "phase1",
    "timestamp": "{ISO timestamp}"
  },

  "halt_reason": null,

  "write_ahead": {
    "action": null,
    "action_type": null,
    "targets": [],
    "timestamp": null,
    "interrupted": false
  },

  "resume_metadata": {
    "total_spawns_this_session": 0,
    "total_failures_this_session": 0,
    "last_agent_spawned": null,
    "recovery_attempts": 0
  }
}
```

**Write protocol for the rest of the pipeline**: Before every agent spawn or orchestrator-inline write, update `run_state.json` with the write-ahead intent (`phase_status: "INTENT"`, `write_ahead.interrupted: true`, fill `write_ahead` fields, update `expected_outputs`). After success, write `phase_status: "DONE"`, `write_ahead.interrupted: false`, move targets to `completed_outputs`. See `~/.valves/rules/execution-state.md` § R1 + § R2 for full protocol.

**Atomic write rule**: `run_state.json` is ALWAYS written as a complete JSON file (using Write tool, not Edit tool). This prevents partial writes from corrupting the state if the conversation is interrupted mid-write.

**Phase transition protocol**: At every phase boundary, also update `checkpoint_level`:
- Session A phase transitions: set `checkpoint_level: "PARTIAL_A"` (overwrites NONE)
- COMPLETE_A boundary: set `checkpoint_level: "COMPLETE_A"`, `halt_reason: "COMPLETE_A_BOUNDARY"`
- Session B entry: set `checkpoint_level: "PARTIAL_B"`, `session: "B"` (BEFORE any Session B work)
- Session B phase transitions: update `checkpoint_level: "PARTIAL_B"` (rewritten with current_phase)
- Phase 6e+1 Session B Closure: set `checkpoint_level: "COMPLETE_B"`

### Step 0.9: Initialize Pipeline Watchdog

After creating the scratchpad directory and before spawning recon agents, initialize the watchdog:

```bash
PY_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null) && "$PY_CMD" ~/.claude/hooks/phase_gate.py --init "{scratchpad}" {MODE} "{PROJECT_PATH}"
```

This activates the Stop hook enforcement. The watchdog will verify artifact existence at each phase transition and block the orchestrator if mandatory steps are skipped. **Thorough mode**: if `~/.claude/hooks/phase_gate.py` is missing or fails to initialize, ABORT before Recon -> the entire v1.5 fail-closed guarantee depends on watchdog enforcement. **Core/Light mode**: non-fatal if the hook script is missing -> the pipeline continues without enforcement.

### Step 1: Read Recon Prompt
**Read full prompt from**: `~/.claude/prompts/{LANGUAGE}/phase1-recon-prompt.md`

Replace placeholders: `{path}`, `{scratchpad}`, `{docs_path_or_url_if_provided}`, `{network_if_provided}`, `{scope_file_if_provided}`, `{scope_notes_if_provided}`

### Step 1b: Spawn 4 Recon Agents (MANDATORY SPLIT)

**Do NOT spawn a single monolithic recon agent.** Read the ORCHESTRATOR SPLIT DIRECTIVE in the prompt header and split into 4 agents. The prompt file may contain 4 separate `Task()` blocks (Solana/Aptos/Sui) or 1 monolithic block with a split directive (EVM) -> in either case, split as follows:

| Agent | Spawn | Model | Await? |
|-------|-------|-------|--------|
| **1A (RAG)** | `run_in_background: true` | sonnet | **NO** -> fire-and-forget |
| **1B (Docs + External)** | foreground | opus (Core/Thorough) or sonnet (Light) | YES |
| **2 (Build + Slither)** | foreground | sonnet | YES |
| **3 (Patterns + Surface)** | foreground | opus (Core/Thorough) or sonnet (Light) | YES |

**Agent 1A is FIRE-AND-FORGET**: spawn in background, never block on it. If it hasn't returned when 1B/2/3 finish, write fallback `meta_buffer.md` and proceed.

**Light mode override**: Spawn only 2 merged agents (both sonnet, both foreground). Skip RAG (Agent 1A) and fork ancestry entirely per Light Mode Orchestration override #2.

### After Agents 1B, 2, 3 Return
1. Verify artifacts exist: `ls {scratchpad}/`
2. Read: `recon_summary.md`, `template_recommendations.md`, `attack_surface.md`
2b. **Operational Implications quality gate (Rule 14)**: Read `{scratchpad}/design_context.md`. Verify it contains an `## Operational Implications` section with at least one implication per documented Key Invariant. If the section is missing or contains fewer implications than invariants, re-prompt Agent 1B: `"The Operational Implications section in design_context.md is incomplete. For each Key Invariant, state what it means for how the system's accounting works -> not what it checks, but what it tells you about the system's model. Derive from invariant formulas and data structure signatures."` This gate prevents downstream agents from analyzing a protocol they don't understand.
3. **RAG resilience check**: If `meta_buffer.md` does not exist or is empty (Agent 1A still running or failed):
   - Spawn lightweight RAG-retry agent (haiku, <2 min, 3 queries only):
     1. get_common_vulnerabilities(protocol_type)
     2. get_attack_vectors(primary_pattern)
     3. search_solodit_live(protocol_category=[category], quality_score=3, max_results=10)
   - Write results to meta_buffer.md
   - If retry also fails: proceed with empty meta_buffer.md
4. **Hard gate**: ALL artifacts must exist before Phase 2

### Step 1.2: Historical Prime Ingest (VALVES v1.3 -> benchmark/rerun mode only)

> **Skip entirely when `HISTORICAL_PRIME_MODE` is not set or false.** This step does NOT run by default for fresh audits.

> **Purpose**: Ingest prior audit reports to seed the current run with regression-detection inputs. See `~/.valves/rules/historical-prime.md`.

**Detection (orchestrator inline, always runs):**

```bash
# Scan for prior audit reports
prior_report_paths=$(find "{PROJECT_PATH}" -maxdepth 3 -type f \( \
  -path "*/AUDIT_REPORTS/*" -o \
  -path "*/reports/*" -o \
  -path "*/audits/*" -o \
  -name "*audit*.md" -o \
  -name "*AUDIT*.md" -o \
  -name "*report*.md" -o \
  -name "*REPORT*.md" -o \
  -name "*final*.md" \
\) -size +2k 2>/dev/null | head -20)
```

**Decision table:**

| Scan result | `$ARGUMENTS` | Action |
|-------------|-------------|--------|
| Zero files | no `benchmark`/`rerun` flag | Skip Step 1.2 entirely |
| Files found | no flag | `AskUserQuestion`: "Prior audit report(s) detected: {list}. Enable Historical Prime? [Yes / No fresh audit]". If "Yes" -> `HISTORICAL_PRIME_MODE = true`. If "No" -> skip. |
| Zero files | `benchmark` or `rerun` flag | Proceed with empty seeds; log `HISTORICAL_PRIME_REQUESTED_NO_REPORTS` to `violations.md` |
| Files found | `benchmark` / `rerun` / `prime:` | Proceed with full ingest (no prompt) |

**Spawn (when ACTIVE):**

Spawn ONE sonnet Prior-Report Ingest Agent in parallel with recon. Input: the detected paths. Output: `{SCRATCHPAD}/historical_prime_seeds.md`. Methodology: `~/.valves/rules/historical-prime.md` § Phase 1.2.

**HARD SCOPE PROHIBITIONS (v1.7-PATCH10 — MANDATORY in HP prompt)**: when composing the HP agent prompt, the orchestrator MUST append the following hard-scope block at the END of the prompt, verbatim:

```
====================================================================
HARD SCOPE PROHIBITIONS (v1.7-PATCH10 — non-negotiable)
====================================================================

You are the Historical Prime Ingest Agent. Your ENTIRE job is:
  (1) Read the prior audit report file paths provided.
  (2) Extract findings into seeds with disposition CONFIRMED / CLEARED / DEFERRED.
  (3) Write EXACTLY ONE file: {SCRATCHPAD}/historical_prime_seeds.md
  (4) Return a short summary message and STOP.

You MUST NOT:
  - Write `recon_summary.md`, `spawn_manifest.md`, `template_recommendations.md`,
    `attack_surface.md`, `design_context.md`, `meta_buffer.md`, `findings_inventory.md`,
    or ANY other file. You own ONLY `historical_prime_seeds.md`.
  - Act as the orchestrator. You are NOT the orchestrator. The orchestrator
    decides phase order, agent count, model selection, and merge hierarchy. You
    do not.
  - Spawn breadth agents, depth agents, or any other agents. You do not run
    `claude --print`, `claude -p`, `npx claude`, `bunx claude`, `yarn claude`,
    `exec claude`, `spawn claude`, `sh -c "claude...`, `bash -c "claude...`,
    or any subprocess that invokes another Claude / LLM process.
  - Run Phase 2 (instantiation), Phase 3 (breadth), or any other phase. Even
    if you believe you can do it cheaper or better, that is NOT your job.
  - Write a binding manifest, a spawn manifest, or any orchestrator-owned
    artifact per `~/.valves/rules/artifact-ownership.md` § Control table.

If you find that you have completed reading the prior reports and want to do
"more useful work" — STOP. Return the summary. The orchestrator will continue
the pipeline.

Your tool trace will be scanned after you return. Any forbidden Bash pattern
(any sub-orchestration command listed above) will:
  1. Cause your output to be marked TAINTED in degradation_log.md
  2. Trigger AUTO-DISCARD of historical_prime_seeds.md (your work is invalidated)
  3. Re-spawn this agent ONCE with even stricter prompt
  4. If the re-spawn also violates: halt the run and emit
     INVALID_FINALIZATION_AGENT_SCOPE_PERSISTENT to compliance_summary.md

This rule is mechanical, not aspirational. The orchestrator does NOT review
your tool trace for "intent" or "quality of off-script work" — any forbidden
pattern means AUTO-DISCARD regardless of how good the off-script output looks.

See `~/.valves/rules/valves-doctrine.md` § Agent tool discipline for the
authoritative rule and `~/.valves/rules/artifact-ownership.md` § Control table
for the artifact-ownership map.
====================================================================
```

**Downstream propagation**: every seed must reach a disposition (CONFIRMED/CLEARED/DEFERRED) by Phase 6 -> silent drops log as `PRIME_SEED_DROP` to `violations.md`.

**Post-spawn integrity check (v1.7-PATCH10 — MANDATORY)**: when the HP agent returns, the orchestrator MUST run the universal post-spawn integrity check per `~/.valves/rules/artifact-ownership.md` § Universal post-spawn integrity check. The HP agent is a high-risk spawn (it has Bash + situational awareness of the pipeline plan); the post-spawn check is non-skippable.

### Step 1.5: Reference Diff-Audit (VALVES -> Core and Thorough only)

> **Purpose**: Catches bugs introduced when the team modifies a known reference (Uniswap V3, OpenZeppelin, Aave, Compound, Balancer, ERC4626). Emits Tier A/B/C global prioritization signal. See `~/.valves/rules/reference-diff-audit.md`.

> **Skip in Light mode**.

> **Trigger**: Agent 1B's fork-ancestry output in `meta_buffer.md` identified a known parent, OR `contract_inventory.md` flagged a fork pattern.

**Orchestrator flow**:

1. Read `meta_buffer.md` section `## Fork Ancestry Analysis`. If no parent is detected, skip this step.
2. For each detected parent, resolve the reference source:
   - Local vendored copy (`lib/`, `vendor/`, or `node_modules/`)
   - URL cited in `design_context.md` (fetch via WebFetch if allowed)
   - Valves-bundled reference at `~/.valves/references/{parent_name}.sol` (per the manifest at `~/.valves/references/MANIFEST.md` -> v1.7-PATCH3 PATCH 5; SHA-256 verification when present)
3. If no reference resolvable, log `"reference unavailable for {parent}"` in `{scratchpad}/diff_audit_log.md` and skip that parent.
4. For each resolved (target, reference) pair, spawn one diff-audit agent. Up to 4 agents in parallel, all opus.
5. Each agent writes `{scratchpad}/diff_audit_{parent_name}.md` including a **Global Tier** field per function (A/B/C per `~/.valves/rules/reference-diff-audit.md`).
6. After all diff-audit agents return, orchestrator merges per-parent tier data into `{scratchpad}/diff_audit_tiers.md` with Tier A/B/C rows and assigned depth agent per row.
7. Every Tier A entry becomes a MANDATORY depth target in Phase 4b iteration 1. Every Tier B becomes RECOMMENDED. Tier C is logged only.
8. Depth agent prompts in Phase 2 are injected with their assigned Tier A/B entries from `diff_audit_tiers.md`.

**Hard rule**: diff-audit runs in parallel with Phase 2 instantiation. It must complete before Phase 4b begins so Tier A/B targets can be injected into depth agent prompts.

---

## Phase 2: Orchestrator Instantiation

### Step 2a: Determine Agent Count
| Condition | Agent Count |
|-----------|-------------|
| Simple (<5 deps, <2000 lines) | 3 agents |
| Medium (5-10 deps, 2000-5000 lines) | 5-7 agents |
| Complex (>10 deps or >5000 lines) | 7-9 agents |

**Minimum always**: 1 core state, 1 access control, 1 per major external dep (overrides Simple tier if needed)

**Breadth-to-depth redirect**: When actual breadth agent count is below the Medium baseline (5), the saved slots increase the depth budget floor: `depth_floor = 12 + (5 - actual_breadth_count)`.

### Step 2a.1: Merge Hierarchy (when required templates exceed target count)

| Priority | Merge | Rationale |
|----------|-------|-----------|
| M1 | TEMPORAL_PARAMETER_STALENESS + core state agent | Cached params are state mutations |
| M2 | SEMI_TRUSTED_ROLES + access control agent | Roles are access control |
| M3 | SHARE_ALLOCATION_FAIRNESS + core state agent | Allocation fairness is state correctness |
| M4 | ECONOMIC_DESIGN_AUDIT + core state agent | Monetary params are state correctness |
| M5 | EXTERNAL_PRECONDITION_AUDIT + external dependency agent | External preconditions are external dep analysis |

**Rules**: Never merge two skills both requiring >5 analysis steps. Never merge across incompatible domains. **Never merge FLASH_LOAN_INTERACTION or ORACLE_ANALYSIS with any other skill.** **Max 2 templates per agent (including injectables) AND max 300 combined SKILL.md lines.** If a 2-template merge would exceed 300 lines, split into an additional breadth agent instead. Narrower scope per agent improves depth -> agents reliably execute ~300 lines of skill payload but degrade on larger prompts (validated by multi-agent audit research: LLMBugScanner, iAudit).

### Step 2a.2: Move-Safety Agent (Aptos/Sui only)

For Aptos and Sui audits, the 4 always-required skills (ABILITY_ANALYSIS, BIT_SHIFT_SAFETY, TYPE_SAFETY, REF_LIFECYCLE/OBJECT_OWNERSHIP) total ~900-950 lines -> far exceeding the 300-line breadth agent cap. These are split into two delivery layers:

1. **Core directives** (~130 lines): Loaded into EVERY breadth agent via `~/.claude/agents/skills/{LANGUAGE}/move-safety-core-directives/SKILL.md`. Contains inventory greps + flag tables. Counts toward the 300-line cap but leaves ~170 lines for conditional skills.
2. **Move-Safety Agent** (1 dedicated agent): Spawned in Phase 3 alongside breadth agents. Loads ALL 4 full skill files (~950 lines). Runs the complete trace methodology that breadth agents cannot fit. Costs 1 breadth agent slot.

The Move-Safety Agent prompt: load all 4 always-required SKILLs into a single agent with scope = "full Move-specific safety analysis." Its findings feed into `findings_inventory.md` alongside breadth findings. Depth agents still receive full skills per their injection rules (depth agents have separate context windows, not subject to the breadth merge cap).

**EVM/Solana**: No Move-Safety Agent needed. EVM has no always-required skills. Solana has ACCOUNT_VALIDATION (130 lines) which fits within the 300-line cap.

### Step 2b: Instantiate Templates
For each template in `template_recommendations.md`:
1. Read template from `~/.claude/agents/skills/{LANGUAGE}/{template-name}/SKILL.md` (folder name is lowercase-hyphenated version of the template name, e.g., ORACLE_ANALYSIS -> oracle-analysis)
2. For Aptos/Sui breadth agents: load `move-safety-core-directives/SKILL.md` instead of the 4 individual always-required skills. The full skills go to the Move-Safety Agent only.
3. Replace `{PLACEHOLDERS}` with instantiation parameters
4. **Conditional loading**: Strip sections wrapped in `<!-- LOAD_IF: FLAG -->...<!-- END_LOAD_IF: FLAG -->` when the flag was NOT detected
5. Compose agent prompt with instantiated template

### Step 2b.1: Load Injectable Skills (Split Delivery)
1. Read protocol type from `{scratchpad}/template_recommendations.md` -> `## Injectable Skills`
2. For each recommended injectable: Read from `~/.claude/agents/skills/injectable/{skill-name}/SKILL.md`
3. **Breadth agents**: Extract ONLY section headers + key questions (1-line per section, ~200 tokens max)
4. **Depth agents (Phase 4b)**: Generate specific investigation questions per depth domain. Spawn **dedicated Injectable Investigation Agents** (sonnet, 1 per domain) IN PARALLEL with main depth agents
5. Injectable skills spawn up to 4 dedicated sonnet agents (1 per domain), each costing 1 depth budget slot

### Step 2b.2: Merge Cap Enforcement Gate (MANDATORY)

**BEFORE composing any agent prompt**, the orchestrator MUST verify the 300-line cap mechanically:

```
For each planned breadth agent:
  combined_lines = 0
  For each SKILL.md assigned to this agent:
    line_count = wc -l ~/.claude/agents/skills/{LANGUAGE}/{skill-name}/SKILL.md
    combined_lines += line_count
  ASSERT: combined_lines <= 300
  If FAIL:
    Log: "MERGE CAP VIOLATED: Agent {N} has {combined_lines} lines ({skill_list}). Splitting."
    Split the largest skill into its own dedicated agent.
    Re-run this gate.
```

**This is a mechanical check -> run `wc -l` on actual files, do not estimate.** The 300-line cap was validated by multi-agent audit research (LLMBugScanner, iAudit): agents reliably execute ~300 lines of skill payload but degrade on larger prompts. Violations of this cap directly cause RC-AGENT misses where methodology exists but agents don't execute it.

**Soroban note**: Soroban skills average 30% larger than Solana equivalents. Merges that fit at Solana sizes often exceed 300 lines at Soroban sizes. Always check -> never assume a merge that works for one language works for another.

### Step 2c: Agent Prompt Structure
```
You are Analysis Agent #{N}: {FOCUS_AREA}

## Protocol Context
{Brief from design_context.md}

## Your Analysis Task
{INSTANTIATED_TEMPLATE}

## Analysis Strategy -> Targeted Sweeps
Do NOT attempt to find all vulnerability types in a single pass.
Instead, for each vulnerability class in your methodology:
1. Sweep the ENTIRE scope for THIS class specifically
2. Write findings for this class before moving on
3. Proceed to the next vulnerability class

## Artifacts Available
{list scratchpad files}

## Relevant Excerpts (Valves Rule 18 -> FILTERED INJECTION)
{Inject ONLY filtered excerpts of Valves artifacts relevant to this agent's domain / assigned BCs / assigned breakpoints. Max 40 lines or ~800 tokens per artifact. Do NOT inject full files. When no filtered view is possible, inject a summary table (ID + 1-line description) instead.}

## Pattern Detection Checklist (Valves Rule 34 -> from 50k-finding Solodit corpus)
{Inject the compact detection checklist for this agent's assigned Solodit clusters from {SCRATCHPAD}/relevant_patterns.md § Detection Checklists. Max 3 clusters per agent, max 40 lines per cluster. These are grep targets and known failure modes from real audit findings — use them as a coverage cross-check AFTER applying your primary methodology, not as a replacement for it.}

## Cantina Pattern Shortlist (Valves Rule 34 -> from 279-finding competition corpus)
{Inject the compact Cantina detection checklist for this agent's assigned Cantina clusters from {SCRATCHPAD}/relevant_patterns.md § Cantina Detection Checklists. Max 2 Cantina clusters per agent, max 20 lines per cluster. These are additional coverage patterns from real DeFi competition findings — use them as a secondary cross-check AFTER your primary methodology and Solodit cross-check. Methodology first, Solodit patterns second, Cantina patterns third.}

## Output Requirements
Write to {SCRATCHPAD}/analysis_{focus_area}.md
Use finding IDs: [{PREFIX}-1], [{PREFIX}-2]...

SCOPE: Write ONLY to your assigned output file. Do NOT read or write other agents' output files. Do NOT proceed to subsequent pipeline phases (chain analysis, verification, report). Return your findings and stop.

ARTIFACT STAMP (Rule 36): The FIRST line of every file you write MUST be this exact header (replace values):
`<!-- VALVES-ARTIFACT run_id:{RUN_ID} producer:{YOUR_AGENT_ID} phase:{PHASE} session:{SESSION} -->`
Example: `<!-- VALVES-ARTIFACT run_id:VALVES-20260508-143022-a7f3 producer:breadth-2 phase:3 session:A -->`
This header enables stale artifact detection on resume. Files without this header may be flagged as stale and discarded.
```

### Step 2c.1: MCP Timeout Directive (MANDATORY -> Rule 11)

Every agent prompt that makes MCP tool calls (recon agents, depth agents, chain agents, verifiers, RAG sweep) MUST include this directive at the end of its prompt:

*"When an MCP tool call returns a timeout error or fails, do NOT retry the same call. Record [MCP: TIMEOUT] and skip ALL remaining calls to that provider -> switch immediately to fallback (code analysis, grep, WebSearch). Claude Code's tool timeout is set to 300s (5 min) via MCP_TOOL_TIMEOUT in settings.json to accommodate ChromaDB cold start. You cannot cancel a pending call -> but you control what happens after the error returns."*

The orchestrator MUST append this text when composing prompts for MCP-calling agents. Agents that do not make MCP calls (pure code analysis breadth agents, report writers) do not need it.

### Step 2c.2: Agent Artifact Stamping Directive (MANDATORY -> Rule 36, ALL agents)

Every agent prompt (breadth, depth, scanner, niche, chain, verifier, report writer, inventory, scoring — ALL of them) MUST include the RUN_ID and artifact stamp directive. The orchestrator reads `RUN_ID` from `{SCRATCHPAD}/run_state.json` and injects it into each agent prompt.

**Directive text** (append to every agent prompt, after SCOPE if present):

*"ARTIFACT STAMP (Rule 36): The FIRST line of every file you write MUST be: `<!-- VALVES-ARTIFACT run_id:{RUN_ID} producer:{YOUR_AGENT_ID} phase:{PHASE} session:{SESSION} -->` — Replace {YOUR_AGENT_ID} with your agent identifier (e.g., breadth-2, depth-token-flow, verifier-batch-1), {PHASE} with the current pipeline phase (e.g., 3, 4b, 5, 6b), and {SESSION} with A or B. This header enables stale artifact detection on resume. Files without this header may be flagged as stale."*

**Orchestrator responsibility**: Before composing any agent prompt, read `run_state.json` to get `run_id` and `session`. Replace `{RUN_ID}` and `{SESSION}` in the directive text with actual values. `{PHASE}` and `{YOUR_AGENT_ID}` are left for the agent to fill based on its assignment.

### Step 2d: Spawn Verification Gate (MANDATORY)

**BEFORE spawning agents**:
1. Read BINDING MANIFEST from `{scratchpad}/template_recommendations.md`
2. Verify agent queued for EACH template marked `Required: YES`
3. If ANY required template missing -> **HALT and add**

**Write spawn manifest** to `{scratchpad}/spawn_manifest.md`:
```markdown
# Spawn Manifest
| Template | Required? | Agent ID | Focus Area | Status |
|----------|-----------|----------|------------|--------|
**Gate Check**: All REQUIRED templates have agents? [YES/NO]
```

### Step 2e: Pattern Cluster Selection (VALVES v1.7-PATTERN + v1.7-CANTINA, orchestrator inline)

> **Purpose**: Select relevant vulnerability pattern clusters from the Solodit library (562 patterns, 50k findings) AND the Cantina library (80 patterns, 279 competition findings) and generate compact detection checklists for breadth/depth/DA agents. See Rule 34 in `~/.valves/CLAUDE.md`.

**Inputs**: `{scratchpad}/design_context.md` (protocol type, external deps), `{scratchpad}/template_recommendations.md` (skill flags), `~/.valves/patterns/PATTERN_INDEX.md` (Solodit index), `~/.valves/patterns/cantina/CANTINA_PATTERN_INDEX.md` (Cantina index).

**Step 2e.1: Identify Protocol Type**

From `design_context.md` and `template_recommendations.md`, classify the protocol into one or more types from the Cross-Cluster Pattern Mapping table in `PATTERN_INDEX.md`:

| Protocol Type | Matching Signals |
|---------------|-----------------|
| Lending | `liquidate`, `borrow`, `repay`, `healthFactor`, `collateral`, LENDING_PROTOCOL_SECURITY injectable |
| DEX/AMM | `swap`, `addLiquidity`, `pool`, `AMM`, DEX_INTEGRATION_SECURITY injectable |
| Vault/Yield | `ERC4626`, `totalAssets`, `convertToShares`, VAULT_ACCOUNTING injectable |
| Bridge | `lzReceive`, `ccipReceive`, `bridge`, CROSS_CHAIN_MSG flag |
| Governance | `Governor`, `vote`, `propose`, GOVERNANCE_ATTACK_VECTORS injectable |
| NFT/Gaming | `ERC721`, `ERC1155`, NFT_PROTOCOL_SECURITY injectable |
| Staking | staking receipt tokens, STAKING_RECEIPT_TOKENS flag |
| Reward Emission | `rewardRate`, `rewardPerToken`, `earned`, `stake`/`unstake`, `slash`, `boost`, `epoch`, `accrue`, `distribute` → sets `REWARD_EMISSION` flag |

If no specific type matches, use a baseline set: `access-control`, `arithmetic-precision`, `reentrancy`, `initialization`, `logic-errors`.

**Step 2e.1.5: Select Cantina Clusters**

Using the matched protocol type(s) from Step 2e.1, select relevant Cantina clusters from `~/.valves/patterns/cantina/CANTINA_PATTERN_INDEX.md`:

| Protocol Type | Cantina Clusters (auto-selected) |
|---------------|----------------------------------|
| Lending | cantina-lending-liquidation, cantina-logic-errors, cantina-arithmetic-precision |
| DEX/AMM | cantina-dex-amm-logic, cantina-frontrunning-mev, cantina-arithmetic-precision |
| Vault/Yield | cantina-vault-share-accounting, cantina-arithmetic-precision, cantina-logic-errors |
| Bridge | cantina-bridge-cross-chain, cantina-access-control |
| Staking | cantina-reward-accounting (if REWARD_EMISSION), cantina-access-control |
| Reward Emission | cantina-reward-accounting (ALWAYS when flag set) |
| Baseline (any) | cantina-access-control, cantina-logic-errors, cantina-denial-of-service |

Cap at 4 Cantina clusters total. Cantina clusters are SEPARATE from the Solodit 8-cluster cap — they do not compete for the same slots.

**Step 2e.2: Select Clusters**

Using the Cross-Cluster Pattern Mapping table, collect Primary + Secondary clusters for each matched protocol type. Deduplicate. Cap at 8 clusters total (sorted by finding-basis count from PATTERN_INDEX.md).

**Step 2e.3: Generate Compact Detection Checklists**

For each selected cluster, read `~/.valves/patterns/{slug}.md` and extract a compact summary table:

```markdown
### {Cluster Name} ({N} patterns, {basis} finding basis)
| ID | Code Shape (grep target) | Failure Mode (1 line) |
|----|--------------------------|----------------------|
| ORACLE-001 | `latestRoundData()` without `updatedAt` check | Stale price consumed -> over-borrowing/blocked liquidations |
| ORACLE-002 | `pool.slot0()` in price-sensitive logic | Flash loan spot price manipulation |
| ... | ... | ... |
```

**Rule 18 compliance**: max 40 lines per cluster summary. For clusters with >35 patterns, include only the top 35 by frequency. Each line is: ID + code shape (shortened to ~60 chars) + failure mode (shortened to ~60 chars).

**Step 2e.4: Write Artifacts**

Write `{SCRATCHPAD}/relevant_patterns.md`:

```markdown
# Relevant Pattern Clusters (v1.7-PATTERN + v1.7-CANTINA)

## Protocol Classification
- Type(s): {detected types}
- Selected Solodit clusters: {list of slugs}
- Selected Cantina clusters: {list of cantina slugs}
- REWARD_EMISSION flag: {YES/NO}

## Breadth Agent Cluster Assignments
| Agent Focus Area | Solodit Clusters (max 3) | Cantina Clusters (max 2) |
|-----------------|--------------------------|--------------------------|
| {focus_area_1} | {cluster_1}, {cluster_2} | {cantina_cluster_1} |
| ... | ... | ... |

## Detection Checklists (Solodit)
{compact summary tables per Solodit cluster}

## Cantina Detection Checklists
{compact summary tables per Cantina cluster — same format: ID | Code Shape | Failure Mode, max 20 lines per cluster}

## Cantina Failure Mode Extracts (for Chain Analysis)
{For each selected Cantina cluster, list ONLY the Failure Mode field from each pattern — one line per pattern, max 30 lines total. Format: `CANTINA-{ID}: {failure mode}`. Used by chain analysis Agent 2 to suggest postcondition→precondition matches.}
```

Assign Solodit clusters to breadth agents by domain relevance (unchanged):
- Core state / economic agents -> protocol-specific clusters (lending, dex, vault, etc.)
- Access control agent -> access-control, initialization, proxy-upgrade
- External dependency agent -> oracle-dependency, bridge-cross-chain, price-manipulation
- Token flow / flash loan agent -> token-accounting, flash-loan-attacks, frontrunning-mev

Assign Cantina clusters to breadth agents by closest domain match:
- Core state / economic agents -> cantina-lending-liquidation, cantina-dex-amm-logic, cantina-vault-share-accounting, cantina-reward-accounting
- Access control agent -> cantina-access-control
- External dependency agent -> cantina-oracle-dependency, cantina-bridge-cross-chain, cantina-frontrunning-mev
- Token flow / flash loan agent -> cantina-arithmetic-precision, cantina-vault-share-accounting

Each agent gets max 3 Solodit clusters + max 2 Cantina clusters. If Cantina would exceed 2, drop the lowest-frequency Cantina cluster.

**Step 2e.5: Depth Agent Pattern Map**

Also write a depth-domain-to-cluster mapping for Phase 4b (Solodit + Cantina):

```markdown
## Depth Agent Pattern Map (Solodit)
| Depth Domain | Pattern Files to Read |
|-------------|----------------------|
| token-flow | token-accounting.md, vault-share-accounting.md, flash-loan-attacks.md |
| state-trace | access-control.md, initialization.md, reentrancy.md |
| edge-case | integer-overflow.md, logic-errors.md, denial-of-service.md |
| external | oracle-dependency.md, price-manipulation.md, bridge-cross-chain.md |

## Cantina Depth Agent Pattern Map
| Depth Domain | Cantina Pattern Files to Read |
|-------------|-------------------------------|
| token-flow | cantina/cantina-vault-share-accounting.md, cantina/cantina-arithmetic-precision.md{, cantina/cantina-reward-accounting.md if REWARD_EMISSION} |
| state-trace | cantina/cantina-access-control.md, cantina/cantina-reentrancy.md |
| edge-case | cantina/cantina-logic-errors.md, cantina/cantina-denial-of-service.md, cantina/cantina-arithmetic-precision.md |
| external | cantina/cantina-oracle-dependency.md, cantina/cantina-bridge-cross-chain.md, cantina/cantina-frontrunning-mev.md |
```

Protocol-specific Solodit clusters (lending-liquidation, dex-amm-logic, governance-attacks, signature-auth) map to whichever depth domain covers the protocol's primary attack surface. Protocol-specific Cantina clusters (cantina-lending-liquidation, cantina-dex-amm-logic, cantina-signature-auth) follow the same mapping.

---

## Phase 3: Parallel Analysis

**CRITICAL**: Spawn ALL analysis agents in a SINGLE message as parallel Task calls.

After all return:
1. Verify: `ls {scratchpad}/analysis_*`
2. **Post-spawn verification**: For each REQUIRED template in spawn manifest:
   - `{scratchpad}/analysis_{focus_area}.md` exists
   - File contains findings (not empty/error)
   - Template methodology was applied
3. If ANY required file missing -> **Re-spawn that agent before Phase 4a**
4. Update spawn_manifest.md with completion status
5. Do NOT read analysis files -> inventory agent reads them

### Phase 3b: Breadth Re-Scan (THOROUGH mode only)

**Skip in Light and Core mode.**

**Read full prompt from**: `~/.claude/rules/phase3b-rescan-prompt.md`

**Flow**: Phase 4a.1-pre (initial inventory) runs first (produces exclusion list), then the THOROUGH MODE INTERLEAVING GATE triggers: re-scan loop (3b, sonnet, 2-3 agents, max 2 iterations, exit on 0 new findings above Info), then per-contract analysis (3c), then Phase 4a.1-final (Inventory Merge / Refresh) merges new findings into findings_inventory.md and adds `## Inventory Source Coverage`. Only then does Phase 4a.1.5 (Strongest Exploit Gate) proceed.

---

## Phase 4: Synthesis, Adaptive Depth, Chain Analysis

**Read prompts from the corresponding phase file:**

| Step | Prompt File | Agent | Trigger |
|------|-------------|-------|---------|
| 4a.1 | `~/.claude/prompts/{LANGUAGE}/phase4a-inventory-prompt.md` (Plamen Inventory) | 1 sonnet agent | Always |
| 3b | `~/.claude/rules/phase3b-rescan-prompt.md` | Breadth Re-Scan (sonnet) | Thorough only (after 4a.1, before 4a.1.5 -> INTERLEAVING GATE) |
| 4a.1-final | Orchestrator inline or haiku merge agent | Inventory Merge / Refresh (haiku) | Thorough only (after 3b+3c COMPLETE) |
| 4a.1.5->4a.3 | Valves Gate + Classification + Thesis v1 | 3 sequential agents (Gate: opus/sonnet per mode; Classification+Thesis: sonnet) | Always (after merge in Thorough, after 4a.1 in Core/Light) |
| 4a.5 | (inline below) | Semantic Invariant + System Breakpoints + Propagation P1 + Structural Anomaly Harvester (4 parallel sonnet) | Core/Thorough |
| 4b (loop) | `~/.claude/prompts/{LANGUAGE}/phase4b-loop.md` | Orchestrator | Always |
| 4b (depth) | `~/.claude/prompts/{LANGUAGE}/phase4b-depth-templates.md` | 4 Depth Agents | Always |
| 4b (scanners) | `~/.claude/prompts/{LANGUAGE}/phase4b-scanner-templates.md` | 3 Scanners + Validation + Design Stress | Always |
| 4c | `~/.valves/rules/phase4c-chain-prompt.md` (cluster-scoped, thesis-tagged, breakpoint-tagged) | Chain Analysis (+ enabler enumeration) | Always |
| 4c.5 | (orchestrator inline; `~/.valves/rules/verification-priority-queue.md`) | Verification Priority Queue | Always |
| 5 | `~/.claude/prompts/{LANGUAGE}/phase5-verification-prompt.md` + `~/.valves/rules/phase5-poc-execution.md` | Verifiers (EV-ranked, cluster inheritance) | Both (scope differs) |
| 5.5 | (orchestrator inline) | Post-verification finding extraction | Always |
| 5.6 | (orchestrator inline; `~/.valves/rules/attack-thesis.md`, `~/.valves/rules/negative-results.md`, `~/.valves/rules/bug-class-registry.md`) | Thesis v3 + Negative Results + Registry Promotion | Always |
| 6a-c | `~/.claude/rules/phase6-report-prompts.md` (cluster-mapped report IDs) | Index -> Tier Writers -> Assembler | Core/Thorough (Light: 2-agent override) |

### Gate Enforcement

> **DEPRECATED (v1.5)**: Legacy `phase4_gates.md` is superseded by `mandatory_step_checklist.md` + explicit artifact validation in Thorough mode. The watchdog and Phase 4a Sequencing Invariant (see `~/.valves/rules/thorough-strict-mode.md`) are the authoritative enforcement mechanism. In Core/Light mode, the legacy gate check below still applies as a lightweight fallback.

**After Step 4a**: Read `{scratchpad}/phase4_gates.md` (Core/Light only -> Thorough uses `mandatory_step_checklist.md`)
- **Gate 1 BLOCKED** (missing agents): MUST re-spawn before Step 4b
- **VIOLATION**: Proceeding past BLOCKED gate without resolution

### Phase 4a (VALVES v1.7): Split Synthesis -> Inventory + Gate + Classification + Thesis v1 (Deferred Clustering)

Three pre-depth agents (Gate + Classification + Thesis v1) replace the old four-agent approach. The key v1.7 change: the Cluster Agent (which merges N findings into M clusters) is deferred to post-depth (Phase 4b step 8b). Pre-depth, only lightweight BC tagging occurs -> no compression, no common-fix assignment, no cluster merging. This preserves finding granularity until depth iter 1 produces real evidence. In Core/Light mode, all three run sequentially. In Thorough mode, a THOROUGH MODE INTERLEAVING GATE after Agent 4a.1 triggers Phase 3b/3c before Agents 4a.1.5-4a.3 proceed.

**Agent 4a.1-pre: Initial Inventory Agent** (standard Plamen inventory -> unchanged)

Reads breadth output, writes `{scratchpad}/findings_inventory.md` per the standard Plamen methodology. No registry work. No thesis work. Single reasoning focus: deduplication + side-effect trace + severity assignment. This is the INITIAL inventory that produces the exclusion list for Phase 3b/3c.

**THOROUGH MODE INTERLEAVING GATE** (after 4a.1-pre, before 4a.1.5):

In Thorough mode ONLY, the orchestrator MUST break out of the Phase 4a sequence here:

1. Phase 4a.1-pre (Initial Inventory) is now COMPLETE -> `findings_inventory.md` exists with the exclusion list
2. Run Phase 3b (Breadth Re-Scan) per `~/.claude/rules/phase3b-rescan-prompt.md`
3. Run Phase 3c (Per-Contract Analysis) per `~/.claude/rules/phase3b-rescan-prompt.md` § Phase 3c
4. Run Phase 4a.1-final: Inventory Merge / Refresh Agent (haiku) -> reads `analysis_rescan_*.md` + `analysis_percontract_*.md`, appends new findings to `findings_inventory.md`, adds `## Inventory Source Coverage` section with: Phase 3 Breadth (included), Phase 3b Re-Scan (included), Phase 3c Per-Contract (included), Final merge timestamp, Total findings after merge
5. HARD GATE: `findings_inventory.md` MUST contain the `## Inventory Source Coverage` section listing all three sources before Phase 4a.1.5 may proceed. If the section is missing -> BLOCK. See `~/.valves/rules/thorough-strict-mode.md` § Phase 4a Sequencing Invariant for the full invariant.

In Core/Light mode, skip this gate -> Phase 3b/3c are NOT_APPLICABLE, proceed directly from 4a.1-pre to 4a.1.5. No merge step needed.

**Agent 4a.1.5: Strongest Exploit Gate Agent** (VALVES -> new, Rule 19)

> **Model selection (mode-dependent)**: Thorough -> `opus` (the strongest-exploit winner selection across custody / permission / DoS / economic categories is a subtle judgment task that benefits from the stronger reasoning model). Core -> `sonnet`. Light -> `sonnet` (kept on to preserve the custody-loss guardrail even on Pro plans; the cost is one sonnet spawn).
>
> The orchestrator substitutes `{GATE_MODEL}` below: `opus` when MODE == thorough, else `sonnet`.

```
Task(subagent_type="general-purpose", model="{GATE_MODEL}", prompt="
You are the Strongest Exploit Gate Agent.

## Your Job
Commit the strongest exploit per high-signal surface to disk BEFORE clustering runs, so the Cluster
Agent and all downstream synthesis cannot silently replace a strong parent exploit (custody loss,
recovery-path severance, asset orphaning, irreversible user lock) with a weaker adjacent finding
(stale approval, CEI impurity, operational note, config awkwardness).

## Your Inputs
- {scratchpad}/findings_inventory.md (ALL findings, including REFUTED and LOW_CONFIDENCE)
- {scratchpad}/attack_surface.md (surface priority signal)
- {scratchpad}/design_context.md (semantics of each surface + trust roles)
- {scratchpad}/setter_list.md (admin setters / pointer replacements)
- {scratchpad}/state_variables.md (what state is tied to each surface)
- {scratchpad}/live_pointer_transitions.md (if present -> from recon; lists LIVE_POINTER_REPLACEMENT transitions)
- Source files as needed for the surfaces you card

## Your Task
Follow methodology in ~/.valves/rules/strongest-exploit-preservation.md.

MANDATORY -> in this exact order:
1. Apply the **Card Eligibility Gate** (§ Card Eligibility Gate, rules E1->E7). Do NOT card a
   surface unless at least one of E1->E7 holds. Surfaces that fail go to `## Non-Card Overflow
   Candidates` with a one-line justification.
2. For each eligible surface, produce one card per the card format. Apply R17 severity floor.
   Apply the **Anti-Overcompression Rule** -> when a surface has BOTH a child permission-state
   symptom AND a parent custody/recovery/reachability exploit, the PARENT is the winner unless
   explicitly refuted.
3. Tag BP-FAMILY-IBC breakpoint references when applicable.
4. Enforce the card cap: soft target <= 15, hard cap <= 25. If >25 pass eligibility, rank by the
   `card_score` formula and keep the top 25; the rest go to the overflow section with their rank.

## Output
Write {scratchpad}/strongest_exploit_cards.md per the format in
~/.valves/rules/strongest-exploit-preservation.md, including the trailing
`## Non-Card Overflow Candidates` section (may be empty).

## SCOPE
Write ONLY to strongest_exploit_cards.md. Do NOT proceed to clustering, thesis generation, or later
phases. Return your cards and stop.

Return: 'DONE: {S} surfaces carded (cap {CAP}), {O} overflow candidates, {C} custody-loss winners, {P} permission winners, {D} DoS winners, {E} economic winners'
")
```

**Gate**: `strongest_exploit_cards.md` MUST exist before the Cluster Agent spawns. Hard gate per Rule 15 and Rule 19.

**Agent 4a.2-lite: Classification Agent** (VALVES v1.7 -> lightweight pre-depth tagging, NO clustering)

> **v1.7 CHANGE**: The old Cluster Agent ran pre-depth, collapsing N findings into M clusters before depth had a chance to investigate. This caused valid candidates to be merged, deprioritized, or BC-NEW-orphaned before any depth evidence existed. The fix: split into two stages. 4a.2-lite TAGS each finding with a BC class but does NOT cluster, merge, assign common fixes, or compute cluster properties. Full clustering is deferred to post-depth (4a.2-full, after iter 1 + scoring), when depth evidence makes merge decisions smarter.

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are the Classification Agent (v1.7 -> pre-depth, NO clustering).

## Your Inputs
- {scratchpad}/findings_inventory.md
- {scratchpad}/strongest_exploit_cards.md (read for card winner IDs -> these get a CARD_WINNER flag)
- ~/.valves/state/bug_class_registry.md (if missing, treat as empty)
- {scratchpad}/design_context.md (for semantic-match context)

## Your Task -> CLASSIFICATION ONLY, NO CLUSTERING
For each finding in findings_inventory.md:
1. Signature-match against registry entries.
2. Semantic-match for classes without clean grep.
3. Assign a BC-NNN tag for matched classes, or BC-NEW-??? (with proposed name) for novel classes.
4. Flag findings that are card winners (from strongest_exploit_cards.md) with [CARD_WINNER:SEC-N].
5. Flag findings that are correctness winners with [CORRECTNESS-WINNER] per ~/.valves/rules/correctness-winner-preservation.md.

## HARD RULES -> what you must NOT do
- Do NOT group findings into clusters. Every finding stays as an individual row.
- Do NOT assign common fixes across findings.
- Do NOT merge findings that share the same BC tag.
- Do NOT compute cluster properties (severity, verification target, thesis path).
- Do NOT apply the Anti-Absorption Axes (those apply at clustering time -> 4a.2-full).
- Do NOT modify findings_inventory.md.

## Output
Write {scratchpad}/finding_classification.md -> a FLAT table, one row per finding:

| Finding ID | BC Tag | Match Type (signature/semantic/novel) | Confidence (HIGH/MEDIUM/LOW) | Flags |
|-----------|--------|--------------------------------------|------------------------------|-------|
| [CS-1]    | BC-001 | signature                             | HIGH                         | -     |
| [BLIND-3] | BC-NEW-001 | novel                            | LOW                          | [CARD_WINNER:SEC-2] |

Also append a ## Novel Class Proposals section listing each BC-NEW-??? with proposed name + 1-line pattern.

Return: 'DONE: {N} findings classified, {M} matched existing BC, {X} novel BC-NEW, {W} card winners flagged, {CW} correctness winners flagged'
")
```

> **Why classification-only works**: Depth agents receive the BC tag per finding (from the P1 propagation hints + finding cards), but each finding retains its individual identity. Depth can confirm or refute each instance independently. Post-depth clustering (4a.2-full) then merges with confidence scores and depth evidence tags -> producing higher-quality clusters with fewer false absorptions.

**Agent 4a.3: Thesis v1 Agent** (VALVES, sonnet)

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are the Thesis v1 Agent.

## Your Inputs
- {scratchpad}/findings_inventory.md
- {scratchpad}/strongest_exploit_cards.md (MANDATORY -> custody-loss card winners become candidate thesis paths unless refuted)
- {scratchpad}/finding_classification.md (v1.7 -> flat BC tags per finding, NOT clusters)
- {scratchpad}/design_context.md
- {scratchpad}/attack_surface.md

## Your Task
Commit to 3-5 concrete attack paths. Each path: (victim, attacker, entry_point) triple + >=1 supporting finding ID + testable precondition + CANDIDATE status. Each path also records a `Strongest Exploit Card Ref` field listing the SEC-N cards whose winners it covers.

NOTE (v1.7): You receive individual findings with BC tags, not clusters. Use the BC tags to identify related findings (same BC-NNN tag = likely same class) but do NOT assume they are the same bug -> depth has not confirmed yet. Reference individual finding IDs in supporting evidence, not cluster IDs.

Follow methodology in ~/.valves/rules/attack-thesis.md § v1 Generation. Emit ONLY v1 -> do not anticipate v2/v3 analysis.

## Output
Write {scratchpad}/attack_thesis.md (v1).

Return: 'DONE: {N} thesis paths committed, {M} orphan findings noted, {W} card winners aligned to paths'
")
```

**Gate preconditions (Thorough mode)**:
- Row 06 (Breadth Re-Scan) MUST be terminal (COMPLETE or NOT_APPLICABLE) -> not PENDING or RUNNING
- Row 07 (Per-Contract Analysis) MUST be terminal (COMPLETE or NOT_APPLICABLE) -> not PENDING or RUNNING
- `findings_inventory.md` MUST contain `## Inventory Source Coverage` section listing Phase 3, Phase 3b, and Phase 3c as included
- If ANY precondition fails -> BLOCK Phase 4a.1.5. Do not proceed to Gate, Cluster, or Thesis.

**Gate (all modes)**: `strongest_exploit_cards.md`, `findings_inventory.md`, `finding_classification.md`, and `attack_thesis.md` MUST all exist before Phase 4a.5. If any is missing, re-spawn ONLY the missing agent. Note: `root_cause_clusters.md` is NOT required here -> it is produced by 4a.2-full (post-depth). (Hard gate -> one of the five in Rule 15's asymmetric gate list, updated per Rule 19.)

### Phase 4a.5: Semantic Invariant Pre-Computation

> **Skip in Light mode.** Depth agents read `state_variables.md` directly.
> **Timeout fallback**: If the semantic invariant agent times out or fails, proceed to Phase 4b without `semantic_invariants.md`. Depth agents fall back to reading `state_variables.md` directly (same as Light mode). Log: "Phase 4a.5 TIMEOUT -> depth agents using state_variables.md fallback."

> **Purpose**: Enumerate write sites, define semantic invariants, group variables into semantic clusters. Pass 2 (Thorough only) reverses direction for function->cluster coverage and recursive stale-read traces.
> **Models**: Pass 1 sonnet, Pass 2 sonnet (sequential)

Spawn between Phase 4a (inventory) and Phase 4b (depth loop).

**Pass 1 Agent** (Variable -> Write Sites + Semantic Clustering):

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are Semantic Invariant Agent -> Pass 1. You enumerate write sites, define semantic invariants, and group variables into semantic clusters.

## Your Inputs
Read:
- {SCRATCHPAD}/state_variables.md (all state variables from recon)
- {SCRATCHPAD}/function_list.md (all functions)
- Source files referenced in state_variables.md

## Your Task

For EACH accumulator, snapshot, or total-tracking variable in state_variables.md:

1. **Enumerate write sites**: Use grep to find ALL locations that write to this variable.
2. **State the semantic invariant**: In ONE sentence, what SHOULD this variable represent?
3. **Enumerate value-changing functions**: Find ALL functions that change the UNDERLYING VALUE the variable tracks -> whether or not they update the variable.
4. **Annotate conditional writes**: For each write site, check if the write is inside a conditional block. If YES, annotate as CONDITIONAL(condition_expression).
4a. **Detect asymmetric branches**: For each CONDITIONAL write, check if the SAME function also writes UNCONDITIONALLY to a different tracking variable. If YES, flag as ASYMMETRIC_BRANCH.
5. **Detect mirror variables**: Identify variable PAIRS tracking the same concept in different storage. For each pair, list ALL functions that write to EITHER. If any function writes to one but not the other -> flag as SYNC_GAP.
6. **Flag time-weighted accumulation inputs**: For (value x time_delta) calculations, note controllable inputs and whether time_delta can grow unboundedly. Flag as ACCUMULATION_EXPOSURE if both true.

## Semantic Clustering

Group ALL enumerated variables into semantic clusters -> groups of variables collectively representing a single domain or lifecycle. For each cluster, identify which functions write ALL members (full-write) vs only SOME members (partial-write).

## Output

Write to {SCRATCHPAD}/semantic_invariants.md:

### Main Table
| Variable | Contract/Module | Semantic Invariant | Write Sites (with CONDITIONAL annotations) | Value-Changing Functions | Potential Gaps |

### Mirror Variable Pairs
| Variable A | Variable B | Same Concept | Functions Writing A Only | Functions Writing B Only | Sync Gaps |

### Time-Weighted Accumulators
| Accumulator | Formula Pattern | Controllable Input | Time Source | Unbounded Delta? | Exposure |

### Semantic Clusters
| Cluster Name | Variables | Lifecycle Functions | Full-Write Functions | Partial-Write Functions |

Return: 'DONE: {N} variables, {M} gaps, {C} conditional, {S} sync_gaps, {A} accumulation, {K} clusters'
")
```

**Pass 2 Agent** (THOROUGH mode only -> Function -> Cluster Coverage + Recursive Gap Trace):

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are Semantic Invariant Agent -> Pass 2. You reverse the analysis direction: for each function, check which clusters it touches incompletely, then recursively trace consequences of stale reads.

## Your Inputs
Read:
- {SCRATCHPAD}/semantic_invariants.md (Pass 1 output)
- {SCRATCHPAD}/function_list.md
- Source files for all Partial-Write Functions from the Semantic Clusters table

## STEP 1: Cluster Coverage Audit

For each Partial-Write Function in the Semantic Clusters table:
1. Which cluster members does it write? Which does it SKIP?
2. For each skipped member: describe in ONE factual sentence WHY it is skipped. This is a FACTUAL ANNOTATION -> do NOT judge whether the skip is safe.
3. Flag ALL skips as CLUSTER_GAP -> no exceptions.

## STEP 2: Recursive Consequence Trace

For each CLUSTER_GAP, SYNC_GAP, and CONDITIONAL where the skip path is reachable:
1. **Level 0**: Identify the stale variable and the function that leaves it stale
2. **Level 1**: Find ALL functions that READ the stale variable. What value do they produce stale vs correct?
3. **Level 2**: For each Level 1 reader that WRITES a different variable using the stale-derived value, find readers of THAT variable.
4. **Level 3**: Repeat one more level. If error still propagates -> flag as DEEP_PROPAGATION.

## STEP 3: Cross-Verify Pass 1 Write Sites

For each function in function_list.md that Pass 1 did NOT list as a write site for ANY variable:
1. Read the function source
2. Check: does it write to ANY state variable from the Main Table?
3. If YES and Pass 1 missed it -> add as MISSED_WRITE_SITE

## STEP 4: Branch Path Completeness

For each function with >=2 branches:
1. List variables written on EACH branch path
2. If any branch writes a variable that another branch does NOT -> flag as BRANCH_ASYMMETRY
3. For each asymmetry: is the missing write a stale-read source for any consumer?

## Output

Append to {SCRATCHPAD}/semantic_invariants.md:

### Cluster Coverage Gaps
| Function | Cluster | Written Members | Skipped Members | Skip Context (factual) | Flag |

### Recursive Consequence Traces
| Gap Source | Stale Variable | L0 Function | L1 Readers -> Impact | L2 Readers -> Impact | L3? | Max Window |

### Missed Write Sites (Cross-Verification)
| Variable | Missed Function | Write Type |

### Branch Path Asymmetries
| Function | Condition | Written on True | Written on False | Consumer Impact |

Return: 'DONE: {G} cluster_gaps, {T} consequence traces ({D} deep_propagation), {W} missed_write_sites, {B} branch_asymmetries'
")
```

### Phase 4a.5 (VALVES v1.7): Four Parallel Focused Agents

Four independent sonnet agents run in parallel (they read shared scratchpad artifacts, not each other) -> spawn in a single message with multiple Task calls. The fourth agent (4a.5.d) is the Structural Anomaly Harvester added in v1.7 for mechanical recall improvement.

**Agent 4a.5.a: Semantic Invariant Agent** (unchanged from Plamen -> see `~/.valves/rules/phase4-confidence-scoring.md` Pass 1 and Pass 2 blocks above).

Writes `{scratchpad}/semantic_invariants.md`. Single reasoning focus: variable-level write-sites, clusters, conditional-write detection.

**Agent 4a.5.b: System Breakpoints Agent** (VALVES, sonnet)

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are the System Breakpoints Agent.

## Your Inputs
- {scratchpad}/design_context.md (Key Invariants + Operational Implications)
- {scratchpad}/state_variables.md
- {scratchpad}/findings_inventory.md
- {scratchpad}/finding_classification.md (v1.7 -> flat BC tags per finding, used for reachability cross-reference)
- {scratchpad}/attack_thesis.md (v1)

## Your Task
Enumerate system-level failure modes (insolvency, DoS, liquidation cascade, first-loss exhaustion, oracle drift beyond tolerance). For each breakpoint: invariant violated, conditions that break it, first-loss path (designed vs actual absorber), observability classification (pre / at-trigger / atomic), reachability cross-reference to findings and BC tags.

Follow methodology in ~/.valves/rules/system-breakpoints.md.

## Output
Write {scratchpad}/system_breakpoints.md.

Return: 'DONE: {N} breakpoints, {A} atomic-only, {F} first-loss mismatches'
")
```

**Agent 4a.5.c: Propagation P1 Agent** (VALVES, sonnet -> EXPANDED SCOPE in v1.3)

This agent now produces FOUR outputs in a single spawn:
1. `propagation_structural.md` -> standard BC-class structural candidates (existing)
2. `symmetric_pairs.md` -> binding pair table per `~/.valves/rules/symmetric-pairs.md` (NEW v1.3)
3. `external_platform_limits.md` -> unbounded aggregation candidates per `~/.valves/rules/external-protocol-limits.md` (NEW v1.3)
4. `external_mutability_candidates.md` -> cached-external-value drift candidates per `~/.valves/rules/external-state-mutability.md` (NEW v1.3)

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are the Propagation P1 Agent (structural sweep, v1.3 expanded).

## Your Inputs
- {scratchpad}/finding_classification.md (v1.7 -> flat BC tags per finding; use BC-NNN tags to identify classes for structural sweep)
- {scratchpad}/findings_inventory.md
- {scratchpad}/function_list.md
- {scratchpad}/contract_inventory.md
- ~/.valves/state/bug_class_registry.md (for signature greps -> MULTI-PATTERN per class)

## Your Tasks (all FOUR required -> Core and Thorough)

### Task 1: Standard structural sweep (existing)
For each BC-NNN tag appearing in finding_classification.md, run ALL signature grep patterns from bug_class_registry.md (not just one per class) and surface STRUCTURAL_CANDIDATE locations. Follow `~/.valves/rules/bug-class-propagation.md` § Pass 1 and § Bug-Class Execution Audit. Record zero-candidate alarms with explicit reasons.

### Task 2: Symmetric-Pairs Binding Table (NEW v1.3)
Build the pair table per `~/.valves/rules/symmetric-pairs.md`. For every sibling pair in the codebase (deposit/withdraw, single-sided/two-sided, normal/skipped, paused-gated/ungated, stake/unstake, claim/emergency-claim, update-path-A/B), enumerate all seven aspects (guards, validation, state writes, external calls, accounting, fee routing, events). Every ASYMMETRY_FLAG row is a mandatory depth target.

Write to `{scratchpad}/symmetric_pairs.md`.

### Task 3: External Platform Limit Scan (NEW v1.3)
For each external-interface function (checkUpkeep, lzReceive, ccipReceive, publishMessage, or any function feeding an off-chain keeper/relayer), compute the max encoded payload size symbolically. Compare to the platform limit per `~/.valves/rules/external-protocol-limits.md` § Reference Table. Flag OVERFLOW_CANDIDATE when payload exceeds (or has no cap below) the platform limit.

Write to `{scratchpad}/external_platform_limits.md` (or append as a section to propagation_structural.md).

### Task 4: External-State Mutability Recon (NEW v1.3)
For each external protocol integrated in the codebase, consult `~/.valves/rules/external-state-mutability.md` § Reference Table. For each locally-cached external value, check whether upstream can mutate it. Flag MUTABILITY_DRIFT_CANDIDATE when local cache is assumed-immutable but upstream has an admin-mutable setter.

Write to `{scratchpad}/external_mutability_candidates.md`.

## Gates
- Each BC class with a listed `Typical scope` that matches the codebase but produces zero candidates -> BUG_CLASS_ZERO_CANDIDATE_ALARM with explicit reason (no silent passes)
- Each ASYMMETRY_FLAG row -> mandatory depth target (cannot be silently dropped)
- Each OVERFLOW_CANDIDATE -> mandatory depth target
- Each MUTABILITY_DRIFT_CANDIDATE -> mandatory depth target

Follow methodology in:
- ~/.valves/rules/bug-class-propagation.md § Pass 1 + § Bug-Class Execution Audit
- ~/.valves/rules/symmetric-pairs.md
- ~/.valves/rules/external-protocol-limits.md
- ~/.valves/rules/external-state-mutability.md

## Output
Write {scratchpad}/propagation_structural.md with per-domain hints section for depth agent injection.

Return: 'DONE: {T} structural candidates ({H} high / {M} medium / {L} low), {C} cleared'
")
```

**Agent 4a.5.d: Structural Anomaly Harvester** (VALVES v1.7, sonnet -> NEW)

> **Purpose**: Mechanical candidate harvester that produces investigation seeds from code structure alone, independent of model creativity. Catches structural patterns that breadth agents tend to miss: symmetric-branch mismatches, cross-contract interface gaps, parameter desync, governance parity holes, and hidden external dependencies. Seeds do NOT become findings -> they become mandatory investigation targets for depth agents.

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are the Structural Anomaly Harvester (v1.7). You produce CANDIDATE SEEDS -> investigation targets for depth agents. Your seeds are NOT findings. They have no severity. They are structural code anomalies that may or may not be bugs.

## Your Inputs
- {scratchpad}/function_list.md (all functions with signatures)
- {scratchpad}/contract_inventory.md (contracts + inheritance + dependencies)
- {scratchpad}/setter_list.md (admin/privileged setters)
- {scratchpad}/state_variables.md (storage variables)
- {scratchpad}/findings_inventory.md (to EXCLUDE already-found areas -> do NOT rediscover known bugs)
- Source files in scope

## Your Task -> 8 Mechanical Sweeps

### Sweep 1: Symmetric-Branch Mismatch
For each public/external function pair that operates on the same state (deposit/withdraw, stake/unstake, lock/unlock, add/remove, create/destroy, open/close, enter/exit):
- List guards/requires on function A vs function B
- List state writes on function A vs function B
- List external calls on function A vs function B
- Flag ASYMMETRY_SEED where any of the 3 lists differs AND the missing element is not explained by directional logic (e.g., deposit takes tokens, withdraw sends -> different calls is expected; but deposit checks pause and withdraw does not -> that is anomalous)
Output: table of pairs with asymmetry annotations.

### Sweep 2: Cross-Contract Interface Mismatch
For each contract-to-contract call in scope (from contract_inventory.md dependency list):
- Read the CALLER's assumed interface (what functions it calls on the target)
- Read the TARGET's actual interface (what functions it exposes)
- Flag INTERFACE_SEED where: (a) caller calls a function the target does not have, OR (b) caller passes parameters in a different order/type than the target expects, OR (c) caller assumes a return value format the target does not guarantee
This is a MECHANICAL grep -> compare call sites to declarations.

### Sweep 3: Parameter/State Desync
For each admin setter in setter_list.md that writes to a parameter used in calculations:
- Trace which functions READ this parameter
- Check: is the parameter read BEFORE or AFTER the setter writes?
- Flag DESYNC_SEED where: (a) the parameter is read by an active operation (deposit, withdraw, claim, rebalance) AND (b) no re-calculation / re-validation occurs after the setter fires AND (c) the parameter change can affect in-flight state (pending deposits, active positions, accruing rewards)

### Sweep 4: Cross-Component Governance Parity
For each privileged role (admin, owner, operator, guardian, keeper) in setter_list.md:
- List ALL contracts that recognize this role
- List the permissions this role has per contract
- Flag PARITY_SEED where: (a) a role can do X in contract A but cannot do the symmetric inverse in contract B (e.g., can pause but not unpause, can set adapter but not migrate positions), OR (b) two contracts have the same parameter with the same name but different setters/guards

### Sweep 5: Hidden External Dependency
For each external call (calls to addresses that are not in-scope contracts):
- Identify: what value does the external call return or what state does it modify?
- Trace: which in-scope calculations depend on this return value?
- Flag DEPENDENCY_SEED where: (a) the dependency is not documented in design_context.md AND (b) no staleness check / failure fallback exists for the external value AND (c) the external value feeds a calculation affecting user funds or access control

### Sweep 6: Recipient / Beneficiary Mismatch (NEW v1.7-PATCH)
For each function that performs a value transfer, an accounting credit, OR records a beneficiary identity:
- Identify the **accounting actor** (whose balance/share/owed slot is updated).
- Identify the **transfer recipient** (the address the tokens / native value / NFT actually go to).
- Identify the **measured beneficiary** (the address an event, view, or downstream read attributes the payout to).
- Identify the **stored recipient** (e.g., `recipient`, `beneficiary`, `to` mapping slot read at distribution time).
- Flag RECIPIENT_SEED where ANY of:
  - accounting actor != actual transfer recipient
  - measured beneficiary != payout target
  - recipient stored in storage != recipient passed to the external call
  - the function lets caller specify a `to` distinct from the accounting actor without an authorization check
This is mechanical: compare the address used in `_mint` / `_credit` / accounting writes against the address used in `transfer` / `call{value:}` / external send. Any divergence not explained by stated trust is a seed.

### Sweep 7: Mirror-Accounting Drift (NEW v1.7-PATCH)
For each variable PAIR that is supposed to track the same quantity in two storage forms (this is the same family as `~/.valves/rules/attribution-audit.md` BC-041 and `semantic_invariants.md` § Mirror Variable Pairs, but mechanical and pre-depth):
- `total*` paired with `sum-over-mapping(...)` of the same quantity
- reward index paired with per-user `owed` / `accrued`
- `escrowed*` vs `active*` balances
- `pending*` vs `finalized*` balances
- two accumulators that semantically MUST move together (e.g., supply / borrow indices, principal / interest)
For each pair, list every function that mutates either side. If the mutator sets diverge in a way that is not direction-justified, flag MIRROR_DRIFT_SEED.
Cross-link: when `semantic_invariants.md` § Mirror Variable Pairs already enumerated this pair, cite the row instead of duplicating; flag only NEW drift surfaces this sweep finds.

### Sweep 8: Emergency-Path Asymmetry (NEW v1.7-PATCH)
For each function whose name or modifier marks it as an emergency / fast-exit / skipped-accounting path (`emergency*`, `fastExit`, `skipRewards`, `forceClose`, `liquidateAll`, `pauseAndDrain`, `migrate*`, recovery / rescue paths):
- Compare the emergency path's state-write set against the corresponding NORMAL path's state-write set on the same domain.
- Flag EMERGENCY_SEED where ANY of:
  - normal path updates state A/B/C; emergency path skips one and the skip is not explicitly documented as safe
  - claim has fee accrual / index update; emergency-claim does not
  - pause has no symmetric `unpause` OR has unpause but no recovery accounting (e.g., interest stops accruing during pause but is not credited on unpause)
  - emergency exit severs a recovery path the user would otherwise have (custody-loss family — escalate to Strongest Exploit Gate at Phase 4a.1.5 if E2/E5 applies)
  - freeze without time-bound auto-thaw or symmetric inverse role
This is the same pattern as `~/.valves/rules/symmetric-pairs.md` § Sibling pair categories (normal/skipped, paused-gated/ungated, claim/emergency-claim) but mechanical and pre-depth.

## HARD RULES
- Do NOT assign severity to seeds. They are investigation targets, not findings.
- Do NOT flag patterns already covered by an existing finding in findings_inventory.md (check by location overlap).
- Every seed MUST include a specific code location (file:line). Vague seeds are discarded.
- Maximum 25 seeds total across all 8 sweeps (prioritize by specificity and potential impact). The cap is unchanged from the 5-sweep era -> adding 3 sweeps does not raise the noise ceiling. When more than 25 candidates pass the per-sweep filters, rank by: emergency-path > custody/recipient > mirror-acct > interface-mismatch > dependency > symmetric > desync > parity, and within tier by specificity (file:line over file-only).

## Output
Write {scratchpad}/candidate_seeds.md:

# Structural Anomaly Seeds (v1.7)

## Summary
| Sweep | Seeds Found | Already Known (excluded) | Net New |

## Seeds by Depth Domain
### For token_flow depth agent
| Seed ID | Sweep | Location | Anomaly (1 line) |

### For state_trace depth agent
| Seed ID | Sweep | Location | Anomaly (1 line) |

### For edge_case depth agent
| Seed ID | Sweep | Location | Anomaly (1 line) |

### For external depth agent
| Seed ID | Sweep | Location | Anomaly (1 line) |

Return: 'DONE: {N} seeds ({S1} symmetric, {S2} interface, {S3} desync, {S4} parity, {S5} dependency, {S6} recipient, {S7} mirror-acct, {S8} emergency), {E} excluded as already-known'
")
```

> **Depth agent integration**: In Phase 4b iteration 1, depth agent prompts include candidate_seeds.md hints for their domain alongside P1 structural candidates. For each seed in their domain, the depth agent MUST produce either a finding or CLEARED(depth) with a specific reason. Seeds are a coverage floor, not a ceiling.

### Phase 4a.5.e: Assumption-Breaker Pass (VALVES v1.7-PATCH, sonnet -> NEW, max 1 spawn)

> **Purpose**: One bounded adversarial sub-pass on Session A. Asks the questions that breadth/depth agents anchored on documented invariants tend not to ask. Produces seeds, NOT findings. Capped at 5 seeds. Not a second breadth phase.

> **When**: After Phase 4a.5 four-agent split returns AND `candidate_seeds.md` exists. Runs sequentially before Phase 4b iter 1 begins (its seeds feed depth iter 1 alongside the harvester's). In Light mode: SKIP. In Core/Thorough: ALWAYS spawn.

```
Task(subagent_type="general-purpose", model="sonnet", prompt="
You are the Assumption-Breaker Pass (Valves v1.7-PATCH). You produce up to 5 CANDIDATE SEEDS by asking adversarial questions that the breadth/depth/scanner/harvester agents tend not to ask. Your seeds are NOT findings. They have no severity.

> **Reasoning baseline**: Read `~/.valves/rules/valves-doctrine.md` § The 8 mandatory adversarial questions. Q1-Q7 below are the seed-producing subset of the broader doctrine; they exist to CATCH things the harvester / breadth / scanner / depth agents anchored on documented invariants tend to miss.

## Your Inputs
- {scratchpad}/design_context.md (Key Invariants + Operational Implications + trust model)
- {scratchpad}/findings_inventory.md (so you can EXCLUDE already-found areas)
- {scratchpad}/semantic_invariants.md (for what's already enumerated as invariant)
- {scratchpad}/system_breakpoints.md (for what's already enumerated as a breakpoint)
- {scratchpad}/candidate_seeds.md (for what the harvester already covered)
- {scratchpad}/propagation_structural.md + {scratchpad}/symmetric_pairs.md + {scratchpad}/external_platform_limits.md + {scratchpad}/external_mutability_candidates.md
- {scratchpad}/setter_list.md
- Source files in scope

## Your 7 Adversarial Questions (Q7 added v1.7-PATCH7 — call-order pressure)

For each question, scan the codebase + scratchpad for cases where the question's answer is YES and no existing finding/seed already covers it. Each YES becomes a seed candidate.

1. **What is assumed immutable but may not be?** State a variable / parameter / address / config that the design treats as fixed. Find a setter, upgrade path, or upstream protocol mutator that can change it.
2. **What path is assumed symmetric but probably isn't?** Find a normal/inverse pair (deposit/withdraw, lock/unlock, claim/emergency-claim, set/unset, freeze/thaw) where one side has a state write or external call the other lacks -> AND that asymmetry is NOT in `symmetric_pairs.md` or `candidate_seeds.md` Sweep 1/8 already.
3. **What external value is treated as trustworthy without fallback?** Find a read of an external return (oracle, price, threshold, fee, address) that flows into a calculation affecting user funds, with no staleness check, no max-age, no circuit-breaker -> AND not already in `external_mutability_candidates.md` or candidate_seeds.md Sweep 5.
4. **What admin action changes live state without migration?** Find a privileged setter that swaps a pointer (vault / strategy / adapter / oracle / treasury) or rewrites a calc input, where in-flight user state still maps to the OLD value -> AND not already in `setter_list.md` LIVE_POINTER_REPLACEMENT entries or admin-setter-validation Check 6.
5. **What recovery path can sever custody?** Find a function that closes / pauses / migrates / rescues / liquidates state in a way that locks user funds behind an actor who can refuse -> AND not already a Strongest Exploit Card (E2 / E4 in `strongest_exploit_cards.md`).
6. **What actor is assumed benign in a path where they should not be?** Find a function whose code assumes a caller (admin, keeper, oracle, relayer, multisig participant) acts honestly even when the trust model in `design_context.md` does not document that assumption -> OR the assumption is wider than the trust model permits.
7. **What happens if this is called in an order the developer did not expect?** Find a path where safety depends on F1 always happening before F2 (or after F2, or at most once, or only inside a specific lifecycle phase), but neither code nor invariant enforces that order. Pressure: reversed order, skipped predecessor step, repeated call, admin mutation inserted between user steps, emergency / recovery path called early, external dependency update interleaved between normal steps, cross-contract sequencing reordered. EXCLUDE if already captured by `symmetric_pairs.md`, candidate_seeds.md Sweep 8 (emergency-path asymmetry), an existing E11 SEQUENCE canonical (when canonical_seed_map.md already exists from a prior partial run), or an existing finding whose root cause is exactly this unenforced order.

## HARD RULES
- Maximum 5 seeds total. If more than 5 candidates clear the EXCLUDE check, keep the top 5 by specificity (file:line over file-only) and by parent-exploit category (custody/recovery > sequence-violation > config > observability).
- Every seed MUST cite a specific code location (file:line). Vague seeds are discarded.
- Seeds are NOT findings. No severity. No fix recommendation. No 'we believe' language.
- Do NOT duplicate existing findings, semantic_invariants entries, system_breakpoints entries, candidate_seeds rows, propagation_structural rows, symmetric_pairs rows, external_*_candidates rows, or setter_list LIVE_POINTER entries. EXCLUDE rigorously.
- One seed per question maximum (so you produce at most one of each of the 7 question categories). If a question yields nothing, leave it blank -> do NOT pad.
- For Q7 specifically: a seed is valid only if you can name BOTH the unenforced expected order AND a concrete actor / call sequence that violates it. "Maybe ordering matters somewhere" is NOT a Q7 seed. "Function X writes state Y but Y must be set by function Z first; Z is callable independently and not checked in X" IS a Q7 seed.

## Output
Write {scratchpad}/assumption_breaker_seeds.md:

# Assumption-Breaker Seeds (Valves v1.7-PATCH)

## Summary
| Question | Seed produced? | Seed ID |
|---|---|---|
| Q1 immutable-but-not | YES/NO | AB-1 |
| Q2 symmetric-but-not | YES/NO | AB-2 |
| Q3 trusted-external | YES/NO | AB-3 |
| Q4 admin-no-migration | YES/NO | AB-4 |
| Q5 recovery-severs-custody | YES/NO | AB-5 |
| Q6 actor-assumed-benign | YES/NO | AB-6 |
| Q7 sequence-not-enforced (v1.7-PATCH7) | YES/NO | AB-7 |

## Seeds
| Seed ID | Question | Location | Anomaly (1 line) | Recommended depth domain | Open Question (≤25 words, optional) | Disputed Assumption (≤20 words, optional) |
|---|---|---|---|---|---|---|

Return: 'DONE: {N} adversarial seeds (Q1-Q7 active: {list}), {E} excluded as already-known/covered'
")
```

> **Depth agent integration**: In Phase 4b iteration 1, depth-agent prompts include `assumption_breaker_seeds.md` rows for their domain alongside `candidate_seeds.md` and `analog_seeds.md`. Each seed must produce a finding OR `CLEARED(depth)` with a specific reason by end of Session A; otherwise it routes to `seed_outcomes.md` as `FORWARD_TO_SESSION_B`.

### Phase 4a.5.f: Bounded Analog Seeding (VALVES v1.7-PATCH, orchestrator inline -> NEW, no agent spawn)

> **Purpose**: Use external vulnerability corpora (Solodit / Code4rena / Sherlock / CodeHawks / DeFiHackLabs) as bounded pattern priors. Seeds, not findings. Hard caps prevent noise.

> **When (v1.7-PATCH2 -> CONDITIONAL)**: After Phase 4a.5.e returns. Orchestrator inline -> no new agent spawn. In Light mode: SKIP unconditionally. In Core/Thorough: evaluate the **6 triggers** in `~/.valves/rules/analog-seeds.md` § Conditional triggers; run only if at least one trigger fires. Otherwise write `analog_seeds.md` as a structured SKIP record per § Skip protocol.

**Trigger evaluation (orchestrator inline, before any RAG / WebSearch call)**:

```
T1_low_local_seeds:
  high_signal_local = (
    count(candidate_seeds.md Sweep 1 entries)
    + count(Sweep 2) + count(Sweep 5) + count(Sweep 6) + count(Sweep 8)
    + count(assumption_breaker_seeds.md Q2/Q3/Q5/Q7 active)   # Q7 added v1.7-PATCH7 (sequence-not-enforced — high-signal local seed)
  )
  T1_FIRES = (high_signal_local < 5)

T2_high_risk_low_breadth:
  high_risk_surfaces = count(attack_surface.md priority >= HIGH)
  breadth_findings = count of all entries in analysis_*.md (Phase 3 breadth)
  ratio = breadth_findings / max(high_risk_surfaces, 1)
  T2_FIRES = (high_risk_surfaces > 5 AND ratio < 0.5)

T3_zero_finding_high_risk:
  setter_heavy_contracts = count(contracts in setter_list.md with >= 3 setters)
  contracts_with_breadth_findings = count(unique contracts cited by analysis_*.md)
  zero_finding_high_risk = setter_heavy_contracts - contracts_with_breadth_findings
  T3_FIRES = (zero_finding_high_risk >= 3)

T4_historical_prime:
  T4_FIRES = (HISTORICAL_PRIME_MODE == true)

T5_novel_architecture:
  fork_ancestry_known = (meta_buffer.md § Fork Ancestry Analysis identifies a known parent)
  diff_audit_tier_count = (Tier A rows + Tier B rows in diff_audit_tiers.md if it exists, else 0)
  T5_FIRES = (fork_ancestry_known == false AND diff_audit_tier_count == 0)

T6_uncovered_breakpoint:
  T6_FIRES = (any row in system_breakpoints.md has empty Reachability.findings AND empty Reachability.BC tags)

if any of (T1, T2, T3, T4, T5, T6) FIRES:
  proceed with analog seeding per § Methodology below
  the file's first line is `## Source: {RAG / Tavily / Combined}` and the body includes
  a `## Triggers fired (v1.7-PATCH2)` section listing which triggers fired
else:
  SKIP analog seeding
  write analog_seeds.md per `~/.valves/rules/analog-seeds.md` § Skip protocol
  log `analog_seeding_SKIPPED_NO_TRIGGER` to `{SCRATCHPAD}/degradation_log.md`
```

> **Methodology (when triggers fire)**: Read `~/.valves/rules/analog-seeds.md` § Sources allowed, § Hard caps, § Local mapping requirement, § Output schema, § Routing into the candidate-seed flow.

> **Source order** (try until one returns ≥ 1 candidate):
> 1. `mcp__unified-vuln-db__*` queries with `protocol_category` + `attack_surface_type` + `quality_score >= 3` (top-K ≤ 16).
> 2. Tavily / WebSearch fallback with the same filter terms (limited to the 5 allowed sources).
> 3. If both fail → write `analog_seeds.md` with `## Source: NONE_AVAILABLE`, log `analog_seeds_UNAVAILABLE` to `degradation_log.md`, proceed.

> **Caps** (binding):
> - ≤ 8 analog seeds total in `analog_seeds.md`.
> - ≤ 5 may flow into Session A (depth iter 1). Remaining (up to 3) recorded with `Why deferred: over Session A cap` and routed to `seed_outcomes.md` as `FORWARD_TO_SESSION_B`.
> - Each seed MUST satisfy the three-part local mapping requirement (Local Surface Match + Candidate Location + Likely BC / Sweep Link). Vague seeds are dropped, not weakened.
> - No imported severity. No copied report wording.

> **Output**: `{SCRATCHPAD}/analog_seeds.md` per the schema in `~/.valves/rules/analog-seeds.md` § Output schema.

> **Depth agent integration**: The 5 Session A analog seeds inject into depth iter 1 prompts in the same slot as `candidate_seeds.md` § Seeds by Depth Domain, tagged with `AS-{N}` IDs.

> **CLEARED(depth) proof requirement (v1.7-PATCH3 PATCH 1 -> binding on ALL depth-iter-1 seed integrations above)**: When a depth agent (token-flow / state-trace / edge-case / external) emits `CLEARED(depth)` on a seed (harvester sweep / assumption-breaker / analog source -> any), the agent MUST produce a structured proof record per `~/.valves/rules/cleared-proof-discipline.md` § Required minimum proof fields:
>
> ```
> CLEARED(depth) [SEED-ID] -> Proof Type: {GUARD_PRESENT | INVARIANT_ENFORCED | TRUST_MODEL_EXPLICIT | STATE_UNREACHABLE | EXTERNAL_DEPENDENCY_SAFE | OTHER}
>   file:line: {exact location of guard / invariant anchor}
>   guard:    {literal code expression OR named invariant ID OR documented trust statement}
>   reason:   {<= 25 words: attacker action + blocking effect}
> ```
>
> The orchestrator's COMPLETE_A handoff sub-step build extracts these structured records from `analysis_depth_*.md` and folds them into `seed_outcomes.md` § CLEARED Proof Records. If a depth agent emits `CLEARED(depth)` WITHOUT a structured proof block:
> - In Thorough: the orchestrator DOWNGRADES the seed to `CONTESTED` and queues it for iter 2 DA per Phase 4-confidence-scoring AD-1 (Hard DA role).
> - In Core/Light: the seed routes to `FORWARD_TO_SESSION_B` with reason `INSUFFICIENT_CLEAR_PROOF`.
>
> This is mechanical. No agent decides to skip proof; missing proof means the CLEARED claim is not durable.

**Gate (SOFT)**: Per Rule 15 in CLAUDE.md, `semantic_invariants.md`, `system_breakpoints.md`, `propagation_structural.md`, `candidate_seeds.md`, `assumption_breaker_seeds.md`, and `analog_seeds.md` are all soft-required. If missing after timeout, log to `{scratchpad}/degradation_log.md` and proceed -> depth agents fall back to `state_variables.md` + classification-level hints. Do NOT re-spawn these agents if they time out; degradation is preferred to orchestration effort on gate-passing.

Hard gates are reserved for artifacts explicitly listed as HARD in Rule 15 (findings_inventory.md, finding_classification.md, root_cause_clusters.md (post-depth), attack_thesis.md v1, verification_priority_queue.md, verification_inheritance.md, attack_thesis.md v3, cluster_instance_map.md, session_a_to_b_handoff.md, cross_session_consensus.md).

### THOROUGH CHECKPOINT: Pre-Depth (orchestrator inline, FAIL-CLOSED v1.5)

When `MODE == thorough` AND `LANGUAGE == evm`:

**Step A: Invariant Fuzz Campaign** (MANDATORY -> checklist row 16 (Invariant Fuzz Campaign))
Update checklist row 16 to RUNNING.
Read template: `~/.claude/prompts/{LANGUAGE}/phase4b-invariant-fuzz.md`
Spawn agent. Await completion. Write results to `invariant_fuzz_results.md`.
Template has 5-minute timeout built in.

After completion:
- If `invariant_fuzz_results.md` exists with valid content -> set row 16 to `COMPLETE`
- If campaign timed out / failed BUT `invariant_fuzz_results.md` exists with `COMPILATION_FAILED` reason cited -> set row 16 to `FAILED_WITH_FALLBACK` (the "log + reason" IS the template-defined fallback)
- If `LANGUAGE != evm` -> set row 16 to `NOT_APPLICABLE` with reason `"LANGUAGE = {x}, EVM-specific invariant fuzz N/A"`
- Otherwise (no artifact, no fallback) -> row 16 stays `RUNNING`/`PENDING`, watchdog will block at next phase gate

**Step B: Medusa Campaign** (MANDATORY if MEDUSA_AVAILABLE -> checklist row 17 (Medusa Stateful Fuzz))
Update checklist row 17 to RUNNING.
Spawn agent IN PARALLEL with Step A. Read from `~/.claude/prompts/{LANGUAGE}/phase4b-loop.md` Medusa section.
Await completion. Write results to `medusa_fuzz_findings.md` (15-min timeout built in).

After completion:
- Artifact exists with findings or "no violations" -> row 17 `COMPLETE`
- Medusa not installed -> row 17 `NOT_APPLICABLE` with reason `"MEDUSA_AVAILABLE = false"`
- Compilation failed in mock harness -> row 17 `FAILED_WITH_FALLBACK` (artifact must contain `MEDUSA_COMPILATION_FAILED` block with reason)
- `LANGUAGE != evm` -> row 17 `NOT_APPLICABLE`
- Otherwise -> row stays unfinished, watchdog will block

**Step C: Strict Watchdog Check (replaces v1.4 "log and continue")**

```
For row in [15, 16]:
  if row.status in {COMPLETE, FAILED_WITH_FALLBACK, NOT_APPLICABLE}:
    proceed
  else:
    # MODE == thorough -> BLOCK
    log to {SCRATCHPAD}/violations.md: "PRE_DEPTH_FUZZ_BLOCKED: row {row.id} state {row.status}"
    enter Recovery Loop per ~/.valves/rules/thorough-strict-mode.md § Recovery Loop
    # do NOT advance until row reaches valid terminal state OR 3 recovery iterations exhausted
```

This replaces the v1.4 behavior of "log violation and continue." For Thorough mode in v1.5, missing fuzz artifacts BLOCK the pipeline until either the campaign completes OR a valid template-defined fallback is recorded.

For non-Thorough modes (Light/Core, neither runs this checkpoint anyway), the v1.4 logic is preserved unchanged.

### Phase 4b (VALVES v1.4): Pre-Spawn Prompt-Length Guard

Before EVERY agent spawn in Phase 4b (depth, scanner, niche, injectable, economic, thesis synthesis, P2 propagation) and Phase 4c (chain), the orchestrator computes the injected-context length per `~/.valves/rules/prompt-injection-guard.md`:

```
Thresholds:
  WARN_LINES = 600
  COMPACT_LINES = 1000   -> auto-substitute summary-table views for oversized artifacts
  HARD_LIMIT_LINES = 1500 -> emergency truncation (drop non-critical artifacts)

If compaction or truncation fires -> log to {SCRATCHPAD}/prompt_guard_log.md AND (for HARD_LIMIT or EMERGENCY) to {SCRATCHPAD}/violations.md.
```

Zero new phase; zero new spawn. Pure mechanical pre-spawn arithmetic. See `~/.valves/rules/prompt-injection-guard.md` § Per-Artifact Compaction Rules for the canonical summary-table formats (cluster table, BP table, SEC-N summary, etc.).

### Phase 4b: Adaptive Depth Loop

> **Reference**: `~/.valves/rules/phase4-confidence-scoring.md` for scoring model (including Valves `composite_reality` and `composite_report` extensions), anti-dilution rules, and convergence criteria.

The orchestrator runs the full loop autonomously:

1. **Light mode override**: When `MODE == light`, skip the standard 8-agent spawn. Instead spawn 4 merged sonnet agents per Light Mode Orchestration override #5: (a) combined token-flow + state-trace, (b) combined edge-case + external, (c) combined scanner A+B+C, (d) validation sweep. Skip niche agents, skip confidence scoring, skip iterations 2-3. After iteration 1 completes, proceed directly to Phase 4c chain analysis (single merged agent per override #6).

1. **Iteration 1 (Core/Thorough)**: Spawn ALL 8 standard agents + niche agents in parallel:
   - 4 depth agents (token-flow, state-trace, edge-case, external)
   - Blind Spot Scanner A (Tokens & Parameters)
   - Blind Spot Scanner B (Guards, Visibility & Inheritance + Override Safety)
   - Blind Spot Scanner C (Role Lifecycle, Capability Exposure & Reachability)
   - Validation Sweep Agent -> **v1.4 EXPANDED + v1.7-PATCH8 + v1.7-PATCH9 (tightened scope)**: runs the Admin-Setter Validation Consolidated sub-check per `~/.valves/rules/admin-setter-validation.md` with 7 checks (zero-address, bounds, state-dependent, active-flag, approve hygiene, pointer-replacement, **cross-component governance parity** -> v1.4 Check 7). Also runs the Variable-Flow Attribution Audit sub-check per `~/.valves/rules/attribution-audit.md` (BC-041). **v1.7-PATCH8 also runs the Test-Suite Skepticism sub-check per `~/.valves/rules/valves-doctrine.md` § Heuristic Lenses → TEST-SKEPTIC**, scoped tighter in v1.7-PATCH9 to prevent noise:

      **Scope (v1.7-PATCH9 priority filter — quality > coverage)**:
      - PRESSURE ONLY paths whose surface is in one of: (a) custody / fund transfer; (b) accounting / share / reward / fee math; (c) lifecycle transitions (init / pause / settle / migrate / terminate); (d) privileged mutation (admin setters writing to calc inputs or live pointers); (e) recovery / emergency paths from `system_breakpoints.md` § Recovery / OrderingViolation. Cross-reference `strongest_exploit_cards.md` (E1-E7 surfaces) and `system_breakpoints.md` BP-NN reachability. Surfaces NOT in these categories are SKIPPED.
      - DO NOT report generic "this admin function lacks a test" — this is low-signal absent the priority filter.
      - DO NOT report missing tests for view functions, internal helpers, library wrappers, or test-only utilities.
      - DO NOT report assertion-shape weakness on tests that exercise paths outside the priority filter.

      **Sub-checks (run only against priority-filtered paths)**:
      1. is there a test that calls this path? (2) if yes, does the test assert post-state (storage / mappings / accounting) or only events / returns / "does not revert"? (3) does the test setUp() encode a stricter sequence than production enforces (e.g., test calls `initialize()` before `deposit()`; production allows `deposit()` pre-initialize)? (4) are there functions called only in production with NO test coverage at all?

      **Hard cap (v1.7-PATCH9)**: maximum **6 [VS-TS-1] findings** total, ranked by surface signal (custody > accounting > lifecycle > privileged-mutation > recovery). When more than 6 priority-filtered candidates surface gaps, keep the 6 highest-signal; the rest are recorded in `validation_sweep.md` § VS-TS Overflow with rank + surface.

      **Quality gate (v1.7-PATCH9 — every [VS-TS-1] finding MUST have)**:
      - production path file:line (concrete; no contract-level only)
      - test file path (or explicit `no test` annotation)
      - which sub-check fired (1 / 2 / 3 / 4 — exactly one primary, additional may be cited)
      - surface category from the priority filter (custody / accounting / lifecycle / privileged-mutation / recovery)

      Findings missing any of the four required fields are DROPPED at the agent's self-check pass before emitting; the orchestrator-inline post-spawn audit verifies field presence and logs `VS_TS_FIELD_GAP_DROPPED` to `degradation_log.md` for each drop.

      Output `[VS-TS-1] Test-suite skepticism gaps` consolidated multi-location table tagged `[CORRECTNESS-WINNER]` (so distinct test-coverage gaps are not absorbed into the same cluster). Emits `[VS-AS-1]` for admin-setter gaps AND `[VS-AT-1]` for attribution mismatches AND `[VS-TS-1]` for test-skepticism gaps — all three consolidated with multi-location tables, all three tagged `[CORRECTNESS-WINNER]`. **Skip [VS-TS-1] gracefully** when no test directory is detected in scope (e.g., audit scope is contracts only, no `test/` or `tests/` folder); record `VS_TS_SKIPPED_NO_TEST_DIR` in degradation_log.md. Also skip when the priority filter yields zero candidate surfaces (small-scope audits where no custody / accounting / lifecycle path exists in scope); record `VS_TS_SKIPPED_NO_PRIORITY_SURFACE`.
   - **Niche agents**: For each REQUIRED niche agent in `template_recommendations.md` -> `Niche Agents` section, read its definition from `~/.claude/agents/skills/niche/{name}/SKILL.md` and spawn alongside depth agents. Each niche agent = 1 budget slot.
   - **Timeout split-and-retry**: If any agent times out, split its findings into 2 "lite" agents (max 3 findings each, no static analyzer, max 5 files). 2 lite agents = 1 budget unit.

   > **Reasoning baseline (v1.7-PATCH7)**: Every depth-agent prompt (the 4 standard + Validation Sweep) and every niche-agent prompt MUST include a one-line directive: `"Read ~/.valves/rules/valves-doctrine.md § The 8 mandatory adversarial questions and § The decision lenses once before starting. Apply your DECISION LENS, not just your file region — the domain biases attention; the lens defines the threats you pressure. When you suspect safety depends on developer-expected call-order but that order is not enforced by code or invariant, that is NOT a strong CLEARED — it is at best a sequence-violation finding or an Open Question for handoff."` This is a prompt directive; it does NOT change the spawn topology, count, or budget.
   >
   > **Novel mechanic pressure (v1.7-CANTINA-RUNID)**: Every depth-agent prompt (the 4 standard domains) MUST include this directive AFTER the reasoning baseline and BEFORE pattern cross-checks: `"Before consulting patterns or RAG, identify any protocol-specific mechanic in your domain that does not cleanly map to a standard vulnerability class (reentrancy, access control, oracle manipulation, etc.). If found, pressure-test it: what invariant should hold, what assumption does it rely on, what call sequence or state drift breaks it. This is your highest-value work — novel mechanics produce novel bugs that no pattern library covers."` This ensures depth agents hunt for unknown-unknowns before falling back to known-pattern matching. The ordering is now: (1) primary skill methodology, (2) novel mechanic pressure, (3) Solodit cross-check, (4) Cantina cross-check. Zero new agents, zero new budget.

   > **Pattern library reference (v1.7-PATTERN, Rule 34)**: Every depth-agent prompt (the 4 standard domains) MUST include a directive to read their assigned pattern files from `{SCRATCHPAD}/relevant_patterns.md` § Depth Agent Pattern Map. The directive: `"After completing your primary methodology, read the pattern detection files listed below for your domain. Use the Code Shape fields as grep targets to cross-check for vulnerability classes your primary analysis may have missed. For each pattern whose Code Shape matches code in scope but was not covered by your primary analysis, investigate and either produce a finding or note CLEARED(pattern) with reason. Pattern files: {list from Depth Agent Pattern Map for this domain, as ~/.valves/patterns/{slug}.md paths}."` This is a coverage cross-check, not a replacement for the depth methodology. Depth agents apply their skill template FIRST, then pattern cross-check. Zero new agents, zero new budget.
   >
   > **Cantina pattern cross-check (v1.7-CANTINA, Rule 34)**: Every depth-agent prompt (the 4 standard domains) MUST ALSO include a second-pass cross-check directive for Cantina patterns from `{SCRATCHPAD}/relevant_patterns.md` § Cantina Depth Agent Pattern Map. The directive: `"After completing your primary methodology AND Solodit pattern cross-check above, read the Cantina pattern files listed below for your domain. These patterns are derived from real DeFi competition findings — they represent failure modes that escaped initial auditor attention in live contests. For each CANTINA pattern whose Code Shape matches code in scope but was not covered by your primary analysis or Solodit cross-check, investigate and either produce a finding or note CLEARED(cantina-pattern) with reason. Cantina files: {list from Cantina Depth Agent Pattern Map for this domain, as ~/.valves/patterns/cantina/cantina-{slug}.md paths}."` This is a SECOND-PASS coverage amplifier. The ordering is always: (1) primary skill methodology, (2) Solodit cross-check, (3) Cantina cross-check. Zero new agents, zero new budget.

2. **Score all findings** (MANDATORY for Core/Thorough -> Light mode skips scoring). Orchestrator MUST spawn the scoring agent and await `confidence_scores.md` before deciding whether to proceed to iteration 2. Skipping scoring to "go straight to chain analysis" is a VIOLATION. Spawn haiku scoring agent -> `confidence_scores.md`
   - **Core mode**: 2-axis scoring (Evidence x 0.5 + Analysis Quality x 0.5)
   - **Thorough mode**: 4-axis scoring (Evidence x 0.25 + Consensus x 0.25 + Analysis Quality x 0.3 + RAG Match x 0.2)
   - CONFIDENT (>= 0.7): no more depth needed
   - UNCERTAIN (0.4-0.7): targeted depth
   - LOW CONFIDENCE (< 0.4): targeted depth + production verification + RAG deep search

3. **Iteration 2**:
   - **Core mode**: Skip iteration 2 entirely. Uncertain findings proceed to chain analysis and verification as-is.
   - **Thorough mode**: Spawn targeted Devil's Advocate depth agents per domain for ALL uncertain findings. Hard DA role: agents are structurally adversarial. Severity-weighted budget: spawn_priority = (1 - confidence) * severity_weight.
   - Anti-dilution: evidence-only finding cards, max 5 per agent
   - Re-score with new-evidence-only rule
   - **Loop dynamics detection**: Classify as CONTRACTIVE/OSCILLATORY/EXPLORATORY. If OSCILLATORY -> force CONTESTED, exit.

4. **Iteration 3 (Thorough mode only, if still uncertain and progress was made)**: Final targeted pass
   - Force remaining < 0.4 to CONTESTED verdict
   - Write `adaptive_loop_log.md`

5. **Post-verification error trace feedback** (Core/Thorough only): After Phase 5, if verifiers returned CONTESTED with error traces AND budget remains, spawn targeted depth with error traces as investigation questions (AD-6).

**Convergence**: Hard cap 3 iterations (Core: 1, Light: 1 with no scoring), dynamic budget cap `min(max(12, ceil(findings/5)+7), 20)`, progress check after each iteration.

> **Light mode: Phase 4b.5 RAG Sweep** -> Skip entirely. RAG validation is not performed in Light mode (no confidence scoring axis requires it).

6. **Design Stress Testing (Thorough mode only)**: ALWAYS spawn Design Stress Testing Agent. 1 slot is pre-reserved and UNCONDITIONAL -> not a "budget redirect." This agent runs regardless of remaining budget.

7. **Economic Incentive Audit (VALVES -> Core and Thorough)**: ALWAYS spawn one Economic Incentive Agent in iteration 1, in parallel with the 8 standard agents. 1 slot pre-reserved and UNCONDITIONAL. Model: opus. Reads `design_context.md`, `attack_surface.md`, `attack_thesis.md v1`, `system_breakpoints.md`, `~/.valves/state/negative_results.md`, and so-far-populated `findings_inventory.md`. Produces `{SCRATCHPAD}/economic_findings.md` with every finding tagged `[EI-THEORY]`, `[EI-TRACE]`, or `[EI-SIM]` per `~/.valves/rules/economic-incentive-audit.md`. `[EI-THEORY]` findings capped at Medium severity. Findings feed hypothesis grouping at Phase 4c tagged with thesis path alignment.

   **Thorough mode only**: spawn a second Economic Incentive Agent in iteration 2 with iter 1's confirmed findings as additional context. Catches compound-economic scenarios.

8. **Thesis Synthesis (VALVES -> Core and Thorough)**: After iteration 1 scoring completes AND Economic Incentive Agent returns, spawn ONE Thesis Synthesis Agent (sonnet, 1 slot, pre-reserved). Reads `attack_thesis.md v1`, all depth/economic/propagation/diff-audit outputs, and `confidence_scores.md`. Updates thesis paths with new evidence, strengthens/weakens/refutes CANDIDATEs, merges convergent paths, adds newly-surfaced paths. Writes `{SCRATCHPAD}/attack_thesis.md` v2 (v1 preserved as appendix). Follows `~/.valves/rules/attack-thesis.md` § v2 Generation.

8b. **Post-Depth Full Clustering (VALVES v1.7 -> Core and Thorough)**: After iter 1 scoring + Thesis Synthesis, run the FULL Cluster Agent. This is the deferred compression step -> it has depth evidence, confidence scores, and thesis alignment to make smarter merge decisions.

   ```
   Task(subagent_type="general-purpose", model="sonnet", prompt="
   You are the Full Cluster Agent (v1.7 -> post-depth, evidence-informed).

   ## Your Inputs
   - {scratchpad}/findings_inventory.md (updated with depth findings)
   - {scratchpad}/finding_classification.md (pre-depth BC tags from 4a.2-lite)
   - {scratchpad}/strongest_exploit_cards.md (MANDATORY -> card winners cannot be absorbed)
   - {scratchpad}/confidence_scores.md (depth evidence quality per finding)
   - {scratchpad}/attack_thesis.md (v2 -> thesis-aligned findings must not be merged away)
   - ~/.valves/state/bug_class_registry.md (if missing, treat as empty)
   - {scratchpad}/design_context.md

   ## Your Task -> FULL CLUSTERING (now with depth evidence)
   Using the BC tags from finding_classification.md as a starting point:
   1. Group findings sharing the same BC-NNN tag into clusters.
   2. For each cluster, verify the common fix pattern (now informed by depth analysis).
   3. Apply the Strongest Exploit Preservation Hard Rule -> card winners get distinct clusters/subgroups.
   4. Apply Correctness-Winner Preservation -> [CORRECTNESS-WINNER] findings get subgroups when fix differs.
   5. Apply Anti-Absorption Axes from ~/.valves/rules/strongest-exploit-preservation.md.
   6. Apply Anti-Overcompression Rule.

   ## v1.7 EVIDENCE-AWARE CLUSTERING RULES
   - Do NOT merge findings where BOTH have confidence >= 0.5 but reach DIFFERENT verdicts (one CONFIRMED, one PARTIAL/REFUTED). Different verdicts at decent confidence = different bugs, not same class.
   - Do NOT merge a CONFIRMED finding with a LOW_CONFIDENCE finding if they have different locations AND different depth evidence tags. The low-confidence finding may be a distinct bug the depth agent could not confirm -> preserving it gives chain analysis a candidate.
   - Thesis-aligned findings (referenced by attack_thesis.md v2 as supporting evidence) CANNOT be absorbed into clusters where they are no longer individually traceable. Each thesis-supporting finding must be identifiable in the cluster's instance list.

   Follow methodology in ~/.valves/rules/bug-class-registry.md § v1 Generation.

   ## Output
   Write {scratchpad}/root_cause_clusters.md per the format in bug-class-registry.md.

   Return: 'DONE: {C} clusters, {N} findings classified, {X} BC-NEW candidates, {W} card winners preserved, {P} thesis-aligned findings preserved individually'
   ")
   ```

   > **Why post-depth clustering is better**: Pre-depth clustering often merges findings A and B because they share a code pattern. After depth, A is CONFIRMED with [BOUNDARY] + [TRACE] evidence while B is REFUTED because a guard exists. Post-depth clustering keeps A as a real finding and drops B from the cluster -> instead of the pre-depth behavior where both were merged and the cluster inherited PARTIAL verdict, losing the strong A signal in averaged confidence.

   **Gate**: `root_cause_clusters.md` MUST exist before P2 Propagation spawns.

9. **Bug-Class Propagation Pass 2 (VALVES -> Core and Thorough)**: After Full Clustering (8b) completes, orchestrator applies the Tier 1 / Tier 2 selection rules from `~/.valves/rules/bug-class-propagation.md` § Trigger + Budget Reconciliation to pick which clusters get a full P2 run within the mode cap (5 in Core, 10 in Thorough).
   - **Tier 1 (mandatory within budget)**: CONFIRMED/PARTIAL Medium+ clusters with `cluster_size >= 2`.
   - **Tier 2 (opportunistic)**: Singleton Medium+ clusters, EV-ranked until cap is exhausted.
   - **UNPROPAGATED_BUDGET**: Clusters beyond cap get a stub `propagated_{BC-NNN}.md` with `STATUS: UNPROPAGATED_BUDGET` -> a marker file, NOT a P2 analysis. No agent is spawned for stubs.

   Each spawned P2 agent receives cluster context + P1 structural candidates and writes a full `{SCRATCHPAD}/propagated_{BC-NNN}.md`. Orchestrator writes `{SCRATCHPAD}/propagation_manifest.md` listing spawned vs stubbed clusters, then merges spawned outputs into `{SCRATCHPAD}/propagation_summary.md` and updates `root_cause_clusters.md`.

   **Propagation ordering rule**: P2 runs AFTER full clustering (8b) (so only confirmed clusters propagate) and BEFORE iteration 2 (so devil's advocate agents can re-evaluate propagated instances in their domain). Cluster-scoped, not finding-scoped -> one agent per qualifying cluster regardless of how many findings are already in it.

### THOROUGH CHECKPOINT: Post-Depth (orchestrator inline -> STATIC MANIFEST CHECK)

**Do NOT write checkpoint assertions from memory.** Read the static manifest and verify against it:

```
// STEP 0: Mode gate -> this check is Thorough-only
if MODE != THOROUGH:
    // Core/Light: only assert confidence_scores.md + adaptive_loop_log.md exist, then proceed
    ASSERT: confidence_scores.md exists (Core) OR skip scoring (Light)
    ASSERT: adaptive_loop_log.md exists
    LOG to {SCRATCHPAD}/checkpoint_postdepth.md
    goto Phase 4c

// STEP 1: Read the static manifest (orchestrator MUST NOT modify this file)
manifest = Read("~/.claude/prompts/{LANGUAGE}/phase4b-required-artifacts.md")

// STEP 2: Check EVERY required artifact exists
missing = []
for each file in manifest.required_artifacts_table:
    if not exists({SCRATCHPAD}/{file}):
        missing.append({file, producer})

// STEP 3: Check niche agent artifacts
for each niche agent marked Required: YES in {SCRATCHPAD}/template_recommendations.md:
    if not exists({SCRATCHPAD}/{niche_file}):
        missing.append({niche_file, niche_agent_name})

// STEP 4: If missing -> spawn, do NOT proceed
if len(missing) > 0:
    LOG to {SCRATCHPAD}/violations.md: "PHASE 4b INCOMPLETE: {missing}"
    for each missing file:
        spawn the responsible agent (see Producer column in manifest)
    re-run STEP 2 after agents complete
    ASSERT len(missing) == 0 -> HARD GATE, cannot proceed to Phase 4c

// STEP 4b (v1.5 Thorough strict-mode): synchronize with mandatory_step_checklist
For each row in mandatory_step_checklist.md whose phase == "Phase 4b":
    if row.status not in {COMPLETE, FAILED_WITH_FALLBACK, NOT_APPLICABLE}:
        enter Recovery Loop per ~/.valves/rules/thorough-strict-mode.md § Recovery Loop
        do NOT advance to Phase 4c until checklist consistent

// Note: per Rule 28, the watchdog (phase_gate.py) ALSO performs this check independently.
// This inline assertion is belt-and-suspenders.

// STEP 5: Standard assertions
ASSERT: confidence_scores.md is non-empty
ASSERT: IF uncertain Medium+ findings exist after iter 1 -> adaptive_loop_log shows iter >= 2

LOG checkpoint result to {SCRATCHPAD}/checkpoint_postdepth.md
```

**WHY STATIC MANIFEST**: The orchestrator previously wrote its own checkpoint -> verifying only what it remembered to do, silently skipping what it forgot. The static manifest file is defined outside the orchestrator's generation context. Missing artifacts trigger agent spawns, not silent passes.

### Session Checkpoint Write: COMPLETE_A (v1.7 -> Planned Session Split)

**Boundary**: COMPLETE_A is written after **depth iteration 1 + confidence scoring** completes -> NOT after all of Phase 4b. This means Session B owns iterations 2-3 (DA with genuine fresh eyes), RAG sweep, chain analysis, verification, and report. The static manifest check (THOROUGH CHECKPOINT: Post-Depth) runs in Session B after DA iterations complete.

**Why this boundary**: The biggest quality gain is DA iteration 2-3 with fresh context. If iter 2-3 run in Session A, Session B only gets RAG/chain/verification -> still valuable but weaker. Splitting after iter 1 + scoring gives Session B the full adversarial + quality pipeline.

**When to write**: After Step 2 of Phase 4b completes (confidence scoring after iter 1). The orchestrator writes COMPLETE_A BEFORE checking whether iter 2 is needed -> Session B makes that decision independently with fresh eyes.

**(v1.7-PATCH11.2) INLINE COMPLETE_A HALT — third enforcement point (after scoring, before any post-scoring work)**:

```
// This block runs IMMEDIATELY after confidence scoring completes (row 22 → COMPLETE).
// It is the third enforcement point for COMPLETE_A halt, alongside:
//   1. CRITICAL RULE 1 (top of file — compaction-resistant prose mandate)
//   2. Phase 0.9 § E (every phase boundary — checks halt marker on disk)
// This third point fires at the EXACT transition moment, before the orchestrator
// can even begin thinking about iter 2 / DA / chain / verification.

if MODE == THOROUGH AND SESSION in ["A", "A_RESUMED"]:
    // === COMPLETE_A BOUNDARY: DO NOT PROCEED ===
    // Write handoff bundle, write COMPLETE_A checkpoint, write halt marker, HALT.
    // See "COMPLETE_A boundary enforcement" section below for full procedure.
    // After this block, the orchestrator MUST NOT execute any further phases.
    // No iter 2. No DA. No chain. No verification. No report. HALT.
    goto COMPLETE_A_BOUNDARY_ENFORCEMENT
    // Control NEVER returns here in Thorough Session A.
```

UPGRADE the existing PARTIAL_A checkpoint to COMPLETE_A by rewriting `session_checkpoint.md` with the full evidence-only packet. Also write `blind_spot_report.md` (back-compat) AND the **Session A → B Handoff Build artifacts** (Valves v1.7-PATCH: `coverage_density.md` + `negative_space.md` + `seed_outcomes.md` + **`canonical_seed_map.md` (v1.7-PATCH2)** + `disagreement_queue.md` + `session_a_to_b_handoff.md`). This whole bundle runs ALWAYS in Thorough mode.

### COMPLETE_A boundary enforcement (v1.7-PATCH10 + PATCH10.3 + PATCH11.3 — MANDATORY in Thorough)

After the COMPLETE_A handoff bundle is written AND `session_checkpoint.md` is rewritten with status=COMPLETE_A, the orchestrator MUST stop the run in this conversation per the architecture's Session A/B independence contract.

**(v1.7-PATCH11.3) INLINE FAIL-CLOSED SEQUENCE** — This is a mechanical checklist, not advisory prose. After row 22 (confidence scoring) completes in Thorough mode, the orchestrator executes EXACTLY these steps in order. Failure at any step triggers the noted recovery; the sequence NEVER silently proceeds past a failure.

```
COMPLETE_A_INLINE_SEQUENCE:
  // Step C1: Build handoff bundle (coverage_density, negative_space, seed_outcomes,
  //          canonical_seed_map, disagreement_queue, session_a_to_b_handoff)
  // Step C2: Validate handoff — for EACH artifact in bundle:
  //          result = VALIDATE_STEP_COMPLETION(row, path, "orchestrator")
  //          if FAIL → Recovery Loop, max 2 retries, then SESSION_A_INCOMPLETE
  // Step C3: Write session_checkpoint.md with CHECKPOINT_LEVEL: COMPLETE_A
  // Step C4: Write HALT_AFTER_COMPLETE_A.md (compaction-proof marker)
  // Step C5: Update run_state.json: checkpoint_level=COMPLETE_A, halt_reason=COMPLETE_A_BOUNDARY
  // Step C6: Physical scratchpad rotation (.audit_scratchpad → .audit_session_a)
  // Step C7: Post-rotation leak scan (verify no analytical artifacts in fresh scratchpad)
  // Step C8: Emit SESSION A COMPLETE banner
  // Step C9: HARD HALT — return control, do NOT process further
  //
  // INVARIANT: Steps C4+C5 execute BEFORE C6+C8. Even if C6 (rotation) fails,
  // the halt marker + run_state are already on disk. § E catches the halt
  // at the next phase boundary regardless of rotation outcome.
```

**FIRST ACTION (v1.7-PATCH10.3 — before any verification, before banner, before anything else)**:

Write `{SCRATCHPAD}/HALT_AFTER_COMPLETE_A.md` with this exact content:
```markdown
# HALT MARKER — SESSION A COMPLETE

Written at: {ISO timestamp}
Mode: THOROUGH
Session: A
Boundary: COMPLETE_A (after depth iter 1 + confidence scoring)

DO NOT PROCEED PAST THIS POINT IN THIS CONVERSATION.
Session B runs in a FRESH Claude Code conversation.

This file is the compaction-proof ground truth. Even if the orchestrator loses
its halt instruction due to context compaction, Phase 0.9 § E checks for this
file at every phase boundary and enforces the halt mechanically.
```

This marker is written UNCONDITIONALLY and IMMEDIATELY when the orchestrator reaches this code path. It is the first thing that happens — before integrity verification, before the banner, before anything that could fail or be interrupted. Once this file exists on disk, the § E gate in Phase 0.9 ensures the run cannot continue even if subsequent steps fail or the context is compacted.

**Enforcement (Thorough mode only — Light/Core continue inline per their existing semantics)**:

1. **Verify COMPLETE_A bundle integrity** (mechanical, after halt marker is written):
   - Run the Protected-artifact pre-write gate (§ B above) one more time on each handoff bundle artifact
   - Verify all six handoff sub-step artifacts exist on disk (coverage_density / negative_space / seed_outcomes / canonical_seed_map / disagreement_queue / session_a_to_b_handoff)
   - Verify `session_checkpoint.md` status field == `COMPLETE_A`
   - Run row drift detection (§ D above) — every row up to and including row 22 (Confidence Scoring) must be in terminal state
   - If ANY check fails → log `COMPLETE_A_BOUNDARY_INTEGRITY_FAILURE` to violations.md, do NOT halt yet, trigger Recovery Loop. If recovery exhausted → Session A is incomplete; emit `SESSION_A_INCOMPLETE_BANNER` (per § Completion states in `~/.valves/rules/thorough-strict-mode.md`) and halt.

1.5. **Scratchpad rotation — physical session isolation** (v1.7-PATCH11, after bundle integrity PASSED):

   This step physically separates Session A's analytical artifacts from Session B's workspace, preventing reasoning contamination and anchoring.

   ```
   // === SCRATCHPAD ROTATION (Thorough only) ===
   // Precondition: COMPLETE_A bundle integrity PASSED (step 1 above)

   SESSION_A_ARCHIVE = "{PROJECT_ROOT}/.audit_session_a"
   SCRATCHPAD = "{PROJECT_ROOT}/.audit_scratchpad"

   // 1. Rename current scratchpad to archive
   rename(SCRATCHPAD, SESSION_A_ARCHIVE)

   // 2. Create fresh scratchpad for Session B
   mkdir(SCRATCHPAD)

   // 3. Copy ONLY the allowlisted handoff/factual artifacts into fresh scratchpad
   ALLOWLIST = [
       "session_checkpoint.md",
       "session_a_to_b_handoff.md",
       "coverage_density.md",
       "negative_space.md",
       "seed_outcomes.md",
       "canonical_seed_map.md",
       "disagreement_queue.md",
       "HALT_AFTER_COMPLETE_A.md",
       "build_status.md",
       "contract_inventory.md",
       "function_list.md",
       "state_variables.md",
       "template_recommendations.md",
       "mandatory_step_checklist.md",
       "pipeline_trace.md",
       "blind_spot_report.md",
       "design_context.md",
       "attack_surface.md",
       "spawn_manifest.md",
       "run_state.json"
   ]

   for file in ALLOWLIST:
       if file_exists("{SESSION_A_ARCHIVE}/{file}"):
           copy("{SESSION_A_ARCHIVE}/{file}", "{SCRATCHPAD}/{file}")

   // 4a. (v1.7-PATCH11-I) Update run_state.json for COMPLETE_A + Session B readiness
   //     The copied run_state.json still says session=A, checkpoint_level=PARTIAL_A.
   //     Update to COMPLETE_A. Session B entry (in a new conversation) will
   //     transition to PARTIAL_B (see § R5 SESSION-AWARE ROUTING in execution-state.md).
   if file_exists("{SCRATCHPAD}/run_state.json"):
       rs = JSON.parse(read("{SCRATCHPAD}/run_state.json"))
       rs.session = "A"  // still Session A at this point
       rs.checkpoint_level = "COMPLETE_A"
       rs.current_phase = "complete_a"
       rs.phase_status = "DONE"
       rs.halt_reason = "COMPLETE_A_BOUNDARY"
       rs.write_ahead = { action: null, action_type: null, targets: [], timestamp: null, interrupted: false }
       rs.last_completed_phase = "phase4b_scoring"
       rs.last_completed_timestamp = now_iso()
       rs.last_write_iso = now_iso()
       Write "{SCRATCHPAD}/run_state.json" (full JSON)

   // 5. Write the Session B read-scope manifest
   Write "{SCRATCHPAD}/SESSION_B_READ_SCOPE.md":
   ```markdown
   # Session B Read Scope (v1.7-PATCH11 — MECHANICAL ENFORCEMENT)

   ## Allowlisted files (Session B may read these BEFORE cross-session consensus)
   - session_checkpoint.md (finding cards — evidence-only, no reasoning)
   - session_a_to_b_handoff.md (ranked target sheet)
   - coverage_density.md, negative_space.md, seed_outcomes.md
   - canonical_seed_map.md, disagreement_queue.md
   - build_status.md, contract_inventory.md, function_list.md
   - state_variables.md, template_recommendations.md
   - design_context.md, attack_surface.md, spawn_manifest.md
   - blind_spot_report.md (back-compat subset of handoff)
   - mandatory_step_checklist.md, pipeline_trace.md
   - HALT_AFTER_COMPLETE_A.md (marker — not analytical)
   - run_state.json (v1.7-PATCH11 — execution state, not analytical)
   - manifest_*.md (v1.7-PATCH11 — agent tracking, not analytical)
   - Source code files under {PROJECT_ROOT}/

   ## DENIED before cross-session consensus (Phase 5.6.1+)
   - ANY file under {PROJECT_ROOT}/.audit_session_a/ (Session A archive)
   - findings_inventory.md (Session A verdicts — recreated fresh by Session B)
   - hypotheses.md, attack_thesis*.md, synthesis_full.md
   - analysis_*.md, depth_*_findings.md, niche_*_findings.md
   - confidence_scores.md (Session A scoring — Session B rescores fresh)
   - rag_validation.md
   - root_cause_clusters.md, cluster_instance_map.md
   - report_index.md, report_critical_high.md, report_medium.md, report_low_info.md
   - AUDIT_REPORT*.md, verification_verdicts_summary.md
   - verify_*.md (Session A verifications — if any exist from recovery)

   ## When cross-session consensus unlocks .audit_session_a reads
   ONLY during the explicit cross_session_consensus.md build step (Phase 5.6.1+),
   the orchestrator reads structured fields from Session A's findings_inventory.md
   and confidence_scores.md to compute the consensus table. This is the ONLY
   legal access to Session A analytical artifacts after scratchpad rotation.
   ```

   // 5. Verify rotation integrity
   ASSERT: SESSION_A_ARCHIVE exists and is a directory
   ASSERT: SCRATCHPAD exists and is a directory
   ASSERT: all ALLOWLIST files present in fresh SCRATCHPAD
   ASSERT: findings_inventory.md NOT in fresh SCRATCHPAD
   ASSERT: hypotheses.md NOT in fresh SCRATCHPAD
   ASSERT: analysis_*.md NOT in fresh SCRATCHPAD
   if ANY ASSERT fails → log SCRATCHPAD_ROTATION_FAILURE to violations.md, HALT
   ```

   **(v1.7-PATCH11.3) Post-rotation cross-check — comprehensive leak scan**:
   ```
   // === NAMED FILE DENYLIST (exact matches) ===
   LEAKED_EXACT = [
       "findings_inventory.md", "finding_classification.md",
       "hypotheses.md", "chain_hypotheses.md", "synthesis_full.md",
       "composition_coverage.md", "enabler_results.md", "finding_mapping.md",
       "confidence_scores.md", "rag_validation.md",
       "root_cause_clusters.md", "cluster_instance_map.md",
       "report_index.md", "report_critical_high.md", "report_medium.md",
       "report_low_info.md", "AUDIT_REPORT.md", "AUDIT_REPORT.INVALID.md",
       "AUDIT_REPORT_SESSION_B.md",
       "cross_session_consensus.md", "cross_batch_consistency.md",
       "verification_verdicts_summary.md", "report_review.md",
       "report_quality.md", "compliance_summary.md",
       "verification_priority_queue.md", "verification_inheritance.md",
       "attack_thesis.md", "strongest_exploit_cards.md",
       "strongest_exploit_final_check.md",
       "historical_prime_seeds.md", "meta_buffer.md",
       "design_stress_findings.md", "validation_sweep_findings.md",
       "sibling_propagation_findings.md",
       "semantic_invariants.md", "system_breakpoints.md",
       "propagation_structural.md", "candidate_seeds.md",
       "assumption_breaker_seeds.md", "analog_seeds.md",
       "symmetric_pairs.md", "external_platform_limits.md",
       "external_mutability_candidates.md",
       "relevant_patterns.md", "chain_summaries_compact.md",
       "variable_finding_map.md", "consensus_map.md",
       "confidence_distribution.md", "adaptive_loop_log.md",
       "verification_error_traces.md"
   ]
   for f in LEAKED_EXACT:
       if file_exists("{SCRATCHPAD}/{f}"):
           log "ROTATION_LEAK_DETECTED: {f} found in fresh scratchpad" to violations.md (HIGH)
           delete "{SCRATCHPAD}/{f}"

   // === GLOB PATTERN DENYLIST (catch all analytical agent outputs) ===
   LEAKED_GLOBS = [
       "analysis_*.md",           // breadth/rescan/percontract
       "analysis_depth_*.md",     // depth agents
       "depth_*_findings.md",     // depth output files
       "verify_*.md",             // verifier outputs
       "niche_*.md",              // niche agent outputs
       "blind_spot_*.md",         // blind spot agents
       "chain_iteration*.md",     // chain iteration outputs
       "manifest_phase4b_*.md",   // depth manifests (contain agent state)
       "manifest_phase5_*.md",    // verification manifests
       "manifest_phase6_*.md"     // report manifests
   ]
   for pattern in LEAKED_GLOBS:
       for f in glob("{SCRATCHPAD}/{pattern}"):
           log "ROTATION_LEAK_DETECTED: {f} found in fresh scratchpad" to violations.md (HIGH)
           delete f

   // === FINAL ASSERTION ===
   leaked_count = count(violations.md entries with ROTATION_LEAK_DETECTED from this scan)
   if leaked_count > 0:
       log "SESSION_B_ISOLATION_LEAK_SUMMARY: {leaked_count} analytical artifacts removed from fresh scratchpad" to violations.md
       // Continue — leaks have been cleaned. But log for observability.
   ```

   **Why physical rotation**: Logical isolation rules (Rule 30, Session B Behavioral Rules) depend on the orchestrator following instructions. Physical rotation makes the isolation MECHANICAL — Session A analytical artifacts literally do not exist in Session B's workspace. An agent cannot read a file that isn't there.

2. **Emit terminal banner verbatim**:

```
====================================================================
SESSION A COMPLETE — STOP HERE
====================================================================

Session A discovery is complete. The COMPLETE_A checkpoint and the
Session A → B Handoff Build bundle are on disk:

  - HALT_AFTER_COMPLETE_A.md (compaction-proof halt marker)
  - session_checkpoint.md (status=COMPLETE_A)
  - coverage_density.md
  - negative_space.md
  - seed_outcomes.md
  - canonical_seed_map.md
  - disagreement_queue.md
  - session_a_to_b_handoff.md

To run Session B (adversarial Devil's Advocate iter 2-3, RAG sweep,
chain analysis, verification, Phase 6d.5 sanity check, report):

  1. CLOSE this Claude Code conversation entirely
  2. OPEN a NEW Claude Code conversation in the same project directory:
     cd {project_path}
  3. Run: /valves thorough

Session B requires fresh context. The architecture's quality guarantee
(Cross-Session Consensus, fresh Devil's Advocate framing, verifier
independence) DEPENDS ON the boundary. Do NOT continue this conversation.

The orchestrator's job in this conversation is DONE.

When you start the new conversation, Step 0-pre will detect the
COMPLETE_A checkpoint and resume in Session B mode. You do not need
to pass any flags.
====================================================================
```

3. **HARD HALT — orchestrator MUST NOT proceed**:
   - Do NOT spawn Phase 4b iter 2 DA agents in this conversation
   - Do NOT run RAG Validation Sweep
   - Do NOT run Chain Analysis
   - Do NOT spawn verifiers
   - Do NOT generate any report artifacts
   - Do NOT proceed to ANY phase ≥ Phase 4b iter 2
   - Do NOT continue conversation processing other than the banner above

4. **Anti-bypass note**: if the user replies in the same conversation asking "continue" / "proceed" / "run session B" / etc., the orchestrator MUST refuse and re-emit the banner. Session B in the same conversation breaks the architecture's quality contract regardless of user request. The user starts a new conversation OR they don't get Session B.

5. **Why this is non-negotiable**: PATCH7+PATCH8 added Cross-Session Consensus, Open Question / Disputed Assumption / Heuristic Lens columns specifically because they're "structured fields, not prose" — designed to survive the boundary. If there's NO BOUNDARY (Session A reasoning lives in Session B's context window), the prose-protection mechanism never gets exercised and the +0.15 / +0.10 / +0.0 consensus bonuses are meaningless.

**For Light/Core mode**: this halt is SKIPPED — those modes don't use the Session A/B split (Core writes COMPLETE_A but proceeds inline; Light skips checkpoints entirely). The Session A/B contract applies only to Thorough. Light/Core do NOT write `HALT_AFTER_COMPLETE_A.md` — Phase 0.9 § E only fires when `MODE == THOROUGH AND SESSION == "A"`.

### Session A → B Handoff Build (Valves v1.7-PATCH -> MANDATORY pre-checkpoint sub-step)

Orchestrator-inline. Five mechanical artifacts written in this order BEFORE `session_checkpoint.md` is rewritten and BEFORE `blind_spot_report.md` is rewritten. Each is bounded, each has a fixed schema, each is a Session B targeting input. None of them generate findings.

**1. `coverage_density.md`** -> per-contract risky-but-underexplored map. Schema, risky-function classifier, and Coverage Score formula in `~/.valves/rules/coverage-density.md` § Risky Function classifier, § Coverage Score, § Priority bands. Inputs: `contract_inventory.md`, `function_list.md`, `findings_inventory.md`, `setter_list.md`, `state_variables.md`, `attack_surface.md`, `system_breakpoints.md` (if present), `economic_findings.md` (if present).

**2. `negative_space.md`** -> explicit zero-finding high-risk targets:

```
Write {SCRATCHPAD}/negative_space.md:

# Negative Space Scan -> {project} -> {ISO timestamp}

## Targets (zero-finding, high-risk)
| Target | Type | Why dangerous | Current coverage gap | Recommended Session B domain |
|---|---|---|---|---|

Categories to enumerate (one row each, only when zero finding maps to it):
- zero-finding modules from coverage_density.md priority CRITICAL/HIGH
- zero-finding emergency paths (functions matching emergency*/forceClose*/migrate*/rescue*/liquidateAll* with no findings)
- zero-finding governance / pause / upgrade paths (functions matching pause*/unpause*/upgrade*/setOwner*/transferOwnership* with no findings)
- zero-finding reward/accounting paths (functions writing reward index, accumulators, share price, fee accumulators with no findings)
- zero-finding cross-contract flows (contract pairs in attack_surface.md dependency graph that have no cross-contract finding linking them)

## Summary
- Total negative-space targets: {N}
- Distribution by type: emergency {E} / governance {G} / reward {R} / cross-contract {X} / module {M}
```

Hard rule: every row must cite a concrete contract or `Contract.function`. Vague entries are discarded. Cap: total ≤ 15 rows; if more candidates qualify, prioritize by: emergency > governance > reward > cross-contract > module.

**3. `seed_outcomes.md`** -> every seed from Session A reaches exactly one terminal outcome:

```
Write {SCRATCHPAD}/seed_outcomes.md:

# Seed Outcomes -> {project} -> {ISO timestamp}

## All seeds (consolidated, raw)
| Seed ID | Sweep / Source | Location | Domain | Outcome | Linked Finding ID or Clear Reason | Proof Type | Canonical Seed ID |
|---|---|---|---|---|---|---|---|

Source files (read all that exist):
- candidate_seeds.md (harvester sweeps 1->8 -> seed IDs use sweep prefix)
- assumption_breaker_seeds.md (AB-1..AB-6)
- analog_seeds.md (AS-1..AS-8 -> Session A subset only; Session B forward-only seeds are routed but recorded with outcome=FORWARD_TO_SESSION_B)
  - If `analog_seeds.md` § Source: SKIPPED (per `~/.valves/rules/analog-seeds.md` § Conditional triggers, v1.7-PATCH2), the analog rows in seed_outcomes.md are simply absent -> NOT a fault. The Per-source counters below show `analog: 0/0/0`.

Outcome (exactly one per seed):
- PROMOTED_TO_FINDING -> depth iter 1 produced a finding for this seed -> record the [F-N] ID
- CLEARED_PRE_DEPTH -> the seed was filtered out before depth iter 1 (e.g., excluded as already-known by harvester) OR cleared by inspection during P1 propagation. **(v1.7-PATCH3 PATCH 1)** REQUIRES a row in `## CLEARED Proof Records` below with all four required proof fields (file:line + guard/invariant + reason + Proof Type per `~/.valves/rules/cleared-proof-discipline.md`). If proof is missing -> DOWNGRADE to FORWARD_TO_SESSION_B with reason `INSUFFICIENT_CLEAR_PROOF`.
- FORWARD_TO_SESSION_B -> the seed is still plausible and unresolved at end of Session A; Session B should consider it (analog Session B subset, assumption-breaker seeds whose depth output was inconclusive, harvester seeds whose CLEARED(depth) reason was weak or absent, OR seeds that previously qualified as CLEARED_PRE_DEPTH but failed the proof discipline downgrade)

Proof Type column (v1.7-PATCH3 PATCH 1):
- Filled when Outcome=CLEARED_PRE_DEPTH. One of: GUARD_PRESENT / INVARIANT_ENFORCED / TRUST_MODEL_EXPLICIT / STATE_UNREACHABLE / EXTERNAL_DEPENDENCY_SAFE / OTHER (with specification).
- Empty when Outcome != CLEARED_PRE_DEPTH.
- See `~/.valves/rules/cleared-proof-discipline.md` § Required minimum proof fields.

Canonical Seed ID column (v1.7-PATCH2):
- Filled by `canonical_seed_map.md` build (next step). Until then, leave column blank; the canonical map writer back-fills the IDs after dedup.
- Every raw row eventually carries a CS-N reference -> the orchestrator verifies this invariant after the canonical map is written.

## CLEARED Proof Records (v1.7-PATCH3 PATCH 1 -> mandatory for every CLEARED_PRE_DEPTH row above)
| Seed ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (<=25 words) |
|---|---|---|---|---|

If a seed has Outcome=CLEARED_PRE_DEPTH in the main table but no row here, the orchestrator's COMPLETE_A handoff sub-step build emits `CLEARED_PROOF_GAP_DETECTED` to `degradation_log.md` and DOWNGRADES the seed to FORWARD_TO_SESSION_B per `~/.valves/rules/cleared-proof-discipline.md` § Hard rule.

## Hard rule
No seed may be silently absent from this table. The orchestrator builds this list mechanically -> every seed ID from the three source files appears in exactly one row.

## Summary
- Total seeds: {N}
- PROMOTED_TO_FINDING: {P}
- CLEARED_PRE_DEPTH (with valid proof): {C_proof}
- DOWNGRADED from CLEARED to FORWARD due to missing proof (v1.7-PATCH3): {C_downgrade}
- FORWARD_TO_SESSION_B (total, including downgrades): {F}
- Per-source: harvester {Hp}/{Hc}/{Hf}, assumption-breaker {ABp}/{ABc}/{ABf}, analog {ASp}/{ASc}/{ASf}
- Proof type distribution (v1.7-PATCH3): GUARD_PRESENT {pg} / INVARIANT_ENFORCED {pi} / TRUST_MODEL_EXPLICIT {pt} / STATE_UNREACHABLE {ps} / EXTERNAL_DEPENDENCY_SAFE {pe} / OTHER {po}
```

**4. `canonical_seed_map.md` (v1.7-PATCH2 -> NEW dedup layer; v1.7-PATCH3 -> + proof records + sibling links; v1.7-PATCH7 -> + Open Question / Disputed Assumption columns; v1.7-PATCH8 -> + Heuristic Lens column)** -> one row per canonical (deduplicated) seed cluster. Methodology, equivalence classes (E1-E11; E11 SEQUENCE added v1.7-PATCH7), merge predicate, Normalized Outcome derivation, **CLEARED proof discipline (v1.7-PATCH3)**, **Sibling Links predicate (v1.7-PATCH3)**, and the **PATCH7+PATCH8 OPTIONAL columns + Heuristic Lens precedence rules** in `~/.valves/rules/canonical-seed-map.md` § Schema + § Heuristic Lens precedence (v1.7-PATCH9). Schema:

```
Write {SCRATCHPAD}/canonical_seed_map.md:

# Canonical Seed Map -> {project} -> {ISO timestamp}

## Canonical seeds
| Canonical Seed ID | Source Provenance | Primary Location | Domain | Seed Family | Likely BC / Sweep Link | Members | Normalized Outcome | Linked Finding ID or Why unresolved | Open Question (v1.7-PATCH7) | Disputed Assumption (v1.7-PATCH7) | Heuristic Lens (v1.7-PATCH8) |
|---|---|---|---|---|---|---|---|---|---|---|---|

After this file is written, back-fill the `Canonical Seed ID` column in `seed_outcomes.md` (every raw row gets the CS-N of its canonical parent). The hard invariant: every raw seed in seed_outcomes.md appears in exactly one canonical entry's Source Provenance, and every CS-N has Members >= 1.

**Column derivation (orchestrator inline, mechanical, v1.7-PATCH9 explicit producer note)**:
- `Open Question`, `Disputed Assumption`, `Heuristic Lens` are OPTIONAL — emit `-` when not derivable from member raw seed evidence. Inventing values is forbidden; the orchestrator follows `~/.valves/rules/canonical-seed-map.md` § Schema derivation rules verbatim.
- `Heuristic Lens` derivation applies the precedence rule from `~/.valves/rules/canonical-seed-map.md` § Heuristic Lens precedence when multiple lenses fit a single canonical (STATE-TRANSITION > SEQUENCE > SYMMETRY > BIG-VS-SMALL > NUMERIC-EXTREME > NONEXISTENT-ID > DEAD-STATE; TEST-SKEPTIC orthogonal — only assigned when source is `[VS-TS-1]`).
- Off-enum values for Heuristic Lens are rejected at COMPLETE_A handoff build time; the rejected canonical is logged to `degradation_log.md` as `LENS_OFF_ENUM_REJECTED` and the column normalized to `-` for the affected row.

## CLEARED Proof Records (v1.7-PATCH3 PATCH 1 -> mandatory for every CLEARED canonical)
| Canonical Seed ID | Proof Type | file:line | Guard / Invariant / State Condition | Reason exploitability fails (<=25 words) |
|---|---|---|---|---|

The orchestrator inherits proof from the strongest member raw seed (most-specific file:line, highest-confidence Proof Type from `seed_outcomes.md` § CLEARED Proof Records). When a canonical has Normalized Outcome=CLEARED_PRE_DEPTH but no row here -> `CLEARED_PROOF_GAP_DETECTED` is logged AND the canonical is DOWNGRADED to FORWARD_TO_SESSION_B per `~/.valves/rules/cleared-proof-discipline.md` § Hard rule.

## Sibling Links (v1.7-PATCH3 PATCH 3 -> investigation-neighborhood hints, NOT merges)
| Canonical Seed ID | Linked Canonicals | Link Type |
|---|---|---|

Two canonicals are linked iff they remain separate per § Merge predicate but satisfy any one of: same function (different lines), same Contract.function within <= 20 lines, same state tuple / accounting tuple, same external callee / integration point, same actor/victim pair, OR same exploit family but cross-class (e.g., E1 and E8 at the same Contract.function). Symmetric relation; max 3 links per canonical. See `~/.valves/rules/canonical-seed-map.md` § Sibling Links.

## Proof gaps (members) -> for canonicals with mixed proof quality
| Canonical Seed ID | Members lacking proof | Action |
|---|---|---|
| CS-N | Sweep-1:S-7, AB-3 | Inherited proof from AS-2; gap members logged but not blocking |

## Summary
- Raw seeds across all sources: {R}
- Canonical seeds (after dedup): {C}
- Compression ratio: {C}/{R}
- By Normalized Outcome: PROMOTED {P_canon} / CLEARED {C_canon} / FORWARD {F_canon}
- DOWNGRADED to FORWARD due to missing proof (v1.7-PATCH3): {C_downgrade}
- By family: E1 {n1} / E2 {n2} / E3 {n3} / E4 {n4} / E5 {n5} / E6 {n6} / E7 {n7} / E8 {n8} / E9 {n9} / E10 {n10} / E11 {n11}   # E11 SEQUENCE added v1.7-PATCH7
- Cross-source canonicals (Members >= 2 from >= 2 different sources): {X} -> high-signal targets
- Sibling-linked canonicals (v1.7-PATCH3): {SL} canonicals with >= 1 sibling link
- Proof type distribution: GUARD_PRESENT {pg} / INVARIANT_ENFORCED {pi} / TRUST_MODEL_EXPLICIT {pt} / STATE_UNREACHABLE {ps} / EXTERNAL_DEPENDENCY_SAFE {pe} / OTHER {po}
```

**5. `disagreement_queue.md`** -> high-signal contradictions found across Session A agent outputs:

```
Write {SCRATCHPAD}/disagreement_queue.md:

# Disagreement Queue (Session A -> Session B)

## Disagreements
| Queue ID | Related IDs | Location | Disagreement type | Agents / sources | Why it matters | Session B owner |
|---|---|---|---|---|---|---|

Disagreement types to capture (orchestrator-inline scan; NOT an agent):
- SAME_LOC_DIFF_VERDICT -> same file:function, two agents reach different verdicts (one CONFIRMED, one REFUTED/CLEARED)
- SAME_BC_DIFF_ROOT_CAUSE -> two findings tagged same BC-NNN in finding_classification.md but their underlying invariant differs
- SAME_SURFACE_DIFF_SEVERITY -> two findings on the same surface (function or storage var) with severity tier delta >= 2 (Critical/Medium, High/Low, etc.)
- FLAG_VS_CLEAR -> one agent flagged a location, another agent's CLEARED(depth) covers the same location
- PARENT_VS_CHILD -> one agent records a child-symptom finding (stale approval, CEI imperfection), another records a parent-exploit on the same surface (custody loss). Cross-reference strongest_exploit_cards.md.

Source files to scan:
- analysis_*.md (breadth)
- analysis_depth_*.md (depth iter 1)
- analysis_scanner_*.md
- analysis_niche_*.md
- validation_sweep.md
- economic_findings.md
- diff_audit_tiers.md (Tier A/B locations)
- candidate_seeds.md CLEARED rows
- finding_classification.md flags

## Hard rules
- Cap: ≤ 12 disagreements total. If more candidates pass the type filter, rank by: PARENT_VS_CHILD > FLAG_VS_CLEAR > SAME_SURFACE_DIFF_SEVERITY > SAME_LOC_DIFF_VERDICT > SAME_BC_DIFF_ROOT_CAUSE.
- Each row MUST cite at least 2 source artifacts in `Agents / sources`.
- This is a Session B targeting input, NOT a final-report input. Disagreements that survive Session B's DA pass go to `cross_session_consensus.md` and `Phase 5.2 cross-batch consistency` -> they are not auto-promoted to findings.

## Summary
- Total disagreements: {N}
- By type: PvC {P} / FvC {F} / SDS {S} / SLD {L} / SBD {B}
```

**6. `session_a_to_b_handoff.md`** -> single ranked target sheet for Session B. Schema, ranking formula, caps, **slack redistribution (v1.7-PATCH3 PATCH 2)**, **Linked CS column (v1.7-PATCH3 PATCH 3)**, **family-diversity cap (v1.7-PATCH4 PATCH 3)**, and **dominant-family override (v1.7-PATCH5 PATCH 3)** in `~/.valves/rules/session-a-to-b-handoff.md`. Six fixed sections (top blind spots / unresolved seeds / disagreements / negative space / uncertain Medium+ / orphans). Default 32-row cap PLUS **up to 3 redistributed slack slots** PLUS **up to +1 dominant-family override slot** = hard upper bound on final total = **36**.

The handoff artifact emits a new **§ 0. Redistribution Metadata** section between the title block and § 1, recording the slack mechanics + family-diversity cap state:

```
## 0. Redistribution Metadata (v1.7-PATCH3 base, extended in v1.7-PATCH4)
- redistributed_from: [{section_id, slots_donated}, ...]
- redistributed_to: [{section_id, slots_received, candidate_ids}, ...]
- slack_slots_used: {0..3}
- threshold_blocked: {true/false}   # true if surplus existed but no candidate cleared the 0.40 score threshold
- slack_eligible_recipients: [§ 1, § 2, § 4, § 5]   # disagreements (§ 3) and orphans (§ 6) are NOT slack-eligible
# (final_total_targets is the SINGLE source-of-truth field at the bottom of this block, post-override)

# v1.7-PATCH4 PATCH 3 - family-diversity cap state for § 2
- family_diversity_cap_applied: {true/false}   # false when total FORWARD pool < 4 (exemption)
- families_capped: [{family_id, candidates_held: N}, ...]   # families that hit the 2-per-family soft cap
- diversity_overflow_promoted: {N}   # overflow candidates refilled into § 2 to prevent underfill

# v1.7-PATCH5 PATCH 3 - dominant-family override (max +1 extra slot when score gap >= 0.25)
- dominant_family_override_applied: {true/false}
- dominant_family: {family_id or null}
- override_score_gap: {decimal or null}
- override_threshold: 0.25
- override_held_promoted: {canonical_seed_id or null}
- override_next_best_alt: {canonical_seed_id or null}
- final_total_targets: {32..36}   # upper bound bumped from 35 (slack only) to 36 (slack + override)
```

`§ 0` is emitted ALWAYS, even when `slack_slots_used == 0` -> silence is not a valid state. Redistributed rows in §§ 1/2/4/5 are tagged `[REDISTRIBUTED]` so Session B sees that they came via slack, not via the section's primary source. See `~/.valves/rules/session-a-to-b-handoff.md` § Slack redistribution for the full algorithm (slack pool computation, distribution algorithm, 0.40 score threshold, deterministic ranking, no-orphan-spam guarantee).

§ 2 of the handoff also gains a `Linked CS` column (v1.7-PATCH3 PATCH 3) sourcing from `canonical_seed_map.md` § Sibling Links -> investigation-neighborhood hints for Session B without merging.

§ 2 also gains `Open Question` and `Disputed Assumption` columns (v1.7-PATCH7) — pasted verbatim from the corresponding `canonical_seed_map.md` rows. Empty values normalize to `-`. The orchestrator's handoff build does NOT invent these fields; if the canonical's row has `-`, this row has `-`. Session B's DA agent prompts read these columns to bias its adversarial probe (see § Session B Behavioral Rules § 1). See `~/.valves/rules/canonical-seed-map.md` § Schema for derivation rules and `~/.valves/rules/valves-doctrine.md` § The 8 mandatory adversarial questions for the reasoning lens.

§ 2 also gains a `Heuristic Lens` column (v1.7-PATCH8) — pasted verbatim from `canonical_seed_map.md`. Tag enum is fixed: `SYMMETRY` / `STATE-TRANSITION` / `SEQUENCE` / `BIG-VS-SMALL` / `NUMERIC-EXTREME` / `NONEXISTENT-ID` / `TEST-SKEPTIC` / `DEAD-STATE` / `-`. The orchestrator validates the enum at build time (off-enum values rejected). Session B's DA agent prompt routes through the lens to apply the corresponding methodology from `~/.valves/rules/valves-doctrine.md` § Heuristic Lenses BEFORE general re-attack. The lens is a routing convenience, not a substantive claim — `-` is always a safe default.

> **Build order is binding** (v1.7-PATCH2): 1 → 2 → 3 → 4 → 5 → 6. Sub-steps 1-5 read raw inputs and write per-step artifacts; sub-step 6 (`session_a_to_b_handoff.md`) consumes 1-5 + `confidence_scores.md` + `findings_inventory.md` + `attack_thesis.md` v1/v2. Critically, **§ 2 of the handoff (Top unresolved seeds) consumes `canonical_seed_map.md` (canonical entries WHERE Normalized Outcome=FORWARD_TO_SESSION_B), NOT raw `seed_outcomes.md`** -> this is where dedup pays off.

**Hard gate (Thorough)**: `session_a_to_b_handoff.md` MUST exist before Session B begins. The Step 0-pre integrity check at COMPLETE_A resume includes this assertion alongside `findings_inventory.md` and `blind_spot_report.md`.

---

**Artifact 1: `session_checkpoint.md`** -> upgraded from PARTIAL_A to COMPLETE_A with finding cards + structured metadata.

The orchestrator writes this INLINE (overwrites the PARTIAL_A version):

```
Write {SCRATCHPAD}/session_checkpoint.md:

# Session Checkpoint (Valves v1.7)
## Pipeline State
- CHECKPOINT_LEVEL: COMPLETE_A
- MODE: {MODE}
- LANGUAGE: {LANGUAGE}
- SCRATCHPAD: {SCRATCHPAD}
- PROJECT_ROOT: {PROJECT_ROOT}
- CHECKPOINT_PHASE: Depth Iter 1 + Scoring (Phase 4b step 2 complete)
- NEXT_PHASE: Phase 4b Iteration 2 (DA pass)
- TIMESTAMP: {ISO 8601}

## Launch-State Fields (audit contract -> must match Session A)
- DOCS_PATH: {DOCS_PATH or "none"}
- NETWORK: {NETWORK or "none"}
- RPC_URL: {RPC_URL or "none"}
- SCOPE_FILE: {SCOPE_FILE or "none"}
- SCOPE_NOTES: {SCOPE_NOTES or "none"}
- PROVEN_ONLY: {true/false}
- HISTORICAL_PRIME_MODE: {true/false}

## Checklist State (ALL rows -> full terminal picture)
{paste ALL rows from mandatory_step_checklist.md including:
 - COMPLETE rows (with evidence artifact)
 - FAILED_WITH_FALLBACK rows (with fallback artifact)
 - NOT_APPLICABLE rows (with reason -> preserved so Session B does not re-evaluate applicability)
 - PENDING / RUNNING rows (Session B resumes from first PENDING)}

## Active Flags
{from template_recommendations.md: all detected flags, niche agents loaded, injectable skills loaded}

## Finding Cards
CRITICAL: These cards contain EVIDENCE ONLY -> no reasoning, no conclusions, no "why this is real" prose.
v1.7-PATCH (PATCH D) extends the schema with STRUCTURED metadata fields. These are mechanical attributes (Y/N, IDs, names) -> NOT prose. Session B gains triage efficiency from them, not inherited Session A conclusions.

| ID | Title | Location | Severity | Evidence Type | Bug-Class | Strongest Exploit? | Correctness Winner? | Contested? | Confidence | Surface | Actor | Victim | State Domain | Cross-Contract? | Economic? | Seed-Origin? | Thesis-Linked? | Historical-Prime-Linked? | Low-Coverage-Module-Linked? | Disputed? |
|----|-------|----------|----------|---------------|-----------|-------------------|--------------------|-----------|------------|---------|-------|--------|--------------|-----------------|-----------|--------------|----------------|--------------------------|-----------------------------|-----------|
{one row per finding from findings_inventory.md}

Field definitions (v1.7-PATCH structured-metadata extension):
- **Surface** -> one of {entry-point, admin-setter, internal-helper, external-call, callback-hook, view, constructor, fallback-receive}. Mechanical from `attack_surface.md` priority + function modifiers.
- **Actor** -> who triggers the path. One of {untrusted, depositor, LP, borrower, admin, governance, keeper, oracle, self, multisig}. Mechanical from access control + caller analysis in the finding's location.
- **Victim** -> whose state is affected. One of {depositor, LP, borrower, treasury, protocol, governance, third-party}. Mechanical from accounting trace.
- **State Domain** -> one of {custody, accounting, privilege, oracle, governance, fee, reward, escrow, accounting-mirror}. From `state_variables.md` classification.
- **Cross-Contract?** -> `Y` if the finding's exploit path crosses contract boundaries (uses a contract-to-contract call from `contract_inventory.md` dependency graph), else `N`. Mechanical.
- **Economic?** -> `Y` if the finding originated from `economic_findings.md` ([EI-THEORY], [EI-TRACE], [EI-SIM]) OR if the path requires an economic trigger (extractable value calculation). Mechanical lookup.
- **Seed-Origin?** -> the seed ID this finding was promoted from (e.g., `Sweep-1:S-3`, `AB-2`, `AS-4`). `-` if no seed origin. Mechanical lookup in `seed_outcomes.md`.
- **Thesis-Linked?** -> the path ID from `attack_thesis.md` v1/v2 if this finding is cited as supporting evidence (e.g., `P-1`). `-` otherwise. Mechanical.
- **Historical-Prime-Linked?** -> the seed ID from `historical_prime_seeds.md` if this finding aligns with a prior-report seed (e.g., `HP-3`). `-` otherwise. Mechanical.
- **Low-Coverage-Module-Linked?** -> the contract name from `coverage_density.md` if the finding's location maps to a CRITICAL/HIGH priority contract. `-` otherwise.
- **Disputed?** -> `Y` if this finding appears in `disagreement_queue.md` (any disagreement type). Else `N`.

These fields are FILLED MECHANICALLY by the orchestrator at COMPLETE_A write time. NO AGENT WRITES THESE. NO REASONING PROSE. Each is a lookup or a structural classification.

## Open Contradictions
{findings with conflicting verdicts across agents -> these are priority targets for Session B. Cross-reference: every entry here MUST also appear in `disagreement_queue.md` (PATCH C). This section is a back-compat duplicate; Session B reads `disagreement_queue.md` for the structured form.}

## Verification Queue
{from verification_priority_queue.md if exists: EV-ranked priority order}
```

**What is deliberately EXCLUDED from the checkpoint** (this is the quality mechanism):
- Depth agent analysis prose and reasoning (iter 1 analysis stays in Session A's context only)
- Confidence score justifications (scores carried, reasoning not)
- "Why I believe this bug is real" arguments from any agent
- Hypothesis grouping reasoning from synthesis

Session B forms its own conclusions from evidence + code. That independence IS the quality gain.

**Artifact 2: `blind_spot_report.md`** -> coverage gaps for Session B targeting.

The orchestrator writes this INLINE by comparing attack_surface.md against findings_inventory.md:

```
Write {SCRATCHPAD}/blind_spot_report.md:

# Blind Spot Report (Session A -> Session B)

## Low-Coverage Modules
| Contract | Total Functions | Findings Mapped | Coverage Ratio | Flag |
|----------|----------------|-----------------|---------------|------|
{for each contract in contract_inventory.md: count functions from function_list.md,
 count findings from findings_inventory.md where location matches,
 ratio = findings/functions, flag LOW if ratio < 0.1}

## Weakly Explored Attack Surfaces
{from attack_surface.md: entry points with zero or one finding mapped to them}

## Missing Cross-Contract Traces
{contract pairs from attack_surface.md dependency graph that have no
 cross-contract finding linking them -> potential unexamined interaction paths}

## Uncertain Medium+ Findings
{findings from confidence_scores.md where composite < 0.5 AND severity >= Medium
 -> these need Session B's independent re-evaluation}

## Unresolved Candidate Seeds (v1.7 -> top 5, capped)
{from candidate_seeds.md: select up to 5 seeds that meet ALL of:
 (a) NOT covered by any finding in findings_inventory.md (no location overlap)
 (b) NOT CLEARED(depth) by any depth agent in iter 1
 (c) sweep type is symmetric-branch, interface-mismatch, or dependency (higher signal)
 priority: interface > symmetric > dependency > desync > parity}

| Seed ID | Sweep | Location | Anomaly | Why Unresolved |
|---------|-------|----------|---------|---------------|

These seeds are specific code-located investigation targets -> not vague coverage gaps.
Session B DA agents treat them as MANDATORY investigation targets alongside blind spot modules.

## Recommended Session B Targets (priority order)
1. {highest priority: low-coverage module with complex logic}
2. {second: unexplored cross-contract path}
3. {third: uncertain Medium+ finding needing fresh analysis}
4. {fourth: top unresolved candidate seed from sweep 1-5}
5. {fifth: second unresolved candidate seed}
```

---

### Session B Behavioral Rules (v1.7 + PATCH11 isolation)

When `SESSION == B`, the following modifications apply to downstream phases. These are NOT new phases -> they modify existing phase behavior to exploit the session boundary for quality gains.

**§ 0. Physical isolation contract (v1.7-PATCH11 — HARD RULE, fires before any agent spawn)**

```
SESSION_A_ARCHIVE = "{PROJECT_ROOT}/.audit_session_a"

HARD RULES (all agents + orchestrator, until cross-session consensus step):
  - MUST NOT Read() any path under SESSION_A_ARCHIVE
  - MUST NOT Read() findings_inventory.md from the archive
  - MUST NOT Read() hypotheses.md, attack_thesis*.md, synthesis_full.md from archive
  - MUST NOT Read() analysis_*.md, depth_*_findings.md from archive
  - MUST NOT Read() confidence_scores.md from archive
  - MUST NOT Read() verify_*.md, report_*.md, AUDIT_REPORT*.md from archive
  - MUST NOT inject Session A reasoning prose into any agent prompt

ALLOWED:
  - Read files listed in {SCRATCHPAD}/SESSION_B_READ_SCOPE.md
  - Read source code files under {PROJECT_ROOT}/
  - After cross-session consensus step: orchestrator may read structured fields
    from {SESSION_A_ARCHIVE}/findings_inventory.md and confidence_scores.md
    for the consensus table ONLY

ENFORCEMENT:
  - Phase 0.9 § A post-spawn integrity check: if agent's Read() targets include
    any path matching ".audit_session_a/" → SESSION_B_ISOLATION_BREACH violation
  - First violation → AUTO-DISCARD + re-spawn with isolation reminder
  - Second violation → SCOPE_VIOLATION_PERSISTENT → INVALID FINALIZATION
```

**1. Depth iterations 2-3: Session B OWNS the DA pass**

Session B begins at Phase 4b iteration 2. Session A completed iteration 1 + scoring only. This means Session B's DA agents run with genuinely fresh context -> no anchoring to Session A's iter 1 reasoning, which is NOT in Session B's context window.

Session B's DA agents receive (v1.7-PATCH -> single authoritative target sheet):
- Finding cards from `session_checkpoint.md` (evidence-only, with structured metadata fields per PATCH D -> NO reasoning prose)
- **`session_a_to_b_handoff.md`** as the SINGLE authoritative target sheet (v1.7-PATCH -> replaces direct reads of `blind_spot_report.md`). Six fixed sections: top dangerous blind spots, top unresolved seeds, top disagreements, top negative-space targets, top uncertain Medium+ findings, top orphan / non-thesis candidates. **32-row default cap; up to 36 with slack redistribution (v1.7-PATCH3, +3) + dominant-family override (v1.7-PATCH5, +1)**. Per-section targeting; Session B does NOT broaden beyond these rows.
- `confidence_scores.md` for routing (UNCERTAIN/LOW findings get priority within § 5 of the handoff)
- Source code files directly

Back-compat: `blind_spot_report.md` is still written for back-compat (existing § 1858 reference). It is a SUBSET of `session_a_to_b_handoff.md` § 1 + § 5. Session B prefers the handoff; do not double-read.

Add to the DA agent prompt:

> "You are running in Session B -> a quality pass with fresh context. Session A completed discovery (iter 1) and identified the findings below. Your job is adversarial re-analysis with NO access to Session A's reasoning. Read `~/.valves/rules/valves-doctrine.md` § The 8 mandatory adversarial questions, § Heuristic Lenses, § The decision lenses, and § The call-order principle once before starting; apply them as your reasoning baseline.
>
> The Session A → B handoff sheet ranks the targets you MUST prioritize before re-examining already-covered areas. For each entry in your domain (matched by Recommended depth domain column), you MUST produce either a finding or CLEARED(depth) with a specific reason.
>
> When § 2 rows carry `Open Question` or `Disputed Assumption` columns (v1.7-PATCH7), treat these as your PRIMARY adversarial probe for that row — try to answer the open question or refute the disputed assumption before falling back to general re-attack. If you cannot mechanically resolve them, carry them forward as residual unresolved questions in your output (`analysis_depth_da_*.md` should record `Open Question: {question}` / `Disputed Assumption: {assumption}` per row touched).
>
> When § 2 rows carry a `Heuristic Lens` tag (v1.7-PATCH8), apply that lens FIRST before general re-attack. Map: `SYMMETRY` → enumerate and pressure the 7 sibling-pair aspects (guards / validation / state writes / external calls / accounting / fee routing / events) and check whether the asymmetry is direction-justified. `STATE-TRANSITION` → treat the protocol as a state machine; ask whether step 2 can fire without step 1 being TRULY completed, or whether the transition leaves an accounting mirror un-updated. `SEQUENCE` → pressure the 7 call-order patterns (reversed / skipped predecessor / repeated / admin-interleaved / emergency-early / external-update-interleaved / cross-contract-reordered). `BIG-VS-SMALL` → test whether N small operations produce the same state effect as 1 large operation with the same total value (rounding, fee tiers, rate limits, slippage, reward distribution). `NUMERIC-EXTREME` → test behavior near zero, near `type.max`, at decimal-precision boundaries, and at first-depositor / first-user state. `NONEXISTENT-ID` → test calls with attacker-chosen tokenId / market / vault / position IDs, including non-existent and attacker-controlled-fake objects. `TEST-SKEPTIC` → check whether the production path's invariants are actually exercised by tests, and whether the test setup is stricter than production enforces. `DEAD-STATE` → identify storage written but never meaningfully read; the missing read may hide a transition gap.
>
> Apply your DECISION LENS, not just your file region. Your domain (token_flow / state_trace / edge_case / external) tells you which code regions to prioritize; your lens (per `valves-doctrine.md` § The decision lenses) tells you which threats to pressure. Cross-contract sequence assumptions cross domains — when the surface you touch has cross-contract sequencing, you own the call-order question even if it crosses into another domain's typical territory.
>
> **Mandatory output structure (v1.7-PATCH9 — operational-not-decorative requirement)**: For each handoff § 2 row in your assigned domain that carries Open Question / Disputed Assumption / Heuristic Lens (any of the three populated, value != `-`), your `analysis_depth_da_*.md` output MUST contain a structured per-row block:
>
> ```
> ### CS-{N} — {primary_location}
> - lens: {tag from handoff or `-`}
> - oq_addressed: {Y/N}: {one-line answer; or "could not resolve mechanically — carrying forward"}
> - da_tested: {Y/N}: {one-line description of what you actually tested or refuted}
> - finding_or_clear: {[F-N] reference / CLEARED(depth) with proof citation / CONTESTED}
> ```
>
> Rows whose Open Question / Disputed Assumption / Heuristic Lens are all `-` (no derivable structured probe from Session A) do NOT need this block — handle them via standard DA reasoning. The block is mandatory ONLY for rows with at least one populated structured field.
>
> Do not exceed the handoff sheet's row scope -> Session B is precision-focused, not breadth."
> {paste session_a_to_b_handoff.md § 1 (top dangerous blind spots) -> rows whose Recommended depth domain matches this agent}
> {paste session_a_to_b_handoff.md § 2 (top unresolved seeds) -> same domain match}
> {paste session_a_to_b_handoff.md § 3 (top disagreements) -> same domain match}
> {paste session_a_to_b_handoff.md § 4 (top negative-space targets) -> same domain match}
> {paste session_a_to_b_handoff.md § 5 (top uncertain Medium+ findings) -> same domain match}
> {paste session_a_to_b_handoff.md § 6 (top orphan / non-thesis candidates) -> same domain match}

Standard DA role (contrastive conditioning, hard adversarial framing from `phase4-confidence-scoring.md` AD-2) still applies. The handoff sheet is *targeting*, not a replacement for adversarial framing. The THOROUGH CHECKPOINT: Post-Depth (static manifest check) runs in Session B AFTER iter 2-3 complete, before proceeding to RAG sweep.

> **Novel mechanic pressure for DA agents (v1.7-CANTINA-RUNID)**: Every DA agent prompt MUST include this directive AFTER the standard DA prompt and BEFORE Cantina pattern injection: `"Before consulting patterns or RAG, identify any protocol-specific mechanic in your domain that does not cleanly map to a standard vulnerability class (reentrancy, access control, oracle manipulation, etc.). If found, pressure-test it: what invariant should hold, what assumption does it rely on, what call sequence or state drift breaks it. Novel mechanics produce novel bugs that no pattern library covers — this is your highest-value adversarial work."` This reinforces the DA agent's primary purpose: first-principles adversarial reasoning before pattern-matching.

> **Cantina pattern injection for DA agents (v1.7-CANTINA, Rule 34 — STRONGEST INTEGRATION POINT)**: Every DA agent prompt in Session B MUST include a directive to read the full relevant Cantina pattern files for their domain (from `{SCRATCHPAD}/relevant_patterns.md` § Cantina Depth Agent Pattern Map). The directive is appended AFTER the standard DA prompt above:
>
> `"Read the Cantina pattern files below. These describe 80 concrete attack patterns extracted from 279 confirmed HIGH/MEDIUM findings across 16 real DeFi security competitions (Cantina). For each pattern whose Code Shape matches code in your assigned scope:`
> `(1) Check whether Session A's iteration 1 explored this failure mode (use the analysis path summary from finding cards).`
> `(2) If NOT explored — investigate it as an alternative attack vector. This is the core DA value: Cantina patterns represent failure modes that escaped initial auditor attention in live contests.`
> `(3) If explored but CONFIRMED — skip (do not re-confirm known bugs).`
> `(4) If explored but REFUTED — check whether the Cantina pattern's Failure Mode suggests an alternative exploit path the refutation did not consider.`
> `Use Cantina patterns as a source of 'what else could go wrong here?' — they are adversarial hypotheses, not confirmations. Do NOT pattern-match blindly; apply first-principles reasoning to each matching pattern.`
> `Cantina files: {list from Cantina Depth Agent Pattern Map for this agent's domain}."`
>
> **Anti-anchoring guard**: If a DA agent's output contains more Cantina-pattern-sourced findings than first-principles findings, the orchestrator logs `CANTINA_ANCHORING_DETECTED` to `degradation_log.md`. The DA agent's primary job is adversarial re-analysis of handoff targets; Cantina patterns are supplementary alternative vectors, not the methodology.

**2. Chain analysis: Fresh grouping**

Chain Agent 1 reads finding cards from `session_checkpoint.md`, NOT `hypotheses.md` reasoning. It performs grouping from scratch based on evidence and code locations. If Session B's grouping matches Session A's (when hypotheses.md exists from a prior session), that is cross-session consensus -> a stronger signal than single-session grouping.

**3. Verification independence (KEY QUALITY GAIN)**

Verifier agents receive:
- Finding card (ID, title, location, severity, evidence type) from `session_checkpoint.md`
- Source code files
- Build environment
- **Protocol context** (allowed): `design_context.md` (trust model, stated permissions, key invariants), scope notes, network context, documentation references. These are protocol FACTS that affect severity calibration and exploitability assessment.

They do NOT receive: depth agent analysis prose, chain reasoning, confidence assessments, synthesis narratives, "why this bug is real" arguments. The verifier forms its own opinion from the code, finding card, and protocol facts. This eliminates confirmation bias while preserving the context needed for accurate impact assessment -> the single biggest quality improvement of the two-session design.

**4. Confidence re-scoring**

The scoring agent in Session B scores from scratch based on Session B's evidence artifacts. Session A scores (from `session_checkpoint.md` Confidence column) are used ONLY for cross-session consensus detection, not as starting anchors.

**5. Cross-session consensus bonus (strict)**

If Session B's independent analysis reaches the same verdict as Session A for a finding, the bonus is applied ONLY when the agreement is grounded in matching evidence -> not just the same high-level label:
- **+0.15** if Session B confirms the same code locus AND identifies the same root cause (matching variable/function/invariant, not just "reentrancy" -> "reentrancy")
- **+0.10** if Session B confirms the same verdict but through a different analytical path (weaker agreement -> labels match but reasoning diverged)
- **+0.0** if Session B merely inherits the finding card label without independent code-level confirmation (no bonus for parroting)

Capped at 1.0. The intent is that two independent context windows agreeing on the SAME code-level evidence is a strong signal, but two sessions using the same framed finding card to reach the same label is not.

**6. Cross-Session Consensus Artifact (Valves v1.7-PATCH -> PATCH J -> MANDATORY)**

Immediately after Session B's confidence re-scoring (rule 4 above) and BEFORE the consensus bonus (rule 5) is applied to composite scores, the orchestrator writes `{SCRATCHPAD}/cross_session_consensus.md` -> one row per finding from `findings_inventory.md`. The artifact is structured-fields-only (no agent prose injected).

Schema, field definitions, and gate semantics: see `~/.valves/rules/cross-session-consensus.md` § Schema, § Hard rule, § Application, § Hard gate.

Inputs (orchestrator inline lookup -> NO new agent spawn):
- `{SCRATCHPAD}/session_checkpoint.md` § Finding Cards (Session A view, evidence + structured metadata only)
- Session B's `analysis_depth_da_*.md` (verdict per finding, where Session B targeted it)
- Session B's freshly re-scored `confidence_scores.md` (Session B view)
- `{SCRATCHPAD}/disagreement_queue.md` (cross-reference for Session A internal disagreements)
- `{SCRATCHPAD}/verify_*.md` (when present at write-time -> partial data acceptable)

Output ONE row per `findings_inventory.md` finding:

```
| Finding ID | Session A View | Session B View | Verdict Match? | Root Cause Match? | Severity Match? | Consensus Bonus Eligible? | Notes |
```

`Session A View` and `Session B View` are each a structured triple `{verdict, severity, root-cause-tag}`. `Consensus Bonus Eligible?` is one of `+0.15`, `+0.10`, `+0.0`, or `INCOMPLETE` (Session B did not exercise this finding because not in handoff targets).

After the artifact is written, the consensus bonus from rule 5 is applied as a parameterized lookup: `composite_after_bonus = min(1.0, composite + Consensus_Bonus_Eligible)`. The applied bonus is logged to `{SCRATCHPAD}/confidence_scores.md` § Cross-Session Bonus Applied (new sub-section).

**Hard gate (Thorough)**: `cross_session_consensus.md` MUST exist before Phase 5.6.1 (Thesis v3 generation). The Thesis v3 PRIOR_NEGATIVE_OVERRIDDEN handling reads this file's Verdict Match column. If missing on first attempt -> orchestrator inline retries once; if still missing -> BLOCK in Thorough (degrade-and-log only in Core/Light).

**Why this does not blur the boundary**: the artifact is built by the orchestrator from structured outputs of both sessions -> no Session A reasoning is injected into Session B agent prompts. Rule 4 (fresh re-scoring) and rule 3 (verifier independence) remain unchanged.

**7. Heuristic-field operational compliance scan (v1.7-PATCH9 — orchestrator inline, NO new agent, NO new artifact)**

After Session B's depth iter 2/3 completes and BEFORE Phase 4c chain analysis spawns, the orchestrator runs a mechanical scan on each `analysis_depth_da_*.md` file. For each handoff § 2 row that the DA agent's domain owned AND that carried at least one populated structured field (Open Question != `-` OR Disputed Assumption != `-` OR Heuristic Lens != `-`):

- Verify the DA file contains a per-row block matching the rule 1 mandatory-output pattern: `### CS-{N}` heading + `lens:` + `oq_addressed:` + `da_tested:` + `finding_or_clear:`.
- If the block is missing → log `HEURISTIC_FIELD_NOT_OPERATIONAL CS-{N} agent={agent_id}` to `{SCRATCHPAD}/violations.md`. The orchestrator does NOT re-spawn the agent and does NOT block — this is observability, not enforcement. The violation count surfaces in `seed_metrics.md` § Operational compliance (v1.7-PATCH9) so future audits can correlate non-compliance with recall regression.

The scan is mechanical: `grep -L "### CS-{N}"` on the DA files, intersected with the handoff § 2 rows whose structured fields are populated. No agent reasoning. No semantic check on whether the DA's answer is actually good — only that the structured block exists. Quality of the DA's answers remains a Session B reasoning property.

**Why this is precision-positive**: makes the PATCH7 + PATCH8 structured fields operational rather than decorative. When DA agents skip the structured block, the violation log surfaces it; over multiple audits the count signals whether the prompt language needs tightening. Without this scan, "Open Question / Disputed Assumption / Heuristic Lens influenced Session B" was a hope, not a measurement.

---

### Phase 4b.5: RAG Validation Sweep (MANDATORY for Core/Thorough -> checklist row 34 (RAG Validation Sweep))

> **Thorough strict-mode (v1.5)**: Row 34 must reach `COMPLETE`, `FAILED_WITH_FALLBACK`, or `NOT_APPLICABLE` -> watchdog will block Phase 4c advancement until then.

Read: `~/.valves/rules/phase4-confidence-scoring.md` -> "Phase 4b.5" section.
Update checklist row 34 to RUNNING.
Spawn sonnet RAG sweep agent.

After completion:
- `rag_validation.md` exists with per-finding RAG scores -> row 34 `COMPLETE`
- `rag_validation.md` exists with floor scores (0.3) AND fallback chain logged in agent's return -> row 34 `FAILED_WITH_FALLBACK` (web search fallback + floor scores IS the template-defined fallback)
- Agent fails entirely (no artifact) AND orchestrator inline writes the floor-scores artifact per the retry-on-agent-failure rule -> row 34 `FAILED_WITH_FALLBACK`
- Otherwise -> row stays unfinished; watchdog blocks

For Thorough mode, "writing floor scores without attempting" remains a VIOLATION (logged) AND blocks the gate.

> **If RAG is not built**: The unified-vuln-db MCP server may not be running. The sweep agent will detect this on the first tool call and fall back to WebSearch automatically (this counts as `FAILED_WITH_FALLBACK`, not a block). To enable real RAG, the user should run `plamen rag` in their terminal before the next audit.

### Phase 4c.5 (VALVES): Verification Priority Queue Construction

After chain analysis completes (Phase 4c), orchestrator inline work. No new agent spawns.

For each finding in `findings_inventory.md` where severity meets the mode's verification threshold, compute:
```
EV(F) = impact_weight(severity)
      Ã thesis_alignment(F, attack_thesis.md)
      Ã cluster_leverage(F, root_cause_clusters.md)
      Ã poc_cost_factor(F)          // bucketed 0.30->1.00 per ~/.valves/rules/verification-priority-queue.md
      Ã information_gain(F)
```

Apply +2 EV bonus for findings at Tier A diff-audit locations. Apply +3 EV bonus for Chain Hypotheses. Apply +1 EV bonus for findings in the Reality-HIGH / Report-LOW quadrant.

Sort descending by EV. Write `{SCRATCHPAD}/verification_priority_queue.md` with the full ranked table, cluster-representative flags, and inheritance rules per `~/.valves/rules/verification-priority-queue.md`.

This queue is the input to Phase 5 -> verifiers spawn in EV-rank order, not severity order.

### Phase 5: Verification (Batched Spawning)

> **Read templates from**: `~/.claude/prompts/{LANGUAGE}/phase5-verification-prompt.md` + `~/.valves/rules/phase5-poc-execution.md`

> **Valves spawn order**: Read `{SCRATCHPAD}/verification_priority_queue.md` and spawn verifiers in descending EV order within each batch. Apply cluster-inheritance rules: when a cluster representative returns [POC-PASS], tag non-representatives with `[POC-PASS:BC-NNN-INHERITED]` and skip spawning per-instance verifiers where inheritance conditions hold (see `~/.valves/rules/verification-priority-queue.md` § Cluster Inheritance).

**Step 5.0: Compute verification scope**

Read `{SCRATCHPAD}/hypotheses.md` (first 100 lines ONLY -> hypothesis table). Count hypotheses per severity tier.

| Mode | Scope |
|------|-------|
| Light | ALL Medium+ (all sonnet) |
| Core | ALL Medium+ (opus for High/Chain, sonnet for Medium) |
| Thorough | ALL severities (opus for High/Chain, sonnet for Medium, sonnet for Low/Info) + fuzz variants |

**Step 5.0.1: Crash resume -> skip already-verified hypotheses**

Before spawning, scan `{SCRATCHPAD}/` for existing `verify_*.md` files. For each file, extract the hypothesis IDs it covers (from the `## Scope:` header or `### H-XX` sections). Remove those IDs from the verification queue. Only spawn verifiers for MISSING hypotheses.

**v1.7-PATCH11 manifest-based recovery**: If `manifest_phase5_batch_*.md` files exist from a prior interrupted run, the orchestrator reads them instead of doing the naive file scan above. For each manifest where Phase outcome ≠ COMPLETE:
1. Identify agents with Status ≠ DONE (missing verifiers).
2. Check if their expected `verify_*.md` output appeared on disk since the manifest was last written (crash recovery — agent finished but manifest wasn't updated).
3. Re-spawn ONLY the truly missing verifiers in the same batch structure.
4. Update the manifest rows on return.
This prevents duplicate verification work and preserves batch ordering.

**Step 5.0.2: Batched spawning (when total verifiers > 8)**

If total verifiers to spawn **<= 8**: spawn ALL in a single parallel message (standard behavior -> no batching needed).

If total verifiers to spawn **> 8**: split into severity-tier batches. Spawn each batch, await ALL agents in that batch, then spawn the next batch.

| Batch | Contains | Model | Max parallel agents |
|-------|----------|-------|---------------------|
| A | Chain hypotheses (CH-*) + High standalone | opus | all (typically 7-10) |
| B | Medium (first half, up to 6) | sonnet | 6 |
| C | Medium (second half) | sonnet | 6 |
| D | Low + Info (single agent covering ALL) | sonnet | 1 |

> **Batch sizing**: If a tier has <= 6 hypotheses, it fits in one batch. If > 6, split into sub-batches of <= 6. Chains + High are always in the same batch (both opus, rarely > 10 combined).

> **Between batches**: Do NOT read the `verify_*.md` files written by the completed batch. Only note the short return message from each agent. Detailed output lives on disk -> the orchestrator does not need it until Phase 5.5/6.

> **Batch D (Low/Info)**: Always a SINGLE agent that handles all Low + Info hypotheses via code trace. This is already the standard approach -> no change here.

**Step 5.0.3: Verifier output convention**

Each verifier writes its full output to `{SCRATCHPAD}/verify_{id}.md` (on disk). The agent return message to the orchestrator MUST be short:

```
Return: '{HYPOTHESIS_ID}: {VERDICT} | {evidence_tag} | {1-sentence justification}'
```

This keeps return messages to ~50 tokens per agent instead of the full verification output accumulating in orchestrator context.

**Step 5.0.4: Verifier hypothesis-killing pre-check directive (v1.7-PATCH7 — MANDATORY)**

When composing each verifier prompt (every batch, every severity), the orchestrator appends this directive after the standard verifier preamble and before the per-finding scope block:

> "Before writing any PoC, emit a § Hypothesis-killing pre-check sub-section in verify_{id}.md per `~/.valves/rules/phase5-poc-execution.md` § Hypothesis-killing pre-check. Answer Q1-Q5 (guard/invariant; state-precondition reachability; unenforced call-order dependence; expected-order survival; test-suite false comfort per v1.7-PATCH8) with `kills_hypothesis: YES/NO` per Q1-Q4 and `tests_imply_safety: YES/NO/PARTIAL/NO_TESTS` for Q5. Q1/Q2 may justify [POC-FAIL: GENUINE] without running a PoC IF AND ONLY IF the killing argument carries full Cleared-Proof Discipline fields (file:line + guard/invariant + reason + Proof Type). Q3-YES + Q4-NO re-classifies the finding as `class: sequence-violation` — the PoC tests the unexpected-order variant. Q5 is asymmetric: it never KILLS a hypothesis, only contextualizes 'tests pass' as evidence weight — when `tests_imply_safety: NO` (strict-setup / loose-production divergence) and Q1/Q2 don't kill, the verifier MUST NOT cite 'tests pass' as evidence of safety. Read `~/.valves/rules/valves-doctrine.md` § Kill-the-hypothesis mindset and § Heuristic Lenses → TEST-SKEPTIC once before starting."

This directive does NOT change the spawn topology, batch structure, model selection, or budget. It changes verifier mindset — the verifier runs the pre-check, records it in `verify_{id}.md`, and only then writes a PoC (or skips with proven REFUTED). The pre-check is independent of the Skeptic-Judge step (Phase 5.1) which runs after on HIGH/CRIT only — the two layers compose. Q5 (v1.7-PATCH8) is also independent of `[VS-TS-1]` test-skepticism findings produced by the Validation Sweep in Phase 4b iter 1: VS-TS surfaces test-coverage gaps as standalone findings; Q5 asks whether existing tests give false safety comfort for THIS finding's hypothesis. The two compose without overlap.

### Phase 5.1: Skeptic-Judge Verification (Thorough mode only, HIGH/CRIT)

> **Read templates from**: `~/.claude/prompts/{LANGUAGE}/phase5-verification-prompt.md` -> "Skeptic-Judge Verification" section

After ALL standard Phase 5 verifiers complete:
1. Identify all HIGH/CRIT findings with standard verdicts
2. For EACH, spawn a skeptic agent (sonnet) with INVERSION MANDATE
3. If skeptic AGREES -> final verdict = standard verdict (high confidence)
4. If skeptic DISAGREES -> spawn haiku judge ("prove it or lose it" -> stronger mechanical evidence wins)
5. Apply final verdict per the ruling table in the verification prompt

**Skip in Light and Core mode.**
**Thorough mode**: This step MUST execute for every HIGH and CRITICAL finding. "All PoCs passed so skeptic is unnecessary" is not a valid skip reason.

### Phase 5.2: Cross-Batch Consistency Check (Core/Thorough)

> **Skip in Light mode.**

After ALL verification batches complete (including Skeptic-Judge in Thorough mode), spawn a haiku agent to check for contradictions between verifier outputs:

```
Task(subagent_type="general-purpose", model="haiku", prompt="
You are the Cross-Batch Consistency Agent. Check for contradictions across verification batches.

Read ALL verify_*.md files in {SCRATCHPAD}/.

For EACH finding that was verified by multiple agents or referenced across batches:
1. Check: do any two verifiers reach OPPOSITE conclusions about the same finding?
2. Check: does any verifier's PoC contradict another verifier's assumptions?
3. Check: are there severity inconsistencies for findings with the same root cause?

Write to {SCRATCHPAD}/cross_batch_consistency.md:
| Finding | Verifier A | Verdict A | Verifier B | Verdict B | Contradiction? | Resolution |

If contradictions found: flag them for the report index agent to resolve (higher-evidence verdict wins).
If no contradictions: write 'No cross-batch contradictions detected.'

Return: 'DONE: {N} findings checked, {C} contradictions found'
")
```

### Phase 5.5: Post-Verification Finding Extraction

After ALL verifiers complete:
1. Read all `verify_*.md` files in the scratchpad
2. Extract any `[VER-NEW-*]` observations from "New Observations" sections
3. For each: check if already covered by an existing hypothesis
4. If NOT covered: create a new hypothesis and add to `hypotheses.md`
5. Assign severity using the standard matrix
6. These do NOT require re-verification

**Step 5.5.1: Verifier hypothesis-killing pre-check compliance scan (v1.7-PATCH9 — orchestrator inline, NO new agent, NO new artifact)**

After Phase 5 batches complete (and before Phase 5.6.1), the orchestrator scans each `verify_*.md` file for the mandatory § Hypothesis-killing pre-check section and its required Q1-Q5 structure per `~/.valves/rules/phase5-poc-execution.md` § Hypothesis-killing pre-check.

For each verify file:
- Check the file contains `## § Hypothesis-killing pre-check` heading.
- Check Q1, Q2, Q3, Q4 each have a `kills_hypothesis: YES` or `kills_hypothesis: NO` line.
- Check Q5 has a `tests_imply_safety: YES`, `NO`, `PARTIAL`, or `NO_TESTS` line.
- If ANY of the required structures is missing → log `VERIFIER_PRECHECK_MISSING verify_{id}.md missing={Q-list}` to `{SCRATCHPAD}/violations.md`. The orchestrator does NOT re-spawn the verifier and does NOT block (Phase 5.6 proceeds) — this is observability. The violation count surfaces in `seed_metrics.md` § Operational compliance (v1.7-PATCH9).

The scan is mechanical (`grep -c "kills_hypothesis"` per file, threshold 4; `grep -c "tests_imply_safety"`, threshold 1). No agent reasoning. No semantic check on whether the answers are actually correct — only that the structure exists. Quality of the answers remains a verifier property.

**Why this is precision-positive**: same rationale as Step 6 of Session B Behavioral Rules — the PATCH7+PATCH8 verifier hypothesis-killing pre-check is operational only if it actually appears in verify outputs. Without this scan, "Q1-Q5 influenced verifier verdict" was a hope. With it, non-compliance is countable across audits and the prompt directive can be tightened if the rate is high.

### Phase 5.6 (VALVES): Thesis v3 + Negative Results Promotion + Registry Promotion

Orchestrator inline work after Phase 5 verification and Phase 5.5 extraction complete. No new agent spawns.

**Step 5.6.1: Thesis v3 update**

Read `{SCRATCHPAD}/attack_thesis.md` (v2). For each path:
- Collect Phase 5 verdicts on supporting findings
- Apply v3 status rules per `~/.valves/rules/attack-thesis.md` § v3 Generation
- Update Status (CONFIRMED/REFUTED/CANDIDATE) and Confidence

Write updated attack_thesis.md with v2 preserved as an appendix. This v3 thesis is the "Residual Risk Summary" section of the final report.

**Step 5.6.2: Cluster inheritance application**

Read `{SCRATCHPAD}/verification_inheritance.md`. For each cluster where the representative verdict is [POC-PASS], tag non-representative instances with `[POC-PASS:BC-NNN-INHERITED]` in findings_inventory.md. Failures do not inherit.

**Step 5.6.3: Negative results capture**

**Step 5.6.3.a -> Stub-ensure (soft-required per Rule 15)**: Before any append, verify `{SCRATCHPAD}/audit_negative_results.md` exists. If it does NOT, create a minimal stub:
```markdown
# Audit Negative Results -> {project}
> Per-audit "considered and cleared" memory. See `~/.valves/rules/negative-results.md`.
> Stub created at Phase 5.6.3 because no earlier writer (depth iter 1, chain REFUTED, verifier [POC-FAIL], thesis-drop) produced a file. Appends below are the only entries.

## Verification [POC-FAIL] Results
_(populated below)_

## Chain Analysis REFUTED Verdicts
_(populated below)_

## Thesis Paths Dropped
_(populated below)_
```
This stub satisfies the Phase 5.6 soft gate and guarantees `~/.valves/rules/negative-results.md` § Promotion Protocol (read by Step 5.6.4) has a well-formed input.

**Step 5.6.3.b -> Verifier-driven appends**:

For each verifier with verdict [POC-FAIL]:
- Classify as GENUINE or SETUP_ERROR (use finding output + variant exploration rules)
- If GENUINE -> append to `{SCRATCHPAD}/audit_negative_results.md` under "Verification [POC-FAIL] Results"

For each chain in `chain_hypotheses.md` with verdict REFUTED -> append to audit_negative_results.md under "Chain Analysis REFUTED Verdicts".

For each path in `attack_thesis.md` v3 with Status REFUTED -> append to audit_negative_results.md under "Thesis Paths Dropped".

> **Coherence note**: `audit_negative_results.md` has four writer paths: (1) Phase 4b depth iter 1 "considered and cleared" collection, (2) Phase 4c REFUTED chain append, (3) this step's [POC-FAIL] / chain-REFUTED / thesis-drop appends, and (4) the stub-ensure above. All four paths append to the same file under the three canonical section headers. Step 5.6.4 (promotion) reads the aggregated file.

**Step 5.6.4-pre (VALVES v1.4): Bug-Class FP Calibration Update**

Orchestrator inline. For each cluster BC-NNN in `root_cause_clusters.md`, aggregate this audit's verifier verdicts:

```
For each finding F with cluster tag BC-NNN:
  Surfaced[BC-NNN] += 1
  If verdict in {CONFIRMED, [POC-PASS], [POC-PASS:BC-NNN-INHERITED]}:
    Confirmed[BC-NNN] += 1
  elif verdict in {FALSE_POSITIVE, [POC-FAIL:GENUINE]}:
    FalsePositive[BC-NNN] += 1

Update (or append) one row per touched BC in ~/.valves/state/bc_class_calibration.md.
Snapshot the pre-update file to ~/.valves/state/bc_class_calibration_snapshots/{YYYY-MM-DD}_{project}.md.
```

See `~/.valves/state/bc_class_calibration.md` § Update Protocol. No severity changes applied here -> this only updates cross-audit priors.

**Step 5.6.4: Promotion to global state**

Following `~/.valves/rules/negative-results.md` § Promotion Protocol:
- Scan `audit_negative_results.md`
- For each entry meeting promotion criteria (HIGH confidence, generalizable, fragility documented) -> append to `~/.valves/state/negative_results.md`

Following `~/.valves/rules/bug-class-registry.md` § New Class Promotion Protocol:
- For each BC-NEW cluster with >=1 [POC-PASS] finding -> promote to `~/.valves/state/bug_class_registry.md` as new BC-NNN

**Step 5.6.5: Cluster -> Report Mapping**

After `attack_thesis.md` v3 is written and cluster inheritance applied, the orchestrator MUST spawn the **Cluster Instance Map Agent** to generate `{scratchpad}/cluster_instance_map.md`. This artifact is the input for Phase 6 report ID assignment.

**Ownership (v1.7-PATCH10.2 — canonicalized)**: `cluster_instance_map.md` is **AGENT-OWNED** per `~/.valves/rules/artifact-ownership.md` § Control table. The orchestrator MUST NOT synthesize this artifact directly even for small cluster counts. The pre-write gate (Phase 0.9 § B) will refuse an orchestrator-inline write attempt; row 46 stays PENDING; Phase 5.99 PRE-REPORT GATE will block the report pipeline. The legitimate path is the agent spawn below.

**Spawn**:

```
Task(subagent_type="general-purpose", model="sonnet" if cluster_count > 15 else "haiku", prompt="
You are the Cluster Instance Map Agent (Phase 5.6.5).

## Your Inputs
- {SCRATCHPAD}/root_cause_clusters.md (clusters with their instances)
- {SCRATCHPAD}/verify_*.md (Phase 5 verifier verdicts)
- {SCRATCHPAD}/verification_inheritance.md (cluster inheritance map)
- {SCRATCHPAD}/attack_thesis.md (v3 — final residual-risk paths)
- {SCRATCHPAD}/strongest_exploit_cards.md (for SEC card winner preservation)
- ~/.valves/rules/bug-class-registry.md § Subgroup Split Rules
- ~/.valves/rules/strongest-exploit-preservation.md § Anti-Absorption Axes

## Your Task
For each cluster in root_cause_clusters.md:
1. Identify subgroups by splitting on material differences (access control, victim, severity after modifiers, exploit path, fix pattern). Apply the Anti-Absorption Axes — when an axis differs, split into a new subgroup (BC-NNN.A, BC-NNN.B, ...).
2. Mark inheritance eligibility per subgroup (which subgroup's verifier outcome inherits to which other subgroups in the same cluster).
3. Assign a report-grouping decision per subgroup: SINGLE report ID (one row in the report) OR SEPARATE report IDs (multi-row table).
4. Preserve every Strongest Exploit Card (SEC-N) winner as its own subgroup — card winners are NOT eligible for absorption.

## Output (single file)
Write {SCRATCHPAD}/cluster_instance_map.md with sections:
- ## Cluster -> Subgroup -> Report-ID Assignments (table per cluster)
- ## Subgroup Split Rules Applied (which axis triggered each split)
- ## Inheritance Map (subgroup A's verdict inherits to subgroups B, C, ...)
- ## Card Winner Preservation (each SEC-N card winner is its own row)

You MUST NOT write any other file. You MUST NOT spawn nested Claude / claude --print subprocesses (per ~/.valves/rules/valves-doctrine.md § Agent tool discipline). Your post-spawn integrity check will scan your tool trace.

Return: 'DONE: {N} clusters, {M} subgroups, {K} report-IDs, {C} SEC card winners preserved'
")
```

**Why a dedicated agent (v1.7-PATCH10.2)**: previously this step said "inline OR agent" depending on cluster count. PATCH10 § B (pre-write gate) refuses orchestrator-inline writes of AGENT-OWNED artifacts; the dual-path option contradicted the manifest. Canonical decision: AGENT-OWNED only, model selection (sonnet/haiku) varies with cluster count but the agent spawn is mandatory.

**Hard gate**: Phase 6 cannot begin until `attack_thesis.md` v3, `verification_inheritance.md`, AND `cluster_instance_map.md` all exist. Phase 5.99 PRE-REPORT GATE additionally verifies the writer of `cluster_instance_map.md` matches the manifest (Cluster Instance Map Agent); orchestrator-inline self-synthesis triggers `ILLEGAL_WRITER_ORCHESTRATOR_ARTIFACT_BY_AGENT` per Phase 0.9 § A.

### Phase 5.99: PRE-REPORT GATE (v1.7-PATCH10 — orchestrator inline, MANDATORY in Thorough)

> **Purpose**: refuse to start the report pipeline if the upstream pipeline is not in a valid terminal state. This is the highest-leverage anti-fake-Thorough check.

> **Mode policy**: HARD GATE in Thorough (refuses to advance to Phase 6a). SOFT GATE in Core (logs violations, allows advance with degraded labeling). NOT_APPLICABLE in Light (uses simplified report flow).

**Mechanical scan (orchestrator inline, no agent spawn)**:

```
1. Load mandatory_step_checklist.md.
2. For each row up to row 46 (Cluster -> Report Mapping):
     - if row.status NOT IN {COMPLETE, FAILED_WITH_FALLBACK, NOT_APPLICABLE}:
         → blocking_rows.append((row_num, row.step, row.status, "non-terminal"))
     - if row.status == COMPLETE:
         → if row.evidence_artifact missing on disk:
             → blocking_rows.append((row_num, row.step, "synthetic_completion"))
         → if row.evidence_artifact has illegal writer per
            ~/.valves/rules/artifact-ownership.md § Control table
            (cross-check with violations.md ILLEGAL_WRITER_* entries):
             → blocking_rows.append((row_num, row.step, "illegal_writer"))
     - if row.status == FAILED_WITH_FALLBACK:
         → if row.fallback_artifact missing on disk:
             → blocking_rows.append((row_num, row.step, "fallback_missing"))
     - if row.status == NOT_APPLICABLE:
         → if reason in {"", "skipped", "n/a", null}:
             → blocking_rows.append((row_num, row.step, "weak_NA_reason"))
3. Cross-check Phase 5 verification specifically (Thorough mode):
     - Mode-policy verification scope (per ~/.valves/rules/verification-priority-queue.md § Mode policy):
         Light: ALL Medium+ verified
         Core: ALL Medium+ verified
         Thorough: ALL severities + fuzz variants verified
     - For each finding in findings_inventory.md within mode-policy scope:
         → expected verify_*.md file must exist on disk (or [POC-PASS:BC-NNN-INHERITED] inheritance via verification_inheritance.md)
         → if missing: blocking_rows.append(("verify", finding_id, "verify_artifact_missing"))
4. Cross-check the COMPLETE_A boundary (Thorough only):
     - if MODE == THOROUGH:
         → session_checkpoint.md must exist with status=COMPLETE_A or status=COMPLETE_B
         → session_a_to_b_handoff.md must exist
         → cross_session_consensus.md must exist
         → if any missing: blocking_rows.append(("session_boundary", artifact, "missing"))
5. If blocking_rows is non-empty:
     - Emit terminal banner verbatim (see below)
     - Refuse Phase 6a spawn
     - Trigger Recovery Loop per ~/.valves/rules/thorough-strict-mode.md § Recovery Loop
     - If recovery exhausted (3 iterations): final embargo blocks finalization (see Phase 6f)
6. If blocking_rows is empty:
     - Log PRE_REPORT_GATE_PASSED to pipeline_trace.md
     - Proceed to Phase 6a Report Index Agent
```

**PRE_REPORT_GATE_BLOCKED banner** (verbatim):

```
====================================================================
PRE-REPORT GATE BLOCKED — REPORT PIPELINE REFUSED
====================================================================

The Thorough pipeline cannot generate a report. The upstream pipeline
is NOT in a valid terminal state. {N} blocking item(s):

  {list each blocking row/artifact:
   - row#:    Phase X step name | status: STATUS | reason}

The orchestrator MUST NOT write:
  - report_index.md
  - report_critical_high.md
  - report_medium.md
  - report_low_info.md
  - AUDIT_REPORT.md
  - report_review.md
  - strongest_exploit_final_check.md

until every blocking item is resolved.

Recovery: spawn the producing agent for each blocking row OR mark the
row FAILED_WITH_FALLBACK with a non-trivial reason if recovery fails.
The orchestrator MUST NOT mark rows COMPLETE based on synthesized
artifacts — that path is detected by the post-spawn integrity check
and the row drift detection (Phase 0.9 § A + § D).

If recovery exhausted (3 attempts): the run will be marked INCOMPLETE
THOROUGH or INVALID FINALIZATION at the Phase 6f embargo. The audit
deliverable (if any artifacts were generated) will be labeled
exploratory / partial — NOT a valid Thorough deliverable.
====================================================================
```

**Why this is the highest-leverage check**: the Snuggle run failed exactly here. Rows 16-73 were PENDING but the orchestrator generated `report_critical_high.md`, `report_medium.md`, `report_low_info.md`, `cluster_instance_map.md`, `chain_hypotheses.md` directly without spawning the producer agents. The pre-report gate would have BLOCKED report generation, forcing the pipeline to either properly run those phases or mark the run INCOMPLETE.

**This gate must run synchronously and inline — there is no agent that can be skipped or fail without triggering the block.**

### Report Naming Convention (v1.7-PATCH11 — session-aware, prevents contamination)

In Thorough mode with Session A/B split:
- **Session A** does NOT produce a report. If any report artifact is found in `.audit_session_a/`, it is a recovery artifact from a prior failed run and MUST NOT be read by Session B.
- **Session B** writes to: `{PROJECT_ROOT}/AUDIT_REPORT.md` (the final deliverable)
- If a prior `AUDIT_REPORT.md` exists from a failed/stale single-session run → the orchestrator renames it to `AUDIT_REPORT.STALE_SESSION_A.md` before Session B's Phase 6 begins. Session B never reads or references it.

In Core/Light mode (single session): report is written directly to `{PROJECT_ROOT}/AUDIT_REPORT.md` as before (no session split, no rename).

**Cross-session consensus interaction**: The consensus step (Phase 5.6.1+) reads structured fields from `.audit_session_a/findings_inventory.md` and `.audit_session_a/confidence_scores.md`. It does NOT read any report artifact from Session A. The consensus feeds into Session B's report generation — it does not produce a separate report.

### Phase 6: Report Generation

> **Valves report changes**:
> - Report IDs map to CLUSTER-SUBGROUPS from `cluster_instance_map.md`, not directly to hypotheses. A homogeneous cluster with 5 instances -> 1 report finding with a multi-location table. A cluster whose instances differ materially (access control, victim, severity, exploit path, or fix) splits into subgroups (BC-NNN.A, BC-NNN.B, ...), each with its own report ID.
> - The v3 `attack_thesis.md` is included verbatim as the "Residual Risk Summary" section (including any PRIOR_NEGATIVE paths with their citations).
> - Cluster-inherited `[POC-PASS:BC-NNN-INHERITED]` tags are presented as `[VERIFIED (cluster inheritance)]` in the client-facing report.
> - The Index Agent's STEP 1.5 (Root-Cause Consolidation) is REPLACED by: "read `cluster_instance_map.md`; emit one report ID per subgroup."

> **Light mode override**: Do NOT read `~/.claude/rules/phase6-report-prompts.md`. Instead, spawn 2 agents: (1) a single sonnet writer handling cluster-based ID assignment and all severity tiers inline; (2) a haiku assembler. No separate index agent or tier-split writers. Include the Light mode disclaimer per override #9.

> **Core/Thorough**: Read `~/.claude/rules/phase6-report-prompts.md` and follow the full 5-agent pipeline (Index -> 3 Tier Writers -> Assembler) with Valves cluster-to-report-ID mapping.

**v1.7-PATCH11 report recovery**: If `manifest_phase6.md` exists from a prior interrupted run, the orchestrator resumes the report pipeline at the first incomplete step:
1. If Index Agent (row 1) Status ≠ DONE → check if `report_index.md` exists and is valid on disk. If yes, mark DONE. If no, re-spawn index agent.
2. If any Tier Writer (rows 2-4) Status ≠ DONE → check if their output files exist on disk. Re-spawn only missing tier writers (the 3 writers are independent — a completed tier writer's output persists even if others failed).
3. If Assembler (row 5) Status ≠ DONE → check if `AUDIT_REPORT.md` exists on disk. If no, re-spawn assembler.
4. Sequential dependency: Assembler requires all tier writers DONE. Tier writers require Index DONE. Resume respects this ordering.

### Phase 6d (VALVES v1.4): Report Quality Self-Review

After the Assembler writes `AUDIT_REPORT.md`, spawn ONE haiku agent to self-review the finished report.

```
Task(subagent_type="general-purpose", model="haiku", prompt="
You are the Report Quality Self-Review Agent.

Read {PROJECT_ROOT}/AUDIT_REPORT.md in full. Run the 6 checks in ~/.valves/rules/report-quality-review.md:
1. Critical/High specificity (concrete victim + attacker + impact)
2. Code snippet presence
3. Recommendation actionability
4. Severity-description coherence
5. Executive summary -> finding list consistency
6. Internal contradictions

For issues with trivial safe fixes (paste existing code snippet from verify_*.md, paste existing fix diff), apply inline to AUDIT_REPORT.md. For everything else (Description rewrites, Severity changes, Exec summary rewrites), FLAG ONLY.

Write {SCRATCHPAD}/report_review.md with the full report.

Return: 'DONE: {N} issues found, {M} auto-fixed inline, {K} flagged for human review'
")
```

If K > 0 flagged-only issues, append a "Report Quality Notes" section to `AUDIT_REPORT.md` that lists the flagged items (see `~/.valves/rules/report-quality-review.md` § Integration With Phase 6 Flow).

### Phase 6d.5 (VALVES v1.7-PATCH5 PATCH 1): Final Strongest-Exploit Sanity Check

Orchestrator inline. Runs AFTER Phase 6d (Report Quality Self-Review) and BEFORE Phase 6e (Pipeline Trace Finalization). Mechanical, no agent spawn. Output: `{SCRATCHPAD}/strongest_exploit_final_check.md`.

**Purpose**: Valves preserves strongest-exploit cards early (Phase 4a.1.5 Strongest Exploit Gate, with anti-overcompression rule). But across the full pipeline (clustering, depth iter 2-3, cross-session consensus, verification, cluster-inheritance, report-ID assignment), a stronger parent exploit can still be displaced by a cleaner but weaker child issue. This sanity check is the final pass that asks: per important surface, is the strongest finding in the FINAL report still the strongest issue Valves ever surfaced there?

**Inputs**:
- `{SCRATCHPAD}/strongest_exploit_cards.md` (Phase 4a.1.5 commitment — SEC-1..SEC-N cards with parent exploit per surface)
- `{SCRATCHPAD}/system_breakpoints.md` (BP-NN families — IBC and others)
- `{SCRATCHPAD}/attack_thesis.md` v3 (final attack paths with status CONFIRMED/CANDIDATE/REFUTED)
- `{SCRATCHPAD}/findings_inventory.md` (final findings with verdicts)
- `{SCRATCHPAD}/cluster_instance_map.md` (cluster -> subgroup -> report-ID mapping)
- `{PROJECT_ROOT}/AUDIT_REPORT.md` (after Phase 6d auto-fixes)

**Algorithm (mechanical, deterministic)**:

```
# For each "important surface" (= a SEC-N card winner OR a BP-NN breakpoint OR an
# attack_thesis.md v3 path with CONFIRMED status):
for surface in (strongest_exploit_cards.SEC + system_breakpoints.BP + attack_thesis_v3.CONFIRMED_paths):

    # Identify the strongest exploit Valves EVER surfaced on this surface.
    # 'Strongest' is ranked by:
    #   1. severity (Critical > High > Medium > Low)
    #   2. eligibility class for SEC cards (E1-custody > E2-recovery-severance > E3-orphan > E4-lock > E5-pointer > E6-reachability > E7-floor)
    #   3. evidence weight (POC-PASS > POC-PASS-INHERITED > CODE-TRACE > INFER)
    earliest_strongest = max_by_strength(
        SEC cards on this surface,
        depth/scanner findings on this surface (any phase),
        chain hypotheses on this surface
    )

    # Identify the strongest finding that SURVIVED to the final report on this surface.
    final_strongest = max_by_strength(
        findings_inventory.md entries WHERE final-status in {CONFIRMED, [POC-PASS], [POC-PASS:BC-NNN-INHERITED]}
            AND location matches this surface
    )

    # Comparison
    if earliest_strongest is None:
        continue  # surface had no exploit ever (legitimate clean surface)
    if final_strongest is None:
        # Surface had a strong earlier exploit but NO survivor in final report
        emit_warning(
            type="STRONGEST_DROPPED_BEFORE_REPORT",
            surface=surface.id,
            earliest_strongest=earliest_strongest,
            reason="all earlier exploit candidates ended REFUTED / [POC-FAIL: GENUINE] / cleared with valid proof"
        )
        # NOTE: this is informational. A correctly-cleared surface is allowed to disappear.
        continue
    if final_strongest.strength_rank < earliest_strongest.strength_rank:
        # Final report keeps a WEAKER finding than what we once had
        emit_warning(
            type="STRONGEST_DISPLACED_BY_WEAKER",
            surface=surface.id,
            earliest_strongest=earliest_strongest,
            final_strongest=final_strongest,
            displacement_evidence={
                cluster_decision: cluster_instance_map.md trace for the surface,
                cross_session_consensus: relevant rows from cross_session_consensus.md,
                verification_inheritance: relevant rows from verification_inheritance.md
            }
        )
    else:
        # Final report kept the strongest known exploit on this surface.
        emit_ok(surface=surface.id, final=final_strongest)
```

**Output (`strongest_exploit_final_check.md`)** — actionable schema (v1.7-PATCH6 PATCH 2):

```markdown
# Strongest-Exploit Final Sanity Check (v1.7-PATCH5 PATCH 1; v1.7-PATCH6 PATCH 2 actionable schema)

## Summary
- Surfaces audited: {N}
- OK (strongest preserved): {ok}
- WARNING STRONGEST_DROPPED_BEFORE_REPORT: {dropped}
- WARNING STRONGEST_DISPLACED_BY_WEAKER: {displaced}
- By mismatch type: SEVERITY_DOWNGRADE {sd} / SUBGROUP_COLLAPSE {sc} / INHERITANCE_SHADOWING {is} / THESIS_DISPLACEMENT {td} / REPORT_ID_CONSOLIDATION {rc} / SEQUENCE_DISPLACEMENT {qd} / STATE_TRANSITION_DISPLACEMENT {std} / ASYMMETRY_DISPLACEMENT {ad} / OTHER {o}

## Per-surface table
| Surface ID | Source (SEC-N / BP-NN / P-N) | Affected location | Earliest strongest (severity / class / evidence) | Final strongest in report (severity / evidence / report-ID) | Verdict | Mismatch type | Why_lost (one-line, structured) | Recommendation | Competing_finding | Competing_subgroup | Competing_cluster |
|---|---|---|---|---|---|---|---|---|---|---|---|
| SEC-2 | strongest_exploit_cards | Vault.sol:142 setStrategy | High / E1-custody / [BOUNDARY] | Medium / [CODE-TRACE] / R-04 | STRONGEST_DISPLACED_BY_WEAKER | SUBGROUP_COLLAPSE | cluster_instance_map.md row 14 absorbed SEC-2 parent into BC-014.A subgroup with 4 child symptoms; severity collapsed to subgroup median | CONSIDER_SPLIT_SUBGROUP | F-44 | BC-014.A | BC-014 |
| BP-03 | system_breakpoints (IBC) | Vault.sol invariant totalShares <= totalDeposits | High / first-loss-mismatch / [TRACE] | High / [POC-PASS] / R-09 | OK | -- | -- | REVIEW_ONLY | F-12 | BC-014.B | BC-014 |
| P-1 | attack_thesis v3 CONFIRMED | LendingPool.sol:88 emergencyExit | Critical / E2-recovery-severance / [POC-PASS] | (no survivor) | STRONGEST_DROPPED_BEFORE_REPORT | THESIS_DISPLACEMENT | Phase 5.6.2 cluster inheritance silenced [F-67] when representative [F-12] returned [POC-FAIL: GENUINE]; thesis-aligned [F-67] never re-verified | CONSIDER_RESTORE_PARENT | -- | -- | BC-007 |
| ... |

## Field definitions (v1.7-PATCH6 PATCH 2)

**Mismatch type** — exactly ONE of:
- `SEVERITY_DOWNGRADE` — final finding has same locus + same root cause as the strongest known, but severity tier dropped (Critical -> Medium, High -> Low). Likely cause: cross-session re-scoring discounted the worst-case path, OR Phase 6d quality review changed severity.
- `SUBGROUP_COLLAPSE` — Phase 5.6.5 cluster_instance_map.md absorbed the strongest parent into a subgroup that emits a single report-ID; the subgroup's severity reflects the median, not the parent. Likely cause: subgroup split rules (`~/.valves/rules/bug-class-registry.md` § Subgroup Split Rules) didn't trigger because the parent and children shared too many axes.
- `INHERITANCE_SHADOWING` — Phase 5 cluster inheritance (verification_priority_queue.md § Cluster Inheritance) marked the parent as `[POC-PASS:BC-NNN-INHERITED]` but the inheritance representative was the WEAKER child; the parent never got its own verifier. Likely cause: representative-selection picked a child by EV ranking (cheap PoC) instead of by exploit-strength.
- `THESIS_DISPLACEMENT` — attack_thesis.md v2->v3 transition demoted a CONFIRMED path to REFUTED on ambiguous evidence; the parent exploit was thesis-aligned but lost its supporting evidence chain.
- `REPORT_ID_CONSOLIDATION` — Phase 6 Index Agent merged what should have been 2 distinct report-IDs into 1 because cluster_instance_map.md said SINGLE; the child ended up as the report-ID title.
- `SEQUENCE_DISPLACEMENT` (v1.7-PATCH7) — the strongest known exploit on this surface was a sequence / call-order-dependent parent (E11 SEQUENCE canonical, AB-7 seed-promoted finding, BP-NN OrderingViolation, or a finding whose verifier classified it `class: sequence-violation` per `~/.valves/rules/phase5-poc-execution.md` § Hypothesis-killing pre-check Q3-YES + Q4-NO), but the final report keeps a narrower child symptom (e.g., a single-function input-validation gap inside the sequence, or a generic asymmetry framing) instead of the call-order parent. Likely cause: clustering / inheritance / report-ID assignment treated the sequence-violation finding as a sibling of single-function findings sharing the same surface, and the cheaper-to-explain child became the cluster representative.
- `STATE_TRANSITION_DISPLACEMENT` (v1.7-PATCH8) — the strongest known exploit on this surface was a state-machine root-cause parent (an invalid / unhandled state transition: e.g., contract enters SETTLED state without debt-mirror updated; position transitions ACTIVE→LIQUIDATED→ACTIVE; transition fires without predecessor-state validation), but the final report keeps a narrower manifestation (e.g., a single missing assert / require, or a downstream symptom of the broken transition). The lens tag `STATE-TRANSITION` from `canonical_seed_map.md` § Heuristic Lens column may identify the parent. Distinct from SEQUENCE_DISPLACEMENT: SEQUENCE is about caller-controlled call-order; STATE_TRANSITION is about protocol-internal lifecycle / state-machine completeness. Likely cause: clustering treated the state-machine root cause as a sibling of single-function symptoms; the cheaper child became the representative.
- `ASYMMETRY_DISPLACEMENT` (v1.7-PATCH8) — the strongest known exploit on this surface was an asymmetry-rooted parent (E1 SYMMETRIC canonical or `[VS-AS-1]` correctness-winner finding where two sibling paths — deposit/withdraw, claim/emergency-claim, normal/skipped — diverge in a non-direction-justified way), but the final report keeps a downstream symptom of the asymmetry (e.g., "withdraw lacks pause check" instead of the broader symmetry-violation framing that includes both sides). Lens tag `SYMMETRY` from `canonical_seed_map.md` § Heuristic Lens column may identify the parent. Likely cause: clustering kept only the side that is broken in isolation; the missing-half view (the other sibling path) was not preserved.
- `OTHER` — anything else (must specify in why_lost field).

**Mismatch-type precedence (v1.7-PATCH9)**: when a single surface's displacement fits multiple structural displacement types, the orchestrator MUST pick exactly ONE per the precedence below. This mirrors the `~/.valves/rules/canonical-seed-map.md` § Heuristic Lens precedence and prevents the same surface from being labeled inconsistently across audits.

Precedence (strongest parent first; pick the first that applies):
1. **STATE_TRANSITION_DISPLACEMENT** — wins when the displaced parent's framing is state-machine completeness (the lens tag on the canonical or thesis path that surfaced the parent was `STATE-TRANSITION`, OR the parent's `Why_lost` cites mirror-accounting drift / missing transition validator / unreachable-state-now-reachable).
2. **SEQUENCE_DISPLACEMENT** — wins when STATE_TRANSITION_DISPLACEMENT does NOT fit AND the displaced parent's framing is caller-controlled call-order (lens `SEQUENCE`, `class: sequence-violation` in the displaced finding's verifier output, or BP-NN OrderingViolation as the surface source).
3. **ASYMMETRY_DISPLACEMENT** — wins when neither STATE_TRANSITION nor SEQUENCE fits AND the displaced parent's framing is asymmetric sibling paths (lens `SYMMETRY`, E1 SYMMETRIC family, or `[VS-AS-1]` correctness-winner as the source).
4. **SEVERITY_DOWNGRADE / SUBGROUP_COLLAPSE / INHERITANCE_SHADOWING / THESIS_DISPLACEMENT / REPORT_ID_CONSOLIDATION** — these are MECHANICAL displacement modes (cluster decisions / verification / report assembly). When a surface's displacement is BOTH structural (1-3 above) AND mechanical (4), prefer the structural type — it surfaces the deeper root-cause framing that the mechanical step compressed away. The mechanical type goes into the `why_lost` field as supporting evidence.
5. **OTHER** — last resort. Why_lost must specify.

When the displacement is purely mechanical (no structural parent framing exists for this surface — e.g., a Critical finding got SEVERITY_DOWNGRADE'd to Medium during cross-session re-scoring with no underlying state-transition / sequence / asymmetry interpretation), use the mechanical type directly.

The `Recommendation` enum follows the same precedence — when STATE_TRANSITION_DISPLACEMENT is chosen, the recommendation is `CONSIDER_RESTORE_STATE_TRANSITION_PARENT`, and so on. Two orchestrator runs on identical inputs MUST yield the same Mismatch type + Recommendation pair.

**Why_lost** — one-line structured citation pointing to the artifact that caused the displacement. Format: `{artifact}:{row} {one-clause reason}`. Examples:
- `cluster_instance_map.md:14 BC-014.A absorbed SEC-2 parent + 4 children`
- `cross_session_consensus.md:F-67 Session B re-scoring downgraded composite from 0.78 to 0.52`
- `verification_inheritance.md:BC-007 representative F-12 returned [POC-FAIL: GENUINE]; non-rep F-67 inherited but is the parent of the surface`
- `attack_thesis.md:P-1 v3 transition: thesis path moved CONFIRMED -> REFUTED based on F-12 [POC-FAIL]`

**Recommendation** — exactly ONE of:
- `REVIEW_ONLY` — verdict is OK; no action needed beyond standard review (default for OK rows).
- `CONSIDER_RESTORE_PARENT` — restore the dropped parent exploit as a distinct report-ID. Use when STRONGEST_DROPPED_BEFORE_REPORT and the parent had POC evidence at any earlier phase.
- `CONSIDER_SPLIT_SUBGROUP` — split the subgroup that absorbed the parent. Use when SUBGROUP_COLLAPSE and the parent's exploit path is materially different from the subgroup's other members.
- `CONSIDER_REWEIGHT_SEVERITY` — re-examine the severity tier. Use when SEVERITY_DOWNGRADE and the worst-case path is still reachable in the final code.
- `CONSIDER_RESELECT_INHERITANCE_REP` — the cluster's inheritance representative should be the parent, not the cheapest-to-verify child. Use for INHERITANCE_SHADOWING. Recommendation explicitly says: re-promote the parent as the representative and re-run Phase 5 verifier on it.
- `CONSIDER_RESTORE_THESIS_PATH` — re-evaluate the v2->v3 thesis transition. Use for THESIS_DISPLACEMENT.
- `CONSIDER_RESTORE_SEQUENCE_PARENT` (v1.7-PATCH7) — restore the call-order / sequence parent as a distinct report-ID. Use for SEQUENCE_DISPLACEMENT. The reviewer action is: re-promote the sequence-violation finding (or AB-7 / E11 canonical) as the cluster representative; emit its own report-ID with the unenforced order assumption explicit in the Description; the narrower child stays as a sibling row OR a separate report-ID if its fix differs (per `~/.valves/rules/strongest-exploit-preservation.md` § Anti-Absorption Axes).
- `CONSIDER_RESTORE_STATE_TRANSITION_PARENT` (v1.7-PATCH8) — restore the state-machine root-cause parent as a distinct report-ID. Use for STATE_TRANSITION_DISPLACEMENT. The reviewer action is: re-promote the invalid-transition finding as the cluster representative; emit a report-ID describing the invalid transition itself (e.g., "Settlement completes without debt-mirror update"), with the narrower manifestations listed as instances; the fix should target the missing transition validator OR the broken state-machine completeness, not just the downstream symptom.
- `CONSIDER_RESTORE_ASYMMETRY_PARENT` (v1.7-PATCH8) — restore the asymmetry-rooted parent as a distinct report-ID. Use for ASYMMETRY_DISPLACEMENT. The reviewer action is: re-frame the finding as a symmetry-violation between two sibling paths (e.g., "deposit pause check missing on withdraw" → "deposit/withdraw pause asymmetry"), so the report's Description explicitly names BOTH paths and the divergent aspect; the recommendation cites the missing-half view (the side whose check / accounting / event was missing) so the fix restores symmetry rather than only patching one side.
- `OTHER` — narrative reasoning required (must specify in a follow-up note).

**Competing_finding / Competing_subgroup / Competing_cluster** — IDs of the surviving final finding that displaced the strongest. Useful for reviewers who want to compare the two side-by-side.

## Per-warning evidence block (one block per WARNING row above; OK rows omit this section)

```markdown
### Warning W-1 — STRONGEST_DISPLACED_BY_WEAKER on SEC-2

- Surface: Vault.sol:142 setStrategy
- Earliest strongest known:
    - card: SEC-2 (E1-custody, severity High floor)
    - first surfaced at: Phase 4a.1.5 Strongest Exploit Gate
    - evidence at first surface: [BOUNDARY] + [TRACE] from Validation Sweep Agent
- Final survivor:
    - finding: F-44 (Medium, [CODE-TRACE]-only after Session B re-scoring)
    - report-ID: R-04
    - subgroup: BC-014.A
- Mismatch type: SUBGROUP_COLLAPSE
- Why_lost (artifact citations):
    - cluster_instance_map.md:14 — SEC-2 parent + 4 child symptoms collapsed into BC-014.A; subgroup-split rule did not trigger because all members shared access-control + victim axes
    - cross_session_consensus.md:F-44 — Session B re-scoring downgraded F-44 composite from 0.81 to 0.55 (no impact on parent)
- Recommendation: CONSIDER_SPLIT_SUBGROUP
- Specific suggested action: open cluster_instance_map.md, manually split BC-014.A into BC-014.A (parent SEC-2 only) and BC-014.A1 (4 child symptoms); emit R-04 for the parent and R-04.1 for the subgroup of children. The Phase 6 Index Agent re-run can pick this up if cluster_instance_map.md is updated before report regeneration.
- Reviewer effort estimate: low (single subgroup split; no new evidence required).
```

These recommendations are ADVISORY. The orchestrator does NOT silently rewrite AUDIT_REPORT.md. The decision to restore a stronger parent exploit is a human review act after this sanity check surfaces it.
```

**Rules**:

- **Sanity check, NOT a synthesis phase**: this step does NOT generate new findings, does NOT modify findings_inventory.md, does NOT rewrite AUDIT_REPORT.md beyond appending a Report Quality Note (below) when warnings exist.
- **Surfacing, not auto-fixing**: warnings are written to `strongest_exploit_final_check.md` and surfaced to AUDIT_REPORT.md as a `## Report Quality Notes (v1.7-PATCH5)` appendix entry IF AND ONLY IF warnings exist. Auto-fix is forbidden — preserving a stronger parent exploit is a human review decision because it may require restructuring the cluster -> subgroup -> report-ID mapping.
- **Mechanical**: surface identification, strength ranking, comparison are all deterministic. No agent reasoning. Strength rank precedence is fixed (severity > class > evidence).
- **Strongest Exploit Preservation invariant honored**: this check is the final enforcement of the "card winner cannot be silently absorbed" rule from `~/.valves/rules/strongest-exploit-preservation.md` § Hard Rule. Earlier phases enforce locally; Phase 6d.5 enforces globally before the report ships.
- **Soft gate**: missing inputs (e.g., strongest_exploit_cards.md not produced in Light) → write `strongest_exploit_final_check.md` with `## Source: SKIPPED — strongest_exploit_cards.md not produced (Light mode)` and proceed. Pipeline does not block.

**Why this improves final exploit quality (and does not increase FP)**:

- It does not generate findings; it surfaces displacement decisions for human review. The bar for a finding being CONFIRMED in AUDIT_REPORT.md is unchanged (full Phase 4 + Phase 5 evidence pipeline still applies).
- Mechanical comparison: warnings are deterministic, inspectable, falsifiable. A reviewer can re-run the check and verify the displacement.
- The advisory `## Report Quality Notes` entry surfaces the warning to the report reader without rewriting findings, so the reviewer chooses whether to escalate.

### Phase 6e (VALVES v1.4): Pipeline Trace Finalization

Orchestrator inline. After Phase 6d completes:

1. Read `{SCRATCHPAD}/pipeline_trace.md` (built incrementally throughout the audit).
2. Run Conservation Check: `report_IDs + Appendix_A_exclusions + documented_absorptions -> initial_findings + extractions`.
3. If mass balance fails: log `PIPELINE_TRACE_CONSERVATION_FAIL` to `violations.md`. Update checklist row 50 (Conservation Check) to `FAILED_WITH_FALLBACK` ONLY IF the fallback artifact (degradation_log.md with the conservation deviation reason) is written. Otherwise row 50 stays unfinished -> Phase 6f embargo will hold.
4. If conservation passes -> row 50 `COMPLETE`.
5. If `--include-trace-in-report` flag set: append the trace table as an appendix to `AUDIT_REPORT.md` under "Appendix B: Pipeline Trace".

See `~/.valves/rules/pipeline-trace.md` for schema.

### Phase 6e-PATCH: Measurement Artifacts (VALVES v1.7-PATCH -> PATCH K -> MANDATORY)

Orchestrator inline, no new agent spawn. Runs at the tail of Phase 6e (after Conservation Check completes, before Phase 6f embargo). Writes two lightweight measurement artifacts so future audits + reviewers can tell whether the v1.7-PATCH improvements are actually moving valid recall + precision.

**Artifact 1: `{SCRATCHPAD}/seed_metrics.md`** -> raw + canonical seed accounting (v1.7-PATCH2 extends with canonical row):

```
Write {SCRATCHPAD}/seed_metrics.md:

# Seed Metrics -> {project} -> {ISO timestamp}

## Raw seeds (per-source, pre-dedup)
| Source | Created | Investigated (Session A) | PROMOTED_TO_FINDING | CLEARED_PRE_DEPTH | FORWARD_TO_SESSION_B | Session B rescues | Promote rate | Rescue rate |
|---|---|---|---|---|---|---|---|---|
| Harvester (sweeps 1-8) | {S1+...+S8} | {N} | {Hp} | {Hc} | {Hf} | {Hr} | {Hp/Investigated} | {Hr/Hf} |
| Assumption-Breaker (AB-1..AB-6) | {AB} | {N} | {ABp} | {ABc} | {ABf} | {ABr} | {hit-rate} | {rescue-rate} |
| Analog Session A | {AS_A} | {N} | {ASp} | {ASc} | {ASf} | {ASr} | {hit-rate} | {rescue-rate} |
| Analog Session B (forward only) | {AS_B} | 0 (forward-only) | -> | -> | {AS_B} | {ASrB} | -> | {ASrB/AS_B} |
| Analog (SKIPPED, no triggers fired) | 0 | -> | -> | -> | -> | -> | -> | -> |

(If `analog_seeds.md` § Source: SKIPPED -> the SKIPPED row above shows zeros and the four Analog rows above it are blank or absent. Otherwise the SKIPPED row reads `n/a`.)

## Canonical seeds (post-dedup, v1.7-PATCH2)
| Bucket | Canonical count | Members (raw) | Compression ratio | PROMOTED_TO_FINDING | CLEARED_PRE_DEPTH | FORWARD_TO_SESSION_B | Cross-source canonicals (>= 2 sources hitting same target) |
|---|---|---|---|---|---|---|---|
| All families | {C} | {R} | {C/R} | {P_canon} | {C_canon} | {F_canon} | {X} |
| E1 SYMMETRIC | {n1c} | {n1r} | {n1c/n1r} | -> | -> | -> | -> |
| E2 INTERFACE | {n2c} | {n2r} | {n2c/n2r} | -> | -> | -> | -> |
| E3 CONFIG-DRIFT | {n3c} | {n3r} | {n3c/n3r} | -> | -> | -> | -> |
| E4 PARITY | {n4c} | {n4r} | ... | -> | -> | -> | -> |
| E5 EXTERNAL-DEP | {n5c} | {n5r} | ... | -> | -> | -> | -> |
| E6 RECIPIENT | {n6c} | {n6r} | ... | -> | -> | -> | -> |
| E7 MIRROR-ACCT | {n7c} | {n7r} | ... | -> | -> | -> | -> |
| E8 EMERGENCY | {n8c} | {n8r} | ... | -> | -> | -> | -> |
| E9 TRUST-MODEL | {n9c} | {n9r} | ... | -> | -> | -> | -> |
| E10 ADMIN-LIVE-POINTER | {n10c} | {n10r} | ... | -> | -> | -> | -> |

(Source: read `~/.valves/state/canonical_seed_map.md` is N/A -> read `{SCRATCHPAD}/canonical_seed_map.md` § Summary + § Canonical seeds. If `canonical_seed_map.md` is missing (SOFT gate degraded), this entire section reads `n/a` and the report uses raw counts only.)

## Aggregates
- Total raw seeds: {R}
- Total canonical seeds: {C}
- Compression ratio (overall): {C/R} -> lower number means more dedup happened
- Total promoted to findings (Session A): {P}
- Total cleared pre-depth (with valid proof): {C_clr_proof}
- Total downgraded from CLEARED to FORWARD due to missing proof (v1.7-PATCH3): {C_downgrade}
- Total forwarded to Session B: {F}
- Total Session B rescues (canonical seed FORWARD_TO_SESSION_B -> confirmed finding via Session B DA pass): {R_rescue}
- Cross-source canonical hit rate: {Confirmed cross-source canonicals} / {Cross-source canonicals X}
- Analog-seed hit rate (when not SKIPPED): {ASp + ASr}/{AS_A + AS_B}
- Assumption-breaker hit rate: {ABp + ABr}/{AB}

## Proof quality (v1.7-PATCH3 PATCH 4 -> per source/family)
| Source | CLEARED count | with full proof | downgraded | proof quality % | OTHER % |
|---|---|---|---|---|---|
| Harvester (sweeps 1-8) | {Hc_total} | {Hc_proof} | {Hc_downgrade} | {Hc_proof/Hc_total} | {Hc_other/Hc_proof} |
| Assumption-Breaker | {ABc_total} | {ABc_proof} | {ABc_downgrade} | {pct} | {other_pct} |
| Analog | {ASc_total} | {ASc_proof} | {ASc_downgrade} | {pct} | {other_pct} |

| Family | CLEARED count | with full proof | proof quality % |
|---|---|---|---|
| E1 SYMMETRIC | {n} | {p} | {p/n} |
| E2 INTERFACE | {n} | {p} | {p/n} |
| ... (E3-> E10) ... |  |  |  |

`proof_type_other_pct` aggregate: {other_total}/{proof_total} -> if > 30%, `PROOF_TYPE_OTHER_HIGH` was logged to degradation_log.md (calibration signal that the proof-type enumeration may need extending; not a blocker).

## Session B rescue rate by handoff section (v1.7-PATCH3 PATCH 4)
| Handoff section | Rows in handoff | Rescued in Session B | Rescue rate |
|---|---|---|---|
| § 1 Top dangerous blind spots | {N1} | {R1} | {R1/N1} |
| § 2 Top unresolved seeds | {N2} | {R2} | {R2/N2} |
| § 3 Top disagreements | {N3} | {R3} | {R3/N3} |
| § 4 Top negative-space targets | {N4} | {R4} | {R4/N4} |
| § 5 Top uncertain Medium+ | {N5} | {R5} | {R5/N5} |
| § 6 Top orphan / non-thesis | {N6} | {R6} | {R6/N6} |

"Rescued" = handoff row whose target became a CONFIRMED finding via Session B DA / verifier (not already CONFIRMED at COMPLETE_A).

## Family saturation (v1.7-PATCH4 PATCH 6 - Session B attention vs final yield by Seed Family)
| Family | Session B slots consumed | Final findings produced | Rescue conversion | Saturation index (slots/finding) |
|---|---|---|---|---|
| E1 SYMMETRIC | {S1} | {F1} | {RC1} | {S1/max(F1,1)} |
| E2 INTERFACE | {S2} | {F2} | {RC2} | {S2/max(F2,1)} |
| E3 CONFIG-DRIFT | {S3} | {F3} | {RC3} | {S3/max(F3,1)} |
| E4 PARITY | {S4} | {F4} | {RC4} | {S4/max(F4,1)} |
| E5 EXTERNAL-DEP | {S5} | {F5} | {RC5} | {S5/max(F5,1)} |
| E6 RECIPIENT | {S6} | {F6} | {RC6} | {S6/max(F6,1)} |
| E7 MIRROR-ACCT | {S7} | {F7} | {RC7} | {S7/max(F7,1)} |
| E8 EMERGENCY | {S8} | {F8} | {RC8} | {S8/max(F8,1)} |
| E9 TRUST-MODEL | {S9} | {F9} | {RC9} | {S9/max(F9,1)} |
| E10 ADMIN-LIVE-POINTER | {S10} | {F10} | {RC10} | {S10/max(F10,1)} |

Definitions:
- **Session B slots consumed**: count of Session B DA / chain / verifier spawns whose target had a Seed Family tag matching this row (from `canonical_seed_map.md` provenance + handoff § 2 entries).
- **Final findings produced**: count of CONFIRMED report-IDs whose primary canonical entry's Seed Family matches this row.
- **Rescue conversion**: count of rescued targets (per § Rescue Reserve eligibility in `~/.valves/rules/verification-priority-queue.md`) of this family that ended CONFIRMED, divided by total rescued targets of this family.
- **Saturation index**: low value (<2) means this family is highly productive per Session B slot; high value (>5) means lots of attention with little yield (calibration signal — family-diversity cap may need tuning, OR canonical map merge predicate may be too aggressive on this family).

Family-diversity cap effectiveness (v1.7-PATCH4 PATCH 3):
- families_capped_count: {N families that hit the 2-per-family cap in § 2 this audit}
- diversity_overflow_promoted: {N candidates refilled into § 2 from overflow}
- cap_dominant_family_share_pct: {pct} - if cap had not been applied, what share of § 2 the top family would occupy (proxy for cap utility)

This entire section is descriptive. Sustained low rescue conversion on a specific family (e.g., E9 TRUST-MODEL consistently <0.10 across 3+ audits) is a calibration signal to either tighten that family's eligibility predicate OR adjust handoff ranking priority. NO auto-retuning.

Source: read `seed_outcomes.md`, `canonical_seed_map.md`, `session_a_to_b_handoff.md` § 0 + § 2, `findings_inventory.md`, Session B `analysis_depth_da_*.md` and `verify_*.md`.

## Reserve-to-final conversion (v1.7-PATCH5 PATCH 5 - "are reserves actually winning")

This is the single best "is Valves beating Plamen" signal. A reserve mechanism is only valuable if its targets convert to final report findings at a meaningful rate.

| Source | Targets verified | Final report findings | Conversion rate | Notes |
|---|---|---|---|---|
| Main queue | {MQ_v} | {MQ_f} | {MQ_f / MQ_v} | EV-ranked findings that won the main queue |
| Orphan reserve | {OR_v} | {OR_f} | {OR_f / OR_v} | findings without strong cluster/thesis/chain (existing pre-Valves) |
| Rescue reserve (total) | {RR_v} | {RR_f} | {RR_f / RR_v} | v1.7-PATCH4 mechanism aggregate |
| -- proof-gap downgrade | {RR_pg_v} | {RR_pg_f} | {pct} | seeds CLEARED-without-proof routed to FORWARD then promoted |
| -- slack redistribution | {RR_sl_v} | {RR_sl_f} | {pct} | handoff rows redistributed via § Slack redistribution then promoted |
| -- sibling-link assist | {RR_sb_v} | {RR_sb_f} | {pct} | findings whose discovery cited a Linked CS |
| -- cross-source canonical | {RR_xs_v} | {RR_xs_f} | {pct} | canonicals with Members >= 2 from >= 2 sources, FORWARD then promoted |
| -- family-diversity overflow | {RR_fo_v} | {RR_fo_f} | {pct} | § 2 rows refilled from family-cap overflow then promoted |

| Override / sanity-check usage | Triggered | Findings affected | Notes |
|---|---|---|---|
| dominant_family_override_applied (v1.7-PATCH5 PATCH 3) | {Y/N} | {N findings from the +1 slot} | recorded in handoff § 0 |
| strongest_exploit_final_check warnings (v1.7-PATCH5 PATCH 1) | {N warnings} | {N report-quality-notes appended} | STRONGEST_DROPPED_BEFORE_REPORT vs STRONGEST_DISPLACED_BY_WEAKER counts |
| rescue_diversity_applied (v1.7-PATCH5 PATCH 2) | {Y/N} | {N candidates held by class cap} | recorded in seed_metrics § Rescue reserve diversity |

**Key derived ratios** (these are the headline metrics for cross-audit comparison):

- **Rescue conversion uplift over orphan reserve**: `(RR_f / RR_v) / (OR_f / OR_v)` — > 1.0 means the rescue reserve is producing finals at a higher rate than orphans (rescue mechanism is earning its budget). < 1.0 across multiple audits is a calibration signal to tighten rescue eligibility OR shrink the reserve.
- **Diversity-control yield**: per-class conversion within rescue reserve. If proof-gap class converts at 50% but cross-source class converts at 5% across 3+ audits, raise the cross-source predicate's bar (e.g., require Members >= 3 instead of 2). NO auto-retuning — surfaced as calibration signal only.
- **Override yield**: how often dominant_family_override_applied resulted in the +1 slot's candidate becoming a final finding. Track across audits to verify the 0.25 score-gap threshold is calibrated.
- **Strongest-exploit final-check effectiveness**: count of STRONGEST_DISPLACED_BY_WEAKER warnings that, after human review, resulted in restoring a stronger parent exploit to the final report. High count means the check is catching real losses; zero count over many audits is a signal to relax or remove the check.

## Notes for reserve-to-final tracking

- "Targets verified" = count of findings that reached Phase 5 verifier spawn from this source bucket. Idempotent across re-runs.
- "Final report findings" = count of report IDs in AUDIT_REPORT.md whose origin trace through cluster_instance_map.md and findings_inventory.md leads back to this source bucket.
- A finding with multiple-source eligibility is counted ONCE in its primary source per the eligibility precedence (rescue > orphan > main).
- All metrics are descriptive. No auto-retuning. Calibration is human-driven, version-controlled.

Source: read `verification_priority_queue.md` (priority queue + orphan reserve + rescue reserve sections), `verify_*.md` (verifier verdicts), `findings_inventory.md` (final findings), `cluster_instance_map.md` (cluster -> report-ID), `session_a_to_b_handoff.md` § 0 (override usage), `seed_metrics.md` § Rescue reserve diversity (diversity-control usage), `strongest_exploit_final_check.md` (sanity-check warnings).

## Trigger / activation rates (v1.7-PATCH3 PATCH 4 -> analog seeding observability)
| Metric | Value |
|---|---|
| analog_trigger_activation_rate | 1 if any of T1-T6 fired this audit, else 0 |
| analog_triggers_fired | List of triggers that fired (e.g., `T1, T4`) |
| analog_trigger_hit_rate_when_active | {analog_promoted + analog_rescued} / {analog_total} -> only meaningful when activation = 1 |

## Slack redistribution (v1.7-PATCH3 PATCH 4 -> handoff observability)
| Metric | Value |
|---|---|
| slack_slots_available | sum of (default cap - actual rows) across all sections, capped at 3 |
| slack_slots_used | 0..3 |
| redistributed_slack_usage_rate | slack_slots_used / 3 |
| threshold_blocked | true if surplus existed but no candidate cleared the 0.40 score threshold |
| redistributed_section_breakdown | {§ 1: x slots, § 2: y slots, § 4: z slots, § 5: w slots} (empty when 0) |

## Conversion rates (v1.7-PATCH3 PATCH 4 -> unresolved-target attribution)
| Metric | Value |
|---|---|
| unresolved_target_conversion_rate | (canonical seeds FORWARD that became findings via Session B) / (total canonical FORWARD seeds) |
| handoff_section_2_conversion_rate | (§ 2 rows that became findings) / (§ 2 row count) |
| sibling_link_assist_count (v1.7-PATCH3 PATCH 3) | count of CONFIRMED findings whose discovery cited a Linked CS in their depth/verifier output |

## False-positive kill rate (v1.7-PATCH3 PATCH 4 -> precision observability, when verification data exists)
| Metric | Value |
|---|---|
| false_positive_kill_count | count of Phase 5 verdicts `[POC-FAIL: GENUINE]` that flipped a Session A CONFIRMED to REFUTED |
| false_positive_kill_rate | false_positive_kill_count / (total Session A CONFIRMED findings that reached Phase 5 verification) |

## Notes
- "Session B rescue" = a canonical seed with Normalized Outcome=FORWARD_TO_SESSION_B AND ended up promoted to a finding via Session B's depth iter 2/3 DA pass.
- "Cross-source canonicals" = canonical entries with Members >= 2 from >= 2 different sources (harvester + AB, harvester + analog, AB + analog, etc.). These are high-signal targets -> three independent mechanisms converging.
- "proof quality %" is descriptive, not normative. Low proof quality on a specific source/family is a calibration signal for future audit tuning, NOT a runtime block.
- "Sibling-link-assist" requires the depth/verifier output to explicitly cite the Linked CS in its evidence trace. This is an observability metric only -> auditors can grep verify_*.md and analysis_depth_da_*.md for `Linked CS:` cites.
- All metrics here are descriptive. The pipeline does NOT auto-modify thresholds based on these numbers. Tuning is human-driven, grounded in cross-audit trends in `~/.valves/state/bc_class_calibration.md`.
- Hit rate is descriptive, not normative. Compression ratio < 1.0 indicates real dedup; 1.0 means every raw seed was unique (no merges happened).
- Source: read `seed_outcomes.md` + `canonical_seed_map.md` + `findings_inventory.md` + `session_a_to_b_handoff.md` (§ 0 redistribution metadata) + Session B's `analysis_depth_da_*.md` + `verify_*.md`.
```

**Artifact 2: `{SCRATCHPAD}/coverage_lift.md`** -> before/after Session B comparison:

```
Write {SCRATCHPAD}/coverage_lift.md:

# Coverage Lift -> {project} -> {ISO timestamp}

## Findings before / after Session B
- Findings at COMPLETE_A boundary (Session A end): {N_A}
- Findings at audit close (final): {N_final}
- Net delta: +{N_final - N_A}
- Of net delta: {dDA} from Session B DA iter 2/3, {dCH} from Phase 4c chain new hypotheses, {dEXT} from Phase 5.5 [VER-NEW-*] extraction

## Severity changes attributable to Session B
- Severity upgrades after Session B (composite + cross-session bonus pushed a finding into a higher band): {U}
- Severity downgrades after Session B (DA refutation pushed a finding into a lower band or REFUTED): {D}
- New CONFIRMED at Session B (was UNCERTAIN/LOW at COMPLETE_A, became CONFIRMED in Session B re-scoring): {NC}
- New REFUTED at Session B (was CONFIRMED at COMPLETE_A, REFUTED by Session B + verifier): {NR}

## Recall / precision deltas
- Misses recovered by Session B (forward seeds + handoff entries that became findings): {MR}
- False positives killed by Session B (CONFIRMED-at-A but [POC-FAIL: GENUINE] at Session B verification): {FPK}

## Coverage residue
- Dangerous zero-finding areas remaining at audit close: {ZF}
   - Source: re-run negative_space.md classifier against final `findings_inventory.md` -> count of contracts / paths still in zero-finding-high-risk state.

## v1.7-PATCH3 lift indicators (PATCH 4)
- CLEARED downgrades that became findings via Session B (downgrade_rescue_count): {DR} -> a CLEARED-but-no-proof seed that routed to FORWARD instead, then Session B promoted it. **High DR is direct evidence the proof discipline is catching real misses.**
- CLEARED downgrade rate (downgraded / (downgraded + cleared_with_proof)): {DR_rate}
- Slack-redistributed rows that became findings (slack_rescue_count): {SR} -> redistributed § 1/2/4/5 rows that became CONFIRMED via Session B.
- Sibling-link-assisted findings (sibling_assist_count, v1.7-PATCH3 PATCH 3): {SA} -> CONFIRMED findings whose discovery cited a Linked CS.
- Cross-source canonical conversion (cross_source_canonical_findings): {CSF} -> CONFIRMED findings whose Source Provenance shows >= 2 different sources (harvester + AB, harvester + analog, etc.). High-signal validation of the dedup design.

## Notes
- Source: read `session_checkpoint.md` § Finding Cards (Session A snapshot), `findings_inventory.md` (final), `confidence_scores.md` (final, post cross-session bonus), `cross_session_consensus.md`, `seed_outcomes.md` § Summary, `canonical_seed_map.md` § Summary, `session_a_to_b_handoff.md` § 0 Redistribution Metadata, `verify_*.md`, `negative_space.md`.
- This is descriptive measurement, not a gate. The numbers above are exposed in the report's "## Audit Methodology Notes" appendix when `--include-trace-in-report` is set.
- v1.7-PATCH3 metrics enable cross-audit calibration: a sustained low downgrade_rescue_count indicates the proof discipline is catching only weak signals (good); a high count indicates the discipline is catching real misses (also good -> this is the recall lift). A sustained low slack_rescue_count with high slack_slots_used indicates the 0.40 threshold may be too lax (calibration signal). All such tuning is human-driven, NOT auto-applied.
```

These artifacts feed `~/.valves/state/bc_class_calibration.md` for cross-audit calibration trends and feed Phase 6 report's `## Audit Methodology Notes` appendix when the `--include-trace-in-report` flag is set. They do NOT modify findings, severity, or report IDs -> they are pure measurement.

**Soft-required (Rule 15)**: if either measurement file fails to write (e.g., source artifact missing), log to `degradation_log.md` and proceed. The audit completes regardless. Phase 6f embargo does NOT depend on these.

### Phase 6e+1: Session B Closure (v1.7-PATCH10 — orchestrator inline, MANDATORY in Thorough)

> **Purpose**: write the real `COMPLETE_B` checkpoint that Phase 6f embargo + Step 0-pre routing already require. Pre-PATCH10, the embargo and routing logic referenced `status==COMPLETE_B` but no write path existed — this step closes that gap.

> **When to run**: after Phase 6e Pipeline Trace Finalization + Phase 6e-PATCH measurement artifacts complete, BEFORE Phase 6f embargo evaluates. Specifically the closure must happen AFTER all of Session B's substantive work is on disk so the closure cannot misrepresent run state.

> **Mode policy**: HARD GATE in Thorough (skip → Phase 6f embargo will fail because session_checkpoint.md status remains COMPLETE_A). NOT_APPLICABLE in Light/Core (those modes don't use the Session A/B split, so no COMPLETE_B is required — their pipeline ends at Phase 6e finalization).

> **Mode gate**: this step runs ONLY when `MODE == THOROUGH` AND `SESSION == B` (i.e., the orchestrator is in the Session B conversation that resumed from COMPLETE_A). The orchestrator MUST NOT write COMPLETE_B in any other mode or session — see Hard rules below.

**Pre-write integrity check (mechanical, MANDATORY before the write)**:

Before rewriting `session_checkpoint.md`, the orchestrator runs a hard verification scan to ensure Session B's substantive work actually completed. The check is identical in spirit to the Pre-Report Gate but covers the ENTIRE Session B segment, not just the report path:

```
1. Confirm session boundary integrity:
   - session_checkpoint.md exists and current status == COMPLETE_A
   - cross_session_consensus.md exists in SCRATCHPAD
   - SESSION variable == "B" (this conversation IS the Session B conversation)

2. Confirm Session B substantive completion (per mode contract):
   For Thorough mode, ALL of these must be terminal in mandatory_step_checklist.md:
     - Row 22 Confidence Scoring → COMPLETE
     - Row 28 Depth iter 2 DA → COMPLETE (or NOT_APPLICABLE if iter 1 already converged with no uncertain Medium+ findings)
     - Row 29 Depth iter 3 → COMPLETE or NOT_APPLICABLE (per convergence rules)
     - Row 30 Design Stress Testing → COMPLETE
     - Row 31-32 Chain Analysis (iter 1 + iter 2) → COMPLETE
     - Row 33 Verification Priority Queue → COMPLETE
     - Row 34 RAG Validation Sweep → COMPLETE or FAILED_WITH_FALLBACK (floor-scores fallback OK)
     - Row 35-38 Phase 5 verification batches → COMPLETE per mode-policy scope (ALL severities for Thorough)
     - Row 39 Skeptic-Judge → COMPLETE or NOT_APPLICABLE if no HIGH/CRIT findings
     - Row 40 Cross-Batch Consistency → COMPLETE
     - Row 41 Post-Verification Extraction → COMPLETE
     - Row 42 Thesis v3 + Cluster Inheritance → COMPLETE
     - Row 43 Negative Results capture → COMPLETE
     - Row 46 Cluster → Report Mapping → COMPLETE
     - Row 47 Report pipeline (Index → Tiers → Assembler) → COMPLETE
     - Row 48 Report Quality Self-Review → COMPLETE
     - Row 49 Pipeline Trace Finalization → COMPLETE
     - Row 58 Cross-Session Consensus → COMPLETE (Thorough HARD gate)
     - Row 69 Final Strongest-Exploit Sanity Check → COMPLETE or NOT_APPLICABLE if no SEC cards

3. Confirm the artifact-ownership integrity:
   - AUDIT_REPORT.md exists at PROJECT_ROOT and was written by the Assembler Agent (per artifact-ownership.md § Control table)
   - report_index.md, report_critical_high.md, report_medium.md, report_low_info.md exist with legal writers
   - cluster_instance_map.md exists with legal writer (Cluster Instance Map Agent)

4. If ANY check fails:
   - Log COMPLETE_B_PRECONDITIONS_NOT_MET to violations.md (HIGH severity)
     with the specific failed check (row#, artifact, expected status/writer)
   - Do NOT write COMPLETE_B
   - Trigger Recovery Loop per ~/.valves/rules/thorough-strict-mode.md § Recovery Loop
   - If recovery exhausted (3 iterations) → Phase 6f embargo MUST hold (since
     session_checkpoint.md status remains COMPLETE_A, the embargo will detect
     "session_checkpoint.md status != COMPLETE_B" and emit INCOMPLETE THOROUGH
     or INVALID FINALIZATION per ~/.valves/rules/thorough-strict-mode.md § Completion states)
```

**Write step (after pre-write integrity check passes)**:

The orchestrator REWRITES `session_checkpoint.md`, overwriting the previous COMPLETE_A version, with status flipped to `COMPLETE_B`. The write is orchestrator-inline (per `~/.valves/rules/artifact-ownership.md` § Control table — `session_checkpoint.md` is ORCHESTRATOR-INLINE).

```
Write {SCRATCHPAD}/session_checkpoint.md (overwrites COMPLETE_A version):

# Session Checkpoint (Valves v1.7)
## Pipeline State
- CHECKPOINT_LEVEL: COMPLETE_B
- MODE: thorough
- LANGUAGE: {LANGUAGE}
- SCRATCHPAD: {SCRATCHPAD}
- PROJECT_ROOT: {PROJECT_ROOT}
- CHECKPOINT_PHASE: Phase 6e-PATCH measurement artifacts complete; Session B substantive work finalized
- NEXT_PHASE: Phase 6f Final Report Embargo
- TIMESTAMP: {ISO 8601}
- SESSION_A_TIMESTAMP: {original COMPLETE_A timestamp from prior checkpoint, preserved}
- SESSION_B_DURATION: {Phase 4b iter 2 start → Phase 6e-PATCH end, in minutes}

## Launch-State Fields (audit contract — preserved verbatim from COMPLETE_A)
- DOCS_PATH: {from prior checkpoint}
- NETWORK: {from prior checkpoint}
- RPC_URL: {from prior checkpoint}
- SCOPE_FILE: {from prior checkpoint}
- SCOPE_NOTES: {from prior checkpoint}
- PROVEN_ONLY: {from prior checkpoint}
- HISTORICAL_PRIME_MODE: {from prior checkpoint}

## Session B Closure Confirmations (v1.7-PATCH10)
- cross_session_consensus_present: YES
- cross_session_consensus_path: {SCRATCHPAD}/cross_session_consensus.md
- verification_complete_per_mode_contract: YES
- verification_scope_executed: ALL severities + fuzz variants (Thorough mode)
- verify_files_count: {N}    # number of verify_*.md files on disk
- skeptic_judge_executed: {YES if HIGH/CRIT existed, else NOT_APPLICABLE}
- final_quality_complete: YES
- report_quality_review_complete: YES
- pre_report_gate_passed: YES
- report_pipeline_complete: YES
- audit_report_present: YES
- audit_report_writer: Assembler Agent (verified per artifact-ownership.md)
- final_strongest_exploit_sanity_check_complete: {YES or NOT_APPLICABLE if no SEC cards}
- pipeline_trace_finalized: YES
- conservation_check_status: {PASSED / FAILED_WITH_FALLBACK}
- measurement_artifacts_present: {YES if seed_metrics.md + coverage_lift.md exist, else PARTIAL with reason}

## Checklist State (ALL rows — full terminal picture at Session B closure)
{paste ALL rows from mandatory_step_checklist.md as of this moment, including:
 - COMPLETE rows (Session A + Session B all rows that succeeded)
 - FAILED_WITH_FALLBACK rows (with fallback artifact)
 - NOT_APPLICABLE rows (with non-trivial reason)
 - any row still PENDING/RUNNING is a precondition violation — the pre-write
   integrity check above should have caught this; if it appears here, something
   is wrong, and Phase 6f embargo will hold}

## Active Flags
{from template_recommendations.md — preserved from COMPLETE_A for full audit trail}

## Outcome (preliminary — Phase 6f embargo emits final classification)
- preliminary_outcome: PASS_PRECONDITIONS_FOR_VALID_THOROUGH
- final_outcome_pending: Phase 6f embargo evaluation
- final_outcome_will_be_one_of: {VALID THOROUGH DELIVERABLE, INCOMPLETE THOROUGH (degraded), INVALID FINALIZATION}
- final_outcome_recorded_in: {SCRATCHPAD}/compliance_summary.md
```

**(v1.7-PATCH11.1) Post-checkpoint writes (MANDATORY, immediately after session_checkpoint.md write)**:

```
// 1. Write SESSION_B_COMPLETE.md marker (analogous to HALT_AFTER_COMPLETE_A.md for Session A)
Write "{SCRATCHPAD}/SESSION_B_COMPLETE.md":
    # Session B Completion Marker (v1.7-PATCH11.1)
    Written by: Phase 6e+1 Session B Closure
    Timestamp: {ISO 8601}
    checkpoint_level: COMPLETE_B
    session_checkpoint_consistent: YES
    This marker confirms Session B closure completed normally.
    Step 0-pre uses it for consistency verification.

// 2. Update run_state.json to COMPLETE_B
rs_path = "{SCRATCHPAD}/run_state.json"
if file_exists(rs_path):
    rs = JSON.parse(read(rs_path))
    rs.checkpoint_level = "COMPLETE_B"
    rs.session = "B"
    rs.current_phase = "phase6e1_closure"
    rs.phase_status = "DONE"
    rs.halt_reason = "COMPLETE_B_FINALIZED"
    rs.last_completed_phase = "phase6e1_closure"
    rs.last_completed_timestamp = now_iso()
    rs.last_write_iso = now_iso()
    rs.write_ahead = { action: null, interrupted: false }
    Write rs_path (full JSON)

// 3. Verify consistency (fail-closed assertion)
rs_verify = JSON.parse(read(rs_path))
cp_verify = Read("{SCRATCHPAD}/session_checkpoint.md")
marker_exists = file_exists("{SCRATCHPAD}/SESSION_B_COMPLETE.md")
ASSERT: rs_verify.checkpoint_level == "COMPLETE_B"
ASSERT: cp_verify.CHECKPOINT_LEVEL == "COMPLETE_B"
ASSERT: marker_exists == true
if ANY assertion fails:
    log "COMPLETE_B_CONSISTENCY_FAILURE: rs={rs_verify.checkpoint_level}, cp={cp_verify.CHECKPOINT_LEVEL}, marker={marker_exists}" to violations.md
    // Do NOT proceed to Phase 6f — state is inconsistent
    HALT: "COMPLETE_B write succeeded but post-write consistency check failed."
```

**Hard rules (v1.7-PATCH10, updated PATCH11.1 — non-negotiable)**:

- **Session A NEVER writes COMPLETE_B**. The COMPLETE_A handoff bundle write step (`~/.valves/commands/valves.md` § COMPLETE_A boundary enforcement) writes `CHECKPOINT_LEVEL: COMPLETE_A` and HARD HALTs. Any orchestrator that finds itself about to write COMPLETE_B in Session A is in a process violation: log `ILLEGAL_COMPLETE_B_WRITE_IN_SESSION_A` to violations.md (HIGH severity) and refuse the write.
- **Session B's COMPLETE_B write happens ONLY at Phase 6e+1**. Earlier writes during Session B are forbidden — the orchestrator does not write intermediate COMPLETE_B checkpoints. Session B uses `PARTIAL_B` as its intermediate recovery checkpoint (v1.7-PATCH11). The COMPLETE_B write also produces a `SESSION_B_COMPLETE.md` marker and updates `run_state.json` — all three must be consistent.
- **Light/Core mode SKIPS this step entirely**. Those modes use a single conversation; their pipeline ends at Phase 6e Pipeline Trace Finalization. There is no `COMPLETE_B` for Light/Core — the embargo logic in `~/.valves/rules/thorough-strict-mode.md` § Final Report Embargo is Thorough-only.
- **Step 0-pre routing handles five checkpoint levels** (v1.7-PATCH11.1): NONE → fresh run; PARTIAL_A → resume Session A; COMPLETE_A → enter Session B (writes PARTIAL_B); PARTIAL_B → resume Session B; COMPLETE_B → run is finalized, halt with the "RUN ALREADY FINALIZED" banner (see Step 0-pre routing). This prevents accidental re-execution of a finalized run.
- **The COMPLETE_B write is orchestrator-inline ONLY**. Per `~/.valves/rules/artifact-ownership.md` § Control table, `session_checkpoint.md` is class=ORCHESTRATOR-INLINE. Any agent that writes COMPLETE_B triggers `ILLEGAL_WRITER_ORCHESTRATOR_ARTIFACT_BY_AGENT` per Phase 0.9 § A.

**Why this closure is mandatory before Phase 6f**:

The Phase 6f embargo (`~/.valves/rules/thorough-strict-mode.md` § Final Report Embargo, hardened in v1.7-PATCH10) requires `session_checkpoint.md status == COMPLETE_B` for VALID THOROUGH DELIVERABLE classification. Without this Phase 6e+1 closure step, the embargo would always emit INCOMPLETE THOROUGH or INVALID FINALIZATION even when Session B's substantive work succeeded — because the checkpoint would still read `COMPLETE_A`. Phase 6e+1 is the legitimate write path; the embargo is the consumer that verifies it.

**Why Phase 6f embargo CAN'T write COMPLETE_B itself**:

The embargo is the FINAL fail-closed gate; its job is to evaluate state and emit a classification. If the embargo wrote COMPLETE_B itself, the integrity check would be self-referential (the embargo would write the artifact it then checks for). The architecture requires a separate step that asserts Session B's substantive completion as a precondition, with the embargo as a downstream verifier. Phase 6e+1 satisfies this separation.

### Phase 6f (VALVES v1.5, Thorough only): Final Report Embargo

Orchestrator inline. ALWAYS RUNS for `MODE == THOROUGH`. Skipped for Light/Core.

```
checklist = read({SCRATCHPAD}/mandatory_step_checklist.md)
trace = read({SCRATCHPAD}/pipeline_trace.md)

embargo_holds = false
blocking_rows = []

# Check every row reaches valid terminal state
for row in checklist.rows:
  if row.status not in {COMPLETE, FAILED_WITH_FALLBACK, NOT_APPLICABLE}:
    embargo_holds = true
    blocking_rows.append((row, "non_terminal_state"))
  elif row.status == COMPLETE and not artifact_exists(row.evidence_artifact):
    embargo_holds = true
    blocking_rows.append((row, "synthetic_completion_no_artifact"))
  elif row.status == FAILED_WITH_FALLBACK and not artifact_exists(row.fallback_artifact):
    embargo_holds = true
    blocking_rows.append((row, "fallback_claimed_no_fallback_artifact"))
  elif row.status == NOT_APPLICABLE and (row.reason is None or row.reason in {"", "skipped", "n/a"}):
    embargo_holds = true
    blocking_rows.append((row, "na_without_reason"))

# Conservation check
if trace.conservation_check != PASSED:
  embargo_holds = true
  blocking_rows.append((row_50, "conservation_fail"))

# v1.7-PATCH10: Session B closure verification (consumes the real COMPLETE_B write)
# The embargo verifies that Phase 6e+1 Session B Closure actually wrote COMPLETE_B.
# This catches "Session B substantive work skipped" cases AND "Phase 6e+1 not run" cases.
if MODE == THOROUGH:
  checkpoint = read({SCRATCHPAD}/session_checkpoint.md)
  if checkpoint.CHECKPOINT_LEVEL != "COMPLETE_B":
    embargo_holds = true
    blocking_rows.append(("session_b_closure", "session_checkpoint_not_complete_b",
                          "current_status=" + checkpoint.CHECKPOINT_LEVEL))
  else:
    # COMPLETE_B was written by Phase 6e+1 — verify the closure confirmations are valid
    if checkpoint.cross_session_consensus_present != "YES":
      embargo_holds = true
      blocking_rows.append(("session_b_closure", "cross_session_consensus_not_confirmed"))
    if not artifact_exists({SCRATCHPAD}/cross_session_consensus.md):
      embargo_holds = true
      blocking_rows.append(("session_b_closure", "cross_session_consensus_artifact_missing"))
    if checkpoint.verification_complete_per_mode_contract != "YES":
      embargo_holds = true
      blocking_rows.append(("session_b_closure", "verification_not_per_mode_contract"))
    if checkpoint.report_pipeline_complete != "YES":
      embargo_holds = true
      blocking_rows.append(("session_b_closure", "report_pipeline_not_complete"))
    if checkpoint.audit_report_present != "YES":
      embargo_holds = true
      blocking_rows.append(("session_b_closure", "audit_report_not_present"))

# Write compliance summary always
write {SCRATCHPAD}/compliance_summary.md per ~/.valves/rules/thorough-strict-mode.md § Compliance Summary

if embargo_holds:
  # Try recovery (up to 3 iterations) per ~/.valves/rules/thorough-strict-mode.md § Recovery Loop
  for iteration in 1..3:
    for (row, reason) in blocking_rows:
      run_recovery_action(row, reason)
    re-evaluate; if blocking_rows empty -> break

  if still blocking after 3 iterations:
    print to terminal:
=======================================================================
  ->  THOROUGH RUN INCOMPLETE -> INVALID FINALIZATION

  The audit cannot be presented as a completed Thorough audit because the
  following mandatory steps did NOT reach a valid terminal state:

  {list of blocking_rows with row#, step, status, reason}

  Recovery attempts: {iteration} / 3 max
  Recovery outcome:  FAILED

  See: {scratchpad}/compliance_summary.md
       {scratchpad}/mandatory_step_checklist.md

  AUDIT_REPORT.md exists but is NOT a valid Thorough deliverable.
  Either:
    1. Re-run with manual recovery of the missing steps, OR
    2. Downgrade to Core mode and re-finalize (different completeness contract)
=======================================================================
    return  # do NOT present the report as completed Thorough audit

else:  # embargo lifted
  print to terminal:
=======================================================================
  -> THOROUGH RUN COMPLETE

  Mandatory steps:
    COMPLETE:              {N}
    FAILED_WITH_FALLBACK:  {M}
    NOT_APPLICABLE:        {K}
  Total mandatory rows:    {T}

  Pipeline Trace Conservation Check: PASSED
  Report Quality Self-Review issues: {flagged_count}

  Audit deliverable: {PROJECT_ROOT}/AUDIT_REPORT.md
=======================================================================
```

For non-Thorough modes (Light/Core), Phase 6f is skipped entirely. Those modes use the existing post-Phase-6 finalization without the embargo gate.

See `~/.valves/rules/thorough-strict-mode.md` § Final Report Embargo for the full enforcement protocol.

---

## FINDING OUTPUT FORMAT

**Full format in**: `~/.valves/rules/finding-output-format.md` -> ALL agents MUST read this file and use its format for findings. Includes Artifact Header (Rule 36), finding template, Rules Applied table (R4-R16), enforcement rules, and Depth Evidence Tags.

---

## GENERIC SECURITY RULES

**Full rules (R1-R16) in**: `~/.claude/prompts/{LANGUAGE}/generic-security-rules.md` -> agents MUST read this file. Key enforcement: CONTESTED -> adversarial assumption (R4), REFUTED -> requires chain analysis for enablers first (R12).

---

## SELF-CHECK

**Full checklists in**: `~/.claude/prompts/{LANGUAGE}/self-check-checklists.md` -> orchestrator MUST read and verify before Phase 5.

Quick checks before verification:
- [ ] All external deps identified?
- [ ] All patterns detected?
- [ ] Fork ancestry research completed?
- [ ] Static analysis fallback used if primary analyzer failed?
- [ ] Production fetch completed?
- [ ] FLASH_LOAN_INTERACTION skill instantiated if FLASH_LOAN or FLASH_LOAN_EXTERNAL flag?
- [ ] ORACLE_ANALYSIS skill instantiated if ORACLE flag?
- [ ] Inventory agent completed side effect trace audit?
- [ ] Static analysis findings promoted?
- [ ] Adaptive depth loop completed?
- [ ] Confidence scores computed?
- [ ] Adaptive loop converged?
- [ ] Chain analysis completed enabler enumeration?
- [ ] Worst-state severity used? (Rule 10)
- [ ] Anti-normalization check applied? (Rule 13)
- [ ] Post-verification finding extraction completed?
