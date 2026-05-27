Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath

    function Test-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }

    foreach ($sourcePath in @(
        (Join-Path $PSScriptRoot '../../Module/GUI/TweakAvailability.ps1')
        (Join-Path $PSScriptRoot '../../Module/GUI/PreviewBuilders.ps1')
        (Join-Path $PSScriptRoot '../../Module/GUI/PresetApplication.ps1')
    )) {
        $sourceText = Get-BaselineTestSourceText -Path $sourcePath
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            if ($fn.Name -in @(
                'Get-GuiTweakAvailability',
                'Test-GuiTweakAvailableOnCurrentSystem',
                'Get-GuiTweakUnavailableReason',
                'Get-GuiIndexedControlState',
                'Get-SelectedTweakRunList',
                'Clear-GuiSelectableControlState',
                'Apply-TabPresetSelections'
            )) {
                Invoke-Expression $fn.Extent.Text
            }
        }
    }

    function Get-GuiExplicitSelectionDefinition {
        param([string]$FunctionName)
        if ($script:ExplicitSelectionDefinitions -and $script:ExplicitSelectionDefinitions.ContainsKey($FunctionName)) {
            return $script:ExplicitSelectionDefinitions[$FunctionName]
        }
        return $null
    }

    function Remove-GuiExplicitSelectionDefinition {
        param([string]$FunctionName)
        $script:RemovedExplicitSelections += [string]$FunctionName
        if ($script:ExplicitSelectionDefinitions -and $script:ExplicitSelectionDefinitions.ContainsKey($FunctionName)) {
            [void]$script:ExplicitSelectionDefinitions.Remove($FunctionName)
        }
    }

    function Get-TweakVisualMetadata {
        param([object]$Tweak, [object]$StateSource)
        return [pscustomobject]@{
            TypeKind = [string]$Tweak.Type
            TypeLabel = [string]$Tweak.Type
            TypeTone = 'neutral'
            TypeBadgeLabel = [string]$Tweak.Type
            StateLabel = 'Test state'
            StateTone = 'neutral'
            StateDetail = ''
            MatchesDesired = $false
            ScenarioTags = @()
            ReasonIncluded = ''
            BlastRadius = ''
            IsRemoval = $false
        }
    }
}

Describe 'GUI availability selection gates' {
    BeforeEach {
        $script:RemovedExplicitSelections = @()
        $script:ExplicitSelectionDefinitions = @{}
        $script:TweakManifest = @()
        $script:Controls = @{}
    }

    It 'builds the GUI run list from the live control hashtable' {
        $script:ExplicitSelectionDefinitions['DemoToggle'] = [pscustomobject]@{
            Function = 'DemoToggle'
            Type = 'Toggle'
            State = 'Off'
        }
        $script:TweakManifest = @(
            [pscustomobject]@{
                Name = 'Demo toggle'
                Function = 'DemoToggle'
                Type = 'Toggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
                Category = 'Testing'
                Risk = 'Low'
                Restorable = $true
                RequiresRestart = $false
                Impact = ''
                PresetTier = 'Basic'
                Default = $true
                Availability = [pscustomobject]@{
                    Available = $true
                    Reason = ''
                }
            }
        )
        $script:Controls[0] = [pscustomobject]@{
            IsEnabled = $true
            IsChecked = $false
        }

        $selected = @(Get-SelectedTweakRunList)

        $selected | Should -HaveCount 1
        $selected[0].Function | Should -Be 'DemoToggle'
        $selected[0].ToggleParam | Should -Be 'Disable'
    }

    It 'keeps unavailable selected controls out of the GUI run list' {
        $script:ExplicitSelectionDefinitions['Windows11Only'] = [pscustomobject]@{
            Function = 'Windows11Only'
            Type = 'Toggle'
            State = 'On'
        }

        $manifest = @(
            [pscustomobject]@{
                Name = 'Windows 11 only'
                Function = 'Windows11Only'
                Type = 'Toggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
                Availability = [pscustomobject]@{
                    Available = $false
                    Reason = 'Not available on Windows 10.'
                }
            }
        )
        $controls = @(
            [pscustomobject]@{
                IsEnabled = $true
                IsChecked = $true
            }
        )

        @(Get-SelectedTweakRunList -TweakManifest $manifest -Controls $controls) | Should -HaveCount 0
    }

    It 'lets system availability override explicit preset selections' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Name = 'Windows 11 only'
                Function = 'Windows11Only'
                Type = 'Action'
                Availability = [pscustomobject]@{
                    Available = $false
                    Reason = 'Not available on Windows 10.'
                }
            }
        )
        $script:Controls = @(
            [pscustomobject]@{
                IsEnabled = $true
                IsChecked = $true
            }
        )

        $presetContext = [pscustomobject]@{
            UsesExplicitPreset = $true
            PresetEntries = @{
                Windows11Only = [pscustomobject]@{
                    Function = 'Windows11Only'
                    Type = 'Action'
                    Run = $true
                }
            }
            PresetDefinition = [pscustomobject]@{
                Name = 'Advanced'
                Tier = 'Advanced'
            }
        }

        $stats = Apply-TabPresetSelections -PresetContext $presetContext -TestTweakMatchesPresetTierScript { param($Tweak, $Tier) $true } -SyncLinkedStateCapture {}

        $stats.SelectedCount | Should -Be 0
        $script:Controls[0].IsChecked | Should -BeFalse
        $script:Controls[0].IsEnabled | Should -BeFalse
        $script:RemovedExplicitSelections | Should -Contain 'Windows11Only'
    }

    It 'keeps non-executable selected controls out of the GUI run list' {
        $manifest = @(
            [pscustomobject]@{
                Name = 'Widgets'
                Function = 'TaskbarWidgets'
                Type = 'Toggle'
                OnParam = 'Show'
                OffParam = 'Hide'
                Availability = [pscustomobject]@{
                    Available = $true
                    Reason = ''
                }
                SupportsExecution = $false
                SupportsExecutionReason = 'Widgets requires the Windows Web Experience Pack to be installed.'
            }
        )
        $controls = @(
            [pscustomobject]@{
                IsEnabled = $true
                IsChecked = $true
            }
        )

        @(Get-SelectedTweakRunList -TweakManifest $manifest -Controls $controls) | Should -HaveCount 0
        Get-GuiTweakUnavailableReason -Tweak $manifest[0] | Should -Match 'Web Experience Pack'
    }

    It 'lets execution support override explicit preset selections' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Name = 'Widgets'
                Function = 'TaskbarWidgets'
                Type = 'Action'
                Availability = [pscustomobject]@{
                    Available = $true
                    Reason = ''
                }
                SupportsExecution = $false
                SupportsExecutionReason = 'Widgets requires the Windows Web Experience Pack to be installed.'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{
                IsEnabled = $true
                IsChecked = $true
            }
        )

        $presetContext = [pscustomobject]@{
            UsesExplicitPreset = $true
            PresetEntries = @{
                TaskbarWidgets = [pscustomobject]@{
                    Function = 'TaskbarWidgets'
                    Type = 'Action'
                    Run = $true
                }
            }
            PresetDefinition = [pscustomobject]@{
                Name = 'Advanced'
                Tier = 'Advanced'
            }
        }

        $stats = Apply-TabPresetSelections -PresetContext $presetContext -TestTweakMatchesPresetTierScript { param($Tweak, $Tier) $true } -SyncLinkedStateCapture {}

        $stats.SelectedCount | Should -Be 0
        $script:Controls[0].IsChecked | Should -BeFalse
        $script:Controls[0].IsEnabled | Should -BeFalse
        $script:RemovedExplicitSelections | Should -Contain 'TaskbarWidgets'
    }
}
