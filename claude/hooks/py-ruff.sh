#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .py files
[[ "$FILE_PATH" =~ \.py$ ]] || exit 0

# Skip if ruff is not installed
command -v ruff &>/dev/null || exit 0

# Run ruff lint, exit 2 to feed errors back to Claude
ERRORS=$(ruff check --target-version py313 --select E,F,I,UP,B,SIM,RUF,N,W --no-fix "$FILE_PATH" 2>&1)
if [[ $? -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
