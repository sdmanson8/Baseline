Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    Add-Type -AssemblyName PresentationFramework

    $script:controlFactoriesPath = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory/ControlFactories.ps1'
    $script:uwpAppsPath = Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1'
    $script:ControlFactoriesContent = Get-BaselineTestSourceText -Path $script:controlFactoriesPath
    $script:UwpAppsContent = Get-BaselineTestSourceText -Path $script:uwpAppsPath

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:controlFactoriesPath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    function script:Test-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }
    function script:Get-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $null }
        if ($Object -is [System.Collections.IDictionary]) { return $Object[$FieldName] }
        if ($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) { return $Object.PSObject.Properties[$FieldName].Value }
        return $null
    }
    function script:Get-UxString {
        param([string]$Key, [string]$Fallback)
        return $Fallback
    }

    foreach ($fn in $functions) {
        if ($fn.Name -in @(
            'Get-TweakRowFactoryFunctionCapture',
            'Get-GuiActionPickerField',
            'Get-GuiActionPickerSelectedPath',
            'New-GuiActionPickerExtraArgs',
            'Update-GuiActionPickerSelectionText',
            'Show-GuiActionOpenFileDialog',
            'Set-GuiActionPickerSelection',
            'Clear-GuiActionPickerSelection',
            'Register-GuiChoiceSelectionHandler',
            'Register-GuiActionSelectionHandlers',
            'Register-GuiNumericRangeSelectionHandlers',
            'Register-GuiToggleExplicitSelectionHandlers'
        )) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    Set-Item -Path Function:\global:Test-GuiObjectField -Value ${function:script:Test-GuiObjectField}
    Set-Item -Path Function:\global:Get-GuiObjectField -Value ${function:script:Get-GuiObjectField}
    Set-Item -Path Function:\global:Get-UxString -Value ${function:script:Get-UxString}

    function Register-GuiEventHandler {
        param(
            [object]$Source,
            [string]$EventName,
            [scriptblock]$Handler
        )

        if (-not $Source.PSObject.Properties['CapturedHandlers']) {
            Add-Member -InputObject $Source -NotePropertyName 'CapturedHandlers' -NotePropertyValue @{} -Force
        }

        $Source.CapturedHandlers[$EventName] = $Handler
        return $null
    }

    function script:NewRowContext {
        param(
            [scriptblock]$TestSelectionBulkUpdateInProgress = { $false }
        )

        $selectionStore = @{}
        $script:RunActionAvailabilityRefreshCount = 0

        return [pscustomobject]@{
            SelectionStore = $selectionStore
            GetExplicitSelectionDefinition = {
                param([string]$FunctionName)
                if ($selectionStore.ContainsKey($FunctionName)) {
                    return $selectionStore[$FunctionName]
                }
                return $null
            }.GetNewClosure()
            SetExplicitSelectionDefinition = {
                param([string]$FunctionName, [object]$Definition)
                $selectionStore[$FunctionName] = $Definition
            }.GetNewClosure()
            RemoveExplicitSelectionDefinition = {
                param([string]$FunctionName)
                if ($selectionStore.ContainsKey($FunctionName)) {
                    [void]$selectionStore.Remove($FunctionName)
                }
            }.GetNewClosure()
            TestSelectionBulkUpdateInProgress = $TestSelectionBulkUpdateInProgress
            SyncGameModePlanFromControlsScript = $null
            UpdateRunActionAvailabilityScript = {
                $script:RunActionAvailabilityRefreshCount++
            }
        }
    }

    function script:Invoke-WithFunctionNamesRemoved {
        param(
            [string[]]$Name,
            [scriptblock]$ScriptBlock
        )

        $savedFunctions = @{}
        foreach ($functionName in $Name) {
            $savedFunction = Get-Item -Path "Function:\$functionName" -ErrorAction SilentlyContinue
            if ($savedFunction) {
                $savedFunctions[$functionName] = $savedFunction.ScriptBlock
                Remove-Item -Path "Function:\$functionName" -ErrorAction SilentlyContinue
            }
        }

        try {
            & $ScriptBlock
        }
        finally {
            foreach ($functionName in $savedFunctions.Keys) {
                Set-Item -Path "Function:\$functionName" -Value $savedFunctions[$functionName]
            }
        }
    }
}

Describe 'Manual explicit selection persistence' {
    It 'creates a manual explicit choice selection outside a preset' {
        $combo = [System.Windows.Controls.ComboBox]::new()
        [void]$combo.Items.Add('Install')
        [void]$combo.Items.Add('Uninstall')
        $combo.SelectedIndex = 1
        $rowContext = NewRowContext
        $stateControl = [pscustomobject]@{ IsRestoring = $false }

        Register-GuiChoiceSelectionHandler -ComboBox $combo -FunctionName 'WindowsCapabilities' -ChoiceOptions @('Install', 'Uninstall') -RowContext $rowContext -StateControl $stateControl
        & $combo.CapturedHandlers['SelectionChanged']

        $rowContext.SelectionStore['WindowsCapabilities'].Type | Should -Be 'Choice'
        $rowContext.SelectionStore['WindowsCapabilities'].Value | Should -Be 'Uninstall'
        $rowContext.SelectionStore['WindowsCapabilities'].Source | Should -Be 'Manual'
    }

    It 'creates a manual explicit action selection outside a preset' {
        $checkBox = [System.Windows.Controls.CheckBox]::new()
        $checkBox.IsChecked = $true
        $rowContext = NewRowContext
        $stateControl = [pscustomobject]@{ IsRestoring = $false }

        Register-GuiActionSelectionHandlers -CheckBox $checkBox -FunctionName 'CreateRestorePoint' -RowContext $rowContext -StateControl $stateControl
        & $checkBox.CapturedHandlers['Checked']

        $rowContext.SelectionStore['CreateRestorePoint'].Type | Should -Be 'Action'
        $rowContext.SelectionStore['CreateRestorePoint'].Run | Should -BeTrue
        $rowContext.SelectionStore['CreateRestorePoint'].Source | Should -Be 'Manual'
    }

    It 'does not open an action picker when bulk selection checks an app-picker row without a path' {
        $checkBox = [System.Windows.Controls.CheckBox]::new()
        $checkBox.IsChecked = $true
        $rowContext = NewRowContext -TestSelectionBulkUpdateInProgress { $true }
        $selectionText = [System.Windows.Controls.TextBlock]::new()
        $actionPicker = [pscustomobject]@{
            Kind = 'OpenFile'
            ParameterName = 'AppPath'
            EmptyLabel = 'No file selected.'
            SelectedLabel = 'Selected file: {0}'
        }
        $stateControl = [pscustomobject]@{
            IsRestoring = $false
            IsChecked = $true
            SelectedValue = $null
            ExtraArgs = $null
            PickerSelectionText = $selectionText
        }

        $script:ActionPickerDialogOpened = $false
        function Show-GuiActionOpenFileDialog {
            param([object]$ActionPicker)
            $script:ActionPickerDialogOpened = $true
            return 'C:\Should\NotOpen.exe'
        }

        Register-GuiActionSelectionHandlers -CheckBox $checkBox -FunctionName 'LaunchTool' -RowContext $rowContext -StateControl $stateControl -ActionPicker $actionPicker
        & $checkBox.CapturedHandlers['Checked']

        $script:ActionPickerDialogOpened | Should -BeFalse
        $checkBox.IsChecked | Should -BeFalse
        $stateControl.IsChecked | Should -BeFalse
        $stateControl.SelectedValue | Should -BeNullOrEmpty
        $rowContext.SelectionStore.ContainsKey('LaunchTool') | Should -BeFalse
    }

    It 'keeps action picker handlers bound after helper names leave command lookup' {
        $checkBox = [System.Windows.Controls.CheckBox]::new()
        $rowContext = NewRowContext
        $selectionText = [System.Windows.Controls.TextBlock]::new()
        $actionPicker = [pscustomobject]@{
            Kind = 'OpenFile'
            ParameterName = 'AppPath'
            EmptyLabel = 'No file selected.'
            SelectedLabel = 'Selected file: {0}'
        }
        $stateControl = [pscustomobject]@{
            IsRestoring = $false
            SelectedValue = 'C:\Tools\App.exe'
            ExtraArgs = $null
            PickerSelectionText = $selectionText
        }

        Register-GuiActionSelectionHandlers -CheckBox $checkBox -FunctionName 'LaunchTool' -RowContext $rowContext -StateControl $stateControl -ActionPicker $actionPicker

        Invoke-WithFunctionNamesRemoved -Name @(
            'Get-GuiActionPickerSelectedPath',
            'Show-GuiActionOpenFileDialog',
            'Clear-GuiActionPickerSelection',
            'Set-GuiActionPickerSelection'
        ) -ScriptBlock {
            { & $checkBox.CapturedHandlers['Checked'] } | Should -Not -Throw
            $rowContext.SelectionStore['LaunchTool'].Type | Should -Be 'Action'
            $rowContext.SelectionStore['LaunchTool'].Value | Should -Be 'C:\Tools\App.exe'
            $rowContext.SelectionStore['LaunchTool'].ExtraArgs['AppPath'] | Should -Be 'C:\Tools\App.exe'
            $selectionText.Text | Should -Be 'Selected file: C:\Tools\App.exe'

            { & $checkBox.CapturedHandlers['Unchecked'] } | Should -Not -Throw
            $rowContext.SelectionStore.ContainsKey('LaunchTool') | Should -BeFalse
            $stateControl.SelectedValue | Should -BeNullOrEmpty
            $selectionText.Text | Should -Be 'No file selected.'
        }
    }

    It 'keeps numeric range handlers bound after formatting helpers leave command lookup' {
        function Get-GuiNumericRangeChannelValue {
            param([object]$Value, [string]$Channel, [object]$NumericRange)
            return [int]$Value
        }
        function Format-GuiPowerSchemeValueText {
            param([object]$Value, [object]$NumericRange, [string]$Units)
            if ($Value -and $Value.PSObject.Properties['ACValue']) {
                return ('AC={0}; DC={1} {2}' -f $Value.ACValue, $Value.DCValue, $Units)
            }
            return ('{0} {1}' -f $Value, $Units)
        }
        function Get-UxLocalizedString {
            param([string]$Key, [string]$Fallback, [object[]]$FormatArgs)
            return ($Fallback -f $FormatArgs)
        }

        $checkBox = [System.Windows.Controls.CheckBox]::new()
        $acSlider = [System.Windows.Controls.Slider]::new()
        $dcSlider = [System.Windows.Controls.Slider]::new()
        $acValueText = [System.Windows.Controls.TextBlock]::new()
        $dcValueText = [System.Windows.Controls.TextBlock]::new()
        $summaryText = [System.Windows.Controls.TextBlock]::new()
        $rowContext = NewRowContext
        $acSlider.Maximum = 100
        $dcSlider.Maximum = 100
        $acSlider.Value = 45
        $dcSlider.Value = 15

        $stateControl = [pscustomobject]@{ IsRestoring = $false; IsChecked = $false; Value = $null; ACValue = $null; DCValue = $null }

        Register-GuiNumericRangeSelectionHandlers -CheckBox $checkBox -AcSlider $acSlider -DcSlider $dcSlider -AcValueText $acValueText -DcValueText $dcValueText -SummaryText $summaryText -FunctionName 'DisplayTimeout' -NumericRange ([pscustomobject]@{}) -Units 'minutes' -RowContext $rowContext -StateControl $stateControl

        Invoke-WithFunctionNamesRemoved -Name @(
            'Get-GuiNumericRangeChannelValue',
            'Format-GuiPowerSchemeValueText',
            'Get-UxLocalizedString'
        ) -ScriptBlock {
            { & $checkBox.CapturedHandlers['Checked'] } | Should -Not -Throw
            $rowContext.SelectionStore['DisplayTimeout'].Type | Should -Be 'NumericRange'
            $rowContext.SelectionStore['DisplayTimeout'].ACValue | Should -Be 45
            $rowContext.SelectionStore['DisplayTimeout'].DCValue | Should -Be 15
            $summaryText.Text | Should -Be 'Selected values: AC=45; DC=15 minutes'
        }
    }

    It 'does not require module-scoped field helper when a toggle event fires' {
        $checkBox = [System.Windows.Controls.CheckBox]::new()
        $rowContext = NewRowContext
        $stateControl = [pscustomobject]@{ IsRestoring = $false }
        $rowContext.SelectionStore['DemoToggle'] = [pscustomobject]@{
            Function = 'DemoToggle'
            Type = 'Toggle'
            State = 'On'
            Source = 'Preset'
        }

        $savedFunction = Get-Item -Path Function:\global:Test-GuiObjectField -ErrorAction SilentlyContinue
        Remove-Item -Path Function:\global:Test-GuiObjectField -ErrorAction SilentlyContinue
        try {
            Register-GuiToggleExplicitSelectionHandlers -CheckBox $checkBox -FunctionName 'DemoToggle' -RowContext $rowContext -StateControl $stateControl
            { & $checkBox.CapturedHandlers['Unchecked'] } | Should -Not -Throw
        }
        finally {
            if ($savedFunction) {
                Set-Item -Path Function:\global:Test-GuiObjectField -Value $savedFunction.ScriptBlock
            }
        }

        $rowContext.SelectionStore['DemoToggle'].Type | Should -Be 'Toggle'
        $rowContext.SelectionStore['DemoToggle'].State | Should -Be 'Off'
        $rowContext.SelectionStore['DemoToggle'].Source | Should -Be 'Preset'
    }

    It 'does not require module-scoped run availability helper when a choice event fires' {
        $combo = [System.Windows.Controls.ComboBox]::new()
        [void]$combo.Items.Add('Install')
        [void]$combo.Items.Add('Uninstall')
        $combo.SelectedIndex = 1
        $rowContext = NewRowContext
        $stateControl = [pscustomobject]@{ IsRestoring = $false }
        $script:RunActionAvailabilityRefreshCount = 0

        Register-GuiChoiceSelectionHandler -ComboBox $combo -FunctionName 'WindowsCapabilities' -ChoiceOptions @('Install', 'Uninstall') -RowContext $rowContext -StateControl $stateControl

        Invoke-WithFunctionNamesRemoved -Name @('Invoke-GuiTweakRowRunActionAvailabilityRefresh') -ScriptBlock {
            { & $combo.CapturedHandlers['SelectionChanged'] } | Should -Not -Throw
        }

        $rowContext.SelectionStore['WindowsCapabilities'].Value | Should -Be 'Uninstall'
        $script:RunActionAvailabilityRefreshCount | Should -Be 1
    }
}

Describe 'UWPApps selection dialogs' {
    It 'guards uninstall picker repopulation against empty package lists' {
        $script:UwpAppsContent | Should -Match '\$AppXPackages = @\(Get-AppxBundle -Exclude \$ExcludedAppxPackages -AllUsers:\$CheckBoxForAllUsers\.IsChecked \| Where-Object \{ \$null -ne \$_ \}\)'
        $script:UwpAppsContent | Should -Match 'if \(\$AppXPackages\.Count -gt 0\)\s*\{\s*Add-UWPAppsUninstallPickerControl -Packages \$AppXPackages'
    }

    It 'guards install picker repopulation against empty package lists' {
        $script:UwpAppsContent | Should -Match '\$MissingPackages = @\(Get-MissingAppxPackages -AllUsers:\$CheckBoxForAllUsers\.IsChecked \| Where-Object \{ \$null -ne \$_ \}\)'
    }
}
