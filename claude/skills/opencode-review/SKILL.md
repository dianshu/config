---
name: opencode-review
description: Code review using the opencode CLI with gemini-3.1-pro via the local proxy. Use when the user says "opencode review", "review with opencode", "ocr", or wants an opencode/Gemini-based AI review of uncommitted changes or a plan document. Not for reviewing already-committed code.
allowed-tools: Workflow, Bash, Read, AskUserQuestion
---

# OpenCode Review

Thin wrapper that delegates to the shared `review-with-agent` workflow with
`backend='opencode'`.

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
     args: { mode, backend: 'opencode', planPath?, planContent? },
   })
   ```

3. **Render the result** — the workflow returns the verdict + findings table.
   Surface it to the user as the review report.

## Notes

- All dispatches use the `review-readonly` agent defined in
  `~/.config/opencode/opencode.json` (set in the workflow's
  `BACKEND_CONFIG.opencode` block). That agent pins
  `permission.edit/bash/write/webfetch: deny`; `read`/`grep`/`glob` remain
  allowed (required for the Integration lens).
- Model and provider (`proxy/gemini-3.1-pro-preview`, baseURL
  `http://localhost:29427/v1`) are pinned in the agent config — never pass `-m`.
- The dispatch uses `jq` to extract the final assistant text from the JSON
  event stream. Preflight (`opencode --version && test -f
  ~/.config/opencode/opencode.json && command -v jq`) runs as the first
  workflow phase; abort with an error if any prerequisite is missing — do NOT
  fall back to any other backend.
