Set-StrictMode -Version Latest

BeforeAll {
    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    # Extract inner functions from the dot-sourced file via AST.
    # Uses Invoke-Expression on function definition AST nodes - safe because
    # ParseFile only parses (no execution) and we only evaluate FunctionDefinitionAst
    # nodes, which merely define functions without side effects.
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionSummary.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'New-ExecutionSummaryRecord' {
    It 'returns a PSCustomObject with all required fields' {
        $tweak = @{
            Key = '5'; Name = 'Test Tweak'; Function = 'TestFunc'
            Category = 'System'; Risk = 'Low'; Type = 'Toggle'
            TypeKind = 'toggle'; TypeLabel = 'Toggle'; TypeTone = 'Primary'
            Selection = 'Enable'; CurrentState = 'Disabled'
            CurrentStateTone = 'Muted'; StateDetail = ''; BlastRadius = 'Low'
        }

        $record = New-ExecutionSummaryRecord -Order 1 -Tweak ([pscustomobject]$tweak)

        $record | Should -Not -BeNullOrEmpty
        $record.Key | Should -Be '5'
        $record.Order | Should -Be 1
        $record.Name | Should -Be 'Test Tweak'
        $record.Function | Should -Be 'TestFunc'
        $record.Status | Should -Be 'Pending'
        $record.OutcomeState | Should -BeNullOrEmpty
    }

    It 'carries Impact and PresetTier from the tweak' {
        $tweak = [pscustomobject]@{
            Key = '7'; Name = 'Tier Test'; Function = 'TierFunc'
            Category = 'System'; Risk = 'Medium'; Type = 'Toggle'
            TypeKind = 'toggle'; TypeLabel = 'Toggle'; TypeTone = 'Primary'
            Selection = 'Enable'; CurrentState = 'Off'
            CurrentStateTone = 'Muted'; StateDetail = ''; BlastRadius = 'Medium'
            Impact = 'Visible'; PresetTier = 'Advanced'
        }

        $record = New-ExecutionSummaryRecord -Order 1 -Tweak $tweak

        $record.Impact | Should -Be 'Visible'
        $record.PresetTier | Should -Be 'Advanced'
    }

    It 'defaults Game Mode fields to false/null when absent' {
        $tweak = [pscustomobject]@{
            Key = '1'; Name = 'Basic'; Function = 'BasicFunc'
            Category = 'System'; Risk = 'Low'; Type = 'Action'
            TypeKind = 'action'; TypeLabel = 'Action'; TypeTone = 'Primary'
            Selection = 'Run'; CurrentState = 'Ready'
            CurrentStateTone = 'Primary'; StateDetail = ''; BlastRadius = 'Low'
        }

        $record = New-ExecutionSummaryRecord -Order 1 -Tweak $tweak

        $record.FromGameMode | Should -Be $false
        $record.GameModeProfile | Should -BeNullOrEmpty
        $record.GameModeOperation | Should -Be 'Apply'
    }

    It 'carries Game Mode fields when present' {
        $tweak = [pscustomobject]@{
            Key = 'gamemode::TestFunc'; Name = 'GM Tweak'; Function = 'TestFunc'
            Category = 'Gaming'; Risk = 'Low'; Type = 'Toggle'
            TypeKind = 'toggle'; TypeLabel = 'Toggle'; TypeTone = 'Primary'
            Selection = 'Enable'; CurrentState = 'Off'
            CurrentStateTone = 'Muted'; StateDetail = ''; BlastRadius = 'Low'
            FromGameMode = $true; GameModeProfile = 'Casual'; GameModeOperation = 'Apply'
        }

        $record = New-ExecutionSummaryRecord -Order 1 -Tweak $tweak

        $record.FromGameMode | Should -Be $true
        $record.GameModeProfile | Should -Be 'Casual'
        $record.GameModeOperation | Should -Be 'Apply'
    }
}

Describe 'Get-ExecutionSummaryClassification' {
    It 'classifies Success correctly' {
        $result = Get-ExecutionSummaryClassification -Status 'Success' -Detail ''

        $result.OutcomeState | Should -Be 'Success'
        $result.OutcomeReason | Should -Not -BeNullOrEmpty
    }

    It 'marks Success with Direct recovery as recoverable' {
        $result = Get-ExecutionSummaryClassification -Status 'Success' -Detail '' -RecoveryLevel 'Direct'

        $result.IsRecoverable | Should -Be $true
    }

    It 'classifies Restart pending' {
        $result = Get-ExecutionSummaryClassification -Status 'Restart pending' -Detail ''

        $result.OutcomeState | Should -Be 'Restart pending'
        $result.FailureCode | Should -Be 'restart_required'
        $result.IsRecoverable | Should -Be $true
    }

    It 'classifies Not Run' {
        $result = Get-ExecutionSummaryClassification -Status 'Not Run' -Detail ''

        $result.OutcomeState | Should -Be 'Not run'
        $result.FailureCode | Should -Be 'not_run'
    }

    It 'classifies Not applicable' {
        $result = Get-ExecutionSummaryClassification -Status 'Not applicable' -Detail ''

        $result.OutcomeState | Should -Be 'Not applicable on this system'
        $result.FailureCode | Should -Be 'not_applicable'
    }

    It 'classifies Skipped with already-desired detail' {
        $result = Get-ExecutionSummaryClassification -Status 'Skipped' -Detail 'already in desired state'

        $result.OutcomeState | Should -Be 'Already in desired state'
        $result.FailureCode | Should -Be 'already_in_desired_state'
    }

    It 'classifies Skipped with unsupported detail' {
        $result = Get-ExecutionSummaryClassification -Status 'Skipped' -Detail 'not supported on this build'

        $result.OutcomeState | Should -Be 'Not applicable on this system'
        $result.FailureCode | Should -Be 'unsupported_environment'
    }

    It 'classifies Skipped by policy' {
        $result = Get-ExecutionSummaryClassification -Status 'Skipped' -Detail 'excluded by filter'

        $result.OutcomeState | Should -Be 'Skipped by preset or selection'
        $result.FailureCode | Should -Be 'skipped_by_policy'
    }

    It 'classifies restore-mode already-at-default skips correctly' {
        $result = Get-ExecutionSummaryClassification -Status 'Skipped' -Detail 'already at windows default' -Mode 'Defaults'

        $result.OutcomeState | Should -Be 'Already at Windows default'
        $result.FailureCode | Should -Be 'already_at_default'
    }

    It 'classifies Failed with access denied detail' {
        $result = Get-ExecutionSummaryClassification -Status 'Failed' -Detail 'access denied to registry key'

        $result.FailureCategory | Should -Be 'Access denied'
        $result.FailureCode | Should -Be 'access_denied'
    }

    It 'classifies Failed with network detail' {
        $result = Get-ExecutionSummaryClassification -Status 'Failed' -Detail 'download timeout'

        $result.FailureCategory | Should -Be 'Network/download failure'
        $result.FailureCode | Should -Be 'network_download_failure'
    }

    It 'classifies generic Failed' {
        $result = Get-ExecutionSummaryClassification -Status 'Failed' -Detail 'something broke'

        $result.FailureCategory | Should -Be 'General failure'
        $result.FailureCode | Should -Be 'general_failure'
    }

    It 'returns Pending for unknown status' {
        $result = Get-ExecutionSummaryClassification -Status '' -Detail ''

        $result.OutcomeState | Should -Be 'Pending'
    }
}

Describe 'Get-RestoreDefaultsOutcomeText' {
    It 'returns restore-specific success text' {
        $result = Get-RestoreDefaultsOutcomeText -OutcomeState 'Success'

        $result | Should -Be 'Restored to Windows default.'
    }

    It 'returns package follow-up wording for package restore failures' {
        $result = Get-RestoreDefaultsOutcomeText -FailureCode 'general_failure' -TypeKind 'Package'

        $result | Should -Be 'This app may require package or Store follow-up to fully restore.'
    }

    It 'returns manual follow-up wording for non-package restore failures' {
        $result = Get-RestoreDefaultsOutcomeText -FailureCode 'manual_intervention_required' -TypeKind 'Toggle'

        $result | Should -Be 'Manual recovery required to finish restoring this item.'
    }
}

Describe 'Update-ExecutionSummaryClassification' {
    It 'applies restore-specific package follow-up wording to defaults records' {
        $Script:ExecutionMode = 'Defaults'
        $record = [pscustomobject]@{
            Status = 'Failed'
            Detail = 'something broke'
            RecoveryLevel = 'Manual'
            Restorable = $false
            TypeKind = 'Package'
            IsRemoval = $false
            OutcomeState = $null
            OutcomeReason = $null
            FailureCategory = $null
            FailureCode = $null
            IsRecoverable = $false
            RetryAvailability = $null
            RetryReason = $null
            RecoveryHint = $null
        }

        Update-ExecutionSummaryClassification -Record $record

        $record.OutcomeState | Should -Be 'Failed and manual intervention required'
        $record.OutcomeReason | Should -Be 'This app may require package or Store follow-up to fully restore.'
    }
}

Describe 'Get-ExecutionResultLiveLogEntry' {
    It 'formats success records as a single success line' {
        $record = [pscustomobject]@{
            Name = 'Display and Sleep Timeouts'
            Status = 'Success'
            Detail = $null
            OutcomeState = 'Success'
            OutcomeReason = 'Baseline applied the requested change successfully.'
        }

        $entry = Get-ExecutionResultLiveLogEntry -Record $record

        $entry.Message | Should -Be 'Display and Sleep Timeouts - success'
        $entry.Level | Should -Be 'SUCCESS'
    }

    It 'formats failed records with the failure reason' {
        $record = [pscustomobject]@{
            Name = 'Install PowerShell 7'
            Status = 'Failed'
            Detail = 'winget executable was not found'
            OutcomeState = 'Failed and manual intervention required'
            OutcomeReason = 'This step could not continue because something it depends on was missing.'
        }

        $entry = Get-ExecutionResultLiveLogEntry -Record $record

        $entry.Message | Should -Be 'Install PowerShell 7 - failed (winget executable was not found)'
        $entry.Level | Should -Be 'ERROR'
    }

    It 'formats skipped records with the skip reason' {
        $record = [pscustomobject]@{
            Name = 'Clipboard History'
            Status = 'Skipped'
            Detail = 'already in desired state'
            OutcomeState = 'Already in desired state'
            OutcomeReason = 'Nothing needed to change because this PC already matched what you asked for.'
        }

        $entry = Get-ExecutionResultLiveLogEntry -Record $record

        $entry.Message | Should -Be 'Clipboard History - skipped (already in desired state)'
        $entry.Level | Should -Be 'SKIP'
    }

    It 'formats restart-pending records as success with a reason' {
        $record = [pscustomobject]@{
            Name = 'Device Sensors'
            Status = 'Restart pending'
            Detail = $null
            OutcomeState = 'Restart pending'
            OutcomeReason = 'Baseline applied this change, but Windows still needs a restart before it is fully finished.'
        }

        $entry = Get-ExecutionResultLiveLogEntry -Record $record

        $entry.Message | Should -Be 'Device Sensors - success (Baseline applied this change, but Windows still needs a restart before it is fully finished.)'
        $entry.Level | Should -Be 'WARNING'
    }
}
