Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/PlatformSupport.Helpers.ps1'
    . $filePath

    function script:NewSystemInfo {
        param(
            [int]$Major = 10,
            [int]$Build = 22631,
            [int]$ProductType = 1,
            [string]$Edition = 'Pro',
            [string]$Architecture = 'amd64'
        )
        Get-BaselineSystemPlatformInfo -Override @{
            MajorVersion = $Major
            BuildNumber = $Build
            ProductType = $ProductType
            EditionID = $Edition
            Architecture = $Architecture
        }
    }
}

Describe 'Get-BaselineSystemPlatformInfo (override)' {
    It 'derives IsWindows11 when build is >= 22000 and ProductType=1' {
        $s = NewSystemInfo -Build 22631 -ProductType 1
        $s.IsWindows11 | Should -BeTrue
        $s.IsWindows10 | Should -BeFalse
        $s.IsServer | Should -BeFalse
    }

    It 'derives IsWindows10 when build is < 22000 and ProductType=1' {
        $s = NewSystemInfo -Build 19045 -ProductType 1
        $s.IsWindows10 | Should -BeTrue
        $s.IsWindows11 | Should -BeFalse
    }

    It 'derives IsServer when ProductType is not 1' {
        $s = NewSystemInfo -Build 20348 -ProductType 3
        $s.IsServer | Should -BeTrue
        $s.IsWindows11 | Should -BeFalse
        $s.IsWindows10 | Should -BeFalse
    }

    It 'accepts a hashtable override and returns a pscustomobject' {
        $s = Get-BaselineSystemPlatformInfo -Override @{ MajorVersion = 10; BuildNumber = 22000; ProductType = 1; EditionID = 'Home' }
        $s | Should -BeOfType ([pscustomobject])
        $s.EditionID | Should -Be 'Home'
    }
}

Describe 'ConvertTo-BaselinePlatformLabel' {
    It 'returns Unknown for null input' {
        ConvertTo-BaselinePlatformLabel -PlatformSupport $null | Should -Be 'Unknown'
    }

    It 'returns Shared when all three are true' {
        $ps = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'Shared'
    }

    It 'returns ClientOnly when only Win10+Win11' {
        $ps = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $false }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'ClientOnly'
    }

    It 'returns ServerOnly when only Server' {
        $ps = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = $true }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'ServerOnly'
    }

    It 'returns Windows10Only / Windows11Only correctly' {
        ConvertTo-BaselinePlatformLabel -PlatformSupport ([pscustomobject]@{ Windows10 = $true; Windows11 = $false; Server = $false }) | Should -Be 'Windows10Only'
        ConvertTo-BaselinePlatformLabel -PlatformSupport ([pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false }) | Should -Be 'Windows11Only'
    }

    It 'returns Unsupported when nothing is enabled' {
        $ps = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = $false }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'Unsupported'
    }
}

Describe 'Test-BaselineEntryAvailable' {
    It 'returns Available when no PlatformSupport is declared (NoPlatformMetadata source)' {
        $entry = [pscustomobject]@{ Id = 'NoMeta' }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo)
        $r.Available | Should -BeTrue
        $r.Source | Should -Be 'NoPlatformMetadata'
    }

    It 'hides a Windows-11-only tweak on Windows 10' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 19045)
        $r.Available | Should -BeFalse
        $r.Source | Should -Be 'PlatformSupport'
        $r.Reason | Should -Match 'Windows 10'
    }

    It 'hides a Windows-10-only tweak on Windows 11' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $false; Server = $false } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 22631)
        $r.Available | Should -BeFalse
        $r.Reason | Should -Match 'Windows 11'
    }

    It 'hides a client-only tweak on Server' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $false } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 20348 -ProductType 3)
        $r.Available | Should -BeFalse
        $r.Reason | Should -Match 'Server'
    }

    It 'hides a server-only tweak on the client' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = $true } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 22631 -ProductType 1)
        $r.Available | Should -BeFalse
        $r.Reason | Should -Match 'Windows 11'
    }

    It 'honors MinBuild' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true; MinBuild = 22631 } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 22000)
        $r.Available | Should -BeFalse
        $r.Source | Should -Be 'MinBuild'
    }

    It 'honors MaxBuild for deprecated tweaks' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true; MaxBuild = 22000 } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 22631)
        $r.Available | Should -BeFalse
        $r.Source | Should -Be 'MaxBuild'
    }

    It 'uses the custom UnavailableReason when provided' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false; UnavailableReason = 'Only available on Windows 11.' } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 19045)
        $r.Available | Should -BeFalse
        $r.Reason | Should -Be 'Only available on Windows 11.'
    }

    It 'enforces Architectures constraint' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true; Architectures = @('arm64') } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Architecture 'amd64')
        $r.Available | Should -BeFalse
        $r.Source | Should -Be 'Architecture'
    }

    It 'leaves Available=$true when nothing in PlatformSupport rules it out' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true } }
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo (NewSystemInfo -Build 22631)
        $r.Available | Should -BeTrue
        $r.Source | Should -Be 'PlatformSupport'
    }

    It 'returns a non-empty Reason whenever Available is false' {
        $cases = @(
            [pscustomobject]@{ Id = 'A'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $true } }
            [pscustomobject]@{ Id = 'B'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true; MinBuild = 99999 } }
        )
        $sys = NewSystemInfo -Build 19045
        foreach ($c in $cases) {
            $r = Test-BaselineEntryAvailable -Entry $c -SystemInfo $sys
            $r.Available | Should -BeFalse
            $r.Reason | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Test-BaselineEditionInFamily' {
    It 'returns $false for empty / null EditionID' {
        Test-BaselineEditionInFamily -EditionID '' -Families @('Pro') | Should -BeFalse
    }

    It 'matches Professional / ProfessionalEducation as Pro family' {
        Test-BaselineEditionInFamily -EditionID 'Professional' -Families @('Pro') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'ProfessionalEducation' -Families @('Pro') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'ProfessionalWorkstation' -Families @('Pro') | Should -BeTrue
    }

    It 'matches Core / CoreSingleLanguage as Home family' {
        Test-BaselineEditionInFamily -EditionID 'Core' -Families @('Home') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'CoreSingleLanguage' -Families @('Home') | Should -BeTrue
    }

    It 'matches Enterprise (and EnterpriseS LTSC)' {
        Test-BaselineEditionInFamily -EditionID 'Enterprise' -Families @('Enterprise') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'EnterpriseS' -Families @('Enterprise') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'IoTEnterprise' -Families @('Enterprise') | Should -BeTrue
    }

    It 'matches Education' {
        Test-BaselineEditionInFamily -EditionID 'Education' -Families @('Education') | Should -BeTrue
    }

    It 'matches Server SKUs' {
        Test-BaselineEditionInFamily -EditionID 'ServerStandard' -Families @('Server') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'ServerDatacenter' -Families @('Server') | Should -BeTrue
    }

    It 'returns $true when any family in the list matches' {
        Test-BaselineEditionInFamily -EditionID 'Professional' -Families @('Pro','Enterprise','Education') | Should -BeTrue
        Test-BaselineEditionInFamily -EditionID 'Education' -Families @('Pro','Enterprise','Education') | Should -BeTrue
    }

    It 'returns $false when none of the families match' {
        Test-BaselineEditionInFamily -EditionID 'Core' -Families @('Pro','Enterprise','Education') | Should -BeFalse
    }
}

Describe 'Get-BaselineServerReleaseFromBuild' {
    It 'returns $null for non-server / pre-2019 builds' {
        Get-BaselineServerReleaseFromBuild -BuildNumber 0 | Should -BeNullOrEmpty
        Get-BaselineServerReleaseFromBuild -BuildNumber 14393 | Should -BeNullOrEmpty
    }

    It 'maps build 17763 to Server2019' {
        Get-BaselineServerReleaseFromBuild -BuildNumber 17763 | Should -Be 'Server2019'
    }

    It 'maps build 20348 to Server2022' {
        Get-BaselineServerReleaseFromBuild -BuildNumber 20348 | Should -Be 'Server2022'
    }

    It 'maps build 25398 (23H2) to Server2022' {
        Get-BaselineServerReleaseFromBuild -BuildNumber 25398 | Should -Be 'Server2022'
    }

    It 'maps build 26100 to Server2025' {
        Get-BaselineServerReleaseFromBuild -BuildNumber 26100 | Should -Be 'Server2025'
    }
}

Describe 'Get-BaselineSystemPlatformInfo ServerRelease' {
    It 'derives ServerRelease from the build for Server hosts' {
        $s = NewSystemInfo -Build 20348 -ProductType 3
        $s.IsServer | Should -BeTrue
        $s.ServerRelease | Should -Be 'Server2022'
    }

    It 'leaves ServerRelease null on client hosts' {
        $s = NewSystemInfo -Build 22631 -ProductType 1
        $s.ServerRelease | Should -BeNullOrEmpty
    }

    It 'honors an explicit ServerRelease override' {
        $s = Get-BaselineSystemPlatformInfo -Override @{
            MajorVersion = 10; BuildNumber = 99999; ProductType = 3; ServerRelease = 'Server2025'
        }
        $s.ServerRelease | Should -Be 'Server2025'
    }
}

Describe 'Test-BaselineEntryAvailable Server array form' {
    It 'allows the entry on a matching ServerRelease' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = @('Server2022','Server2025') } }
        $sys = NewSystemInfo -Build 20348 -ProductType 3
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo $sys
        $r.Available | Should -BeTrue
    }

    It 'hides the entry on a non-matching ServerRelease' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = @('Server2022','Server2025') } }
        $sys = NewSystemInfo -Build 17763 -ProductType 3  # 2019
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo $sys
        $r.Available | Should -BeFalse
        $r.Reason | Should -Match 'Server2022'
        $r.Source | Should -Be 'PlatformSupport'
    }

    It 'treats an empty Server array as fully unsupported on Server' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = @() } }
        $sys = NewSystemInfo -Build 20348 -ProductType 3
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo $sys
        $r.Available | Should -BeFalse
        $r.Reason | Should -Match 'Windows Server'
    }

    It 'falls back to the custom UnavailableReason on a non-matching ServerRelease' {
        $entry = [pscustomobject]@{ Id = 'X'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = @('Server2025'); UnavailableReason = 'Requires Server 2025.' } }
        $sys = NewSystemInfo -Build 20348 -ProductType 3
        $r = Test-BaselineEntryAvailable -Entry $entry -SystemInfo $sys
        $r.Available | Should -BeFalse
        $r.Reason | Should -Be 'Requires Server 2025.'
    }
}

Describe 'ConvertTo-BaselinePlatformLabel Server array form' {
    It 'treats a non-empty Server array as ServerOnly when client flags are off' {
        $ps = [pscustomobject]@{ Windows10 = $false; Windows11 = $false; Server = @('Server2022') }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'ServerOnly'
    }

    It 'treats an empty Server array as no-server' {
        $ps = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = @() }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'ClientOnly'
    }

    It 'treats a non-empty Server array as Shared when both client flags are on' {
        $ps = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = @('Server2022','Server2025') }
        ConvertTo-BaselinePlatformLabel -PlatformSupport $ps | Should -Be 'Shared'
    }
}

Describe 'Get-BaselineEntryAvailabilitySummary' {
    It 'reports zero counts for an empty / null collection' {
        $s = Get-BaselineEntryAvailabilitySummary -Entries @() -SystemInfo (NewSystemInfo)
        $s.Total | Should -Be 0
        $s.Available | Should -Be 0
        $s.Skipped | Should -Be 0
    }

    It 'uses the same shape (Selected: 40 / Available: 35 / Skipped: 5)' {
        $entries = @()
        for ($i = 0; $i -lt 35; $i++) {
            $entries += [pscustomobject]@{ Id = "shared-$i"; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true } }
        }
        for ($i = 0; $i -lt 5; $i++) {
            $entries += [pscustomobject]@{ Id = "win11-$i"; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false } }
        }
        $sys = NewSystemInfo -Build 19045
        $s = Get-BaselineEntryAvailabilitySummary -Entries $entries -SystemInfo $sys
        $s.Total | Should -Be 40
        $s.Available | Should -Be 35
        $s.Skipped | Should -Be 5
        ($s.Entries | Where-Object { -not $_.Available } | Measure-Object).Count | Should -Be 5
    }

    It 'preserves the entry id for each per-entry record' {
        $entries = @(
            [pscustomobject]@{ Id = 'IdField'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true } }
            [pscustomobject]@{ Name = 'NameField'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false } }
        )
        $sys = NewSystemInfo -Build 19045
        $s = Get-BaselineEntryAvailabilitySummary -Entries $entries -SystemInfo $sys
        $s.Entries[0].Id | Should -Be 'IdField'
        $s.Entries[1].Id | Should -Be 'NameField'
    }
}

Describe 'Test-BaselineEntrySupportsExecution' {
    It 'returns $true when the field is missing (default executable)' {
        $entry = [pscustomobject]@{ Id = 'NoField' }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeTrue
    }

    It 'returns $true when SupportsExecution is explicitly true' {
        $entry = [pscustomobject]@{ Id = 'Yes'; SupportsExecution = $true }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeTrue
    }

    It 'returns $false when SupportsExecution is explicitly false' {
        $entry = [pscustomobject]@{ Id = 'No'; SupportsExecution = $false }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeFalse
    }

    It 'returns $true when the entry is $null (no entry to gate)' {
        Test-BaselineEntrySupportsExecution -Entry $null | Should -BeTrue
    }

    It 'works against an ordered hashtable (loader entry shape)' {
        $entry = [ordered]@{ Id = 'H'; SupportsExecution = $false }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeFalse
    }

    It 'is independent of PlatformSupport / Availability' {
        # PlatformSupport says available, but execution is disclaimed: still false.
        $entry = [pscustomobject]@{
            Id = 'X'
            PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true }
            SupportsExecution = $false
        }
        Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeFalse
    }
}

Describe 'Get-BaselineEntrySupportsExecutionReason' {
    It 'returns the explicit reason when present' {
        $entry = [pscustomobject]@{
            SupportsExecution = $false
            SupportsExecutionReason = 'Windows Terminal is not installed on this system.'
        }

        Get-BaselineEntrySupportsExecutionReason -Entry $entry | Should -Be 'Windows Terminal is not installed on this system.'
    }

    It 'returns $null when no reason is present' {
        $entry = [pscustomobject]@{ SupportsExecution = $false }
        Get-BaselineEntrySupportsExecutionReason -Entry $entry | Should -BeNullOrEmpty
    }
}

Describe 'Get-BaselineEntryExecutionSupport' {
    It 'preserves explicit SupportsExecution metadata' {
        $entry = [pscustomobject]@{
            Function = 'Any'
            SupportsExecution = $false
            SupportsExecutionReason = 'Explicit manifest reason.'
        }

        $result = Get-BaselineEntryExecutionSupport -Entry $entry
        $result.SupportsExecution | Should -BeFalse
        $result.Reason | Should -Be 'Explicit manifest reason.'
    }

    It 'marks package-backed entries unsupported when the required Appx package is missing' {
        Mock Get-AppxPackage { $null } -ParameterFilter { $Name -eq 'MicrosoftWindows.Client.WebExperience' }

        $result = Get-BaselineEntryExecutionSupport -Entry ([pscustomobject]@{
            Function = 'TaskbarWidgets'
        })

        $result.SupportsExecution | Should -BeFalse
        $result.Reason | Should -Match 'Web Experience Pack'
    }

    It 'loads bundled WinRT dependencies before Appx package-backed checks' {
        $script:WinRtDependencyLoaderCalled = $false
        function Initialize-BaselineWinRtRuntimeDependencies {
            $script:WinRtDependencyLoaderCalled = $true
            return $true
        }
        Mock Get-AppxPackage { [pscustomobject]@{ Name = $Name } } -ParameterFilter { $Name -eq 'MicrosoftWindows.Client.WebExperience' }

        try {
            $result = Get-BaselineEntryExecutionSupport -Entry ([pscustomobject]@{
                Function = 'TaskbarWidgets'
            })

            $script:WinRtDependencyLoaderCalled | Should -BeTrue
            $result.SupportsExecution | Should -BeTrue
            $result.Reason | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item Function:\Initialize-BaselineWinRtRuntimeDependencies -ErrorAction SilentlyContinue
            Remove-Variable -Name WinRtDependencyLoaderCalled -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'does not mark package-backed entries unsupported when the Appx probe is inconclusive' {
        function Initialize-BaselineWinRtRuntimeDependencies {
            return $true
        }
        Mock Get-AppxPackage { throw [System.TypeInitializationException]::new('<Module>', [System.IO.FileNotFoundException]::new('System.Numerics.Vectors')) } -ParameterFilter { $Name -eq 'MicrosoftWindows.Client.WebExperience' }

        try {
            { $script:PackageProbeResult = Get-BaselineEntryExecutionSupport -Entry ([pscustomobject]@{ Function = 'TaskbarWidgets' }) } | Should -Not -Throw
            $script:PackageProbeResult.SupportsExecution | Should -BeTrue
            $script:PackageProbeResult.Reason | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item Function:\Initialize-BaselineWinRtRuntimeDependencies -ErrorAction SilentlyContinue
            Remove-Variable -Name PackageProbeResult -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'marks Defender cmdlet-backed entries unsupported when the Defender command surface is unavailable' {
        Set-BaselineDefenderExecutionAvailability -Available $false -UnavailableReason 'Set-MpPreference is not available.'
        try {
            $result = Get-BaselineEntryExecutionSupport -Entry ([pscustomobject]@{
                Function = 'DefenderScanCPULimit'
            })

            $result.SupportsExecution | Should -BeFalse
            $result.Reason | Should -Match 'Set-MpPreference is not available'
        }
        finally {
            Reset-BaselineDefenderExecutionAvailability
        }
    }

    It 'does not block registry-only Windows Security entries on Defender command availability' {
        Set-BaselineDefenderExecutionAvailability -Available $false -UnavailableReason 'Set-MpPreference is not available.'
        try {
            $result = Get-BaselineEntryExecutionSupport -Entry ([pscustomobject]@{
                Function = 'AppsSmartScreen'
            })

            $result.SupportsExecution | Should -BeTrue
            $result.Reason | Should -BeNullOrEmpty
        }
        finally {
            Reset-BaselineDefenderExecutionAvailability
        }
    }
}

Describe 'Update-BaselineManifestExecutionSupport' {
    It 'stamps SupportsExecution metadata onto manifest entries' {
        Mock Get-AppxPackage { $null } -ParameterFilter { $Name -eq 'MicrosoftWindows.Client.WebExperience' }

        $manifest = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Function = 'TaskbarWidgets' }
            )
        }

        $null = Update-BaselineManifestExecutionSupport -Manifest $manifest

        $manifest.Entries[0].SupportsExecution | Should -BeFalse
        $manifest.Entries[0].SupportsExecutionReason | Should -Match 'Web Experience Pack'
    }
}

Describe 'Update-BaselineManifestAvailability' {
    It 'stamps Availability onto every entry of an Entries-shaped manifest' {
        $manifest = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ Id = 'A'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true } }
                [pscustomobject]@{ Id = 'B'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false } }
            )
        }
        $sys = NewSystemInfo -Build 19045  # Win10
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sys
        $manifest.Entries[0].Availability.Available | Should -BeTrue
        $manifest.Entries[0].Availability.Label | Should -Be 'Shared'
        $manifest.Entries[1].Availability.Available | Should -BeFalse
        $manifest.Entries[1].Availability.Reason | Should -Be 'Not available on Windows 10.'
        $manifest.Entries[1].Availability.Label | Should -Be 'Windows11Only'
    }

    It 'stamps Availability onto a bare array of entries' {
        $entries = @(
            [pscustomobject]@{ Id = 'X' }
            [pscustomobject]@{ Id = 'Y'; PlatformSupport = [pscustomobject]@{ Server = $false; Windows10 = $true; Windows11 = $true } }
        )
        $sys = NewSystemInfo -Build 22631 -ProductType 3
        $null = Update-BaselineManifestAvailability -Manifest $entries -SystemInfo $sys
        $entries[0].Availability.Available | Should -BeTrue
        $entries[0].Availability.Source | Should -Be 'NoPlatformMetadata'
        $entries[1].Availability.Available | Should -BeFalse
        $entries[1].Availability.Reason | Should -Be 'Not available on Windows Server.'
    }

    It 'stamps Availability onto hashtable entries (mutating the dictionary in place)' {
        $entry = [ordered]@{ Id = 'H'; PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false } }
        $manifest = [pscustomobject]@{ Entries = @($entry) }
        $sys = NewSystemInfo -Build 22631
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sys
        $entry.Contains('Availability') | Should -BeTrue
        $entry['Availability'].Available | Should -BeTrue
    }

    It 'tolerates a $null manifest' {
        { Update-BaselineManifestAvailability -Manifest $null -SystemInfo (NewSystemInfo) } | Should -Not -Throw
    }

    It 'is idempotent — re-stamping replaces the prior Availability block' {
        $entry = [pscustomobject]@{ Id = 'R'; PlatformSupport = [pscustomobject]@{ Windows10 = $true; Windows11 = $true; Server = $true } }
        $manifest = [pscustomobject]@{ Entries = @($entry) }
        $sysA = NewSystemInfo -Build 19045
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysA
        $entry.Availability.Available | Should -BeTrue
        # Now re-stamp with a Windows11-only entry against a Win10 host.
        $entry.PlatformSupport = [pscustomobject]@{ Windows10 = $false; Windows11 = $true; Server = $false }
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysA
        $entry.Availability.Available | Should -BeFalse
        $entry.Availability.Label | Should -Be 'Windows11Only'
    }
}
