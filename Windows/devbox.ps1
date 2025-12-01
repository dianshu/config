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
	"Microsoft.PowerShell",
	"Tencent.WeChat",
	"MikeFarah.yq",
	"Microsoft.AzureCLI",
 	"Python.Python.3.14",
   	"OpenJS.NodeJS.LTS"
)
$locations = @(
	"Sublime",
	"VisualStudioCode",
	"PowerShell",
	"WeChat",
	"Yq",
	"AzureCLI",
	"Python314",
  	"NodeJS"
)
for ($i = 0; $i -lt $packages.Length; $i++) {
    $package = $packages[$i]
    $location = "Q:\Programs\" + $locations[$i]
    Write-Output "Going to install $package..."
    
    winget install --accept-package-agreements --accept-source-agreements -i -l $location -e $package
}

Write-Output "Going to install Azure Artifacts Credential Provider..."
iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) } -InstallNet8"

Write-Output "Going to delete redundant directories and files..."
$needToDeletePaths = @(
	"Q:\Edge",
 	"Q:\src",
  	"Q:\.tools\QuickBuild",
   	"C:\CommonTools\*"
)
foreach ($path in $needToDeletePaths) {
	Write-Output "Going to delete $path..."
 	Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Going to create new directories..."
New-Item -ItemType Directory -Path "Q:\Repos" -Force

Write-Output "Going to install vscode extensions..."
$vscodeExtensions = @(
	"alefragnani.project-manager",
 	"ms-azuretools.vscode-bicep",
  	"github.copilot",
   	"github.copilot-chat",
	"ms-python.python",
	"ms-vscode-remote.remote-wsl",
	"panxiaoan.themes-falcon-vscode"
)
foreach ($extension in $vscodeExtensions) {
	Write-Output "Going to install vscode extension: $extension..."
 	Q:\Programs\VisualStudioCode\bin\code.cmd --install-extension $extension
}

# Overwrite pwsh profile
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/refs/heads/master/Windows/pwsh_profile.ps1" | Select-Object -ExpandProperty Content | Set-Content -Path $PROFILE -Force

# Overwrite windows terminal settings.json
$remoteFIle = "https://raw.githubusercontent.com/dianshu/config/refs/heads/master/Windows/windows_terminal.json"
$localPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Invoke-WebRequest -Uri $remoteUrl -OutFile $localPath -Force

wsl --update
wsl --install --no-launch Ubuntu-24.04
Write-Output 'Init script for Ubuntu-24.04: sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/24.04/init.sh?${RANDOM})"'
Write-Output 'Windows Terminal json config: https://raw.githubusercontent.com/dianshu/config/refs/heads/master/Windows/windows_terminal.json'
