#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .py files
[[ "$FILE_PATH" =~ \.py$ ]] || exit 0

# Skip if file no longer exists (e.g. deleted)
[[ -f "$FILE_PATH" ]] || exit 0

# Skip if ruff is not installed
command -v ruff &>/dev/null || exit 0

RUFF_ARGS=(--target-version py313 --line-length 120 --select E,F,I,UP,B,SIM,RUF,N,W --no-fix)

# If reviewdog is available and the file is inside a git repo, filter to changed lines only.
if command -v reviewdog &>/dev/null && git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel &>/dev/null; then
  REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel)
  REL_PATH=$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH")
  # Tracked by HEAD? If not (new/untracked file), fall through to full-file lint.
  if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$REL_PATH" &>/dev/null; then
    ERRORS=$(cd "$REPO_ROOT" && ruff check "${RUFF_ARGS[@]}" --output-format=rdjson "$REL_PATH" 2>/dev/null \
      | reviewdog -f=rdjson -diff="git diff HEAD -- $REL_PATH" -filter-mode=added -reporter=local 2>&1)
    if [[ -n "$ERRORS" ]]; then
      echo "$ERRORS" >&2
      exit 2
    fi
    exit 0
  fi
fi

# Fallback: full-file lint
ERRORS=$(ruff check "${RUFF_ARGS[@]}" "$FILE_PATH" 2>&1)
if [[ $? -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
