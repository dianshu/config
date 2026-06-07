export const meta = {
  name: 'issues-review-loop-progression-check',
  description: 'Deterministic 3-of-4 Progression Check for /issues-review-loop, with coverage as a parent-confirmed precondition and parserPass as an independent hard gate. Mirrors /prd-review-loop progression but swaps H2-section churn for issue-file churn, splits coverage out of the counted criteria into a precondition, and adds parserPass.',
  phases: [
    { title: 'Score', detail: 'compute auto-evaluable criteria + apply wont-fix folding + hard-gate parserPass + escape-hatch eligibility' },
  ],
}

const {
  // From this round's review.workflow.js issues-mode output
  findings,                       // [{severity, category, issueFile, anchor, description, lenses?}]
  roundNum,                       // 1-based
  // Bookkeeping carried across rounds by the parent
  priorRoundFindingCount,         // number | null (null on round 1)
  priorRoundAnchors,              // string[] of "<issueFile>::<anchor>" from prior round
  // From context injection + wont-fix ledger
  wontfixLedger,                  // [{id, severity, source, rationale, decidedRoundN, issueFile, anchor}]
  // Issue-file churn signals (replace PRD H2-section churn)
  thisRoundIssueFiles,            // string[] of pending issue filenames present this round
  priorRoundIssueFiles,           // string[] of pending issue filenames present previous round (null on round 1)
  thisRoundTotalBytes,            // sum of non-whitespace byte count across pending issue bodies this round
  priorRoundTotalBytes,           // number | null
  // Hard gate input — deterministic parser preflight result from review.workflow.js
  parserFailureCount,             // integer >= 0
  // Escape-hatch eligibility
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
if (typeof parserFailureCount !== 'number' || parserFailureCount < 0 || !Number.isInteger(parserFailureCount)) {
  throw new Error('progression-check: parserFailureCount must be a non-negative integer')
}

phase('Score')

// ----- Fold wont-fix ledger -----
// Anchor key for issue findings is "<issueFile>::<anchor>" — narrower than PRD's "section::anchor"
// because the same anchor string (e.g. "AC-2") naturally appears in many issue files.
// Use a SHARED keyer for both sides to guarantee symmetry — a wont-fix entry with no anchor
// would never match a finding (findings always emit an anchor), so we skip such entries
// rather than fall back to `w.id` (which produced phantom keys like "::W-001" that matched nothing).
const ledger = Array.isArray(wontfixLedger) ? wontfixLedger : []

function recordKey(o) {
  return `${o.issueFile || ''}::${o.anchor || ''}`
}

// Skip wont-fix entries missing EITHER issueFile or anchor — both are required for
// a valid `<issueFile>::<anchor>` key. Surface skipped entries by id so the parent
// can re-author them; without this, a missing-issueFile entry would produce a
// phantom `::anchor` key that matches nothing and silently re-raises every round.
const ledgerKeySkipped = ledger
  .filter(w => !w.issueFile || !w.anchor)
  .map(w => w.id || '(unknown)')
const ledgerKeys = new Set(
  ledger
    .filter(w => !!w.issueFile && !!w.anchor)
    .map(recordKey)
)

const reRaisedDespiteWontfix = findings.filter(f => ledgerKeys.has(recordKey(f)))
const effectiveFindings = findings.filter(f => !ledgerKeys.has(recordKey(f)))

// ----- 1. minimumRounds (deterministic) -----
// Allow first-round-LGTM exit: roundNum === 1 AND zero blockers AND zero effective findings.
// Otherwise require roundNum >= 2.
const effectiveBlockers = effectiveFindings.filter(f => f.severity === 'Blocking').length
const firstRoundLGTM = roundNum === 1 && effectiveBlockers === 0 && effectiveFindings.length === 0
const minimumRounds = roundNum >= 2 || firstRoundLGTM

// ----- 2. reviewerAcknowledgment (deterministic) -----
// Cross-lens aggregate Blocker count must be 0 (effective — wont-fix re-raises don't count).
const reviewerAcknowledgment = effectiveBlockers === 0

// ----- 3. diminishingSeverity (deterministic) -----
// Blocker ratio among effective findings < 0.2 (or 0 findings).
const blockerRatio = effectiveFindings.length > 0
  ? effectiveBlockers / effectiveFindings.length
  : 0
const diminishingSeverity = effectiveFindings.length === 0
  ? true
  : blockerRatio < 0.2

// ----- 4. positionStability (semi-deterministic) -----
// PRD-version signal: H2-section churn. Issues-version: issue-file churn.
// Two signals: |added| + |removed| issue files AND total body-bytes delta.
// "Position stability" = the issue SET shape didn't churn; only refinements within issues.
// Threshold: file-churn <= 1 AND body delta < 30%
let positionStability
let positionStabilityDetail
if (roundNum === 1 || priorRoundIssueFiles == null || priorRoundTotalBytes == null) {
  positionStability = null
  positionStabilityDetail = 'round 1 — no prior to compare'
} else {
  const priorSet = new Set(priorRoundIssueFiles)
  const thisSet = new Set(thisRoundIssueFiles || [])
  const added = [...thisSet].filter(f => !priorSet.has(f))
  const removed = [...priorSet].filter(f => !thisSet.has(f))
  const fileChurn = added.length + removed.length
  const bodyDelta = priorRoundTotalBytes > 0
    ? Math.abs(thisRoundTotalBytes - priorRoundTotalBytes) / priorRoundTotalBytes
    : 0
  positionStability = fileChurn <= 1 && bodyDelta < 0.3
  positionStabilityDetail = `fileChurn=${fileChurn} (added=${JSON.stringify(added)}, removed=${JSON.stringify(removed)}), bodyDelta=${Math.round(bodyDelta * 100)}%`
}

// ----- 5. coverage (parent must confirm — preconditional, NOT one of the 4 counted criteria) -----
// Coverage is treated as a PRECONDITION for the normal-EXIT path (alongside parserPass),
// not as a 5th counted criterion. The 4 auto-evaluable criteria (diminishingSeverity,
// positionStability, minimumRounds, reviewerAcknowledgment) are scored 3-of-4 — that's
// the "3-of-5" rule from the source PRD loop, minus coverage (which moved to a precondition).
// Workflow surfaces unresolved anchors as evidence, but cannot judge intent.
//
// Exclude evergreen anchors from the still-open tracking — Coverage lens always emits
// a `GLOBAL::MATRIX-SUMMARY` finding (see lenses/issues/Coverage.md "Matrix summary
// (always emit one)"). Without exclusion it would re-fire every round with the same
// key, forcing the parent to wont-fix it just to clear stillOpenAnchors. Treat it as
// a status report, not a coverage gap.
const EVERGREEN_ANCHORS = new Set(['GLOBAL::MATRIX-SUMMARY'])

const priorAnchorSet = Array.isArray(priorRoundAnchors)
  ? new Set(priorRoundAnchors.filter(k => !EVERGREEN_ANCHORS.has(k)))
  : new Set()
const thisAnchorSet = new Set(
  findings
    .map(recordKey)
    .filter(k => k !== '::' && !EVERGREEN_ANCHORS.has(k))
)
const wontfixAnchors = ledgerKeys   // already computed above via recordKey + anchor-required filter
const stillOpenAnchors = [...priorAnchorSet].filter(a => thisAnchorSet.has(a) && !wontfixAnchors.has(a))

const coverage = parentConfirmsCoverage === true
  ? true
  : parentConfirmsCoverage === false
    ? false
    : null

// ----- Hard gate: parserPass (deterministic, independent) -----
// `/run-all-issues` blocker parser must accept every pending issue file.
// This is a SEPARATE boolean from the counted criteria. Even if all 4 counted criteria
// pass AND coverage is confirmed, the loop CANNOT exit while parserPass is false —
// the unparseable-blocker hazard (silently undispatchable issue jams the entire drain)
// is too high to ever override.
const parserPass = parserFailureCount === 0

// ----- Aggregate verdict -----
// `criteria` holds only the 4 auto-evaluable COUNTED criteria — coverage is a separate
// precondition (tracked in `preconditions`), not double-counted here.
const criteria = {
  diminishingSeverity,
  positionStability,
  minimumRounds,
  reviewerAcknowledgment,
}
const preconditions = { coverage, parserPass }

const autoEvaluable = Object.entries(criteria).filter(([, v]) => v !== null)
const satisfiedCount = autoEvaluable.filter(([, v]) => v === true).length
const totalEvaluable = autoEvaluable.length
const shouldExitNormal = satisfiedCount >= 3 && coverage === true && parserPass === true

// ----- Escape-hatch eligibility -----
// Documented constraints (SKILL.md "Why these 5 criteria + parserPass hard gate"):
//   - At most ONE use per loop instance
//   - Only unlocked at roundNum >= 3
//   - NEVER eligible while any unresolved effective Blocker exists
//   - NEVER eligible while parserPass === false  (parser hard gate has no override)
//   - Parent MUST supply structured rationale (surfaced as escapeHatchRequiresRationale)
//
// Coverage is INTENTIONALLY NOT a hard precondition for the escape hatch — its whole
// purpose is to let the parent exit when remaining issues are judged not worth fixing,
// which often includes ambiguity around whether prior-round anchors are "fixed". The
// structured rationale is the audit trail that explains the call.
const escapeHatchEligible = !shouldExitNormal
  && roundNum >= 3
  && !escapeHatchAlreadyUsed
  && effectiveBlockers === 0
  && parserPass === true

const verdict = shouldExitNormal
  ? 'EXIT'
  : (escapeHatchEligible ? 'EXIT_VIA_ESCAPE_HATCH' : 'CONTINUE')

// ----- Build byCategory + byIssueFile views for parent decision-making -----
const byCategory = effectiveFindings.reduce((acc, f) => {
  (acc[f.category] = acc[f.category] || []).push(f)
  return acc
}, {})

const byIssueFile = effectiveFindings.reduce((acc, f) => {
  (acc[f.issueFile || 'GLOBAL'] = acc[f.issueFile || 'GLOBAL'] || []).push(f)
  return acc
}, {})

// ----- Trace line for SKILL.md to print after each round -----
// criteriaFired lists only the COUNTED criteria that fired. Preconditions are
// reported separately so the user sees the distinction between "3-of-4 vote
// satisfied" and "all preconditions met".
const criteriaFired = autoEvaluable
  .filter(([, v]) => v === true)
  .map(([k]) => k)

const trace = {
  round: roundNum,
  verdict,
  criteriaFired,
  criteriaState: criteria,
  preconditions,
  hardGates: { parserPass },
}

return {
  verdict,
  satisfied: satisfiedCount,
  total: totalEvaluable,
  criteria,
  preconditions,
  hardGates: { parserPass, parserFailureCount },
  stats: {
    totalFindings: findings.length,
    effectiveFindings: effectiveFindings.length,
    effectiveBlockers,
    blockerRatio: Math.round(blockerRatio * 100) / 100,
    reRaisedDespiteWontfixCount: reRaisedDespiteWontfix.length,
    ledgerEntriesSkipped: ledgerKeySkipped,    // wont-fix entries missing `issueFile` or `anchor` — silently ineffective
    priorRoundFindingCount: priorRoundFindingCount ?? null,
    stillOpenAnchorCount: stillOpenAnchors.length,
  },
  byCategory,
  byIssueFile,
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
