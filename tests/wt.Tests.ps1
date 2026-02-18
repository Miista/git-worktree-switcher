#Requires -Modules Pester

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '..' 'wt.ps1'

    # Helper: dot-source wt.ps1 with a given set of arguments.
    # Because wt.ps1 uses param() and calls Set-Location / Write-Host directly
    # when dot-sourced, we load the functions and then call them individually in
    # most tests, using InModuleScope-style helpers where Pester Mocks work.
    #
    # For command-dispatch tests we invoke the script via a wrapper that captures
    # output and lets us assert on it without actually changing the real $PWD.

    function Invoke-Wt {
        param([string[]]$Arguments)
        # Run in a child scope so Set-Location doesn't bleed into test env
        & pwsh -NoProfile -File $ScriptPath @Arguments 2>&1
    }
}

Describe 'wt.ps1' {

    Describe 'No arguments' {
        It 'prints help text' {
            $output = Invoke-Wt @()
            $output | Should -Match 'Usage'
        }
    }

    Describe 'help command' {
        It 'prints help text' {
            $output = Invoke-Wt @('help')
            $output | Should -Match 'Usage'
        }
    }

    Describe 'version command' {
        It 'prints version string' {
            $output = Invoke-Wt @('version')
            $output | Should -Match '0\.1\.2'
        }
    }

    Describe 'list command' {
        It 'calls git worktree list and returns output' {
            # We run inside a real git repo so git worktree list should work
            $output = Invoke-Wt @('list')
            # Should contain at least the current worktree path
            $output | Should -Not -BeNullOrEmpty
        }
    }

    # ---- Tests that need mocking require dot-sourcing the functions ----
    # We use a separate Describe block that dot-sources wt.ps1 into the current
    # scope so Pester can Mock the internal calls.

    Describe 'Switch to worktree by name (unit, mocked git)' {
        BeforeAll {
            # Dot-source to bring functions into scope
            . $ScriptPath -Command '__noop__'
        }

        BeforeEach {
            Mock git {
                # Minimal porcelain output with two worktrees
                @(
                    'worktree /repo/main',
                    'HEAD abc123',
                    'branch refs/heads/main',
                    '',
                    'worktree /repo/feature-foo',
                    'HEAD def456',
                    'branch refs/heads/feature-foo',
                    ''
                )
            }
            Mock Set-Location {}
        }

        It 'calls Set-Location with matching worktree path' {
            Invoke-Switch 'feature-foo'
            Should -Invoke Set-Location -Times 1 -ParameterFilter { $Path -eq '/repo/feature-foo' }
        }

        It 'does nothing when no worktree matches' {
            Invoke-Switch 'nonexistent-branch'
            Should -Invoke Set-Location -Times 0
        }
    }

    Describe 'Switch to main worktree (unit, mocked git)' {
        BeforeAll {
            . $ScriptPath -Command '__noop__'
        }

        BeforeEach {
            Mock git {
                @(
                    'worktree /repo/main',
                    'HEAD abc123',
                    'branch refs/heads/main',
                    '',
                    'worktree /repo/feature-foo',
                    'HEAD def456',
                    'branch refs/heads/feature-foo',
                    ''
                )
            }
            Mock Set-Location {}
        }

        It 'calls Set-Location with the first worktree path' {
            Invoke-GotoMain
            Should -Invoke Set-Location -Times 1 -ParameterFilter { $Path -eq '/repo/main' }
        }
    }

    Describe 'Interactive mode without fzf' {
        BeforeAll {
            . $ScriptPath -Command '__noop__'
        }

        BeforeEach {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'fzf' }
            Mock Write-Host {}
        }

        It 'prints error when fzf is not installed' {
            # Invoke-InteractiveSwitch should write an error message
            try { Invoke-InteractiveSwitch } catch {}
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -match 'fzf' }
        }
    }
}
