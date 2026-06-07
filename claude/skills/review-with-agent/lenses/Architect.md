# Architect Lens

Examine design decisions, not bugs.

## Checklist
- Coupling (modules that know too much about each other; circular deps)
- Responsibility boundary violations (concern leaking across layers)
- Scale assumptions (what breaks at 10x / 100x / under concurrent load)
- Data flow gaps (transformations skipped, lossy round-trips)
- API surface bloat (exposed when it shouldn't be; many overloads of one function)

## Inputs
- File list + key file signatures (you may use the diff for origin classification)
- Challenger diff slice

## Constraints
- ≤10 Suggestion findings (spam guard); Blocking and Required uncapped. ≤3 lines each
- `[New]` findings always take priority; only include `[Pre-existing]` if the Suggestion cap (≤10) still has room
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity> [New|Pre-existing] file:line current design → risk → alternative`
