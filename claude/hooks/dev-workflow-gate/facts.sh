#!/bin/bash
# Probe facts under augmented PATH; output key=value lines
set -u
CWD=${1:-.}

probe() {
  local name=$1
  local p
  p=$(\command -v "$name" 2>/dev/null || true)
  echo "${name//-/_}_path=${p:-}"
}

probe codex
probe gemini
probe bun
probe pnpm
probe npm
probe timeout
probe gtimeout

PM=""
if [ -f "$CWD/package.json" ]; then
  PM=$(jq -r '.packageManager // empty' "$CWD/package.json" 2>/dev/null)
fi
echo "package_manager=$PM"

UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null \
  | head -20 | tr '\n' ',' | sed 's/,$//')
echo "untracked_files=$UNTRACKED"
