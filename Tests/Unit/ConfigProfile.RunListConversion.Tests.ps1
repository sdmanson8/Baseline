Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')

    . (Join-Path $repoRoot 'Module/SharedHelpers/Manifest.Helpers.ps1')
    . (Join-Path $repoRoot 'Module/SharedHelpers/Json.Helpers.ps1')
    . (Join-Path $repoRoot 'Module/SharedHelpers/ConfigProfile.Helpers.ps1')

    function script:NewToggleManifestEntry {
        param([string]$Function, [string]$OnParam = 'Enable', [string]$OffParam = 'Disable', [string]$Risk = 'Low')
        return [pscustomobject]@{
            Function   = $Function
            Name       = $Function
            Type       = 'Toggle'
            Category   = 'Test'
            Risk       = $Risk
            Restorable = $true
            RequiresRestart = $false
            OnParam    = $OnParam
            OffParam   = $OffParam
            Default    = $false
        }
    }

    function script:NewChoiceManifestEntry {
        param([string]$Function, [object[]]$Options, [object[]]$DisplayOptions = $null, [object]$Default = $null)
        return [pscustomobject]@{
            Function       = $Function
            Name           = $Function
            Type           = 'Choice'
            Category       = 'Test'
            Risk           = 'Low'
            Restorable     = $true
            RequiresRestart= $false
            Options        = $Options
            DisplayOptions = if ($DisplayOptions) { $DisplayOptions } else { $Options }
            Default        = $Default
            ExtraArgs      = @{ Mode = 'Standard' }
        }
    }
}

Describe 'ConvertFrom-BaselineConfigProfileToRunList' {
    It 'projects Toggle entries to runlist hashtables with manifest metadata' {
        $manifest = @(
            (NewToggleManifestEntry -Function 'DisableTelemetry' -OnParam 'Enable' -OffParam 'Disable' -Risk 'Medium'),
            (NewToggleManifestEntry -Function 'OtherTweak'       -OnParam 'On'     -OffParam 'Off')
        )
        $importedProfile = [pscustomobject]@{
            Schema = 'Baseline.ConfigProfile'
            Entries = @(
                [pscustomobject]@{ Function = 'DisableTelemetry'; Type = 'Toggle'; Param = 'Enable'; Category = 'Privacy' }
            )
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 1
        $r = $rows[0]
        $r['Function']    | Should -Be 'DisableTelemetry'
        $r['Type']        | Should -Be 'Toggle'
        $r['Selection']   | Should -Be 'Enable'
        $r['ToggleParam'] | Should -Be 'Enable'
        $r['OnParam']     | Should -Be 'Enable'
        $r['OffParam']    | Should -Be 'Disable'
        $r['Risk']        | Should -Be 'Medium'
        $r['IsChecked']   | Should -BeTrue
        $r['Index']       | Should -Be 0
    }

    It 'matches Function names case-insensitively' {
        $manifest = @((NewToggleManifestEntry -Function 'DisableTelemetry'))
        $importedProfile = [pscustomobject]@{
            Entries = @([pscustomobject]@{ Function = 'disabletelemetry'; Type = 'Toggle'; Param = 'Enable' })
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 1
        $rows[0]['Function'] | Should -Be 'disabletelemetry'
    }

    It 'skips entries whose Function is not present in the manifest' {
        $manifest = @((NewToggleManifestEntry -Function 'KnownTweak'))
        $importedProfile = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Function = 'KnownTweak';   Type = 'Toggle'; Param = 'Enable' },
                [pscustomobject]@{ Function = 'UnknownTweak'; Type = 'Toggle'; Param = 'Enable' }
            )
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 1
        $rows[0]['Function'] | Should -Be 'KnownTweak'
    }

    It 'skips Toggle entries that are missing the Param value' {
        $manifest = @((NewToggleManifestEntry -Function 'DisableTelemetry'))
        $importedProfile = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Function = 'DisableTelemetry'; Type = 'Toggle' }
            )
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 0
    }

    It 'projects Choice entries by SelectedValue against manifest Options' {
        $manifest = @((NewChoiceManifestEntry -Function 'PowerPlan' -Options @('Balanced','HighPerf','PowerSaver') -Default 'Balanced'))
        $importedProfile = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Function = 'PowerPlan'; Type = 'Choice'; SelectedValue = 'HighPerf' }
            )
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 1
        $rows[0]['Type']          | Should -Be 'Choice'
        $rows[0]['SelectedIndex'] | Should -Be 1
        $rows[0]['SelectedValue'] | Should -Be 'HighPerf'
        $rows[0]['Value']         | Should -Be 'HighPerf'
        $rows[0]['DefaultValue']  | Should -Be 'Balanced'
        $rows[0]['ExtraArgs']     | Should -Not -BeNullOrEmpty
    }

    It 'skips Choice entries whose SelectedValue is not in the manifest Options' {
        $manifest = @((NewChoiceManifestEntry -Function 'PowerPlan' -Options @('Balanced','HighPerf')))
        $importedProfile = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Function = 'PowerPlan'; Type = 'Choice'; SelectedValue = 'NotARealOption' }
            )
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 0
    }

    It 'returns an empty array when the profile has no Entries property' {
        $manifest = @((NewToggleManifestEntry -Function 'X'))
        $importedProfile = [pscustomobject]@{ Schema = 'Baseline.ConfigProfile' }
        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 0
    }

    It 'preserves the order of Entries in the imported profile' {
        $manifest = @(
            (NewToggleManifestEntry -Function 'AuthHardening'    -OnParam 'On'     -OffParam 'Off'),
            (NewToggleManifestEntry -Function 'DisableTelemetry' -OnParam 'Enable' -OffParam 'Disable')
        )
        $importedProfile = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Function = 'DisableTelemetry'; Type = 'Toggle'; Param = 'Enable' },
                [pscustomobject]@{ Function = 'AuthHardening';    Type = 'Toggle'; Param = 'On' }
            )
        }

        $rows = ConvertFrom-BaselineConfigProfileToRunList -Profile $importedProfile -Manifest $manifest
        @($rows).Count | Should -Be 2
        @($rows | ForEach-Object { $_['Function'] })    | Should -Be @('DisableTelemetry','AuthHardening')
        @($rows | ForEach-Object { $_['ToggleParam'] }) | Should -Be @('Enable','On')
        # Manifest indexes should reflect the manifest position, not the entry order.
        @($rows | ForEach-Object { $_['Index'] }) | Should -Be @(1, 0)
    }
}
