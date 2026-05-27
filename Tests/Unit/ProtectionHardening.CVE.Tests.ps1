Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('CertPaddingCheck','ActiveXLockdown','MsMsdtHandler')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'CertPaddingCheck (CVE-2013-3900)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:throwOnSet = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnSet) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'creates both Wintrust\Config paths when missing and writes EnableCertPaddingCheck=1' {
        $script:pathExists = $false

        CertPaddingCheck

        $script:newItemCalls.Count | Should -Be 2
        $script:newItemCalls[0] | Should -Match 'SOFTWARE\\Microsoft\\Cryptography\\Wintrust\\Config'
        $script:newItemCalls[1] | Should -Match 'SOFTWARE\\Wow6432Node\\Microsoft\\Cryptography\\Wintrust\\Config'

        $script:setItemPropertyCalls.Count | Should -Be 2
        $script:setItemPropertyCalls[0].Name | Should -Be 'EnableCertPaddingCheck'
        $script:setItemPropertyCalls[0].Value | Should -Be 1
        $script:setItemPropertyCalls[1].Name | Should -Be 'EnableCertPaddingCheck'
        $script:setItemPropertyCalls[1].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips New-Item when paths already exist' {
        $script:pathExists = $true

        CertPaddingCheck

        $script:newItemCalls.Count | Should -Be 0
        $script:setItemPropertyCalls.Count | Should -Be 2
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed and logs error when Set-ItemProperty throws' {
        $script:pathExists = $true
        $script:throwOnSet = $true

        CertPaddingCheck

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'set-itemproperty failed'
    }
}

Describe 'ActiveXLockdown (CVE-2021-40444)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:throwOnWrite = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnWrite) { throw 'new-itemproperty failed' }
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; PropertyType = $Type })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes 1004=3 (DWord) across zones 0..4 and creates missing keys' {
        $script:pathExists = $false

        ActiveXLockdown

        $script:newItemCalls.Count | Should -Be 5
        $script:newItemPropertyCalls.Count | Should -Be 5
        for ($i = 0; $i -lt 5; $i++) {
            $script:newItemPropertyCalls[$i].Path | Should -Match "Internet Settings\\Zones\\$i$"
            $script:newItemPropertyCalls[$i].Name | Should -Be '1004'
            $script:newItemPropertyCalls[$i].Value | Should -Be 3
            $script:newItemPropertyCalls[$i].PropertyType | Should -Be 'DWord'
        }
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips New-Item when zone keys already exist' {
        $script:pathExists = $true

        ActiveXLockdown

        $script:newItemCalls.Count | Should -Be 0
        $script:newItemPropertyCalls.Count | Should -Be 5
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed and logs error when New-ItemProperty throws' {
        $script:pathExists = $true
        $script:throwOnWrite = $true

        ActiveXLockdown

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'new-itemproperty failed'
    }
}

Describe 'MsMsdtHandler (CVE-2022-30190 Follina)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $false
        $script:throwOnRemove = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function Remove-Item {
            param([string]$Path, [switch]$Recurse, [switch]$Force, [object]$ErrorAction)
            if ($script:throwOnRemove) { throw 'remove-item failed' }
            [void]$script:removeItemCalls.Add($Path)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','Remove-Item')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'removes the ms-msdt key when it exists' {
        $script:pathExists = $true

        MsMsdtHandler

        $script:removeItemCalls.Count | Should -Be 1
        $script:removeItemCalls[0] | Should -Match 'HKEY_CLASSES_ROOT\\ms-msdt$'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'is idempotent when the ms-msdt key is already missing' {
        $script:pathExists = $false

        MsMsdtHandler

        $script:removeItemCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed and logs error when Remove-Item throws' {
        $script:pathExists = $true
        $script:throwOnRemove = $true

        MsMsdtHandler

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'remove-item failed'
    }
}
