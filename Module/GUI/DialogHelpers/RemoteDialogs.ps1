

	<#
	    .SYNOPSIS
	#>

	function Show-GuiRemoteConsoleDialog
	{
		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-RemoteConsole'
		$windowTitle = Get-UxLocalizedString -Key 'GuiRemoteConsole' -Fallback 'Remote Console'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiRemoteConsoleSubtitle' -Fallback 'Monitor and control the current remote orchestration context.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$refreshLabel = Get-UxLocalizedString -Key 'GuiRefreshButton' -Fallback 'Refresh'
		$preflightLabel = Get-UxLocalizedString -Key 'GuiPlanPreflightChecks' -Fallback 'Preflight'
		$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme $theme

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="920" Height="640"
	MinWidth="760" MinHeight="560"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
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
					<TextBlock Name="TxtDialogTitle" Text="$windowTitle" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtDialogSubtitle" Text="$windowSubtitle"
							   FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Padding="20,18,20,18">
				<Grid>
					<Grid.RowDefinitions>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
					</Grid.RowDefinitions>
					<TextBlock Name="TxtConnectedTargets" Grid.Row="0" Text="" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtApprovedTargets" Grid.Row="1" Text="" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="$($theme.TextSecondary)"/>
					<TextBlock Name="TxtConnectedAt" Grid.Row="2" Text="" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="$($theme.TextSecondary)"/>
					<TextBlock Name="TxtApprovalMessage" Grid.Row="3" Text="" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="$($theme.TextSecondary)"/>
					<TextBlock Name="TxtCachedSessions" Grid.Row="4" Text="" Margin="0,0,0,8" TextWrapping="Wrap" Foreground="$($theme.TextSecondary)"/>
					<Border Grid.Row="5" Background="$($theme.InputBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="6" Padding="12,10,12,10" Margin="0,0,0,8">
						<StackPanel>
							<Grid Margin="0,0,0,8">
								<Grid.ColumnDefinitions>
									<ColumnDefinition Width="*"/>
									<ColumnDefinition Width="Auto"/>
								</Grid.ColumnDefinitions>
								<TextBlock Grid.Column="0" Text="Recent remote runs" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)" VerticalAlignment="Center"/>
								<TextBox Name="TxtFilterRuns" Grid.Column="1" Width="200" Padding="4" VerticalAlignment="Center"/>
							</Grid>
							<ListView Name="LstRecentRemoteRuns" BorderThickness="0" Background="Transparent" Height="180">
								<ListView.View>
									<GridView>
										<GridViewColumn Header="Date" Width="155" DisplayMemberBinding="{Binding Timestamp, StringFormat='yyyy-MM-dd HH:mm:ss'}"/>
										<GridViewColumn Header="Operation" Width="120" DisplayMemberBinding="{Binding Operation}"/>
										<GridViewColumn Header="State" Width="90" DisplayMemberBinding="{Binding TerminalState}"/>
										<GridViewColumn Header="Targets" Width="70" DisplayMemberBinding="{Binding TargetCount}"/>
										<GridViewColumn Header="Counts" Width="240" DisplayMemberBinding="{Binding CountsSummary}"/>
										<GridViewColumn Header="Summary" Width="420" DisplayMemberBinding="{Binding Summary}"/>
									</GridView>
								</ListView.View>
							</ListView>
						</StackPanel>
					</Border>
					<TextBlock Name="TxtConsoleHint" Grid.Row="6" Text="" Margin="0,6,0,0" TextWrapping="Wrap" Foreground="$($theme.TextMuted)"/>
				</Grid>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<WrapPanel HorizontalAlignment="Right">
					<Button Name="BtnConnect" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnDisconnect" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnApprove" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnSavePolicy" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnLoadPolicy" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnPreflight" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnRefresh" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnClose" Content="" Padding="16,6" FontSize="13"/>
				</WrapPanel>
			</Border>
		</Grid>
	</Border>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form

		$rootBorder = $dlg.FindName('RootBorder')
		if ($rootBorder)
		{
			$rootBorder.Background = $bc.ConvertFromString($theme.WindowBg)
			$rootBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		}

		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		$btnConnect = $dlg.FindName('BtnConnect')
		$btnDisconnect = $dlg.FindName('BtnDisconnect')
		$btnApprove = $dlg.FindName('BtnApprove')
		$btnSavePolicy = $dlg.FindName('BtnSavePolicy')
		$btnLoadPolicy = $dlg.FindName('BtnLoadPolicy')
		$btnPreflight = $dlg.FindName('BtnPreflight')
		$btnRefresh = $dlg.FindName('BtnRefresh')
		$btnClose = $dlg.FindName('BtnClose')
		$txtConnectedTargets = $dlg.FindName('TxtConnectedTargets')
		$txtApprovedTargets = $dlg.FindName('TxtApprovedTargets')
		$txtConnectedAt = $dlg.FindName('TxtConnectedAt')
		$txtApprovalMessage = $dlg.FindName('TxtApprovalMessage')
		$txtCachedSessions = $dlg.FindName('TxtCachedSessions')
		$lstRecentRemoteRuns = $dlg.FindName('LstRecentRemoteRuns')
		$txtConsoleHint = $dlg.FindName('TxtConsoleHint')
		$txtFilterRuns = $dlg.FindName('TxtFilterRuns')

		$promptRemoteTargetConnectionCommand = Get-GuiRuntimeCommand -Name 'Prompt-GuiRemoteTargetConnection' -CommandType 'Function'
		$setRemoteTargetContextCommand = Get-GuiRuntimeCommand -Name 'Set-GuiRemoteTargetContext' -CommandType 'Function'
		$getRemoteTargetContextCommand = Get-GuiRuntimeCommand -Name 'Get-GuiRemoteTargetContext' -CommandType 'Function'
		$clearRemoteTargetContextCommand = Get-GuiRuntimeCommand -Name 'Clear-GuiRemoteTargetContext' -CommandType 'Function'
		$setRemoteTargetApprovalCommand = Get-GuiRuntimeCommand -Name 'Set-GuiRemoteTargetApprovalList' -CommandType 'Function'
		$testRemoteTargetApprovalCommand = Get-GuiRuntimeCommand -Name 'Test-GuiRemoteTargetApproval' -CommandType 'Function'
		$exportRemoteTargetApprovalPolicyCommand = Get-GuiRuntimeCommand -Name 'Export-GuiRemoteTargetApprovalPolicy' -CommandType 'Function'
		$importRemoteTargetApprovalPolicyCommand = Get-GuiRuntimeCommand -Name 'Import-GuiRemoteTargetApprovalPolicy' -CommandType 'Function'
		$getRemoteSessionSummaryCommand = Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteSessionSummary' -CommandType 'Function'
		$getRemoteRunSummariesCommand = Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteRunSummaries' -CommandType 'Function'
		$getRemoteOrchestrationDetailsCommand = Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteOrchestrationDetails' -CommandType 'Function'
		$getRemoteOrchestrationSummaryCommand = Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteOrchestrationSummary' -CommandType 'Function'
		$exportSupportBundleCommand = Get-GuiRuntimeCommand -Name 'Export-BaselineSupportBundle' -CommandType 'Function'
		$showGuiFileSaveDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFileSaveDialog' -CommandType 'Function'
		$getGuiSettingsSnapshotCommand = Get-GuiRuntimeCommand -Name 'Get-GuiSettingsSnapshot' -CommandType 'Function'
		$testRemoteConnectivityCommand = Get-GuiRuntimeCommand -Name 'Test-BaselineRemoteConnectivity' -CommandType 'Function'
		$testInteractiveHostCapture = Get-GuiFunctionCapture -Name 'Test-InteractiveHost'
		$showRemoteConsoleError = {
			param(
				[string]$Title,
				[string]$Message
			)

			$canShowDialog = $false
			try
			{
				if ($testInteractiveHostCapture)
				{
					$canShowDialog = [bool](& $testInteractiveHostCapture)
				}
			}
			catch
			{
				$canShowDialog = $false
				Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiRemoteConsoleDialog.ResolveErrorDialog'
			}

			if ($canShowDialog)
			{
				[void](Show-ThemedDialog -Title $Title -Message $Message -Buttons @('OK') -AccentButton 'OK')
				return
			}

			LogWarn ($Title + ': ' + $Message)
		}.GetNewClosure()

		if ($txtFilterRuns -and (Get-Command -Name 'Set-GuiWatermarkText' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-GuiWatermarkText -TextBox $txtFilterRuns -Text 'Filter runs...'
		}

		$remoteRunsCtx = New-Object System.Windows.Controls.ContextMenu
		$ctxOpenLog = New-Object System.Windows.Controls.MenuItem
		$ctxOpenLog.Header = 'Open Log...'
		$ctxExportBundle = New-Object System.Windows.Controls.MenuItem
		$ctxExportBundle.Header = 'Export Support Bundle...'
		$ctxIncidentPack = New-Object System.Windows.Controls.MenuItem
		$ctxIncidentPack.Header = 'Generate Incident Repro Pack...'
		$ctxExportDeepLinkedBundle = New-Object System.Windows.Controls.MenuItem
		$ctxExportDeepLinkedBundle.Header = 'Export Deep-Linked Support Bundle...'
		$ctxRetryFailed = New-Object System.Windows.Controls.MenuItem
		$ctxRetryFailed.Header = 'Retry Failed Targets'
		$ctxExportFailed = New-Object System.Windows.Controls.MenuItem
		$ctxExportFailed.Header = 'Export Failed Target List...'

		[void]$remoteRunsCtx.Items.Add($ctxOpenLog)
		[void]$remoteRunsCtx.Items.Add($ctxExportBundle)
		[void]$remoteRunsCtx.Items.Add($ctxIncidentPack)
		[void]$remoteRunsCtx.Items.Add($ctxExportDeepLinkedBundle)
		[void]$remoteRunsCtx.Items.Add((New-Object System.Windows.Controls.Separator))
		[void]$remoteRunsCtx.Items.Add($ctxRetryFailed)
		[void]$remoteRunsCtx.Items.Add($ctxExportFailed)
		if ($lstRecentRemoteRuns) { $lstRecentRemoteRuns.ContextMenu = $remoteRunsCtx }

		$remoteRunsCtx.Add_Opened({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if (-not $selected)
			{
				$ctxOpenLog.IsEnabled = $false
				$ctxExportBundle.IsEnabled = $false
				$ctxIncidentPack.IsEnabled = $false
				$ctxRetryFailed.IsEnabled = $false
				$ctxExportFailed.IsEnabled = $false
			}
			else
			{
				$hasLog = (Test-GuiObjectField -Object $selected -FieldName 'LogPath') -and -not [string]::IsNullOrWhiteSpace($selected.LogPath)
				$hasBundle = (Test-GuiObjectField -Object $selected -FieldName 'BundlePath') -and -not [string]::IsNullOrWhiteSpace($selected.BundlePath)
				$hasFailed = (Test-GuiObjectField -Object $selected -FieldName 'FailedCount') -and $selected.FailedCount -gt 0
				$canDeepLink = (Test-GuiObjectField -Object $selected -FieldName 'RunId') -and -not [string]::IsNullOrWhiteSpace([string]$selected.RunId) -and $hasFailed

				$ctxOpenLog.IsEnabled = $hasLog
				$ctxExportBundle.IsEnabled = $hasBundle
				$ctxIncidentPack.IsEnabled = ($hasBundle -and [string]$selected.TerminalState -match '(?i)Failed')
				$ctxExportDeepLinkedBundle.IsEnabled = $canDeepLink
				$ctxRetryFailed.IsEnabled = $hasFailed
				$ctxExportFailed.IsEnabled = $hasFailed
			}
		}.GetNewClosure())

		$ctxOpenLog.Add_Click({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if ($selected -and (Test-GuiObjectField -Object $selected -FieldName 'LogPath') -and -not [string]::IsNullOrWhiteSpace($selected.LogPath))
			{
				Show-LogDialog -LogPath $selected.LogPath
			}
		}.GetNewClosure())

		$ctxExportBundle.Add_Click({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if ($selected -and (Test-GuiObjectField -Object $selected -FieldName 'BundlePath') -and -not [string]::IsNullOrWhiteSpace($selected.BundlePath))
			{
				try { [System.Diagnostics.Process]::Start('explorer.exe', "/select,`"$($selected.BundlePath)`"") } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RemoteDialogs.Show-GuiRemoteConsoleDialog:catch277' -Severity Debug }
				 & $showRemoteConsoleError -Title 'Remote Console' -Message "Failed to show bundle: $($_.Exception.Message)" }
			}
		}.GetNewClosure())

		. (Join-Path $PSScriptRoot 'RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1')

		if ($dlgTitleBar) { $dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure()) }
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
		if ($btnClose)
		{
			$btnClose.Content = $closeLabel
			Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
			$btnClose.IsDefault = $true
			$btnClose.IsCancel = $true
			$btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())
		}
		if ($btnRefresh)
		{
			$btnRefresh.Content = $refreshLabel
			Set-ButtonChrome -Button $btnRefresh -Variant 'Secondary' -Compact
			$btnRefresh.Add_Click({
				& $refreshConsole
			}.GetNewClosure())
		}
		. (Join-Path $PSScriptRoot 'RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1')

		$dlg.Add_ContentRendered({
			& $refreshConsole
		})
		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape)
			{
				$dlg.Close()
			}
		})

		[void]($dlg.ShowDialog())
		return $null
	}

