---
name: review-loop
description: Post-implementation review loop: /simplify → parallel /codex-review + /gemini-review (loop) → /e2e-verify (loop). Use after completing a code change. Trigger: "review-loop", "/review-loop".
allowed-tools: Bash, Read, Skill
---

# Review Loop

Orchestrates the full post-implementation review cycle. Pure orchestration — every step delegates to an existing skill.

## Flow

1. **Simplify (once)** — invoke `/simplify`.
2. **Review loop** — repeat until the Progression Check (below) signals exit:
   a. Invoke `/codex-review` and `/gemini-review` **in parallel** (single message, two Skill calls).
   b. Read both structured outputs. For each issue, decide: **fix** (apply edit in main session), or **add to won't-fix list** (parent's working memory; not persisted, not sent back to reviewers).
   c. Run the **Progression Check** (see below). If exit signal → proceed to step 3. Otherwise loop back to (a).
3. **E2E verify loop** — repeat until passing:
   a. Detect whether `e2e-verify` is applicable: check for a `Makefile` with an `up` target via `grep -E '^up:' Makefile 2>/dev/null`. If absent → skip step 3 entirely, print `review-loop: e2e-verify skipped (no \`make up\` target)`, exit successfully.
   b. Invoke `/e2e-verify`.
   c. If passing → exit successfully.
   d. If failing → parent fixes the failure in main session, then **return to step 2a** (one more review pass before re-running e2e). If parent judges the failure not worth fixing → exit.

## Rules

- **Parent does the fixing.** This skill never edits code. It only orchestrates other skills and surfaces their output.
- **Parallel reviews.** `/codex-review` and `/gemini-review` MUST be dispatched in a single message containing two Skill tool calls, not sequentially.
- **Won't-fix list is ephemeral.** Lives only in the parent's working memory for this loop invocation. Not written to disk. Not sent to reviewers (no point — they don't remember between calls).
- **Exit conditions** (any one):
  - All review issues are in won't-fix and e2e passes (or is skipped).
  - Parent judges remaining e2e failure not worth fixing.
- **Simplify runs exactly once**, at the start. Subsequent iterations are pure review-driven fixes.

## Progression Check (3-of-5)

After each review round, evaluate these 5 criteria. **Exit the review loop when ≥3 are satisfied.** Adapted from prd-debate's debate-progression algorithm.

1. **Coverage** — Every actionable issue from the prior round was either fixed or added to won't-fix. No issue left unaddressed.
2. **Diminishing severity** — In the latest round, **structural/blocker** issues (correctness bugs, security, missing requirements) make up <20% of total findings. The rest are nits/style/minor.
3. **Diff stability** — The fixes in the most recent round did not introduce a new direction or rewrite (compare to prior round's diff scope). Cosmetic/local fixes only.
4. **Minimum rounds** — At least **1 full review round** has completed (i.e. don't exit on simplify alone).
5. **Reviewer acknowledgment** — Both `/codex-review` and `/gemini-review` returned no blocker-severity findings in the latest round. (Their nits/suggestions don't disqualify.)

If <3 satisfied AND parent judges remaining issues low-value → still exit, but log which criterion was missing in the final summary so the user can override.
