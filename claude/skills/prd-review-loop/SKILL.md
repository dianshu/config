---
name: prd-review-loop
description: Pre-approval review loop for PRD/spec markdown files: parallel /codex-review + /gemini-review until clean. Use before presenting a PRD/spec for approval. Trigger: "prd-review-loop", "/prd-review-loop".
allowed-tools: Bash, Read, Skill
---

# PRD Review Loop

Orchestrates dual adversarial review of a PRD or spec file before user approval. Pure orchestration — every step delegates to an existing skill. Parent does any rewriting in the main session.

## Input

The PRD or spec file path. If parent invoked the skill without a path, ask once for it.

## Flow

Repeat until parent decides remaining issues aren't worth changing:

1. Invoke `/codex-review` and `/gemini-review` on the PRD/spec file **in parallel** (single message, two Skill calls).
2. Read both structured outputs. Cross-reference findings — issues flagged by **both** reviewers get priority.
3. For each issue, decide: **revise** (parent edits the PRD/spec in main session), or **add to won't-fix list** (parent's working memory).
4. If any revision was made → loop back to (1).
5. If all remaining issues are in won't-fix list → exit; plan is ready for user approval (ExitPlanMode or spec presentation).

## Rules

- **Manual only.** Never invoke automatically.
- **Parent does the editing.** This skill never modifies the PRD/spec; it only orchestrates reviews and surfaces findings.
- **Parallel reviews.** `/codex-review` and `/gemini-review` MUST be dispatched in a single message containing two Skill tool calls.
- **Won't-fix list is ephemeral.** Lives only in the parent's working memory for this loop invocation. Not persisted, not sent to reviewers.
- **No code-only steps.** Unlike `/review-loop`, there is no `/simplify` or `/e2e-verify` here — PRDs are documents, not running code.
