<#
    .SYNOPSIS
    Configures Windows feature and capability selection.

    .DESCRIPTION
    Provides the GUI-facing request path for enabling or disabling Windows
    optional features and capabilities through Baseline's maintenance flow.
#>

using module ..\..\GUICommon.psm1


function Request-GuiSystemSelection
{
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('WindowsCapabilities', 'WindowsFeatures')]
		[string]
		$RequestType,

		[Parameter(Mandatory = $true)]
		[string]
		$Mode,

		[Parameter(Mandatory = $false)]
		[string[]]
		$SelectedNames = @()
	)

	$queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
	if (-not $queue)
	{
		throw "GUI execution could not open the $RequestType picker because the GUI request queue is unavailable."
	}

	$responseState = [hashtable]::Synchronized(@{
		Done = $false
		Result = $null
		Error = $null
	})

	$queue.Enqueue([PSCustomObject]@{
		Kind = '_InteractiveSelectionRequest'
		RequestType = $RequestType
		Mode = $Mode
		SelectedNames = @($SelectedNames)
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

function Resolve-SystemPickerUseDarkMode
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

function Get-SystemPickerTheme
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

function Resolve-SystemPickerGuiCommonPath
{
	param
	(
		[string]
		$ModulePath
	)

	if ([string]::IsNullOrWhiteSpace([string]$ModulePath))
	{
		return $null
	}

	$cursor = Split-Path -Path $ModulePath -Parent
	while (-not [string]::IsNullOrWhiteSpace([string]$cursor))
	{
		$candidate = Join-Path -Path $cursor -ChildPath 'GUICommon.psm1'
		if (Test-Path -LiteralPath $candidate)
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

function Resolve-SystemPickerSharedHelpersPath
{
	param
	(
		[string]
		$ModulePath
	)

	if ([string]::IsNullOrWhiteSpace([string]$ModulePath))
	{
		return $null
	}

	$cursor = Split-Path -Path $ModulePath -Parent
	while (-not [string]::IsNullOrWhiteSpace([string]$cursor))
	{
		$candidate = Join-Path -Path $cursor -ChildPath 'SharedHelpers.psm1'
		if (Test-Path -LiteralPath $candidate)
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

function Get-SystemPickerResolvedThemeColor
{
	param
	(
		[object]
		$Theme,

		[Parameter(Mandatory = $true)]
		[string]
		$ColorName,

		[string]
		$DefaultColor,

		[object]
		$BrushConverter,

		[object]
		$UseDarkMode = $true,

		[string]
		$ErrorSource = 'System.WindowsFeatures.ThemeColor'
	)

	$resolvedUseDarkMode = [bool]$UseDarkMode
	$fallbackColors = if ($resolvedUseDarkMode)
	{
		@{
			WindowBg = '#1E1E2E'
			BorderColor = '#333346'
		}
	}
	else
	{
		@{
			WindowBg = '#F3F5F8'
			BorderColor = '#D8DEE8'
		}
	}

	if (-not $BrushConverter)
	{
		$BrushConverter = New-Object System.Windows.Media.BrushConverter
	}

	$candidates = @()
	try
	{
		if ($Theme -and ($Theme -is [System.Collections.IDictionary]) -and $Theme.Contains($ColorName))
		{
			$value = [string]$Theme[$ColorName]
			if (-not [string]::IsNullOrWhiteSpace($value))
			{
				$candidates += $value
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source $ErrorSource
		}
		else
		{
			Write-Verbose ("{0}: {1}" -f $ErrorSource, $_.Exception.Message)
		}
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$DefaultColor))
	{
		$candidates += [string]$DefaultColor
	}
	if ($fallbackColors.ContainsKey($ColorName) -and -not [string]::IsNullOrWhiteSpace([string]$fallbackColors[$ColorName]))
	{
		$candidates += [string]$fallbackColors[$ColorName]
	}

	foreach ($candidate in $candidates)
	{
		try
		{
			[void]$BrushConverter.ConvertFromString([string]$candidate)
			return [string]$candidate
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source $ErrorSource
			}
			else
			{
				Write-Verbose ("{0}: {1}" -f $ErrorSource, $_.Exception.Message)
			}
		}
	}

	return $(if ($resolvedUseDarkMode) { '#1E1E2E' } else { '#F3F5F8' })
}

function Invoke-WindowsCapabilityDismOperation
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('Install', 'Uninstall')]
		[string]
		$Operation,

		[Parameter(Mandatory = $true)]
		[string]
		$Name,

		[ValidateRange(1, 86400)]
		[int]
		$TimeoutSeconds = 180
	)

	$dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
	if (-not (Test-Path -LiteralPath $dismPath -PathType Leaf))
	{
		throw "DISM executable not found: $dismPath"
	}

	$operationArguments = if ([string]::Equals($Operation, 'Install', [System.StringComparison]::OrdinalIgnoreCase))
	{
		@('/Online', '/Add-Capability', ("/CapabilityName:$Name"), '/NoRestart')
	}
	else
	{
		@('/Online', '/Remove-Capability', ("/CapabilityName:$Name"), '/NoRestart')
	}

	$result = Invoke-BaselineProcess `
		-FilePath $dismPath `
		-ArgumentList $operationArguments `
		-TimeoutSeconds $TimeoutSeconds `
		-CaptureOutput `
		-AllowedExitCodes @(0, 3010)

	if ($result.ExitCode -notin @(0, 3010))
	{
		$diagnostic = @(
			[string]$result.StandardOutput
			[string]$result.StandardError
		) -join [Environment]::NewLine
		throw ("DISM capability {0} failed for '{1}' with exit code {2}. {3}" -f $Operation.ToLowerInvariant(), $Name, $result.ExitCode, $diagnostic.Trim())
	}

	return $result
}

<#
.SYNOPSIS
	Optional features



.DESCRIPTION

Applies the Baseline behavior for optional features.
	.PARAMETER Uninstall
	Uninstall optional features

	.PARAMETER Install
	Install optional features

	.EXAMPLE
	WindowsCapabilities -Uninstall

	.EXAMPLE
	WindowsCapabilities -Install

	.NOTES
	A pop-up dialog box lets a user select features

	.NOTES
	Current user
#>

function WindowsCapabilities
{
	[CmdletBinding(DefaultParameterSetName = "Uninstall")]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Uninstall"
		)]
		[switch]
		$Uninstall,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Install"
		)]
		[switch]
		$Install,

		[Parameter(Mandatory = $false)]
		[string[]]
		$SelectedCapabilityNames,

		[Parameter(Mandatory = $false)]
		[switch]
		$CollectSelectionOnly,

		[Parameter(Mandatory = $false)]
		[switch]
		$UseDefaultSelection,

		[Parameter(Mandatory = $false)]
		[switch]
		$NonInteractive
	)

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\ModulePathResolution.ps1')
	$guiCommonPath = Resolve-SystemPickerGuiCommonPath -ModulePath $modulePath
	$sharedHelpersPath = Resolve-SystemPickerSharedHelpersPath -ModulePath $modulePath

	Add-Type -AssemblyName PresentationCore, PresentationFramework

	#region Variables
	# Initialize an array list to store the selected optional features
	$SelectedCapabilities = New-Object -TypeName System.Collections.ArrayList($null)
	$SelectionState = [PSCustomObject]@{
		Confirmed = $false
	}
	$script:WindowsCapabilitiesSelectionResult = $null
	$SelectedCapabilityNamesProvided = $PSBoundParameters.ContainsKey('SelectedCapabilityNames')
	# Selection defaults are defined in SharedHelpers/WindowsFeatures.Helpers.ps1 so
	# unit tests can validate selection logic without starting WPF.
	[string[]]$CheckedCapabilities = @(Get-WindowsCapabilityCheckedDefaults)
	[string[]]$UncheckedCapabilities = @(Get-WindowsCapabilityUncheckedDefaults)
	[string[]]$ExcludedCapabilities = @(Get-WindowsCapabilityExcludedDefaults)
	$CapabilityOperationTimeoutSeconds = 180
	#endregion Variables

	#region XAML Markup
	# This block defines the dialog XAML used at runtime.
		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilitySelectionDialogXaml.ps1')
	#endregion XAML Markup

	$Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))
	$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
		Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
	}

	$pickerBrushConverter = New-Object System.Windows.Media.BrushConverter

	# Apply theme styling
	$Theme = Get-SystemPickerTheme
	$UseDarkMode = Resolve-SystemPickerUseDarkMode
	$repairGuiThemePalette = Get-Command -Name 'GUICommon\Repair-GuiThemePalette' -CommandType Function -ErrorAction SilentlyContinue
	if ($repairGuiThemePalette)
	{
		$Theme = & $repairGuiThemePalette -Theme $Theme -ThemeName $(if ($UseDarkMode) { 'Dark' } else { 'Light' })
	}
	$windowBgDefault = if ($UseDarkMode) { [string]$Script:DarkTheme.WindowBg } else { [string]$Script:LightTheme.WindowBg }
	$borderColorDefault = if ($UseDarkMode) { [string]$Script:DarkTheme.BorderColor } else { [string]$Script:LightTheme.BorderColor }
	$windowBg = Get-SystemPickerResolvedThemeColor -Theme $Theme -ColorName 'WindowBg' -DefaultColor $windowBgDefault -BrushConverter $pickerBrushConverter -UseDarkMode $UseDarkMode -ErrorSource 'System.WindowsFeatures.OptionalFeaturesPicker.WindowBg'
	$borderColor = Get-SystemPickerResolvedThemeColor -Theme $Theme -ColorName 'BorderColor' -DefaultColor $borderColorDefault -BrushConverter $pickerBrushConverter -UseDarkMode $UseDarkMode -ErrorSource 'System.WindowsFeatures.OptionalFeaturesPicker.BorderColor'
	$RootBorder.Background = [System.Windows.Media.Brush]($pickerBrushConverter.ConvertFromString($windowBg))
	$RootBorder.BorderBrush = [System.Windows.Media.Brush]($pickerBrushConverter.ConvertFromString($borderColor))
	$RootBorder.BorderThickness = '1'
	if (Get-Command -Name 'Set-GuiWindowChromeTheme' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-GuiWindowChromeTheme -Window $Form -UseDarkMode $UseDarkMode
	}

	#region Functions
		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilityPatternMatching.ps1')

	<#
	    .SYNOPSIS
	    Gets selected capability list.

		#>

	function Get-SelectedCapabilityList
	{
		return @($SelectedCapabilities | Where-Object { $_ })
	}

	<#
	    .SYNOPSIS
	    Gets selected capability names.

		#>
	function Get-SelectedCapabilityNames
	{
		return @(
			Get-SelectedCapabilityList |
				ForEach-Object {[string]$_.Name} |
				Where-Object {-not [string]::IsNullOrWhiteSpace($_)}
		)
	}

	<#
	    .SYNOPSIS
	    Runs check box select all click.

	#>

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\SelectAllCapabilityHandler.ps1')

	# Friendly display names live in SharedHelpers/WindowsFeatures.Helpers.ps1
	$CapabilityFriendlyNames = Get-WindowsCapabilityFriendlyNameMap

	<#
	    .SYNOPSIS
	    Gets capability friendly name.

		#>

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilityFriendlyName.ps1')

	<#
	    .SYNOPSIS
	    Creates capability info icon.

		#>

	function New-CapabilityInfoIcon
	{
		param ([string]$TooltipText)

		return GUICommon\New-GuiPopupInfoIcon -TooltipText $(if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'Optional feature' } else { $TooltipText }) -Theme $Theme -UseDarkMode $UseDarkMode
	}

	<#
	    .SYNOPSIS
	    Adds capability control.

		#>

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilityControlFactory.ps1')
	#endregion Functions

	switch ($PSCmdlet.ParameterSetName)
	{
		"Install"
		{
			try
			{
				$State = "NotPresent"
				$ButtonContent = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceInstall' -Fallback 'Install'
				$ButtonAdd_Click = {
					param
					(
						[object[]]
						$CapabilityList
					)

					InstallButton -CapabilityList $CapabilityList
				}
			}
			catch [System.ComponentModel.Win32Exception]
			{
				LogError ($Localization.NoResponse -f "http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice")
				LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))

				return
			}
		}
		"Uninstall"
		{
			$State = "Installed"
			$ButtonContent = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceUninstall' -Fallback 'Uninstall'
			$ButtonAdd_Click = {
				param
				(
					[object[]]
					$CapabilityList
				)

				UninstallButton -CapabilityList $CapabilityList
			}
		}
	}

	if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedCapabilityNamesProvided -and -not $UseDefaultSelection)
	{
		$selectionResult = Request-GuiSystemSelection -RequestType 'WindowsCapabilities' -Mode $PSCmdlet.ParameterSetName -SelectedNames @($SelectedCapabilityNames)
		if ($null -ne $selectionResult)
		{
			$SelectedCapabilityNames = @($selectionResult.SelectedCapabilityNames)
			$SelectedCapabilityNamesProvided = $true
		}
	}

	if ($NonInteractive -and -not $SelectedCapabilityNamesProvided -and -not $UseDefaultSelection)
	{
		LogWarning 'Skipping optional features because no preselected capabilities were provided for noninteractive execution.'
		Write-ConsoleStatus -Status warning
		return
	}

	# Getting list of all capabilities according to the conditions
		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilityQuery.ps1')

	if (-not $Capabilities)
	{
		if ($CollectSelectionOnly)
		{
			return [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedCapabilityNames = @()
			}
		}
		LogInfo "Optional Features:"
		LogInfo "Skipping optional features because no preset-matched Optional features were found."
		Write-ConsoleStatus -Action "$(if ($PSCmdlet.ParameterSetName -eq 'Uninstall') { 'Uninstalling optional features' } else { 'Installing optional features' })" -Status warning
		return
	}

	if ($UseDefaultSelection -and -not $SelectedCapabilityNamesProvided -and -not $CollectSelectionOnly)
	{
		$SelectedCapabilityNames = @(
			$Capabilities |
				Where-Object -FilterScript { Test-CapabilityPatternMatch -CapabilityName $_.Name -Patterns $CheckedCapabilities } |
				ForEach-Object -Process { [string]$_.Name } |
				Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) }
		)
		$SelectedCapabilityNamesProvided = $true

		if ($SelectedCapabilityNames.Count -eq 0)
		{
			LogWarning 'Skipping optional features because the default capability selection is empty on this system.'
			Write-ConsoleStatus -Status warning
			return
		}
	}

	if ($SelectedCapabilityNamesProvided -and -not $CollectSelectionOnly)
	{
		$ResolvedSelectedCapabilities = @(
			$Capabilities | Where-Object -FilterScript {$SelectedCapabilityNames -contains $_.Name}
		)
		& $ButtonAdd_Click -CapabilityList $ResolvedSelectedCapabilities
		return
	}

	. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilityDialogForegroundActivation.ps1')
	$Button.IsEnabled = $false
	$Window.Add_Loaded({$Capabilities | Add-CapabilityControl})
	$Button.Content = $ButtonContent
	$Button.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$Button.FontSize = 12
	try { GUICommon\Set-GuiPopupActionButtonStyle -Button $Button -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowsCapabilities.SetPopupActionButtonStyle' }
	$TextBlockSelectAll.Text = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All'
	$TextBlockSelectAll.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	if ($Form.Foreground) { $TextBlockSelectAll.Foreground = $Form.Foreground }
	$Button.Add_Click({Confirm-WindowsCapabilitiesSelection})
	$CheckBoxSelectAll.Add_Click({Invoke-CapabilitySelectAllClick})

	$windowsCapabilitiesTitle = GUICommon\Get-GuiPopupLocalizedString -Key 'Tweak_WindowsCapabilities' -Fallback 'Windows Capabilities'
	$Form.Title = $windowsCapabilitiesTitle
	if (Test-Path -Path Function:\Add-GuiPopupWindowChrome)
	{
		[void](GUICommon\Add-GuiPopupWindowChrome -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Title $windowsCapabilitiesTitle -Theme $Theme -UseDarkMode $UseDarkMode)
	}
		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\CapabilityDialogThemeCallback.ps1')
	if (Test-Path -Path Function:\Register-GuiPopupThemeWindow)
	{
		[void](GUICommon\Register-GuiPopupThemeWindow -Window $Form -ThemeCallback $windowsCapabilitiesThemeCallback)
	}
	& $windowsCapabilitiesThemeCallback -Window $Form -Theme $Theme -UseDarkMode $UseDarkMode

	if ($Global:GUIMode -and -not $CollectSelectionOnly)
	{
		# GUI-mode runs collect the capability selection on the main UI thread when this tweak starts.
	}
	else
	{
		Initialize-WpfWindowForeground -Window $Form
		$Form.ShowDialog() | Out-Null
	}

	if ($CollectSelectionOnly)
	{
		return $script:WindowsCapabilitiesSelectionResult
	}

	if ($Form.PSObject.Properties['GuiPopupOperationError'] -and $Form.GuiPopupOperationError)
	{
		$operationError = $Form.GuiPopupOperationError
		Remove-HandledErrorRecord -ErrorRecord $operationError
		LogError "Failed to $(if ($PSCmdlet.ParameterSetName -eq 'Uninstall') { 'uninstall' } else { 'install' }) optional features: $($operationError.Exception.Message)"
		Write-ConsoleStatus -Status failed
		throw $operationError
	}

	if ($SelectionState.Confirmed)
	{
		Write-ConsoleStatus -Status success
	}

	if (-not $SelectionState.Confirmed)
	{
		LogWarning 'Skipping optional features because no selection was confirmed.'
		Write-ConsoleStatus -Status warning
	}
}

<#
	.SYNOPSIS
	Windows features



.DESCRIPTION

Applies the Baseline behavior for windows features.
	.PARAMETER Disable
	Disable Windows features

	.PARAMETER Enable
	Enable Windows features

	.EXAMPLE
	WindowsFeatures -Disable

	.EXAMPLE
	WindowsFeatures -Enable

	.NOTES
	A pop-up dialog box lets a user select features

	.NOTES
	Current user
#>

function WindowsFeatures
{
	[CmdletBinding(DefaultParameterSetName = "Disable")]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(Mandatory = $false)]
		[string[]]
		$SelectedFeatureNames,

		[Parameter(Mandatory = $false)]
		[switch]
		$CollectSelectionOnly,

		[Parameter(Mandatory = $false)]
		[switch]
		$UseDefaultSelection,

		[Parameter(Mandatory = $false)]
		[switch]
		$NonInteractive
	)

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsCapabilities\ModulePathResolution.ps1')
	$guiCommonPath = Resolve-SystemPickerGuiCommonPath -ModulePath $modulePath

	Add-Type -AssemblyName PresentationCore, PresentationFramework

	#region Variables
	# Initialize an array list to store the selected Windows features
	$SelectedFeatures = New-Object -TypeName System.Collections.ArrayList($null)
	$SelectionState = [PSCustomObject]@{
		Confirmed = $false
	}
	$script:WindowsFeaturesSelectionResult = $null
	$SelectedFeatureNamesProvided = $PSBoundParameters.ContainsKey('SelectedFeatureNames')
	# Selection defaults are defined in SharedHelpers/WindowsFeatures.Helpers.ps1.
	# (also fixes a missing-comma bug between "Recall" and "WorkFolders-Client").
	[string[]]$CheckedFeatures = @(Get-WindowsFeatureCheckedDefaults)
	[string[]]$UncheckedFeatures = @(Get-WindowsFeatureUncheckedDefaults)
	#endregion Variables

	#region XAML Markup
	# This block defines the dialog XAML used at runtime.
		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsFeatures\FeatureSelectionDialogXaml.ps1')
	#endregion XAML Markup

	$Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))
	$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
		Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
	}

	$pickerBrushConverter = New-Object System.Windows.Media.BrushConverter

	# Apply theme styling
	$Theme = Get-SystemPickerTheme
	$UseDarkMode = Resolve-SystemPickerUseDarkMode
	$repairGuiThemePalette = Get-Command -Name 'GUICommon\Repair-GuiThemePalette' -CommandType Function -ErrorAction SilentlyContinue
	if ($repairGuiThemePalette)
	{
		$Theme = & $repairGuiThemePalette -Theme $Theme -ThemeName $(if ($UseDarkMode) { 'Dark' } else { 'Light' })
	}
	$windowBgDefault = if ($UseDarkMode) { [string]$Script:DarkTheme.WindowBg } else { [string]$Script:LightTheme.WindowBg }
	$borderColorDefault = if ($UseDarkMode) { [string]$Script:DarkTheme.BorderColor } else { [string]$Script:LightTheme.BorderColor }
	$windowBg = Get-SystemPickerResolvedThemeColor -Theme $Theme -ColorName 'WindowBg' -DefaultColor $windowBgDefault -BrushConverter $pickerBrushConverter -UseDarkMode $UseDarkMode -ErrorSource 'System.WindowsFeatures.WindowsFeaturesPicker.WindowBg'
	$borderColor = Get-SystemPickerResolvedThemeColor -Theme $Theme -ColorName 'BorderColor' -DefaultColor $borderColorDefault -BrushConverter $pickerBrushConverter -UseDarkMode $UseDarkMode -ErrorSource 'System.WindowsFeatures.WindowsFeaturesPicker.BorderColor'
	$RootBorder.Background = [System.Windows.Media.Brush]($pickerBrushConverter.ConvertFromString($windowBg))
	$RootBorder.BorderBrush = [System.Windows.Media.Brush]($pickerBrushConverter.ConvertFromString($borderColor))
	$RootBorder.BorderThickness = '1'
	if (Get-Command -Name 'Set-GuiWindowChromeTheme' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-GuiWindowChromeTheme -Window $Form -UseDarkMode $UseDarkMode
	}

	#region Functions

	<#
	    .SYNOPSIS
	    Checks feature pattern match.

		#>

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsFeatures\FeaturePatternMatching.ps1')

	<#
	    .SYNOPSIS
	    Gets selected feature list.

		#>

	function Get-SelectedFeatureList
	{
		return @($SelectedFeatures | Where-Object { $_ })
	}

	<#
	    .SYNOPSIS
	    Gets selected feature names.

		#>
	function Get-SelectedFeatureNames
	{
		return @(
			Get-SelectedFeatureList |
				ForEach-Object {[string]$_.FeatureName} |
				Where-Object {-not [string]::IsNullOrWhiteSpace($_)}
		)
	}

	<#
	    .SYNOPSIS
	    Runs check box select all click.

	#>

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsFeatures\SelectAllFeatureHandler.ps1')

	<#
	    .SYNOPSIS
	    Creates feature info icon.

		#>

	function New-FeatureInfoIcon
	{
		param ([string]$TooltipText)

		return GUICommon\New-GuiPopupInfoIcon -TooltipText $(if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'Windows feature' } else { $TooltipText }) -Theme $Theme -UseDarkMode $UseDarkMode
	}

	<#
	    .SYNOPSIS
	    Adds feature control.

		#>

		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsFeatures\FeatureControlFactory.ps1')

	if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedFeatureNamesProvided -and -not $UseDefaultSelection)
	{
		$selectionResult = Request-GuiSystemSelection -RequestType 'WindowsFeatures' -Mode $PSCmdlet.ParameterSetName -SelectedNames @($SelectedFeatureNames)
		if ($null -ne $selectionResult)
		{
			$SelectedFeatureNames = @($selectionResult.SelectedFeatureNames)
			$SelectedFeatureNamesProvided = $true
		}
	}

	if ($NonInteractive -and -not $SelectedFeatureNamesProvided -and -not $UseDefaultSelection)
	{
		LogWarning 'Skipping Windows features because no preselected features were provided for noninteractive execution.'
		Write-ConsoleStatus -Status warning
		return
	}

	# Getting list of all optional features according to the conditions
		. (Join-Path $PSScriptRoot 'WindowsFeatures\WindowsFeatures\FeatureQuery.ps1')

	if (-not $Features)
	{
		if ($CollectSelectionOnly)
		{
			return [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedFeatureNames = @()
			}
		}
		LogInfo "Windows Features:"
		LogInfo "Skipping Windows features because no preset-matched Windows features were found."
		Write-ConsoleStatus -Action "$(if ($PSCmdlet.ParameterSetName -eq 'Disable') { 'Disabling Windows features' } else { 'Enabling Windows features' })" -Status warning
		return
	}

	if ($UseDefaultSelection -and -not $SelectedFeatureNamesProvided -and -not $CollectSelectionOnly)
	{
		$SelectedFeatureNames = @(
			$Features |
				Where-Object -FilterScript { Test-FeaturePatternMatch -FeatureName $_.FeatureName -Patterns $CheckedFeatures } |
				ForEach-Object -Process { [string]$_.FeatureName } |
				Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) }
		)
		$SelectedFeatureNamesProvided = $true

		if ($SelectedFeatureNames.Count -eq 0)
		{
			LogWarning 'Skipping Windows features because the default feature selection is empty on this system.'
			Write-ConsoleStatus -Status warning
			return
		}
	}

	if ($SelectedFeatureNamesProvided -and -not $CollectSelectionOnly)
	{
		$ResolvedSelectedFeatures = @(
			$Features | Where-Object -FilterScript {$SelectedFeatureNames -contains $_.FeatureName}
		)
		& $ButtonAdd_Click -FeatureList $ResolvedSelectedFeatures
		return
	}

	$Button.IsEnabled = $false
	$Window.Add_Loaded({$Features | Add-FeatureControl})
	$Button.Content = $ButtonContent
	$Button.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$Button.FontSize = 12
	try { GUICommon\Set-GuiPopupActionButtonStyle -Button $Button -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowsFeatures.SetPopupActionButtonStyle' }
	$TextBlockSelectAll.Text = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All'
	$TextBlockSelectAll.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	if ($Form.Foreground) { $TextBlockSelectAll.Foreground = $Form.Foreground }
	$Button.Add_Click({Confirm-WindowsFeaturesSelection})
	$CheckBoxSelectAll.Add_Click({Invoke-FeatureSelectAllClick})

	$windowsFeaturesTitle = GUICommon\Get-GuiPopupLocalizedString -Key 'Tweak_WindowsFeatures' -Fallback 'Windows Features'
	$Form.Title = $windowsFeaturesTitle
	if (Test-Path -Path Function:\Add-GuiPopupWindowChrome)
	{
		[void](GUICommon\Add-GuiPopupWindowChrome -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Title $windowsFeaturesTitle -Theme $Theme -UseDarkMode $UseDarkMode)
	}
	$windowsFeaturesThemeCallback = {
		param($Window, $Theme, $UseDarkMode)

		if ($Button)
		{
			try { GUICommon\Set-GuiPopupActionButtonStyle -Button $Button -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowsFeatures.ThemeCallback.SetPopupActionButtonStyle' }
		}

		if ($TextBlockSelectAll -and $Window.Foreground)
		{
			$TextBlockSelectAll.Foreground = $Window.Foreground
		}
	}.GetNewClosure()
	if (Test-Path -Path Function:\Register-GuiPopupThemeWindow)
	{
		[void](GUICommon\Register-GuiPopupThemeWindow -Window $Form -ThemeCallback $windowsFeaturesThemeCallback)
	}
	& $windowsFeaturesThemeCallback -Window $Form -Theme $Theme -UseDarkMode $UseDarkMode

	if ($Global:GUIMode -and -not $CollectSelectionOnly)
	{
		# GUI-mode runs collect the Windows feature selection on the main UI thread when this tweak starts.
	}
	else
	{
		Initialize-WpfWindowForeground -Window $Form
		$Form.ShowDialog() | Out-Null
	}

	if ($CollectSelectionOnly)
	{
		return $script:WindowsFeaturesSelectionResult
	}

	if ($Form.PSObject.Properties['GuiPopupOperationError'] -and $Form.GuiPopupOperationError)
	{
		$operationError = $Form.GuiPopupOperationError
		Remove-HandledErrorRecord -ErrorRecord $operationError
		LogError "Failed to $(if ($PSCmdlet.ParameterSetName -eq 'Disable') { 'disable' } else { 'enable' }) Windows features: $($operationError.Exception.Message)"
		Write-ConsoleStatus -Status failed
		throw $operationError
	}

	if ($SelectionState.Confirmed)
	{
		Write-ConsoleStatus -Status success
	}

	if (-not $SelectionState.Confirmed)
	{
		LogWarning 'Skipping Windows features because no selection was confirmed.'
		Write-ConsoleStatus -Status warning
	}
}
$ExportedFunctions = @(
    'Get-SystemPickerResolvedThemeColor',
    'Get-SystemPickerTheme',
    'Invoke-WindowsCapabilityDismOperation',
    'Request-GuiSystemSelection',
    'Resolve-SystemPickerGuiCommonPath',
    'Resolve-SystemPickerSharedHelpersPath',
    'Resolve-SystemPickerUseDarkMode',
    'WindowsCapabilities',
    'WindowsFeatures'
)
Export-ModuleMember -Function $ExportedFunctions
