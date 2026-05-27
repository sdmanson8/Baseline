Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/DetectScriptblocks.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $script:DetectScriptblocksContent = Get-BaselineTestSourceText -Path $filePath
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Invoke-GuiDetectScriptblock' {
    BeforeEach {
        $script:DesignMode = $false
    }

    It 'returns the scriptblock result when Design Mode is off' {
        $result = Invoke-GuiDetectScriptblock -Detect { $true } -DefaultValue $false

        $result | Should -Be $true
    }

    It 'returns the manifest default when Design Mode is on' {
        $script:DesignMode = $true

        $result = Invoke-GuiDetectScriptblock -Detect { throw 'should not run' } -DefaultValue $true

        $result | Should -Be $true
    }

    It 'keeps missing object properties non-fatal for registry-style detection probes' {
        $result = Invoke-GuiDetectScriptblock -Detect {
            ([pscustomobject]@{}).MissingRegistryValue -ne 1
        } -DefaultValue $false

        $result | Should -Be $true
    }

    It 'routes expected detection catches through Write-SwallowedException and keeps Defender probes quiet' {
        $script:DetectScriptblocksContent | Should -Match 'DetectScriptblocks\.RegistryBackup\.LoadAutoRegBackupTask'
        $script:DetectScriptblocksContent | Should -Match 'function Get-GuiDetectMpPreference'
        $script:DetectScriptblocksContent | Should -Not -Match 'DetectScriptblocks\.NetworkProtection\.LoadMpPreference'
        $script:DetectScriptblocksContent | Should -Not -Match 'DetectScriptblocks\.DefenderScanCPULimit\.LoadMpPreference'
        $script:DetectScriptblocksContent | Should -Not -Match 'DetectScriptblocks\.DefenderSignatureUpdateInterval\.LoadMpPreference'
        $script:DetectScriptblocksContent | Should -Match 'DetectScriptblocks\.BlockStoreSearchResults\.LoadIdentitySid'
    }

    It 'keeps Windows Sandbox detection bounded outside the GUI runspace' {
        $script:DetectScriptblocksContent | Should -Match 'function Get-GuiDetectWindowsOptionalFeatureState'
        $script:DetectScriptblocksContent | Should -Match '\.WaitForExit\(\[Math\]::Max\(1, \$TimeoutSeconds\) \* 1000\)'
        $script:DetectScriptblocksContent | Should -Match '\$process\.Kill\(\)'
        $script:DetectScriptblocksContent | Should -Match "'WindowsSandbox' = \{ \(Get-GuiDetectWindowsOptionalFeatureState -FeatureName 'Containers-DisposableClientVM'\) -eq 'Enabled' \}"
        $script:DetectScriptblocksContent | Should -Not -Match "'WindowsSandbox' = \{ \(Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM"
    }
}
