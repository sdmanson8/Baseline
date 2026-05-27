Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/PackageManagement.Helpers.ps1'
    $script:PackageManagementContent = Get-Content -LiteralPath $filePath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Assert-FileHash' {
    It 'returns the computed SHA-256 when the file matches the expected value' {
        $filePath = Join-Path $TestDrive 'sample.txt'
        Set-Content -LiteralPath $filePath -Value 'baseline' -Encoding ASCII
        $expectedHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToUpperInvariant()

        $result = Assert-FileHash -Path $filePath -ExpectedSha256 $expectedHash -Label 'Sample file'

        $result | Should -Be $expectedHash
    }

    It 'throws when the hash does not match' {
        $filePath = Join-Path $TestDrive 'sample.txt'
        Set-Content -LiteralPath $filePath -Value 'baseline' -Encoding ASCII

        { Assert-FileHash -Path $filePath -ExpectedSha256 ('0' * 64) -Label 'Sample file' } | Should -Throw '*SHA-256 verification*'
    }
}

Describe 'Resolve-PowerShellInstallerUri' {
    BeforeEach {
        Mock Set-DownloadSecurityProtocol {}
        Mock Get-PowerShellInstallerArchitecture { 'win-x64' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                assets = @(
                    [pscustomobject]@{ name = 'PowerShell-7.5.0-win-arm64.msi'; browser_download_url = 'https://example.test/arm64.msi' }
                    [pscustomobject]@{ name = 'PowerShell-7.5.0-win-x64.msi'; browser_download_url = 'https://example.test/x64.msi' }
                )
            }
        }
    }

    It 'selects the MSI that matches the resolved architecture' {
        $result = Resolve-PowerShellInstallerUri -ReleaseApiUri 'https://example.test/latest'

        $result | Should -Be 'https://example.test/x64.msi'
    }

    It 'throws when no matching MSI asset exists' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                assets = @(
                    [pscustomobject]@{ name = 'PowerShell-7.5.0-linux-x64.tar.gz'; browser_download_url = 'https://example.test/linux.tar.gz' }
                )
            }
        }

        { Resolve-PowerShellInstallerUri -ReleaseApiUri 'https://example.test/latest' } | Should -Throw '*Could not find a PowerShell MSI installer*'
    }
}

Describe 'Resolve-ChocolateyExecutable' {
    It 'returns the known Chocolatey install path when PATH resolution is stale' {
        $previousProgramData = $env:ProgramData
        $previousChocolateyInstall = $env:ChocolateyInstall
        try {
            $env:ProgramData = Join-Path $TestDrive 'ProgramData'
            $env:ChocolateyInstall = $null
            $expectedPath = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $expectedPath -Parent) -Force
            Set-Content -LiteralPath $expectedPath -Value '' -Encoding ASCII

            Mock Update-ProcessPathFromRegistry {}
            Mock Get-Command { $null } -ParameterFilter {
                @($Name) -contains 'choco' -or @($Name) -contains 'choco.exe'
            }

            $result = Resolve-ChocolateyExecutable

            $result | Should -Be $expectedPath
        }
        finally {
            $env:ProgramData = $previousProgramData
            $env:ChocolateyInstall = $previousChocolateyInstall
        }
    }
}

Describe 'Chocolatey bootstrap download and integrity' {
    BeforeEach {
        $script:previousChocolateyHash = $env:BASELINE_CHOCOLATEY_INSTALLER_SHA256
        $script:previousTemp = $env:TEMP
        $script:chocolateyBootstrapInfoScopes = [System.Collections.Generic.List[string]]::new()
        $script:chocolateyBootstrapWarningScopes = [System.Collections.Generic.List[string]]::new()
        $script:chocolateyBootstrapErrorScopes = [System.Collections.Generic.List[string]]::new()
        Remove-Item Env:\BASELINE_CHOCOLATEY_INSTALLER_SHA256 -ErrorAction SilentlyContinue
        $env:TEMP = $TestDrive

        function Get-BaselineBilingualString {
            param(
                [string]$Key,
                [string]$Fallback,
                [object[]]$FormatArgs = @()
            )

            if ($FormatArgs.Count -gt 0) { return ($Fallback -f $FormatArgs) }
            return $Fallback
        }

        function LogInfo {
            param([string]$Message, [string]$Scope)
            [void]$script:chocolateyBootstrapInfoScopes.Add($Scope)
        }
        function LogWarning {
            param([string]$Message, [string]$Scope)
            [void]$script:chocolateyBootstrapWarningScopes.Add($Scope)
        }
        function LogError {
            param([string]$Message, [string]$Scope)
            [void]$script:chocolateyBootstrapErrorScopes.Add($Scope)
        }

        Mock Test-ChocolateyBootstrapInteractiveHost { $false }
        Mock Get-ChocolateyVersion { $null }
        Mock Invoke-DownloadFile {
            param($Uri, $OutFile)
            Set-Content -LiteralPath $OutFile -Value 'installer' -Encoding ASCII
        }
        Mock Assert-FileHash { 'OK' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Wait-PackageManagerProcess { 0 }
        Mock Get-PackageManagerBootstrapLogLines { @() }
        Mock Start-Sleep {}
        Mock Reset-ChocolateyAvailabilityState {}
    }

    AfterEach {
        if ($null -eq $script:previousChocolateyHash) { Remove-Item Env:\BASELINE_CHOCOLATEY_INSTALLER_SHA256 -ErrorAction SilentlyContinue } else { $env:BASELINE_CHOCOLATEY_INSTALLER_SHA256 = $script:previousChocolateyHash }
        $env:TEMP = $script:previousTemp
        Remove-Item Function:\Get-BaselineBilingualString -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
    }

    It 'downloads and executes Chocolatey without an environment gate or pinned hash' {
        $result = Invoke-ChocolateyBootstrap

        $result.Success | Should -BeTrue
        $result.Error | Should -BeNullOrEmpty

        Should -Invoke Invoke-DownloadFile -Times 1
        Should -Invoke Assert-FileHash -Times 0
        Should -Invoke Start-Process -Times 1
        @($script:chocolateyBootstrapInfoScopes.ToArray() | Where-Object { $_ -ne 'Chocolatey' }) | Should -BeNullOrEmpty
        @($script:chocolateyBootstrapWarningScopes.ToArray() | Where-Object { $_ -and $_ -ne 'Chocolatey' }) | Should -BeNullOrEmpty
        @($script:chocolateyBootstrapErrorScopes.ToArray() | Where-Object { $_ -and $_ -ne 'Chocolatey' }) | Should -BeNullOrEmpty
    }

    It 'uses the Chocolatey scope for already-installed startup status logs' {
        Mock Get-ChocolateyVersion { '2.7.2' }

        $result = Invoke-ChocolateyBootstrap

        $result.Success | Should -BeTrue
        $script:chocolateyBootstrapInfoScopes[0] | Should -Be 'Chocolatey'
        @($script:chocolateyBootstrapInfoScopes.ToArray() | Where-Object { $_ -eq 'Checking installation status...' }) | Should -BeNullOrEmpty
    }

    It 'does not require a pinned hash before executing the Chocolatey installer' {
        $result = Invoke-ChocolateyBootstrap

        $result.Success | Should -BeTrue

        Should -Invoke Invoke-DownloadFile -Times 1
        Should -Invoke Assert-FileHash -Times 0
        Should -Invoke Start-Process -Times 1
    }

    It 'verifies the pinned hash before executing the Chocolatey installer' {
        $env:BASELINE_CHOCOLATEY_INSTALLER_SHA256 = ('A' * 64)
        $script:chocolateyVersionProbeCount = 0
        Mock Get-ChocolateyVersion {
            $script:chocolateyVersionProbeCount++
            if ($script:chocolateyVersionProbeCount -eq 1) { return $null }
            return '2.2.2'
        }

        $result = Invoke-ChocolateyBootstrap -TimeoutSeconds 77

        $result.Success | Should -BeTrue
        $result.Available | Should -BeTrue
        Should -Invoke Assert-FileHash -Times 1 -ParameterFilter {
            $ExpectedSha256 -eq ('A' * 64) -and $Label -eq 'Chocolatey install.ps1'
        }
        Should -Invoke Start-Process -Times 1
        Should -Invoke Wait-PackageManagerProcess -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 77
        }
    }
}

Describe 'Get-WinGetBootstrapInstallerMetadata' {
    It 'returns the reviewed 5.3.6 WinGet bootstrap metadata' {
        $metadata = Get-WinGetBootstrapInstallerMetadata

        $metadata.Version | Should -Be '5.3.6'
        $metadata.Sha256 | Should -Be '6016097051EBD3385F4E315FE33B17CEDA6912B9E71CD0C60C1D0DF1823D3262'
        $metadata.Uri | Should -Match '^https://github\.com/.+/releases/download/5\.3\.6/.+\.ps1$'
        $metadata.Label | Should -Be 'Baseline WinGet bootstrap v5.3.6'
    }
}

Describe 'Get-WinGetBootstrapInstallerArguments' {
    It 'keeps the installer in charge of Server-specific method selection' {
        $arguments = @(Get-WinGetBootstrapInstallerArguments)

        $arguments | Should -Be @('-Force')
    }
}

Describe 'Get-WinGetVersion' {
    It 'uses the bounded process capture helper with the supplied timeout' {
        Mock Resolve-WinGetExecutable { 'winget.exe' }
        Mock Invoke-PackageManagerProcessCapture {
            [pscustomobject]@{
                ExitCode = 0
                StandardOutput = "v1.9.0`r`n"
                StandardError = ''
            }
        }

        $version = Get-WinGetVersion -TimeoutSeconds 17

        $version | Should -Be 'v1.9.0'
        Should -Invoke Invoke-PackageManagerProcessCapture -Times 1 -ParameterFilter {
            $FilePath -eq 'winget.exe' -and $TimeoutSeconds -eq 17
        }
    }
}

Describe 'Invoke-WinGetBootstrap' {
    BeforeEach {
        $script:wingetBootstrapInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:wingetBootstrapWarningMessages = [System.Collections.Generic.List[string]]::new()
        $script:wingetBootstrapErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:wingetBootstrapInfoScopes = [System.Collections.Generic.List[string]]::new()
        $script:wingetBootstrapWarningScopes = [System.Collections.Generic.List[string]]::new()
        $script:wingetBootstrapErrorScopes = [System.Collections.Generic.List[string]]::new()
        $script:wingetVersionCallCount = 0
        $script:capturedWinGetInstallerArgumentList = $null
        $script:previousTemp = $env:TEMP
        $env:TEMP = $TestDrive

        function Get-BaselineBilingualString {
            param(
                [string]$Key,
                [string]$Fallback,
                [object[]]$FormatArgs = @()
            )

            if ($FormatArgs.Count -gt 0) {
                return ($Fallback -f $FormatArgs)
            }

            return $Fallback
        }

        function LogInfo {
            param([string]$Message, [string]$Scope)
            [void]$script:wingetBootstrapInfoMessages.Add($Message)
            [void]$script:wingetBootstrapInfoScopes.Add($Scope)
        }

        function LogWarning {
            param([string]$Message, [string]$Scope)
            [void]$script:wingetBootstrapWarningMessages.Add($Message)
            [void]$script:wingetBootstrapWarningScopes.Add($Scope)
        }

        function LogError {
            param([string]$Message, [string]$Scope)
            [void]$script:wingetBootstrapErrorMessages.Add($Message)
            [void]$script:wingetBootstrapErrorScopes.Add($Scope)
        }

        function Repair-WinGetPackageManager { }
    }

    AfterEach {
        $env:TEMP = $script:previousTemp
        Remove-Item Function:\Get-BaselineBilingualString -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Repair-WinGetPackageManager -ErrorAction SilentlyContinue
    }

    It 'uses the Winget scope for already-installed startup status logs' {
        Mock Get-WinGetVersion { 'v1.28.240' }

        $result = Invoke-WinGetBootstrap

        $result.Success | Should -BeTrue
        $script:wingetBootstrapInfoMessages[0] | Should -Be 'WinGet is already installed and working. Version: v1.28.240'
        $script:wingetBootstrapInfoScopes[0] | Should -Be 'Winget'
        @($script:wingetBootstrapInfoScopes.ToArray() | Where-Object { $_ -eq 'Checking installation status...' }) | Should -BeNullOrEmpty
    }

    It 'does not accept a zero exit code as success when stderr reported errors and winget is still unavailable' {
        Mock Invoke-DownloadFile {
            param($Uri, $OutFile)
            Set-Content -LiteralPath $OutFile -Value 'installer' -Encoding ASCII
        }
        Mock Assert-FileHash { 'OK' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-PackageManagerBootstrapLogLines {
            param($Path)
            if ([string]$Path -like '*stderr*') {
                return @('Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF1')
            }

            return @('Baseline WinGet bootstrap completed')
        }
        Mock Get-WinGetVersion {
            $script:wingetVersionCallCount++
            return $null
        }
        Mock Wait-PackageManagerProcess { 0 }
        Mock Start-Sleep {}
        Mock Set-PSRepository { throw 'repair path hit' }
        Mock Install-PackageProvider {}
        Mock Install-Module {}
        Mock Import-Module {}
        Mock Repair-WinGetPackageManager {}
        Mock Reset-WinGetAvailabilityState {}

        $result = Invoke-WinGetBootstrap

        $result.Success | Should -BeFalse
        ($script:wingetBootstrapWarningMessages -join "`n") | Should -Match 'reported errors despite a zero exit code'
        ($script:wingetBootstrapErrorMessages -join "`n") | Should -Match 'winget\.exe is still unavailable\. First error: Add-AppxPackage'
    }

    It 'treats a clean installer with no stderr as success even if winget needs a new session' {
        Mock Invoke-DownloadFile {
            param($Uri, $OutFile)
            Set-Content -LiteralPath $OutFile -Value 'installer' -Encoding ASCII
        }
        Mock Assert-FileHash { 'OK' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-PackageManagerBootstrapLogLines {
            param($Path)
            if ([string]$Path -like '*stderr*') {
                return @()
            }

            return @('Baseline WinGet bootstrap completed')
        }
        Mock Get-WinGetVersion {
            $script:wingetVersionCallCount++
            return $null
        }
        Mock Wait-PackageManagerProcess { 0 }
        Mock Start-Sleep {}
        Mock Reset-WinGetAvailabilityState {}

        $result = Invoke-WinGetBootstrap

        $result.Success | Should -BeTrue
        $result.Installed | Should -BeTrue
        $result.Available | Should -BeFalse
        ($script:wingetBootstrapWarningMessages -join "`n") | Should -Match 'installation completed, but winget\.exe is not available in the current session yet'
    }

    It 'passes only the generic installer switch so Server 2019 and 2022 stay on the Baseline-defined paths' {
        Mock Invoke-DownloadFile {
            param($Uri, $OutFile)
            Set-Content -LiteralPath $OutFile -Value 'installer' -Encoding ASCII
        }
        Mock Assert-FileHash { 'OK' }
        Mock Start-Process {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList
            )

            $script:capturedWinGetInstallerArgumentList = @($ArgumentList)
            [pscustomobject]@{ ExitCode = 0 }
        }
        Mock Get-PackageManagerBootstrapLogLines { @() }
        Mock Get-WinGetVersion {
            $script:wingetVersionCallCount++
            if ($script:wingetVersionCallCount -eq 1) {
                return $null
            }

            return '1.0.0'
        }
        Mock Start-Sleep {}
        Mock Reset-WinGetAvailabilityState {}

        $null = Invoke-WinGetBootstrap

        ($script:capturedWinGetInstallerArgumentList -join ' ') | Should -Match '-Force'
        ($script:capturedWinGetInstallerArgumentList -join ' ') | Should -Not -Match 'AlternateInstallMethod'
    }

    It 'waits for the installer process with the supplied timeout' {
        Mock Invoke-DownloadFile {
            param($Uri, $OutFile)
            Set-Content -LiteralPath $OutFile -Value 'installer' -Encoding ASCII
        }
        Mock Assert-FileHash { 'OK' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0; StartInfo = [pscustomobject]@{ FileName = 'powershell.exe' } } }
        Mock Wait-PackageManagerProcess { 0 }
        Mock Get-PackageManagerBootstrapLogLines { @() }
        Mock Get-WinGetVersion {
            $script:wingetVersionCallCount++
            if ($script:wingetVersionCallCount -eq 1) { return $null }
            return '1.0.0'
        }
        Mock Start-Sleep {}
        Mock Reset-WinGetAvailabilityState {}

        $null = Invoke-WinGetBootstrap -TimeoutSeconds 321

        Should -Invoke Wait-PackageManagerProcess -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 321
        }
    }
}
