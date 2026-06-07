# Issues Coverage Lens

Verify that the union of pending issues covers every User Story and Acceptance Criterion in the parent PRD. This lens **requires the PARENT_PRD context file** — the workflow drops this lens from the roster when no PRD is injected.

## Primary dimensions covered
- COVERAGE (primary)

## Method
1. Read the PARENT_PRD content (from `args.contextFiles` entry whose label === `"PARENT_PRD"`).
2. Enumerate every User Story (`US-<n>`) and its Acceptance Criteria from the PRD.
3. Read every pending issue file (`NN-*.md`, no `done-` prefix) — this is what the bundle contains.
4. Note: the bundle does NOT include `done-NN-*.md` file content (only filenames are observable via the bundle separator pattern in the workflow). For done coverage, infer from filenames + PRD-document Story status if any (e.g. PRD `## Completed Stories` list). When uncertain, surface as a Suggestion-severity note rather than a Blocking gap.
5. Build the coverage matrix:
   - PRD User Story `US-<n>` → which pending issue file(s) reference it (via `## Parent` link, `## What to build` mention, or an Acceptance Criterion that obviously implements one of US-`<n>`'s Acceptance Criteria)
   - Each pending issue → which PRD User Story it covers
6. Walk for gaps and orphans.

## Checklist
- **Uncovered User Story**: PRD `US-<n>` exists, no pending or done issue covers it → Blocking
- **Uncovered Acceptance Criterion within a covered Story**: `US-<n>` overall is covered by some issue, but a specific Acceptance Criterion bullet has no corresponding criterion in any issue → Required
- **Orphan issue**: pending issue doesn't trace to any User Story or stated PRD scope item → Required (rewrite the `## Parent` link, or move to Out-of-Scope, or drop)
- **Multi-claim**: two issues both claim to cover the same `US-<n>` Acceptance Criterion without specifying which slice of the behavior each owns → Required (delineate slices or merge)
- **Partial-coverage masquerading as full**: issue claims to cover `US-<n>` but its `## Acceptance criteria` only addresses a subset; remaining slice is silently unscheduled → Required
- **PRD-Out-of-Scope being implemented**: an issue ships behavior the PRD's `## Out of Scope` explicitly excludes → Blocking (the author either re-scoped the PRD without updating it, or built the wrong thing)
- **Coverage-of-done**: the workflow bundle only contains pending issue file content. For Stories you suspect are covered by an already-done issue, mark them as inferred-covered with a Suggestion noting which `done-NN-*.md` filename appears to cover the Story — don't emit Blocking unless the PRD itself states the Story should still be in scope.
- **Implicit Story addition**: pending issue adds user-visible behavior not in any PRD Story → Required (add the Story to PRD via a follow-up, or drop the issue)

## Matrix summary (always emit one)
Emit a single `Suggestion`-severity GLOBAL finding summarizing coverage:
`Suggestion|COVERAGE|GLOBAL|MATRIX-SUMMARY|<X> of <Y> PRD User Stories covered by pending+inferred-done issues; <Z> orphan issues`

The `GLOBAL::MATRIX-SUMMARY` anchor is **evergreen** — it re-fires every round by design as a status report. `progression-check.workflow.js` explicitly excludes this anchor from the `stillOpenAnchors` tracking so the loop is not forced to wont-fix it each round (see `EVERGREEN_ANCHORS` in progression-check).

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
