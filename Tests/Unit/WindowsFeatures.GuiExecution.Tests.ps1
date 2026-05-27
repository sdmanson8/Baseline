Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:SystemWindowsFeaturesPath = Join-Path $script:RepoRoot 'Module/Regions/System/System.WindowsFeatures.psm1'
    $script:GuiExecutionPath = Join-Path $script:RepoRoot 'Module/GUIExecution.psm1'
    $script:SystemWindowsFeaturesContent = Get-BaselineTestSourceText -Path $script:SystemWindowsFeaturesPath
    $script:GuiExecutionContent = Get-BaselineTestSourceText -Path $script:GuiExecutionPath
}

Describe 'Windows Features GUI execution' {
    It 'lets live GUI runs request Windows Capabilities selection instead of forcing seeded defaults' {
        $script:SystemWindowsFeaturesContent | Should -Match '\$Global:GUIMode -and -not \$CollectSelectionOnly -and -not \$SelectedCapabilityNamesProvided -and -not \$UseDefaultSelection'
        $script:SystemWindowsFeaturesContent | Should -Match 'Request-GuiSystemSelection -RequestType ''WindowsCapabilities'''
        $script:SystemWindowsFeaturesContent | Should -Match 'Test-CapabilityPatternMatch -CapabilityName \$_.Name -Patterns \$CheckedCapabilities'
        $script:GuiExecutionContent | Should -Not -Match '\$splat\[''UseDefaultSelection''\] = \$true'
    }

    It 'runs optional feature install and removal through bounded DISM process execution' {
        $script:SystemWindowsFeaturesContent | Should -Match 'function Invoke-WindowsCapabilityDismOperation'
        $script:SystemWindowsFeaturesContent | Should -Match '\$CapabilityOperationTimeoutSeconds = 180'
        $script:SystemWindowsFeaturesContent | Should -Match '\$TimeoutSeconds = 180'
        $script:SystemWindowsFeaturesContent | Should -Match 'Invoke-BaselineProcess[\s\S]+-TimeoutSeconds \$TimeoutSeconds'
        $script:SystemWindowsFeaturesContent | Should -Match 'Invoke-WindowsCapabilityDismOperation -Operation Install -Name \$Capability\.Name -TimeoutSeconds \$CapabilityOperationTimeoutSeconds'
        $script:SystemWindowsFeaturesContent | Should -Match 'Invoke-WindowsCapabilityDismOperation -Operation Uninstall -Name \$Capability\.Name -TimeoutSeconds \$CapabilityOperationTimeoutSeconds'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'Add-WindowsCapability -Online -Name \$Capability\.Name'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'Remove-WindowsCapability -Online -Name \$Capability\.Name'
    }

    It 'imports shared helpers into the popup operation runspace for process timeout helpers' {
        $script:SystemWindowsFeaturesContent | Should -Match '\$sharedHelpersPath = Resolve-SystemPickerSharedHelpersPath -ModulePath \$modulePath'
        $script:SystemWindowsFeaturesContent | Should -Match '-AdditionalModulePaths @\(\$sharedHelpersPath, \$guiCommonPath\)'
    }

    It 'lets live GUI runs request Windows Features selection instead of forcing seeded defaults' {
        $script:SystemWindowsFeaturesContent | Should -Match '\$Global:GUIMode -and -not \$CollectSelectionOnly -and -not \$SelectedFeatureNamesProvided -and -not \$UseDefaultSelection'
        $script:SystemWindowsFeaturesContent | Should -Match 'Request-GuiSystemSelection -RequestType ''WindowsFeatures'''
        $script:SystemWindowsFeaturesContent | Should -Match 'Test-FeaturePatternMatch -FeatureName \$_.FeatureName -Patterns \$CheckedFeatures'
        $script:GuiExecutionContent | Should -Not -Match '\$splat\[''UseDefaultSelection''\] = \$true'
    }

    It 'treats confirmed empty Windows picker selections as no-op skips' {
        $script:SystemWindowsFeaturesContent | Should -Match 'No optional features were selected for installation\. Skipping\.'
        $script:SystemWindowsFeaturesContent | Should -Match 'No Windows features were selected for enable\. Skipping\.'
        $script:SystemWindowsFeaturesContent | Should -Match 'No Windows features were selected for disable\. Skipping\.'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'throw "No optional features were selected for installation\."'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'throw "No Windows features were selected\."'
    }

    It 'marks preset-matched empty feature lists as skipped instead of successful' {
        $script:SystemWindowsFeaturesContent | Should -Match 'Skipping optional features because no preset-matched Optional features were found\.'
        $script:SystemWindowsFeaturesContent | Should -Match 'Skipping Windows features because no preset-matched Windows features were found\.'
        $script:SystemWindowsFeaturesContent | Should -Match 'Installing optional features'' \}\)\" -Status warning'
        $script:SystemWindowsFeaturesContent | Should -Match 'Enabling Windows features'' \}\)\" -Status warning'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'No preset-matched Optional features were found\. Moving on\.'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'No preset-matched Windows features were found\. Moving on\.'
    }
}
