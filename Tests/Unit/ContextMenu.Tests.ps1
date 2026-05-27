Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    # Json helpers must load first — ContextMenu calls ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/ContextMenu.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'CABInstallContext' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-Item {
            param([string]$Path, [switch]$Recurse, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemCalls.Add($Path)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','New-ItemProperty','Remove-Item')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Show or Hide' {
        { CABInstallContext } | Should -Throw
    }

    It 'writes the DISM command-line on Show' {
        CABInstallContext -Show

        # One of the property writes should contain the DISM command template
        $commandWrite = @($script:newItemPropertyCalls | Where-Object { $_.Value -match 'DISM\.exe' })
        $commandWrite.Count | Should -BeGreaterThan 0
        $commandWrite[0].Value | Should -Match '/Add-Package'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'creates the key on Show when Test-Path returns false' {
        $script:pathExists = $false

        CABInstallContext -Show

        $script:newItemCalls.Count | Should -Be 1
    }

    It 'removes the runas key on Hide' {
        $script:pathExists = $true

        CABInstallContext -Hide

        $script:removeItemCalls.Count | Should -Be 1
        $script:removeItemCalls[0] | Should -Match 'CABFolder\\Shell\\runas'
    }

    It 'does not remove the runas key on Hide when it does not exist' {
        $script:pathExists = $false

        CABInstallContext -Hide

        $script:removeItemCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'MultipleInvokeContext' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes MultipleInvokePromptMinimum=300 on Enable' {
        MultipleInvokeContext -Enable

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Name | Should -Be 'MultipleInvokePromptMinimum'
        $script:setRegistrySafeCalls[0].Value | Should -Be 300
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes MultipleInvokePromptMinimum on Disable' {
        MultipleInvokeContext -Disable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'MultipleInvokePromptMinimum'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failure and logs an error if registry op throws' {
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            throw 'reg write failed'
        }

        MultipleInvokeContext -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'reg write failed'
    }
}

Describe 'EditWithPaintContext (appx-gated)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:paintInstalled = $true
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Get-AppxPackage {
            param([string]$Name, [object]$WarningAction)
            if ($script:paintInstalled) { return [pscustomobject]@{ Name = $Name } }
            return $null
        }
        function Get-TweakSkipLabel { param($Invocation) return 'EditWithPaintContext' }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
        }
        function Test-Path { param([string]$Path) return $true }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-AppxPackage','Get-TweakSkipLabel','Remove-ItemProperty','Test-Path','New-Item','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'skips when the Paint appx package is not present' {
        $script:paintInstalled = $false

        EditWithPaintContext -Hide

        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Skipped'
        $script:setRegistrySafeCalls.Count | Should -Be 0
    }

    It 'writes the block-list string on Hide when Paint is installed' {
        $script:paintInstalled = $true

        EditWithPaintContext -Hide

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Name | Should -Be '{2430F218-B743-4FD6-97BF-5C76541B4AE9}'
    }

    It 'removes the block-list entry on Show when Paint is installed' {
        $script:paintInstalled = $true

        EditWithPaintContext -Show

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be '{2430F218-B743-4FD6-97BF-5C76541B4AE9}'
    }
}

Describe 'Set-TakeOwnershipContextMenu' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-Item {
            param([string]$Path, [switch]$Recurse, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemCalls.Add($Path)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-ItemProperty','Remove-Item')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'creates both TakeOwnership and command keys on Add and writes the takeown command' {
        $script:pathExists = $false

        Set-TakeOwnershipContextMenu -Add

        $script:newItemCalls.Count | Should -Be 2
        $commandWrite = @($script:setItemPropertyCalls | Where-Object { $_.Value -match 'takeown' })
        $commandWrite.Count | Should -BeGreaterThan 0
        $commandWrite[0].Value | Should -Match 'icacls'
        $muiWrite = @($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'MUIVerb' })
        $muiWrite[0].Value | Should -Be 'Take Ownership'
    }

    It 'deletes the TakeOwnership key on Remove when it exists' {
        $script:pathExists = $true

        Set-TakeOwnershipContextMenu -Remove

        $script:removeItemCalls.Count | Should -Be 1
        $script:removeItemCalls[0] | Should -Match 'TakeOwnership'
    }
}

Describe 'TakeOwnership ContextMenu JSON entry' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $jsonPath = Join-Path $PSScriptRoot '..\..\Module\Data\ContextMenu.json'
        $script:contextMenuJson = Get-BaselineTestSourceText -Path $jsonPath | ConvertFrom-Json
        $script:takeOwnershipEntry = $script:contextMenuJson.Entries | Where-Object { $_.Function -eq 'TakeOwnershipContextMenu' }
    }

    It 'exposes TakeOwnershipContextMenu as a Toggle entry' {
        $script:takeOwnershipEntry | Should -Not -BeNullOrEmpty
        $script:takeOwnershipEntry.Type | Should -Be 'Toggle'
        $script:takeOwnershipEntry.OnParam | Should -Be 'Add'
        $script:takeOwnershipEntry.OffParam | Should -Be 'Remove'
    }

    It 'ships Caution=$true with a Defender ASR mitigation reason' {
        $script:takeOwnershipEntry.Caution | Should -BeTrue
        $script:takeOwnershipEntry.CautionReason | Should -Match 'ASR'
        $script:takeOwnershipEntry.CautionReason | Should -Match 'takeown\.exe'
    }

    It 'surfaces the takeown.exe ASR exclusion guidance in Description' {
        $script:takeOwnershipEntry.Description | Should -Match 'Defender'
        $script:takeOwnershipEntry.Description | Should -Match 'takeown\.exe'
    }

    It 'tags the entry with defender-asr so future audits can find it' {
        $script:takeOwnershipEntry.Tags | Should -Contain 'defender-asr'
    }

    It 'defaults to off (WinDefault=$false, Default=$false) so users opt in' {
        $script:takeOwnershipEntry.Default | Should -BeFalse
        $script:takeOwnershipEntry.WinDefault | Should -BeFalse
    }
}

Describe 'Set-FileExtensionsContextMenu' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:regCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:regCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes ShowFileExtensions=1 on Enable' {
        Set-FileExtensionsContextMenu -Enable

        $script:regCalls.Count | Should -Be 1
        $script:regCalls[0].Name | Should -Be 'ShowFileExtensions'
        $script:regCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes ShowFileExtensions on Disable' {
        Set-FileExtensionsContextMenu -Disable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'ShowFileExtensions'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'OpenWindowsTerminalAdminContext' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:getContentPaths = [System.Collections.Generic.List[string]]::new()
        $script:setContentPaths = [System.Collections.Generic.List[string]]::new()
        $script:startProcessPaths = [System.Collections.Generic.List[string]]::new()
        $script:stopProcessNames = [System.Collections.Generic.List[string]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:testPathResults = @{}
        $script:terminalInstalled = $true
        $script:terminalPackageFamily = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'
        $script:wtCommandPath = 'C:\Program Files\WindowsApps\wt.exe'
        $script:originalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = 'C:\Users\Test\AppData\Local'
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-AppxPackage {
            param([string]$Name, [object]$WarningAction)
            if ($script:terminalInstalled) {
                return [pscustomobject]@{
                    Name = $Name
                    PackageFamilyName = $script:terminalPackageFamily
                }
            }
            return $null
        }
        function Get-TweakSkipLabel { param($Invocation) return 'OpenWindowsTerminalAdminContext' }
        function Test-Path {
            param([string]$Path)
            return [bool]$script:testPathResults[$Path]
        }
        function Get-Command {
            param([string]$Name, [object]$ErrorAction)
            if (-not [string]::IsNullOrWhiteSpace($script:wtCommandPath)) {
                return [pscustomobject]@{ Path = $script:wtCommandPath }
            }
            return $null
        }
        function Start-Process {
            param([string]$FilePath, [switch]$PassThru)
            [void]$script:startProcessPaths.Add($FilePath)
            return [pscustomobject]@{}
        }
        function Start-Sleep { param([int]$Seconds) }
        function Stop-Process {
            param([string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:stopProcessNames.Add($Name)
        }
        function Get-Content {
            param([string]$Path, [object]$Encoding, [switch]$Force)
            [void]$script:getContentPaths.Add($Path)
            return '{"profiles":{"defaults":{}}}'
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Set-Content {
            param(
                [Parameter(ValueFromPipeline = $true)]
                [object]$Value,
                [string]$Path,
                [object]$Encoding,
                [switch]$Force
            )
            begin { }
            process { }
            end { [void]$script:setContentPaths.Add($Path) }
        }
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:originalLocalAppData
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-AppxPackage','Get-TweakSkipLabel','Test-Path','Get-Command','Start-Process','Start-Sleep','Stop-Process','Get-Content','Remove-RegistryValueSafe','Set-Content')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'uses the package family localstate path instead of a hardcoded Terminal path' {
        $script:terminalPackageFamily = 'Contoso.WindowsTerminal_abcd1234'
        $expectedPath = Join-Path $env:LOCALAPPDATA "Packages\$($script:terminalPackageFamily)\LocalState\settings.json"
        $script:testPathResults[$expectedPath] = $true

        OpenWindowsTerminalAdminContext -Enable

        $script:getContentPaths.Count | Should -Be 1
        $script:getContentPaths[0] | Should -Be $expectedPath
        $script:setContentPaths.Count | Should -Be 1
        $script:setContentPaths[0] | Should -Be $expectedPath
    }

    It 'warns and skips when the Terminal settings file is still missing after probing' {
        $expectedPath = Join-Path $env:LOCALAPPDATA "Packages\$($script:terminalPackageFamily)\LocalState\settings.json"
        $script:testPathResults[$expectedPath] = $false
        $script:wtCommandPath = $null

        OpenWindowsTerminalAdminContext -Disable

        $script:getContentPaths.Count | Should -Be 0
        $script:errorMessages.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 2
        $script:warningMessages[0] | Should -Match 'settings file not found'
        $script:warningMessages[1] | Should -Match 'Skipped'
    }
}
