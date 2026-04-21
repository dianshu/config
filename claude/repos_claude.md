The @config repo mirrors dotfiles and tool configs from the home directory. When you change any file under these paths, copy the change to the corresponding config repo path (home → config, one-way sync).

## Sync Rules

1. Full sync: sync total file
2. Diff only: sync changed keys, not the entire file

## Mapping Rules

| Home Directory | Config Repo Path | Sync Rule |
|---|---|---|
| `~/.claude/` | `~/repos/config/claude/` | Full sync |
| `~/.claude/settings.json` | `~/repos/config/claude/settings.json` | Diff only |
| `~/.zshrc` | `~/repos/config/zsh/.zshrc` | Full sync |
| `~/.config/ghostty/config` | `~/repos/config/ghostty/config` | Full sync |
| `~/.config/searxng/settings.yml` | `~/repos/config/searxng/settings.yml` | Full sync |
| `~/.config/glow/glow.yml` | `~/repos/config/glow/glow.yml` | Full sync |
| `~/repos/CLAUDE.md` | `~/repos/config/claude/repo_claude.md` | Full sync |

This directory (`~/repos`) is a normal directory, not a git repo. Do not run git commands directly in this directory.
