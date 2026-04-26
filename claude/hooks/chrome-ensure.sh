#!/usr/bin/env bash
# PreToolUse hook: ensures Chrome is running with --remote-debugging-port
# before any mcp__chrome__* tool call.

PORT=9222
CHROME_URL="http://localhost:$PORT/json/version"
CHROME_EXE="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"

if curl -sf --connect-timeout 0.5 "$CHROME_URL" >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

launch_chrome_macos() {
  local chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [[ -x "$chrome_bin" ]] || {
    echo '{"decision": "block", "reason": "Chrome not found at '"$chrome_bin"'"}'
    exit 1
  }
  "$chrome_bin" --remote-debugging-port=$PORT --user-data-dir="$HOME/.chrome-mcp-profile" --no-first-run </dev/null >/dev/null 2>&1 &
}

launch_chrome_wsl() {
  [[ -x "$CHROME_EXE" ]] || {
    echo '{"decision": "block", "reason": "Chrome not found at '"$CHROME_EXE"'"}'
    exit 1
  }
  local CHROME_WIN='C:\Program Files\Google\Chrome\Application\chrome.exe'
  setsid pwsh.exe -NoProfile -Command "
    Start-Process '$CHROME_WIN' -ArgumentList '--remote-debugging-port=$PORT','--user-data-dir=Q:\ChromeProfiles\mcp','--no-first-run'
    Start-Sleep -Milliseconds 1500
    Add-Type -Name NativeMethods -Namespace Win32 -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
    Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowHandle -ne 0 } | ForEach-Object { [Win32.NativeMethods]::ShowWindow(\$_.MainWindowHandle, 6) }
  " </dev/null >/dev/null 2>&1 &
}

if [[ -n "$WSL_DISTRO_NAME" ]]; then
  launch_chrome_wsl
elif [[ "$(uname)" == "Darwin" ]]; then
  launch_chrome_macos
else
  echo '{}'
  exit 0
fi

for ((i=1; i<=15; i++)); do
  if curl -sf --connect-timeout 0.5 "$CHROME_URL" >/dev/null 2>&1; then
    echo '{}'
    exit 0
  fi
  sleep 1
done

echo '{"decision": "block", "reason": "Chrome failed to start on port '"$PORT"' within 15s"}'
exit 1
