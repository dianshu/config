#!/bin/bash
# Test harness for simplified debug-gate hook.
# The new hook only blocks Edit|Write (on non-~/.claude/ paths) when gate dir exists.
# Usage: bash ~/.claude/hooks/test-debug-gate.sh

set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE_HOOK="$SCRIPT_DIR/debug-gate.sh"

SESSION_ID="test-session-$(date +%s)"
GATE_DIR="$HOME/.claude/debug-gate/$SESSION_ID"

make_json() {
  local tool_name="$1" tool_input="$2"
  printf '{"session_id":"%s","tool_name":"%s","tool_input":%s}' "$SESSION_ID" "$tool_name" "$tool_input"
}

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

echo "=== Debug Gate Tests (Simplified) ==="
echo ""

# --- No gate dir: everything passes ---
echo "--- No gate dir ---"

test_case "no-gate: Edit passes" 0 \
  "$(make_json "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}')"

test_case "no-gate: Write passes" 0 \
  "$(make_json "Write" '{"file_path":"/home/fei/repos/app/main.ts","content":"hello"}')"

echo ""

# --- No session_id: everything passes ---
echo "--- No session_id ---"

test_case "no-session-id: Edit passes" 0 \
  '{"tool_name":"Edit","tool_input":{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}}'

echo ""

# --- Gate active: Edit/Write blocked ---
echo "--- Gate active ---"
mkdir -p "$GATE_DIR"

test_case "gate: Edit blocked" 2 \
  "$(make_json "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}')" \
  "debug-fixer"

test_case "gate: Write blocked" 2 \
  "$(make_json "Write" '{"file_path":"/home/fei/repos/app/main.ts","content":"hello"}')" \
  "debug-fixer"

# ~/.claude/ paths allowed
test_case "gate: Edit ~/.claude/ allowed" 0 \
  "$(make_json "Edit" "{\"file_path\":\"$HOME/.claude/plans/test.md\",\"old_string\":\"a\",\"new_string\":\"b\"}")"

test_case "gate: Write ~/.claude/ allowed" 0 \
  "$(make_json "Write" "{\"file_path\":\"$HOME/.claude/plans/test.md\",\"content\":\"test\"}")"

echo ""

# --- Cleanup ---
rm -rf "$GATE_DIR"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -gt 0 ]] && exit 1
exit 0
