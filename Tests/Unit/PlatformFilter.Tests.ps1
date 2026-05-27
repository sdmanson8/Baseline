Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/PlatformSupport.Helpers.ps1'
    . $filePath

    # Tiny in-memory manifest with one entry per platform combo, exercising
    # both ordered-hashtable and pscustomobject shapes the real loader emits.
    function script:NewSyntheticManifest
    {
        $win10Only = [ordered]@{
            Id = 'TweakWin10Only'
            Name = 'Windows 10 only'
            PlatformSupport = [ordered]@{ Windows10 = $true; Windows11 = $false; Server = $false }
        }
        $win11Only = [ordered]@{
            Id = 'TweakWin11Only'
            Name = 'Windows 11 only'
            PlatformSupport = [ordered]@{ Windows10 = $false; Windows11 = $true; Server = $false }
        }
        $serverOnly = [ordered]@{
            Id = 'TweakServerOnly'
            Name = 'Server only'
            PlatformSupport = [ordered]@{ Windows10 = $false; Windows11 = $false; Server = $true }
        }
        $shared = [ordered]@{
            Id = 'TweakShared'
            Name = 'Shared (all platforms)'
            PlatformSupport = [ordered]@{ Windows10 = $true; Windows11 = $true; Server = $true }
        }
        $noMeta = [ordered]@{
            Id = 'TweakNoMeta'
            Name = 'No platform metadata'
        }
        return @($win10Only, $win11Only, $serverOnly, $shared, $noMeta)
    }

    function script:GetEntry
    {
        param([object[]]$Manifest, [string]$Id)
        foreach ($entry in $Manifest) { if ([string]$entry['Id'] -eq $Id) { return $entry } }
        return $null
    }

    function script:GetAvailable
    {
        param([object[]]$Manifest, [string]$Id)
        $entry = GetEntry -Manifest $Manifest -Id $Id
        if (-not $entry -or -not $entry.Contains('Availability')) { return $null }
        return [bool]$entry['Availability'].Available
    }
}

Describe 'Get-BaselinePlatformFilterOverride' {
    It 'returns ThisDevice mode + null override for empty / null filter' {
        $r = Get-BaselinePlatformFilterOverride -Filter ''
        $r.Mode | Should -Be 'ThisDevice'
        $r.Override | Should -BeNullOrEmpty
        $r2 = Get-BaselinePlatformFilterOverride -Filter $null
        $r2.Mode | Should -Be 'ThisDevice'
    }

    It 'returns AllSupported mode + null override for All / AllSupported' {
        (Get-BaselinePlatformFilterOverride -Filter 'All').Mode          | Should -Be 'AllSupported'
        (Get-BaselinePlatformFilterOverride -Filter 'AllSupported').Mode | Should -Be 'AllSupported'
        (Get-BaselinePlatformFilterOverride -Filter 'AllSupported').Override | Should -BeNullOrEmpty
    }

    It 'returns Windows 10 client override (build < 22000, ProductType=1)' {
        $r = Get-BaselinePlatformFilterOverride -Filter 'Windows10'
        $r.Mode | Should -Be 'Windows10'
        $r.Override.BuildNumber | Should -BeLessThan 22000
        $r.Override.ProductType | Should -Be 1
    }

    It 'returns Windows 11 client override (build >= 22000, ProductType=1)' {
        $r = Get-BaselinePlatformFilterOverride -Filter 'Windows11'
        $r.Mode | Should -Be 'Windows11'
        $r.Override.BuildNumber | Should -BeGreaterOrEqual 22000
        $r.Override.ProductType | Should -Be 1
    }

    It 'returns Server override (ProductType=3, ServerRelease populated)' {
        $r = Get-BaselinePlatformFilterOverride -Filter 'Server'
        $r.Mode | Should -Be 'Server'
        $r.Override.ProductType | Should -Be 3
        $r.Override.ServerRelease | Should -Be 'Server2025'
    }

    It 'falls back to ThisDevice for unknown filter values' {
        $r = Get-BaselinePlatformFilterOverride -Filter 'NotARealMode'
        $r.Mode | Should -Be 'ThisDevice'
        $r.Override | Should -BeNullOrEmpty
    }
}

Describe 'Platform filter — manifest re-stamp end-to-end' {
    It 'Windows10 filter: only Win10-supporting entries become Available' {
        $manifest = NewSyntheticManifest
        $resolved = Get-BaselinePlatformFilterOverride -Filter 'Windows10'
        $sysInfo = Get-BaselineSystemPlatformInfo -Override $resolved.Override
        $sysInfo.IsWindows10 | Should -BeTrue
        $sysInfo.IsWindows11 | Should -BeFalse
        $sysInfo.IsServer    | Should -BeFalse
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysInfo

        GetAvailable -Manifest $manifest -Id 'TweakWin10Only'   | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only'   | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakServerOnly'  | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakShared'      | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakNoMeta'      | Should -BeTrue
    }

    It 'Windows11 filter: only Win11-supporting entries become Available' {
        $manifest = NewSyntheticManifest
        $resolved = Get-BaselinePlatformFilterOverride -Filter 'Windows11'
        $sysInfo = Get-BaselineSystemPlatformInfo -Override $resolved.Override
        $sysInfo.IsWindows11 | Should -BeTrue
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysInfo

        GetAvailable -Manifest $manifest -Id 'TweakWin10Only'   | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only'   | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakServerOnly'  | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakShared'      | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakNoMeta'      | Should -BeTrue
    }

    It 'Server filter: only Server-supporting entries become Available' {
        $manifest = NewSyntheticManifest
        $resolved = Get-BaselinePlatformFilterOverride -Filter 'Server'
        $sysInfo = Get-BaselineSystemPlatformInfo -Override $resolved.Override
        $sysInfo.IsServer | Should -BeTrue
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysInfo

        GetAvailable -Manifest $manifest -Id 'TweakWin10Only'   | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only'   | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakServerOnly'  | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakShared'      | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakNoMeta'      | Should -BeTrue
    }

    It 'AllSupported filter: every entry is force-stamped Available regardless of metadata' {
        $manifest = NewSyntheticManifest
        $resolved = Get-BaselinePlatformFilterOverride -Filter 'AllSupported'
        $resolved.Mode | Should -Be 'AllSupported'
        $null = Set-BaselineManifestAllAvailable -Manifest $manifest

        GetAvailable -Manifest $manifest -Id 'TweakWin10Only'   | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only'   | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakServerOnly'  | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakShared'      | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakNoMeta'      | Should -BeTrue
        # Source field signals which code path produced the stamp so callers
        # / log readers can tell preview-mode apart from real availability.
        $entry = GetEntry -Manifest $manifest -Id 'TweakServerOnly'
        $entry['Availability'].Source | Should -Be 'PlatformFilterAllSupported'
    }

    It 'ThisDevice filter (no override): uses a real-shaped Win11 SystemInfo' {
        $manifest = NewSyntheticManifest
        $resolved = Get-BaselinePlatformFilterOverride -Filter 'ThisDevice'
        $resolved.Override | Should -BeNullOrEmpty
        # Caller would invoke Get-BaselineSystemPlatformInfo with no override.
        # We simulate a Win11 host explicitly so the test is deterministic.
        $sysInfo = Get-BaselineSystemPlatformInfo -Override @{ MajorVersion = 10; BuildNumber = 26100; ProductType = 1; EditionID = 'Pro' }
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysInfo

        # Same gating as the Windows11 filter case, by construction.
        GetAvailable -Manifest $manifest -Id 'TweakWin10Only'   | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only'   | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakServerOnly'  | Should -BeFalse
        GetAvailable -Manifest $manifest -Id 'TweakShared'      | Should -BeTrue
    }

    It 'Re-stamping switches an entry from Unavailable to Available cleanly' {
        $manifest = NewSyntheticManifest
        # First pass — Win10
        $sysInfo10 = Get-BaselineSystemPlatformInfo -Override (Get-BaselinePlatformFilterOverride -Filter 'Windows10').Override
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysInfo10
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only' | Should -BeFalse

        # Second pass — Win11. Same entry must flip without leaving stale state.
        $sysInfo11 = Get-BaselineSystemPlatformInfo -Override (Get-BaselinePlatformFilterOverride -Filter 'Windows11').Override
        $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sysInfo11
        GetAvailable -Manifest $manifest -Id 'TweakWin11Only' | Should -BeTrue
        GetAvailable -Manifest $manifest -Id 'TweakWin10Only' | Should -BeFalse
    }
}
