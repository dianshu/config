# Issues Acceptance Criteria Lens

Every `## Acceptance criteria` checkbox must describe externally observable behavior, be testable, and not leak implementation internals. The bar is identical to the PRD User Story Acceptance Criteria bar, applied per-issue.

## Primary dimensions covered
- ACCEPTANCE_CRITERIA (primary)

## Method
1. Read every pending issue file's `## Acceptance criteria` section.
2. For each checkbox bullet, judge against the checklist below.

## Checklist — per checkbox
- **Missing section**: issue has no `## Acceptance criteria` heading at all → Blocking
- **Empty section**: heading present, zero bullets → Blocking
- **Internals leak**: bullet names a class, method, file path, schema field, DB column, library API, or internal constant → Blocking (rewrite in observable terms)
- **Not testable**: bullet is so vague no test could be written ("it works", "performance is good", "user is happy") → Blocking
- **Happy path only**: section covers success but not failure / boundary / empty / concurrency cases the issue's surface obviously exposes → Required
- **Pure implementation step**: bullet describes WHAT to do, not what shall be observable afterwards ("create the X table", "import the Y module") → Required (rewrite as outcome)
- **Compound criterion**: one bullet bundles 3+ assertions joined by "and" — split for testability → Suggestion
- **Implicit precondition not stated**: bullet asserts an outcome but the prerequisite state (user signed in, data populated, feature flag on) is omitted → Suggestion
- **Quantification missing where needed**: "fast", "many", "small" — replace with a measurable target → Required
- **Negative-form-only**: section only says what shouldn't happen, never asserts what should → Required

## Inputs
- The issue files in `issuesDir`
- Wont-fix ledger
- Optional: PARENT_PRD (lets you cross-check that this issue's criteria don't contradict the parent Story's criteria)

## Constraints
- ≤10 Suggestion findings; Blocking and Required uncapped. ≤3 lines each
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>`

Where:
- Category — ACCEPTANCE_CRITERIA
- IssueFile — the issue filename
- Anchor — `"AC-<n>"` where `<n>` is the 1-based ordinal of the checkbox bullet (e.g. `AC-2` is the second `- [ ]`); use `"AC-section"` for whole-section findings (missing/empty)
- Description — the problem with this criterion → why it's not testable / not observable → suggested rewrite (≤3 lines)
