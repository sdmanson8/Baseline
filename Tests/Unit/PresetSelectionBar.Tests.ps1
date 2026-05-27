Set-StrictMode -Version Latest

BeforeAll {
    $presetUiPath = Join-Path $PSScriptRoot '../../Module/GUI/PresetUI.ps1'
    $script:PresetUiContent = Get-Content -LiteralPath $presetUiPath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($presetUiPath, [ref]$null, [ref]$null)
    foreach ($functionName in @(
            'Get-GuiBulkSelectionObjectField',
            'Get-GuiBulkSelectableActionPath',
            'New-GuiBulkSelectableControlTestScript',
            'Test-GuiBulkSelectableControl',
            'Clear-GuiTweakSelectionControl'
        ))
    {
        $targetFunction = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
        }, $true)
        Invoke-Expression $targetFunction.Extent.Text
    }

    Add-Type -AssemblyName PresentationFramework
}

Describe 'Clear-GuiTweakSelectionControl' {
    It 'clears choice state and its visible ComboBox selection together' {
        $combo = [System.Windows.Controls.ComboBox]::new()
        [void]$combo.Items.Add('Install')
        [void]$combo.Items.Add('Uninstall')
        $combo.SelectedIndex = 1
        $stateControl = [pscustomobject]@{
            Type = 'Choice'
            ComboBox = $combo
            SelectedIndex = 1
            Value = 'Uninstall'
            IsEnabled = $true
        }

        Clear-GuiTweakSelectionControl -Control $stateControl

        $stateControl.SelectedIndex | Should -Be -1
        $stateControl.Value | Should -BeNullOrEmpty
        $combo.SelectedIndex | Should -Be -1
    }

    It 'clears checkbox-backed controls' {
        $checkBox = [System.Windows.Controls.CheckBox]::new()
        $checkBox.IsChecked = $true
        $stateControl = [pscustomobject]@{
            Type = 'Toggle'
            CheckBox = $checkBox
            IsChecked = $true
            IsEnabled = $true
        }

        Clear-GuiTweakSelectionControl -Control $stateControl

        $stateControl.IsChecked | Should -BeFalse
        $checkBox.IsChecked | Should -BeFalse
    }
}

Describe 'Test-GuiBulkSelectableControl' {
    It 'allows regular toggle controls to be selected in bulk' {
        $control = [pscustomobject]@{
            Type = 'Toggle'
            IsChecked = $false
            IsEnabled = $true
        }

        Test-GuiBulkSelectableControl -Control $control | Should -BeTrue
    }

    It 'does not bulk-select action-picker controls without a selected path' {
        $control = [pscustomobject]@{
            Type = 'Action'
            IsChecked = $false
            IsEnabled = $true
            ActionPicker = [pscustomobject]@{ ParameterName = 'AppPath' }
            SelectedValue = $null
            ExtraArgs = $null
        }

        Test-GuiBulkSelectableControl -Control $control | Should -BeFalse
    }

    It 'does not bulk-select checkbox-backed action-picker manifest entries without a selected path' {
        $control = [pscustomobject]@{
            IsChecked = $false
            IsEnabled = $true
        }
        $manifestEntry = [pscustomobject]@{
            Function = 'AppGraphicsPerformance'
            Type = 'Action'
            ActionPicker = [pscustomobject]@{ ParameterName = 'AppPath' }
        }

        Test-GuiBulkSelectableControl -Control $control -ManifestEntry $manifestEntry | Should -BeFalse
    }

    It 'bulk-selects action-picker controls when the row already has a selected path' {
        $control = [pscustomobject]@{
            Type = 'Action'
            IsChecked = $false
            IsEnabled = $true
            ActionPicker = [pscustomobject]@{ ParameterName = 'AppPath' }
            SelectedValue = 'C:\Games\Game.exe'
            ExtraArgs = $null
        }

        Test-GuiBulkSelectableControl -Control $control | Should -BeTrue
    }

    It 'bulk-selects action-picker controls when explicit selection has the selected path' {
        $control = [pscustomobject]@{
            Type = 'Action'
            IsChecked = $false
            IsEnabled = $true
            ActionPicker = [pscustomobject]@{ ParameterName = 'AppPath' }
            SelectedValue = $null
            ExtraArgs = $null
        }
        $explicitSelection = [pscustomobject]@{
            Type = 'Action'
            ExtraArgs = @{ AppPath = 'C:\Games\Restored.exe' }
        }

        Test-GuiBulkSelectableControl -Control $control -ExplicitSelectionDefinition $explicitSelection | Should -BeTrue
    }

    It 'bulk-selects checkbox-backed action-picker manifest entries when explicit selection has the selected path' {
        $control = [pscustomobject]@{
            IsChecked = $false
            IsEnabled = $true
        }
        $manifestEntry = [pscustomobject]@{
            Function = 'AppGraphicsPerformance'
            Type = 'Action'
            ActionPicker = [pscustomobject]@{ ParameterName = 'AppPath' }
        }
        $explicitSelection = [pscustomobject]@{
            Type = 'Action'
            ExtraArgs = @{ AppPath = 'C:\Games\Restored.exe' }
        }

        Test-GuiBulkSelectableControl -Control $control -ManifestEntry $manifestEntry -ExplicitSelectionDefinition $explicitSelection | Should -BeTrue
    }

    It 'captures the predicate scriptblock before wiring the Select All event' {
        $script:PresetUiContent | Should -Match '\$testBulkSelectableControl = New-GuiBulkSelectableControlTestScript'
        $script:PresetUiContent | Should -Match '& \$testBulkSelectableControl -Control \$control -ManifestEntry \$manifestEntry -ExplicitSelectionDefinition \$explicitSelectionDefinition'
        $script:PresetUiContent | Should -Not -Match '\(Test-GuiBulkSelectableControl -Control \$control'
    }

    It 'captures the clear helper before wiring the Unselect All event' {
        $script:PresetUiContent | Should -Match '\$clearTweakSelectionControl = \$\{function:Clear-GuiTweakSelectionControl\}'
        $script:PresetUiContent | Should -Match '& \$clearTweakSelectionControl -Control \$control'
        $script:PresetUiContent | Should -Not -Match '(?m)^\s*Clear-GuiTweakSelectionControl -Control \$control'
    }

    It 'wraps tab bulk selection handlers in a selection bulk update' {
        $script:PresetUiContent | Should -Match "Get-GuiFunctionCapture -Name 'Enter-GuiSelectionBulkUpdate'"
        $script:PresetUiContent | Should -Match "Get-GuiFunctionCapture -Name 'Exit-GuiSelectionBulkUpdate'"
        ([regex]::Matches($script:PresetUiContent, '\$selectionBulkPreviousState = \[bool\]\(& \$enterSelectionBulkUpdate\)')).Count | Should -Be 2
        ([regex]::Matches($script:PresetUiContent, '& \$exitSelectionBulkUpdate -PreviousState \$selectionBulkPreviousState')).Count | Should -Be 2
    }
}
