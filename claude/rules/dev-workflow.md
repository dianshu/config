Follow this workflow when writing code, implementing features, or fixing bugs.

**Scope exclusion:** Pure documentation/config changes (md/txt/yml/json/toml,
CLAUDE.md, rules/, .claude/, settings) generally do not require the loop.
The Codex-driven Stop gate makes the final call — it has final authority.

1. **Before implementation**: Use the /tdd skill. Always write tests first.

2. **After implementation**, loop until clean:
   a. /simplify
   b. /codex-review and /gemini-review in parallel
   c. /e2e-verify
   d. If any step found issues, fix them and repeat from (a)

3. **Stop gate**: A Codex-driven hook judges at Stop time whether the loop is
   complete. Block reasons appear in stderr — read them, fix, re-run skipped
   steps. There is no SKIP syntax; the gate decides exemptions itself based on
   facts (e.g., gemini not installed → gemini-review auto-exempted).

4. **Escape hatch**: `SKIP_GATE=1` env var bypasses the gate (for emergencies
   or when the judge appears to be malfunctioning). Use sparingly.
