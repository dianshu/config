The @config repo mirrors dotfiles and tool configs from the home directory. When you change any file under these paths, copy the change to the corresponding config repo path (home → config, one-way sync).

## Sync Rules

1. Full sync: sync total file
2. Diff only: sync changed keys, not the entire file

## Mapping Rules

| Home Directory | Config Repo Path | Sync Rule |
|---|---|---|
| `~/.claude/` | `claude/` | Full sync |
| `~/.claude/settings.json` | `claude/settings.json` | Diff only |
| `~/.zshrc` | `zsh/.zshrc` | Full sync |
| `~/.config/ghostty/config` | `ghostty/config` | Full sync |
| `~/.config/searxng/settings.yml` | `searxng/settings.yml` | Full sync |
| `~/.config/glow/glow.yml` | `glow/glow.yml` | Full sync |

This directory (`~/repos`) is a normal directory, not a git repo. Do not run git commands directly in this directory.
