export const meta = {
  name: 'finalize-testing-rules-audit',
  description: 'For each test file changed in this session, audit against ~/.claude/injected-rules/testing.md and emit a per-file evidence block.',
  phases: [
    { title: 'List', detail: 'enumerate changed test files via git' },
    { title: 'Audit', detail: 'one agent per file, schema-enforced verdict' },
  ],
}

const TEST_PATTERN = '(^|/)(tests?|__tests__|spec|specs|e2e|androidTest|unitTest|E2ETests?)/|(\\.|_)(test|spec)\\.[^/]+$|_test\\.go$|Tests?\\.(swift|kt|java|cs|m|mm)$|Spec\\.swift$|(^|/)test_[^/]+\\.py$'

phase('List')

const listResult = await agent(
  `Run these shell commands and combine their outputs:

  1. \`git diff --name-only HEAD\`            # tracked + modified
  2. \`git diff --cached --name-only\`        # staged
  3. \`git ls-files --others --exclude-standard\`  # untracked

  Sort -u the union. Then filter to test files matching this regex (extended POSIX):
  ${TEST_PATTERN}

  Return {files: [string]} listing only the test files.
  If git rev-parse --git-dir fails (not a git repo), return {files: []}.`,
  {
    schema: {
      type: 'object',
      required: ['files'],
      properties: {
        files: { type: 'array', items: { type: 'string' } },
      },
    },
    label: 'list-test-files',
    phase: 'List',
  },
)

const testFiles = listResult?.files || []

if (testFiles.length === 0) {
  return {
    violations: 0,
    fileCount: 0,
    byFile: [],
    note: 'No test files changed in this session — testing-rules self-check trivially passes.',
  }
}

phase('Audit')

const TESTING_RULES = `From ~/.claude/injected-rules/testing.md:

Rule 1: Don't modify tests themselves just to make them pass.
  Violation signals: assertion weakened (concrete value -> XCTAssert(true) or removed);
  expected value rewritten to match buggy actual output; test skipped/disabled/commented
  without justification; test method deleted; visibility widened solely to enable assertions;
  test introduces a parallel implementation (Fake replaces the subject under test, then
  asserts on the Fake); production code branches on test detection (isTesting, #if DEBUG
  wrapping real logic); production exposes test-only writable hook.

Rule 2: Use Mock for external APIs and time-related logic; prefer real dependencies for
  other scenarios.
  Violation signals: mocks an internal collaborator (own service layer, own DB model);
  real external dependency not mocked (real HTTP, real third-party SDK); time-related
  logic not mocked / no injectable clock.`

const AUDIT_SCHEMA = {
  type: 'object',
  required: ['file', 'changeSummary', 'applicableRules', 'verdict', 'justification'],
  properties: {
    file: { type: 'string' },
    changeSummary: { type: 'string', description: 'What was changed in this file (1-2 sentences). For untracked, summarize the whole file purpose.' },
    applicableRules: {
      type: 'array',
      items: { enum: ['rule-1-no-test-mod-to-pass', 'rule-2-mock-scope', 'none'] },
      description: 'Which testing.md rules are relevant to the change. Use ["none"] if no rule applies (e.g. new test for new code with proper mocks).',
    },
    verdict: { enum: ['compliant', 'violation'] },
    justification: { type: 'string', description: 'One-line evidence-based reasoning. Cite specific lines/changes.' },
  },
}

const audits = await parallel(testFiles.map(file => () => agent(
  `Audit test file changes against testing.md.

${TESTING_RULES}

Steps:
1. Determine the file's git state:
   - Try \`git diff HEAD -- ${file}\` and \`git diff --cached -- ${file}\`. If both empty, the file may be untracked.
   - For untracked: \`Read ${file}\` to see the full new contents.
2. Read ${file} for full context if needed.
3. Apply the testing.md rules above against the changes.
4. Return the schema. Be evidence-based: cite specific lines/changes in justification.`,
  {
    schema: AUDIT_SCHEMA,
    label: `audit:${file}`,
    phase: 'Audit',
  },
)))

const valid = audits.filter(Boolean)
const violations = valid.filter(a => a.verdict === 'violation')

return {
  violations: violations.length,
  fileCount: valid.length,
  byFile: valid,
  violationsList: violations.map(v => ({ file: v.file, justification: v.justification })),
}
