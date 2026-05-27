Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'RansomwareScriptLockdown') {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:canonicalExtensions = @(
        '.bat','.cmd','.js','.vbs','.hta','.wsf','.reg','.msc','.rdg','.application','.deploy'
    )
}

Describe 'RansomwareScriptLockdown -Enable' {
    BeforeEach {
        $script:consoleStatuses    = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages      = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages    = [System.Collections.Generic.List[string]]::new()
        $script:mitigateCalls      = [System.Collections.Generic.List[string]]::new()
        $script:restoreCalls       = [System.Collections.Generic.List[string]]::new()
        $script:mitigateBehavior   = @{}   # ext -> @{ Mitigated/AlreadyMitigated/Skipped/SkipReason }
        $script:throwOnMitigate    = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-BaselineRansomwareFtypeExtensions { return $script:canonicalExtensions }

        function Set-BaselineRansomwareFtypeMitigation {
            param([string]$Extension)
            if ($script:throwOnMitigate) { throw 'mitigation failed' }
            [void]$script:mitigateCalls.Add($Extension)
            $defaults = @{ Mitigated = $true; AlreadyMitigated = $false; Skipped = $false; SkipReason = $null }
            if ($script:mitigateBehavior.ContainsKey($Extension)) {
                foreach ($k in $script:mitigateBehavior[$Extension].Keys) {
                    $defaults[$k] = $script:mitigateBehavior[$Extension][$k]
                }
            }
            return [pscustomobject]$defaults
        }

        function Restore-BaselineRansomwareFtypeMitigation {
            param([string]$Extension)
            [void]$script:restoreCalls.Add($Extension)
            return [pscustomobject]@{ Restored = $true; Skipped = $false; SkipReason = $null }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineRansomwareFtypeExtensions','Set-BaselineRansomwareFtypeMitigation','Restore-BaselineRansomwareFtypeMitigation')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'invokes Set-BaselineRansomwareFtypeMitigation once per canonical extension' {
        RansomwareScriptLockdown -Enable

        $script:mitigateCalls.Count | Should -Be $script:canonicalExtensions.Count
        foreach ($ext in $script:canonicalExtensions) {
            $script:mitigateCalls | Should -Contain $ext
        }
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'does not call the restore helper on Enable' {
        RansomwareScriptLockdown -Enable
        $script:restoreCalls.Count | Should -Be 0
    }

    It 'logs a summary line tallying mitigated / already / skipped' {
        $script:mitigateBehavior['.bat'] = @{ Mitigated = $false; AlreadyMitigated = $true }
        $script:mitigateBehavior['.rdg'] = @{ Mitigated = $false; Skipped = $true; SkipReason = 'NoProgID' }

        RansomwareScriptLockdown -Enable

        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Ransomware lockdown summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'mitigated=9'
        $summary | Should -Match 'already=1'
        $summary | Should -Match 'skipped=1'
    }

    It 'logs the SkipReason for each skipped extension' {
        $script:mitigateBehavior['.rdg']    = @{ Mitigated = $false; Skipped = $true; SkipReason = 'NoProgID' }
        $script:mitigateBehavior['.deploy'] = @{ Mitigated = $false; Skipped = $true; SkipReason = 'NoProgID' }

        RansomwareScriptLockdown -Enable

        ($script:logInfoMessages | Where-Object { $_ -match 'Skipped \.rdg.*NoProgID' })    | Should -Not -BeNullOrEmpty
        ($script:logInfoMessages | Where-Object { $_ -match 'Skipped \.deploy.*NoProgID' }) | Should -Not -BeNullOrEmpty
    }

    It 'reports failed and logs error when a helper throws' {
        $script:throwOnMitigate = $true

        RansomwareScriptLockdown -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0]    | Should -Match 'mitigation failed'
    }
}

Describe 'RansomwareScriptLockdown -Disable' {
    BeforeEach {
        $script:consoleStatuses    = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages      = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages    = [System.Collections.Generic.List[string]]::new()
        $script:mitigateCalls      = [System.Collections.Generic.List[string]]::new()
        $script:restoreCalls       = [System.Collections.Generic.List[string]]::new()
        $script:restoreBehavior    = @{}
        $script:throwOnRestore     = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-BaselineRansomwareFtypeExtensions { return $script:canonicalExtensions }

        function Set-BaselineRansomwareFtypeMitigation {
            param([string]$Extension)
            [void]$script:mitigateCalls.Add($Extension)
            return [pscustomobject]@{ Mitigated = $true; AlreadyMitigated = $false; Skipped = $false; SkipReason = $null }
        }

        function Restore-BaselineRansomwareFtypeMitigation {
            param([string]$Extension)
            if ($script:throwOnRestore) { throw 'restore failed' }
            [void]$script:restoreCalls.Add($Extension)
            $defaults = @{ Restored = $true; Skipped = $false; SkipReason = $null }
            if ($script:restoreBehavior.ContainsKey($Extension)) {
                foreach ($k in $script:restoreBehavior[$Extension].Keys) {
                    $defaults[$k] = $script:restoreBehavior[$Extension][$k]
                }
            }
            return [pscustomobject]$defaults
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineRansomwareFtypeExtensions','Set-BaselineRansomwareFtypeMitigation','Restore-BaselineRansomwareFtypeMitigation')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'invokes Restore-BaselineRansomwareFtypeMitigation once per canonical extension' {
        RansomwareScriptLockdown -Disable

        $script:restoreCalls.Count | Should -Be $script:canonicalExtensions.Count
        foreach ($ext in $script:canonicalExtensions) {
            $script:restoreCalls | Should -Contain $ext
        }
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'does not call the mitigation helper on Disable' {
        RansomwareScriptLockdown -Disable
        $script:mitigateCalls.Count | Should -Be 0
    }

    It 'logs a reversal summary line tallying restored / skipped' {
        $script:restoreBehavior['.rdg'] = @{ Restored = $false; Skipped = $true; SkipReason = 'NoBackup' }

        RansomwareScriptLockdown -Disable

        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Ransomware lockdown reversal summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'restored=10'
        $summary | Should -Match 'skipped=1'
    }

    It 'logs the SkipReason for each skipped extension on reversal' {
        $script:restoreBehavior['.rdg'] = @{ Restored = $false; Skipped = $true; SkipReason = 'NoBackup' }

        RansomwareScriptLockdown -Disable

        ($script:logInfoMessages | Where-Object { $_ -match 'Skipped \.rdg.*NoBackup' }) | Should -Not -BeNullOrEmpty
    }

    It 'reports failed and logs error when restore helper throws' {
        $script:throwOnRestore = $true

        RansomwareScriptLockdown -Disable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0]    | Should -Match 'restore failed'
    }
}

Describe 'RansomwareScriptLockdown parameter contract' {
    BeforeEach {
        function Write-ConsoleStatus { param($Action, $Status) }
        function LogInfo  { param($Message) }
        function LogError { param($Message) }
        function Get-BaselineRansomwareFtypeExtensions { return @() }
        function Set-BaselineRansomwareFtypeMitigation { param($Extension) }
        function Restore-BaselineRansomwareFtypeMitigation { param($Extension) }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineRansomwareFtypeExtensions','Set-BaselineRansomwareFtypeMitigation','Restore-BaselineRansomwareFtypeMitigation')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires either -Enable or -Disable' {
        { RansomwareScriptLockdown } | Should -Throw
    }

    It 'rejects passing both -Enable and -Disable together' {
        { RansomwareScriptLockdown -Enable -Disable } | Should -Throw
    }
}
