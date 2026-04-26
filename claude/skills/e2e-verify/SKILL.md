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

### 1. Check for Makefile

Verify the project root has a Makefile with an `up` target:

```bash
grep -q '^up:' Makefile 2>/dev/null || grep -q '^up ' Makefile 2>/dev/null
```

If no Makefile or no `up` target exists, suggest adding one but do **not** force it. Fall back to other verification methods (unit tests, integration tests, manual testing).

### 2. Start services

Run `make up` in the background:

```bash
make up  # run with run_in_background: true
```

Note the task ID and output file path — use `Read` on the output file to check service logs if needed.

### 3. Verify frontend

Use Chrome MCP to verify the UI:

- Open pages relevant to the change
- Take screenshots as evidence
- Click elements and interact with the UI
- Verify expected content is displayed

### 4. Verify backend

Use `curl` to verify API behavior:

- Call API endpoints affected by the change
- Check status codes and response content
- Verify error handling where applicable

### 5. Capture evidence

Save verification artifacts:

- Screenshots from Chrome MCP
- API response snippets from curl

### 6. Clean up

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
