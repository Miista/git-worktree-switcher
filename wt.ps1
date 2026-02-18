#!/usr/bin/env pwsh
# Switch between git worktrees with speed.
#
# IMPORTANT: This script must be dot-sourced so that Set-Location affects
# your current shell session:
#
#   . .\wt.ps1 <worktree-name>
#
# See README.md for a $PROFILE wrapper that lets you call `wt` directly.

param(
    [Parameter(Position = 0)] [string]$Command,
    [Parameter(Position = 1)] [string]$Arg,
    [switch]$i
)

$VERSION = '0.1.2'
$RELEASE_URL = 'https://github.com/yankeexe/git-worktree-switcher/releases/latest'
$RELEASE_API_URL = 'https://api.github.com/repos/yankeexe/git-worktree-switcher/releases/latest'

function Show-Help {
    Write-Host 'wt lets you switch between your git worktrees with speed.'
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  . .\wt.ps1 <worktree-name>  search for worktree and change to that directory.'
    Write-Host '  . .\wt.ps1 -i               interactively select a worktree using fzf.'
    Write-Host '  . .\wt.ps1 list             list out all the git worktrees.'
    Write-Host '  . .\wt.ps1 update           update to the latest release of worktree switcher.'
    Write-Host '  . .\wt.ps1 version          show the CLI version.'
    Write-Host '  . .\wt.ps1 help             show this help message.'
    Write-Host '  . .\wt.ps1 -                switch to the main (first) worktree.'
    Write-Host '  . .\wt.ps1 current          show the current worktree.'
    Write-Host '  . .\wt.ps1 add <branch>     add a new worktree for <branch> as a sibling folder.'
    Write-Host '  . .\wt.ps1 remove <branch>  remove the worktree matching <branch>.'
}

function Get-WorktreeList {
    git worktree list
}

# Parse `git worktree list --porcelain` output and return an array of
# hashtables with keys: Path, Head, Branch.
function Get-ParsedWorktrees {
    $lines = git worktree list --porcelain
    $worktrees = @()
    $current = $null

    foreach ($line in $lines) {
        if ($line -match '^worktree (.+)$') {
            $current = @{ Path = $Matches[1]; Head = ''; Branch = '' }
        }
        elseif ($line -match '^HEAD (.+)$' -and $current) {
            $current.Head = $Matches[1]
        }
        elseif ($line -match '^branch (.+)$' -and $current) {
            $current.Branch = ($Matches[1] -replace '^refs/heads/', '')
        }
        elseif ($line -eq '' -and $current) {
            $worktrees += $current
            $current = $null
        }
    }
    # Handle missing trailing blank line
    if ($current) { $worktrees += $current }

    return ,$worktrees
}

function Show-CurrentWorktree {
    $worktrees = Get-ParsedWorktrees
    $pwd = (Get-Location).Path
    $match = $worktrees | Where-Object { $pwd -eq $_.Path -or $pwd.StartsWith($_.Path + [System.IO.Path]::DirectorySeparatorChar) } | Select-Object -Last 1
    if ($match) {
        Write-Host "Current worktree: $($match.Path) [$($match.Branch)]"
    }
    else {
        Write-Host "Not inside any known worktree."
    }
}

function Invoke-GotoMain {
    $worktrees = Get-ParsedWorktrees
    if ($worktrees.Count -gt 0) {
        $path = $worktrees[0].Path
        Write-Host "Changing to main worktree at: $path"
        Set-Location $path
    }
}

function Invoke-Switch([string]$Name) {
    $worktrees = Get-ParsedWorktrees
    $match = $worktrees | Where-Object { $_.Path -match [regex]::Escape($Name) -or $_.Branch -match [regex]::Escape($Name) } | Select-Object -First 1
    if ($match) {
        Write-Host "Changing to worktree at: $($match.Path)"
        Set-Location $match.Path
    }
}

function Invoke-InteractiveSwitch {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host 'Error: fzf is not installed for interactive mode'
        Write-Host 'Install from: https://github.com/junegunn/fzf#installation'
        return
    }

    $worktrees = Get-ParsedWorktrees
    $lines = $worktrees | ForEach-Object { "$($_.Path) [$($_.Branch)]" }
    $selected = $lines | fzf --query '' --height=10% --no-multi --exit-0
    if ($selected) {
        $path = ($selected -split ' \[')[0].Trim()
        Write-Host "Changing to worktree at: $path"
        Set-Location $path
    }
}

function Invoke-AddWorktree([string]$Branch) {
    if (-not $Branch) {
        Write-Host 'Usage: wt add <branch-name>'
        return
    }
    $worktrees = Get-ParsedWorktrees
    $mainPath = $worktrees[0].Path
    $parentPath = Split-Path $mainPath -Parent
    $worktreePath = Join-Path $parentPath $Branch

    git rev-parse --verify $Branch 2>$null | Out-Null
    $branchExists = $LASTEXITCODE -eq 0

    Write-Host "Adding worktree '$Branch' at: $worktreePath"
    if ($branchExists) {
        git worktree add $worktreePath $Branch
    } else {
        git worktree add -b $Branch $worktreePath
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Switching to worktree at: $worktreePath"
        Set-Location $worktreePath
    }
}

function Invoke-RemoveWorktree([string]$Name) {
    if (-not $Name) {
        Write-Host 'Usage: wt remove <branch-name>'
        return
    }
    $worktrees = Get-ParsedWorktrees
    $match = $worktrees | Where-Object { $_.Path -match [regex]::Escape($Name) -or $_.Branch -match [regex]::Escape($Name) } | Select-Object -First 1
    if (-not $match) {
        Write-Host "No worktree matching '$Name' found."
        return
    }
    $pwd = (Get-Location).Path
    if ($pwd -eq $match.Path -or $pwd.StartsWith($match.Path + [System.IO.Path]::DirectorySeparatorChar)) {
        Write-Host "Cannot remove the current worktree. Switch to a different worktree first."
        return
    }
    Write-Host "Removing worktree at: $($match.Path)"
    git worktree remove $match.Path
}

function Invoke-Update {
    try {
        $release = Invoke-RestMethod -Uri $RELEASE_API_URL -ErrorAction Stop
        $fetchedVersion = $release.tag_name

        if ($fetchedVersion -eq $VERSION) {
            Write-Host "You have the latest version of worktree switcher!"
            Write-Host "Version: $VERSION"
        }
        else {
            $downloadUrl = $release.assets[0].browser_download_url
            Write-Host "Downloading latest version $fetchedVersion"
            $tmpPath = [System.IO.Path]::GetTempFileName()
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpPath -ErrorAction Stop
            Write-Host "Update downloaded to: $tmpPath"
            Write-Host "Please replace your wt.ps1 with the downloaded file, or visit:"
            Write-Host $RELEASE_URL
        }
    }
    catch {
        Write-Host "Failed to check for updates: $_"
        Write-Host "Visit: $RELEASE_URL"
    }
}

# ---- Command dispatch ----
# Early exit for __noop__ (used by tests to dot-source functions only)
if ($Command -eq '__noop__') { return }

if (-not $Command -and -not $i) {
    Show-Help
    return
}

if ($i) {
    Invoke-InteractiveSwitch
    return
}

switch ($Command) {
    'list'    { Get-WorktreeList }
    'help'    { Show-Help }
    'version' { Write-Host "Version: $VERSION" }
    '-'       { Invoke-GotoMain }
    'current' { Show-CurrentWorktree }
    'add'     { Invoke-AddWorktree $Arg }
    'remove'  { Invoke-RemoveWorktree $Arg }
    'update'  { Invoke-Update }
    default   { Invoke-Switch $Command }
}
