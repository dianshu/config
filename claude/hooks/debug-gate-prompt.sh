#!/bin/bash
set -euo pipefail
# UserPromptSubmit hook: activates debug gate when /debug slash command is used.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

[[ -z "$SESSION_ID" ]] && exit 0

# Check if user typed /debug (CLI injects <command-name>/debug</command-name>)
if echo "$PROMPT" | grep -q '<command-name>/debug</command-name>'; then
  mkdir -p "$HOME/.claude/debug-gate/$SESSION_ID"
fi

exit 0
