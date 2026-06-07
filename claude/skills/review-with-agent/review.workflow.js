export const meta = {
  name: 'review-with-agent',
  description: 'Multi-lens adversarial code review orchestrated by Workflow. Dispatches 1-6 lens reviewers in parallel via an external CLI (codex|opencode), parses structured findings via schema, runs red-line scan in parallel, then synthesizes + verifies before emitting a verdict.',
  phases: [
    { title: 'Preflight', detail: 'verify backend CLI is available' },
    { title: 'Prep-diff', detail: 'classify scale + prepare diff slices via review-prep-diff.sh' },
    { title: 'Intent' },
    { title: 'Lens-fanout', detail: 'parallel lens reviewers (external CLI) + red-line scan' },
    { title: 'Synthesize', detail: 'merge + verify [New] Required/Blocking findings against worktree' },
  ],
}

// Backend dispatch commands — single source of truth (replaces shell-var config in codex-review/opencode-review)
const BACKEND_CONFIG = {
  codex: {
    preflight: 'codex --version 2>/dev/null',
    dispatch: 'codex exec - --cd "$(pwd)" --ephemeral -s read-only',
    readonlyDispatch: 'codex exec - --cd "$(pwd)" --ephemeral -s read-only',
    planDispatch: 'codex exec - --skip-git-repo-check --ephemeral -s read-only',
    modeLabel: 'codex-adversarial',
    noiseFilter: 'grep -vE "^OpenAI Codex|^----|^workdir:|^model:|^provider:|^approval:|^sandbox:|^reasoning|^session id:|^$"',
    tmpdirPrefix: 'codex-review',
  },
  opencode: {
    preflight: 'opencode --version 2>/dev/null && test -f "$HOME/.config/opencode/opencode.json" && command -v jq >/dev/null',
    dispatch: 'opencode run --agent review-readonly --format json 2>/dev/null | jq -rs \'[.[] | select(.type=="text")] | last | .part.text // empty\'',
    readonlyDispatch: 'opencode run --agent review-readonly --format json 2>/dev/null | jq -rs \'[.[] | select(.type=="text")] | last | .part.text // empty\'',
    planDispatch: 'opencode run --agent review-readonly --format json 2>/dev/null | jq -rs \'[.[] | select(.type=="text")] | last | .part.text // empty\'',
    modeLabel: 'opencode-gemini-3.1-pro',
    noiseFilter: 'cat',
    tmpdirPrefix: 'opencode-review',
  },
}

const LENS_ROSTER = {
  Light:  ['Challenger'],
  Medium: ['Challenger', 'Architect', 'Integration', 'DevilsAdvocate'],
  Heavy:  ['Challenger', 'Architect', 'Integration', 'DevilsAdvocate', 'Subtractor'],
}

const LENS_INPUT = {
  Challenger:     'challengerDiffPath',
  Architect:      'challengerDiffPath',
  Subtractor:     'subtractorDiffPath',
  Integration:    'challengerDiffPath',
  DevilsAdvocate: 'challengerDiffPath',
  TestHygiene:    'challengerDiffPath',
}

const LENS_USES_READONLY = new Set(['Integration'])

const FINDING_ITEM_SCHEMA = {
  type: 'object',
  required: ['severity', 'origin', 'file', 'line', 'description'],
  properties: {
    severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
    origin: { enum: ['New', 'Pre-existing'] },
    file: { type: 'string' },
    line: { type: ['integer', 'string'] },
    description: { type: 'string' },
  },
}

const LENS_RESULT_SCHEMA = {
  type: 'object',
  required: ['lens', 'status', 'findings'],
  properties: {
    lens: { type: 'string' },
    status: { enum: ['ok', 'empty', 'failed'] },
    findings: { type: 'array', items: FINDING_ITEM_SCHEMA },
    rawSnippet: { type: 'string' },
  },
}

const MERGED_FINDING_SCHEMA = {
  type: 'object',
  required: ['severity', 'origin', 'file', 'line', 'description', 'lenses'],
  properties: {
    severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
    origin: { enum: ['New', 'Pre-existing'] },
    file: { type: 'string' },
    line: { type: ['integer', 'string'] },
    description: { type: 'string' },
    lenses: { type: 'array', items: { type: 'string' }, minItems: 1 },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['findingIndex', 'decision', 'rationale'],
  properties: {
    findingIndex: { type: 'integer' },
    decision: { enum: ['Accept', 'Dismiss'] },
    rationale: { type: 'string' },
    evidence: { type: 'string', description: 'File path + line range + snippet from Read/Grep/git show' },
  },
}

// ============================================================
// Entry point — args validation
// ============================================================

const {
  mode = 'code',
  backend,
  planPath,
  planContent,
  prdPath,
  prdContent,
  issuesDir,
  contextFiles,
  wontfixLedger,
  lensRoster,
} = args || {}

if (!backend || !BACKEND_CONFIG[backend]) {
  throw new Error(`review-with-agent: args.backend must be one of: ${Object.keys(BACKEND_CONFIG).join(', ')}`)
}
if (mode !== 'code' && mode !== 'plan' && mode !== 'prd' && mode !== 'issues') {
  throw new Error(`review-with-agent: args.mode must be 'code', 'plan', 'prd', or 'issues'`)
}
if (mode === 'plan' && !planPath && !planContent) {
  throw new Error(`review-with-agent: plan mode requires args.planPath or args.planContent`)
}
if (mode === 'prd' && !prdPath && !prdContent) {
  throw new Error(`review-with-agent: prd mode requires args.prdPath or args.prdContent`)
}
if (mode === 'issues' && !issuesDir) {
  throw new Error(`review-with-agent: issues mode requires args.issuesDir`)
}

const BACKEND = BACKEND_CONFIG[backend]

// ============================================================
// Phase 1 — Preflight
// ============================================================

phase('Preflight')

const preflight = await agent(
  `Run this preflight check via Bash, capture stdout and stderr:

  ${BACKEND.preflight}

  Return {ok: bool, output: string} — ok=true if exit code is 0.`,
  {
    schema: {
      type: 'object',
      required: ['ok'],
      properties: { ok: { type: 'boolean' }, output: { type: 'string' } },
    },
    label: `preflight:${backend}`,
    phase: 'Preflight',
  },
)

if (!preflight.ok) {
  return {
    aborted: true,
    stage: 'preflight',
    reason: `Backend ${backend} preflight failed: ${preflight.output || '(no output)'}`,
  }
}

// ============================================================
// Plan Review mode (short branch — single dispatch, no fan-out)
// ============================================================
//
// Two execution paths:
//   1. Single-pass (default, no lensRoster arg) — one dispatch per backend
//      with the 8-dimension PRD checklist. Use when /prd-review-loop drives
//      dual-backend voting (current P0 wiring).
//   2. Lens fan-out (when args.lensRoster is provided) — N parallel lens
//      dispatches to a SINGLE backend, each lens reading its own prompt
//      file under lenses/prd/<Lens>.md. Aggregation: ≥2 lens agreement on
//      same finding → Blocking promoted; single-lens flag → Contested.
//      Use when /prd-review-loop drops the second backend in favor of
//      orthogonal lens perspectives (P1 wiring).
//
// Both paths accept:
//   - args.prdPath OR args.prdContent — the PRD to review
//   - args.contextFiles — array of {path, label, content} for ADR/glossary/
//     GRILLCOMMITMENTS/historical-PRD context injection (P0-2)
//   - args.wontfixLedger — array of {id, severity, source, rationale,
//     decidedRoundN} for already-decided exclusions (P1-6); reviewer is
//     told NOT to re-flag these
//
// PRD 8-dimension checklist (drives both paths):
//   1. USER_STORY_INVEST — actor/feature/benefit triple, Independent,
//      Negotiable, Valuable, Estimable, Small, Testable
//   2. ACCEPTANCE_CRITERIA — Given-When-Then or observable behavior per
//      story; must NOT reference class/method/schema/file
//   3. TRACEABILITY — every story has at least one Testing Decision; every
//      Testing Decision maps to ≥1 story
//   4. USER_VOCABULARY — Problem/Solution/Stories in user language, not
//      implementation terms; engineering metrics translated to UX
//   5. INTERNAL_CAUSAL_CHAIN — Problem → Solution → Story → Decision
//      traceable each direction
//   6. OUT_OF_SCOPE_DISCIPLINE — every item has observable
//      Re-evaluate-when trigger
//   7. ASSUMPTIONS_SURFACED — explicit list + reviewer-inferred list of
//      load-bearing assumptions
//   8. NFR_PRESENCE — perf/security/a11y/observability per applicable
//      feature category
// Plus CONSISTENCY when args.contextFiles is non-empty:
//   9. CONSISTENCY — terminology matches glossary; ADR relationship
//      declared (extends/refines/supersedes); no GRILLCOMMITMENTS
//      violation; no contradiction with historical PRDs

if (mode === 'plan') {
  phase('Lens-fanout')

  const planSource = planPath
    ? `Read the plan file at: ${planPath}`
    : `Use this inline plan content:\n\n${planContent}`

  const PLAN_FINDINGS_SCHEMA = {
    type: 'object',
    required: ['findings'],
    properties: {
      findings: {
        type: 'array',
        items: {
          type: 'object',
          required: ['severity', 'category', 'description'],
          properties: {
            severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
            category: { type: 'string' },
            description: { type: 'string' },
          },
        },
      },
    },
  }

  const planReview = await agent(
    `${planSource}

    Then dispatch the plan content to the ${backend} CLI for review using this exact pipeline:

    \`\`\`bash
    { cat <plan_or_tempfile>; cat <<'PROMPT'
    ---
    You are reviewing an implementation plan document.

    Review for:
    1. COMPLETENESS: TODOs, placeholders, missing steps
    2. SPEC ALIGNMENT: requirements coverage, scope creep
    3. TASK DECOMPOSITION: atomic, clear boundaries, 2-5 min each
    4. FILE STRUCTURE: single responsibility per file
    5. FILE SIZE: files that would grow too large
    6. TASK SYNTAX: checkbox syntax (- [ ]) for tracking
    7. CHUNK SIZE: chunks under 1000 lines, self-contained

    Also: missing verification after impl steps, missing test-first (TDD),
    incomplete code snippets, missing commit steps between logical units.

    Output each finding as:
    Blocking|Required|Suggestion [Category] description
    PROMPT
    } | ${BACKEND.planDispatch}
    \`\`\`

    Filter the output with: ${BACKEND.noiseFilter}
    Parse each output line as one finding. Return the schema.
    If output is empty or matches /Retry attempts exhausted|Error executing tool|NumericalClassifier/, treat as failed and return {findings: []}.`,
    {
      schema: PLAN_FINDINGS_SCHEMA,
      label: `plan-review:${backend}`,
      phase: 'Lens-fanout',
    },
  )

  const blockers = (planReview.findings || []).filter(f => f.severity === 'Blocking').length
  let verdict
  if (blockers === 0) verdict = 'PASS'
  else if (blockers >= 2) verdict = 'REJECT'
  else verdict = 'CONTESTED'

  return {
    mode: 'plan',
    verdict,
    modeLabel: BACKEND.modeLabel,
    findings: planReview.findings || [],
    blockerCount: blockers,
  }
}

// ============================================================
// PRD Review mode
// ============================================================
//
// Two execution paths:
//   1. Single-pass (default, no lensRoster arg) — one dispatch per backend
//      with the 8-dimension PRD checklist. Use when /prd-review-loop drives
//      dual-backend voting (current P0 wiring).
//   2. Lens fan-out (when args.lensRoster is provided) — N parallel lens
//      dispatches to a SINGLE backend, each lens reading its own prompt
//      file under lenses/prd/<Lens>.md. Aggregation: ≥2 lens agreement on
//      same finding → Blocking promoted; single-lens flag → Contested.
//      Use when /prd-review-loop drops the second backend in favor of
//      orthogonal lens perspectives (P1 wiring).
//
// Both paths accept:
//   - args.prdPath OR args.prdContent — the PRD to review
//   - args.contextFiles — array of {path, label, content} for ADR/glossary/
//     GRILLCOMMITMENTS/historical-PRD context injection (P0-2)
//   - args.wontfixLedger — array of {id, severity, source, rationale,
//     decidedRoundN} for already-decided exclusions (P1-6); reviewer is
//     told NOT to re-flag these
//
// PRD 8-dimension checklist (drives both paths):
//   1. USER_STORY_INVEST — actor/feature/benefit triple, Independent,
//      Negotiable, Valuable, Estimable, Small, Testable
//   2. ACCEPTANCE_CRITERIA — Given-When-Then or observable behavior per
//      story; must NOT reference class/method/schema/file
//   3. TRACEABILITY — every story has at least one Testing Decision; every
//      Testing Decision maps to ≥1 story
//   4. USER_VOCABULARY — Problem/Solution/Stories in user language, not
//      implementation terms; engineering metrics translated to UX
//   5. INTERNAL_CAUSAL_CHAIN — Problem → Solution → Story → Decision
//      traceable each direction
//   6. OUT_OF_SCOPE_DISCIPLINE — every item has observable
//      Re-evaluate-when trigger
//   7. ASSUMPTIONS_SURFACED — explicit list + reviewer-inferred list of
//      load-bearing assumptions
//   8. NFR_PRESENCE — perf/security/a11y/observability per applicable
//      feature category
// Plus CONSISTENCY when args.contextFiles is non-empty:
//   9. CONSISTENCY — terminology matches glossary; ADR relationship
//      declared (extends/refines/supersedes); no GRILLCOMMITMENTS
//      violation; no contradiction with historical PRDs

if (mode === 'prd') {
  phase('Lens-fanout')

  const prdSource = prdPath
    ? `Read the PRD file at: ${prdPath}`
    : `Use this inline PRD content:\n\n${prdContent}`

  const ctxFiles = Array.isArray(contextFiles) ? contextFiles : []
  const ctxBlock = ctxFiles.length === 0
    ? ''
    : `\n\nPROJECT CONTEXT (injected — reviewer MUST cross-check PRD against these):\n${
        ctxFiles.map(c => `\n--- ${c.label} (${c.path}) ---\n${c.content}`).join('\n')
      }\n--- end project context ---\n`

  const wontfix = Array.isArray(wontfixLedger) ? wontfixLedger : []
  const wontfixBlock = wontfix.length === 0
    ? ''
    : `\n\nWONT-FIX LEDGER (already-decided exclusions — do NOT re-flag these unless you have NEW evidence the decision is wrong):\n${
        wontfix.map(w => `- [${w.id}] ${w.severity} (decided round ${w.decidedRoundN} via ${w.source}): ${w.rationale}`).join('\n')
      }\n--- end wont-fix ---\n`

  const PRD_DIMENSIONS = `
1. USER_STORY_INVEST — For each "As an X, I want Y, so that Z" story:
   (a) actor must be a concrete persona, not "user"
   (b) want must be observable behavior, not UI/implementation
   (c) so-that must name measurable value, not a tautology / restatement of want
   (d) story must be Independent (no hidden ordering deps), Negotiable
       (no premature impl freeze), Estimable (enough info), Small (single
       sprint), Testable (writeable acceptance scenario)
   Flag every violation as Required; circular benefit or non-testable as Blocking.

2. ACCEPTANCE_CRITERIA — Each user story MUST have explicit acceptance
   criteria nested below it (Given-When-Then or observable-behavior
   bullets). Criteria MUST describe external behavior only — flag any
   criterion that names a class / method / schema field / file path / DB
   column as Blocking. Missing criteria → Blocking.

3. TRACEABILITY — Output a two-way coverage matrix:
   (a) every User Story id → which Testing Decision covers it (or
       UNCOVERED → Blocking)
   (b) every Testing Decision → which User Story id(s) it serves (or
       ORPHAN → Required)
   Also: every Implementation Decision should trace to ≥1 User Story
   (orphan Implementation Decision → Required).

4. USER_VOCABULARY — Scan Problem Statement / Solution / User Stories
   sentence-by-sentence:
   (a) ANY implementation term (API name, class name, schema field,
       protocol name, library name) → Required
   (b) ANY engineering metric (SLO, p99, QPS, throughput, ms) without a
       user-experience translation (wait time, retry count, failure
       probability) → Required
   Implementation terms belong in Implementation Decisions, not the user-facing
   sections.

5. INTERNAL_CAUSAL_CHAIN — Trace Problem → Solution → Story → Decision in
   both directions:
   (a) every Solution element traces back to a stated Problem (orphan
       Solution → Required)
   (b) every Story traces to a Solution capability (orphan Story → Required)
   (c) every Implementation Decision serves ≥1 Story (orphan → Required)
   Problems without Solutions, Solutions without Problems → Blocking.

6. OUT_OF_SCOPE_DISCIPLINE — For each Out of Scope item:
   (a) must have an explicit Re-evaluate-when trigger
   (b) trigger must be observable (metric threshold / user count / upstream
       change / regulatory change), not vague ("if users complain")
   (c) trigger must reference signals defined elsewhere in the doc or in
       project metrics
   Missing trigger → Required; unobservable trigger → Required.

7. ASSUMPTIONS_SURFACED — Output two lists:
   (a) Assumptions the PRD explicitly states
   (b) Assumptions YOU inferred from the prose but the author did NOT make
       explicit — for each, quote the line that triggered the inference
   Flag (b) entries as Required so the author either documents them or
   adds wont-fix justification.

8. NFR_PRESENCE — Based on the feature category, check for presence of
   relevant non-functional requirements:
   - User-facing UI → accessibility, latency budget
   - API / service → throughput, error budget, observability
   - Data-handling → privacy, retention, encryption
   - Auth-touching → security threat model
   Missing applicable NFR section → Required.
${ctxFiles.length === 0 ? '' : `
9. CONSISTENCY (project-context cross-check):
   (a) Any domain term in PRD that conflicts with CONTEXT.md glossary →
       Required (with the canonical term to use instead)
   (b) Any Implementation Decision that conflicts with an Accepted ADR
       without naming it (extends/refines/supersedes) → Blocking
   (c) Any violation of an active GRILLCOMMITMENTS commitment → Blocking
       (cite the C-number)
   (d) Any conflict with a sibling historical PRD without acknowledgment
       → Required
`}
`.trim()

  const PRD_FINDINGS_SCHEMA = {
    type: 'object',
    required: ['findings'],
    properties: {
      findings: {
        type: 'array',
        items: {
          type: 'object',
          required: ['severity', 'category', 'section', 'description'],
          properties: {
            severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
            category: {
              enum: [
                'USER_STORY_INVEST',
                'ACCEPTANCE_CRITERIA',
                'TRACEABILITY',
                'USER_VOCABULARY',
                'INTERNAL_CAUSAL_CHAIN',
                'OUT_OF_SCOPE_DISCIPLINE',
                'ASSUMPTIONS_SURFACED',
                'NFR_PRESENCE',
                'CONSISTENCY',
              ],
            },
            section: {
              type: 'string',
              description: 'H2 section name (e.g. "User Stories", "Out of Scope") or "GLOBAL" if cross-cutting',
            },
            anchor: {
              type: 'string',
              description: 'Story id (e.g. "US-7"), Out-of-Scope item index, or quoted phrase — for dedup across lenses/rounds',
            },
            description: { type: 'string' },
          },
        },
      },
    },
  }

  // ----- Path A: lens fan-out (when lensRoster provided) -----
  if (Array.isArray(lensRoster) && lensRoster.length > 0) {
    log(`PRD lens fan-out: dispatching ${lensRoster.length} lenses to ${backend}: ${lensRoster.join(', ')}`)

    async function dispatchPrdLens(lens) {
      return agent(
        `Dispatch the ${lens} PRD-review lens via the ${backend} CLI.

        1. ${prdSource}
        2. Read ~/.claude/skills/review-with-agent/lenses/prd/${lens}.md for this lens's checklist and output format.
        3. Compose the prompt: [lens checklist from file] + the shared PRD context block (project context + wont-fix ledger).
        4. Dispatch using this exact Bash pipeline (heredoc — avoids shell arg length limits):

           \`\`\`bash
           { cat <prd_or_tempfile>; cat <<'PROMPT'
           ---
           <lens checklist from step 2>
           ${ctxBlock.replace(/\n/g, '\n           ')}
           ${wontfixBlock.replace(/\n/g, '\n           ')}
           PROMPT
           } | ${BACKEND.planDispatch}
           \`\`\`

        5. Filter banner noise with: ${BACKEND.noiseFilter}
        6. Detect failure: empty output OR matches /Retry attempts exhausted|Error executing tool|NumericalClassifier/.
           Treat as failure and return {findings: []}.
        7. Parse each non-noise line as one finding. Each finding has {severity, category, section, anchor, description}.
           Set category to this lens's primary dimension when ambiguous (the lens file documents which).
        Return {findings: [...]} matching the schema.`,
        {
          schema: PRD_FINDINGS_SCHEMA,
          label: `prd-lens:${lens}`,
          phase: 'Lens-fanout',
        },
      )
    }

    const lensResults = await parallel(lensRoster.map(l => () => dispatchPrdLens(l)))

    // Tag each finding with originating lens, then merge with semantic dedup by (section, anchor)
    const taggedFindings = lensResults.flatMap((r, i) => {
      const lens = lensRoster[i]
      return (r?.findings || []).map(f => ({ ...f, lenses: [lens] }))
    })

    phase('Synthesize')

    const MERGED_PRD_SCHEMA = {
      type: 'object',
      required: ['findings'],
      properties: {
        findings: {
          type: 'array',
          items: {
            type: 'object',
            required: ['severity', 'category', 'section', 'description', 'lenses'],
            properties: {
              severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
              category: { type: 'string' },
              section: { type: 'string' },
              anchor: { type: 'string' },
              description: { type: 'string' },
              lenses: { type: 'array', items: { type: 'string' }, minItems: 1 },
            },
          },
        },
      },
    }

    const merged = taggedFindings.length === 0
      ? { findings: [] }
      : await agent(
        `Merge these per-lens PRD findings, deduping by semantic equivalence at (section, anchor).
         Two findings dedup when they refer to the same section AND same anchor (story id, OoS index, or quoted phrase) AND describe the same problem.
         When merging duplicates: union the lenses array, keep the highest severity.
         Drop nothing unique.

         Input: ${JSON.stringify(taggedFindings)}

         Return {findings: [...]} per the schema.`,
        {
          schema: MERGED_PRD_SCHEMA,
          label: 'merge-prd',
          phase: 'Synthesize',
        },
      )

    // Verdict: ≥2 lens agreement on a Blocking → REJECT; any single-lens Blocking → CONTESTED; 0 Blocking → PASS
    const blockers = merged.findings.filter(f => f.severity === 'Blocking')
    const multiLensBlockers = blockers.filter(f => f.lenses.length >= 2)
    let verdict
    if (blockers.length === 0) verdict = 'PASS'
    else if (multiLensBlockers.length > 0) verdict = 'REJECT'
    else verdict = 'CONTESTED'

    return {
      mode: 'prd',
      execPath: 'lens-fanout',
      verdict,
      modeLabel: BACKEND.modeLabel,
      lensRoster,
      lensResults: lensResults.map((r, i) => ({
        lens: lensRoster[i],
        findingCount: (r?.findings || []).length,
      })),
      findings: merged.findings,
      stats: {
        total: merged.findings.length,
        blockers: blockers.length,
        multiLensBlockers: multiLensBlockers.length,
        contextFilesInjected: ctxFiles.length,
        wontfixEntriesApplied: wontfix.length,
      },
    }
  }

  // ----- Path B: single-pass (default, no lensRoster) -----

  const prdReview = await agent(
    `${prdSource}

    Then dispatch the PRD content to the ${backend} CLI for review using this exact pipeline:

    \`\`\`bash
    { cat <prd_or_tempfile>; cat <<'PROMPT'
    ---
    You are reviewing a Product Requirements Document (PRD), not an implementation plan.
    A PRD describes a product feature from the USER's perspective. It does NOT
    contain code, file paths, or task lists. Do NOT flag missing checkboxes,
    missing TDD steps, missing file-size limits, or missing commit boundaries —
    those concerns do not apply to PRDs.

    Review the PRD against these 8 dimensions${ctxFiles.length > 0 ? ' + CONSISTENCY' : ''}:

    ${PRD_DIMENSIONS}
    ${ctxBlock}
    ${wontfixBlock}

    Output format — one finding per line:
    <Severity>|<Category>|<Section>|<Anchor>|<Description>
    where Severity ∈ {Blocking, Required, Suggestion}
    and Category ∈ {USER_STORY_INVEST, ACCEPTANCE_CRITERIA, TRACEABILITY,
                    USER_VOCABULARY, INTERNAL_CAUSAL_CHAIN, OUT_OF_SCOPE_DISCIPLINE,
                    ASSUMPTIONS_SURFACED, NFR_PRESENCE${ctxFiles.length > 0 ? ', CONSISTENCY' : ''}}
    and Section is the H2 heading name or "GLOBAL"
    and Anchor is a story id / OoS index / quoted phrase (for dedup across rounds)

    If the PRD is clean: output literally "LGTM" and nothing else.
    PROMPT
    } | ${BACKEND.planDispatch}
    \`\`\`

    Filter output with: ${BACKEND.noiseFilter}
    Parse each non-noise non-LGTM line into a finding {severity, category, section, anchor, description}.
    If output is empty or "LGTM" or matches /Retry attempts exhausted|Error executing tool|NumericalClassifier/, return {findings: []}.`,
    {
      schema: PRD_FINDINGS_SCHEMA,
      label: `prd-review:${backend}`,
      phase: 'Lens-fanout',
    },
  )

  const findings = prdReview.findings || []
  const blockers = findings.filter(f => f.severity === 'Blocking').length
  let verdict
  if (blockers === 0) verdict = 'PASS'
  else if (blockers >= 2) verdict = 'REJECT'
  else verdict = 'CONTESTED'

  return {
    mode: 'prd',
    execPath: 'single-pass',
    verdict,
    modeLabel: BACKEND.modeLabel,
    findings,
    stats: {
      total: findings.length,
      blockers,
      contextFilesInjected: ctxFiles.length,
      wontfixEntriesApplied: wontfix.length,
    },
  }
}

// ============================================================
// Issues Review mode
// ============================================================
//
// Reviews the SET of pending issue files written by /issues (typically under
// ~/.claude/matt/features/<slug>/issues/NN-<slug>.md). Two-axis fan-out:
//   axis 1: 5 issue lenses (Slicer / DependencyAuditor / Granularity /
//           AcceptanceCriteria / Coverage). Coverage drops automatically
//           when no PARENT_PRD entry is present in args.contextFiles.
//   axis 2: per-issue dispatch (each lens sees ALL pending issues — set-wide
//           review, not per-issue — so it's lens-parallel × 1 dispatch per
//           lens, with the lens prompt receiving the full pending-issues
//           bundle inline).
//
// Before lens dispatch, a deterministic Bash preflight runs the
// /run-all-issues `## Blocked by` regex over every pending issue. Results
// are surfaced as `parserFailures: [{file, reason, offendingLine}]`. This
// is the source of truth used by /issues-review-loop's progression-check
// `parserPass` hard gate — LLM lenses never see these as findings.

if (mode === 'issues') {
  phase('Lens-fanout')

  // Helper: quote a JS string for safe use in a POSIX shell single-quoted context.
  // JSON.stringify only produces JS string literals (double-quoted) — those still
  // do $-expansion and command-substitution when embedded in bash. Single-quote
  // wrapping with '\'' escaping makes the value a pure literal.
  const shellQuote = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'"

  const ctxFiles = Array.isArray(contextFiles) ? contextFiles : []
  const hasPrd = ctxFiles.some(c => c && c.label === 'PARENT_PRD')
  const wontfix = Array.isArray(wontfixLedger) ? wontfixLedger : []

  // ----- Step 1: List pending issue files + deterministic parser preflight -----
  const PARSER_SCHEMA = {
    type: 'object',
    required: ['pendingFiles', 'parserFailures'],
    properties: {
      pendingFiles: { type: 'array', items: { type: 'string' } },
      parserFailures: {
        type: 'array',
        items: {
          type: 'object',
          required: ['file', 'reason'],
          properties: {
            file: { type: 'string' },
            reason: { type: 'string' },
            offendingLine: { type: 'string' },
          },
        },
      },
    },
  }

  const parserPreflight = await agent(
    `Run this Bash script and parse its JSON stdout. The script enumerates pending issue files in ${issuesDir} (NN-*.md, no done- prefix) and validates each one's "## Blocked by" section against the same regex /run-all-issues uses (see ~/.claude/skills/run-all-issues/SKILL.md:40-59 — backtick form OR hash form OR single "None" shortcut).

\`\`\`bash
set -euo pipefail
# issuesDir is wrapped as a POSIX single-quoted shell literal (defangs $-expansion / command-substitution).
ISSUES_DIR=${shellQuote(issuesDir)}
[ ! -d "$ISSUES_DIR" ] && echo '{"pendingFiles":[],"parserFailures":[]}' && exit 0

# Bash 3.2 compatible — no mapfile, no <<<; macOS default bash is 3.2.

emit_failure() {
  # args: $1=file basename, $2=reason, $3=offendingLine (may be empty)
  printf '{"file":%s,"reason":%s,"offendingLine":%s}\n' \
    "$(jq -Rn --arg s "$1" '$s')" \
    "$(jq -Rn --arg s "$2" '$s')" \
    "$(jq -Rn --arg s "$3" '$s')"
}

PENDING_LIST=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'done-*' | sort)

# /run-all-issues preflight step 3 invariant: every file in issues/ must match
# ^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$ AND NN must be unique across pending+done.
# Detect filenames that violate the shape — they would crash /run-all-issues at
# preflight step 3 before any drain. Surface them as parserFailures so the
# parserPass hard gate fires.
SHAPE_BAD=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' \
  | sed -E 's|^.*/||' \
  | grep -Ev '^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$' || true)
if [ -n "$SHAPE_BAD" ]; then
  while IFS= read -r bn; do
    [ -z "$bn" ] && continue
    emit_failure "$bn" 'Filename violates /run-all-issues invariant ^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$ — would crash preflight step 3' "" >> "$FAILURES_FILE"
  done <<EOF_BAD
$SHAPE_BAD
EOF_BAD
fi

# Duplicate-NN detection: stripping the optional done- prefix and the slug suffix,
# the NN must be unique across the directory. Both 03-foo.md and done-03-bar.md
# present is a conflict per /run-all-issues preflight step 3.
DUP_NNS=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
  | sed -E 's|.*/(done-)?([0-9]{2,})-[a-z0-9-]+\.md|\2|' \
  | grep -E '^[0-9]{2,}$' \
  | sort | uniq -d || true)
if [ -n "$DUP_NNS" ]; then
  for nn in $DUP_NNS; do
    DUPS=$(find "$ISSUES_DIR" -maxdepth 1 -type f \( -name "$nn-*.md" -o -name "done-$nn-*.md" \) | sed 's|^.*/||' | tr '\n' ' ')
    emit_failure "$nn" "Duplicate NN $nn — multiple files share this number: $DUPS" "" >> "$FAILURES_FILE"
  done
fi

# Build the set of valid blocker numbers (NN) from filenames: pending NN-*.md OR done-NN-*.md
# Used by /run-all-issues preflight step 9: "blocker NN must reference an existing issue file".
ALL_NNS=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
  | sed -E 's|.*/(done-)?([0-9]{2,})-[a-z0-9-]+\.md|\2|' \
  | grep -E '^[0-9]{2,}$' \
  | sort -u || true)

FAILURES_FILE=$(mktemp)
PENDING_FILE=$(mktemp)
trap 'rm -f "$FAILURES_FILE" "$PENDING_FILE"' EXIT

# Iterate via heredoc to preserve outer-shell state across loop body
while IFS= read -r f; do
  [ -z "$f" ] && continue
  bn=$(basename "$f")
  printf '%s\n' "$bn" >> "$PENDING_FILE"
  # Extract section body between "## Blocked by" and next "## " or EOF
  body=$(awk '
    /^##[ \t]+Blocked by[ \t]*$/ {in_sec=1; next}
    in_sec && /^##[ \t]/ {exit}
    in_sec {print}
  ' "$f")

  # No section → no blockers, OK
  [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ] && continue

  # Single-line "None" shortcut — case-SENSITIVE [Nn]one only, mirroring
  # /run-all-issues/SKILL.md:49 regex \`^[ \t]*[Nn]one\b.*$\`
  non_blank_lines=$(printf '%s\n' "$body" | grep -vE '^[[:space:]]*$' || true)
  non_blank_count=$(printf '%s\n' "$non_blank_lines" | grep -c '.' || true)
  if [ "$non_blank_count" = "1" ] && printf '%s' "$non_blank_lines" | grep -qE '^[[:space:]]*[Nn]one([^[:alnum:]_]|$)'; then
    continue
  fi
  # Mixed "None" + other lines → fail (same case-sensitive matcher)
  if printf '%s' "$non_blank_lines" | grep -qE '^[[:space:]]*[Nn]one([^[:alnum:]_]|$)'; then
    bad_line=$(printf '%s\n' "$non_blank_lines" | grep -E '^[[:space:]]*[Nn]one([^[:alnum:]_]|$)' | head -1)
    emit_failure "$bn" 'Mixed None shortcut with other bullets (not allowed)' "$bad_line" >> "$FAILURES_FILE"
    continue
  fi

  # Every non-blank line must match backtick form OR hash form.
  # Both regexes mirror /run-all-issues/SKILL.md:51-52 — the hash form uses a
  # word-boundary equivalent ([^[:alnum:]_]|$) instead of GNU \b so that #10x
  # (digit→letter, both word chars) is rejected — same semantics as \b in /run-all-issues.
  fail_this=""
  fail_tmp=$(mktemp)
  printf '%s\n' "$non_blank_lines" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    if printf '%s' "$line" | grep -qE '^[[:space:]]*[-*+][[:space:]]+\`(done-)?[0-9]{2,}-[a-z0-9-]+\.md\`'; then continue; fi
    if printf '%s' "$line" | grep -qE '^[[:space:]]*[-*+][[:space:]]+#[0-9]{2,}([^[:alnum:]_]|$)'; then continue; fi
    printf '%s' "$line" > "$fail_tmp"
    break
  done
  fail_this=$(cat "$fail_tmp")
  rm -f "$fail_tmp"

  if [ -n "$fail_this" ]; then
    emit_failure "$bn" 'Unparseable Blocked by line (neither backtick \`NN-slug.md\` form nor hash #NN form)' "$fail_this" >> "$FAILURES_FILE"
    continue
  fi

  # Existence check — mirror /run-all-issues SKILL.md step 9: every referenced
  # blocker NN must exist as either NN-*.md or done-NN-*.md in the directory.
  # Extract NN from every well-formed bullet (both backtick and hash forms).
  # Note: the boundary check already happened in the earlier shape-validation
  # loop, so sed here can use a simpler trailing match without alternation
  # (BSD sed -E has trouble with `([^[:alnum:]_]|$)` capture groups).
  ref_nns=$(printf '%s\n' "$non_blank_lines" | sed -nE \
    -e 's|^[[:space:]]*[-*+][[:space:]]+\`(done-)?([0-9]{2,})-[a-z0-9-]+\.md\`.*|\2|p' \
    -e 's|^[[:space:]]*[-*+][[:space:]]+#([0-9]{2,}).*|\1|p' \
    | sort -u)
  missing_nn=""
  for nn in $ref_nns; do
    if ! printf '%s\n' "$ALL_NNS" | grep -qx "$nn"; then
      missing_nn="$nn"
      break
    fi
  done
  if [ -n "$missing_nn" ]; then
    bad_line=$(printf '%s\n' "$non_blank_lines" | grep -E "(\`(done-)?$missing_nn-|#$missing_nn([^[:alnum:]_]|$))" | head -1)
    emit_failure "$bn" "References nonexistent blocker $missing_nn (no NN-*.md or done-NN-*.md)" "$bad_line" >> "$FAILURES_FILE"
  fi
done <<EOF_LIST
$PENDING_LIST
EOF_LIST

# Emit JSON object
if [ -s "$PENDING_FILE" ]; then
  pending_json=$(jq -R . < "$PENDING_FILE" | jq -s .)
else
  pending_json='[]'
fi
if [ -s "$FAILURES_FILE" ]; then
  failures_json=$(jq -s . < "$FAILURES_FILE")
else
  failures_json='[]'
fi
jq -n --argjson p "$pending_json" --argjson f "$failures_json" '{pendingFiles: $p, parserFailures: $f}'
\`\`\`

Return the parsed JSON object verbatim.`,
    {
      schema: PARSER_SCHEMA,
      label: 'parser-preflight',
      phase: 'Lens-fanout',
    },
  )

  const pendingFiles = parserPreflight.pendingFiles || []
  const parserFailures = parserPreflight.parserFailures || []

  // ----- Step 2: Build the issue-bundle file (deterministic — pure shell cat) -----
  // Each lens dispatch will `cat $BUNDLE_PATH` in its heredoc, the same pattern
  // PRD mode uses (`cat <prd_or_tempfile>`). The bundle is built via Bash, not
  // an LLM, per ~/.claude/injected-rules/model-judgment-only.md — concat is
  // deterministic data transformation, not judgment.
  const BUNDLE_BUILD_SCHEMA = {
    type: 'object',
    required: ['bundlePath'],
    properties: { bundlePath: { type: 'string' } },
  }

  const bundleBuild = pendingFiles.length === 0
    ? { bundlePath: '' }
    : await agent(
      `Run this Bash script and parse its JSON stdout:

\`\`\`bash
set -euo pipefail
# issuesDir is wrapped as a POSIX single-quoted shell literal (defangs $-expansion / command-substitution).
ISSUES_DIR=${shellQuote(issuesDir)}
BUNDLE_PATH=$(mktemp -t issues-bundle.XXXXXX)
for f in ${pendingFiles.map(f => shellQuote(f)).join(' ')}; do
  printf '===== ISSUE FILE: %s =====\n' "$f" >> "$BUNDLE_PATH"
  cat "$ISSUES_DIR/$f" >> "$BUNDLE_PATH"
  printf '\n' >> "$BUNDLE_PATH"
done
jq -n --arg p "$BUNDLE_PATH" '{bundlePath: $p}'
\`\`\`

Return the parsed JSON object verbatim.`,
      {
        schema: BUNDLE_BUILD_SCHEMA,
        label: 'issue-bundle-build',
        phase: 'Lens-fanout',
      },
    )
  const bundlePath = bundleBuild.bundlePath

  // ----- Step 3: Decide lens roster (auto-drop Coverage when no PARENT_PRD) -----
  const DEFAULT_ROSTER = ['Slicer', 'DependencyAuditor', 'Granularity', 'AcceptanceCriteria', 'Coverage']
  let effectiveRoster = (Array.isArray(lensRoster) && lensRoster.length > 0)
    ? [...lensRoster]
    : [...DEFAULT_ROSTER]
  if (!hasPrd && effectiveRoster.includes('Coverage')) {
    log('issues: Coverage lens dropped from roster — no PARENT_PRD in contextFiles')
    effectiveRoster = effectiveRoster.filter(l => l !== 'Coverage')
  }

  // ----- Step 4: Compose context block (PARENT_PRD + others) and wont-fix block -----
  // Filter wont-fix entries down to "effective" entries (BOTH issueFile and anchor present).
  // The same effective list feeds lens prompts AND the progression-check ledger fold —
  // single source of truth prevents the previous skew where lens prompts said
  // "do NOT re-flag [id]" but progression silently treated the entry as inactive.
  const effectiveLedger = wontfix.filter(w => w && w.issueFile && w.anchor)
  const ledgerEntriesSkipped = wontfix
    .filter(w => !w || !w.issueFile || !w.anchor)
    .map(w => (w && w.id) || '(unknown)')

  const ctxBlock = ctxFiles.length === 0
    ? ''
    : `\n\nPROJECT CONTEXT (injected — reviewer MUST cross-check issues against these):\n${
        ctxFiles.map(c => `\n--- ${c.label} (${c.path}) ---\n${c.content}`).join('\n')
      }\n--- end project context ---\n`

  const wontfixBlock = effectiveLedger.length === 0
    ? ''
    : `\n\nWONT-FIX LEDGER (already-decided exclusions — do NOT re-flag these unless you have NEW evidence the decision is wrong):\n${
        effectiveLedger.map(w => `- [${w.id}] ${w.severity} (decided round ${w.decidedRoundN} via ${w.source}): ${w.issueFile}::${w.anchor} — ${w.rationale}`).join('\n')
      }\n--- end wont-fix ---\n`

  // ----- Step 5: Issues finding schema (per lens) -----
  // anchor + issueFile are BOTH required — downstream merge / progression / wont-fix
  // all key on `<issueFile>::<anchor>`. Allowing missing anchor lets findings validate
  // then silently corrupt dedup, coverage tracking, and wont-fix matching.
  const ISSUES_FINDINGS_SCHEMA = {
    type: 'object',
    required: ['findings'],
    properties: {
      findings: {
        type: 'array',
        items: {
          type: 'object',
          required: ['severity', 'category', 'issueFile', 'anchor', 'description'],
          properties: {
            severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
            category: {
              enum: [
                'VERTICAL_SLICE',
                'DEPENDENCIES',
                'GRANULARITY',
                'ACCEPTANCE_CRITERIA',
                'COVERAGE',
                'SUBTRACTABILITY',
                'CONSISTENCY',
              ],
            },
            issueFile: {
              type: 'string',
              description: 'Issue filename (e.g. "03-foo.md") or "GLOBAL" for set-wide findings',
            },
            anchor: {
              type: 'string',
              description: 'Stable identifier within the issue (e.g. "AC-2", "Blocked-by:NN", "Title", "MATRIX-SUMMARY") for cross-round dedup',
            },
            description: { type: 'string' },
          },
        },
      },
    },
  }

  // ----- Step 5b: per-lens-result schema (wraps findings with status for fail-closed detection) -----
  // Lens dispatch failures (CLI/quota/parse errors) MUST be visible — silently coercing to
  // {findings: []} would let a transient backend hiccup look like LGTM and the loop EXIT
  // with zero coverage by that lens. status='failed' bubbles up to a synthetic parserFailure
  // that the parserPass hard gate catches.
  const ISSUES_LENS_RESULT_SCHEMA = {
    type: 'object',
    required: ['status', 'findings'],
    properties: {
      status: { enum: ['ok', 'empty', 'failed'] },
      reason: { type: 'string' },
      findings: ISSUES_FINDINGS_SCHEMA.properties.findings,
    },
  }

  // ----- Step 6: Lens fan-out -----
  log(`issues: dispatching ${effectiveRoster.length} lenses to ${backend} over ${pendingFiles.length} pending issue files: ${effectiveRoster.join(', ')}`)

  async function dispatchIssuesLens(lens) {
    return agent(
      `Dispatch the ${lens} issues-review lens via the ${backend} CLI.

      1. Read ~/.claude/skills/review-with-agent/lenses/issues/${lens}.md for this lens's checklist and output format.
      2. Dispatch using this exact Bash pipeline (heredoc + cat for the bundle file — avoids shell arg length limits and avoids LLM-mangling the bundle):

         \`\`\`bash
         { cat <<'PROMPT_HEAD'
         <lens checklist from step 1>

         ISSUE BUNDLE (all pending issues for this feature, concatenated below):
         PROMPT_HEAD
         cat ${shellQuote(bundlePath)}
         cat <<'PROMPT_TAIL'
         ${ctxBlock.replace(/\n/g, '\n         ')}
         ${wontfixBlock.replace(/\n/g, '\n         ')}
         PROMPT_TAIL
         } | ${BACKEND.planDispatch}
         \`\`\`

      3. Filter banner noise with: ${BACKEND.noiseFilter}
      4. Detect outcome:
         - Failure: empty output OR matches /Retry attempts exhausted|Error executing tool|NumericalClassifier/.
           Return {status: 'failed', reason: '<short summary of what failed>', findings: []}.
         - Empty (legitimate LGTM): output is literally "LGTM" or contains zero parseable findings.
           Return {status: 'empty', findings: []}.
         - OK: at least one parseable finding. Return {status: 'ok', findings: [...]}.
      5. Parse each non-noise non-LGTM line into a finding {severity, category, issueFile, anchor, description}.
         The lens output format is: \`<Severity>|<Category>|<IssueFile>|<Anchor>|<Description>\`
         Set category to the lens's primary dimension when ambiguous (lens file documents which).
         **Both issueFile AND anchor MUST be present in every finding** — the schema rejects missing values.
      Return the lens-result object matching the schema.`,
      {
        schema: ISSUES_LENS_RESULT_SCHEMA,
        label: `issues-lens:${lens}`,
        phase: 'Lens-fanout',
      },
    )
  }

  const lensResults = await parallel(effectiveRoster.map(l => () => dispatchIssuesLens(l)))

  // Surface failed lenses as synthetic parserFailures so the hard gate fires.
  // Per /run-all-issues semantics, parserPass blocks EXIT — and a silently-failed
  // lens is exactly the "scored zero coverage by that dimension" hazard that should
  // block EXIT until the operator notices.
  for (let i = 0; i < lensResults.length; i++) {
    const r = lensResults[i]
    if (r && r.status === 'failed') {
      parserFailures.push({
        file: '__lens__',
        reason: `Lens '${effectiveRoster[i]}' dispatch failed: ${r.reason || 'unknown reason'} — fail-closed (parserPass blocks EXIT)`,
      })
    }
  }

  // Tag each finding with originating lens (only ok status produces findings)
  const taggedFindings = lensResults.flatMap((r, i) => {
    const lens = effectiveRoster[i]
    return (r?.findings || []).map(f => ({ ...f, lenses: [lens] }))
  })

  // ----- Step 7: Synthesize — merge by (issueFile, anchor) -----
  phase('Synthesize')

  const MERGED_ISSUES_SCHEMA = {
    type: 'object',
    required: ['findings'],
    properties: {
      findings: {
        type: 'array',
        items: {
          type: 'object',
          required: ['severity', 'category', 'issueFile', 'anchor', 'description', 'lenses'],
          properties: {
            severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
            category: { type: 'string' },
            issueFile: {
              type: 'string',
              description: 'Issue filename (e.g. "03-foo.md") or "GLOBAL" for set-wide findings',
            },
            anchor: {
              type: 'string',
              description: 'Stable identifier within the issue (e.g. "AC-2", "Blocked-by:NN", "Title", "MATRIX-SUMMARY") for cross-round dedup',
            },
            description: { type: 'string' },
            lenses: { type: 'array', items: { type: 'string' }, minItems: 1 },
          },
        },
      },
    },
  }

  const merged = taggedFindings.length === 0
    ? { findings: [] }
    : await agent(
      `Merge these per-lens issues findings, deduping by semantic equivalence at (issueFile, anchor).
       Two findings dedup when they refer to the same issueFile AND same anchor AND describe the same problem.
       When merging duplicates: union the lenses array, keep the highest severity.
       Drop nothing unique.

       Input: ${JSON.stringify(taggedFindings)}

       Return {findings: [...]} per the schema.`,
      {
        schema: MERGED_ISSUES_SCHEMA,
        label: 'merge-issues',
        phase: 'Synthesize',
      },
    )

  // ----- Step 8: Verdict -----
  // PRD-lens-fanout style: 0 Blocking → PASS; ≥2-lens agreement on Blocking → REJECT; single-lens Blocking → CONTESTED.
  // Plus the deterministic hard override: parserFailures.length > 0 → REJECT regardless of LLM verdict.
  const blockers = merged.findings.filter(f => f.severity === 'Blocking')
  const multiLensBlockers = blockers.filter(f => f.lenses.length >= 2)
  let verdict
  if (parserFailures.length > 0) {
    verdict = 'REJECT'   // hard override — parser failure cannot be voted away
  } else if (blockers.length === 0) {
    verdict = 'PASS'
  } else if (multiLensBlockers.length > 0) {
    verdict = 'REJECT'
  } else {
    verdict = 'CONTESTED'
  }

  // Cleanup bundle tempfile (best-effort; ignore failure if file was never created or already gone)
  if (bundlePath) {
    await agent(`Run: rm -f ${shellQuote(bundlePath)}`, { label: 'cleanup-bundle', phase: 'Synthesize' })
  }

  return {
    mode: 'issues',
    execPath: 'lens-fanout',
    verdict,
    modeLabel: BACKEND.modeLabel,
    lensRoster: effectiveRoster,
    issueFilesReviewed: pendingFiles,
    parserFailures,
    lensResults: lensResults.map((r, i) => ({
      lens: effectiveRoster[i],
      status: r?.status || 'failed',
      findingCount: (r?.findings || []).length,
      reason: r?.reason,
    })),
    findings: merged.findings,
    stats: {
      total: merged.findings.length,
      blockers: blockers.length,
      multiLensBlockers: multiLensBlockers.length,
      parserFailureCount: parserFailures.length,
      contextFilesInjected: ctxFiles.length,
      wontfixEntriesApplied: effectiveLedger.length,
      ledgerEntriesSkipped,        // wont-fix entries missing issueFile or anchor
    },
  }
}

// ============================================================
// Code Review mode
// ============================================================

// Phase 2 — Prep-diff (pure Bash wrapper; agent is a thin shell of jq + parse)
phase('Prep-diff')

const PREP_SCHEMA = {
  type: 'object',
  required: ['scale', 'lines', 'dirs', 'tmpdir', 'challengerDiffPath', 'subtractorDiffPath', 'contextFlag', 'testFiles', 'largeFileCount', 'budgetTruncated', 'excludedCount'],
  properties: {
    scale: { enum: ['Light', 'Medium', 'Heavy'] },
    lines: { type: 'integer' },
    dirs: { type: 'integer' },
    totalFiles: { type: 'integer' },
    filteredFiles: { type: 'integer' },
    excludedCount: { type: 'integer' },
    tmpdir: { type: 'string' },
    challengerDiffPath: { type: 'string' },
    subtractorDiffPath: { type: 'string' },
    contextFlag: { type: 'string' },
    largeFileCount: { type: 'integer' },
    largeFiles: { type: 'array', items: { type: 'string' } },
    budgetTruncated: { type: 'integer' },
    testFiles: { type: 'array', items: { type: 'string' } },
  },
}

const prep = await agent(
  `Run this Bash command and parse its JSON stdout (it's a single JSON object):

  ~/.claude/scripts/review-prep-diff.sh ${BACKEND.tmpdirPrefix}

  If the script exits non-zero (2 = not a git repo / nothing to review, 3 = no eligible files, 4 = prep failure), return an error.
  Otherwise return the parsed JSON object verbatim.`,
  {
    schema: PREP_SCHEMA,
    label: 'prep-diff',
    phase: 'Prep-diff',
  },
)

// Phase 3 — Intent
phase('Intent')

const intent = await agent(
  `Read ${prep.challengerDiffPath}. Write a 1-2 sentence statement of what this change is trying to accomplish.
   Return just the statement as plain text — no preamble.`,
  {
    label: 'intent',
    phase: 'Intent',
  },
)

// Phase 4 — Lens fan-out + Red-line scan (parallel)
phase('Lens-fanout')

const lenses = [...LENS_ROSTER[prep.scale]]
if (prep.testFiles && prep.testFiles.length > 0) lenses.push('TestHygiene')

log(`Scale=${prep.scale}, dispatching ${lenses.length} lenses: ${lenses.join(', ')}, redLine=true`)

async function dispatchLens(lens) {
  const inputPath = prep[LENS_INPUT[lens]]
  const dispatchCmd = LENS_USES_READONLY.has(lens) ? BACKEND.readonlyDispatch : BACKEND.dispatch

  return agent(
    `Dispatch the ${lens} lens via the ${backend} CLI.

    1. Read ~/.claude/skills/review-with-agent/lenses/${lens}.md for the lens checklist + output format.
    2. Compose the prompt: [lens checklist from file] + "Intent: ${intent.replace(/"/g, '\\"').slice(0, 500)}"
    3. Dispatch using this exact Bash pipeline (heredoc — avoids shell arg length limits):

       \`\`\`bash
       { cat ${inputPath}; cat <<'PROMPT'
       ---
       <full lens prompt from step 2>
       PROMPT
       } | ${dispatchCmd}
       \`\`\`

       ${lens === 'Integration' ? `Note: Integration lens needs READ-ONLY codebase access — the dispatch command above already provides it.` : ''}

    4. Filter banner noise with: ${BACKEND.noiseFilter}
    5. Detect failure: empty output OR matches /Retry attempts exhausted|Error executing tool|NumericalClassifier/.
       Set status='failed' on failure. Set status='empty' if output is literally "LGTM" or contains zero parseable findings. Otherwise status='ok'.
    6. Parse each non-noise line as one finding: \`<Sev> [New|Pre-existing] file:line description\`.
       For TestHygiene: description starts with item letter (a-o).
       For Integration: description includes affected caller path.
    7. Cap Suggestion findings at 10 (spam guard); leave Blocking and Required uncapped so multi-lens REJECT signal and real bugs aren't silently dropped. Truncate each description to 3 lines if needed.
    8. Return the schema with lens="${lens}".`,
    {
      schema: LENS_RESULT_SCHEMA,
      label: `lens:${lens}`,
      phase: 'Lens-fanout',
    },
  )
}

async function redLineScan() {
  return agent(
    `Red-line scan against the diff at ${prep.challengerDiffPath}:

    1. Project constraints — Read CLAUDE.md, AGENTS.md, .ai/constraints.json from the repo root if they exist. Check the diff against any constraints they define.
    2. Universal red-lines — Grep the diff for:
       - eval() / innerHTML / dangerouslySetInnerHTML with user-controlled input
       - Hardcoded secrets, API keys, tokens
       - Unvalidated process.env usage in security-sensitive paths

    Every violation is a Blocking finding with origin='New' (red-line violations are always triggered by the diff).
    Description should start with "[Red-Line]".
    Return the schema with lens="RedLine".
    If no violations found, status='empty', findings=[].`,
    {
      schema: LENS_RESULT_SCHEMA,
      label: 'red-line',
      phase: 'Lens-fanout',
    },
  )
}

// Dispatch all lenses + red-line in parallel
const firstPassResults = await parallel([
  ...lenses.map(lens => () => dispatchLens(lens)),
  () => redLineScan(),
])

// Workflow-native retry: re-run any lens that returned status='failed'
const failedLenses = firstPassResults
  .map((r, i) => r?.status === 'failed' ? { result: r, lens: r.lens, isRedLine: i === lenses.length } : null)
  .filter(Boolean)

let retryResults = []
if (failedLenses.length > 0) {
  log(`Retrying ${failedLenses.length} failed lens(es): ${failedLenses.map(f => f.lens).join(', ')}`)
  retryResults = await parallel(
    failedLenses.map(f => () => f.isRedLine ? redLineScan() : dispatchLens(f.lens))
  )
}

// Merge first-pass + retry: prefer retry when first failed
const lensResults = firstPassResults.map((r, i) => {
  if (r?.status !== 'failed') return r
  const retried = retryResults[failedLenses.findIndex(f => f.lens === r.lens)]
  if (retried && retried.status !== 'failed') return retried
  return { ...r, status: 'failed', findings: [] }
}).filter(Boolean)

// ============================================================
// Phase 5 — Synthesize (merge + verify [New] Required/Blocking)
// ============================================================
phase('Synthesize')

// 5a. Merge across lenses (LLM judgment: semantic dedup at file:line)
const allFindingsByLens = lensResults.map(r => ({
  lens: r.lens,
  findings: r.findings || [],
}))

const totalRawFindings = allFindingsByLens.reduce((sum, l) => sum + l.findings.length, 0)

let merged
if (totalRawFindings === 0) {
  merged = { findings: [] }
} else {
  merged = await agent(
    `Merge these per-lens findings, deduping by semantic equivalence at (file, line).
     Two findings dedup when they describe the same issue at the same location.
     When merging duplicates: union the lenses array, keep the highest severity.
     Drop nothing unique.

     Input: ${JSON.stringify(allFindingsByLens)}

     Return {findings: [<MergedFinding>...]}.`,
    {
      schema: { type: 'object', required: ['findings'], properties: { findings: { type: 'array', items: MERGED_FINDING_SCHEMA } } },
      label: 'merge',
      phase: 'Synthesize',
    },
  )
}

// 5b. Verify every [New] Required|Blocking finding against the worktree (A6 contract)
const toVerify = merged.findings
  .map((f, i) => ({ ...f, _idx: i }))
  .filter(f => f.origin === 'New' && (f.severity === 'Required' || f.severity === 'Blocking'))

const verified = toVerify.length === 0 ? [] : await parallel(toVerify.map(f => () => agent(
  `Verify this finding against the actual worktree before writing a Decision:

  Finding #${f._idx}: ${f.severity} [${f.origin}] ${f.file}:${f.line} — ${f.description}
  Lenses: ${f.lenses.join(', ')}

  Use whichever source fits the path:
  - Read / Grep on the worktree for modified or untracked files
  - \`git show :${f.file}\` for staged content
  - \`git show HEAD:${f.file}\` or \`git diff\` for deleted/renamed paths

  Decide:
  - Accept = finding is valid (real bug / valid concern)
  - Dismiss = false positive / acceptable trade-off / no longer applies

  Never judge from diff context alone — open the file.
  Return {findingIndex: ${f._idx}, decision, rationale, evidence}.`,
  {
    schema: VERIFY_SCHEMA,
    label: `verify:${f.file}:${f.line}`,
    phase: 'Synthesize',
  },
)))

const verifiedById = verified.filter(Boolean).reduce((acc, v) => {
  acc[v.findingIndex] = v
  return acc
}, {})

// 5c. Verdict — pure code
const newFindings = merged.findings.filter(f => f.origin === 'New')
const newBlockers = newFindings.filter(f => f.severity === 'Blocking')
const redLineNew = newBlockers.filter(f => f.description.startsWith('[Red-Line]') || f.lenses.includes('RedLine'))
const multiLensBlockers = newBlockers.filter(f => f.lenses.length >= 2)

let verdict
if (newBlockers.length === 0) verdict = 'PASS'
else if (redLineNew.length > 0 || multiLensBlockers.length > 0) verdict = 'REJECT'
else verdict = 'CONTESTED'

// 5d. Summary paragraph
const summary = await agent(
  `Write a one-paragraph conclusion + next-steps statement for this code review.

   Verdict: ${verdict}
   Scale: ${prep.scale}
   Mode: ${BACKEND.modeLabel}
   Total findings: ${merged.findings.length} (${newFindings.length} New, ${merged.findings.length - newFindings.length} Pre-existing)
   New Blockers: ${newBlockers.length} (${redLineNew.length} red-line, ${multiLensBlockers.length} multi-lens agreement)
   Lenses run: ${lensResults.map(r => `${r.lens}=${r.status}`).join(', ')}

   Keep it tight — one paragraph max, no headers, no bullet list.`,
  {
    label: 'summary',
    phase: 'Synthesize',
  },
)

// Cleanup tmpdir
await agent(`Run: rm -rf ${prep.tmpdir}`, { label: 'cleanup', phase: 'Synthesize' })

return {
  mode: 'code',
  verdict,
  scale: prep.scale,
  modeLabel: BACKEND.modeLabel,
  intent,
  filtered: {
    excludedCount: prep.excludedCount,
    largeFileCount: prep.largeFileCount,
    budgetTruncated: prep.budgetTruncated,
  },
  lensResults: lensResults.map(r => ({ lens: r.lens, status: r.status, findingCount: (r.findings || []).length })),
  findings: merged.findings.map((f, i) => ({
    ...f,
    verification: verifiedById[i] || null,
  })),
  stats: {
    total: merged.findings.length,
    new: newFindings.length,
    newBlockers: newBlockers.length,
    redLineBlockers: redLineNew.length,
    multiLensBlockers: multiLensBlockers.length,
  },
  summary,
}
