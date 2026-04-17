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
    [Parameter(Position = 2)] [string]$ForceArg,
    [switch]$i,
    [switch]$h,
    [switch]$help,
    [switch]$force
)

$isForce = $force.IsPresent -or $ForceArg -eq '--force' -or $ForceArg -eq '-force'

$VERSION = '0.1.3'

function Show-Help {
    Write-Host 'wt lets you switch between your git worktrees with speed.'
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  wt                  interactively select a worktree using fzf (default).'
    Write-Host '  wt <worktree-name>  search for worktree and change to that directory.'
    Write-Host '  wt -i               interactively select a worktree using fzf.'
    Write-Host '  wt list             list out all the git worktrees.'
    Write-Host '  wt version          show the CLI version.'
    Write-Host '  wt help             show this help message.'
    Write-Host '  wt -h, --help       show this help message.'
    Write-Host '  wt -                switch to the main (first) worktree.'
    Write-Host '  wt current          show the current worktree.'
    Write-Host '  wt add <branch> [--force]     add a new worktree for <branch> as a sibling folder.'
    Write-Host '  wt create <branch> [--force]  add a new worktree for <branch> and switch to it.'
    Write-Host '  wt rm <branch> [--force]      remove the worktree matching <branch>.'
    Write-Host '  wt done <branch>              safely clean up a worktree after all changes are pushed.'
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
            $current = @{ Path = $Matches[1].Trim(); Head = ''; Branch = '' }
        }
        elseif ($line -match '^HEAD (.+)$' -and $current) {
            $current.Head = $Matches[1]
        }
        elseif ($line -match '^branch (.+)$' -and $current) {
            $current.Branch = ($Matches[1].Trim() -replace '^refs/heads/', '')
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
    $pwd = (Get-Location).Path.Replace('\', '/')
    $match = $worktrees | Where-Object { $p = $_.Path.Replace('\', '/'); $pwd -eq $p -or $pwd.StartsWith($p + '/') } | Select-Object -Last 1
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

function Invoke-AddWorktree([string]$Branch, [bool]$Force) {
    if (-not $Branch) {
        Write-Host 'Usage: wt add <branch-name> [--force]'
        return
    }
    $worktrees = Get-ParsedWorktrees
    $mainPath = $worktrees[0].Path
    $parentPath = Split-Path $mainPath -Parent
    $worktreePath = Join-Path $parentPath $Branch

    Write-Host "Adding worktree '$Branch' at: $worktreePath"
    $forceArg = if ($Force) { @('--force') } else { @() }
    git rev-parse --verify $Branch 2>$null | Out-Null
    $branchExists = $LASTEXITCODE -eq 0

    # 1. check for remote branch
    git rev-parse --verify "origin/$Branch" 2>$null | Out-Null
    $remoteBranchExists = $LASTEXITCODE -eq 0

    if ($remoteBranchExists -and $branchExists) {
        git worktree add @forceArg $worktreePath $Branch --quiet
    } elseif ($remoteBranchExists) {
        git worktree add @forceArg --track -b $Branch $worktreePath "origin/$Branch" --quiet
    } elseif ($branchExists) {
        git worktree add @forceArg $worktreePath $Branch --quiet
    } else {
        # 2. fetch and check for remote branch again
        git fetch --quiet
        git rev-parse --verify "origin/$Branch" 2>$null | Out-Null
        $remoteBranchExists = $LASTEXITCODE -eq 0

        if ($remoteBranchExists) {
            git worktree add @forceArg --track -b $Branch $worktreePath "origin/$Branch" --quiet
        # 3. create new local branch
        } else {
            git worktree add @forceArg -b $Branch $worktreePath --quiet
        }
    }
}

function Invoke-CreateWorktree([string]$Branch, [bool]$Force) {
    if (-not $Branch) {
        Write-Host 'Usage: wt create <branch-name> [--force]'
        return
    }
    Invoke-AddWorktree $Branch $Force
    if ($LASTEXITCODE -eq 0) {
        Invoke-Switch $Branch
    }
}


function Invoke-DoneWorktree([string]$Name) {
    if (-not $Name) {
        Write-Host 'Usage: wt done <branch-name>'
        return
    }
    $worktrees = Get-ParsedWorktrees
    $match = $worktrees | Where-Object { $_.Path -match [regex]::Escape($Name) -or $_.Branch -match [regex]::Escape($Name) } | Select-Object -First 1
    if (-not $match) {
        Write-Host "No worktree matching '$Name' found."
        return
    }
    $pwd = (Get-Location).Path.Replace('\', '/')
    $matchPath = $match.Path.Replace('\', '/')
    if ($pwd -eq $matchPath -or $pwd.StartsWith($matchPath + '/')) {
        Write-Host "Cannot clean up the current worktree. Switch to a different worktree first."
        return
    }
    # check for uncommitted changes
    $status = git -C $match.Path status --porcelain
    if ($status) {
        Write-Host "Worktree '$Name' has uncommitted changes:"
        git -C $match.Path status --short
        Write-Host ""
        Write-Host "Commit or stash your changes first, then run 'wt done $Name' again."
        return
    }
    # check for unpushed commits
    $upstream = git -C $match.Path rev-parse --abbrev-ref "@{upstream}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstream) {
        $unpushed = git -C $match.Path log "$upstream..HEAD" --oneline
        if ($unpushed) {
            Write-Host "Worktree '$Name' has unpushed commits:"
            Write-Host $unpushed
            Write-Host ""
            Write-Host "Push your changes first with 'git push', then run 'wt done $Name' again."
            return
        }
    } else {
        # no upstream set
        $branchName = git -C $match.Path rev-parse --abbrev-ref HEAD 2>$null
        Write-Host "Branch '$branchName' has no upstream tracking branch."
        Write-Host "Push your branch first with 'git push -u origin $branchName', then run 'wt done $Name' again."
        return
    }
    # all clean — remove worktree and delete branch
    Write-Host "Removing worktree at: $($match.Path)"
    git worktree remove $match.Path
    if ($LASTEXITCODE -eq 0 -and $match.Branch) {
        Write-Host "Deleting branch: $($match.Branch)"
        git branch -d $match.Branch
    }
}

function Invoke-RmWorktree([string]$Name, [bool]$Force) {
    if (-not $Name) {
        Write-Host 'Usage: wt rm <branch-name> [--force]'
        return
    }
    $worktrees = Get-ParsedWorktrees
    $match = $worktrees | Where-Object { $_.Path -match [regex]::Escape($Name) -or $_.Branch -match [regex]::Escape($Name) } | Select-Object -First 1
    if (-not $match) {
        Write-Host "No worktree matching '$Name' found."
        return
    }
    $pwd = (Get-Location).Path.Replace('\', '/')
    $matchPath = $match.Path.Replace('\', '/')
    if ($pwd -eq $matchPath -or $pwd.StartsWith($matchPath + '/')) {
        Write-Host "Cannot remove the current worktree. Switch to a different worktree first."
        return
    }
    Write-Host "Removing worktree at: $($match.Path)"
    if ($Force) {
        git worktree remove --force $match.Path
    } else {
        git worktree remove $match.Path
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
    $selected = $lines | fzf --height=10% --no-multi --exit-0
    if ($selected) {
        $path = ($selected -split ' \[')[0].Trim()
        Write-Host "Changing to worktree at: $path"
        Set-Location $path
    }
}

# ---- Command dispatch ----
if ($h -or $help) {
    Show-Help
    return
}

if (-not $Command -and -not $i) {
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        Invoke-InteractiveSwitch
    } else {
        Show-Help
    }
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
    'add'     { Invoke-AddWorktree $Arg $isForce }
    'create'  { Invoke-CreateWorktree $Arg $isForce }
    'rm'      { Invoke-RmWorktree $Arg $isForce }
    'done'    { Invoke-DoneWorktree $Arg }
    default   { Invoke-Switch $Command }
}
