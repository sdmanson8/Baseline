Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'AuditingBaseline') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'AuditingBaseline' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:auditpolCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:throwOnSet = $false
        $script:auditpolFailGuid = $null
        $script:auditpolFailExitCode = $false
        $global:LASTEXITCODE = 0

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
        function auditpol {
            $captured = $args
            [void]$script:auditpolCalls.Add($captured)
            $guid = ($captured | Where-Object { $_ -like '/subcategory:*' }) -replace '^/subcategory:',''
            $guid = $guid.Trim('"')
            if ($script:auditpolFailGuid -and $guid -eq $script:auditpolFailGuid) {
                if ($script:auditpolFailExitCode) {
                    $global:LASTEXITCODE = 1
                } else {
                    throw "auditpol denied for $guid"
                }
            } else {
                $global:LASTEXITCODE = 0
            }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe','auditpol')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'creates the Audit policy key when missing, sets ProcessCreationIncludeCmdLine_Enabled=1, and runs auditpol for all 8 subcategories' {
        $script:pathExists = $false

        AuditingBaseline

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Match 'Policies\\System\\Audit$'
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Name | Should -Be 'ProcessCreationIncludeCmdLine_Enabled'
        $script:setItemPropertyCalls[0].Value | Should -Be 1

        $script:auditpolCalls.Count | Should -Be 8
        foreach ($call in $script:auditpolCalls) {
            ($call -join ' ') | Should -Match '/set'
            ($call -join ' ') | Should -Match '/success:enable'
            ($call -join ' ') | Should -Match '/failure:enable'
        }
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips New-Item when the Audit path already exists' {
        $script:pathExists = $true

        AuditingBaseline

        $script:newItemCalls.Count | Should -Be 0
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:auditpolCalls.Count | Should -Be 8
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when Set-ItemProperty throws but still runs all auditpol calls' {
        $script:pathExists = $true
        $script:throwOnSet = $true

        AuditingBaseline

        $script:auditpolCalls.Count | Should -Be 8
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'ProcessCreationIncludeCmdLine'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }

    It 'continues when one auditpol subcategory throws and reports failed' {
        $script:pathExists = $true
        $script:auditpolFailGuid = '{0CCE9213-69AE-11D9-BED3-505054503030}'

        AuditingBaseline

        $script:auditpolCalls.Count | Should -Be 8
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'IPsec Driver'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }

    It 'reports failed when auditpol returns a non-zero exit code' {
        $script:pathExists = $true
        $script:auditpolFailGuid = '{0CCE9228-69AE-11D9-BED3-505054503030}'
        $script:auditpolFailExitCode = $true

        AuditingBaseline

        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'Sensitive Privilege Use'
        $script:errorMessages[0] | Should -Match 'exit code 1'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }
}
