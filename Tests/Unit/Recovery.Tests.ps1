Set-StrictMode -Version Latest

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-DirectUndoCommandForEntry' {
    It 'returns the inverse param for a Toggle with OnParam selected' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'Enable'
        }
        $manifest = [pscustomobject]@{
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'Disable'
    }

    It 'returns the inverse param for a Toggle with OffParam selected' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'Disable'
        }
        $manifest = [pscustomobject]@{
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'Enable'
    }

    It 'returns null for non-Toggle types' {
        $entry = [pscustomobject]@{ Restorable = $true; RecoveryLevel = 'Direct' }
        $manifest = [pscustomobject]@{ Type = 'Action' }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -BeNullOrEmpty
    }

    It 'returns null when Restorable is false' {
        $entry = [pscustomobject]@{ Restorable = $false; RecoveryLevel = 'Direct'; ToggleParam = 'Enable' }
        $manifest = [pscustomobject]@{ Type = 'Toggle'; OnParam = 'Enable'; OffParam = 'Disable' }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -BeNullOrEmpty
    }

    It 'returns null when RecoveryLevel is not Direct' {
        $entry = [pscustomobject]@{ Restorable = $true; RecoveryLevel = 'Manual'; ToggleParam = 'Enable' }
        $manifest = [pscustomobject]@{ Type = 'Toggle'; OnParam = 'Enable'; OffParam = 'Disable' }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -BeNullOrEmpty
    }

    It 'returns null for null inputs' {
        $result = Get-DirectUndoCommandForEntry -Entry $null -ManifestEntry $null

        $result | Should -BeNullOrEmpty
    }

    It 'falls back to WinDefault when param does not match OnParam or OffParam' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'CustomParam'
        }
        $manifest = [pscustomobject]@{
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
            WinDefault = $true
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'Enable'
    }

    It 'returns WinDefault for Choice entries with a direct undo path' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            Value = 'Google'
        }
        $manifest = [pscustomobject]@{
            Type = 'Choice'
            Options = @('Disable', 'Google', 'Cloudflare')
            Default = 'Disable'
            WinDefault = 'Disable'
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'Disable'
    }

    It 'returns null for Choice entries without a manifest default' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            Value = 'Google'
        }
        $manifest = [pscustomobject]@{
            Type = 'Choice'
            Options = @('Google', 'Cloudflare')
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest 3>$null

        $result | Should -BeNullOrEmpty
    }

    It 'returns AC and DC values for NumericRange entries with direct rollback' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
        }
        $manifest = [pscustomobject]@{
            Type = 'NumericRange'
            WinDefault = [ordered]@{
                ACValue = 80
                DCValue = 60
            }
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'ACValue 80 -DCValue 60'
    }

    It 'returns OffParam via WinDefault $true fallback when selectedParam is unrecognized' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'SomethingElse'
        }
        $manifest = [pscustomobject]@{
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
            WinDefault = $true
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'Enable'
    }

    It 'returns OnParam via WinDefault $false fallback when selectedParam is unrecognized' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'SomethingElse'
        }
        $manifest = [pscustomobject]@{
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
            WinDefault = $false
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest

        $result | Should -Be 'Disable'
    }

    It 'returns null when selectedParam matches neither OnParam nor OffParam and no WinDefault exists' {
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'SomethingElse'
        }
        $manifest = [pscustomobject]@{
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
        }

        $result = Get-DirectUndoCommandForEntry -Entry $entry -ManifestEntry $manifest 3>$null

        $result | Should -BeNullOrEmpty
    }
}

Describe 'Get-DirectUndoCommandLineForEntry' {
    It 'returns the explicit counterpart command line when CounterpartFunction is declared' {
        $manifest = @(
            [pscustomobject]@{
                Function = 'EnableFeature'
                Type = 'Toggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
                CounterpartFunction = 'DisableFeature'
                Default = $true
            },
            [pscustomobject]@{
                Function = 'DisableFeature'
                Type = 'Toggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
                Default = $false
            }
        )
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'Enable'
        }

        $result = Get-DirectUndoCommandLineForEntry -Entry $entry -ManifestEntry $manifest[0] -Manifest $manifest

        $result | Should -Be 'DisableFeature -Disable'
    }

    It 'falls back to the legacy same-function inverse command line when no counterpart exists' {
        $manifest = [pscustomobject]@{
            Function = 'EnableFeature'
            Type = 'Toggle'
            OnParam = 'Enable'
            OffParam = 'Disable'
            Default = $true
        }
        $entry = [pscustomobject]@{
            Restorable = $true
            RecoveryLevel = 'Direct'
            ToggleParam = 'Enable'
        }

        $result = Get-DirectUndoCommandLineForEntry -Entry $entry -ManifestEntry $manifest -Manifest @($manifest)

        $result | Should -Be 'EnableFeature -Disable'
    }
}

Describe 'Test-ShouldRecommendRestorePoint' {
    It 'returns ShouldRecommend false for safe tweaks' {
        $tweaks = @(
            [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; RequiresRestart = $false; RecoveryLevel = 'Direct' }
        )

        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks $tweaks

        $result.ShouldRecommend | Should -Be $false
        $result.Severity | Should -Be 'None'
    }

    It 'recommends for restart-requiring tweaks' {
        $tweaks = @(
            [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; RequiresRestart = $true; RecoveryLevel = 'Direct' }
        )

        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks $tweaks

        $result.ShouldRecommend | Should -Be $true
        $result.Severity | Should -Be 'Recommended'
        $result.RestartRequiredCount | Should -Be 1
    }

    It 'strongly recommends for Advanced tier tweaks' {
        $tweaks = @(
            [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Advanced'; RequiresRestart = $false; RecoveryLevel = 'Direct' }
        )

        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks $tweaks

        $result.ShouldRecommend | Should -Be $true
        $result.Severity | Should -Be 'StronglyRecommended'
        $result.AdvancedTierCount | Should -Be 1
    }

    It 'strongly recommends for high-risk tweaks' {
        $tweaks = @(
            [pscustomobject]@{ Risk = 'High'; PresetTier = 'Basic'; RequiresRestart = $false; RecoveryLevel = 'Direct' }
        )

        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks $tweaks

        $result.ShouldRecommend | Should -Be $true
        $result.Severity | Should -Be 'StronglyRecommended'
        $result.HighRiskCount | Should -Be 1
    }

    It 'strongly recommends for non-Direct recovery' {
        $tweaks = @(
            [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; RequiresRestart = $false; RecoveryLevel = 'Manual' }
        )

        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks $tweaks

        $result.ShouldRecommend | Should -Be $true
        $result.Severity | Should -Be 'StronglyRecommended'
        $result.NonDirectRecoveryCount | Should -Be 1
    }

    It 'returns false for empty input' {
        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks @()

        $result.ShouldRecommend | Should -Be $false
    }

    It 'includes reasons as sorted list' {
        $tweaks = @(
            [pscustomobject]@{ Risk = 'High'; PresetTier = 'Advanced'; RequiresRestart = $true; RecoveryLevel = 'Manual' }
        )

        $result = Test-ShouldRecommendRestorePoint -SelectedTweaks $tweaks

        $result.Reasons.Count | Should -BeGreaterThan 0
        $result.Reasons | Should -Contain 'high-risk changes'
    }
}
