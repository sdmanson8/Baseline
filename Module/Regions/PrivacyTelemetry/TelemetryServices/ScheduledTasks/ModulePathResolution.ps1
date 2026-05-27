function Resolve-ScheduledTasksParentPath
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$StartPath,

		[Parameter(Mandatory = $true)]
		[string]$FileName
	)

	$cursor = if (Test-Path -LiteralPath $StartPath -PathType Leaf) { Split-Path -Path $StartPath -Parent } else { $StartPath }
	while (-not [string]::IsNullOrWhiteSpace([string]$cursor))
	{
		$candidate = Join-Path -Path $cursor -ChildPath $FileName
		if (Test-Path -LiteralPath $candidate -PathType Leaf)
		{
			return $candidate
		}

		$parent = Split-Path -Path $cursor -Parent
		if ([string]::Equals([string]$parent, [string]$cursor, [System.StringComparison]::OrdinalIgnoreCase))
		{
			break
		}
		$cursor = $parent
	}

	return $null
}

$scheduledTasksSeedPath = if (-not [string]::IsNullOrWhiteSpace([string]$PSCommandPath))
	{
		[string]$PSCommandPath
	}
	elseif ($MyInvocation.MyCommand.Module -and -not [string]::IsNullOrWhiteSpace([string]$MyInvocation.MyCommand.Module.Path))
	{
		[string]$MyInvocation.MyCommand.Module.Path
	}
	else
	{
		$null
	}
$modulePath = if ($scheduledTasksSeedPath) { Resolve-ScheduledTasksParentPath -StartPath $scheduledTasksSeedPath -FileName 'PrivacyTelemetry.TelemetryServices.psm1' } else { $null }
$guiCommonPath = if ($scheduledTasksSeedPath) { Resolve-ScheduledTasksParentPath -StartPath $scheduledTasksSeedPath -FileName 'GUICommon.psm1' } else { $null }

	function Resolve-ScheduledTasksPickerUseDarkMode
	{
		if (Test-Path -Path Variable:\Script:CurrentThemeName)
		{
			return ($Script:CurrentThemeName -ne 'Light')
		}

		if (Test-Path -Path Variable:\Global:BaselineCurrentThemeName)
		{
			return ([string]$Global:BaselineCurrentThemeName -ne 'Light')
		}

		if (Test-Path -Path Variable:\Global:BaselineUseDarkMode)
		{
			return [bool]$Global:BaselineUseDarkMode
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$env:BASELINE_USE_DARK_MODE))
		{
			return ([string]$env:BASELINE_USE_DARK_MODE -eq '1')
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$env:BASELINE_THEME_NAME))
		{
			return ([string]$env:BASELINE_THEME_NAME -ne 'Light')
		}

		return $true
	}

	function Get-ScheduledTasksPickerTheme
	{
		if (Test-Path -Path Variable:\Script:CurrentTheme)
		{
			return $Script:CurrentTheme
		}

		if (Test-Path -Path Variable:\Global:BaselineCurrentTheme)
		{
			return $Global:BaselineCurrentTheme
		}

		return @{}
	}

	function Set-ScheduledTasksPickerElementTheme
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[object]
			$Element,

			[Parameter(Mandatory = $true)]
			[System.Windows.Media.Brush]
			$TextBrush,

			[Parameter(Mandatory = $true)]
			[System.Windows.Media.Brush]
			$AccentBrush
		)

		if ($null -eq $Element)
		{
			return
		}

		if ($Element -is [System.Windows.Controls.TextBlock])
		{
			if ([string]$Element.Text -eq ([char]0x24D8).ToString())
			{
				$Element.Foreground = $AccentBrush
			}
			else
			{
				$Element.Foreground = $TextBrush
			}

			return
		}

		if ($Element -is [System.Windows.Controls.CheckBox])
		{
			$Element.Foreground = $TextBrush
		}

		if ((Test-GuiObjectField -Object $Element -FieldName 'Content') -and $null -ne $Element.Content -and $Element.Content -isnot [string])
		{
			Set-ScheduledTasksPickerElementTheme -Element $Element.Content -TextBrush $TextBrush -AccentBrush $AccentBrush
		}

		if ((Test-GuiObjectField -Object $Element -FieldName 'Children') -and $null -ne $Element.Children)
		{
			foreach ($child in @($Element.Children))
			{
				Set-ScheduledTasksPickerElementTheme -Element $child -TextBrush $TextBrush -AccentBrush $AccentBrush
			}
		}
	}

	function Set-ScheduledTasksPickerSurface
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[object]
			$Window,

			[Parameter(Mandatory = $true)]
			[System.Windows.Controls.Border]
			$RootBorder,

			[Parameter(Mandatory = $true)]
			[System.Windows.Controls.Panel]
			$PanelContainer,

			[Parameter(Mandatory = $false)]
			[object]
			$ScrollViewer = $null,

			[Parameter(Mandatory = $true)]
			[hashtable]
			$Theme,

			[Parameter(Mandatory = $true)]
			[System.Windows.Media.BrushConverter]
			$BrushConverter,

			[Parameter(Mandatory = $true)]
			[object]
			$UseDarkMode
		)

		$resolvedUseDarkMode = GUICommon\Get-GuiBooleanValue -Value $UseDarkMode -Default (Resolve-ScheduledTasksPickerUseDarkMode) -Context 'Set-ScheduledTasksPickerSurface'

		$surfaceTheme = $Theme
		if (-not $surfaceTheme -or $surfaceTheme.Count -le 0)
		{
			$surfaceTheme = Get-ScheduledTasksPickerTheme
		}

		$repairGuiThemePalette = Get-Command -Name 'GUICommon\Repair-GuiThemePalette' -CommandType Function -ErrorAction SilentlyContinue
		if ($surfaceTheme -and $surfaceTheme.Count -gt 0 -and $repairGuiThemePalette)
		{
			$surfaceTheme = & $repairGuiThemePalette -Theme $surfaceTheme -ThemeName $(if ($resolvedUseDarkMode) { 'Dark' } else { 'Light' })
		}

		$defaultThemeColors = if ($resolvedUseDarkMode)
		{
			@{
				WindowBg    = '#0E111A'
				PanelBg     = '#161A26'
				BorderColor = '#333346'
				TextPrimary = '#E5E7EB'
				AccentBlue  = '#89B4FA'
			}
		}
		else
		{
			@{
				WindowBg    = '#F0F2F6'
				PanelBg     = '#F0F2F6'
				BorderColor = '#D8DEE8'
				TextPrimary = '#111827'
				AccentBlue  = '#2563EB'
			}
		}

		$getThemeColor = {
			param(
				[string]$ColorName,
				[string]$DefaultColor
			)

			try
			{
				if ($surfaceTheme -and ($surfaceTheme -is [System.Collections.IDictionary]) -and $surfaceTheme.Contains($ColorName))
				{
					$value = [string]$surfaceTheme[$ColorName]
					if (-not [string]::IsNullOrWhiteSpace($value))
					{
						[void]$BrushConverter.ConvertFromString($value)
						return $value
					}
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'ScheduledTasks.SetSurface.ThemeColor'
				}
				else
				{
					Write-Verbose ("ScheduledTasks.SetSurface.ThemeColor: {0}" -f $_.Exception.Message)
				}
			}

			return $DefaultColor
		}.GetNewClosure()

		$windowBg = & $getThemeColor -ColorName 'WindowBg' -DefaultColor ([string]$defaultThemeColors.WindowBg)
		$panelBg = & $getThemeColor -ColorName 'PanelBg' -DefaultColor ([string]$defaultThemeColors.PanelBg)
		$borderColor = & $getThemeColor -ColorName 'BorderColor' -DefaultColor ([string]$defaultThemeColors.BorderColor)
		$textPrimary = & $getThemeColor -ColorName 'TextPrimary' -DefaultColor ([string]$defaultThemeColors.TextPrimary)
		$accentBlue = & $getThemeColor -ColorName 'AccentBlue' -DefaultColor ([string]$defaultThemeColors.AccentBlue)

		$textBrush = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($textPrimary)
		$accentBrush = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($accentBlue)

		if ($Window)
		{
			$Window.Foreground = $textBrush
		}
		if ($RootBorder)
		{
			$RootBorder.Background = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($windowBg)
			$RootBorder.BorderBrush = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($borderColor)
			$RootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		}
		if ($ScrollViewer)
		{
			$ScrollViewer.Background = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($panelBg)
			$ScrollViewer.BorderBrush = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($borderColor)
		}
		if ($PanelContainer)
		{
			$PanelContainer.Background = [System.Windows.Media.Brush]$BrushConverter.ConvertFromString($panelBg)
			foreach ($child in @($PanelContainer.Children))
			{
				Set-ScheduledTasksPickerElementTheme -Element $child -TextBrush $textBrush -AccentBrush $accentBrush
			}
		}
	}
