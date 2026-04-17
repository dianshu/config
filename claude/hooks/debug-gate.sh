#!/bin/bash
# PreToolUse hook for Read|Grep|Glob|Edit|Write|Bash: enforces debug discipline phases.
# Phase 1 (no phase1-done): blocks all code tools, forces understanding confirmation first.
# Phase 2 (phase1-done, no phase2-done): blocks Edit/Write/Bash-writes, allows Read/Grep/Glob/Bash-readonly.
# Phase 3+ (phase2-done): allows everything.

INPUT=$(cat)

# Single jq call — one field per line
mapfile -t FIELDS < <(
  echo "$INPUT" | jq -r '
    (.session_id // ""),
    (.tool_name // ""),
    (.tool_input.file_path // .tool_input.path // ""),
    (.tool_input.command // "")
  '
)
SESSION_ID="${FIELDS[0]}"
TOOL_NAME="${FIELDS[1]}"
TARGET_PATH="${FIELDS[2]}"
COMMAND="${FIELDS[3]}"

[[ -z "$SESSION_ID" ]] && exit 0

GATE_DIR="$HOME/.claude/debug-gate/$SESSION_ID"
[[ ! -d "$GATE_DIR" ]] && exit 0

is_claude_path() {
  [[ "$1" == "$HOME/.claude/"* || "$1" == "~/.claude/"* ]]
}

is_claude_command() {
  [[ "$COMMAND" =~ (~/.claude/|\.claude/debug-gate) ]]
}

WRITE_PATTERN='(sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|>[[:space:]]*[^&]|>>[[:space:]]|tee[[:space:]]|install[[:space:]]|patch[[:space:]])'

# Phase 3+: all tools allowed
[[ -f "$GATE_DIR/phase2-done" ]] && exit 0

# Phase 2: phase1-done exists, no phase2-done
if [[ -f "$GATE_DIR/phase1-done" ]]; then
  if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
    is_claude_path "$TARGET_PATH" && exit 0
    echo "Debug phase 2: Reproduce the bug before editing code. Then run: echo done > $GATE_DIR/phase2-done" >&2
    exit 2
  fi
  if [[ "$TOOL_NAME" == "Bash" ]]; then
    is_claude_command && exit 0
    if [[ "$COMMAND" =~ $WRITE_PATTERN ]]; then
      echo "Debug phase 2: Reproduce the bug before modifying files. Then run: echo done > $GATE_DIR/phase2-done" >&2
      exit 2
    fi
  fi
  exit 0
fi

# Phase 1: no phase1-done — block everything except ~/.claude/ paths
is_claude_path "$TARGET_PATH" && exit 0
[[ "$TOOL_NAME" == "Bash" ]] && is_claude_command && exit 0

echo "Debug phase 1: Confirm your understanding with the user first (restate the bug, ask for confirmation). Then run: echo done > $GATE_DIR/phase1-done" >&2
exit 2
