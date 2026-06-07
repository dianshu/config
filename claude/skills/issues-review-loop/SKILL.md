---
name: issues-review-loop
description: Pre-dispatch review loop for the issue SET written by /issues. Runs single-backend × 5-lens fan-out (Slicer / DependencyAuditor / Granularity / AcceptanceCriteria / Coverage) over every pending issue file, plus a deterministic `## Blocked by` parser preflight (hard gate — overrides 3-of-5 progression). Loop until a deterministic 3-of-5 Progression Check + parserPass hard gate exits. Use before /issues applies the ready-for-agent triage label. Trigger: "issues-review-loop", "/issues-review-loop".
allowed-tools: Bash, Read, Write, Edit, Skill, Workflow
---

# Issues Review Loop

Drives an adversarial multi-lens review of the issue SET written by `/issues` before those issues are labelled `ready-for-agent` and picked up by `/run-all-issues`. Workflow position:

```
/issues step 5 writes issue files  →  /issues-review-loop  →  user final approval  →  /issues step 6 applies triage labels
                                              ^^^ THIS SKILL ^^^
```

This skill never publishes anything or applies labels. It loops review-and-revise on the issue files in place, then hands back to `/issues` (or the user) to label.

`/issues-review-loop` is the sibling of `/prd-review-loop`: same architectural shape (single backend × N-lens fan-out + 3-of-5 progression check + persisted wont-fix ledger), specialized for issue-set defects (vertical-slice violations, undeclared dependencies, granularity drift, under-specified Acceptance Criteria, PRD-coverage gaps). It adds one extra **deterministic hard gate**: every pending issue file's `## Blocked by` section must pass the `/run-all-issues` parser — no amount of LLM consensus can override this gate, because an unparseable issue silently jams the entire `/run-all-issues` drain.

## Input — two accepted forms

The skill accepts the issue set in one of two forms. Resolve which via this priority order:

1. **Feature slug** — `slug` arg or `/issues-review-loop <slug>` invocation (e.g. `/issues-review-loop sessions-list-by-last-event-at`). Skill resolves to `~/.claude/matt/features/<slug>/issues/` per `~/.claude/matt/issue-tracker.md` conventions; reads and edits issue files in place. After EXIT, if any pending issue is already labelled `ready-for-agent` in the parent `/issues` flow, prompt the user to confirm the label remains valid (sync drift guard).
2. **Feature directory path** — `featureDir` arg or `/issues-review-loop ~/.claude/matt/features/<slug>` invocation. Same behavior as form (1) — the skill computes `issuesDir = <featureDir>/issues` and `prdPath = <featureDir>/PRD.md`.

There is intentionally **no inline form**. Issues are files on disk by construction (they ship via `/run-all-issues`'s file-iteration loop); a pre-file draft isn't a meaningful unit to review.

If parent invokes the skill without either form, ask once which to use.

The skill computes from the resolved path:
- `issuesDir` — directory containing pending `NN-*.md` issue files
- `prdPath` — `<featureDir>/PRD.md` (read if exists; absence is allowed and silently drops the Coverage lens)
- `wontfixPath` — `<featureDir>/.issues-review.wontfix.md` (sibling of `issues/`, **not** inside it — placing the ledger inside `issues/` would violate `/run-all-issues`'s `^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$` filename invariant)

## Architecture

```
Context preflight  →  List pending issue files  →  Glob project context  →  Build wont-fix ledger
        │
        ▼
For each round:
  ┌─ Workflow(review.workflow.js, mode=issues, lensRoster=5) ────────────────────┐
  │   step 1: deterministic `## Blocked by` parser preflight (HARD GATE)         │
  │           → parserFailures[]                                                 │
  │   step 2: auto-drop Coverage lens if no PARENT_PRD in contextFiles           │
  │   step 3: lens × issue-file fan-out (5 lenses × N pending issues, chunked)   │
  │           Slicer | DependencyAuditor | Granularity | AcceptanceCriteria      │
  │           [+ Coverage when PRD injected]                                     │
  │   step 4: merge by (issueFile, anchor) → verdict                             │
  │           parserFailures!=0 → REJECT regardless of LLM consensus             │
  └───────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
  Parent edits issue files in place (split / merge / fix Blocked-by / sharpen AC / move non-code gates to ## Hold)
  or marks a finding wont-fix → persists to ledger
        │
        ▼
  Workflow(progression-check.workflow.js)
  3-of-5 deterministic/semi-deterministic criteria + 1 parent-confirmed (coverage)
  + parserPass hard gate (independent — must be true for any EXIT path)
        │
        ▼
  EXIT? → done.  CONTINUE? → next round (re-read issue files, re-load wont-fix ledger, re-run parser).
```

## Flow

### Step 0 — Context preflight (run ONCE per loop invocation, before round 1)

Resolve `issuesDir`, `prdPath`, `wontfixPath` from the input. Then run in parallel:

```bash
# Required: pending issue files
PENDING_FILES=$(find "$ISSUES_DIR" -maxdepth 1 -name '*.md' ! -name 'done-*' | sort)
[ -z "$PENDING_FILES" ] && echo "❌ No pending issue files in $ISSUES_DIR" && exit 1

# Optional: parent PRD (required by Coverage lens; absence drops that lens silently)
CTX_FILES=()
[ -f "$PRD_PATH" ] && CTX_FILES+=("PARENT_PRD:$PRD_PATH")

# Optional: project context (same as /prd-review-loop)
[ -f "$PWD/GRILLCOMMITMENTS.md" ] && CTX_FILES+=("GRILLCOMMITMENTS:$PWD/GRILLCOMMITMENTS.md")
[ -f "$PWD/CONTEXT.md" ] && CTX_FILES+=("GLOSSARY:$PWD/CONTEXT.md")
[ -d "$PWD/docs/adr" ] && for f in "$PWD/docs/adr"/*.md; do
  [ -f "$f" ] && CTX_FILES+=("ADR:$f")
done
# NO sibling-PRD injection — issue review is scoped to ONE feature's issue set.
```

For each file in `CTX_FILES`:
- `PARENT_PRD` — **full read** (Coverage lens needs the entire User Stories + Acceptance Criteria sections; truncating would silently weaken the lens)
- `GRILLCOMMITMENTS` / `GLOSSARY` — full read
- `ADR` — `head -200` per file to avoid context bloat

Assemble `{path, label, content}[]` to pass as `contextFiles` to the workflow.

If `PARENT_PRD` is absent, log `issues-review-loop: no PARENT_PRD at <expected path> — Coverage lens will be skipped, other 4 lenses run` and proceed.

### Step 1 — Load wont-fix ledger

Look for `<featureDir>/.issues-review.wontfix.md`. Schema is a markdown list:

```markdown
# Wont-fix ledger for <feature slug> issue review

<!-- entries below, one per item, never delete; new entries appended -->

## [W-001] Required — Slicer round 2
- **IssueFile**: 04-balance-fetch.md
- **Anchor**: AC-3
- **Rationale**: AC-3 intentionally only covers the happy path; failure-mode AC lives in issue 05-balance-fetch-failure-handling.md (referenced via ## Blocked by from 05).
- **Decided round**: 2

## [W-002] Suggestion — Granularity round 1
- **IssueFile**: GLOBAL
- **Anchor**: MATRIX-SUMMARY
- **Rationale**: Set-wide observation about issue count vs. PRD Story count — accepted as informational; not actionable until next PRD revision.
- **Decided round**: 1
```

Parse into `wontfixLedger: [{id, severity, source, rationale, decidedRoundN, issueFile, anchor}]`. If the file does not exist, `wontfixLedger = []`. Pass to both the workflow and the progression-check.

The ledger lives at `<featureDir>/.issues-review.wontfix.md` (sibling of `issues/`, **not** inside it — placing the ledger inside `issues/` would violate `/run-all-issues`'s `^(done-)?[0-9]{2,}-[a-z0-9-]+\.md$` filename invariant)

### Step 2 — Review round loop

For round N (starting at 1):

#### 2a. Invoke the issues review workflow

```
Workflow({
  scriptPath: '~/.claude/skills/review-with-agent/review.workflow.js',
  args: {
    mode: 'issues',
    backend: 'codex',                       // single backend (same rationale as /prd-review-loop)
    issuesDir: '<resolved issues path>',
    contextFiles: <from step 0>,            // PARENT_PRD optional; GRILLCOMMITMENTS / GLOSSARY / ADR optional
    wontfixLedger: <from step 1>,
    lensRoster: ['Slicer', 'DependencyAuditor', 'Granularity', 'AcceptanceCriteria', 'Coverage'],
    // Workflow auto-drops Coverage from the dispatched roster when no PARENT_PRD in contextFiles.
  },
})
```

The workflow returns `{verdict, issueFilesReviewed, parserFailures, findings, lensResults, stats}`. Findings are already merged across lenses with the `lenses: [...]` array showing which lenses flagged each one. `parserFailures` is populated by the deterministic `## Blocked by` regex preflight — these are NOT findings from LLM lenses; they are hard mechanical failures.

#### 2b. Triage findings — parent decides per finding

For each finding, decide one of:
- **Revise** — edit the issue file in place to address the finding (Edit tool on the issue file). Possible edits include:

  | Decision | Mechanics | Round-N+1 effect on signals |
  |---|---|---|
  | Split issue | Create new `NN+1-<slug>.md` (renumber subsequent files if needed), move content, update any `## Blocked by` references that pointed to the original | Bumps issue-file count → trips `positionStability` to false |
  | Merge two issues | Delete one, fold content into the other, rewrite `## Blocked by` of every dependent that pointed to the removed one | Bumps `|removed|` → trips `positionStability` |
  | Fix `## Blocked by` line | Replace malformed bullet with backtick form `` - `NN-slug.md` `` or hash form `- #NN` | May flip `parserPass` from false → true |
  | Move non-code gate to `## Hold` | Cut the offending bullet out of `## Blocked by`, paste into a new `## Hold` section in the same issue (or out of the issue entirely) | Flips `parserPass` to true for that file |
  | Sharpen Acceptance Criteria | Edit AC bullets in place | Body-byte delta only; no file churn |
  | Rewrite `## What to build` | Edit in place | Body-byte delta only |

- **Wont-fix** — append a new entry to `<featureDir>/.issues-review.wontfix.md` with `id = W-<NNN>` (next available), the finding's `issueFile` + `anchor`, source = the lens(es) that flagged it, current round, and parent's structured rationale. **Persisted to disk** — survives loop / session / cross-day.

Prioritize multi-lens findings (`lenses.length >= 2`) — they are by construction the highest-confidence signal.

**Treat `parserFailures` specially**: these are NOT triageable as wont-fix. The author MUST fix them (edit the offending `## Blocked by` line per the parser regex, OR move the non-code gate to `## Hold`). The loop cannot EXIT while `parserFailures.length > 0`.

#### 2c. Compute progression

Capture round-state for the progression check:
```bash
# Pending issue file list (after edits)
ISSUE_FILES=$(find "$ISSUES_DIR" -maxdepth 1 -name '*.md' ! -name 'done-*' -exec basename {} \; | sort)
# Sum of non-whitespace bytes across all pending issues — null-safe in empty dir
TOTAL_BYTES=$(find "$ISSUES_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'done-*' -print0 \
  | xargs -0 cat 2>/dev/null | tr -d '[:space:]' | wc -c | tr -d ' ')
```

The `find ... -print0 | xargs -0 cat` form is null-safe — `xargs -0` with no input is a no-op (does not invoke `cat`), so the pipeline returns 0 bytes cleanly when the directory is empty. The bare `cat $(find ...)` form is unsafe: an empty `find` makes it `cat` (no args) which blocks on stdin forever.

```
Workflow({
  scriptPath: '~/.claude/skills/issues-review-loop/progression-check.workflow.js',
  args: {
    findings: <effective findings — workflow output excluding wont-fix re-raises>,
    roundNum: <N>,
    priorRoundFindingCount: <stored across rounds, null on round 1>,
    priorRoundAnchors: <stored across rounds, [] on round 1; each entry "<issueFile>::<anchor>">,
    wontfixLedger: <from step 1, possibly with round N additions>,
    thisRoundIssueFiles: <from find above>,
    priorRoundIssueFiles: <stored across rounds, null on round 1>,
    thisRoundTotalBytes: <from wc above>,
    priorRoundTotalBytes: <stored across rounds, null on round 1>,
    parserFailureCount: <from workflow output: parserFailures.length>,
    escapeHatchAlreadyUsed: <stored across rounds, false initially>,
    parentConfirmsCoverage: <true/false/undefined — see below>,
  },
})
```

**Coverage confirmation**: workflow returns `parentMustConfirm.coverage` listing `<issueFile>::<anchor>` keys still open this round and NOT in wont-fix. Parent inspects:
- If every prior-round anchor was either edited away OR moved to wont-fix → set `parentConfirmsCoverage: true` and re-invoke the progression check.
- Otherwise → loop back to 2a (still-open anchors will resurface).

#### 2d. Act on verdict

- `verdict === 'EXIT'` → proceed to Step 3 (Final).
- `verdict === 'EXIT_VIA_ESCAPE_HATCH'` → permitted **only once per loop invocation**, **only at roundNum ≥ 3**, **only when zero effective Blockers remain**, AND **only when `hardGates.parserPass === true`** (the parser gate has no escape). Parent MUST emit a structured rationale (`{remainingIssues: [...], rationaleForExitAnyway: '...'}`) and log it to the final summary. Set `escapeHatchAlreadyUsed = true` for the rest of this loop. Proceed to Step 3.
- `verdict === 'CONTINUE'` → loop back to 2a (round N+1). Persist `thisRoundIssueFiles / TotalBytes / FindingCount / Anchors` as next round's prior state.

#### 2e. Per-round trace

The progression-check workflow returns `trace: {round, verdict, criteriaFired, criteriaState, preconditions, hardGates}`. At the end of every round, **print this trace verbatim to the user** so the EXIT decision is auditable:

```
issues-review-loop round 2 → CONTINUE
  criteriaFired: [diminishingSeverity, minimumRounds]                       (counted 2 of 4)
  criteriaState: {diminishingSeverity: true, positionStability: false, minimumRounds: true, reviewerAcknowledgment: false}
  preconditions: {coverage: null, parserPass: false}                        ← either being false blocks normal EXIT
  hardGates: {parserPass: false}                                            ← THIS also blocks the escape hatch
  effective findings this round: 4 (1 Blocking, 2 Required, 1 Suggestion)
  parser failures this round: 1 (03-cleanup.md: Blocked by line "- Phase 4 rollout signal" is unparseable prose)
  re-raised despite wont-fix: 0
```

### Step 3 — Final summary

Emit the loop summary as the standalone final message (no other content before or after):

```
issues-review-loop: EXIT after N rounds
  Feature: <slug>
  Pending issues reviewed: <count> (<list of NN-<slug>.md filenames>)
  Wont-fix ledger: <count> entries (persisted at <featureDir>/.issues-review.wontfix.md)
  Parser preflight: PASS (0 failures)
  Exit path: normal | escape-hatch (rationale: ...)
  Remaining unresolved findings: <count, with severities, or "none">
  Context cross-checked: <list of label:path>, or "none"
  Coverage lens: enabled (PRD: <path>) | skipped (no PARENT_PRD)
  Per-round trace:
    round 1: <verdict> criteriaFired=[...] hardGates={parserPass:true|false}
    round 2: <verdict> criteriaFired=[...] hardGates={parserPass:true|false}
    ...
  Next step: user reviews the issues, then either re-invokes /issues step 6 to apply triage labels (ready-for-agent / ready-for-human) or requests further changes.
```

After this summary, the loop is done. Do NOT apply triage labels; do NOT modify any `Status:` line inside an issue file. That is `/issues` step 6's job.

## Rules

- **Manual only.** Never invoke automatically.
- **Parent does the editing.** This skill never modifies issue file content; it only orchestrates reviews and surfaces findings + parser failures. The parent uses Edit/Write on issue files between rounds (split / merge / fix Blocked-by / sharpen AC / move non-code gates).
- **Single backend × multi-lens.** Use one backend (default `codex`) with the 5-lens roster (4 lenses if no PARENT_PRD — Coverage drops). Same rationale as `/prd-review-loop`: orthogonal lens perspectives outperform same-prompt dual-backend voting at proportional cost.
- **`parserPass` is a HARD GATE — no LLM override.** Per `~/.claude/injected-rules/model-judgment-only.md`, the `## Blocked by` regex is deterministic and runs in `review.workflow.js` Bash, not as an LLM lens. The loop CANNOT EXIT (normal OR escape-hatch) while any pending issue file fails the parser. Even 5-of-5 progression criteria passing does not override this gate.
- **Won't-fix is persisted to disk.** `<featureDir>/.issues-review.wontfix.md` survives sessions. Entries never deleted; rationales become the audit trail for the issue review. **`parserFailures` are NOT wont-fix-able** — they must be physically fixed (edit the offending line or move it to `## Hold`).
- **No new issue files between rounds without rationale.** Splitting an issue is a legitimate response to a Granularity / Slicer finding — but the new file must be backtick-referenced from any dependent's `## Blocked by`, and the next-round `parserPass` check must still pass.
- **No code-only steps.** Unlike `/finalize`, there is no `/simplify` or `/e2e-verify` here — issues are documents (specifications), not running code. The verification is structural (parser + lens checklist + progression criteria), not behavioral.
- **Escape hatch is bounded.** At most one use per loop, only at round ≥ 3, only with zero unresolved Blockers, only with `parserPass === true`, only with structured rationale logged.

## Why these criteria + preconditions + hard gate

Adapted from `~/.claude/skills/prd-review-loop/progression-check.workflow.js` (which inherits the 3-of-5 pattern from `~/.claude/skills/finalize/progression-check.workflow.js`), but specialized for issue sets and split into three groups so the EXIT contract is unambiguous:

**Counted criteria** (4 — 3-of-4 must be satisfied):

1. **Diminishing severity** — deterministic. Effective-finding Blocker ratio < 0.2 (or zero findings).
2. **Position stability** — semi-deterministic. **Issue-file churn ≤ 1 added/removed AND total body-byte delta < 30%.** This differs from PRD-loop (which checks H2 section churn): for issues, the structural signal is the issue SET shape — a split/merge between rounds is real position churn even though it's the right response to a Granularity finding. Null on round 1.
3. **Minimum rounds** — deterministic. `roundNum >= 2` OR (`roundNum === 1` AND zero effective findings AND `parserPass === true` — first-round-LGTM shortcut, only fires when the initial issue set was clean on both axes).
4. **Reviewer acknowledgment** — deterministic. Aggregated effective Blocker count across lenses === 0.

**Preconditions** (BOTH must hold for normal EXIT):

5. **Coverage** — parent-confirmed. Every prior-round `<issueFile>::<anchor>` either fixed or moved to wont-fix. Workflow surfaces still-open anchors as evidence.
6. **parserPass** — deterministic hard gate. Every pending issue file's `## Blocked by` section accepts under `/run-all-issues`'s parser (backtick form / hash form / `[Nn]one` shortcut; referenced blocker NNs must exist).

Normal **EXIT** requires `satisfied >= 3` of the 4 counted criteria **AND** `coverage === true` **AND** `parserPass === true`.

**Escape hatch** (`EXIT_VIA_ESCAPE_HATCH`) — at most one use per loop, only at roundNum ≥ 3, only with zero unresolved Blockers, only with `parserPass === true`, and parent MUST log a structured rationale. **Coverage is NOT a hard precondition for the escape hatch** — its whole purpose is to let the parent exit when remaining issues are judged not worth fixing (which often includes ambiguity around whether prior-round anchors are "fixed"); the rationale is the audit trail.

### Why `parserPass` is a hard gate, not the 5th counted criterion

`parserPass` is structurally different from the 4 counted criteria:

- The counted criteria measure **review progress** — are the findings shrinking? Did churn settle? Did the reviewer give an LGTM?
- `parserPass` measures a **downstream hazard** — will `/run-all-issues` accept this file?

If `parserPass` were the 5th counted criterion in a 3-of-5 vote, the loop could EXIT with `parserPass === false` as long as 3 of the other 4 are satisfied. That would be wrong: any unparseable `## Blocked by` line silently stops the entire `/run-all-issues` drain at preflight step 8 (per `/run-all-issues` SKILL.md:28). One bad bullet in one issue file blocks every queued issue from that point. The cost of letting `parserPass === false` slip past EXIT vastly exceeds the cost of forcing one more round to fix the bullet.

So: `parserPass` is computed deterministically and surfaced separately as `hardGates.parserPass` (also visible in `preconditions.parserPass`). It must be `true` for any EXIT path. There is no "the LLM judges this parser failure spurious" override — the parser is the source of truth `/run-all-issues` actually uses, so it is the source of truth here too.

### Why `coverage` is a precondition for normal EXIT but not for the escape hatch

`coverage` is parent-confirmed (the workflow can never auto-judge "did the author fix the prior anchor?"). For the normal EXIT path, requiring confirmation prevents premature exit while real findings sit open. For the escape hatch, requiring confirmation would defeat its purpose: the hatch exists precisely for cases where the parent has stared at remaining findings and decided they're not worth another round — and that decision often spans "I'm not 100% sure I 'fixed' that anchor, but I'm sure it's not worth iterating". The structured rationale documents the call.
