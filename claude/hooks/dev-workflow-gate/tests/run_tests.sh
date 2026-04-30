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

# --- stdin parse failure (invalid JSON) ---
S=$(make_sandbox); install_real_timeout "$S"
install_fake_codex "$S" '{}'
HOME="$S/home" PATH="$S/path" \
  bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"not json" 2>"$S/stderr.log"
assert_exit "stdin invalid" "$?" 2
assert_stderr_contains "stdin error msg" "$S" "stdin"

# --- non-git repo: exit 0 quietly ---
S=$(make_sandbox); install_real_timeout "$S"
install_fake_codex "$S" '{}'
TRANSCRIPT="$S/repo/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" \
  bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "non-git repo" "$?" 0

summary