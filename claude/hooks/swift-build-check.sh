#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger on git commit commands
[[ "$COMMAND" =~ ^git\ commit ]] || exit 0

# Only on macOS with xcodebuild
[[ "$(uname)" == "Darwin" ]] || exit 0
command -v xcodebuild &>/dev/null || exit 0

WORKSPACE="$HOME/repos/EarbudIOS/Earbud/Earbud.xcworkspace"
SCHEME="Earbud"

# Only if workspace exists
[[ -d "$WORKSPACE" ]] || exit 0

# Only if we're inside the project directory
[[ "$PWD" == */EarbudIOS* ]] || exit 0

# Run incremental build and extract warnings (exclude Pods)
WARNINGS=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' build 2>&1 \
  | grep "warning:" | grep -v "/Pods/" | grep -v "appintentsmetadataprocessor" | head -30)

if [[ -n "$WARNINGS" ]]; then
  echo "xcodebuild warnings found:" >&2
  echo "$WARNINGS" >&2
  exit 2
fi
exit 0
