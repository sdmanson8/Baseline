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

<#
.SYNOPSIS
	Optional features

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
		$NonInteractive
	)

	Add-Type -AssemblyName PresentationCore, PresentationFramework

	#region Variables
	# Initialize an array list to store the selected optional features
	$SelectedCapabilities = New-Object -TypeName System.Collections.ArrayList($null)
	$SelectionState = [PSCustomObject]@{
		Confirmed = $false
	}
	$script:WindowsCapabilitiesSelectionResult = $null
	$SelectedCapabilityNamesProvided = $PSBoundParameters.ContainsKey('SelectedCapabilityNames')
	# The following optional features will have their checkboxes checked
	[string[]]$CheckedCapabilities = @(
		# Steps Recorder
		"App.StepsRecorder*"
	)

	# The following optional features will have their checkboxes unchecked
	[string[]]$UncheckedCapabilities = @(
		# Internet Explorer mode
		"Browser.InternetExplorer*",

		# Windows Media Player
		# If you want to leave "Multimedia settings" element in the advanced settings of Power Options do not uninstall this feature
		"Media.WindowsMediaPlayer*",

		# Voice Access / related speech capability entries
		"*VoiceAccess*"
	)

	# The following optional features will be excluded from the display
	[string[]]$ExcludedCapabilities = @(
		# The DirectX Database to configure and optimize apps when multiple Graphics Adapters are present
		"DirectX.Configuration.Database*",

		# Language components
		"Language.*",

		# Notepad
		"Microsoft.Windows.Notepad*",

		# Mail, contacts, and calendar sync component
		"OneCoreUAP.OneSync*",

		# Windows PowerShell Intergrated Scripting Enviroment
		"Microsoft.Windows.PowerShell.ISE*",

		# Management of printers, printer drivers, and printer servers
		"Print.Management.Console*",

		# Features critical to Windows functionality
		"Windows.Client.ShellComponents*"
	)
	#endregion Variables

	#region XAML Markup
	# The section defines the design of the upcoming dialog box
	[xml]$XAML = @"
	<Window
		xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		Name="Window"
		MinHeight="450" MinWidth="415"
		SizeToContent="Width" WindowStartupLocation="CenterScreen"
		TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
		FontFamily="Candara" FontSize="16" ShowInTaskbar="True"
		Background="#F1F1F1" Foreground="#262626">
		<Window.Resources>
			<Style TargetType="CheckBox">
				<Setter Property="IsChecked" Value="True"/>
			</Style>
			<Style TargetType="Button">
				<Setter Property="Margin" Value="20"/>
				<Setter Property="Padding" Value="10"/>
			</Style>
			<Style TargetType="Border">
				<Setter Property="Grid.Row" Value="1"/>
				<Setter Property="CornerRadius" Value="0"/>
				<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
				<Setter Property="BorderBrush" Value="#000000"/>
			</Style>
			<Style TargetType="ScrollViewer">
				<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>
				<Setter Property="BorderBrush" Value="#000000"/>
				<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
			</Style>
		</Window.Resources>
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>
			<Border>
				<ScrollViewer>
					<StackPanel Name="PanelContainer" Orientation="Vertical"/>
				</ScrollViewer>
			</Border>
			<Button Name="Button" Grid.Row="2"/>
		</Grid>
	</Window>
"@
	#endregion XAML Markup

	$Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))
	$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
		Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
	}

	#region Functions
	function Test-CapabilityPatternMatch
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]
			$CapabilityName,

			[string[]]
			$Patterns
		)

		foreach ($Pattern in $Patterns)
		{
			if ($CapabilityName -like $Pattern)
			{
				return $true
			}
		}

		return $false
	}

	function Get-CheckboxClicked
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$CheckBox
		)

		$Capability = $CheckBox.Tag

		if ($CheckBox.IsChecked)
		{
			if ($Capability -and ($Capability -notin $SelectedCapabilities))
			{
				[void]$SelectedCapabilities.Add($Capability)
			}
		}
		else
		{
			if ($Capability)
			{
				[void]$SelectedCapabilities.Remove($Capability)
			}
		}

		if ($SelectedCapabilities.Count -gt 0)
		{
			$Button.IsEnabled = $true
		}
		else
		{
			$Button.IsEnabled = $false
		}
	}

	function Test-CapabilitySeedSelected
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			$Capability
		)

		if ($SelectedCapabilityNamesProvided)
		{
			return [bool](@($SelectedCapabilityNames | Where-Object -FilterScript {$_ -eq $Capability.Name}).Count -gt 0)
		}

		return Test-CapabilityPatternMatch -CapabilityName $Capability.Name -Patterns $CheckedCapabilities
	}

	function Get-SelectedCapabilityList
	{
		return @($SelectedCapabilities | Where-Object { $_ })
	}

	function Get-SelectedCapabilityNames
	{
		return @(
			Get-SelectedCapabilityList |
				ForEach-Object {[string]$_.Name} |
				Where-Object {-not [string]::IsNullOrWhiteSpace($_)}
		)
	}

	function UninstallButton
	{
		param
		(
			[object[]]
			$CapabilityList = @(Get-SelectedCapabilityList)
		)

		try
		{
			$ResolvedCapabilityList = @($CapabilityList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Uninstalling optional features"
			LogInfo "Uninstalling optional features"
			LogInfo "Optional features selected for uninstall: $($ResolvedCapabilityList.Count)"

			if ($ResolvedCapabilityList.Count -eq 0)
			{
				LogInfo "No optional features were selected for removal. Skipping."
				Write-ConsoleStatus -Status success
				return
			}

			$AvailableCapabilityNames = (Get-WindowsCapability -Online -ErrorAction Stop).Name

			$CapabilitiesToRemove = @(
				$ResolvedCapabilityList | Where-Object -FilterScript {$_.Name -in $AvailableCapabilityNames}
			)

			if (-not $CapabilitiesToRemove)
			{
				throw "None of the selected optional features are currently available for removal."
			}

			foreach ($Capability in $CapabilitiesToRemove)
			{
				LogInfo "Uninstalling optional feature: $($Capability.Name)"
				Invoke-SilencedProgress {
					Remove-WindowsCapability -Online -Name $Capability.Name -ErrorAction Stop | Out-Null
				}
				LogInfo "Uninstalled optional feature: $($Capability.Name)"
			}

			if ([string]$ResolvedCapabilityList.Name -match "Browser.InternetExplorer")
			{
				#LogWarning $Localization.RestartWarning
			}
				Write-ConsoleStatus -Status success
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogError "Failed to uninstall optional features: $($_.Exception.Message)"
			Write-ConsoleStatus -Status failed
		}
	}

	function InstallButton
	{
		param
		(
			[object[]]
			$CapabilityList = @(Get-SelectedCapabilityList)
		)

		try
		{
			$ResolvedCapabilityList = @($CapabilityList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Installing optional features"
			LogInfo "Installing optional features"
			LogInfo "Optional features selected for install: $($ResolvedCapabilityList.Count)"

			if ($ResolvedCapabilityList.Count -eq 0)
			{
				throw "No optional features were selected for installation."
			}

			$AvailableCapabilityNames = (Get-WindowsCapability -Online -ErrorAction Stop).Name

			$CapabilitiesToInstall = @(
				$ResolvedCapabilityList | Where-Object -FilterScript {$_.Name -in $AvailableCapabilityNames}
			)

			if (-not $CapabilitiesToInstall)
			{
				throw "None of the selected optional features are currently available for installation."
			}

			foreach ($Capability in $CapabilitiesToInstall)
			{
				LogInfo "Installing optional feature: $($Capability.Name)"
				Invoke-SilencedProgress {
					Add-WindowsCapability -Online -Name $Capability.Name -ErrorAction Stop | Out-Null
				}
				LogInfo "Installed optional feature: $($Capability.Name)"
			}

			if ([string]$ResolvedCapabilityList.Name -match "Browser.InternetExplorer")
			{
				#LogWarning $Localization.RestartWarning
			}
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			if ($_.Exception -is [System.Runtime.InteropServices.COMException])
			{
				LogError ($Localization.NoResponse -f "http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice")
				LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))
			}
			else
			{
				LogError "Failed to install optional features: $($_.Exception.Message)"
			}
			Write-ConsoleStatus -Status failed
			return
		}
			Write-ConsoleStatus -Status success
	}

	function Confirm-WindowsCapabilitiesSelection
	{
		$SelectedCapabilityList = @(Get-SelectedCapabilityList)
		$SelectionState.Confirmed = $true

		if ($CollectSelectionOnly)
		{
			$script:WindowsCapabilitiesSelectionResult = [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedCapabilityNames = @(Get-SelectedCapabilityNames)
			}
			if ($null -ne $Window)
			{
				[void]$Window.Close()
			}
			return
		}

		if ($null -ne $Window)
		{
			[void]$Window.Close()
		}

		& $ButtonAdd_Click -CapabilityList $SelectedCapabilityList
	}

	# Friendly display names for capabilities whose DisplayName is empty or unhelpful
	$CapabilityFriendlyNames = @{
		'App.StepsRecorder'                  = 'Steps Recorder'
		'App.WiredNetworkDriverInstaller'    = 'Wired Network Driver Installer'
		'Browser.InternetExplorer'           = 'Internet Explorer Mode'
		'Hello.Face'                         = 'Windows Hello Face'
		'MathRecognizer'                     = 'Math Recognizer'
		'Media.WindowsMediaPlayer'           = 'Windows Media Player'
		'Microsoft.Wallpapers.Extended'      = 'Extended Wallpapers'
		'Microsoft.Windows.MSPaint'          = 'Microsoft Paint'
		'Microsoft.Windows.Notepad.System'   = 'Notepad (System)'
		'Microsoft.Windows.WordPad'          = 'WordPad'
		'OpenSSH.Client'                     = 'OpenSSH Client'
		'OpenSSH.Server'                     = 'OpenSSH Server'
		'Print.Fax.Scan'                     = 'Windows Fax and Scan'
		'Accessibility.Braille'              = 'Accessibility - Braille Support'
		'App.Support.QuickAssist'            = 'Quick Assist'
		'VoiceAccess'                        = 'Voice Access'
	}

	function Get-CapabilityFriendlyName
	{
		param ([string]$Name, [string]$DisplayName)

		if (-not [string]::IsNullOrWhiteSpace($DisplayName))
		{
			return $DisplayName
		}

		# Strip version suffix (e.g. ~~~~0.0.1.0) and match against friendly names
		$baseName = ($Name -replace '~.*$', '').TrimEnd('~')
		foreach ($pattern in $CapabilityFriendlyNames.Keys)
		{
			if ($baseName -like "$pattern*")
			{
				return $CapabilityFriendlyNames[$pattern]
			}
		}

		# Last resort: strip the version suffix and return as-is
		return $baseName
	}

	function New-CapabilityInfoIcon
	{
		param ([string]$TooltipText)

		$icon = New-Object -TypeName System.Windows.Controls.TextBlock
		$icon.Text = [char]0x24D8  # info icon
		$icon.FontSize = 14
		$icon.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
		$icon.VerticalAlignment = 'Center'
		$icon.Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
		$icon.Cursor = [System.Windows.Input.Cursors]::Arrow
		$icon.ToolTip = $(if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'Optional feature' } else { $TooltipText })
		[System.Windows.Controls.ToolTipService]::SetPlacement($icon, [System.Windows.Controls.Primitives.PlacementMode]::Right)
		[System.Windows.Controls.ToolTipService]::SetShowDuration($icon, 20000)
		[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($icon, 150)
		return $icon
	}

	function Add-CapabilityControl
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$Capability
		)

		process
		{
			$CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
			$CheckBox.Add_Click({Get-CheckboxClicked -CheckBox $_.Source})
			$CheckBox.Tag = $Capability
			$CheckBox.VerticalAlignment = 'Center'
			$CheckBox.Margin = [System.Windows.Thickness]::new(10, 10, 5, 10)

			$CapabilityLabel = Get-CapabilityFriendlyName -Name $Capability.Name -DisplayName $Capability.DisplayName
			$tooltipText = if (-not [string]::IsNullOrWhiteSpace($Capability.Description))
			{
				[string]$Capability.Description
			}
			elseif (-not [string]::IsNullOrWhiteSpace($Capability.DisplayName))
			{
				"Optional feature: $($Capability.DisplayName)"
			}
			else
			{
				"Optional feature: $CapabilityLabel"
			}

			$TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
			$TextBlock.Text = $CapabilityLabel
			$TextBlock.VerticalAlignment = 'Center'
			$TextBlock.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)

			$infoIcon = New-CapabilityInfoIcon -TooltipText $tooltipText

			$rowPanel = New-Object -TypeName System.Windows.Controls.DockPanel
			$rowPanel.LastChildFill = $true
			$rowPanel.HorizontalAlignment = 'Stretch'
			$rowPanel.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)

			[System.Windows.Controls.DockPanel]::SetDock($CheckBox, [System.Windows.Controls.Dock]::Left)
			[void]$rowPanel.Children.Add($CheckBox)

			$infoPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$infoPanel.Orientation = 'Horizontal'
			$infoPanel.VerticalAlignment = 'Center'
			$infoPanel.HorizontalAlignment = 'Right'
			$infoPanel.Margin = [System.Windows.Thickness]::new(8, 0, 10, 0)
			[void]$infoPanel.Children.Add($infoIcon)

			[System.Windows.Controls.DockPanel]::SetDock($infoPanel, [System.Windows.Controls.Dock]::Right)
			[void]$rowPanel.Children.Add($infoPanel)

			[void]$rowPanel.Children.Add($TextBlock)
			[void]$PanelContainer.Children.Add($rowPanel)

			if (Test-CapabilitySeedSelected -Capability $Capability)
			{
				[void]$SelectedCapabilities.Add($Capability)
			}
			else
			{
				$CheckBox.IsChecked = $false
			}

			if ($null -ne $Button)
			{
				$Button.IsEnabled = ($SelectedCapabilities.Count -gt 0)
			}
		}
	}
	#endregion Functions

	switch ($PSCmdlet.ParameterSetName)
	{
		"Install"
		{
			try
			{
				$State = "NotPresent"
				$ButtonContent = $Localization.Install
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
			$ButtonContent = $Localization.Uninstall
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

	if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedCapabilityNamesProvided)
	{
		$selectionResult = Request-GuiSystemSelection -RequestType 'WindowsCapabilities' -Mode $PSCmdlet.ParameterSetName -SelectedNames @($SelectedCapabilityNames)
		if ($null -ne $selectionResult)
		{
			$SelectedCapabilityNames = @($selectionResult.SelectedCapabilityNames)
			$SelectedCapabilityNamesProvided = $true
		}
	}

	if ($NonInteractive -and -not $SelectedCapabilityNamesProvided)
	{
		LogWarning 'Skipping optional features because no preselected capabilities were provided for noninteractive execution.'
		Write-ConsoleStatus -Status warning
		return
	}

	# Getting list of all capabilities according to the conditions
	try
	{
		$Capabilities = Get-WindowsCapability -Online -ErrorAction Stop |
			Where-Object -FilterScript {
				$CapabilityName = $_.Name
				($_.State -eq $State) -and
				(
					(Test-CapabilityPatternMatch -CapabilityName $CapabilityName -Patterns $UncheckedCapabilities) -or
					(Test-CapabilityPatternMatch -CapabilityName $CapabilityName -Patterns $CheckedCapabilities)
				) -and
				-not (Test-CapabilityPatternMatch -CapabilityName $CapabilityName -Patterns $ExcludedCapabilities)
			} |
			Sort-Object -Property DisplayName, Name
	}
	catch
	{
		Remove-HandledErrorRecord -ErrorRecord $_
		$Capabilities = $null
	}

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
		LogInfo "No preset-matched Optional features were found. Moving on."
		Write-ConsoleStatus -Action "$(if ($PSCmdlet.ParameterSetName -eq 'Uninstall') { 'Uninstalling optional features' } else { 'Installing optional features' })" -Status success
		return
	}

	if ($SelectedCapabilityNamesProvided -and -not $CollectSelectionOnly)
	{
		$ResolvedSelectedCapabilities = @(
			$Capabilities | Where-Object -FilterScript {$SelectedCapabilityNames -contains $_.Name}
		)
		& $ButtonAdd_Click -CapabilityList $ResolvedSelectedCapabilities
		return
	}

	#region Sendkey function
	# Emulate the Backspace key sending to prevent the console window to freeze
	Start-Sleep -Milliseconds 500

	Add-Type -AssemblyName System.Windows.Forms

	# We cannot use Get-Process -Id $PID as script might be invoked via Terminal with different $PID
	Get-Process -Name powershell, WindowsTerminal -ErrorAction Ignore | Where-Object -FilterScript {$_.MainWindowTitle -match "Baseline \| Utility for Windows"} | ForEach-Object -Process {
		# Show window, if minimized
		[WinAPI.ForegroundWindow]::ShowWindowAsync($_.MainWindowHandle, 10)

		Start-Sleep -Milliseconds 150

		# Force move the console window to the foreground
		[WinAPI.ForegroundWindow]::SetForegroundWindow($_.MainWindowHandle)

		Start-Sleep -Milliseconds 150

		# Emulate the Backspace key sending
		[System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE 1}")
	}
	#endregion Sendkey function
	$Button.IsEnabled = $false
	$Window.Add_Loaded({$Capabilities | Add-CapabilityControl})
	$Button.Content = $ButtonContent
	$Button.Add_Click({Confirm-WindowsCapabilitiesSelection})

	$Window.Title = $Localization.OptionalFeaturesTitle

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

	if (-not $SelectionState.Confirmed)
	{
		LogWarning 'Skipping optional features because no selection was confirmed.'
		Write-ConsoleStatus -Status warning
	}
}

<#
	.SYNOPSIS
	Windows features

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
		$NonInteractive
	)

	Add-Type -AssemblyName PresentationCore, PresentationFramework

	#region Variables
	# Initialize an array list to store the selected Windows features
	$SelectedFeatures = New-Object -TypeName System.Collections.ArrayList($null)
	$SelectionState = [PSCustomObject]@{
		Confirmed = $false
	}
	$script:WindowsFeaturesSelectionResult = $null
	$SelectedFeatureNamesProvided = $PSBoundParameters.ContainsKey('SelectedFeatureNames')
	# The following Windows features will have their checkboxes checked
	[string[]]$CheckedFeatures = @(
		# Legacy Components
		"LegacyComponents",

		# PowerShell 2.0
		"MicrosoftWindowsPowerShellV2",
		"MicrosoftWindowsPowershellV2Root",

		# Microsoft XPS Document Writer
		"Printing-XPSServices-Features",

		# Recall
		"Recall"

		# Work Folders Client
		"WorkFolders-Client"
	)

	# The following Windows features will have their checkboxes unchecked
	[string[]]$UncheckedFeatures = @(
		# Media Features
		# If you want to leave "Multimedia settings" in the advanced settings of Power Options do not disable this feature
		"MediaPlayback",

		# Windows Sandbox
		"Containers-DisposableClientVM",

		# Windows Defender Application Guard
		"Windows-Defender-ApplicationGuard"
	)
	#endregion Variables

	#region XAML Markup
	# The section defines the design of the upcoming dialog box
	[xml]$XAML = @"
	<Window
		xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		Name="Window"
		MinHeight="450" MinWidth="415"
		SizeToContent="Width" WindowStartupLocation="CenterScreen"
		TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
		FontFamily="Candara" FontSize="16" ShowInTaskbar="True"
		Background="#F1F1F1" Foreground="#262626">
		<Window.Resources>
			<Style TargetType="CheckBox">
				<Setter Property="IsChecked" Value="True"/>
			</Style>
			<Style TargetType="Button">
				<Setter Property="Margin" Value="20"/>
				<Setter Property="Padding" Value="10"/>
			</Style>
			<Style TargetType="Border">
				<Setter Property="Grid.Row" Value="1"/>
				<Setter Property="CornerRadius" Value="0"/>
				<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
				<Setter Property="BorderBrush" Value="#000000"/>
			</Style>
			<Style TargetType="ScrollViewer">
				<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>
				<Setter Property="BorderBrush" Value="#000000"/>
				<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
			</Style>
		</Window.Resources>
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>
			<Border>
				<ScrollViewer>
					<StackPanel Name="PanelContainer" Orientation="Vertical"/>
				</ScrollViewer>
			</Border>
			<Button Name="Button" Grid.Row="2"/>
		</Grid>
	</Window>
"@
	#endregion XAML Markup

	$Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))
	$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
		Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
	}

	#region Functions

	function Test-FeaturePatternMatch
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]
			$FeatureName,

			[string[]]
			$Patterns
		)

		foreach ($Pattern in $Patterns)
		{
			if ($FeatureName -like $Pattern)
			{
				return $true
			}
		}

		return $false
	}

	function Get-CheckboxClicked
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$CheckBox
		)

		$Feature = $CheckBox.Tag

		if ($CheckBox.IsChecked)
		{
			if ($Feature -and ($Feature -notin $SelectedFeatures))
			{
				[void]$SelectedFeatures.Add($Feature)
			}
		}
		else
		{
			if ($Feature)
			{
				[void]$SelectedFeatures.Remove($Feature)
			}
		}
		if ($SelectedFeatures.Count -gt 0)
		{
			$Button.IsEnabled = $true
		}
		else
		{
			$Button.IsEnabled = $false
		}
	}

	function Test-FeatureSeedSelected
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			$Feature
		)

		if ($SelectedFeatureNamesProvided)
		{
			return [bool](@($SelectedFeatureNames | Where-Object -FilterScript {$_ -eq $Feature.FeatureName}).Count -gt 0)
		}

		return Test-FeaturePatternMatch -FeatureName $Feature.FeatureName -Patterns $CheckedFeatures
	}

	function Get-SelectedFeatureList
	{
		return @($SelectedFeatures | Where-Object { $_ })
	}

	function Get-SelectedFeatureNames
	{
		return @(
			Get-SelectedFeatureList |
				ForEach-Object {[string]$_.FeatureName} |
				Where-Object {-not [string]::IsNullOrWhiteSpace($_)}
		)
	}

	function DisableButton
	{
		param
		(
			[object[]]
			$FeatureList = @(Get-SelectedFeatureList)
		)

		try
		{
			$ResolvedFeatureList = @($FeatureList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Disabling Windows features"
			LogInfo "Disabling Windows features"
			LogInfo "Windows features selected for disable: $($ResolvedFeatureList.Count)"

			if ($ResolvedFeatureList.Count -eq 0)
			{
				throw "No Windows features were selected."
			}

			foreach ($Feature in $ResolvedFeatureList)
			{
				LogInfo "Disabling Windows feature: $($Feature.FeatureName)"
				Invoke-SilencedProgress {
					Disable-WindowsOptionalFeature -FeatureName $Feature.FeatureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
				}
				LogInfo "Disabled Windows feature: $($Feature.FeatureName)"
			}
				Write-ConsoleStatus -Status success
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogError "Failed to disable Windows features: $($_.Exception.Message)"
			Write-ConsoleStatus -Status failed
		}
	}

	function EnableButton
	{
		param
		(
			[object[]]
			$FeatureList = @(Get-SelectedFeatureList)
		)

		try
		{
			$ResolvedFeatureList = @($FeatureList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Enabling Windows features"
			LogInfo "Enabling Windows features"
			LogInfo "Windows features selected for enable: $($ResolvedFeatureList.Count)"

			if ($ResolvedFeatureList.Count -eq 0)
			{
				throw "No Windows features were selected."
			}

			foreach ($Feature in $ResolvedFeatureList)
			{
				LogInfo "Enabling Windows feature: $($Feature.FeatureName)"
				Invoke-SilencedProgress {
					Enable-WindowsOptionalFeature -FeatureName $Feature.FeatureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
				}
				LogInfo "Enabled Windows feature: $($Feature.FeatureName)"
			}
				Write-ConsoleStatus -Status success
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogError "Failed to enable Windows features: $($_.Exception.Message)"
			Write-ConsoleStatus -Status failed
		}
	}

	function Confirm-WindowsFeaturesSelection
	{
		$SelectedFeatureList = @(Get-SelectedFeatureList)
		$SelectionState.Confirmed = $true

		if ($CollectSelectionOnly)
		{
			$script:WindowsFeaturesSelectionResult = [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedFeatureNames = @(Get-SelectedFeatureNames)
			}
			if ($null -ne $Window)
			{
				[void]$Window.Close()
			}
			return
		}

		if ($null -ne $Window)
		{
			[void]$Window.Close()
		}

		& $ButtonAdd_Click -FeatureList $SelectedFeatureList
	}

	# Friendly display names for features whose DisplayName is empty or is just the internal name
	$FeatureFriendlyNames = @{
		'LegacyComponents'                       = 'Legacy Components'
		'MicrosoftWindowsPowerShellV2'            = 'PowerShell 2.0 Engine'
		'MicrosoftWindowsPowershellV2Root'        = 'PowerShell 2.0'
		'Printing-XPSServices-Features'           = 'Microsoft XPS Document Writer'
		'Recall'                                  = 'Recall'
		'WorkFolders-Client'                      = 'Work Folders Client'
		'MediaPlayback'                           = 'Media Features'
		'Containers-DisposableClientVM'           = 'Windows Sandbox'
		'Windows-Defender-ApplicationGuard'       = 'Windows Defender Application Guard'
		'Microsoft-Hyper-V-All'                   = 'Hyper-V'
		'VirtualMachinePlatform'                  = 'Virtual Machine Platform'
		'HypervisorPlatform'                      = 'Windows Hypervisor Platform'
		'Microsoft-Windows-Subsystem-Linux'       = 'Windows Subsystem for Linux'
		'Printing-PrintToPDFServices-Features'    = 'Microsoft Print to PDF'
		'NetFx3'                                  = '.NET Framework 3.5'
		'TelnetClient'                            = 'Telnet Client'
		'TFTP'                                    = 'TFTP Client'
		'SMB1Protocol'                            = 'SMB 1.0/CIFS File Sharing'
		'SearchEngine-Client-Package'             = 'Windows Search'
		'SmbDirect'                               = 'SMB Direct'
		'DirectPlay'                              = 'DirectPlay'
	}

	function Get-FeatureFriendlyName
	{
		param ([string]$FeatureName, [string]$DisplayName)

		if (-not [string]::IsNullOrWhiteSpace($DisplayName))
		{
			return $DisplayName
		}

		if ($FeatureFriendlyNames.ContainsKey($FeatureName))
		{
			return $FeatureFriendlyNames[$FeatureName]
		}

		return $FeatureName
	}

	function New-FeatureInfoIcon
	{
		param ([string]$TooltipText)

		$icon = New-Object -TypeName System.Windows.Controls.TextBlock
		$icon.Text = [char]0x24D8  # info icon
		$icon.FontSize = 14
		$icon.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
		$icon.VerticalAlignment = 'Center'
		$icon.Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
		$icon.Cursor = [System.Windows.Input.Cursors]::Arrow
		$icon.ToolTip = $(if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'Windows feature' } else { $TooltipText })
		[System.Windows.Controls.ToolTipService]::SetPlacement($icon, [System.Windows.Controls.Primitives.PlacementMode]::Right)
		[System.Windows.Controls.ToolTipService]::SetShowDuration($icon, 20000)
		[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($icon, 150)
		return $icon
	}

	function Add-FeatureControl
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$Feature
		)

		process
		{
			$CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
			$CheckBox.Add_Click({Get-CheckboxClicked -CheckBox $_.Source})
			$CheckBox.Tag = $Feature
			$CheckBox.VerticalAlignment = 'Center'
			$CheckBox.Margin = [System.Windows.Thickness]::new(10, 10, 5, 10)

			$FeatureLabel = Get-FeatureFriendlyName -FeatureName $Feature.FeatureName -DisplayName $Feature.DisplayName
			$tooltipText = if (-not [string]::IsNullOrWhiteSpace($Feature.Description))
			{
				[string]$Feature.Description
			}
			elseif (-not [string]::IsNullOrWhiteSpace($Feature.DisplayName))
			{
				"Windows feature: $($Feature.DisplayName)"
			}
			else
			{
				"Windows feature: $FeatureLabel"
			}

			$TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
			$TextBlock.Text = $FeatureLabel
			$TextBlock.VerticalAlignment = 'Center'
			$TextBlock.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)

			$infoIcon = New-FeatureInfoIcon -TooltipText $tooltipText

			$rowPanel = New-Object -TypeName System.Windows.Controls.DockPanel
			$rowPanel.LastChildFill = $true
			$rowPanel.HorizontalAlignment = 'Stretch'
			$rowPanel.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)

			[System.Windows.Controls.DockPanel]::SetDock($CheckBox, [System.Windows.Controls.Dock]::Left)
			[void]$rowPanel.Children.Add($CheckBox)

			$infoPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$infoPanel.Orientation = 'Horizontal'
			$infoPanel.VerticalAlignment = 'Center'
			$infoPanel.HorizontalAlignment = 'Right'
			$infoPanel.Margin = [System.Windows.Thickness]::new(8, 0, 10, 0)
			[void]$infoPanel.Children.Add($infoIcon)

			[System.Windows.Controls.DockPanel]::SetDock($infoPanel, [System.Windows.Controls.Dock]::Right)
			[void]$rowPanel.Children.Add($infoPanel)

			[void]$rowPanel.Children.Add($TextBlock)
			[void]$PanelContainer.Children.Add($rowPanel)

			if (Test-FeatureSeedSelected -Feature $Feature)
			{
				[void]$SelectedFeatures.Add($Feature)
			}
			else
			{
				$CheckBox.IsChecked = $false
			}

			if ($null -ne $Button)
			{
				$Button.IsEnabled = ($SelectedFeatures.Count -gt 0)
			}
		}
	}
	#endregion Functions

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			$State           = @("Disabled", "DisablePending")
			$ButtonContent   = $Localization.Enable
			$ButtonAdd_Click = {
				param
				(
					[object[]]
					$FeatureList
				)

				EnableButton -FeatureList $FeatureList
			}
		}
		"Disable"
		{
			$State           = @("Enabled", "EnablePending")
			$ButtonContent   = $Localization.Disable
			$ButtonAdd_Click = {
				param
				(
					[object[]]
					$FeatureList
				)

				DisableButton -FeatureList $FeatureList
			}
		}
	}

	if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedFeatureNamesProvided)
	{
		$selectionResult = Request-GuiSystemSelection -RequestType 'WindowsFeatures' -Mode $PSCmdlet.ParameterSetName -SelectedNames @($SelectedFeatureNames)
		if ($null -ne $selectionResult)
		{
			$SelectedFeatureNames = @($selectionResult.SelectedFeatureNames)
			$SelectedFeatureNamesProvided = $true
		}
	}

	if ($NonInteractive -and -not $SelectedFeatureNamesProvided)
	{
		LogWarning 'Skipping Windows features because no preselected features were provided for noninteractive execution.'
		Write-ConsoleStatus -Status warning
		return
	}

	# Getting list of all optional features according to the conditions
	try
	{
		$Features = Get-WindowsOptionalFeature -Online -ErrorAction Stop |
			Where-Object -FilterScript {
				($_.State -in $State) -and
				(
					(Test-FeaturePatternMatch -FeatureName $_.FeatureName -Patterns $UncheckedFeatures) -or
					(Test-FeaturePatternMatch -FeatureName $_.FeatureName -Patterns $CheckedFeatures)
				)
			} |
			Sort-Object -Property DisplayName, FeatureName
	}
	catch
	{
		Remove-HandledErrorRecord -ErrorRecord $_
		$Features = $null
	}

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
		LogInfo "No preset-matched Windows features were found. Moving on."
		Write-ConsoleStatus -Action "$(if ($PSCmdlet.ParameterSetName -eq 'Disable') { 'Disabling Windows features' } else { 'Enabling Windows features' })" -Status success
		return
	}

	if ($SelectedFeatureNamesProvided -and -not $CollectSelectionOnly)
	{
		$ResolvedSelectedFeatures = @(
			$Features | Where-Object -FilterScript {$SelectedFeatureNames -contains $_.FeatureName}
		)
		& $ButtonAdd_Click -FeatureList $ResolvedSelectedFeatures
		return
	}

	#region Sendkey function
	# Emulate the Backspace key sending to prevent the console window to freeze
	Start-Sleep -Milliseconds 500

	Add-Type -AssemblyName System.Windows.Forms

	# We cannot use Get-Process -Id $PID as script might be invoked via Terminal with different $PID
	Get-Process -Name powershell, WindowsTerminal -ErrorAction Ignore | Where-Object -FilterScript {$_.MainWindowTitle -match "Baseline \| Utility for Windows"} | ForEach-Object -Process {
		# Show window, if minimized
		[WinAPI.ForegroundWindow]::ShowWindowAsync($_.MainWindowHandle, 10)

		Start-Sleep -Milliseconds 150

		# Force move the console window to the foreground
		[WinAPI.ForegroundWindow]::SetForegroundWindow($_.MainWindowHandle)

		Start-Sleep -Milliseconds 150

		# Emulate the Backspace key sending
		[System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE 1}")
	}
	#endregion Sendkey function
	$Button.IsEnabled = $false
	$Window.Add_Loaded({$Features | Add-FeatureControl})
	$Button.Content = $ButtonContent
	$Button.Add_Click({Confirm-WindowsFeaturesSelection})

	$Window.Title = $Localization.WindowsFeaturesTitle

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

	if (-not $SelectionState.Confirmed)
	{
		LogWarning 'Skipping Windows features because no selection was confirmed.'
		Write-ConsoleStatus -Status warning
	}
}
Export-ModuleMember -Function '*'
