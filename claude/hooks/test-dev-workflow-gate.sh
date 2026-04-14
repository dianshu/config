#!/bin/bash
# Test harness for dev-workflow-gate hooks
# Tests the shared Python checker (dev-workflow-check.py) against various transcript scenarios.
# Usage: bash ~/.claude/hooks/test-dev-workflow-gate.sh

set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/dev-workflow-check.py"
STOP_HOOK="$SCRIPT_DIR/dev-workflow-gate.sh"
PRECOMMIT_HOOK="$SCRIPT_DIR/dev-workflow-gate-precommit.sh"
TMPDIR=$(mktemp -d /tmp/dev-workflow-test-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Helper: create a JSONL transcript line for an assistant tool_use
tool_use_line() {
  local name="$1" input_json="$2"
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$name" "$input_json"
}

# Helper: create a JSONL transcript line for assistant text
text_line() {
  local text="$1"
  # Escape quotes in text for JSON
  local escaped
  escaped=$(printf '%s' "$text" | sed 's/"/\\"/g')
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$escaped"
}

# Helper: create all 5 skill invocations
all_skills() {
  tool_use_line "Skill" '{"skill":"simplify"}'
  tool_use_line "Skill" '{"skill":"codex-review"}'
  tool_use_line "Skill" '{"skill":"gemini-review"}'
  tool_use_line "Skill" '{"skill":"e2e-verify"}'
  tool_use_line "Skill" '{"skill":"superpowers:verification-before-completion"}'
}

# Test runner for the Python checker directly
test_checker() {
  local desc="$1" expected_exit="$2" transcript_file="$3" expected_stderr_pattern="${4:-}"
  local actual_exit=0 stderr_output

  stderr_output=$(python3 "$CHECKER" "$transcript_file" 2>&1 >/dev/null) || actual_exit=$?

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

# Test runner for the Stop hook (shell wrapper)
test_stop_hook() {
  local desc="$1" expected_exit="$2" transcript_file="$3" expected_stderr_pattern="${4:-}"
  local actual_exit=0 stderr_output

  stderr_output=$(echo "{\"transcript_path\":\"$transcript_file\"}" | bash "$STOP_HOOK" 2>&1 >/dev/null) || actual_exit=$?

  if [[ $actual_exit -ne $expected_exit ]]; then
    echo "FAIL: [stop-hook] $desc (expected exit=$expected_exit, got=$actual_exit)"
    [[ -n "$stderr_output" ]] && echo "  stderr: $stderr_output"
    FAIL=$((FAIL + 1))
    return
  fi

  if [[ -n "$expected_stderr_pattern" ]]; then
    if ! echo "$stderr_output" | grep -qE "$expected_stderr_pattern"; then
      echo "FAIL: [stop-hook] $desc (stderr does not match pattern: $expected_stderr_pattern)"
      echo "  stderr: $stderr_output"
      FAIL=$((FAIL + 1))
      return
    fi
  fi

  echo "PASS: [stop-hook] $desc"
  PASS=$((PASS + 1))
}

# Test runner for the PreToolUse hook (precommit wrapper)
test_precommit_hook() {
  local desc="$1" expected_exit="$2" command="$3" transcript_file="$4" expected_stderr_pattern="${5:-}"
  local actual_exit=0 stderr_output
  local escaped_cmd
  escaped_cmd=$(printf '%s' "$command" | sed 's/"/\\"/g')

  stderr_output=$(printf '{"tool_input":{"command":"%s"},"transcript_path":"%s"}' "$escaped_cmd" "$transcript_file" | bash "$PRECOMMIT_HOOK" 2>&1 >/dev/null) || actual_exit=$?

  if [[ $actual_exit -ne $expected_exit ]]; then
    echo "FAIL: [precommit] $desc (expected exit=$expected_exit, got=$actual_exit)"
    [[ -n "$stderr_output" ]] && echo "  stderr: $stderr_output"
    FAIL=$((FAIL + 1))
    return
  fi

  if [[ -n "$expected_stderr_pattern" ]]; then
    if ! echo "$stderr_output" | grep -qE "$expected_stderr_pattern"; then
      echo "FAIL: [precommit] $desc (stderr does not match pattern: $expected_stderr_pattern)"
      echo "  stderr: $stderr_output"
      FAIL=$((FAIL + 1))
      return
    fi
  fi

  echo "PASS: [precommit] $desc"
  PASS=$((PASS + 1))
}

echo "=== Dev-Workflow Gate Tests ==="
echo ""

# --- Python checker tests ---

echo "--- Checker: Basic scenarios ---"

# Test 1: No implementation work → pass
F="$TMPDIR/t1.jsonl"
tool_use_line "Read" '{"file_path":"/tmp/x"}' > "$F"
tool_use_line "Grep" '{"pattern":"foo"}' >> "$F"
test_checker "no-impl: only Read/Grep" 0 "$F"

# Test 2: Edit present, no loop steps → blocked
F="$TMPDIR/t2.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_checker "impl-no-workflow: Edit without loop" 2 "$F" "Missing steps.*5/5"

# Test 3: Write present, no loop steps → blocked
F="$TMPDIR/t3.jsonl"
tool_use_line "Write" '{"file_path":"/home/fei/repos/app/new-file.ts","content":"hello"}' > "$F"
test_checker "impl-no-workflow: Write without loop" 2 "$F" "Missing steps.*5/5"

# Test 4: Edit + all 5 steps → pass
F="$TMPDIR/t4.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
all_skills >> "$F"
test_checker "impl-with-all-steps: Edit + all 5 skills" 0 "$F"

# Test 5: Edit + 3/5 steps → blocked, lists 2 missing
F="$TMPDIR/t5.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
tool_use_line "Skill" '{"skill":"simplify"}' >> "$F"
tool_use_line "Skill" '{"skill":"codex-review"}' >> "$F"
tool_use_line "Skill" '{"skill":"gemini-review"}' >> "$F"
test_checker "partial-workflow: 3/5 steps" 2 "$F" "Missing steps.*2/5"

echo ""
echo "--- Checker: Path exclusions ---"

# Test 6: Edit to .claude/plans/ → pass (excluded)
F="$TMPDIR/t6.jsonl"
tool_use_line "Write" '{"file_path":"/home/fei/.claude/plans/my-plan.md","content":"plan"}' > "$F"
test_checker "excluded-path: .claude/plans/" 0 "$F"

# Test 7: Edit to .claude/hooks/ → pass (excluded)
F="$TMPDIR/t7.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/.claude/hooks/my-hook.sh","old_string":"a","new_string":"b"}' > "$F"
test_checker "excluded-path: .claude/hooks/" 0 "$F"

# Test 8: Edit to .claude/rules/ → pass (excluded)
F="$TMPDIR/t8.jsonl"
tool_use_line "Write" '{"file_path":"/home/fei/.claude/rules/my-rule.md","content":"rule"}' > "$F"
test_checker "excluded-path: .claude/rules/" 0 "$F"

# Test 9: Edit to .claude/settings → pass (excluded)
F="$TMPDIR/t9.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/.claude/settings.json","old_string":"a","new_string":"b"}' > "$F"
test_checker "excluded-path: .claude/settings" 0 "$F"

echo ""
echo "--- Checker: Bash commands (not treated as impl) ---"

# Test 10: Bash commands are NOT treated as implementation work
# (implementation detection relies on Edit/Write tools only)
F="$TMPDIR/t10.jsonl"
tool_use_line "Bash" '{"command":"echo hello > /tmp/output.txt"}' > "$F"
test_checker "bash-redirect: not treated as impl" 0 "$F"

# Test 11: Bash with npm test → not impl
F="$TMPDIR/t11.jsonl"
tool_use_line "Bash" '{"command":"npm test"}' > "$F"
test_checker "bash-readonly: npm test" 0 "$F"

# Test 12: Bash with git status → not impl
F="$TMPDIR/t12.jsonl"
tool_use_line "Bash" '{"command":"git status"}' > "$F"
test_checker "bash-readonly: git status" 0 "$F"

echo ""
echo "--- Checker: SKIP declarations ---"

# Test 15: Edit + 3 steps + SKIP for remaining 2 → pass
F="$TMPDIR/t15.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
tool_use_line "Skill" '{"skill":"simplify"}' >> "$F"
tool_use_line "Skill" '{"skill":"codex-review"}' >> "$F"
tool_use_line "Skill" '{"skill":"gemini-review"}' >> "$F"
text_line "SKIP: e2e-verify — reason: no runnable application" >> "$F"
text_line "SKIP: verification-before-completion — reason: config-only change" >> "$F"
test_checker "skip-declarations: 3 steps + 2 skips" 0 "$F"

# Test 16: SKIP with plain hyphen → accepted
F="$TMPDIR/t16.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
all_skills >> "$F"
# Replace e2e-verify with a skip
F="$TMPDIR/t16.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
tool_use_line "Skill" '{"skill":"simplify"}' >> "$F"
tool_use_line "Skill" '{"skill":"codex-review"}' >> "$F"
tool_use_line "Skill" '{"skill":"gemini-review"}' >> "$F"
tool_use_line "Skill" '{"skill":"superpowers:verification-before-completion"}' >> "$F"
text_line "SKIP: e2e-verify - reason: trivial change" >> "$F"
test_checker "skip-with-hyphen: plain hyphen accepted" 0 "$F"

echo ""
echo "--- Checker: Stale loop prevention ---"

# Test 17: Steps BEFORE last edit → blocked
F="$TMPDIR/t17.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
all_skills >> "$F"
# Now add another edit AFTER the skills — skills should be stale
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"b","new_string":"c"}' >> "$F"
test_checker "stale-loop: steps before last edit" 2 "$F" "Missing steps.*5/5"

# Test 18: Steps AFTER last edit → pass
F="$TMPDIR/t18.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"b","new_string":"c"}' >> "$F"
all_skills >> "$F"
test_checker "fresh-loop: steps after last edit" 0 "$F"

echo ""
echo "--- Checker: Edge cases ---"

# Test 19: Empty transcript → pass
F="$TMPDIR/t19.jsonl"
: > "$F"
test_checker "edge: empty transcript" 0 "$F"

# Test 20: Malformed JSONL lines → graceful (doesn't crash)
F="$TMPDIR/t20.jsonl"
echo "not valid json" > "$F"
echo '{"type":"user"}' >> "$F"
test_checker "edge: malformed jsonl" 0 "$F"

# Test 21: Non-existent transcript → pass
test_checker "edge: missing transcript file" 0 "/tmp/nonexistent-transcript-xyz.jsonl"

echo ""
echo "--- Stop hook wrapper tests ---"

# Test 22: Stop hook passes through non-impl session
F="$TMPDIR/t22.jsonl"
tool_use_line "Read" '{"file_path":"/tmp/x"}' > "$F"
test_stop_hook "no-impl passthrough" 0 "$F"

# Test 23: Stop hook blocks impl without workflow
F="$TMPDIR/t23.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_stop_hook "impl blocked" 2 "$F" "Missing steps"

# Test 24: Stop hook with missing transcript_path
test_stop_hook "missing transcript" 0 "/tmp/nonexistent-xyz.jsonl"

echo ""
echo "--- PreToolUse (precommit) hook tests ---"

# Test 25: Non-git command → pass through immediately
F="$TMPDIR/t25.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_precommit_hook "non-git passthrough" 0 "npm test" "$F"

# Test 26: git commit blocked without workflow
F="$TMPDIR/t26.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_precommit_hook "git-commit blocked" 2 "git commit -m 'feat: add auth'" "$F" "Missing steps"

# Test 27: git push blocked without workflow
F="$TMPDIR/t27.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_precommit_hook "git-push blocked" 2 "git push origin main" "$F" "Missing steps"

# Test 28: git commit passes with completed workflow
F="$TMPDIR/t28.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
all_skills >> "$F"
test_precommit_hook "git-commit passes with workflow" 0 "git commit -m 'feat: done'" "$F"

# Test 29: git -C repo commit → detected
F="$TMPDIR/t29.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_precommit_hook "git-C-commit blocked" 2 "git -C /tmp/repo commit -m 'test'" "$F" "Missing steps"

# Test 30: git log → not blocked
F="$TMPDIR/t30.jsonl"
tool_use_line "Edit" '{"file_path":"/home/fei/repos/app/main.ts","old_string":"a","new_string":"b"}' > "$F"
test_precommit_hook "git-log passthrough" 0 "git log --oneline" "$F"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
