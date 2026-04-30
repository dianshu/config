#!/bin/bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib.sh"

# --- SKIP_GATE escape hatch ---
S=$(make_sandbox)
SKIP_GATE=1 HOME="$S/home" PATH="$S/path:$PATH" \
  bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<'{}' 2>"$S/stderr.log"
RC=$?
assert_exit "SKIP_GATE bypass" "$RC" 0
assert_stderr_contains "SKIP_GATE warning" "$S" "BYPASSED"

summary