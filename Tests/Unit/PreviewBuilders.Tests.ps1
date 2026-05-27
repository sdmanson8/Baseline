Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:PreviewBuildersPath = Join-Path $PSScriptRoot '../../Module/GUI/PreviewBuilders.ps1'
    $script:PreviewBuildersContent = Get-BaselineTestSourceText -Path $script:PreviewBuildersPath
}

Describe 'Preview builders' {
    It 'routes preview cursor fallbacks through Write-SwallowedException' {
        $script:PreviewBuildersContent | Should -Match 'function Show-SelectedTweakPreview'
        $script:PreviewBuildersContent | Should -Match 'PreviewBuilders\.Show-SelectedTweakPreview\.SetWaitCursor'
        $script:PreviewBuildersContent | Should -Match 'PreviewBuilders\.Show-SelectedTweakPreview\.RestoreCursor'
    }
}
