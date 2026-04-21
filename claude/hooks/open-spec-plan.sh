#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" == */docs/superpowers/specs/*.md ]] || \
[[ "$FILE_PATH" == */docs/superpowers/plans/*.md ]] || exit 0

GLOW=$(command -v glow) || exit 0
TITLE=$(basename "$FILE_PATH")

pgrep -f "$GLOW.*$FILE_PATH" &>/dev/null && exit 0

if [[ -n "$WSL_DISTRO_NAME" ]]; then
  wt.exe -w new --title "$TITLE" wsl.exe -d "$WSL_DISTRO_NAME" -- "$GLOW" -p -s dracula -w 0 "$FILE_PATH" &
elif [[ "$OSTYPE" == darwin* ]]; then
  ghostty -e "$GLOW" -p -s dracula -w 0 "$FILE_PATH" --title="$TITLE" &
fi
exit 0
