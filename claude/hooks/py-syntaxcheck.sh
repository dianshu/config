#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .py files
[[ "$FILE_PATH" =~ \.py$ ]] || exit 0

# Run syntax check, exit 2 to feed errors back to Claude
ERRORS=$(python3 -m py_compile "$FILE_PATH" 2>&1)
if [[ $? -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
