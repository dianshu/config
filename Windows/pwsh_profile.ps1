function Prompt {
    $currentTime = Get-Date -Format "HH:mm:ss"
    Write-Host "$currentTime" -NoNewline -ForegroundColor Green
    Write-Host " | " -NoNewline -ForegroundColor Gray
    
    # Check if current directory is inside a Git repository
    if (git status) {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($branch) {
            Write-Host "$branch" -NoNewline -ForegroundColor Red
            Write-Host " | " -NoNewline -ForegroundColor Gray
        }
    }

    $currentPath = Get-Location
    Write-Host "$currentPath" -NoNewline -ForegroundColor Cyan

    Write-Host ""
    return "> "
}

# Set up history search with arrow keys
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
