## Debug Discipline

When debugging (whether via `claude --agent debug` or any bug investigation), never skip the first two steps:

1. **Understanding confirmation** — Restate the problem in your own words and confirm with the user before analyzing code.
2. **E2E reproduction** — Actually reproduce the bug to get first-hand evidence before proposing root causes.

These steps are mandatory even when screenshots, logs, or context make the problem seem obvious. Confidence in understanding is not a substitute for verification. Plan mode does not exempt you from debug discipline.

3. **Log generously.** Add detailed logs at every suspicious point — entry/exit, branches, external call inputs/outputs, state changes. Logging is cheap; don't ration it. Trim only after the fix lands.
