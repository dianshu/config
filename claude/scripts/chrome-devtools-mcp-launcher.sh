#!/usr/bin/env bash
set -euo pipefail

PORT=9222
PWSH="/mnt/q/Programs/PowerShell/7/pwsh.exe"
CHROME_EXE='C:\Program Files\Google\Chrome\Application\chrome.exe'
PROFILE_DIR='Q:\ChromeProfiles\mcp'

# Validate PowerShell 7 is available
[[ -x "$PWSH" ]] || { echo "ERROR: PowerShell 7 not found at $PWSH" >&2; exit 1; }

# Check if Chrome DevTools is already running on the port
# Validate it's actually Chrome by checking for "Browser" in /json/version
CHROME_VERSION=$(curl -sf --max-time 2 "http://localhost:$PORT/json/version" 2>/dev/null || true)
if echo "$CHROME_VERSION" | grep -q '"Browser"'; then
  exec npx -y chrome-devtools-mcp@latest --browserUrl "http://localhost:$PORT"
fi

# Launch Chrome on Windows via PowerShell 7
"$PWSH" -NoProfile -Command "Start-Process '$CHROME_EXE' -ArgumentList '--remote-debugging-port=$PORT','--user-data-dir=$PROFILE_DIR'"

# Wait for Chrome DevTools to be ready (up to 15 seconds)
for i in $(seq 1 30); do
  CHROME_VERSION=$(curl -sf --max-time 1 "http://localhost:$PORT/json/version" 2>/dev/null || true)
  if echo "$CHROME_VERSION" | grep -q '"Browser"'; then
    exec npx -y chrome-devtools-mcp@latest --browserUrl "http://localhost:$PORT"
  fi
  sleep 0.5
done

echo "ERROR: Chrome did not start on port $PORT within 15 seconds" >&2
exit 1
