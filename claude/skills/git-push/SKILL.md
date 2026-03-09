---
name: git-push
description: Use when the user wants to push staged git changes, says "push", "/git-push", "push my changes", "create PR", "submit PR", or wants to commit and push work. Automatically determines whether to push directly or create a PR based on branch permissions.
---

# Git Push

Automates pushing staged git changes. Checks push permissions to decide whether to push directly or create an Azure DevOps PR. Handles branch creation, committing, pushing, and optional PR creation with minimal manual input.

## Workflow

Follow these steps strictly and sequentially. Do not skip or reorder.

### 1. Verify staged changes

```bash
git diff --cached --stat
```

If nothing is staged, tell the user and stop. Do not proceed.

### 2. Analyze staged diff

Read the full staged diff (`git diff --cached`) and determine:

- **Commit strategy**: decide whether to make one commit or split into logical groups
- **Commit message(s)**: short, imperative (e.g., "Add UTC timestamp migration")

Also prepare in case the PR path is needed:

- **Branch slug**: short, descriptive, `[a-z0-9-]` only (e.g., `fix-timestamp-utc`)
- **PR title**: concise summary of the change
- **PR description**: 1-3 bullet points explaining what and why. Do NOT include "Generated with Claude Code" or similar.

### 3. Check push permissions

Test whether the current branch can be pushed to directly:

```bash
git push --dry-run origin HEAD 2>&1
```

- If the dry-run **succeeds** (exit code 0): the user has direct push access → follow **Path A** (direct push)
- If the dry-run **fails** (permission denied, branch policy requires PR, etc.): follow **Path B** (create PR)

---

### Path A: Direct push (has permission)

#### A1. Commit staged changes

**Follow these rules exactly:**

- **NEVER unstage or reset.** Do not run `git reset`, `git restore --staged`, or `git checkout --` on any file.
- To split into multiple commits, use `git commit <path1> <path2> ...` to commit specific file subsets from the staged area. This commits only those paths without disturbing the rest of the staging area.
- Use short, imperative commit messages (e.g., "Add UTC timestamp migration").
- If a single commit is appropriate, just run `git commit -m "..."`.

#### A2. Push

```bash
git push origin HEAD
```

#### A3. Done

Print the pushed commit hash and branch. No PR is created.

---

### Path B: Create PR (no direct push permission)

#### B1. Create branch (if on main)

Only if currently on `main`:

```bash
git checkout -b feiyue/<slug>
```

The slug must be a valid git ref name using only `[a-z0-9-]`.

#### B2. Commit staged changes

**Follow these rules exactly:**

- **NEVER unstage or reset.** Do not run `git reset`, `git restore --staged`, or `git checkout --` on any file.
- To split into multiple commits, use `git commit <path1> <path2> ...` to commit specific file subsets from the staged area. This commits only those paths without disturbing the rest of the staging area.
- Use short, imperative commit messages (e.g., "Add UTC timestamp migration").
- If a single commit is appropriate, just run `git commit -m "..."`.

#### B3. Push branch

```bash
git push -u origin HEAD
```

#### B4. Create PR

```bash
az repos pr create --detect --draft --title "<title>" --description "<description>" --output json
```

The `--detect` flag auto-detects org/project/repo from the git remote.

Parse the JSON output to construct the PR web URL:
- Extract `repository.webUrl` and `pullRequestId`
- URL format: `{webUrl}/pullrequest/{pullRequestId}`

#### B5. Open in browser

```bash
sensible-browser "<url>" 2>/dev/null || true
```

Always print the PR URL to the user regardless of whether the browser opens.

---

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Unstaging files to split commits | Use `git commit <paths>` instead — never `git reset` or `git restore --staged` |
| Hardcoding org/project in `az` command | Always use `--detect` to auto-detect from remote |
| Forgetting `--output json` | Required to parse PR URL dynamically |
| Not checking for staged changes first | Always run `git diff --cached --stat` before anything else |
| Skipping dry-run push check | Always test permissions before deciding the push path |
