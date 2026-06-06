---
name: review-with-agent
description: Multi-lens adversarial code review using external AI CLIs (Codex or opencode). Shared workflow invoked by /codex-review and /opencode-review. Supports both code review (working-tree diffs) and plan review (markdown files). Not for reviewing already-committed code.
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
    mode: 'code' | 'plan',
    backend: 'codex' | 'opencode',
    planPath: '<path>',           // plan mode, when reviewing a file on disk
    planContent: '<inline text>', // plan mode, when reviewing in-conversation plan
  },
})
```

If `mode === 'plan'` and neither `planPath` nor `planContent` is provided, the
workflow aborts. The calling backend skill is responsible for resolving the
ambiguity (asking the user, writing in-conversation plans to a tempfile, etc.)
**before** invoking the workflow — workflow scripts cannot prompt the user
mid-run.

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
