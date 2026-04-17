#!/bin/bash
# Test harness for debug-gate hooks.
# Usage: bash ~/.claude/hooks/test-debug-gate.sh

set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREATE_HOOK="$SCRIPT_DIR/debug-gate-create.sh"
GATE_HOOK="$SCRIPT_DIR/debug-gate.sh"
TMPDIR=$(mktemp -d /tmp/debug-gate-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

SESSION_ID="test-session-$(date +%s)"
GATE_DIR="$HOME/.claude/debug-gate/$SESSION_ID"

# Helper: run gate hook with given JSON input, return exit code
run_gate() {
  local json="$1"
  echo "$json" | bash "$GATE_HOOK" 2>/dev/null
  return $?
}

run_gate_stderr() {
  local json="$1"
  echo "$json" | bash "$GATE_HOOK" 2>&1 >/dev/null
}

# Helper: build JSON payload
make_json() {
  local tool_name="$1" tool_input="$2"
  printf '{"session_id":"%s","tool_name":"%s","tool_input":%s}' "$SESSION_ID" "$tool_name" "$tool_input"
}

# Test runner
test_case() {
  local desc="$1" expected_exit="$2" json="$3" expected_stderr_pattern="${4:-}"
  local actual_exit=0 stderr_output

  stderr_output=$(echo "$json" | bash "$GATE_HOOK" 2>&1 >/dev/null) || actual_exit=$?

  if [[ $actual_exit -ne $expected_exit ]]; then
    echo "FAIL: $desc (expected exit=$expected_exit, got=$actual_exit)"
    [[ -n "$stderr_output" ]] && echo "  stderr: $stderr_output"
    FAIL=$((FAIL + 1))
    return
  fi

  if [[ -n "$expected_stderr_pattern" ]]; then
    if ! echo "$stderr_output" | grep -qE "$expected_stderr_pattern"; then
      echo "FAIL: $desc (stderr does not match pattern: $expected_stderr_pattern)"
      echo "  stderr: $stderr_output"
      FAIL=$((FAIL + 1))
      return
    fi
  fi

  echo "PASS: $desc"
  PASS=$((PASS + 1))
}

echo "=== Debug Gate Tests ==="
echo ""

# --- No gate dir: everything passes ---
echo "--- No gate dir ---"

test_case "no-gate-dir: Read passes" 0 \
  "$(make_json "Read" '{"file_path":"/home/fei/repos/app/main.ts"}')"

test_case "no-gate-dir: Edit passes" 0 \
  "$(make_json "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}')"

test_case "no-gate-dir: Bash passes" 0 \
  "$(make_json "Bash" '{"command":"ls -la"}')"

echo ""

# --- No session_id: everything passes ---
echo "--- No session_id ---"

test_case "no-session-id: Read passes" 0 \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/fei/repos/app/main.ts"}}'

echo ""

# --- Create gate dir (simulate debug skill activation) ---
echo "--- Phase 1 (understanding confirmation) ---"
mkdir -p "$GATE_DIR"

test_case "phase1: Read blocked" 2 \
  "$(make_json "Read" '{"file_path":"/home/fei/repos/app/main.ts"}')" \
  "phase 1"

test_case "phase1: Grep blocked" 2 \
  "$(make_json "Grep" '{"pattern":"foo","path":"/home/fei/repos/app"}')" \
  "phase 1"

test_case "phase1: Glob blocked" 2 \
  "$(make_json "Glob" '{"pattern":"**/*.ts","path":"/home/fei/repos/app"}')" \
  "phase 1"

test_case "phase1: Bash blocked" 2 \
  "$(make_json "Bash" '{"command":"cat /home/fei/repos/app/main.ts"}')" \
  "phase 1"

test_case "phase1: Edit blocked" 2 \
  "$(make_json "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}')" \
  "phase 1"

test_case "phase1: Write blocked" 2 \
  "$(make_json "Write" '{"file_path":"/home/fei/repos/app/main.ts","content":"hello"}')" \
  "phase 1"

# ~/.claude/ paths allowed
test_case "phase1: Read ~/.claude/ allowed" 0 \
  "$(make_json "Read" "{\"file_path\":\"$HOME/.claude/skills/debug/SKILL.md\"}")"

test_case "phase1: Bash ~/.claude/ allowed" 0 \
  "$(make_json "Bash" '{"command":"echo done > ~/.claude/debug-gate/test/phase1-done"}')"

echo ""

# --- Phase 2 (reproduction) ---
echo "--- Phase 2 (reproduction) ---"
echo "done" > "$GATE_DIR/phase1-done"

test_case "phase2: Read allowed" 0 \
  "$(make_json "Read" '{"file_path":"/home/fei/repos/app/main.ts"}')"

test_case "phase2: Grep allowed" 0 \
  "$(make_json "Grep" '{"pattern":"foo","path":"/home/fei/repos/app"}')"

test_case "phase2: Glob allowed" 0 \
  "$(make_json "Glob" '{"pattern":"**/*.ts","path":"/home/fei/repos/app"}')"

test_case "phase2: Bash read-only allowed" 0 \
  "$(make_json "Bash" '{"command":"make up"}')"

test_case "phase2: Bash npm test allowed" 0 \
  "$(make_json "Bash" '{"command":"npm test"}')"

test_case "phase2: Edit blocked" 2 \
  "$(make_json "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}')" \
  "phase 2"

test_case "phase2: Write blocked" 2 \
  "$(make_json "Write" '{"file_path":"/home/fei/repos/app/main.ts","content":"hello"}')" \
  "phase 2"

test_case "phase2: Bash sed -i blocked" 2 \
  "$(make_json "Bash" '{"command":"sed -i s/foo/bar/ /home/fei/repos/app/main.ts"}')" \
  "phase 2"

test_case "phase2: Bash redirect blocked" 2 \
  "$(make_json "Bash" '{"command":"echo hello > /home/fei/repos/app/main.ts"}')" \
  "phase 2"

test_case "phase2: Bash tee blocked" 2 \
  "$(make_json "Bash" '{"command":"echo hello | tee /home/fei/repos/app/main.ts"}')" \
  "phase 2"

test_case "phase2: Bash perl -pi blocked" 2 \
  "$(make_json "Bash" '{"command":"perl -pi -e s/foo/bar/ main.ts"}')" \
  "phase 2"

# ~/.claude/ writes allowed in phase 2
test_case "phase2: Write ~/.claude/ allowed" 0 \
  "$(make_json "Write" "{\"file_path\":\"$HOME/.claude/plans/test.md\",\"content\":\"test\"}")"

test_case "phase2: Bash ~/.claude/ allowed" 0 \
  "$(make_json "Bash" '{"command":"echo done > ~/.claude/debug-gate/test/phase2-done"}')"

echo ""

# --- Phase 3+ (all allowed) ---
echo "--- Phase 3+ (all allowed) ---"
echo "done" > "$GATE_DIR/phase2-done"

test_case "phase3: Read allowed" 0 \
  "$(make_json "Read" '{"file_path":"/home/fei/repos/app/main.ts"}')"

test_case "phase3: Edit allowed" 0 \
  "$(make_json "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}')"

test_case "phase3: Write allowed" 0 \
  "$(make_json "Write" '{"file_path":"/home/fei/repos/app/main.ts","content":"hello"}')"

test_case "phase3: Bash allowed" 0 \
  "$(make_json "Bash" '{"command":"sed -i s/foo/bar/ main.ts"}')"

echo ""

# --- Create hook tests ---
echo "--- Create hook ---"

# Clean up test gate dir
rm -rf "$GATE_DIR"

# Test: non-debug skill doesn't create gate dir
echo '{"session_id":"'"$SESSION_ID"'","tool_name":"Skill","tool_input":{"skill":"simplify"}}' | bash "$CREATE_HOOK" 2>/dev/null
if [[ -d "$GATE_DIR" ]]; then
  echo "FAIL: create-hook: non-debug skill created gate dir"
  FAIL=$((FAIL + 1))
else
  echo "PASS: create-hook: non-debug skill ignored"
  PASS=$((PASS + 1))
fi

# Test: debug skill creates gate dir
echo '{"session_id":"'"$SESSION_ID"'","tool_name":"Skill","tool_input":{"skill":"debug"}}' | bash "$CREATE_HOOK" 2>/dev/null
if [[ -d "$GATE_DIR" ]]; then
  echo "PASS: create-hook: debug skill creates gate dir"
  PASS=$((PASS + 1))
else
  echo "FAIL: create-hook: debug skill did not create gate dir"
  FAIL=$((FAIL + 1))
fi

# Test: no session_id doesn't create anything
rm -rf "$GATE_DIR"
echo '{"tool_name":"Skill","tool_input":{"skill":"debug"}}' | bash "$CREATE_HOOK" 2>/dev/null
if [[ -d "$GATE_DIR" ]]; then
  echo "FAIL: create-hook: no session_id created gate dir"
  FAIL=$((FAIL + 1))
else
  echo "PASS: create-hook: no session_id ignored"
  PASS=$((PASS + 1))
fi

echo ""

# --- Cleanup ---
rm -rf "$GATE_DIR"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -gt 0 ]] && exit 1
exit 0
