# Issues Dependency Auditor Lens

Audit declared and undeclared dependencies between issues. The `## Blocked by` section drives `/run-all-issues` dispatch order — wrong dependencies stall the loop or dispatch issues whose prerequisites aren't met.

## Primary dimensions covered
- DEPENDENCIES (primary)
- CONSISTENCY (cross-issue references must align)

## Method
1. Build a directed graph: for every issue, parse its `## Blocked by` list (issues already declared as blockers) and read its `## What to build` + `## Acceptance criteria` for semantic dependencies (e.g. "uses schema from X", "calls API defined in Y", "extends component from Z").
2. Compare declared blockers vs semantic blockers.
3. Walk the graph for cycles and wrong-direction edges.

## Checklist — per issue
- **Undeclared semantic dependency**: issue B's `## What to build` references something (schema, API, component, util) that issue A introduces, but B doesn't list A in `## Blocked by` → Blocking (loop will dispatch B before A is done)
- **Phantom blocker**: issue lists `## Blocked by` reference to an issue file that doesn't exist in `issuesDir` → Blocking (will fail `/run-all-issues` preflight step 8)
- **Wrong-direction blocker**: A claims to be blocked by B, but it's actually B that depends on A's output → Required (swap direction)
- **Cycle**: A blocks B blocks A (transitively too) → Blocking — `/run-all-issues` will report `⚠️ Stuck`
- **Non-code gate misplaced in `## Blocked by`**: bullets like `- **Phase 4 rollout signal**`, `- wait 1 week of telemetry`, `- needs design sign-off` → Blocking — these will fail `/run-all-issues` parser; instruct the author to move them to a new `## Hold` section or out of the issue
- **Stale done-blocker reference**: A lists `done-NN-*.md` in `## Blocked by` — technically parser-valid, but the author probably forgot to update after the blocker was completed → Suggestion (clean up for readability)
- **Coarse dependency**: A lists a sweeping blocker like "all schema work" rather than the specific issue → Required
- **Implicit ordering via numbering**: issue 02 logically depends on 01's output but doesn't say so — readers will assume `/run-all-issues` enforces NN ordering (it doesn't; it picks smallest unblocked NN) → Required

## Inputs
- The issue files in `issuesDir`
- Wont-fix ledger
- Optional: PARENT_PRD context (helps you reason about logical ordering)

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable: output `LGTM`
- **You do NOT validate `## Blocked by` regex format** — that's a deterministic preflight in the workflow. Focus on SEMANTIC correctness only.

## Output Format
One finding per line:
`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>`

Where:
- Category — DEPENDENCIES (primary) or CONSISTENCY
- IssueFile — the issue filename relative to `issuesDir`
- Anchor — `"Blocked by"` (for the section as a whole) or `"Blocked by:<NN>"` (referencing a specific blocker NN) or `"What to build"` (for undeclared semantic deps)
- Description — the dependency problem → consequence at `/run-all-issues` dispatch time → fix (≤3 lines)
