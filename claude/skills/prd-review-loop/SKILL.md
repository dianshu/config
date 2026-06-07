---
name: prd-review-loop
description: Pre-publish review loop for PRD drafts. Runs single-backend × N-PRD-lens fan-out (Architect / Challenger / DevilsAdvocate / Subtractor / Glossarian / Coverer) against the 8-dimension PRD checklist, with project context (ADR / glossary / GRILLCOMMITMENTS / sibling PRDs) injected and a persistent wont-fix ledger applied. Loop until a deterministic 3-of-5 Progression Check exits. Use before /prd publishes the PRD with the ready-for-agent label. Trigger: "prd-review-loop", "/prd-review-loop".
allowed-tools: Bash, Read, Write, Edit, Skill, Workflow
---

# PRD Review Loop

Drives an adversarial multi-lens review of a PRD draft before it is published to the issue tracker with the `ready-for-agent` label. Workflow position:

```
/prd seam check  →  /prd writes draft (step 3)  →  /prd-review-loop  →  user final approval  →  /prd publish (step 4)
                                                          ^^^ THIS SKILL ^^^
```

This skill never publishes anything. It loops review-and-revise on the draft file in place, then hands back to `/prd` (or the user) to publish.

`/prd-review-loop` has a sibling skill — `/issues-review-loop` — that applies the same architectural pattern (single backend × N-lens fan-out + 3-of-5 progression check + persisted wont-fix ledger) to the issue SET produced by `/issues`. Use them in sequence on a typical feature: `/prd` draft → `/prd-review-loop` → publish PRD → `/issues` draft → `/issues-review-loop` → label issues → `/run-all-issues`.

## Input — three accepted forms

The skill accepts the PRD source in one of three forms. Resolve which via this priority order:

1. **PRD file path** — `prdPath` arg or `/prd-review-loop <path>` invocation. Skill reads the file in place, writes edits in place.
2. **Issue tracker ID / slug** — e.g. `/prd-review-loop sessions-list-by-last-event-at`. Skill resolves to `~/.claude/matt/features/<slug>/PRD.md` per `~/.claude/matt/issue-tracker.md` conventions; reads and edits in place. After EXIT, if the slug was already published with `ready-for-agent`, prompt the user to confirm the label remains valid (sync drift guard).
3. **Inline PRD content** — when the parent has a PRD draft in conversation that is not yet on disk. Skill writes it to `/tmp/prd-review-<slug>-<roundN>.md`, reviews, then returns the final edited content inline. Parent decides where to land it.

If parent invokes the skill without any of (1)/(2)/(3), ask once which to use.

## Architecture

```
Context preflight  →  Read PRD + glob project context  →  Build wont-fix ledger
        │
        ▼
For each round:
  ┌─ Workflow(review.workflow.js, mode=prd, lensRoster=6) ─────────────────┐
  │   parallel: Architect | Challenger | DevilsAdvocate                    │
  │             Subtractor | Glossarian | Coverer                          │
  │   merge by (section, anchor) → verdict (multi-lens=REJECT, single=CONTESTED, none=PASS) │
  └───────────────────────────────────────────────────────────────────────────┘
        │
        ▼
  Parent edits PRD in place (or marks finding wont-fix → persists to ledger)
        │
        ▼
  Workflow(progression-check.workflow.js)
  3 deterministic + 1 semi-deterministic + 1 parent-confirmed criteria
        │
        ▼
  EXIT? → done.  CONTINUE? → next round (re-read PRD, re-load wont-fix ledger).
```

## Flow

### Step 0 — Context preflight (run ONCE per loop invocation, before round 1)

Run these in parallel (single bash block):

```bash
# Glob project context that PRD reviewer must cross-check against
PRD_DIR="$(dirname "$PRD_PATH")"
CTX_FILES=()
[ -f "$PWD/GRILLCOMMITMENTS.md" ] && CTX_FILES+=("GRILLCOMMITMENTS:$PWD/GRILLCOMMITMENTS.md")
[ -f "$PWD/CONTEXT.md" ] && CTX_FILES+=("GLOSSARY:$PWD/CONTEXT.md")
[ -d "$PWD/docs/adr" ] && for f in "$PWD/docs/adr"/*.md; do
  [ -f "$f" ] && CTX_FILES+=("ADR:$f")
done
# Sibling PRDs (other features under the same issue tracker root)
for sib in "$(dirname "$PRD_DIR")"/*/PRD.md; do
  [ -f "$sib" ] && [ "$sib" != "$PRD_PATH" ] && CTX_FILES+=("SIBLING_PRD:$sib")
done
```

For each file in `CTX_FILES`, Read it (use `head -200` for ADRs / sibling PRDs to avoid context bloat; full read for GRILLCOMMITMENTS and CONTEXT.md). Assemble an array of `{path, label, content}` to pass as `contextFiles` to the workflow.

If NO context files are found, log `prd-review-loop: no project context found (no GRILLCOMMITMENTS / CONTEXT.md / docs/adr/ / sibling PRDs)` and proceed — `CONSISTENCY` dimension will be skipped in the reviewer prompt.

### Step 1 — Load wont-fix ledger

Look for `<PRD-path>.wontfix.md` (sibling file). Schema is a markdown list:

```markdown
# Wont-fix ledger for <PRD slug>

<!-- entries below, one per item, never delete; new entries appended -->

## [W-001] Required — codex round 2
- **Anchor**: User Stories::US-7
- **Rationale**: Story 7 actor "power user" is intentional; concrete persona ("billing admin") was considered but loses the cross-role generalization we want here.
- **Decided round**: 2

## [W-002] Suggestion — Architect round 1
- **Anchor**: Implementation Decisions::API contract for /sessions
- **Rationale**: This is a draft; the actual contract will be finalized in a follow-up implementation issue, not this PRD.
- **Decided round**: 1
```

Parse into `wontfixLedger: [{id, severity, source, rationale, decidedRoundN, anchor, section}]` (split `Anchor` on `::` into section + anchor). If file does not exist, `wontfixLedger = []`. Pass to both the workflow and the progression-check.

### Step 2 — Review round loop

For round N (starting at 1):

#### 2a. Invoke the PRD review workflow

```
Workflow({
  scriptPath: '~/.claude/skills/review-with-agent/review.workflow.js',
  args: {
    mode: 'prd',
    backend: 'codex',                          // single backend (see "Why single backend" below)
    prdPath: '<resolved PRD path>',
    contextFiles: <from step 0>,
    wontfixLedger: <from step 1>,
    lensRoster: ['Architect', 'Challenger', 'DevilsAdvocate',
                 'Subtractor', 'Glossarian', 'Coverer'],
  },
})
```

The workflow returns `{verdict, findings, lensResults, stats}`. Findings are already merged across lenses with the `lenses: [...]` array showing which lenses flagged each one.

#### 2b. Triage findings — parent decides per finding

For each finding, decide one of:
- **Revise** — edit the PRD in place to address the finding (use Edit tool on `prdPath`; if `prdContent` was inline, accumulate the edit in working memory and re-pass on next round)
- **Wont-fix** — append a new entry to `<PRD-path>.wontfix.md` with `id = W-<NNN>` (next available), the finding's section + anchor, source = the lens(es) that flagged it, current round, and parent's structured rationale. This is **persisted to disk** — survives loop / session / cross-day.

Prioritize multi-lens findings (`lenses.length >= 2`) — they are by construction the highest-confidence signal.

#### 2c. Compute progression

Capture round-state for the progression check:
```bash
# H2 section list (after edits)
H2_SECTIONS=$(grep -E '^## ' "$PRD_PATH" | sed 's/^## //')
# Non-whitespace body byte count
BODY_BYTES=$(tr -d '[:space:]' < "$PRD_PATH" | wc -c)
```

```
Workflow({
  scriptPath: '~/.claude/skills/prd-review-loop/progression-check.workflow.js',
  args: {
    findings: <effective findings — workflow output excluding wont-fix re-raises>,
    roundNum: <N>,
    priorRoundFindingCount: <stored across rounds, null on round 1>,
    priorRoundAnchors: <stored across rounds, [] on round 1>,
    wontfixLedger: <from step 1, possibly with round N additions>,
    thisRoundH2Sections: <from grep above>,
    priorRoundH2Sections: <stored across rounds, null on round 1>,
    thisRoundBodyBytes: <from wc above>,
    priorRoundBodyBytes: <stored across rounds, null on round 1>,
    escapeHatchAlreadyUsed: <stored across rounds, false initially>,
    parentConfirmsCoverage: <true/false/undefined — see below>,
  },
})
```

**Coverage confirmation**: workflow returns `parentMustConfirm.coverage` listing anchors that still appear this round and are NOT in wont-fix. Parent inspects:
- If every prior-round anchor was either edited away OR moved to wont-fix → set `parentConfirmsCoverage: true` and re-invoke the progression check.
- Otherwise → loop back to 2a (the still-open anchors will resurface).

#### 2d. Act on verdict

- `verdict === 'EXIT'` → proceed to Step 3 (Final).
- `verdict === 'EXIT_VIA_ESCAPE_HATCH'` → permitted **only once per loop invocation**, **only at roundNum ≥ 3**, and **only when zero effective Blockers remain**. Parent MUST emit a structured rationale (`{remainingIssues: [...], rationaleForExitAnyway: '...'}`) and log it to the final summary. Set `escapeHatchAlreadyUsed = true` for the rest of this loop. Proceed to Step 3.
- `verdict === 'CONTINUE'` → loop back to 2a (round N+1). Persist `thisRoundH2Sections / BodyBytes / FindingCount / Anchors` as next round's prior state.

#### 2e. Per-round trace

The progression-check workflow returns `trace: {round, verdict, criteriaFired, criteriaState}`. At the end of every round, **print this trace verbatim to the user** so the EXIT decision is auditable:

```
prd-review-loop round 2 → CONTINUE
  criteriaFired: [diminishingSeverity, minimumRounds]
  criteriaState: {coverage: null, diminishingSeverity: true, positionStability: false, minimumRounds: true, reviewerAcknowledgment: false}
  effective findings this round: 4 (1 Blocking, 2 Required, 1 Suggestion)
  re-raised despite wont-fix: 0
```

### Step 3 — Final summary

Emit the loop summary as the standalone final message (no other content before or after):

```
prd-review-loop: EXIT after N rounds
  PRD: <path>
  Wont-fix ledger: <count> entries (persisted at <path>.wontfix.md)
  Exit path: normal | escape-hatch (rationale: ...)
  Remaining unresolved findings: <count, with severities, or "none">
  Context cross-checked: <list of label:path>, or "none"
  Per-round trace:
    round 1: <verdict> criteriaFired=[...]
    round 2: <verdict> criteriaFired=[...]
    ...
  Next step: user reviews the PRD, then either re-invokes /prd to publish (apply ready-for-agent label) or requests further changes.
```

After this summary, the loop is done. Do NOT publish the PRD; do NOT apply the `ready-for-agent` label. That is `/prd` step 4's job.

## Rules

- **Manual only.** Never invoke automatically.
- **Parent does the editing.** This skill never modifies the PRD content; it only orchestrates reviews and surfaces findings. The parent uses Edit on the PRD file (or on the inline content) between rounds.
- **Single backend × multi-lens.** Use one backend (default `codex`) with the 6-lens roster. The historical dual-backend × same-prompt configuration is replaced — see "Why single backend" below.
- **Won't-fix is persisted to disk.** `<PRD-path>.wontfix.md` survives sessions. Entries never deleted; rationales become the audit trail for the PRD review.
- **No code-only steps.** Unlike `/finalize`, there is no `/simplify` or `/e2e-verify` here — PRDs are documents, not running code.
- **Escape hatch is bounded.** At most one use per loop, only at round ≥ 3, only with zero unresolved Blockers, only with structured rationale logged.

## Why single backend (not dual)

The 8-dimension PRD checklist + 6-lens fan-out generates orthogonal-perspective coverage along the **right axis** (defect classes), so dual-backend voting along the **wrong axis** (same checklist, two LLMs that mostly differ in nitpick density) no longer adds value at proportional cost. If you genuinely want a second-opinion pass, re-invoke the loop with `backend: 'opencode'` after the codex round exits and treat it as an independent re-review — but don't run both backends per round.

## Why these 5 progression criteria

Adapted from `~/.claude/skills/finalize/progression-check.workflow.js` (the source of truth for the 3-of-5 idea), but specialized for PRDs:

1. **Coverage** — parent-confirmed. Every prior-round anchor either fixed or moved to wont-fix. Workflow surfaces still-open anchors as evidence.
2. **Diminishing severity** — deterministic. Effective-finding Blocker ratio < 0.2 (or zero findings).
3. **Position stability** — semi-deterministic. H2 section churn ≤ 1 added/removed AND body-byte delta < 30%. Null on round 1.
4. **Minimum rounds** — deterministic. `roundNum >= 2` OR (`roundNum === 1` AND zero effective findings — first-round-LGTM shortcut, avoids forcing round 2 when the draft was clean).
5. **Reviewer acknowledgment** — deterministic. Aggregated effective Blocker count across lenses === 0.

EXIT requires `satisfied >= 3` of the auto-evaluable criteria **AND** parent-confirmed coverage. The escape-hatch path additionally requires roundNum ≥ 3, no prior use, zero Blockers, and a structured rationale — explicitly NOT an unbounded override.
