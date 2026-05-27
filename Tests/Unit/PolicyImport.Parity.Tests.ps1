Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ReviewPath = Join-Path $script:RepoRoot 'dev_docs/Baseline-PolicyImport-Parity.md'
    $script:SystemTweaksManifestPath = Join-Path $script:RepoRoot 'Module/Data/SystemTweaks.json'
    $script:AllManifestContent = Get-BaselineTestSourceText -Path (Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'Module/Data') -File -Filter '*.json' | ForEach-Object { $_.FullName })
}

Describe 'Baseline policy import parity review' {
    It 'records the reviewed decision outside runtime product code' {
        Test-Path -LiteralPath $script:ReviewPath -PathType Leaf | Should -BeTrue
        $content = Get-BaselineTestSourceText -Path $script:ReviewPath

        $content | Should -Match 'Baseline does not import arbitrary pre-existing registry policy values into Baseline policy state at runtime'
        $content | Should -Match 'Stash review found no related implementation to recover'
        $content | Should -Match 'External review found only audit/reference records'
        $content | Should -Match 'reviewed ADMX mappings'
        $content | Should -Match 'require explicit user confirmation before importing anything'
    }

    It 'keeps ScanRegistryPolicies out of runtime tweak manifests until import support is explicit' {
        $script:AllManifestContent | Should -Not -Match '"Function"\s*:\s*"ScanRegistryPolicies"'
        $script:AllManifestContent | Should -Not -Match '"Name"\s*:\s*"ScanRegistryPolicies"'
    }
}
