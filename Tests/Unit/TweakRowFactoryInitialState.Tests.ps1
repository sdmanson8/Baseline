Set-StrictMode -Version Latest

BeforeAll {
    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Get-GameModePlanEntryForTweak', 'Get-ToggleInitialCheckedState', 'Get-ActionInitialCheckedState', 'Get-ChoiceInitialSelectedIndex')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    function Get-GameModePlan {
        return @($script:TestGameModePlan)
    }

    function Get-GuiExplicitSelectionDefinition {
        param([string]$FunctionName)

        if ($script:ExplicitSelectionDefinitions.ContainsKey($FunctionName)) {
            return $script:ExplicitSelectionDefinitions[$FunctionName]
        }

        return $null
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
}