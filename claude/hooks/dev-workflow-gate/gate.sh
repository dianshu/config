#!/bin/bash
# Stop hook: Codex-driven dev-workflow gate
set -u

# Augmented PATH: ensure Homebrew bin available even under macOS GUI launch
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# 1. Escape hatch
if [ "${SKIP_GATE:-0}" = "1" ]; then
  echo "DEV-WORKFLOW GATE: BYPASSED via SKIP_GATE=1" >&2
  exit 0
fi

# (more steps in later tasks)
exit 0
