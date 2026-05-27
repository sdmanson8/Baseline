Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.CoreProtection.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('DefenderScanCPULimit', 'DefenderSignatureUpdateInterval')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'DefenderScanCPULimit' {
    BeforeEach {
        $script:consoleActions  = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages    = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:mpCalls         = [System.Collections.Generic.List[object]]::new()
        $script:defenderExecutionAvailable = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-MpPreference {
            param([int]$ScanAvgCPULoadFactor, [object]$ErrorAction)
            [void]$script:mpCalls.Add([pscustomobject]@{
                ScanAvgCPULoadFactor = $ScanAvgCPULoadFactor
                HasScanCpu = $PSBoundParameters.ContainsKey('ScanAvgCPULoadFactor')
            })
        }
        function Get-TweakSkipLabel { param($Invocation) return 'DefenderScanCPULimit' }
        function Test-BaselineDefenderExecutionAvailable { return [bool]$script:defenderExecutionAvailable }
        function Get-BaselineDefenderExecutionUnavailableReason { return 'Set-MpPreference is not available.' }
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-MpPreference -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-BaselineDefenderExecutionAvailable -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineDefenderExecutionUnavailableReason -ErrorAction SilentlyContinue
    }

    It 'caps Defender scan CPU at 25% via Set-MpPreference -ScanAvgCPULoadFactor 25 when enabling' {
        DefenderScanCPULimit -Enable

        $script:mpCalls.Count | Should -Be 1
        $script:mpCalls[0].ScanAvgCPULoadFactor | Should -Be 25
        $script:consoleActions[0] | Should -Match 'Capping Defender scheduled-scan CPU'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'restores the Windows default 50% cap when disabling' {
        DefenderScanCPULimit -Disable

        $script:mpCalls.Count | Should -Be 1
        $script:mpCalls[0].ScanAvgCPULoadFactor | Should -Be 50
        $script:consoleActions[0] | Should -Match 'Restoring Defender default scan CPU cap'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips entirely when Defender command surface is unavailable' {
        $script:defenderExecutionAvailable = $false

        DefenderScanCPULimit -Enable

        $script:mpCalls.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Set-MpPreference is not available'
    }

    It 'reports failure and logs the error message when Set-MpPreference throws' {
        function Set-MpPreference {
            param([int]$ScanAvgCPULoadFactor, [object]$ErrorAction)
            throw 'simulated mpPreference failure'
        }

        DefenderScanCPULimit -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'simulated mpPreference failure'
    }

    It 'requires either Enable or Disable (parameter set validation)' {
        { DefenderScanCPULimit -Enable -Disable } | Should -Throw
    }
}

Describe 'DefenderSignatureUpdateInterval' {
    BeforeEach {
        $script:consoleActions  = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages    = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:mpCalls         = [System.Collections.Generic.List[object]]::new()
        $script:defenderExecutionAvailable = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-MpPreference {
            param([int]$SignatureUpdateInterval, [object]$ErrorAction)
            [void]$script:mpCalls.Add([pscustomobject]@{
                SignatureUpdateInterval = $SignatureUpdateInterval
                HasSigInterval = $PSBoundParameters.ContainsKey('SignatureUpdateInterval')
            })
        }
        function Get-TweakSkipLabel { param($Invocation) return 'DefenderSignatureUpdateInterval' }
        function Test-BaselineDefenderExecutionAvailable { return [bool]$script:defenderExecutionAvailable }
        function Get-BaselineDefenderExecutionUnavailableReason { return 'Set-MpPreference is not available.' }
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-MpPreference -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-BaselineDefenderExecutionAvailable -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineDefenderExecutionUnavailableReason -ErrorAction SilentlyContinue
    }

    It 'forces hourly signature checks when enabling' {
        DefenderSignatureUpdateInterval -Enable

        $script:mpCalls.Count | Should -Be 1
        $script:mpCalls[0].SignatureUpdateInterval | Should -Be 1
        $script:consoleActions[0] | Should -Match 'Checking Defender signatures hourly'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'restores the WU-managed default (0) when disabling' {
        DefenderSignatureUpdateInterval -Disable

        $script:mpCalls.Count | Should -Be 1
        $script:mpCalls[0].SignatureUpdateInterval | Should -Be 0
        $script:consoleActions[0] | Should -Match 'Restoring default Defender signature update interval'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips entirely when Defender command surface is unavailable' {
        $script:defenderExecutionAvailable = $false

        DefenderSignatureUpdateInterval -Enable

        $script:mpCalls.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Set-MpPreference is not available'
    }

    It 'reports failure when Set-MpPreference throws' {
        function Set-MpPreference {
            param([int]$SignatureUpdateInterval, [object]$ErrorAction)
            throw 'simulated sig failure'
        }

        DefenderSignatureUpdateInterval -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'simulated sig failure'
    }

    It 'requires either Enable or Disable (parameter set validation)' {
        { DefenderSignatureUpdateInterval -Enable -Disable } | Should -Throw
    }
}
