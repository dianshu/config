---
name: push
description: Use when the user wants to push git changes, says "push", "send this up", "ship it", "/push", "push my changes", "create PR", "submit PR", or after completing implementation when it's time to commit and push. Handles both staged and unstaged changes. Tries to push directly; falls back to creating a PR if the push fails.
---

# Push

Automates committing and pushing git changes. Handles staged and unstaged changes. Tries to push directly. If the push fails (permission denied, branch policy, etc.), reverts the local commit and falls back to creating an Azure DevOps PR.

## Workflow

### 1. Check working tree status

```bash
git status --short
git diff --cached --stat
```

Determine what exists:
- **Staged changes**: files in the index ready to commit
- **Unstaged changes**: modified tracked files not yet staged
- **Untracked files**: new files not yet tracked

If nothing is staged AND nothing is modified/untracked, tell the user and stop.

### 2. Handle unstaged/untracked changes

If there are **staged changes already**, skip to step 3.

If **nothing is staged** but there are unstaged or untracked changes:
- Identify which files were created or modified **by this conversation session** (files you edited, wrote, or generated during this session)
- **Auto-stage only those session-produced files** via `git add <path1> <path2> ...`
- **NEVER stage files that were not touched in this session** — pre-existing dirty files, unrelated modifications, or changes from other tools must be left alone
- If after filtering there is nothing to stage, tell the user and stop

### 3. Analyze staged diff

Read the full staged diff (`git diff --cached`) and determine:

- **Commit strategy**: decide whether to make one commit or split into logical groups
- **Commit message(s)**: short, imperative (e.g., "Add UTC timestamp migration")

### 4. Commit staged changes

- **Do not unstage or reset files** (`git reset`, `git restore --staged`, `git checkout --`). Unstaging breaks the rollback path — if the push fails in step 5, `git reset --soft HEAD~N` cleanly returns everything to staged. If you've already unstaged files, you can't roll back to a known-good state.
- To split into multiple commits, use `git commit <path1> <path2> ...` to commit specific file subsets from the staged area. This commits only those paths without disturbing the rest of the staging area.
- Use short, imperative commit messages (e.g., "Add UTC timestamp migration").
- If a single commit is appropriate, just run `git commit -m "..."`.

Track how many commits were made (N) — needed for rollback if the push fails.

### 5. Push

```bash
git push origin HEAD
```

### 6. If push succeeds

Print the pushed commit hash and branch. Done.

### 7. If push fails

The push was rejected (permission denied, branch policy, etc.). Revert the local commits and fall back to PR creation:

#### 7a. Revert local commits

```bash
git reset --soft HEAD~N
```

Where N is the number of commits made in step 4. This puts changes back into the staging area.

#### 7b. Create branch (if on main)

Only if currently on `main`:

```bash
git checkout -b feiyue/<slug>
```

The slug must be a valid git ref name using only `[a-z0-9-]`. Derive it from the change description.

#### 7c. Re-commit staged changes

Follow the same commit rules from step 4.

#### 7d. Push branch

```bash
git push -u origin HEAD
```

#### 7e. Create PR

**Draft PR description before invoking `az`:**

- Read the full branch diff (`git diff origin/<base>...HEAD`), not just the latest commit.
- **Default to the structured template below.** Use bullets, not prose paragraphs — reviewers scan, they don't read. Ground claims in the actual diff (specific files/functions/flags), but don't restate the file list.
- **Exception:** trivial single-concern changes (typo, one-line fix, doc tweak) may use a single sentence with no headings.
- Title: concise, imperative; match the repo's existing PR title style (Conventional Commits if used).
- Do NOT include "Generated with Claude Code" or similar attribution.

**Template** (omit any section that doesn't apply — don't write "N/A"):

```markdown
## Summary
One sentence: what changed and why it matters.

## Changes
- `<file or area>`: what changed
- `<file or area>`: what changed

## Verification
- How it was tested (E2E test name, unit test, manual repro)

## Notes
- Side fixes, follow-ups, caveats reviewers should know
```

Keep each bullet to one line. If a bullet needs a sub-point, indent with `  - `.

Then invoke:

```bash
az repos pr create --detect --draft --auto-complete false --title "<title>" --description "<description>" --output json
```

The `--detect` flag auto-detects org/project/repo from the git remote.

Parse the JSON output to construct the PR web URL:
- Extract `repository.webUrl` and `pullRequestId`
- URL format: `{webUrl}/pullrequest/{pullRequestId}`

#### 7f. Open PR in browser

1. Print the PR URL to the user.
2. Open the PR in Chrome:
   ```
   mcp__chrome__new_page({ url: "<pr_url>" })
   ```
3. Wait for the page to load, then take a snapshot:
   ```
   mcp__chrome__take_snapshot()
   ```
4. If the snapshot shows a login/auth page (e.g., Azure DevOps sign-in):
   - Look for a pre-authenticated account option (e.g., an account tile or "Sign in as ..." button) and click it.
   - If multiple accounts are shown, pick the one matching the organization.
   - After clicking, wait for navigation to complete and take another snapshot to confirm the PR page loaded.
   - If no pre-authenticated account is available, tell the user: "Please log in in the browser, then let me know when you're done." After they confirm, re-snapshot and continue.
5. Once the PR page is confirmed loaded, report success.

---

## Common Mistakes

| Mistake | Prevention |
|---------|-----------|
| Unstaging files to split commits | Use `git commit <paths>` instead — unstaging breaks the rollback path (see step 4) |
| Setting auto-complete on PR | Always pass `--auto-complete false` to prevent PRs from auto-completing |
| Stopping when nothing is staged | Auto-stage files changed in this session — but never stage pre-existing dirty files (see step 2) |
| Vague PR description ("improved X", "fixed bug") | Read full `git diff origin/<base>...HEAD` and explain what changed and why |
