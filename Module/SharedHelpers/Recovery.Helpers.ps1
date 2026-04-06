# Recovery helper slice for Baseline.
# Extracted from Manifest.Helpers.ps1 - contains direct undo command resolution
# and restore point recommendation logic.
#
# Dependencies (from Manifest.Helpers.ps1, loaded first):
#   Get-TweakManifestEntryValue, Write-ManifestValidationWarning

function Get-DirectUndoCommandForEntry
{
	<# .SYNOPSIS Resolves the direct undo/recovery command parameter for a tweak execution result. #>
	# $ManifestEntry = the canonical manifest definition (carries Type, OnParam, OffParam, Options, etc.)
	# Both are required; they are separate objects because runtime items may add/override fields.
	param (
		[object]$Entry,
		[object]$ManifestEntry
	)

	if ($null -eq $Entry -or $null -eq $ManifestEntry)
	{
		return $null
	}

	$typeValue = [string](Get-TweakManifestEntryValue -Entry $ManifestEntry -FieldName 'Type')
	if ($typeValue -ne 'Toggle')
	{
		return $null
	}

	$restorableValue = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Restorable'
	if ($null -eq $restorableValue -or -not [bool]$restorableValue)
	{
		return $null
	}

	$recoveryLevel = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'RecoveryLevel')
	if ([string]::IsNullOrWhiteSpace($recoveryLevel))
	{
		$recoveryLevel = [string](Get-TweakManifestEntryValue -Entry $ManifestEntry -FieldName 'RecoveryLevel')
	}
	if (-not [string]::IsNullOrWhiteSpace($recoveryLevel) -and $recoveryLevel -ne 'Direct')
	{
		return $null
	}

	$selectedParam = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'ToggleParam')
	if ([string]::IsNullOrWhiteSpace($selectedParam))
	{
		$selectedParam = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'OnParam')
	}
	if ([string]::IsNullOrWhiteSpace($selectedParam))
	{
		return $null
	}

	$manifestOnParam = [string](Get-TweakManifestEntryValue -Entry $ManifestEntry -FieldName 'OnParam')
	$manifestOffParam = [string](Get-TweakManifestEntryValue -Entry $ManifestEntry -FieldName 'OffParam')

	if (-not [string]::IsNullOrWhiteSpace($manifestOnParam) -and $selectedParam.Equals($manifestOnParam, [System.StringComparison]::OrdinalIgnoreCase))
	{
		return $manifestOffParam
	}

	if (-not [string]::IsNullOrWhiteSpace($manifestOffParam) -and $selectedParam.Equals($manifestOffParam, [System.StringComparison]::OrdinalIgnoreCase))
	{
		return $manifestOnParam
	}

	$winDefaultValue = Get-TweakManifestEntryValue -Entry $ManifestEntry -FieldName 'WinDefault'
	if ($null -ne $winDefaultValue)
	{
		return $(if ([bool]$winDefaultValue) { $manifestOnParam } else { $manifestOffParam })
	}

	# Neither OnParam/OffParam matched and WinDefault is absent - no undo command available.
	$fnName = if ($Entry.Function) { $Entry.Function } else { '(unknown)' }
	Write-ManifestValidationWarning "No undo command could be determined for '$fnName' - selected param did not match OnParam/OffParam and WinDefault is absent."
	return $null
}

function Test-ShouldRecommendRestorePoint
{
	<# .SYNOPSIS Evaluates selected tweaks and returns whether a restore point is recommended. #>
	param (
		[object[]]$SelectedTweaks
	)

	$selected = @($SelectedTweaks | Where-Object { $_ })

	# If CreateRestorePoint is already in the selection, a restore point will be
	# created during the run so there is no need to recommend one separately.
	$hasCreateRestorePoint = @($selected | Where-Object {
		$_.PSObject.Properties['Function'] -and [string]$_.Function -eq 'CreateRestorePoint'
	}).Count -gt 0
	if ($hasCreateRestorePoint)
	{
		return [pscustomobject]@{
			ShouldRecommend          = $false
			Severity                 = 'None'
			Message                  = $null
			Reasons                  = @()
			RestartRequiredCount     = 0
			NonDirectRecoveryCount   = 0
			CompatibilityBranchCount = 0
			HighRiskCount            = 0
			AdvancedTierCount        = 0
		}
	}

	$restartRequiredCount = 0
	$nonDirectRecoveryCount = 0
	$compatibilityBranchCount = 0
	$highRiskCount = 0
	$advancedTierCount = 0
	$reasonSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($tweak in $selected)
	{
		if ([bool](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'RequiresRestart'))
		{
			$restartRequiredCount++
			[void]$reasonSet.Add('restart-required changes')
		}

		$recoveryLevel = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'RecoveryLevel')
		if (-not [string]::IsNullOrWhiteSpace($recoveryLevel) -and $recoveryLevel -ne 'Direct')
		{
			$nonDirectRecoveryCount++
			[void]$reasonSet.Add('changes that do not have a direct in-app undo path')
		}

		$gamingPreviewGroup = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'GamingPreviewGroup')
		$isTroubleshootingOnly = [bool](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'TroubleshootingOnly')
		if ($isTroubleshootingOnly -or $gamingPreviewGroup -eq 'Compatibility & Troubleshooting')
		{
			$compatibilityBranchCount++
			[void]$reasonSet.Add('compatibility or troubleshooting changes')
		}

		if ([string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Risk') -eq 'High')
		{
			$highRiskCount++
			[void]$reasonSet.Add('high-risk changes')
		}

		if ([string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'PresetTier') -eq 'Advanced')
		{
			$advancedTierCount++
			[void]$reasonSet.Add('expert-level Advanced changes')
		}
	}

	$shouldRecommend = ($restartRequiredCount -gt 0 -or $nonDirectRecoveryCount -gt 0 -or $compatibilityBranchCount -gt 0 -or $highRiskCount -gt 0 -or $advancedTierCount -gt 0)
	$severity = if (-not $shouldRecommend)
	{
		'None'
	}
	elseif ($advancedTierCount -gt 0 -or $nonDirectRecoveryCount -gt 0 -or $compatibilityBranchCount -gt 0 -or $highRiskCount -gt 0)
	{
		'StronglyRecommended'
	}
	else
	{
		'Recommended'
	}

	$message = switch ($severity)
	{
		'StronglyRecommended' { 'Create a restore point before continuing. Recommended for expert-level, troubleshooting, compatibility, or harder-to-recover changes.'; break }
		'Recommended' { 'Create a restore point before continuing. Recommended for restart-requiring changes.'; break }
		default { $null }
	}

	return [pscustomobject]@{
		ShouldRecommend = $shouldRecommend
		Severity = $severity
		Message = $message
		Reasons = @($reasonSet | Sort-Object)
		RestartRequiredCount = $restartRequiredCount
		NonDirectRecoveryCount = $nonDirectRecoveryCount
		CompatibilityBranchCount = $compatibilityBranchCount
		HighRiskCount = $highRiskCount
		AdvancedTierCount = $advancedTierCount
	}
}
