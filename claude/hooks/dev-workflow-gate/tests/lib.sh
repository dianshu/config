#!/bin/bash
# Test helpers shared by run_tests.sh
set -u

PASS=0
FAIL=0
FAILED_NAMES=()

# Each test creates an isolated tmp dir with: a fake $HOME, a tmp git repo, a stub PATH
# Symlinks common host tools (git/jq/etc) into sandbox PATH; deliberately omits
# timeout/gtimeout so individual tests opt-in via install_real_timeout.
make_sandbox() {
  SANDBOX=$(mktemp -d /tmp/gate-test-XXXXXX)
  mkdir -p "$SANDBOX/home/.claude/cache/gate-baseline"
  mkdir -p "$SANDBOX/repo"
  mkdir -p "$SANDBOX/path"
  for cmd in git jq bash sh head tail wc cat sed grep awk find sort uniq mktemp date dirname basename rm mv cp mkdir touch ln readlink python3 shasum sha256sum diff printf seq xargs tr sleep; do
    src=$(command -v "$cmd" 2>/dev/null)
    [ -n "$src" ] && ln -sf "$src" "$SANDBOX/path/$cmd"
  done
  echo "$SANDBOX"
}

# Symlink real timeout/gtimeout into sandbox PATH (opt-in per test)
install_real_timeout() {
  local sandbox=$1
  for cand in $(command -v timeout 2>/dev/null) $(command -v gtimeout 2>/dev/null) /usr/bin/timeout /opt/homebrew/bin/gtimeout; do
    [ -x "$cand" ] && { ln -sf "$cand" "$sandbox/path/$(basename "$cand")"; return 0; }
  done
  echo "WARN: no timeout binary on host; some tests will be skipped" >&2
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