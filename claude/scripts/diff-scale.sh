#!/usr/bin/env bash
# diff-scale.sh — Classify uncommitted-change size as Light/Medium/Heavy.
#
# Shared by /finalize (to pick a /code-review effort level) and review-with-agent
# (to pick reviewer lenses + diff context). Single source of truth for "how big
# is this change", so both skills stay in sync.
#
# Output (stdout): three lines
#   SCALE=<Light|Medium|Heavy>
#   LINES=<int>
#   DIRS=<int>
#
# Exit: 0 classified; 2 not a git repo / nothing to review.
#
# Thresholds match review-with-agent/SKILL.md A1:
#   Light : <50 lines
#   Medium: 50–199 lines
#   Heavy : 200+ lines OR 3+ dirs

set -u

git rev-parse --git-dir >/dev/null 2>&1 || { echo "diff-scale: not a git repo" >&2; exit 2; }

# Pathspec magic — must reach git unquoted but without eval (parens trip eval in zsh/bash).
EXCLUDE=':(exclude)**/package-lock.json :(exclude)**/yarn.lock :(exclude)**/pnpm-lock.yaml :(exclude)**/Cargo.lock :(exclude)**/go.sum :(exclude)**/composer.lock :(exclude)**/Gemfile.lock :(exclude)**/poetry.lock :(exclude)**/Pipfile.lock :(exclude)**/*.min.js :(exclude)**/*.min.css :(exclude)**/*.bundle.js :(exclude)**/*.map :(exclude)**/dist/** :(exclude)**/vendor/** :(exclude)**/node_modules/** :(exclude)**/__pycache__/**'

UNTRACKED=$(git ls-files --others --exclude-standard -- . $EXCLUDE)
UNTRACKED_LINES=0
if [ -n "$UNTRACKED" ]; then
  UNTRACKED_LINES=$(printf '%s\n' "$UNTRACKED" | while IFS= read -r F; do
    [ -n "$F" ] && [ -f "$F" ] && wc -l < "$F"
  done | awk '{s+=$1} END {print s+0}')
fi

stat_sum() {  # $1 = "insertion"|"deletion"
  { git diff --stat -- . $EXCLUDE | tail -1 | grep -oE "[0-9]+ $1" | grep -oE '[0-9]+'
    git diff --cached --stat -- . $EXCLUDE | tail -1 | grep -oE "[0-9]+ $1" | grep -oE '[0-9]+'
  } | awk '{s+=$1} END {print s+0}'
}

INS=$(stat_sum insertion)
DEL=$(stat_sum deletion)
LINES=$(( INS + DEL + UNTRACKED_LINES ))

DIRS=$( { git diff --name-only -- . $EXCLUDE
          git diff --cached --name-only -- . $EXCLUDE
          printf '%s\n' "$UNTRACKED"
        } | sed '/^$/d' | xargs -I{} dirname {} 2>/dev/null | sort -u | wc -l | tr -d ' ')

if [ "$LINES" -eq 0 ] && [ -z "$UNTRACKED" ]; then
  echo "diff-scale: nothing to review" >&2; exit 2
fi

if   [ "$LINES" -ge 200 ] || [ "$DIRS" -ge 3 ]; then SCALE=Heavy
elif [ "$LINES" -ge 50 ];                       then SCALE=Medium
else                                                  SCALE=Light
fi

echo "SCALE=$SCALE"
echo "LINES=$LINES"
echo "DIRS=$DIRS"
