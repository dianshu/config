#!/usr/bin/env bash
# SessionStart hook: inject ONE user-level rule by basename (without .md).
# Each rule is registered as its own hook entry in settings.json to keep
# every additionalContext payload well under the 10,000-char persisted-output threshold.
#
# Usage in settings.json:
#   { "type": "command", "command": "bash ~/.claude/hooks/inject-one-user-rule.sh language" }

set -u

name="${1:-}"
if [ -z "$name" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}\n'
  exit 0
fi

file="$HOME/.claude/injected-rules/${name}.md"
if [ ! -f "$file" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}\n'
  exit 0
fi

body=$(cat "$file" 2>/dev/null) || {
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}\n'
  exit 0
}

context="User-level rule (${name}.md) from ~/.claude/injected-rules/:"$'\n\n'"$body"

python3 -c '
import json, sys
ctx = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
' <<< "$context"
