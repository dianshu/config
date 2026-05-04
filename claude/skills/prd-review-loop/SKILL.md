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

Repeat until the Progression Check (below) signals exit:

1. Invoke `/codex-review` and `/gemini-review` on the PRD/spec file **in parallel** (single message, two Skill calls).
2. Read both structured outputs. Cross-reference findings — issues flagged by **both** reviewers get priority.
3. For each issue, decide: **revise** (parent edits the PRD/spec in main session), or **add to won't-fix list** (parent's working memory).
4. Run the **Progression Check**. If exit signal → plan is ready for user approval (ExitPlanMode or spec presentation). Otherwise loop back to (1).

## Rules

- **Manual only.** Never invoke automatically.
- **Parent does the editing.** This skill never modifies the PRD/spec; it only orchestrates reviews and surfaces findings.
- **Parallel reviews.** `/codex-review` and `/gemini-review` MUST be dispatched in a single message containing two Skill tool calls.
- **Won't-fix list is ephemeral.** Lives only in the parent's working memory for this loop invocation. Not persisted, not sent to reviewers.
- **No code-only steps.** Unlike `/review-loop`, there is no `/simplify` or `/e2e-verify` here — PRDs are documents, not running code.

## Progression Check (3-of-5)

After each review round, evaluate these 5 criteria. **Exit when ≥3 are satisfied.** Adapted from prd-debate's debate-progression algorithm.

1. **Coverage** — Every actionable issue from the prior round was addressed (revised or moved to won't-fix).
2. **Diminishing severity** — In the latest round, **structural** issues (missing requirement, contradicted decision, ambiguous scope, unspecified edge case) make up <20% of total findings. The rest are wording/clarity nits.
3. **Position stability** — The PRD's core decisions/scope/priorities did not shift in the most recent revision. Only refinements, no rewrites.
4. **Minimum rounds** — At least **2 review rounds** completed (PRDs benefit from a second pass to catch what the first revision introduced).
5. **Reviewer acknowledgment** — Both reviewers returned no structural blocker findings in the latest round.

If <3 satisfied AND parent judges remaining issues are user-decisions (not defects) → still exit, but flag them in the summary so the user can decide before approval.
