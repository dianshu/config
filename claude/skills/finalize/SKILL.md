---
name: finalize
description: Post-implementation finalization: /code-review → parallel /codex-review + /opencode-review (loop) → /e2e-verify (loop) → testing-rules self-check → full UT+E2E → summary. Use after completing a code change. Trigger: "finalize", "/finalize".
allowed-tools: Bash, Read, Skill
---

# Finalize

Orchestrates the full post-implementation finalization cycle: review, verify, self-check against testing rules, run full tests, and summarize. Pure orchestration — every step delegates to an existing skill or runs a user-provided command.

## Decision: Fix or Won't-Fix

A cross-cutting rule, not a sequential step. Apply to **every issue surfaced** by any Flow step — code review findings, external-reviewer findings, e2e-verify failures, testing-rules violations, full-test failures.

For each issue, parent decides one of:

- **Fix** — parent edits in main session.
- **Won't-fix** — record on the in-memory won't-fix list (parent's working memory only; **ephemeral**: not written to disk, not sent back to reviewers, lost when this `/finalize` invocation ends). Won't-fix items are surfaced in the final Summary.

No third option — every issue gets one of these two labels before the step that surfaced it can be considered "handled". Flow steps below reference this by name: "apply the Fix/Won't-Fix Decision".

## Flow

1. **Code review (once)** — run `~/.claude/scripts/diff-scale.sh` to classify the change, then invoke `/code-review` with the matching effort level. Mapping (one tier above review-with-agent's lens map, since `/code-review` is a single pass without independent lenses to compensate):

   | Scale (script output) | `/code-review` argument |
   |---|---|
   | Light  | `medium` |
   | Medium | `high`   |
   | Heavy  | `xhigh`  |

   Apply the **Fix/Won't-Fix Decision** to each finding.

   If the script exits non-zero (not a git repo / nothing to review), skip this step and proceed to step 2.

   **MANDATORY HAND-OFF:** Step 1's output (findings list or empty `[]`) does NOT determine whether Step 2 runs — Step 2 ALWAYS runs next, regardless of how many findings were fixed. Step 1 is an internal multi-lens pass; Step 2 is independent external reviewers (`/codex-review` + `/opencode-review`). Empty Step 1 findings are NOT an exit condition — only the Progression Check inside Step 2 can exit the review loop. If you find yourself writing a summary or stopping after Step 1, you are doing it wrong: immediately dispatch Step 2a.
2. **Review loop** — repeat until the Progression Check (below) signals exit:
   a. Invoke `/codex-review` and `/opencode-review` **in parallel** (single message, two Skill calls).
   b. Read both structured outputs. Apply the **Fix/Won't-Fix Decision** to every issue.
   c. Run the **Progression Check** via the workflow at `~/.claude/skills/finalize/progression-check.workflow.js`:

      ```
      Workflow({
        scriptPath: '~/.claude/skills/finalize/progression-check.workflow.js',
        args: {
          codexOutput: <raw /codex-review output from this round>,
          opencodeOutput: <raw /opencode-review output from this round>,
          roundNum: <1-based round counter>,
          priorRoundFindingCount: <merged findings count from prior round, or null on round 1>,
        },
      })
      ```

      The workflow returns `{verdict: 'EXIT' | 'CONTINUE', satisfied, total, criteria, mergedFindings, byFile, stats, parentMustConfirm}`:
      - `criteria.coverage` is **always null** — the workflow cannot judge whether you addressed every prior-round issue. Confirm it yourself before re-running.
      - `verdict === 'EXIT'` AND coverage confirmed → proceed to step 3.
      - Otherwise → use `byFile` to drive your Fix/Won't-Fix Decisions (one issue at a time), then loop back to (a).
      - Remember `stats.totalFindings` for the next round's `priorRoundFindingCount`.
3. **E2E verify loop** — repeat until passing:
   a. Detect whether `e2e-verify` is applicable: check for a `Makefile` with an `up` target via `grep -E '^up:' Makefile 2>/dev/null`. If absent → skip step 3, print `finalize: e2e-verify skipped (no \`make up\` target)`, proceed to step 4.
   b. Invoke `/e2e-verify`.
   c. If passing → proceed to step 4.
   d. If failing → apply the **Fix/Won't-Fix Decision** to the failure. If fix → parent edits in main session, then **return to step 2a** (one more review pass before re-running e2e). If won't-fix → proceed to step 4.
4. **Testing-rules self-check**:
   a. Run the audit via the workflow at `~/.claude/skills/finalize/testing-rules-audit.workflow.js`:

      ```
      Workflow({scriptPath: '~/.claude/skills/finalize/testing-rules-audit.workflow.js'})
      ```

      The workflow enumerates every test file changed in this session, then in parallel
      (one agent per file) audits each against `~/.claude/injected-rules/testing.md` and
      returns `{violations, fileCount, byFile, violationsList}`. Each `byFile` entry has
      `{file, changeSummary, applicableRules, verdict, justification}` — surface the
      table to the user as the per-file evidence requirement (a single "looks clean"
      sentence is NOT acceptable; this workflow's output IS the enumeration).
   b. Apply the **Fix/Won't-Fix Decision** to each violation. If fix → parent edits in main session, then **return to step 2a** (one more review pass). Track fix count for the summary.
   c. No violations (or all won't-fix) → proceed to step 5.
5. **Full test suite**:
   a. Resolve the UT and E2E commands by checking, in order:
      1. Explicit commands the user provided in the current session context.
      2. Project scripts under `.claude/scripts/` — e.g. `test.sh` for UT, `e2e.sh` for E2E. Use these as-is if executable.
      3. `Makefile` targets — `make test` for UT, `make e2e` (or `make test-e2e`) for E2E.
      4. `package.json` `scripts.test` / `scripts.e2e` (run via `npm test` / `npm run e2e`).
   b. For each of UT and E2E: if a command is resolved → run it; if not → mark as `skipped (no command found)` and continue. **Do not ask the user.**
   c. On failure → apply the **Fix/Won't-Fix Decision**. If fix → parent edits in main session, then **return to step 2a**. If won't-fix → proceed to step 6.
   d. On pass / skipped → proceed to step 6.
6. **Summary** — output the summary as the **final, standalone assistant message** (no other content before or after — no "next steps", no "ready to push", no file lists). Prefix each line with a status emoji so the reader can scan outcomes at a glance.

   Emoji legend (pick per line based on the actual outcome):
   - ✅ pass / clean / "none" / no issues
   - 🔧 fixed N violations (started dirty, ended clean — signals work was done)
   - ⚠️ won't-fix item(s) present, or fail-but-accepted-as-won't-fix
   - ⏭️ skipped (no command found, or step not applicable)
   - 🔄 informational round counter (no pass/fail concept)

   Lines (substitute the right emoji from the legend, do NOT print "✅ or ⚠️"):
   - 🔄 Review rounds completed: N
   - {✅|⚠️} Won't-fix items: list (or "none")
   - {✅|🔧} Testing-rules self-check: clean | fixed N violations
   - {✅|⚠️|⏭️} e2e-verify (step 3): pass | fail (won't-fix) | skipped
   - {✅|⚠️|⏭️} Full UT (step 5): pass | fail (won't-fix) | skipped (no command found)
   - {✅|⚠️|⏭️} Full E2E (step 5): pass | fail (won't-fix) | skipped (no command found)

## Rules

- **Parent does the fixing.** This skill never edits code. It only orchestrates other skills and surfaces their output.
- **Parallel reviews.** `/codex-review` and `/opencode-review` MUST be dispatched in a single message containing two Skill tool calls, not sequentially.
- **Exit conditions** (any one):
  - Steps 1–5 all complete: every issue from any step is fixed-or-won't-fix; e2e-verify pass-or-won't-fix-or-skipped; testing-rules self-check clean (after any fixes); full UT and full E2E each pass-or-skipped-or-won't-fix.
  - Parent judges a remaining failure not worth fixing (logged in summary).
- **Code review runs exactly once**, at the start (with auto-selected effort). Subsequent iterations are pure review-driven fixes via `/codex-review` + `/opencode-review`.
- **Steps 2, 3, 4, 5 may re-run multiple times.** Any "return to step 2a" replays Step 2 → 3 → 4 → 5 in order. Convergence is governed by Step 2's Progression Check and the natural decrease in violations/failures per round. If a fix repeatedly fails to converge, parent marks it won't-fix (via the Fix/Won't-Fix Decision) and exits via the second exit condition.

## Progression Check (3-of-5)

The 5-of-3 progression criteria are computed deterministically by
`~/.claude/skills/finalize/progression-check.workflow.js`. The workflow parses both
reviewer outputs into structured findings (LLM, fan-out + retry), merges/dedups
across reviewers, then scores 4 of the 5 criteria as pure code:

1. **Coverage** — **your job** (workflow returns `null`). Confirm every prior-round
   issue was either fixed or added to won't-fix.
2. **Diminishing severity** — auto. New `Blocking` make up <20% of new findings
   (or `newFindings.length === 0`, which counts as satisfied).
3. **Diff stability** — auto. Finding count did not increase by more than
   `max(1, floor(priorRoundCount * 0.2))`. `null` (not evaluated) on round 1.
4. **Minimum rounds** — auto. `roundNum >= 1`.
5. **Reviewer acknowledgment** — auto. Zero New `Blocking` findings across both
   reviewers in the merged set.

Exit when `satisfied >= 3` of the auto-evaluable criteria AND coverage is
confirmed. If `<3` satisfied but parent judges remaining issues low-value →
still exit, log which criterion was missing in the final summary so the user
can override.
