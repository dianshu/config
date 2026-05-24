---
name: e2e-verify
description: >
  Use after implementation and code review to verify changes work end-to-end
  through the running application. Starts services via make up, verifies
  frontend (Chrome MCP) and backend (curl), captures evidence, and cleans up.
---

# E2E Verification

Verify that changes work end-to-end through the running application. This complements (does not replace) unit tests and the `/superpowers:verification-before-completion` workflow.

## Workflow

### 1. Enumerate observable behaviors introduced by this change

Run `git diff` against the appropriate base. Extract every **observable** behavior the change introduces — anything an outside observer can see at runtime. Examples (not exhaustive): new log lines or log fields, new emitted metrics/events, new HTTP/RPC endpoints or response fields, new error paths, new env-var-driven branches, new UI elements.

Write a short checklist (typically 3–10 items). This is the verification target. Steps 2–7 below must each tie back to one or more items on this list.

If you cannot enumerate a list (diff too large or unfocused), stop and ask the user to narrow scope before running verification.

### 2. Check for Makefile

Verify the project root has a Makefile with an `up` target:

```bash
grep -q '^up:' Makefile 2>/dev/null || grep -q '^up ' Makefile 2>/dev/null
```

If no Makefile or no `up` target exists, suggest adding one but do **not** force it. Fall back to other verification methods (unit tests, integration tests, manual testing).

### 3. Start services

Run `make up` in the background:

```bash
make up  # run with run_in_background: true
```

Note the task ID and output file path — use `Read` on the output file to check service logs if needed.

### 4. Verify frontend

Use Chrome MCP to verify the UI:

- Open pages relevant to the change
- Take screenshots as evidence
- Click elements and interact with the UI
- Verify expected content is displayed

### 5. Reconcile against the Step 1 checklist

For each item on the Step 1 checklist:

1. **Identify the observation channel** — the concrete thing that, if you look at it, tells you the behavior happened (a log line, a response body, a metric value, a file written, an exit code, a UI element, etc.).
2. **Look at it directly.** Capture the actual value/content, not just "the framework loaded OK" or "the test passed". A passing unit test is not, by itself, end-to-end reconciliation.
3. **If the natural channel is unavailable in your environment**, do not skip — construct a temporary local channel before giving up: add a debug log, attach a test-only exporter/reader, capture a fixture, swap an env var, etc. Revert any temporary instrumentation after verification.
4. **If after step 3 the item still cannot be verified locally**, mark it `deferred to <env>` in the report with a one-line justification. Never silently skip.

### 6. Capture evidence

Save verification artifacts. Evidence must map back to specific Step 1 items, not a generic "service started OK" log dump.

- Screenshots from Chrome MCP
- API response snippets from curl
- Log/metric snapshots tied to each checklist item

### 7. Clean up

Stop services when verification is complete:

```bash
make down  # if available, otherwise kill background processes
```

## Standard Makefile Targets

| Target | Required | Purpose |
|--------|----------|---------|
| `make up` | Yes | Start all project services (backend + frontend) |
| `make down` | Optional | Stop all services |

## When Makefile is Missing

- If the repo has no Makefile or lacks an `up` target, **suggest** adding one but do **not** force it
- Continue using other verification methods (unit tests, integration tests, etc.)
