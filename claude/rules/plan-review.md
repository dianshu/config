## Plan Pre-Review

Before presenting a plan/spec for user approval (i.e., before calling ExitPlanMode or presenting a spec from brainstorming), loop until clean:

1. Run `/codex-review` and `/gemini-review` on the plan/spec file in parallel.
2. Cross-reference findings — issues flagged by both reviewers get priority attention.
3. If either review identifies issues worth addressing, update the plan/spec and repeat from (1).
4. Stop when both reviews find no issues worth changing, then proceed to user review.
