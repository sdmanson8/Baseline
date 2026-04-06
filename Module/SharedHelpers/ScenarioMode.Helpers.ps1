# Scenario Mode helper slice for Baseline.
# Extracted from Manifest.Helpers.ps1 - contains scenario profile definitions,
# plan building, and command list generation.
#
# Dependencies (from Manifest.Helpers.ps1, loaded first):
#   Get-TweakManifestEntryValue, Import-TweakManifestFromData,
#   Get-ManifestEntryByFunction, Get-TweakManifestDefaultCommand
#
# --- Scenario expansion policy ---
# Scenario modes are SEPARATE from the preset ladder (Minimal/Basic/Balanced/Advanced).
# They are workflow-driven profiles, not risk-tiered presets.
#
# Before adding a new scenario profile:
#   1. It must have a clear, distinct purpose that presets do not already cover
#   2. Its function list must be small, focused, and manually reviewed
#   3. All included functions must have safe defaults (no high-risk-by-default)
#   4. It must preview clearly - each entry needs ReasonIncluded text
#   5. It must not silently change behavior; recommendations only in v1
#
# Before adding functions to an existing profile:
#   1. The function must already exist in the manifest with complete metadata
#   2. It must align with the profile's stated purpose (Summary field)
#   3. It must be low-risk or have Direct recovery level
#   4. Update the ValidateSet in Get-ScenarioProfilePlan and Baseline.ps1 if adding profiles
#
# --- Design note ---
# Scenario profiles are intentionally defined inline (not loaded from JSON) because:
#   - The function lists are manually curated and reviewed for safety
#   - Each profile's function set must remain small, focused, and stable
#   - Inline definitions keep the safety-review audit trail in source control
# If the number of profiles grows beyond 5, consider migrating to a validated
# JSON data file (similar to GameMode profiles) with schema enforcement.

function Get-ScenarioProfileDefinitions
{
	<# .SYNOPSIS Returns the hardcoded scenario profile definitions (Workstation, Privacy, Recovery). #>
	return @(
		[pscustomobject]@{
			Name = 'Workstation'
			Label = 'Workstation'
			Summary = 'Productivity-focused defaults for terminals, long paths, Explorer clarity, and stable daily-driver behavior.'
			Functions = @(
				'DefaultTerminalApp'
				'Win32LongPathLimit'
				'NTFSLongPaths'
				'TaskbarEndTask'
				'FileExtensions'
				'UpdateMicrosoftProducts'
				'WindowsManageDefaultPrinter'
				'QuickAccessFrequentFolders'
				'QuickAccessRecentFiles'
			)
		}
		[pscustomobject]@{
			Name = 'Privacy'
			Label = 'Privacy'
			Summary = 'Conservative privacy defaults that reduce telemetry, cross-device sharing, and ad-style personalization without gutting core Windows workflows.'
			Functions = @(
				'ActivityHistory'
				'AdvertisingID'
				'DiagTrackService'
				'DiagnosticDataLevel'
				'FeedbackFrequency'
				'LanguageListAccess'
				'TailoredExperiences'
				'SharedExperiences'
				'Powershell7Telemetry'
				'DNSoverHTTPS'
				'DeliveryOptimization'
				'LockWidgets'
			)
		}
		[pscustomobject]@{
			Name = 'Recovery'
			Label = 'Recovery'
			Summary = 'Recovery-ready helpers that add rollback touchpoints, startup access, and diagnostic shortcuts before you need them.'
			Functions = @(
				'CreateRestorePoint'
				'AdvancedStartupShortcut'
				'AutoRebootOnCrash'
				'BootRecovery'
				'RegistryBackup'
				'EventViewerCustomView'
				'F8BootMenu'
				'RestartNotification'
			)
		}
	)
}

function Resolve-ScenarioProfileDefinition
{
	<# .SYNOPSIS Searches for and returns a scenario profile definition by name. #>
	param (
		[string]$ProfileName
	)

	if ([string]::IsNullOrWhiteSpace($ProfileName))
	{
		return $null
	}

	foreach ($definition in @(Get-ScenarioProfileDefinitions))
	{
		if ([string]$definition.Name -eq [string]$ProfileName)
		{
			return $definition
		}
	}

	return $null
}

function Get-ScenarioProfileValidationIssues
{
	<# .SYNOPSIS Validates scenario profile definitions against the tweak manifest. #>
	param (
		[array]$Manifest,
		[object[]]$Definitions = @(Get-ScenarioProfileDefinitions)
	)

	$issues = [System.Collections.Generic.List[string]]::new()
	$definitionNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$manifestEntries = if ($Manifest) { @($Manifest) } else { @() }

	foreach ($definition in @($Definitions))
	{
		if ($null -eq $definition) { continue }

		$name = [string]$definition.Name
		if ([string]::IsNullOrWhiteSpace($name))
		{
			[void]$issues.Add('Scenario profile definitions cannot have a blank Name.')
			continue
		}

		if (-not $definitionNames.Add($name))
		{
			[void]$issues.Add("Scenario profile '$name' is defined more than once.")
		}

		if ([string]::IsNullOrWhiteSpace([string]$definition.Label))
		{
			[void]$issues.Add("Scenario profile '$name' is missing Label.")
		}

		if ([string]::IsNullOrWhiteSpace([string]$definition.Summary))
		{
			[void]$issues.Add("Scenario profile '$name' is missing Summary.")
		}

		$functions = @($definition.Functions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
		if ($functions.Count -eq 0)
		{
			[void]$issues.Add("Scenario profile '$name' does not include any functions.")
			continue
		}

		$seenFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		foreach ($functionName in $functions)
		{
			if (-not $seenFunctions.Add([string]$functionName))
			{
				[void]$issues.Add("Scenario profile '$name' includes duplicate function '$functionName'.")
				continue
			}

			if ($manifestEntries.Count -eq 0)
			{
				continue
			}

			$entry = Get-ManifestEntryByFunction -Manifest $manifestEntries -Function ([string]$functionName)
			if ($null -eq $entry)
			{
				[void]$issues.Add("Scenario profile '$name' references missing function '$functionName'.")
				continue
			}

			$commandLine = Get-TweakManifestDefaultCommand -Entry $entry
			if ([string]::IsNullOrWhiteSpace([string]$commandLine))
			{
				[void]$issues.Add("Scenario profile '$name' function '$functionName' does not resolve to a runnable default command.")
			}
		}
	}

	return @($issues)
}

function Get-ScenarioProfilePlan
{
	<# .SYNOPSIS Builds the execution plan with metadata for a scenario profile. #>
	param (
		[array]$Manifest,
		[ValidateSet('Workstation', 'Privacy', 'Recovery')]
		[string]$ProfileName
	)

	$definition = Resolve-ScenarioProfileDefinition -ProfileName $ProfileName
	if ($null -eq $definition)
	{
		return @()
	}

	if (-not $Manifest)
	{
		$Manifest = @(Import-TweakManifestFromData)
	}
	if (-not $Manifest)
	{
		return @()
	}

	$validationIssues = @(Get-ScenarioProfileValidationIssues -Manifest $Manifest)
	if ($validationIssues.Count -gt 0)
	{
		throw ($validationIssues -join ' ')
	}

	$plan = [System.Collections.Generic.List[object]]::new()
	$seenFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($functionName in @($definition.Functions))
	{
		if ([string]::IsNullOrWhiteSpace([string]$functionName)) { continue }
		if (-not $seenFunctions.Add([string]$functionName)) { continue }

		$entry = Get-ManifestEntryByFunction -Manifest $Manifest -Function ([string]$functionName)
		if ($null -eq $entry) { continue }

		$commandLine = Get-TweakManifestDefaultCommand -Entry $entry
		if ([string]::IsNullOrWhiteSpace([string]$commandLine)) { continue }

		[void]$plan.Add([pscustomobject]@{
			Entry          = $entry
			Profile        = [string]$definition.Name
			Label          = [string]$definition.Label
			Function       = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Function')
			Name           = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Name')
			Category       = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Category')
			Type           = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Type')
			Risk           = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Risk')
			Restorable     = Get-TweakManifestEntryValue -Entry $entry -FieldName 'Restorable'
			RecoveryLevel  = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'RecoveryLevel')
			RequiresRestart = [bool](Get-TweakManifestEntryValue -Entry $entry -FieldName 'RequiresRestart')
			Command        = [string]$commandLine
			ReasonIncluded = "Included by the $([string]$definition.Label) scenario profile."
		})
	}

	return @($plan)
}

function Get-ScenarioProfileCommandList
{
	<# .SYNOPSIS Extracts the command list from a scenario profile plan. #>
	param (
		[array]$Manifest,
		[ValidateSet('Workstation', 'Privacy', 'Recovery')]
		[string]$ProfileName
	)

	return @(
		Get-ScenarioProfilePlan -Manifest $Manifest -ProfileName $ProfileName |
			ForEach-Object { [string]$_.Command } |
			Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
	)
}
