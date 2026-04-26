#!/bin/bash
if [[ "$(uname)" == "Darwin" ]]; then
    osascript -e 'display notification "需要您的注意" with title "Claude Code" sound name "default"' &>/dev/null &
else
    /mnt/q/Programs/PowerShell/7/pwsh.exe -NoProfile -Command "
      Import-Module BurntToast
      New-BurntToastNotification -Text 'Claude Code', '需要您的注意' -Sound 'Default'
    " &>/dev/null &
fi
exit 0
