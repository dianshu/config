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
| `~/.config/ghostty/config` | `~/repos/config/ghostty/config` |
| `~/.config/searxng/settings.yml` | `~/repos/config/searxng/settings.yml` |
| `~/.config/glow/glow.yml` | `~/repos/config/glow/glow.yml` |
| `~/repos/CLAUDE.md` | `~/repos/config/claude/repo_claude.md` |

This directory (`~/repos`) is a normal directory, not a git repo. Do not run git commands directly in this directory.

## Dependency Tracking

When adding a new external command dependency to any hook or script under `~/.claude/`, also add it to `~/.claude/hooks/session-deps-check.sh` in the appropriate platform section (common, macOS, or WSL).
