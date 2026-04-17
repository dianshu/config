#!/bin/bash
# PreToolUse hook for Skill tool: activates debug gate when debug skill is invoked.

INPUT=$(cat)
read -r SKILL SESSION_ID < <(
  echo "$INPUT" | jq -r '[(.tool_input.skill // ""), (.session_id // "")] | @tsv'
)

[[ "$SKILL" != "debug" || -z "$SESSION_ID" ]] && exit 0

mkdir -p "$HOME/.claude/debug-gate/$SESSION_ID"
exit 0
