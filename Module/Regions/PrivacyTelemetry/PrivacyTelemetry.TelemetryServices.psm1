using module ..\..\GUICommon.psm1
using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1


<#
	.SYNOPSIS
	Configures the Connected User Experiences and Telemetry (DiagTrack) service.



.DESCRIPTION

Applies the Connected User Experiences and Telemetry (DiagTrack) service in GUI and headless runs.
	.PARAMETER Disable
	Disable the Connected User Experiences and Telemetry (DiagTrack) service, and block connection for the Unified Telemetry Client Outbound Traffic

	.PARAMETER Enable
	Enable the Connected User Experiences and Telemetry (DiagTrack) service, and allow connection for the Unified Telemetry Client Outbound Traffic (default value)

	.EXAMPLE
	DiagTrackService -Disable

	.EXAMPLE
	DiagTrackService -Enable

	.NOTES
	Disabling the "Connected User Experiences and Telemetry" service (DiagTrack) can cause you not being able to get Xbox achievements anymore and affects Feedback Hub

	.NOTES
	Current user
#>

function DiagTrackService
{
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
		$Enable
	)

	# Checking whether "InitialActions" function was removed in preset file
	if (-not ("WinAPI.GetStrings" -as [type]))
	{
		# Get the name of a preset (e.g Bootstrap/Baseline.ps1) regardless if it was renamed
		# $_.File has no EndsWith() method
		$PresetName = Split-Path -Path (((Get-PSCallStack).Position | Where-Object -FilterScript {$_.File}).File | Where-Object -FilterScript {$_.EndsWith(".ps1")}) -Leaf

		LogError ($Localization.InitialActionsCheckFailed -f $PresetName)
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			# Connected User Experiences and Telemetry
			# Disabling the "Connected User Experiences and Telemetry" service (DiagTrack) can cause you not being able to get Xbox achievements anymore and affects Feedback Hub
			LogInfo 'Disabling the "Connected User Experiences and Telemetry" service'
			Get-Service -Name DiagTrack -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
			Get-Service -Name DiagTrack | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

			# Block connection for the Unified Telemetry Client Outbound Traffic
			Get-NetFirewallRule -Group DiagTrack | Set-NetFirewallRule -Enabled True -Action Block | Out-Null
		}
		"Enable"
		{
			# Connected User Experiences and Telemetry
			LogInfo 'Enabling the "Connected User Experiences and Telemetry" service'
			Get-Service -Name DiagTrack | Set-Service -StartupType Automatic -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
			Get-Service -Name DiagTrack | Start-Service -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

			# Allow connection for the Unified Telemetry Client Outbound Traffic
			Get-NetFirewallRule -Group DiagTrack | Set-NetFirewallRule -Enabled True -Action Allow | Out-Null
		}
	}
}

<#
	.SYNOPSIS
	Diagnostic data



.DESCRIPTION

Applies the Baseline behavior for diagnostic data.
	.PARAMETER Minimal
	Set the diagnostic data collection to minimum

	.PARAMETER Default
	Set the diagnostic data collection to default (default value)

	.EXAMPLE
	DiagnosticDataLevel -Minimal

	.EXAMPLE
	DiagnosticDataLevel -Default

	.NOTES
	Machine-wide
#>
function DiagnosticDataLevel
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Minimal"
		)]
		[switch]
		$Minimal,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	if (-not (Test-Path -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection))
	{
		New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Force | Out-Null
	}

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack -Force | Out-Null
	}

    # Get Windows edition
    $isEnterpriseOrEducation = $false
    if (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -ErrorAction SilentlyContinue)
    {
        $editionId = [string](Get-BaselineSystemPlatformInfo).EditionID
        $isEnterpriseOrEducation = $editionId -match '(?i)Enterprise|Education'
    }
    else
    {
        $WindowsEdition = (Get-WmiObject -Class Win32_OperatingSystem).Caption
        $isEnterpriseOrEducation = ($WindowsEdition -match "Enterprise") -or ($WindowsEdition -match "Education")
    }

    switch ($PSCmdlet.ParameterSetName) {
        "Minimal" {
			Write-ConsoleStatus -Action "Set Diagnostic Data Collection to Minimal"
			LogInfo "Setting Diagnostic Data Collection to Minimal"
			try
			{
				if ($isEnterpriseOrEducation) {
					New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name AllowTelemetry -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				} else {
					New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name AllowTelemetry -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				}

				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection -Name MaxTelemetryAllowed -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" -Name ShowedToastAtLevel -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Diagnostic Data Collection to Minimal: $($_.Exception.Message)"
			}
		}
        "Default" {
            # Optional diagnostic data
			Write-ConsoleStatus -Action "Set Diagnostic Data Collection to Default"
			LogInfo "Setting Diagnostic Data Collection to Default"
			try
			{
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection -Name MaxTelemetryAllowed -PropertyType DWord -Value 3 -Force -ErrorAction Stop | Out-Null
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" -Name ShowedToastAtLevel -Type DWord -Value 3 | Out-Null
				if ((Get-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name AllowTelemetry -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Diagnostic Data Collection to Default: $($_.Exception.Message)"
			}
		}
    }
}

<#
	.SYNOPSIS
	The diagnostics tracking scheduled tasks



.DESCRIPTION

Applies the Baseline behavior for the diagnostics tracking scheduled tasks.
	.PARAMETER Disable
	Turn off the diagnostics tracking scheduled tasks

	.PARAMETER Enable
	Turn on the diagnostics tracking scheduled tasks (default value)

	.EXAMPLE
	ScheduledTasks -Disable

	.EXAMPLE
	ScheduledTasks -Enable

	.NOTES
	A pop-up dialog box lets a user select tasks

	.NOTES
	Current user
#>

function Request-GuiScheduledTasksSelection
{
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('Enable', 'Disable')]
		[string]
		$Mode,

		[Parameter(Mandatory = $false)]
		[string[]]
		$SelectedNames = @()
	)

	$queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
	if (-not $queue)
	{
		throw 'GUI execution could not open the Scheduled Tasks picker because the GUI request queue is unavailable.'
	}

	$responseState = [hashtable]::Synchronized(@{
		Done = $false
		Result = $null
		Error = $null
	})

	$queue.Enqueue([PSCustomObject]@{
		Kind = '_InteractiveSelectionRequest'
		RequestType = 'ScheduledTasks'
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
    Runs scheduled tasks.

    #>

function ScheduledTasks
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
		$SelectedTaskNames,

		[Parameter(Mandatory = $false)]
		[switch]
		$CollectSelectionOnly,

		[Parameter(Mandatory = $false)]
		[switch]
		$NonInteractive
	)

		. (Join-Path $PSScriptRoot 'TelemetryServices\ScheduledTasks\ModulePathResolution.ps1')

	#region Variables
	# Initialize an array list to store the selected scheduled tasks
	$SelectedTasks = New-Object -TypeName System.Collections.ArrayList($null)
	$SelectionState = [PSCustomObject]@{
		Confirmed = $false
	}
	$script:ScheduledTasksSelectionResult = $null
	$SelectedTaskNamesProvided = $PSBoundParameters.ContainsKey('SelectedTaskNames')

	# The following tasks will have their checkboxes checked
		. (Join-Path $PSScriptRoot 'TelemetryServices\ScheduledTasks\ScheduledTaskList.ps1')

	<#
	    .SYNOPSIS
	    Gets selected scheduled task list.

		#>

	function Get-SelectedScheduledTaskList
	{
		return @($SelectedTasks | Where-Object { $_ })
	}

	<#
	    .SYNOPSIS
	    Gets selected scheduled task names.

		#>
	function Get-SelectedScheduledTaskNames
	{
		return @(
			Get-SelectedScheduledTaskList |
				ForEach-Object {[string]$_.TaskName} |
				Where-Object {-not [string]::IsNullOrWhiteSpace($_)}
		)
	}

	<#
	    .SYNOPSIS
	    Runs scheduled tasks operation.

		#>

		. (Join-Path $PSScriptRoot 'TelemetryServices\ScheduledTasks\ScheduledTaskOperation.ps1')

	# Getting list of all scheduled tasks according to the conditions
	$Tasks = Get-ScheduledTask | Where-Object -FilterScript {($_.State -eq $State) -and ($_.TaskName -in $CheckedScheduledTasks)}

	if (-not $Tasks)
	{
		if ($CollectSelectionOnly)
		{
			return [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedTaskNames = @()
			}
		}
		return
	}

	if ($Global:GUIMode -and -not $CollectSelectionOnly -and -not $SelectedTaskNamesProvided)
	{
		$selectionResult = Request-GuiScheduledTasksSelection -Mode $PSCmdlet.ParameterSetName -SelectedNames @($SelectedTaskNames)
		if ($null -ne $selectionResult)
		{
			$SelectedTaskNames = @($selectionResult.SelectedTaskNames)
			$SelectedTaskNamesProvided = $true
		}
	}

	if ($SelectedTaskNamesProvided -and -not $CollectSelectionOnly)
	{
		$ResolvedSelectedTasks = @(
			$Tasks | Where-Object -FilterScript {$SelectedTaskNames -contains $_.TaskName}
		)
		Invoke-ScheduledTasksOperation -TaskList $ResolvedSelectedTasks
		Write-ConsoleStatus -Status success
		return
	}

	if ($NonInteractive -and -not $SelectedTaskNamesProvided)
	{
		LogWarning 'Skipping diagnostics tracking scheduled tasks because no preselected tasks were provided for noninteractive execution.'
		Write-ConsoleStatus -Status warning
		return
	}

	Add-Type -AssemblyName PresentationCore, PresentationFramework

	#region XAML Markup
	# This block defines the dialog XAML used at runtime.
	[xml]$XAML = @"
	<Window
		xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		Name="Window"
		MinHeight="450" MinWidth="400"
		SizeToContent="WidthAndHeight" WindowStartupLocation="CenterScreen"
		TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
		FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"
		Background="Transparent" WindowStyle="None" AllowsTransparency="True" Foreground="#262626">
		<Window.Resources>
			<Style TargetType="StackPanel">
				<Setter Property="Orientation" Value="Horizontal"/>
				<Setter Property="VerticalAlignment" Value="Top"/>
			</Style>
			<Style TargetType="CheckBox">
				<Setter Property="Margin" Value="10, 10, 5, 10"/>
				<Setter Property="IsChecked" Value="True"/>
			</Style>
			<Style TargetType="TextBlock">
				<Setter Property="Margin" Value="5, 10, 10, 10"/>
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
		<Border Name="RootBorder" CornerRadius="8">
			<Grid>
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="*"/>
					<RowDefinition Height="Auto"/>
				</Grid.RowDefinitions>
				<Grid Grid.Row="0" Margin="10,8,10,8">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
					</Grid.ColumnDefinitions>
					<StackPanel Name="PanelSelectAll" Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
						<CheckBox Name="CheckBoxSelectAll" IsChecked="False" VerticalAlignment="Center" Margin="0,0,6,0"/>
						<TextBlock Name="TextBlockSelectAll" VerticalAlignment="Center"/>
					</StackPanel>
				</Grid>
				<Border>
					<ScrollViewer Name="Scroll"
						HorizontalScrollBarVisibility="Disabled"
						VerticalScrollBarVisibility="Auto">
						<StackPanel Name="PanelContainer" Orientation="Vertical"/>
					</ScrollViewer>
				</Border>
				<Button Name="Button" Grid.Row="2"/>
			</Grid>
		</Border>
	</Window>
"@
	#endregion XAML Markup

	$Form = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML))
	$XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
		Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
	}

	$bc = New-Object System.Windows.Media.BrushConverter
	$Theme = Get-ScheduledTasksPickerTheme
	$UseDarkMode = Resolve-ScheduledTasksPickerUseDarkMode
	$setScheduledTasksPickerSurface = ${function:Set-ScheduledTasksPickerSurface}
	& $setScheduledTasksPickerSurface -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -ScrollViewer $Scroll -Theme $Theme -BrushConverter $bc -UseDarkMode $UseDarkMode
	if (Get-Command -Name 'Set-GuiWindowChromeTheme' -CommandType Function -ErrorAction SilentlyContinue)
	{
		[void](Set-GuiWindowChromeTheme -Window $Form -UseDarkMode $UseDarkMode)
	}

	$Window.Add_Loaded({$Tasks | Add-TaskControl})
	$Button.Content = $ButtonContent
	$Button.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$Button.FontSize = 12
	try { GUICommon\Set-GuiPopupActionButtonStyle -Button $Button -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ScheduledTasks.SetPopupActionButtonStyle' }
	$TextBlockSelectAll.Text = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All'
	$TextBlockSelectAll.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	if ($Form.Foreground) { $TextBlockSelectAll.Foreground = $Form.Foreground }
	$Button.Add_Click({Confirm-ScheduledTasksSelection})
	$CheckBoxSelectAll.Add_Click({Invoke-TelemetryServiceSelectAllClick})

	$scheduledTasksTitle = GUICommon\Get-GuiPopupLocalizedString -Key 'Tweak_ScheduledTasks' -Fallback 'Diagnostics Tracking Tasks'
	$Form.Title = $scheduledTasksTitle
	if (Test-Path -Path Function:\Add-GuiPopupWindowChrome)
	{
		[void](GUICommon\Add-GuiPopupWindowChrome -Window $Form -RootBorder $RootBorder -PanelContainer $PanelContainer -Title $scheduledTasksTitle -Theme $Theme -UseDarkMode $UseDarkMode)
	}
	$scheduledTasksThemeCallback = {
		param($Window, $Theme, $UseDarkMode)

		try
		{
			& $setScheduledTasksPickerSurface -Window $Window -RootBorder $RootBorder -PanelContainer $PanelContainer -ScrollViewer $Scroll -Theme $Theme -BrushConverter $bc -UseDarkMode $UseDarkMode
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'ScheduledTasks.ThemeCallback.SetSurface'
		}

		if ($Button)
		{
			try { GUICommon\Set-GuiPopupActionButtonStyle -Button $Button -Theme $Theme -UseDarkMode $UseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ScheduledTasks.ThemeCallback.SetPopupActionButtonStyle' }
		}

		if ($TextBlockSelectAll -and $Window.Foreground)
		{
			$TextBlockSelectAll.Foreground = $Window.Foreground
		}
	}.GetNewClosure()
	if (Test-Path -Path Function:\Register-GuiPopupThemeWindow)
	{
		[void](GUICommon\Register-GuiPopupThemeWindow -Window $Form -ThemeCallback $scheduledTasksThemeCallback)
	}
	& $scheduledTasksThemeCallback -Window $Form -Theme $Theme -UseDarkMode $UseDarkMode
	$Button.IsEnabled = $false

	if ($Global:GUIMode -and -not $CollectSelectionOnly)
	{
		# GUI-mode runs collect the scheduled task selection on the main UI thread when this tweak starts.
	}
	else
	{
		# Normalize minimized dialogs before showing without reclaiming foreground focus.
		Initialize-WpfWindowForeground -Window $Form
		$Form.ShowDialog() | Out-Null
	}

	if ($CollectSelectionOnly)
	{
		return $script:ScheduledTasksSelectionResult
	}

	if ($Form.PSObject.Properties['GuiPopupOperationError'] -and $Form.GuiPopupOperationError)
	{
		$operationError = $Form.GuiPopupOperationError
		Remove-HandledErrorRecord -ErrorRecord $operationError
		LogError "Failed to $(if ($PSCmdlet.ParameterSetName -eq 'Disable') { 'disable' } else { 'enable' }) scheduled tasks: $($operationError.Exception.Message)"
		Write-ConsoleStatus -Status failed
		throw $operationError
	}

	if ($SelectionState.Confirmed)
	{
		Write-ConsoleStatus -Status success
	}

	if (-not $SelectionState.Confirmed)
	{
		LogWarning 'Skipping diagnostics tracking scheduled tasks because no selection was confirmed.'
		Write-ConsoleStatus -Status warning
	}

}

<#
.SYNOPSIS
Enable or disable PowerShell 7 Telemetry

.PARAMETER Enable
Enable PowerShell 7 Telemetry (default value)

.PARAMETER Disable
Disable PowerShell 7 Telemetry

.EXAMPLE
Powershell7Telemetry -Enable

.EXAMPLE
Powershell7Telemetry -Disable

.NOTES
Current user
#>
function Powershell7Telemetry
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling PowerShell 7 Telemetry"
			LogInfo "Enabling PowerShell 7 Telemetry"
			try
			{
				[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '', 'Machine')
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable PowerShell 7 Telemetry: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling PowerShell 7 Telemetry"
			LogInfo "Disabling PowerShell 7 Telemetry"
			try
			{
				[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable PowerShell 7 Telemetry: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Windows Error Reporting



.DESCRIPTION

Applies the Baseline behavior for windows Error Reporting.
	.PARAMETER Disable
	Turn off Windows Error Reporting

	.PARAMETER Enable
	Turn on Windows Error Reporting (default value)

	.EXAMPLE
	ErrorReporting -Disable

	.EXAMPLE
	ErrorReporting -Enable

	.NOTES
	Current user
#>
function ErrorReporting
{
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
		$Enable
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" -Name Disabled -Force -ErrorAction Ignore | Out-Null
	Remove-RegistryValueSafe -Path "HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" -Name Disabled -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path "Software\Policies\Microsoft\Windows\Windows Error Reporting" -Name Disabled -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
			{
				Write-ConsoleStatus -Action "Disable Windows Error Reporting"
				LogInfo "Disabling Windows Error Reporting"
				try
				{
					Get-ScheduledTask -TaskName QueueReporting -ErrorAction Ignore | Disable-ScheduledTask | Out-Null
					Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" -Name Disabled -Type DWord -Value 1 | Out-Null
					try
					{
						Get-Service -Name WerSvc -ErrorAction Stop | Stop-Service -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
					}
					catch
					{
						LogWarning "Windows Error Reporting Service stop failed: $($_.Exception.Message)"
						Remove-HandledErrorRecord -ErrorRecord $_
					}

					try
					{
						Get-Service -Name WerSvc -ErrorAction Stop | Set-Service -StartupType Disabled -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
					}
					catch
					{
						LogWarning "Windows Error Reporting Service startup-type update failed: $($_.Exception.Message)"
						Remove-HandledErrorRecord -ErrorRecord $_
					}
					Write-ConsoleStatus -Status success
				}
				catch
				{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows Error Reporting: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enable Windows Error Reporting"
			LogInfo "Enabling Windows Error Reporting"
			try
			{
				Get-ScheduledTask -TaskName QueueReporting -ErrorAction Ignore | Enable-ScheduledTask | Out-Null
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" -Name Disabled -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" | Out-Null
				}
				Get-Service -Name WerSvc | Set-Service -StartupType Manual -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
				Get-Service -Name WerSvc | Start-Service -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows Error Reporting: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Device Management Wireless Application Protocol (WAP) Push Service settings

    .DESCRIPTION
    Note: This service is needed for Microsoft Intune interoperability

    .PARAMETER Enable
    Enable the Device Management Wireless Application Protocol (WAP) Push Service

    .PARAMETER Disable
    Disable the Device Management Wireless Application Protocol (WAP) Push Service

    .EXAMPLE
    WAPPush -Enable

    .EXAMPLE
    WAPPush -Disable

    .NOTES
    Current user
#>

function WAPPush
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Device Management Wireless Application Protocol (WAP) Push Service"
			LogInfo "Enabling Device Management Wireless Application Protocol (WAP) Push Service"
			try
			{
				Set-Service "dmwappushservice" -StartupType Automatic -ErrorAction Stop | Out-Null
				Start-Service "dmwappushservice" -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\dmwappushservice" -Name "DelayedAutoStart" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the WAP Push Service: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Device Management Wireless Application Protocol (WAP) Push Service"
			LogInfo "Disabling Device Management Wireless Application Protocol (WAP) Push Service"
			try
			{
				Stop-Service "dmwappushservice" -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
				Set-Service "dmwappushservice" -StartupType Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the WAP Push Service: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'DiagnosticDataLevel',
    'DiagTrackService',
    'ErrorReporting',
    'Powershell7Telemetry',
    'Request-GuiScheduledTasksSelection',
    'ScheduledTasks',
    'WAPPush'
)
Export-ModuleMember -Function $ExportedFunctions
