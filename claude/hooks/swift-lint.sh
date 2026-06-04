#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only for .swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0

# Skip if file no longer exists (e.g. deleted)
[[ -f "$FILE_PATH" ]] || exit 0

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

# If reviewdog + git tracked file: filter swiftlint output to changed lines only.
if command -v reviewdog &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --show-toplevel &>/dev/null; then
  REPO_ROOT=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)
  GIT_REL="${FILE_PATH#$REPO_ROOT/}"
  if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$GIT_REL" &>/dev/null; then
    Q_PATH=$(printf '%q' "$GIT_REL")
    ERRORS=$(cd "$PROJECT_ROOT" && swiftlint lint --quiet --reporter checkstyle "$FILE_PATH" 2>/dev/null \
      | (cd "$REPO_ROOT" && reviewdog -f=checkstyle -diff="git diff HEAD -- $Q_PATH" -filter-mode=added -reporter=local) 2>&1)
    if [[ -n "$ERRORS" ]]; then
      # File-level aggregate rules (file_length / type_body_length /
      # function_body_length / cyclomatic_complexity) attach to a single
      # line, so reviewdog treats them as "newly added" whenever the diff
      # happens to touch that line. Re-lint the HEAD version of the file
      # and subtract any aggregate violation that already existed.
      AGG_PATTERN='file_length|type_body_length|function_body_length|cyclomatic_complexity'
      if grep -Eq "$AGG_PATTERN" <<<"$ERRORS"; then
        TMP_BASE=$(mktemp -t swiftlint-base.XXXXXX).swift
        if git -C "$REPO_ROOT" show "HEAD:$GIT_REL" >"$TMP_BASE" 2>/dev/null; then
          BASE_RULES=$(cd "$PROJECT_ROOT" && swiftlint lint --quiet "$TMP_BASE" 2>/dev/null \
            | grep -Eo "($AGG_PATTERN)" | sort -u)
          if [[ -n "$BASE_RULES" ]]; then
            EXCLUDE=$(echo "$BASE_RULES" | paste -sd'|' -)
            ERRORS=$(echo "$ERRORS" | grep -Ev "swiftlint.rules.($EXCLUDE)|\(($EXCLUDE)\)")
          fi
        fi
        rm -f "$TMP_BASE"
      fi
      if [[ -n "$ERRORS" ]]; then
        echo "$ERRORS" >&2
        exit 2
      fi
    fi
    exit 0
  fi
fi

# Fallback: full-file lint
ERRORS=$(cd "$PROJECT_ROOT" && swiftlint lint --quiet "$FILE_PATH" 2>&1)
STATUS=$?
if [[ $STATUS -ne 0 && -n "$ERRORS" ]]; then
  echo "$ERRORS" >&2
  exit 2
fi
exit 0
