#!/bin/bash
# SessionStart hook: check that tool dependencies are installed
# Warns about missing tools so silent skips in other hooks don't hide problems

MISSING=()
OS=$(uname)

# Common tools (all platforms)
for cmd in jq git python3 curl npx npm codex; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done

# Optional tools (all platforms)
for cmd in ruff glow entr gemini; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done

# macOS-only tools
if [[ "$OS" == "Darwin" ]]; then
  for cmd in swiftlint xcodebuild gtimeout; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
  done
fi

# WSL-only tools
if grep -qi microsoft /proc/version 2>/dev/null; then
  for cmd in pwsh.exe wt.exe; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
  done
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing tools: ${MISSING[*]}" >&2
  echo "Some hooks/features will be silently skipped." >&2
  exit 0
fi
exit 0
