---
name: codex-review
description: Code review using OpenAI Codex CLI. Use when the user says "codex review", "review with codex", "get a second opinion", "independent review", "review this plan", "codex review plan", or wants a Codex-based AI review of uncommitted changes or a plan document. Not for reviewing already-committed code.
allowed-tools: Workflow, Bash, Read, AskUserQuestion
---

# Codex Review

Thin wrapper that delegates to the shared `review-with-agent` workflow with
`backend='codex'`.

## Flow

1. **Determine mode** from the user's request:
   - "review changes" / no path → `mode: 'code'`
   - File path provided → `mode: 'plan'`, `planPath: <path>`
   - "review plan" with plan in conversation → `mode: 'plan'`, `planContent: <inline text>`
   - Ambiguous → ask the user via AskUserQuestion BEFORE invoking the workflow
     (the workflow itself cannot prompt mid-run)

2. **Invoke the workflow:**

   ```
   Workflow({
     scriptPath: '~/.claude/skills/review-with-agent/review.workflow.js',
     args: { mode, backend: 'codex', planPath?, planContent? },
   })
   ```

3. **Render the result** — the workflow returns the verdict + findings table.
   Surface it to the user as the review report.

## Notes

- All Codex dispatches use `-s read-only` sandbox (set in the workflow's
  `BACKEND_CONFIG.codex` block) — Codex never modifies the workspace.
- Codex dispatches use per-lens static model assignment via the `LENS_MODEL`
  map in `review.workflow.js`: heavier-reasoning lenses (Architect /
  Integration / Subtractor / Coverer / Coverage / Slicer) go to `gpt-5.5`,
  checklist / pattern-match lenses (Challenger / DevilsAdvocate /
  TestHygiene / Glossarian / DependencyAuditor / Granularity /
  AcceptanceCriteria) go to `gpt-5.4`. Single-call sites fall back to
  `DEFAULT_CODEX_MODEL` (`gpt-5.5`). The split also happens to keep typical
  fan-outs at ~50/50 (3:2 / 2:2 / 3:3 / 2:3 across modes) so the
  concurrent-cap goal is met as a side effect. Edit `LENS_MODEL` to retune.
- Plan mode uses `--skip-git-repo-check --ephemeral` (set in the workflow);
  do NOT use `--uncommitted` (mutually exclusive with custom prompts).
- Preflight (`codex --version`) runs as the first workflow phase; abort with
  an error if Codex CLI is not installed — do NOT fall back to any other
  backend.
