Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:DiffViewPath = Join-Path $PSScriptRoot '../../Module/GUI/DiffView.ps1'
    $script:DiffViewContent = Get-BaselineTestSourceText -Path $script:DiffViewPath
}

Describe 'Diff view' {
    It 'routes dialog setup and list initialization fallbacks through Write-SwallowedException' {
        $script:DiffViewContent | Should -Match 'function Show-DiffViewDialog'
        $script:DiffViewContent | Should -Match 'function Show-DiffViewFromSelection'
        $script:DiffViewContent | Should -Match 'DiffView\.Show-DiffViewDialog\.SetOwner'
        $script:DiffViewContent | Should -Match 'DiffView\.Show-DiffViewFromSelection\.BeginInit'
        $script:DiffViewContent | Should -Match 'DiffView\.Show-DiffViewFromSelection\.EndInit'
    }
}
