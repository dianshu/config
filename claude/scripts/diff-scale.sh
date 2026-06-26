#!/usr/bin/env bash
# diff-scale.sh — Classify uncommitted-change size as Light/Medium/Heavy.
#
# Shared by /finalize (to pick a /code-review effort level) and review-with-agent
# (to pick reviewer lenses + diff context). Single source of truth for "how big
# is this change", so both skills stay in sync.
#
# Scale reflects PRODUCTION change size: test files (unit/e2e/spec) are excluded
# from the LINES and DIRS counts, so a small production change wrapped in a large
# test diff is not misclassified as Heavy. Test changes are still reviewed — the
# review-with-agent workflow adds the TestHygiene lens whenever a test file is
# touched, independent of scale. The "nothing to review" gate still considers
# ALL changes (incl. tests), so a test-only change classifies as Light rather
# than tripping the early exit. "What is a test file" is defined once in
# test-file-pattern.sh (shared with review-prep-diff.sh).
#
# Output (stdout): three lines
#   SCALE=<Light|Medium|Heavy>
#   LINES=<int>     # production (non-test) insertions+deletions+untracked
#   DIRS=<int>      # distinct dirs touched by production (non-test) files
#
# Exit: 0 classified; 2 not a git repo / nothing to review (incl. tests).
#
# Thresholds match review-with-agent/SKILL.md:
#   Light : <50 lines
#   Medium: 50–199 lines
#   Heavy : 200+ lines OR 3+ dirs

set -u

git rev-parse --git-dir >/dev/null 2>&1 || { echo "diff-scale: not a git repo" >&2; exit 2; }

# Single source of truth for the test-file path regex (shared with review-prep-diff.sh).
# Guard the load: a missing/invalid dependency must fail loud (exit 2), never leave
# TEST_PATTERN unset and silently mis-measure every change as 0 lines / Light (the
# consumer's `|| exit 2` gate can't catch that, since the script would still exit 0).
. ~/.claude/scripts/test-file-pattern.sh || true
if [ -z "${TEST_PATTERN:-}" ]; then
  echo "diff-scale: failed to load TEST_PATTERN (test-file-pattern.sh missing or invalid)" >&2; exit 2
fi

# Pathspec magic — must reach git unquoted but without eval (parens trip eval in zsh/bash).
EXCLUDE=':(exclude)**/package-lock.json :(exclude)**/yarn.lock :(exclude)**/pnpm-lock.yaml :(exclude)**/Cargo.lock :(exclude)**/go.sum :(exclude)**/composer.lock :(exclude)**/Gemfile.lock :(exclude)**/poetry.lock :(exclude)**/Pipfile.lock :(exclude)**/*.min.js :(exclude)**/*.min.css :(exclude)**/*.bundle.js :(exclude)**/*.map :(exclude)**/dist/** :(exclude)**/vendor/** :(exclude)**/node_modules/** :(exclude)**/__pycache__/**'

UNTRACKED_SET=$(git ls-files --others --exclude-standard -- . $EXCLUDE)

# All changed files after path exclusions (tracked worktree + staged + untracked).
# Gates "nothing to review" — tests count here, so a test-only change is still
# reviewable (classified Light below, not an early exit).
ALL_FILES=$( { git diff --name-only -- . $EXCLUDE
               git diff --cached --name-only -- . $EXCLUDE
               printf '%s\n' "$UNTRACKED_SET"
             } | sed '/^$/d' | sort -u )

if [ -z "$ALL_FILES" ]; then
  echo "diff-scale: nothing to review" >&2; exit 2
fi

# Production (non-test) subset — the only files that count toward the scale.
PROD_FILES=$(printf '%s\n' "$ALL_FILES" | grep -Ev "$TEST_PATTERN" || true)

# Split production files into untracked (count full file length) vs tracked
# (count diff insertions+deletions). grep -Fxf against the untracked set; both
# greps degrade correctly when either side is empty.
UNTRACKED_PROD=$(printf '%s\n' "$PROD_FILES" | grep -Fxf <(printf '%s\n' "$UNTRACKED_SET") || true)
TRACKED_PROD=$(printf '%s\n' "$PROD_FILES" | grep -Fxvf <(printf '%s\n' "$UNTRACKED_SET") || true)

UNTRACKED_LINES=0
if [ -n "$UNTRACKED_PROD" ]; then
  UNTRACKED_LINES=$(printf '%s\n' "$UNTRACKED_PROD" | while IFS= read -r F; do
    [ -n "$F" ] && [ -f "$F" ] && wc -l < "$F"
  done | awk '{s+=$1} END {print s+0}')
fi

# Tracked production churn (insertions+deletions). Iterate per file with a quoted
# pathspec: paths arrive one-per-line via `read -r`, so spaces/tabs in a path
# (common in iOS/Xcode trees) can't word-split into bogus non-matching pathspecs
# the way an unquoted list would — that silently undercounts to 0 and downgrades
# SCALE. numstat keeps add/del as columns ("-" marks binary); worktree + index are
# summed to match the prior staged+unstaged churn behavior.
TRACKED_LINES=0
if [ -n "$TRACKED_PROD" ]; then
  TRACKED_LINES=$(printf '%s\n' "$TRACKED_PROD" | while IFS= read -r F; do
    [ -n "$F" ] || continue
    git diff --numstat -- "$F"
    git diff --cached --numstat -- "$F"
  done | awk -F'\t' '$1 != "-" { s += $1 + $2 } END {print s+0}')
fi

LINES=$(( TRACKED_LINES + UNTRACKED_LINES ))

DIRS=$(printf '%s\n' "$PROD_FILES" | sed '/^$/d' | xargs -I{} dirname {} 2>/dev/null | sort -u | wc -l | tr -d ' ')

if   [ "$LINES" -ge 200 ] || [ "$DIRS" -ge 3 ]; then SCALE=Heavy
elif [ "$LINES" -ge 50 ];                       then SCALE=Medium
else                                                  SCALE=Light
fi

echo "SCALE=$SCALE"
echo "LINES=$LINES"
echo "DIRS=$DIRS"
