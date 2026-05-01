---
name: review-loop
description: Post-implementation review loop: /simplify → parallel /codex-review + /gemini-review (loop) → /e2e-verify (loop). Use after completing a code change. Trigger: "review-loop", "/review-loop".
allowed-tools: Bash, Read, Skill
---

# Review Loop

Orchestrates the full post-implementation review cycle. Pure orchestration — every step delegates to an existing skill.

## Flow

1. **Simplify (once)** — invoke `/simplify`.
2. **Review loop** — repeat until parent decides remaining issues aren't worth fixing:
   a. Invoke `/codex-review` and `/gemini-review` **in parallel** (single message, two Skill calls).
   b. Read both structured outputs. For each issue, decide: **fix** (apply edit in main session), or **add to won't-fix list** (parent's working memory; not persisted, not sent back to reviewers).
   c. If any issue was fixed → loop back to (a).
   d. If all remaining issues are in won't-fix list → exit review loop, proceed to step 3.
3. **E2E verify loop** — repeat until passing:
   a. Detect whether `e2e-verify` is applicable: check for a `Makefile` with an `up` target via `grep -E '^up:' Makefile 2>/dev/null`. If absent → skip step 3 entirely, print `review-loop: e2e-verify skipped (no \`make up\` target)`, exit successfully.
   b. Invoke `/e2e-verify`.
   c. If passing → exit successfully.
   d. If failing → parent fixes the failure in main session, then **return to step 2a** (one more review pass before re-running e2e). If parent judges the failure not worth fixing → exit.

## Rules

- **Manual only.** Never invoke this skill automatically.
- **Parent does the fixing.** This skill never edits code. It only orchestrates other skills and surfaces their output.
- **Parallel reviews.** `/codex-review` and `/gemini-review` MUST be dispatched in a single message containing two Skill tool calls, not sequentially.
- **Won't-fix list is ephemeral.** Lives only in the parent's working memory for this loop invocation. Not written to disk. Not sent to reviewers (no point — they don't remember between calls).
- **Exit conditions** (any one):
  - All review issues are in won't-fix and e2e passes (or is skipped).
  - Parent judges remaining e2e failure not worth fixing.
- **Simplify runs exactly once**, at the start. Subsequent iterations are pure review-driven fixes.
