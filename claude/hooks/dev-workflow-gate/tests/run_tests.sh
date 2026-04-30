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
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" \
  bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "non-git repo" "$?" 0

# --- codex missing ---
S=$(make_sandbox); install_real_timeout "$S"
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
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
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
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
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
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
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"session_id":"y","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "pre-existing dirty ignored" "$?" 0

# --- timeline.py extracts events ---
S=$(make_sandbox)
TRANSCRIPT="$S/transcript.jsonl"
cat > "$TRANSCRIPT" <<'TX'
{"type":"user","message":{"content":"/simplify"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/foo.py"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"sed -i 's/a/b/' bar.py"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"codex-review"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I checked, codex is not installed."}]}}
TX
OUT=$(python3 ~/.claude/hooks/dev-workflow-gate/timeline.py "$TRANSCRIPT")
echo "$OUT" | jq -e '.events | length >= 4' >/dev/null \
  && { PASS=$((PASS+1)); echo "  PASS timeline events count"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("timeline events count"); echo "  FAIL: $OUT"; }
echo "$OUT" | jq -e '.events[] | select(.type=="slash_command") | .target == "simplify"' >/dev/null \
  && { PASS=$((PASS+1)); echo "  PASS timeline detects slash command"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("timeline slash command"); echo "  FAIL"; }
echo "$OUT" | jq -e '.events[] | select(.type=="bash_modify") | .target | contains("sed -i")' >/dev/null \
  && { PASS=$((PASS+1)); echo "  PASS timeline detects bash modify"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("timeline bash modify"); echo "  FAIL"; }
echo "$OUT" | jq -e '.events[] | select(.type=="skill") | .target == "codex-review"' >/dev/null \
  && { PASS=$((PASS+1)); echo "  PASS timeline detects skill tool_use"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("timeline skill"); echo "  FAIL"; }
echo "$OUT" | jq -e '.recent_text | length >= 1' >/dev/null \
  && { PASS=$((PASS+1)); echo "  PASS timeline collects recent_text"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("timeline recent_text"); echo "  FAIL"; }

# --- facts.sh outputs key=value ---
S=$(make_sandbox); install_real_timeout "$S"; install_fake_codex "$S" '{}'
git -C "$S/repo" init -q
echo "x" > "$S/repo/new.py"
OUT=$(HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/facts.sh "$S/repo")
echo "$OUT" | grep -q "^codex_path=" \
  && { PASS=$((PASS+1)); echo "  PASS facts has codex_path"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("facts codex_path"); echo "  FAIL: $OUT"; }
echo "$OUT" | grep -q "^untracked_files=" \
  && { PASS=$((PASS+1)); echo "  PASS facts has untracked_files"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("facts untracked"); echo "  FAIL"; }
echo "$OUT" | grep -q "new.py" \
  && { PASS=$((PASS+1)); echo "  PASS facts lists untracked file"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("facts lists untracked"); echo "  FAIL"; }

# --- diff.sh outputs stat + capped hunks ---
S=$(make_sandbox); install_real_timeout "$S"
git -C "$S/repo" init -q
seq 1 500 > "$S/repo/big.py"
git -C "$S/repo" add big.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
seq 100 600 > "$S/repo/big.py"
echo "new" > "$S/repo/new.py"
OUT=$(HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/diff.sh "$S/repo" | head -1500)
echo "$OUT" | grep -q "^## stat" \
  && { PASS=$((PASS+1)); echo "  PASS diff has stat"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("diff stat"); echo "  FAIL"; }
echo "$OUT" | grep -q "^## untracked-preview" \
  && { PASS=$((PASS+1)); echo "  PASS diff has untracked-preview"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("diff untracked"); echo "  FAIL"; }
LINES=$(echo "$OUT" | wc -l)
[ "$LINES" -le 1600 ] \
  && { PASS=$((PASS+1)); echo "  PASS diff under budget ($LINES lines)"; } \
  || { FAIL=$((FAIL+1)); FAILED_NAMES+=("diff budget"); echo "  FAIL: $LINES lines"; }

# --- full review pass (codex returns pass JSON) ---
S=$(make_sandbox); install_real_timeout "$S"
install_fake_codex "$S" '```json
{"verdict":"pass","needs_review":true,"completed":["simplify","codex-review","gemini-review","e2e-verify","verification-before-completion"],"missing":[],"issues":[],"reason":"all steps completed"}
```'
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"f\",\"cwd\":\"$S/repo\"}"
echo "c" >> "$S/repo/a.py"
TRANSCRIPT="$S/transcript.jsonl"
cat > "$TRANSCRIPT" <<'TX'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.py"}}]}}
{"type":"user","message":{"content":"/simplify"}}
TX
INPUT=$(printf '{"session_id":"f","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "full review pass" "$?" 0

# --- block returned by codex ---
S=$(make_sandbox); install_real_timeout "$S"
install_fake_codex "$S" '```json
{"verdict":"block","needs_review":true,"completed":[],"missing":["simplify"],"issues":["simplify not run"],"reason":"missing simplify"}
```'
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"g\",\"cwd\":\"$S/repo\"}"
echo "x" >> "$S/repo/a.py"
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"session_id":"g","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "codex block" "$?" 2
assert_stderr_contains "block reason in stderr" "$S" "missing simplify"

# --- JSON parse failure ---
S=$(make_sandbox); install_real_timeout "$S"
install_fake_codex "$S" 'totally not JSON'
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"h\",\"cwd\":\"$S/repo\"}"
echo "x" >> "$S/repo/a.py"
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"session_id":"h","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "json parse fail" "$?" 2
assert_stderr_contains "parse error msg" "$S" "parse"

# --- raw JSON without code fence (production observed bug) ---
S=$(make_sandbox); install_real_timeout "$S"
install_fake_codex "$S" '{"verdict":"block","needs_review":true,"completed":[],"missing":["simplify"],"issues":[],"reason":"raw JSON no fence"}'
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"r\",\"cwd\":\"$S/repo\"}"
echo "x" >> "$S/repo/a.py"
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"session_id":"r","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "raw json no fence" "$?" 2
assert_stderr_contains "raw json reason" "$S" "raw JSON no fence"

# --- codex timeout ---
S=$(make_sandbox); install_real_timeout "$S"
cat > "$S/path/codex" <<'STUB'
#!/bin/bash
sleep 200
STUB
chmod +x "$S/path/codex"
git -C "$S/repo" init -q
echo "a" > "$S/repo/a.py"; git -C "$S/repo" add a.py
git -C "$S/repo" -c user.email=a@b -c user.name=a commit -q -m init
HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/baseline.sh <<<"{\"session_id\":\"to\",\"cwd\":\"$S/repo\"}"
echo "x" >> "$S/repo/a.py"
TRANSCRIPT="$S/transcript.jsonl"; echo '' > "$TRANSCRIPT"
INPUT=$(printf '{"session_id":"to","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$S/repo")
GATE_TIMEOUT=2 HOME="$S/home" PATH="$S/path" bash ~/.claude/hooks/dev-workflow-gate/gate.sh <<<"$INPUT" 2>"$S/stderr.log"
assert_exit "codex timeout" "$?" 2
assert_stderr_contains "timeout msg" "$S" "timeout"

summary