$packages = @(
	"SublimeHQ.SublimeText.4",
	"Microsoft.VisualStudioCode",
	"Microsoft.PowerShell",
	"Tencent.WeChat",
	"MikeFarah.yq",
	"Microsoft.AzureCLI",
 	"Python.Python.3.13",
    "OpenJS.NodeJS.LTS",
	"Microsoft.Git"
)
$locations = @(
	"Sublime",
	"VisualStudioCode",
	"PowerShell",
	"WeChat",
	"Yq",
	"AzureCLI",
	"Python313",
    "NodeJS",
	"Git"
)
for ($i = 0; $i -lt $packages.Length; $i++) {
    $package = $packages[$i]
    $location = "C:\Programs\" + $locations[$i]
    Write-Output "Going to install $package..."
    
    winget install --accept-package-agreements --accept-source-agreements -i -l $location -e $package
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

Write-Output "Going to install Azure Artifacts Credential Provider..."
iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) }"

Write-Output "Going to create new directories..."
New-Item -ItemType Directory -Path "C:\Repos" -Force

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
	"mai-engineeringsystems.mai-ai-telemetry",
	"mai-engineeringsystems.mai-papyrusproxy"
)
foreach ($extension in $vscodeExtensions) {
	Write-Output "Going to install vscode extension: $extension..."
 	C:\Programs\VisualStudioCode\bin\code.cmd --install-extension $extension
}

# Overwrite pwsh profile
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/pwsh_profile.ps1" | Select-Object -ExpandProperty Content | Set-Content -Path $PROFILE -Force

# Overwrite windows terminal settings.json
$remoteFile = "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/windows_terminal.json"
$localPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Invoke-WebRequest -Uri $remoteFile -OutFile $localPath

wsl --update
wsl --install --no-launch Ubuntu-24.04
Write-Output 'Init script for Ubuntu-24.04: sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/24.04/init.sh?${RANDOM})"'
Write-Output 'Windows Terminal json config: https://raw.githubusercontent.com/dianshu/config/refs/heads/master/Windows/windows_terminal.json'
