Set-StrictMode -Version Latest

# Covers the IsServer skip path for SharedExperiences (CDP / Connected Devices
# Platform — client-only) and ClipboardHistory (Win+V history — client-only).
# The other related toggles (DefenderAppGuard, WindowsSandbox,
# RevertStartMenu) get edition coverage in their own region tests; this file
# fills the gap left by PrivacyTelemetry.Tests.ps1, which whitelists a
# different set of functions and never loads these two.

BeforeAll {
    $sharedExpPath = Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.SystemSettings.psm1'
    $clipboardPath = Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.PrivacySettings.psm1'

    foreach ($path in @($sharedExpPath, $clipboardPath)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            if ($fn.Name -in @('SharedExperiences', 'ClipboardHistory')) {
                Invoke-Expression $fn.Extent.Text
            }
        }
    }
}

Describe 'SharedExperiences edition guard' {
    BeforeEach {
        $script:platformIsServer = $false
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()

        $Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }
        $script:Localization = $Localization

        function Get-TweakSkipLabel { param($Invocation) return 'SharedExperiences' }
        function Get-BaselineSystemPlatformInfo {
            [pscustomobject]@{
                IsServer = $script:platformIsServer
                IsWindows10 = $false
                IsWindows11 = (-not $script:platformIsServer)
                BuildNumber = 22631
                EditionID = 'Professional'
                Architecture = 'amd64'
                MajorVersion = 10
                ProductType = if ($script:platformIsServer) { 3 } else { 1 }
                ServerRelease = $null
                DisplayName = 'Test'
            }
        }
        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
        function Test-Path { param([string]$Path) return $true }
        function New-Item { param([string]$Path, $ErrorAction) }
    }

    AfterEach {
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineSystemPlatformInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
    }

    It 'silently skips -Enable on Windows Server without writing CDP keys' {
        $script:platformIsServer = $true
        SharedExperiences -Enable

        $script:setRegistryCalls.Count | Should -Be 0
        $script:warningMessages -join ' ' | Should -Match 'Skipped'
    }

    It 'silently skips -Disable on Windows Server without writing CDP keys' {
        $script:platformIsServer = $true
        SharedExperiences -Disable

        $script:setRegistryCalls.Count | Should -Be 0
        $script:warningMessages -join ' ' | Should -Match 'Skipped'
    }

    It 'writes the CDP enable key on a client SKU' {
        $script:platformIsServer = $false
        SharedExperiences -Enable

        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'RomeSdkChannelUserAuthzPolicy'
        $script:setRegistryCalls[0].Value | Should -Be 1
    }
}

Describe 'ClipboardHistory edition guard' {
    BeforeEach {
        $script:platformIsServer = $false
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()

        $Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }
        $script:Localization = $Localization

        function Get-TweakSkipLabel { param($Invocation) return 'ClipboardHistory' }
        function Get-BaselineSystemPlatformInfo {
            [pscustomobject]@{
                IsServer = $script:platformIsServer
                IsWindows10 = $false
                IsWindows11 = (-not $script:platformIsServer)
                BuildNumber = 22631
                EditionID = 'Professional'
                Architecture = 'amd64'
                MajorVersion = 10
                ProductType = if ($script:platformIsServer) { 3 } else { 1 }
                ServerRelease = $null
                DisplayName = 'Test'
            }
        }
        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Test-Path { param([string]$Path) return $true }
        function Get-ItemProperty { param([string]$Path, [string]$Name, $ErrorAction) [pscustomobject]@{ EnableClipboardHistory = 1 } }
        function New-Item { param([string]$Path, $Force, $ErrorAction) }
    }

    AfterEach {
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineSystemPlatformInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
    }

    It 'silently skips -Enable on Windows Server without touching the Clipboard registry' {
        $script:platformIsServer = $true
        ClipboardHistory -Enable

        $script:setRegistryCalls.Count | Should -Be 0
        $script:warningMessages -join ' ' | Should -Match 'Skipped'
    }

    It 'silently skips -Disable on Windows Server without touching the Clipboard registry' {
        $script:platformIsServer = $true
        ClipboardHistory -Disable

        $script:removeRegistryCalls.Count | Should -Be 0
        $script:warningMessages -join ' ' | Should -Match 'Skipped'
    }

    It 'writes EnableClipboardHistory=1 on a client SKU' {
        $script:platformIsServer = $false
        ClipboardHistory -Enable

        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'EnableClipboardHistory'
        $script:setRegistryCalls[0].Value | Should -Be 1
    }
}
