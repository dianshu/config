# Issues Coverage Lens

Verify that the union of pending issues covers every User Story and Acceptance Criterion in the parent PRD. This lens **requires the PARENT_PRD context file** — the workflow drops this lens from the roster when no PRD is injected.

## Primary dimensions covered
- COVERAGE (primary)

## Method
1. Read the PARENT_PRD content (from `args.contextFiles` entry whose label === `"PARENT_PRD"`).
2. Enumerate every User Story (`US-<n>`) and its Acceptance Criteria from the PRD.
3. Read every pending issue file (`NN-*.md`, no `done-` prefix).
4. Build the coverage matrix:
   - PRD User Story `US-<n>` → which issue file(s) reference it (via `## Parent` link, `## What to build` mention, or an Acceptance Criterion that obviously implements one of US-`<n>`'s Acceptance Criteria)
   - Each issue → which PRD User Story it covers
5. Walk for gaps and orphans.

## Checklist
- **Uncovered User Story**: PRD `US-<n>` exists, no pending or done issue covers it → Blocking
- **Uncovered Acceptance Criterion within a covered Story**: `US-<n>` overall is covered by some issue, but a specific Acceptance Criterion bullet has no corresponding criterion in any issue → Required
- **Orphan issue**: pending issue doesn't trace to any User Story or stated PRD scope item → Required (rewrite the `## Parent` link, or move to Out-of-Scope, or drop)
- **Multi-claim**: two issues both claim to cover the same `US-<n>` Acceptance Criterion without specifying which slice of the behavior each owns → Required (delineate slices or merge)
- **Partial-coverage masquerading as full**: issue claims to cover `US-<n>` but its `## Acceptance criteria` only addresses a subset; remaining slice is silently unscheduled → Required
- **PRD-Out-of-Scope being implemented**: an issue ships behavior the PRD's `## Out of Scope` explicitly excludes → Blocking (the author either re-scoped the PRD without updating it, or built the wrong thing)
- **Coverage-of-done**: when `done-NN-*.md` files cover a Story, count them as covered — don't re-flag — but note in a Suggestion that the audit assumes the done work was correct
- **Implicit Story addition**: pending issue adds user-visible behavior not in any PRD Story → Required (add the Story to PRD via a follow-up, or drop the issue)

## Matrix summary (always emit one)
Emit a single `Suggestion`-severity GLOBAL finding summarizing coverage:
`Suggestion|COVERAGE|GLOBAL|MATRIX-SUMMARY|<X> of <Y> PRD User Stories covered by pending+done issues; <Z> orphan issues`

## Inputs
- The issue files in `issuesDir`
- **REQUIRED**: PARENT_PRD entry in `args.contextFiles`
- Wont-fix ledger

## Behavior when PARENT_PRD is absent
If invoked despite the workflow's auto-drop logic (defensive): output a single `Suggestion`-severity GLOBAL finding stating "Coverage lens skipped — no PARENT_PRD injected" and stop. Do NOT attempt heuristic coverage analysis without the source of truth.

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable beyond the matrix summary: output the summary line only

## Output Format
One finding per line:
`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>`

Where:
- Category — COVERAGE
- IssueFile — the issue filename, OR `"GLOBAL"` for matrix-summary / set-wide findings
- Anchor — `"US-<n>"` (PRD User Story id) / `"US-<n>:AC-<m>"` (specific PRD AC) / `"MATRIX-SUMMARY"` / `"Parent"` (when the issue's parent link is the problem)
- Description — what's uncovered / orphan / over-claimed → which PRD reference is missing → action (≤3 lines)
