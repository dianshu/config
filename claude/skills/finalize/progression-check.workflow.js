export const meta = {
  name: 'finalize-progression-check',
  description: 'Compute the 5-of-3 Progression Check deterministically from /codex-review + /opencode-review outputs. Parsing uses LLM (free-form prose -> findings); scoring is pure code.',
  phases: [
    { title: 'Parse', detail: 'parse codex + opencode outputs into structured findings (parallel)' },
    { title: 'Merge', detail: 'dedup across reviewers by (file, line, semantic equivalence)' },
    { title: 'Score', detail: 'compute 4 auto-evaluable criteria from counts; leave Coverage for parent' },
  ],
}

const { codexOutput, opencodeOutput, priorRoundFindingCount, roundNum } = args

if (typeof codexOutput !== 'string' || typeof opencodeOutput !== 'string' || typeof roundNum !== 'number') {
  throw new Error('progression-check: required args {codexOutput: string, opencodeOutput: string, roundNum: number, priorRoundFindingCount?: number|null}')
}

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

const FINDINGS_ENVELOPE_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: { type: 'array', items: FINDING_ITEM_SCHEMA },
  },
}

phase('Parse')

const PARSE_INSTRUCTION = `Parse the review output below into structured findings.
- Each line typically looks like: \`<Severity> [New|Pre-existing] file:line description\`
- Severity is one of: Blocking, Required, Suggestion
- Origin is exactly: New or Pre-existing
- If a finding has no line number, use the string "N/A"
- If the entire output is "LGTM" / empty / banner noise only, return {findings: []}
- Do NOT invent findings that are not in the output
- Do NOT filter findings — return all of them

Output:
`

const [codex, opencode] = await parallel([
  () => agent(`${PARSE_INSTRUCTION}\n${codexOutput}`, {
    schema: FINDINGS_ENVELOPE_SCHEMA,
    label: 'parse:codex',
    phase: 'Parse',
  }),
  () => agent(`${PARSE_INSTRUCTION}\n${opencodeOutput}`, {
    schema: FINDINGS_ENVELOPE_SCHEMA,
    label: 'parse:opencode',
    phase: 'Parse',
  }),
])

const codexFindings = (codex?.findings || []).map(f => ({ ...f, lenses: ['codex'] }))
const opencodeFindings = (opencode?.findings || []).map(f => ({ ...f, lenses: ['opencode'] }))

phase('Merge')

const MERGE_INSTRUCTION = `Dedup these findings across reviewers.
Two findings are the same when they refer to the same (file, line) and describe semantically the same issue.
When merging, union the \`lenses\` arrays (e.g. ['codex'] + ['opencode'] -> ['codex', 'opencode']).
Keep the highest severity if they disagree.
Do not drop any unique findings.

Input:
${JSON.stringify({ codex: codexFindings, opencode: opencodeFindings })}`

const MERGED_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'origin', 'file', 'line', 'description', 'lenses'],
        properties: {
          severity: { enum: ['Blocking', 'Required', 'Suggestion'] },
          origin: { enum: ['New', 'Pre-existing'] },
          file: { type: 'string' },
          line: { type: ['integer', 'string'] },
          description: { type: 'string' },
          lenses: {
            type: 'array',
            items: { enum: ['codex', 'opencode'] },
            minItems: 1,
          },
        },
      },
    },
  },
}

const merged = (codexFindings.length === 0 && opencodeFindings.length === 0)
  ? { findings: [] }
  : await agent(MERGE_INSTRUCTION, { schema: MERGED_SCHEMA, label: 'merge', phase: 'Merge' })

phase('Score')

const all = merged.findings
const newFindings = all.filter(f => f.origin === 'New')
const blockers = newFindings.filter(f => f.severity === 'Blocking').length
const blockerRatio = newFindings.length > 0 ? blockers / newFindings.length : 0

const hasPriorRound = priorRoundFindingCount != null && typeof priorRoundFindingCount === 'number'
const findingDelta = hasPriorRound ? (all.length - priorRoundFindingCount) : null
const diffStabilityThreshold = hasPriorRound ? Math.max(1, Math.floor(priorRoundFindingCount * 0.2)) : null

const criteria = {
  coverage: null,
  diminishingSeverity: newFindings.length === 0 ? true : blockerRatio < 0.2,
  diffStability: hasPriorRound ? (findingDelta <= diffStabilityThreshold) : null,
  minimumRounds: roundNum >= 1,
  reviewerAcknowledgment: blockers === 0,
}

const autoEvaluable = Object.entries(criteria).filter(([, v]) => v !== null)
const satisfied = autoEvaluable.filter(([, v]) => v === true).length
const total = autoEvaluable.length
const shouldExit = satisfied >= 3

const byFile = all.reduce((acc, f) => {
  (acc[f.file] = acc[f.file] || []).push(f)
  return acc
}, {})

return {
  verdict: shouldExit ? 'EXIT' : 'CONTINUE',
  satisfied,
  total,
  criteria,
  mergedFindings: all,
  byFile,
  stats: {
    totalFindings: all.length,
    newFindings: newFindings.length,
    newBlockers: blockers,
    blockerRatio: Math.round(blockerRatio * 100) / 100,
    priorRoundFindingCount: hasPriorRound ? priorRoundFindingCount : null,
    findingDelta,
    diffStabilityThreshold,
  },
  parentMustConfirm: {
    coverage: 'Confirm every prior-round issue was either fixed or moved to wont-fix before the next round.',
  },
}
