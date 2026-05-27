# PlatformSupport — canonical OS-detection + per-entry availability gating.
#
# Today every tweak/app function detects the host OS itself (or worse,
# doesn't), and manifests don't declare which platforms they're valid on.
# One shared evaluator is now the single source of truth for OS support so
# individual functions no longer read EditionID / ProductType directly.
# See "OS support matrix" in todo.md for the full schema.
#
# Cross-cutting use:
#   - manifest loader stamps `Availability` onto every entry at load time
#   - GUI filter pipeline drops Available=$false entries when the
#     "Hide unavailable items" pref is on
#   - presets skip unavailable entries with a "Skipped — not available on
#     this system" line in the run report (instead of failing)

$Script:CachedBaselineDefenderExecutionAvailable = $null
$Script:CachedBaselineDefenderExecutionUnavailableReason = $null
$Script:CachedBaselineDefenderComponentAvailable = $null
$Script:CachedBaselineDefenderComponentUnavailableReason = $null

# Shape-agnostic field probes — manifest entries arrive as either ordered
# hashtables (from Import-TweakManifestFromData) or pscustomobjects (from
# tests / scripted callers). Both Test-BaselineEntryAvailable and
# Update-BaselineManifestAvailability go through these so we only have one
# place to fix when the manifest loader's shape decisions evolve.
function Test-BaselineEntryFieldPresent
{
	[CmdletBinding()]
	[OutputType([bool])]
	param ([Parameter(Mandatory)][AllowNull()][object]$Entry, [Parameter(Mandatory)][string]$Name)

	if ($null -eq $Entry) { return $false }
	if ($Entry -is [System.Collections.IDictionary]) { return [bool]$Entry.Contains($Name) }
	if ($Entry.PSObject -and $Entry.PSObject.Properties[$Name]) { return $true }
	return $false
}

function Get-BaselineEntryFieldValue
{
	[CmdletBinding()]
	param ([Parameter(Mandatory)][AllowNull()][object]$Entry, [Parameter(Mandatory)][string]$Name)

	# Use ,$value when returning collections so PowerShell does not unwrap a
	# single-element array into a scalar (PlatformSupport's `Server` field
	# can be a 1-element release-tag list and we need callers to see the array).
	if ($null -eq $Entry) { return $null }
	if ($Entry -is [System.Collections.IDictionary])
	{
		if (-not $Entry.Contains($Name)) { return $null }
		$value = $Entry[$Name]
	}
	elseif ($Entry.PSObject -and $Entry.PSObject.Properties[$Name])
	{
		$value = $Entry.$Name
	}
	else
	{
		return $null
	}

	if ($null -ne $value -and $value -is [System.Collections.IEnumerable] -and -not ($value -is [string]) -and -not ($value -is [System.Collections.IDictionary]))
	{
		return , @($value)
	}
	return $value
}

function Test-BaselineEditionInFamily
{
	# Returns $true if the supplied EditionID belongs to one of the listed
	# families. Families are: 'Pro', 'Home', 'Enterprise', 'Education',
	# 'Server'. Microsoft's EditionID strings are noisy variants
	# (Professional / ProfessionalEducation / EnterpriseS / Core / etc.), so
	# we match by substring on the family token. Anything unrecognised falls
	# through to $false — caller decides whether to default-allow or block.
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)][AllowEmptyString()][string]$EditionID,
		[Parameter(Mandatory)][string[]]$Families
	)

	if ([string]::IsNullOrWhiteSpace($EditionID)) { return $false }

	foreach ($family in $Families)
	{
		switch -Regex ($family)
		{
			'^(?i)Pro(fessional)?$'
			{
				if ($EditionID -match '(?i)Professional')      { return $true }
				if ($EditionID -match '(?i)^Pro')              { return $true }
				break
			}
			'^(?i)Home(Core)?$|^(?i)Core$'
			{
				if ($EditionID -match '(?i)Core(?!Server)')    { return $true }
				if ($EditionID -match '(?i)^Home')             { return $true }
				break
			}
			'^(?i)Enterprise$'
			{
				if ($EditionID -match '(?i)Enterprise')        { return $true }
				if ($EditionID -match '(?i)IoTEnterprise')     { return $true }
				break
			}
			'^(?i)Education$'
			{
				if ($EditionID -match '(?i)Education')         { return $true }
				break
			}
			'^(?i)Server$'
			{
				if ($EditionID -match '(?i)Server')            { return $true }
				break
			}
			default
			{
				if ($EditionID -match ('(?i){0}' -f [regex]::Escape($family))) { return $true }
			}
		}
	}
	return $false
}

function Get-BaselineServerReleaseFromBuild
{
	# Maps a Server build number to the marketing release tag PlatformSupport
	# arrays use ("Server2019" / "Server2022" / "Server2025"). Build ranges
	# are inclusive of the next release's RTM build to be forward-compatible
	# with cumulative-update build bumps. Returns $null on unknown builds so
	# callers can fall back to the bool form of `Server`.
	[CmdletBinding()]
	[OutputType([string])]
	param ([Parameter(Mandatory)][int]$BuildNumber)

	if ($BuildNumber -le 0) { return $null }
	if ($BuildNumber -lt 17763) { return $null }     # Pre-2019 unsupported
	if ($BuildNumber -lt 20348) { return 'Server2019' }
	if ($BuildNumber -lt 26100) { return 'Server2022' }  # also covers 23H2 (25398)
	return 'Server2025'
}

<#
    .SYNOPSIS
#>

function Get-BaselineSystemPlatformInfo
{
	<#
		.SYNOPSIS
		Returns the canonical platform info object every other helper in this
		module consumes. One source of truth for "what OS am I on?".

		.DESCRIPTION
		Wraps Win32_OperatingSystem + the registry CurrentVersion key into a
		single deterministic shape:
		  - MajorVersion : 10 (Windows 10/11), 6 (Server 2008/2012), etc.
		  - BuildNumber  : the OS build (e.g. 22631 for Win11 23H2)
		  - ProductType  : 1 = Workstation (Win10/Win11), 2 = Domain Controller, 3 = Server
		  - IsServer     : $true when ProductType -ne 1
		  - IsWindows10  : $true on Windows 10 client builds (10.0 + build < 22000)
		  - IsWindows11  : $true on Windows 11 client builds (10.0 + build >= 22000)
		  - EditionID    : Pro / Home / Enterprise / ServerStandard / ...
		  - Architecture : amd64 / arm64 / x86
		  - DisplayName  : friendly label, e.g. "Windows 11 Pro 24H2"

		Accepts an `-Override` param (hashtable / pscustomobject) that lets
		tests inject synthetic OS readings without WMI. The override is also
		how the GUI's "This device only" / "Windows 10 / 11 / Server" filter
		picks a virtual platform to evaluate availability against.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[AllowNull()]
		[object]$Override
	)

	if ($Override)
	{
		# Normalise hashtables into pscustomobject so callers can do dotted
		# access without hashtable-key gymnastics.
		if ($Override -is [System.Collections.IDictionary])
		{
			$ordered = [ordered]@{}
			foreach ($key in $Override.Keys) { $ordered[[string]$key] = $Override[$key] }
			$Override = [pscustomobject]$ordered
		}

		$majorRaw = if ($Override.PSObject.Properties['MajorVersion']) { $Override.MajorVersion } else { 10 }
		$buildRaw = if ($Override.PSObject.Properties['BuildNumber']) { $Override.BuildNumber } else { 0 }
		$ptypeRaw = if ($Override.PSObject.Properties['ProductType']) { $Override.ProductType } else { 1 }
		$editionRaw = if ($Override.PSObject.Properties['EditionID']) { $Override.EditionID } else { 'Pro' }
		$archRaw = if ($Override.PSObject.Properties['Architecture']) { $Override.Architecture } else { 'amd64' }
		$displayRaw = if ($Override.PSObject.Properties['DisplayName']) { $Override.DisplayName } else { $null }

		[int]$major = [int]$majorRaw
		[int]$build = [int]$buildRaw
		[int]$ptype = [int]$ptypeRaw
		$isServer = $ptype -ne 1
		$isWin11 = (-not $isServer) -and $major -eq 10 -and $build -ge 22000
		$isWin10 = (-not $isServer) -and $major -eq 10 -and $build -lt 22000

		# Server release derivation: build-range based, mutually exclusive with
		# IsWindows10/IsWindows11. Allow tests to override directly.
		$serverReleaseRaw = if ($Override.PSObject.Properties['ServerRelease']) { $Override.ServerRelease } else { $null }
		$serverRelease = if ($null -ne $serverReleaseRaw -and -not [string]::IsNullOrWhiteSpace([string]$serverReleaseRaw)) {
			[string]$serverReleaseRaw
		} elseif ($isServer) {
			Get-BaselineServerReleaseFromBuild -BuildNumber $build
		} else {
			$null
		}

		$serverDisplay = if ($serverRelease) { 'Windows Server {0} (build {1})' -f $serverRelease, $build } else { 'Windows Server (build {0})' -f $build }
		$display = if ($displayRaw) { [string]$displayRaw } elseif ($isServer) { $serverDisplay } elseif ($isWin11) { ('Windows 11 {0} (build {1})' -f $editionRaw, $build) } else { ('Windows 10 {0} (build {1})' -f $editionRaw, $build) }

		return [pscustomobject]@{
			MajorVersion = $major
			BuildNumber = $build
			ProductType = $ptype
			IsServer = $isServer
			IsWindows10 = $isWin10
			IsWindows11 = $isWin11
			ServerRelease = $serverRelease
			EditionID = [string]$editionRaw
			Architecture = [string]$archRaw
			DisplayName = $display
		}
	}

	$osMajor = 10
	$osBuild = 0
	$osProductType = 1
	$edition = 'Pro'
	$arch = 'amd64'
	try
	{
		$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
		$verParts = ([string]$os.Version) -split '\.'
		if ($verParts.Length -ge 1) { $osMajor = [int]$verParts[0] }
		if ($verParts.Length -ge 3) { $osBuild = [int]$verParts[2] } else { $osBuild = [int]$os.BuildNumber }
		$osProductType = [int]$os.ProductType
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PlatformSupport.Helpers.Get-BaselineSystemPlatformInfo:catch247' -Severity Debug }

		$null = $_
	}

	try
	{
		$cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
		if ($cv.PSObject.Properties['EditionID']) { $edition = [string]$cv.EditionID }
		if ($cv.PSObject.Properties['CurrentBuildNumber'] -and $osBuild -eq 0) { $osBuild = [int]$cv.CurrentBuildNumber }
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PlatformSupport.Helpers.Get-BaselineSystemPlatformInfo:catch258' -Severity Debug }

		$null = $_
	}

	try
	{
		$archEnv = [System.Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
		if (-not [string]::IsNullOrWhiteSpace($archEnv))
		{
			switch -Regex ($archEnv)
			{
				'^(?i)amd64$' { $arch = 'amd64'; break }
				'^(?i)arm64$' { $arch = 'arm64'; break }
				'^(?i)x86$'   { $arch = 'x86';   break }
				default       { $arch = $archEnv.ToLowerInvariant() }
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PlatformSupport.Helpers.Get-BaselineSystemPlatformInfo:catch277' -Severity Debug }

		$null = $_
	}

	$isServer = $osProductType -ne 1
	$isWin11 = (-not $isServer) -and $osMajor -eq 10 -and $osBuild -ge 22000
	$isWin10 = (-not $isServer) -and $osMajor -eq 10 -and $osBuild -lt 22000
	$serverRelease = if ($isServer) { Get-BaselineServerReleaseFromBuild -BuildNumber $osBuild } else { $null }
	$serverDisplay = if ($serverRelease) { 'Windows Server {0} (build {1})' -f $serverRelease, $osBuild } else { 'Windows Server (build {0})' -f $osBuild }
	$display = if ($isServer) { $serverDisplay } elseif ($isWin11) { ('Windows 11 {0} (build {1})' -f $edition, $osBuild) } else { ('Windows 10 {0} (build {1})' -f $edition, $osBuild) }

	return [pscustomobject]@{
		MajorVersion = $osMajor
		BuildNumber = $osBuild
		ProductType = $osProductType
		IsServer = $isServer
		IsWindows10 = $isWin10
		IsWindows11 = $isWin11
		ServerRelease = $serverRelease
		EditionID = $edition
		Architecture = $arch
		DisplayName = $display
	}
}

<#
    .SYNOPSIS
#>

function ConvertTo-BaselinePlatformLabel
{
	<#
		.SYNOPSIS
		Resolves a `PlatformSupport` block into the project's standard label
		vocabulary so manifests + GUI badges + tests speak the same language:
		`Shared`, `Windows10Only`, `Windows11Only`, `ClientOnly`, `ServerOnly`,
		`Unsupported`. Returns `Unknown` if the block is missing or
		uninterpretable (caller decides whether that means available or not).
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter()]
		[AllowNull()]
		[object]$PlatformSupport
	)

	if (-not $PlatformSupport) { return 'Unknown' }

	$win10 = $true; $win11 = $true; $server = $true
	if (Test-BaselineEntryFieldPresent -Entry $PlatformSupport -Name 'Windows10') { $win10 = [bool](Get-BaselineEntryFieldValue -Entry $PlatformSupport -Name 'Windows10') }
	if (Test-BaselineEntryFieldPresent -Entry $PlatformSupport -Name 'Windows11') { $win11 = [bool](Get-BaselineEntryFieldValue -Entry $PlatformSupport -Name 'Windows11') }
	if (Test-BaselineEntryFieldPresent -Entry $PlatformSupport -Name 'Server')
	{
		$serverRaw = Get-BaselineEntryFieldValue -Entry $PlatformSupport -Name 'Server'
		# Array form (["Server2022","Server2025"]): label as supporting Server
		# at all if the list is non-empty. Granular release filtering happens
		# at runtime evaluation, not in the badge label.
		if ($serverRaw -is [System.Collections.IEnumerable] -and -not ($serverRaw -is [string]))
		{
			$server = (@($serverRaw).Count -gt 0)
		}
		else
		{
			$server = [bool]$serverRaw
		}
	}

	if (-not $win10 -and -not $win11 -and -not $server) { return 'Unsupported' }
	if ($win10 -and $win11 -and $server) { return 'Shared' }
	if ($win10 -and $win11 -and -not $server) { return 'ClientOnly' }
	if (-not $win10 -and -not $win11 -and $server) { return 'ServerOnly' }
	if ($win10 -and -not $win11 -and -not $server) { return 'Windows10Only' }
	if (-not $win10 -and $win11 -and -not $server) { return 'Windows11Only' }
	return 'Mixed'
}

<#
    .SYNOPSIS
#>

function Test-BaselineEntrySupportsExecution
{
	<#
		.SYNOPSIS
		Returns whether a manifest entry's underlying function can actually run
		on this host — independent of PlatformSupport (visibility).

		.DESCRIPTION
		For AppsCategory entries (and any other manifest entry that opts in)
		`SupportsExecution` is the execution gate that runs alongside the
		availability gate. Concept:
		  - PlatformSupport answers "should this entry be visible/selectable?"
		  - SupportsExecution answers "if selected, can the function run?"
		An entry can be available (visible) but non-executable (e.g., the
		underlying Appx removal would no-op because the package isn't there).
		Missing field defaults to $true — entries without an explicit claim
		are presumed executable so legacy manifests keep working without a
		field-by-field sweep.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry
	)

	if ($null -eq $Entry) { return $true }
	if (-not (Test-BaselineEntryFieldPresent -Entry $Entry -Name 'SupportsExecution')) { return $true }

	$value = Get-BaselineEntryFieldValue -Entry $Entry -Name 'SupportsExecution'
	if ($null -eq $value) { return $true }
	return [bool]$value
}

<#
    .SYNOPSIS
#>

function Get-BaselineEntrySupportsExecutionReason
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry
	)

	if ($null -eq $Entry) { return $null }
	if (-not (Test-BaselineEntryFieldPresent -Entry $Entry -Name 'SupportsExecutionReason')) { return $null }

	$reason = Get-BaselineEntryFieldValue -Entry $Entry -Name 'SupportsExecutionReason'
	if ([string]::IsNullOrWhiteSpace([string]$reason))
	{
		return $null
	}

	return [string]$reason
}

<#
    .SYNOPSIS
#>

function Set-BaselineDefenderExecutionAvailability
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[bool]$Available,

		[Parameter(Mandatory = $false)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$UnavailableReason = $null
	)

	$Script:CachedBaselineDefenderExecutionAvailable = [bool]$Available
	$Script:CachedBaselineDefenderExecutionUnavailableReason = if ($Available) { $null } else { [string]$UnavailableReason }
}

<#
    .SYNOPSIS
#>

function Set-BaselineDefenderComponentAvailability
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[bool]$Available,

		[Parameter(Mandatory = $false)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$UnavailableReason = $null
	)

	$Script:CachedBaselineDefenderComponentAvailable = [bool]$Available
	$Script:CachedBaselineDefenderComponentUnavailableReason = if ($Available) { $null } else { [string]$UnavailableReason }
}

<#
    .SYNOPSIS
#>

function Reset-BaselineDefenderExecutionAvailability
{
	[CmdletBinding()]
	param ()

	$Script:CachedBaselineDefenderExecutionAvailable = $null
	$Script:CachedBaselineDefenderExecutionUnavailableReason = $null
	$Script:CachedBaselineDefenderComponentAvailable = $null
	$Script:CachedBaselineDefenderComponentUnavailableReason = $null
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineDefenderExecutionAvailability
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param ()

	$setMpPreference = Get-Command -Name 'Set-MpPreference' -CommandType Function,Cmdlet -ErrorAction SilentlyContinue
	if ($setMpPreference)
	{
		return [pscustomobject]@{
			Available = $true
			Reason = ''
		}
	}

	return [pscustomobject]@{
		Available = $false
		Reason = 'Microsoft Defender PowerShell command Set-MpPreference is not available on this system.'
	}
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineDefenderComponentAvailability
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param ()

	$winDefendService = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue
	if ($winDefendService)
	{
		return [pscustomobject]@{
			Available = $true
			Reason = ''
		}
	}

	$mpCmdRunPath = Join-Path -Path $env:ProgramFiles -ChildPath 'Windows Defender\MpCmdRun.exe'
	if (Test-Path -LiteralPath $mpCmdRunPath)
	{
		return [pscustomobject]@{
			Available = $true
			Reason = ''
		}
	}

	return [pscustomobject]@{
		Available = $false
		Reason = 'Microsoft Defender Antivirus service and command-line scanner were not found on this system.'
	}
}

<#
    .SYNOPSIS
#>

function Test-BaselineDefenderExecutionAvailable
{
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	if ($null -ne $Script:CachedBaselineDefenderExecutionAvailable)
	{
		return [bool]$Script:CachedBaselineDefenderExecutionAvailable
	}

	$availability = Resolve-BaselineDefenderExecutionAvailability
	Set-BaselineDefenderExecutionAvailability -Available ([bool]$availability.Available) -UnavailableReason ([string]$availability.Reason)
	return [bool]$Script:CachedBaselineDefenderExecutionAvailable
}

<#
    .SYNOPSIS
#>

function Get-BaselineDefenderExecutionUnavailableReason
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	if ($null -eq $Script:CachedBaselineDefenderExecutionAvailable)
	{
		[void](Test-BaselineDefenderExecutionAvailable)
	}

	if ([bool]$Script:CachedBaselineDefenderExecutionAvailable)
	{
		return ''
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$Script:CachedBaselineDefenderExecutionUnavailableReason))
	{
		return [string]$Script:CachedBaselineDefenderExecutionUnavailableReason
	}

	return 'Microsoft Defender PowerShell command surface is not available on this system.'
}

<#
    .SYNOPSIS
#>

function Test-BaselineDefenderComponentAvailable
{
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	if ($null -ne $Script:CachedBaselineDefenderComponentAvailable)
	{
		return [bool]$Script:CachedBaselineDefenderComponentAvailable
	}

	$availability = Resolve-BaselineDefenderComponentAvailability
	Set-BaselineDefenderComponentAvailability -Available ([bool]$availability.Available) -UnavailableReason ([string]$availability.Reason)
	return [bool]$Script:CachedBaselineDefenderComponentAvailable
}

<#
    .SYNOPSIS
#>

function Get-BaselineDefenderComponentUnavailableReason
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	if ($null -eq $Script:CachedBaselineDefenderComponentAvailable)
	{
		[void](Test-BaselineDefenderComponentAvailable)
	}

	if ([bool]$Script:CachedBaselineDefenderComponentAvailable)
	{
		return ''
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$Script:CachedBaselineDefenderComponentUnavailableReason))
	{
		return [string]$Script:CachedBaselineDefenderComponentUnavailableReason
	}

	return 'Microsoft Defender components are not available on this system.'
}

<#
    .SYNOPSIS
#>

function Get-BaselineEntryExecutionSupport
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry
	)

	$result = [ordered]@{
		SupportsExecution = $true
		Reason = ''
	}

	if ($null -eq $Entry)
	{
		return [pscustomobject]$result
	}

	if (Test-BaselineEntryFieldPresent -Entry $Entry -Name 'SupportsExecution')
	{
		$result.SupportsExecution = Test-BaselineEntrySupportsExecution -Entry $Entry
		if (-not $result.SupportsExecution)
		{
			$reason = Get-BaselineEntrySupportsExecutionReason -Entry $Entry
			$result.Reason = if ([string]::IsNullOrWhiteSpace([string]$reason)) { 'Execution not supported on this system.' } else { [string]$reason }
		}
		return [pscustomobject]$result
	}

	$functionName = if (Test-BaselineEntryFieldPresent -Entry $Entry -Name 'Function')
	{
		[string](Get-BaselineEntryFieldValue -Entry $Entry -Name 'Function')
	}
	else
	{
		$null
	}

	if ([string]::IsNullOrWhiteSpace([string]$functionName))
	{
		return [pscustomobject]$result
	}

	$requiresPowerSchemeSetting = @{
		IntelGraphicsPowerPlan = @{
			SubgroupGuid = '44f3beca-a7c0-460e-9df2-bb8b99e0cba6'
			SettingGuid  = '3619c3f2-afb2-4afc-b0e9-e7fef372de36'
			Reason       = 'The Intel integrated graphics power setting is not available on this system.'
		}
		USBHubSelectiveSuspendTimeout = @{
			SubgroupGuid = '2a737441-1930-4402-8d77-b2bebba308a3'
			SettingGuid  = '0853a681-27c8-4100-a2fd-82013e970683'
			Reason       = 'The USB hub selective suspend timeout power setting is not available on this system.'
		}
	}

	if ($requiresPowerSchemeSetting.ContainsKey($functionName))
	{
		$settingRequirement = $requiresPowerSchemeSetting[$functionName]
		if (-not (Test-BaselinePowerSchemeSettingAvailable -SubgroupGuid ([string]$settingRequirement.SubgroupGuid) -SettingGuid ([string]$settingRequirement.SettingGuid)))
		{
			$result.SupportsExecution = $false
			$result.Reason = [string]$settingRequirement.Reason
		}
		return [pscustomobject]$result
	}

	$requiresAppxPackage = @{
		TaskbarWidgets = @{
			Name = 'MicrosoftWindows.Client.WebExperience'
			Reason = 'Widgets requires the Windows Web Experience Pack to be installed.'
		}
		CortanaAutostart = @{
			Name = 'Microsoft.549981C3F5F10'
			Reason = 'Cortana is not installed on this system.'
		}
		EditWithClipchampContext = @{
			Name = 'Clipchamp.Clipchamp'
			Reason = 'Clipchamp is not installed on this system.'
		}
		OpenWindowsTerminalAdminContext = @{
			Name = 'Microsoft.WindowsTerminal'
			Reason = 'Windows Terminal is not installed on this system.'
		}
	}

	if ($requiresAppxPackage.ContainsKey($functionName))
	{
		$packageRequirement = $requiresAppxPackage[$functionName]
		if (Get-Command -Name 'Initialize-BaselineWinRtRuntimeDependencies' -CommandType Function -ErrorAction SilentlyContinue)
		{
			[void](Initialize-BaselineWinRtRuntimeDependencies)
		}

		$package = $null
		$packageQueryFailed = $false
		try
		{
			$package = Get-AppxPackage -Name ([string]$packageRequirement.Name) -ErrorAction Stop -WarningAction SilentlyContinue | Select-Object -First 1
		}
		catch
		{
			$packageQueryFailed = $true
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'PlatformSupport.Helpers.Get-BaselineEntryExecutionSupport.AppxPackageProbe' -Severity Debug
			}
		}

		if (-not $package -and -not $packageQueryFailed)
		{
			$result.SupportsExecution = $false
			$result.Reason = [string]$packageRequirement.Reason
		}
		return [pscustomobject]$result
	}

	$defenderComponentBackedFunctions = @(
		'DefenderSandbox'
	)
	if ($functionName -in $defenderComponentBackedFunctions)
	{
		if (-not (Test-BaselineDefenderComponentAvailable))
		{
			$result.SupportsExecution = $false
			$result.Reason = Get-BaselineDefenderComponentUnavailableReason
		}
		return [pscustomobject]$result
	}

	$defenderPreferenceBackedFunctions = @(
		'DefenderScanCPULimit'
		'DefenderSignatureUpdateInterval'
		'NetworkProtection'
		'PUAppsDetection'
	)
	if ($functionName -in $defenderPreferenceBackedFunctions)
	{
		if (-not (Test-BaselineDefenderExecutionAvailable))
		{
			$result.SupportsExecution = $false
			$result.Reason = Get-BaselineDefenderExecutionUnavailableReason
		}
		return [pscustomobject]$result
	}

	if ($functionName -eq 'NetworkAdaptersSavePower')
	{
		try
		{
			$adapters = @(
				Get-NetAdapter -Physical -ErrorAction Stop |
					Where-Object -FilterScript { $_.MacAddress } |
					Get-NetAdapterPowerManagement -ErrorAction Stop |
					Where-Object -FilterScript { $_.AllowComputerToTurnOffDevice -ne 'Unsupported' }
			)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PlatformSupport.Helpers.Get-BaselineEntryExecutionSupport:catch776' -Severity Debug }

			$adapters = @()
		}

		if ($adapters.Count -eq 0)
		{
			$result.SupportsExecution = $false
			$result.Reason = 'No compatible physical network adapters are available on this system.'
		}

		return [pscustomobject]$result
	}

	return [pscustomobject]$result
}

<#
    .SYNOPSIS
#>

function Test-BaselinePowerSchemeSettingAvailable
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$SubgroupGuid,

		[Parameter(Mandatory)]
		[string]$SettingGuid
	)

	try
	{
		& powercfg /QUERY SCHEME_CURRENT $SubgroupGuid $SettingGuid 2>$null | Out-Null
		return ($LASTEXITCODE -eq 0)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PlatformSupport.Helpers.Test-BaselinePowerSchemeSettingAvailable:catch813' -Severity Debug }

		Remove-HandledErrorRecord -ErrorRecord $_
		return $false
	}
}

<#
    .SYNOPSIS
#>

function Test-BaselineEntryAvailable
{
	<#
		.SYNOPSIS
		Returns whether a manifest entry is available on the supplied system,
		plus a reason string explaining why if not.

		.DESCRIPTION
		Mirrors the spec in todo.md (OS support matrix → "Runtime evaluator")
		but with three deliberate semantics fixes:
		  1. A missing PlatformSupport block defaults to Available=$true
		     (we never hide an entry just because metadata wasn't authored).
		  2. The MinBuild / MaxBuild gates run AFTER the per-OS gates so the
		     reason is more specific ("Only available on Win11" beats
		     "Requires build 22000+").
		  3. The reason is always populated when Available=$false — never
		     null — so the GUI badge has something to render.

		Returns:
		  Available : [bool]
		  Reason    : [string]   ("" when Available=$true)
		  Source    : [string]   one of:
		                'NoPlatformMetadata' / 'PlatformSupport' /
		                'MinBuild' / 'MaxBuild' / 'Architecture'
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[object]$Entry,

		[Parameter(Mandatory)]
		[object]$SystemInfo
	)

	$support = Get-BaselineEntryFieldValue -Entry $Entry -Name 'PlatformSupport'

	if (-not $support)
	{
		return [pscustomobject]@{
			Available = $true
			Reason = ''
			Source = 'NoPlatformMetadata'
		}
	}

	$isServer = [bool]$SystemInfo.IsServer
	$isWin10 = [bool]$SystemInfo.IsWindows10
	$isWin11 = [bool]$SystemInfo.IsWindows11
	[int]$build = [int]$SystemInfo.BuildNumber

	$customReasonRaw = Get-BaselineEntryFieldValue -Entry $support -Name 'UnavailableReason'
	$customReason = if ($null -ne $customReasonRaw) { [string]$customReasonRaw } else { $null }

	$serverHas = Test-BaselineEntryFieldPresent -Entry $support -Name 'Server'
	$serverRaw = if ($serverHas) { Get-BaselineEntryFieldValue -Entry $support -Name 'Server' } else { $true }
	# Server may be bool (legacy) OR array of release tags (Server2019/2022/2025).
	# Treat array form as: "available on these releases only".
	$serverIsArray = $false
	$serverAllowedReleases = @()
	$serverVal = $true
	if ($serverHas)
	{
		if ($serverRaw -is [System.Collections.IEnumerable] -and -not ($serverRaw -is [string]))
		{
			$serverIsArray = $true
			$serverAllowedReleases = @($serverRaw | ForEach-Object { [string]$_ })
			$serverVal = ($serverAllowedReleases.Count -gt 0)
		}
		else
		{
			$serverVal = [bool]$serverRaw
		}
	}
	$win10Has = Test-BaselineEntryFieldPresent -Entry $support -Name 'Windows10'
	$win10Val = if ($win10Has) { [bool](Get-BaselineEntryFieldValue -Entry $support -Name 'Windows10') } else { $true }
	$win11Has = Test-BaselineEntryFieldPresent -Entry $support -Name 'Windows11'
	$win11Val = if ($win11Has) { [bool](Get-BaselineEntryFieldValue -Entry $support -Name 'Windows11') } else { $true }

	if ($isServer -and $serverHas -and -not $serverVal)
	{
		$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Not available on Windows Server.' } else { $customReason }
		return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
	}
	elseif ($isServer -and $serverIsArray)
	{
		$currentRelease = if ($SystemInfo.PSObject.Properties['ServerRelease']) { [string]$SystemInfo.ServerRelease } else { '' }
		if ([string]::IsNullOrWhiteSpace($currentRelease) -or ($serverAllowedReleases -notcontains $currentRelease))
		{
			$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Only available on Windows Server releases: {0}.' -f ($serverAllowedReleases -join ', ') } else { $customReason }
			return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
		}
	}
	elseif ($isWin10 -and $win10Has -and -not $win10Val)
	{
		$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Not available on Windows 10.' } else { $customReason }
		return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
	}
	elseif ($isWin11 -and $win11Has -and -not $win11Val)
	{
		$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Not available on Windows 11.' } else { $customReason }
		return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
	}

	$minBuildRaw = Get-BaselineEntryFieldValue -Entry $support -Name 'MinBuild'
	if ($minBuildRaw)
	{
		[int]$minBuild = [int]$minBuildRaw
		if ($build -lt $minBuild)
		{
			return [pscustomobject]@{
				Available = $false
				Reason = ('Requires Windows build {0} or newer.' -f $minBuild)
				Source = 'MinBuild'
			}
		}
	}

	$maxBuildRaw = Get-BaselineEntryFieldValue -Entry $support -Name 'MaxBuild'
	if ($maxBuildRaw)
	{
		[int]$maxBuild = [int]$maxBuildRaw
		if ($build -gt $maxBuild)
		{
			return [pscustomobject]@{
				Available = $false
				Reason = ('Only available up to Windows build {0}.' -f $maxBuild)
				Source = 'MaxBuild'
			}
		}
	}

	$archesRaw = Get-BaselineEntryFieldValue -Entry $support -Name 'Architectures'
	if ($archesRaw)
	{
		$allowed = @($archesRaw | ForEach-Object { [string]$_ })
		if ($allowed.Count -gt 0 -and ($allowed -notcontains [string]$SystemInfo.Architecture))
		{
			return [pscustomobject]@{
				Available = $false
				Reason = ('Only available on architectures: {0}.' -f ($allowed -join ', '))
				Source = 'Architecture'
			}
		}
	}

	return [pscustomobject]@{ Available = $true; Reason = ''; Source = 'PlatformSupport' }
}

<#
    .SYNOPSIS
#>

function Get-BaselineEntryAvailabilitySummary
{
	<#
		.SYNOPSIS
		Walks an array of manifest entries against a SystemInfo and returns
		the counts the GUI / preset run reports show ("Selected: 40 /
		Available: 35 / Skipped as unavailable: 5"), plus the per-entry
		availability records so callers don't have to re-evaluate.

		.DESCRIPTION
		Pure function — no I/O, no side effects. Caller supplies entries +
		SystemInfo, gets back the counts and the per-entry records keyed by
		whatever Id-like field each entry already has. We probe Id, Name,
		FunctionName in that order so the helper works for both tweak rows
		(Id) and preset command lines (Name / FunctionName).
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Entries,

		[Parameter(Mandatory)]
		[object]$SystemInfo
	)

	$total = 0
	$available = 0
	$skipped = 0
	$records = [System.Collections.Generic.List[pscustomobject]]::new()

	if ($Entries)
	{
		foreach ($entry in $Entries)
		{
			if (-not $entry) { continue }
			$total++
			$result = Test-BaselineEntryAvailable -Entry $entry -SystemInfo $SystemInfo
			if ($result.Available) { $available++ } else { $skipped++ }

			$id = $null
			foreach ($candidate in @('Id', 'Name', 'FunctionName'))
			{
				if (Test-BaselineEntryFieldPresent -Entry $entry -Name $candidate)
				{
					$id = [string](Get-BaselineEntryFieldValue -Entry $entry -Name $candidate)
					break
				}
			}

			$records.Add([pscustomobject]@{
				Id = $id
				Available = $result.Available
				Reason = $result.Reason
				Source = $result.Source
			})
		}
	}

	return [pscustomobject]@{
		Total = $total
		Available = $available
		Skipped = $skipped
		Entries = @($records)
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselinePlatformFilterOverride
{
	<#
		.SYNOPSIS
		Translates a GUI Platform-filter selection into the synthetic override
		hashtable (or $null) consumed by Get-BaselineSystemPlatformInfo.

		.DESCRIPTION
		The toolbar offers five preview modes — `All`, `Windows10`, `Windows11`,
		`Server`, `ThisDevice`. Returning a single contract here keeps the GUI
		handler thin (it just calls Get-BaselineSystemPlatformInfo with the
		result) and gives the unit tests one place to assert the synthetic OS
		readings each mode produces.

		Mapping:
		  AllSupported — no override + special-case re-stamp via
		                 Set-BaselineManifestAllAvailable. The cleanest way
		                 to express "show every supported entry" without a
		                 multi-headed SystemInfo is to skip the per-entry
		                 evaluator and force-flip Availability=$true.
		  Windows10    — Win10 22H2 client (build 19045, Pro)
		  Windows11    — Win11 24H2 client (build 26100, Pro)
		  Server       — Server 2025 (build 26100, ServerStandard)
		  ThisDevice   — $null (caller falls back to real Get-Baseline
		                 SystemPlatformInfo with no override)

		Returns a hashtable with keys 'Mode' and 'Override'. Mode is one of:
		'AllSupported' / 'Windows10' / 'Windows11' / 'Server' / 'ThisDevice'.
		Unknown filter values fall back to ThisDevice.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Filter
	)

	$normalized = if ([string]::IsNullOrWhiteSpace($Filter)) { 'ThisDevice' } else { $Filter.Trim() }
	switch -Regex ($normalized)
	{
		'^(?i)All(Supported)?$'    { return @{ Mode = 'AllSupported'; Override = $null } }
		'^(?i)Win(dows)?10$'       { return @{ Mode = 'Windows10';   Override = @{ MajorVersion = 10; BuildNumber = 19045; ProductType = 1; EditionID = 'Professional'; Architecture = 'amd64' } } }
		'^(?i)Win(dows)?11$'       { return @{ Mode = 'Windows11';   Override = @{ MajorVersion = 10; BuildNumber = 26100; ProductType = 1; EditionID = 'Professional'; Architecture = 'amd64' } } }
		'^(?i)Server$'             { return @{ Mode = 'Server';      Override = @{ MajorVersion = 10; BuildNumber = 26100; ProductType = 3; EditionID = 'ServerStandard'; Architecture = 'amd64'; ServerRelease = 'Server2025' } } }
		'^(?i)This(Device)?$'      { return @{ Mode = 'ThisDevice';  Override = $null } }
		default                    { return @{ Mode = 'ThisDevice';  Override = $null } }
	}
}

<#
    .SYNOPSIS
#>

function Set-BaselineManifestAllAvailable
{
	<#
		.SYNOPSIS
		Stamps Availability=$true on every entry of a loaded manifest. Used
		by the GUI's "All supported" Platform-filter mode where no synthetic
		OS can simultaneously satisfy Windows10-only, Windows11-only, and
		Server-only entries via Test-BaselineEntryAvailable. Re-uses the same
		Availability block shape Update-BaselineManifestAvailability produces
		so downstream consumers don't have to special-case the Source/Reason.
	#>
	[CmdletBinding()]
	[OutputType([object])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Manifest
	)

	if ($null -eq $Manifest) { return $Manifest }

	$entries = @()
	if ($Manifest -is [System.Collections.IDictionary])
	{
		foreach ($key in @($Manifest.Keys))
		{
			$bucket = $Manifest[$key]
			if ($null -eq $bucket) { continue }
			if ($bucket -is [System.Collections.IEnumerable] -and -not ($bucket -is [string]))
			{
				foreach ($e in $bucket) { if ($e) { $entries += , $e } }
			}
			else { $entries += , $bucket }
		}
	}
	elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Entries']) { $entries = @($Manifest.Entries) }
	elseif ($Manifest -is [System.Collections.IEnumerable] -and -not ($Manifest -is [string])) { $entries = @($Manifest) }
	else { $entries = @($Manifest) }

	foreach ($entry in $entries)
	{
		if ($null -eq $entry) { continue }
		$support = Get-BaselineEntryFieldValue -Entry $entry -Name 'PlatformSupport'
		$label = ConvertTo-BaselinePlatformLabel -PlatformSupport $support
		$availability = [pscustomobject]@{
			Available = $true
			Reason    = ''
			Source    = 'PlatformFilterAllSupported'
			Label     = [string]$label
		}
		if ($entry -is [System.Collections.IDictionary]) { $entry['Availability'] = $availability }
		else { Add-Member -InputObject $entry -NotePropertyName 'Availability' -NotePropertyValue $availability -Force }
	}
	return $Manifest
}

function ConvertTo-BaselinePlatformLabelFromDictionary
{
	param (
		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$PlatformSupport
	)

	if (-not $PlatformSupport) { return 'Unknown' }

	$win10 = $true
	$win11 = $true
	$server = $true
	if ($PlatformSupport.Contains('Windows10')) { $win10 = [bool]$PlatformSupport['Windows10'] }
	if ($PlatformSupport.Contains('Windows11')) { $win11 = [bool]$PlatformSupport['Windows11'] }
	if ($PlatformSupport.Contains('Server'))
	{
		$serverRaw = $PlatformSupport['Server']
		if ($serverRaw -is [System.Collections.IEnumerable] -and -not ($serverRaw -is [string]))
		{
			$server = (@($serverRaw).Count -gt 0)
		}
		else
		{
			$server = [bool]$serverRaw
		}
	}

	if (-not $win10 -and -not $win11 -and -not $server) { return 'Unsupported' }
	if ($win10 -and $win11 -and $server) { return 'Shared' }
	if ($win10 -and $win11 -and -not $server) { return 'ClientOnly' }
	if (-not $win10 -and -not $win11 -and $server) { return 'ServerOnly' }
	if ($win10 -and -not $win11 -and -not $server) { return 'Windows10Only' }
	if (-not $win10 -and $win11 -and -not $server) { return 'Windows11Only' }
	return 'Mixed'
}

function Test-BaselineDictionaryPlatformSupportAvailable
{
	param (
		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$PlatformSupport,

		[Parameter(Mandatory)]
		[object]$SystemInfo
	)

	if (-not $PlatformSupport)
	{
		return [pscustomobject]@{ Available = $true; Reason = ''; Source = 'NoPlatformMetadata' }
	}

	$isServer = [bool]$SystemInfo.IsServer
	$isWin10 = [bool]$SystemInfo.IsWindows10
	$isWin11 = [bool]$SystemInfo.IsWindows11
	[int]$build = [int]$SystemInfo.BuildNumber

	$customReasonRaw = if ($PlatformSupport.Contains('UnavailableReason')) { $PlatformSupport['UnavailableReason'] } else { $null }
	$customReason = if ($null -ne $customReasonRaw) { [string]$customReasonRaw } else { $null }

	$serverHas = $PlatformSupport.Contains('Server')
	$serverRaw = if ($serverHas) { $PlatformSupport['Server'] } else { $true }
	$serverIsArray = $false
	$serverAllowedReleases = @()
	$serverVal = $true
	if ($serverHas)
	{
		if ($serverRaw -is [System.Collections.IEnumerable] -and -not ($serverRaw -is [string]))
		{
			$serverIsArray = $true
			$serverAllowedReleases = @($serverRaw | ForEach-Object { [string]$_ })
			$serverVal = ($serverAllowedReleases.Count -gt 0)
		}
		else
		{
			$serverVal = [bool]$serverRaw
		}
	}
	$win10Has = $PlatformSupport.Contains('Windows10')
	$win10Val = if ($win10Has) { [bool]$PlatformSupport['Windows10'] } else { $true }
	$win11Has = $PlatformSupport.Contains('Windows11')
	$win11Val = if ($win11Has) { [bool]$PlatformSupport['Windows11'] } else { $true }

	if ($isServer -and $serverHas -and -not $serverVal)
	{
		$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Not available on Windows Server.' } else { $customReason }
		return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
	}
	elseif ($isServer -and $serverIsArray)
	{
		$currentRelease = if ($SystemInfo.PSObject.Properties['ServerRelease']) { [string]$SystemInfo.ServerRelease } else { '' }
		if ([string]::IsNullOrWhiteSpace($currentRelease) -or ($serverAllowedReleases -notcontains $currentRelease))
		{
			$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Only available on Windows Server releases: {0}.' -f ($serverAllowedReleases -join ', ') } else { $customReason }
			return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
		}
	}
	elseif ($isWin10 -and $win10Has -and -not $win10Val)
	{
		$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Not available on Windows 10.' } else { $customReason }
		return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
	}
	elseif ($isWin11 -and $win11Has -and -not $win11Val)
	{
		$reason = if ([string]::IsNullOrWhiteSpace($customReason)) { 'Not available on Windows 11.' } else { $customReason }
		return [pscustomobject]@{ Available = $false; Reason = $reason; Source = 'PlatformSupport' }
	}

	$minBuildRaw = if ($PlatformSupport.Contains('MinBuild')) { $PlatformSupport['MinBuild'] } else { $null }
	if ($minBuildRaw)
	{
		[int]$minBuild = [int]$minBuildRaw
		if ($build -lt $minBuild)
		{
			return [pscustomobject]@{ Available = $false; Reason = ('Requires Windows build {0} or newer.' -f $minBuild); Source = 'MinBuild' }
		}
	}

	$maxBuildRaw = if ($PlatformSupport.Contains('MaxBuild')) { $PlatformSupport['MaxBuild'] } else { $null }
	if ($maxBuildRaw)
	{
		[int]$maxBuild = [int]$maxBuildRaw
		if ($build -gt $maxBuild)
		{
			return [pscustomobject]@{ Available = $false; Reason = ('Only available up to Windows build {0}.' -f $maxBuild); Source = 'MaxBuild' }
		}
	}

	$archesRaw = if ($PlatformSupport.Contains('Architectures')) { $PlatformSupport['Architectures'] } else { $null }
	if ($archesRaw)
	{
		$allowed = @($archesRaw | ForEach-Object { [string]$_ })
		if ($allowed.Count -gt 0 -and ($allowed -notcontains [string]$SystemInfo.Architecture))
		{
			return [pscustomobject]@{ Available = $false; Reason = ('Only available on architectures: {0}.' -f ($allowed -join ', ')); Source = 'Architecture' }
		}
	}

	return [pscustomobject]@{ Available = $true; Reason = ''; Source = 'PlatformSupport' }
}

<#
    .SYNOPSIS
#>

function Update-BaselineManifestAvailability
{
	<#
		.SYNOPSIS
		Walks a loaded manifest collection, evaluates each entry against the
		supplied SystemInfo via Test-BaselineEntryAvailable, and stamps an
		`Availability` block onto every entry in place. Used by the bootstrap
		right after manifest load so downstream GUI/preset code can read
		`$entry.Availability.Available` without re-evaluating.

		.DESCRIPTION
		Tolerates three input shapes — a bare array of entries, a manifest
		object exposing `.Entries`, or a hashtable of category→entries. For
		hashtable / dictionary entries we mutate the same dictionary instance
		so callers see the stamp. For pscustomobject entries we use
		Add-Member -Force so a re-stamp during a settings change overwrites
		cleanly. Returns the same input untouched (for pipeline ergonomics).

		The Availability block has the same shape as Test-BaselineEntryAvailable
		returns (Available / Reason / Source) plus a `Label` populated by
		ConvertTo-BaselinePlatformLabel for badge rendering.
	#>
	[CmdletBinding()]
	[OutputType([object])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Manifest,

		[Parameter(Mandatory)]
		[object]$SystemInfo
	)

	if ($null -eq $Manifest) { return $Manifest }

	$entries = @()
	if ($Manifest -is [System.Collections.IDictionary])
	{
		# Category -> entries hashtable (e.g. preset run map). Flatten.
		foreach ($key in @($Manifest.Keys))
		{
			$bucket = $Manifest[$key]
			if ($null -eq $bucket) { continue }
			if ($bucket -is [System.Collections.IEnumerable] -and -not ($bucket -is [string]))
			{
				foreach ($e in $bucket) { if ($e) { $entries += , $e } }
			}
			else
			{
				$entries += , $bucket
			}
		}
	}
	elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Entries'])
	{
		$entries = @($Manifest.Entries)
	}
	elseif ($Manifest -is [System.Collections.IEnumerable] -and -not ($Manifest -is [string]))
	{
		$entries = @($Manifest)
	}
	else
	{
		$entries = @($Manifest)
	}

	foreach ($entry in $entries)
	{
		if ($null -eq $entry) { continue }

		$support = $null
		$result = $null
		$label = $null
		if ($entry -is [System.Collections.IDictionary])
		{
			$support = if ($entry.Contains('PlatformSupport')) { $entry['PlatformSupport'] } else { $null }
			if ($support -is [System.Collections.IDictionary])
			{
				$result = Test-BaselineDictionaryPlatformSupportAvailable -PlatformSupport $support -SystemInfo $SystemInfo
				$label = ConvertTo-BaselinePlatformLabelFromDictionary -PlatformSupport $support
			}
		}

		if (-not $result)
		{
			$result = Test-BaselineEntryAvailable -Entry $entry -SystemInfo $SystemInfo
			$support = Get-BaselineEntryFieldValue -Entry $entry -Name 'PlatformSupport'
			$label = ConvertTo-BaselinePlatformLabel -PlatformSupport $support
		}

		$availability = [pscustomobject]@{
			Available = [bool]$result.Available
			Reason    = [string]$result.Reason
			Source    = [string]$result.Source
			Label     = [string]$label
		}

		if ($entry -is [System.Collections.IDictionary])
		{
			$entry['Availability'] = $availability
		}
		else
		{
			Add-Member -InputObject $entry -NotePropertyName 'Availability' -NotePropertyValue $availability -Force
		}
	}

	return $Manifest
}

<#
    .SYNOPSIS
#>

function Update-BaselineManifestExecutionSupport
{
	[CmdletBinding()]
	[OutputType([object])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Manifest
	)

	if ($null -eq $Manifest) { return $Manifest }

	$entries = @()
	if ($Manifest -is [System.Collections.IDictionary])
	{
		foreach ($key in @($Manifest.Keys))
		{
			$bucket = $Manifest[$key]
			if ($null -eq $bucket) { continue }
			if ($bucket -is [System.Collections.IEnumerable] -and -not ($bucket -is [string]))
			{
				foreach ($e in $bucket) { if ($e) { $entries += , $e } }
			}
			else
			{
				$entries += , $bucket
			}
		}
	}
	elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Entries'])
	{
		$entries = @($Manifest.Entries)
	}
	elseif ($Manifest -is [System.Collections.IEnumerable] -and -not ($Manifest -is [string]))
	{
		$entries = @($Manifest)
	}
	else
	{
		$entries = @($Manifest)
	}

	foreach ($entry in $entries)
	{
		if ($null -eq $entry) { continue }

		$support = Get-BaselineEntryExecutionSupport -Entry $entry
		if ($entry -is [System.Collections.IDictionary])
		{
			$entry['SupportsExecution'] = [bool]$support.SupportsExecution
			if ([string]::IsNullOrWhiteSpace([string]$support.Reason))
			{
				if ($entry.Contains('SupportsExecutionReason'))
				{
					$entry.Remove('SupportsExecutionReason') | Out-Null
				}
			}
			else
			{
				$entry['SupportsExecutionReason'] = [string]$support.Reason
			}
		}
		else
		{
			Add-Member -InputObject $entry -NotePropertyName 'SupportsExecution' -NotePropertyValue ([bool]$support.SupportsExecution) -Force
			if ([string]::IsNullOrWhiteSpace([string]$support.Reason))
			{
				Add-Member -InputObject $entry -NotePropertyName 'SupportsExecutionReason' -NotePropertyValue $null -Force
			}
			else
			{
				Add-Member -InputObject $entry -NotePropertyName 'SupportsExecutionReason' -NotePropertyValue ([string]$support.Reason) -Force
			}
		}
	}

	return $Manifest
}
