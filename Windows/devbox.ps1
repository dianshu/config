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
	"GitHub.cli",
 	"Microsoft.Azure.CosmosEmulator",
  	"Microsoft Azure PowerShell - April 2018"
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
	"NetEase.CloudMusic",
	"MikeFarah.yq",
	"Docker.DockerDesktop",
	"Microsoft.AzureCLI",
	"Microsoft.NuGet",
  	"ByteDance.Feishu",
   	"voidtools.Everything",
	"Ollama.Ollama",
 	"Python.Python.3.13"
)
$locations = @(
	"Sublime",
	"VisualStudioCode",
	"PowerShell",
	"WeChat",
	"NetEastCloudMusic",
	"Yq",
	"DockerDesktop",
	"AzureCLI",
	"NuGet",
 	"Feishu",
  	"Everything",
    "Ollama",
	"Python313"
)
for ($i = 0; $i -lt $packages.Length; $i++) {
    $package = $packages[$i]
    $location = "Q:\Programs\" + $locations[$i]
    Write-Output "Going to install $package..."
    
    winget install --accept-package-agreements --accept-source-agreements -i -l $location -e $package
}

Write-Ouput "Going to install Azure Powershell..."
Install-Module -Name Az -Repository PSGallery -Force

Write-Output "Going to install Azure Artifacts Credential Provider..."
iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) } -InstallNet8"

Write-Ouput "Going to delete redundant directories and files..."
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
for ($extension in $vscodeExtensions) {
	Write-Output "Going to install vscode extension: $extension..."
 	code --install-extension $extension
}

wsl --update
wsl --install --no-launch Ubuntu-24.04
Write-Output 'Init script for Ubuntu-24.04: sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dianshu/config/HEAD/Ubuntu/24.04/init.sh?${RANDOM})"'
Write-Output 'Windows Terminal json config: https://raw.githubusercontent.com/dianshu/config/refs/heads/master/Windows/windows_terminal.json'
