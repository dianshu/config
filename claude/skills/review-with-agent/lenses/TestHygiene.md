# Test Hygiene Lens

Focus is on test files, but production-code edits are in scope when they exist solely to make tests pass.

## Inputs
- Challenger diff slice (full diff — compare test changes against production-code changes)

## Checklist — 12 items, three groups

### Group 1 — Test weakened to make it pass (default Blocking unless noted)
- (a, **Blocking**) Assertion weakened (`assertEqual` → `assertNotNil`, concrete value → `XCTAssert(true)`, removed)
- (b, **Required**) Test skipped / disabled / `xit` / commented-out without justification
- (c, **Blocking**) Expected value rewritten to match buggy actual output
- (d, **Required**) Test method deleted

### Group 2 — Mock scope (testing.md rule 2: mock external APIs and time-related logic; prefer real dependencies elsewhere)
- (e, **Suggestion**) Mocks an internal collaborator (own service layer, own DB model)
- (f, **Suggestion**) Real external dependency not mocked (real HTTP, real third-party SDK)
- (g, **Suggestion**) Time-related logic not mocked / no injectable clock

### Group 3 — Production code polluted to satisfy tests (default Blocking unless noted)
- (k, **Blocking**) Production code branches on test-environment detection (`if isTesting`, `XCTestConfigurationFilePath` env var, `#if DEBUG` wrapping real logic)
- (l, **Required**) Production code exposes a test-only writable hook (e.g. `var _testOverride: Foo?`); injectable default args like `func foo(now: Date = Date())` are fine
- (m, **Required**) Production code branches commented "for tests" / "test only"
- (n, **Blocking**) Test introduces a parallel implementation (Fake replaces the subject under test, then asserts on the Fake)
- (o, **Required**) Visibility widened (private → public/internal) solely to enable assertions

## Constraints
- ≤10 findings, ≤3 lines each
- Severity defaults above; you may adjust up/down with explicit reasoning
- If nothing actionable: output `LGTM`

## Output Format
One finding per line:
`<Severity> [New|Pre-existing] file:line which item (a–o) → evidence → fix`
