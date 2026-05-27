Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $systemScanPath = Join-Path $PSScriptRoot '../../Module/GUI/SystemScan.ps1'
    $systemScanFooterHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers/SystemScanFooterHandlers.ps1'
    $script:SystemScanContent = Get-BaselineTestSourceText -Path $systemScanPath
    $script:SystemScanFooterHandlersContent = Get-BaselineTestSourceText -Path $systemScanFooterHandlersPath
}

Describe 'System scan' {
    It 'routes non-fatal scan fallbacks through Write-SwallowedException' {
        $script:SystemScanContent | Should -Match 'SystemScan\.Test-GuiManifestToggleNeedsAttention\.LoadCurrentState'
        $script:SystemScanContent | Should -Match 'SystemScan\.Get-GuiEnvironmentRecommendationData\.LoadGameBarState'
        $script:SystemScanContent | Should -Match 'SystemScan\.Get-GuiEnvironmentRecommendationData\.LoadTerminalState'
        $script:SystemScanContent | Should -Match 'SystemScan\.Get-GuiEnvironmentRecommendationData\.LoadOfficeState'
        $script:SystemScanContent | Should -Match 'SystemScan\.Get-GuiEnvironmentRecommendationData\.LoadMappedNetworkDrives'
        $script:SystemScanContent | Should -Match 'SystemScan\.Get-GuiEnvironmentRecommendationData\.LoadDomainJoined'
        $script:SystemScanContent | Should -Match 'SystemScan\.Get-GuiEnvironmentRecommendationData\.LoadWinReState'
    }

    It 'guards system-scan enabled-state writes for heterogeneous control state objects' {
        $script:SystemScanContent | Should -Match 'function Set-GuiSystemScanControlEnabled'
        $script:SystemScanContent | Should -Match 'Test-GuiObjectField -Object \$Control -FieldName ''IsEnabled'''
        $script:SystemScanContent | Should -Match 'Set-GuiSystemScanControlEnabled -Control \$sctl -Enabled \$true'
        ([regex]::Matches($script:SystemScanContent, 'Set-GuiSystemScanControlEnabled -Control \$sctl -Enabled \$false')).Count | Should -Be 2
        $script:SystemScanContent | Should -Not -Match '\$sctl\.IsEnabled\s*='
        $script:SystemScanFooterHandlersContent | Should -Match '& \$hasField -Object \$sctl -FieldName ''IsEnabled'''
    }

    It 'records detection results for tabs that have not been built yet' {
        $script:SystemScanContent | Should -Not -Match 'if \(-not \$sctl\) \{ continue \}'
        $script:SystemScanContent | Should -Match 'Set-CachedDetection -Function'
        $script:SystemScanContent | Should -Match 'Save-GuiDetectCache'
    }
}
