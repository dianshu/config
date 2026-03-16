---
name: reset-workspace
description: Use when the user wants to reset their workspace, says "reset workspace", "clean up workspace", "switch back to main", "go back to default branch", or wants to start fresh after pushing changes. Switches to the default branch, pulls latest, and clears the session.
---

# Reset Workspace

Resets the local workspace to a clean state on the default branch. Intended for use after pushing changes when the user wants to start fresh.

## Workflow

Follow these steps strictly and sequentially. Do not skip or reorder.

### 1. Check for uncommitted changes

```bash
git status --porcelain
```

If the output is non-empty (any staged or unstaged changes exist), **warn the user and stop**. Do not proceed — uncommitted work would be lost.

### 2. Detect the default branch

```bash
git remote show origin
```

Parse the `HEAD branch:` line from the output to get the default branch name (e.g., `main`, `master`, `develop`).

### 3. Checkout default branch and pull latest

```bash
git checkout <default-branch>
```

```bash
git pull --ff-only
```

Replace `<default-branch>` with the branch name detected in step 2. The `--ff-only` flag overrides the user's global `pull.ff` setting and refuses to create merge commits. If fast-forward isn't possible, it fails — which is correct for a reset-workspace scenario since it indicates unexpected local divergence.

### 4. Clean up stale branches

```bash
git remote prune origin
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D
```

This prunes remote-tracking refs for branches deleted on the remote, then deletes any local branches whose upstream is gone.

### 5. Clear session

Tell the user to run `/clear` to reset the session context, then `/plan` to enter plan mode for their next task. Both are built-in CLI commands that only the user can invoke — the agent cannot run them programmatically.

---

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Proceeding with uncommitted changes | Always check `git status --porcelain` first and stop if non-empty |
| Hardcoding `main` as the default branch | Always detect via `git remote show origin` — repos may use `master`, `develop`, etc. |
| Forgetting to pull after checkout | Always pull to ensure local branch is up to date with remote |
| Creating merge commits from `git pull` | Always use `git pull --ff-only` to override `pull.ff=false` and prevent spurious merge commits |
| Skipping session clear | Always remind the user to run `/clear` then `/plan` — the agent cannot invoke them |
