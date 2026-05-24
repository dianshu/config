## Verify Against Diff

When you finish a code change and are about to declare it "verified" — whether via `/e2e-verify`, `/finalize`, manual checks, or just running tests — do not equate "workflow completed" with "change verified".

1. **Enumerate first.** Run `git diff` (vs the appropriate base) and list every observable behavior the change introduces. "Observable" = something an outside observer could see at runtime (log lines, emitted events, response payloads, error paths, env-var branches, UI elements, files written, side effects, etc.).
2. **Reconcile each item.** For each entry, point to the concrete observation that proves it works. A passing test suite or "the service started OK" is not, by itself, reconciliation — you must look at the thing the change actually produces.
3. **"Signal absent" ≠ "verified".** If the natural observation channel is unavailable in your environment, construct a local one (debug log, temporary capture, in-memory fixture, env-var toggle, etc.) rather than skip. Only after that fails may you mark an item `deferred to <environment>` with a one-line justification.

This rule applies to any verification step, not only `/e2e-verify`.
