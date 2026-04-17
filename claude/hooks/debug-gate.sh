#!/bin/bash
# PreToolUse hook for Edit|Write: prevents main agent from directly editing files
# during a debug session. Forces use of debug-fixer agent instead.
#
# Debug sessions are activated by the /debug skill, which sets a session marker.

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[[ -z "$SESSION_ID" ]] && exit 0

GATE_DIR="$HOME/.claude/debug-gate/$SESSION_ID"
[[ ! -d "$GATE_DIR" ]] && exit 0

TARGET_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
[[ "$TARGET_PATH" == "$HOME/.claude/"* || "$TARGET_PATH" == "~/.claude/"* ]] && exit 0

echo "Debug session active: do not edit files directly. Dispatch to the debug-fixer agent instead." >&2
exit 2
