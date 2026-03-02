---
name: codex-review
description: Use when the user wants to review code changes with Codex CLI, says "codex review", "/codex-review", "review with codex", or wants an independent AI review of their changes
---

# Codex Code Review

Reviews uncommitted git changes using OpenAI's Codex CLI for an independent second opinion.

## Workflow

Follow these steps strictly and sequentially. Do not skip or reorder.

### 1. Verify there are changes to review

Run:
```bash
git diff --stat && git diff --cached --stat
```

If both are empty, tell the user there are no changes to review and stop.

### 2. Run Codex review

Run the following command. Do NOT modify any files. This is a read-only review.

```bash
codex exec review --uncommitted --ephemeral "Review these changes with focus on:
1. SECURITY: Identify vulnerabilities (injection, XSS, credential exposure, unsafe patterns)
2. CORRECTNESS: Find bugs, logic errors, edge cases, off-by-one errors, race conditions
3. STYLE: Check naming conventions, readability, consistency with surrounding code
4. PERFORMANCE: Flag unnecessary complexity, N+1 patterns, memory leaks, inefficient algorithms

Format findings as:
- [SEVERITY] Category: Description (file:line if applicable)
Severity levels: CRITICAL, WARNING, INFO
End with a summary verdict: APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION."
```

### 3. Present findings

Display the Codex review output to the user exactly as received. Do not modify, summarize, or editorialize the findings.

If Codex CLI fails (not installed, no API key, network error), show the error message and suggest:
- Check `codex --version` to verify installation
- Check that CODEX_API_KEY is set or `codex login` has been run
- Check network connectivity

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Modifying files based on review | This is read-only. Never edit files. |
| Running without checking for changes | Always check git diff first |
| Summarizing Codex output | Show it verbatim — the user wants Codex's actual review |
