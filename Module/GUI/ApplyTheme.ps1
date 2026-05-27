		<#
		    .SYNOPSIS
		#>

		function Set-GUITheme
		{
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
			param (
				[hashtable]$Theme,
				[switch]$SkipContentRebuild
			)
			$themeRepairName = 'Dark'
			if ($Theme -eq $Script:LightTheme)
			{
				$Script:CurrentThemeName = 'Light'
				$themeRepairName = 'Light'
			}
			elseif ($Theme -eq $Script:DarkTheme)
			{
				$Script:CurrentThemeName = 'Dark'
				$themeRepairName = 'Dark'
			}
			else
			{
				$Script:CurrentThemeName = 'Custom'
			}
		$Theme = Repair-GuiThemePaletteWithReferences -Theme $Theme -ThemeName $themeRepairName
		$Script:CurrentTheme = $Theme
		Set-Variable -Name 'BaselineCurrentTheme' -Value $Theme -Scope Global -Force
		Set-Variable -Name 'BaselineCurrentThemeName' -Value $Script:CurrentThemeName -Scope Global -Force
		Set-Variable -Name 'BaselineUseDarkMode' -Value ($Script:CurrentThemeName -eq 'Dark') -Scope Global -Force
		$env:BASELINE_THEME_NAME = $Script:CurrentThemeName
		$env:BASELINE_USE_DARK_MODE = if ($Script:CurrentThemeName -eq 'Dark') { '1' } else { '0' }
		try { $env:BASELINE_THEME_JSON = ($Theme | ConvertTo-Json -Compress -Depth 4) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.SerializeThemeToEnv' }
		$Script:BrushCache = @{}
		$Script:SharedCardShadow = $null
		$Script:CardHoverResources = $null
		$bc = New-SafeBrushConverter -Context 'Set-GUITheme'

		if ([System.Windows.Application]::Current)
		{
			[void](Set-GuiThemeResources -Target ([System.Windows.Application]::Current) -ThemeName $(if ($Script:CurrentThemeName -eq 'Light') { 'Light' } else { 'Dark' }))
		}
		[void](Set-GuiThemeResources -Target $Form -ThemeName $(if ($Script:CurrentThemeName -eq 'Light') { 'Light' } else { 'Dark' }))
		$Form.Background = [System.Windows.Media.Brushes]::Transparent
		$Form.Foreground  = $bc.ConvertFromString($Theme.TextPrimary)
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $Form -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
		[void](GUICommon\Update-GuiPopupWindowThemes -Theme $Theme -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
		if ($WindowBorder) { $WindowBorder.Background = $bc.ConvertFromString($Theme.WindowBg); $WindowBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor) }
		if ($TitleBar) { $TitleBar.Background = $bc.ConvertFromString($Theme.HeaderBg) }
		if ($TitleBarText) { $TitleBarText.Foreground = $bc.ConvertFromString($Theme.TextPrimary) }
		if ($BtnMinimize) { Set-WindowCaptionButtonStyle -Button $BtnMinimize }
		if ($BtnMaximize) { Set-WindowCaptionButtonStyle -Button $BtnMaximize }
		if ($BtnClose) { Set-WindowCaptionButtonStyle -Button $BtnClose -Variant 'Close' }
		if (Get-Command -Name 'Update-GuiNavModeChrome' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Update-GuiNavModeChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.Set-GUITheme.UpdateGuiNavModeChrome' }
		}
		if ($Script:BtnUpdateAllApps) { Set-ButtonChrome -Button $Script:BtnUpdateAllApps -Variant 'Primary' -Compact }
		if ($Script:BtnDownloadYes) { Set-ButtonChrome -Button $Script:BtnDownloadYes -Variant 'Primary' }
		if ($Script:BtnDownloadNo) { Set-ButtonChrome -Button $Script:BtnDownloadNo -Variant 'Secondary' }
		$HeaderBorder.Background = $bc.ConvertFromString($Theme.HeaderBg)
		if ($HeaderSeparator) { $HeaderSeparator.Background = $bc.ConvertFromString($Theme.BorderColor) }
		$ContentBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		if ($Script:ExpertModeBanner)
		{
			$Script:ExpertModeBanner.Background = [System.Windows.Media.Brushes]::Transparent
			$Script:ExpertModeBanner.BorderBrush = [System.Windows.Media.Brushes]::Transparent
			$Script:ExpertModeBanner.BorderThickness = [System.Windows.Thickness]::new(0)
			$bannerText = $Script:ExpertModeBanner.Child
			if ($bannerText) { $bannerText.Foreground = $bc.ConvertFromString($Theme.CautionText) }
		}
		$BottomBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$BottomBorder.BorderBrush = $bc.ConvertFromString($Theme.CardBorder)
		$BottomBorder.CornerRadius = [System.Windows.CornerRadius]::new(0, 0, 8, 8)
		$TitleText.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
		$ScanLabel.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$currentStatusText = if ($StatusText) { [string]$StatusText.Text } else { '' }
		if ($Script:GuiState -and $Script:GuiState.PSObject.Methods['Get'])
		{
			try
			{
				$currentStatusText = [string](& $Script:GuiState.Get 'StatusText')
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.Set-GUITheme.ReadStatusText'
			}
		}
		Set-GuiStatusText -Text $currentStatusText -Tone $(if ($Script:CurrentStatusTone) { [string]$Script:CurrentStatusTone } else { 'muted' })
		Set-HeaderToggleControlsStyle
		if ($Script:UpdateDialogCard)
		{
			$Script:UpdateDialogCard.Background = $bc.ConvertFromString($Theme.CardBg)
			$Script:UpdateDialogCard.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
		}
		if ($Script:CustomPBarContainer) { $Script:CustomPBarContainer.Background = $bc.ConvertFromString($Theme.CardBorder) }
		foreach ($progressBar in @($Script:CustomProgressBar, $Script:ExecutionProgressBar, $Script:AppsProgressBar, $Script:PresetProgressBar, $Script:DeploymentMediaProgressBar))
		{
			if ($progressBar)
			{
				if ($progressBar -is [System.Windows.Controls.ProgressBar])
				{
					$progressBar.Foreground = ConvertTo-GuiBrush -Color $Theme.ProgressGreen -Context 'ApplyTheme.ProgressBar.Foreground'
					$progressBar.Background = ConvertTo-GuiBrush -Color $Theme.ProgressGreenTrack -Context 'ApplyTheme.ProgressBar.Background'
				}
				else
				{
					Set-SheenProgressBarTheme -ProgressBar $progressBar -Theme $Theme
				}
			}
		}
		if ($Script:AppsPackageManagerBanner)
		{
			$Script:AppsPackageManagerBanner.Background = $bc.ConvertFromString($Theme.CautionBg)
			$Script:AppsPackageManagerBanner.BorderBrush = $bc.ConvertFromString($Theme.CautionBorder)
		}
		if ($Script:TxtAppsPackageManagerBanner) { $Script:TxtAppsPackageManagerBanner.Foreground = $bc.ConvertFromString($Theme.CautionText) }
		if ($Script:DeploymentMediaStatusBanner)
		{
			$Script:DeploymentMediaStatusBanner.Background = $bc.ConvertFromString($Theme.CautionBg)
			$Script:DeploymentMediaStatusBanner.BorderBrush = $bc.ConvertFromString($Theme.CautionBorder)
		}
		if ($Script:TxtDeploymentMediaBuildStatus) { $Script:TxtDeploymentMediaBuildStatus.Foreground = $bc.ConvertFromString($Theme.CautionText) }
		if ($Script:TxtDeploymentMediaSelectionStatus) { $Script:TxtDeploymentMediaSelectionStatus.Foreground = $bc.ConvertFromString($Theme.TextSecondary) }
		if (Get-Command -Name 'Sync-GuiDeploymentMediaBuilderViewText' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Sync-GuiDeploymentMediaBuilderViewText } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.Set-GUITheme.SyncDeploymentMediaBuilderViewText' }
		}
		if ($Script:TxtAppSelectionStatus) { $Script:TxtAppSelectionStatus.Foreground = $bc.ConvertFromString($Theme.TextSecondary) }
		if ($Script:TxtAppsProgressText) { $Script:TxtAppsProgressText.Foreground = $bc.ConvertFromString($Theme.TextSecondary) }
		if ($Script:TxtOverlayTitle) { $Script:TxtOverlayTitle.Foreground = $bc.ConvertFromString($Theme.TextPrimary) }
		if ($Script:TxtUpdateDescription) { $Script:TxtUpdateDescription.Foreground = $bc.ConvertFromString($Theme.TextSecondary) }
		if ($Script:TxtDownloadProgressLabel) { $Script:TxtDownloadProgressLabel.Foreground = $bc.ConvertFromString($Theme.TextSecondary) }
		if ($Script:TxtDownloadProgressPct) { $Script:TxtDownloadProgressPct.Foreground = $bc.ConvertFromString($Theme.TextSecondary) }
		Set-SearchInputStyle
		Set-FilterControlStyle
		Set-StaticButtonStyle
		Update-PrimaryTabVisuals
		if (Get-Command -Name 'Update-AppsCategoryTabVisuals' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppsCategoryTabVisuals
		}
		if (Get-Command -Name 'Update-GuiMenuBarTheme' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-GuiMenuBarTheme
		}
		if (Get-Command -Name 'Update-GuiScrollBarTheme' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-GuiScrollBarTheme
		}
		if ($Script:UpdateGuiBackToTopButtonScript)
		{
			try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.Set-GUITheme.UpdateBackToTopButton' }
		}

		if (-not $SkipContentRebuild)
		{
			# Rebuild content for current tab to pick up new theme colors.
			$Script:FilterGeneration++
			Clear-TabContentCache
			$Script:AppsViewBuildSignature = $null
			if ($Script:AppsModeActive)
			{
				if (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Build-AppsViewCards
				}
			}
			elseif ($Script:GamingModeActive)
			{
				Build-TabContent -PrimaryTab 'Gaming' -SkipIdlePrebuild
			}
			elseif ($Script:DeploymentMediaModeActive)
			{
				if (Get-Command -Name 'Initialize-GuiDeploymentMediaBuilderView' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Initialize-GuiDeploymentMediaBuilderView
				}
				if (Get-Command -Name 'Sync-GuiDeploymentMediaBuilderViewText' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Sync-GuiDeploymentMediaBuilderViewText
				}
			}
			elseif (-not [string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab))
			{
				Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab -SkipIdlePrebuild
			}
		}
		Update-HeaderModeStateText
		if (Get-Command -Name 'Update-RunPathContextLabel' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-RunPathContextLabel
		}
	}

	<#
	    .SYNOPSIS
	    Returns 'Light' or 'Dark' based on the Windows AppsUseLightTheme registry value.
	#>
	function Get-BaselineSystemThemePreference
	{
		[CmdletBinding()]
		param ()

		try
		{
			$value = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
			if (-not $value.PSObject.Properties['AppsUseLightTheme']) { return 'Light' }
			if ([int]$value.AppsUseLightTheme -eq 1) { return 'Light' }
			return 'Dark'
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.Get-BaselineSystemThemePreference:catch209' -Severity Debug }

			return 'Light'
		}
	}

	<#
	    .SYNOPSIS
	    Maps a theme preference ('Light', 'Dark', 'System') to a concrete theme name.
	#>
	function Resolve-BaselineThemePreference
	{
		[CmdletBinding()]
		param (
			[string]$Preference
		)

		$normalized = if ([string]::IsNullOrWhiteSpace($Preference)) { 'System' } else { [string]$Preference }
		if ($normalized -eq 'System') { return (Get-BaselineSystemThemePreference) }
		if ($normalized -eq 'Light' -or $normalized -eq 'Dark') { return $normalized }
		return (Get-BaselineSystemThemePreference)
	}

	<#
	    .SYNOPSIS
	    Records the user's preference ('Light', 'Dark', 'System') and applies the
	    resolved concrete theme without losing the System preference.
	#>
	function Apply-BaselineThemePreference
	{
		[CmdletBinding()]
		param (
			[Parameter(Mandatory)]
			[string]$Preference,

			[switch]$SkipContentRebuild
		)

		$normalized = if ([string]::IsNullOrWhiteSpace($Preference)) { 'System' } else { [string]$Preference }
		if ($normalized -ne 'Light' -and $normalized -ne 'Dark' -and $normalized -ne 'System') { $normalized = 'System' }

		$Script:ThemePreference = $normalized
		$resolved = Resolve-BaselineThemePreference -Preference $normalized

		if ($ChkTheme)
		{
			$wantLight = ($resolved -eq 'Light')
			$Script:ThemeUiUpdating = $true
			try
			{
				$ChkTheme.IsChecked = $wantLight
			}
			finally
			{
				$Script:ThemeUiUpdating = $false
			}
			if ([bool]$ChkTheme.IsChecked -ne $wantLight)
			{
				$ChkTheme.IsChecked = $wantLight
			}
			if ($wantLight) { Set-GUITheme -Theme $Script:LightTheme -SkipContentRebuild:$SkipContentRebuild }
			else { Set-GUITheme -Theme $Script:DarkTheme -SkipContentRebuild:$SkipContentRebuild }
		}
		else
		{
			if ($resolved -eq 'Light') { Set-GUITheme -Theme $Script:LightTheme -SkipContentRebuild:$SkipContentRebuild }
			else { Set-GUITheme -Theme $Script:DarkTheme -SkipContentRebuild:$SkipContentRebuild }
		}

		$Script:ThemePreference = $normalized
		if (Get-Command -Name 'Set-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Set-BaselineUserPreference -Key 'Theme' -Value $normalized } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ApplyTheme.ApplyBaselineThemePreference.SavePreference' }
		}
	}
