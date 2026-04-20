param([string]$Task = 'Test')

switch ($Task) {
    'Test' {
        Import-Module Pester -MinimumVersion 5.0
        Invoke-Pester ./tests/wt.Tests.ps1 -Output Detailed
    }
}
