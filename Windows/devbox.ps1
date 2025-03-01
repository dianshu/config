$needToUninstallPackages = @(
	"Microsoft.VisualStudioCode",
	"Anaconda.Anaconda3",
  	"Notepad++.Notepad++",
  	"Oracle.JavaRuntimeEnvironment",
  	"Microsoft.Edge.Beta",
   	"Microsoft.Office",
    "OpenJS.NodeJS.LTS",
	"GoLang.Go",
 	"Microsoft.AzureCLI"
)
foreach ($package in $needToUninstallPackages) {
	Write-Output "Going to uninstall $package..."
	winget uninstall -i -e $package
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
  	"ByteDance.Feishu"
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
 	"Feishu"
)
for ($i = 0; $i -lt $packages.Length; $i++) {
    $package = $packages[$i]
    $location = "Q:\Programs\" + $locations[$i]
    Write-Output "Going to install $package..."
    
    winget install --accept-package-agreements --accept-source-agreements -i -l $location -e $package
}

Write-Output "Going to install Azure Artifacts Credential Provider..."
iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) } -InstallNet8"

wsl --update
wsl --install Ubuntu-24.04
