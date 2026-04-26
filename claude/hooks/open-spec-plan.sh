#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" == */docs/superpowers/specs/*.md ]] || \
[[ "$FILE_PATH" == */docs/superpowers/plans/*.md ]] || exit 0

GLOW=$(command -v glow) || exit 0
ENTR=$(command -v entr) || exit 0
TITLE=$(basename "$FILE_PATH")

ESCAPED_PATH=$(printf '%s' "$FILE_PATH" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
pgrep -f "$ESCAPED_PATH.*entr" &>/dev/null && exit 0

ENTR_CMD="echo '$FILE_PATH' | $ENTR -c $GLOW -w 0 /_"

if [[ -n "$WSL_DISTRO_NAME" ]]; then
  wt.exe -w new --title "$TITLE" wsl.exe -d "$WSL_DISTRO_NAME" -- bash -c "$ENTR_CMD" &
elif [[ "$OSTYPE" == darwin* ]]; then
  open -na Ghostty --args --window-save-state=never -e bash -c "$ENTR_CMD" &>/dev/null &
fi
exit 0
