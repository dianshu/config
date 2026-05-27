$scriptUrl = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/pc.ps1"
$phase = $env:PC_PHASE
$pwshLocation = "C:\Programs\PowerShell"

# Phase 1 (default): Install/update PowerShell 7, then relaunch in pwsh.exe
if (-not $phase -or $phase -eq "1") {
    Write-Output "=== Phase 1: Installing/updating PowerShell 7 ==="
    winget install --accept-package-agreements --accept-source-agreements -i -l $pwshLocation -e Microsoft.PowerShell

    if ($PSVersionTable.PSEdition -ne "Core") {
        Write-Output "Relaunching in PowerShell 7..."
        # pwsh.exe may not be in PATH yet after fresh install
        $pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwshExe) {
            $pwshExe = "$pwshLocation\pwsh.exe"
        }
        if (-not (Test-Path $pwshExe)) {
            Write-Error "Could not find pwsh.exe. Please add PowerShell 7 to PATH and re-run."
            exit 1
        }
        $env:PC_PHASE = "2"
        Start-Process $pwshExe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "Invoke-Expression -Command (Invoke-WebRequest -Uri '$scriptUrl').Content; pause"
        pause; exit
    }
    $phase = "2"
}

# Phase 2: Self-elevate to admin (already running in pwsh.exe at this point)
if ($phase -eq "2") {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Output "=== Phase 2: Elevating to admin ==="
        $pwshExe = (Get-Process -Id $PID).Path
        Start-Process $pwshExe -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "`$env:PC_PHASE='3'; Invoke-Expression -Command (Invoke-WebRequest -Uri '$scriptUrl').Content; pause"
        pause; exit
    }
    $phase = "3"
}

# Phase 3: Admin setup (pwsh.exe, elevated)
if ($phase -eq "3") {
    Write-Output "=== Phase 3: Admin setup (pwsh.exe, elevated) ==="

    $packages = @(
        "SublimeHQ.SublimeText.4",
        "Microsoft.VisualStudioCode",
        "Microsoft.Git",
        "Obsidian.Obsidian",
        "Google.Chrome"
    )
    $locations = @(
        "Sublime",
        "VisualStudioCode",
        "Git",
        "Obsidian",
        "Chrome"
    )
    for ($i = 0; $i -lt $packages.Length; $i++) {
        $package = $packages[$i]
        $location = "C:\Programs\" + $locations[$i]
        Write-Output "Going to install $package..."

        winget install --accept-package-agreements --accept-source-agreements -i -l $location -e $package
    }

    Write-Output "Going to create new directories..."
    $needToCreatePaths = @(
        "C:\Repos",
        "C:\ChromeProfiles",
        "C:\ChromeProfiles\mcp"
    )
    foreach ($path in $needToCreatePaths) {
        Write-Output "Going to create $path..."
        New-Item -ItemType Directory -Path $path -Force
    }

    # Launch Phase 4 as regular user (non-elevated) for per-user setup
    Write-Output "Launching Phase 4 (non-elevated) for per-user setup..."
    $pwshExe = (Get-Process -Id $PID).Path
    Start-Process $pwshExe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "`$env:PC_PHASE='4'; Invoke-Expression -Command (Invoke-WebRequest -Uri '$scriptUrl').Content; pause"
    pause; exit
}

# Phase 4: Per-user setup (non-elevated, avoids REGDB_E_CLASSNOTREG for WSL)
if ($phase -eq "4") {
    Write-Output "=== Phase 4: Per-user setup (non-elevated) ==="

    Write-Output "Going to install vscode extensions..."
    $vscodeExtensions = @(
        "github.copilot",
        "github.copilot-chat",
        "ms-python.python",
        "ms-vscode-remote.remote-wsl",
        "panxiaoan.themes-falcon-vscode"
    )
    foreach ($extension in $vscodeExtensions) {
        Write-Output "Going to install vscode extension: $extension..."
        C:\Programs\VisualStudioCode\bin\code.cmd --install-extension $extension
    }

    # Overwrite pwsh profile
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force
    }
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/pwsh_profile.ps1" | Select-Object -ExpandProperty Content | Set-Content -Path $PROFILE -Force

    # Install Maple Mono NF CN font to per-user dir (no admin needed).
    # Windows Terminal settings.json (downloaded below) references this font + grayscale AA
    # for a macOS-like rendering. If the font is missing, Terminal silently falls back to Consolas.
    $fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (-not (Get-ChildItem $fontDir -Filter 'MapleMono-NF-CN-*.ttf' -ErrorAction SilentlyContinue)) {
        Write-Output "Installing Maple Mono NF CN..."
        $mapleVer = "v7.9"
        $tmpZip = "$env:TEMP\MapleMono-NF-CN.zip"
        $tmpDir = "$env:TEMP\MapleMono-NF-CN"
        Invoke-WebRequest -Uri "https://github.com/subframe7536/maple-font/releases/download/$mapleVer/MapleMono-NF-CN.zip" -OutFile $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
        Copy-Item "$tmpDir\*.ttf" -Destination $fontDir -Force
        $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
        Get-ChildItem $fontDir -Filter 'MapleMono-NF-CN-*.ttf' | ForEach-Object {
            New-ItemProperty -Path $regPath -Name ($_.BaseName + ' (TrueType)') -Value $_.FullName -PropertyType String -Force | Out-Null
        }
        Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Maple Mono NF CN installed."
    } else {
        Write-Output "Maple Mono NF CN already installed."
    }

    # Overwrite windows terminal settings.json
    $remoteFile = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/windows_terminal.json"
    $localPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $localDir = Split-Path -Parent $localPath
    if (-not (Test-Path $localDir)) {
        New-Item -ItemType Directory -Path $localDir -Force
    }
    Invoke-WebRequest -Uri $remoteFile -OutFile $localPath

    wsl --update
    wsl --unregister Ubuntu-26.04 2>$null
    wsl --install --no-launch Ubuntu-26.04

    # Overwrite .wslconfig (mirrored networking required for chrome-devtools-mcp and cross-OS localhost access)
    $remoteFile = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/.wslconfig"
    $localPath = "$env:USERPROFILE\.wslconfig"
    $localDir = Split-Path -Parent $localPath
    if (-not (Test-Path $localDir)) {
        New-Item -ItemType Directory -Path $localDir -Force
    }
    Invoke-WebRequest -Uri $remoteFile -OutFile $localPath

    Write-Output 'Init script for Ubuntu-26.04: sudo /bin/bash -c "$(curl -fsSL -H ''Cache-Control: no-cache'' https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/26.04/init.sh)"'
    Write-Output 'Windows Terminal json config: https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/windows_terminal.json'
}
