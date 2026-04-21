# Shared test helpers for wt.ps1 Pester tests.
# Provides functions to create and tear down temporary git repos with worktrees.

function New-TestRepo {
    <#
    .SYNOPSIS
    Creates a temporary bare repo + cloned main worktree with one initial commit.
    Returns @{ Root; MainPath; BarePath; RepoName }.
    #>
    param(
        [string]$RepoName = 'test-repo'
    )
    $root = Join-Path $env:TEMP "wt-tests-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $barePath = Join-Path $root "$RepoName.git"
    $mainPath = Join-Path $root 'main'

    New-Item -ItemType Directory -Path $root -Force | Out-Null

    # Create bare repo
    git init --bare $barePath --quiet 2>$null

    # Clone it as the main worktree
    git clone $barePath $mainPath --quiet 2>$null

    # Make an initial commit so the repo isn't empty
    Push-Location $mainPath
    try {
        git config user.email "test@test.com"
        git config user.name "Test"
        New-Item -ItemType File -Path (Join-Path $mainPath '.gitkeep') -Force | Out-Null
        git add .gitkeep
        git commit -m "initial commit" --quiet
        git push --quiet 2>$null
    }
    finally {
        Pop-Location
    }

    return @{
        Root      = $root
        MainPath  = $mainPath
        BarePath  = $barePath
        RepoName  = $RepoName
    }
}

function New-TestWorktreeRepo {
    <#
    .SYNOPSIS
    Creates a test repo and adds worktrees for the given branch names.
    Returns the same hash as New-TestRepo plus a Worktrees hashtable mapping branch names to paths.
    #>
    param(
        [string[]]$Branches = @()
    )

    $repo = New-TestRepo
    $worktrees = @{}

    Push-Location $repo.MainPath
    try {
        foreach ($branch in $Branches) {
            $wtPath = Join-Path (Split-Path $repo.MainPath -Parent) $branch
            git worktree add -b $branch $wtPath --quiet 2>$null
            $worktrees[$branch] = $wtPath
        }
    }
    finally {
        Pop-Location
    }

    $repo.Worktrees = $worktrees
    return $repo
}

function Remove-TestRepo {
    <#
    .SYNOPSIS
    Cleans up a test repo created by New-TestRepo or New-TestWorktreeRepo.
    #>
    param(
        [string]$Root
    )

    if (-not $Root -or -not (Test-Path $Root)) { return }

    # Make sure we're not inside the directory we're about to delete
    Set-Location $env:TEMP

    # Remove any git worktrees first to release locks
    $mainPath = Join-Path $Root 'main'
    if (Test-Path $mainPath) {
        Push-Location $mainPath
        try {
            $list = git worktree list --porcelain 2>$null
            # just prune to clean up stale entries
            git worktree prune 2>$null
        }
        finally {
            Pop-Location
        }
    }

    # Remove .worktrees sibling directory if it was created by tests
    $worktreesDir = Join-Path (Split-Path $Root -Parent) '.worktrees'
    if (Test-Path $worktreesDir) {
        Remove-Item -Recurse -Force $worktreesDir -ErrorAction SilentlyContinue
    }

    # Force remove the whole tree
    Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
}
