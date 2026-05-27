Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $modulePath = Join-Path $PSScriptRoot '../../Module/GUIExecution.psm1'
    Import-Module $modulePath -Force

    $sharedPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
    Import-Module $sharedPath -Force

    $script:ExecutionContent = Get-BaselineTestSourceText -Path $modulePath
}

# These four cases mirror the spec wording in todo.md (OS Support Matrix →
# AppsCategory SupportsExecution): execution is gated by SupportsExecution
# in addition to (and independently from) Availability/PlatformSupport.
Describe 'Resolve-GuiExecutionSupportsExecutionGate' {
    It 'returns Allow when the field is missing (default executable, back-compat)' {
        $entry = [pscustomobject]@{ Name = 'NoField'; Function = 'NoField' }
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry
        $r.Decision | Should -Be 'Allow'
        $r.Reason | Should -Be ''
    }

    It 'returns Allow when SupportsExecution is explicitly $true' {
        $entry = [pscustomobject]@{ Name = 'Yes'; Function = 'Yes'; SupportsExecution = $true }
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry
        $r.Decision | Should -Be 'Allow'
    }

    It 'returns Block when SupportsExecution is $false and ForceUnsupported is not set' {
        $entry = [pscustomobject]@{ Name = 'No'; Function = 'No'; SupportsExecution = $false }
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry
        $r.Decision | Should -Be 'Block'
        $r.Reason | Should -Match 'Execution not supported'
    }

    It 'returns the entry-specific reason when SupportsExecutionReason is present' {
        $entry = [pscustomobject]@{
            Name = 'Widgets'
            Function = 'TaskbarWidgets'
            SupportsExecution = $false
            SupportsExecutionReason = 'Widgets requires the Windows Web Experience Pack to be installed.'
        }
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry
        $r.Decision | Should -Be 'Block'
        $r.Reason | Should -Match 'Web Experience Pack'
    }

    It 'blocks non-default cursor themes when the cursor archive URL is not configured' {
        $previous = $env:BASELINE_CURSOR_ARCHIVE_URL
        try {
            Remove-Item Env:\BASELINE_CURSOR_ARCHIVE_URL -ErrorAction SilentlyContinue
            $entry = [pscustomobject]@{ Name = 'Cursors'; Function = 'Cursors'; Type = 'Choice'; Value = 'Dark'; SupportsExecution = $true }
            $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry

            $r.Decision | Should -Be 'Block'
            $r.Reason | Should -Match 'BASELINE_CURSOR_ARCHIVE_URL'
        } finally {
            if ($null -eq $previous) {
                Remove-Item Env:\BASELINE_CURSOR_ARCHIVE_URL -ErrorAction SilentlyContinue
            } else {
                $env:BASELINE_CURSOR_ARCHIVE_URL = $previous
            }
        }
    }

    It 'allows the default cursor theme without the cursor archive URL' {
        $previous = $env:BASELINE_CURSOR_ARCHIVE_URL
        try {
            Remove-Item Env:\BASELINE_CURSOR_ARCHIVE_URL -ErrorAction SilentlyContinue
            $entry = [pscustomobject]@{ Name = 'Cursors'; Function = 'Cursors'; Type = 'Choice'; Value = 'Default'; SupportsExecution = $true }
            $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry

            $r.Decision | Should -Be 'Allow'
        } finally {
            if ($null -eq $previous) {
                Remove-Item Env:\BASELINE_CURSOR_ARCHIVE_URL -ErrorAction SilentlyContinue
            } else {
                $env:BASELINE_CURSOR_ARCHIVE_URL = $previous
            }
        }
    }

    It 'returns Force when SupportsExecution is $false and ForceUnsupported is set' {
        $entry = [pscustomobject]@{ Name = 'No'; Function = 'No'; SupportsExecution = $false }
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry -ForceUnsupported
        $r.Decision | Should -Be 'Force'
        $r.Reason | Should -Match 'Execution not supported'
    }

    It 'accepts a hashtable-style entry (loader IDictionary path)' {
        $entry = @{ Name = 'H'; Function = 'H'; SupportsExecution = $false }
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $entry
        $r.Decision | Should -Be 'Block'
    }

    It 'returns Allow on a $null entry (defensive default)' {
        $r = Resolve-GuiExecutionSupportsExecutionGate -Entry $null
        $r.Decision | Should -Be 'Allow'
    }

    # The four spec cases (matrix of SupportsExecution x Availability):
    Context 'spec matrix: SupportsExecution and Availability are independent' {
        It 'SupportsExecution=true + Available=true => executes (Allow on both gates)' {
            $entry = [pscustomobject]@{
                Name = 'AvailExec'; Function = 'AvailExec'
                SupportsExecution = $true
                Availability = [pscustomobject]@{ Available = $true; Reason = '' }
            }
            (Resolve-GuiExecutionAvailabilityGate -Entry $entry).Decision    | Should -Be 'Allow'
            (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Allow'
        }

        It 'SupportsExecution=true + Available=false => skipped by availability gate' {
            $entry = [pscustomobject]@{
                Name = 'NotAvailExec'; Function = 'NotAvailExec'
                SupportsExecution = $true
                Availability = [pscustomobject]@{ Available = $false; Reason = 'Not available on Windows 10.' }
            }
            (Resolve-GuiExecutionAvailabilityGate -Entry $entry).Decision    | Should -Be 'Block'
            (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Allow'
        }

        It 'SupportsExecution=false + Available=true => skipped by execution gate' {
            $entry = [pscustomobject]@{
                Name = 'AvailNotExec'; Function = 'AvailNotExec'
                SupportsExecution = $false
                Availability = [pscustomobject]@{ Available = $true; Reason = '' }
            }
            (Resolve-GuiExecutionAvailabilityGate -Entry $entry).Decision    | Should -Be 'Allow'
            (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Block'
        }

        It 'SupportsExecution missing + Available=true => executes (default executable)' {
            $entry = [pscustomobject]@{
                Name = 'DefaultExec'; Function = 'DefaultExec'
                Availability = [pscustomobject]@{ Available = $true; Reason = '' }
            }
            (Resolve-GuiExecutionAvailabilityGate -Entry $entry).Decision    | Should -Be 'Allow'
            (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Allow'
        }
    }

    It 'ForceUnsupported overrides BOTH gates simultaneously' {
        $entry = [pscustomobject]@{
            Name = 'Both'; Function = 'Both'
            SupportsExecution = $false
            Availability = [pscustomobject]@{ Available = $false; Reason = 'Not available on Windows Server.' }
        }
        (Resolve-GuiExecutionAvailabilityGate -Entry $entry -ForceUnsupported).Decision    | Should -Be 'Force'
        (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry -ForceUnsupported).Decision | Should -Be 'Force'
    }
}

Describe 'Test-BaselineEntrySupportsExecution (shared helper) parity with the gate' {
    It 'agrees with the gate decision on present-true entries' {
        $entry = [pscustomobject]@{ SupportsExecution = $true }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeTrue
        (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Allow'
    }

    It 'agrees with the gate decision on present-false entries' {
        $entry = [pscustomobject]@{ SupportsExecution = $false }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeFalse
        (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Block'
    }

    It 'agrees with the gate decision on missing-field entries (both default to allow)' {
        $entry = [pscustomobject]@{ Name = 'Missing' }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeTrue
        (Resolve-GuiExecutionSupportsExecutionGate -Entry $entry).Decision | Should -Be 'Allow'
    }
}

Describe 'Get-BaselineEntryExecutionSupport power setting probes' {
    BeforeEach {
        $global:BaselineTestPowercfgExitCode = 0
        $global:BaselineTestPowercfgCalls = [System.Collections.Generic.List[string]]::new()

        function global:powercfg {
            [void]$global:BaselineTestPowercfgCalls.Add(($args -join ' '))
            $global:LASTEXITCODE = $global:BaselineTestPowercfgExitCode
        }
    }

    AfterEach {
        Remove-Item Function:\global:powercfg -ErrorAction SilentlyContinue
        Remove-Variable -Name BaselineTestPowercfgExitCode -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name BaselineTestPowercfgCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'allows IntelGraphicsPowerPlan when the power setting exists' {
        $manifest = @([ordered]@{ Function = 'IntelGraphicsPowerPlan' })
        $null = Update-BaselineManifestExecutionSupport -Manifest $manifest
        $entry = $manifest[0]

        $entry['SupportsExecution'] | Should -BeTrue
        $entry.Contains('SupportsExecutionReason') | Should -BeFalse
        $global:BaselineTestPowercfgCalls[0] | Should -Be '/QUERY SCHEME_CURRENT 44f3beca-a7c0-460e-9df2-bb8b99e0cba6 3619c3f2-afb2-4afc-b0e9-e7fef372de36'
    }

    It 'blocks IntelGraphicsPowerPlan when the power setting is absent' {
        $global:BaselineTestPowercfgExitCode = 1

        $manifest = @([ordered]@{ Function = 'IntelGraphicsPowerPlan' })
        $null = Update-BaselineManifestExecutionSupport -Manifest $manifest
        $entry = $manifest[0]

        $entry['SupportsExecution'] | Should -BeFalse
        $entry['SupportsExecutionReason'] | Should -Match 'Intel integrated graphics power setting'
    }

    It 'blocks USBHubSelectiveSuspendTimeout when the power setting is absent' {
        $global:BaselineTestPowercfgExitCode = 1

        $manifest = @([ordered]@{ Function = 'USBHubSelectiveSuspendTimeout' })
        $null = Update-BaselineManifestExecutionSupport -Manifest $manifest
        $entry = $manifest[0]

        $entry['SupportsExecution'] | Should -BeFalse
        $entry['SupportsExecutionReason'] | Should -Match 'USB hub selective suspend timeout power setting'
        $global:BaselineTestPowercfgCalls[0] | Should -Be '/QUERY SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 0853a681-27c8-4100-a2fd-82013e970683'
    }
}

Describe 'Worker execution gate (Start-GuiExecutionWorker source-pattern checks)' {
    It 'invokes the SupportsExecution gate after the availability gate' {
        $script:ExecutionContent | Should -Match 'Resolve-GuiExecutionSupportsExecutionGate -Entry \$tweak -ForceUnsupported:\$bgForceUnsupported'
    }

    It 'logs a localized execution-not-supported line when the gate blocks' {
        $script:ExecutionContent | Should -Match 'GuiLogExecutionSkippedNotExecutable'
        $script:ExecutionContent | Should -Match 'Skipped . execution not supported on this system: \{0\}'
    }

    It 'logs a warning when the gate forces a non-executable entry' {
        $script:ExecutionContent | Should -Match 'Forcing execution of non-executable entry: \{0\} . \{1\}'
    }

    It 'increments a separate NotExecutableCount counter so the run report can distinguish skip reasons' {
        $script:ExecutionContent | Should -Match "NotExecutableCount"
    }

    It 'exports Resolve-GuiExecutionSupportsExecutionGate from the GUIExecution module' {
        $script:ExecutionContent | Should -Match "'Resolve-GuiExecutionSupportsExecutionGate'"
    }
}
