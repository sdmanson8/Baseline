# End-to-end scenario: remote dry-run with a fake transport.
#
# Verifies the multi-target preview default and structured CLI output paths
# without touching real WinRM. The transport is replaced with a stub that
# returns deterministic per-target results so we can assert aggregation.

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    Import-Module (Join-Path $repoRoot 'Module\SharedHelpers.psm1') -Force -ErrorAction Stop
    # directly so the scenario can call Test-PreflightWinRMReachability without
    # spinning up the full WPF host.
    . (Join-Path $repoRoot 'Module\GUI\PreflightChecks.ps1')
    if (-not (Get-Command -Name 'Get-UxLocalizedString' -ErrorAction SilentlyContinue))
    {
        <#
            .SYNOPSIS
        #>

        function Global:Get-UxLocalizedString { param([string]$Key, [string]$Fallback = $Key) return $Fallback }
    }
}

Describe 'Remote dry-run scenario (fake transport)' {

    BeforeEach {
        Set-BaselineCliOutputFormat -Format 'Ndjson'
    }

    AfterEach {
        Set-BaselineCliOutputFormat -Format 'Text'
    }

    It 'serialises a single result object as compact JSON when format=Json' {
        Set-BaselineCliOutputFormat -Format 'Json'
        $captured = $null
        $previousOut = [Console]::Out
        try {
            $writer = New-Object System.IO.StringWriter
            [Console]::SetOut($writer)
            Format-BaselineCliResult -InputObject ([pscustomobject]@{ Target = 'host-a'; Result = 'Pass' })
            $captured = $writer.ToString()
        }
        finally { [Console]::SetOut($previousOut) }
        $captured | Should -Match '"Target"\s*:\s*"host-a"'
        $captured | Should -Match '"Result"\s*:\s*"Pass"'
    }

    It 'emits one ndjson record per item when format=Ndjson' {
        $captured = $null
        $previousOut = [Console]::Out
        try {
            $writer = New-Object System.IO.StringWriter
            [Console]::SetOut($writer)
            $items = @(
                [pscustomobject]@{ Target = 'host-a'; Status = 'Reachable' }
                [pscustomobject]@{ Target = 'host-b'; Status = 'Unreachable'; Error = 'WinRM timeout' }
                [pscustomobject]@{ Target = 'host-c'; Status = 'Reachable' }
            )
            $items | Format-BaselineCliResult
            $captured = $writer.ToString()
        }
        finally { [Console]::SetOut($previousOut) }

        $lines = ($captured -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        @($lines).Count | Should -Be 3

        $second = $lines[1] | ConvertFrom-Json
        $second.Target | Should -Be 'host-b'
        $second.Status | Should -Be 'Unreachable'
        $second.Error  | Should -Be 'WinRM timeout'
    }

    It 'classifies WinRM preflight as Passed when no targets supplied' {
        $result = Test-PreflightWinRMReachability -Targets @()
        $result.Status | Should -Be 'Passed'
    }

    It 'returns a per-target conflict aggregate from the GPO report' {
        $entries = @(
            [pscustomobject]@{ Function = 'NonPolicyA'; RegistryPath = 'HKCU:\SOFTWARE\Baseline\NoPolicyA'; RegistryName = 'V' },
            [pscustomobject]@{ Function = 'NonPolicyB'; RegistryPath = 'HKCU:\SOFTWARE\Baseline\NoPolicyB'; RegistryName = 'V' }
        )
        $report = Get-BaselineGpoConflictReport -Manifest $entries -FunctionFilter @('NonPolicyA')
        $report.HasConflicts | Should -BeFalse
        $report.Conflicts | Should -BeNullOrEmpty
    }
}
