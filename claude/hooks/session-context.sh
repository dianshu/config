#!/bin/bash
# SessionStart hook: inject recent git activity into context
# stdout with exit 0 → added to Claude's context

git rev-parse --is-inside-work-tree &>/dev/null || exit 0

echo "Recent commits:"
git log --oneline -3 2>/dev/null
exit 0
