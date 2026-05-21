#!/usr/bin/env bash
# Regenerate the SessionStart hook entries in settings.json for every file under
# ~/.claude/injected-rules/*.md. Run after adding or removing rule files.
#
# Replaces all existing inject-one-user-rule.sh entries with a freshly-built
# sorted set, and preserves the relative order of other SessionStart hooks
# (deps-check, load-project-rules) at the front.

set -euo pipefail

regen_one() {
  local settings_path="$1"
  [ -f "$settings_path" ] || { echo "  skip: $settings_path not found"; return; }

  local rules_dir="$HOME/.claude/injected-rules"
  local names=()
  shopt -s nullglob
  for f in "$rules_dir"/*.md; do
    names+=("$(basename "$f" .md)")
  done
  shopt -u nullglob
  IFS=$'\n' names=($(printf '%s\n' "${names[@]}" | sort))
  unset IFS

  local entries_json
  entries_json=$(printf '%s\n' "${names[@]}" | python3 -c '
import json, sys
names = [l.strip() for l in sys.stdin if l.strip()]
out = [
    {"type": "command",
     "command": f"bash ~/.claude/hooks/inject-one-user-rule.sh {n}"}
    for n in names
]
print(json.dumps(out))
')

  local tmp
  tmp=$(mktemp)
  jq --argjson new "$entries_json" '
    .hooks.SessionStart[0].hooks |= (
      # Strip all existing inject-one-user-rule entries (idempotent)
      map(select(.command | test("inject-one-user-rule\\.sh") | not))
      # Append the freshly-built set
      + $new
    )
  ' "$settings_path" > "$tmp"

  mv "$tmp" "$settings_path"
  python3 -m json.tool "$settings_path" > /dev/null
  echo "  updated: $settings_path  (${#names[@]} rules)"
}

echo "=== Regenerating per-rule SessionStart hook entries ==="
regen_one "$HOME/.claude/settings.json"
regen_one "$HOME/repos/config/claude/settings.json"
echo "Done."
