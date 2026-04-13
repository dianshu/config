#!/usr/bin/env bash
# PreToolUse hook: ensures Chrome is running with --remote-debugging-port
# before any mcp__chrome__* tool call.

PORT=9222
CHROME_URL="http://localhost:$PORT/json/version"
CHROME_EXE="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"

[[ -z "$WSL_DISTRO_NAME" ]] && { echo '{}'; exit 0; }

if curl -sf --connect-timeout 0.5 "$CHROME_URL" >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

[[ -x "$CHROME_EXE" ]] || {
  echo '{"decision": "block", "reason": "Chrome not found at '"$CHROME_EXE"'"}'
  exit 1
}

# Launch Chrome then minimize its window via PowerShell
CHROME_WIN='C:\Program Files\Google\Chrome\Application\chrome.exe'
setsid pwsh.exe -NoProfile -Command "
  Start-Process '$CHROME_WIN' -ArgumentList '--remote-debugging-port=$PORT','--user-data-dir=Q:\ChromeProfiles\mcp','--no-first-run'
  Start-Sleep -Milliseconds 1500
  Add-Type -Name NativeMethods -Namespace Win32 -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
  Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowHandle -ne 0 } | ForEach-Object { [Win32.NativeMethods]::ShowWindow(\$_.MainWindowHandle, 6) }
" </dev/null >/dev/null 2>&1 &

for ((i=1; i<=15; i++)); do
  if curl -sf --connect-timeout 0.5 "$CHROME_URL" >/dev/null 2>&1; then
    echo '{}'
    exit 0
  fi
  sleep 1
done

echo '{"decision": "block", "reason": "Chrome failed to start on port '"$PORT"' within 15s"}'
exit 1
