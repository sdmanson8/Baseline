# GUI session state, undo snapshots, and settings profile management

if (-not (Get-Variable -Name 'GuiSelectionBulkUpdateInProgress' -Scope Script -ErrorAction SilentlyContinue))
{
	$Script:GuiSelectionBulkUpdateInProgress = $false
}

if (-not (Get-Variable -Name 'GameModePlanSyncPending' -Scope Script -ErrorAction SilentlyContinue))
{
	$Script:GameModePlanSyncPending = $false
}

<#
    .SYNOPSIS
#>

function Resolve-GuiModePreference
{
	param (
		[bool]$SafeMode,
		[bool]$AdvancedMode
	)

	if ($SafeMode)
	{
		return [pscustomobject]@{
			SafeMode = $true
			AdvancedMode = $false
		}
	}

	if ($AdvancedMode)
	{
		return [pscustomobject]@{
			SafeMode = $false
			AdvancedMode = $true
		}
	}

	return [pscustomobject]@{
		SafeMode = $true
		AdvancedMode = $false
	}
}

<#
    .SYNOPSIS
#>

function Enter-GuiSelectionBulkUpdate
{
	$previousState = [bool]$Script:GuiSelectionBulkUpdateInProgress
	$Script:GuiSelectionBulkUpdateInProgress = $true
	return $previousState
}

<#
    .SYNOPSIS
#>

function Test-GuiSelectionBulkUpdateInProgress
{
	return [bool]$Script:GuiSelectionBulkUpdateInProgress
}

<#
    .SYNOPSIS
#>

function Exit-GuiSelectionBulkUpdate
{
	param (
		[bool]$PreviousState
	)

	$Script:GuiSelectionBulkUpdateInProgress = [bool]$PreviousState
	if ($Script:GuiSelectionBulkUpdateInProgress)
	{
		return
	}

	if (-not [bool]$Script:GameModePlanSyncPending)
	{
		return
	}

	if (-not (Get-Command -Name 'Sync-GameModePlanFromGamingControls' -CommandType Function -ErrorAction SilentlyContinue))
	{
		return
	}

	$Script:GameModePlanSyncPending = $false
	Sync-GameModePlanFromGamingControls
}

<#
    .SYNOPSIS
#>

function Get-GuiRemoteTargetContext
{
	<# .SYNOPSIS Returns the current remote target context. #>
	if (-not $Script:Ctx)
	{
		return [pscustomobject]@{
			Connected                 = $false
			TargetComputers           = @()
			ApprovedTargetComputers   = @()
			Credential                = $null
			ConnectedAt               = $null
			ApprovedAt                = $null
			StatusMessage             = $null
			ApprovalMessage           = $null
			ConnectionMethod          = 'WinRM'
			LastConnectivityResults   = @()
		}
	}

	if (-not $Script:Ctx.ContainsKey('Remote'))
	{
		$Script:Ctx['Remote'] = @{
			Connected                 = $false
			TargetComputers           = @()
			ApprovedTargetComputers   = @()
			Credential                = $null
			ConnectedAt               = $null
			ApprovedAt                = $null
			StatusMessage             = $null
			ApprovalMessage           = $null
			ConnectionMethod          = 'WinRM'
			LastConnectivityResults   = @()
		}
	}

	if (-not $Script:Ctx.Remote.ContainsKey('ConnectionMethod')) { $Script:Ctx.Remote['ConnectionMethod'] = 'WinRM' }
	if (-not $Script:Ctx.Remote.ContainsKey('LastConnectivityResults')) { $Script:Ctx.Remote['LastConnectivityResults'] = @() }

	return [pscustomobject]@{
		Connected                 = [bool]$Script:Ctx.Remote.Connected
		TargetComputers           = @($Script:Ctx.Remote.TargetComputers)
		ApprovedTargetComputers   = @($Script:Ctx.Remote.ApprovedTargetComputers)
		Credential                = $Script:Ctx.Remote.Credential
		ConnectedAt               = $Script:Ctx.Remote.ConnectedAt
		ApprovedAt                = $Script:Ctx.Remote.ApprovedAt
		StatusMessage             = $Script:Ctx.Remote.StatusMessage
		ApprovalMessage           = $Script:Ctx.Remote.ApprovalMessage
		ConnectionMethod          = [string]$Script:Ctx.Remote.ConnectionMethod
		LastConnectivityResults   = @($Script:Ctx.Remote.LastConnectivityResults)
	}
}

<#
    .SYNOPSIS
#>

function Test-GuiRemoteTargetConnected
{
	<# .SYNOPSIS Tests whether a remote target context is currently active. #>
	return [bool]((Get-GuiRemoteTargetContext).Connected)
}

function Set-GuiRemoteTargetContext
{
	<# .SYNOPSIS Stores the active remote target context for the GUI session. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[System.Management.Automation.PSCredential]$Credential,

		[string]$StatusMessage,

		[string]$ConnectionMethod = 'WinRM'
	)

	if (-not $Script:Ctx)
	{
		throw 'GUI context has not been initialized.'
	}

	$targets = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim() })
	if ($targets.Count -eq 0)
	{
		throw 'At least one computer name is required.'
	}

	$canonicalMethod = if (Get-Command -Name 'ConvertTo-BaselineRemoteConnectionMethod' -CommandType Function -ErrorAction SilentlyContinue) {
		ConvertTo-BaselineRemoteConnectionMethod -Method $ConnectionMethod
	} else {
		'WinRM'
	}

	$Script:Ctx.Remote.Connected = $true
	$Script:Ctx.Remote.TargetComputers = @($targets)
	$Script:Ctx.Remote.ApprovedTargetComputers = @()
	$Script:Ctx.Remote.Credential = $Credential
	$Script:Ctx.Remote.ConnectedAt = [datetime]::UtcNow.ToString('o')
	$Script:Ctx.Remote.ApprovedAt = $null
	$Script:Ctx.Remote.StatusMessage = if ([string]::IsNullOrWhiteSpace($StatusMessage)) { 'Remote target connected.' } else { [string]$StatusMessage }
	$Script:Ctx.Remote.ApprovalMessage = $null
	$Script:Ctx.Remote.ConnectionMethod = $canonicalMethod

	$displayTargets = ($targets -join ', ')
	if ($Script:MenuActionsDisconnect) { $Script:MenuActionsDisconnect.IsEnabled = $true }
	Set-GuiStatusText -Text ("Remote: {0}" -f $displayTargets) -Tone 'accent'
	try { Update-GuiRemoteModeBanner } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Set-GuiRemoteTargetContext.UpdateGuiRemoteModeBanner' }
	return (Get-GuiRemoteTargetContext)
}

<#
    .SYNOPSIS
#>

function Clear-GuiRemoteTargetContext
{
	<# .SYNOPSIS Clears the active remote target context. #>
	if (-not $Script:Ctx)
	{
		return
	}

	if (-not $Script:Ctx.ContainsKey('Remote'))
	{
		return
	}

	$Script:Ctx.Remote.Connected = $false
	$Script:Ctx.Remote.TargetComputers = @()
	$Script:Ctx.Remote.ApprovedTargetComputers = @()
	$Script:Ctx.Remote.Credential = $null
	$Script:Ctx.Remote.ConnectedAt = $null
	$Script:Ctx.Remote.ApprovedAt = $null
	$Script:Ctx.Remote.StatusMessage = $null
	$Script:Ctx.Remote.ApprovalMessage = $null
	$Script:Ctx.Remote.ConnectionMethod = 'WinRM'
	$Script:Ctx.Remote.LastConnectivityResults = @()
	if (Get-Command -Name 'Clear-BaselineRemoteSessionCache' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { Clear-BaselineRemoteSessionCache } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Clear-GuiRemoteTargetContext.ClearBaselineRemoteSessionCache' }
	}
	if ($Script:MenuActionsDisconnect) { $Script:MenuActionsDisconnect.IsEnabled = $false }
	Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiRemoteDisconnected' -Fallback 'Remote target disconnected.') -Tone 'muted'
	try { Update-GuiRemoteModeBanner } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Clear-GuiRemoteTargetContext.UpdateGuiRemoteModeBanner' }
}

<#
    .SYNOPSIS
#>

function Set-GuiRemoteConnectivityResults
{
	<#
		.SYNOPSIS
		Persists the most recent Test-BaselineRemoteConnectivity output on
		the GUI remote-target context so the Support Bundle exporter and
		Connect-dialog status panel can read it back. Stores a slim copy
		(ComputerName / Reachable / Status / Error / FailureCategory /
		BlockedByPolicy / ConnectionMethod / Timestamp) - full attempt
		histories live in remote-orchestration.jsonl.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Results
	)

	if (-not $Script:Ctx)
	{
		throw 'GUI context has not been initialized.'
	}
	if (-not $Script:Ctx.ContainsKey('Remote'))
	{
		$null = Get-GuiRemoteTargetContext
	}

	$timestamp = [datetime]::UtcNow.ToString('o')
	$slim = [System.Collections.Generic.List[pscustomobject]]::new()
	if ($null -ne $Results)
	{
		foreach ($entry in @($Results))
		{
			if ($null -eq $entry) { continue }
			$props = $entry.PSObject.Properties
			$slim.Add([pscustomobject]@{
				ComputerName     = if ($props['ComputerName']) { [string]$entry.ComputerName } else { '' }
				Reachable        = if ($props['Reachable']) { [bool]$entry.Reachable } else { $false }
				Status           = if ($props['Status']) { [string]$entry.Status } else { 'Unknown' }
				Error            = if ($props['Error']) { [string]$entry.Error } else { '' }
				FailureCategory  = if ($props['FailureCategory']) { [string]$entry.FailureCategory } else { '' }
				BlockedByPolicy  = if ($props['BlockedByPolicy']) { [bool]$entry.BlockedByPolicy } else { $false }
				ConnectionMethod = if ($props['ConnectionMethod']) { [string]$entry.ConnectionMethod } else { '' }
				Timestamp        = $timestamp
			})
		}
	}

	$Script:Ctx.Remote.LastConnectivityResults = @($slim)
	return @($slim)
}

<#
    .SYNOPSIS
#>

function Update-GuiRemoteModeBanner
{
	<#
		.SYNOPSIS
		Toggles the persistent RemoteModeBanner row in MainWindow.xaml so
		the user always knows whether they are operating locally or
		against remote targets. Reads context via Get-GuiRemoteTargetContext
		and writes to the banner controls (Border / TextBlock / Disconnect
		Button) bound to script-scope on window load. No-op when the banner
		controls were not bound (headless / test runners).
	#>
	[CmdletBinding()]
	param ()

	$banner = $Script:RemoteModeBanner
	$label = $Script:RemoteModeBannerText
	if (-not $banner -or -not $label) { return }

	$context = $null
	try { $context = Get-GuiRemoteTargetContext } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Update-GuiRemoteModeBanner.LoadRemoteTargetContext'; $context = $null }

	if (-not $context -or -not $context.Connected -or $context.TargetComputers.Count -eq 0)
	{
		$banner.Visibility = [System.Windows.Visibility]::Collapsed
		return
	}

	$methodLabel = 'WinRM'
	if (Get-Command -Name 'Get-BaselineRemoteConnectionMethodLabel' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { $methodLabel = Get-BaselineRemoteConnectionMethodLabel -Method $context.ConnectionMethod } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Update-GuiRemoteModeBanner.ResolveRemoteConnectionMethodLabel'; $methodLabel = 'WinRM' }
	}

	$targetList = ($context.TargetComputers -join ', ')
	$label.Text = ('Remote Mode ({0}): {1}' -f $methodLabel, $targetList)
	$banner.Visibility = [System.Windows.Visibility]::Visible
}

<#
    .SYNOPSIS
#>

function Prompt-GuiRemoteTargetConnection
{
	<#
		.SYNOPSIS
		Shows the Connect-to-Computer dialog and returns the user's
		ComputerName / Credential / ConnectionMethod selection.

		.DESCRIPTION
		Renders a themed WPF dialog with a multiline target-list TextBox,
		a connection-method ComboBox (WinRM / WinRM-HTTPS / SSH), and
		credentials radio buttons (current vs. alternate). The Test
		Connection button runs Test-BaselineRemoteConnectivity on a
		background runspace, polled by a DispatcherTimer using the
		same closure pattern, then renders
		Format-BaselineRemoteConnectivityStatus rows into the status
		panel and persists the slim copy via Set-GuiRemoteConnectivityResults.
		Falls back to Read-Host/Get-Credential when WPF / theme is
		unavailable (headless test runners).
	#>
	[CmdletBinding()]
	param ()

	$currentContext = Get-GuiRemoteTargetContext
	$defaultTargets = if ($currentContext -and $currentContext.TargetComputers.Count -gt 0) { ($currentContext.TargetComputers -join ', ') } else { '' }
	$defaultMethod = if ($currentContext -and $currentContext.ConnectionMethod) { [string]$currentContext.ConnectionMethod } else { 'WinRM' }

	$theme = $Script:CurrentTheme
	$canUseWpf = $false
	if ($theme)
	{
		try
		{
			$null = [System.Windows.Window]
			$null = [Windows.Markup.XamlReader]
			$canUseWpf = $true
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection:catch386' -Severity Debug }

			$canUseWpf = $false
		}
	}

	if (-not $canUseWpf)
	{
		# Headless / test-runner fallback - uses the same contract minus the UI.
		$prompt = if ($defaultTargets) { ('Computer name(s) [{0}]:' -f $defaultTargets) } else { 'Computer name(s):' }
		$targetText = Read-Host -Prompt $prompt
		if ([string]::IsNullOrWhiteSpace($targetText)) { $targetText = $defaultTargets }
		if ([string]::IsNullOrWhiteSpace($targetText)) { return $null }
		$parsed = ConvertFrom-BaselineRemoteTargetInput -InputText $targetText
		if ($parsed.Targets.Count -eq 0) { throw 'At least one computer name must be provided.' }
		$cred = $null
		try { $cred = Get-Credential -Message 'Enter credentials for remote access, or Cancel for current user.' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.GetCredential'; $cred = $null }
		return [pscustomobject]@{
			ComputerName     = @($parsed.Targets)
			Credential       = $cred
			ConnectionMethod = 'WinRM'
		}
	}

	$bc = New-SafeBrushConverter -Context 'DialogHelpers-RemoteConnect'
	$windowTitle = Get-UxLocalizedString -Key 'GuiRemoteConnectTitle' -Fallback 'Connect to Computer'
	$windowSubtitle = Get-UxLocalizedString -Key 'GuiRemoteConnectSubtitle' -Fallback 'Reach one or more remote computers over WinRM or SSH.'
	$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
	$cancelLabel = Get-UxLocalizedString -Key 'GuiCancelButton' -Fallback 'Cancel'
	$connectLabel = Get-UxLocalizedString -Key 'GuiRemoteConnectAction' -Fallback 'Connect'
	$testLabel = Get-UxLocalizedString -Key 'GuiRemoteConnectTest' -Fallback 'Test Connection'
	$scrollBarStyleXaml = if (Get-Command -Name 'Get-GuiSharedScrollBarStyleXaml' -ErrorAction SilentlyContinue) { Get-GuiSharedScrollBarStyleXaml -Theme $theme } else { '' }

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="640" Height="640"
	MinWidth="560" MinHeight="560"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="Segoe UI"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Window.Resources>
$scrollBarStyleXaml
	</Window.Resources>
	<Border Name="RootBorder" CornerRadius="8">
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>

			<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
				<Grid>
					<TextBlock Text="$windowTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
						Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
						HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</Grid>
			</Border>

			<Border Grid.Row="1" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
					Padding="20,14,20,14">
				<StackPanel>
					<TextBlock Text="$windowTitle" FontSize="16" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Text="$windowSubtitle" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Padding="20,18,20,18">
				<StackPanel>
					<TextBlock Text="Computer name(s)" FontWeight="SemiBold" FontSize="13" Foreground="$($theme.TextPrimary)" Margin="0,0,0,4"/>
					<TextBlock Text="Separate multiple names with commas, semicolons, pipes, or whitespace."
							   FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,0,6" TextWrapping="Wrap"/>
					<TextBox Name="TxtTargets" Height="62" AcceptsReturn="True" TextWrapping="Wrap"
							 VerticalScrollBarVisibility="Auto" FontSize="13" Padding="6,4"/>
					<TextBlock Name="TxtInvalid" Foreground="#D9534F" FontSize="11" Margin="0,4,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>

					<TextBlock Text="Connection method" FontWeight="SemiBold" FontSize="13" Foreground="$($theme.TextPrimary)" Margin="0,16,0,4"/>
					<ComboBox Name="CmbMethod" Height="28" FontSize="12">
						<ComboBoxItem Content="WinRM (HTTP) - default, port 5985" Tag="WinRM"/>
						<ComboBoxItem Content="WinRM over HTTPS - port 5986" Tag="WinRMHttps"/>
						<ComboBoxItem Content="SSH (PowerShell over OpenSSH) - port 22" Tag="SSH"/>
					</ComboBox>

					<TextBlock Text="Credentials" FontWeight="SemiBold" FontSize="13" Foreground="$($theme.TextPrimary)" Margin="0,16,0,4"/>
					<RadioButton Name="RbCurrentCreds" GroupName="CredsMode" Content="Use current credentials" IsChecked="True" Foreground="$($theme.TextPrimary)" Margin="0,2,0,2"/>
					<RadioButton Name="RbAlternateCreds" GroupName="CredsMode" Content="Use alternate credentials" Foreground="$($theme.TextPrimary)" Margin="0,2,0,2"/>

					<Grid Name="CredsGrid" IsEnabled="False" Margin="18,8,0,0">
						<Grid.RowDefinitions>
							<RowDefinition Height="Auto"/>
							<RowDefinition Height="Auto"/>
							<RowDefinition Height="Auto"/>
							<RowDefinition Height="Auto"/>
						</Grid.RowDefinitions>
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="140"/>
							<ColumnDefinition Width="*"/>
						</Grid.ColumnDefinitions>
						<TextBlock Grid.Row="0" Grid.Column="0" Text="Domain\Username:" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,4,8,4"/>
						<TextBox Name="TxtUsername" Grid.Row="0" Grid.Column="1" Height="26" FontSize="12" Margin="0,4,0,4" Padding="6,2"/>
						<TextBlock Grid.Row="1" Grid.Column="0" Text="Password:" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center" Margin="0,4,8,4"/>
						<PasswordBox Name="PwdPassword" Grid.Row="1" Grid.Column="1" Height="26" FontSize="12" Margin="0,4,0,4" Padding="6,2"/>
					</Grid>

					<Grid Margin="0,16,0,0">
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="Auto"/>
							<ColumnDefinition Width="*"/>
						</Grid.ColumnDefinitions>
						<Button Name="BtnTest" Grid.Column="0" Content="$testLabel" Padding="14,6" FontSize="12"/>
						<TextBlock Name="TxtTestStatus" Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="$($theme.TextMuted)" FontSize="12" TextWrapping="Wrap"/>
					</Grid>

					<Border Background="$($theme.HeaderBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="4" Padding="10,8" Margin="0,12,0,0" MinHeight="120">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" MaxHeight="160">
							<TextBlock Name="TxtResults" FontFamily="Consolas" FontSize="12" Foreground="$($theme.TextSecondary)" TextWrapping="NoWrap" Text="(no test run yet)"/>
						</ScrollViewer>
					</Border>
				</StackPanel>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<Button Name="BtnCancel" Grid.Column="1" Content="$cancelLabel" Padding="20,6" FontSize="13" Margin="0,0,8,0"/>
					<Button Name="BtnConnect" Grid.Column="2" Content="$connectLabel" Padding="20,6" FontSize="13"/>
				</Grid>
			</Border>
		</Grid>
	</Border>
</Window>
"@

	$reader = [System.Xml.XmlNodeReader]::new($xaml)
	$dlg = [Windows.Markup.XamlReader]::Load($reader)
	if ($Script:MainForm) { try { $dlg.Owner = $Script:MainForm } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.SetOwner' } }

	$rootBorder = $dlg.FindName('RootBorder')
	if ($rootBorder)
	{
		$rootBorder.Background = $bc.ConvertFromString($theme.WindowBg)
		$rootBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
		$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	}

	if (Get-Command -Name 'Set-GuiWindowChromeTheme' -ErrorAction SilentlyContinue)
	{
		try { [void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark')) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.SetWindowChromeTheme' }
	}

	$titleBar = $dlg.FindName('DlgTitleBar')
	$btnDlgClose = $dlg.FindName('BtnDlgClose')
	$txtTargets = $dlg.FindName('TxtTargets')
	$txtInvalid = $dlg.FindName('TxtInvalid')
	$cmbMethod = $dlg.FindName('CmbMethod')
	$rbCurrent = $dlg.FindName('RbCurrentCreds')
	$rbAlternate = $dlg.FindName('RbAlternateCreds')
	$credsGrid = $dlg.FindName('CredsGrid')
	$txtUsername = $dlg.FindName('TxtUsername')
	$pwdPassword = $dlg.FindName('PwdPassword')
	$btnTest = $dlg.FindName('BtnTest')
	$txtTestStatus = $dlg.FindName('TxtTestStatus')
	$txtResults = $dlg.FindName('TxtResults')
	$btnCancel = $dlg.FindName('BtnCancel')
	$btnConnect = $dlg.FindName('BtnConnect')

	if ($titleBar) { $titleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure()) }
	if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
	if ($btnCancel) { $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure()) }

	foreach ($btn in @($btnTest, $btnCancel, $btnConnect))
	{
		if ($btn -and (Get-Command -Name 'Set-ButtonChrome' -ErrorAction SilentlyContinue))
		{
			$variant = if ($btn -eq $btnConnect) { 'Primary' } else { 'Secondary' }
			try { Set-ButtonChrome -Button $btn -Variant $variant -Compact } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.SetButtonChrome' }
		}
	}

	$txtTargets.Text = $defaultTargets
	$selectedMethodIndex = switch ($defaultMethod) { 'WinRMHttps' { 1 } 'SSH' { 2 } default { 0 } }
	$cmbMethod.SelectedIndex = $selectedMethodIndex

	$rbCurrent.Add_Checked({ $credsGrid.IsEnabled = $false }.GetNewClosure())
	$rbAlternate.Add_Checked({ $credsGrid.IsEnabled = $true; $txtUsername.Focus() | Out-Null }.GetNewClosure())

	$resultBox = @{ Value = $null }

	$buildSelection = {
		$parsed = ConvertFrom-BaselineRemoteTargetInput -InputText $txtTargets.Text
		if ($parsed.Invalid.Count -gt 0)
		{
			$txtInvalid.Text = ('Ignored invalid entries: {0}' -f ($parsed.Invalid -join ', '))
			$txtInvalid.Visibility = [System.Windows.Visibility]::Visible
		}
		else
		{
			$txtInvalid.Text = ''
			$txtInvalid.Visibility = [System.Windows.Visibility]::Collapsed
		}
		if ($parsed.Targets.Count -eq 0)
		{
			throw [System.ArgumentException]::new('At least one valid computer name is required.', 'ComputerName')
		}
		$methodTag = if ($cmbMethod.SelectedItem) { [string]$cmbMethod.SelectedItem.Tag } else { 'WinRM' }
		$method = ConvertTo-BaselineRemoteConnectionMethod -Method $methodTag
		$cred = $null
		if ($rbAlternate.IsChecked)
		{
			$cred = New-BaselineRemoteTargetCredential -Username $txtUsername.Text -SecurePassword $pwdPassword.SecurePassword
		}
		return [pscustomobject]@{
			ComputerName     = @($parsed.Targets)
			Credential       = $cred
			ConnectionMethod = $method
		}
	}.GetNewClosure()

	$renderResults = {
		param ($Results)
		$rows = Format-BaselineRemoteConnectivityStatus -Result $Results
		if ($rows.Count -eq 0)
		{
			$txtResults.Text = '(no per-target results)'
			return
		}
		$txtResults.Text = (($rows | ForEach-Object { $_.Display }) -join [Environment]::NewLine)
		try { $null = Set-GuiRemoteConnectivityResults -Results $Results } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.SetGuiRemoteConnectivityResults' }
	}.GetNewClosure()

	$testState = @{ PS = $null; Async = $null; Timer = $null }

	$cleanupTest = {
		if ($testState.Timer) { try { $testState.Timer.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.CleanupTestTimer' }; $testState.Timer = $null }
		if ($testState.PS)
		{
			try { $testState.PS.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection.CleanupTestDisposePowerShell' }
			$testState.PS = $null
		}
		$testState.Async = $null
		$btnTest.IsEnabled = $true
	}.GetNewClosure()

	$btnTest.Add_Click({
		try
		{
			$selection = & $buildSelection
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection:catch650' -Severity Debug }

			$txtTestStatus.Text = $_.Exception.Message
			return
		}
		$btnTest.IsEnabled = $false
		$txtTestStatus.Text = ('Testing {0} target(s) via {1}...' -f $selection.ComputerName.Count, (Get-BaselineRemoteConnectionMethodLabel -Method $selection.ConnectionMethod))
		$txtResults.Text = '(running...)'

		$ps = [powershell]::Create()
		$ps.AddCommand('Test-BaselineRemoteConnectivity') | Out-Null
		$ps.AddParameter('ComputerName', $selection.ComputerName) | Out-Null
		$ps.AddParameter('ConnectionMethod', $selection.ConnectionMethod) | Out-Null
		if ($selection.Credential) { $ps.AddParameter('Credential', $selection.Credential) | Out-Null }
		$async = $ps.BeginInvoke()
		$testState.PS = $ps
		$testState.Async = $async

		$timer = New-Object System.Windows.Threading.DispatcherTimer
		$timer.Interval = [TimeSpan]::FromMilliseconds(150)
		$pollTick = {
			if (-not $testState.Async -or -not $testState.PS) { & $cleanupTest; return }
			if (-not $testState.Async.IsCompleted) { return }
			try
			{
				$results = @($testState.PS.EndInvoke($testState.Async))
				& $renderResults $results
				$reachable = @($results | Where-Object { $_.Reachable }).Count
				$total = $results.Count
				$txtTestStatus.Text = ('Done: {0}/{1} reachable.' -f $reachable, $total)
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection:catch681' -Severity Debug }

				$txtTestStatus.Text = ('Test failed: {0}' -f $_.Exception.Message)
				$txtResults.Text = ('Error: {0}' -f $_.Exception.Message)
			}
			finally
			{
				& $cleanupTest
			}
		}.GetNewClosure()
		$timer.Add_Tick($pollTick)
		$testState.Timer = $timer
		$timer.Start()
	}.GetNewClosure())

	$btnConnect.Add_Click({
		try
		{
			$selection = & $buildSelection
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Prompt-GuiRemoteTargetConnection:catch701' -Severity Debug }

			$txtTestStatus.Text = $_.Exception.Message
			return
		}
		$resultBox.Value = $selection
		$dlg.Close()
	}.GetNewClosure())

	$dlg.Add_Closed({ & $cleanupTest }.GetNewClosure())

	[void]$dlg.ShowDialog()
	return $resultBox.Value
}

<#
    .SYNOPSIS
#>

function Test-GuiRemoteTargetApproval
{
	<# .SYNOPSIS Tests whether the current remote target list is approved for the session. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName
	)

	$current = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
	$context = Get-GuiRemoteTargetContext
	$approved = @($context.ApprovedTargetComputers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() } | Sort-Object -Unique)

	if ($current.Count -ne $approved.Count)
	{
		return $false
	}

	for ($i = 0; $i -lt $current.Count; $i++)
	{
		if ($current[$i] -ne $approved[$i])
		{
			return $false
		}
	}

	return $true
}

<#
    .SYNOPSIS
#>

function Set-GuiRemoteTargetApprovalList
{
	<# .SYNOPSIS Approves the current target list for the active GUI session. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[string]$ApprovalMessage
	)

	if (-not $Script:Ctx)
	{
		throw 'GUI context has not been initialized.'
	}

	$targets = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim() })
	if ($targets.Count -eq 0)
	{
		throw 'At least one computer name is required.'
	}

	$Script:Ctx.Remote.ApprovedTargetComputers = @($targets)
	$Script:Ctx.Remote.ApprovedAt = [datetime]::UtcNow.ToString('o')
	$Script:Ctx.Remote.ApprovalMessage = if ([string]::IsNullOrWhiteSpace($ApprovalMessage)) { 'Remote target list approved.' } else { [string]$ApprovalMessage }
	return (Get-GuiRemoteTargetContext)
}

<#
    .SYNOPSIS
#>

function Clear-GuiRemoteTargetApprovalList
{
	<# .SYNOPSIS Clears the approved target list for the active GUI session. #>
	if (-not $Script:Ctx -or -not $Script:Ctx.ContainsKey('Remote'))
	{
		return
	}

	$Script:Ctx.Remote.ApprovedTargetComputers = @()
	$Script:Ctx.Remote.ApprovedAt = $null
	$Script:Ctx.Remote.ApprovalMessage = $null
}

function Get-GuiRemoteTargetPolicyDirectory
{
	[CmdletBinding()]
	param ()

	$settingsRoot = Get-BaselineGuiSettingsProfileDirectory
	if ([string]::IsNullOrWhiteSpace($settingsRoot))
	{
		$settingsRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
	}

	$policyDirectory = Join-Path $settingsRoot 'RemotePolicies'
	if (-not (Test-Path -LiteralPath $policyDirectory))
	{
		$null = New-Item -ItemType Directory -Path $policyDirectory -Force
	}

	return $policyDirectory
}

<#
    .SYNOPSIS
#>

function Export-GuiRemoteTargetApprovalPolicy
{
	<# .SYNOPSIS Saves the current approved remote target list to a reusable policy file. #>
	[CmdletBinding()]
	param (
		[string]$FilePath
	)

	$context = Get-GuiRemoteTargetContext
	if (-not $context.Connected -or $context.TargetComputers.Count -eq 0)
	{
		throw 'Connect to a remote target before saving a remote approval policy.'
	}

	if ($context.ApprovedTargetComputers.Count -eq 0)
	{
		throw 'Approve the current target list before saving a remote approval policy.'
	}

	if ([string]::IsNullOrWhiteSpace($FilePath))
	{
		$defaultName = 'Baseline-RemoteApprovalPolicy-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
		$FilePath = GUICommon\Show-GuiFileSaveDialog -Title 'Save Remote Approval Policy' -Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' -DefaultExtension 'json' -InitialDirectory (Get-GuiRemoteTargetPolicyDirectory) -FileName $defaultName
	}

	if ([string]::IsNullOrWhiteSpace($FilePath))
	{
		return $false
	}

	$payload = [ordered]@{
		Schema = 'Baseline.GuiRemoteTargetApprovalPolicy'
		SchemaVersion = 1
		SavedAt = [datetime]::UtcNow.ToString('o')
		TargetComputers = @($context.ApprovedTargetComputers)
		ApprovalMessage = $context.ApprovalMessage
	}

	($payload | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $FilePath -Encoding UTF8 -Force
	LogInfo ("Saved remote approval policy to {0}" -f $FilePath)
	return $true
}

<#
    .SYNOPSIS
#>

function Import-GuiRemoteTargetApprovalPolicy
{
	<# .SYNOPSIS Loads a reusable remote approval policy and applies it to the current remote target context. #>
	[CmdletBinding()]
	param (
		[string]$FilePath
	)

	if ([string]::IsNullOrWhiteSpace($FilePath))
	{
		$FilePath = GUICommon\Show-GuiFileOpenDialog -Title 'Load Remote Approval Policy' -Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' -InitialDirectory (Get-GuiRemoteTargetPolicyDirectory)
	}

	if ([string]::IsNullOrWhiteSpace($FilePath))
	{
		return $false
	}

	if (-not (Test-Path -LiteralPath $FilePath))
	{
		throw "Policy file not found: $FilePath"
	}

	$policy = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16
	if (-not $policy -or [string]::IsNullOrWhiteSpace([string]$policy.Schema) -or [string]$policy.Schema -ne 'Baseline.GuiRemoteTargetApprovalPolicy')
	{
		throw 'The selected file does not contain a valid remote approval policy.'
	}

	$targets = @($policy.TargetComputers)
	if ($targets.Count -eq 0)
	{
		throw 'The selected policy did not contain any approved targets.'
	}

	if (-not (Test-GuiRemoteTargetConnected))
	{
		throw 'Connect to a remote target before loading a remote approval policy.'
	}

	$current = Get-GuiRemoteTargetContext
	if ($current.TargetComputers.Count -ne $targets.Count -or -not (Test-GuiRemoteTargetApproval -ComputerName @($targets)))
	{
		throw 'The loaded policy does not match the currently connected target list.'
	}

	Set-GuiRemoteTargetApprovalList -ComputerName @($targets) -ApprovalMessage ([string]$policy.ApprovalMessage)
	LogInfo ("Loaded remote approval policy from {0}" -f $FilePath)
	return $true
}

<#
    .SYNOPSIS
	#>

	function Save-GuiUndoSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$Script:UiSnapshotUndo = Get-GuiSettingsSnapshot
		Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
	}

	function Copy-GuiRecommendationPanelCollapseState
	{
		param ([object]$State)

		$copy = @{}
		if ($null -eq $State) { return $copy }

		$normalizedState = Convert-JsonManifestValue $State
		if ($normalizedState -is [System.Collections.IDictionary])
		{
			foreach ($collapseEntry in $normalizedState.GetEnumerator())
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$collapseEntry.Key))
				{
					$copy[[string]$collapseEntry.Key] = [bool]$collapseEntry.Value
				}
			}
		}

		return $copy
	}

	function Get-GuiSettingsSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		# Theme preference can be 'Light', 'Dark', or 'System'. The header ChkTheme
		# only reflects the resolved Light/Dark state, so we persist the user's
		# preference (if any) so 'System' round-trips across launches.
		$themeName = if ($Script:ThemePreference) {
			[string]$Script:ThemePreference
		}
		elseif ($ChkTheme) {
			if ($ChkTheme.IsChecked) { 'Light' } else { 'Dark' }
		}
		elseif ($Script:CurrentThemeName) {
			[string]$Script:CurrentThemeName
		}
		else {
			'System'
		}

		# Session restore is UI state restore: keep the user's last search and
		# filter context, then re-detect live system state during restore.
		$searchText = if ($Script:SearchText) { [string]$Script:SearchText } else { '' }
		$appsSearchText = if ($Script:AppsSearchText) { [string]$Script:AppsSearchText } else { '' }
		# System scan is transient machine state. Persisting it across launches can silently
		# re-run expensive detection work during startup, so session snapshots always store it off.
		$scanEnabled = $false
		$searchResultsTabTag = if (Get-Variable -Name 'SearchResultsTabTag' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:SearchResultsTabTag } else { $null }
		$currentPrimaryTab = if (-not [string]::IsNullOrWhiteSpace($searchText) -and -not [string]::IsNullOrWhiteSpace($searchResultsTabTag) -and [string]$Script:CurrentPrimaryTab -eq $searchResultsTabTag) {
			$searchResultsTabTag
		}
		elseif ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}

		$currentSafeMode = if ($Script:Ctx -and $Script:Ctx.ContainsKey('Mode') -and $null -ne $Script:Ctx.Mode -and $Script:Ctx.Mode.ContainsKey('Safe')) { [bool]$Script:Ctx.Mode.Safe } else { [bool]$Script:SafeMode }
		$currentAdvancedMode = if ($Script:Ctx -and $Script:Ctx.ContainsKey('Mode') -and $null -ne $Script:Ctx.Mode -and $Script:Ctx.Mode.ContainsKey('Expert')) { [bool]$Script:Ctx.Mode.Expert } else { [bool]$Script:AdvancedMode }
		$currentModePreference = Resolve-GuiModePreference -SafeMode $currentSafeMode -AdvancedMode $currentAdvancedMode
		$currentDefaultStartupModeRaw = if (Get-Variable -Name 'DefaultStartupMode' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:DefaultStartupMode } else { $null }
		$currentDefaultStartupMode = if ($currentDefaultStartupModeRaw -in @('Safe', 'Expert'))
		{
			$currentDefaultStartupModeRaw
		}
		elseif (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			[string](Get-BaselineUserPreference -Key 'DefaultStartupMode' -Default 'Safe')
		}
		else
		{
			'Safe'
		}
		if ($currentDefaultStartupMode -notin @('Safe', 'Expert')) { $currentDefaultStartupMode = 'Safe' }
		$currentAppsModeActive = if (Get-Variable -Name 'AppsModeActive' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:AppsModeActive } else { $false }
		$currentGamingModeActive = if (Get-Variable -Name 'GamingModeActive' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:GamingModeActive } else { $false }
		$currentUpdatesModeActive = if (Get-Variable -Name 'UpdatesModeActive' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:UpdatesModeActive } else { $false }
		$currentDeploymentMediaModeActive = if (Get-Variable -Name 'DeploymentMediaModeActive' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:DeploymentMediaModeActive } else { $false }
		$currentNavigationMode = if ($currentGamingModeActive) { 'Gaming' } elseif ($currentUpdatesModeActive) { 'Updates' } elseif ($currentDeploymentMediaModeActive) { 'DeploymentMedia' } elseif ($currentAppsModeActive) { 'Apps' } else { 'Optimize' }
		$currentActivePresetName = if ((Get-Variable -Name 'ActivePresetName' -Scope Script -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace([string]$Script:ActivePresetName)) { [string]$Script:ActivePresetName } else { $null }
		$currentActiveScenarioNames = @(
			if ((Get-Variable -Name 'ActiveScenarioNames' -Scope Script -ErrorAction SilentlyContinue) -and $Script:ActiveScenarioNames -is [System.Collections.IDictionary])
			{
				$Script:ActiveScenarioNames.GetEnumerator() |
					Where-Object { [bool]$_.Value -and -not [string]::IsNullOrWhiteSpace([string]$_.Key) } |
					Sort-Object Key |
					ForEach-Object { [string]$_.Key }
			}
		)
		$currentRecommendationPanelCollapseState = if ((Get-Variable -Name 'RecommendedSelectionsCollapsedByScope' -Scope Script -ErrorAction SilentlyContinue)) { Copy-GuiRecommendationPanelCollapseState -State $Script:RecommendedSelectionsCollapsedByScope } else { @{} }
		$currentFilterPanelExpanded = if ((Get-Variable -Name 'FilterOptionsPanel' -Scope Script -ErrorAction SilentlyContinue) -and $Script:FilterOptionsPanel) { [string]$Script:FilterOptionsPanel.Visibility -eq 'Visible' } else { $false }
		$currentAppsFilterPanelExpanded = if ((Get-Variable -Name 'AppsFilterOptionsPanel' -Scope Script -ErrorAction SilentlyContinue) -and $Script:AppsFilterOptionsPanel) { [string]$Script:AppsFilterOptionsPanel.Visibility -eq 'Visible' } else { $false }

		$explicitDefinitionsByFunction = @{}
		$snapshotExplicitDefinitions = [System.Collections.Generic.List[object]]::new()
		if ($Script:ExplicitPresetSelectionDefinitions)
		{
			$Script:ExplicitPresetSelectionDefinitions.GetEnumerator() |
				Sort-Object Key |
				ForEach-Object {
					$definitionCopy = Copy-GuiExplicitSelectionDefinition -Definition $_.Value -FunctionName ([string]$_.Key)
					if ($definitionCopy)
					{
						$explicitDefinitionsByFunction[[string]$_.Key] = $definitionCopy
						[void]$snapshotExplicitDefinitions.Add($definitionCopy)
					}
				}
		}
		$addSessionExplicitDefinition = {
			param (
				[string]$FunctionName,
				[object]$Definition
			)

			if ([string]::IsNullOrWhiteSpace($FunctionName)) { return }
			if ($explicitDefinitionsByFunction.ContainsKey($FunctionName)) { return }

			$definitionCopy = Copy-GuiExplicitSelectionDefinition -Definition $Definition -FunctionName $FunctionName -Source 'Session'
			if (-not $definitionCopy) { return }

			$explicitDefinitionsByFunction[$FunctionName] = $definitionCopy
			[void]$snapshotExplicitDefinitions.Add($definitionCopy)
		}

		$snapshot = [ordered]@{
			Schema = 'Baseline.GuiSettings'
			SchemaVersion = 20
			SavedAt = (Get-Date).ToString('o')
			Theme = $themeName
			Language = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
			SearchText = $searchText
			AppsSearchText = $appsSearchText
			UIDensity = if (Get-Command -Name 'Get-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineUiDensity } elseif ($Script:UIDensity) { [string]$Script:UIDensity } else { 'Comfort' }
			AuditRetentionDays = if ($Script:AuditRetentionDays) { [int]$Script:AuditRetentionDays } else { 90 }
			AppsPackageSourcePreference = if ($Script:AppsPackageSourcePreference) { [string]$Script:AppsPackageSourcePreference } else { 'auto' }
			AppsSourceFilter = if ($Script:AppsSourceFilter) { [string]$Script:AppsSourceFilter } else { 'All' }
			NavigationMode = $currentNavigationMode
			ActivePresetName = $currentActivePresetName
			ActiveScenarioNames = @($currentActiveScenarioNames)
			RecommendationPanelCollapseState = Convert-JsonManifestValue $currentRecommendationPanelCollapseState
			PinnedBaselineVersion = if ($Script:PinnedBaselineVersion) { [string]$Script:PinnedBaselineVersion } else { $null }
			AppsQueuedActions = @(
				if ($Script:AppsQueuedActions -is [System.Collections.Generic.Dictionary[string, string]])
				{
					$Script:AppsQueuedActions.GetEnumerator() |
						Sort-Object Key |
						ForEach-Object {
							[ordered]@{
								AppId = [string]$_.Key
								Action = [string]$_.Value
							}
						}
				}
			)
			ScanEnabled = $scanEnabled
			AutoScanOnLaunch = [bool]$Script:AutoScanOnLaunch
			RestoreLastSession = if ($null -ne $Script:RestoreLastSession) { [bool]$Script:RestoreLastSession } else { $true }
			StartupRunInitialActions = if (Get-Variable -Name 'StartupRunInitialActions' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:StartupRunInitialActions } else { $true }
			StartupCheckWinGet = if (Get-Variable -Name 'StartupCheckWinGet' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:StartupCheckWinGet } else { $true }
			StartupWinGetCheckFrequency = if (Get-Variable -Name 'StartupWinGetCheckFrequency' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:StartupWinGetCheckFrequency } else { 'Startup' }
			StartupCheckChocolatey = if (Get-Variable -Name 'StartupCheckChocolatey' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:StartupCheckChocolatey } else { $true }
			StartupChocolateyCheckFrequency = if (Get-Variable -Name 'StartupChocolateyCheckFrequency' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:StartupChocolateyCheckFrequency } else { 'Startup' }
			DefaultStartupMode = $currentDefaultStartupMode
			AutoCheckUpdates = if ($null -ne $Script:AutoCheckUpdates) { [bool]$Script:AutoCheckUpdates } else { $true }
			UpdateCheckFrequency = if ($Script:UpdateCheckFrequency) { [string]$Script:UpdateCheckFrequency } else { 'Startup' }
			UpdateBranch = if ($Script:UpdateBranch) { [string]$Script:UpdateBranch } elseif (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
			IncludePrereleaseUpdates = if ($null -ne $Script:IncludePrereleaseUpdates) { [bool]$Script:IncludePrereleaseUpdates } else { $false }
			AdvancedMode = [bool]$currentModePreference.AdvancedMode
			SafeMode = [bool]$currentModePreference.SafeMode
			RequireRunConfirmation = if ($null -ne $Script:RequireRunConfirmation) { [bool]$Script:RequireRunConfirmation } else { $true }
			PreviewBeforeRunDefault = [bool]$Script:PreviewBeforeRunDefault
			GameMode = [bool]$Script:GameMode
			GameModeProfile = if ($Script:GameModeProfile) { [string]$Script:GameModeProfile } else { $null }
			GameModeCorePlan = @($Script:GameModeCorePlan)
			GameModePlan = @($Script:GameModePlan)
			GameModeDecisionOverrides = Convert-JsonManifestValue $Script:GameModeDecisionOverrides
			GameModeAdvancedSelections = Convert-JsonManifestValue $Script:GameModeAdvancedSelections
			GameModePreviousPrimaryTab = if ($Script:GameModePreviousPrimaryTab) { [string]$Script:GameModePreviousPrimaryTab } else { $null }
			RiskFilter = if ($Script:RiskFilter) { [string]$Script:RiskFilter } else { 'All' }
			CategoryFilter = if ($Script:CategoryFilter) { [string]$Script:CategoryFilter } else { 'All' }
			PlatformFilter = if ($Script:PlatformFilter) { [string]$Script:PlatformFilter } else { 'ThisDevice' }
			FilterPanelExpanded = [bool]$currentFilterPanelExpanded
			AppsFilterPanelExpanded = [bool]$currentAppsFilterPanelExpanded
			AppsCategoryFilter = if ($Script:AppsCategoryFilter) { [string]$Script:AppsCategoryFilter } else { 'Browsers' }
			AppsStatusFilter = if ($Script:AppsStatusFilter) { [string]$Script:AppsStatusFilter } else { 'All' }
			SelectedOnlyFilter = [bool]$Script:SelectedOnlyFilter
			HideUnavailableItems = [bool]$Script:HideUnavailableItems
			AppsAutoUpdate = [bool]$Script:AppsAutoUpdate
			AppsSilentInstall = if ($null -ne $Script:AppsSilentInstall) { [bool]$Script:AppsSilentInstall } else { $true }
			LoggingEnabled = if ($null -ne $Script:LoggingEnabled) { [bool]$Script:LoggingEnabled } else { $true }
			DebugLoggingEnabled = if ($null -ne $Script:DebugLoggingEnabled) { [bool]$Script:DebugLoggingEnabled } else { $false }
			LogLevel = if ($Script:LogLevel) { [string]$Script:LogLevel } else { 'All' }
			DesignMode = [bool]$Script:DesignMode
			HighRiskOnlyFilter = [bool]$Script:HighRiskOnlyFilter
			RestorableOnlyFilter = [bool]$Script:RestorableOnlyFilter
			GamingOnlyFilter = [bool]$Script:GamingOnlyFilter
			CurrentPrimaryTab = $currentPrimaryTab
			LastStandardPrimaryTab = if ($Script:LastStandardPrimaryTab) { [string]$Script:LastStandardPrimaryTab } else { $null }
			ExplicitSelections = @($Script:ExplicitPresetSelections)
			ExplicitSelectionDefinitions = $null
			Controls = $null
		}

		$controlList = [System.Collections.Generic.List[pscustomobject]]::new($Script:TweakManifest.Count)
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$manifest = $Script:TweakManifest[$i]
			$control = $Script:Controls[$i]
			$manifestFunction = [string]$manifest.Function
			$explicitDefinition = if (-not [string]::IsNullOrWhiteSpace($manifestFunction) -and $explicitDefinitionsByFunction.ContainsKey($manifestFunction)) { $explicitDefinitionsByFunction[$manifestFunction] } else { $null }
			$entry = [ordered]@{
				Index = $i
				Function = $manifest.Function
				Type = $manifest.Type
			}

			switch ($manifest.Type)
			{
				'Date'
				{
					$controlIsEnabled = if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsEnabled')) { [bool]$control.IsEnabled } else { $true }
					if ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'Date' -and (Test-GuiObjectField -Object $explicitDefinition -FieldName 'Run'))
					{
						$entry.IsChecked = [bool]$explicitDefinition.Run
					}
					elseif ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'Date' -and (
						((Test-GuiObjectField -Object $explicitDefinition -FieldName 'DateValue') -and -not [string]::IsNullOrWhiteSpace([string]$explicitDefinition.DateValue)) -or
						((Test-GuiObjectField -Object $explicitDefinition -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$explicitDefinition.Value)) -or
						((Test-GuiObjectField -Object $explicitDefinition -FieldName 'SelectedDate') -and -not [string]::IsNullOrWhiteSpace([string]$explicitDefinition.SelectedDate))))
					{
						$entry.IsChecked = $true
					}
					else
					{
						$entry.IsChecked = if ($controlIsEnabled -and $control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked')) { [bool]$control.IsChecked } else { $false }
					}
					$selectedDate = $null
					if ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'Date')
					{
						foreach ($dateFieldName in @('DateValue', 'Value', 'SelectedDate'))
						{
							if ((Test-GuiObjectField -Object $explicitDefinition -FieldName $dateFieldName) -and -not [string]::IsNullOrWhiteSpace([string]$explicitDefinition.$dateFieldName))
							{
								$selectedDate = [string]$explicitDefinition.$dateFieldName
								break
							}
						}
					}
					if (-not $selectedDate -and $control)
					{
						if ((Test-GuiObjectField -Object $control -FieldName 'SelectedDate') -and $control.SelectedDate)
						{
							$selectedDate = ([datetime]$control.SelectedDate).ToString('yyyy-MM-dd')
						}
						elseif ((Test-GuiObjectField -Object $control -FieldName 'DatePicker') -and $control.DatePicker -and (Test-GuiObjectField -Object $control.DatePicker -FieldName 'SelectedDate') -and $control.DatePicker.SelectedDate)
						{
							$selectedDate = ([datetime]$control.DatePicker.SelectedDate).ToString('yyyy-MM-dd')
						}
					}
					$entry.SelectedDate = $selectedDate
					if (-not $explicitDefinition -and [bool]$entry.IsChecked)
					{
						& $addSessionExplicitDefinition -FunctionName $manifestFunction -Definition ([pscustomobject]@{
							Function = $manifestFunction
							Type = 'Date'
							Run = $true
							Value = $selectedDate
						})
					}
				}
				'Choice'
				{
					$selectedIndex = -1
					if ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'Choice' -and (Test-GuiObjectField -Object $explicitDefinition -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$explicitDefinition.Value) -and $manifest.Options)
					{
						$selectedIndex = [array]::IndexOf(@($manifest.Options), [string]$explicitDefinition.Value)
					}
					elseif ($control -and (Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
					{
						$selectedIndex = [int]$control.SelectedIndex
					}
					$selectedValue = $null
					if ($selectedIndex -ge 0 -and $selectedIndex -lt $manifest.Options.Count)
					{
						$selectedValue = [string]$manifest.Options[$selectedIndex]
					}
					$entry.SelectedIndex = [int]$selectedIndex
					$entry.SelectedValue = $selectedValue
					if (-not $explicitDefinition -and $selectedIndex -ge 0 -and -not [string]::IsNullOrWhiteSpace($selectedValue))
					{
						& $addSessionExplicitDefinition -FunctionName $manifestFunction -Definition ([pscustomobject]@{
							Function = $manifestFunction
							Type = 'Choice'
							Value = $selectedValue
						})
					}
				}
				default
				{
					$controlIsEnabled = if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsEnabled')) { [bool]$control.IsEnabled } else { $true }
					if ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'Toggle')
					{
						$entry.IsChecked = ((Test-GuiObjectField -Object $explicitDefinition -FieldName 'State') -and [string]$explicitDefinition.State -eq 'On')
					}
					elseif ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'Action' -and (Test-GuiObjectField -Object $explicitDefinition -FieldName 'Run'))
					{
						$entry.IsChecked = [bool]$explicitDefinition.Run
					}
					elseif ($explicitDefinition -and [string]$explicitDefinition.Type -eq 'NumericRange')
					{
						$entry.IsChecked = $true
					}
					else
					{
						$entry.IsChecked = if ($controlIsEnabled -and $control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked')) { [bool]$control.IsChecked } else { $false }
					}
					if (-not $explicitDefinition -and [bool]$entry.IsChecked)
					{
						switch ([string]$manifest.Type)
						{
							'Toggle'
							{
								& $addSessionExplicitDefinition -FunctionName $manifestFunction -Definition ([pscustomobject]@{
									Function = $manifestFunction
									Type = 'Toggle'
									State = 'On'
								})
							}
							'Action'
							{
								& $addSessionExplicitDefinition -FunctionName $manifestFunction -Definition ([pscustomobject]@{
									Function = $manifestFunction
									Type = 'Action'
									Run = $true
								})
							}
						}
					}
				}
			}

			$controlList.Add([pscustomobject]$entry)
		}

		$snapshot.ExplicitSelectionDefinitions = $snapshotExplicitDefinitions.ToArray()
		$snapshot.Controls = $controlList.ToArray()
		return [pscustomobject]$snapshot
	}

	<#
	    .SYNOPSIS
	#>

	function Restore-GuiSettingsSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[Parameter(Mandatory = $true)]
			[object]
			$Snapshot,

			[switch]
			$PreserveDurablePreferences
		)

		if (-not $Snapshot)
		{
			throw "No GUI settings snapshot was supplied."
		}

		Clear-TabContentCache

		$controlStates = @{}
		if ((Test-GuiObjectField -Object $Snapshot -FieldName 'Controls'))
		{
			foreach ($entry in @($Snapshot.Controls))
			{
				if ($entry -and (Test-GuiObjectField -Object $entry -FieldName 'Function'))
				{
					$controlStates[[string]$entry.Function] = $entry
				}
			}
		}

		Initialize-GuiSelectionStateStores
		$Script:ExplicitPresetSelections.Clear()
		$Script:ExplicitPresetSelectionDefinitions.Clear()

		$desiredTheme = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'Theme')) { [string]$Snapshot.Theme } else { 'System' }
		# System scan must be rerun explicitly for the current machine state instead of being
		# replayed from a saved session.
		$desiredScan  = $false
		$desiredLanguage = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'Language') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.Language)) { [string]$Snapshot.Language } else { $null }
		$desiredSearch = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'SearchText')) { [string]$Snapshot.SearchText } else { '' }
		$desiredAppsSearch = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsSearchText')) { [string]$Snapshot.AppsSearchText } else { '' }
		$desiredUiDensity = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'UIDensity') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.UIDensity)) { [string]$Snapshot.UIDensity } else { 'Comfort' }
		if (Get-Command -Name 'Normalize-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$desiredUiDensity = Normalize-BaselineUiDensity -Density $desiredUiDensity
		}
		$desiredAuditRetentionDays = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AuditRetentionDays')) { [int]$Snapshot.AuditRetentionDays } else { 90 }
		$desiredAppsPackageSourcePreference = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsPackageSourcePreference') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.AppsPackageSourcePreference)) { [string]$Snapshot.AppsPackageSourcePreference } else { 'auto' }
		$desiredAppsSourceFilter = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsSourceFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.AppsSourceFilter)) { [string]$Snapshot.AppsSourceFilter } else { 'All' }
		$allowedAppsSourceFilter = @('All', 'winget', 'choco')
		if ($allowedAppsSourceFilter -notcontains $desiredAppsSourceFilter) { $desiredAppsSourceFilter = 'All' }
		$desiredNavigationMode = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'NavigationMode') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.NavigationMode)) { [string]$Snapshot.NavigationMode } else { 'Optimize' }
		$allowedNavigationModes = @('Optimize', 'Gaming', 'Apps', 'Updates', 'DeploymentMedia')
		if ($allowedNavigationModes -notcontains $desiredNavigationMode) { $desiredNavigationMode = 'Optimize' }
		$desiredActivePresetName = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'ActivePresetName') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.ActivePresetName)) { [string]$Snapshot.ActivePresetName } else { $null }
		$desiredActiveScenarioNames = @(
			if ([string]::IsNullOrWhiteSpace($desiredActivePresetName) -and (Test-GuiObjectField -Object $Snapshot -FieldName 'ActiveScenarioNames') -and $null -ne $Snapshot.ActiveScenarioNames)
			{
				@($Snapshot.ActiveScenarioNames) |
					Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
					ForEach-Object { [string]$_ } |
					Select-Object -Unique
			}
		)
		$desiredRecommendationPanelCollapseState = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RecommendationPanelCollapseState')) { Copy-GuiRecommendationPanelCollapseState -State $Snapshot.RecommendationPanelCollapseState } else { @{} }
		$desiredAppsQueuedActions = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsQueuedActions') -and $null -ne $Snapshot.AppsQueuedActions) { @($Snapshot.AppsQueuedActions) } else { @() }
		$desiredPinnedBaselineVersion = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'PinnedBaselineVersion') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.PinnedBaselineVersion)) { [string]$Snapshot.PinnedBaselineVersion } else { $null }
		$desiredAutoScanOnLaunch = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			[bool](Get-BaselineUserPreference -Key 'AutoScanOnLaunch' -Default $false)
		}
		elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'AutoScanOnLaunch')) { [bool]$Snapshot.AutoScanOnLaunch }
		else { $false }
		$desiredRestoreLastSession = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RestoreLastSession')) { [bool]$Snapshot.RestoreLastSession } else { $true }
		$snapshotStartupRunInitialActions = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'StartupRunInitialActions')) { [bool]$Snapshot.StartupRunInitialActions } elseif (Get-Variable -Name 'StartupRunInitialActions' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:StartupRunInitialActions } else { $true }
		$snapshotStartupCheckWinGet = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'StartupCheckWinGet')) { [bool]$Snapshot.StartupCheckWinGet } elseif (Get-Variable -Name 'StartupCheckWinGet' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:StartupCheckWinGet } else { $true }
		$snapshotStartupWinGetCheckFrequency = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'StartupWinGetCheckFrequency') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.StartupWinGetCheckFrequency)) { [string]$Snapshot.StartupWinGetCheckFrequency } elseif (Get-Variable -Name 'StartupWinGetCheckFrequency' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:StartupWinGetCheckFrequency } else { 'Startup' }
		$snapshotStartupCheckChocolatey = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'StartupCheckChocolatey')) { [bool]$Snapshot.StartupCheckChocolatey } elseif (Get-Variable -Name 'StartupCheckChocolatey' -Scope Script -ErrorAction SilentlyContinue) { [bool]$Script:StartupCheckChocolatey } else { $true }
		$snapshotStartupChocolateyCheckFrequency = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'StartupChocolateyCheckFrequency') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.StartupChocolateyCheckFrequency)) { [string]$Snapshot.StartupChocolateyCheckFrequency } elseif (Get-Variable -Name 'StartupChocolateyCheckFrequency' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:StartupChocolateyCheckFrequency } else { 'Startup' }
		$desiredStartupRunInitialActions = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'StartupRunInitialActions' -Default $snapshotStartupRunInitialActions) } else { $snapshotStartupRunInitialActions }
		$desiredStartupCheckWinGet = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'StartupCheckWinGet' -Default $snapshotStartupCheckWinGet) } else { $snapshotStartupCheckWinGet }
		$desiredStartupWinGetCheckFrequency = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [string](Get-BaselineUserPreference -Key 'StartupWinGetCheckFrequency' -Default $snapshotStartupWinGetCheckFrequency) } else { $snapshotStartupWinGetCheckFrequency }
		$desiredStartupCheckChocolatey = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'StartupCheckChocolatey' -Default $snapshotStartupCheckChocolatey) } else { $snapshotStartupCheckChocolatey }
		$desiredStartupChocolateyCheckFrequency = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [string](Get-BaselineUserPreference -Key 'StartupChocolateyCheckFrequency' -Default $snapshotStartupChocolateyCheckFrequency) } else { $snapshotStartupChocolateyCheckFrequency }
		if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$desiredStartupWinGetCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $desiredStartupWinGetCheckFrequency
			$desiredStartupChocolateyCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $desiredStartupChocolateyCheckFrequency
		}
		$preserveDurablePreferences = [bool]$PreserveDurablePreferences
		$hasUserPreferenceReader = [bool](Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		$hasSnapshotUpdateSettings = (Test-GuiObjectField -Object $Snapshot -FieldName 'AutoCheckUpdates') -or (Test-GuiObjectField -Object $Snapshot -FieldName 'UpdateCheckFrequency') -or (Test-GuiObjectField -Object $Snapshot -FieldName 'UpdateBranch') -or (Test-GuiObjectField -Object $Snapshot -FieldName 'IncludePrereleaseUpdates')
		$desiredAutoCheckUpdates = if ($preserveDurablePreferences -and $hasUserPreferenceReader) { [bool](Get-BaselineUserPreference -Key 'AutoCheckUpdates' -Default $true) } elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'AutoCheckUpdates')) { [bool]$Snapshot.AutoCheckUpdates } elseif ($hasUserPreferenceReader) { [bool](Get-BaselineUserPreference -Key 'AutoCheckUpdates' -Default $true) } else { if ($null -ne $Script:AutoCheckUpdates) { [bool]$Script:AutoCheckUpdates } else { $true } }
		$desiredUpdateCheckFrequency = if ($preserveDurablePreferences -and $hasUserPreferenceReader) { [string](Get-BaselineUserPreference -Key 'UpdateCheckFrequency' -Default 'Startup') } elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'UpdateCheckFrequency') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.UpdateCheckFrequency)) { [string]$Snapshot.UpdateCheckFrequency } elseif ($hasUserPreferenceReader) { [string](Get-BaselineUserPreference -Key 'UpdateCheckFrequency' -Default 'Startup') } else { if ($Script:UpdateCheckFrequency) { [string]$Script:UpdateCheckFrequency } else { 'Startup' } }
		if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$desiredUpdateCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $desiredUpdateCheckFrequency
		}
		$defaultUpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
		$desiredUpdateBranch = if ($preserveDurablePreferences -and $hasUserPreferenceReader) { [string](Get-BaselineUserPreference -Key 'UpdateBranch' -Default $defaultUpdateBranch) } elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'UpdateBranch') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.UpdateBranch)) { [string]$Snapshot.UpdateBranch } elseif ($hasUserPreferenceReader) { [string](Get-BaselineUserPreference -Key 'UpdateBranch' -Default $defaultUpdateBranch) } else { if ($Script:UpdateBranch) { [string]$Script:UpdateBranch } else { $defaultUpdateBranch } }
		if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$desiredUpdateBranch = ConvertTo-BaselineUpdateBranch -Branch $desiredUpdateBranch
		}
		$desiredIncludePrereleaseUpdates = if ($preserveDurablePreferences -and $hasUserPreferenceReader) { [bool](Get-BaselineUserPreference -Key 'IncludePrereleaseUpdates' -Default $false) } elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'IncludePrereleaseUpdates')) { [bool]$Snapshot.IncludePrereleaseUpdates } elseif ($hasUserPreferenceReader) { [bool](Get-BaselineUserPreference -Key 'IncludePrereleaseUpdates' -Default $false) } else { if ($null -ne $Script:IncludePrereleaseUpdates) { [bool]$Script:IncludePrereleaseUpdates } else { $false } }
		$desiredSafe = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'SafeMode')) { [bool]$Snapshot.SafeMode } else { $false }
		$desiredAdvanced = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AdvancedMode')) { [bool]$Snapshot.AdvancedMode } else { $false }
		$desiredDefaultStartupMode = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'DefaultStartupMode') -and ([string]$Snapshot.DefaultStartupMode -in @('Safe', 'Expert')))
		{
			[string]$Snapshot.DefaultStartupMode
		}
		elseif (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			[string](Get-BaselineUserPreference -Key 'DefaultStartupMode' -Default 'Safe')
		}
		elseif ((Get-Variable -Name 'DefaultStartupMode' -Scope Script -ErrorAction SilentlyContinue) -and ($Script:DefaultStartupMode -in @('Safe', 'Expert')))
		{
			[string]$Script:DefaultStartupMode
		}
		else
		{
			'Safe'
		}
		if ($desiredDefaultStartupMode -notin @('Safe', 'Expert')) { $desiredDefaultStartupMode = 'Safe' }
		$desiredRequireRunConfirmation = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RequireRunConfirmation')) { [bool]$Snapshot.RequireRunConfirmation } else { $true }
		$desiredPreviewBeforeRunDefault = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'PreviewBeforeRunDefault')) { [bool]$Snapshot.PreviewBeforeRunDefault } else { $false }
		$desiredGameMode = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameMode')) { [bool]$Snapshot.GameMode } else { $false }
		if ($desiredGameMode -and $desiredNavigationMode -eq 'Optimize')
		{
			$desiredNavigationMode = 'Gaming'
		}
		$desiredGameModeProfile = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeProfile')) { [string]$Snapshot.GameModeProfile } else { $null }
		$desiredGameModeCorePlan = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeCorePlan')) { @($Snapshot.GameModeCorePlan) } else { @() }
		$desiredGameModePlan = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModePlan')) { @($Snapshot.GameModePlan) } else { @() }
		$desiredGameModeDecisionOverrides = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeDecisionOverrides') -and $null -ne $Snapshot.GameModeDecisionOverrides) { Convert-JsonManifestValue $Snapshot.GameModeDecisionOverrides } else { @{} }
		$desiredGameModeAdvancedSelections = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeAdvancedSelections') -and $null -ne $Snapshot.GameModeAdvancedSelections) { Convert-JsonManifestValue $Snapshot.GameModeAdvancedSelections } else { @{} }
		$desiredGameModePreviousPrimaryTab = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModePreviousPrimaryTab')) { [string]$Snapshot.GameModePreviousPrimaryTab } else { $null }
		$desiredModePreference = Resolve-GuiModePreference -SafeMode $desiredSafe -AdvancedMode $desiredAdvanced
		$desiredSafe = [bool]$desiredModePreference.SafeMode
		$desiredAdvanced = [bool]$desiredModePreference.AdvancedMode
		$desiredRisk = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RiskFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.RiskFilter)) { [string]$Snapshot.RiskFilter } else { 'All' }
		$desiredCategory = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'CategoryFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.CategoryFilter)) { [string]$Snapshot.CategoryFilter } else { 'All' }
		$desiredPlatform = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'PlatformFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.PlatformFilter)) { [string]$Snapshot.PlatformFilter } else { 'ThisDevice' }
		$desiredAppsCategory = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsCategoryFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.AppsCategoryFilter)) { [string]$Snapshot.AppsCategoryFilter } else { 'Browsers' }
		if (Get-Command -Name 'Resolve-AppsCatalogCategory' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$desiredAppsCategory = Resolve-AppsCatalogCategory -Category $desiredAppsCategory
		}
		elseif ($desiredAppsCategory -eq 'All')
		{
			$desiredAppsCategory = 'Browsers'
		}
		$desiredAppsStatus = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsStatusFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.AppsStatusFilter)) { [string]$Snapshot.AppsStatusFilter } else { 'All' }
		$allowedAppsStatus = @('All', 'Installed', 'NotInstalled', 'UpdateAvailable')
		if ($allowedAppsStatus -notcontains $desiredAppsStatus) { $desiredAppsStatus = 'All' }
		$desiredFilterPanelExpanded = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'FilterPanelExpanded')) { [bool]$Snapshot.FilterPanelExpanded } else { $false }
		$desiredAppsFilterPanelExpanded = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsFilterPanelExpanded')) { [bool]$Snapshot.AppsFilterPanelExpanded } else { $false }
		$desiredSelectedOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'SelectedOnlyFilter')) { [bool]$Snapshot.SelectedOnlyFilter } else { $false }
		$desiredHideUnavailableItems = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'HideUnavailableItems')) { [bool]$Snapshot.HideUnavailableItems } else { [bool]$Script:HideUnavailableItems }
		$desiredAppsAutoUpdate = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsAutoUpdate')) { [bool]$Snapshot.AppsAutoUpdate } else { $false }
		$desiredAppsSilentInstall = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AppsSilentInstall')) { [bool]$Snapshot.AppsSilentInstall } else { $true }
		$desiredLoggingEnabled = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'LoggingEnabled')) { [bool]$Snapshot.LoggingEnabled } else { $true }
		$desiredDebugLoggingEnabled = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'DebugLoggingEnabled')) { [bool]$Snapshot.DebugLoggingEnabled } else { if ($null -ne $Script:DebugLoggingEnabled) { [bool]$Script:DebugLoggingEnabled } else { $false } }
		$desiredLogLevel = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'LogLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.LogLevel)) { [string]$Snapshot.LogLevel } else { if ($Script:LogLevel) { [string]$Script:LogLevel } else { 'All' } }
		if (Get-Command -Name 'Normalize-GuiLogLevel' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$desiredLogLevel = Normalize-GuiLogLevel -Level $desiredLogLevel
		}
		$desiredDesignMode = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'DesignMode')) { [bool]$Snapshot.DesignMode } else { [bool]$Script:DesignMode }
		$desiredHighRiskOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'HighRiskOnlyFilter')) { [bool]$Snapshot.HighRiskOnlyFilter } else { $false }
		$desiredRestorableOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RestorableOnlyFilter')) { [bool]$Snapshot.RestorableOnlyFilter } else { $false }
		$desiredGamingOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GamingOnlyFilter')) { [bool]$Snapshot.GamingOnlyFilter } else { $false }
		$desiredTab   = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'CurrentPrimaryTab')) { [string]$Snapshot.CurrentPrimaryTab } else { $null }
		$desiredLast  = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'LastStandardPrimaryTab')) { [string]$Snapshot.LastStandardPrimaryTab } else { $null }

		if ($desiredLast)
		{
			$Script:LastStandardPrimaryTab = $desiredLast
		}
		if (-not [string]::IsNullOrWhiteSpace($desiredGameModePreviousPrimaryTab))
		{
			$Script:GameModePreviousPrimaryTab = $desiredGameModePreviousPrimaryTab
		}

		# Resolve 'System' preference to a concrete Light/Dark theme based on the
		# Windows AppsUseLightTheme registry value, but keep $Script:ThemePreference
		# as 'System' so the choice persists across relaunches.
		if (Get-Command -Name 'Apply-BaselineThemePreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Apply-BaselineThemePreference -Preference $desiredTheme } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.ApplyThemePreference' }
		}
		else
		{
			$resolvedTheme = if ($desiredTheme -eq 'System') {
				if (Get-Command -Name 'Get-BaselineSystemThemePreference' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineSystemThemePreference } else { 'Light' }
			} elseif ($desiredTheme -eq 'Light' -or $desiredTheme -eq 'Dark') {
				$desiredTheme
			} else {
				'Dark'
			}
			$Script:ThemePreference = $desiredTheme
			if ($ChkTheme)
			{
				if ($resolvedTheme -eq 'Light' -and -not $ChkTheme.IsChecked)
				{
					$ChkTheme.IsChecked = $true
				}
				elseif ($resolvedTheme -ne 'Light' -and $ChkTheme.IsChecked)
				{
					$ChkTheme.IsChecked = $false
				}
			}
			else
			{
				if ($resolvedTheme -eq 'Light')
				{
					Set-GUITheme -Theme $Script:LightTheme
				}
				else
				{
					Set-GUITheme -Theme $Script:DarkTheme
				}
			}
		}

		# Restore saved language preference.
        if ($desiredLanguage)
        {
            $Script:SelectedLanguage = $desiredLanguage
            $locDir = $Script:GuiLocalizationDirectoryPath
            if (-not [string]::IsNullOrWhiteSpace([string]$locDir))
            {
                $Global:Localization = Import-BaselineLocalization -BaseDirectory $locDir -UICulture $desiredLanguage
				[void](Set-BaselineThreadCulture -UICulture $desiredLanguage)
				$env:BASELINE_LANGUAGE = $desiredLanguage
            }
		}

		$Script:FilterUiUpdating = $true
		# P5 rollback checkpoint: Restore-GuiSettingsSnapshot preferences split to SessionState/Restore-GuiSettingsSnapshot/RestorePreferenceSettings.ps1.
		. (Join-Path $PSScriptRoot 'SessionState\Restore-GuiSettingsSnapshot\RestorePreferenceSettings.ps1')

		$Script:RequireRunConfirmation = $desiredRequireRunConfirmation
		$Script:PreviewBeforeRunDefault = $desiredPreviewBeforeRunDefault
		$Script:AppsAutoUpdate = $desiredAppsAutoUpdate
		$Script:AppsSilentInstall = $desiredAppsSilentInstall
		$Script:LoggingEnabled = $desiredLoggingEnabled
		$Script:DebugLoggingEnabled = $desiredDebugLoggingEnabled
		$Script:LogLevel = $desiredLogLevel
		if (Get-Command -Name 'Set-BaselineDebugLogging' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Set-BaselineDebugLogging -Enabled $desiredDebugLoggingEnabled } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SetDebugLogging' }
		}
		if (Get-Command -Name 'Set-GuiPerfTraceState' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Set-GuiPerfTraceState -Enabled $desiredDebugLoggingEnabled } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SetPerfTrace' }
		}
		$null = Set-PlatformFilterState -PlatformFilter $desiredPlatform
		$null = Set-HideUnavailableItemsState -HideUnavailableItems $desiredHideUnavailableItems
		# P5 rollback checkpoint: Restore-GuiSettingsSnapshot selection replay split to SessionState/Restore-GuiSettingsSnapshot/RestoreExplicitSelectionState.ps1.
		$selectionBulkPreviousState = Enter-GuiSelectionBulkUpdate
		try
		{
			. (Join-Path $PSScriptRoot 'SessionState\Restore-GuiSettingsSnapshot\RestoreExplicitSelectionState.ps1')
		}
		finally
		{
			Exit-GuiSelectionBulkUpdate -PreviousState $selectionBulkPreviousState
		}
		$Script:ActivePresetName = $desiredActivePresetName
		$Script:ActiveScenarioNames = @{}
		foreach ($scenarioName in @($desiredActiveScenarioNames))
		{
			if (-not [string]::IsNullOrWhiteSpace([string]$scenarioName))
			{
				$Script:ActiveScenarioNames[[string]$scenarioName] = $true
			}
		}
		$Script:RecommendedSelectionsCollapsedByScope = Copy-GuiRecommendationPanelCollapseState -State $desiredRecommendationPanelCollapseState
		$Script:SearchText = $desiredSearch
		$Script:AppsSearchText = $desiredAppsSearch
		$Script:AuditRetentionDays = [int]$desiredAuditRetentionDays
		if ($Script:Ctx -and $Script:Ctx.ContainsKey('UI'))
		{
			$Script:Ctx.UI.AuditRetentionDays = [int]$desiredAuditRetentionDays
		}
		$Script:PinnedBaselineVersion = $desiredPinnedBaselineVersion
		if ($Script:Ctx -and $Script:Ctx.ContainsKey('UI'))
		{
			$Script:Ctx.UI.PinnedBaselineVersion = $desiredPinnedBaselineVersion
		}
		$Script:AppsPackageSourcePreference = $desiredAppsPackageSourcePreference
		$Script:AppsSourceFilter = $desiredAppsSourceFilter
		Initialize-AppsQueuedActionState
		$Script:AppsQueuedActions.Clear()
		foreach ($queuedAction in @($desiredAppsQueuedActions))
		{
			if (-not $queuedAction) { continue }
			$appId = if ((Test-GuiObjectField -Object $queuedAction -FieldName 'AppId')) { [string]$queuedAction.AppId } else { $null }
			$action = if ((Test-GuiObjectField -Object $queuedAction -FieldName 'Action')) { [string]$queuedAction.Action } else { $null }
			if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($action)) { continue }
			switch ($action)
			{
				'Install' { $Script:AppsQueuedActions[$appId] = 'Install' }
				'Uninstall' { $Script:AppsQueuedActions[$appId] = 'Uninstall' }
			}
		}
		Sync-AppsQueuedActionControls
		if ($TxtSearch)
		{
			$desiredSearchText = if ($desiredNavigationMode -eq 'Apps') { $desiredAppsSearch } else { $desiredSearch }
			if ($TxtSearch.Text -ne $desiredSearchText)
			{
				$Script:SearchUiUpdating = $true
				try
				{
					$TxtSearch.Text = $desiredSearchText
				}
				finally
				{
					$Script:SearchUiUpdating = $false
				}
			}
			if (Get-Command -Name 'Sync-GuiSearchInputChrome' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Sync-GuiSearchInputChrome
			}
		}

		Update-SearchResultsTabState

		$Script:FilterUiUpdating = $true
		# P5 rollback checkpoint: Restore-GuiSettingsSnapshot filter/search split to SessionState/Restore-GuiSettingsSnapshot/RestoreFilterAndSearchState.ps1.
		. (Join-Path $PSScriptRoot 'SessionState\Restore-GuiSettingsSnapshot\RestoreFilterAndSearchState.ps1')
		$setGuiFilterPanelExpandedStateScript = Get-GuiFunctionCapture -Name 'Set-GuiFilterPanelExpandedState'
		if ($setGuiFilterPanelExpandedStateScript)
		{
			& $setGuiFilterPanelExpandedStateScript -Scope 'Optimize' -Expanded ([bool]($desiredFilterPanelExpanded -and -not $desiredSafe))
			& $setGuiFilterPanelExpandedStateScript -Scope 'Apps' -Expanded ([bool]$desiredAppsFilterPanelExpanded)
		}

		Update-CategoryFilterList -PrimaryTab $(if ($desiredSearch) { $Script:SearchResultsTabTag } else { $desiredTab })
		Update-SearchResultsTabState
		if (Get-Command -Name 'Update-AppPackageSourcePreferenceControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppPackageSourcePreferenceControls
		}
		if (Get-Command -Name 'Update-AppSourceFilterControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppSourceFilterControls
		}
		if (Get-Command -Name 'Update-AppsViewModeControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppsViewModeControls
		}

		# P5 rollback checkpoint: Restore-GuiSettingsSnapshot navigation split to SessionState/Restore-GuiSettingsSnapshot/RestoreNavigationMode.ps1.
		. (Join-Path $PSScriptRoot 'SessionState\Restore-GuiSettingsSnapshot\RestoreNavigationMode.ps1')
		if ($setGuiFilterPanelExpandedStateScript)
		{
			if ($desiredNavigationMode -ne 'Apps' -and $desiredNavigationMode -ne 'DeploymentMedia')
			{
				& $setGuiFilterPanelExpandedStateScript -Scope 'Optimize' -Expanded ([bool]($desiredFilterPanelExpanded -and -not $desiredSafe))
			}
			& $setGuiFilterPanelExpandedStateScript -Scope 'Apps' -Expanded ([bool]$desiredAppsFilterPanelExpanded)
		}

		if (Get-Command -Name 'Set-DesignModeState' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Set-DesignModeState -Enabled $desiredDesignMode
		}

		# Invalidate tab content cache so the preset panel rebuilds with the
		# restored Safe Mode / Advanced Mode state instead of reusing stale
		# cached content that was built with the default mode values.
		$Script:FilterGeneration++
		if ($Script:ClearTabContentCacheScript) { & $Script:ClearTabContentCacheScript }

		$refreshCurrentTabContentScript = ${function:Update-CurrentTabContent}
		$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Start-GuiPerfScope'
		$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Stop-GuiPerfScope'
		$__perf = if ($startGuiPerfScopeScript) { & $startGuiPerfScopeScript -Name 'RestoreGuiSessionState.TabHydrate' } else { $null }
		try
		{
			& $refreshCurrentTabContentScript -SkipIdlePrebuild
		}
		finally
		{
			if ($stopGuiPerfScopeScript) { & $stopGuiPerfScopeScript -Scope $__perf }
		}
		Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiLogSessionRestoredPreviousState' -Fallback 'Session restored') -Tone 'accent'
		$Script:StartupRestoreSessionPending = $false
		Update-HeaderModeStateText
		if ($TxtLanguageState -and -not [string]::IsNullOrWhiteSpace([string]$Script:SelectedLanguage))
		{
			$TxtLanguageState.Text = ([string]$Script:SelectedLanguage).ToUpperInvariant()
		}
		if (Get-Command -Name 'Update-GuiLocalizationStrings' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-GuiLocalizationStrings
		}
		if (Get-Command -Name 'Update-PrimaryTabHeaders' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-PrimaryTabHeaders
		}
		if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-UxActionButtonText
		}
		if (Get-Command -Name 'Sync-ActivePresetButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-ActivePresetButtonChrome
		}
		Update-RunPathContextLabel
		Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
	}

	<#
	    .SYNOPSIS
	#>

	function Restore-GuiSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if (-not $Script:UiSnapshotUndo)
		{
			return $false
		}

		$redoSnapshot = Get-GuiSettingsSnapshot
		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $Script:UiSnapshotUndo
		}
		catch
		{
			try
			{
				Restore-GuiSettingsSnapshot -Snapshot $redoSnapshot
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Restore-GuiSnapshot.RestoreRedoSnapshot' }
			throw "Failed to restore the previous GUI snapshot: $($_.Exception.Message)"
		}

		$Script:UiSnapshotUndo = $redoSnapshot
		Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
		return $true
	}

	<#
	    .SYNOPSIS
	#>

	function Get-BaselineGuiSettingsProfileDirectory
	{
		param ()
		return (GUICommon\Get-GuiSettingsProfileDirectory -AppName 'Baseline')
	}

	function Get-BaselineGuiSessionStatePath
	{
		param ()
		return (GUICommon\Get-GuiSessionStatePath -AppName 'Baseline')
	}

	function Get-GuiFirstRunWelcomeMarkerPath
	{
		param ()
		return (Join-Path (Get-BaselineGuiSettingsProfileDirectory) 'Baseline-first-run-welcome.txt')
	}

	<#
	    .SYNOPSIS
	#>

	function Test-GuiFirstRunWelcomePending
	{
		param ()
		return (-not (Test-Path -LiteralPath (Get-GuiFirstRunWelcomeMarkerPath)))
	}

	function Complete-GuiFirstRunWelcome
	{
		param ()

		$markerPath = Get-GuiFirstRunWelcomeMarkerPath
		$markerDirectory = Split-Path -Parent $markerPath
		try
		{
			if (-not (Test-Path -LiteralPath $markerDirectory))
			{
				[void](New-Item -ItemType Directory -Path $markerDirectory -Force -ErrorAction Stop)
			}

			(Get-Date).ToString('o') | Set-Content -LiteralPath $markerPath -Encoding UTF8 -Force
			return $true
		}
		catch
		{
			LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogSessionPersistWelcomeStateFailed' -Fallback 'Failed to persist first-run welcome state'))
			return $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Import-GuiLastRunProfile
	{
		param ()

		$path = GUICommon\Get-GuiLastRunFilePath
		if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue))
		{
			return $null
		}

		try
		{
			return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16)
		}
		catch
		{
			LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogSessionLoadLastRunFailed' -Fallback 'Failed to load last run profile'))
			return $null
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Import-GuiInterruptedRunProfile
	{
		param ()

		$path = GUICommon\Get-GuiInterruptedRunFilePath
		if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue))
		{
			return $null
		}

		try
		{
			return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16)
		}
		catch
		{
			LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogSessionLoadInterruptedRunFailed' -Fallback 'Failed to load interrupted run profile'))
			return $null
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Clear-GuiLastRunProfile
	{
		param ()

		$path = GUICommon\Get-GuiLastRunFilePath
		if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)
		{
			try
			{
				Remove-Item -LiteralPath $path -Force -ErrorAction Stop
			}
			catch
			{
				LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogSessionRemoveLastRunFailed' -Fallback 'Failed to remove last run profile'))
			}
		}
		$Script:LastRunProfile = $null
	}

	<#
	    .SYNOPSIS
	#>

	function Clear-GuiInterruptedRunProfile
	{
		param ()

		$path = GUICommon\Get-GuiInterruptedRunFilePath
		if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)
		{
			try
			{
				Remove-Item -LiteralPath $path -Force -ErrorAction Stop
			}
			catch
			{
				LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogSessionRemoveInterruptedRunFailed' -Fallback 'Failed to remove interrupted run profile'))
			}
		}
		$Script:InterruptedRunProfile = $null
	}

	<#
	    .SYNOPSIS
	#>

	function Save-GuiInterruptedRunProfile
	{
		param (
			[Parameter(Mandatory = $true)]
			[object[]]$ResumeCandidates,

			[string]$Mode = 'Run',
			[string]$Reason = 'Interrupted'
		)

		$candidates = @($ResumeCandidates | Where-Object { $_ })
		if ($candidates.Count -eq 0)
		{
			return $false
		}

		$payload = [ordered]@{
			Schema = 'Baseline.InterruptedRun'
			SchemaVersion = 1
			Timestamp = (Get-Date).ToString('o')
			Mode = [string]$Mode
			Reason = [string]$Reason
			ResumeCandidates = @($candidates)
		}

		$path = GUICommon\Get-GuiInterruptedRunFilePath
		try
		{
			($payload | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $path -Encoding UTF8 -Force
			$Script:InterruptedRunProfile = [pscustomobject]$payload
			return $true
		}
		catch
		{
			LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogSessionSaveInterruptedRunFailed' -Fallback 'Failed to save interrupted run profile'))
			return $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Save-GuiSessionState
	{
		param ()
		return (GUICommon\Save-GuiSessionStateDocument -Snapshot (Get-GuiSettingsSnapshot) -AppName 'Baseline')
	}

	function Restore-GuiSessionState
	{
		param (
			[object]
			$Snapshot = $null,

			[switch]
			$PreserveDurablePreferences
		)

		$snapshot = $Snapshot
		if (-not $snapshot)
		{
			$snapshot = GUICommon\Read-GuiSessionStateDocument -AppName 'Baseline' -ExpectedSchema 'Baseline.GuiSettings'
		}
		if (-not $snapshot)
		{
			return $false
		}

		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $snapshot -PreserveDurablePreferences:$PreserveDurablePreferences
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogSessionRestoredPreviousState' -Fallback 'Restored previous GUI session state.')
			return $true
		}
		catch
		{
			LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogRestoreSessionFailed' -Fallback 'Failed to restore GUI session state'))
			return $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Export-GuiSettingsProfile
	{
		param ()

		$snapshot = Get-GuiSettingsSnapshot
		$savePath = GUICommon\Show-GuiSettingsSaveDialog -AppName 'Baseline'
		if ([string]::IsNullOrWhiteSpace($savePath))
		{
			return $false
		}

		try
		{
			[void](GUICommon\Write-GuiSettingsProfileDocument -Snapshot $snapshot -FilePath $savePath)
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExportGuiSettings' -Fallback 'Exported GUI settings to {0}' -FormatArgs @($savePath))
			Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiLogExportGuiSettings' -Fallback '' -FormatArgs @($savePath)) -Tone 'accent'
			return $true
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export GUI settings')
			[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiExportSettings' -Fallback '') -Message (Get-UxLocalizedString -Key 'GuiLogExportGuiSettingsFailed' -Fallback '' -FormatArgs @($_.Exception.Message)) -Buttons @('OK') -AccentButton 'OK')
			return $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Import-GuiSettingsProfile
	{
		param ()

		$importTitle = (Get-UxLocalizedString -Key 'GuiImportSettings' -Fallback 'Import Settings')
		$importChoice = Show-GuiSettingsImportDialog -AppName 'Baseline'
		if ([string]::IsNullOrWhiteSpace($importChoice))
		{
			return $false
		}

		$profilePath = $null
		$sourceLabel = $null
		$sourceDescription = $null
		$useSessionStateReader = $false

		switch ($importChoice)
		{
			'Own'
			{
				$sourceLabel = (Get-UxLocalizedString -Key 'GuiImportSettingsOwnTitle' -Fallback 'Saved profile')
				$sourceDescription = (Get-UxLocalizedString -Key 'GuiImportSettingsOwnDetail' -Fallback ("Open a Baseline settings profile from the {0} settings folder." -f 'Baseline'))
				$profilePath = GUICommon\Show-GuiFileOpenDialog -Title $importTitle -Filter 'Baseline Settings (*.json)|*.json|All Files (*.*)|*.*' -InitialDirectory (Get-BaselineGuiSettingsProfileDirectory)
			}
			'Recommended'
			{
				$sourceLabel = (Get-UxLocalizedString -Key 'GuiImportSettingsRecommendedTitle' -Fallback 'Last run')
				$sourceDescription = (Get-UxLocalizedString -Key 'GuiImportSettingsRecommendedDetail' -Fallback 'Load the profile saved after Baseline finished its last run.')
				$profilePath = GUICommon\Get-GuiLastRunFilePath
			}
			'Backup'
			{
				$sourceLabel = (Get-UxLocalizedString -Key 'GuiImportSettingsBackupTitle' -Fallback 'Session backup')
				$sourceDescription = (Get-UxLocalizedString -Key 'GuiImportSettingsBackupDetail' -Fallback 'Load the current session-state backup used for undo and restore.')
				$profilePath = Get-BaselineGuiSessionStatePath
				$useSessionStateReader = $true
			}
			'Custom'
			{
				$sourceLabel = (Get-UxLocalizedString -Key 'GuiImportSettingsCustomTitle' -Fallback 'Custom file')
				$sourceDescription = (Get-UxLocalizedString -Key 'GuiImportSettingsCustomDetail' -Fallback 'Browse to any compatible Baseline settings JSON file.')
				$profilePath = GUICommon\Show-GuiFileOpenDialog -Title $importTitle -Filter 'Baseline Settings (*.json)|*.json|All Files (*.*)|*.*'
			}
			default
			{
				return $false
			}
		}

		if ([string]::IsNullOrWhiteSpace($profilePath))
		{
			return $false
		}

		if (-not (Test-Path -LiteralPath $profilePath -ErrorAction SilentlyContinue))
		{
			$missingMessage = switch ($importChoice)
			{
				'Recommended' { Get-UxLocalizedString -Key 'GuiImportSettingsNoLastRun' -Fallback '' }
				'Backup' { Get-UxLocalizedString -Key 'GuiImportSettingsNoSessionBackup' -Fallback '' }
				default { Get-UxLocalizedString -Key 'GuiImportSettingsFileNotFound' -Fallback '' }
			}
			LogWarning (Get-UxBilingualLocalizedString -Key 'GuiLogImportGuiSettingsReadFailed' -Fallback 'Failed to read GUI settings profile: {0}' -FormatArgs @($missingMessage))
			[void](Show-ThemedDialog -Title $importTitle -Message $missingMessage -Buttons @('OK') -AccentButton 'OK')
			return $false
		}

		Show-BaselineImportOverlay -Title $importTitle -Description $sourceDescription -StatusText (Get-UxLocalizedString -Key 'GuiImportSettingsPreparing' -Fallback 'Preparing import...')
		if ($Script:MainForm -and $Script:MainForm.Dispatcher)
		{
			Invoke-GuiDispatcherAction -Dispatcher $Script:MainForm.Dispatcher -Action { } -PriorityUsage 'RenderRefresh' -Synchronous
		}

		try
		{
			if ($useSessionStateReader)
			{
				$snapshot = GUICommon\Read-GuiSessionStateDocument -AppName 'Baseline' -ExpectedSchema 'Baseline.GuiSettings'
			if (-not $snapshot)
			{
				throw 'The selected session backup did not contain a valid Baseline settings snapshot.'
			}
			}
			else
			{
				$snapshot = GUICommon\Read-GuiSettingsProfileDocument -FilePath $profilePath -ExpectedSchema 'Baseline.GuiSettings'
			}
		}
		catch
		{
			Hide-BaselineUpdateOverlay
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to read GUI settings profile')
			[void](Show-ThemedDialog -Title $importTitle -Message (Get-UxLocalizedString -Key 'GuiLogImportGuiSettingsReadFailed' -Fallback '' -FormatArgs @($_.Exception.Message)) -Buttons @('OK') -AccentButton 'OK')
			return $false
		}

		Save-GuiUndoSnapshot
		try
		{
			Show-BaselineImportOverlay -Title $importTitle -Description $sourceDescription -StatusText (Get-UxLocalizedString -Key 'GuiImportSettingsApplying' -Fallback 'Applying settings...')
			if ($Script:MainForm -and $Script:MainForm.Dispatcher)
			{
				Invoke-GuiDispatcherAction -Dispatcher $Script:MainForm.Dispatcher -Action { } -PriorityUsage 'RenderRefresh' -Synchronous
			}

			Restore-GuiSettingsSnapshot -Snapshot $snapshot
			Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiLogImportGuiSettings' -Fallback '' -FormatArgs @($sourceLabel)) -Tone 'accent'
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogImportGuiSettings' -Fallback 'Imported GUI settings from {0}' -FormatArgs @($profilePath))
			Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
			return $true
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to import GUI settings')
			if ($Script:UiSnapshotUndo)
			{
				try
				{
					Restore-GuiSettingsSnapshot -Snapshot $Script:UiSnapshotUndo
				}
				catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.Import-GuiSettingsProfile.RestoreUndoSnapshot' }
			}
			$Script:UiSnapshotUndo = $null
			Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
			Hide-BaselineUpdateOverlay
			[void](Show-ThemedDialog -Title $importTitle -Message (Get-UxLocalizedString -Key 'GuiLogImportGuiSettingsFailed' -Fallback '' -FormatArgs @($_.Exception.Message)) -Buttons @('OK') -AccentButton 'OK')
			return $false
		}
		finally
		{
			Hide-BaselineUpdateOverlay
		}
	}
