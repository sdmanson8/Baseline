# Feature maturity helpers for Baseline.
# Provides a consistent maturity taxonomy for tweak entries and enterprise
# actions so diagnostics and policy gates can reason about readiness.

function Get-BaselineFeatureMaturityOrder
{
	return @(
		'Implemented'
		'Tested'
		'CI-validated'
		'Production-validated'
	)
}

function Get-BaselineEnterpriseActionMaturityCatalogData
{
	return [ordered]@{
		ConnectivityTest = [ordered]@{
			Current        = 'CI-validated'
			Required       = 'Tested'
			EnterpriseOnly = $true
			Description    = 'Remote connectivity probes used before multi-target operations.'
		}
		RemoteCompliance = [ordered]@{
			Current        = 'CI-validated'
			Required       = 'CI-validated'
			EnterpriseOnly = $true
			Description    = 'Remote compliance checks across one or more managed targets.'
		}
		RemoteApply = [ordered]@{
			Current        = 'Production-validated'
			Required       = 'Production-validated'
			EnterpriseOnly = $true
			Description    = 'Remote configuration apply runs that change endpoint state.'
		}
		IncidentReproductionPack = [ordered]@{
			Current        = 'Tested'
			Required       = 'Tested'
			EnterpriseOnly = $true
			Description    = 'Incident pack generation from support bundles for escalation workflows.'
		}
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineFeatureMaturityLevels
{
	[CmdletBinding()]
	[OutputType([string[]])]
	param()

	return @(Get-BaselineFeatureMaturityOrder)
}

<#
    .SYNOPSIS
#>

function ConvertTo-BaselineFeatureMaturityLevel
{
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[object]$Value
	)

	if ($null -eq $Value)
	{
		return 'Implemented'
	}

	$raw = ([string]$Value).Trim()
	if ([string]::IsNullOrWhiteSpace($raw))
	{
		return 'Implemented'
	}

	switch -Regex ($raw)
	{
		'^\s*implemented\s*$' { return 'Implemented' }
		'^\s*tested\s*$' { return 'Tested' }
		'^\s*ci([\s\-_]?validated)?\s*$' { return 'CI-validated' }
		'^\s*ci[\s\-_]validated\s*$' { return 'CI-validated' }
		'^\s*production([\s\-_]?validated)?\s*$' { return 'Production-validated' }
		'^\s*prod([\s\-_]?validated)?\s*$' { return 'Production-validated' }
		default { return 'Implemented' }
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineFeatureMaturityRank
{
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[Parameter(Mandatory)]
		[string]$Level
	)

	$normalized = ConvertTo-BaselineFeatureMaturityLevel -Value $Level
	$index = [array]::IndexOf(@(Get-BaselineFeatureMaturityOrder), $normalized)
	if ($index -lt 0)
	{
		return 0
	}

	return [int]$index
}

<#
    .SYNOPSIS
#>

function Test-BaselineFeatureMaturityAtLeast
{
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[string]$Current,

		[Parameter(Mandatory)]
		[string]$Required
	)

	$currentRank = Get-BaselineFeatureMaturityRank -Level $Current
	$requiredRank = Get-BaselineFeatureMaturityRank -Level $Required
	return ($currentRank -ge $requiredRank)
}

<#
    .SYNOPSIS
#>

function Get-BaselineEnterpriseActionMaturityCatalog
{
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param()

	$rows = [System.Collections.Generic.List[pscustomobject]]::new()
	$catalog = Get-BaselineEnterpriseActionMaturityCatalogData
	foreach ($key in $catalog.Keys)
	{
		$entry = $catalog[$key]
		$rows.Add([pscustomobject]@{
			FeatureName     = [string]$key
			CurrentMaturity = ConvertTo-BaselineFeatureMaturityLevel -Value $entry.Current
			RequiredMaturity = ConvertTo-BaselineFeatureMaturityLevel -Value $entry.Required
			EnterpriseOnly  = [bool]$entry.EnterpriseOnly
			Description     = [string]$entry.Description
		})
	}

	return @($rows)
}

<#
    .SYNOPSIS
#>

function Test-BaselineEnterpriseActionMaturityGate
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory)]
		[string]$FeatureName,

		[string]$RequiredMaturity
	)

	$catalog = Get-BaselineEnterpriseActionMaturityCatalogData
	$current = 'Implemented'
	$required = if ([string]::IsNullOrWhiteSpace($RequiredMaturity)) { 'Implemented' } else { $RequiredMaturity }
	$description = $null
	$enterpriseOnly = $true

	if ($catalog.Contains($FeatureName))
	{
		$entry = $catalog[$FeatureName]
		$current = [string]$entry.Current
		if ([string]::IsNullOrWhiteSpace($RequiredMaturity) -and $entry.Contains('Required'))
		{
			$required = [string]$entry.Required
		}
		if ($entry.Contains('Description'))
		{
			$description = [string]$entry.Description
		}
		if ($entry.Contains('EnterpriseOnly'))
		{
			$enterpriseOnly = [bool]$entry.EnterpriseOnly
		}
	}

	$normalizedCurrent = ConvertTo-BaselineFeatureMaturityLevel -Value $current
	$normalizedRequired = ConvertTo-BaselineFeatureMaturityLevel -Value $required
	$allowed = Test-BaselineFeatureMaturityAtLeast -Current $normalizedCurrent -Required $normalizedRequired

	return [pscustomobject]@{
		FeatureName       = $FeatureName
		CurrentMaturity   = $normalizedCurrent
		RequiredMaturity  = $normalizedRequired
		Allowed           = [bool]$allowed
		EnterpriseOnly    = [bool]$enterpriseOnly
		Description       = $description
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineFeatureMaturityReport
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[array]$Manifest
	)

	$entries = [System.Collections.Generic.List[pscustomobject]]::new()
	$counts = [ordered]@{
		Implemented = 0
		Tested = 0
		'CI-validated' = 0
		'Production-validated' = 0
	}

	foreach ($entry in @($Manifest))
	{
		if (-not $entry) { continue }

		$maturityRaw = $null
		if ($entry -is [System.Collections.IDictionary])
		{
			if ($entry.Contains('Maturity')) { $maturityRaw = $entry['Maturity'] }
		}
		elseif ($entry.PSObject -and $entry.PSObject.Properties['Maturity'])
		{
			$maturityRaw = $entry.Maturity
		}

		$maturity = ConvertTo-BaselineFeatureMaturityLevel -Value $maturityRaw
		$counts[$maturity] = [int]$counts[$maturity] + 1

		$name = $null
		$functionName = $null
		$category = $null
		if ($entry -is [System.Collections.IDictionary])
		{
			if ($entry.Contains('Name')) { $name = [string]$entry['Name'] }
			if ($entry.Contains('Function')) { $functionName = [string]$entry['Function'] }
			if ($entry.Contains('Category')) { $category = [string]$entry['Category'] }
		}
		else
		{
			if ($entry.PSObject.Properties['Name']) { $name = [string]$entry.Name }
			if ($entry.PSObject.Properties['Function']) { $functionName = [string]$entry.Function }
			if ($entry.PSObject.Properties['Category']) { $category = [string]$entry.Category }
		}

		$entries.Add([pscustomobject]@{
			Name = $name
			Function = $functionName
			Category = $category
			Maturity = $maturity
		})
	}

	$enterpriseActions = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($action in @(Get-BaselineEnterpriseActionMaturityCatalog))
	{
		$gate = Test-BaselineEnterpriseActionMaturityGate -FeatureName $action.FeatureName -RequiredMaturity $action.RequiredMaturity
		$enterpriseActions.Add([pscustomobject]@{
			FeatureName = $action.FeatureName
			CurrentMaturity = $gate.CurrentMaturity
			RequiredMaturity = $gate.RequiredMaturity
			Allowed = [bool]$gate.Allowed
			EnterpriseOnly = [bool]$gate.EnterpriseOnly
			Description = $action.Description
		})
	}

	return [pscustomobject]@{
		Schema = 'Baseline.FeatureMaturity'
		SchemaVersion = 1
		GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
		Summary = [ordered]@{
			Total = @($entries).Count
			Implemented = [int]$counts['Implemented']
			Tested = [int]$counts['Tested']
			'CI-validated' = [int]$counts['CI-validated']
			'Production-validated' = [int]$counts['Production-validated']
		}
		EnterpriseActions = @($enterpriseActions)
		Features = @($entries)
	}
}
