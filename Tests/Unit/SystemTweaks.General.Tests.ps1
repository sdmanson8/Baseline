Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.General.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'PerformanceTuning' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:legacyCalled = $false
        $script:fallbackCalled = $false
        $script:fallbackAvailable = $true
        $script:legacyAvailable = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-Command {
            param([string]$Name)
            if ($Name -eq 'Invoke-SystemOptimizations') {
                if ($script:legacyAvailable) { return { $script:legacyCalled = $true } }
                return $null
            }
            if ($Name -eq 'Invoke-AdditionalServiceOptimizations') {
                if ($script:fallbackAvailable) { return { $script:fallbackCalled = $true } }
                return $null
            }
            return $null
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-Command')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'reports success and invokes both helpers when both are available' {
        PerformanceTuning

        $script:legacyCalled | Should -BeTrue
        $script:fallbackCalled | Should -BeTrue
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports warning when the legacy entry point is absent but fallback is present' {
        $script:legacyAvailable = $false

        PerformanceTuning

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:warningMessages.Count | Should -BeGreaterOrEqual 1
    }

    It 'reports warning when no helpers are available' {
        $script:legacyAvailable = $false
        $script:fallbackAvailable = $false

        PerformanceTuning

        $script:consoleStatuses[-1] | Should -Be 'warning'
    }
}

Describe 'AdobeNetworkBlock' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:copyCalls = [System.Collections.Generic.List[object]]::new()
        $script:webCalls = [System.Collections.Generic.List[object]]::new()
        $script:moveCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeCalls = [System.Collections.Generic.List[string]]::new()
        $script:setContentCalls = [System.Collections.Generic.List[object]]::new()
        $script:ipconfigExit = 0
        $script:hostsExists = $true
        $script:backupExists = $true
        $script:existingHostsContent = @(
            '# Local hosts',
            '127.0.0.1   localhost',
            '0.0.0.0     ads.example.com   # StevenBlack entry'
        )
        $script:downloadedBlockContent = @(
            '# Adobe block list header',
            '0.0.0.0 activate.adobe.com',
            '0.0.0.0 ads.example.com',
            '0.0.0.0 lm.licenses.adobe.com'
        )

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path {
            param([string]$Path)
            if ($Path -like '*.bak') { return $script:backupExists }
            if ($Path -like '*BaselineAdobeBlock_*') { return $true }
            return $script:hostsExists
        }
        function Copy-Item {
            [CmdletBinding()]
            param([Parameter(Position=0)][string]$Path, [Parameter(Position=1)][string]$Destination, [switch]$Force)
            [void]$script:copyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Destination = $Destination })
        }
        function Invoke-WebRequest {
            [CmdletBinding()]
            param([Parameter(Position=0)][string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [int]$TimeoutSec)
            [void]$script:webCalls.Add([pscustomobject]@{ Uri = $Uri; OutFile = $OutFile })
        }
        function ipconfig { $global:LASTEXITCODE = $script:ipconfigExit }
        function Remove-Item {
            [CmdletBinding()]
            param([Parameter(Position=0)][string]$Path, [switch]$Force)
            [void]$script:removeCalls.Add($Path)
        }
        function Move-Item {
            [CmdletBinding()]
            param([Parameter(Position=0)][string]$Path, [Parameter(Position=1)][string]$Destination, [switch]$Force)
            [void]$script:moveCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Destination = $Destination })
        }
        function Get-Content {
            [CmdletBinding()]
            param([string]$Path)
            if ($Path -like '*BaselineAdobeBlock_*') { return $script:downloadedBlockContent }
            return $script:existingHostsContent
        }
        function Set-Content {
            [CmdletBinding()]
            param([string]$Path, [object]$Value, [string]$Encoding, [switch]$Force)
            [void]$script:setContentCalls.Add([pscustomobject]@{ Path = $Path; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','Copy-Item','Invoke-WebRequest','ipconfig','Remove-Item','Move-Item','Get-Content','Set-Content')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'backs up hosts, downloads to temp, merges block list, flushes DNS on Enable' {
        AdobeNetworkBlock -Enable

        $script:copyCalls.Count | Should -Be 1
        $script:webCalls.Count | Should -Be 1
        $script:webCalls[0].Uri | Should -Match 'Adobe-URL-Block-List'
        # Must not clobber the hosts file directly.
        $script:webCalls[0].OutFile | Should -Not -Be "$Env:SystemRoot\System32\drivers\etc\hosts"
        $script:webCalls[0].OutFile | Should -Match 'BaselineAdobeBlock_'
        $script:setContentCalls.Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'preserves existing Baseline hosts entries when merging' {
        AdobeNetworkBlock -Enable

        $written = [string[]]$script:setContentCalls[0].Value
        # All pre-existing lines must survive the merge
        $written | Should -Contain '127.0.0.1   localhost'
        $written | Should -Contain '0.0.0.0     ads.example.com   # StevenBlack entry'
        # Marker block must wrap our additions for idempotent re-runs
        $written | Should -Contain '# BEGIN BASELINE-AdobeBlock'
        $written | Should -Contain '# END BASELINE-AdobeBlock'
        # New Adobe entries appended
        $written | Should -Contain '0.0.0.0 activate.adobe.com'
        $written | Should -Contain '0.0.0.0 lm.licenses.adobe.com'
    }

    It 'deduplicates: does not re-add block-list entries already present in hosts' {
        AdobeNetworkBlock -Enable

        $written = [string[]]$script:setContentCalls[0].Value
        # ads.example.com appears in BOTH existing and downloaded - should appear exactly once
        ($written | Where-Object { $_ -match 'ads\.example\.com' }).Count | Should -Be 1
    }

    It 'is idempotent: prior BEGIN/END marker block is stripped before re-merging' {
        $script:existingHostsContent = @(
            '127.0.0.1   localhost',
            '',
            '# BEGIN BASELINE-AdobeBlock',
            '0.0.0.0 stale.adobe.com',
            '# END BASELINE-AdobeBlock'
        )

        AdobeNetworkBlock -Enable

        $written = [string[]]$script:setContentCalls[0].Value
        # Stale entry from prior marker block must NOT survive
        ($written | Where-Object { $_ -match 'stale\.adobe\.com' }).Count | Should -Be 0
        # Fresh additions land inside a single new marker block
        ($written | Where-Object { $_ -eq '# BEGIN BASELINE-AdobeBlock' }).Count | Should -Be 1
    }

    It 'reports failed when ipconfig returns a non-zero exit code' {
        $script:ipconfigExit = 2

        AdobeNetworkBlock -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'ipconfig'
    }

    It 'restores hosts from backup and flushes DNS on Disable' {
        AdobeNetworkBlock -Disable

        $script:removeCalls.Count | Should -Be 1
        $script:moveCalls.Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'BraveDebloat' {
    BeforeEach {
        $script:setPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removePropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:bravePathExists = $false

        function Write-ConsoleStatus { param([string]$Action, [string]$Status) }
        function LogInfo { param([string]$Message) }
        function Test-Path { param([string]$Path) return $script:bravePathExists }
        function New-Item {
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force)
            [void]$script:setPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force)
            [void]$script:removePropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','Test-Path','New-Item','Set-ItemProperty','Remove-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'creates the policy key and writes all 5 debloat values on Enable' {
        $script:bravePathExists = $false

        BraveDebloat -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:setPropertyCalls.Count | Should -Be 5
        ($script:setPropertyCalls | Where-Object { $_.Name -eq 'BraveRewardsDisabled' }).Value | Should -Be 1
        ($script:setPropertyCalls | Where-Object { $_.Name -eq 'BraveAIChatEnabled' }).Value | Should -Be 0
    }

    It 'removes all 5 policy values on Disable' {
        BraveDebloat -Disable

        $script:removePropertyCalls.Count | Should -Be 5
    }
}

Describe 'CrossDeviceResume (build-gated)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:setPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:isSupported = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Test-Windows11FeatureBranchSupport { return $script:isSupported }
        function Test-Path { param([string]$Path) return $true }
        function New-Item { param([string]$Path, [switch]$Force) }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force)
            [void]$script:setPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Test-Windows11FeatureBranchSupport','Test-Path','New-Item','Set-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'warns and skips when build version is not supported' {
        $script:isSupported = $false

        CrossDeviceResume -Enable

        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Cross-Device Resume'
        $script:setPropertyCalls.Count | Should -Be 0
    }

    It 'writes IsResumeAllowed=1 on Enable when supported' {
        $script:isSupported = $true

        CrossDeviceResume -Enable

        $script:setPropertyCalls[0].Name | Should -Be 'IsResumeAllowed'
        $script:setPropertyCalls[0].Value | Should -Be 1
    }

    It 'writes IsResumeAllowed=0 on Disable when supported' {
        $script:isSupported = $true

        CrossDeviceResume -Disable

        $script:setPropertyCalls[0].Value | Should -Be 0
    }
}
