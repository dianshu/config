# Windows Claude Code Init Script
# One-time setup: installs Claude Code + agency, configures proxy and MCP servers.
# Usage:
#   Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/main/Windows/init-claude.ps1").Content
#   Or: .\init-claude.ps1

$ErrorActionPreference = "Stop"

# --- Step 1: Install Prerequisites ---

Write-Output "=== Installing Node.js LTS ==="
winget install --accept-package-agreements --accept-source-agreements -e OpenJS.NodeJS.LTS

# Refresh PATH so npm/npx are available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Output "=== Installing Claude Code ==="
npm install -g @anthropic-ai/claude-code

Write-Output "=== Installing Agency ==="
$installScript = (Invoke-WebRequest -Uri "https://aka.ms/InstallTool.ps1" -UseBasicParsing).Content
Invoke-Expression "& { $installScript } agency"
$env:Path = "$HOME\.config\agency\CurrentVersion;$env:Path"

# --- Step 2: Write ~/.claude/settings.json ---

$claudeDir = Join-Path $HOME ".claude"
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$settingsJson = @'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:29427",
    "ANTHROPIC_AUTH_TOKEN": "your-anthropic-auth-token",
    "CLAUDE_CODE_SKIP_AUTH_LOGIN": "true",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_NO_FLICKER": "1"
  },
  "permissions": {
    "allow": [
      "Bash",
      "WebFetch",
      "WebSearch",
      "mcp__mail",
      "mcp__s360",
      "mcp__word",
      "mcp__sharepoint",
      "mcp__workiq",
      "mcp__ado"
    ]
  }
}
'@
$settingsPath = Join-Path $claudeDir "settings.json"
Set-Content -Path $settingsPath -Value $settingsJson -Force
Write-Output "Wrote $settingsPath"

# --- Step 3: Write ~/.claude.json (MCP servers) ---

$claudeJsonPath = Join-Path $HOME ".claude.json"
$mcpJson = @'
{
  "mcpServers": {
    "mail": { "type": "http", "url": "http://localhost:30970" },
    "s360": { "type": "http", "url": "http://localhost:30971" },
    "word": { "type": "http", "url": "http://localhost:30972" },
    "sharepoint": { "type": "http", "url": "http://localhost:30973" },
    "workiq": { "type": "http", "url": "http://localhost:30974" },
    "ado": { "type": "http", "url": "http://localhost:30975" }
  }
}
'@
Set-Content -Path $claudeJsonPath -Value $mcpJson -Force
Write-Output "Wrote $claudeJsonPath"

# --- Step 4: Start Agency MCP Servers (Background) ---

$mcpServices = @(
    @{ Name = "mail";       Service = "mail";        Port = 30970 },
    @{ Name = "s360";       Service = "s360-breeze";  Port = 30971 },
    @{ Name = "word";       Service = "word";         Port = 30972 },
    @{ Name = "sharepoint"; Service = "sharepoint";   Port = 30973 },
    @{ Name = "workiq";     Service = "workiq";       Port = 30974 },
    @{ Name = "ado";        Service = "ado";          Port = 30975; ExtraArgs = @("--organization", $env:ADO_ORGANIZATION, "--toolsets", "all") }
)

foreach ($svc in $mcpServices) {
    $port = $svc.Port
    $name = $svc.Name
    $service = $svc.Service

    # Kill any process on the port
    $existing = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | ForEach-Object {
            Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
    }

    $args = @("mcp", $service, "--transport", "http", "--port", $port)
    if ($svc.ExtraArgs) { $args += $svc.ExtraArgs }
    Start-Process -WindowStyle Hidden -FilePath "agency" -ArgumentList $args
    Write-Output "Agency MCP '$name' started (port $port)"
}

# --- Step 5: Start copilot-api (Foreground, Blocking) ---

Write-Output ""
Write-Output "============================================"
Write-Output " copilot-api starting on port 29427"
Write-Output " Open a new terminal and run: claude"
Write-Output "============================================"
Write-Output ""

npx --yes @dianshuv/copilot-api@latest start -p 29427 -a enterprise