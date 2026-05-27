Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    <#
        .SYNOPSIS
    #>

    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    <#
        .SYNOPSIS
    #>
    function Get-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $null }; if ($Object -is [System.Collections.IDictionary]) { return $Object[$FieldName] }; if ($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) { return $Object.PSObject.Properties[$FieldName].Value }; return $null }
    $densityPath = Join-Path $PSScriptRoot '../../Module/GUI/UIDensity.ps1'
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory.ps1'
    $splitRoot = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory'
    $filePaths = @(
        $densityPath
        $filePath
        (Join-Path $splitRoot 'RowStateDefaults.ps1')
        (Join-Path $splitRoot 'MetadataDetails.ps1')
        (Join-Path $splitRoot 'ControlFactories.ps1')
    )
    $script:FileContent = @($filePaths | ForEach-Object { Get-BaselineTestSourceText -Path $_ }) -join "`n"
    $script:FunctionTextByName = @{}
    foreach ($path in $filePaths) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            $script:FunctionTextByName[$fn.Name] = $fn.Extent.Text
            if ($fn.Name -in @('Get-TweakRowFactoryRuntimeCommand', 'Test-TweakRowFactoryTweakAvailable', 'Get-GameModePlanEntryForTweak', 'Get-ToggleInitialCheckedState', 'Get-ActionInitialCheckedState', 'Get-ChoiceInitialSelectedIndex', 'ConvertTo-GuiDateTimeValue', 'Get-DateInitialRunState', 'Get-DateInitialSelectedDate')) {
                Invoke-Expression $fn.Extent.Text
            }
        }
    }

    <#
        .SYNOPSIS
    #>
    function Get-GameModePlan {
        return @($script:TestGameModePlan)
    }

    <#
        .SYNOPSIS
    #>

    function Get-GuiExplicitSelectionDefinition {
        param([string]$FunctionName)

        if ($script:ExplicitSelectionDefinitions.ContainsKey($FunctionName)) {
            return $script:ExplicitSelectionDefinitions[$FunctionName]
        }

        return $null
    }
}

Describe 'Tweak row content pins' {
    It 'routes tweak-row opacity updates through Write-SwallowedException' {
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Update-TweakRowState\.CardOpacity'''
    }

    It 'routes hover and focus chrome updates through Write-SwallowedException' {
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.Add_MouseEnter'''
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.Add_MouseLeave'''
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.Add_PreviewMouseLeftButtonDown'''
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.Add_PreviewMouseLeftButtonUp'''
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.Add_GotKeyboardFocus'''
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.Add_LostKeyboardFocus'''
        $script:FileContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''TweakRowFactory\.Build-TweakRowCard\.UpdateChrome'''
    }

    It 'separates tweak cards with soft elevation instead of hard shadow offsets' {
        $script:FileContent | Should -Match '\$shadow\.ShadowDepth = 0'
        $script:FileContent | Should -Match '\$shadow\.Opacity = if \(\$isLight\) \{ 0\.04 \} else \{ 0\.18 \}'
        $script:FileContent | Should -Match '\$shadow\.BlurRadius = if \(\$isLight\) \{ 8 \} else \{ 18 \}'
    }

    It 'uses divider-only row chrome instead of boxed row borders' {
        $script:FileContent | Should -Match 'RowDivider\s+= \[System\.Windows\.Thickness\]::new\(0, 0, 0, 1\)'
        $script:FileContent | Should -Match 'RowDividerFocus\s+= \[System\.Windows\.Thickness\]::new\(0, 0, 0, 2\)'
        $script:FileContent | Should -Match 'Thickness1\s+= if \(\$isLight\) \{ \$Script:T\.CardBorder \} else \{ \$Script:T\.RowDivider \}'
        $script:FileContent | Should -Match 'Thickness2\s+= if \(\$isLight\) \{ \$Script:T\.CardBorderFocus \} else \{ \$Script:T\.RowDividerFocus \}'
        $script:FileContent | Should -Match 'AccentBorder\s+= \[System\.Windows\.Thickness\]::new\(3, 0, 0, 1\)'
        $script:FileContent | Should -Match 'RowCardPadding\s+= \[System\.Windows\.Thickness\]::new\(16, 12, 16, 12\)'
        $script:FileContent | Should -Match 'RowCardPadding\s+= \[System\.Windows\.Thickness\]::new\(10, 7, 10, 7\)'
        $script:FileContent | Should -Match 'RowCardPadding\s+= \[System\.Windows\.Thickness\]::new\(7, 4, 7, 4\)'
        $script:FunctionTextByName['Build-TweakRow'] | Should -Match 'RowContextSharedDensity'
        $script:FunctionTextByName['Build-TweakRow'] | Should -Match 'NameLineHeight'
    }

    It 'does not render per-row reset actions in the primary row header' {
        $script:FileContent | Should -Not -Match '-ActionButton \$ResetButton'
        $script:FunctionTextByName['New-ToggleLikeHeaderGrid'] | Should -Not -Match 'ResetButton'
        $script:FunctionTextByName['New-ChoiceHeaderGrid'] | Should -Not -Match 'ResetButton'
        $script:FileContent | Should -Not -Match 'New-ToggleLikeHeaderGrid[^\r\n]+-ResetButton'
        $script:FileContent | Should -Not -Match 'New-ChoiceHeaderGrid[^\r\n]+-ResetButton'
    }

    It 'keeps tweak metadata inline like the recovered stash' {
        $detailsFunction = $script:FunctionTextByName['Add-TweakMetadataDetails']
        $script:FileContent | Should -Match 'Set-TweakSearchHighlightedTextBlock'
        $detailsFunction | Should -Not -Match '\$detailsPanel'
        $detailsFunction | Should -Not -Match "Get-UxString -Key 'GuiDetailsButton' -Fallback 'Details'"
        $detailsFunction | Should -Not -Match "Get-UxString -Key 'GuiShowDetails' -Fallback 'Show details'"
        $detailsFunction | Should -Not -Match "Get-UxString -Key 'GuiHideDetails' -Fallback 'Hide details'"
        $detailsFunction | Should -Not -Match 'Add-TweakDetailLine'
        $detailsFunction | Should -Match '\[void\]\(\$Container\.Children\.Add\(\$descriptionTextBlock\)\)'
        $detailsFunction | Should -Match 'New-TweakMetadataChipPanel -Metadata \$RowContext\.Metadata -IncludeType:\$false -IncludeState:\$false -IncludeRestart:\$false -IncludeRestorable:\$false -IncludeRecoveryLevel:\$true .* -IncludeScenarioTags:\$false'
        $detailsFunction | Should -Match '-not \[bool\]\$RowContext\.Metadata\.MatchesDesired -and -not \[string\]::IsNullOrWhiteSpace\(\[string\]\$RowContext\.Metadata\.BlastRadius\)'
        $script:FunctionTextByName['Add-TweakScenarioTagsToDetailsPanel'] | Should -Not -Match 'New-TweakMetadataChipPanel'
        $script:FunctionTextByName['Add-TweakScenarioTagsToDetailsPanel'] | Should -Match '\$tagBorder = .*AccentBlue'
        $script:FunctionTextByName['Add-TweakScenarioTagsToDetailsPanel'] | Should -Match '\$tagForeground = .*AccentHover'
        $script:FunctionTextByName['Add-TweakScenarioTagsToDetailsPanel'] | Should -Match "Get-UxString -Key 'GuiTweakChipTooltipScenarioTag'"
        $script:FunctionTextByName['Add-TweakScenarioTagsToDetailsPanel'] | Should -Match "Get-UxString -Key 'GuiTweakChipMoreFormat'"
        $script:FunctionTextByName['Add-TweakScenarioTagsToDetailsPanel'] | Should -Not -Match "Get-UxString -Key 'GuiSectionTags' -Fallback 'Tags'"
        $script:FunctionTextByName['Add-TweakWhyBlockDetails'] | Should -Match 'Add-TweakScenarioTagsToDetailsPanel -DetailsHost \$whyBlock\.Tag -RowContext \$RowContext'
        $script:FunctionTextByName['New-ToggleTweakRow'] | Should -Match '\$statusContext\.WhyBlock -and \$statusContext\.WhyBlock\.Tag'
        $script:FunctionTextByName['New-ToggleTweakRow'] | Should -Match 'Add-TweakScenarioTagsToDetailsPanel -DetailsHost \$statusContext\.WhyBlock\.Tag -RowContext \$RowContext'
        $script:FunctionTextByName['New-ToggleTweakRow'] | Should -Match '\[void\]\(\$leftStack\.Children\.Add\(\$statusContext\.WhyBlock\.Tag\)\)'
    }

    It 'reuses row metadata for toggle status state' {
        $script:FunctionTextByName['Get-ToggleDisplayStateFromRowMetadata'] | Should -Match 'StateLabel'
        $script:FunctionTextByName['Get-ToggleDisplayStateFromRowMetadata'] | Should -Match 'DetectedState'
        $script:FunctionTextByName['New-ToggleStatusRow'] | Should -Match 'Get-ToggleDisplayStateFromRowMetadata -RowContext \$RowContext'
        $script:FunctionTextByName['New-ToggleStatusRow'] | Should -Match 'if \(-not \$toggleDisplay\)'
        $script:FunctionTextByName['New-ToggleStatusRow'] | Should -Match 'Get-GuiToggleDisplayState -Tweak \$Tweak -StateSource \$CheckBox'
        $script:FileContent | Should -Not -Match 'Add-Member -MemberType NoteProperty -Name ''_StateLabel'''
        $script:FileContent | Should -Match 'TweakVisualStateByFunction'
    }

    It 'labels manifest default chips as Baseline defaults, not Windows defaults' {
        $script:FileContent | Should -Match "GuiTweakChipBaselineDefaultFormat"
        $script:FileContent | Should -Match "Baseline default: \{0\}"
        $script:FileContent | Should -Match "not a Windows default"
        $script:FileContent | Should -Not -Match "'Default: \{0\}'"
    }
}

Describe 'Tweak row initial state recovery' {
    BeforeEach {
        $script:GameMode = $false
        $script:TestGameModePlan = @()
        $script:ExplicitSelectionDefinitions = @{}
        $script:Controls = @{}
    }

    Describe 'Get-ToggleInitialCheckedState' {
        It 'uses explicit preset On state when the tab control has not been built yet' {
            $script:ExplicitSelectionDefinitions['DemoToggle'] = [pscustomobject]@{
                Function = 'DemoToggle'
                Type = 'Toggle'
                State = 'On'
                Source = 'Preset'
            }

            $result = Get-ToggleInitialCheckedState -Index 42 -Tweak ([pscustomobject]@{
                Function = 'DemoToggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
            })

            $result | Should -BeTrue
        }

        It 'uses explicit preset Off state when the tab control has not been built yet' {
            $script:ExplicitSelectionDefinitions['DemoToggle'] = [pscustomobject]@{
                Function = 'DemoToggle'
                Type = 'Toggle'
                State = 'Off'
                Source = 'Preset'
            }

            $result = Get-ToggleInitialCheckedState -Index 42 -Tweak ([pscustomobject]@{
                Function = 'DemoToggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
            })

            $result | Should -BeFalse
        }

        It 'keeps game mode plan precedence over explicit preset state' {
            $script:GameMode = $true
            $script:TestGameModePlan = @(
                [pscustomobject]@{
                    Function = 'DemoToggle'
                    ToggleParam = 'Enable'
                }
            )
            $script:ExplicitSelectionDefinitions['DemoToggle'] = [pscustomobject]@{
                Function = 'DemoToggle'
                Type = 'Toggle'
                State = 'Off'
                Source = 'Preset'
            }

            $result = Get-ToggleInitialCheckedState -Index 42 -Tweak ([pscustomobject]@{
                Function = 'DemoToggle'
                OnParam = 'Enable'
                OffParam = 'Disable'
            })

            $result | Should -BeTrue
        }
    }

    Describe 'New-ToggleLikeHeaderGrid accessibility' {
        It 'binds explicit tweak descriptions into AutomationProperties.HelpText' {
            $script:FunctionTextByName['New-ToggleLikeHeaderGrid'] | Should -Match '\[System\.Windows\.Automation\.AutomationProperties\]::SetHelpText\(\$CheckBox, \$helpText\)'
            $script:FunctionTextByName['New-ToggleLikeHeaderGrid'] | Should -Match 'Get-UxString -Key \$Tweak\.DescriptionKey -Fallback \$Tweak\.Description'
            $script:FunctionTextByName['New-ToggleLikeHeaderGrid'] | Should -Match '\[string\]\$Tweak\.Description'
        }
    }

    Describe 'Get-ActionInitialCheckedState' {
        It 'uses explicit preset action selections when the tab control has not been built yet' {
            $script:ExplicitSelectionDefinitions['DemoAction'] = [pscustomobject]@{
                Function = 'DemoAction'
                Type = 'Action'
                Run = $true
                Source = 'Preset'
            }

            $result = Get-ActionInitialCheckedState -Index 7 -Tweak ([pscustomobject]@{
                Function = 'DemoAction'
            })

            $result | Should -BeTrue
        }
    }

    Describe 'Get-ChoiceInitialSelectedIndex' {
        It 'prefers explicit preset choices over stale placeholder state' {
            $script:Controls[3] = [pscustomobject]@{
                SelectedIndex = 0
            }
            $script:ExplicitSelectionDefinitions['DemoChoice'] = [pscustomobject]@{
                Function = 'DemoChoice'
                Type = 'Choice'
                Value = 'Uninstall'
                Source = 'Preset'
            }

            $rowContext = [pscustomobject]@{
                GetExplicitSelectionDefinition = {
                    param([string]$FunctionName)

                    if ($script:ExplicitSelectionDefinitions.ContainsKey($FunctionName)) {
                        return $script:ExplicitSelectionDefinitions[$FunctionName]
                    }

                    return $null
                }
            }

            $result = Get-ChoiceInitialSelectedIndex -Index 3 -Tweak ([pscustomobject]@{
                Function = 'DemoChoice'
            }) -ChoiceOptions @('Install', 'Uninstall') -RowContext $rowContext

            $result | Should -Be 1
        }

        It 'falls back to placeholder choice state when no explicit preset exists' {
            $script:Controls[3] = [pscustomobject]@{
                SelectedIndex = 0
            }

            $rowContext = [pscustomobject]@{
                GetExplicitSelectionDefinition = {
                    param([string]$FunctionName)
                    return $null
                }
            }

            $result = Get-ChoiceInitialSelectedIndex -Index 3 -Tweak ([pscustomobject]@{
                Function = 'DemoChoice'
            }) -ChoiceOptions @('Install', 'Uninstall') -RowContext $rowContext

            $result | Should -Be 0
        }
    }

    Describe 'Get-DateInitialRunState' {
        It 'honours explicit preset date selections when the tab control has not been built yet' {
            $script:ExplicitSelectionDefinitions['DemoDate'] = [pscustomobject]@{
                Function = 'DemoDate'
                Type = 'Date'
                Run = $true
                Value = '2025-04-08'
                DateParam = 'StartDate'
                Source = 'Preset'
            }

            $result = Get-DateInitialRunState -Index 9 -Tweak ([pscustomobject]@{
                Function = 'DemoDate'
                DateParam = 'StartDate'
            })

            $result | Should -BeTrue
        }

        It 'keeps unchecked explicit date selections as unchecked' {
            $script:ExplicitSelectionDefinitions['DemoDate'] = [pscustomobject]@{
                Function = 'DemoDate'
                Type = 'Date'
                Run = $false
                Value = '2025-04-08'
                DateParam = 'StartDate'
                Source = 'Preset'
            }

            $result = Get-DateInitialRunState -Index 9 -Tweak ([pscustomobject]@{
                Function = 'DemoDate'
                DateParam = 'StartDate'
            })

            $result | Should -BeFalse
        }
    }

    Describe 'Get-DateInitialSelectedDate' {
        It 'prefers explicit preset date values over stale placeholder state' {
            $script:Controls[4] = [pscustomobject]@{
                SelectedDate = [datetime]'2024-01-01'
            }
            $script:ExplicitSelectionDefinitions['DemoDate'] = [pscustomobject]@{
                Function = 'DemoDate'
                Type = 'Date'
                Run = $true
                Value = '2025-04-08'
                DateParam = 'StartDate'
                Source = 'Preset'
            }

            $result = Get-DateInitialSelectedDate -Index 4 -Tweak ([pscustomobject]@{
                Function = 'DemoDate'
                DateParam = 'StartDate'
            })

            $result.ToString('yyyy-MM-dd') | Should -Be '2025-04-08'
        }

        It 'falls back to placeholder selected dates when no explicit preset exists' {
            $script:Controls[4] = [pscustomobject]@{
                SelectedDate = [datetime]'2024-01-01'
            }

            $result = Get-DateInitialSelectedDate -Index 4 -Tweak ([pscustomobject]@{
                Function = 'DemoDate'
                DateParam = 'StartDate'
            })

            $result.ToString('yyyy-MM-dd') | Should -Be '2024-01-01'
        }
    }

    Describe 'Numeric range row wiring' {
        It 'resolves the checkbox label font size through density-aware row context tokens' {
            $script:FunctionTextByName['New-ToggleLikeCheckBox'] | Should -Match '\[double\]\$FontSize = \(GUICommon\\Get-GuiCommonSafeFontSize -Key ''FontSizeLabel'' -Default 11\)'
            $script:FunctionTextByName['New-ToggleLikeCheckBox'] | Should -Match '\$checkBox\.FontSize = \$FontSize'
            $script:FunctionTextByName['New-NumericRangeTweakRow'] | Should -Match '-FontSize \$RowContext\.LabelFontSize'
        }

        It 'does not force FontSize onto the numeric-range checkbox or slider controls' {
            $numericRangeText = $script:FunctionTextByName['New-NumericRangeTweakRow']

            $numericRangeText | Should -Not -Match '(?i)\$checkBox\.FontSize\s*='
            $numericRangeText | Should -Not -Match '(?i)\$slider\.FontSize\s*='
        }
    }
}
