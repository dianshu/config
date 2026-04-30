#!/bin/bash
# SessionStart hook: snapshot dirty workspace state so Stop hook can compute
# only this-session-produced changes.
set -u

if [ "${GATE_NO_AUGMENT_PATH:-0}" != "1" ]; then
  export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
fi

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] || [ -z "$CWD" ] && exit 0
git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null || exit 0

CACHE_DIR="$HOME/.claude/cache/gate-baseline"
mkdir -p "$CACHE_DIR"
SNAP="$CACHE_DIR/$SESSION_ID.snapshot"

HASH_CMD=$(command -v shasum >/dev/null && echo "shasum -a 256" || echo "sha256sum")

{
  echo "## status"
  git -C "$CWD" status -s
  echo "## tracked-diff"
  git -C "$CWD" diff HEAD 2>/dev/null
  echo "## cached-diff"
  git -C "$CWD" diff --cached 2>/dev/null
  echo "## untracked-hashes"
  git -C "$CWD" ls-files --others --exclude-standard | while read -r f; do
    HASH=$($HASH_CMD "$CWD/$f" 2>/dev/null | awk '{print $1}')
    echo "$HASH  $f"
  done
} > "$SNAP"

exit 0
