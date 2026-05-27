Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:ModuleManifestPath = Join-Path $PSScriptRoot '../../Module/Baseline.psd1'
    $script:ShortcutLauncherPath = Join-Path $PSScriptRoot '../../ShortcutLauncher/Program.cs'

    $script:RuntimeContractFiles = @(
        (Join-Path $PSScriptRoot '../../Module/SharedHelpers/ScenarioMode.Helpers.ps1')
        (Join-Path $PSScriptRoot '../../Module/GUI/SystemScan.ps1')
        (Join-Path $PSScriptRoot '../../Module/GUI/PresetManagement.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Add-MissingMetadata.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Generate-PresetFiles.ps1')
    )

    $script:ExampleFiles = @(
        (Join-Path $PSScriptRoot '../../Tools/Validate-ManifestData.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Test-SmokeTest.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Test-ReleaseSmoke.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Test-ScreenshotDrift.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Test-PresetGeneration.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Test-DocumentationConsistency.ps1')
        (Join-Path $PSScriptRoot '../../Tools/New-ReleasePackage.ps1')
        (Join-Path $PSScriptRoot '../../Tools/New-InstallerPackage.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Zip.Helpers.ps1')
        (Join-Path $PSScriptRoot '../../Tools/New-IncidentReproductionPack.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Invoke-LifecyclePlaybook.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Get-EmbeddedRuntimeSurface.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Generate-PresetFiles.ps1')
        (Join-Path $PSScriptRoot '../../Tools/Export-TestReport.ps1')
        (Join-Path $PSScriptRoot '../../Tests/README.md')
        (Join-Path $PSScriptRoot '../../Tests/Integration/README.md')
        (Join-Path $PSScriptRoot '../../Tests/Integration/IntegrationTest.ps1')
        (Join-Path $PSScriptRoot '../../Tests/Integration/Test-RegistryTweak.ps1')
    )

    $script:JsonCompatibilityFiles = @(
        (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Preset.Helpers.ps1')
        (Join-Path $PSScriptRoot '../../Module/SharedHelpers/SupportBundle.Helpers.ps1')
        (Join-Path $PSScriptRoot '../../Module/Regions/ContextMenu.psm1')
    )
}

Describe 'PowerShell 5.1 support contract' {
    It 'marks the loader module as Windows PowerShell Desktop only' {
        $content = Get-BaselineTestSourceText -Path $script:ModuleManifestPath

        $content | Should -Match "CompatiblePSEditions\s*=\s*@\('Desktop'\)"
        $content | Should -Match "PowerShellVersion\s*=\s*'5\.1'"
        $content | Should -Not -Match "CompatiblePSEditions\s*=\s*@\('Core'"
    }

    It 'keeps the shortcut launcher pinned to trusted Windows PowerShell paths' {
        $content = Get-BaselineTestSourceText -Path $script:ShortcutLauncherPath

        $content | Should -Not -Match 'FindOnPath'
        $content | Should -Not -Match 'EnvironmentVariable\("PATH"\)'
        $content | Should -Match '"WindowsPowerShell",\s*"v1\.0",\s*"powershell\.exe"'
        $content | Should -Match 'Sysnative'
        $content | Should -Match 'System32'
        $content | Should -Not -Match 'pwsh\.exe'
        $content | Should -Match 'Windows PowerShell 5\.1 \(powershell\.exe\) was not found at the trusted System32 path\.'
        $content | Should -Match 'FileNotFoundException'
    }

    It 'documents and enforces the shortcut launcher as GUI-only fire-and-forget' {
        $content = Get-BaselineTestSourceText -Path $script:ShortcutLauncherPath

        $content | Should -Match 'private static int Main\(string\[\] args\)'
        $content | Should -Match 'does not accept command-line arguments'
        $content | Should -Match 'Run Baseline\.exe directly for CLI workflows'
        $content | Should -Not -Match 'WaitForExit\(\)'
    }

    It 'keeps runtime curation helpers from selecting PowerShell 7 as the Baseline host' {
        foreach ($path in $script:RuntimeContractFiles) {
            $content = Get-BaselineTestSourceText -Path $path

            $content | Should -Not -Match '\bpwsh(?:\.exe)?\b'
        }
    }

    It 'keeps maintainer examples on powershell.exe' {
        foreach ($path in $script:ExampleFiles) {
            $content = Get-BaselineTestSourceText -Path $path

            $content | Should -Not -Match '\bpwsh\b'
        }
    }

    It 'uses JSON helper calls instead of PowerShell major-version gates in runtime modules' {
        foreach ($path in $script:JsonCompatibilityFiles) {
            $content = Get-BaselineTestSourceText -Path $path

            $content | Should -Not -Match 'PSVersionTable\.PSVersion\.Major\s+-ge\s+6'
            $content | Should -Match 'ConvertFrom-BaselineJson\s+-Depth\s+\d+'
        }
    }
}
