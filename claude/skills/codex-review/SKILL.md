---
name: codex-review
description: Code review using OpenAI Codex CLI. Use when the user says "codex review", "review with codex", "get a second opinion", "independent review", "review this plan", "codex review plan", or wants a Codex-based AI review of uncommitted changes or a plan document. Not for reviewing already-committed code.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Codex Review

Use the Codex CLI as the reviewer backend, then execute the workflow in `~/.claude/skills/review-with-agent/SKILL.md`.

## Backend Configuration

Set the following before running the shared workflow:

```bash
PREFLIGHT_CMD='codex --version 2>/dev/null'
DISPATCH_CMD='codex exec - --cd "$(pwd)" --ephemeral -s read-only'
READONLY_DISPATCH_CMD='codex exec - --cd "$(pwd)" --ephemeral -s read-only'
PLAN_DISPATCH_CMD='codex exec - --skip-git-repo-check --ephemeral -s read-only'
MODE_LABEL='codex-adversarial'
NOISE_FILTER='grep -vE "^OpenAI Codex|^----|^workdir:|^model:|^provider:|^approval:|^sandbox:|^reasoning|^session id:|^$"'
TMPDIR_PREFIX='codex-review'
```

Notes:
- All dispatches use `-s read-only` sandbox — Codex must not modify the workspace.
- Never override the user's model setting (no `--model`).
- Plan mode requires `--skip-git-repo-check --ephemeral`; do NOT use `--uncommitted` (mutually exclusive with custom prompts).

## Preflight

Run `PREFLIGHT_CMD`. If it fails (Codex CLI not installed or not on PATH), abort with an error — do NOT fall back to any other backend.
