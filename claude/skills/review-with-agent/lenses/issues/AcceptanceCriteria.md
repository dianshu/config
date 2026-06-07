# Issues Acceptance Criteria Lens

Enforce that Acceptance Criteria are testable, observable, and strictly behavioral — no implementation details allowed in the ACs. (Implementation details belong in `## What to build`).

## Primary dimensions covered
- ACCEPTANCE_CRITERIA (primary)

## Method
1. Read ALL pending issue files.
2. For each issue, scrutinize the `## Acceptance criteria` section bullet by bullet.

## Checklist
- **Implementation leak**: An AC bullet mentions a specific class, function name, file path, database column, or library (e.g. "The `UserService.login()` method returns true") → Blocking (rewrite as observable behavior: "When a valid user logs in, they are redirected to the dashboard")
- **Unverifiable**: "The UI feels fast" or "The code is robust" → Blocking (needs concrete observable condition)
- **Tautology**: "The feature works as described in What to build" → Blocking
- **Missing negative path**: The ACs only cover the happy path; missing validation failures, network errors, or empty states → Required
- **Missing AC section**: The issue has no `## Acceptance criteria` section at all → Blocking
- **Checkbox formatting**: The ACs use `- [ ]` syntax instead of just `- ` or `* `. Issues are documents, not checklists (the issue itself is the checklist item) → Suggestion

## Inputs
- The issue files in `issuesDir`
- Wont-fix ledger

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>`

Where:
- Category — ACCEPTANCE_CRITERIA (primary)
- IssueFile — the issue filename
- Anchor — `"AC-<n>"` (the ordinal of the offending bullet)
- Description — why the AC is flawed → suggested rewrite (≤3 lines)
