## Bash Timeout

Before every Bash call, estimate a `timeout` (ms, max 600000) based on the command and pass it explicitly. Don't rely on the 120000ms default.

Estimate small rather than large — retrying with a bigger timeout beats waiting minutes on a hang.

For commands expected to exceed 10 minutes (long builds, training), use `run_in_background: true` instead of fighting the cap. Background tasks ignore the `timeout` parameter — if the command has no natural endpoint, wrap it with shell `timeout` (e.g. `timeout 1800 <cmd>`) so it self-terminates.

On timeout, don't blindly retry. Diagnose: interactive prompt (make non-interactive or ask user to run with `!`), slow network (raise timeout once), or true hang (change approach).
