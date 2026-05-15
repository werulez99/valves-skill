# Pattern Library Integration Rules

> Used by: breadth, depth, rescan phases.

## Pattern Library Location
- Index: `~/.valves/patterns/PATTERN_INDEX.md`
- Cluster files: `~/.valves/patterns/{category}.md`
- Cantina corpus: `~/.valves/patterns/cantina/`

## How to Use Patterns

1. **At phase start**: Read `PATTERN_INDEX.md` to identify which pattern clusters match the protocol type
2. **Select 1-3 clusters**: Read only the relevant cluster files (e.g., `lending-liquidation.md` for lending, `oracle-dependency.md` for oracle users)
3. **Apply as detection heuristics**: Each pattern describes a vulnerability class with root cause, symptoms, and code signatures
4. **Ground in target code**: Every pattern match MUST be grounded in the target codebase with specific file:line references

## Anti-Anchoring Rule (CRITICAL)
Patterns inform WHAT to look for, not WHAT to find. A pattern match is a HYPOTHESIS, not a FINDING.
- Pattern says "check for X" -> check for X -> if X exists, investigate -> if exploitable, report
- Pattern says "check for X" -> check for X -> if X does not exist, move on
- NEVER: pattern says "check for X" -> report X without checking
- NEVER: anchor on a pattern and force-fit it to code that doesn't match

## Pattern Priority
When multiple patterns match, prioritize by:
1. Historical severity (patterns from Critical/High findings first)
2. Protocol-type relevance (exact match > adjacent match)
3. Recency (newer patterns reflect current audit landscape)
