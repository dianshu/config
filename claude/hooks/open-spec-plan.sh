#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" == */docs/superpowers/specs/*.md ]] || \
[[ "$FILE_PATH" == */docs/superpowers/plans/*.md ]] || exit 0

if [[ -n "$WSL_DISTRO_NAME" ]]; then
  command -v subl.exe &>/dev/null || exit 0
  WIN_PATH=$(wslpath -w "$FILE_PATH")
  subl.exe "$WIN_PATH" &
elif [[ "$OSTYPE" == darwin* ]]; then
  command -v subl &>/dev/null || exit 0
  subl "$FILE_PATH" &
fi
exit 0
