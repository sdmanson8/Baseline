Set-StrictMode -Version Latest

BeforeAll {
    # so the test exercises the real source without loading the full GUI module.
    $splitRoot = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory'
    $sourceFiles = @(
        (Join-Path $PSScriptRoot '../../Module/GUI/TweakAvailability.ps1')
        (Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory.ps1')
        (Join-Path $splitRoot 'RowStateDefaults.ps1')
        (Join-Path $splitRoot 'MetadataDetails.ps1')
        (Join-Path $splitRoot 'ControlFactories.ps1')
    )
    $script:FunctionTextByName = @{}
    foreach ($sourceFile in $sourceFiles) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourceFile, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            $script:FunctionTextByName[$fn.Name] = $fn.Extent.Text
        }
    }
    foreach ($requiredFunction in @('Get-GuiTweakAvailability', 'Test-GuiTweakAvailableOnCurrentSystem', 'Get-TweakRowFactoryRuntimeCommand', 'Test-TweakRowFactoryTweakAvailable', 'Get-TweakRowFactoryHideUnavailableItems', 'Test-TweakRowVisible', 'Get-ToggleInitialCheckedState', 'Get-ActionInitialCheckedState', 'Get-ChoiceInitialSelectedIndex')) {
        if ($script:FunctionTextByName.ContainsKey($requiredFunction)) {
            Invoke-Expression $script:FunctionTextByName[$requiredFunction]
        } else {
            throw "$requiredFunction was not found in the GUI source files."
        }
    }

    # Mock the user-preference accessor that Test-TweakRowVisible delegates to.
    # The script-scoped variable lets each It block flip the pref.
    $script:HideUnavailablePrefValue = $true
    function Get-BaselineUserPreference {
        param([string]$Key, [object]$Default = $null)
        if ($Key -eq 'HideUnavailableItems') { return $script:HideUnavailablePrefValue }
        return $Default
    }

    function script:NewAvailableTweak {
        return [pscustomobject]@{
            Name = 'AvailableEntry'
            Function = 'AvailableEntry'
            Type = 'Toggle'
            Availability = [pscustomobject]@{
                Available = $true
                UnavailableReason = $null
            }
        }
    }

    function script:NewUnavailableTweak {
        param([string]$Reason = 'Requires Windows 11')
        return [pscustomobject]@{
            Name = 'UnavailableEntry'
            Function = 'UnavailableEntry'
            Type = 'Toggle'
            Availability = [pscustomobject]@{
                Available = $false
                UnavailableReason = $Reason
            }
        }
    }

    function script:NewNonExecutableTweak {
        param([string]$Reason = 'Required component is not installed.')
        return [pscustomobject]@{
            Name = 'NonExecutableEntry'
            Function = 'NonExecutableEntry'
            Type = 'Toggle'
            Availability = [pscustomobject]@{
                Available = $true
                UnavailableReason = $null
            }
            SupportsExecution = $false
            SupportsExecutionReason = $Reason
        }
    }
}

Describe 'Test-TweakRowVisible HideUnavailableItems gate' {
    It 'returns $true for an available entry when HideUnavailableItems = $true' {
        $script:HideUnavailablePrefValue = $true
        $tweak = NewAvailableTweak
        Test-TweakRowVisible -Tweak $tweak | Should -BeTrue
    }

    It 'returns $true for an available entry when HideUnavailableItems = $false' {
        $script:HideUnavailablePrefValue = $false
        $tweak = NewAvailableTweak
        Test-TweakRowVisible -Tweak $tweak | Should -BeTrue
    }

    It 'returns $false for an unavailable entry when HideUnavailableItems = $true' {
        $script:HideUnavailablePrefValue = $true
        $tweak = NewUnavailableTweak
        Test-TweakRowVisible -Tweak $tweak | Should -BeFalse
    }

    It 'returns $true for an unavailable entry when HideUnavailableItems = $false (rendered greyed)' {
        $script:HideUnavailablePrefValue = $false
        $tweak = NewUnavailableTweak
        Test-TweakRowVisible -Tweak $tweak | Should -BeTrue
    }

    It 'returns $false for a non-executable entry when HideUnavailableItems = $true' {
        $script:HideUnavailablePrefValue = $true
        $tweak = NewNonExecutableTweak
        Test-TweakRowVisible -Tweak $tweak | Should -BeFalse
    }

    It 'returns $true for a non-executable entry when HideUnavailableItems = $false' {
        $script:HideUnavailablePrefValue = $false
        $tweak = NewNonExecutableTweak
        Test-TweakRowVisible -Tweak $tweak | Should -BeTrue
    }

    It 'still hides an entry whose VisibleIf returns $false even when available' {
        $script:HideUnavailablePrefValue = $false
        $tweak = [pscustomobject]@{
            Name = 'GatedEntry'
            Function = 'GatedEntry'
            Type = 'Toggle'
            Availability = [pscustomobject]@{ Available = $true; UnavailableReason = $null }
            VisibleIf = { $false }
        }
        Test-TweakRowVisible -Tweak $tweak | Should -BeFalse
    }

    It 'defaults to hiding unavailable rows when Get-BaselineUserPreference is unavailable' {
        # Simulate the function being absent by removing it for this case.
        $script:TweakRowFactoryRuntimeCommandCache = @{}
        Remove-Item Function:Get-BaselineUserPreference -ErrorAction SilentlyContinue
        try {
            $tweak = NewUnavailableTweak
            Test-TweakRowVisible -Tweak $tweak | Should -BeFalse
        }
        finally {
            # Restore for other tests in the file.
            function script:Get-BaselineUserPreference {
                param([string]$Key, [object]$Default = $null)
                if ($Key -eq 'HideUnavailableItems') { return $script:HideUnavailablePrefValue }
                return $Default
            }
            $script:TweakRowFactoryRuntimeCommandCache = @{}
        }
    }

    It 'prevents unavailable rows from restoring checked or selected preset state' {
        $script:Controls = @(
            [pscustomobject]@{
                IsChecked = $true
                SelectedIndex = 0
            }
        )

        function Get-GuiExplicitSelectionDefinition {
            param([string]$FunctionName)
            return [pscustomobject]@{
                Function = $FunctionName
                Type = 'Toggle'
                State = 'On'
                Run = $true
                Value = 'Enabled'
            }
        }

        $tweak = NewUnavailableTweak

        Get-ToggleInitialCheckedState -Index 0 -Tweak $tweak | Should -BeFalse
        Get-ActionInitialCheckedState -Index 0 -Tweak $tweak | Should -BeFalse
        Get-ChoiceInitialSelectedIndex -Index 0 -Tweak $tweak -ChoiceOptions @('Enabled') | Should -Be -1
    }
}
