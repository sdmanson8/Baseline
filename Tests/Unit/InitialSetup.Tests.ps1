Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/InitialSetup.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'CreateRestorePoint' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:getComputerRestorePointCalls = [System.Collections.Generic.List[object]]::new()
        $script:restorePoints = @()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }

        function LogInfo {
            param([string]$Message)
            [void]$script:infoMessages.Add($Message)
        }

        function LogWarning {
            param([string]$Message)
            [void]$script:warningMessages.Add($Message)
        }

        function LogError {
            param([string]$Message)
            [void]$script:errorMessages.Add($Message)
        }

        function Get-Service {
            [CmdletBinding()]
            param([string]$Name)
            return [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' }
        }

        function Set-Service {
            [CmdletBinding()]
            param([string]$Name, [string]$StartupType)
        }

        function Start-Service {
            [CmdletBinding()]
            param([string]$Name)
        }

        function Get-Volume {
            [CmdletBinding()]
            param()
            return [pscustomobject]@{ DriveLetter = 'C'; UniqueID = 'VOL-123' }
        }

        function Get-ItemProperty {
            [CmdletBinding()]
            param([string]$Path)
            return [pscustomobject]@{ '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}' = 'VOL-123' }
        }

        function Get-OSInfo {
            [CmdletBinding()]
            param()
            return [pscustomobject]@{ OSName = 'Windows 11' }
        }

        function Get-BaselineDisplayVersion {
            [CmdletBinding()]
            param()
            return '24H2'
        }

        function New-ItemProperty {
            [CmdletBinding()]
            param(
                [string]$Path,
                [string]$Name,
                [object]$Value,
                [string]$PropertyType,
                [switch]$Force
            )

            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{
                Path = $Path
                Name = $Name
                Value = $Value
                PropertyType = $PropertyType
            })
        }

        function Start-Job {
            [CmdletBinding()]
            param([scriptblock]$ScriptBlock, [object[]]$ArgumentList)
            return [pscustomobject]@{ Id = 1; ScriptBlock = $ScriptBlock; ArgumentList = $ArgumentList }
        }

        function Wait-Job {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline)] [object]$InputObject, [int]$Timeout)
            process { return [pscustomobject]@{ Id = 1 } }
        }

        function Receive-Job {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline)] [object]$InputObject)
            process { }
        }

        function Stop-Job {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline)] [object]$InputObject)
            process { }
        }

        function Remove-Job {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline)] [object]$InputObject, [switch]$Force)
            process { }
        }

        function Get-ComputerRestorePoint {
            [CmdletBinding()]
            param()
            [void]$script:getComputerRestorePointCalls.Add($true)
            return @($script:restorePoints)
        }

        function Enable-ComputerRestore {
            [CmdletBinding()]
            param([string]$Drive)
        }

        function Disable-ComputerRestore {
            [CmdletBinding()]
            param([string]$Drive)
        }
    }

    AfterEach {
        foreach ($name in @(
                'Write-ConsoleStatus',
                'LogInfo',
                'LogWarning',
                'LogError',
                'Get-Service',
                'Set-Service',
                'Start-Service',
                'Get-Volume',
                'Get-ItemProperty',
                'Get-OSInfo',
                'Get-BaselineDisplayVersion',
                'New-ItemProperty',
                'Start-Job',
                'Wait-Job',
                'Receive-Job',
                'Stop-Job',
                'Remove-Job',
                'Get-ComputerRestorePoint',
                'Enable-ComputerRestore',
                'Disable-ComputerRestore'
            )) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$name -ErrorAction SilentlyContinue
        }
    }

    It 'reports success only after the restore point is confirmed present' {
        $script:restorePoints = @(
            [pscustomobject]@{ Description = 'Baseline | Utility for Windows 11 24H2' }
        )

        CreateRestorePoint

        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:errorMessages.Count | Should -Be 0
        $script:getComputerRestorePointCalls.Count | Should -Be 1
        $script:newItemPropertyCalls.Count | Should -Be 2
        $script:newItemPropertyCalls[0].Value | Should -Be 0
        $script:newItemPropertyCalls[1].Value | Should -Be 1440
    }

    It 'reports failed when no matching restore point is returned after creation' {
        $script:restorePoints = @(
            [pscustomobject]@{ Description = 'Different restore point' }
        )

        CreateRestorePoint

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'was not found after creation'
        $script:getComputerRestorePointCalls.Count | Should -Be 1
        $script:newItemPropertyCalls.Count | Should -Be 2
        $script:newItemPropertyCalls[0].Value | Should -Be 0
        $script:newItemPropertyCalls[1].Value | Should -Be 1440
    }
}
