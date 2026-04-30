#!/bin/bash
# Test helpers shared by run_tests.sh
set -u

PASS=0
FAIL=0
FAILED_NAMES=()

# Each test creates an isolated tmp dir with: a fake $HOME, a tmp git repo, a stub PATH
make_sandbox() {
  SANDBOX=$(mktemp -d /tmp/gate-test-XXXXXX)
  mkdir -p "$SANDBOX/home/.claude/cache/gate-baseline"
  mkdir -p "$SANDBOX/repo"
  mkdir -p "$SANDBOX/path"
  echo "$SANDBOX"
}

# Install fake codex stub at $1, returning $2 from --output-last-message file
install_fake_codex() {
  local sandbox=$1
  local payload=$2
  cat > "$sandbox/path/codex" <<STUB
#!/bin/bash
# Fake codex: write payload to --output-last-message arg
while [ \$# -gt 0 ]; do
  case "\$1" in
    --output-last-message) shift; OUT=\$1 ;;
  esac
  shift
done
[ -n "\${OUT:-}" ] && cat > "\$OUT" <<'PAYLOAD'
$payload
PAYLOAD
exit 0
STUB
  chmod +x "$sandbox/path/codex"
}

# Run gate.sh in sandbox; pass stdin JSON; return exit code; capture stderr
run_gate() {
  local sandbox=$1
  local stdin_json=$2
  HOME="$sandbox/home" PATH="$sandbox/path" \
    bash ~/.claude/hooks/dev-workflow-gate/gate.sh \
    <<<"$stdin_json" 2>"$sandbox/stderr.log"
}

assert_exit() {
  local name=$1; local actual=$2; local expected=$3
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS+1)); echo "  PASS $name"
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "  FAIL $name: expected $expected got $actual"
  fi
}

assert_stderr_contains() {
  local name=$1; local sandbox=$2; local needle=$3
  if grep -qF "$needle" "$sandbox/stderr.log"; then
    PASS=$((PASS+1)); echo "  PASS $name (stderr)"
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name (stderr)")
    echo "  FAIL $name (stderr): missing '$needle'"
    echo "  --- stderr ---"; sed 's/^/  /' "$sandbox/stderr.log"; echo "  ---"
  fi
}

summary() {
  echo ""
  echo "=== $PASS passed, $FAIL failed ==="
  [ $FAIL -eq 0 ] || { printf '  - %s\n' "${FAILED_NAMES[@]}"; exit 1; }
}