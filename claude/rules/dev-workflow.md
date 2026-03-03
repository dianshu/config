Follow this workflow when writing code, implementing features, or fixing bugs:

1. **Before implementation**: Use the /test-driven-development skill. Always write tests first.
2. **After implementation**, loop until clean:
   a. Use the /simplify skill (via the Skill tool, not the code-simplifier agent) to review changed code for reuse, quality, and efficiency.
   b. Use the /codex-review skill for an independent AI review of the changes.
   c. If either found issues, fix them and repeat from (a). Stop when both find no issues.
