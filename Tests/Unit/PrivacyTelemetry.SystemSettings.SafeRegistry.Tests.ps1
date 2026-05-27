Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.SystemSettings.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('SharedExperiences', 'WebLangList')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Privacy telemetry system-settings registry toggles' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $true
        $script:isServer = $false

        $script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-BaselineSystemPlatformInfo {
            [pscustomobject]@{ IsServer = $script:isServer }
        }
        function Get-TweakSkipLabel {
            param($Invocation)
            return 'PrivacyTelemetry.SystemSettings'
        }
        function Test-Path {
            param([string]$Path)
            return $script:pathExists
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-BaselineSystemPlatformInfo','Get-TweakSkipLabel','Test-Path','Set-RegistryValueSafe','Remove-RegistryValueSafe','New-Item')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'routes Shared Experiences through the safe registry helper' {
        SharedExperiences -Enable
        SharedExperiences -Disable

        $script:setRegistryCalls.Count | Should -Be 2
        ($script:setRegistryCalls | Where-Object { $_.Name -eq 'RomeSdkChannelUserAuthzPolicy' }).Count | Should -Be 2
        $script:setRegistryCalls[0].Value | Should -Be 1
        $script:setRegistryCalls[1].Value | Should -Be 0
    }

    It 'routes the language-list toggle through the safe registry helper' {
        WebLangList -Enable
        WebLangList -Disable

        $script:removeRegistryCalls.Count | Should -Be 1
        $script:removeRegistryCalls[0].Name | Should -Be 'HttpAcceptLanguageOptOut'
        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'HttpAcceptLanguageOptOut'
        $script:setRegistryCalls[0].Value | Should -Be 1
    }
}
