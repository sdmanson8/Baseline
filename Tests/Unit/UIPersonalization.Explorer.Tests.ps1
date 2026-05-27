Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UIPersonalization/UIPersonalization.Explorer.psm1'
    $source = Get-Content -Raw $filePath
    $source = [regex]::Replace($source, '^using module[^\r\n]*[\r\n]+', '', 'Multiline')
    $sb = [scriptblock]::Create($source)
    $ast = $sb.Ast
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'UIPersonalization.Explorer toggle functions' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:hasExistingProperty = $false
        $script:shouldThrow = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force)
            if ($script:shouldThrow) { throw 'new-itemproperty failed' }
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value; PropertyType = $PropertyType })
        }
        function Set-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value)
            if ($script:shouldThrow) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Get-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$Name)
            if ($script:hasExistingProperty) { return [pscustomobject]@{ $Name = 1 } }
            return $null
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:shouldThrow) { throw 'set-registryvaluesafe failed' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistrySafeCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','New-ItemProperty','Set-ItemProperty','Get-ItemProperty','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    Context 'FileDeleteConfirm' {
        It 'requires Enable or Disable' {
            { FileDeleteConfirm } | Should -Throw
        }

        It 'creates the policy key and writes ConfirmFileDelete=1 on Enable when missing' {
            $script:pathExists = $false

            FileDeleteConfirm -Enable

            $script:newItemCalls.Count | Should -Be 1
            $script:setRegistrySafeCalls[0].Name | Should -Be 'ConfirmFileDelete'
            $script:setRegistrySafeCalls[0].Value | Should -Be 1
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'removes ConfirmFileDelete on Disable when the property exists' {
            $script:pathExists = $true
            $script:hasExistingProperty = $true

            FileDeleteConfirm -Disable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'ConfirmFileDelete'
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'reports failed when Set-RegistryValueSafe throws' {
            $script:pathExists = $true
            $script:shouldThrow = $true

            FileDeleteConfirm -Enable

            $script:consoleStatuses[-1] | Should -Be 'failed'
            $script:errorMessages[0] | Should -Match 'set-registryvaluesafe failed'
        }
    }

    Context 'FileExtensions' {
        It 'writes HideFileExt=0 on Show (show extensions)' {
            FileExtensions -Show

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'HideFileExt' }).Value | Should -Be 0
        }

        It 'writes HideFileExt=1 on Hide (hide extensions)' {
            FileExtensions -Hide

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'HideFileExt' }).Value | Should -Be 1
        }
    }

    Context 'HiddenItems' {
        It 'writes Hidden=1 on Enable' {
            HiddenItems -Enable

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'Hidden' }).Value | Should -Be 1
        }

        It 'writes Hidden=2 on Disable' {
            HiddenItems -Disable

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'Hidden' }).Value | Should -Be 2
        }
    }

    Context 'OpenFileExplorerTo' {
        It 'writes LaunchTo=1 on -ThisPC' {
            OpenFileExplorerTo -ThisPC

            $script:setRegistrySafeCalls[0].Name | Should -Be 'LaunchTo'
            $script:setRegistrySafeCalls[0].Value | Should -Be 1
        }

        It 'writes LaunchTo=2 on -QuickAccess' {
            OpenFileExplorerTo -QuickAccess

            $script:setRegistrySafeCalls[0].Value | Should -Be 2
        }

        It 'writes LaunchTo=3 on -Downloads' {
            OpenFileExplorerTo -Downloads

            $script:setRegistrySafeCalls[0].Value | Should -Be 3
        }
    }

    Context 'JPEGWallpapersQuality' {
        It 'writes JPEGImportQuality=100 on Max' {
            JPEGWallpapersQuality -Max

            $script:setRegistrySafeCalls[0].Name | Should -Be 'JPEGImportQuality'
            $script:setRegistrySafeCalls[0].Value | Should -Be 100
        }

        It 'removes JPEGImportQuality on Default when the value exists' {
            $script:hasExistingProperty = $true

            JPEGWallpapersQuality -Default

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'JPEGImportQuality'
        }
    }

    Context 'Set-StartupAppDelay' {
        It 'writes StartupDelayInMSec=2000 on Enable' {
            Set-StartupAppDelay -Enable

            $script:setRegistrySafeCalls[0].Name | Should -Be 'StartupDelayInMSec'
            $script:setRegistrySafeCalls[0].Value | Should -Be 2000
            $script:setRegistrySafeCalls[0].Type | Should -Be 'DWord'
        }

        It 'removes StartupDelayInMSec on Disable' {
            Set-StartupAppDelay -Disable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'StartupDelayInMSec'
        }
    }

    Context 'Set-ExplorerBrowseMode' {
        It 'writes BrowseNewProcess=0 on -SameWindow' {
            Set-ExplorerBrowseMode -SameWindow

            $script:setRegistrySafeCalls[0].Name | Should -Be 'BrowseNewProcess'
            $script:setRegistrySafeCalls[0].Value | Should -Be 0
        }

        It 'writes BrowseNewProcess=1 on -NewWindow' {
            Set-ExplorerBrowseMode -NewWindow

            $script:setRegistrySafeCalls[0].Value | Should -Be 1
        }
    }

    Context 'SuperHiddenFiles' {
        It 'writes ShowSuperHidden=1 on Enable' {
            SuperHiddenFiles -Enable

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShowSuperHidden' }).Value | Should -Be 1
        }

        It 'writes ShowSuperHidden=0 on Disable' {
            SuperHiddenFiles -Disable

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShowSuperHidden' }).Value | Should -Be 0
        }
    }

    Context 'CheckBoxes' {
        It 'writes AutoCheckSelect=1 on Enable' {
            CheckBoxes -Enable

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'AutoCheckSelect' }).Value | Should -Be 1
        }

        It 'writes AutoCheckSelect=0 on Disable' {
            CheckBoxes -Disable

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'AutoCheckSelect' }).Value | Should -Be 0
        }
    }

    Context 'Set-ShowHomeFolderInNavPane' {
        It 'removes the None value on Enable' {
            Set-ShowHomeFolderInNavPane -Enable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'None'
        }

        It 'creates the namespace key and writes None="" on Disable when path missing' {
            $script:pathExists = $false

            Set-ShowHomeFolderInNavPane -Disable

            $script:newItemCalls.Count | Should -Be 1
            $script:setRegistrySafeCalls[0].Name | Should -Be 'None'
            $script:setRegistrySafeCalls[0].Type | Should -Be 'String'
        }
    }

    Context 'Set-ShowGalleryInNavPane' {
        It 'removes the None value on Enable' {
            Set-ShowGalleryInNavPane -Enable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'None'
        }

        It 'creates the gallery namespace key and writes None="" on Disable when path missing' {
            $script:pathExists = $false

            Set-ShowGalleryInNavPane -Disable

            $script:newItemCalls.Count | Should -Be 1
            $script:setRegistrySafeCalls[0].Path | Should -Match 'e88865ea'
        }
    }
}
