Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Cursors.psm1'
    $script:CompilerParameters = $null

    $sourceText = Get-BaselineTestSourceText -Path $filePath
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    # Pre-register a dummy WinAPI.Cursor type so Cursors' final
    # [void][WinAPI.Cursor]::SystemParametersInfo(...) call succeeds under test.
    if (-not ('WinAPI.Cursor' -as [type])) {
        Add-Type -TypeDefinition @"
namespace WinAPI {
    public static class Cursor {
        public static bool SystemParametersInfo(uint uiAction, uint uiParam, uint pvParam, uint fWinIni) { return true; }
    }
}
"@ -Language CSharp
    }
}

Describe 'Cursors' {
    BeforeEach {
        $script:originalCursorArchiveUrl = $env:BASELINE_CURSOR_ARCHIVE_URL
        $env:BASELINE_CURSOR_ARCHIVE_URL = 'https://example.test/Windows11Cursors.zip'
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:downloadCalls = [System.Collections.Generic.List[object]]::new()
        $script:assertCalls = [System.Collections.Generic.List[object]]::new()
        $script:extractCalls = [System.Collections.Generic.List[object]]::new()
        $script:shouldThrowDownload = $false
        $script:shouldThrowAssert = $false
        $script:shouldThrowExtract = $false
        $script:pathExists = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-ItemPropertyValue {
            param([string]$Path, [string]$Name)
            return "$env:TEMP\TestDownloads"
        }
        function Invoke-DownloadFile {
            param([string]$Uri, [string]$OutFile)
            [void]$script:downloadCalls.Add([pscustomobject]@{ Uri = $Uri; OutFile = $OutFile })
            if ($script:shouldThrowDownload) { throw 'simulated download failure' }
        }
        function Assert-FileHash {
            param([string]$Path, [string]$ExpectedSha256, [string]$Label)
            [void]$script:assertCalls.Add([pscustomobject]@{ Path = $Path; ExpectedSha256 = $ExpectedSha256 })
            if ($script:shouldThrowAssert) { throw 'bad hash' }
        }
        function Expand-CursorArchiveFolder {
            param([string]$ArchivePath, [string]$DestinationPath, [string]$FolderName)
            [void]$script:extractCalls.Add([pscustomobject]@{
                ArchivePath = $ArchivePath
                DestinationPath = $DestinationPath
                FolderName = $FolderName
            })
            if ($script:shouldThrowExtract) { throw 'simulated extract failure' }
        }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [string]$ItemType, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
        function Start-Sleep { param([int]$Seconds) }
        function Remove-Item {
            param([string[]]$Path, [switch]$Force, [switch]$Recurse, [object]$ErrorAction)
        }
    }

    AfterEach {
        $env:BASELINE_CURSOR_ARCHIVE_URL = $script:originalCursorArchiveUrl
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-ItemPropertyValue','Invoke-DownloadFile','Assert-FileHash','Expand-CursorArchiveFolder','Test-Path','New-Item','Set-RegistryValueSafe','Start-Sleep','Remove-Item')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Dark/Light/Default' {
        { Cursors } | Should -Throw
    }

    It 'writes aero_arrow.cur values for the Default cursor scheme' {
        Cursors -Default

        $arrow = @($script:newItemPropertyCalls | Where-Object { $_.Name -eq 'Arrow' })
        $arrow.Count | Should -Be 1
        $arrow[0].Value | Should -Be '%SystemRoot%\cursors\aero_arrow.cur'

        $schemeSource = @($script:newItemPropertyCalls | Where-Object { $_.Name -eq 'Scheme Source' })
        $schemeSource[0].Value | Should -Be 2

        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'does not download an archive when Default is requested' {
        Cursors -Default

        $script:downloadCalls.Count | Should -Be 0
        $script:assertCalls.Count | Should -Be 0
    }

    It 'downloads and verifies the archive before installing dark cursors' {
        Cursors -Dark

        $script:downloadCalls.Count | Should -Be 1
        $script:downloadCalls[0].Uri | Should -Match 'Windows11Cursors\.zip$'
        $script:assertCalls.Count | Should -Be 1
        $script:assertCalls[0].ExpectedSha256 | Should -Match '^[0-9A-Fa-f]{64}$'
        $script:extractCalls.Count | Should -Be 1
        $script:extractCalls[0].FolderName | Should -Be 'dark'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs an error and stops if the download fails for Light' {
        $script:shouldThrowDownload = $true

        Cursors -Light

        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'download or verify'
        $script:newItemPropertyCalls.Count | Should -Be 0
    }

    It 'logs an error and stops if hash verification fails' {
        $script:shouldThrowDownload = $false
        $script:shouldThrowAssert = $true

        Cursors -Dark

        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'download or verify'
    }

    It 'logs an error if archive extraction fails' {
        $script:shouldThrowExtract = $true

        Cursors -Light

        $script:extractCalls.Count | Should -Be 1
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'light cursor theme'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }
}
