# Shared helper slice for Baseline.

function Update-ProcessPathFromRegistry
{
	<# .SYNOPSIS Refreshes $env:Path from machine and user registry environment variables. #>
	$MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
	$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
	$env:Path = (@($MachinePath, $UserPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";"
}

function Write-PackageHelperWarning
{
	<# .SYNOPSIS Writes a warning via LogWarning or Write-Warning fallback. #>
	param([string]$Message)

	if ([string]::IsNullOrWhiteSpace($Message))
	{
		return
	}

	if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
	{
		LogWarning $Message
	}
	else
	{
		Write-Warning $Message
	}
}

function Resolve-WinGetExecutable
{
	<# .SYNOPSIS Resolves the winget.exe path from command lookup or known install locations. #>
	Update-ProcessPathFromRegistry

	$WingetCommand = Get-Command -Name winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source -ErrorAction SilentlyContinue
	if (-not [string]::IsNullOrWhiteSpace($WingetCommand))
	{
		return $WingetCommand
	}

	$CandidatePaths = @(
		(Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe")
		(Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\winget.exe")
	) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

	return ($CandidatePaths | Select-Object -First 1)
}

function Get-WinGetVersion
{
	<# .SYNOPSIS Returns the installed winget version string. #>
	$WingetPath = Resolve-WinGetExecutable
	if (-not $WingetPath)
	{
		return $null
	}

	try
	{
		$WingetVersion = & $WingetPath --version 2>$null
		if ($LASTEXITCODE -eq 0)
		{
			$ResolvedVersion = [string]($WingetVersion | Select-Object -First 1)
			if (-not [string]::IsNullOrWhiteSpace($ResolvedVersion))
			{
				return $ResolvedVersion.Trim()
			}
		}
	}
	catch
	{
		return $null
	}

	return $null
}

function Invoke-DownloadFile
{
	<# .SYNOPSIS Downloads a file with retry logic and WebClient fallback. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Uri,

		[Parameter(Mandatory = $true)]
		[string]
		$OutFile,

		[int]
		$MaxAttempts = 3
	)

	Set-DownloadSecurityProtocol

	$attemptErrors = [System.Collections.Generic.List[string]]::new()
	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
	{
		try
		{
			Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -UserAgent 'Baseline' -TimeoutSec 30 -ErrorAction Stop
			if (Test-Path -LiteralPath $OutFile)
			{
				return
			}
		}
		catch
		{
			$attemptErrors.Add("attempt ${attempt}: $($_.Exception.Message)")
			Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
			Start-Sleep -Seconds ([Math]::Min($attempt * 2, 5))
		}
	}

	$webClient = $null
	try
	{
		Set-DownloadSecurityProtocol
		$webClient = [System.Net.WebClient]::new()
		$webClient.Headers['User-Agent'] = 'Baseline'
		$webClient.DownloadFile($Uri, $OutFile)
		if (Test-Path -LiteralPath $OutFile)
		{
			return
		}
	}
	catch
	{
		$attemptErrors.Add("webclient fallback: $($_.Exception.Message)")
		Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
	}
	finally
	{
		if ($null -ne $webClient)
		{
			try
			{
				$webClient.Dispose()
			}
			catch
			{
				Write-PackageHelperWarning "Failed to dispose WebClient after download attempt: $($_.Exception.Message)"
			}
		}
	}

	throw ("Failed to download '{0}'. {1}" -f $Uri, ($attemptErrors -join ' | '))
}

function Set-DownloadSecurityProtocol
{
	<# .SYNOPSIS Enforces TLS 1.2 for downloads via SecurityProtocol. #>
	try
	{
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	}
	catch
	{
		Write-PackageHelperWarning "Could not enforce TLS 1.2 for download. Current protocol: $([Net.ServicePointManager]::SecurityProtocol)"
	}
}

function Assert-FileHash
{
	<# .SYNOPSIS Verifies a file's SHA256 hash matches an expected value. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$ExpectedSha256,

		[string]$Label = 'Downloaded file'
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		throw "$Label was not found: $Path"
	}

	$expected = $ExpectedSha256.Trim().ToUpperInvariant()
	$actual = $null
	if (Get-Command -Name 'Get-FileHash' -ErrorAction SilentlyContinue)
	{
		$actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
	}
	else
	{
		$stream = [System.IO.File]::OpenRead($Path)
		try
		{
			$sha256 = [System.Security.Cryptography.SHA256]::Create()
			try
			{
				$hashBytes = $sha256.ComputeHash($stream)
			}
			finally
			{
				$sha256.Dispose()
			}
		}
		finally
		{
			$stream.Dispose()
		}

		$actual = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToUpperInvariant()
	}

	if ($actual -ne $expected)
	{
		throw "$Label failed SHA-256 verification. Expected $expected but received $actual."
	}

	return $actual
}

function Assert-AuthenticodeSignature
{
	<# .SYNOPSIS Verifies Authenticode signature on a file against allowed subjects. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[string[]]$AllowedSubjects = @('CN=Microsoft Corporation')
	)

	if (-not (Get-Command -Name 'Get-AuthenticodeSignature' -ErrorAction SilentlyContinue))
	{
		throw "Get-AuthenticodeSignature is not available to verify '$Path'."
	}

	$signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
	if ($signature.Status -ne 'Valid')
	{
		throw "Authenticode signature verification failed for '$Path' (status: $($signature.Status))."
	}

	if ($AllowedSubjects.Count -gt 0)
	{
		$subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
		$subjectMatched = $false
		foreach ($allowedSubject in @($AllowedSubjects))
		{
			if ([string]::IsNullOrWhiteSpace([string]$allowedSubject)) { continue }
			if ($subject -like "*$allowedSubject*")
			{
				$subjectMatched = $true
				break
			}
		}

		if (-not $subjectMatched)
		{
			throw "Authenticode signer for '$Path' was '$subject', which is not in the allowed subject list."
		}
	}

	return $signature
}

function Get-PowerShellInstallerArchitecture
{
	<# .SYNOPSIS Determines the PowerShell installer architecture for the current platform. #>
	if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')
	{
		return 'win-arm64'
	}

	if ([Environment]::Is64BitOperatingSystem)
	{
		return 'win-x64'
	}

	return 'win-x86'
}

function Resolve-PowerShellInstallerUri
{
	<# .SYNOPSIS Fetches the latest PowerShell release and resolves the installer URL. #>
	param (
		[string]$ReleaseApiUri = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
	)

	Set-DownloadSecurityProtocol
	$release = Invoke-RestMethod -Uri $ReleaseApiUri -Headers @{ 'User-Agent' = 'Baseline' } -TimeoutSec 30 -ErrorAction Stop
	$assetSuffix = Get-PowerShellInstallerArchitecture
	$assets = @($release.assets)
	if ($assets.Count -eq 0)
	{
		throw "PowerShell release metadata did not include any downloadable assets."
	}

	$installerAsset = $assets | Where-Object {
		$assetName = [string]$_.name
		$assetUrl = [string]$_.browser_download_url
		($assetName -match ("^PowerShell-.*-{0}\.msi$" -f [regex]::Escape($assetSuffix))) -and
		(-not [string]::IsNullOrWhiteSpace($assetUrl))
	} | Select-Object -First 1

	if (-not $installerAsset)
	{
		throw "Could not find a PowerShell MSI installer for architecture '$assetSuffix'."
	}

	return [string]$installerAsset.browser_download_url
}

function Get-OneDriveSetupPath
{
	<# .SYNOPSIS Locates OneDriveSetup.exe across system and ProgramFiles paths. #>
	$preferredPaths = @()

	if ([Environment]::Is64BitOperatingSystem)
	{
		$preferredPaths += Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'
		$preferredPaths += Join-Path $env:SystemRoot 'Sysnative\OneDriveSetup.exe'

		if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles))
		{
			$preferredPaths += Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDriveSetup.exe'
		}

		if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)}))
		{
			$preferredPaths += Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDriveSetup.exe'
			$preferredPaths += Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'
		}
	}
	else
	{
		$preferredPaths += Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'
	}

	$preferredPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function ConvertTo-NormalizedVersion
{
	<# .SYNOPSIS Parses and normalizes a version string to a System.Version object. #>
	param
	(
		[AllowNull()]
		[string]
		$Version
	)

	if ([string]::IsNullOrWhiteSpace($Version))
	{
		return $null
	}

	$Match = [regex]::Match($Version.Trim(), "\d+(?:\.\d+){1,3}")
	if (-not $Match.Success)
	{
		return $null
	}

	$Parts = $Match.Value.Split(".")
	while ($Parts.Count -lt 4)
	{
		$Parts += "0"
	}
	if ($Parts.Count -gt 4)
	{
		$Parts = $Parts[0..3]
	}

	try
	{
		return [System.Version]($Parts -join ".")
	}
	catch
	{
		return $null
	}
}

function Get-InstalledVCRedistVersion
{
	<# .SYNOPSIS Retrieves the Visual C++ Redistributable version from registry. #>
	param
	(
		[ValidateSet("x86", "x64")]
		[string]
		$Architecture
	)

	$RegistryPaths = @(
		"HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$Architecture",
		"HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$Architecture"
	)

	foreach ($RegistryPath in $RegistryPaths)
	{
		try
		{
			$Runtime = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
		}
		catch
		{
			continue
		}

		if ($Runtime.Installed -eq 1)
		{
			return ConvertTo-NormalizedVersion -Version $Runtime.Version
		}
	}

	return $null
}

function Get-InstalledDotNetRuntimeVersion
{
	<# .SYNOPSIS Retrieves the installed .NET Runtime version by major version. #>
	param
	(
		[ValidateRange(1, 99)]
		[int]
		$MajorVersion
	)

	$RegistryPaths = @(
		"HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App",
		"HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
		"HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App",
		"HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"
	)

	$InstalledVersions = foreach ($RegistryPath in $RegistryPaths)
	{
		if (-not (Test-Path -Path $RegistryPath))
		{
			continue
		}

		Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
			ConvertTo-NormalizedVersion -Version $_.PSChildName
		}
	}

	$InstalledVersions = $InstalledVersions |
		Where-Object -FilterScript {$null -ne $_ -and $_.Major -eq $MajorVersion} |
		Sort-Object -Descending -Unique

	if ($InstalledVersions)
	{
		return $InstalledVersions[0]
	}

	return $null
}

function Get-LatestDotNetRuntimeRelease
{
	<# .SYNOPSIS Fetches the latest .NET Runtime release metadata from Microsoft. #>
	param
	(
		[ValidateRange(1, 99)]
		[int]
		$MajorVersion
	)

	$ReleaseMetadataUri = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$MajorVersion.0/releases.json"
	$ReleaseMetadata = Invoke-RestMethod -Uri $ReleaseMetadataUri -UseBasicParsing -TimeoutSec 30
	$LatestReleaseVersion = [string]$ReleaseMetadata."latest-release"
	$Release = $null

	if (-not [string]::IsNullOrWhiteSpace($LatestReleaseVersion))
	{
		$Release = $ReleaseMetadata.releases | Where-Object -FilterScript {$_."release-version" -eq $LatestReleaseVersion} | Select-Object -First 1
	}

	if ($null -eq $Release)
	{
		$Release = $ReleaseMetadata.releases | Select-Object -First 1
	}

	if ($null -eq $Release -or $null -eq $Release.runtime)
	{
		return $null
	}

	$RuntimeFile = $Release.runtime.files | Where-Object -FilterScript {$_.name -eq "dotnet-runtime-win-x64.exe"} | Select-Object -First 1
	$DownloadUrl = [string]$RuntimeFile.url

	if ([string]::IsNullOrWhiteSpace($DownloadUrl))
	{
		return $null
	}

	$DownloadUri = [uri]$DownloadUrl

	[pscustomobject]@{
		Version     = ConvertTo-NormalizedVersion -Version $Release.runtime.version
		DownloadUrl = $DownloadUrl
		FileName    = [System.IO.Path]::GetFileName($DownloadUri.AbsolutePath)
		SourceHost  = $DownloadUri.GetLeftPart([System.UriPartial]::Authority)
		MetadataUri = $ReleaseMetadataUri
	}
}

function Install-VCRedist
{
	<# .SYNOPSIS Downloads and installs Visual C++ 2015-2022 redistributables. #>
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Redistributables"
		)]
		[ValidateSet("2015_2022_x86", "2015_2022_x64")]
		[string[]]
		$Redistributables
	)

	$vcredistVersion = $null

	try
	{
		# Version metadata from the ScoopInstaller community bucket (mutable ref -
		# tracks latest VC++ 2015-2022 redistributable). If the upstream JSON
		# schema changes, the .version field access will fail and the catch block
		# below will leave $vcredistVersion as $null, skipping the upgrade check.
		$Parameters = @{
			Uri             = "https://raw.githubusercontent.com/ScoopInstaller/Extras/refs/heads/master/bucket/vcredist2022.json"
			UseBasicParsing = $true
			TimeoutSec      = 15
		}
		$vcredistVersion = ConvertTo-NormalizedVersion -Version (Invoke-RestMethod @Parameters).version
	}
	catch [System.Net.WebException]
	{
		LogWarning "Unable to determine the latest Visual C++ Redistributable version. Installed packages will be left unchanged unless missing."
	}

	$DownloadsFolder = Join-Path $env:TEMP "Baseline-Downloads-$([System.IO.Path]::GetRandomFileName())"
	New-Item -ItemType Directory -Path $DownloadsFolder -Force -ErrorAction Stop | Out-Null

	foreach ($Redistributable in $Redistributables)
	{
		switch ($Redistributable)
		{
			2015_2022_x86
			{
				$DisplayName = "Visual C++ Redistributable (2015 - 2022) x86"
				$InstalledVersion = Get-InstalledVCRedistVersion -Architecture "x86"
				$ShouldInstall = $null -eq $InstalledVersion

				if ($null -ne $InstalledVersion -and $null -ne $vcredistVersion)
				{
					$ShouldInstall = $vcredistVersion -gt $InstalledVersion
				}

				if (-not $ShouldInstall)
				{
					LogInfo "$DisplayName already installed (version $InstalledVersion)."
					Write-ConsoleStatus -Action "Checking $DisplayName"
					Write-ConsoleStatus -Status success
					continue
				}

				if ($null -eq $InstalledVersion)
				{
					LogInfo "$DisplayName not detected. Installing it."
				}
				elseif ($null -ne $vcredistVersion)
				{
					LogInfo "$DisplayName version $InstalledVersion detected. Updating to $vcredistVersion."
				}

				try
				{
					Write-ConsoleStatus -Action "Installing $DisplayName"
					LogInfo "Installing $DisplayName"

					$Parameters = @{
						Uri             = "https://aka.ms/vs/17/release/VC_redist.x86.exe"
						OutFile         = "$DownloadsFolder\VC_redist.x86.exe"
						UseBasicParsing = $true
						TimeoutSec      = 30
					}
					Invoke-WebRequest @Parameters

					$sig = Get-AuthenticodeSignature -FilePath "$DownloadsFolder\VC_redist.x86.exe"
					if ($sig.Status -ne 'Valid') { throw "Authenticode signature verification failed for VC_redist.x86.exe (status: $($sig.Status))" }

					$VCx86Process = Start-Process -FilePath "$DownloadsFolder\VC_redist.x86.exe" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
					if ($VCx86Process.ExitCode -ne 0) { throw "VC_redist.x86.exe returned exit code $($VCx86Process.ExitCode)" }

					$Paths = @(
						"$DownloadsFolder\VC_redist.x86.exe",
						"$env:TEMP\dd_vcredist_x86_*.log"
					)
					Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch [System.Net.WebException]
				{
					LogError ($Localization.NoResponse -f "https://download.visualstudio.microsoft.com")
					LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))
					Write-ConsoleStatus -Status failed

					return
				}
				catch
				{
					LogError "Failed to install ${DisplayName}: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
					continue
				}
			}
			2015_2022_x64
			{
				$DisplayName = "Visual C++ Redistributable (2015 - 2022) x64"
				$InstalledVersion = Get-InstalledVCRedistVersion -Architecture "x64"
				$ShouldInstall = $null -eq $InstalledVersion

				if ($null -ne $InstalledVersion -and $null -ne $vcredistVersion)
				{
					$ShouldInstall = $vcredistVersion -gt $InstalledVersion
				}

				if (-not $ShouldInstall)
				{
					LogInfo "$DisplayName already installed (version $InstalledVersion)."
					Write-ConsoleStatus -Action "Checking $DisplayName"
					Write-ConsoleStatus -Status success
					continue
				}

				if ($null -eq $InstalledVersion)
				{
					LogInfo "$DisplayName not detected. Installing it."
				}
				elseif ($null -ne $vcredistVersion)
				{
					LogInfo "$DisplayName version $InstalledVersion detected. Updating to $vcredistVersion."
				}

				try
				{
					Write-ConsoleStatus -Action "Installing $DisplayName"
					LogInfo "Installing $DisplayName"

					$Parameters = @{
						Uri             = "https://aka.ms/vs/17/release/VC_redist.x64.exe"
						OutFile         = "$DownloadsFolder\VC_redist.x64.exe"
						UseBasicParsing = $true
						TimeoutSec      = 30
					}
					Invoke-WebRequest @Parameters

					$sig = Get-AuthenticodeSignature -FilePath "$DownloadsFolder\VC_redist.x64.exe"
					if ($sig.Status -ne 'Valid') { throw "Authenticode signature verification failed for VC_redist.x64.exe (status: $($sig.Status))" }

					$VCx64Process = Start-Process -FilePath "$DownloadsFolder\VC_redist.x64.exe" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
					if ($VCx64Process.ExitCode -ne 0) { throw "VC_redist.x64.exe returned exit code $($VCx64Process.ExitCode)" }

					$Paths = @(
						"$DownloadsFolder\VC_redist.x64.exe",
						"$env:TEMP\dd_vcredist_amd64_*.log"
					)
					Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch [System.Net.WebException]
				{
					LogError ($Localization.NoResponse -f "https://download.visualstudio.microsoft.com")
					LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))
					Write-ConsoleStatus -Status failed

					return
				}
				catch
				{
					LogError "Failed to install ${DisplayName}: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
					continue
				}
			}
		}
	}
}

function Install-DotNetRuntimeVersion
{
	<#
		.SYNOPSIS
		Shared helper that installs or updates a single .NET runtime version.

		.DESCRIPTION
		Downloads and installs a .NET Desktop Runtime for the specified major version.
		Returns a status string: "success", "skip", "return", or "continue" so the
		caller can apply the appropriate flow-control (continue / return) inside its
		foreach loop.
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[int]
		$MajorVersion,

		[Parameter(Mandatory = $true)]
		[string]
		$DisplayName,

		[Parameter(Mandatory = $true)]
		[string]
		$DownloadsFolder,

		[Parameter(Mandatory = $true)]
		[System.Management.Automation.InvocationInfo]
		$CallerInvocation
	)

	$InstalledVersion = Get-InstalledDotNetRuntimeVersion -MajorVersion $MajorVersion
	$LatestVersion = $null
	$DownloadUrl = $null
	$FileName = $null
	$SourceHost = "https://builds.dotnet.microsoft.com"

	try
	{
		$Release = Get-LatestDotNetRuntimeRelease -MajorVersion $MajorVersion
		if ($null -ne $Release)
		{
			$LatestVersion = $Release.Version
			$DownloadUrl = $Release.DownloadUrl
			$FileName = $Release.FileName
			$SourceHost = $Release.SourceHost
		}
	}
	catch [System.Net.WebException]
	{
		if ($null -ne $InstalledVersion)
		{
			LogWarning "Unable to determine the latest $DisplayName version. Detected installed version $InstalledVersion, so the install will be skipped."
		}
		else
		{
			LogError ($Localization.NoResponse -f "https://builds.dotnet.microsoft.com")
			LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $CallerInvocation))
			Write-ConsoleStatus -Action "Installing $DisplayName"
			Write-ConsoleStatus -Status failed

			return "return"
		}
	}

	$ShouldInstall = $null -eq $InstalledVersion

	if ($null -ne $InstalledVersion -and $null -ne $LatestVersion)
	{
		$ShouldInstall = $LatestVersion -gt $InstalledVersion
	}

	if (-not $ShouldInstall)
	{
		LogInfo "$DisplayName already installed (version $InstalledVersion)."
		Write-ConsoleStatus -Action "Checking $DisplayName"
		Write-ConsoleStatus -Status success
		return "skip"
	}

	if ($null -eq $LatestVersion)
	{
		LogError "Unable to determine the latest $DisplayName version."
		Write-ConsoleStatus -Action "Installing $DisplayName"
		Write-ConsoleStatus -Status failed
		return "return"
	}

	if ($null -eq $InstalledVersion)
	{
		LogInfo "$DisplayName not detected. Installing version $LatestVersion."
	}
	else
	{
		LogInfo "$DisplayName version $InstalledVersion detected. Updating to $LatestVersion."
	}

	try
	{
		Write-ConsoleStatus -Action "Installing .NET $LatestVersion x64"
		LogInfo "Installing .NET $LatestVersion x64"

		$Parameters = @{
			Uri             = $DownloadUrl
			OutFile         = "$DownloadsFolder\$FileName"
			UseBasicParsing = $true
			TimeoutSec      = 30
		}
		Invoke-WebRequest @Parameters

		$sig = Get-AuthenticodeSignature -FilePath "$DownloadsFolder\$FileName"
		if ($sig.Status -ne 'Valid') { throw "Authenticode signature verification failed for $FileName (status: $($sig.Status))" }

		$InstallProcess = Start-Process -FilePath "$DownloadsFolder\$FileName" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
		if ($InstallProcess.ExitCode -ne 0) { throw "$FileName returned exit code $($InstallProcess.ExitCode)" }

		$Paths = @(
			"$DownloadsFolder\$FileName",
			"$env:TEMP\Microsoft_.NET_Runtime*.log"
		)
		Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
		Write-ConsoleStatus -Status success
		return "success"
	}
	catch [System.Net.WebException]
	{
		LogError ($Localization.NoResponse -f $SourceHost)
		LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $CallerInvocation))
		Write-ConsoleStatus -Status failed

		return "return"
	}
	catch
	{
		LogError "Failed to install .NET $LatestVersion x64: $($_.Exception.Message)"
		Write-ConsoleStatus -Status failed
		return "continue"
	}
}

function Install-DotNetRuntimes
{
	<# .SYNOPSIS Installs specified .NET runtimes by name (NET8x64, NET9x64). #>
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Runtimes"
		)]
		[ValidateSet("NET8x64", "NET9x64")]
		[string[]]
		$Runtimes
	)

	$DownloadsFolder = Join-Path $env:TEMP "Baseline-Downloads-$([System.IO.Path]::GetRandomFileName())"
	New-Item -ItemType Directory -Path $DownloadsFolder -Force -ErrorAction Stop | Out-Null

	foreach ($Runtime in $Runtimes)
	{
		switch ($Runtime)
		{
			NET8x64
			{
				$Result = Install-DotNetRuntimeVersion -MajorVersion 8 -DisplayName ".NET 8 x64" -DownloadsFolder $DownloadsFolder -CallerInvocation $MyInvocation
				if ($Result -eq "return") { return }
				if ($Result -eq "continue" -or $Result -eq "skip") { continue }
			}
			NET9x64
			{
				$Result = Install-DotNetRuntimeVersion -MajorVersion 9 -DisplayName ".NET 9 x64" -DownloadsFolder $DownloadsFolder -CallerInvocation $MyInvocation
				if ($Result -eq "return") { return }
				if ($Result -eq "continue" -or $Result -eq "skip") { continue }
			}
		}
	}
}
