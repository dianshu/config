#!/bin/bash
/mnt/q/Programs/PowerShell/7/pwsh.exe -NoProfile -Command "
  Import-Module BurntToast
  New-BurntToastNotification -Text 'Claude Code', '需要您的注意' -Sound 'Default'
" &>/dev/null &
exit 0
