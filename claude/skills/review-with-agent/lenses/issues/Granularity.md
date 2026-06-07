# Issues Granularity Lens

Judge whether each issue is sized right — neither a multi-day epic nor a sub-task fragment — and whether the set as a whole avoids duplication and decorative slices that don't earn their keep.

## Primary dimensions covered
- GRANULARITY (primary)
- SUBTRACTABILITY (fold-in target for the PRD `Subtractor` lens's "doesn't earn its keep" critique)

## Method
1. Read every pending issue file.
2. For each issue, estimate the implementation surface from `## What to build` + `## Acceptance criteria` (rough scale: lines of code, files touched, test surface).
3. Compare adjacent issues for overlap, near-duplication, or unjustified hairline splits.

## Checklist — per issue
- **Too coarse (epic)**: `## What to build` reads as multiple unrelated user-visible changes; `## Acceptance criteria` mixes orthogonal concerns; estimated >1 sprint → Required (propose split point)
- **Too coarse (multi-concern)**: one issue ships a schema + an API + a UI + a migration script + a deprecation — even if all serve one story, the loop can't recover from a partial fail → Required (split along seams)
- **Too fine (fragment)**: issue's only output is a sub-task of a sibling (e.g. "write the helper function used by issue 04") with no independent user value → Required (fold into the consumer)
- **Too fine (mechanical split)**: two issues with near-identical `## What to build` that should be one → Required
- **Decorative slice**: issue exists for thoroughness but no acceptance criterion produces user-observable change (e.g. "add metrics dashboards", "refactor naming") AND PRD doesn't tie it to a Story → Suggestion (consider dropping or labelling Out-of-Scope)
- **While-we're-here scope creep**: `## What to build` mentions "and also clean up X" / "while doing this, refactor Y" → Required (extract or drop)
- **Speculative slice**: issue addresses a "might need later" capability with no current consumer in the PRD → Required
- **Duplicate slice**: two issues describe the same vertical from different angles → Blocking (merge)

## Inputs
- The issue files in `issuesDir`
- Wont-fix ledger
- Optional: PARENT_PRD (lets you cross-check decorative slices against actual Stories)

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>`

Where:
- Category — GRANULARITY (primary) or SUBTRACTABILITY
- IssueFile — the issue filename (when finding spans two issues, pick the one to act on, mention the other in the description)
- Anchor — `"Title"` / `"What to build"` / `"AC-<n>"` / `"GLOBAL"` (for set-wide observations like overall duplication summary)
- Description — current size/duplication problem → why it bites → split/merge/drop suggestion (≤3 lines)
