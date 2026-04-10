$scriptUrl = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/devbox.ps1"
$phase = $env:DEVBOX_PHASE
$pwshLocation = "Q:\Programs\PowerShell"

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
        $env:DEVBOX_PHASE = "2"
        Start-Process $pwshExe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "Invoke-Expression -Command (Invoke-WebRequest -Uri '$scriptUrl').Content"
        exit
    }
    $phase = "2"
}

# Phase 2: Self-elevate to admin (already running in pwsh.exe at this point)
if ($phase -eq "2") {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Output "=== Phase 2: Elevating to admin ==="
        $pwshExe = (Get-Process -Id $PID).Path
        Start-Process $pwshExe -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "`$env:DEVBOX_PHASE='3'; Invoke-Expression -Command (Invoke-WebRequest -Uri '$scriptUrl').Content; pause"
        exit
    }
    $phase = "3"
}

# Phase 3: Admin setup (pwsh.exe, elevated)
if ($phase -eq "3") {
    Write-Output "=== Phase 3: Admin setup (pwsh.exe, elevated) ==="

    $needToUninstallPackages = @(
        "Microsoft.VisualStudioCode",
        "Anaconda.Anaconda3",
        "Notepad++.Notepad++",
        "Oracle.JavaRuntimeEnvironment",
        "Microsoft.Edge.Beta",
        "Microsoft.Office",
        "OpenJS.NodeJS.LTS",
        "GoLang.Go",
        "Microsoft.AzureCLI",
        "Unity.UnityHub",
        "Microsoft.Azure.CosmosEmulator",
        "Microsoft.msodbcsql.17",
        "GitHub.cli",
        "Microsoft.CLRTypesSQLServer.2019",
        "Microsoft.VisualStudio.2022.Enterprise"
    )
    foreach ($package in $needToUninstallPackages) {
        Write-Output "Going to uninstall $package..."
        winget uninstall -e $package --nowarn --disable-interactivity --silent --purge --accept-source-agreements
    }

    $packages = @(
        "SublimeHQ.SublimeText.4",
        "Microsoft.VisualStudioCode",
        "Python.Python.3.13",
        "Microsoft.Git",
        "Obsidian.Obsidian",
        "Google.Chrome"
    )
    $locations = @(
        "Sublime",
        "VisualStudioCode",
        "Python313",
        "Git",
        "Obsidian",
        "Chrome"
    )
    for ($i = 0; $i -lt $packages.Length; $i++) {
        $package = $packages[$i]
        $location = "Q:\Programs\" + $locations[$i]
        Write-Output "Going to install $package..."

        winget install --accept-package-agreements --accept-source-agreements -i -l $location -e $package
    }

    Write-Output "Going to uninstall old Az PowerShell module..."
    Get-ChildItem "C:\Program Files\WindowsPowerShell\Modules\Az*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "Removing $($_.FullName)..."
        Remove-Item -Path $_.FullName -Recurse -Force
    }
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\PowerShell\ModuleAnalysisCache" -Force -ErrorAction SilentlyContinue

    Write-Output "Going to delete redundant directories and files..."
    $needToDeletePaths = @(
        "Q:\Edge",
        "Q:\src",
        "Q:\cr",
        "Q:\.tools\QuickBuild",
        "C:\CommonTools\*"
    )
    foreach ($path in $needToDeletePaths) {
        Write-Output "Going to delete $path..."
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Output "Going to create new directories..."
    $needToCreatePaths = @(
        "Q:\Repos",
        "Q:\ChromeProfiles",
        "Q:\ChromeProfiles\mcp",
        "Q:\ObsidianVaults"
    )
    foreach ($path in $needToCreatePaths) {
        Write-Output "Going to create $path..."
        New-Item -ItemType Directory -Path $path -Force
    }

    # Launch Phase 4 as regular user (non-elevated) for per-user setup
    Write-Output "Launching Phase 4 (non-elevated) for per-user setup..."
    $pwshExe = (Get-Process -Id $PID).Path
    Start-Process $pwshExe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "`$env:DEVBOX_PHASE='4'; Invoke-Expression -Command (Invoke-WebRequest -Uri '$scriptUrl').Content; pause"
    exit
}

# Phase 4: Per-user setup (non-elevated, avoids REGDB_E_CLASSNOTREG for WSL)
if ($phase -eq "4") {
    Write-Output "=== Phase 4: Per-user setup (non-elevated) ==="

    Write-Output "Going to install Azure Artifacts Credential Provider..."
    iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) }"

    Write-Output "Going to install vscode extensions..."
    $vscodeExtensions = @(
        "alefragnani.project-manager",
        "ms-azuretools.vscode-bicep",
        "github.copilot",
        "github.copilot-chat",
        "ms-python.python",
        "ms-vscode-remote.remote-wsl",
        "panxiaoan.themes-falcon-vscode",
        "codeblend.codeblend",
        "mai-engineeringsystems.mai-ai-telemetry"
    )
    foreach ($extension in $vscodeExtensions) {
        Write-Output "Going to install vscode extension: $extension..."
        Q:\Programs\VisualStudioCode\bin\code.cmd --install-extension $extension
    }

    # Overwrite pwsh profile
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force
    }
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/pwsh_profile.ps1" | Select-Object -ExpandProperty Content | Set-Content -Path $PROFILE -Force

    # Overwrite windows terminal settings.json
    $remoteFile = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/windows_terminal.json"
    $localPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $localDir = Split-Path -Parent $localPath
    if (-not (Test-Path $localDir)) {
        New-Item -ItemType Directory -Path $localDir -Force
    }
    Invoke-WebRequest -Uri $remoteFile -OutFile $localPath

    wsl --update
    wsl --install --no-launch Ubuntu-24.04

    # Overwrite .wslconfig (mirrored networking required for chrome-devtools-mcp and cross-OS localhost access)
    $remoteFile = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/.wslconfig"
    $localPath = "$env:USERPROFILE\.wslconfig"
    $localDir = Split-Path -Parent $localPath
    if (-not (Test-Path $localDir)) {
        New-Item -ItemType Directory -Path $localDir -Force
    }
    Invoke-WebRequest -Uri $remoteFile -OutFile $localPath

    Write-Output 'Init script for Ubuntu-24.04: sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/24.04/init.sh?${RANDOM})"'
    Write-Output 'Windows Terminal json config: https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/windows_terminal.json'
    exit
}
