Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')

    . (Join-Path $repoRoot 'Module/SharedHelpers/ConfigReview.Helpers.ps1')

    # Stub localization before loading ReviewMode so the function
    # references resolve at call time without dragging in UxPolicy.
    function global:Get-UxLocalizedString {
        param(
            [Parameter(Mandatory)][string]$Key,
            [Parameter(Mandatory)][AllowEmptyString()][string]$Fallback,
            [object[]]$FormatArgs = @()
        )
        if ($FormatArgs -and $FormatArgs.Count -gt 0) { return ($Fallback -f $FormatArgs) }
        return $Fallback
    }

    . (Join-Path $repoRoot 'Module/GUI/ReviewMode.ps1')
    $script:ReviewModeContent = Get-BaselineTestSourceText -Path (Join-Path $repoRoot 'Module/GUI/ReviewMode.ps1')

    $Script:FixturesRoot = Join-Path $repoRoot 'Tests/Fixtures/ConfigReview'

    function script:LoadFixture {
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $Script:FixturesRoot $Name
        return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    }

    # Force the dialog into its headless branch — no $Script:CurrentTheme
    # means Show-GuiReviewModeDialog short-circuits to default decisions.
    Remove-Variable -Name CurrentTheme -Scope Script -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item -Path 'Function:\Get-UxLocalizedString' -ErrorAction SilentlyContinue
}

Describe 'Get-GuiReviewModeDefaultDecisionForRow' {
    It 'returns Accept for Add' {
        Get-GuiReviewModeDefaultDecisionForRow -Action 'Add' | Should -Be 'Accept'
    }
    It 'returns Accept for Change' {
        Get-GuiReviewModeDefaultDecisionForRow -Action 'Change' | Should -Be 'Accept'
    }
    It 'returns Reject for Remove' {
        Get-GuiReviewModeDefaultDecisionForRow -Action 'Remove' | Should -Be 'Reject'
    }
    It 'returns Reject for Same' {
        Get-GuiReviewModeDefaultDecisionForRow -Action 'Same' | Should -Be 'Reject'
    }
}

Describe 'Show-GuiReviewModeDialog (headless)' {
    It 'short-circuits to default decisions when no theme is loaded' {
        $diff = @(
            [pscustomobject]@{ Id = 'A1'; Action = 'Add';    CurrentValue = '';   ImportedValue = '-Enable'  },
            [pscustomobject]@{ Id = 'C1'; Action = 'Change'; CurrentValue = '50'; ImportedValue = '25'       },
            [pscustomobject]@{ Id = 'R1'; Action = 'Remove'; CurrentValue = '-X'; ImportedValue = ''         },
            [pscustomobject]@{ Id = 'S1'; Action = 'Same';   CurrentValue = 'v';  ImportedValue = 'v'        }
        )
        $result = Show-GuiReviewModeDialog -Diff $diff
        $result.Cancelled | Should -BeFalse
        @($result.Decisions).Count | Should -Be 3
        ($result.Decisions | Where-Object Id -eq 'A1').Decision | Should -Be 'Accept'
        ($result.Decisions | Where-Object Id -eq 'C1').Decision | Should -Be 'Accept'
        ($result.Decisions | Where-Object Id -eq 'R1').Decision | Should -Be 'Reject'
    }

    It 'honours an explicit DefaultDecision override' {
        $diff = @(
            [pscustomobject]@{ Id = 'A1'; Action = 'Add';    CurrentValue = ''; ImportedValue = '-X' },
            [pscustomobject]@{ Id = 'R1'; Action = 'Remove'; CurrentValue = '-X'; ImportedValue = '' }
        )
        $result = Show-GuiReviewModeDialog -Diff $diff -DefaultDecision 'Reject'
        @($result.Decisions).Count | Should -Be 2
        ($result.Decisions | ForEach-Object Decision) | Should -Be @('Reject','Reject')
    }
}

Describe 'Compare-Resolve fixture round-trip' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $Script:Current  = LoadFixture -Name 'current-profile.json'
        $Script:Imported = LoadFixture -Name 'imported-profile.json'
        $Script:Expected = LoadFixture -Name 'expected-diff.json'
        $Script:DecisionsFx = LoadFixture -Name 'decisions-mixed.json'
        $Script:Diff = Compare-BaselineConfigForReview -Current $Script:Current -Imported $Script:Imported
        $Script:Summary = Get-BaselineConfigReviewSummary -Diff $Script:Diff
    }

    It 'matches the expected summary counts' {
        $Script:Summary.Total      | Should -Be $Script:Expected.Summary.Total
        $Script:Summary.Add        | Should -Be $Script:Expected.Summary.Add
        $Script:Summary.Remove     | Should -Be $Script:Expected.Summary.Remove
        $Script:Summary.Change     | Should -Be $Script:Expected.Summary.Change
        $Script:Summary.Same       | Should -Be $Script:Expected.Summary.Same
        $Script:Summary.Actionable | Should -Be $Script:Expected.Summary.Actionable
    }

    It 'matches the expected per-row order, action, and values' {
        @($Script:Diff).Count | Should -Be @($Script:Expected.Rows).Count
        for ($i = 0; $i -lt @($Script:Expected.Rows).Count; $i++)
        {
            $actual = $Script:Diff[$i]
            $expected = $Script:Expected.Rows[$i]
            $actual.Id            | Should -Be $expected.Id
            $actual.Action        | Should -Be $expected.Action
            $actual.CurrentValue  | Should -Be $expected.CurrentValue
            $actual.ImportedValue | Should -Be $expected.ImportedValue
        }
    }

    It 'resolves the mixed decisions to the expected accepted/rejected/skipped sets' {
        $resolved = Resolve-BaselineConfigReviewDecisions `
            -Diff $Script:Diff `
            -Decisions $Script:DecisionsFx.Decisions `
            -DefaultDecision $Script:DecisionsFx.DefaultDecision

        $acceptedIds = @($resolved.Accepted | ForEach-Object { ConvertTo-BaselineReviewEntryKey -Entry $_ })
        $acceptedIds | Sort-Object | Should -Be (@($Script:DecisionsFx.ExpectedAcceptedIds) | Sort-Object)
        @($resolved.Rejected) | Sort-Object | Should -Be (@($Script:DecisionsFx.ExpectedRejectedIds) | Sort-Object)
        @($resolved.Skipped)  | Sort-Object | Should -Be (@($Script:DecisionsFx.ExpectedSkippedIds)  | Sort-Object)
    }
}

Describe 'Invoke-GuiReviewModeGate (headless)' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $Script:GateCurrent  = LoadFixture -Name 'current-profile.json'
        $Script:GateImported = LoadFixture -Name 'imported-profile.json'
    }

    It 'returns Cancelled=$false on the headless auto-accept path' {
        $result = Invoke-GuiReviewModeGate -CurrentProfile $Script:GateCurrent -ImportedProfile $Script:GateImported
        $result.Cancelled | Should -BeFalse
    }

    It 'auto-accepts Add and Change rows and auto-rejects Remove rows' {
        $result = Invoke-GuiReviewModeGate -CurrentProfile $Script:GateCurrent -ImportedProfile $Script:GateImported
        $acceptedIds = @($result.Accepted | ForEach-Object { ConvertTo-BaselineReviewEntryKey -Entry $_ })
        $acceptedIds | Should -Contain 'BrowserEnterprisePolicies'
        $acceptedIds | Should -Contain 'AuthHardeningRegistry'
        $acceptedIds | Should -Contain 'DefenderScanCPULimit'
        $acceptedIds | Should -Contain 'PowerPlanTimeout'
        $acceptedIds | Should -Not -Contain 'BatteryPercentage'
        $acceptedIds | Should -Not -Contain 'LegacyTLSProtocols'

        @($result.Rejected) | Should -Contain 'BatteryPercentage'
        @($result.Rejected) | Should -Contain 'LegacyTLSProtocols'
        @($result.Skipped)  | Should -Contain 'DisableTelemetry'
    }

    It 'returns Cancelled=$true when the dialog is cancelled' {
        # Simulate cancel by stubbing Show-GuiReviewModeDialog within scope.
        Mock -CommandName Show-GuiReviewModeDialog -MockWith {
            return @{ Cancelled = $true; Decisions = @() }
        }
        $result = Invoke-GuiReviewModeGate -CurrentProfile $Script:GateCurrent -ImportedProfile $Script:GateImported
        $result.Cancelled | Should -BeTrue
        @($result.Accepted).Count | Should -Be 0
        @($result.Rejected).Count | Should -Be 0
    }
}

Describe 'Invoke-GuiReviewModePromptForRun' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $Script:RunCurrent  = LoadFixture -Name 'current-profile.json'
        $Script:RunImported = LoadFixture -Name 'imported-profile.json'
    }

    It 'filters the live tweak list to functions in the accepted set' {
        $tweakList = @(
            [pscustomobject]@{ Function = 'DisableTelemetry' },
            [pscustomobject]@{ Function = 'DefenderScanCPULimit' },
            [pscustomobject]@{ Function = 'PowerPlanTimeout' },
            [pscustomobject]@{ Function = 'BrowserEnterprisePolicies' },
            [pscustomobject]@{ Function = 'AuthHardeningRegistry' },
            [pscustomobject]@{ Function = 'UnrelatedTweak' }
        )

        $filtered = Invoke-GuiReviewModePromptForRun `
            -CurrentProfile $Script:RunCurrent `
            -ImportedProfile $Script:RunImported `
            -TweakList $tweakList

        $names = @($filtered | ForEach-Object Function)
        # Headless defaults: Add+Change accepted, Remove rejected, Same skipped.
        # Filter drops anything not in the accepted set.
        $names | Should -Contain 'DefenderScanCPULimit'
        $names | Should -Contain 'PowerPlanTimeout'
        $names | Should -Contain 'BrowserEnterprisePolicies'
        $names | Should -Contain 'AuthHardeningRegistry'
        $names | Should -Not -Contain 'DisableTelemetry'
        $names | Should -Not -Contain 'UnrelatedTweak'
        @($filtered).Count | Should -Be 4
    }

    It 'preserves the original tweak ordering for accepted entries' {
        $tweakList = @(
            [pscustomobject]@{ Function = 'BrowserEnterprisePolicies'; Order = 1 },
            [pscustomobject]@{ Function = 'PowerPlanTimeout';          Order = 2 },
            [pscustomobject]@{ Function = 'DefenderScanCPULimit';      Order = 3 },
            [pscustomobject]@{ Function = 'AuthHardeningRegistry';     Order = 4 }
        )

        $filtered = Invoke-GuiReviewModePromptForRun `
            -CurrentProfile $Script:RunCurrent `
            -ImportedProfile $Script:RunImported `
            -TweakList $tweakList

        @($filtered | ForEach-Object Order) | Should -Be @(1, 2, 3, 4)
    }

    It 'returns $null when the gate is cancelled' {
        Mock -CommandName Show-GuiReviewModeDialog -MockWith {
            return @{ Cancelled = $true; Decisions = @() }
        }
        $result = Invoke-GuiReviewModePromptForRun `
            -CurrentProfile $Script:RunCurrent `
            -ImportedProfile $Script:RunImported `
            -TweakList @([pscustomobject]@{ Function = 'X' })
        $result | Should -Be $null
    }
}

Describe 'ReviewMode UI surface' {
    It 'renders an Exit button and action-tone highlighting' {
        $script:ReviewModeContent | Should -Match 'Name="BtnExit"'
        $script:ReviewModeContent | Should -Match "GuiReviewModeExit"
        $script:ReviewModeContent | Should -Match 'function Get-GuiReviewModeRowTone'
        $script:ReviewModeContent | Should -Match 'LowRiskBadgeBg'
        $script:ReviewModeContent | Should -Match 'RiskHighBadgeBg'
    }
}
