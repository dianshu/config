---
name: review-with-agent
description: Multi-lens adversarial code review using external AI CLIs (Codex or opencode). Shared workflow invoked by /codex-review and /opencode-review for code review, by /prd-review-loop for PRD review, by /issues-review-loop for issue-set review. Supports code mode (working-tree diffs), plan mode (implementation-plan markdown), prd mode (PRD documents with 8-dimension checklist), and issues mode (issue-set with 5-lens fan-out + deterministic Blocked-by parser preflight). Not for reviewing already-committed code.
allowed-tools: Workflow, Bash, Read
---

# Review with Agent (Workflow Form)

This skill is the shared backend for `/codex-review` and `/opencode-review`. It is
**not invoked directly** — the two backend skills above call its workflow with
their respective `backend` arg.

## Architecture

```
/codex-review or /opencode-review  →  Workflow(review.workflow.js, {backend, mode, ...})
                                           ↓
                                  preflight → prep-diff → intent
                                           ↓
                                  parallel: N lens reviewers + red-line scan
                                           ↓
                                  merge findings → verify [New] Required/Blocking
                                           ↓
                                  compute verdict (pure code) → summary
```

The workflow lives at `~/.claude/skills/review-with-agent/review.workflow.js`.
Per-lens prompts live under `~/.claude/skills/review-with-agent/lenses/<Lens>.md`.
Diff preparation is delegated to `~/.claude/scripts/review-prep-diff.sh`.

## Invocation

```
Workflow({
  scriptPath: '~/.claude/skills/review-with-agent/review.workflow.js',
  args: {
    mode: 'code' | 'plan' | 'prd' | 'issues',
    backend: 'codex' | 'opencode',
    // code mode: no extra args
    // plan mode (implementation plan review):
    planPath: '<path>',           // when reviewing a file on disk
    planContent: '<inline text>', // when reviewing in-conversation plan
    // prd mode (PRD review with 8-dim checklist):
    prdPath: '<path>',            // when reviewing a PRD file on disk
    prdContent: '<inline text>',  // when reviewing in-conversation PRD draft
    // issues mode (issue-set review with 5-lens fan-out + parser preflight):
    issuesDir: '<path>',          // directory containing pending NN-*.md issue files
    contextFiles: [               // optional project-context cross-check (P0-2)
      { path, label, content }    // ADR / GLOSSARY / GRILLCOMMITMENTS / sibling-PRD
                                  // for issues mode: PARENT_PRD (required by Coverage lens)
    ],
    wontfixLedger: [              // optional already-decided exclusions (P1-6)
      { id, severity, source, rationale, decidedRoundN }
    ],
    lensRoster: [                 // optional — opt into PRD lens fan-out (P1-4)
      'Architect', 'Challenger', 'DevilsAdvocate',
      'Subtractor', 'Glossarian', 'Coverer'
                                  // for issues mode default:
                                  //   ['Slicer', 'DependencyAuditor', 'Granularity',
                                  //    'AcceptanceCriteria', 'Coverage']
                                  // Coverage auto-drops when no PARENT_PRD in contextFiles
    ],
  },
})
```

If `mode === 'plan'` and neither `planPath` nor `planContent` is provided, the
workflow aborts. If `mode === 'prd'` and neither `prdPath` nor `prdContent`
is provided, the workflow aborts. If `mode === 'issues'` and `issuesDir`
is not provided, the workflow aborts. The calling backend skill is responsible
for resolving the ambiguity (asking the user, writing in-conversation drafts
to a tempfile, etc.) **before** invoking the workflow — workflow scripts
cannot prompt the user mid-run.

## Lens Roster (by scale)

Scale is computed by `~/.claude/scripts/diff-scale.sh` (single source of truth,
shared with `/finalize`):

| Scale  | Condition           | Lenses                                                          |
|--------|---------------------|-----------------------------------------------------------------|
| Light  | <50 lines           | Challenger                                                      |
| Medium | 50–199 lines        | Challenger + Architect + Integration + DevilsAdvocate           |
| Heavy  | 200+ lines OR 3+ dirs | + Subtractor                                                  |

**Test Hygiene** is added at any scale when the diff touches a test file.

**Red-Line scan** always runs in parallel with the lenses (separate agent).

### Issues mode lens roster

Fixed 5-lens roster — no scale tiers (every pending issue is reviewed by every lens):

| Lens                | Primary dimension              | Drops when                     |
|---------------------|--------------------------------|--------------------------------|
| Slicer              | VERTICAL_SLICE                 | never                          |
| DependencyAuditor   | DEPENDENCIES                   | never                          |
| Granularity         | GRANULARITY / SUBTRACTABILITY  | never                          |
| AcceptanceCriteria  | ACCEPTANCE_CRITERIA            | never                          |
| Coverage            | COVERAGE                       | no PARENT_PRD in contextFiles  |

A deterministic `## Blocked by` parser preflight runs BEFORE the lenses (Bash regex, not an LLM lens). Results are surfaced as `parserFailures: [{file, reason, offendingLine}]`. The parser is the same one used by `/run-all-issues` (see `run-all-issues/SKILL.md:40-59`).

## Output Schema

Code mode:

```ts
{
  mode: 'code',
  verdict: 'PASS' | 'CONTESTED' | 'REJECT',
  scale: 'Light' | 'Medium' | 'Heavy',
  modeLabel: string,        // e.g. 'codex-adversarial', 'opencode-gemini-3.1-pro'
  intent: string,           // 1-2 sentence intent statement
  filtered: { excludedCount, largeFileCount, budgetTruncated },
  lensResults: [{ lens, status: 'ok'|'empty'|'failed', findingCount }],
  findings: [{
    severity: 'Blocking'|'Required'|'Suggestion',
    origin: 'New'|'Pre-existing',
    file, line, description,
    lenses: string[],
    verification: { decision: 'Accept'|'Dismiss', rationale, evidence } | null,
  }],
  stats: { total, new, newBlockers, redLineBlockers, multiLensBlockers },
  summary: string,          // one-paragraph conclusion + next steps
}
```

Plan mode:

```ts
{
  mode: 'plan',
  verdict: 'PASS' | 'CONTESTED' | 'REJECT',
  modeLabel: string,
  findings: [{ severity, category, description }],
  blockerCount: number,
}
```

PRD mode (single-pass — default when no lensRoster passed):

```ts
{
  mode: 'prd',
  execPath: 'single-pass',
  verdict: 'PASS' | 'CONTESTED' | 'REJECT',
  modeLabel: string,
  findings: [{
    severity: 'Blocking' | 'Required' | 'Suggestion',
    category: 'USER_STORY_INVEST' | 'ACCEPTANCE_CRITERIA' | 'TRACEABILITY'
            | 'USER_VOCABULARY' | 'INTERNAL_CAUSAL_CHAIN'
            | 'OUT_OF_SCOPE_DISCIPLINE' | 'ASSUMPTIONS_SURFACED'
            | 'NFR_PRESENCE' | 'CONSISTENCY',
    section: string,            // H2 heading or "GLOBAL"
    anchor: string,             // story id / OoS index / quoted phrase (for cross-round dedup)
    description: string,
  }],
  stats: { total, blockers, contextFilesInjected, wontfixEntriesApplied },
}
```

PRD mode (lens fan-out — when args.lensRoster is non-empty):

```ts
{
  mode: 'prd',
  execPath: 'lens-fanout',
  verdict: 'PASS' | 'CONTESTED' | 'REJECT',
  modeLabel: string,
  lensRoster: string[],
  lensResults: [{ lens, findingCount }],
  findings: [{ ...PRD finding, lenses: string[] }],
  stats: { total, blockers, multiLensBlockers, contextFilesInjected, wontfixEntriesApplied },
}
```

PRD verdict rules:
- **single-pass**: 0 Blocking → PASS, 1 → CONTESTED, ≥2 → REJECT
- **lens fan-out**: 0 Blocking → PASS, any Blocking flagged by ≥2 lenses → REJECT, single-lens Blocking → CONTESTED

Issues mode (lens fan-out — always; no single-pass variant):

```ts
{
  mode: 'issues',
  execPath: 'lens-fanout',
  verdict: 'PASS' | 'CONTESTED' | 'REJECT',
  modeLabel: string,
  lensRoster: string[],                 // effective roster after Coverage auto-drop
  issueFilesReviewed: string[],         // basenames of pending NN-*.md files
  parserFailures: [{                    // deterministic — NOT from LLM lenses
    file: string,
    reason: string,
    offendingLine?: string,
  }],
  lensResults: [{ lens, findingCount }],
  findings: [{
    severity: 'Blocking' | 'Required' | 'Suggestion',
    category: 'VERTICAL_SLICE' | 'DEPENDENCIES' | 'GRANULARITY'
            | 'ACCEPTANCE_CRITERIA' | 'COVERAGE' | 'SUBTRACTABILITY',
    issueFile: string,                  // e.g. "03-foo.md" or "GLOBAL"
    anchor: string,                     // e.g. "AC-2", "Blocked-by:NN", "MATRIX-SUMMARY"
    description: string,
    lenses: string[],
  }],
  stats: {
    total, blockers, multiLensBlockers,
    parserFailureCount,                  // mirrors parserFailures.length
    contextFilesInjected, wontfixEntriesApplied,
  },
}
```

Issues verdict rules:
- `parserFailures.length > 0` → **REJECT** regardless of LLM verdict (deterministic hard override)
- 0 Blocking → PASS
- Any Blocking flagged by ≥2 lenses → REJECT
- Single-lens Blocking → CONTESTED

## Verdict Rules

Computed deterministically from `[New]` findings only (Pre-existing findings are
bonus signal, never affect verdict):

- **PASS** — zero New `Blocking`
- **REJECT** — any New red-line violation, OR a New `Blocking` agreed on by ≥2 lenses
- **CONTESTED** — New `Blocking` exists but only one lens flags it

## Severity

- **Blocking** — likely bug, security issue, or red-line violation; must fix before merge
- **Required** — design flaw, broken contract, real correctness concern; should fix
- **Suggestion** — style, taste, minor cleanup

## Backend Configuration

The two backend dispatch profiles (codex, opencode) are defined as a `BACKEND_CONFIG`
object at the top of `review.workflow.js`. To change preflight checks, dispatch
commands, or noise filters, edit that file — not env vars in `/codex-review` or
`/opencode-review`.

## What This Skill Does NOT Contain

- Per-lens prompts → see `lenses/<Lens>.md` (6 files)
- Diff preparation → see `~/.claude/scripts/review-prep-diff.sh`
- Scale thresholds → see `~/.claude/scripts/diff-scale.sh`
- Backend dispatch commands → see `BACKEND_CONFIG` in `review.workflow.js`

The deprecated bash-orchestrated SKILL.md is preserved at `SKILL.md.bak` during
the 2-week observation period after rollout. Delete after.
