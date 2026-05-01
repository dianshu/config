#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0

# Skip if swiftlint is not installed
command -v swiftlint &>/dev/null || exit 0

# Locate the project root (nearest ancestor containing .swiftlint.yml).
# No config => no opinion, exit silently.
DIR=$(dirname "$FILE_PATH")
PROJECT_ROOT=""
while [[ "$DIR" != "/" && "$DIR" != "." ]]; do
  if [[ -f "$DIR/.swiftlint.yml" ]]; then
    PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done
[[ -n "$PROJECT_ROOT" ]] || exit 0

# Skip files inside excluded paths (Pods, .build, DerivedData, etc.)
REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"
case "$REL_PATH" in
  Pods/*|.build/*|DerivedData/*) exit 0 ;;
esac

# Run swiftlint from project root so .swiftlint.yml + relative baseline resolve
ERRORS=$(cd "$PROJECT_ROOT" && swiftlint lint --quiet "$FILE_PATH" 2>&1)
STATUS=$?
if [[ $STATUS -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
