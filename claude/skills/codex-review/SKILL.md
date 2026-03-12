---
name: codex-review
description: Use when the user wants a second opinion on code changes or implementation plans, says "codex review", "review with codex", "get a second opinion", "independent review", "review this plan", "codex review plan", or wants an AI review of uncommitted changes or a plan document. Not for reviewing already-committed code — this reviews working-tree diffs or plan files.
---

# Codex Review

Reviews uncommitted git changes or implementation plans using OpenAI's Codex CLI for an independent second opinion.

## Workflow

### 1. Determine review mode

- If the user provided a plan file path or said "review plan" → **Plan Review Mode** (go to Section B)
- If the user said "review changes" or no plan file was specified → **Code Review Mode** (go to Section A)
- If ambiguous → ask the user which mode they want

---

## Section A: Code Review Mode

### A1. Verify there are changes to review

Run:
```bash
git diff --stat && git diff --cached --stat
```

If both are empty, tell the user there are no changes to review and stop.

### A2. Run Codex review

This is a read-only review — do not edit any files based on the output.

```bash
codex exec review --uncommitted --ephemeral
```

**Important:** The `--uncommitted` flag and `[PROMPT]` argument are mutually exclusive in codex-cli. Do NOT pass a custom prompt string when using `--uncommitted` — it will fail with `error: the argument '--uncommitted' cannot be used with '[PROMPT]'`. The built-in review behavior already covers security, correctness, style, and performance.

### A3. Present findings

Display the Codex review output to the user exactly as received. Do not modify, summarize, or editorialize the findings.

If Codex CLI fails (not installed, no API key, network error), show the error message and suggest:
- Check `codex --version` to verify installation
- Check that CODEX_API_KEY is set or `codex login` has been run
- Check network connectivity

---

## Section B: Plan Review Mode

### B1. Locate or create plan file

- If the user provided a file path, confirm it exists and is non-empty
- If no file path was given but you have plan content in the current conversation (e.g., from plan mode), write it to a temp file:
  ```bash
  mktemp /tmp/plan-review-XXXXXX.md
  ```
  Write the plan content to this temp file. Remember to delete it after the review (step B3).
- If no file path and no plan content is available, ask the user

### B2. Run Codex plan review

Run the following command, replacing `<plan_file_path>` with the actual path. This is a read-only review — do not edit any files based on the output.

```bash
cat "<plan_file_path>" | codex exec - --skip-git-repo-check --ephemeral <<'PROMPT'
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

Output:
## Plan Review
**Status:** Approved | Issues Found
**Issues:** - [Task/Section]: [issue] - [why it matters]
**Recommendations:** - [advisory suggestions]
PROMPT
```

Key flags:
- `--skip-git-repo-check` — plan files may not be in a git repo
- `--ephemeral` — no persistent state needed
- No `--uncommitted` — that flag is for code diffs only

**Fallback:** If piping via `cat | codex exec -` fails, try embedding the content directly:
```bash
codex exec "$(cat '<plan_file_path>') --- Review this implementation plan for completeness, task decomposition, missing verification steps, and missing TDD steps. Output a structured review with Status, Issues, and Recommendations." --skip-git-repo-check --ephemeral
```

### B3. Present findings and clean up

Display the Codex review output to the user exactly as received. Do not modify, summarize, or editorialize the findings.

If a temp file was created in B1, delete it now:
```bash
rm "<temp_file_path>"
```

If Codex CLI fails (not installed, no API key, network error), show the error message and suggest:
- Check `codex --version` to verify installation
- Check that CODEX_API_KEY is set or `codex login` has been run
- Check network connectivity

---

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Passing a custom prompt with `--uncommitted` | These are mutually exclusive in codex-cli. Use `--uncommitted` alone for code review. |
| Using `--uncommitted` for plan review | Plan review uses a prompt argument, not `--uncommitted` |
| Embedding large plans with `$()` | Prefer piping via `cat` to avoid shell argument length limits |
