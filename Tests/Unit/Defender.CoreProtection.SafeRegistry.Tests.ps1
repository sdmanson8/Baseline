Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.CoreProtection.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('AccountProtectionWarn', 'DownloadBlocking')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Defender core-protection registry toggles' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path {
            param([string]$Path)
            return $script:pathExists
        }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes and clears the Microsoft account warning through the safe registry helper' {
        $script:pathExists = $true

        AccountProtectionWarn -Enable
        AccountProtectionWarn -Disable

        $script:removeRegistryCalls.Count | Should -Be 1
        $script:removeRegistryCalls[0].Name | Should -Be 'AccountProtection_MicrosoftAccount_Disconnected'
        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'AccountProtection_MicrosoftAccount_Disconnected'
        $script:setRegistryCalls[0].Value | Should -Be 1
    }

    It 'writes and clears the download-blocking policy through the safe registry helper' {
        $script:pathExists = $true

        DownloadBlocking -Enable
        $script:pathExists = $false
        DownloadBlocking -Disable

        $script:removeRegistryCalls.Count | Should -Be 1
        $script:removeRegistryCalls[0].Name | Should -Be 'SaveZoneInformation'
        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'SaveZoneInformation'
        $script:setRegistryCalls[0].Value | Should -Be 1
    }
}
