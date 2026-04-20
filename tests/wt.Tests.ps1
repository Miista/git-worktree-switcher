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
