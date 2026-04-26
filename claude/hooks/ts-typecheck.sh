#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .ts/.tsx files
[[ "$FILE_PATH" =~ \.(ts|tsx)$ ]] || exit 0

# Walk up to find tsconfig.json
DIR=$(dirname "$FILE_PATH")
while [[ "$DIR" != "/" ]]; do
  [[ -f "$DIR/tsconfig.json" ]] && break
  DIR=$(dirname "$DIR")
done
[[ -f "$DIR/tsconfig.json" ]] || exit 0

# Run type check, exit 2 to feed errors back to Claude
cd "$DIR"
ERRORS=$(npx tsc --noEmit --pretty 2>&1 | head -20)
if [[ $? -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
