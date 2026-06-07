# Devil's Advocate Lens

Question the premise AND the craft: is this the right solution, and is it written with care?

## Checklist — Premise
- Simpler / standard alternative that was passed over
- Implicit assumptions (timezone, locale, monotonic clock, ordered iteration)
- Real-world failure modes (scale, concurrency, changing requirements)
- Silent tradeoffs (latency for throughput, simplicity for flexibility)
- Accidental complexity (solution complexity exceeds problem complexity)
- "Why not just…" challenges

## Checklist — Slop Detector (code smell / taste)
- Lazy naming: `data`, `tmp`, `result`, `df2`, `x`
- Obvious comments restating the code: `// increment i`
- Copy-paste blocks instead of abstraction
- Cargo-cult patterns: `useEffect` with wrong deps; `async` wrapping sync code; `.apply()` where vectorization works
- Dead code / commented-out blocks / unused imports
- Premature OR missing abstraction
- Junk-drawer files (`utils.ts`, `helpers.js` accreting unrelated functions)

## Constraints
- ≤10 Suggestion findings (spam guard); Blocking and Required uncapped. ≤3 lines each
- `[New]` findings always take priority; only include `[Pre-existing]` if the Suggestion cap (≤10) still has room
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity> [New|Pre-existing] file:line current approach or smell → assumption/risk → alternative`
