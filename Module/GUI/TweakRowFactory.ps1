	# Pre-computed shared resources for card hover effects.

# Keep this explicit order so defaults and metadata helpers load before row factories and Build-TweakRow.
$tweakRowFactorySplitRoot = Join-Path $PSScriptRoot 'TweakRowFactory'
. (Join-Path $tweakRowFactorySplitRoot 'RowStateDefaults.ps1')
. (Join-Path $tweakRowFactorySplitRoot 'MetadataDetails.ps1')
. (Join-Path $tweakRowFactorySplitRoot 'ControlFactories.ps1')
	# Frozen DropShadowEffect instances are reused across all cards in the same
	# theme, avoiding per-card object allocation and WPF effect re-composition.
	$Script:CardHoverResources = $null

	$syncLinkedState = {
		param (
			[string]$TargetFunction,
			[bool]$IsChecked
		)

		if ([string]::IsNullOrWhiteSpace($TargetFunction)) { return }
		if ($Script:ApplyingGuiPreset) { return }
		Ensure-PendingLinkedStateCollections

		$fidx = $Script:FunctionToIndex[$TargetFunction]
		if ($null -eq $fidx) { return }

		$tctl = $Script:Controls[$fidx]
		if ($null -ne $tctl -and $tctl.PSObject.Properties["IsChecked"])
		{
			$tctl.IsChecked = $IsChecked
		}

		if ($IsChecked)
		{
			if ($Script:PendingLinkedUnchecks) { [void]$Script:PendingLinkedUnchecks.Remove($TargetFunction) }
			if ($Script:PendingLinkedChecks) { [void]$Script:PendingLinkedChecks.Add($TargetFunction) }
		}
		else
		{
			if ($Script:PendingLinkedChecks) { [void]$Script:PendingLinkedChecks.Remove($TargetFunction) }
			if ($Script:PendingLinkedUnchecks) { [void]$Script:PendingLinkedUnchecks.Add($TargetFunction) }
		}
	}

	# Pre-computed CornerRadius shared across all tweak row cards.
	$Script:CardCornerRadius6 = [System.Windows.CornerRadius]::new(6)
	# Pre-computed Thickness values reused across all tweak row cards to avoid
	# per-row allocations.  Thickness is immutable in WPF so sharing is safe.
	function Set-TweakRowFactoryDensityTokens
	{
		$densityTokens = Get-BaselineUiDensityTokens
		$Script:T = @{
			Zero            = [System.Windows.Thickness]::new(0)
			CheckBoxRight   = $densityTokens.CheckBoxRight
			ComboLeft       = [System.Windows.Thickness]::new(14, 0, 0, 0)
			StatusRow       = $densityTokens.StatusRow
			BadgePad        = [System.Windows.Thickness]::new(5, 1, 5, 1)
			RowDivider      = [System.Windows.Thickness]::new(0, 0, 0, 1)
			RowDividerFocus = [System.Windows.Thickness]::new(0, 0, 0, 2)
			CardBorder      = [System.Windows.Thickness]::new(1)
			CardBorderFocus = [System.Windows.Thickness]::new(2)
			AccentBorder    = [System.Windows.Thickness]::new(3, 0, 0, 1)
			AccentFocus     = [System.Windows.Thickness]::new(3, 0, 0, 2)
			DescIndent      = $densityTokens.DescIndent
			MetaIndent      = $densityTokens.MetaIndent
			BlastIndent     = $densityTokens.BlastIndent
			WhyIndent       = $densityTokens.WhyIndent
			DescFlush       = $densityTokens.DescFlush
			MetaFlush       = $densityTokens.MetaFlush
			BlastFlush      = $densityTokens.BlastFlush
			WhyFlush        = $densityTokens.WhyFlush
		}
	}
	Set-TweakRowFactoryDensityTokens

	<#
	    .SYNOPSIS
	#>

	function Build-TweakRow
	{
		param ([int]$Index, [object]$Tweak, [object]$BrushConverter = $null)

		$__perf = Start-GuiPerfScope -Name 'BuildTweakRow' -Note ("{0}:{1}:{2}" -f $Index, [string]$Tweak.Type, [string]$Tweak.Function) -Detailed
		try
		{
			if (-not (Test-TweakRowVisible -Tweak $Tweak))
			{
				return $null
			}

			# Cache shared row context parts that are identical for every row.
			$density = Get-BaselineUiDensity
			if (-not $Script:RowContextShared -or $Script:RowContextSharedTheme -ne $Script:CurrentThemeName -or $Script:RowContextSharedDensity -ne $density)
			{
				$densityTokens = Get-BaselineUiDensityTokens -Density $density
				$Script:RowContextShared = @{
					ConvertBrushCapture               = Get-GuiRuntimeCommand -Name 'ConvertTo-GuiBrush' -CommandType 'Function'
					GetExplicitSelectionDefinition    = ${function:Get-GuiExplicitSelectionDefinition}
					SetExplicitSelectionDefinition    = ${function:Set-GuiExplicitSelectionDefinition}
					RemoveExplicitSelectionDefinition = ${function:Remove-GuiExplicitSelectionDefinition}
					TestSelectionBulkUpdateInProgress = ${function:Test-GuiSelectionBulkUpdateInProgress}
					SyncGameModePlanFromControlsScript = ${function:Sync-GameModePlanFromGamingControls}
					UpdateRunActionAvailabilityScript = ${function:Update-GuiScopedRunActionAvailability}
					RowCardMargin                     = $densityTokens.RowCardMargin
					RowCardPadding                    = $densityTokens.RowCardPadding
					BadgeSpacing                      = $densityTokens.BadgeSpacing
					NameFontSize                      = [double]$densityTokens.NameFontSize
					LabelFontSize                     = [double]$densityTokens.LabelFontSize
					DetailFontSize                    = [double]$densityTokens.DetailFontSize
					NameLineHeight                    = [double]$densityTokens.NameLineHeight
					LabelLineHeight                   = [double]$densityTokens.LabelLineHeight
					DetailLineHeight                  = [double]$densityTokens.DetailLineHeight
					RowIconSize                       = [double]$densityTokens.RowIconSize
					SyncLinkedState                   = $syncLinkedState
					FallbackBrushConverter            = New-SafeBrushConverter -Context 'Build-TweakRow'
				}
				$Script:RowContextSharedTheme = $Script:CurrentThemeName
				$Script:RowContextSharedDensity = $density
			}
			$shared = $Script:RowContextShared
			$rowContext = [pscustomobject]@{
				BrushConverter                    = if ($BrushConverter) { $BrushConverter } else { $shared.FallbackBrushConverter }
				ConvertBrushCapture               = $shared.ConvertBrushCapture
				GetExplicitSelectionDefinition    = $shared.GetExplicitSelectionDefinition
				SetExplicitSelectionDefinition    = $shared.SetExplicitSelectionDefinition
				RemoveExplicitSelectionDefinition = $shared.RemoveExplicitSelectionDefinition
				TestSelectionBulkUpdateInProgress = $shared.TestSelectionBulkUpdateInProgress
				SyncGameModePlanFromControlsScript = $shared.SyncGameModePlanFromControlsScript
				UpdateRunActionAvailabilityScript = $shared.UpdateRunActionAvailabilityScript
				Metadata                          = Get-TweakVisualMetadata -Tweak $Tweak -StateSource $Script:Controls[$Index]
				UseCompactRecoveryLevelLabel      = ([string]$Tweak.Category -eq 'Initial Setup')
				RowCardMargin                     = $shared.RowCardMargin
				RowCardPadding                    = $shared.RowCardPadding
				BadgeSpacing                      = $shared.BadgeSpacing
				NameFontSize                      = $shared.NameFontSize
				LabelFontSize                     = $shared.LabelFontSize
				DetailFontSize                    = $shared.DetailFontSize
				NameLineHeight                    = $shared.NameLineHeight
				LabelLineHeight                   = $shared.LabelLineHeight
				DetailLineHeight                  = $shared.DetailLineHeight
				RowIconSize                       = $shared.RowIconSize
				SyncLinkedState                   = $shared.SyncLinkedState
			}

			switch ($Tweak.Type)
			{
				'Toggle' { return New-ToggleTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
				'Choice' { return New-ChoiceTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
				'NumericRange' { return New-NumericRangeTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
				'Date' { return New-DateTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
				'Action' { return New-ActionTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
			}

			return $null
		}
		finally
		{
			Stop-GuiPerfScope -Scope $__perf
		}
	}
	#endregion
