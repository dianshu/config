---
name: review-with-agent
description: Multi-lens adversarial code review using external AI CLIs (Codex or Gemini). Shared backend logic invoked by /codex-review and /gemini-review. Supports both code review (working-tree diffs) and plan review (markdown files). Not for reviewing already-committed code.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Review — Multi-Lens Adversarial Review

Reviews uncommitted git changes or implementation plans using multi-lens adversarial review. Supports multiple external AI CLI backends for cross-model independence, with Claude sub-agent fallback.

## Backend Configuration

| Config | Codex | Gemini |
|--------|-------|--------|
| PREFLIGHT_CMD | `codex --version 2>/dev/null` | `gemini --version 2>/dev/null` |
| DISPATCH_CMD | `codex exec - --cd "$(pwd)" --ephemeral --full-auto` | `gemini -p '' --approval-mode yolo --output-format text` |
| READONLY_DISPATCH_CMD | `codex exec - --cd "$(pwd)" --ephemeral -s read-only` | `gemini -p '' --approval-mode plan --output-format text` |
| PLAN_DISPATCH_CMD | `codex exec - --skip-git-repo-check --ephemeral` | `gemini -p '' --approval-mode yolo --output-format text` |
| MODE_LABEL | codex-adversarial | gemini-adversarial |
| NOISE_FILTER | `grep -vE "^OpenAI Codex\|^----\|^workdir:\|^model:\|^provider:\|^approval:\|^sandbox:\|^reasoning\|^session id:\|^$"` | `grep -vE "^YOLO mode\|^$\|^\[STARTUP\]"` |
| TMPDIR_PREFIX | codex-review | gemini-review |

## Workflow

### 1. Select Backend

- If invoked via `/codex-review` → use **Codex** column
- If invoked via `/gemini-review` → use **Gemini** column
- If invoked via `/review-with-agent` or user just said "review" → check availability of both CLIs, prefer Codex if both available
- If selected backend is unavailable → try the other backend
- If neither CLI available → Single-model-multi-lens fallback (Agent tool dispatches reviewers)

Run the selected backend's PREFLIGHT_CMD to confirm availability. Record the mode for the verdict report header.

### 2. Determine Review Mode

- If the user provided a plan file path or said "review plan" → **Plan Review Mode** (go to Section B)
- If the user said "review changes" or no plan file was specified → **Code Review Mode** (go to Section A)
- If ambiguous → ask the user which mode they want

---

## Section A: Code Review Mode

### A1. Verify there are changes to review

```bash
git diff --stat && git diff --cached --stat
```

If both are empty, tell the user there are no changes to review and stop.

### A1.5. Define Exclusion Patterns

Define `EXCLUDE_PATHS` to filter noise files (lock files, minified code, generated output, vendor directories) from all diff commands:

```bash
EXCLUDE_PATHS=':(exclude)**/package-lock.json :(exclude)**/yarn.lock :(exclude)**/pnpm-lock.yaml :(exclude)**/Cargo.lock :(exclude)**/go.sum :(exclude)**/composer.lock :(exclude)**/Gemfile.lock :(exclude)**/poetry.lock :(exclude)**/Pipfile.lock :(exclude)**/*.min.js :(exclude)**/*.min.css :(exclude)**/*.bundle.js :(exclude)**/*.map :(exclude)**/dist/** :(exclude)**/vendor/** :(exclude)**/node_modules/** :(exclude)**/__pycache__/**'
```

Compute the excluded file count for the verdict report:

```bash
TOTAL_FILES=$( (git diff --name-only && git diff --cached --name-only) | sort -u | wc -l)
FILTERED_FILES=$( (git diff --name-only -- . $EXCLUDE_PATHS && git diff --cached --name-only -- . $EXCLUDE_PATHS) | sort -u | wc -l)
EXCLUDED_COUNT=$(( TOTAL_FILES - FILTERED_FILES ))
```

### A2. Scale Detection

```bash
LINES=$(( $(git diff --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ insertion' | grep -oP '\d+' || echo 0) + $(git diff --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ deletion' | grep -oP '\d+' || echo 0) + $(git diff --cached --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ insertion' | grep -oP '\d+' || echo 0) + $(git diff --cached --stat -- . $EXCLUDE_PATHS | tail -1 | grep -oP '\d+ deletion' | grep -oP '\d+' || echo 0) ))
DIRS=$( (git diff --name-only -- . $EXCLUDE_PATHS; git diff --cached --name-only -- . $EXCLUDE_PATHS) | xargs -I{} dirname {} | sort -u | wc -l)

if [ "$LINES" -ge 200 ] || [ "$DIRS" -ge 3 ]; then
  SCALE="Heavy"
elif [ "$LINES" -ge 50 ]; then
  SCALE="Medium"
else
  SCALE="Light"
fi
```

| Scale | Condition | Reviewers |
|-------|-----------|-----------|
| Light | < 50 lines | Challenger only |
| Medium | 50–199 lines | Challenger + Architect + Integration + Devil's Advocate |
| Heavy | 200+ lines OR 3+ dirs | Challenger + Architect + Integration + Subtractor + Devil's Advocate |

### A2.5. Prepare Diff Content

Prepare filtered, compressed, and budgeted diffs for reviewers. Write results to temp files.

**a) Context line reduction by scale:**

| Scale | Flag | Rationale |
|-------|------|-----------|
| Light | `-U3` | Default context |
| Medium | `-U2` | Moderate compression |
| Heavy | `-U1` | Minimal context |

**b) Per-file size cap (300 lines):**

For each file in the filtered diff, if the file's diff exceeds 300 lines, replace it with a `git diff --stat` summary and a truncation note. Track these files for the verdict report.

**c) Overall budget (2000 lines per reviewer):**

After per-file processing, if the total diff exceeds 2000 lines, truncate at the budget and append a notice.

```bash
TMPDIR=$(mktemp -d /tmp/${TMPDIR_PREFIX}-XXXXXX)

CONTEXT_FLAG="-U3"
if [ "$SCALE" = "Medium" ]; then CONTEXT_FLAG="-U2"; fi
if [ "$SCALE" = "Heavy" ]; then CONTEXT_FLAG="-U1"; fi

MAX_FILE_LINES=300
BUDGET=2000
LARGE_FILES=""
BUDGET_TRUNCATED=0

# Generate per-file diffs with filtering and caps
PREPARED=""
for FILE in $( (git diff --name-only $CONTEXT_FLAG -- . $EXCLUDE_PATHS; git diff --cached --name-only $CONTEXT_FLAG -- . $EXCLUDE_PATHS) | sort -u); do
  FILE_DIFF=$( (git diff $CONTEXT_FLAG -- "$FILE" && git diff --cached $CONTEXT_FLAG -- "$FILE") )
  FILE_LINES=$(echo "$FILE_DIFF" | wc -l)
  if [ "$FILE_LINES" -gt "$MAX_FILE_LINES" ]; then
    LARGE_FILES="$LARGE_FILES $FILE"
    STAT=$( (git diff --stat -- "$FILE" && git diff --cached --stat -- "$FILE") )
    FILE_DIFF="--- $FILE [TRUNCATED: $FILE_LINES lines, showing stat only] ---
$STAT
--- End truncated file ---"
  fi
  PREPARED="$PREPARED
$FILE_DIFF"
done

# Apply overall budget
TOTAL_LINES=$(echo "$PREPARED" | wc -l)
if [ "$TOTAL_LINES" -gt "$BUDGET" ]; then
  BUDGET_TRUNCATED=$(( TOTAL_LINES - BUDGET ))
  PREPARED=$(echo "$PREPARED" | head -n "$BUDGET")
  PREPARED="$PREPARED
--- BUDGET TRUNCATED: $BUDGET_TRUNCATED additional lines omitted (2000 line budget) ---"
fi

LARGE_FILE_COUNT=$(echo "$LARGE_FILES" | wc -w)

# Write prepared diff for Challenger
echo "$PREPARED" > "$TMPDIR/challenger_diff.txt"
```

For the **Subtractor lens**, use `--diff-filter=AM` to include only added/modified files:

```bash
SUBTRACTOR_PREPARED=""
for FILE in $( (git diff --name-only --diff-filter=AM $CONTEXT_FLAG -- . $EXCLUDE_PATHS; git diff --cached --name-only --diff-filter=AM $CONTEXT_FLAG -- . $EXCLUDE_PATHS) | sort -u); do
  FILE_DIFF=$( (git diff $CONTEXT_FLAG -- "$FILE" && git diff --cached $CONTEXT_FLAG -- "$FILE") )
  FILE_LINES=$(echo "$FILE_DIFF" | wc -l)
  if [ "$FILE_LINES" -gt "$MAX_FILE_LINES" ]; then
    STAT=$( (git diff --stat -- "$FILE" && git diff --cached --stat -- "$FILE") )
    FILE_DIFF="--- $FILE [TRUNCATED: $FILE_LINES lines, showing stat only] ---
$STAT
--- End truncated file ---"
  fi
  SUBTRACTOR_PREPARED="$SUBTRACTOR_PREPARED
$FILE_DIFF"
done

TOTAL_LINES=$(echo "$SUBTRACTOR_PREPARED" | wc -l)
if [ "$TOTAL_LINES" -gt "$BUDGET" ]; then
  SUBTRACTOR_PREPARED=$(echo "$SUBTRACTOR_PREPARED" | head -n "$BUDGET")
  SUBTRACTOR_PREPARED="$SUBTRACTOR_PREPARED
--- BUDGET TRUNCATED: additional lines omitted (2000 line budget) ---"
fi

echo "$SUBTRACTOR_PREPARED" > "$TMPDIR/subtractor_diff.txt"
```

### A3. Extract Intent

Read the diff output and formulate a 1–2 sentence intent statement describing what the changes are trying to accomplish. This intent is included in each reviewer's prompt to provide context.

### A4. Dispatch Lens-Specific Reviews

This is a read-only review — do not edit any files based on the output.

Each reviewer gets:
- The intent statement (1–2 sentences)
- Their lens-specific checklist and output format
- The appropriate diff slice
- Constraint: ≤10 findings, ≤3 lines each, "LGTM" if nothing found

**Reviewers must NOT see each other's output.** Run them independently.

#### Challenger Lens

Input: prepared diff (`$TMPDIR/challenger_diff.txt`)

Prompt:
```
You are the CHALLENGER reviewer. Assume this code has bugs — your job is to prove it.

Intent: {intent}

Checklist:
- Crash-inducing inputs or states
- Swallowed errors or silent failures
- Race conditions or concurrency issues
- Boundary values and off-by-one errors
- Off-happy-path behavior
- Resource leaks (file handles, connections, listeners)

Output format (one per finding, max 10):
[!]/[~]/[.] `file:line` trigger → impact → fix

If nothing found, output: LGTM
```

#### Architect Lens

Input: file list + function/class signatures (`git diff --name-only`, plus reading key changed files for signatures)

Prompt:
```
You are the ARCHITECT reviewer. Examine design decisions, not bugs.

Intent: {intent}

Checklist:
- Coupling points between modules
- Responsibility boundary violations
- Scale assumptions that may not hold
- Data flow traceability gaps
- API surface bloat or inconsistency

Output format (one per finding, max 10):
[!]/[~]/[.] `file:line` current design → risk → alternative

If nothing found, output: LGTM
```

#### Subtractor Lens

Input: prepared diff of added/modified files only (`$TMPDIR/subtractor_diff.txt`) + list of new files (`git diff --name-only --diff-filter=A`)

Prompt:
```
You are the SUBTRACTOR reviewer. Question every line's necessity.

Intent: {intent}

Checklist:
- Code that could be deleted without behavior change
- Premature abstractions (used only once)
- "Just in case" code with no current caller
- Over-configuration (env vars, flags) for single-use values
- Dead code or unreachable branches

Output format (one per finding, max 10):
[!]/[~]/[.] `file:line` deletable → impact if removed → simplification

If nothing found, output: LGTM
```

#### Integration Lens

Input: prepared diff (`$TMPDIR/challenger_diff.txt`)

Prompt:
```
You are the INTEGRATION reviewer. The diff may be correct in isolation — your job is to find where it breaks the surrounding system.

Intent: {intent}

You have READ-ONLY access to the codebase. Do NOT modify any files. You may read any file, grep, and trace references.

For each changed function, class, or export in the diff:
1. Find all callers and consumers (grep, read imports, trace references)
2. Check if the change violates any assumptions those callers depend on
3. Trace data flow through the change — does upstream input still produce correct downstream output?

If the diff input is truncated or stat-only for some files, read the actual changed files from the codebase to identify changed symbols before tracing callers. For deleted or renamed files, use `git diff --name-status` to identify the old path and check callers of the removed/renamed exports.

Checklist:
- Behavioral changes that callers don't expect (same signature, different semantics)
- Implicit contracts broken (ordering, nullability, error types, timing)
- Configuration or environment assumptions that no longer hold
- Middleware/pipeline/hook interactions that conflict with the change
- State mutations that affect other components reading the same state
- Missing updates to callers that need to adapt to the change

Do NOT flag issues already visible in the diff itself — the Challenger handles those.
Focus on what breaks OUTSIDE the changed files.

Output format (one per finding, max 10):
[!]/[~]/[.] `file:line` changed behavior → affected caller/consumer → impact

If nothing found, output: LGTM
```

#### Devil's Advocate Lens

Input: prepared diff (`$TMPDIR/challenger_diff.txt`)

Prompt:
```
You are the DEVIL'S ADVOCATE reviewer. Challenge whether this is the right approach.

Don't look for bugs or style issues — the other reviewers handle that.
Your job is to question the premise: is this the right solution to the problem?

Intent: {intent}

Checklist:
- Is there a simpler or more standard approach that achieves the same goal?
- What implicit assumptions does this implementation depend on?
- Where could this design fail under real-world conditions (scale, concurrency, changing requirements)?
- Are there silent tradeoffs being made (performance vs readability, flexibility vs simplicity)?
- Does this change introduce accidental complexity that will compound over time?
- Would this approach survive a "why not just..." challenge from a senior engineer?

Output format (one per finding, max 10):
[!]/[~]/[.] `file:line` current approach → assumption/risk → alternative

If nothing found, output: LGTM
```

#### Dispatch via External CLI (adversarial mode)

Run reviewers in parallel using the selected backend's DISPATCH_CMD. For each lens, run as a background Bash process writing to a temp file:

```bash
# Challenger (always runs)
{ cat "$TMPDIR/challenger_diff.txt"; cat <<'PROMPT'

---
{challenger prompt with intent filled in}
PROMPT
} | ${DISPATCH_CMD} > "$TMPDIR/challenger.txt" 2>&1 &

# Architect (Medium/Heavy only)
{ git diff --name-only -- . $EXCLUDE_PATHS; git diff --cached --name-only -- . $EXCLUDE_PATHS; cat <<'PROMPT'

---
{architect prompt with intent filled in}
PROMPT
} | ${DISPATCH_CMD} > "$TMPDIR/architect.txt" 2>&1 &

# Subtractor (Heavy only)
{ cat "$TMPDIR/subtractor_diff.txt"; cat <<'PROMPT'

---
{subtractor prompt with intent filled in}
PROMPT
} | ${DISPATCH_CMD} > "$TMPDIR/subtractor.txt" 2>&1 &

# Devil's Advocate (Medium/Heavy)
{ cat "$TMPDIR/challenger_diff.txt"; cat <<'PROMPT'

---
{devil's advocate prompt with intent filled in}
PROMPT
} | ${DISPATCH_CMD} > "$TMPDIR/devils_advocate.txt" 2>&1 &

# Integration (Medium/Heavy)
{ cat "$TMPDIR/challenger_diff.txt"; cat <<'PROMPT'

---
{integration prompt with intent filled in}
PROMPT
} | ${READONLY_DISPATCH_CMD} > "$TMPDIR/integration.txt" 2>&1 &

wait
```

**Retry failed reviewers:** After `wait`, check each output file using the backend's NOISE_FILTER. A reviewer failed if its output contains `Retry attempts exhausted`, `Error executing tool`, or `NumericalClassifier`, or has no meaningful content after filtering. Retry each failed reviewer **once, sequentially**:

```bash
FAIL_PATTERNS="Retry attempts exhausted|Error executing tool|NumericalClassifier"

for LENS in challenger architect subtractor devils_advocate integration; do
    FILE="$TMPDIR/${LENS}.txt"
    [ ! -f "$FILE" ] && continue
    CONTENT=$(${NOISE_FILTER} "$FILE" | head -3)
    if [ -z "$CONTENT" ] || grep -qE "$FAIL_PATTERNS" "$FILE"; then
        echo "[retry] $LENS failed, retrying once..."
        # Re-run using the same input file and prompt
    fi
done
```

If the retry also fails, mark that lens as `[FAILED]` in the verdict report — do not silently omit it.

#### Dispatch via Agent Tool (single-model-multi-lens fallback)

When no external CLI is available, spawn independent Claude Agent sub-agents per lens using the Agent tool. Each agent:
- Gets its lens-specific prompt
- Gets the prepared diff content directly in the prompt
- Cannot see other agents' output (isolation is automatic with separate Agent calls)
- Integration lens (Medium/Heavy only): additionally instructed to use Read and Bash tools to explore the codebase for callers and consumers

Run agents in parallel by making multiple Agent tool calls in a single message. Use `subagent_type: "general-purpose"` for each.

### A5. Red-Line Scan

After collecting reviewer findings, scan the filtered diff (from `$TMPDIR/challenger_diff.txt`) for constraint violations:

1. **Project constraints** — read `CLAUDE.md`, `AGENTS.md`, `.ai/constraints.json` (if they exist) and check the diff against any rules they define
2. **Universal red-lines** — scan the diff for:
   - `eval()` or `innerHTML` with user-controlled input
   - Hardcoded secrets (API keys, passwords, tokens in string literals)
   - Unvalidated `process.env` used in security-sensitive contexts
   - `dangerouslySetInnerHTML` with unsanitized content

Violations become additional `[!]` High severity findings prefixed with `[Red-Line]`.

### A6. Aggregate Findings + Produce Verdict Report

Collect all findings from all lenses and the red-line scan. Produce a structured report:

```markdown
## Code Review — {short description of changes}

**Scale**: Light / Medium / Heavy
**Mode**: ${MODE_LABEL} / single-model-multi-lens
**Reviewers**: Challenger [+ Architect] [+ Integration] [+ Devil's Advocate] [+ Subtractor]
**Filtered**: {EXCLUDED_COUNT} noise files excluded, {LARGE_FILE_COUNT} large files summarized, {BUDGET_TRUNCATED} lines budget-truncated

### Verdict: PASS / CONTESTED / REJECT

| # | Sev | Lens | Issue | Decision |
|---|-----|------|-------|----------|
| 1 | [!] | Ch | `file:line` description | Accept — rationale |
| 2 | [~] | Ar | `file:line` description | Dismiss — rationale |

### Summary
{One paragraph: review conclusion and recommended next steps}
```

**Severity levels:**
- `[!]` High — likely bug, security issue, or constraint violation
- `[~]` Medium — design concern or code smell
- `[.]` Low — style, naming, minor improvement

**Verdict rules:**
- **PASS** — no `[!]` findings
- **CONTESTED** — `[!]` findings exist but reviewers disagree (one lens flags it, another doesn't)
- **REJECT** — multiple lenses agree on `[!]` findings, or red-line violations exist

**Decision column:**
- For each finding, Claude evaluates and marks `Accept` (finding is valid, should be addressed) or `Dismiss` (false positive or acceptable trade-off), with a brief rationale
- Wide mode (≤5 findings): rationale inline in the Decision column
- Narrow mode (6+ findings): Decision column shows just `Accept`/`Dismiss`, rationale in a separate **Rationale** section below the table

After the verdict report is complete, clean up temp files:
```bash
rm -rf "$TMPDIR"
```

## Section B: Plan Review Mode

### B1. Locate or create plan file

- If the user provided a file path, confirm it exists and is non-empty
- If no file path was given but you have plan content in the current conversation (e.g., from plan mode), write it to a temp file:
  ```bash
  mktemp /tmp/plan-review-XXXXXX.md
  ```
  Write the plan content to this temp file. Remember to delete it after the review (step B3).
- If no file path and no plan content is available, ask the user

### B2. Run Plan Review

**Via external CLI (if available):**

```bash
{ cat "<plan_file_path>"; cat <<'PROMPT'

---
You are reviewing an implementation plan document.

Review for these categories:
1. COMPLETENESS: TODOs, placeholders, incomplete tasks, missing steps
2. SPEC ALIGNMENT: Requirements coverage, scope creep
3. TASK DECOMPOSITION: Atomic tasks, clear boundaries, actionable steps (2-5 min each)
4. FILE STRUCTURE: Single responsibility per file
5. FILE SIZE: Files that would grow too large to reason about
6. TASK SYNTAX: Checkbox syntax (- [ ]) for tracking
7. CHUNK SIZE: Chunks under 1000 lines, logically self-contained

Also check for:
- Missing verification/expected output after implementation steps
- Missing test-first steps (TDD)
- Incomplete code snippets ("add X here" instead of actual code)
- Missing commit steps between logical units

Output each finding as:
[!]/[~]/[.] [Category] description
PROMPT
} | ${PLAN_DISPATCH_CMD}
```

**Codex-specific flags:** `--skip-git-repo-check` (plan files may not be in a git repo), `--ephemeral` (no persistent state needed). Do NOT use `--uncommitted` — that flag is for code diffs only.

**Fallback (Agent tool):** If no CLI available, spawn a single Agent sub-agent with the plan content and the same review prompt.

### B3. Present findings as structured verdict

Format the plan review output into the verdict table:

```markdown
## Plan Review — {plan title or filename}

**Mode**: ${MODE_LABEL} / single-model-multi-lens

### Verdict: PASS / CONTESTED / REJECT

| # | Sev | Category | Issue | Decision |
|---|-----|----------|-------|----------|
| 1 | [~] | Completeness | Missing verification step after DB migration | Accept |

### Summary
{One paragraph with review conclusion and next steps}
```

### B4. Clean up

If a temp file was created in B1, delete it:
```bash
rm "<temp_file_path>"
```

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Embedding large plans/diffs with `$()` | Prefer piping via `cat` or heredoc to avoid shell argument length limits |
| Sending project constraints to individual reviewers | Constraints go to the red-line scan (A5), not to lens prompts |
| Letting reviewers see each other's output | Each reviewer must run independently — no shared context |
| Skipping scale detection | Always run A2 before dispatching — it determines which lenses to use |
| Overriding the CLI's model setting | Respect the user's config — never pass `--model` (Codex) or `-m` (Gemini) |
| Using `claude -p` from Claude Code | Use the Agent tool for fallback sub-agents, not the `claude` CLI |
| Editing files based on review output | This is a read-only review — present findings only |
| Using raw `git diff` without `$EXCLUDE_PATHS` | Always append `-- . $EXCLUDE_PATHS` to filter noise files from diffs |
| Sending full diff for files over 300 lines | Replace with `git diff --stat` summary + truncation note |
| Exceeding 2000-line budget per reviewer | Apply tail truncation with appended notice after per-file capping |
| Passing `--uncommitted` with a custom prompt (Codex) | These are mutually exclusive in codex-cli. Use piped input with a prompt instead |
| Using `--uncommitted` for plan review (Codex) | Plan review uses piped input with a prompt, not `--uncommitted` |
| Forgetting `--output-format text` (Gemini) | Without it, Gemini may produce interactive output that breaks background execution |
| Omitting `--approval-mode yolo` (Gemini) | Without it, Gemini will prompt for tool approval and hang in background |
