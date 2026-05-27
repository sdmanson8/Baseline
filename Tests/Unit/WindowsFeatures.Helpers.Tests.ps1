Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/WindowsFeatures.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Get-WindowsCapabilityCheckedDefaults' {
    It 'returns a non-empty pattern list' {
        $result = Get-WindowsCapabilityCheckedDefaults
        $result.Count | Should -BeGreaterThan 0
    }

    It 'includes the Steps Recorder wildcard' {
        Get-WindowsCapabilityCheckedDefaults | Should -Contain 'App.StepsRecorder*'
    }
}

Describe 'Get-WindowsCapabilityUncheckedDefaults' {
    It 'includes Internet Explorer mode' {
        Get-WindowsCapabilityUncheckedDefaults | Should -Contain 'Browser.InternetExplorer*'
    }

    It 'includes Windows Media Player' {
        Get-WindowsCapabilityUncheckedDefaults | Should -Contain 'Media.WindowsMediaPlayer*'
    }

    It 'includes a wildcard for Voice Access' {
        Get-WindowsCapabilityUncheckedDefaults | Should -Contain '*VoiceAccess*'
    }
}

Describe 'Get-WindowsCapabilityExcludedDefaults' {
    It 'includes language components' {
        Get-WindowsCapabilityExcludedDefaults | Should -Contain 'Language.*'
    }

    It 'includes Notepad' {
        Get-WindowsCapabilityExcludedDefaults | Should -Contain 'Microsoft.Windows.Notepad*'
    }

    It 'includes shell components critical to Windows' {
        Get-WindowsCapabilityExcludedDefaults | Should -Contain 'Windows.Client.ShellComponents*'
    }
}

Describe 'Get-WindowsCapabilityFriendlyNameMap' {
    It 'returns a hashtable' {
        Get-WindowsCapabilityFriendlyNameMap | Should -BeOfType ([hashtable])
    }

    It 'maps App.StepsRecorder to "Steps Recorder"' {
        $map = Get-WindowsCapabilityFriendlyNameMap
        $map['App.StepsRecorder'] | Should -Be 'Steps Recorder'
    }

    It 'maps OpenSSH.Server to "OpenSSH Server"' {
        $map = Get-WindowsCapabilityFriendlyNameMap
        $map['OpenSSH.Server'] | Should -Be 'OpenSSH Server'
    }

    It 'maps VoiceAccess to "Voice Access"' {
        $map = Get-WindowsCapabilityFriendlyNameMap
        $map['VoiceAccess'] | Should -Be 'Voice Access'
    }
}

Describe 'Get-WindowsFeatureCheckedDefaults' {
    It 'includes LegacyComponents' {
        Get-WindowsFeatureCheckedDefaults | Should -Contain 'LegacyComponents'
    }

    It 'includes both PowerShell V2 entries' {
        $defaults = Get-WindowsFeatureCheckedDefaults
        $defaults | Should -Contain 'MicrosoftWindowsPowerShellV2'
        $defaults | Should -Contain 'MicrosoftWindowsPowershellV2Root'
    }

    It 'includes Recall and WorkFolders-Client (regression: previously joined by missing comma)' {
        $defaults = Get-WindowsFeatureCheckedDefaults
        $defaults | Should -Contain 'Recall'
        $defaults | Should -Contain 'WorkFolders-Client'
    }

    It 'includes the XPS document writer' {
        Get-WindowsFeatureCheckedDefaults | Should -Contain 'Printing-XPSServices-Features'
    }
}

Describe 'Get-WindowsFeatureUncheckedDefaults' {
    It 'includes MediaPlayback' {
        Get-WindowsFeatureUncheckedDefaults | Should -Contain 'MediaPlayback'
    }

    It 'includes Windows Sandbox container' {
        Get-WindowsFeatureUncheckedDefaults | Should -Contain 'Containers-DisposableClientVM'
    }

    It 'includes Windows Defender Application Guard' {
        Get-WindowsFeatureUncheckedDefaults | Should -Contain 'Windows-Defender-ApplicationGuard'
    }
}

Describe 'Test-WindowsCapabilityPatternMatch' {
    It 'matches by exact wildcard' {
        Test-WindowsCapabilityPatternMatch -Name 'App.StepsRecorder~~~~0.0.1.0' -Patterns @('App.StepsRecorder*') | Should -BeTrue
    }

    It 'matches across multiple patterns and returns on first hit' {
        Test-WindowsCapabilityPatternMatch -Name 'Media.WindowsMediaPlayer~~~~0.0.12.0' -Patterns @('Browser.InternetExplorer*', 'Media.WindowsMediaPlayer*') | Should -BeTrue
    }

    It 'returns false when no pattern matches' {
        Test-WindowsCapabilityPatternMatch -Name 'Some.Random.Thing' -Patterns @('Browser.InternetExplorer*', 'Media.WindowsMediaPlayer*') | Should -BeFalse
    }

    It 'returns false for an empty pattern list' {
        Test-WindowsCapabilityPatternMatch -Name 'App.StepsRecorder' -Patterns @() | Should -BeFalse
    }

    It 'returns false when patterns is $null' {
        Test-WindowsCapabilityPatternMatch -Name 'App.StepsRecorder' -Patterns $null | Should -BeFalse
    }

    It 'returns false for an empty name' {
        Test-WindowsCapabilityPatternMatch -Name '' -Patterns @('App.*') | Should -BeFalse
    }

    It 'supports leading-wildcard patterns (matches *VoiceAccess*)' {
        Test-WindowsCapabilityPatternMatch -Name 'Microsoft.Windows.Speech.VoiceAccess~~~~' -Patterns @('*VoiceAccess*') | Should -BeTrue
    }
}

Describe 'Get-WindowsCapabilityFriendlyName' {
    It 'prefers the supplied DisplayName when not whitespace' {
        Get-WindowsCapabilityFriendlyName -Name 'App.StepsRecorder~~~~0.0.1.0' -DisplayName 'Steps Recorder (DISM)' |
            Should -Be 'Steps Recorder (DISM)'
    }

    It 'falls back to the friendly name map when DisplayName is empty' {
        Get-WindowsCapabilityFriendlyName -Name 'App.StepsRecorder~~~~0.0.1.0' -DisplayName '' |
            Should -Be 'Steps Recorder'
    }

    It 'falls back to the friendly name map when DisplayName is whitespace' {
        Get-WindowsCapabilityFriendlyName -Name 'OpenSSH.Server~~~~0.0.1.0' -DisplayName '   ' |
            Should -Be 'OpenSSH Server'
    }

    It 'strips the version suffix and returns the bare base name when no map entry exists' {
        Get-WindowsCapabilityFriendlyName -Name 'Some.Unknown.Capability~~~~0.0.1.0' -DisplayName '' |
            Should -Be 'Some.Unknown.Capability'
    }

    It 'matches a pattern in the map even when the name has a long version tail' {
        Get-WindowsCapabilityFriendlyName -Name 'VoiceAccess~~~~0.0.0.0' -DisplayName '' |
            Should -Be 'Voice Access'
    }

    It 'accepts a caller-supplied friendly name map' {
        $map = @{ 'Custom.Cap' = 'Custom Capability' }
        Get-WindowsCapabilityFriendlyName -Name 'Custom.Cap~~~~1.0.0.0' -DisplayName '' -FriendlyNameMap $map |
            Should -Be 'Custom Capability'
    }
}

Describe 'Test-WindowsCapabilitySeedSelected' {
    Context 'when an explicit selected-name list was provided' {
        It 'is selected when the capability appears in the supplied list' {
            Test-WindowsCapabilitySeedSelected -CapabilityName 'App.StepsRecorder~~~~0.0.1.0' `
                -SelectedNames @('App.StepsRecorder~~~~0.0.1.0') `
                -SelectedNamesProvided `
                -CheckedPatterns @() |
                Should -BeTrue
        }

        It 'is not selected when the capability is missing from the supplied list' {
            Test-WindowsCapabilitySeedSelected -CapabilityName 'App.StepsRecorder~~~~0.0.1.0' `
                -SelectedNames @('OpenSSH.Server~~~~0.0.1.0') `
                -SelectedNamesProvided `
                -CheckedPatterns @('App.StepsRecorder*') |
                Should -BeFalse
        }

        It 'is not selected when the supplied list is null' {
            Test-WindowsCapabilitySeedSelected -CapabilityName 'App.StepsRecorder~~~~0.0.1.0' `
                -SelectedNames $null `
                -SelectedNamesProvided `
                -CheckedPatterns @('App.StepsRecorder*') |
                Should -BeFalse
        }
    }

    Context 'when no explicit selected-name list was provided' {
        It 'falls back to the curated CheckedPatterns list' {
            Test-WindowsCapabilitySeedSelected -CapabilityName 'App.StepsRecorder~~~~0.0.1.0' `
                -CheckedPatterns @('App.StepsRecorder*') |
                Should -BeTrue
        }

        It 'is not selected when no curated pattern matches' {
            Test-WindowsCapabilitySeedSelected -CapabilityName 'Some.Other.Capability' `
                -CheckedPatterns @('App.StepsRecorder*') |
                Should -BeFalse
        }
    }
}

Describe 'Select-WindowsCapabilityVisible' {
    It 'returns every capability when no exclude patterns are supplied' {
        $caps = @(
            [pscustomobject]@{ Name = 'A.B' },
            [pscustomobject]@{ Name = 'Language.x-AA' }
        )

        $result = @(Select-WindowsCapabilityVisible -Capabilities $caps -ExcludedPatterns @())
        $result.Count | Should -Be 2
    }

    It 'excludes capabilities matching any pattern in the exclude list' {
        $caps = @(
            [pscustomobject]@{ Name = 'A.B' },
            [pscustomobject]@{ Name = 'Language.x-AA' },
            [pscustomobject]@{ Name = 'Microsoft.Windows.Notepad~~~~' }
        )

        $result = @(Select-WindowsCapabilityVisible -Capabilities $caps -ExcludedPatterns @('Language.*', 'Microsoft.Windows.Notepad*'))
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'A.B'
    }

    It 'returns an empty array when capabilities is null' {
        $result = @(Select-WindowsCapabilityVisible -Capabilities $null -ExcludedPatterns @('Language.*'))
        $result.Count | Should -Be 0
    }

    It 'returns an empty array when capabilities is empty' {
        $result = @(Select-WindowsCapabilityVisible -Capabilities @() -ExcludedPatterns @('Language.*'))
        $result.Count | Should -Be 0
    }
}
