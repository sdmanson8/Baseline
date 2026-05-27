Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SystemMaintenance.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    <#
        .SYNOPSIS
    #>

    function Remove-HandledErrorRecord {}
    <#
        .SYNOPSIS
    #>
    function Get-WinEvent {}
    <#
        .SYNOPSIS
    #>
    function LogWarning { param([string]$Message) $script:lastSystemMaintenanceWarning = $Message }
}

Describe 'Get-MinimumRecommendedMemoryCompressionRamGB' {
    It 'returns the shared RAM threshold as an integer' {
        $result = Get-MinimumRecommendedMemoryCompressionRamGB

        $result | Should -BeOfType [int]
        $result | Should -BeGreaterThan 0
    }
}

Describe 'Test-Windows11SmbDuplicateSidIssue' {
    BeforeEach {
        $script:lastSystemMaintenanceWarning = $null
    }

    It 'returns true when LSASS duplicate SID events are present' {
        Mock Get-WinEvent {
            @(
                [pscustomobject]@{ Message = 'There is a partial mismatch in the machine ID for this system.' }
            )
        }

        $result = Test-Windows11SmbDuplicateSidIssue -LookbackDays 7

        $result | Should -Be $true
    }

    It 'returns false and logs a warning when the event query fails' {
        Mock Get-WinEvent { throw 'event query failed' }

        $result = Test-Windows11SmbDuplicateSidIssue -LookbackDays 7

        $result | Should -Be $false
        $script:lastSystemMaintenanceWarning | Should -Match 'Unable to query LSASS Event ID 6167'
    }
}

Describe 'Invoke-AdditionalServiceOptimizations' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:setServiceCalls = [System.Collections.Generic.List[object]]::new()
        $script:stopServiceCalls = [System.Collections.Generic.List[string]]::new()
        $script:disableMMAgentCalled = $false
        $script:mmAgentCompressionEnabled = $true
        $script:serviceLookup = @{}
        $script:totalPhysicalMemory = 16GB

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function Get-MMAgent {
            param([object]$ErrorAction)
            return [pscustomobject]@{ MemoryCompression = $script:mmAgentCompressionEnabled }
        }
        function Disable-MMAgent {
            param([switch]$mc, [object]$ErrorAction)
            $script:disableMMAgentCalled = $true
            $script:mmAgentCompressionEnabled = $false
        }
        function Get-CimInstance {
            param([string]$ClassName, [object]$ErrorAction)
            return [pscustomobject]@{ TotalPhysicalMemory = $script:totalPhysicalMemory }
        }
        function Get-Service {
            param([string]$Name, [object]$ErrorAction)
            return $script:serviceLookup[$Name]
        }
        function Set-Service {
            param([string]$Name, [string]$StartupType, [object]$ErrorAction)
            [void]$script:setServiceCalls.Add([pscustomobject]@{ Name = $Name; StartupType = $StartupType })
        }
        function Stop-Service {
            param([string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:stopServiceCalls.Add($Name)
        }
        function Test-Path { param([string]$Path) return $false }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','Get-MMAgent','Disable-MMAgent','Get-CimInstance','Get-Service','Set-Service','Stop-Service','Test-Path','Set-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'calls Disable-MMAgent when memory compression is enabled and RAM is above threshold' {
        Invoke-AdditionalServiceOptimizations

        $script:disableMMAgentCalled | Should -BeTrue
    }

    It 'does not disable Memory Compression below the minimum RAM threshold' {
        $script:totalPhysicalMemory = 4GB

        Invoke-AdditionalServiceOptimizations

        $script:disableMMAgentCalled | Should -BeFalse
        ($script:warningMessages | Where-Object { $_ -match 'Skipping Memory Compression disable' }).Count | Should -Be 1
    }

    It 'disables the extra services when they exist' {
        $script:serviceLookup = @{
            'PeerDistSvc' = [pscustomobject]@{ Name = 'PeerDistSvc'; StartType = 'Manual' }
            'RemoteRegistry' = [pscustomobject]@{ Name = 'RemoteRegistry'; StartType = 'Manual' }
        }

        Invoke-AdditionalServiceOptimizations

        ($script:setServiceCalls | Where-Object { $_.Name -eq 'PeerDistSvc' }).StartupType | Should -Be 'Disabled'
        ($script:setServiceCalls | Where-Object { $_.Name -eq 'RemoteRegistry' }).StartupType | Should -Be 'Disabled'
    }

    It 'logs a warning when a service is missing and its registry key does not exist' {
        $script:serviceLookup = @{}

        Invoke-AdditionalServiceOptimizations

        ($script:warningMessages | Where-Object { $_ -match 'PeerDistSvc' }).Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports success when no issue occurred' {
        $script:serviceLookup = @{
            'PeerDistSvc' = [pscustomobject]@{ Name = 'PeerDistSvc'; StartType = 'Manual' }
            'diagnosticshub.standardcollector.service' = [pscustomobject]@{ Name = 'diagnosticshub.standardcollector.service'; StartType = 'Manual' }
            'RemoteRegistry' = [pscustomobject]@{ Name = 'RemoteRegistry'; StartType = 'Manual' }
        }

        Invoke-AdditionalServiceOptimizations

        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
