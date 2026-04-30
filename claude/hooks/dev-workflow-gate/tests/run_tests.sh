#!/bin/bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/lib.sh"

# Disable PATH augmentation so sandbox PATH is honored
export GATE_NO_AUGMENT_PATH=1

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

# --- codex missing ---
S=$(make_sandbox); install_real_timeout "$S"
TRANSCRIPT="$S/repo/transcript.jsonl"; echo '' > "$TRANSCRIPT"
git -C "$S/repo" init -q
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
echo "x" > "$S/repo/x.py"
INPUT=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "codex missing" "$?" 2
assert_stderr_contains "codex missing msg" "$S" "codex CLI required"

# --- timeout missing ---
S=$(make_sandbox)
install_fake_codex "$S" '{}'
TRANSCRIPT="$S/repo/transcript.jsonl"; echo '' > "$TRANSCRIPT"
git -C "$S/repo" init -q
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
echo "x" > "$S/repo/x.py"
INPUT=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "timeout missing" "$?" 2
assert_stderr_contains "timeout missing msg" "$S" "timeout"

# --- baseline.sh writes snapshot ---
S=$(make_sandbox)
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
echo "b" > "$S/repo/a.py"
echo "x" > "$S/repo/new.py"
INPUT=$(printf '{"session_id":"sess123","cwd":"%s"}' "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"$INPUT"
SNAP="$S/home/.claude/cache/gate-baseline/sess123.snapshot"
[ -f "$SNAP" ] && { PASS=$((PASS+1)); echo "  PASS baseline file created"; } \
                 || { FAIL=$((FAIL+1)); FAILED_NAMES+=("baseline file created"); echo "  FAIL baseline file"; }
grep -q "a.py" "$SNAP" 2>/dev/null && { PASS=$((PASS+1)); echo "  PASS baseline contains modified file"; } \
                       || { FAIL=$((FAIL+1)); FAILED_NAMES+=("baseline contains modified file"); echo "  FAIL"; }
grep -q "new.py" "$SNAP" 2>/dev/null && { PASS=$((PASS+1)); echo "  PASS baseline contains untracked file"; } \
                          || { FAIL=$((FAIL+1)); FAILED_NAMES+=("baseline contains untracked file"); echo "  FAIL"; }

# --- no diff vs baseline → pass ---
S=$(make_sandbox); install_real_timeout "$S"; install_fake_codex "$S" '{"verdict":"block","reason":"should not be called"}'
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
TRANSCRIPT="$S/repo/transcript.jsonl"; echo '' > "$TRANSCRIPT"
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"x\",\"cwd\":\"$S/repo\"}"
INPUT=$(printf '{"session_id":"x","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "no diff vs baseline" "$?" 0

# --- pre-existing dirty (baseline already dirty), no new edits → pass ---
S=$(make_sandbox); install_real_timeout "$S"; install_fake_codex "$S" '{"verdict":"block","reason":"should not be called"}'
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
echo "dirty" >> "$S/repo/a.py"
echo "untracked" > "$S/repo/u.py"
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"y\",\"cwd\":\"$S/repo\"}"
TRANSCRIPT="$S/repo/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"session_id":"y","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "pre-existing dirty ignored" "$?" 0

summary