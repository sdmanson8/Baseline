Set-StrictMode -Version Latest

BeforeAll {
    # via AST so we can exercise the real helper without spinning up WPF.
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/TweakRowFactory/MetadataDetails.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $script:FunctionTextByName = @{}
    foreach ($fn in $functions) {
        $script:FunctionTextByName[$fn.Name] = $fn.Extent.Text
    }
    if ($script:FunctionTextByName.ContainsKey('Get-CompatibilityBadgeInfo')) {
        Invoke-Expression $script:FunctionTextByName['Get-CompatibilityBadgeInfo']
    }
    else {
        throw 'Get-CompatibilityBadgeInfo was not found in TweakRowFactory.ps1'
    }

    # Stub Get-UxString so the helper resolves to the supplied fallback strings
    # (uses the production English fallback path that other locales rely on).
    function Get-UxString {
        param([string]$Key, [string]$Fallback)
        return $Fallback
    }
}

Describe 'Get-CompatibilityBadgeInfo label-to-pill mapping' {
    It 'returns a pill for Windows10Only with Primary tone' {
        $result = Get-CompatibilityBadgeInfo -Label 'Windows10Only'
        $result | Should -Not -BeNullOrEmpty
        $result.Label | Should -Be 'Windows 10 only'
        $result.Tone | Should -Be 'Primary'
        $result.Tooltip | Should -Be 'This item targets Windows 10 only.'
    }

    It 'returns a pill for Windows11Only with Primary tone' {
        $result = Get-CompatibilityBadgeInfo -Label 'Windows11Only'
        $result | Should -Not -BeNullOrEmpty
        $result.Label | Should -Be 'Windows 11 only'
        $result.Tone | Should -Be 'Primary'
        $result.Tooltip | Should -Be 'This item targets Windows 11 only.'
    }

    It 'returns a pill for ServerOnly with Primary tone' {
        $result = Get-CompatibilityBadgeInfo -Label 'ServerOnly'
        $result | Should -Not -BeNullOrEmpty
        $result.Label | Should -Be 'Server only'
        $result.Tone | Should -Be 'Primary'
        $result.Tooltip | Should -Be 'This item targets Server only.'
    }

    It 'returns a pill for ClientOnly with Primary tone' {
        $result = Get-CompatibilityBadgeInfo -Label 'ClientOnly'
        $result | Should -Not -BeNullOrEmpty
        $result.Label | Should -Be 'Client only'
        $result.Tone | Should -Be 'Primary'
        $result.Tooltip | Should -Be 'This item targets Client only.'
    }

    It 'returns $null for Shared (no badge needed for ubiquitous entries)' {
        $result = Get-CompatibilityBadgeInfo -Label 'Shared'
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null for Mixed (label is too ambiguous to badge)' {
        $result = Get-CompatibilityBadgeInfo -Label 'Mixed'
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null for Unknown (metadata absent)' {
        $result = Get-CompatibilityBadgeInfo -Label 'Unknown'
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null for Unsupported (handled by the "Not on this system" pill)' {
        $result = Get-CompatibilityBadgeInfo -Label 'Unsupported'
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null when Label is empty' {
        $result = Get-CompatibilityBadgeInfo -Label ''
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null when Label is whitespace' {
        $result = Get-CompatibilityBadgeInfo -Label '   '
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null when Label is $null' {
        $result = Get-CompatibilityBadgeInfo -Label $null
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null for an unrecognised label value' {
        $result = Get-CompatibilityBadgeInfo -Label 'SomeFutureLabel'
        $result | Should -BeNullOrEmpty
    }
}
