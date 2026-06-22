The @config repo mirrors dotfiles and tool configs from the home directory. When you change any file under these paths, copy the change to the corresponding config repo path (home → config).

## Sync Rules

- New files: copy/write directly.
- Existing files: Edit only the changed parts — never overwrite the whole file, as home and repo versions may have intentional differences.

## Mapping Rules

| Home Directory | Config Repo Path |
|---|---|
| `~/.claude/` | `~/repos/config/claude/` |
| `~/.claude/settings.json` | `~/repos/config/claude/settings.json` |
| `~/.zshrc` | `~/repos/config/zsh/.zshrc` |
| `~/.zsh_scripts/` | `~/repos/config/zsh/scripts/` |
| `~/.tmux.conf` | `~/repos/config/tmux/.tmux.conf` |
| `~/.config/ghostty/config` | `~/repos/config/ghostty/config` |
| `~/.config/opencode/opencode.json` | `~/repos/config/opencode/opencode.json` |
| `~/.config/searxng/settings.yml` | `~/repos/config/searxng/settings.yml` |
| `~/.config/glow/glow.yml` | `~/repos/config/glow/glow.yml` |
| `~/.gitconfig` | `~/repos/config/git/config` |
| `~/.config/git/ignore` | `~/repos/config/git/ignore` |
| `~/repos/CLAUDE.md` | `~/repos/config/claude/repos_claude.md` |
| `~/.claude/skills/diagnose/` | `~/repos/skills/diagnose/` |
| `~/.claude/skills/grill/` | `~/repos/skills/grill/` |
| `~/.claude/skills/improve-codebase-architecture/` | `~/repos/skills/improve-codebase-architecture/` |
| `~/.claude/skills/issues/` | `~/repos/skills/issues/` |
| `~/.claude/skills/load-feature/` | `~/repos/skills/load-feature/` |
| `~/.claude/skills/prd/` | `~/repos/skills/prd/` |
| `~/.claude/skills/run-next-issue/` | `~/repos/skills/run-next-issue/` |
| `~/.claude/skills/run-all-issues/` | `~/repos/skills/run-all-issues/` |
| `~/.claude/skills/tdd/` | `~/repos/skills/tdd/` |
| `~/.claude/skills/triage/` | `~/repos/skills/triage/` |
| `~/.claude/skills/writing-skills/` | `~/repos/skills/writing-skills/` |

Skills under `~/.claude/skills/` that are managed in the `~/repos/skills` git repo (currently: diagnose, grill, improve-codebase-architecture, issues, load-feature, prd, run-next-issue, run-all-issues, tdd, triage, writing-skills) sync to `~/repos/skills/<name>/` instead of the config repo. Commit and push changes there.

This directory (`~/repos`) is a normal directory, not a git repo. Do not run git commands directly in this directory.

## Dependency Tracking

When adding a new external command dependency to any hook or script under `~/.claude/`, also add it to `~/.claude/hooks/session-deps-check.sh` in the appropriate platform section (common, macOS, or WSL).

## User-Level Rule Injection

User-level rules live under `~/.claude/injected-rules/*.md` (mirrored to `~/repos/config/claude/injected-rules/`). They are **not** loaded automatically by Claude Code — each rule is injected via its own SessionStart hook entry in `settings.json` (one `bash ~/.claude/hooks/inject-one-user-rule.sh <name>` per rule). This avoids the 10,000-char persisted-output threshold that truncates bulk additionalContext payloads.

When you add, remove, or rename a file under `injected-rules/`, you **must** regenerate the SessionStart hook entries:

```bash
bash ~/.claude/hooks/regen-user-rule-hooks.sh
```

`cc_sync` runs this automatically after pulling the latest config, so if you add a rule via the config repo + `cc_sync` workflow, no manual step is needed. The regen script is idempotent — running it when nothing changed is a no-op.

## Download Discipline

In init/sync scripts, always download with `curl -fsSL` (or `wget -q` with explicit failure check). Never `wget URL -O FILE` without `--content-on-error` rejection — `wget` exits 0 on HTTP 404 and writes the error page into the destination, silently corrupting the install. A single 404 hidden this way once made the Ubuntu vimrc setup look fine for years while actually doing nothing; the same path was caught immediately when migrated to `curl -fsSL`.
