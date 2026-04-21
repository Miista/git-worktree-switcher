#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . "$PSScriptRoot\TestHelper.ps1"
    $script:ScriptPath = "$PSScriptRoot\..\wt.ps1"
}

Describe 'Show-Help' {
    BeforeAll {
        $null = (. $script:ScriptPath help) 6>&1
    }

    It 'prints usage information' {
        $output = (Show-Help) 6>&1 | Out-String
        $output | Should -Match 'Usage:'
    }

    It 'mentions available commands' {
        $output = (Show-Help) 6>&1
        "$output" | Should -Match 'wt list'
        "$output" | Should -Match 'wt add'
        "$output" | Should -Match 'wt rm'
        "$output" | Should -Match 'wt done'
        "$output" | Should -Match 'wt check'
    }
}

Describe 'Get-WorktreeList' {
    BeforeAll {
        $script:repo = New-TestWorktreeRepo -Branches @('feature-a')
        Set-Location $script:repo.MainPath
        $null = (. $script:ScriptPath help) 6>&1
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'returns output containing the main worktree path' {
        $output = Get-WorktreeList | Out-String
        $output | Should -Match ([regex]::Escape($script:repo.MainPath.Replace('\', '/')))
    }

    It 'shows all worktrees' {
        $output = Get-WorktreeList | Out-String
        $output | Should -Match 'feature-a'
    }
}

Describe 'Get-ParsedWorktrees' {
    BeforeAll {
        $script:repo = New-TestWorktreeRepo -Branches @('feature-a', 'feature-b')
        Set-Location $script:repo.MainPath
        $null = (. $script:ScriptPath help) 6>&1
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'returns an array with the correct count' {
        $result = Get-ParsedWorktrees
        $result.Count | Should -Be 3
    }

    It 'parses Path, Head, and Branch for each entry' {
        $result = Get-ParsedWorktrees
        foreach ($wt in $result) {
            $wt.Path | Should -Not -BeNullOrEmpty
            $wt.Head | Should -Not -BeNullOrEmpty
            $wt.Branch | Should -Not -BeNullOrEmpty
        }
    }

    It 'strips refs/heads/ from branch names' {
        $result = Get-ParsedWorktrees
        foreach ($wt in $result) {
            $wt.Branch | Should -Not -Match '^refs/heads/'
        }
    }

    It 'parses the main worktree first' {
        $result = Get-ParsedWorktrees
        $result[0].Path.Replace('/', '\') | Should -Be $script:repo.MainPath
    }
}

Describe 'Show-CurrentWorktree' {
    BeforeAll {
        $script:repo = New-TestWorktreeRepo -Branches @('feature-a')
        Set-Location $script:repo.MainPath
        $null = (. $script:ScriptPath help) 6>&1
    }

    BeforeEach {
        $script:savedLocation = Get-Location
    }

    AfterEach {
        Set-Location $script:savedLocation
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'shows current worktree when inside one' {
        Set-Location $script:repo.Worktrees['feature-a']
        $output = (Show-CurrentWorktree) 6>&1 | Out-String
        $output | Should -Match 'feature-a'
        $output | Should -Match 'Current worktree:'
    }

    It 'shows not inside message when outside any worktree' {
        Set-Location $env:TEMP
        $output = (Show-CurrentWorktree) 6>&1 | Out-String
        $output | Should -Match 'Not inside any known worktree'
    }
}

Describe 'Invoke-GotoMain' {
    BeforeAll {
        $script:repo = New-TestWorktreeRepo -Branches @('feature-a')
        Set-Location $script:repo.MainPath
        $null = (. $script:ScriptPath help) 6>&1
    }

    BeforeEach {
        $script:savedLocation = Get-Location
    }

    AfterEach {
        Set-Location $script:savedLocation
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'changes directory to the main worktree from a secondary worktree' {
        Set-Location $script:repo.Worktrees['feature-a']
        $null = (Invoke-GotoMain) 6>&1
        (Get-Location).Path | Should -Be $script:repo.MainPath
    }
}

Describe 'Invoke-Switch' {
    BeforeAll {
        $script:repo = New-TestWorktreeRepo -Branches @('feature-a', 'feature-b')
        Set-Location $script:repo.MainPath
        $null = (. $script:ScriptPath help) 6>&1
    }

    BeforeEach {
        $script:savedLocation = Get-Location
        Set-Location $script:repo.MainPath
    }

    AfterEach {
        Set-Location $script:savedLocation
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'switches to a worktree matching by branch name' {
        $null = (Invoke-Switch 'feature-a') 6>&1
        (Get-Location).Path | Should -BeLike '*feature-a*'
    }

    It 'switches to a different worktree' {
        $null = (Invoke-Switch 'feature-b') 6>&1
        (Get-Location).Path | Should -BeLike '*feature-b*'
    }

    It 'stays in place when no match found' {
        $before = (Get-Location).Path
        $null = (Invoke-Switch 'nonexistent') 6>&1
        (Get-Location).Path | Should -Be $before
    }
}

Describe 'Get-WorktreePath' {
    Context 'no .wtconfig - uses ~/.worktrees/<repo>/<branch> default' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            # Remove the .wtconfig written by New-TestRepo so we test the default behaviour
            Remove-Item (Join-Path $script:repo.MainPath '.wtconfig') -ErrorAction SilentlyContinue
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'falls back to ~/.worktrees/<repo>/<branch>' {
            $result = Get-WorktreePath 'feature-x'
            $expected = Join-Path $HOME ".worktrees\my-repo\feature-x"
            $result | Should -Be $expected
        }

        It 'uses the repo name from the remote URL' {
            $result = Get-WorktreePath 'some-branch'
            $result | Should -Match 'my-repo'
        }
    }

    Context '.wtconfig with absolute path' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            $script:customRoot = Join-Path $env:TEMP "wt-custom-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            $configPath = Join-Path $script:repo.MainPath '.wtconfig'
            Set-Content $configPath "[worktrees]`n`tpath = $($script:customRoot.Replace('\', '/'))"
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-Item -Recurse -Force $script:customRoot -ErrorAction SilentlyContinue
            Remove-TestRepo $script:repo.Root
        }

        It 'uses the absolute path from .wtconfig' {
            $result = Get-WorktreePath 'feature-x'
            $expected = Join-Path $script:customRoot 'my-repo\feature-x'
            $result | Should -Be $expected
        }
    }

    Context '.wtconfig with relative path' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            $configPath = Join-Path $script:repo.MainPath '.wtconfig'
            Set-Content $configPath "[worktrees]`n`tpath = ../.wt"
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'resolves relative path from the main worktree directory' {
            $result = Get-WorktreePath 'feature-x'
            $expected = Join-Path $script:repo.Root ".wt\my-repo\feature-x"
            $result | Should -Be $expected
        }
    }
}

Describe 'Invoke-AddWorktree' {
    Context 'no branch argument' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'prints usage when no branch given' {
            $output = (Invoke-AddWorktree '' $false) 6>&1 | Out-String
            $output | Should -Match 'Usage:'
        }
    }

    Context 'branch does not exist anywhere' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'creates a new branch and worktree' {
            $null = (Invoke-AddWorktree 'brand-new' $false) 6>&1
            $wtPath = Join-Path $script:repo.Root "my-repo\brand-new"
            Test-Path $wtPath | Should -BeTrue
        }
    }

    Context 'branch exists only locally' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            # Create a local branch but don't push it
            git branch local-only 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'creates a worktree for the local branch' {
            $null = (Invoke-AddWorktree 'local-only' $false) 6>&1
            $wtPath = Join-Path $script:repo.Root "my-repo\local-only"
            Test-Path $wtPath | Should -BeTrue
        }
    }

    Context 'branch exists only on remote' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            # Create a branch, push it, then delete locally
            git checkout -b remote-only --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'remote-file.txt') -Force | Out-Null
            git add remote-file.txt
            git commit -m "remote commit" --quiet
            git push -u origin remote-only --quiet 2>$null
            git checkout master --quiet 2>$null
            git branch -D remote-only 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'creates a tracking worktree from remote' {
            $null = (Invoke-AddWorktree 'remote-only' $false) 6>&1
            $wtPath = Join-Path $script:repo.Root "my-repo\remote-only"
            Test-Path $wtPath | Should -BeTrue
            # Verify it tracks the remote
            $upstream = git -C $wtPath rev-parse --abbrev-ref '@{upstream}' 2>$null
            $upstream | Should -Be 'origin/remote-only'
        }
    }

    Context 'branch exists both locally and remotely with correct tracking' {
        BeforeAll {
            $script:repo = New-TestRepo -RepoName 'my-repo'
            Set-Location $script:repo.MainPath
            git checkout -b tracked-branch --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'tracked.txt') -Force | Out-Null
            git add tracked.txt
            git commit -m "tracked commit" --quiet
            git push -u origin tracked-branch --quiet 2>$null
            git checkout master --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'creates the worktree' {
            $null = (Invoke-AddWorktree 'tracked-branch' $false) 6>&1
            $wtPath = Join-Path $script:repo.Root "my-repo\tracked-branch"
            Test-Path $wtPath | Should -BeTrue
        }
    }

    Context 'branch exists both locally and remotely with wrong tracking' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            # Create and push a branch
            git checkout -b mismatched --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'mis.txt') -Force | Out-Null
            git add mis.txt
            git commit -m "mismatched commit" --quiet
            git push origin mismatched --quiet 2>$null
            # Break tracking by setting upstream to master
            git branch --set-upstream-to=origin/master mismatched 2>$null
            git checkout master --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'warns about tracking mismatch' {
            $output = (Invoke-AddWorktree 'mismatched' $false) 6>&1 | Out-String
            $output | Should -Match 'does not track'
        }
    }
}

Describe 'Invoke-CreateWorktree' {
    BeforeAll {
        $script:repo = New-TestRepo
        Set-Location $script:repo.MainPath
        $null = (. $script:ScriptPath help) 6>&1
    }

    BeforeEach {
        $script:savedLocation = Get-Location
        Set-Location $script:repo.MainPath
    }

    AfterEach {
        Set-Location $script:savedLocation
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'prints usage when no branch given' {
        $output = (Invoke-CreateWorktree '' $false) 6>&1 | Out-String
        $output | Should -Match 'Usage:'
    }

    It 'creates a worktree and switches to it' {
        $null = (Invoke-CreateWorktree 'new-feature' $false) 6>&1
        $wtPath = Join-Path $script:repo.Root "$($script:repo.RepoName)\new-feature"
        Test-Path $wtPath | Should -BeTrue
        (Get-Location).Path | Should -BeLike '*new-feature*'
    }
}

Describe 'Invoke-CheckWorktree' {
    Context 'clean worktree (committed, pushed, tracked)' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            # Create branch, commit, push, then add as worktree
            git checkout -b clean-branch --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'clean.txt') -Force | Out-Null
            git add clean.txt
            git commit -m "clean commit" --quiet
            git push -u origin clean-branch --quiet 2>$null
            git checkout master --quiet 2>$null
            $wtPath = Join-Path $script:repo.Root 'clean-branch'
            git worktree add $wtPath clean-branch --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows clean but not yet merged' {
            $output = (Invoke-CheckWorktree 'clean-branch') 6>&1 | Out-String
            $output | Should -Match 'No uncommitted changes'
            $output | Should -Match 'No unpushed commits'
            $output | Should -Match 'Not merged into'
            $output | Should -Match 'Some checks failed'
        }
    }

    Context 'uncommitted changes' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b dirty-branch --quiet 2>$null
            git push -u origin dirty-branch --quiet 2>$null
            git checkout master --quiet 2>$null
            $wtPath = Join-Path $script:repo.Root 'dirty-branch'
            git worktree add $wtPath dirty-branch --quiet 2>$null
            # Add an uncommitted file
            New-Item -ItemType File -Path (Join-Path $wtPath 'dirty.txt') -Force | Out-Null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows uncommitted changes warning' {
            $output = (Invoke-CheckWorktree 'dirty-branch') 6>&1 | Out-String
            $output | Should -Match 'Has uncommitted changes'
            $output | Should -Match 'Some checks failed'
        }
    }

    Context 'no upstream tracking' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $wtPath = Join-Path $script:repo.Root 'no-upstream'
            git worktree add -b no-upstream $wtPath --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows no upstream warning' {
            $output = (Invoke-CheckWorktree 'no-upstream') 6>&1 | Out-String
            $output | Should -Match 'No upstream tracking branch'
            $output | Should -Match 'Some checks failed'
        }
    }

    Context 'unpushed commits' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b unpushed-branch --quiet 2>$null
            git push -u origin unpushed-branch --quiet 2>$null
            git checkout master --quiet 2>$null
            $wtPath = Join-Path $script:repo.Root 'unpushed-branch'
            git worktree add $wtPath unpushed-branch --quiet 2>$null
            # Add a commit in the worktree that isn't pushed
            Push-Location $wtPath
            New-Item -ItemType File -Path (Join-Path $wtPath 'unpushed.txt') -Force | Out-Null
            git add unpushed.txt
            git commit -m "unpushed commit" --quiet
            Pop-Location
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows unpushed commits warning' {
            $output = (Invoke-CheckWorktree 'unpushed-branch') 6>&1 | Out-String
            $output | Should -Match 'Has unpushed commits'
            $output | Should -Match 'Some checks failed'
        }
    }

    Context 'no name argument (uses current worktree)' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b current-check --quiet 2>$null
            git push -u origin current-check --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'current-check'
            git worktree add $script:wtPath current-check --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        BeforeEach {
            $script:savedLocation = Get-Location
        }

        AfterEach {
            Set-Location $script:savedLocation
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'checks the current worktree when no name given' {
            Set-Location $script:wtPath
            $output = (Invoke-CheckWorktree '') 6>&1 | Out-String
            $output | Should -Match 'current-check'
            $output | Should -Match 'Merged into'
            $output | Should -Match 'Ready for'
        }
    }

    Context 'branch merged into main' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b merged-branch --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'merged.txt') -Force | Out-Null
            git add merged.txt
            git commit -m "merged commit" --quiet
            git checkout master --quiet 2>$null
            git merge merged-branch --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'merged-branch'
            git worktree add $script:wtPath merged-branch --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows merged into main warning' {
            $output = (Invoke-CheckWorktree 'merged-branch') 6>&1 | Out-String
            $output | Should -Match 'Merged into'
        }
    }

    Context 'not inside any worktree' {
        BeforeAll {
            $script:repo = New-TestRepo
            $null = (. $script:ScriptPath help) 6>&1
        }

        BeforeEach {
            $script:savedLocation = Get-Location
        }

        AfterEach {
            Set-Location $script:savedLocation
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows not inside message' {
            Set-Location $env:TEMP
            $output = (Invoke-CheckWorktree '') 6>&1 | Out-String
            $output | Should -Match 'Not inside any known worktree'
        }
    }
}

Describe 'Invoke-CheckWorktree --all' {
    Context 'mixed worktrees - some clean, some not' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath

            # clean-all: committed, pushed, tracked
            git checkout -b clean-all --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'ca.txt') -Force | Out-Null
            git add ca.txt
            git commit -m "clean-all commit" --quiet
            git push -u origin clean-all --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:cleanPath = Join-Path $script:repo.Root 'clean-all'
            git worktree add $script:cleanPath clean-all --quiet 2>$null

            # dirty-all: has uncommitted changes
            git checkout -b dirty-all --quiet 2>$null
            git push -u origin dirty-all --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:dirtyPath = Join-Path $script:repo.Root 'dirty-all'
            git worktree add $script:dirtyPath dirty-all --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:dirtyPath 'dirty.txt') -Force | Out-Null

            # merged-all: branch is merged into master
            git checkout -b merged-all --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'ma.txt') -Force | Out-Null
            git add ma.txt
            git commit -m "merged-all commit" --quiet
            git checkout master --quiet 2>$null
            git merge merged-all --quiet 2>$null
            $script:mergedPath = Join-Path $script:repo.Root 'merged-all'
            git worktree add $script:mergedPath merged-all --quiet 2>$null

            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'shows a table with column headers' {
            $output = (Invoke-CheckWorktree '' $true) 6>&1 | Out-String
            $output | Should -Match 'Worktree'
            $output | Should -Match 'Is clean\?'
            $output | Should -Match 'Has upstream\?'
            $output | Should -Match 'Unpushed\?'
            $output | Should -Match 'Merged\?'
        }

        It 'shows merged status for merged worktree row' {
            $output = (Invoke-CheckWorktree '' $true) 6>&1 | Out-String
            $lines = $output -split "`n"
            $mergedLine = $lines | Where-Object { $_ -match 'merged-all' } | Select-Object -First 1
            $mergedLine | Should -Not -BeNullOrEmpty
            $mergedLine | Should -Match ([regex]::Escape([char]0x2713))  # ✓
        }

        It 'shows not-merged status for unmerged worktree row' {
            $output = (Invoke-CheckWorktree '' $true) 6>&1 | Out-String
            $lines = $output -split "`n"
            $cleanLine = $lines | Where-Object { $_ -match 'clean-all' } | Select-Object -First 1
            $cleanLine | Should -Not -BeNullOrEmpty
            $cleanLine | Should -Match ([regex]::Escape([char]0x2717))  # ✗
        }

        It 'lists all non-main worktrees as table rows' {
            $output = (Invoke-CheckWorktree '' $true) 6>&1 | Out-String
            $output | Should -Match 'clean-all'
            $output | Should -Match 'dirty-all'
        }

        It 'shows clean status for clean worktree row' {
            $output = (Invoke-CheckWorktree '' $true) 6>&1 | Out-String
            # clean-all row: Is clean? and Has upstream? should be ✓
            $lines = $output -split "`n"
            $cleanLine = $lines | Where-Object { $_ -match 'clean-all' } | Select-Object -First 1
            $cleanLine | Should -Not -BeNullOrEmpty
            $cleanLine | Should -Match ([regex]::Escape([char]0x2713))  # ✓
        }

        It 'shows dirty status for dirty worktree row' {
            $output = (Invoke-CheckWorktree '' $true) 6>&1 | Out-String
            # dirty-all row should contain ✗ (has uncommitted changes)
            $lines = $output -split "`n"
            $dirtyLine = $lines | Where-Object { $_ -match 'dirty-all' } | Select-Object -First 1
            $dirtyLine | Should -Not -BeNullOrEmpty
            $dirtyLine | Should -Match ([regex]::Escape([char]0x2717))  # ✗
        }
    }
}

Describe 'Invoke-DoneWorktree' {
    Context 'blocks when uncommitted changes (no --yes)' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b dirty-done --quiet 2>$null
            git push -u origin dirty-done --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'dirty-done'
            git worktree add $script:wtPath dirty-done --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:wtPath 'dirty.txt') -Force | Out-Null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'warns about uncommitted changes and keeps worktree' {
            $output = (Invoke-DoneWorktree 'dirty-done' $false) 6>&1 | Out-String
            $output | Should -Match 'uncommitted changes'
            Test-Path $script:wtPath | Should -BeTrue
        }
    }

    Context 'blocks when unpushed commits (no --yes)' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b unpushed-done --quiet 2>$null
            git push -u origin unpushed-done --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'unpushed-done'
            git worktree add $script:wtPath unpushed-done --quiet 2>$null
            Push-Location $script:wtPath
            New-Item -ItemType File -Path (Join-Path $script:wtPath 'new.txt') -Force | Out-Null
            git add new.txt
            git commit -m "unpushed" --quiet
            Pop-Location
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'warns about unpushed commits and keeps worktree' {
            $output = (Invoke-DoneWorktree 'unpushed-done' $false) 6>&1 | Out-String
            $output | Should -Match 'unpushed commits'
            Test-Path $script:wtPath | Should -BeTrue
        }
    }

    Context 'blocks when no upstream (no --yes)' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $script:wtPath = Join-Path $script:repo.Root 'no-up-done'
            git worktree add -b no-up-done $script:wtPath --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'warns about no upstream and keeps worktree' {
            $output = (Invoke-DoneWorktree 'no-up-done' $false) 6>&1 | Out-String
            $output | Should -Match 'no upstream tracking branch'
            Test-Path $script:wtPath | Should -BeTrue
        }
    }

    Context 'all clean — removes worktree and deletes branch' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b clean-done --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'clean.txt') -Force | Out-Null
            git add clean.txt
            git commit -m "clean commit" --quiet
            git push -u origin clean-done --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'clean-done'
            git worktree add $script:wtPath clean-done --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'removes the worktree and deletes the branch' {
            $null = (Invoke-DoneWorktree 'clean-done' $false) 6>&1
            Test-Path $script:wtPath | Should -BeFalse
            $branches = git branch --list 'clean-done'
            $branches | Should -BeNullOrEmpty
        }
    }

    Context 'force removes with --yes despite uncommitted changes' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b force-done --quiet 2>$null
            git push -u origin force-done --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'force-done'
            git worktree add $script:wtPath force-done --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:wtPath 'dirty.txt') -Force | Out-Null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'removes the worktree despite dirty state' {
            $null = (Invoke-DoneWorktree 'force-done' $true) 6>&1
            Test-Path $script:wtPath | Should -BeFalse
        }
    }

    Context 'uses current worktree when no name given' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            git checkout -b current-done --quiet 2>$null
            New-Item -ItemType File -Path (Join-Path $script:repo.MainPath 'c.txt') -Force | Out-Null
            git add c.txt
            git commit -m "current done commit" --quiet
            git push -u origin current-done --quiet 2>$null
            git checkout master --quiet 2>$null
            $script:wtPath = Join-Path $script:repo.Root 'current-done'
            git worktree add $script:wtPath current-done --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        BeforeEach {
            $script:savedLocation = Get-Location
        }

        AfterEach {
            Set-Location $script:savedLocation
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'switches to main and removes the current worktree' {
            Set-Location $script:wtPath
            $null = (Invoke-DoneWorktree '' $false) 6>&1
            (Get-Location).Path | Should -Be $script:repo.MainPath
            Test-Path $script:wtPath | Should -BeFalse
        }
    }

    Context 'cannot clean up the main worktree' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        BeforeEach {
            $script:savedLocation = Get-Location
        }

        AfterEach {
            Set-Location $script:savedLocation
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'prints cannot clean up main worktree' {
            Set-Location $script:repo.MainPath
            $output = (Invoke-DoneWorktree '' $false) 6>&1 | Out-String
            $output | Should -Match 'Cannot clean up the main worktree'
        }
    }

    Context 'no matching worktree' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'prints no worktree found message' {
            $output = (Invoke-DoneWorktree 'nonexistent' $false) 6>&1 | Out-String
            $output | Should -Match 'No worktree matching'
        }
    }
}

Describe 'Invoke-RmWorktree' {
    Context 'prints usage when no name given' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'prints usage' {
            $output = (Invoke-RmWorktree '' $false) 6>&1 | Out-String
            $output | Should -Match 'Usage:'
        }
    }

    Context 'removes a matching worktree' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $script:wtPath = Join-Path $script:repo.Root 'rm-target'
            git worktree add -b rm-target $script:wtPath --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'removes the worktree' {
            $null = (Invoke-RmWorktree 'rm-target' $false) 6>&1
            Test-Path $script:wtPath | Should -BeFalse
        }
    }

    Context 'blocks when inside the target worktree' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $script:wtPath = Join-Path $script:repo.Root 'rm-current'
            git worktree add -b rm-current $script:wtPath --quiet 2>$null
            $null = (. $script:ScriptPath help) 6>&1
        }

        BeforeEach {
            $script:savedLocation = Get-Location
        }

        AfterEach {
            Set-Location $script:savedLocation
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'prints cannot remove message' {
            Set-Location $script:wtPath
            $output = (Invoke-RmWorktree 'rm-current' $false) 6>&1 | Out-String
            $output | Should -Match 'Cannot remove the current worktree'
            Test-Path $script:wtPath | Should -BeTrue
        }
    }

    Context 'prints not found for unknown name' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'prints not found message' {
            $output = (Invoke-RmWorktree 'nonexistent' $false) 6>&1 | Out-String
            $output | Should -Match 'No worktree matching'
        }
    }

    Context 'removes directory left behind when git deregistered the worktree but could not delete the folder' {
        BeforeAll {
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $script:wtPath = Join-Path $script:repo.Root 'leftover'
            git worktree add -b leftover $script:wtPath --quiet 2>$null
            # Simulate: git already deregistered the worktree (prune), but the directory remains
            git worktree remove --force $script:wtPath 2>$null
            # Directory is gone; recreate it to represent the leftover folder
            New-Item -ItemType Directory -Path $script:wtPath -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:wtPath 'stray.txt') -Force | Out-Null
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'removes the leftover directory' {
            $null = (Invoke-RemoveLeftoverWorktreeDirectory $script:wtPath) 6>&1
            Test-Path $script:wtPath | Should -BeFalse
        }
    }
}

Describe 'Command dispatch' {
    BeforeAll {
        $script:repo = New-TestWorktreeRepo -Branches @('dispatch-a')
        Set-Location $script:repo.MainPath
    }

    BeforeEach {
        $script:savedLocation = Get-Location
        Set-Location $script:repo.MainPath
    }

    AfterEach {
        Set-Location $script:savedLocation
    }

    AfterAll {
        Remove-TestRepo $script:repo.Root
    }

    It 'dispatches list command' {
        $output = (. $script:ScriptPath list) 6>&1 | Out-String
        $output | Should -Match 'dispatch-a'
    }

    It 'dispatches version command' {
        $output = (. $script:ScriptPath version) 6>&1 | Out-String
        $output | Should -Match 'Version:'
    }

    It 'dispatches help command' {
        $output = (. $script:ScriptPath help) 6>&1 | Out-String
        $output | Should -Match 'Usage:'
    }

    It 'dispatches -h flag' {
        $output = (. $script:ScriptPath -h) 6>&1 | Out-String
        $output | Should -Match 'Usage:'
    }

    It 'dispatches --help flag' {
        $output = (. $script:ScriptPath -help) 6>&1 | Out-String
        $output | Should -Match 'Usage:'
    }

    It 'dispatches current command' {
        $output = (. $script:ScriptPath current) 6>&1 | Out-String
        $output | Should -Match 'Current worktree:'
    }

    It 'dispatches - to go to main worktree' {
        Set-Location $script:repo.Worktrees['dispatch-a']
        $null = (. $script:ScriptPath '-') 6>&1
        (Get-Location).Path | Should -Be $script:repo.MainPath
    }

    It 'dispatches bare name as worktree switch' {
        $null = (. $script:ScriptPath 'dispatch-a') 6>&1
        (Get-Location).Path | Should -BeLike '*dispatch-a*'
    }

    It 'dispatches check --all' {
        $output = (. $script:ScriptPath check --all) 6>&1 | Out-String
        $output | Should -Match 'dispatch-a'
    }
}
