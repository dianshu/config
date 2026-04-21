#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" == */docs/superpowers/specs/*.md ]] || \
[[ "$FILE_PATH" == */docs/superpowers/plans/*.md ]] || exit 0

GLOW=$(command -v glow) || exit 0
TITLE=$(basename "$FILE_PATH")

ESCAPED_PATH=$(printf '%s' "$FILE_PATH" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
pgrep -f "$GLOW.*$ESCAPED_PATH" &>/dev/null && exit 0

if [[ -n "$WSL_DISTRO_NAME" ]]; then
  wt.exe -w new --title "$TITLE" wsl.exe -d "$WSL_DISTRO_NAME" -- "$GLOW" "$FILE_PATH" &
elif [[ "$OSTYPE" == darwin* ]]; then
  ghostty -e "$GLOW" "$FILE_PATH" --title="$TITLE" &
fi
exit 0
