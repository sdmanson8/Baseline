Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Test-BaselineAdobeReaderInstalled', 'AdobereaderDCSTIG')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Test-BaselineAdobeReaderInstalled' {
    BeforeEach {
        $script:pathExistsLookup = @{}
        function Test-Path {
            param([string]$Path)
            if ($script:pathExistsLookup.ContainsKey($Path)) { return [bool]$script:pathExistsLookup[$Path] }
            return $false
        }
    }

    AfterEach {
        Microsoft.PowerShell.Management\Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
    }

    It 'returns $false when none of the Reader detection paths exist' {
        Test-BaselineAdobeReaderInstalled | Should -BeFalse
    }

    It 'returns $true when any canonical Reader detection path exists' {
        foreach ($path in @(
            'HKLM:\Software\Adobe\Acrobat Reader\DC'
            'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC'
            'HKCU:\Software\Adobe\Acrobat Reader\DC'
            'HKCU:\Software\Policies\Adobe\Acrobat Reader\DC\Privileged'
        ))
        {
            $script:pathExistsLookup.Clear()
            $script:pathExistsLookup[$path] = $true
            Test-BaselineAdobeReaderInstalled | Should -BeTrue
        }
    }
}

Describe 'AdobereaderDCSTIG' {
    BeforeEach {
        $script:consoleStatuses     = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages     = [System.Collections.Generic.List[string]]::new()
        $script:logWarnMessages     = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls        = [System.Collections.Generic.List[string]]::new()
        $script:setRegistryCalls    = [System.Collections.Generic.List[object]]::new()
        $script:pathExistsLookup    = @{}

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo    { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:logWarnMessages.Add($Message) }
        function LogError   { param([string]$Message) }
        function Test-Path {
            param([string]$Path)
            if ($script:pathExistsLookup.ContainsKey($Path)) { return [bool]$script:pathExistsLookup[$Path] }
            return $false
        }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Test-Path','New-Item','Set-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'short-circuits with success status when Reader is not installed' {
        # All four detection paths return $false → skip with a warning.
        AdobereaderDCSTIG

        $script:newItemCalls.Count | Should -Be 0
        $script:setRegistryCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
        ($script:logWarnMessages | Where-Object { $_ -match 'not installed' }).Count | Should -BeGreaterThan 0
    }

    It 'detects Reader via the HKLM machine-wide install key and proceeds' {
        $script:pathExistsLookup['HKLM:\Software\Adobe\Acrobat Reader\DC'] = $true

        AdobereaderDCSTIG

        $script:setRegistryCalls.Count | Should -BeGreaterThan 0
    }

    It 'writes the canonical Protected Mode + Protected View + Enhanced Security policy values' {
        $script:pathExistsLookup['HKLM:\Software\Policies\Adobe\Acrobat Reader\DC'] = $true

        AdobereaderDCSTIG

        $featureLockDown = 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown'
        $names = $script:setRegistryCalls | Where-Object { $_.Path -eq $featureLockDown } | Select-Object -ExpandProperty Name
        $names | Should -Contain 'bProtectedMode'
        $names | Should -Contain 'iProtectedView'
        $names | Should -Contain 'bEnhancedSecurityInBrowser'
        $names | Should -Contain 'bEnhancedSecurityStandalone'
        ($script:setRegistryCalls | Where-Object { $_.Name -eq 'bProtectedMode' -and $_.Path -eq $featureLockDown }).Value | Should -Be 1
        ($script:setRegistryCalls | Where-Object { $_.Name -eq 'iProtectedView' -and $_.Path -eq $featureLockDown }).Value | Should -Be 2
    }

    It 'disables Adobe cloud / Sign / Document Services' {
        $script:pathExistsLookup['HKLM:\Software\Adobe\Acrobat Reader\DC'] = $true

        AdobereaderDCSTIG

        $servicesPath = 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown\cServices'
        $names = $script:setRegistryCalls | Where-Object { $_.Path -eq $servicesPath } | Select-Object -ExpandProperty Name
        $names | Should -Contain 'bToggleAdobeDocumentServices'
        $names | Should -Contain 'bToggleAdobeSign'
        $names | Should -Contain 'bUpdater'
    }

    It 'disables Flash via bEnableFlash=0' {
        $script:pathExistsLookup['HKLM:\Software\Adobe\Acrobat Reader\DC'] = $true

        AdobereaderDCSTIG

        $featureLockDown = 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown'
        $flashCall = $script:setRegistryCalls | Where-Object { $_.Name -eq 'bEnableFlash' -and $_.Path -eq $featureLockDown }
        $flashCall | Should -Not -BeNullOrEmpty
        $flashCall.Value | Should -Be 0
    }

    It 'creates each policy subkey when missing before writing into it' {
        $script:pathExistsLookup['HKLM:\Software\Adobe\Acrobat Reader\DC'] = $true
        # Every subkey starts missing — every one should get a New-Item.

        AdobereaderDCSTIG

        $script:newItemCalls | Should -Contain 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC'
        $script:newItemCalls | Should -Contain 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown'
        $script:newItemCalls | Should -Contain 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown\cCloud'
        $script:newItemCalls | Should -Contain 'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown\cServices'
    }

    It 'writes DisableMaintenance=1 to both the native and Wow6432 installer paths' {
        $script:pathExistsLookup['HKLM:\Software\Adobe\Acrobat Reader\DC'] = $true

        AdobereaderDCSTIG

        $native = $script:setRegistryCalls | Where-Object { $_.Name -eq 'DisableMaintenance' -and $_.Path -eq 'HKLM:\Software\Adobe\Acrobat Reader\DC\Installer' }
        $wow    = $script:setRegistryCalls | Where-Object { $_.Name -eq 'DisableMaintenance' -and $_.Path -eq 'HKLM:\Software\Wow6432Node\Adobe\Acrobat Reader\DC\Installer' }
        $native | Should -Not -BeNullOrEmpty
        $wow    | Should -Not -BeNullOrEmpty
        $native.Value | Should -Be 1
        $wow.Value    | Should -Be 1
    }

    It 'overrides the per-user privileged Protected Mode override only when that path exists' {
        $script:pathExistsLookup['HKCU:\Software\Adobe\Acrobat Reader\DC'] = $true
        $script:pathExistsLookup['HKCU:\Software\Policies\Adobe\Acrobat Reader\DC\Privileged'] = $true

        AdobereaderDCSTIG

        $userOverride = $script:setRegistryCalls | Where-Object { $_.Path -eq 'HKCU:\Software\Policies\Adobe\Acrobat Reader\DC\Privileged' -and $_.Name -eq 'bProtectedMode' }
        $userOverride | Should -Not -BeNullOrEmpty
        $userOverride.Value | Should -Be 0
    }
}
