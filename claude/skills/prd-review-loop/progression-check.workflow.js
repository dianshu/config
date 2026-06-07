export const meta = {
  name: 'prd-review-loop-progression-check',
  description: 'Deterministic 3-of-5 Progression Check for /prd-review-loop. 3 criteria computed as pure code, 1 semi-deterministic (H2 section diff), 1 (coverage) left for parent. Folds wont-fix ledger into scoring so reviewer-re-raised exclusions do not block exit.',
  phases: [
    { title: 'Score', detail: 'compute auto-evaluable criteria + apply wont-fix folding + escape-hatch eligibility' },
  ],
}

const {
  // From this round's review.workflow.js prd-mode output (single-pass or lens-fanout)
  findings,                       // [{severity, category, section, anchor, description, lenses?}]
  roundNum,                       // 1-based
  // Bookkeeping carried across rounds by the parent
  priorRoundFindingCount,         // number | null (null on round 1)
  priorRoundAnchors,              // string[] (anchors from previous round, for coverage tracking)
  // From P0-2 context injection + P1-6 wont-fix ledger
  wontfixLedger,                  // [{id, severity, source, rationale, decidedRoundN}]
  // From P0-3 position-stability check
  thisRoundH2Sections,            // string[] of H2 section names present this round
  priorRoundH2Sections,           // string[] of H2 section names present previous round (null on round 1)
  thisRoundBodyBytes,             // total non-whitespace byte count of PRD body this round
  priorRoundBodyBytes,            // number | null
  // From escape-hatch eligibility check
  escapeHatchAlreadyUsed,         // boolean (parent tracks whether this loop instance has used it)
  // Parent must confirm Coverage before EXIT
  parentConfirmsCoverage,         // boolean | undefined (undefined = parent has not confirmed yet)
} = args

if (!Array.isArray(findings)) {
  throw new Error('progression-check: required arg {findings: array}')
}
if (typeof roundNum !== 'number' || roundNum < 1) {
  throw new Error('progression-check: roundNum must be integer >= 1')
}

phase('Score')

// ----- Fold wont-fix ledger -----
// If a finding's (section, anchor) matches an entry in the ledger, mark it as
// "re-raised despite wont-fix" — it does NOT count toward newFindings/blockers
// for verdict purposes, but it IS surfaced separately so the parent can decide
// whether new evidence warrants overriding the prior decision.
const ledger = Array.isArray(wontfixLedger) ? wontfixLedger : []
const ledgerKeys = new Set(ledger.map(w => `${w.section || ''}::${w.anchor || w.id || ''}`))

function findingKey(f) {
  return `${f.section || ''}::${f.anchor || ''}`
}

const reRaisedDespiteWontfix = findings.filter(f => ledgerKeys.has(findingKey(f)))
const effectiveFindings = findings.filter(f => !ledgerKeys.has(findingKey(f)))

// ----- 1. minimumRounds (deterministic) -----
// Allow first-round-LGTM exit: if roundNum === 1 AND zero blockers, satisfied.
// Otherwise require roundNum >= 2 (the "second pass catches what first revision introduced" rationale).
const effectiveBlockers = effectiveFindings.filter(f => f.severity === 'Blocking').length
const firstRoundLGTM = roundNum === 1 && effectiveBlockers === 0 && effectiveFindings.length === 0
const minimumRounds = roundNum >= 2 || firstRoundLGTM

// ----- 2. reviewerAcknowledgment (deterministic) -----
// Cross-reviewer / cross-lens aggregate Blocker count must be 0
// (effective — wont-fix re-raises don't count here)
const reviewerAcknowledgment = effectiveBlockers === 0

// ----- 3. diminishingSeverity (deterministic) -----
// Blocker ratio among effective findings < 0.2 (or 0 findings)
const blockerRatio = effectiveFindings.length > 0
  ? effectiveBlockers / effectiveFindings.length
  : 0
const diminishingSeverity = effectiveFindings.length === 0
  ? true
  : blockerRatio < 0.2

// ----- 4. positionStability (semi-deterministic) -----
// Two signals: H2 section set churn (added/removed sections) and body-size delta.
// "Position stability" = core decisions/scope didn't churn; only refinements.
// Threshold: |new H2 sections| + |removed H2 sections| <= 1 AND body delta < 30%
let positionStability
let positionStabilityDetail
if (roundNum === 1 || priorRoundH2Sections == null || priorRoundBodyBytes == null) {
  positionStability = null
  positionStabilityDetail = 'round 1 — no prior to compare'
} else {
  const priorSet = new Set(priorRoundH2Sections)
  const thisSet = new Set(thisRoundH2Sections || [])
  const added = [...thisSet].filter(s => !priorSet.has(s))
  const removed = [...priorSet].filter(s => !thisSet.has(s))
  const sectionChurn = added.length + removed.length
  const bodyDelta = priorRoundBodyBytes > 0
    ? Math.abs(thisRoundBodyBytes - priorRoundBodyBytes) / priorRoundBodyBytes
    : 0
  positionStability = sectionChurn <= 1 && bodyDelta < 0.3
  positionStabilityDetail = `sectionChurn=${sectionChurn} (added=${JSON.stringify(added)}, removed=${JSON.stringify(removed)}), bodyDelta=${Math.round(bodyDelta * 100)}%`
}

// ----- 5. coverage (parent must confirm) -----
// Parent must confirm every prior-round anchor was either fixed or moved to wont-fix.
// Workflow surfaces unresolved anchors as evidence, but cannot judge intent.
const priorAnchorSet = Array.isArray(priorRoundAnchors) ? new Set(priorRoundAnchors) : new Set()
const thisAnchorSet = new Set(findings.map(f => f.anchor).filter(Boolean))
const wontfixAnchors = new Set(ledger.map(w => w.anchor || w.id))
const stillOpenAnchors = [...priorAnchorSet].filter(a => thisAnchorSet.has(a) && !wontfixAnchors.has(a))

const coverage = parentConfirmsCoverage === true
  ? true
  : parentConfirmsCoverage === false
    ? false
    : null

// ----- Aggregate verdict -----
const criteria = {
  coverage,
  diminishingSeverity,
  positionStability,
  minimumRounds,
  reviewerAcknowledgment,
}

const autoEvaluable = Object.entries(criteria).filter(([, v]) => v !== null)
const satisfiedCount = autoEvaluable.filter(([, v]) => v === true).length
const totalEvaluable = autoEvaluable.length
const shouldExitNormal = satisfiedCount >= 3 && coverage === true

// ----- Escape-hatch eligibility (constrained per critique) -----
// Original SKILL.md had unbounded "if <3 satisfied AND parent judges remaining
// issues are user-decisions → still exit". Per critique that is unbounded and
// becomes the dominant exit path. Constraints:
//   - At most ONE use per loop instance (parent tracks via escapeHatchAlreadyUsed)
//   - Only unlocked at roundNum >= 3
//   - NEVER eligible while any unresolved effective Blocker exists
//   - Parent MUST supply structured rationale separately (not enforced here, but
//     surfaced as `escapeHatchRequiresRationale` so SKILL.md can gate on it)
const escapeHatchEligible = !shouldExitNormal
  && roundNum >= 3
  && !escapeHatchAlreadyUsed
  && effectiveBlockers === 0
  && coverage === true

const verdict = shouldExitNormal
  ? 'EXIT'
  : (escapeHatchEligible ? 'EXIT_VIA_ESCAPE_HATCH' : 'CONTINUE')

// ----- Build byCategory + byAnchor views for parent decision-making -----
const byCategory = effectiveFindings.reduce((acc, f) => {
  (acc[f.category] = acc[f.category] || []).push(f)
  return acc
}, {})

const bySection = effectiveFindings.reduce((acc, f) => {
  (acc[f.section || 'GLOBAL'] = acc[f.section || 'GLOBAL'] || []).push(f)
  return acc
}, {})

// ----- Trace line for SKILL.md to print after each round -----
const criteriaFired = autoEvaluable
  .filter(([, v]) => v === true)
  .map(([k]) => k)
  .concat(coverage === true ? ['coverage(parent-confirmed)'] : [])

const trace = {
  round: roundNum,
  verdict,
  criteriaFired,
  criteriaState: criteria,
}

return {
  verdict,
  satisfied: satisfiedCount + (coverage === true ? 1 : 0),
  total: totalEvaluable + (coverage === null ? 0 : 1),
  criteria,
  stats: {
    totalFindings: findings.length,
    effectiveFindings: effectiveFindings.length,
    effectiveBlockers,
    blockerRatio: Math.round(blockerRatio * 100) / 100,
    reRaisedDespiteWontfixCount: reRaisedDespiteWontfix.length,
    priorRoundFindingCount: priorRoundFindingCount ?? null,
    stillOpenAnchorCount: stillOpenAnchors.length,
  },
  byCategory,
  bySection,
  reRaisedDespiteWontfix,
  stillOpenAnchors,
  positionStabilityDetail,
  escapeHatchEligible,
  escapeHatchRequiresRationale: verdict === 'EXIT_VIA_ESCAPE_HATCH',
  parentMustConfirm: coverage === null
    ? {
        coverage: `Confirm every prior-round anchor was fixed or moved to wont-fix. ${stillOpenAnchors.length} anchor(s) still appear this round and are NOT in wont-fix: ${JSON.stringify(stillOpenAnchors)}`,
      }
    : null,
  trace,
}
