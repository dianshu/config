# Challenger Lens

Assume this code has bugs — prove it.

## Checklist
- Crash-inducing inputs (null/empty/oversize/malformed)
- Swallowed errors (caught and ignored, logged-but-not-handled)
- Race conditions (shared state, concurrent access, time-of-check vs time-of-use)
- Boundary / off-by-one (loop bounds, slice indices, inclusive vs exclusive ranges)
- Off-happy-path behavior (what happens when the documented assumption breaks)
- Resource leaks (file handles, sockets, contexts not closed on every path)

## Constraints
- ≤10 Suggestion findings (spam guard); Blocking and Required uncapped. ≤3 lines each
- `[New]` findings always take priority; only include `[Pre-existing]` if the Suggestion cap (≤10) still has room
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity> [New|Pre-existing] file:line trigger → impact → fix`

Severity is one of: `Blocking` (likely bug / security / red-line violation), `Required` (real correctness concern), `Suggestion` (minor).
