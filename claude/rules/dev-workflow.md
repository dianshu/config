Follow this workflow when writing code, implementing features, or fixing bugs:

1. **Before implementation**: Use the /superpowers:test-driven-development skill. Always write tests first.

<HARD-GATE>
POST-IMPLEMENTATION LOOP — MANDATORY, NO EXCEPTIONS

You MUST run the full loop below after EVERY implementation task, before reporting completion to the user. This applies regardless of which skill initiated the work (brainstorming, debugging, plan mode, direct request — all paths). Do NOT reply to the user with "done", "complete", "implemented", or any completion claim until every step below has executed in the current session. Skipping this loop is a workflow violation.
</HARD-GATE>

2. **After implementation**, loop until clean:
   a. Use the /simplify skill (via the Skill tool, not the code-simplifier agent) to review changed code for reuse, quality, and efficiency.
   b. Run /codex-review and /gemini-review in parallel for independent AI reviews. Cross-reference findings — issues flagged by both reviewers get priority attention.
   c. Use the /e2e-verify skill for end-to-end verification.
   d. Use the /superpowers:verification-before-completion skill. Run verification commands and confirm output before asserting work is done.
   e. If any step found issues, fix them and repeat from (a). Stop when all steps find no issues.
