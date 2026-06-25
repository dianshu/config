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
- Codex dispatches use round-robin model rotation across `CODEX_MODELS`
  (default `['gpt-5.5', 'gpt-5.4']`) per parallel lens index, splitting load
  50/50 within a fan-out so neither model hits its concurrent-request cap.
  Edit `CODEX_MODELS` in `review.workflow.js` to change the pool.
- Plan mode uses `--skip-git-repo-check --ephemeral` (set in the workflow);
  do NOT use `--uncommitted` (mutually exclusive with custom prompts).
- Preflight (`codex --version`) runs as the first workflow phase; abort with
  an error if Codex CLI is not installed — do NOT fall back to any other
  backend.
