<#
	.SYNOPSIS
	Generate curated preset JSON files from manifest metadata.

	.DESCRIPTION
	Builds conservative preset files from the current tweak manifest so the
	low-risk preset tiers do not have to be maintained entirely by hand.

	The generator currently focuses on the release-safe presets:
	- Minimal
	- Basic
	- Balanced

	Advanced remains intentionally curated because it is an expert preset and
	is allowed to be more opinionated than the lower-risk tiers.

	.EXAMPLE
	pwsh -File .\Tools\Generate-PresetFiles.ps1

	.EXAMPLE
	pwsh -File .\Tools\Generate-PresetFiles.ps1 -PresetNames Basic,Balanced -DryRun
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[string[]]$PresetNames = @('Minimal', 'Basic', 'Balanced'),
	[string]$OutputDirectory,
	[switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleRoot = Join-Path $repoRoot 'Module'

if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container))
{
	throw "Module directory not found under: $repoRoot"
}

$sharedHelpersPath = Join-Path $moduleRoot 'SharedHelpers.psm1'
if (-not (Test-Path -LiteralPath $sharedHelpersPath -PathType Leaf))
{
	throw "SharedHelpers module not found: $sharedHelpersPath"
}

Import-Module -Name $sharedHelpersPath -Force -ErrorAction Stop

$presetRoot = if ([string]::IsNullOrWhiteSpace($OutputDirectory))
{
	Join-Path $moduleRoot 'Data\Presets'
}
else
{
	$OutputDirectory
}

if (-not (Test-Path -LiteralPath $presetRoot))
{
	New-Item -Path $presetRoot -ItemType Directory -Force | Out-Null
}

$validPresetNames = @('Minimal', 'Basic', 'Balanced')
$basicAllowlistedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($approvedFunction in @(
	'CheckWinGet'
	'Update-Powershell'
	'Update-DesktopRegistry'
	'Disable-AutoRun'
	'DismissMSAccount'
	'DismissSmartScreenFilter'
	'Repair-Windows11SMBUpdateIssue'
	'UnpinTaskbarShortcuts'
))
{
	[void]$basicAllowlistedFunctions.Add($approvedFunction)
}

$balancedAllowlistedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($approvedFunction in @(
	'CheckWinGet'
	'Update-Powershell'
	'Update-DesktopRegistry'
	'Disable-AutoRun'
	'DismissMSAccount'
	'DismissSmartScreenFilter'
	'Repair-Windows11SMBUpdateIssue'
	'UnpinTaskbarShortcuts'
	'Update-EventLogSize'
	'Protect-FileSystemPerformance'
	'Set-WindowsFirewallLogging'
	'Install-Cursors'
))
{
	[void]$balancedAllowlistedFunctions.Add($approvedFunction)
}

$minimalAllowedTiers = @('Minimal', 'Safe')
$basicAllowedTiers = @('Minimal', 'Safe', 'Basic')
$balancedAllowedTiers = @('Minimal', 'Safe', 'Basic', 'Balanced')

function Expand-ManifestRecords
{
	param([object]$Value)

	foreach ($item in @($Value))
	{
		if ($null -eq $item)
		{
			continue
		}

		if ($item -is [pscustomobject] -or $item -is [System.Collections.IDictionary])
		{
			$item
			continue
		}

		if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string]))
		{
			foreach ($nestedItem in $item)
			{
				if ($null -ne $nestedItem)
				{
					$nestedItem
				}
			}

			continue
		}

		$item
	}
}

$manifest = @(Expand-ManifestRecords -Value (Import-TweakManifestFromData))

function Test-TweakField
{
	param(
		[object]$Tweak,
		[string]$FieldName
	)

	if ($null -eq $Tweak -or [string]::IsNullOrWhiteSpace($FieldName))
	{
		return $false
	}

	if ($Tweak -is [System.Collections.IDictionary])
	{
		return $Tweak.Contains($FieldName)
	}

	return ($Tweak.PSObject.Properties.Match($FieldName).Count -gt 0)
}

function Get-TweakFieldValue
{
	param(
		[object]$Tweak,
		[string]$FieldName
	)

	if (-not (Test-TweakField -Tweak $Tweak -FieldName $FieldName))
	{
		return $null
	}

	if ($Tweak -is [System.Collections.IDictionary])
	{
		return $Tweak[$FieldName]
	}

	return $Tweak.$FieldName
}

function Get-PresetCommandLine
{
	param([object]$Tweak)

	if (-not $Tweak) { return $null }

	$functionName = [string]$Tweak.Function
	if ([string]::IsNullOrWhiteSpace($functionName)) { return $null }

	function ConvertTo-PresetParameterName
	{
		param([object]$Value)

		if ($null -eq $Value)
		{
			return $null
		}

		$text = [string]$Value
		if ([string]::IsNullOrWhiteSpace($text))
		{
			return $null
		}

		return $text.Trim().TrimStart('-')
	}

	function ConvertTo-PresetArgumentText
	{
		param([object]$Value)

		if ($null -eq $Value)
		{
			return $null
		}

		if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]))
		{
			$items = @(
				@($Value) |
					ForEach-Object { ConvertTo-PresetArgumentText -Value $_ } |
					Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
			)

			if ($items.Count -eq 0)
			{
				return $null
			}

			return ($items -join ', ')
		}

		$text = [string]$Value
		if ([string]::IsNullOrWhiteSpace($text))
		{
			return $null
		}

		return $text.Trim()
	}

	function Get-PresetExtraArgumentFragments
	{
		param([object]$Value)

		if ($null -eq $Value)
		{
			return @()
		}

		if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject])
		{
			$fragments = [System.Collections.Generic.List[string]]::new()
			$properties = if ($Value -is [System.Collections.IDictionary])
			{
				$Value.GetEnumerator() | ForEach-Object {
					[pscustomobject]@{
						Name = [string]$_.Key
						Value = $_.Value
					}
				}
			}
			else
			{
				$Value.PSObject.Properties | ForEach-Object {
					[pscustomobject]@{
						Name = [string]$_.Name
						Value = $_.Value
					}
				}
			}

			foreach ($property in @($properties))
			{
				$parameterName = ConvertTo-PresetParameterName -Value $property.Name
				if ([string]::IsNullOrWhiteSpace($parameterName))
				{
					continue
				}

				if ($property.Value -is [bool])
				{
					if ([bool]$property.Value)
					{
						[void]$fragments.Add(('-{0}' -f $parameterName))
					}

					continue
				}

				$argumentText = ConvertTo-PresetArgumentText -Value $property.Value
				if ([string]::IsNullOrWhiteSpace($argumentText))
				{
					continue
				}

				[void]$fragments.Add(('-{0} {1}' -f $parameterName, $argumentText))
			}

			return @($fragments)
		}

		$argumentText = ConvertTo-PresetArgumentText -Value $Value
		if ([string]::IsNullOrWhiteSpace($argumentText))
		{
			return @()
		}

		return @($argumentText)
	}

	$baseCommand = switch ([string]$Tweak.Type)
	{
		'Toggle'
		{
			$defaultValue = $false
			if (Test-TweakField -Tweak $Tweak -FieldName 'Default')
			{
				$defaultValue = [bool](Get-TweakFieldValue -Tweak $Tweak -FieldName 'Default')
			}

			# Manifest Default already represents the curated preset state for the tweak,
			# so choose the matching parameter instead of inverting against Windows defaults.
			$paramName = if ($defaultValue)
			{
				ConvertTo-PresetParameterName -Value (Get-TweakFieldValue -Tweak $Tweak -FieldName 'OnParam')
			}
			else
			{
				ConvertTo-PresetParameterName -Value (Get-TweakFieldValue -Tweak $Tweak -FieldName 'OffParam')
			}

			if ([string]::IsNullOrWhiteSpace($paramName))
			{
				throw "Toggle entry '$functionName' is missing OnParam/OffParam metadata."
			}

			('{0} -{1}' -f $functionName, $paramName)
		}
		'Choice'
		{
			$defaultValue = Get-TweakFieldValue -Tweak $Tweak -FieldName 'Default'
			if ($null -eq $defaultValue)
			{
				$functionName
				break
			}

			('{0} -{1}' -f $functionName, [string]$defaultValue)
		}
		default
		{
			$functionName
		}
	}

	if ([string]::IsNullOrWhiteSpace($baseCommand))
	{
		return $null
	}

	$extraArgumentFragments = @()
	if (Test-TweakField -Tweak $Tweak -FieldName 'ExtraArgs')
	{
		$extraArgumentFragments = @(
			Get-PresetExtraArgumentFragments -Value (Get-TweakFieldValue -Tweak $Tweak -FieldName 'ExtraArgs')
		)
	}

	if ($extraArgumentFragments.Count -gt 0)
	{
		return ((@($baseCommand) + $extraArgumentFragments) -join ' ').Trim()
	}

	return $baseCommand
}

function Test-PresetEntryIncluded
{
	param(
		[object]$Tweak,
		[string]$PresetName
	)

	if (-not $Tweak) { return $false }

	$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
	$normalizedPresetName = [System.IO.Path]::GetFileNameWithoutExtension($normalizedPresetName.Trim())

	$riskValue = [string]$Tweak.Risk
	$presetTierValue = [string]$Tweak.PresetTier
	$workflowSensitivityValue = if (Test-TweakField -Tweak $Tweak -FieldName 'WorkflowSensitivity') { [string](Get-TweakFieldValue -Tweak $Tweak -FieldName 'WorkflowSensitivity') } else { 'Low' }
	$restorableValue = Get-TweakFieldValue -Tweak $Tweak -FieldName 'Restorable'
	$isSafeValue = if (Test-TweakField -Tweak $Tweak -FieldName 'Safe') { [bool](Get-TweakFieldValue -Tweak $Tweak -FieldName 'Safe') } else { $true }

	$isRemovalOperation = ([string]$Tweak.Function -match '^(?i)(uninstall|remove|delete)')
	$defaultCommandLine = Get-PresetCommandLine -Tweak $Tweak
	if (-not $isRemovalOperation -and -not [string]::IsNullOrWhiteSpace([string]$defaultCommandLine) -and $defaultCommandLine -match '(?i)(?:^|\s)-(?:uninstall|remove|delete)(?=\s|$)')
	{
		$isRemovalOperation = $true
	}
	if (-not $isRemovalOperation -and [string]$Tweak.Type -eq 'Choice' -and (Test-TweakField -Tweak $Tweak -FieldName 'Options'))
	{
		$optionValues = @(Get-TweakFieldValue -Tweak $Tweak -FieldName 'Options' | ForEach-Object { [string]$_ })
		if ($optionValues | Where-Object { $_ -match '^(?i)(uninstall|remove|delete)$' })
		{
			$isRemovalOperation = $true
		}
	}

	switch ($normalizedPresetName)
	{
		'Minimal'
		{
			return (
				($minimalAllowedTiers -contains $presetTierValue) -and
				$riskValue -ne 'High' -and
				$workflowSensitivityValue -ne 'High' -and
				-not $isRemovalOperation
			)
		}
			'Basic'
				{
					return (
						($basicAllowedTiers -contains $presetTierValue) -and
						($isSafeValue -or $presetTierValue -eq 'Minimal') -and
						$riskValue -ne 'High' -and
						$workflowSensitivityValue -ne 'High' -and
						-not @('XboxGameBar', 'XboxGameTips', 'OpenWindowsTerminalAdminContext').Contains([string]$Tweak.Function) -and
					-not $isRemovalOperation -and
					-not ([string]$Tweak.Type -eq 'Action' -and $null -ne $restorableValue -and -not [bool]$restorableValue -and -not $basicAllowlistedFunctions.Contains([string]$Tweak.Function))
				)
			}
			'Balanced'
				{
					return (
						($balancedAllowedTiers -contains $presetTierValue) -and
						($isSafeValue -or $presetTierValue -eq 'Minimal') -and
						$riskValue -ne 'High' -and
						$workflowSensitivityValue -ne 'High' -and
						-not $isRemovalOperation -and
					-not ($presetTierValue -eq 'Advanced') -and
				-not ([string]$Tweak.Type -eq 'Action' -and $null -ne $restorableValue -and -not [bool]$restorableValue -and -not $balancedAllowlistedFunctions.Contains([string]$Tweak.Function))
			)
		}
		default
		{
			return $false
		}
	}
}

$requestedPresetNames = @(
	$PresetNames |
		ForEach-Object { [string]$_ } |
		Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
		ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Trim()) } |
		Select-Object -Unique
)

foreach ($presetName in $requestedPresetNames)
{
	if ($validPresetNames -notcontains $presetName)
	{
		Write-Warning "Skipping unsupported preset '$presetName'. Supported presets: $($validPresetNames -join ', ')."
		continue
	}

	$presetEntries = [System.Collections.Generic.List[string]]::new()
	$seenFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($tweak in $manifest)
	{
		if (-not (Test-PresetEntryIncluded -Tweak $tweak -PresetName $presetName))
		{
			continue
		}

		$commandLine = Get-PresetCommandLine -Tweak $tweak
		if ([string]::IsNullOrWhiteSpace($commandLine))
		{
			continue
		}

		$functionName = [string]$tweak.Function
		if ([string]::IsNullOrWhiteSpace($functionName))
		{
			continue
		}

		if ($seenFunctions.Add($functionName))
		{
			[void]$presetEntries.Add($commandLine)
		}
	}

	$presetPayload = [ordered]@{
		Name = $presetName
		Entries = @($presetEntries)
	}

	$json = $presetPayload | ConvertTo-Json -Depth 6
	$outputPath = Join-Path -Path $presetRoot -ChildPath ("{0}.json" -f $presetName)

	if ($DryRun)
	{
		# Write-Host: intentional — test/tooling console output
		Write-Host ("[DryRun] {0} -> {1} entries at {2}" -f $presetName, $presetEntries.Count, $outputPath)
		continue
	}

	if ($PSCmdlet.ShouldProcess($outputPath, "Write generated preset '$presetName'"))
	{
		[System.IO.File]::WriteAllText($outputPath, ($json + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
		Write-Host ("Generated {0} preset with {1} entries: {2}" -f $presetName, $presetEntries.Count, $outputPath)
	}
}
