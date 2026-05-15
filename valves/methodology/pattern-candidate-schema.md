# Pattern Candidate Schema (v1.8-PATCH1)

Post-audit artifact for proposing new patterns to the Valves pattern library.
Agents write `{SCRATCHPAD}/pattern_candidates.md` during verification (Phase 5)
when a confirmed finding represents a novel, generalizable vulnerability class.

## Hard Rules

1. **Agents propose, never promote.** No agent writes to `~/.valves/patterns/learned/`.
   Candidates stay in the scratchpad until the post-audit curator reviews them.
2. **No proprietary code.** Candidates must not contain client code, contract names,
   addresses, or protocol-specific identifiers unless the audit is public.
3. **Abstract, not specific.** The pattern describes a CODE SHAPE and FAILURE MODE,
   not a specific bug in a specific contract.
4. **False-positive filters required.** Every candidate must include conditions where
   the pattern does NOT apply. A pattern without filters is a false-positive factory.
5. **Evidence threshold.** Only verified High/Medium findings qualify by default.
   Novel Low findings with strong mechanical proof ([POC-PASS] or [MEDUSA-PASS])
   may be proposed with explicit justification.

## Candidate Format

```markdown
## CANDIDATE: {short-title}

### Metadata
- **Proposed By**: {agent_id} during {audit_project}
- **Source Finding**: {report_id} (severity: {sev}, evidence: {tag})
- **Cluster**: {nearest existing cluster from PATTERN_INDEX.md, or "NEW: {name}"}
- **Chains**: {EVM / Solana / Aptos / Sui / Soroban / All}

### Code Shape
What to grep/look for in source code. Function signatures, operator patterns,
structural shapes. Be specific enough to trigger, general enough to transfer.

### Failure Mode
What breaks and how. One paragraph. State the invariant that is violated and
the consequence (fund loss, accounting drift, DoS, etc.).

### Attack Sketch
1. {step 1}
2. {step 2}
3. {impact}

### Look For
Bullet list of concrete code-level indicators an agent should check.

### False-Positive Filters
Conditions where this pattern does NOT apply:
- {filter 1 — e.g., "minimum deposit prevents dust amplification"}
- {filter 2 — e.g., "rounding direction consistently favors protocol"}
- {filter 3}

### Where This Does NOT Apply
Protocol types, chain contexts, or architectural patterns where this
vulnerability class is structurally impossible or irrelevant.

### Required Evidence Level
Minimum evidence for a finding based on this pattern to be credible:
- {e.g., "[POC-PASS] with concrete value drift over N operations"}
- {e.g., "[CODE-TRACE] with real constants showing accumulation"}
```

## Promotion Rules (Post-Audit Curator)

The post-audit improvement protocol (`~/.plamen/rules/post-audit-improvement-protocol.md`)
governs promotion. Summary:

1. Candidate must pass the RC-AGENT Exclusion Test (the miss was a methodology gap,
   not an agent reasoning error).
2. Candidate must pass anti-bloat gates (no >60% overlap with existing patterns,
   no duplication, marginal value check).
3. Candidate must pass the methodology test: does it teach HOW to look, not WHAT
   to find? If it encodes a specific bug → RAG only, not pattern library.
4. Pattern must include false-positive filters and "where this does NOT apply."
5. Curator verifies the pattern is chain-appropriate (EVM pattern doesn't go in
   a Move-specific cluster without adaptation).
6. Promoted patterns go to `~/.valves/patterns/learned/{slug}.md` and get an
   entry in `PATTERN_INDEX.md` under `## Learned Patterns`.

## Scratchpad Integration

Verification agents (Phase 5) check each [POC-PASS] finding:
- Is this vulnerability class already in `PATTERN_INDEX.md`?
- If NO → append a candidate entry to `{SCRATCHPAD}/pattern_candidates.md`
- If YES but the existing pattern misses a variant → append a refinement note

The orchestrator does NOT act on `pattern_candidates.md` during the audit.
It is a post-audit artifact only.
