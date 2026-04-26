#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0

# Skip if swiftlint is not installed
command -v swiftlint &>/dev/null || exit 0

# Run swiftlint, exit 2 to feed errors back to Claude
ERRORS=$(swiftlint lint --quiet "$FILE_PATH" 2>&1)
if [[ $? -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
