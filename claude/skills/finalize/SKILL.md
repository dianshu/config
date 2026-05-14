---
name: finalize
description: Post-implementation finalization: /simplify → parallel /codex-review + /gemini-review (loop) → /e2e-verify (loop) → testing-rules self-check → full UT+E2E → summary. Use after completing a code change. Trigger: "finalize", "/finalize".
allowed-tools: Bash, Read, Skill
---

# Finalize

Orchestrates the full post-implementation finalization cycle: review, verify, self-check against testing rules, run full tests, and summarize. Pure orchestration — every step delegates to an existing skill or runs a user-provided command.

## Flow

1. **Simplify (once)** — invoke `/simplify`.
2. **Review loop** — repeat until the Progression Check (below) signals exit:
   a. Invoke `/codex-review` and `/gemini-review` **in parallel** (single message, two Skill calls).
   b. Read both structured outputs. For each issue, decide: **fix** (apply edit in main session), or **add to won't-fix list** (parent's working memory; not persisted, not sent back to reviewers).
   c. Run the **Progression Check** (below). If exit signal → proceed to step 3. Otherwise loop back to (a).
3. **E2E verify loop** — repeat until passing:
   a. Detect whether `e2e-verify` is applicable: check for a `Makefile` with an `up` target via `grep -E '^up:' Makefile 2>/dev/null`. If absent → skip step 3, print `finalize: e2e-verify skipped (no \`make up\` target)`, proceed to step 4.
   b. Invoke `/e2e-verify`.
   c. If passing → proceed to step 4.
   d. If failing → parent fixes the failure in main session, then **return to step 2a** (one more review pass before re-running e2e). If parent judges the failure not worth fixing → record as won't-fix and proceed to step 4.
4. **Testing-rules self-check**:
   a. Re-read `~/.claude/rules/testing.md` and check every test file changed in this session against it.
   b. Each violation → fix in main session, then **return to step 2a** (one more review pass). Track count for the summary.
   c. No violations → proceed to step 5.
5. **Full test suite**:
   a. Look in the current session context for explicit commands the user has provided for running the full unit-test suite and the full E2E suite (these are typically injected by the user as part of the conversation context, not read from any file).
   b. For each of UT and E2E: if a command is present → run it; if not → mark as `skipped (no command in session context)` and continue. **Do not ask the user.**
   c. On failure → parent fixes in main session → **return to step 2a**.
   d. On pass / skipped → proceed to step 6.
6. **Summary** — print a single block:
   - Review rounds completed: N
   - Won't-fix items: list (or "none")
   - Testing-rules self-check: clean | fixed N violations
   - e2e-verify (step 3): pass | fail (won't-fix) | skipped
   - Full UT (step 5): pass | fail (won't-fix) | skipped (no command in session context)
   - Full E2E (step 5): pass | fail (won't-fix) | skipped (no command in session context)

## Rules

- **Parent does the fixing.** This skill never edits code. It only orchestrates other skills and surfaces their output.
- **Parallel reviews.** `/codex-review` and `/gemini-review` MUST be dispatched in a single message containing two Skill tool calls, not sequentially.
- **Won't-fix list is ephemeral.** Lives only in the parent's working memory for this loop invocation. Not written to disk. Not sent to reviewers (no point — they don't remember between calls).
- **Exit conditions** (any one):
  - Steps 1–5 all complete: every review issue fixed-or-won't-fix; e2e-verify pass-or-won't-fix-or-skipped; testing-rules self-check clean (after any fixes); full UT and full E2E each pass-or-skipped-or-won't-fix.
  - Parent judges a remaining failure not worth fixing (logged in summary).
- **Simplify runs exactly once**, at the start. Subsequent iterations are pure review-driven fixes.
- **Steps 2, 3, 4, 5 may re-run multiple times.** Any "return to step 2a" replays Step 2 → 3 → 4 → 5 in order. Convergence is governed by Step 2's Progression Check and the natural decrease in violations/failures per round. If a fix repeatedly fails to converge, parent marks it won't-fix and exits via the second exit condition.

## Progression Check (3-of-5)

After each review round, evaluate these 5 criteria. **Exit the review loop when ≥3 are satisfied.** Adapted from prd-debate's debate-progression algorithm.

1. **Coverage** — Every actionable issue from the prior round was either fixed or added to won't-fix. No issue left unaddressed.
2. **Diminishing severity** — In the latest round, **structural/blocker** issues (correctness bugs, security, missing requirements) make up <20% of total findings. The rest are nits/style/minor.
3. **Diff stability** — The fixes in the most recent round did not introduce a new direction or rewrite (compare to prior round's diff scope). Cosmetic/local fixes only.
4. **Minimum rounds** — At least **1 full review round** has completed (i.e. don't exit on simplify alone).
5. **Reviewer acknowledgment** — Both `/codex-review` and `/gemini-review` returned no blocker-severity findings in the latest round. (Their nits/suggestions don't disqualify.)

If <3 satisfied AND parent judges remaining issues low-value → still exit, but log which criterion was missing in the final summary so the user can override.
