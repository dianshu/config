## E2E Makefile Verification

When investigating bugs or verifying bug fixes / feature implementations, use standardized Makefile targets to start services and perform end-to-end validation.

### Integration with Systematic Debugging

When `/superpowers:systematic-debugging` is active, **Phase 1 step 2 ("Reproduce Consistently")** MUST use the E2E workflow below if a Makefile with an `up` target exists. Do not consider a bug "reproduced" based solely on reading code or logs — start the services, trigger the bug through the actual UI or API, and observe the failure firsthand.

Similarly, **Phase 4 step 3 ("Verify Fix")** MUST use the E2E workflow to confirm the fix works end-to-end, not just that tests pass.

### Standard Makefile Targets

| Target | Required | Purpose |
|--------|----------|---------|
| `make up` | Yes | Start all project services (backend + frontend) |
| `make down` | Optional | Stop all services |

### When to Use

**Bug Investigation:**
1. Check if the project root has a Makefile with an `up` target
2. If yes, run `make up` in the background (use Bash tool with `run_in_background: true`). Note the task ID and output file path from the result — use `Read` on the output file to check service logs when debugging.
3. Wait for services to be ready, then reproduce the bug:
   - Frontend: Use Chrome MCP to open the page, take screenshots, interact with elements
   - Backend: Use `curl` to call API endpoints and check responses
4. After investigation, clean up: run `make down` if available, otherwise kill the background processes

**Implementation Verification (after bug fix or feature code):**
1. Check if the project root has a Makefile with an `up` target
2. If yes, run `make up` in the background (use Bash tool with `run_in_background: true`). Note the task ID and output file path — use `Read` on the output file to check service logs if needed.
3. Verify the fix/feature works end-to-end:
   - Frontend: Chrome MCP — open pages, screenshot, click, verify elements
   - Backend: `curl` — call API endpoints, check status codes and response content
4. Capture evidence (screenshots, API responses)
5. Clean up: run `make down` if available, otherwise kill the background processes
6. This complements (does not replace) unit tests and the verification-before-completion workflow

### When Makefile is Missing

- If the repo has no Makefile or lacks an `up` target, **suggest** adding one but do **not** force it
- Continue using other verification methods (unit tests, integration tests, etc.)
