---
name: opencode-review
description: Code review using the opencode CLI with gemini-3.1-pro via the local proxy. Use when the user says "opencode review", "review with opencode", "ocr", or wants an opencode/Gemini-based AI review of uncommitted changes or a plan document. Not for reviewing already-committed code.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# OpenCode Review

Use the `opencode` CLI (with the `review-readonly` agent → gemini-3.1-pro via local proxy) as the reviewer backend, then execute the workflow in `~/.claude/skills/review-with-agent/SKILL.md`.

## Backend Configuration

Set the following before running the shared workflow:

```bash
PREFLIGHT_CMD='opencode --version 2>/dev/null && test -f "$HOME/.config/opencode/opencode.json"'

# DISPATCH_CMD reads the prompt from stdin (review-with-agent pipes via heredoc),
# runs the read-only agent, and uses `jq` to extract just the final assistant
# text from the JSON event stream. The output is already clean — no banner noise
# to filter — so NOISE_FILTER is a no-op pass-through.
#
# `--format json` emits one JSON object per line; `text` events carry the
# assistant's reply. The Integration lens triggers real `tool_use` events
# (read/grep/glob remain allowed by default); we ignore those and take the
# last assistant `text` part as the verdict.
DISPATCH_CMD='opencode run --agent review-readonly --format json 2>/dev/null | jq -rs "[.[] | select(.type==\"text\")] | last | .part.text // empty"'
READONLY_DISPATCH_CMD="$DISPATCH_CMD"
PLAN_DISPATCH_CMD="$DISPATCH_CMD"
MODE_LABEL='opencode-gemini-3.1-pro'
NOISE_FILTER='cat'
TMPDIR_PREFIX='opencode-review'
```

Notes:
- All dispatches use the `review-readonly` agent defined in `~/.config/opencode/opencode.json`, which sets `permission.edit/bash/write/webfetch: deny`. `read`/`grep`/`glob` remain `allow` by default (required for the Integration lens).
- Model and provider (`proxy/gemini-3.1-pro-preview`, baseURL `http://localhost:29427/v1`) are pinned in the agent config — never pass `-m` here.
- The `jq` pipeline extracts the final assistant text; if the model returns nothing the result is empty, which the shared workflow's retry/failure path then handles.

## Preflight

Run `PREFLIGHT_CMD`. If `opencode` is not on PATH **or** `~/.config/opencode/opencode.json` is missing, abort with an error pointing the user at this skill's setup — do NOT fall back to another backend.

Also requires `jq` on PATH (used by `DISPATCH_CMD`). If absent, abort with `opencode-review: jq is required`.

## Then

Hand off to `~/.claude/skills/review-with-agent/SKILL.md` and let it drive the rest (mode detection, diff prep, lens dispatch, aggregation).
