---
name: git-push
description: Use when the user wants to push staged git changes, says "push", "send this up", "ship it", "/git-push", "push my changes", "create PR", "submit PR", or after completing implementation when it's time to commit and push. Not for unstaged or unrelated changes — only pushes what's already staged. Tries to push directly; falls back to creating a PR if the push fails.
---

# Git Push

Automates pushing staged git changes. Tries to push directly. If the push fails (permission denied, branch policy, etc.), reverts the local commit and falls back to creating an Azure DevOps PR.

## Workflow

### 1. Verify staged changes

```bash
git diff --cached --stat
```

If nothing is staged, tell the user and stop. Do not proceed.

### 2. Analyze staged diff

Read the full staged diff (`git diff --cached`) and determine:

- **Commit strategy**: decide whether to make one commit or split into logical groups
- **Commit message(s)**: short, imperative (e.g., "Add UTC timestamp migration")

### 3. Commit staged changes

- **Do not unstage or reset files** (`git reset`, `git restore --staged`, `git checkout --`). Unstaging breaks the rollback path — if the push fails in step 4, `git reset --soft HEAD~N` cleanly returns everything to staged. If you've already unstaged files, you can't roll back to a known-good state.
- To split into multiple commits, use `git commit <path1> <path2> ...` to commit specific file subsets from the staged area. This commits only those paths without disturbing the rest of the staging area.
- Use short, imperative commit messages (e.g., "Add UTC timestamp migration").
- If a single commit is appropriate, just run `git commit -m "..."`.

Track how many commits were made (N) — needed for rollback if the push fails.

### 4. Push

```bash
git push origin HEAD
```

### 5. If push succeeds

Print the pushed commit hash and branch. Done.

### 6. If push fails

The push was rejected (permission denied, branch policy, etc.). Revert the local commits and fall back to PR creation:

#### 6a. Revert local commits

```bash
git reset --soft HEAD~N
```

Where N is the number of commits made in step 3. This puts changes back into the staging area.

#### 6b. Create branch (if on main)

Only if currently on `main`:

```bash
git checkout -b feiyue/<slug>
```

The slug must be a valid git ref name using only `[a-z0-9-]`. Derive it from the change description.

#### 6c. Re-commit staged changes

Follow the same commit rules from step 3.

#### 6d. Push branch

```bash
git push -u origin HEAD
```

#### 6e. Create PR

```bash
az repos pr create --detect --draft --auto-complete false --title "<title>" --description "<description>" --output json
```

The `--detect` flag auto-detects org/project/repo from the git remote.

Parse the JSON output to construct the PR web URL:
- Extract `repository.webUrl` and `pullRequestId`
- URL format: `{webUrl}/pullrequest/{pullRequestId}`

Prepare for the PR:
- **PR title**: concise summary of the change
- **PR description**: 1-3 bullet points explaining what and why. Do NOT include "Generated with Claude Code" or similar.

#### 6f. Open in browser

```bash
sensible-browser "<url>" 2>/dev/null || true
```

Always print the PR URL to the user regardless of whether the browser opens.

---

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Unstaging files to split commits | Use `git commit <paths>` instead — unstaging breaks the rollback path (see step 3) |
| Setting auto-complete on PR | Always pass `--auto-complete false` to prevent PRs from auto-completing |
