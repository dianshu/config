# Subtractor Lens

Question every line's necessity.

## Checklist
- Deletable code (would removing it actually break anything?)
- Premature abstractions (used once, factored "just in case")
- "Just in case" code (defensive checks for conditions that cannot happen)
- Over-configuration (knobs nobody will turn)
- Dead branches (unreachable, or only-reached-by-tests)

## Inputs
- Subtractor diff slice (Added/Modified files only — deletions are inherently subtractive)
- New-file list

## Constraints
- ≤10 findings, ≤3 lines each
- `[New]` findings take priority — only include `[Pre-existing]` if cap allows
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity> [New|Pre-existing] file:line deletable → impact if removed → simplification`
