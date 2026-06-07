# Issues Slicer Lens

Enforce the vertical-slice / tracer-bullet rule: every issue must cut end-to-end through ALL integration layers it touches, NOT a horizontal slice of one layer.

## Primary dimensions covered
- VERTICAL_SLICE (primary)
- GRANULARITY (a slice that's purely one layer is also wrong-sized)

## Method
1. Read every pending issue file (`NN-*.md`, no `done-` prefix) under the feature's `issues/` directory.
2. For each issue, identify which layers/components it claims to touch (schema, API, server logic, transport, client/UI, tests).
3. Judge: is the work demoable or end-to-end verifiable on its own? Or does it produce a half-finished layer that requires sibling issues before any user-observable behavior changes?

## Checklist — per issue
- **All-backend slice**: issue only modifies schema / DB / API but produces no user-observable change → Blocking (cite the missing client/UI/test boundary)
- **All-frontend slice**: issue wires up UI but the data path doesn't exist yet → Blocking unless explicitly stubbed end-to-end (mock server, fake data)
- **Schema-only slice**: pure schema migration with no consumer change in the same issue → Required (justify why it ships alone)
- **Test-only slice**: a "write tests for X" issue with no production code touched → Required unless the issue covers retrofitting tests for already-shipped code
- **No demo path**: nothing in `## What to build` or `## Acceptance criteria` is externally observable → Blocking
- **Layer-only granularity in `## What to build`**: phrasing like "implement the data layer" / "build the API endpoints" without mentioning the consumer → Required
- **Hidden vertical**: issue claims to be vertical but every acceptance criterion is internal (file written, function defined, schema applied) → Required (rewrite criteria as observable behavior)

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
- Category — VERTICAL_SLICE (primary) or GRANULARITY (for layer-only granularity findings)
- IssueFile — the issue filename relative to `issuesDir`, e.g. `03-balance-fetch.md`
- Anchor — `"Title"` or `"What to build"` or `"AC-<n>"` (the specific acceptance-criterion bullet ordinal) — stable for cross-round dedup
- Description — why this isn't a vertical slice → user-visible behavior that's missing → suggested rewrite or merge target (≤3 lines)
