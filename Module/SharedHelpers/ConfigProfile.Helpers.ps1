# Configuration profile helper slice for Baseline.
# Provides portable configuration profile creation, import/export, compatibility
# checking, comparison, and conversion from existing presets.
# Uses Write-BaselineDocument / Read-BaselineDocument patterns for persistence.

$Script:ConfigProfileSchema = 'Baseline.ConfigProfile'
$Script:ConfigProfileSchemaVersion = 1

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

		[Parameter(Mandatory)]
		[string]$BaselineVersion,

		[string]$Description
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
	catch { }

	try
	{
		$currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
		if ($currentVersion -and $currentVersion.PSObject.Properties['EditionID'] -and -not [string]::IsNullOrWhiteSpace([string]$currentVersion.EditionID))
		{
			$edition = [string]$currentVersion.EditionID
		}
	}
	catch { }

	# Build normalized entry list from selections.
	$entries = [System.Collections.Generic.List[ordered]]::new()
	foreach ($selection in @($Selections))
	{
		if ($null -eq $selection) { continue }

		$functionName = $null
		$entryType = 'Toggle'
		$param = $null
		$category = $null
		$value = $null

		if ($selection -is [System.Collections.IDictionary])
		{
			$functionName = if ($selection.Contains('Function')) { [string]$selection['Function'] } else { $null }
			$entryType = if ($selection.Contains('Type')) { [string]$selection['Type'] } else { 'Toggle' }
			$param = if ($selection.Contains('ToggleParam')) { [string]$selection['ToggleParam'] }
						elseif ($selection.Contains('Selection')) { [string]$selection['Selection'] }
						else { $null }
			$category = if ($selection.Contains('Category')) { [string]$selection['Category'] } else { $null }
			$value = if ($selection.Contains('SelectedValue')) { [string]$selection['SelectedValue'] } else { $null }
		}
		elseif ($selection -is [pscustomobject] -or ($null -ne $selection.PSObject))
		{
			$functionName = if ($selection.PSObject.Properties['Function']) { [string]$selection.Function } else { $null }
			$entryType = if ($selection.PSObject.Properties['Type']) { [string]$selection.Type } else { 'Toggle' }
			$param = if ($selection.PSObject.Properties['ToggleParam']) { [string]$selection.ToggleParam }
						elseif ($selection.PSObject.Properties['Selection']) { [string]$selection.Selection }
						else { $null }
			$category = if ($selection.PSObject.Properties['Category']) { [string]$selection.Category } else { $null }
			$value = if ($selection.PSObject.Properties['SelectedValue']) { [string]$selection.SelectedValue } else { $null }
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
			default
			{
				$entry.Param = if (-not [string]::IsNullOrWhiteSpace($param)) { $param } else { $null }
				$entry.Category = $category
			}
		}

		$entries.Add($entry)
	}

	$profile = [ordered]@{
		Schema             = $Script:ConfigProfileSchema
		SchemaVersion      = $Script:ConfigProfileSchemaVersion
		Name               = $Name
		Description        = if (-not [string]::IsNullOrWhiteSpace($Description)) { $Description } else { $null }
		CreatedAt          = [System.DateTime]::UtcNow.ToString('o')
		BaselineVersion    = $BaselineVersion
		SourceMachine      = $env:COMPUTERNAME
		TargetRequirements = [ordered]@{
			MinBuild = $minBuild
			Edition  = $edition
		}
		Entries            = @($entries)
	}

	return [pscustomobject]$profile
}

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
		$document = $content | ConvertFrom-Json
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
	if (-not $document.PSObject.Properties['Entries'])
	{
		throw "Configuration profile '$FilePath' is missing the required 'Entries' field."
	}

	return $document
}

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
	catch { }

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
		catch { }

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
			$val = if ($Entry.PSObject.Properties['Value']) { [string]$Entry.Value } else { '' }
			return "$fn|Choice|$val"
		}
		default
		{
			$param = if ($Entry.PSObject.Properties['Param']) { [string]$Entry.Param } else { '' }
			return "$fn|Toggle|$param"
		}
	}
}

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
	$selections = [System.Collections.Generic.List[ordered]]::new()
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
		try { $baselineVersion = Get-BaselineDisplayVersion } catch { }
	}
	if ([string]::IsNullOrWhiteSpace($baselineVersion))
	{
		$baselineVersion = 'unknown'
	}

	return New-ConfigurationProfile `
		-Name $PresetName `
		-Selections @($selections) `
		-BaselineVersion $baselineVersion `
		-Description "Profile converted from preset '$PresetName'."
}
