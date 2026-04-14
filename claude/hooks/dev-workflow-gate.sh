#!/bin/bash
# Stop hook: enforces dev-workflow post-implementation loop.
# Blocks Claude from ending its turn if implementation edits were made
# but the 5-step loop was not completed (or explicitly skipped).

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0
python3 ~/.claude/hooks/dev-workflow-check.py "$TRANSCRIPT"
