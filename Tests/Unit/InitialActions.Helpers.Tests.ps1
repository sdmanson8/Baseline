Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/InitialActions.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Get-BaselineStartupLabel' {
    It 'concatenates the OS name and version when a version is supplied' {
        Get-BaselineStartupLabel -OSName 'Windows 11 Pro' -DisplayVersion 'v1.0.0' |
            Should -Be 'Baseline | Utility for Windows 11 Pro v1.0.0'
    }

    It 'omits the trailing space when the version is empty' {
        Get-BaselineStartupLabel -OSName 'Windows 11 Pro' -DisplayVersion '' |
            Should -Be 'Baseline | Utility for Windows 11 Pro'
    }

    It 'omits the trailing space when the version is whitespace' {
        Get-BaselineStartupLabel -OSName 'Windows 11 Pro' -DisplayVersion '   ' |
            Should -Be 'Baseline | Utility for Windows 11 Pro'
    }

    It 'omits the trailing space when no version is supplied' {
        Get-BaselineStartupLabel -OSName 'Windows 11 Pro' |
            Should -Be 'Baseline | Utility for Windows 11 Pro'
    }
}

Describe 'Test-BaselineUnsupportedHost' {
    It 'flags PowerShell ISE host names' {
        Test-BaselineUnsupportedHost -HostName 'Windows PowerShell ISE Host' -TermProgram '' | Should -BeTrue
    }

    It 'flags VS Code regardless of the PowerShell host name' {
        Test-BaselineUnsupportedHost -HostName 'ConsoleHost' -TermProgram 'vscode' | Should -BeTrue
    }

    It 'permits the standard ConsoleHost outside VS Code' {
        Test-BaselineUnsupportedHost -HostName 'ConsoleHost' -TermProgram '' | Should -BeFalse
    }

    It 'permits an empty host name when the terminal is not VS Code' {
        Test-BaselineUnsupportedHost -HostName '' -TermProgram '' | Should -BeFalse
    }
}

Describe 'Test-BaselineHostsEntry' {
    It 'accepts an IPv4 entry with a hostname' {
        Test-BaselineHostsEntry -Line '127.0.0.1 telemetry.example.com' | Should -BeTrue
    }

    It 'accepts a leading-whitespace IPv4 entry' {
        Test-BaselineHostsEntry -Line '  10.0.0.1 host' | Should -BeTrue
    }

    It 'accepts an IPv6 entry' {
        Test-BaselineHostsEntry -Line '::1 ipv6.example.com' | Should -BeTrue
    }

    It 'rejects a comment line' {
        Test-BaselineHostsEntry -Line '# this is a comment' | Should -BeFalse
    }

    It 'rejects an empty line' {
        Test-BaselineHostsEntry -Line '' | Should -BeFalse
    }

    It 'rejects a line with only whitespace' {
        Test-BaselineHostsEntry -Line '   ' | Should -BeFalse
    }

    It 'rejects garbage text without an IP-shaped prefix' {
        Test-BaselineHostsEntry -Line 'oops not a hosts entry' | Should -BeFalse
    }

    It 'rejects $null without throwing' {
        Test-BaselineHostsEntry -Line $null | Should -BeFalse
    }
}

Describe 'Get-BaselineHostsCandidateEntries' {
    It 'strips comment lines and empty entries' {
        $input = @(
            '127.0.0.1 a.example',
            '# comment',
            '',
            '10.0.0.1 b.example'
        )

        $result = @(Get-BaselineHostsCandidateEntries -Content $input)

        $result.Count | Should -Be 2
        $result[0] | Should -Be '127.0.0.1 a.example'
        $result[1] | Should -Be '10.0.0.1 b.example'
    }

    It 'returns an empty array when content is null' {
        $result = @(Get-BaselineHostsCandidateEntries -Content $null)
        $result.Count | Should -Be 0
    }

    It 'returns an empty array when content is empty' {
        $result = @(Get-BaselineHostsCandidateEntries -Content @())
        $result.Count | Should -Be 0
    }
}

Describe 'Test-BaselineHostsDownloadSuspect' {
    It 'is suspect when more than half of entries are invalid' {
        Test-BaselineHostsDownloadSuspect -InvalidCount 6 -TotalCount 10 | Should -BeTrue
    }

    It 'is not suspect when exactly half of entries are invalid' {
        Test-BaselineHostsDownloadSuspect -InvalidCount 5 -TotalCount 10 | Should -BeFalse
    }

    It 'is not suspect when fewer than half of entries are invalid' {
        Test-BaselineHostsDownloadSuspect -InvalidCount 4 -TotalCount 10 | Should -BeFalse
    }

    It 'is not suspect when no entries were downloaded' {
        Test-BaselineHostsDownloadSuspect -InvalidCount 0 -TotalCount 0 | Should -BeFalse
    }

    It 'honours a caller-supplied threshold' {
        Test-BaselineHostsDownloadSuspect -InvalidCount 3 -TotalCount 10 -Threshold 0.2 | Should -BeTrue
        Test-BaselineHostsDownloadSuspect -InvalidCount 1 -TotalCount 10 -Threshold 0.2 | Should -BeFalse
    }
}

Describe 'Get-BaselineDefenderProductStateCode' {
    It 'extracts the state byte from a fully-on Defender product state' {
        # 0x41000 -> hex string "0x41000", second byte is "10"
        Get-BaselineDefenderProductStateCode -ProductState 0x41000 | Should -Be '10'
    }

    It 'extracts "00" for a not-running scanner' {
        Get-BaselineDefenderProductStateCode -ProductState 0x40000 | Should -Be '00'
    }

    It 'extracts "01" for a partially-disabled scanner' {
        Get-BaselineDefenderProductStateCode -ProductState 0x41100 | Should -Be '11'
    }

    It 'returns $null when the product state is null' {
        Get-BaselineDefenderProductStateCode -ProductState $null | Should -BeNullOrEmpty
    }

    It 'returns $null when the formatted state has fewer than 5 characters' {
        # 0x10 -> "0x10" length 4 -> not enough digits to read the middle byte
        Get-BaselineDefenderProductStateCode -ProductState 0x10 | Should -BeNullOrEmpty
    }

    It 'returns $null when the input cannot be coerced to an int' {
        Get-BaselineDefenderProductStateCode -ProductState 'not-an-int' | Should -BeNullOrEmpty
    }
}

Describe 'Test-BaselineDefenderActiveByProductState' {
    It 'is active for a non-zero, non-one second byte' {
        Test-BaselineDefenderActiveByProductState -StateCode '10' | Should -BeTrue
    }

    It 'is inactive when the second byte is 00' {
        Test-BaselineDefenderActiveByProductState -StateCode '00' | Should -BeFalse
    }

    It 'is inactive when the second byte is 01' {
        Test-BaselineDefenderActiveByProductState -StateCode '01' | Should -BeFalse
    }

    It 'is inactive when no state code was parsed' {
        Test-BaselineDefenderActiveByProductState -StateCode '' | Should -BeFalse
        Test-BaselineDefenderActiveByProductState -StateCode $null | Should -BeFalse
    }
}

Describe 'Test-BaselineDefenderFullyEnabled' {
    It 'is enabled only when every input flag is true' {
        Test-BaselineDefenderFullyEnabled -ServicesRunning $true -ProductStateActive $true -AntiSpywareEnabled $true -RealtimeMonitoringEnabled $true -BehaviorMonitoringEnabled $true |
            Should -BeTrue
    }

    It 'is disabled when any flag is false' {
        Test-BaselineDefenderFullyEnabled -ServicesRunning $true -ProductStateActive $true -AntiSpywareEnabled $true -RealtimeMonitoringEnabled $true -BehaviorMonitoringEnabled $false |
            Should -BeFalse
        Test-BaselineDefenderFullyEnabled -ServicesRunning $false -ProductStateActive $true -AntiSpywareEnabled $true -RealtimeMonitoringEnabled $true -BehaviorMonitoringEnabled $true |
            Should -BeFalse
    }
}

Describe 'Test-BaselineDefenderServicesHealthy' {
    It 'is healthy when at least one service is Running' {
        $services = @(
            [pscustomobject]@{ Name = 'A'; Status = 'Stopped' },
            [pscustomobject]@{ Name = 'B'; Status = 'Running' }
        )

        Test-BaselineDefenderServicesHealthy -Services $services | Should -BeTrue
    }

    It 'is unhealthy when every service is stopped' {
        $services = @(
            [pscustomobject]@{ Name = 'A'; Status = 'Stopped' },
            [pscustomobject]@{ Name = 'B'; Status = 'Stopped' }
        )

        Test-BaselineDefenderServicesHealthy -Services $services | Should -BeFalse
    }

    It 'is unhealthy when no services were sampled' {
        Test-BaselineDefenderServicesHealthy -Services @() | Should -BeFalse
        Test-BaselineDefenderServicesHealthy -Services $null | Should -BeFalse
    }
}

Describe 'Resolve-BaselineSettingsAppsFeaturesHealthAssessment' {
    It 'returns a healthy assessment when Settings opens and services are sampled' {
        Mock Start-Process { }
        Mock Get-Process { [pscustomobject]@{ Name = 'SystemSettings' } }
        Mock Get-Service {
            @(
                [pscustomobject]@{ Name = 'ClipSVC'; Status = 'Running' }
                [pscustomobject]@{ Name = 'AppXSvc'; Status = 'Stopped' }
            )
        }

        $assessment = Resolve-BaselineSettingsAppsFeaturesHealthAssessment -TimeoutSeconds 0

        Should -Invoke Start-Process -Times 1
        Should -Invoke Get-Process -Times 1
        Should -Invoke Get-Service -Times 1

        $assessment.Healthy | Should -BeTrue
        $assessment.LaunchSucceeded | Should -BeTrue
        $assessment.SettingsProcessDetected | Should -BeTrue
        @($assessment.ServiceStates).Count | Should -Be 2
        $assessment.LaunchError | Should -BeNullOrEmpty
        $assessment.ServiceError | Should -BeNullOrEmpty
        $assessment.ServiceSummary | Should -Be 'AppXSvc:Stopped, ClipSVC:Running'
        $assessment.Message | Should -Be 'Settings appsfeatures health check passed. Service states: AppXSvc:Stopped, ClipSVC:Running'
    }

    It 'surfaces launch failures without inventing a healthy result' {
        Mock Start-Process { throw [System.InvalidOperationException]::new('start failed') }
        Mock Get-Process { }
        Mock Get-Service {
            @([pscustomobject]@{ Name = 'AppXSvc'; Status = 'Running' })
        }

        $assessment = Resolve-BaselineSettingsAppsFeaturesHealthAssessment -TimeoutSeconds 0

        Should -Invoke Start-Process -Times 1
        Should -Invoke Get-Process -Times 0
        Should -Invoke Get-Service -Times 1

        $assessment.Healthy | Should -BeFalse
        $assessment.LaunchSucceeded | Should -BeFalse
        $assessment.SettingsProcessDetected | Should -BeFalse
        $assessment.LaunchError | Should -Be 'start failed'
        $assessment.ServiceError | Should -BeNullOrEmpty
        $assessment.ServiceSummary | Should -Be 'AppXSvc:Running'
        $assessment.Message | Should -Match '^Settings appsfeatures health check failed; could not launch ms-settings:appsfeatures: start failed'
        $assessment.Message | Should -Match 'Service states: AppXSvc:Running$'
    }
}

Describe 'Resolve-BaselineScreenSnippingHealthAssessment' {
    It 'returns a healthy assessment when no ScreenSketch packages remain and the Print Screen toggle is enabled' {
        Mock Get-AppxPackage { @() }
        Mock Get-ItemProperty { [pscustomobject]@{ PrintScreenKeyForSnippingEnabled = 1 } }

        $assessment = Resolve-BaselineScreenSnippingHealthAssessment

        $assessment.Healthy | Should -BeTrue
        @($assessment.InstalledPackages).Count | Should -Be 0
        $assessment.PackageSummary | Should -Be 'n/a'
        $assessment.PrintScreenKeyForSnippingEnabled | Should -Be 1
        $assessment.PackageError | Should -BeNullOrEmpty
        $assessment.RegistryError | Should -BeNullOrEmpty
        $assessment.Message | Should -Be 'Screen snipping health check passed. Packages: n/a. PrintScreenKeyForSnippingEnabled=1'
    }

    It 'reports packages and the toggle state when ScreenSketch is still present' {
        Mock Get-AppxPackage {
            @(
                [pscustomobject]@{ Name = 'Microsoft.ScreenSketch' }
                [pscustomobject]@{ Name = 'Microsoft.Windows.SnipAndSketch' }
            )
        }
        Mock Get-ItemProperty { [pscustomobject]@{ PrintScreenKeyForSnippingEnabled = 0 } }

        $assessment = Resolve-BaselineScreenSnippingHealthAssessment

        $assessment.Healthy | Should -BeFalse
        @($assessment.InstalledPackages).Count | Should -Be 2
        $assessment.PackageSummary | Should -Be 'Microsoft.ScreenSketch, Microsoft.Windows.SnipAndSketch'
        $assessment.PrintScreenKeyForSnippingEnabled | Should -Be 0
        $assessment.Message | Should -Match 'Screen snipping health check failed; ScreenSketch/SnipAndSketch packages are still installed: Microsoft.ScreenSketch, Microsoft.Windows.SnipAndSketch'
        $assessment.Message | Should -Match 'Current PrintScreenKeyForSnippingEnabled value: 0'
    }
}

Describe 'Resolve-BaselineHostsCleanupPolicy' {
    It 'defaults to warn-and-skip when neither source is supplied' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue $null -PreferenceValue $null
        $policy.AutoStrip | Should -BeFalse
        $policy.Source | Should -Be 'default'
    }

    It 'treats whitespace env values as unset and falls through to preference' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue '   ' -PreferenceValue $true
        $policy.AutoStrip | Should -BeTrue
        $policy.Source | Should -Be 'preference'
    }

    It 'reports env source when env supplies a truthy "1"' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue '1' -PreferenceValue $false
        $policy.AutoStrip | Should -BeTrue
        $policy.Source | Should -Be 'env'
    }

    It 'reports env source for the case-insensitive "TRUE" string' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue 'TRUE' -PreferenceValue $null
        $policy.AutoStrip | Should -BeTrue
        $policy.Source | Should -Be 'env'
    }

    It 'reports env source for "yes" and "on" aliases' {
        (Resolve-BaselineHostsCleanupPolicy -EnvValue 'yes' -PreferenceValue $null).AutoStrip | Should -BeTrue
        (Resolve-BaselineHostsCleanupPolicy -EnvValue 'on' -PreferenceValue $null).AutoStrip | Should -BeTrue
        (Resolve-BaselineHostsCleanupPolicy -EnvValue 'enabled' -PreferenceValue $null).AutoStrip | Should -BeTrue
    }

    It 'records env source even when env is falsy and preference is truthy' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue '0' -PreferenceValue $true
        $policy.AutoStrip | Should -BeFalse
        $policy.Source | Should -Be 'env'
    }

    It 'records env source for the literal string "false"' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue 'false' -PreferenceValue $true
        $policy.AutoStrip | Should -BeFalse
        $policy.Source | Should -Be 'env'
    }

    It 'reports preference source when only the preference is set (boolean true)' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue $null -PreferenceValue $true
        $policy.AutoStrip | Should -BeTrue
        $policy.Source | Should -Be 'preference'
    }

    It 'reports preference source when only the preference is set (boolean false)' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue $null -PreferenceValue $false
        $policy.AutoStrip | Should -BeFalse
        $policy.Source | Should -Be 'preference'
    }

    It 'treats integer 1 from preference as truthy' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue $null -PreferenceValue 1
        $policy.AutoStrip | Should -BeTrue
        $policy.Source | Should -Be 'preference'
    }

    It 'treats integer 0 from preference as falsy' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue $null -PreferenceValue 0
        $policy.AutoStrip | Should -BeFalse
        $policy.Source | Should -Be 'preference'
    }

    It 'treats arbitrary garbage strings as falsy' {
        $policy = Resolve-BaselineHostsCleanupPolicy -EnvValue 'maybe' -PreferenceValue $null
        $policy.AutoStrip | Should -BeFalse
        $policy.Source | Should -Be 'env'
    }
}

Describe 'Resolve-BaselineHostTaintAssessment' {
    It 'returns Level=None when no tweakers were detected' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @()
        $assessment.Level | Should -Be 'None'
        $assessment.BackdoorFound | Should -BeFalse
        @($assessment.Detected).Count | Should -Be 0
        @($assessment.AdvisoryUrls).Count | Should -Be 0
    }

    It 'returns Level=None when the input is null' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames $null
        $assessment.Level | Should -Be 'None'
        $assessment.BackdoorFound | Should -BeFalse
    }

    It 'returns Level=Warning when generic tweakers are detected' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('AtlasOS', 'BoosterX')
        $assessment.Level | Should -Be 'Warning'
        $assessment.BackdoorFound | Should -BeFalse
        @($assessment.Detected) | Should -Contain 'AtlasOS'
        @($assessment.Detected) | Should -Contain 'BoosterX'
        @($assessment.AdvisoryUrls).Count | Should -Be 0
    }

    It 'returns Level=Blocked when the Win 10 Tweaker backdoor is in the list' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('Win 10 Tweaker', 'AtlasOS')
        $assessment.Level | Should -Be 'Blocked'
        $assessment.BackdoorFound | Should -BeTrue
        @($assessment.AdvisoryUrls).Count | Should -BeGreaterThan 0
    }

    It 'surfaces the massgrave genuine-ISO link when blocked' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('Win 10 Tweaker')
        @($assessment.AdvisoryUrls) | Should -Contain 'https://massgrave.dev/genuine-installation-media'
    }

    It 'de-duplicates and sorts the detected list' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('AtlasOS', 'BoosterX', 'AtlasOS')
        @($assessment.Detected).Count | Should -Be 2
        $assessment.Detected[0] | Should -Be 'AtlasOS'
        $assessment.Detected[1] | Should -Be 'BoosterX'
    }

    It 'ignores empty and whitespace names' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('', '   ', 'AtlasOS', $null)
        @($assessment.Detected).Count | Should -Be 1
        $assessment.Detected[0] | Should -Be 'AtlasOS'
        $assessment.Level | Should -Be 'Warning'
    }

    It 'honours a caller-supplied backdoor name when probing custom catalogs' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('CustomBackdoor') -BackdoorTweakerName 'CustomBackdoor'
        $assessment.Level | Should -Be 'Blocked'
        $assessment.BackdoorFound | Should -BeTrue
    }

    It 'trims whitespace before comparing the backdoor name' {
        $assessment = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames @('  Win 10 Tweaker  ')
        $assessment.BackdoorFound | Should -BeTrue
        $assessment.Level | Should -Be 'Blocked'
    }
}

Describe 'InitialActions hosts-cleanup wiring' {
    BeforeAll {
        $script:initialActionsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/InitialActions.psm1')
    }

    It 'invokes Resolve-BaselineHostsCleanupPolicy in the hosts-cleanup branch' {
        $script:initialActionsContent | Should -Match 'Resolve-BaselineHostsCleanupPolicy'
    }

    It 'reads the BASELINE_AUTO_STRIP_HOSTS environment variable' {
        $script:initialActionsContent | Should -Match 'BASELINE_AUTO_STRIP_HOSTS'
    }

    It 'reads the AutoStripBaselineHosts user preference' {
        $script:initialActionsContent | Should -Match 'AutoStripBaselineHosts'
    }

    It 'guards Set-Content + Notepad behind the AutoStrip branch' {
        $script:initialActionsContent | Should -Match 'if \(-not \$hostsPolicy\.AutoStrip\)'
    }
}

Describe 'InitialActions host-taint wiring' {
    BeforeAll {
        $script:initialActionsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/InitialActions.psm1')
    }

    It 'collects detected tweakers into a list' {
        $script:initialActionsContent | Should -Match '\$DetectedTweakers = New-Object System\.Collections\.Generic\.List\[string\]'
    }

    It 'feeds the list into Resolve-BaselineHostTaintAssessment' {
        $script:initialActionsContent | Should -Match 'Resolve-BaselineHostTaintAssessment -DetectedTweakerNames \$DetectedTweakers'
    }

    It 'pins the assessment onto a global so downstream regions can read it' {
        $script:initialActionsContent | Should -Match '\$Global:BaselineHostTaint = Resolve-BaselineHostTaintAssessment'
    }

    It 'no longer emits the redundant generic warning when Win 10 Tweaker is the match' {
        # Both warnings used to fire back-to-back; the regression-fix branch
        # uses an else so only the trojan warning surfaces in that case.
        $script:initialActionsContent | Should -Match 'Win 10 Tweaker"\)\s*\r?\n\s*\{\s*\r?\n\s*LogWarning .*Win10TweakerWarning.*\r?\n\s*\}\s*\r?\n\s*else'
    }
}
