Set-StrictMode -Version Latest

BeforeAll {
    function Get-TweakManifestEntryValue {
        param(
            [Parameter(Mandatory = $true)][object]$Entry,
            [Parameter(Mandatory = $true)][string]$FieldName
        )

        if ($Entry -is [System.Collections.IDictionary])
        {
            if ($Entry.Contains($FieldName)) { return $Entry[$FieldName] }
            return $null
        }

        if ($Entry.PSObject -and $Entry.PSObject.Properties[$FieldName])
        {
            return $Entry.PSObject.Properties[$FieldName].Value
        }

        return $null
    }

    function Get-OSInfo {
        [pscustomobject]@{ Caption = 'Test OS' }
    }

    function Get-WindowsVersionData {
        [pscustomobject]@{ DisplayVersion = 'Test Display Version' }
    }

    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/StateCapture.Helpers.ps1')
}

Describe 'New-SystemStateSnapshot progress callbacks' {
    It 'reports system information and each scannable Detect entry before evaluation' {
        $script:ProgressEvents = [System.Collections.Generic.List[object]]::new()
        $manifest = @(
            [pscustomobject]@{
                Name = 'First entry'
                Function = 'FirstFunction'
                Category = 'Test'
                Scannable = $true
                Detect = { 'first' }
            },
            [pscustomobject]@{
                Name = 'Skipped entry'
                Function = 'SkippedFunction'
                Category = 'Test'
                Scannable = $false
                Detect = { 'skipped' }
            },
            [pscustomobject]@{
                Name = 'Other category'
                Function = 'OtherFunction'
                Category = 'Other'
                Scannable = $true
                Detect = { 'other' }
            }
        )

        $snapshot = New-SystemStateSnapshot -Manifest $manifest -CategoryFilter 'Test' -ProgressCallback {
            param([object]$Progress)
            [void]$script:ProgressEvents.Add($Progress)
        }

        @($snapshot.Entries) | Should -HaveCount 1
        $script:ProgressEvents | Should -HaveCount 2
        $script:ProgressEvents[0].Stage | Should -Be 'SystemInfo'
        $script:ProgressEvents[1].Stage | Should -Be 'EntryStart'
        $script:ProgressEvents[1].Index | Should -Be 1
        $script:ProgressEvents[1].Total | Should -Be 1
        $script:ProgressEvents[1].Function | Should -Be 'FirstFunction'
    }
}
