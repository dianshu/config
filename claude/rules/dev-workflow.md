Follow this workflow when writing code, implementing features, or fixing bugs:

1. **Bug investigation gate** (bug fixes only): Reproduce the bug first — before reading code, spawning Explore agents, or forming hypotheses.
   - Check if the project root has a Makefile with an `up` target
   - If yes, run `make up` in the background (Bash tool with `run_in_background: true`). Note the task ID and output file path — use `Read` on the output file to check service logs when debugging.
   - Reproduce the bug through the actual UI or API:
     - Frontend: Chrome MCP — open the page, take screenshots, interact with elements
     - Backend: `curl` — call API endpoints and check responses
   - Only after observing the failure firsthand, proceed to code analysis
   - Reading code tells you WHERE to look. Only running the system tells you WHAT the bug actually is.
   - This gate applies to `/superpowers:systematic-debugging` Phase 1 step 2 ("Reproduce Consistently") and Phase 4 step 3 ("Verify Fix").

2. **Before implementation**: Use the /superpowers:test-driven-development skill. Always write tests first.

3. **After implementation**, loop until clean:
   a. Use the /simplify skill (via the Skill tool, not the code-simplifier agent) to review changed code for reuse, quality, and efficiency.
   b. Run /codex-review and /gemini-review in parallel for independent AI reviews. Cross-reference findings — issues flagged by both reviewers get priority attention.
   c. Use the /e2e-verify skill for end-to-end verification.
   d. Use the /superpowers:verification-before-completion skill. Run verification commands and confirm output before asserting work is done.
   e. If any step found issues, fix them and repeat from (a). Stop when all steps find no issues.
