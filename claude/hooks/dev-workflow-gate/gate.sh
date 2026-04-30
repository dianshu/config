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
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$CWD" ]; then
  echo "DEV-WORKFLOW GATE: failed to parse stdin (transcript_path/cwd missing)" >&2
  exit 2
fi

# 5. Non-git repo: exit 0
if ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# 6. Compute "this-session" changes by comparing current state to baseline snapshot
HASH_CMD=$(command -v shasum >/dev/null && echo "shasum -a 256" || echo "sha256sum")
SNAP="$HOME/.claude/cache/gate-baseline/${SESSION_ID:-_unknown}.snapshot"

current_state() {
  echo "## status"
  git -C "$CWD" status -s
  echo "## tracked-diff"
  git -C "$CWD" diff HEAD 2>/dev/null
  echo "## cached-diff"
  git -C "$CWD" diff --cached 2>/dev/null
  echo "## untracked-hashes"
  git -C "$CWD" ls-files --others --exclude-standard | while read -r f; do
    HASH=$($HASH_CMD "$CWD/$f" 2>/dev/null | awk '{print $1}')
    echo "$HASH  $f"
  done
}

CURRENT_TMP=$(mktemp)
current_state > "$CURRENT_TMP"

if [ -f "$SNAP" ]; then
  if diff -q "$SNAP" "$CURRENT_TMP" >/dev/null; then
    rm -f "$CURRENT_TMP"
    exit 0
  fi
else
  if [ -z "$(git -C "$CWD" status --porcelain)" ]; then
    rm -f "$CURRENT_TMP"
    exit 0
  fi
fi
rm -f "$CURRENT_TMP"

# 7. Build prompt parts
HOOK_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
TIMELINE_JSON=$(python3 "$HOOK_DIR/timeline.py" "$TRANSCRIPT_PATH")
FACTS=$(bash "$HOOK_DIR/facts.sh" "$CWD")
DIFF=$(bash "$HOOK_DIR/diff.sh" "$CWD" | head -1500)
PROMPT_TMPL=$(cat "$HOOK_DIR/prompt.md")

PROMPT=$(cat <<EOF
$PROMPT_TMPL

<facts>
$FACTS
</facts>

<timeline>
$TIMELINE_JSON
</timeline>

<diff>
$DIFF
</diff>

REMINDER: facts is ground truth. Output exactly one fenced \`\`\`json block.
EOF
)

# 8. Invoke codex with retry on JSON parse failure
parse_verdict() {
  python3 -c '
import re, sys
raw = sys.stdin.read()
m = re.search(r"```json\s*(\{[\s\S]*?\})\s*```", raw)
if not m:
    m = re.search(r"\{[\s\S]*\}\s*$", raw)
print(m.group(1) if m and m.lastindex else (m.group(0) if m else ""))
'
}

call_codex() {
  local out=$1
  echo "$PROMPT" | $TIMEOUT_CMD "${GATE_TIMEOUT:-120}" codex exec \
    --skip-git-repo-check -s read-only --ephemeral \
    --output-last-message "$out" - 2>/dev/null
}

CODEX_OUT=$(mktemp)
call_codex "$CODEX_OUT"
RC=$?
if [ $RC -eq 124 ]; then
  echo "DEV-WORKFLOW GATE: codex timeout after ${GATE_TIMEOUT:-120}s" >&2
  rm -f "$CODEX_OUT"
  exit 2
fi

VERDICT_JSON=$(parse_verdict < "$CODEX_OUT")

if [ -z "$VERDICT_JSON" ]; then
  call_codex "$CODEX_OUT"
  VERDICT_JSON=$(parse_verdict < "$CODEX_OUT")
fi

if [ -z "$VERDICT_JSON" ] || ! echo "$VERDICT_JSON" | jq empty 2>/dev/null; then
  echo "DEV-WORKFLOW GATE: failed to parse codex JSON output" >&2
  echo "--- raw codex output ---" >&2
  cat "$CODEX_OUT" >&2
  rm -f "$CODEX_OUT"
  exit 2
fi
rm -f "$CODEX_OUT"

VERDICT=$(echo "$VERDICT_JSON" | jq -r '.verdict // "block"')
REASON=$(echo "$VERDICT_JSON" | jq -r '.reason // ""')
MISSING=$(echo "$VERDICT_JSON" | jq -r '.missing // [] | join(", ")')
ISSUES=$(echo "$VERDICT_JSON" | jq -r '.issues // [] | map("  - " + .) | join("\n")')

if [ "$VERDICT" = "pass" ]; then
  exit 0
fi

{
  echo "DEV-WORKFLOW GATE (Codex verdict): block"
  echo "Reason: $REASON"
  [ -n "$MISSING" ] && echo "Missing: $MISSING"
  [ -n "$ISSUES" ] && { echo "Issues:"; printf "%s\n" "$ISSUES"; }
} >&2
exit 2
