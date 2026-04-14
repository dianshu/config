#!/bin/bash
# PreToolUse hook: blocks git commit/push without completed dev-workflow loop.
# Only activates for git commit/push commands; all other Bash commands pass through.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only gate git commit and git push commands
if ! echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|\|)git\s+(\S+\s+)*?(commit|push)\b'; then
  exit 0
fi

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0
python3 ~/.claude/hooks/dev-workflow-check.py "$TRANSCRIPT"
