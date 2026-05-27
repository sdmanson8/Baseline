Set-StrictMode -Version Latest

BeforeAll {
    $script:runtimesPath = Join-Path $PSScriptRoot '../../Module/Data/AppsCategory/Runtimes.json'
    $script:runtimes = Get-Content -LiteralPath $script:runtimesPath -Raw | ConvertFrom-Json

    $script:runtimeDetectionPatterns = [ordered]@{
        'Microsoft.VCRedist.2005.x86'   = '^Microsoft Visual C\+\+ 2005 Redistributable \(x86\) - 8\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2005.x64'   = '^Microsoft Visual C\+\+ 2005 Redistributable \(x64\) - 8\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2008.x86'   = '^Microsoft Visual C\+\+ 2008 Redistributable - x86 9\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2008.x64'   = '^Microsoft Visual C\+\+ 2008 Redistributable - x64 9\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2010.x86'   = '^Microsoft Visual C\+\+ 2010\s+x86 Redistributable - 10\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2010.x64'   = '^Microsoft Visual C\+\+ 2010\s+x64 Redistributable - 10\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2012.x86'   = '^Microsoft Visual C\+\+ 2012 Redistributable \(x86\) - 11\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2012.x64'   = '^Microsoft Visual C\+\+ 2012 Redistributable \(x64\) - 11\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2013.x86'   = '^Microsoft Visual C\+\+ 2013 Redistributable \(x86\) - 12\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2013.x64'   = '^Microsoft Visual C\+\+ 2013 Redistributable \(x64\) - 12\.0\.[0-9.]+$'
        'Microsoft.VCRedist.2015+.x86'  = '^Microsoft Visual C\+\+ 2015-2022 Redistributable \(x86\) - 14\.[0-9.]+\.[0-9.]+\.[0-9.]+$'
        'Microsoft.VCRedist.2015+.x64'  = '^Microsoft Visual C\+\+ 2015-2022 Redistributable \(x64\) - 14\.[0-9.]+\.[0-9.]+\.[0-9.]+$'
        'Microsoft.VCRedist.2015+.arm64' = '^Microsoft Visual C\+\+ 2015-2022 Redistributable \(arm64\) - 14\.[0-9.]+\.[0-9.]+\.[0-9.]+$'
    }

    function Get-RuntimeRegistryDetectionMap {
        foreach ($entry in $script:runtimeDetectionPatterns.GetEnumerator()) {
            [pscustomobject]@{
                WinGetId = [string]$entry.Key
                Pattern = [string]$entry.Value
            }
        }
    }

    function Get-InstalledRuntimeRegistryCache {
        param(
            [hashtable]$DisplayNameMap
        )

        $cache = @{}
        $map = @(Get-RuntimeRegistryDetectionMap)
        foreach ($displayName in @($DisplayNameMap.Values)) {
            if ([string]::IsNullOrWhiteSpace([string]$displayName)) { continue }
            foreach ($entry in $map) {
                if ([regex]::IsMatch([string]$displayName, [string]$entry.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                    $cache[$entry.WinGetId] = $true
                    break
                }
            }
        }
        return $cache
    }
}

Describe 'Get-RuntimeRegistryDetectionMap' {
    It 'returns one entry per VC++ runtime in Runtimes.json' {
        $map = Get-RuntimeRegistryDetectionMap
        $map.Count | Should -BeGreaterOrEqual 13
        @($map | Where-Object { $_.WinGetId -eq 'Microsoft.VCRedist.2005.x86' }).Count | Should -Be 1
        @($map | Where-Object { $_.WinGetId -eq 'Microsoft.VCRedist.2015+.arm64' }).Count | Should -Be 1
    }

    It 'every entry exposes WinGetId and Pattern' {
        $map = Get-RuntimeRegistryDetectionMap
        foreach ($entry in $map) {
            $entry.WinGetId | Should -Not -BeNullOrEmpty
            $entry.Pattern | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-InstalledRuntimeRegistryCache' {
    It 'returns an empty hashtable when no DisplayNames match' {
        $names = @{ 'a' = 'Mozilla Firefox'; 'b' = 'Notepad++' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache.Keys.Count | Should -Be 0
    }

    It 'detects the 2015-2022 x64 redistributable from a real DisplayName' {
        $names = @{ 'a' = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.36.32532.0' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2015+.x64'] | Should -Be $true
        $cache.Keys.Count | Should -Be 1
    }

    It 'detects the 2015-2022 x86 redistributable from a real DisplayName' {
        $names = @{ 'a' = 'Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.36.32532.0' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2015+.x86'] | Should -Be $true
    }

    It 'detects the 2013 x64 redistributable from a real DisplayName' {
        $names = @{ 'a' = 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2013.x64'] | Should -Be $true
    }

    It 'detects the 2010 x86 redistributable using the legacy "x86 Redistributable" naming' {
        $names = @{ 'a' = 'Microsoft Visual C++ 2010  x86 Redistributable - 10.0.40219' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2010.x86'] | Should -Be $true
    }

    It 'detects the 2008 x64 redistributable using the legacy "- x64" naming' {
        $names = @{ 'a' = 'Microsoft Visual C++ 2008 Redistributable - x64 9.0.30729.6161' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2008.x64'] | Should -Be $true
    }

    It 'distinguishes 2008 x86 from 2008 x64 (no false positive)' {
        $names = @{ 'a' = 'Microsoft Visual C++ 2008 Redistributable - x86 9.0.30729.6161' }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2008.x86'] | Should -Be $true
        $cache.ContainsKey('Microsoft.VCRedist.2008.x64') | Should -Be $false
    }

    It 'excludes Minimum Runtime / Additional Runtime MSI sub-components' {
        $names = @{
            'a' = 'Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.36.32532'
            'b' = 'Microsoft Visual C++ 2015-2022 Additional Runtime - 14.36.32532'
            'c' = 'Microsoft Visual C++ 2015-2022 Debug Runtime - 14.36.32532'
        }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache.Keys.Count | Should -Be 0
    }

    It 'detects multiple runtimes from a mixed DisplayName list' {
        $names = @{
            'a' = 'Microsoft Visual C++ 2010  x86 Redistributable - 10.0.40219'
            'b' = 'Microsoft Visual C++ 2010  x64 Redistributable - 10.0.40219'
            'c' = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.36.32532.0'
            'd' = 'Mozilla Firefox 124.0'
        }
        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $cache['Microsoft.VCRedist.2010.x86'] | Should -Be $true
        $cache['Microsoft.VCRedist.2010.x64'] | Should -Be $true
        $cache['Microsoft.VCRedist.2015+.x64'] | Should -Be $true
        $cache.Keys.Count | Should -Be 3
    }

    It 'detects every VC++ runtime when the full catalog is installed' {
        $names = @{
            'vc2005x86' = 'Microsoft Visual C++ 2005 Redistributable (x86) - 8.0.61001'
            'vc2005x64' = 'Microsoft Visual C++ 2005 Redistributable (x64) - 8.0.61001'
            'vc2008x86' = 'Microsoft Visual C++ 2008 Redistributable - x86 9.0.30729.6161'
            'vc2008x64' = 'Microsoft Visual C++ 2008 Redistributable - x64 9.0.30729.6161'
            'vc2010x86' = 'Microsoft Visual C++ 2010  x86 Redistributable - 10.0.40219'
            'vc2010x64' = 'Microsoft Visual C++ 2010  x64 Redistributable - 10.0.40219'
            'vc2012x86' = 'Microsoft Visual C++ 2012 Redistributable (x86) - 11.0.61030'
            'vc2012x64' = 'Microsoft Visual C++ 2012 Redistributable (x64) - 11.0.61030'
            'vc2013x86' = 'Microsoft Visual C++ 2013 Redistributable (x86) - 12.0.40664'
            'vc2013x64' = 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664'
            'vc2015x86' = 'Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.36.32532.0'
            'vc2015x64' = 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.36.32532.0'
            'vc2015arm64' = 'Microsoft Visual C++ 2015-2022 Redistributable (arm64) - 14.36.32532.0'
        }

        $cache = Get-InstalledRuntimeRegistryCache -DisplayNameMap $names
        $map = Get-RuntimeRegistryDetectionMap

        $cache.Keys.Count | Should -Be $map.Count
        foreach ($entry in $map)
        {
            $cache[$entry.WinGetId] | Should -Be $true
        }
    }

    It 'skips empty / whitespace DisplayName entries without throwing' {
        $names = @{ 'a' = ''; 'b' = '   '; 'c' = $null }
        { Get-InstalledRuntimeRegistryCache -DisplayNameMap $names } | Should -Not -Throw
    }
}
