# Windows Subsystem for Linux (WSL) install helpers.
#
# Spec: todo.md "WSL install flow (`Install-WSL`)" -- picks a distro from
# the DistributionInfo.json catalog, runs `wsl.exe --install --distribution
# <Alias>`, and enables the Microsoft Update delivery service so the WSL
# Kernel update handling and install helpers live here.
# The GUI picker and runner wiring used by the menu entry are handled
# in the separate WSL menu slice.

function Get-BaselineWslDistributionCatalogUrl
{
	<#
		.SYNOPSIS
		Returns the configured DistributionInfo.json URL.

		.DESCRIPTION
		Honours the BASELINE_WSL_CATALOG_URL env override so tests redirect to
		a local fixture without ever touching the network.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$catalogUrl = [string]$env:BASELINE_WSL_CATALOG_URL
	if ([string]::IsNullOrWhiteSpace($catalogUrl))
	{
		return ''
	}

	return $catalogUrl.Trim()
}

function ConvertFrom-BaselineWslDistributionCatalogJson
{
	<#
		.SYNOPSIS
		Projects the DistributionInfo.json payload into the
		`{Distribution, Alias}` shape Baseline callers consume.

		.DESCRIPTION
		Pure / side-effect-free: takes a raw JSON string, returns an array of
		[pscustomobject]@{Distribution, Alias} sorted by FriendlyName so the
		picker dialog renders in stable order. Defensive on missing / empty /
		malformed input -- returns an empty array rather than throwing so a
		stale CDN copy of the catalog cannot crash the host.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$RawJson
	)

	if ([string]::IsNullOrWhiteSpace($RawJson))
	{
		return @()
	}

	try
	{
		$parsed = $RawJson | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Wsl.Helpers.ConvertFrom-BaselineWslDistributionCatalogJson:catch64' -Severity Debug }

		return @()
	}

	if ($null -eq $parsed) { return @() }

	$distros = $null
	if ($parsed.PSObject.Properties.Name -contains 'Distributions')
	{
		$distros = $parsed.Distributions
	}
	if ($null -eq $distros) { return @() }

	$results = New-Object System.Collections.Generic.List[object]
	foreach ($d in $distros)
	{
		if ($null -eq $d) { continue }

		$friendly = $null
		$alias = $null
		if ($d.PSObject.Properties.Name -contains 'FriendlyName')
		{
			$friendly = [string]$d.FriendlyName
		}
		if ($d.PSObject.Properties.Name -contains 'Name')
		{
			$alias = [string]$d.Name
		}

		if ([string]::IsNullOrWhiteSpace($alias)) { continue }
		if ([string]::IsNullOrWhiteSpace($friendly)) { $friendly = $alias }

		$results.Add([pscustomobject]@{
			Distribution = $friendly
			Alias        = $alias
		}) | Out-Null
	}

	return @($results | Sort-Object -Property Distribution)
}

function Get-BaselineWslDistributionCatalog
{
	<#
		.SYNOPSIS
		Fetches the configured distribution catalog and projects it into
		the Baseline `{Distribution, Alias}` shape.

		.DESCRIPTION
		Wraps Invoke-WebRequest so the network call is the only side effect.
		Returns an empty array on any failure (network down, 404, parse
		error) -- callers render an "unreachable" message rather than crash.
		The fetcher is overridable via -Fetcher so tests can pin behaviour
		without touching the network.

		.PARAMETER Url
		Optional explicit catalog URL. Defaults to
		Get-BaselineWslDistributionCatalogUrl.

		.PARAMETER Fetcher
		Optional [scriptblock] override that takes the URL and returns the
		raw JSON string. Tests pass a fixture-returning block to keep the
		network out of the unit run.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[string]$Url,
		[scriptblock]$Fetcher
	)

	if ([string]::IsNullOrWhiteSpace($Url))
	{
		$Url = Get-BaselineWslDistributionCatalogUrl
	}

	if ([string]::IsNullOrWhiteSpace($Url))
	{
		return @()
	}

	$rawJson = $null
	try
	{
		if ($Fetcher)
		{
			$rawJson = & $Fetcher $Url
		}
		else
		{
			$response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
			$rawJson = [string]$response.Content
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Wsl.Helpers.Get-BaselineWslDistributionCatalog:catch159' -Severity Debug }

		return @()
	}

	return (ConvertFrom-BaselineWslDistributionCatalogJson -RawJson ([string]$rawJson))
}

function Test-BaselineWslPrerequisite
{
	<#
		.SYNOPSIS
		Returns whether the host meets the minimum requirements for
		`wsl --install`.

		.DESCRIPTION
		The single-line `wsl --install` flow Microsoft introduced in
		Windows 10 build 19041 (2004) requires Windows 10 2004+ or
		Windows 11. Earlier builds require the legacy multi-step opt-in
		path which Baseline does not script.

		Returns a record describing Supported / Reason / BuildNumber /
		ProductType so the caller can render a localized warning before
		attempting install. Defers OS detection to
		Get-BaselineSystemPlatformInfo when available; falls back to
		Get-CimInstance directly so the helper stays callable from a
		bare Pester run that has not loaded the PlatformSupport slice.

		.PARAMETER PlatformInfo
		Optional explicit platform record (test hook). When supplied, no
		OS detection is performed.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[pscustomobject]$PlatformInfo
	)

	if (-not $PSBoundParameters.ContainsKey('PlatformInfo') -or $null -eq $PlatformInfo)
	{
		if (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -ErrorAction SilentlyContinue)
		{
			$PlatformInfo = Get-BaselineSystemPlatformInfo
		}
		else
		{
			$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
			$buildVal = 0
			$productType = 1
			if ($os)
			{
				if ($os.PSObject.Properties.Name -contains 'BuildNumber')
				{
					$buildVal = 0
					[int]::TryParse([string]$os.BuildNumber, [ref]$buildVal) | Out-Null
				}
				if ($os.PSObject.Properties.Name -contains 'ProductType')
				{
					$productType = [int]$os.ProductType
				}
			}
			$PlatformInfo = [pscustomobject]@{
				BuildNumber = $buildVal
				ProductType = $productType
				IsServer    = ($productType -ne 1)
			}
		}
	}

	$build = 0
	if ($PlatformInfo.PSObject.Properties.Name -contains 'BuildNumber')
	{
		[int]::TryParse([string]$PlatformInfo.BuildNumber, [ref]$build) | Out-Null
	}

	$productType = 1
	if ($PlatformInfo.PSObject.Properties.Name -contains 'ProductType')
	{
		$productType = [int]$PlatformInfo.ProductType
	}
	elseif ($PlatformInfo.PSObject.Properties.Name -contains 'IsServer' -and $PlatformInfo.IsServer)
	{
		$productType = 3
	}

	if ($build -lt 19041)
	{
		return [pscustomobject]@{
			Supported   = $false
			Reason      = "Windows build $build is below the WSL --install minimum (19041 / Windows 10 2004)."
			BuildNumber = $build
			ProductType = $productType
		}
	}

	return [pscustomobject]@{
		Supported   = $true
		Reason      = $null
		BuildNumber = $build
		ProductType = $productType
	}
}

function Get-BaselineWslInstallationState
{
	<#
		.SYNOPSIS
		Reports whether wsl.exe is installed and which distros are present.

		.DESCRIPTION
		Returns a record with `Installed`, `Path`, `InstalledDistributions`,
		and `RawList` fields. Installed=$true means wsl.exe resolves; presence
		of distros is reported separately so callers can offer the install
		dialog even when wsl.exe is present but empty (the post-Win11 default
		since `wsl --install` ships the runtime by default).

		.PARAMETER WslExePath
		Optional explicit path (test hook). Defaults to resolving via
		Get-Command.

		.PARAMETER ListInvoker
		Optional scriptblock that returns the raw `wsl --list --quiet`
		string. Tests pin behaviour without spawning a real wsl.exe child.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$WslExePath,
		[scriptblock]$ListInvoker
	)

	if ([string]::IsNullOrWhiteSpace($WslExePath))
	{
		$cmd = Get-Command -Name 'wsl.exe' -ErrorAction SilentlyContinue
		if ($cmd)
		{
			$WslExePath = $cmd.Source
		}
	}

	if ([string]::IsNullOrWhiteSpace($WslExePath) -or -not (Test-Path -LiteralPath $WslExePath))
	{
		return [pscustomobject]@{
			Installed              = $false
			Path                   = $null
			InstalledDistributions = @()
			RawList                = $null
		}
	}

	$rawList = $null
	try
	{
		if ($ListInvoker)
		{
			$rawList = [string](& $ListInvoker $WslExePath)
		}
		else
		{
			# Suppress stderr so the "no installed distros" stderr message
			# does not pollute the parent's error stream.
			$rawList = & $WslExePath --list --quiet 2>$null | Out-String
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Wsl.Helpers.Get-BaselineWslInstallationState:catch323' -Severity Debug }

		$rawList = $null
	}

	$distros = @()
	if (-not [string]::IsNullOrWhiteSpace($rawList))
	{
		# wsl.exe writes UTF-16LE list output by default; the parent is on
		# the host's OEM CP. Strip BOM bytes / NULs that survive the
		# decode round-trip.
		$cleaned = ($rawList -replace "[`0﻿]", '').Trim()
		$distros = @(
			$cleaned -split "`r?`n" |
				ForEach-Object { $_.Trim() } |
				Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
		)
	}

	return [pscustomobject]@{
		Installed              = $true
		Path                   = $WslExePath
		InstalledDistributions = $distros
		RawList                = $rawList
	}
}

function Install-BaselineWslDistribution
{
	<#
		.SYNOPSIS
		Runs `wsl.exe --install --distribution <Alias>` and records the
		exit code. Honours -WhatIf so callers can dry-run from the GUI.

		.DESCRIPTION
		Returns a record with `Started`, `ExitCode`, `Alias`, and
		`StartInfo` fields. Started=$false when prerequisites fail or
		wsl.exe is absent; ExitCode is the wsl.exe exit code on success.
		Reboot prompt handling is left to wsl.exe itself -- the
		`--install` flow surfaces its own UAC + reboot dialog.

		.PARAMETER Alias
		The distribution alias (e.g. "Ubuntu", "Debian", "kali-linux").
		Validated against the catalog when -Catalog is supplied; otherwise
		passed through verbatim.

		.PARAMETER Catalog
		Optional catalog (Get-BaselineWslDistributionCatalog output). When
		supplied, -Alias must match one of the catalog Alias values.

		.PARAMETER WslExePath
		Optional explicit wsl.exe path (test hook).

		.PARAMETER StartProcessInvoker
		Optional scriptblock that takes (FilePath, ArgumentList) and
		returns an int exit code. Tests pin behaviour without spawning a
		real wsl.exe child.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Alias,
		[pscustomobject[]]$Catalog,
		[string]$WslExePath,
		[scriptblock]$StartProcessInvoker
	)

	if ($PSBoundParameters.ContainsKey('Catalog') -and $null -ne $Catalog -and $Catalog.Count -gt 0)
	{
		$known = @($Catalog | ForEach-Object { [string]$_.Alias })
		if ($known -notcontains $Alias)
		{
			return [pscustomobject]@{
				Started   = $false
				ExitCode  = $null
				Alias     = $Alias
				StartInfo = $null
				Reason    = "Alias '$Alias' is not present in the supplied WSL distribution catalog."
			}
		}
	}

	if ([string]::IsNullOrWhiteSpace($WslExePath))
	{
		$cmd = Get-Command -Name 'wsl.exe' -ErrorAction SilentlyContinue
		if ($cmd) { $WslExePath = $cmd.Source }
	}

	if ([string]::IsNullOrWhiteSpace($WslExePath) -or -not (Test-Path -LiteralPath $WslExePath))
	{
		return [pscustomobject]@{
			Started   = $false
			ExitCode  = $null
			Alias     = $Alias
			StartInfo = $null
			Reason    = 'wsl.exe is not available on this host.'
		}
	}

	$argumentList = @('--install', '--distribution', $Alias)
	$startInfo = [pscustomobject]@{
		FilePath     = $WslExePath
		ArgumentList = $argumentList
	}

	if (-not $PSCmdlet.ShouldProcess("$WslExePath $($argumentList -join ' ')", 'Install WSL distribution'))
	{
		return [pscustomobject]@{
			Started   = $false
			ExitCode  = $null
			Alias     = $Alias
			StartInfo = $startInfo
			Reason    = 'WhatIf'
		}
	}

	$exitCode = $null
	try
	{
		if ($StartProcessInvoker)
		{
			$exitCode = [int](& $StartProcessInvoker $WslExePath $argumentList)
		}
		else
		{
			$proc = Invoke-BaselineProcess -FilePath $WslExePath -ArgumentList $argumentList -TimeoutSeconds 900
			if ($proc -and $proc.PSObject.Properties.Name -contains 'ExitCode')
			{
				$exitCode = [int]$proc.ExitCode
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Wsl.Helpers.Install-BaselineWslDistribution:catch457' -Severity Debug }

		return [pscustomobject]@{
			Started   = $false
			ExitCode  = $null
			Alias     = $Alias
			StartInfo = $startInfo
			Reason    = $_.Exception.Message
		}
	}

	return [pscustomobject]@{
		Started   = $true
		ExitCode  = $exitCode
		Alias     = $Alias
		StartInfo = $startInfo
		Reason    = $null
	}
}

function Enable-BaselineMicrosoftUpdateDelivery
{
	<#
		.SYNOPSIS
		Sets HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings\AllowMUUpdateService=1
		so Windows Update receives kernel updates for WSL (the "Receive
		updates for other Microsoft products" toggle in Settings).

		.DESCRIPTION
		Performs the post-install step required for WSL kernel updates.
		Honours -WhatIf via SupportsShouldProcess. Defers the actual write to
		Set-RegistryValueSafe when available so the rest of Baseline's audit
		pipeline picks it up; falls back to a direct write so the helper stays
		callable from a bare unit run.

		Returns a record with `Applied`, `PreviousValue`, `Path`, `Name`.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param ()

	$path = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
	$name = 'AllowMUUpdateService'

	$previous = $null
	try
	{
		if (Test-Path -LiteralPath $path)
		{
			$item = Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
			if ($item -and $item.PSObject.Properties.Name -contains $name)
			{
				$previous = $item.$name
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Wsl.Helpers.Enable-BaselineMicrosoftUpdateDelivery:catch513' -Severity Debug }

		$previous = $null
	}

	if (-not $PSCmdlet.ShouldProcess("$path\$name", 'Set AllowMUUpdateService=1'))
	{
		return [pscustomobject]@{
			Applied       = $false
			PreviousValue = $previous
			Path          = $path
			Name          = $name
		}
	}

	if (Get-Command -Name 'Set-RegistryValueSafe' -ErrorAction SilentlyContinue)
	{
		$null = Set-RegistryValueSafe -Path $path -Name $name -Type DWord -Value 1
	}
	else
	{
		if (-not (Test-Path -LiteralPath $path))
		{
			New-Item -Path $path -Force | Out-Null
		}
		Set-ItemProperty -LiteralPath $path -Name $name -Value 1 -Type DWord -Force
	}

	return [pscustomobject]@{
		Applied       = $true
		PreviousValue = $previous
		Path          = $path
		Name          = $name
	}
}

function Invoke-BaselineWindowsUpdateScan
{
	<#
		.SYNOPSIS
		Triggers `UsoClient.exe StartInteractiveScan` so Windows Update
		picks up the AllowMUUpdateService change immediately.

		.DESCRIPTION
		Performs the post-install Windows Update scan step. Honours -WhatIf.
		`UsoClient.exe` lives at $env:SystemRoot\System32\UsoClient.exe;
		returns Started=$false when the binary is absent so a callsite on a
		stripped Server SKU does not throw.

		.PARAMETER UsoClientPath
		Optional explicit path (test hook).

		.PARAMETER StartProcessInvoker
		Optional scriptblock that takes (FilePath, ArgumentList) and
		returns an int exit code.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[string]$UsoClientPath,
		[scriptblock]$StartProcessInvoker
	)

	if ([string]::IsNullOrWhiteSpace($UsoClientPath))
	{
		$UsoClientPath = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
	}

	if (-not (Test-Path -LiteralPath $UsoClientPath))
	{
		return [pscustomobject]@{
			Started  = $false
			Path     = $UsoClientPath
			ExitCode = $null
			Reason   = 'UsoClient.exe is not present on this host.'
		}
	}

	$argumentList = @('StartInteractiveScan')
	if (-not $PSCmdlet.ShouldProcess("$UsoClientPath StartInteractiveScan", 'Trigger Windows Update scan'))
	{
		return [pscustomobject]@{
			Started  = $false
			Path     = $UsoClientPath
			ExitCode = $null
			Reason   = 'WhatIf'
		}
	}

	$exitCode = $null
	try
	{
		if ($StartProcessInvoker)
		{
			$exitCode = [int](& $StartProcessInvoker $UsoClientPath $argumentList)
		}
		else
		{
			$proc = Start-Process -FilePath $UsoClientPath -ArgumentList $argumentList -PassThru -ErrorAction Stop
			if ($proc -and $proc.PSObject.Properties.Name -contains 'ExitCode')
			{
				$exitCode = [int]$proc.ExitCode
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Wsl.Helpers.Invoke-BaselineWindowsUpdateScan:catch618' -Severity Debug }

		return [pscustomobject]@{
			Started  = $false
			Path     = $UsoClientPath
			ExitCode = $null
			Reason   = $_.Exception.Message
		}
	}

	return [pscustomobject]@{
		Started  = $true
		Path     = $UsoClientPath
		ExitCode = $exitCode
		Reason   = $null
	}
}

function Invoke-BaselineWslInstallFlow
{
	<#
		.SYNOPSIS
		Runs the end-to-end WSL install flow for a selected distro.

		.DESCRIPTION
		Performs the same sequence the GUI uses after the user picks a
		distribution: prerequisite check, `wsl.exe --install --distribution
		<Alias>`, Microsoft Update delivery enablement, and a Windows
		Update scan. Returns a single summary object so the caller can
		report the result in one place.

		.PARAMETER Alias
		The WSL distribution alias selected by the user.

		.PARAMETER Catalog
		Optional distribution catalog used to validate Alias before any
		installation step begins.

		.PARAMETER WslExePath
		Optional explicit `wsl.exe` path for callers that want to pin a
		particular binary during tests or diagnostics.

		.PARAMETER UsoClientPath
		Optional explicit `UsoClient.exe` path for callers that want to pin
		a particular binary during tests or diagnostics.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Alias,
		[pscustomobject[]]$Catalog,
		[string]$WslExePath,
		[string]$UsoClientPath
	)

	$prereq = Test-BaselineWslPrerequisite
	if (-not $prereq.Supported)
	{
		return [pscustomobject]@{
			Succeeded     = $false
			Stage         = 'Prerequisite'
			Alias         = $Alias
			Prerequisite  = $prereq
			Installation  = $null
			UpdateDelivery = $null
			UpdateScan    = $null
			Reason        = $prereq.Reason
		}
	}

	if (-not $PSCmdlet.ShouldProcess("WSL install flow for $Alias", 'Run WSL install flow'))
	{
		return [pscustomobject]@{
			Succeeded     = $false
			Stage         = 'WhatIf'
			Alias         = $Alias
			Prerequisite  = $prereq
			Installation  = $null
			UpdateDelivery = $null
			UpdateScan    = $null
			Reason        = 'WhatIf'
		}
	}

	$install = Install-BaselineWslDistribution -Alias $Alias -Catalog $Catalog -WslExePath $WslExePath
	if (-not $install.Started)
	{
		return [pscustomobject]@{
			Succeeded     = $false
			Stage         = 'Install'
			Alias         = $Alias
			Prerequisite  = $prereq
			Installation  = $install
			UpdateDelivery = $null
			UpdateScan    = $null
			Reason        = $install.Reason
		}
	}

	if ($null -ne $install.ExitCode -and [int]$install.ExitCode -ne 0)
	{
		return [pscustomobject]@{
			Succeeded     = $false
			Stage         = 'Install'
			Alias         = $Alias
			Prerequisite  = $prereq
			Installation  = $install
			UpdateDelivery = $null
			UpdateScan    = $null
			Reason        = ('wsl.exe exited with code {0}.' -f [int]$install.ExitCode)
		}
	}

	$updateDelivery = Enable-BaselineMicrosoftUpdateDelivery
	$updateScan = Invoke-BaselineWindowsUpdateScan -UsoClientPath $UsoClientPath
	$completed = [bool]$updateDelivery.Applied -and [bool]$updateScan.Started

	return [pscustomobject]@{
		Succeeded      = $completed
		Stage          = if ($completed) { 'Complete' } elseif (-not $updateDelivery.Applied) { 'UpdateDelivery' } else { 'UpdateScan' }
		Alias          = $Alias
		Prerequisite   = $prereq
		Installation   = $install
		UpdateDelivery = $updateDelivery
		UpdateScan     = $updateScan
		Reason         = if ($completed) { $null } elseif (-not $updateDelivery.Applied) { 'Failed to enable Microsoft Update delivery.' } else { $updateScan.Reason }
	}
}
