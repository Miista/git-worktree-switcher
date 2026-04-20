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
            $script:repo = New-TestRepo
            Set-Location $script:repo.MainPath
            $null = (. $script:ScriptPath help) 6>&1
        }

        AfterAll {
            Remove-TestRepo $script:repo.Root
        }

        It 'creates a new branch and worktree' {
            $null = (Invoke-AddWorktree 'brand-new' $false) 6>&1
            $wtPath = Join-Path $script:repo.Root 'brand-new'
            Test-Path $wtPath | Should -BeTrue
        }
    }

    Context 'branch exists only locally' {
        BeforeAll {
            $script:repo = New-TestRepo
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
            $wtPath = Join-Path $script:repo.Root 'local-only'
            Test-Path $wtPath | Should -BeTrue
        }
    }

    Context 'branch exists only on remote' {
        BeforeAll {
            $script:repo = New-TestRepo
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
            $wtPath = Join-Path $script:repo.Root 'remote-only'
            Test-Path $wtPath | Should -BeTrue
            # Verify it tracks the remote
            $upstream = git -C $wtPath rev-parse --abbrev-ref '@{upstream}' 2>$null
            $upstream | Should -Be 'origin/remote-only'
        }
    }

    Context 'branch exists both locally and remotely with correct tracking' {
        BeforeAll {
            $script:repo = New-TestRepo
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
            $wtPath = Join-Path $script:repo.Root 'tracked-branch'
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
        $wtPath = Join-Path $script:repo.Root 'new-feature'
        Test-Path $wtPath | Should -BeTrue
        (Get-Location).Path | Should -BeLike '*new-feature*'
    }
}
