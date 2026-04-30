#!/bin/bash
# Stop hook: Codex-driven dev-workflow gate
set -u

# Augmented PATH: ensure Homebrew bin available even under macOS GUI launch.
# Tests can disable by setting GATE_NO_AUGMENT_PATH=1.
if [ "${GATE_NO_AUGMENT_PATH:-0}" != "1" ]; then
  export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
fi

# 1. Escape hatch
if [ "${SKIP_GATE:-0}" = "1" ]; then
  echo "DEV-WORKFLOW GATE: BYPASSED via SKIP_GATE=1" >&2
  exit 0
fi

# 2. Detect timeout cmd
if command -v timeout &>/dev/null; then TIMEOUT_CMD=timeout
elif command -v gtimeout &>/dev/null; then TIMEOUT_CMD=gtimeout
else
  echo "DEV-WORKFLOW GATE: timeout/gtimeout not found (brew install coreutils)" >&2
  exit 2
fi

# 3. Detect codex
if ! command -v codex &>/dev/null; then
  echo "DEV-WORKFLOW GATE: codex CLI required for dev-workflow gate" >&2
  exit 2
fi

# 4. Parse Stop hook stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$CWD" ]; then
  echo "DEV-WORKFLOW GATE: failed to parse stdin (transcript_path/cwd missing)" >&2
  exit 2
fi

# 3. Non-git repo: exit 0
if ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# (more steps in later tasks)
exit 0
