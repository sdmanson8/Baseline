Set-StrictMode -Version Latest

BeforeAll {
    $script:RestoreSelectionStatePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState/Restore-GuiSettingsSnapshot/RestoreExplicitSelectionState.ps1'

    function Test-GuiObjectField {
        param(
            [object]$Object,
            [string]$FieldName
        )

        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }

    function Set-GuiExplicitSelectionDefinition {
        param(
            [Parameter(Mandatory = $true)][string]$FunctionName,
            [Parameter(Mandatory = $true)][object]$Definition
        )

        $script:RestoredDefinitions[$FunctionName] = $Definition
        [void]$script:ExplicitPresetSelections.Add($FunctionName)
    }

    function Get-GuiExplicitSelectionDefinition {
        param([string]$FunctionName)

        if ($script:RestoredDefinitions -and $script:RestoredDefinitions.ContainsKey($FunctionName)) {
            return $script:RestoredDefinitions[$FunctionName]
        }

        return $null
    }

    function Invoke-RestoreExplicitSelectionStateForTest {
        param(
            [Parameter(Mandatory = $true)][object]$Snapshot
        )

        $controlStates = @{}
        foreach ($entry in @($Snapshot.Controls)) {
            if ($entry -and (Test-GuiObjectField -Object $entry -FieldName 'Function')) {
                $controlStates[[string]$entry.Function] = $entry
            }
        }

        . $script:RestoreSelectionStatePath
    }
}

Describe 'GUI session selection restore' {
    BeforeEach {
        $script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $script:RestoredDefinitions = @{}
        $script:Controls = @()
    }

    It 'rebuilds missing selection definitions from saved control state' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'DemoChoice'
                Type = 'Choice'
                Options = @('Install', 'Uninstall')
            },
            [pscustomobject]@{
                Function = 'DemoToggle'
                Type = 'Toggle'
            },
            [pscustomobject]@{
                Function = 'DemoAction'
                Type = 'Action'
            },
            [pscustomobject]@{
                Function = 'DemoDate'
                Type = 'Date'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{ SelectedIndex = -1 },
            [pscustomobject]@{ IsChecked = $false },
            [pscustomobject]@{ IsChecked = $false },
            [pscustomobject]@{ IsChecked = $false; SelectedDate = $null }
        )
        $snapshot = [pscustomobject]@{
            Controls = @(
                [pscustomobject]@{ Function = 'DemoChoice'; SelectedIndex = 1; SelectedValue = 'Uninstall' },
                [pscustomobject]@{ Function = 'DemoToggle'; IsChecked = $true },
                [pscustomobject]@{ Function = 'DemoAction'; IsChecked = $true },
                [pscustomobject]@{ Function = 'DemoDate'; IsChecked = $true; SelectedDate = '2026-05-19' }
            )
        }

        Invoke-RestoreExplicitSelectionStateForTest -Snapshot $snapshot

        $script:RestoredDefinitions['DemoChoice'].Type | Should -Be 'Choice'
        $script:RestoredDefinitions['DemoChoice'].Value | Should -Be 'Uninstall'
        $script:RestoredDefinitions['DemoToggle'].State | Should -Be 'On'
        $script:RestoredDefinitions['DemoAction'].Run | Should -BeTrue
        $script:RestoredDefinitions['DemoDate'].Run | Should -BeTrue
        $script:RestoredDefinitions['DemoDate'].Value | Should -Be '2026-05-19'
    }

    It 'uses legacy explicit selection names to preserve off-toggle selections' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'SelectedOffToggle'
                Type = 'Toggle'
            },
            [pscustomobject]@{
                Function = 'PlainUncheckedToggle'
                Type = 'Toggle'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{ IsChecked = $true },
            [pscustomobject]@{ IsChecked = $true }
        )
        $snapshot = [pscustomobject]@{
            ExplicitSelections = @('SelectedOffToggle')
            Controls = @(
                [pscustomobject]@{ Function = 'SelectedOffToggle'; IsChecked = $false },
                [pscustomobject]@{ Function = 'PlainUncheckedToggle'; IsChecked = $false }
            )
        }

        Invoke-RestoreExplicitSelectionStateForTest -Snapshot $snapshot

        $script:RestoredDefinitions['SelectedOffToggle'].State | Should -Be 'Off'
        $script:RestoredDefinitions.ContainsKey('PlainUncheckedToggle') | Should -BeFalse
    }

    It 'keeps explicit selection definitions authoritative over control state' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'DemoChoice'
                Type = 'Choice'
                Options = @('Install', 'Uninstall')
            }
        )
        $script:Controls = @(
            [pscustomobject]@{ SelectedIndex = -1 }
        )
        $snapshot = [pscustomobject]@{
            ExplicitSelectionDefinitions = @(
                [pscustomobject]@{
                    Function = 'DemoChoice'
                    Type = 'Choice'
                    Value = 'Install'
                }
            )
            Controls = @(
                [pscustomobject]@{ Function = 'DemoChoice'; SelectedIndex = 1; SelectedValue = 'Uninstall' }
            )
        }

        Invoke-RestoreExplicitSelectionStateForTest -Snapshot $snapshot

        $script:RestoredDefinitions['DemoChoice'].Value | Should -Be 'Install'
    }

    It 'applies explicit selection definitions to controls when saved control state is missing' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'DemoChoice'
                Type = 'Choice'
                Options = @('Install', 'Uninstall')
            },
            [pscustomobject]@{
                Function = 'DemoToggle'
                Type = 'Toggle'
            },
            [pscustomobject]@{
                Function = 'DemoAction'
                Type = 'Action'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{ SelectedIndex = -1 },
            [pscustomobject]@{ IsChecked = $false },
            [pscustomobject]@{ IsChecked = $false }
        )
        $snapshot = [pscustomobject]@{
            ExplicitSelectionDefinitions = @(
                [pscustomobject]@{
                    Function = 'DemoChoice'
                    Type = 'Choice'
                    Value = 'Uninstall'
                },
                [pscustomobject]@{
                    Function = 'DemoToggle'
                    Type = 'Toggle'
                    State = 'On'
                },
                [pscustomobject]@{
                    Function = 'DemoAction'
                    Type = 'Action'
                    Run = $true
                }
            )
            Controls = @()
        }

        Invoke-RestoreExplicitSelectionStateForTest -Snapshot $snapshot

        $script:Controls[0].SelectedIndex | Should -Be 1
        $script:Controls[1].IsChecked | Should -BeTrue
        $script:Controls[2].IsChecked | Should -BeTrue
    }
}
