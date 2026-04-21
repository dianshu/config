The @config repo mirrors dotfiles and tool configs from the home directory. When you change any files under `~/.claude`, `~/.codex`, or `~/.config`, apply the same changes to the corresponding paths in @config repo so they stay in sync. The map is: `~/.claude/` maps to `@config/claude/`, same pattern for .codex and .config dir

Exception: `~/.claude/settings.json` — only sync the specific changes (added/removed/modified keys), not the entire file. This file contains machine-local permissions and allowlists that differ between environments.

This directory (`~/repos`) is a normal directory, not a git repo. It is used to hold git repos. Do not run git commands directly in this directory.
