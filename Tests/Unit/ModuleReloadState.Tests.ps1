Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:LoaderPath = Join-Path $PSScriptRoot '../../Module/Baseline.psm1'
    $script:GuiRegionPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:StateDocPath = Join-Path $PSScriptRoot '../../dev_docs/STATE.md'
    $script:LoaderContent = Get-BaselineTestSourceText -Path $script:LoaderPath
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path $script:GuiRegionPath
    $script:StateDocContent = Get-BaselineTestSourceText -Path $script:StateDocPath
}

Describe 'Module reload state visibility' {
    It 'logs when module reload resets session statistics because the log path changed' {
        $script:LoaderContent | Should -Match 'Initialize-SessionStatistics'
        $script:LoaderContent | Should -Match '\$statisticsInitialized = \(\$existingSessionStats -and \$existingSessionStats\.ContainsKey\(''SessionStartTime''\)'
        $script:LoaderContent | Should -Match 'if \(\(-not \$alreadyInitialized\) -or \(-not \$statisticsInitialized\)\)'
        $script:LoaderContent | Should -Match 'LogWarning\s+\("Baseline loader reset session statistics after module reload because the log path changed from'
    }

    It 'marks GUI sessions in session statistics before the WPF window is shown' {
        $script:GuiRegionContent | Should -Match 'function Show-TweakGUI'
        $script:GuiRegionContent | Should -Match 'Update-SessionStatistics -Values @\{ IsGUI = \$true \}'
    }

    It 'imports core modules with immediate terminating failures and clear module names' {
        $script:LoaderContent | Should -Match '\$coreModuleImports = @\('
        $script:LoaderContent | Should -Match 'Logging\.psm1'
        $script:LoaderContent | Should -Match 'SharedHelpers\.psm1'
        $script:LoaderContent | Should -Match 'GUICommon\.psm1'
        $script:LoaderContent | Should -Match 'GUIExecution\.psm1'
        $script:LoaderContent | Should -Match 'Import-Module -Name \$coreImport\.Path.*-ErrorAction Stop'
        $script:LoaderContent | Should -Match 'Failed to import core module'
        $script:LoaderContent | Should -Match 'throw'
    }

    It 'fails immediately when a core module import is missing' {
        $moduleRoot = Join-Path $TestDrive 'Module'
        [void](New-Item -ItemType Directory -Path $moduleRoot -Force)
        Set-Content -LiteralPath (Join-Path $moduleRoot 'Baseline.psm1') -Value $script:LoaderContent -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $moduleRoot 'Logging.psm1') -Value @'
function LogError { param([string]$Message) $script:LastLoaderError = $Message }
function Set-LogFile { param([string]$Path) }
function Initialize-SessionStatistics { }
'@ -Encoding UTF8

        { Import-Module (Join-Path $moduleRoot 'Baseline.psm1') -Force -ErrorAction Stop } |
            Should -Throw '*Failed to import core module ''SharedHelpers.psm1''*'
    }

    It 'documents loader reload resets in STATE.md' {
        $script:StateDocContent | Should -Match 'Loader reload behaviour'
        $script:StateDocContent | Should -Match 'session statistics'
        $script:StateDocContent | Should -Match 'log path'
    }
}
