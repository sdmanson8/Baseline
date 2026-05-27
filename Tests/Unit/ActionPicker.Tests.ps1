Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:manifestHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Manifest.Helpers.ps1'
    $script:presetSelectionPath = Join-Path $PSScriptRoot '../../Module/GUI/PresetManagement/PresetSelectionState.ps1'
    $script:previewBuildersPath = Join-Path $PSScriptRoot '../../Module/GUI/PreviewBuilders.ps1'
    $script:tweakRowControlFactoriesPath = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory/ControlFactories.ps1'
    $script:gamingManifestPath = Join-Path $PSScriptRoot '../../Module/Data/Gaming.json'
    $script:gamingRegionPath = Join-Path $PSScriptRoot '../../Module/Regions/Gaming.psm1'

    $script:ManifestHelpersContent = Get-BaselineTestSourceText -Path $script:manifestHelpersPath
    $script:PreviewBuildersContent = Get-BaselineTestSourceText -Path $script:previewBuildersPath
    $script:TweakRowControlFactoriesContent = Get-BaselineTestSourceText -Path $script:tweakRowControlFactoriesPath
    $script:GamingRegionContent = Get-BaselineTestSourceText -Path $script:gamingRegionPath
    $script:GamingManifest = Get-BaselineTestSourceText -Path $script:gamingManifestPath | ConvertFrom-Json

    function Test-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }

    $presetAst = [System.Management.Automation.Language.Parser]::ParseFile($script:presetSelectionPath, [ref]$null, [ref]$null)
    $copyFunction = $presetAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Copy-GuiExplicitSelectionDefinition'
    }, $true)
    Invoke-Expression $copyFunction.Extent.Text
}

Describe 'Manifest-driven action picker' {
    It 'preserves ActionPicker metadata through manifest normalization without using ExtraArgs' {
        $script:ManifestHelpersContent | Should -Match "'ActionPicker'"
        $script:ManifestHelpersContent | Should -Match "'ExtraArgs'"
    }

    It 'copies explicit selection ExtraArgs so picker selections survive tab rebuilds' {
        $copy = Copy-GuiExplicitSelectionDefinition -FunctionName 'AppGraphicsPerformance' -Definition ([pscustomobject]@{
            Function = 'AppGraphicsPerformance'
            Type = 'Action'
            Run = $true
            Value = 'C:\Games\game.exe'
            ExtraArgs = @{ AppPath = 'C:\Games\game.exe' }
            Source = 'Preset'
        })

        $copy.ExtraArgs.AppPath | Should -Be 'C:\Games\game.exe'
    }

    It 'builds selected action-picker paths into preview ExtraArgs instead of static manifest args' {
        $script:PreviewBuildersContent | Should -Match 'Get-GuiPreviewActionPickerParameterName'
        $script:PreviewBuildersContent | Should -Match '\$selectedExtraArgs\[\$actionPickerParameterName\] = \[string\]\$selectedPath'
        $script:PreviewBuildersContent | Should -Match 'continue'
    }

    It 'wires the WPF action row to Microsoft.Win32.OpenFileDialog' {
        $script:TweakRowControlFactoriesContent | Should -Match '\[Microsoft\.Win32\.OpenFileDialog\]::new\(\)'
        $script:TweakRowControlFactoriesContent | Should -Match 'Register-GuiActionSelectionHandlers .* -ActionPicker \$actionPicker'
        $script:TweakRowControlFactoriesContent | Should -Match 'Set-GuiActionPickerSelection'
    }

    It 'surfaces per-app graphics preference as a bare-noun manifest action' {
        $entry = @($script:GamingManifest.Entries | Where-Object { $_.Function -eq 'AppGraphicsPerformance' })[0]

        $entry | Should -Not -BeNullOrEmpty
        $entry.Type | Should -Be 'Action'
        $entry.ActionPicker.Kind | Should -Be 'OpenFile'
        $entry.ActionPicker.ParameterName | Should -Be 'AppPath'
        $entry.ExtraArgs | Should -Be $null
        $script:GamingRegionContent | Should -Match 'function AppGraphicsPerformance'
        $script:GamingRegionContent | Should -Match 'Set-AppGraphicsPerformance -AppPath \$AppPath'
    }
}
