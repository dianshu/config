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
  contextFiles,
  wontfixLedger,
  lensRoster,
} = args || {}

if (!backend || !BACKEND_CONFIG[backend]) {
  throw new Error(`review-with-agent: args.backend must be one of: ${Object.keys(BACKEND_CONFIG).join(', ')}`)
}
if (mode !== 'code' && mode !== 'plan' && mode !== 'prd') {
  throw new Error(`review-with-agent: args.mode must be 'code', 'plan', or 'prd'`)
}
if (mode === 'plan' && !planPath && !planContent) {
  throw new Error(`review-with-agent: plan mode requires args.planPath or args.planContent`)
}
if (mode === 'prd' && !prdPath && !prdContent) {
  throw new Error(`review-with-agent: prd mode requires args.prdPath or args.prdContent`)
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
