function Request-GuiUWPAppsSelection
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[ValidateSet('Install', 'Uninstall')]
			[string]
			$Mode,

			[Parameter(Mandatory = $false)]
			[bool]
			$ForAllUsersSelection = $false,

			[Parameter(Mandatory = $false)]
			[string[]]
			$SeedPackages = @()
		)

		$queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
		if (-not $queue)
		{
			throw 'GUI execution could not open the UWP app picker because the GUI request queue is unavailable.'
		}

		$responseState = [hashtable]::Synchronized(@{
			Done = $false
			Result = $null
			Error = $null
		})

		$queue.Enqueue([PSCustomObject]@{
			Kind = '_InteractiveSelectionRequest'
			RequestType = 'UWPApps'
			Mode = $Mode
			ForAllUsers = [bool]$ForAllUsersSelection
			SelectedPackages = @($SeedPackages)
			ResponseState = $responseState
		})

		while (-not [bool]$responseState['Done'])
		{
			$runState = Get-Variable -Name 'runState' -ValueOnly -ErrorAction Ignore
			if ($runState -and $runState.ContainsKey('AbortRequested') -and [bool]$runState['AbortRequested'])
			{
				return $null
			}

			Start-Sleep -Milliseconds 200
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$responseState['Error']))
		{
			throw [System.InvalidOperationException]::new([string]$responseState['Error'])
		}

		return $responseState['Result']
	}

		<#
		    .SYNOPSIS
		    Sets UWP apps execution result.

				#>

		function Set-UWPAppsExecutionResult
		{
			param
			(
			[Parameter(Mandatory = $true)]
			[ValidateSet('Success', 'Partial', 'Failed')]
			[string]
			$Outcome,

			[Parameter(Mandatory = $true)]
			[string]
			$Message
		)

			$script:UWPAppsExecutionResult = [PSCustomObject]@{
				Outcome = $Outcome
				Message = $Message
			}
		}

		function Get-UWPAppsConfirmedSelectionPackages
		{
			param
			(
				[Parameter(Mandatory = $false)]
				[object]
				$SelectionResult
			)

			if ($null -eq $SelectionResult)
			{
				return @()
			}

			$selectedPackagesProperty = $SelectionResult.PSObject.Properties['SelectedPackages']
			if ($null -eq $selectedPackagesProperty)
			{
				return @()
			}

			$confirmedPackages = New-Object 'System.Collections.Generic.List[string]'
			foreach ($package in @($selectedPackagesProperty.Value))
			{
				$packageName = [string]$package
				if (-not [string]::IsNullOrWhiteSpace($packageName))
				{
					[void]$confirmedPackages.Add($packageName)
				}
			}

			return $confirmedPackages.ToArray()
		}

		<#
		    .SYNOPSIS
		    Resolves the UWP apps picker theme mode from GUI state shared across runspaces.
		#>

		function Resolve-UWPAppsPickerUseDarkMode
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

		function Get-UWPAppsPickerTheme
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

		<#
		    .SYNOPSIS
		    Sets UWP apps picker surface.

				#>

		function Set-UWPAppsPickerSurface
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

			$resolvedUseDarkMode = GUICommon\Get-GuiBooleanValue -Value $UseDarkMode -Default (Resolve-UWPAppsPickerUseDarkMode) -Context 'Set-UWPAppsPickerSurface'

			$surfaceTheme = $Theme
			if (-not $surfaceTheme -or $surfaceTheme.Count -le 0)
			{
				$surfaceTheme = if ($resolvedUseDarkMode) { $Script:DarkTheme } else { $Script:LightTheme }
			}
			else
			{
				$repairGuiThemePalette = Get-Command -Name 'GUICommon\Repair-GuiThemePalette' -CommandType Function -ErrorAction SilentlyContinue
				if ($repairGuiThemePalette)
				{
					$surfaceTheme = & $repairGuiThemePalette -Theme $surfaceTheme -ThemeName $(if ($resolvedUseDarkMode) { 'Dark' } else { 'Light' })
				}
			}

			$defaultThemeColors = if ($resolvedUseDarkMode)
			{
				@{ WindowBg = '#0E111A'; PanelBg = '#161A26' }
			}
			else
			{
				@{ WindowBg = '#F0F2F6'; PanelBg = '#F0F2F6' }
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
						Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.ApplyRemovalResults.ThemeColor'
					}
					else
					{
						Write-Verbose ("UWPApps.ApplyRemovalResults.ThemeColor: {0}" -f $_.Exception.Message)
					}
				}

				return $DefaultColor
			}.GetNewClosure()

			$windowBg = & $getThemeColor -ColorName 'WindowBg' -DefaultColor ([string]$defaultThemeColors.WindowBg)
			$panelBg = & $getThemeColor -ColorName 'PanelBg' -DefaultColor ([string]$defaultThemeColors.PanelBg)

			if ($Window)
			{
				$Window.Background = $BrushConverter.ConvertFromString($windowBg)
			}
			if ($RootBorder)
			{
				$RootBorder.Background = $BrushConverter.ConvertFromString($windowBg)
			}
			if ($PanelContainer)
			{
				$PanelContainer.Background = $BrushConverter.ConvertFromString($panelBg)
			}
		}
