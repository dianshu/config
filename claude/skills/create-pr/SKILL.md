---
name: create-pr
description: Use when the user wants to create a pull request from staged git changes, says "create PR", "/create-pr", "push staged changes as PR", "submit PR", or wants to push work to Azure DevOps for review
---

# Create PR

Automates creating Azure DevOps PRs from staged git changes. Handles branch creation, committing, pushing, and PR creation with minimal manual input.

## Workflow

Follow these steps strictly and sequentially. Do not skip or reorder.

### 1. Verify staged changes

```bash
git diff --cached --stat
```

If nothing is staged, tell the user and stop. Do not proceed.

### 2. Analyze staged diff

Read the full staged diff (`git diff --cached`) and determine:

- **Branch slug**: short, descriptive, `[a-z0-9-]` only (e.g., `fix-timestamp-utc`)
- **PR title**: concise summary of the change
- **PR description**: 1-3 bullet points explaining what and why. Do NOT include "Generated with Claude Code" or similar.
- **Commit strategy**: decide whether to make one commit or split into logical groups

### 3. Pull latest main

```bash
git pull --rebase origin main
```

If there are conflicts, tell the user and stop. Do not attempt to resolve automatically.

### 4. Create branch (if on main)

Only if currently on `main`:

```bash
git checkout -b feiyue/<slug>
```

The slug must be a valid git ref name using only `[a-z0-9-]`.

### 5. Commit staged changes

**This is the most error-prone step. Follow these rules exactly:**

- **NEVER unstage or reset.** Do not run `git reset`, `git restore --staged`, or `git checkout --` on any file.
- To split into multiple commits, use `git commit <path1> <path2> ...` to commit specific file subsets from the staged area. This commits only those paths without disturbing the rest of the staging area.
- Use short, imperative commit messages (e.g., "Add UTC timestamp migration").
- If a single commit is appropriate, just run `git commit -m "..."`.

### 6. Push branch

```bash
git push -u origin HEAD
```

### 7. Create PR

```bash
az repos pr create --detect --draft --title "<title>" --description "<description>" --output json
```

The `--detect` flag auto-detects org/project/repo from the git remote.

Parse the JSON output to construct the PR web URL:
- Extract `repository.webUrl` and `pullRequestId`
- URL format: `{webUrl}/pullrequest/{pullRequestId}`

### 8. Open in browser

```bash
sensible-browser "<url>" 2>/dev/null || true
```

Always print the PR URL to the user regardless of whether the browser opens.

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Unstaging files to split commits | Use `git commit <paths>` instead — never `git reset` or `git restore --staged` |
| Hardcoding org/project in `az` command | Always use `--detect` to auto-detect from remote |
| Forgetting `--output json` | Required to parse PR URL dynamically |
| Not checking for staged changes first | Always run `git diff --cached --stat` before anything else |
| Resolving rebase conflicts automatically | Stop and ask the user — conflicts need human judgment |
