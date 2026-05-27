Set-StrictMode -Version Latest

BeforeAll {
    $registryHelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Registry.Helpers.ps1'
    . $registryHelperPath

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Wsl.Helpers.ps1'
    . $filePath

    $script:sandboxBase = "HKCU:\Software\Baseline_Wsl_Tests_$([guid]::NewGuid().ToString('N'))"
    if (Test-Path -LiteralPath $script:sandboxBase)
    {
        Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $script:sandboxBase -Force | Out-Null

    $script:sampleCatalogJson = @'
{
  "Default": "Ubuntu",
  "Distributions": [
    { "Name": "Ubuntu",     "FriendlyName": "Ubuntu" },
    { "Name": "Debian",     "FriendlyName": "Debian GNU/Linux" },
    { "Name": "kali-linux", "FriendlyName": "Kali Linux Rolling" },
    { "Name": "OracleLinux_8_7", "FriendlyName": "Oracle Linux 8.7" }
  ]
}
'@
}

AfterAll {
    if (Test-Path -LiteralPath $script:sandboxBase)
    {
        Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath Env:BASELINE_WSL_CATALOG_URL -ErrorAction SilentlyContinue
}

Describe 'Get-BaselineWslDistributionCatalogUrl' {
    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_WSL_CATALOG_URL -ErrorAction SilentlyContinue
    }

    It 'returns an empty string by default' {
        Get-BaselineWslDistributionCatalogUrl | Should -Be ''
    }

    It 'honours BASELINE_WSL_CATALOG_URL override' {
        $env:BASELINE_WSL_CATALOG_URL = 'file:///C:/fixtures/wsl.json'
        Get-BaselineWslDistributionCatalogUrl | Should -Be 'file:///C:/fixtures/wsl.json'
    }

    It 'ignores blank override' {
        $env:BASELINE_WSL_CATALOG_URL = '   '
        Get-BaselineWslDistributionCatalogUrl | Should -Be ''
    }
}

Describe 'ConvertFrom-BaselineWslDistributionCatalogJson' {
    It 'projects every distro into {Distribution, Alias}' {
        $records = ConvertFrom-BaselineWslDistributionCatalogJson -RawJson $script:sampleCatalogJson
        $records.Count | Should -Be 4
        ($records | ForEach-Object { $_.Alias }) | Should -Contain 'Ubuntu'
        ($records | ForEach-Object { $_.Alias }) | Should -Contain 'Debian'
        ($records | ForEach-Object { $_.Alias }) | Should -Contain 'kali-linux'
    }

    It 'sorts results by friendly name for stable picker order' {
        $records = ConvertFrom-BaselineWslDistributionCatalogJson -RawJson $script:sampleCatalogJson
        $names = @($records | ForEach-Object { $_.Distribution })
        $sorted = @($names | Sort-Object)
        ($names -join '|') | Should -Be ($sorted -join '|')
    }

    It 'falls back to Alias when FriendlyName is missing' {
        $json = @'
{ "Distributions": [ { "Name": "AlpineEdge" } ] }
'@
        $records = @(ConvertFrom-BaselineWslDistributionCatalogJson -RawJson $json)
        $records.Count | Should -Be 1
        $records[0].Distribution | Should -Be 'AlpineEdge'
        $records[0].Alias | Should -Be 'AlpineEdge'
    }

    It 'skips entries with no Name' {
        $json = @'
{ "Distributions": [ { "FriendlyName": "Orphan" }, { "Name": "Real", "FriendlyName": "Real" } ] }
'@
        $records = @(ConvertFrom-BaselineWslDistributionCatalogJson -RawJson $json)
        $records.Count | Should -Be 1
        $records[0].Alias | Should -Be 'Real'
    }

    It 'returns an empty array for empty input' {
        $records = @(ConvertFrom-BaselineWslDistributionCatalogJson -RawJson '')
        $records.Count | Should -Be 0
    }

    It 'returns an empty array for malformed JSON instead of throwing' {
        $records = @(ConvertFrom-BaselineWslDistributionCatalogJson -RawJson '{not json')
        $records.Count | Should -Be 0
    }

    It 'returns an empty array when Distributions is missing' {
        $records = @(ConvertFrom-BaselineWslDistributionCatalogJson -RawJson '{"Default":"Ubuntu"}')
        $records.Count | Should -Be 0
    }
}

Describe 'Get-BaselineWslDistributionCatalog' {
    It 'invokes the supplied fetcher and projects the JSON' {
        $captured = $null
        $records = Get-BaselineWslDistributionCatalog -Url 'https://example.test/wsl.json' -Fetcher {
            param($u)
            $script:capturedUrl = $u
            return $script:sampleCatalogJson
        }
        $script:capturedUrl | Should -Be 'https://example.test/wsl.json'
        $records.Count | Should -Be 4
    }

    It 'returns @() when -Url is omitted and no catalog is configured' {
        Remove-Item -LiteralPath Env:BASELINE_WSL_CATALOG_URL -ErrorAction SilentlyContinue
        $records = Get-BaselineWslDistributionCatalog -Fetcher {
            param($u)
            $script:capturedUrl2 = $u
            return $script:sampleCatalogJson
        }
        $script:capturedUrl2 | Should -BeNullOrEmpty
        $records.Count | Should -Be 0
    }

    It 'returns @() when the fetcher throws' {
        $records = @(Get-BaselineWslDistributionCatalog -Fetcher { throw 'network down' })
        $records.Count | Should -Be 0
    }
}

Describe 'Test-BaselineWslPrerequisite' {
    It 'reports Supported=$true for Windows 11 build' {
        $info = [pscustomobject]@{ BuildNumber = 22631; ProductType = 1; IsServer = $false }
        $r = Test-BaselineWslPrerequisite -PlatformInfo $info
        $r.Supported | Should -BeTrue
        $r.BuildNumber | Should -Be 22631
        $r.Reason | Should -BeNullOrEmpty
    }

    It 'reports Supported=$true for Windows 10 2004 (build 19041)' {
        $info = [pscustomobject]@{ BuildNumber = 19041; ProductType = 1; IsServer = $false }
        (Test-BaselineWslPrerequisite -PlatformInfo $info).Supported | Should -BeTrue
    }

    It 'reports Supported=$false for Windows 10 1909 (build 18363)' {
        $info = [pscustomobject]@{ BuildNumber = 18363; ProductType = 1; IsServer = $false }
        $r = Test-BaselineWslPrerequisite -PlatformInfo $info
        $r.Supported | Should -BeFalse
        $r.Reason | Should -Match '19041'
    }

    It 'reports ProductType from IsServer fallback when ProductType absent' {
        $info = [pscustomobject]@{ BuildNumber = 22631; IsServer = $true }
        $r = Test-BaselineWslPrerequisite -PlatformInfo $info
        $r.ProductType | Should -Be 3
    }
}

Describe 'Get-BaselineWslInstallationState' {
    It 'reports Installed=$false when wsl.exe is absent' {
        $r = Get-BaselineWslInstallationState -WslExePath (Join-Path $env:TEMP "missing-wsl-$([guid]::NewGuid()).exe")
        $r.Installed | Should -BeFalse
        $r.InstalledDistributions.Count | Should -Be 0
    }

    It 'parses the wsl --list output into the distro array' {
        $fakeWsl = Join-Path $env:TEMP "fake-wsl-$([guid]::NewGuid()).exe"
        Set-Content -LiteralPath $fakeWsl -Value 'placeholder' -Encoding ascii
        try
        {
            $r = Get-BaselineWslInstallationState -WslExePath $fakeWsl -ListInvoker {
                param($p)
                return "Ubuntu`r`nDebian`r`nkali-linux`r`n"
            }
            $r.Installed | Should -BeTrue
            $r.Path | Should -Be $fakeWsl
            $r.InstalledDistributions.Count | Should -Be 3
            $r.InstalledDistributions | Should -Contain 'Ubuntu'
            $r.InstalledDistributions | Should -Contain 'Debian'
            $r.InstalledDistributions | Should -Contain 'kali-linux'
        }
        finally
        {
            Remove-Item -LiteralPath $fakeWsl -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns an empty distros array when the listing is blank' {
        $fakeWsl = Join-Path $env:TEMP "fake-wsl-$([guid]::NewGuid()).exe"
        Set-Content -LiteralPath $fakeWsl -Value 'placeholder' -Encoding ascii
        try
        {
            $r = Get-BaselineWslInstallationState -WslExePath $fakeWsl -ListInvoker { return '' }
            $r.Installed | Should -BeTrue
            $r.InstalledDistributions.Count | Should -Be 0
        }
        finally
        {
            Remove-Item -LiteralPath $fakeWsl -Force -ErrorAction SilentlyContinue
        }
    }

    It 'tolerates ListInvoker throwing' {
        $fakeWsl = Join-Path $env:TEMP "fake-wsl-$([guid]::NewGuid()).exe"
        Set-Content -LiteralPath $fakeWsl -Value 'placeholder' -Encoding ascii
        try
        {
            $r = Get-BaselineWslInstallationState -WslExePath $fakeWsl -ListInvoker { throw 'permission denied' }
            $r.Installed | Should -BeTrue
            $r.InstalledDistributions.Count | Should -Be 0
        }
        finally
        {
            Remove-Item -LiteralPath $fakeWsl -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Install-BaselineWslDistribution' {
    BeforeAll {
        $script:fakeWsl = Join-Path $env:TEMP "fake-wsl-install-$([guid]::NewGuid()).exe"
        Set-Content -LiteralPath $script:fakeWsl -Value 'placeholder' -Encoding ascii
    }
    AfterAll {
        Remove-Item -LiteralPath $script:fakeWsl -Force -ErrorAction SilentlyContinue
    }

    It 'invokes wsl.exe with --install --distribution <Alias>' {
        $captured = $null
        $r = Install-BaselineWslDistribution -Alias 'Ubuntu' -WslExePath $script:fakeWsl -StartProcessInvoker {
            param($file, $argList)
            $script:capturedFile = $file
            $script:capturedArgs = $argList
            return 0
        }
        $r.Started | Should -BeTrue
        $r.ExitCode | Should -Be 0
        $r.Alias | Should -Be 'Ubuntu'
        $script:capturedFile | Should -Be $script:fakeWsl
        ($script:capturedArgs -join ' ') | Should -Be '--install --distribution Ubuntu'
    }

    It 'rejects an alias not present in the supplied catalog' {
        $catalog = @(
            [pscustomobject]@{ Distribution = 'Ubuntu'; Alias = 'Ubuntu' }
            [pscustomobject]@{ Distribution = 'Debian'; Alias = 'Debian' }
        )
        $r = Install-BaselineWslDistribution -Alias 'Bogus' -Catalog $catalog -WslExePath $script:fakeWsl -StartProcessInvoker {
            throw 'should never run'
        }
        $r.Started | Should -BeFalse
        $r.Reason | Should -Match "'Bogus'"
    }

    It 'returns Started=$false when wsl.exe is absent' {
        $r = Install-BaselineWslDistribution -Alias 'Ubuntu' -WslExePath (Join-Path $env:TEMP "missing-$([guid]::NewGuid()).exe") -StartProcessInvoker {
            throw 'should never run'
        }
        $r.Started | Should -BeFalse
        $r.Reason | Should -Match 'wsl.exe is not available'
    }

    It 'honours -WhatIf and never invokes the StartProcessInvoker' {
        $r = Install-BaselineWslDistribution -Alias 'Ubuntu' -WslExePath $script:fakeWsl -StartProcessInvoker {
            throw 'should never run under WhatIf'
        } -WhatIf
        $r.Started | Should -BeFalse
        $r.Reason | Should -Be 'WhatIf'
        $r.StartInfo.FilePath | Should -Be $script:fakeWsl
    }

    It 'captures the StartProcessInvoker exit code' {
        $r = Install-BaselineWslDistribution -Alias 'kali-linux' -WslExePath $script:fakeWsl -StartProcessInvoker {
            return 5
        }
        $r.Started | Should -BeTrue
        $r.ExitCode | Should -Be 5
    }

    It 'captures the StartProcessInvoker exception in Reason' {
        $r = Install-BaselineWslDistribution -Alias 'Ubuntu' -WslExePath $script:fakeWsl -StartProcessInvoker {
            throw 'simulated UAC denied'
        }
        $r.Started | Should -BeFalse
        $r.Reason | Should -Match 'simulated UAC denied'
    }
}

Describe 'Enable-BaselineMicrosoftUpdateDelivery' {
    BeforeEach {
        # Override Set-RegistryValueSafe and Test-Path/Get-ItemProperty/Set-ItemProperty
        # so the helper writes into our HKCU sandbox instead of HKLM.
        $script:sandboxPath = "$script:sandboxBase\WindowsUpdate\UX\Settings"
        if (Test-Path -LiteralPath $script:sandboxPath)
        {
            Remove-Item -LiteralPath $script:sandboxPath -Recurse -Force
        }
    }

    It 'writes AllowMUUpdateService=1 (DWord) when invoked' {
        Mock -CommandName Set-RegistryValueSafe -MockWith {
            param($Path, $Name, $Type, $Value)
            $script:capturedSetCall = [pscustomobject]@{ Path = $Path; Name = $Name; Type = $Type; Value = $Value }
        } -Verifiable

        $r = Enable-BaselineMicrosoftUpdateDelivery
        $r.Applied | Should -BeTrue
        $r.Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $r.Name | Should -Be 'AllowMUUpdateService'
        $script:capturedSetCall.Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $script:capturedSetCall.Name | Should -Be 'AllowMUUpdateService'
        [string]$script:capturedSetCall.Type | Should -Be 'DWord'
        [int]$script:capturedSetCall.Value | Should -Be 1
    }

    It 'honours -WhatIf and does not call Set-RegistryValueSafe' {
        Mock -CommandName Set-RegistryValueSafe -MockWith {
            throw 'should never run under WhatIf'
        }
        $r = Enable-BaselineMicrosoftUpdateDelivery -WhatIf
        $r.Applied | Should -BeFalse
        Should -Invoke -CommandName Set-RegistryValueSafe -Times 0 -Exactly
    }
}

Describe 'Invoke-BaselineWindowsUpdateScan' {
    BeforeAll {
        $script:fakeUso = Join-Path $env:TEMP "fake-uso-$([guid]::NewGuid()).exe"
        Set-Content -LiteralPath $script:fakeUso -Value 'placeholder' -Encoding ascii
    }
    AfterAll {
        Remove-Item -LiteralPath $script:fakeUso -Force -ErrorAction SilentlyContinue
    }

    It 'invokes UsoClient.exe StartInteractiveScan' {
        $r = Invoke-BaselineWindowsUpdateScan -UsoClientPath $script:fakeUso -StartProcessInvoker {
            param($file, $argList)
            $script:capturedUsoFile = $file
            $script:capturedUsoArgs = $argList
            return 0
        }
        $r.Started | Should -BeTrue
        $r.ExitCode | Should -Be 0
        $script:capturedUsoFile | Should -Be $script:fakeUso
        ($script:capturedUsoArgs -join ' ') | Should -Be 'StartInteractiveScan'
    }

    It 'reports Started=$false when UsoClient.exe is absent' {
        $r = Invoke-BaselineWindowsUpdateScan -UsoClientPath (Join-Path $env:TEMP "missing-uso-$([guid]::NewGuid()).exe")
        $r.Started | Should -BeFalse
        $r.Reason | Should -Match 'not present'
    }

    It 'honours -WhatIf' {
        $r = Invoke-BaselineWindowsUpdateScan -UsoClientPath $script:fakeUso -StartProcessInvoker {
            throw 'should never run under WhatIf'
        } -WhatIf
        $r.Started | Should -BeFalse
        $r.Reason | Should -Be 'WhatIf'
    }
}

Describe 'Invoke-BaselineWslInstallFlow' {
    It 'returns prerequisite failure without calling later steps' {
        Mock -CommandName Test-BaselineWslPrerequisite -MockWith {
            [pscustomobject]@{
                Supported  = $false
                Reason     = 'Windows build is too old.'
                BuildNumber = 18363
            }
        }
        Mock -CommandName Install-BaselineWslDistribution -MockWith { throw 'should not be called' }
        Mock -CommandName Enable-BaselineMicrosoftUpdateDelivery -MockWith { throw 'should not be called' }
        Mock -CommandName Invoke-BaselineWindowsUpdateScan -MockWith { throw 'should not be called' }

        $r = Invoke-BaselineWslInstallFlow -Alias 'Ubuntu'
        $r.Succeeded | Should -BeFalse
        $r.Stage | Should -Be 'Prerequisite'
        $r.Reason | Should -Be 'Windows build is too old.'
        Should -Invoke -CommandName Install-BaselineWslDistribution -Times 0 -Exactly
        Should -Invoke -CommandName Enable-BaselineMicrosoftUpdateDelivery -Times 0 -Exactly
        Should -Invoke -CommandName Invoke-BaselineWindowsUpdateScan -Times 0 -Exactly
    }

    It 'runs the install, update delivery, and scan steps when prerequisites pass' {
        $script:wslFlowStepOrder = @()
        Mock -CommandName Test-BaselineWslPrerequisite -MockWith {
            $script:wslFlowStepOrder += 'prereq'
            [pscustomobject]@{ Supported = $true }
        }
        Mock -CommandName Install-BaselineWslDistribution -MockWith {
            param($Alias)
            $script:wslFlowStepOrder += "install:$Alias"
            [pscustomobject]@{
                Started  = $true
                ExitCode = 0
                Reason   = $null
            }
        }
        Mock -CommandName Enable-BaselineMicrosoftUpdateDelivery -MockWith {
            $script:wslFlowStepOrder += 'mu'
            [pscustomobject]@{ Applied = $true }
        }
        Mock -CommandName Invoke-BaselineWindowsUpdateScan -MockWith {
            $script:wslFlowStepOrder += 'scan'
            [pscustomobject]@{ Started = $true; Reason = $null }
        }

        $r = Invoke-BaselineWslInstallFlow -Alias 'Ubuntu'
        $r.Succeeded | Should -BeTrue
        $r.Stage | Should -Be 'Complete'
        $script:wslFlowStepOrder -join ',' | Should -Be 'prereq,install:Ubuntu,mu,scan'
    }
}
