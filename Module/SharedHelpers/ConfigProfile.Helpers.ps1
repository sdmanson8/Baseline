# Configuration profile helpers for Baseline.
# Provides portable configuration profile creation, import/export, compatibility
# checking, comparison, and conversion from existing presets.
# Uses Write-BaselineDocument / Read-BaselineDocument patterns for persistence.

$Script:ConfigProfileSchema = 'Baseline.ConfigProfile'
$Script:ConfigProfileSchemaVersion = 3

function Write-ConfigProfileDebugSwallowedException
{
	param (
		[Parameter(Mandatory)]
		[System.Management.Automation.ErrorRecord]$ErrorRecord,

		[Parameter(Mandatory)]
		[string]$Source
	)

	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Write-SwallowedException -ErrorRecord $ErrorRecord -Source $Source
		return
	}

	Write-Verbose ("{0}: {1}" -f $Source, $ErrorRecord.Exception.Message)
}

<#
    .SYNOPSIS
#>

function ConvertTo-ConfigurationProfileValueText
{
	[CmdletBinding()]
	param ([object]$Value)

	if ($null -eq $Value)
	{
		return $null
	}

	if ($Value -is [string])
	{
		return [string]$Value
	}

	if ($Value -is [bool] -or $Value -is [ValueType])
	{
		return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
	}

	if ($Value -is [System.Collections.IDictionary])
	{
		if ($Value.Contains('ACValue') -or $Value.Contains('DCValue'))
		{
			$acValue = if ($Value.Contains('ACValue')) { $Value['ACValue'] } else { $null }
			$dcValue = if ($Value.Contains('DCValue')) { $Value['DCValue'] } else { $null }
			$acText = if ($null -ne $acValue) { ConvertTo-ConfigurationProfileValueText -Value $acValue } else { $null }
			$dcText = if ($null -ne $dcValue) { ConvertTo-ConfigurationProfileValueText -Value $dcValue } else { $null }

			if (-not [string]::IsNullOrWhiteSpace([string]$acText) -and -not [string]::IsNullOrWhiteSpace([string]$dcText))
			{
				if ([string]$acText -eq [string]$dcText)
				{
					return [string]$acText
				}

				return ('AC={0};DC={1}' -f [string]$acText, [string]$dcText)
			}

			if (-not [string]::IsNullOrWhiteSpace([string]$acText))
			{
				return ('AC={0}' -f [string]$acText)
			}

			if (-not [string]::IsNullOrWhiteSpace([string]$dcText))
			{
				return ('DC={0}' -f [string]$dcText)
			}
		}

		if ($Value.Contains('Value'))
		{
			return ConvertTo-ConfigurationProfileValueText -Value $Value['Value']
		}
		if ($Value.Contains('SelectedValue'))
		{
			return ConvertTo-ConfigurationProfileValueText -Value $Value['SelectedValue']
		}
		if ($Value.Contains('NumericValue'))
		{
			return ConvertTo-ConfigurationProfileValueText -Value $Value['NumericValue']
		}

		return ([string]($Value | ConvertTo-Json -Depth 8 -Compress))
	}

	if ($Value -is [pscustomobject])
	{
		if ($Value.PSObject.Properties['ACValue'] -or $Value.PSObject.Properties['DCValue'])
		{
			$acValue = if ($Value.PSObject.Properties['ACValue']) { $Value.ACValue } else { $null }
			$dcValue = if ($Value.PSObject.Properties['DCValue']) { $Value.DCValue } else { $null }
			$acText = if ($null -ne $acValue) { ConvertTo-ConfigurationProfileValueText -Value $acValue } else { $null }
			$dcText = if ($null -ne $dcValue) { ConvertTo-ConfigurationProfileValueText -Value $dcValue } else { $null }

			if (-not [string]::IsNullOrWhiteSpace([string]$acText) -and -not [string]::IsNullOrWhiteSpace([string]$dcText))
			{
				if ([string]$acText -eq [string]$dcText)
				{
					return [string]$acText
				}

				return ('AC={0};DC={1}' -f [string]$acText, [string]$dcText)
			}

			if (-not [string]::IsNullOrWhiteSpace([string]$acText))
			{
				return ('AC={0}' -f [string]$acText)
			}

			if (-not [string]::IsNullOrWhiteSpace([string]$dcText))
			{
				return ('DC={0}' -f [string]$dcText)
			}
		}

		foreach ($fieldName in @('Value', 'SelectedValue', 'NumericValue'))
		{
			if ($Value.PSObject.Properties[$fieldName] -and $null -ne $Value.$fieldName)
			{
				return ConvertTo-ConfigurationProfileValueText -Value $Value.$fieldName
			}
		}

		return ([string]($Value | ConvertTo-Json -Depth 8 -Compress))
	}

	return [string]$Value
}

<#
    .SYNOPSIS
#>

function New-ConfigurationProfile
{
	<#
		.SYNOPSIS
		Creates a new configuration profile object from the supplied selections.

		.DESCRIPTION
		Builds a portable profile envelope containing tweak entries, metadata, and
		target requirements for the current machine. The profile can be exported,
		imported on another machine, and compared with other profiles.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$Name,

		[Parameter(Mandatory)]
		[array]$Selections,

		[array]$AppActions = @(),

		[array]$UserApps = @(),

		[array]$IncludePaths = @(),

		[Parameter(Mandatory)]
		[string]$BaselineVersion,

		[string]$Description,

		[string]$AppsPackageSourcePreference
	)

	# Determine target requirements from the current machine.
	$minBuild = 22621
	$edition = 'Pro|Home|Enterprise'
	try
	{
		$versionData = Get-WindowsVersionData
		if ($versionData -and $versionData.CurrentBuild)
		{
			$parsedBuild = 0
			if ([int]::TryParse([string]$versionData.CurrentBuild, [ref]$parsedBuild) -and $parsedBuild -gt 0)
			{
				$minBuild = $parsedBuild
			}
		}
	}
	catch
	{
		Write-ConfigProfileDebugSwallowedException -ErrorRecord $_ -Source 'ConfigProfile.New-ConfigurationProfile.WindowsVersionData'
	}

	try
	{
		$currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
		if ($currentVersion -and $currentVersion.PSObject.Properties['EditionID'] -and -not [string]::IsNullOrWhiteSpace([string]$currentVersion.EditionID))
		{
			$edition = [string]$currentVersion.EditionID
		}
	}
	catch
	{
		Write-ConfigProfileDebugSwallowedException -ErrorRecord $_ -Source 'ConfigProfile.New-ConfigurationProfile.CurrentVersion'
	}

	# Build normalized entry list from selections.
	$entries = [System.Collections.Generic.List[object]]::new()
	foreach ($selection in @($Selections))
	{
		if ($null -eq $selection) { continue }

		$functionName = $null
		$entryType = 'Toggle'
		$param = $null
		$category = $null
		$value = $null
		$runFlag = $null

		if ($selection -is [System.Collections.IDictionary])
		{
			$functionName = if ($selection.Contains('Function')) { [string]$selection['Function'] } else { $null }
			$entryType = if ($selection.Contains('Type')) { [string]$selection['Type'] } else { 'Toggle' }
			$param = if ($selection.Contains('ToggleParam')) { [string]$selection['ToggleParam'] }
						elseif ($selection.Contains('Selection')) { [string]$selection['Selection'] }
						else { $null }
			$category = if ($selection.Contains('Category')) { [string]$selection['Category'] } else { $null }
			$value = if ($selection.Contains('Value')) { $selection['Value'] } elseif ($selection.Contains('SelectedValue')) { $selection['SelectedValue'] } else { $null }
			$runFlag = if ($selection.Contains('Run')) { [bool]$selection['Run'] } else { $null }
		}
		elseif ($selection -is [pscustomobject] -or ($null -ne $selection.PSObject))
		{
			$functionName = if ($selection.PSObject.Properties['Function']) { [string]$selection.Function } else { $null }
			$entryType = if ($selection.PSObject.Properties['Type']) { [string]$selection.Type } else { 'Toggle' }
			$param = if ($selection.PSObject.Properties['ToggleParam']) { [string]$selection.ToggleParam }
						elseif ($selection.PSObject.Properties['Selection']) { [string]$selection.Selection }
						else { $null }
			$category = if ($selection.PSObject.Properties['Category']) { [string]$selection.Category } else { $null }
			$value = if ($selection.PSObject.Properties['Value']) { $selection.Value } elseif ($selection.PSObject.Properties['SelectedValue']) { $selection.SelectedValue } else { $null }
			$runFlag = if ($selection.PSObject.Properties['Run']) { [bool]$selection.Run } elseif ($selection.PSObject.Properties['State']) { ([string]$selection.State -match '^(?i:on|true|1)$') } else { $null }
		}

		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		$entry = [ordered]@{
			Function = $functionName
			Type     = $entryType
		}

		switch ($entryType)
		{
			'Choice'
			{
				$entry.Value = $value
				$entry.Category = $category
			}
			'NumericRange'
			{
				$entry.Value = $value
				$entry.Category = $category
				if ($selection -is [System.Collections.IDictionary])
				{
					foreach ($fieldName in @('NumericValue', 'ACValue', 'DCValue', 'Units'))
					{
						if ($selection.Contains($fieldName))
						{
							$entry[$fieldName] = $selection[$fieldName]
						}
					}
				}
				elseif ($selection -is [pscustomobject] -or ($null -ne $selection.PSObject))
				{
					foreach ($fieldName in @('NumericValue', 'ACValue', 'DCValue', 'Units'))
					{
						if ($selection.PSObject.Properties[$fieldName])
						{
							$entry[$fieldName] = $selection.$fieldName
						}
					}
				}
			}
			'Date'
			{
				$entry.Run = if ($null -eq $runFlag) { [bool]$value } else { [bool]$runFlag }
				$entry.Value = $value
				$entry.Category = $category
				if ($selection -is [System.Collections.IDictionary] -and $selection.Contains('DateParam'))
				{
					$entry.DateParam = [string]$selection['DateParam']
				}
				elseif ($selection -is [pscustomobject] -and $selection.PSObject.Properties['DateParam'])
				{
					$entry.DateParam = [string]$selection.DateParam
				}
			}
			default
			{
				$entry.Param = if (-not [string]::IsNullOrWhiteSpace($param)) { $param } else { $null }
				$entry.Category = $category
			}
		}

		$entries.Add($entry)
	}

	$appActionEntries = [System.Collections.Generic.List[object]]::new()
	foreach ($appAction in @($AppActions))
	{
		if ($null -eq $appAction) { continue }

		$appId = $null
		$action = $null
		$name = $null
		$winGetId = $null
		$chocoId = $null

		if ($appAction -is [System.Collections.IDictionary])
		{
			$appId = if ($appAction.Contains('AppId')) { [string]$appAction['AppId'] } elseif ($appAction.Contains('SelectionKey')) { [string]$appAction['SelectionKey'] } else { $null }
			$action = if ($appAction.Contains('Action')) { [string]$appAction['Action'] } else { $null }
			$name = if ($appAction.Contains('Name')) { [string]$appAction['Name'] } else { $null }
			$winGetId = if ($appAction.Contains('WinGetId')) { [string]$appAction['WinGetId'] } else { $null }
			$chocoId = if ($appAction.Contains('ChocoId')) { [string]$appAction['ChocoId'] } else { $null }
		}
		elseif ($appAction -is [pscustomobject] -or ($null -ne $appAction.PSObject))
		{
			$appId = if ($appAction.PSObject.Properties['AppId']) { [string]$appAction.AppId } elseif ($appAction.PSObject.Properties['SelectionKey']) { [string]$appAction.SelectionKey } else { $null }
			$action = if ($appAction.PSObject.Properties['Action']) { [string]$appAction.Action } else { $null }
			$name = if ($appAction.PSObject.Properties['Name']) { [string]$appAction.Name } else { $null }
			$winGetId = if ($appAction.PSObject.Properties['WinGetId']) { [string]$appAction.WinGetId } else { $null }
			$chocoId = if ($appAction.PSObject.Properties['ChocoId']) { [string]$appAction.ChocoId } else { $null }
		}

		if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($action))
		{
			continue
		}

		$normalizedAction = [string]$action.Trim()
		if ($normalizedAction -notin @('Install', 'Uninstall'))
		{
			continue
		}

		$appActionEntries.Add([ordered]@{
			AppId = [string]$appId
			Action = $normalizedAction
			Name = $name
			WinGetId = $winGetId
			ChocoId = $chocoId
		}) | Out-Null
	}

	# Inline a snapshot of user-added external software entries so the profile
	# is portable: importing on a different machine can restore the catalog
	# definitions, not just selection state. Only fields that round-trip safely
	# are copied - runtime annotations (Source, SourceFile) are stripped.
	$userAppEntries = [System.Collections.Generic.List[object]]::new()
	$userAppCarryFields = @('Name', 'SubCategory', 'Function', 'Description', 'Category', 'Risk', 'Restorable')
	foreach ($userApp in @($UserApps))
	{
		if ($null -eq $userApp) { continue }

		$resolveProp = {
			param ($obj, $field)
			if ($null -eq $obj) { return $null }
			if ($obj -is [System.Collections.IDictionary])
			{
				if ($obj.Contains($field)) { return $obj[$field] }
				return $null
			}
			if ($obj.PSObject -and $obj.PSObject.Properties[$field]) { return $obj.$field }
			return $null
		}

		$nameValue = [string](& $resolveProp $userApp 'Name')
		if ([string]::IsNullOrWhiteSpace($nameValue)) { continue }

		$normalized = [ordered]@{}
		foreach ($field in $userAppCarryFields)
		{
			$fieldValue = & $resolveProp $userApp $field
			if ($null -ne $fieldValue) { $normalized[$field] = $fieldValue }
		}

		# Function defaults to AppInstall - Test-BaselineUserAppEntry rejects
		# anything else, so stamping it explicitly here matches the security
		# guard on the dialog's save path.
		if (-not $normalized.Contains('Function') -or [string]::IsNullOrWhiteSpace([string]$normalized['Function']))
		{
			$normalized['Function'] = 'AppInstall'
		}

		$extraArgs = & $resolveProp $userApp 'ExtraArgs'
		if ($null -ne $extraArgs)
		{
			$winGetId = [string](& $resolveProp $extraArgs 'WinGetId')
			$chocoId = [string](& $resolveProp $extraArgs 'ChocoId')
			$extraNormalized = [ordered]@{}
			if (-not [string]::IsNullOrWhiteSpace($winGetId)) { $extraNormalized['WinGetId'] = $winGetId }
			if (-not [string]::IsNullOrWhiteSpace($chocoId)) { $extraNormalized['ChocoId'] = $chocoId }
			if ($extraNormalized.Count -gt 0)
			{
				$normalized['ExtraArgs'] = $extraNormalized
			}
		}

		$userAppEntries.Add($normalized) | Out-Null
	}

	$includePathEntries = [System.Collections.Generic.List[string]]::new()
	$includePathSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($includePath in @($IncludePaths))
	{
		if ([string]::IsNullOrWhiteSpace([string]$includePath))
		{
			continue
		}

		$normalizedIncludePath = ([string]$includePath).Trim()
		if ($includePathSeen.Add($normalizedIncludePath))
		{
			[void]$includePathEntries.Add($normalizedIncludePath)
		}
	}

	$profile = [ordered]@{
		Schema             = $Script:ConfigProfileSchema
		SchemaVersion      = $Script:ConfigProfileSchemaVersion
		Name               = $Name
		Description        = if (-not [string]::IsNullOrWhiteSpace($Description)) { $Description } else { $null }
		CreatedAt          = [System.DateTime]::UtcNow.ToString('o')
		BaselineVersion    = $BaselineVersion
		SourceMachine      = $env:COMPUTERNAME
		AppsPackageSourcePreference = if (-not [string]::IsNullOrWhiteSpace($AppsPackageSourcePreference)) { [string]$AppsPackageSourcePreference } else { $null }
		TargetRequirements = [ordered]@{
			MinBuild = $minBuild
			Edition  = $edition
		}
		Entries            = @($entries)
		AppActions         = @($appActionEntries)
		UserApps           = @($userAppEntries)
		IncludePaths       = @($includePathEntries)
	}

	return [pscustomobject]$profile
}

<#
    .SYNOPSIS
#>

function Export-ConfigurationProfile
{
	<#
		.SYNOPSIS
		Writes a configuration profile object to a JSON file using UTF-8 no BOM.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[object]$Profile,

		[Parameter(Mandatory)]
		[string]$FilePath
	)

	$parentDir = Split-Path -Path $FilePath -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		[void](New-Item -Path $parentDir -ItemType Directory -Force)
	}

	$json = ConvertTo-Json -InputObject $Profile -Depth 16
	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	[System.IO.File]::WriteAllText($FilePath, $json, $utf8NoBom)
}

<#
    .SYNOPSIS
#>

function Export-BaselineFirstLogonCommandSnippet
{
	<#
		.SYNOPSIS
		Writes a FirstLogonCommands XML snippet for autounattend-based runs.

		.DESCRIPTION
		Generates a single SynchronousCommand entry that invokes Baseline with a
		saved configuration profile path, then writes the snippet to disk as UTF-8
		without a BOM. The output is intentionally a snippet, not a full unattend
		document, so it can be pasted into an existing autounattend.xml.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[string]$ConfigPath,

		[Parameter(Mandatory)]
		[string]$FilePath,

		[Parameter()]
		[string]$BaselineExePath = 'Baseline.exe',

		[Parameter()]
		[string]$Description = 'Run Baseline configuration profile',

		[Parameter()]
		[ValidateRange(1, [int]::MaxValue)]
		[int]$Order = 1
	)

	if ([string]::IsNullOrWhiteSpace($ConfigPath))
	{
		throw 'ConfigPath is required.'
	}
	if ([string]::IsNullOrWhiteSpace($FilePath))
	{
		throw 'FilePath is required.'
	}
	if ([string]::IsNullOrWhiteSpace($BaselineExePath))
	{
		throw 'BaselineExePath is required.'
	}
	if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf))
	{
		throw "Configuration profile not found: $ConfigPath"
	}

	$normalizedConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
	$normalizedBaselineExePath = ([string]$BaselineExePath).Trim().Trim('"')
	$commandLine = '{0} --configfile "{1}" --apply' -f $normalizedBaselineExePath, $normalizedConfigPath
	$escapedCommandLine = [System.Security.SecurityElement]::Escape($commandLine)
	$escapedDescription = [System.Security.SecurityElement]::Escape([string]$Description)

	$xml = @"
<FirstLogonCommands xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <SynchronousCommand wcm:action="add">
    <Order>$Order</Order>
    <Description>$escapedDescription</Description>
    <CommandLine>$escapedCommandLine</CommandLine>
  </SynchronousCommand>
</FirstLogonCommands>
"@

	$parentDir = Split-Path -Path $FilePath -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		[void](New-Item -Path $parentDir -ItemType Directory -Force)
	}

	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	[System.IO.File]::WriteAllText($FilePath, $xml, $utf8NoBom)

	return [pscustomobject]@{
		ConfigPath        = $normalizedConfigPath
		FilePath          = $FilePath
		BaselineExePath   = $normalizedBaselineExePath
		CommandLine       = $commandLine
		Xml               = $xml
	}
}

<#
    .SYNOPSIS
#>

function Import-ConfigurationProfile
{
	<#
		.SYNOPSIS
		Reads a configuration profile from a JSON file and validates the schema.

		.DESCRIPTION
		Parses the JSON file, checks that the Schema field matches
		'Baseline.ConfigProfile' and that SchemaVersion is at least 1, and
		returns the profile object. Throws on missing file or invalid schema.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$FilePath
	)

	if (-not (Test-Path -LiteralPath $FilePath))
	{
		throw "Configuration profile not found: $FilePath"
	}

	try
	{
		$content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
		$document = $content | ConvertFrom-BaselineJson -Depth 16
	}
	catch
	{
		throw "Failed to read or parse configuration profile '$FilePath': $_"
	}

	# Validate schema field.
	$actualSchema = if ($document.PSObject.Properties['Schema']) { [string]$document.Schema } else { $null }
	if ($actualSchema -ne $Script:ConfigProfileSchema)
	{
		throw "Schema mismatch in '$FilePath': expected '$($Script:ConfigProfileSchema)', found '$actualSchema'."
	}

	# Validate minimum schema version.
	$actualVersion = if ($document.PSObject.Properties['SchemaVersion']) { [int]$document.SchemaVersion } else { 0 }
	if ($actualVersion -lt 1)
	{
		throw "Unsupported schema version $actualVersion in '$FilePath'. Minimum supported version is 1."
	}

	# Validate required fields.
	if (-not $document.PSObject.Properties['Entries'] -and -not $document.PSObject.Properties['AppActions'])
	{
		throw "Configuration profile '$FilePath' is missing the required 'Entries' or 'AppActions' field."
	}

	return $document
}

<#
    .SYNOPSIS
#>

function Import-ConfigurationProfileIncludeLibraries
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Profile
	)

	if ($null -eq $Profile)
	{
		return
	}

	$includePaths = @()
	if ($Profile.PSObject.Properties['IncludePaths'] -and $null -ne $Profile.IncludePaths)
	{
		$includePaths = @(
			@($Profile.IncludePaths) |
				Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
				ForEach-Object { ([string]$_).Trim() }
		)
	}

	if ($includePaths.Count -eq 0)
	{
		return
	}

	$importHelper = Get-Command -Name 'Import-BaselineIncludedTweakLibraries' -CommandType Function -ErrorAction SilentlyContinue
	if (-not $importHelper)
	{
		throw 'Import-BaselineIncludedTweakLibraries is not available to load profile include paths.'
	}

	& $importHelper -IncludePaths $includePaths
}

<#
    .SYNOPSIS
#>

function Test-ConfigurationProfileCompatibility
{
	<#
		.SYNOPSIS
		Checks whether the current system meets the target requirements of a profile.

		.DESCRIPTION
		Compares the profile's TargetRequirements (MinBuild, Edition) against the
		running system and returns an object with a Compatible flag and any warnings.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Profile
	)

	$warnings = [System.Collections.Generic.List[string]]::new()
	$compatible = $true

	$requirements = if ($Profile.PSObject.Properties['TargetRequirements']) { $Profile.TargetRequirements } else { $null }
	if ($null -eq $requirements)
	{
		return [pscustomobject]@{
			Compatible = $true
			Warnings   = @()
		}
	}

	# Check Windows build number.
	$requiredBuild = 0
	if ($requirements.PSObject.Properties['MinBuild'])
	{
		[void][int]::TryParse([string]$requirements.MinBuild, [ref]$requiredBuild)
	}

	$currentBuild = 0
	try
	{
		$versionData = Get-WindowsVersionData
		if ($versionData -and $versionData.CurrentBuild)
		{
			[void][int]::TryParse([string]$versionData.CurrentBuild, [ref]$currentBuild)
		}
	}
	catch
	{
		Write-ConfigProfileDebugSwallowedException -ErrorRecord $_ -Source 'ConfigProfile.Test-ConfigurationProfileCompatibility.WindowsVersionData'
	}

	if ($requiredBuild -gt 0 -and $currentBuild -gt 0 -and $currentBuild -lt $requiredBuild)
	{
		$compatible = $false
		$warnings.Add("Profile requires Windows build $requiredBuild or later, current build is $currentBuild.")
	}
	elseif ($requiredBuild -gt 0 -and $currentBuild -gt 0 -and $currentBuild -ne $requiredBuild)
	{
		$warnings.Add("Profile created for build $requiredBuild, current is $currentBuild.")
	}

	# Check Windows edition.
	if ($requirements.PSObject.Properties['Edition'] -and -not [string]::IsNullOrWhiteSpace([string]$requirements.Edition))
	{
		$allowedEditions = [string]$requirements.Edition
		$currentEdition = $null
		try
		{
			$currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
			if ($currentVersion -and $currentVersion.PSObject.Properties['EditionID'])
			{
				$currentEdition = [string]$currentVersion.EditionID
			}
		}
		catch
		{
			Write-ConfigProfileDebugSwallowedException -ErrorRecord $_ -Source 'ConfigProfile.Test-ConfigurationProfileCompatibility.CurrentVersion'
		}

		if (-not [string]::IsNullOrWhiteSpace($currentEdition))
		{
			$editionList = $allowedEditions -split '\|' | ForEach-Object { $_.Trim() }
			$editionMatch = $false
			foreach ($allowed in $editionList)
			{
				if ($currentEdition -eq $allowed)
				{
					$editionMatch = $true
					break
				}
			}

			if (-not $editionMatch)
			{
				$warnings.Add("Profile targets edition(s) '$allowedEditions', current edition is '$currentEdition'.")
			}
		}
	}

	return [pscustomobject]@{
		Compatible = $compatible
		Warnings   = @($warnings)
	}
}

<#
    .SYNOPSIS
#>

function Compare-ConfigurationProfiles
{
	<#
		.SYNOPSIS
		Compares two configuration profiles and returns differences.

		.DESCRIPTION
		Examines the Entries arrays of both profiles and categorises each entry as
		OnlyInA, OnlyInB, Different (present in both but with different parameters),
		or Same.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$ProfileA,

		[Parameter(Mandatory)]
		[object]$ProfileB
	)

	$entriesA = @()
	if ($ProfileA.PSObject.Properties['Entries'] -and $null -ne $ProfileA.Entries)
	{
		$entriesA = @($ProfileA.Entries)
	}

	$entriesB = @()
	if ($ProfileB.PSObject.Properties['Entries'] -and $null -ne $ProfileB.Entries)
	{
		$entriesB = @($ProfileB.Entries)
	}

	# Index entries by Function name for O(n) comparison.
	$indexA = [ordered]@{}
	foreach ($entry in $entriesA)
	{
		if ($null -eq $entry) { continue }
		$fn = if ($entry.PSObject.Properties['Function']) { [string]$entry.Function } else { $null }
		if (-not [string]::IsNullOrWhiteSpace($fn))
		{
			$indexA[$fn] = $entry
		}
	}

	$indexB = [ordered]@{}
	foreach ($entry in $entriesB)
	{
		if ($null -eq $entry) { continue }
		$fn = if ($entry.PSObject.Properties['Function']) { [string]$entry.Function } else { $null }
		if (-not [string]::IsNullOrWhiteSpace($fn))
		{
			$indexB[$fn] = $entry
		}
	}

	$onlyInA = [System.Collections.Generic.List[object]]::new()
	$onlyInB = [System.Collections.Generic.List[object]]::new()
	$different = [System.Collections.Generic.List[object]]::new()
	$same = [System.Collections.Generic.List[object]]::new()

	foreach ($fn in $indexA.Keys)
	{
		$entryA = $indexA[$fn]
		if ($indexB.Contains($fn))
		{
			$entryB = $indexB[$fn]
			if ((Get-ProfileEntryComparisonKey $entryA) -eq (Get-ProfileEntryComparisonKey $entryB))
			{
				$same.Add($entryA)
			}
			else
			{
				$different.Add([pscustomobject]@{
					Function = $fn
					InA      = $entryA
					InB      = $entryB
				})
			}
		}
		else
		{
			$onlyInA.Add($entryA)
		}
	}

	foreach ($fn in $indexB.Keys)
	{
		if (-not $indexA.Contains($fn))
		{
			$onlyInB.Add($indexB[$fn])
		}
	}

	return [pscustomobject]@{
		OnlyInA   = @($onlyInA)
		OnlyInB   = @($onlyInB)
		Different = @($different)
		Same      = @($same)
	}
}

<#
    .SYNOPSIS
#>

function Get-ProfileEntryComparisonKey
{
	<# .SYNOPSIS Builds a normalised comparison string for a profile entry. #>
	param ([object]$Entry)

	if ($null -eq $Entry) { return '' }

	$type = if ($Entry.PSObject.Properties['Type']) { [string]$Entry.Type } else { 'Toggle' }
	$fn = if ($Entry.PSObject.Properties['Function']) { [string]$Entry.Function } else { '' }

		switch ($type)
		{
			'Choice'
			{
				$val = if ($Entry.PSObject.Properties['Value']) { ConvertTo-ConfigurationProfileValueText -Value $Entry.Value } else { '' }
				return "$fn|Choice|$val"
			}
			'NumericRange'
			{
				$val = if ($Entry.PSObject.Properties['Value']) { ConvertTo-ConfigurationProfileValueText -Value $Entry.Value }
					elseif ($Entry.PSObject.Properties['NumericValue']) { ConvertTo-ConfigurationProfileValueText -Value $Entry.NumericValue }
					elseif ($Entry.PSObject.Properties['ACValue'] -or $Entry.PSObject.Properties['DCValue']) { ConvertTo-ConfigurationProfileValueText -Value $Entry }
					else { '' }
				return "$fn|NumericRange|$val"
			}
			'Date'
			{
				$run = if ($Entry.PSObject.Properties['Run']) { [bool]$Entry.Run } else { $false }
				$val = if ($Entry.PSObject.Properties['Value']) { ConvertTo-ConfigurationProfileValueText -Value $Entry.Value } else { '' }
				return "$fn|Date|$run|$val"
			}
			default
			{
			$param = if ($Entry.PSObject.Properties['Param']) { [string]$Entry.Param } else { '' }
			return "$fn|Toggle|$param"
		}
	}
}

<#
    .SYNOPSIS
#>

function ConvertFrom-PresetToProfile
{
	<#
		.SYNOPSIS
		Converts an existing preset file into a configuration profile.

		.DESCRIPTION
		Reads the preset JSON from Module/Data/Presets/{PresetName}.json, resolves
		each command line against the manifest, and returns a full configuration
		profile object. This bridges the legacy preset system with the new profile
		system.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$PresetName,

		[Parameter(Mandatory)]
		[array]$Manifest,

		[string]$ModuleRoot
	)

	# Load the preset command list using the existing helper.
	$commandList = Get-HeadlessPresetCommandList -PresetName $PresetName -ModuleRoot $ModuleRoot

	# Resolve each command line into a selection object.
	$selections = [System.Collections.Generic.List[object]]::new()
	foreach ($commandLine in @($commandList))
	{
		if ([string]::IsNullOrWhiteSpace([string]$commandLine)) { continue }

		$parts = ([string]$commandLine).Trim() -split '\s+', 2
		$functionName = $parts[0]
		$paramRaw = if ($parts.Count -gt 1) { $parts[1] } else { $null }
		$paramName = if (-not [string]::IsNullOrWhiteSpace($paramRaw)) { $paramRaw.TrimStart('-') } else { $null }

		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		$manifestEntry = Get-ManifestEntryByFunction -Manifest $Manifest -Function $functionName
		$category = if ($manifestEntry -and $manifestEntry.PSObject.Properties['Category']) { [string]$manifestEntry.Category } else { $null }
		$type = if ($manifestEntry -and $manifestEntry.PSObject.Properties['Type']) { [string]$manifestEntry.Type } else { 'Toggle' }

		$selection = [ordered]@{
			Function = $functionName
			Type     = $type
			Category = $category
		}

		switch ($type)
		{
			'Choice'
			{
				$selection.SelectedValue = $paramName
			}
			'NumericRange'
			{
				$acValue = $null
				$dcValue = $null
				$scalarValue = $null

				for ($i = 1; $i -lt $tokens.Count - 1; $i++)
				{
					$token = [string]$tokens[$i]
					if (-not $token.StartsWith('-'))
					{
						continue
					}

					$tokenName = $token.TrimStart('-')
					$tokenValue = [string]$tokens[$i + 1]
					switch ($tokenName)
					{
						'Value' { $scalarValue = $tokenValue }
						'NumericValue' { $scalarValue = $tokenValue }
						'ACValue' { $acValue = $tokenValue }
						'DCValue' { $dcValue = $tokenValue }
					}
				}

				if ($null -ne $acValue -or $null -ne $dcValue)
				{
					if ($null -ne $acValue)
					{
						$selection.ACValue = $acValue
					}
					if ($null -ne $dcValue)
					{
						$selection.DCValue = $dcValue
					}
					$selection.Value = [ordered]@{
						ACValue = $acValue
						DCValue = if ($null -ne $dcValue) { $dcValue } else { $acValue }
					}
				}
				elseif (-not [string]::IsNullOrWhiteSpace($scalarValue))
				{
					$selection.Value = $scalarValue
					$selection.NumericValue = $scalarValue
				}
				elseif (-not [string]::IsNullOrWhiteSpace($paramName))
				{
					$selection.Value = $paramName
				}
			}
			'Date'
			{
				$selection.Run = $true
				if (-not [string]::IsNullOrWhiteSpace($paramName) -and $commandLine -match '(?i)-StartDate\s+(\S+)')
				{
					$selection.DateParam = if ($manifestEntry -and $manifestEntry.PSObject.Properties['DateParam']) { [string]$manifestEntry.DateParam } else { 'StartDate' }
					$selection.Value = [string]$matches[1]
				}
				else
				{
					$selection.Value = $paramName
				}
			}
			default
			{
				$selection.ToggleParam = $paramName
			}
		}

		$selections.Add($selection)
	}

	# Resolve Baseline version.
	$baselineVersion = $null
	if (Get-Command -Name 'Get-BaselineDisplayVersion' -ErrorAction SilentlyContinue)
	{
		try { $baselineVersion = Get-BaselineDisplayVersion } catch { Write-ConfigProfileDebugSwallowedException -ErrorRecord $_ -Source 'ConfigProfile.ConvertFrom-PresetToProfile.BaselineVersion' }
	}
	if ([string]::IsNullOrWhiteSpace($baselineVersion))
	{
		$baselineVersion = 'unknown'
	}

	$includePaths = @()
	$includePathCmd = Get-Command -Name 'Get-HeadlessPresetIncludedTweakLibraryPathSet' -CommandType Function -ErrorAction SilentlyContinue
	if ($includePathCmd)
	{
		$includePaths = @(& $includePathCmd)
	}

	return New-ConfigurationProfile `
		-Name $PresetName `
		-Selections @($selections) `
		-IncludePaths $includePaths `
		-BaselineVersion $baselineVersion `
		-Description "Profile converted from preset '$PresetName'."
}

<#
    .SYNOPSIS
#>

function ConvertFrom-BaselineConfigProfileToRunList
{
	<#
		.SYNOPSIS
		Projects an imported configuration profile's Entries[] back into
		runlist-shaped hashtables keyed against the live tweak manifest.

		.DESCRIPTION
		Used by the GUI Import Config Profile flow to translate a portable
		profile document into the same shape Get-SelectedTweakRunList emits
		(Function, Type, Selection, ToggleParam, Value, SelectedValue,
		NumericValue, ACValue, DCValue, ExtraArgs), so it can be fed to
		Start-GuiExecutionRun without first having to mutate GUI controls.

		Each profile entry is joined to the manifest by Function name; entries
		without a manifest match are skipped (they cannot be run on this
		Baseline build). Manifest fields supply the static metadata
		(Index, Name, Risk, Category, RequiresRestart, OnParam/OffParam,
		Options/DisplayOptions, NumericRange.Units), the profile entry
		supplies the chosen value.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object]$Profile,

		[Parameter(Mandatory)]
		[array]$Manifest
	)

	$runList = [System.Collections.Generic.List[hashtable]]::new()

	try
	{
		Import-ConfigurationProfileIncludeLibraries -Profile $Profile
	}
	catch
	{
		throw "Failed to import configuration profile include libraries before run-list conversion: $($_.Exception.Message)"
	}

	$profileEntries = @()
	if ($Profile -and $Profile.PSObject.Properties['Entries']) { $profileEntries = @($Profile.Entries) }
	if (-not $profileEntries -or $profileEntries.Count -eq 0)
	{
		return ,@($runList.ToArray())
	}

	for ($pi = 0; $pi -lt $profileEntries.Count; $pi++)
	{
		$pe = $profileEntries[$pi]
		if (-not $pe) { continue }

		$functionName = $null
		if ($pe.PSObject.Properties['Function']) { $functionName = [string]$pe.Function }
		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		# Locate the matching manifest entry and its index for run-list shape parity.
		$manifestIndex = -1
		$manifestEntry = $null
		for ($mi = 0; $mi -lt @($Manifest).Count; $mi++)
		{
			$me = $Manifest[$mi]
			if (-not $me) { continue }
			$meFunction = [string](Get-TweakManifestEntryValue -Entry $me -FieldName 'Function')
			if ([string]::IsNullOrWhiteSpace($meFunction)) { continue }
			if ($meFunction.Equals($functionName, [System.StringComparison]::OrdinalIgnoreCase))
			{
				$manifestEntry = $me
				$manifestIndex = $mi
				break
			}
		}
		if (-not $manifestEntry) { continue }

		$entryType = if ($pe.PSObject.Properties['Type']) { [string]$pe.Type } else { 'Toggle' }
		$manifestType = [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Type')
		if ([string]::IsNullOrWhiteSpace($entryType) -and -not [string]::IsNullOrWhiteSpace($manifestType))
		{
			$entryType = $manifestType
		}

		$category = if ($pe.PSObject.Properties['Category']) { [string]$pe.Category } else { [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Category') }
		$risk = [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Risk')
		$restorable = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Restorable')
		$requiresRestart = [bool](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'RequiresRestart')
		$impact = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Impact')
		$presetTier = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'PresetTier')
		$nameValue = [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Name')
		$onParam = [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'OnParam')
		$offParam = [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'OffParam')
		$defaultValue = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Default')

		$row = [ordered]@{
			Key             = [string]$manifestIndex
			Index           = $manifestIndex
			Name            = $nameValue
			Function        = $functionName
			Type            = $entryType
			Category        = $category
			Risk            = $risk
			Restorable      = $restorable
			RequiresRestart = $requiresRestart
			Impact          = $impact
			PresetTier      = $presetTier
			IsChecked       = $true
			ExtraArgs       = $null
		}

		$skipRow = $false
		switch ($entryType)
		{
			'Choice'
			{
				$selectedRaw = $null
				if ($pe.PSObject.Properties['SelectedValue']) { $selectedRaw = [string]$pe.SelectedValue }
				elseif ($pe.PSObject.Properties['Value']) { $selectedRaw = [string]$pe.Value }

				$options = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Options')
				$displayOptions = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'DisplayOptions')
				if (-not $displayOptions) { $displayOptions = $options }
				$selectedIdx = -1
				if ($options -and -not [string]::IsNullOrWhiteSpace($selectedRaw))
				{
					$optionList = [object[]]@($options)
					$selectedIdx = [array]::IndexOf($optionList, $selectedRaw)
					if ($selectedIdx -lt 0 -and $displayOptions)
					{
						$selectedIdx = [array]::IndexOf([object[]]@($displayOptions), $selectedRaw)
					}
				}
				if ($selectedIdx -lt 0) { $skipRow = $true; break }

				$row.Selection      = [string]$displayOptions[$selectedIdx]
				$row.Value          = $options[$selectedIdx]
				$row.SelectedIndex  = [int]$selectedIdx
				$row.SelectedValue  = [string]$displayOptions[$selectedIdx]
				$row.DefaultIndex   = if ($options) { [array]::IndexOf([object[]]@($options), $defaultValue) } else { -1 }
				$row.DefaultValue   = if ($null -ne $defaultValue) { [string]$defaultValue } else { $null }
				$row.ExtraArgs      = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'ExtraArgs')
			}
			'NumericRange'
			{
				$numericRange = (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'NumericRange')
				$units = $null
				if ($numericRange -and ($numericRange.PSObject.Properties['Units']))
				{
					$units = [string]$numericRange.Units
				}

				$acValue = if ($pe.PSObject.Properties['ACValue']) { $pe.ACValue } else { $null }
				$dcValue = if ($pe.PSObject.Properties['DCValue']) { $pe.DCValue } else { $null }
				$numericValue = if ($pe.PSObject.Properties['NumericValue']) { $pe.NumericValue } else { $null }
				$valueObject = $null
				if ($pe.PSObject.Properties['Value']) { $valueObject = $pe.Value }

				if ($null -eq $valueObject -and ($null -ne $acValue -or $null -ne $dcValue))
				{
					$valueObject = [pscustomobject]@{ ACValue = $acValue; DCValue = $dcValue }
				}
				if ($null -eq $valueObject -and $null -ne $numericValue)
				{
					$valueObject = $numericValue
				}

				$row.Selection    = if ($null -ne $valueObject) { [string]$valueObject } else { '' }
				$row.Value        = $valueObject
				$row.NumericValue = $numericValue
				$row.ACValue      = $acValue
				$row.DCValue      = $dcValue
				$row.Units        = $units
				$row.DefaultValue = $defaultValue
			}
			'Date'
			{
				$dateValue = if ($pe.PSObject.Properties['Value']) { [string]$pe.Value } else { $null }
				$runFlag = $true
				if ($pe.PSObject.Properties['Run']) { $runFlag = [bool]$pe.Run }

				$row.Run         = $runFlag
				$row.Value       = $dateValue
				$row.DateValue   = $dateValue
				$row.DateParam   = if ($pe.PSObject.Properties['DateParam']) { [string]$pe.DateParam } else { [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'DateParam') }
				$row.Selection   = if ($runFlag -and -not [string]::IsNullOrWhiteSpace($dateValue)) { $dateValue } elseif ($runFlag) { 'Pause enabled' } else { 'Pause cleared' }
				$row.ToggleParam = if ($runFlag) { if (-not [string]::IsNullOrWhiteSpace($onParam)) { $onParam } else { 'Enable' } } else { if (-not [string]::IsNullOrWhiteSpace($offParam)) { $offParam } else { 'Disable' } }
				$row.IsChecked   = $runFlag
				$row.DefaultValue = $defaultValue
			}
			default
			{
				# Toggle (or unspecified type - treat as Toggle).
				$paramRaw = if ($pe.PSObject.Properties['Param']) { [string]$pe.Param } else { $null }
				if ([string]::IsNullOrWhiteSpace($paramRaw)) { $skipRow = $true; break }

				$row.Selection    = $paramRaw
				$row.ToggleParam  = $paramRaw
				$row.OnParam      = $onParam
				$row.OffParam     = $offParam
				$row.DefaultValue = if ($null -ne $defaultValue) { [bool]$defaultValue } else { $false }
			}
		}

		if ($skipRow) { continue }
		$runList.Add([hashtable]$row)
	}

	return ,@($runList.ToArray())
}
