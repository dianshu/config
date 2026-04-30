#!/bin/bash
# Build budgeted diff output for Codex
set -u
CWD=${1:-.}
PER_FILE=200

cd "$CWD" || exit 1

echo "## stat"
git diff --stat HEAD 2>/dev/null
git diff --cached --stat 2>/dev/null

echo ""
echo "## file-list"
git diff --name-only HEAD 2>/dev/null
git diff --cached --name-only 2>/dev/null
git ls-files --others --exclude-standard 2>/dev/null

echo ""
echo "## per-file-hunks"
for f in $(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null); do
  echo "--- $f ---"
  git diff HEAD -- "$f" 2>/dev/null | head -$PER_FILE
  git diff --cached -- "$f" 2>/dev/null | head -$PER_FILE
done

echo ""
echo "## untracked-preview"
i=0
for f in $(git ls-files --others --exclude-standard 2>/dev/null); do
  i=$((i+1)); [ $i -gt 5 ] && break
  echo "--- (untracked) $f ---"
  git diff --no-index /dev/null "$f" 2>/dev/null | head -$PER_FILE
done
