Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SystemMaintenance.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    function Remove-HandledErrorRecord {}
    function Get-WinEvent {}
    function LogWarning { param([string]$Message) $script:lastSystemMaintenanceWarning = $Message }
}

Describe 'Get-MinimumRecommendedMemoryCompressionRamGB' {
    It 'returns the shared RAM threshold as an integer' {
        $result = Get-MinimumRecommendedMemoryCompressionRamGB

        $result | Should -BeOfType [int]
        $result | Should -BeGreaterThan 0
    }
}

Describe 'Test-Windows11SmbDuplicateSidIssue' {
    BeforeEach {
        $script:lastSystemMaintenanceWarning = $null
    }

    It 'returns true when LSASS duplicate SID events are present' {
        Mock Get-WinEvent {
            @(
                [pscustomobject]@{ Message = 'There is a partial mismatch in the machine ID for this system.' }
            )
        }

        $result = Test-Windows11SmbDuplicateSidIssue -LookbackDays 7

        $result | Should -Be $true
    }

    It 'returns false and logs a warning when the event query fails' {
        Mock Get-WinEvent { throw 'event query failed' }

        $result = Test-Windows11SmbDuplicateSidIssue -LookbackDays 7

        $result | Should -Be $false
        $script:lastSystemMaintenanceWarning | Should -Match 'Unable to query LSASS Event ID 6167'
    }
}
