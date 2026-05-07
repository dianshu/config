---
name: review-with-agent
description: Multi-lens adversarial code review using external AI CLIs (Codex or Gemini). Shared backend logic invoked by /codex-review and /gemini-review. Supports both code review (working-tree diffs) and plan review (markdown files). Not for reviewing already-committed code.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Review — Multi-Lens Adversarial Review

Reviews uncommitted git changes or implementation plans using independent lens-specific reviewers. Each reviewer runs in isolation — they must NOT see each other's output.

## Backend Inputs

This skill is invoked by a backend skill (`/codex-review`, `/gemini-review`) that defines these shell variables before calling the workflow:

- `PREFLIGHT_CMD` — version check; non-zero exit means abort
- `DISPATCH_CMD` — read-only dispatch for in-diff lenses (Challenger, Architect, Subtractor, Devil's Advocate)
- `READONLY_DISPATCH_CMD` — read-only dispatch with codebase access for the Integration lens
- `PLAN_DISPATCH_CMD` — read-only dispatch for plan review (no git repo required)
- `MODE_LABEL` — string for the verdict header (e.g. `codex-adversarial`)
- `NOISE_FILTER` — `grep -vE` command for trimming CLI banner output
- `TMPDIR_PREFIX` — prefix for the per-run temp directory

All dispatches must be read-only. Never override the user's model setting.

## Workflow

### 1. Preflight

Run `PREFLIGHT_CMD`. If it fails, abort with an error explaining the backend CLI is not installed — do NOT silently fall back. Record `MODE_LABEL` for the verdict header.

### 2. Determine Mode

- Plan file path / "review plan" → **Plan Review** (Section B)
- "review changes" or no path → **Code Review** (Section A)
- Ambiguous → ask

---

## Section A: Code Review Mode

### A1. Define exclusions and detect scale

First confirm `git diff --stat && git diff --cached --stat` is non-empty; otherwise stop and tell the user.

```bash
EXCLUDE_PATHS=':(exclude)**/package-lock.json :(exclude)**/yarn.lock :(exclude)**/pnpm-lock.yaml :(exclude)**/Cargo.lock :(exclude)**/go.sum :(exclude)**/composer.lock :(exclude)**/Gemfile.lock :(exclude)**/poetry.lock :(exclude)**/Pipfile.lock :(exclude)**/*.min.js :(exclude)**/*.min.css :(exclude)**/*.bundle.js :(exclude)**/*.map :(exclude)**/dist/** :(exclude)**/vendor/** :(exclude)**/node_modules/** :(exclude)**/__pycache__/**'

TOTAL_FILES=$( (git diff --name-only && git diff --cached --name-only) | sort -u | wc -l)
FILTERED_FILES=$( (git diff --name-only -- . $EXCLUDE_PATHS && git diff --cached --name-only -- . $EXCLUDE_PATHS) | sort -u | wc -l)
EXCLUDED_COUNT=$(( TOTAL_FILES - FILTERED_FILES ))

LINES=$(( $(git diff --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ insertion' | grep -oP '\d+' || echo 0) + $(git diff --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ deletion' | grep -oP '\d+' || echo 0) + $(git diff --cached --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ insertion' | grep -oP '\d+' || echo 0) + $(git diff --cached --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ deletion' | grep -oP '\d+' || echo 0) ))
DIRS=$( (git diff --name-only -- . $EXCLUDE_PATHS; git diff --cached --name-only -- . $EXCLUDE_PATHS) | xargs -I{} dirname {} | sort -u | wc -l)

if   [ "$LINES" -ge 200 ] || [ "$DIRS" -ge 3 ]; then SCALE="Heavy"
elif [ "$LINES" -ge 50 ];                       then SCALE="Medium"
else                                                  SCALE="Light"; fi
```

| Scale | Condition | Reviewers |
|-------|-----------|-----------|
| Light | < 50 lines | Challenger only |
| Medium | 50–199 lines | Challenger + Architect + Integration + Devil's Advocate |
| Heavy | 200+ lines OR 3+ dirs | Above + Subtractor |

### A2. Prepare diff content

Context flag by scale: Light=`-U3`, Medium=`-U2`, Heavy=`-U1`. Per-file cap: 300 lines (replace overflow with `git diff --stat` + truncation note). Overall budget: 2000 lines per reviewer (tail-truncate with notice).

```bash
TMPDIR=$(mktemp -d /tmp/${TMPDIR_PREFIX}-XXXXXX)
case "$SCALE" in Light) CONTEXT_FLAG="-U3";; Medium) CONTEXT_FLAG="-U2";; Heavy) CONTEXT_FLAG="-U1";; esac
MAX_FILE_LINES=300
BUDGET=2000

prepare_diff() {  # $1 = extra git filter (e.g. "--diff-filter=AM" or empty), $2 = output file
  local FILTER="$1" OUT="$2" PREPARED="" LARGE_FILES="" BUDGET_TRUNCATED=0
  for FILE in $( (git diff --name-only $FILTER -- . $EXCLUDE_PATHS; git diff --cached --name-only $FILTER -- . $EXCLUDE_PATHS) | sort -u); do
    FILE_DIFF=$( (git diff $CONTEXT_FLAG -- "$FILE" && git diff --cached $CONTEXT_FLAG -- "$FILE") )
    FILE_LINES=$(echo "$FILE_DIFF" | wc -l)
    if [ "$FILE_LINES" -gt "$MAX_FILE_LINES" ]; then
      LARGE_FILES="$LARGE_FILES $FILE"
      STAT=$( (git diff --stat -- "$FILE" && git diff --cached --stat -- "$FILE") )
      FILE_DIFF="--- $FILE [TRUNCATED: $FILE_LINES lines, stat only] ---
$STAT
--- End truncated ---"
    fi
    PREPARED="$PREPARED
$FILE_DIFF"
  done
  TOTAL_LINES=$(echo "$PREPARED" | wc -l)
  if [ "$TOTAL_LINES" -gt "$BUDGET" ]; then
    BUDGET_TRUNCATED=$(( TOTAL_LINES - BUDGET ))
    PREPARED=$(echo "$PREPARED" | head -n "$BUDGET")
    PREPARED="$PREPARED
--- BUDGET TRUNCATED: $BUDGET_TRUNCATED additional lines omitted ($BUDGET line budget) ---"
  fi
  echo "$PREPARED" > "$OUT"
  echo "$LARGE_FILES|$BUDGET_TRUNCATED"
}

CH_META=$(prepare_diff "" "$TMPDIR/challenger_diff.txt")
SUB_META=$(prepare_diff "--diff-filter=AM" "$TMPDIR/subtractor_diff.txt")
LARGE_FILE_COUNT=$(echo "${CH_META%|*}" | wc -w)
BUDGET_TRUNCATED=${CH_META#*|}
```

### A3. Extract intent

Read the diff and write a 1–2 sentence intent statement describing what the change is trying to accomplish. Each reviewer prompt embeds this.

### A4. Dispatch lens-specific reviewers

Each reviewer gets: intent (1–2 sentences), lens-specific checklist + output format, appropriate diff slice. Constraint: ≤10 findings, ≤3 lines each, "LGTM" if nothing. `[New]` findings take priority — only include `[Pre-existing]` if the cap allows. Tag every finding with:
- a **severity** from the scale defined in A6, AND
- an **origin** tag — `[New]` (introduced by this diff) or `[Pre-existing]` (issue lives in surrounding code, not introduced by this diff).

Each lens Output line below is given as `<Sev> file:line ...`; reviewers must extend it to `<Sev> [New|Pre-existing] file:line ...`.

#### Lenses

**Challenger** — input `challenger_diff.txt`. "Assume this code has bugs — prove it." Checklist: crash-inducing inputs, swallowed errors, race conditions, boundary/off-by-one, off-happy-path, resource leaks. Output: `<Sev> [New|Pre-existing] file:line trigger → impact → fix`.

**Architect** — input file list + key file signatures + `challenger_diff.txt` (for origin classification). "Examine design decisions, not bugs." Checklist: coupling, responsibility boundary violations, scale assumptions, data flow gaps, API surface bloat. Output: `<Sev> [New|Pre-existing] file:line current design → risk → alternative`.

**Subtractor** — input `subtractor_diff.txt` + new-file list. "Question every line's necessity." Checklist: deletable code, premature abstractions (used once), "just in case" code, over-configuration, dead branches. Output: `<Sev> [New|Pre-existing] file:line deletable → impact if removed → simplification`.

**Integration** — input `challenger_diff.txt`, READ-ONLY codebase access. For each changed function/class/export: find callers via grep, check broken assumptions, trace data flow. May read truncated/stat-only files from disk. Use `git diff --name-status` for renamed/deleted paths. Checklist: behavioral changes callers don't expect, broken implicit contracts, env/config assumptions, middleware/pipeline conflicts, shared-state mutations, missing caller updates. Do NOT flag in-diff issues — Challenger handles those. Output: `<Sev> [New|Pre-existing] file:line changed behavior → affected caller → impact`.

**Devil's Advocate** — input `challenger_diff.txt`. "Question the premise *and* the craft: is this the right solution, and is it written with care?" Checklist:
- *Premise:* simpler/standard alternative, implicit assumptions, real-world failure modes (scale/concurrency/changing requirements), silent tradeoffs, accidental complexity, "why not just…" challenges
- *Slop detector (code smell / taste):* lazy naming (`data`, `tmp`, `result`, `df2`, `x`); obvious comments restating the code; copy-paste blocks instead of abstraction; cargo-cult patterns (e.g. `useEffect` with wrong deps, `async` wrapping sync code, `.apply()` where vectorization works); dead code / commented-out blocks / unused imports; premature OR missing abstraction; junk-drawer files

Output: `<Sev> [New|Pre-existing] file:line current approach or smell → assumption/risk → alternative`.

#### Dispatch (external CLI)

Run reviewers in parallel as background processes. Use `cat | DISPATCH_CMD` (heredoc), never `$()` — avoids shell argument length limits. Integration uses `READONLY_DISPATCH_CMD`.

```bash
{ cat "$TMPDIR/challenger_diff.txt"; cat <<'PROMPT'

---
{challenger prompt with intent filled in}
PROMPT
} | ${DISPATCH_CMD} > "$TMPDIR/challenger.txt" 2>&1 &

# Architect (Medium/Heavy), Subtractor (Heavy), Devil's Advocate (Medium/Heavy): same shape.
# Integration (Medium/Heavy): use ${READONLY_DISPATCH_CMD}.

wait
```

**Retry once** for failures. A reviewer failed if its output (after NOISE_FILTER) is empty or matches `Retry attempts exhausted|Error executing tool|NumericalClassifier`. After retry, mark persistent failures as `[FAILED]` in the verdict — never silently omit.

### A5. Red-line scan

Scan the filtered diff for constraint violations:
1. **Project constraints** — read `CLAUDE.md`, `AGENTS.md`, `.ai/constraints.json` if they exist; check the diff against their rules
2. **Universal red-lines** — `eval()` / `innerHTML` with user input; hardcoded secrets; unvalidated `process.env` in security contexts; `dangerouslySetInnerHTML` with unsanitized content

Violations → additional `Blocking` findings prefixed `[Red-Line]`.

### A6. Aggregate + verdict report

```markdown
## Code Review — {short description}

**Scale**: Light / Medium / Heavy
**Mode**: ${MODE_LABEL}
**Reviewers**: Challenger [+ Architect] [+ Integration] [+ Devil's Advocate] [+ Subtractor]
**Filtered**: {EXCLUDED_COUNT} noise files excluded, {LARGE_FILE_COUNT} large files summarized, {BUDGET_TRUNCATED} lines budget-truncated

### Verdict: PASS / CONTESTED / REJECT

| # | Sev | Origin | Lens | Issue | Decision |
|---|-----|--------|------|-------|----------|
| 1 | Blocking | New | Ch | `file:line` description | Accept — rationale |

### Summary
{One paragraph: conclusion + next steps}
```

**Severity:** `Blocking` (likely bug, security, or red-line violation — must fix before merge), `Required` (design flaw, broken contract, real correctness concern — should fix), `Suggestion` (style, taste, minor cleanup).

**Origin:** `New` (introduced by this diff) or `Pre-existing` (lived in surrounding code before this change). `[Red-Line]` findings from A5 are always `New` (they're triggered by the diff).

**Verdict (computed from `[New]` findings only — `[Pre-existing]` are bonus signal, never affect verdict):**
- **PASS** — no `New` `Blocking`
- **CONTESTED** — `New` `Blocking` exists but lenses disagree
- **REJECT** — multiple lenses agree on a `New` `Blocking`, or any `New` red-line violation

**Decision:** Claude marks each finding `Accept` (valid) or `Dismiss` (false positive / acceptable trade-off). For every `New` finding at `Required` or `Blocking`, Claude **must verify against the actual code before writing the Decision** using whichever source fits the path: `Read`/`Grep` on the worktree (modified or untracked), `git show :<path>` for staged content, `git show HEAD:<path>` or `git diff` for deleted/renamed paths. Never judge from diff context alone. ≤5 findings → rationale inline; 6+ → rationale in separate section below the table.

Cleanup: `rm -rf "$TMPDIR"`.

---

## Section B: Plan Review Mode

### B1. Locate plan

- File path provided → confirm exists and non-empty
- No path but plan in conversation → write to `mktemp /tmp/plan-review-XXXXXX.md`; delete in B3
- Otherwise → ask the user

### B2. Run review

```bash
{ cat "<plan_file>"; cat <<'PROMPT'

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
} | ${PLAN_DISPATCH_CMD}
```

### B3. Verdict + cleanup

Same severity / decision semantics as A6, but **without origin** — Plan Review has no diff, so all findings are treated uniformly and the `New`-conditioned verification rule does not apply (decisions are plain `Accept`/`Dismiss`). Verdict computation: PASS when no `Blocking`, REJECT when ≥2 `Blocking` agree, otherwise CONTESTED. Header uses **Category** instead of **Lens**:

```markdown
## Plan Review — {plan title}

**Mode**: ${MODE_LABEL}

### Verdict: PASS / CONTESTED / REJECT

| # | Sev | Category | Issue | Decision |
|---|-----|----------|-------|----------|
| 1 | Required | Completeness | Missing verification after DB migration | Accept |

### Summary
{One paragraph}
```

If a temp file was created in B1: `rm "<temp_file>"`.
