#!/usr/bin/env pwsh
# Switch between git worktrees with speed.
#
# IMPORTANT: This script must be dot-sourced so that Set-Location affects
# your current shell session:
#
#   . .\wt.ps1 <worktree>
#
# See README.md for a $PROFILE wrapper that lets you call `wt` directly.

param(
    [Parameter(Position = 0)] [string]$Command,
    [Parameter(Position = 1)] [string]$Arg,
    [Parameter(Position = 2)] [string]$ForceArg,
    [switch]$i,
    [switch]$h,
    [switch]$help,
    [switch]$force,
    [switch]$yes
)

$isForce = $force.IsPresent -or $ForceArg -eq '--force' -or $ForceArg -eq '-force'
$isYes = $yes.IsPresent -or $ForceArg -eq '--yes' -or $ForceArg -eq '-yes'
$isAll = $Arg -eq '--all' -or $Arg -eq '-all'

$VERSION = '0.1.3'

function Show-Help {
    Write-Host 'wt lets you switch between your git worktrees with speed.'
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  wt                             interactively select a worktree using fzf (default).'
    Write-Host '  wt <worktree>                  search for worktree and change to that directory.'
    Write-Host '  wt -i                          interactively select a worktree using fzf.'
    Write-Host '  wt list                        list out all the git worktrees.'
    Write-Host '  wt version                     show the CLI version.'
    Write-Host '  wt help                        show this help message.'
    Write-Host '  wt -h, --help                  show this help message.'
    Write-Host '  wt -                           switch to the main (first) worktree.'
    Write-Host '  wt current                     show the current worktree.'
    Write-Host '  wt add <branch> [--force]      add a new worktree for <branch> as a sibling folder.'
    Write-Host '  wt create <branch> [--force]   add a new worktree for <branch> and switch to it.'
    Write-Host '  wt rm <worktree> [--force]     remove the worktree matching <worktree>.'
    Write-Host '  wt done [worktree]             safely clean up a worktree after all changes are pushed.'
    Write-Host '  wt check [worktree]            show the status of safety checks for a worktree.'
    Write-Host '  wt check --all                 show safety check status for all non-main worktrees.'
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

function Get-WorktreePath([string]$Branch) {
    $worktrees = Get-ParsedWorktrees
    $mainPath = $worktrees[0].Path
    $remoteUrl = git remote get-url origin 2>$null
    $repoName = if ($remoteUrl) {
        ($remoteUrl -split '[/:\\]' | Where-Object { $_ -ne '' })[-1] -replace '\.git$', ''
    } else {
        Split-Path $mainPath -Leaf
    }

    # Read base path from .wtconfig if present
    $basePath = $null
    $configFile = Join-Path $mainPath '.wtconfig'
    if (Test-Path $configFile) {
        $inWorktreesSection = $false
        foreach ($line in (Get-Content $configFile)) {
            if ($line -match '^\[worktrees\]') {
                $inWorktreesSection = $true
            } elseif ($line -match '^\[') {
                $inWorktreesSection = $false
            } elseif ($inWorktreesSection -and $line -match '^\s*path\s*=\s*(.+)$') {
                $basePath = $Matches[1].Trim()
                break
            }
        }
    }

    if ($basePath) {
        # Resolve relative paths against the main worktree directory
        if (-not [System.IO.Path]::IsPathRooted($basePath)) {
            $basePath = [System.IO.Path]::GetFullPath((Join-Path $mainPath $basePath))
        }
    } else {
        $basePath = Join-Path $HOME '.worktrees'
    }

    return Join-Path $basePath "$repoName\$Branch"
}

function Invoke-AddWorktree([string]$Branch, [bool]$Force) {
    if (-not $Branch) {
        Write-Host 'Usage: wt add <branch-name> [--force]'
        return
    }
    $worktreePath = Get-WorktreePath $Branch
    if (-not $worktreePath) { return }

    Write-Host "Adding worktree '$Branch' at: $worktreePath"
    New-Item -ItemType Directory -Path (Split-Path $worktreePath -Parent) -Force | Out-Null
    $forceArg = if ($Force) { @('--force') } else { @() }
    git rev-parse --verify $Branch 2>$null | Out-Null
    $branchExists = $LASTEXITCODE -eq 0

    # 1. check for remote branch
    git rev-parse --verify "origin/$Branch" 2>$null | Out-Null
    $remoteBranchExists = $LASTEXITCODE -eq 0

    # 1a. both remote and local exist — verify local tracks the correct remote
    if ($remoteBranchExists -and $branchExists) {
        $upstream = git config "branch.$Branch.remote" 2>$null
        $mergeRef = git config "branch.$Branch.merge" 2>$null
        if ($upstream -eq 'origin' -and $mergeRef -eq "refs/heads/$Branch") {
            Write-Host "Set up to track origin/$Branch"
            git worktree add @forceArg $worktreePath $Branch --quiet
        } else {
            # local branch tracks a different remote or has no upstream — inform the user
            Write-Host "Local branch '$Branch' exists but does not track 'origin/$Branch'."
            if ($upstream -and $mergeRef) {
                $trackingBranch = $mergeRef -replace '^refs/heads/', ''
                Write-Host "It currently tracks '$upstream/$trackingBranch'."
            } else {
                Write-Host "It has no upstream tracking branch configured."
            }
            Write-Host "Fix with: git branch --set-upstream-to=origin/$Branch $Branch"
            return
        }
    # 1b. only remote exists — create local tracking branch
    } elseif ($remoteBranchExists) {
        Write-Host "Creating local branch tracking origin/$Branch"
        git worktree add @forceArg --track -b $Branch $worktreePath "origin/$Branch" --quiet
    # 1c. only local exists — use it directly
    } elseif ($branchExists) {
        Write-Host "Using existing local branch '$Branch'"
        git worktree add @forceArg $worktreePath $Branch --quiet
    } else {
        # 2. fetch and check for remote branch again
        Write-Host "Branch '$Branch' not found locally or on origin, fetching..."
        git fetch --quiet
        git rev-parse --verify "origin/$Branch" 2>$null | Out-Null
        $remoteBranchExists = $LASTEXITCODE -eq 0

        if ($remoteBranchExists) {
            Write-Host "Found origin/$Branch after fetch, creating local tracking branch"
            git worktree add @forceArg --track -b $Branch $worktreePath "origin/$Branch" --quiet
        # 3. create new local branch
        } else {
            Write-Host "Creating new local branch '$Branch'"
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


function Invoke-DoneWorktree([string]$Name, [bool]$Yes) {
    $worktrees = Get-ParsedWorktrees
    $pwd = (Get-Location).Path.Replace('\', '/')

    if (-not $Name) {
        # no argument — use current worktree
        $match = $worktrees | Where-Object {
            $p = $_.Path.Replace('\', '/')
            $pwd -eq $p -or $pwd.StartsWith($p + '/')
        } | Select-Object -Last 1
        if (-not $match) {
            Write-Host "Not inside any known worktree."
            return
        }
        $Name = $match.Branch
        # check we're not in the main worktree
        $mainPath = $worktrees[0].Path.Replace('\', '/')
        if ($pwd -eq $mainPath -or $pwd.StartsWith($mainPath + '/')) {
            Write-Host "Cannot clean up the main worktree."
            return
        }
        # switch to main worktree before cleaning up
        Write-Host "Switching to main worktree at: $($worktrees[0].Path)"
        Set-Location $worktrees[0].Path
    } else {
        $match = $worktrees | Where-Object { $_.Path -match [regex]::Escape($Name) -or $_.Branch -match [regex]::Escape($Name) } | Select-Object -First 1
        if (-not $match) {
            Write-Host "No worktree matching '$Name' found."
            return
        }
        $matchPath = $match.Path.Replace('\', '/')
        if ($pwd -eq $matchPath -or $pwd.StartsWith($matchPath + '/')) {
            # in the target worktree — switch to main first
            Write-Host "Switching to main worktree at: $($worktrees[0].Path)"
            Set-Location $worktrees[0].Path
        }
    }
    if (-not $Yes) {
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
    }
    # all clean — remove worktree and delete branch
    Write-Host "Removing worktree at: $($match.Path)"
    if ($Yes) {
        git worktree remove --force $match.Path
    } else {
        git worktree remove $match.Path
    }
    if ($LASTEXITCODE -eq 0) {
        Invoke-RemoveLeftoverWorktreeDirectory $match.Path
    }
    if ($LASTEXITCODE -eq 0 -and $match.Branch) {
        Write-Host "Deleting branch: $($match.Branch)"
        if ($Yes) {
            git branch -D $match.Branch
        } else {
            git branch -d $match.Branch
        }
    }
}

function Invoke-CheckWorktreeOne($worktree) {
    $name = $worktree.Branch
    $path = $worktree.Path
    $allOk = $true

    # Check 1: uncommitted changes
    $status = git -C $path status --porcelain
    if ($status) {
        Write-Host "  ✗ Has uncommitted changes" -ForegroundColor Red
        $allOk = $false
    } else {
        Write-Host "  ✓ No uncommitted changes" -ForegroundColor Green
    }

    # Check 2: upstream tracking
    $upstream = git -C $path rev-parse --abbrev-ref '@{upstream}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        Write-Host "  ✗ No upstream tracking branch" -ForegroundColor Red
        $allOk = $false
    } else {
        Write-Host "  ✓ Tracking $upstream" -ForegroundColor Green

        # Check 3: unpushed commits (only if upstream exists)
        $unpushed = git -C $path log "$upstream..HEAD" --oneline
        if ($unpushed) {
            Write-Host "  ✗ Has unpushed commits" -ForegroundColor Red
            $allOk = $false
        } else {
            Write-Host "  ✓ No unpushed commits" -ForegroundColor Green
        }
    }

    Write-Host ''
    if ($allOk) {
        Write-Host "  ✓ Ready for 'wt done $name'." -ForegroundColor Green
    } else {
        Write-Host "  Some checks failed. Resolve them before running 'wt done $name'." -ForegroundColor Red
    }
    return $allOk
}

function Invoke-CheckWorktree([string]$Name, [bool]$All) {
    $worktrees = Get-ParsedWorktrees
    $pwd = (Get-Location).Path.Replace('\', '/')

    if ($All) {
        $nonMain = $worktrees | Select-Object -Skip 1
        if ($nonMain.Count -eq 0) {
            Write-Host "No non-main worktrees found."
            return
        }
        foreach ($wt in $nonMain) {
            Write-Host "Checking worktree '$($wt.Branch)' at: $($wt.Path)"
            Write-Host ''
            $null = Invoke-CheckWorktreeOne $wt
            Write-Host ''
        }
        return
    }

    if (-not $Name) {
        $match = $worktrees | Where-Object {
            $p = $_.Path.Replace('\', '/')
            $pwd -eq $p -or $pwd.StartsWith($p + '/')
        } | Select-Object -Last 1
        if (-not $match) {
            Write-Host "Not inside any known worktree."
            return
        }
        $Name = $match.Branch
    } else {
        $match = $worktrees | Where-Object { $_.Path -match [regex]::Escape($Name) -or $_.Branch -match [regex]::Escape($Name) } | Select-Object -First 1
        if (-not $match) {
            Write-Host "No worktree matching '$Name' found."
            return
        }
    }

    Write-Host "Checking worktree '$Name' at: $($match.Path)"
    Write-Host ''
    $allOk = Invoke-CheckWorktreeOne $match
    if (-not $allOk) { return }
}

function Invoke-RemoveLeftoverWorktreeDirectory([string]$Path) {
    if (Test-Path $Path) {
        Write-Host "Removing leftover directory: $Path"
        Remove-Item -Recurse -Force $Path
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
    if ($LASTEXITCODE -eq 0) {
        Invoke-RemoveLeftoverWorktreeDirectory $match.Path
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
    'done'    { Invoke-DoneWorktree $Arg $isYes }
    'check'   { Invoke-CheckWorktree $Arg $isAll }
    default   { Invoke-Switch $Command }
}
