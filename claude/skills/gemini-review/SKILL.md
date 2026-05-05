---
name: gemini-review
description: Code review using Google Gemini CLI. Use when the user says "gemini review", "review with gemini", "gr", or wants a Gemini-based AI review of uncommitted changes or a plan document. Not for reviewing already-committed code.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Gemini Review

Use the Gemini CLI as the reviewer backend, then execute the workflow in `~/.claude/skills/review-with-agent/SKILL.md`.

## Backend Configuration

Set the following before running the shared workflow:

```bash
PREFLIGHT_CMD='gemini --version 2>/dev/null'
DISPATCH_CMD="gemini -p '' --approval-mode plan --output-format text"
READONLY_DISPATCH_CMD="gemini -p '' --approval-mode plan --output-format text"
PLAN_DISPATCH_CMD="gemini -p '' --approval-mode plan --output-format text"
MODE_LABEL='gemini-adversarial'
NOISE_FILTER='grep -vE "^Ripgrep is not available|^YOLO mode|^Loaded cached credentials|^$|^\[STARTUP\]"'
TMPDIR_PREFIX='gemini-review'
```

Notes:
- All dispatches use `--approval-mode plan` (read-only) — Gemini must not modify the workspace.
- `--output-format text` is required to run non-interactively in background.
- Never override the user's model setting (no `-m`).

## Preflight

Run `PREFLIGHT_CMD`. If it fails (Gemini CLI not installed or not on PATH), abort with an error — do NOT fall back to any other backend.
