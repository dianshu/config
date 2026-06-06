#!/usr/bin/env bash
# review-prep-diff.sh — Prepare diff slices for review-with-agent workflow.
#
# Replaces the inline A1+A2 bash blocks in the old review-with-agent/SKILL.md.
# Single-source-of-truth for: exclusion paths, untracked snapshot, scale
# detection, diff slicing (challenger + subtractor), per-file/budget caps,
# test-file detection.
#
# Usage: review-prep-diff.sh <tmpdir_prefix>
#
# Output (stdout): single JSON object on success
#   {
#     "scale": "Light|Medium|Heavy",
#     "lines": <int>,
#     "dirs": <int>,
#     "totalFiles": <int>,
#     "filteredFiles": <int>,
#     "excludedCount": <int>,
#     "tmpdir": "/tmp/...",
#     "challengerDiffPath": "/tmp/.../challenger_diff.txt",
#     "subtractorDiffPath": "/tmp/.../subtractor_diff.txt",
#     "contextFlag": "-U1|-U2|-U3",
#     "largeFileCount": <int>,
#     "largeFiles": ["path", ...],
#     "budgetTruncated": <int>,
#     "testFiles": ["path", ...]
#   }
#
# Exit:
#   0 = ok
#   2 = not a git repo / nothing to review
#   3 = no files reviewable after exclusions
#   4 = prepare_diff failure (git diff --no-index returned >1)

set -u

TMPDIR_PREFIX="${1:?usage: review-prep-diff.sh <tmpdir_prefix>}"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "review-prep-diff: not a git repo" >&2; exit 2; }

EXCLUDE_PATHS=':(exclude)**/package-lock.json :(exclude)**/yarn.lock :(exclude)**/pnpm-lock.yaml :(exclude)**/Cargo.lock :(exclude)**/go.sum :(exclude)**/composer.lock :(exclude)**/Gemfile.lock :(exclude)**/poetry.lock :(exclude)**/Pipfile.lock :(exclude)**/*.min.js :(exclude)**/*.min.css :(exclude)**/*.bundle.js :(exclude)**/*.map :(exclude)**/dist/** :(exclude)**/vendor/** :(exclude)**/node_modules/** :(exclude)**/__pycache__/**'

list_files() {
  local FILTER="$1"
  ( git diff --name-only $FILTER -- . $EXCLUDE_PATHS
    git diff --cached --name-only $FILTER -- . $EXCLUDE_PATHS
    git ls-files --others --exclude-standard -- . $EXCLUDE_PATHS
  ) | sort -u
}

UNTRACKED_SET=$(git ls-files --others --exclude-standard -- . $EXCLUDE_PATHS)
is_untracked() { printf '%s\n' "$UNTRACKED_SET" | grep -Fxq -- "$1"; }

TOTAL_FILES=$( ( git diff --name-only; git diff --cached --name-only; git ls-files --others --exclude-standard ) | sort -u | wc -l | tr -d ' ')
FILTERED_FILES=$(list_files "" | wc -l | tr -d ' ')
EXCLUDED_COUNT=$(( TOTAL_FILES - FILTERED_FILES ))

[ "$FILTERED_FILES" -eq 0 ] && { echo "review-prep-diff: no eligible files after exclusions" >&2; exit 3; }

# Delegate scale to the shared script — single source of truth
eval "$(~/.claude/scripts/diff-scale.sh)" || { echo "review-prep-diff: diff-scale failed" >&2; exit 2; }

TMPDIR=$(mktemp -d /tmp/${TMPDIR_PREFIX}-XXXXXX)
case "$SCALE" in
  Light)  CONTEXT_FLAG="-U3" ;;
  Medium) CONTEXT_FLAG="-U2" ;;
  Heavy)  CONTEXT_FLAG="-U1" ;;
esac
MAX_FILE_LINES=300
BUDGET=2000

prepare_diff() {  # $1 = git filter, $2 = output file; prints "<largeFileCount>|<largeFiles>|<budgetTruncated>"
  local FILTER="$1" OUT="$2" PREPARED="" LARGE_FILES="" LARGE_COUNT=0 BUDGET_TRUNCATED=0
  for FILE in $(list_files "$FILTER"); do
    if is_untracked "$FILE"; then
      FILE_DIFF=$(git diff --no-index $CONTEXT_FLAG -- /dev/null "$FILE"); RC=$?
      [ "$RC" -gt 1 ] && { echo "review-prep-diff: git diff --no-index failed for $FILE (rc=$RC)" >&2; return 4; }
    else
      FILE_DIFF=$( (git diff $CONTEXT_FLAG -- "$FILE" && git diff --cached $CONTEXT_FLAG -- "$FILE") )
    fi
    FILE_LINES=$(echo "$FILE_DIFF" | wc -l | tr -d ' ')
    if [ "$FILE_LINES" -gt "$MAX_FILE_LINES" ]; then
      LARGE_FILES="$LARGE_FILES $FILE"
      LARGE_COUNT=$((LARGE_COUNT + 1))
      if is_untracked "$FILE"; then
        STAT="$(wc -l < "$FILE") lines (untracked, new file)"
      else
        STAT=$( (git diff --stat -- "$FILE" && git diff --cached --stat -- "$FILE") )
      fi
      FILE_DIFF="--- $FILE [TRUNCATED: $FILE_LINES lines, stat only] ---
$STAT
--- End truncated ---"
    fi
    PREPARED="$PREPARED
$FILE_DIFF"
  done
  TOTAL_LINES=$(echo "$PREPARED" | wc -l | tr -d ' ')
  if [ "$TOTAL_LINES" -gt "$BUDGET" ]; then
    BUDGET_TRUNCATED=$(( TOTAL_LINES - BUDGET ))
    PREPARED=$(echo "$PREPARED" | head -n "$BUDGET")
    PREPARED="$PREPARED
--- BUDGET TRUNCATED: $BUDGET_TRUNCATED additional lines omitted ($BUDGET line budget) ---"
  fi
  echo "$PREPARED" > "$OUT"
  echo "${LARGE_COUNT}|${LARGE_FILES# }|${BUDGET_TRUNCATED}"
}

CH_META=$(prepare_diff "" "$TMPDIR/challenger_diff.txt") || exit 4
SUB_META=$(prepare_diff "--diff-filter=AM" "$TMPDIR/subtractor_diff.txt") || exit 4

LARGE_FILE_COUNT="${CH_META%%|*}"
REST_TMP="${CH_META#*|}"
LARGE_FILES_LIST="${REST_TMP%|*}"
BUDGET_TRUNCATED="${REST_TMP##*|}"

TEST_PATTERN='(^|/)(tests?|__tests__|spec|specs|e2e|androidTest|unitTest|E2ETests?)/|(\.|_)(test|spec)\.[^/]+$|_test\.go$|Tests?\.(swift|kt|java|cs|m|mm)$|Spec\.swift$|(^|/)test_[^/]+\.py$'
TEST_FILES=$(list_files "" | grep -E "$TEST_PATTERN" || true)

# Build the JSON output. Use printf+jq for safe string escaping.
LARGE_FILES_JSON=$(printf '%s\n' $LARGE_FILES_LIST | grep -v '^$' | jq -R . | jq -s .)
TEST_FILES_JSON=$(printf '%s\n' $TEST_FILES | grep -v '^$' | jq -R . | jq -s .)

jq -n \
  --arg scale "$SCALE" \
  --arg lines "$LINES" \
  --arg dirs "$DIRS" \
  --arg totalFiles "$TOTAL_FILES" \
  --arg filteredFiles "$FILTERED_FILES" \
  --arg excludedCount "$EXCLUDED_COUNT" \
  --arg tmpdir "$TMPDIR" \
  --arg challengerDiffPath "$TMPDIR/challenger_diff.txt" \
  --arg subtractorDiffPath "$TMPDIR/subtractor_diff.txt" \
  --arg contextFlag "$CONTEXT_FLAG" \
  --arg largeFileCount "$LARGE_FILE_COUNT" \
  --argjson largeFiles "$LARGE_FILES_JSON" \
  --arg budgetTruncated "$BUDGET_TRUNCATED" \
  --argjson testFiles "$TEST_FILES_JSON" \
  '{
    scale: $scale,
    lines: ($lines | tonumber),
    dirs: ($dirs | tonumber),
    totalFiles: ($totalFiles | tonumber),
    filteredFiles: ($filteredFiles | tonumber),
    excludedCount: ($excludedCount | tonumber),
    tmpdir: $tmpdir,
    challengerDiffPath: $challengerDiffPath,
    subtractorDiffPath: $subtractorDiffPath,
    contextFlag: $contextFlag,
    largeFileCount: ($largeFileCount | tonumber),
    largeFiles: $largeFiles,
    budgetTruncated: ($budgetTruncated | tonumber),
    testFiles: $testFiles
  }'
