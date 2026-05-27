

	<#
	    .SYNOPSIS
	#>

	function Show-GuiAuditSettingsDialog
	{
		param (
			[int]$InitialRetentionDays = 90
		)

		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-AuditSettings'
		$windowTitle = Get-UxLocalizedString -Key 'GuiAuditSettings' -Fallback 'Audit Settings'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiAuditSettingsSubtitle' -Fallback 'Choose the retention window used by audit exports, cleanup, and support bundles.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$saveLabel = Get-UxLocalizedString -Key 'GuiSaveButton' -Fallback 'Save'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="640" Height="360"
	MinWidth="560" MinHeight="320"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
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

			<Grid Grid.Row="2" Margin="20,18,20,18">
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="*"/>
				</Grid.RowDefinitions>

				<TextBlock Name="TxtRetentionLabel" Grid.Row="0" Text="" Margin="0,0,0,8" FontSize="13" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
				<ComboBox Name="CmbAuditRetention" Grid.Row="1" Height="32" HorizontalAlignment="Left" MinWidth="220"/>
				<TextBlock Name="TxtRetentionHelp" Grid.Row="2" Text="" Margin="0,12,0,0" TextWrapping="Wrap" Foreground="$($theme.TextSecondary)"/>
			</Grid>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<Button Name="BtnCancel" Content="" HorizontalAlignment="Right" Padding="20,6" FontSize="13" Margin="0,0,8,0"/>
					<Button Name="BtnSave" Content="" HorizontalAlignment="Right" Padding="20,6" FontSize="13"/>
				</Grid>
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
		$btnCancel = $dlg.FindName('BtnCancel')
		$btnSave = $dlg.FindName('BtnSave')
		$cmbAuditRetention = $dlg.FindName('CmbAuditRetention')
		$txtRetentionLabel = $dlg.FindName('TxtRetentionLabel')
		$txtRetentionHelp = $dlg.FindName('TxtRetentionHelp')
		$resultRef = @{ Value = $null }
		$selectedRetentionRef = @{ Value = [int]$InitialRetentionDays }

		if ($txtRetentionLabel)
		{
			$txtRetentionLabel.Text = (Get-UxLocalizedString -Key 'GuiAuditSettingsRetentionLabel' -Fallback 'Retention window')
		}
		if ($txtRetentionHelp)
		{
			$txtRetentionHelp.Text = (Get-UxLocalizedString -Key 'GuiAuditSettingsRetentionHelp' -Fallback 'This window is used for audit exports, log cleanup, support bundles, and other retention-aware actions.')
		}

		$items = @(
			[pscustomobject]@{ Days = 30;  Label = '30 days' }
			[pscustomobject]@{ Days = 90;  Label = '90 days' }
			[pscustomobject]@{ Days = 180; Label = '180 days' }
			[pscustomobject]@{ Days = 365; Label = '365 days' }
		)

		if ($cmbAuditRetention)
		{
			foreach ($item in $items)
			{
				$comboItem = New-Object System.Windows.Controls.ComboBoxItem
				$comboItem.Content = $item.Label
				$comboItem.Tag = $item.Days
				[void]$cmbAuditRetention.Items.Add($comboItem)
			}

			$selectedIndex = 1
			for ($i = 0; $i -lt $cmbAuditRetention.Items.Count; $i++)
			{
				$item = $cmbAuditRetention.Items[$i]
				if ([int]$item.Tag -eq $selectedRetentionRef.Value)
				{
					$selectedIndex = $i
					break
				}
			}
			$cmbAuditRetention.SelectedIndex = $selectedIndex
			$selectedRetentionRef.Value = [int]$cmbAuditRetention.SelectedItem.Tag

			$cmbAuditRetention.Add_SelectionChanged({
				$selected = $cmbAuditRetention.SelectedItem
				if ($selected -and $selected.Tag -ne $null)
				{
					$selectedRetentionRef.Value = [int]$selected.Tag
				}
			}.GetNewClosure())
		}

		if ($dlgTitleBar)
		{
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
		if ($btnCancel)
		{
			$btnCancel.Content = $closeLabel
			Set-ButtonChrome -Button $btnCancel -Variant 'Secondary' -Compact
			$btnCancel.IsCancel = $true
			$btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
		}
		if ($btnSave)
		{
			$btnSave.Content = $saveLabel
			Set-ButtonChrome -Button $btnSave -Variant 'Primary' -Compact
			$btnSave.IsDefault = $true
			$btnSave.Add_Click({
				$resultRef.Value = [int]$selectedRetentionRef.Value
				$dlg.Close()
			}.GetNewClosure())
		}

		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape)
			{
				$dlg.Close()
			}
		})

		[void]($dlg.ShowDialog())
		return $resultRef.Value
	}

	<#
	    .SYNOPSIS

	    .DESCRIPTION
	    Operator-facing safeguards console: per-run cap, concurrency, change
	    window, kill switch, allow/deny lists, and the live policy decision for
	    the currently connected target list. Backed by the OperatorPolicy helpers
	    in Module\SharedHelpers\OperatorPolicy.Helpers.ps1.
	#>

	function Show-GuiOperatorConsoleDialog
	{
		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-OperatorConsole'
		$windowTitle = Get-UxLocalizedString -Key 'GuiOperatorConsoleTitle' -Fallback 'Operator Console'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiOperatorConsoleSubtitle' -Fallback 'Multi-target safeguards: caps, change window, kill switch, allow/deny lists.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$refreshLabel = Get-UxLocalizedString -Key 'GuiRefreshButton' -Fallback 'Refresh'
		$saveLabel = Get-UxLocalizedString -Key 'GuiOperatorPolicySave' -Fallback 'Save Policy...'
		$loadLabel = Get-UxLocalizedString -Key 'GuiOperatorPolicyLoad' -Fallback 'Load Policy...'
		$evaluateLabel = Get-UxLocalizedString -Key 'GuiOperatorPolicyEvaluate' -Fallback 'Evaluate'
		$killEngageLabel = Get-UxLocalizedString -Key 'GuiOperatorKillEngage' -Fallback 'Engage Kill Switch'
		$killClearLabel = Get-UxLocalizedString -Key 'GuiOperatorKillClear' -Fallback 'Clear Kill Switch'

		. (Join-Path $PSScriptRoot 'AuditOperatorDialogs\Show-GuiOperatorConsoleDialog\Show-GuiOperatorConsoleDialog.ps1')

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

		$dlgTitleBar       = $dlg.FindName('DlgTitleBar')
		$btnDlgClose       = $dlg.FindName('BtnDlgClose')
		$txtMaxTargets     = $dlg.FindName('TxtMaxTargets')
		$txtMaxConcurrent  = $dlg.FindName('TxtMaxConcurrent')
		$txtChangeDays     = $dlg.FindName('TxtChangeDays')
		$txtChangeStart    = $dlg.FindName('TxtChangeStart')
		$txtChangeEnd      = $dlg.FindName('TxtChangeEnd')
		$txtChangeState    = $dlg.FindName('TxtChangeWindowState')
		$txtAllowed        = $dlg.FindName('TxtAllowedTargets')
		$txtDenied         = $dlg.FindName('TxtDeniedTargets')
		$txtDeniedFns      = $dlg.FindName('TxtDeniedFunctions')
		$txtKillPath       = $dlg.FindName('TxtKillSwitchPath')
		$txtKillState      = $dlg.FindName('TxtKillSwitchState')
		$txtDecisionTgts   = $dlg.FindName('TxtDecisionTargets')
		$txtDecisionSummary= $dlg.FindName('TxtDecisionSummary')
		$btnKillEngage     = $dlg.FindName('BtnKillEngage')
		$btnKillClear      = $dlg.FindName('BtnKillClear')
		$btnEvaluate       = $dlg.FindName('BtnEvaluate')
		$btnSavePolicy     = $dlg.FindName('BtnSavePolicy')
		$btnLoadPolicy     = $dlg.FindName('BtnLoadPolicy')
		$btnRefresh        = $dlg.FindName('BtnRefresh')
		$btnClose          = $dlg.FindName('BtnClose')

		# Resolve helpers via runtime command lookup so this dialog stays
		# loadable in test harnesses where SharedHelpers may not be imported.
		$newPolicyCmd     = Get-GuiRuntimeCommand -Name 'New-BaselineOperatorPolicy' -CommandType 'Function'
		$testRunCmd       = Get-GuiRuntimeCommand -Name 'Test-BaselineOperatorRunPolicy' -CommandType 'Function'
		$formatDecisionCmd= Get-GuiRuntimeCommand -Name 'Format-BaselineOperatorPolicyDecision' -CommandType 'Function'
		$testKillCmd      = Get-GuiRuntimeCommand -Name 'Test-BaselineKillSwitch' -CommandType 'Function'
		$engageKillCmd    = Get-GuiRuntimeCommand -Name 'Invoke-BaselineKillSwitch' -CommandType 'Function'
		$clearKillCmd     = Get-GuiRuntimeCommand -Name 'Clear-BaselineKillSwitch' -CommandType 'Function'
		$getRemoteCtxCmd  = Get-GuiRuntimeCommand -Name 'Get-GuiRemoteTargetContext' -CommandType 'Function'

		# Per-dialog policy state. We seed from the helper defaults so the
		# operator sees the same caps the CLI honours.
		$policy = $null
		try { $policy = & $newPolicyCmd } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch281' -Severity Debug }
		 $policy = [pscustomobject]@{ MaxTargetsPerRun = 25; MaxConcurrentTargets = 5; DeniedFunctions = @(); DeniedTargets = @(); AllowedTargets = @(); ChangeWindow = @{}; KillSwitchPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'BASELINE_KILL_SWITCH'); CreatedAt = [DateTimeOffset]::UtcNow } }

		$splitLines = {
			param([string]$Text)
			if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
			$arr = [System.Collections.Generic.List[string]]::new()
			foreach ($l in ($Text -split "`r?`n"))
			{
				$t = $l.Trim()
				if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$arr.Add($t) }
			}
			return ,$arr.ToArray()
		}

		$loadPolicyIntoUi = {
			param($p)
			if (-not $p) { return }
			if ($txtMaxTargets) { $txtMaxTargets.Text = [string]$p.MaxTargetsPerRun }
			if ($txtMaxConcurrent) { $txtMaxConcurrent.Text = [string]$p.MaxConcurrentTargets }
			if ($txtAllowed) { $txtAllowed.Text = (@($p.AllowedTargets) -join [Environment]::NewLine) }
			if ($txtDenied) { $txtDenied.Text = (@($p.DeniedTargets) -join [Environment]::NewLine) }
			if ($txtDeniedFns) { $txtDeniedFns.Text = (@($p.DeniedFunctions) -join [Environment]::NewLine) }
			if ($txtKillPath) { $txtKillPath.Text = ('Sentinel: {0}' -f $p.KillSwitchPath) }
			$cw = $p.ChangeWindow
			if ($cw -and $cw.Count -gt 0)
			{
				if ($txtChangeDays) { $txtChangeDays.Text = if ($cw['Days']) { (@($cw['Days']) -join ',') } else { '' } }
				if ($txtChangeStart) { $txtChangeStart.Text = if ($cw['StartTime']) { [string]$cw['StartTime'] } else { '' } }
				if ($txtChangeEnd) { $txtChangeEnd.Text = if ($cw['EndTime']) { [string]$cw['EndTime'] } else { '' } }
			}
		}.GetNewClosure()

		$readPolicyFromUi = {
			$max = 25; $conc = 5
			if ($txtMaxTargets -and -not [string]::IsNullOrWhiteSpace($txtMaxTargets.Text)) { [void][int]::TryParse($txtMaxTargets.Text, [ref]$max) }
			if ($txtMaxConcurrent -and -not [string]::IsNullOrWhiteSpace($txtMaxConcurrent.Text)) { [void][int]::TryParse($txtMaxConcurrent.Text, [ref]$conc) }

			$allowed = if ($txtAllowed) { & $splitLines $txtAllowed.Text } else { @() }
			$denied  = if ($txtDenied) { & $splitLines $txtDenied.Text } else { @() }
			$dfns    = if ($txtDeniedFns) { & $splitLines $txtDeniedFns.Text } else { @() }

			$cw = @{}
			$daysText = if ($txtChangeDays) { $txtChangeDays.Text } else { '' }
			if (-not [string]::IsNullOrWhiteSpace($daysText))
			{
				$days = @(($daysText -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
				if ($days.Count -gt 0) { $cw['Days'] = $days }
			}
			$startText = if ($txtChangeStart) { $txtChangeStart.Text.Trim() } else { '' }
			$endText   = if ($txtChangeEnd) { $txtChangeEnd.Text.Trim() } else { '' }
			if (-not [string]::IsNullOrWhiteSpace($startText) -and -not [string]::IsNullOrWhiteSpace($endText))
			{
				$cw['StartTime'] = $startText
				$cw['EndTime']   = $endText
			}

			return (& $newPolicyCmd -MaxTargetsPerRun $max -MaxConcurrentTargets $conc -DeniedFunctions $dfns -DeniedTargets $denied -AllowedTargets $allowed -ChangeWindow $cw)
		}.GetNewClosure()

		$refreshKillState = {
			if (-not $policy) { return }
			$engaged = $false
			try { $engaged = [bool](& $testKillCmd -Path $policy.KillSwitchPath) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch343' -Severity Debug }
			 $engaged = $false }
			if ($txtKillState) { $txtKillState.Text = if ($engaged) { 'Status: ENGAGED - new runs will be blocked.' } else { 'Status: clear - runs allowed.' } }
			if ($btnKillEngage) { $btnKillEngage.IsEnabled = -not $engaged }
			if ($btnKillClear) { $btnKillClear.IsEnabled = $engaged }
		}.GetNewClosure()

		$evaluateDecision = {
			$policy = & $readPolicyFromUi
			$targets = @()
			try
			{
				$ctx = & $getRemoteCtxCmd
				if ($ctx -and $ctx.Connected -and $ctx.TargetComputers) { $targets = @($ctx.TargetComputers) }
			}
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch357' -Severity Debug }
			 $targets = @() }

			if ($txtDecisionTgts)
			{
				$txtDecisionTgts.Text = if ($targets.Count -gt 0) { ('Planned targets: {0}' -f ($targets -join ', ')) } else { 'Planned targets: none (connect or stage targets in Remote Console).' }
			}

			if ($targets.Count -eq 0)
			{
				if ($txtDecisionSummary) { $txtDecisionSummary.Text = 'No planned targets - decision evaluation skipped.' }
				return
			}

			try
			{
				$decision = & $testRunCmd -Policy $policy -Targets $targets -Apply:$true
				if ($txtDecisionSummary) { $txtDecisionSummary.Text = (& $formatDecisionCmd -Decision $decision) }
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch375' -Severity Debug }

				if ($txtDecisionSummary) { $txtDecisionSummary.Text = ('Failed to evaluate policy: {0}' -f $_.Exception.Message) }
			}
		}.GetNewClosure()

		$refreshAll = {
			& $loadPolicyIntoUi $policy
			& $refreshKillState
			if ($txtChangeState) { $txtChangeState.Text = 'Empty values mean the change window is always allowed.' }
			& $evaluateDecision
		}.GetNewClosure()

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
			$btnRefresh.Add_Click({ & $refreshAll }.GetNewClosure())
		}
		if ($btnEvaluate)
		{
			$btnEvaluate.Content = $evaluateLabel
			Set-ButtonChrome -Button $btnEvaluate -Variant 'Secondary' -Compact
			$btnEvaluate.Add_Click({ & $evaluateDecision }.GetNewClosure())
		}
		if ($btnKillEngage)
		{
			$btnKillEngage.Content = $killEngageLabel
			Set-ButtonChrome -Button $btnKillEngage -Variant 'Secondary' -Compact
			$btnKillEngage.Add_Click({
				try { $script:policy = & $readPolicyFromUi; & $engageKillCmd -Path $script:policy.KillSwitchPath -Reason 'Operator console' } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch415' -Severity Debug }
				 [void](Show-ThemedDialog -Title 'Operator Console' -Message ("Failed to engage kill switch.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK') }
				& $refreshKillState
				& $evaluateDecision
			}.GetNewClosure())
		}
		if ($btnKillClear)
		{
			$btnKillClear.Content = $killClearLabel
			Set-ButtonChrome -Button $btnKillClear -Variant 'Secondary' -Compact
			$btnKillClear.Add_Click({
				try { $script:policy = & $readPolicyFromUi; & $clearKillCmd -Path $script:policy.KillSwitchPath } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch425' -Severity Debug }
				 [void](Show-ThemedDialog -Title 'Operator Console' -Message ("Failed to clear kill switch.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK') }
				& $refreshKillState
				& $evaluateDecision
			}.GetNewClosure())
		}
		if ($btnSavePolicy)
		{
			$btnSavePolicy.Content = $saveLabel
			Set-ButtonChrome -Button $btnSavePolicy -Variant 'Secondary' -Compact
			$btnSavePolicy.Add_Click({
				$dialog = New-Object Microsoft.Win32.SaveFileDialog
				$dialog.Title = $saveLabel
				$dialog.Filter = 'Operator Policy (*.json)|*.json|All Files (*.*)|*.*'
				$dialog.DefaultExt = 'json'
				$dialog.FileName = ('Baseline-OperatorPolicy-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
				if ($dialog.ShowDialog($dlg) -ne $true) { return }
				try
				{
					$current = & $readPolicyFromUi
					$payload = [ordered]@{
						MaxTargetsPerRun     = [int]$current.MaxTargetsPerRun
						MaxConcurrentTargets = [int]$current.MaxConcurrentTargets
						DeniedFunctions      = @($current.DeniedFunctions)
						DeniedTargets        = @($current.DeniedTargets)
						AllowedTargets       = @($current.AllowedTargets)
						ChangeWindow         = $current.ChangeWindow
						KillSwitchPath       = [string]$current.KillSwitchPath
					}
					$json = ConvertTo-Json -InputObject $payload -Depth 6
					[System.IO.File]::WriteAllText($dialog.FileName, $json)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch456' -Severity Debug }

					[void](Show-ThemedDialog -Title 'Operator Console' -Message ("Failed to save operator policy.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
			}.GetNewClosure())
		}
		if ($btnLoadPolicy)
		{
			$btnLoadPolicy.Content = $loadLabel
			Set-ButtonChrome -Button $btnLoadPolicy -Variant 'Secondary' -Compact
			$btnLoadPolicy.Add_Click({
				$dialog = New-Object Microsoft.Win32.OpenFileDialog
				$dialog.Title = $loadLabel
				$dialog.Filter = 'Operator Policy (*.json)|*.json|All Files (*.*)|*.*'
				if ($dialog.ShowDialog($dlg) -ne $true) { return }
				try
				{
					$raw = Get-Content -LiteralPath $dialog.FileName -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
					$cw = @{}
					if ($raw.ChangeWindow)
					{
						foreach ($prop in $raw.ChangeWindow.PSObject.Properties) { $cw[$prop.Name] = $prop.Value }
					}
					$script:policy = & $newPolicyCmd `
						-MaxTargetsPerRun ([int]$raw.MaxTargetsPerRun) `
						-MaxConcurrentTargets ([int]$raw.MaxConcurrentTargets) `
						-DeniedFunctions @($raw.DeniedFunctions) `
						-DeniedTargets @($raw.DeniedTargets) `
						-AllowedTargets @($raw.AllowedTargets) `
						-ChangeWindow $cw
					if ($raw.KillSwitchPath -and -not [string]::IsNullOrWhiteSpace([string]$raw.KillSwitchPath))
					{
						$script:policy.KillSwitchPath = [string]$raw.KillSwitchPath
					}
					& $refreshAll
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiOperatorConsoleDialog:catch492' -Severity Debug }

					[void](Show-ThemedDialog -Title 'Operator Console' -Message ("Failed to load operator policy.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
			}.GetNewClosure())
		}

		$dlg.Add_ContentRendered({ & $refreshAll })
		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		[void]($dlg.ShowDialog())
		return $null
	}

	<#
	    .SYNOPSIS

	    .DESCRIPTION
	    Internal implementation helper used by Baseline. Shows historical run
	    data with query, filter, and export capabilities.
	#>

	function Show-GuiHistoryViewerDialog
	{
		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-HistoryViewer'
		$windowTitle = Get-UxLocalizedString -Key 'GuiHistoryViewerTitle' -Fallback 'History Viewer'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiHistoryViewerSubtitle' -Fallback 'Review, query, and export historical run data.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$refreshLabel = Get-UxLocalizedString -Key 'GuiRefreshButton' -Fallback 'Refresh'
		$viewDetailsLabel = Get-UxLocalizedString -Key 'GuiHistoryViewDetails' -Fallback 'View Details...'
		$exportBundleLabel = Get-UxLocalizedString -Key 'GuiHistoryExportBundle' -Fallback 'Export Bundle...'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="960" Height="720"
	MinWidth="800" MinHeight="600"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
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

			<Grid Grid.Row="2" Margin="20,16,20,16">
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="*"/>
					<RowDefinition Height="Auto"/>
				</Grid.RowDefinitions>

				<Grid Grid.Row="0" Margin="0,0,0,12">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<TextBox Name="TxtSearch" Grid.Column="0" Padding="6,4,6,4" VerticalContentAlignment="Center"/>
					<Button Name="BtnRefresh" Grid.Column="1" Content="$refreshLabel" Margin="8,0,0,0" Padding="16,6" FontSize="13"/>
				</Grid>

				<ListView Name="HistoryList" Grid.Row="1" BorderThickness="1" BorderBrush="$($theme.BorderColor)">
					<ListView.View>
						<GridView>
							<GridViewColumn Header="Date" Width="160" DisplayMemberBinding="{Binding Timestamp, StringFormat='yyyy-MM-dd HH:mm:ss'}"/>
							<GridViewColumn Header="Operation" Width="120" DisplayMemberBinding="{Binding Operation}"/>
							<GridViewColumn Header="Targets" Width="180" DisplayMemberBinding="{Binding Targets}"/>
							<GridViewColumn Header="Result" Width="100" DisplayMemberBinding="{Binding Result}"/>
							<GridViewColumn Header="Summary" Width="350" DisplayMemberBinding="{Binding Summary}"/>
						</GridView>
					</ListView.View>
				</ListView>

				<TextBlock Name="TxtStatus" Grid.Row="2" Margin="0,8,0,0" Foreground="$($theme.TextMuted)"/>
			</Grid>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<WrapPanel HorizontalAlignment="Right">
					<Button Name="BtnViewDetails" Content="$viewDetailsLabel" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnExportBundle" Content="$exportBundleLabel" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnClose" Content="$closeLabel" Padding="16,6" FontSize="13"/>
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

		$dlgTitleBar     = $dlg.FindName('DlgTitleBar')
		$btnDlgClose     = $dlg.FindName('BtnDlgClose')
		$txtSearch       = $dlg.FindName('TxtSearch')
		$historyList     = $dlg.FindName('HistoryList')
		$txtStatus       = $dlg.FindName('TxtStatus')
		$btnRefresh      = $dlg.FindName('BtnRefresh')
		$btnViewDetails  = $dlg.FindName('BtnViewDetails')
		$btnExportBundle = $dlg.FindName('BtnExportBundle')
		$btnClose        = $dlg.FindName('BtnClose')

		$getHistoryCmd = Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteOrchestrationDetails' -CommandType 'Function'
		$allHistoryItems = @()

		$updateActionButtons = {
			$selected = $historyList.SelectedItem
			if ($btnViewDetails) { $btnViewDetails.IsEnabled = ($null -ne $selected -and (Test-GuiObjectField -Object $selected -FieldName 'LogPath') -and -not [string]::IsNullOrWhiteSpace($selected.LogPath)) }
			if ($btnExportBundle) { $btnExportBundle.IsEnabled = ($null -ne $selected -and (Test-GuiObjectField -Object $selected -FieldName 'BundlePath') -and -not [string]::IsNullOrWhiteSpace($selected.BundlePath)) }
		}.GetNewClosure()

		$refreshHistory = {
			if (-not $getHistoryCmd)
			{
				$historyList.ItemsSource = @()
				$txtStatus.Text = 'History query service is not available.'
				return
			}

			try
			{
				$script:allHistoryItems = @((& $getHistoryCmd))
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiHistoryViewerDialog:catch666' -Severity Debug }

				$script:allHistoryItems = @()
				$txtStatus.Text = "Failed to load history: $($_.Exception.Message)"
			}

			$filterText = $txtSearch.Text
			$filteredItems = if ([string]::IsNullOrWhiteSpace($filterText))
			{
				$script:allHistoryItems
			}
			else
			{
				@($script:allHistoryItems | Where-Object {
					$_.Targets -match $filterText -or
					$_.Operation -match $filterText -or
					$_.Result -match $filterText -or
					$_.Summary -match $filterText
				})
			}

			$historyList.ItemsSource = $filteredItems
			if ($filteredItems.Count -eq 0)
			{
				$txtStatus.Text = (Get-UxLocalizedString -Key 'GuiHistoryNoRunsFound' -Fallback 'No historical runs found.')
			}
			else
			{
				$txtStatus.Text = (Get-UxLocalizedString -Key 'GuiHistoryStatus' -Fallback 'Showing {0} of {1} runs.' -FormatArgs @($filteredItems.Count, $script:allHistoryItems.Count))
			}
			& $updateActionButtons
		}.GetNewClosure()

		if ($dlgTitleBar) { $dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure()) }
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		if ($txtSearch)
		{
			$txtSearch.Add_TextChanged({ & $refreshHistory }.GetNewClosure())
			if (Get-Command -Name 'Set-GuiWatermarkText' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiWatermarkText -TextBox $txtSearch -Text (Get-UxLocalizedString -Key 'GuiHistoryFilterByTarget' -Fallback 'Filter by target, operation, result...')
			}
		}

		if ($historyList)
		{
			$historyList.Add_SelectionChanged({ & $updateActionButtons }.GetNewClosure())
		}

		if ($btnRefresh)
		{
			Set-ButtonChrome -Button $btnRefresh -Variant 'Secondary' -Compact
			$btnRefresh.Add_Click({ & $refreshHistory }.GetNewClosure())
		}

		if ($btnViewDetails)
		{
			Set-ButtonChrome -Button $btnViewDetails -Variant 'Secondary' -Compact
			$btnViewDetails.Add_Click({
				$selected = $historyList.SelectedItem
				if ($null -ne $selected -and (Test-GuiObjectField -Object $selected -FieldName 'LogPath') -and -not [string]::IsNullOrWhiteSpace($selected.LogPath))
				{
					Show-LogDialog -LogPath $selected.LogPath
				}
			}.GetNewClosure())
		}

		if ($btnExportBundle)
		{
			Set-ButtonChrome -Button $btnExportBundle -Variant 'Secondary' -Compact
			$btnExportBundle.Add_Click({
				$selected = $historyList.SelectedItem
				if ($null -ne $selected -and (Test-GuiObjectField -Object $selected -FieldName 'BundlePath') -and -not [string]::IsNullOrWhiteSpace($selected.BundlePath))
				{
					try { [System.Diagnostics.Process]::Start($selected.BundlePath) } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiHistoryViewerDialog:catch741' -Severity Debug }
					 [void](Show-ThemedDialog -Title $windowTitle -Message "Failed to open bundle: $($_.Exception.Message)") }
				}
			}.GetNewClosure())
		}

		if ($btnClose)
		{
			Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
			$btnClose.IsDefault = $true
			$btnClose.IsCancel = $true
			$btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())
		}

		$dlg.Add_ContentRendered({ & $refreshHistory })
		$dlg.Add_KeyDown({
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		[void]($dlg.ShowDialog())
		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Show-GuiReleaseStatusDialog
	{
		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-ReleaseStatus'
		$windowTitle = Get-UxLocalizedString -Key 'GuiReleaseStatusTitle' -Fallback 'Release Status'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiReleaseStatusSubtitle' -Fallback 'Current build, signing, and artifact posture.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$resolvedModuleRoot = $null
		$resolvedRepoRoot = $null
		try
		{
			if (-not [string]::IsNullOrWhiteSpace([string]$Script:SharedHelpersModuleRoot))
			{
				$resolvedModuleRoot = [string]$Script:SharedHelpersModuleRoot
			}
			elseif ($Script:DialogHelpersRoot)
			{
				$resolvedModuleRoot = Split-Path -Parent $Script:DialogHelpersRoot
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiReleaseStatusDialog.ResolveModuleRoot' }
		try
		{
			if (-not [string]::IsNullOrWhiteSpace([string]$Script:SharedHelpersRepoRoot))
			{
				$resolvedRepoRoot = [string]$Script:SharedHelpersRepoRoot
			}
			elseif ($resolvedModuleRoot)
			{
				$resolvedRepoRoot = Split-Path -Parent $resolvedModuleRoot
			}
			elseif ($Script:DialogHelpersRoot)
			{
				$resolvedRepoRoot = Split-Path -Parent (Split-Path -Parent $Script:DialogHelpersRoot)
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiReleaseStatusDialog.ResolveRepoRoot' }

		$version = 'unknown'
		try { $version = Get-BaselineDisplayVersion } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiReleaseStatusDialog.LoadVersion' }
		$iconStatus = 'Unknown'
		$iconFontPath = $null
		try
		{
			if (Get-Command -Name 'Test-GuiIconsAvailable' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$iconStatus = if (Test-GuiIconsAvailable) { 'Enabled' } else { 'Fallback' }
			}
			if (Get-Command -Name 'Get-GuiIconFontPath' -CommandType Function -ErrorAction SilentlyContinue)
			{
				if ($resolvedRepoRoot)
				{
					$iconFontPath = Get-GuiIconFontPath -ModuleRoot $resolvedRepoRoot
				}
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch832' -Severity Debug }

			$iconStatus = 'Unknown'
		}
		$matrixSummary = 'Unavailable'
		$serverValidationSummary = 'Unavailable'
		try
		{
			if (Get-Command -Name 'Get-BaselineValidationMatrixSummary' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$matrix = Get-BaselineValidationMatrixSummary -RepoRoot $resolvedRepoRoot
				if ($matrix)
				{
					if ($matrix.Summary)
					{
						$matrixSummary = [string]$matrix.Summary
					}
					if ($matrix.ServerValidationSummary)
					{
						$serverValidationSummary = [string]$matrix.ServerValidationSummary
					}
				}
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch856' -Severity Debug }

			$matrixSummary = 'Unavailable'
			$serverValidationSummary = 'Unavailable'
		}
		$validationEvidenceSummary = 'Unavailable'
		$validationEvidenceChannels = 'Unavailable'
		$validationEvidenceProvenance = 'Unavailable'
		try
		{
			if (Get-Command -Name 'Get-BaselineValidationEvidenceReport' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$validationEvidence = Get-BaselineValidationEvidenceReport -RepoRoot $resolvedRepoRoot
				if ($validationEvidence)
				{
					if ($validationEvidence.Summary)
					{
						$validationEvidenceSummary = [string]$validationEvidence.Summary
					}
					if ($validationEvidence.ValidationChannels)
					{
						$validationEvidenceChannels = (@($validationEvidence.ValidationChannels | ForEach-Object { [string]$_.Channel }) -join ', ')
					}

					$provenanceParts = [System.Collections.Generic.List[string]]::new()
					if ($validationEvidence.Build)
					{
						if ($validationEvidence.Build.BaselineVersion) { [void]$provenanceParts.Add(('version {0}' -f [string]$validationEvidence.Build.BaselineVersion)) }
						if ($validationEvidence.Build.TestReportGeneratedAt) { [void]$provenanceParts.Add(('test report {0}' -f [string]$validationEvidence.Build.TestReportGeneratedAt)) }
						if ($validationEvidence.Build.TestPlatform) { [void]$provenanceParts.Add(('platform {0}' -f [string]$validationEvidence.Build.TestPlatform)) }
					}
					if ($validationEvidence.SourcePath)
					{
						if ($validationEvidence.SourcePath.TestReport) { [void]$provenanceParts.Add(('report {0}' -f [string]$validationEvidence.SourcePath.TestReport)) }
						if ($validationEvidence.SourcePath.ValidationMatrix) { [void]$provenanceParts.Add(('matrix {0}' -f [string]$validationEvidence.SourcePath.ValidationMatrix)) }
					}
					if ($provenanceParts.Count -gt 0)
					{
						$validationEvidenceProvenance = ($provenanceParts -join ' | ')
					}
				}
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch899' -Severity Debug }

			$validationEvidenceSummary = 'Unavailable'
			$validationEvidenceChannels = 'Unavailable'
			$validationEvidenceProvenance = 'Unavailable'
		}
		$featureMaturitySummary = 'Unavailable'
		$enterpriseGateSummary = 'Unavailable'
		try
		{
			$featureMaturityCmd = Get-GuiRuntimeCommand -Name 'Get-BaselineFeatureMaturityReport' -CommandType 'Function'
			if ($featureMaturityCmd)
			{
				$featureMaturityReport = & $featureMaturityCmd -Manifest $Script:TweakManifest
				if ($featureMaturityReport -and $featureMaturityReport.Summary)
				{
					$featureMaturitySummary = @(
						('Implemented={0}' -f [int]$featureMaturityReport.Summary.Implemented),
						('Tested={0}' -f [int]$featureMaturityReport.Summary.Tested),
						('CI-validated={0}' -f [int]$featureMaturityReport.Summary.'CI-validated'),
						('Production-validated={0}' -f [int]$featureMaturityReport.Summary.'Production-validated')
					) -join ', '

					$gateParts = @(
						@($featureMaturityReport.EnterpriseActions | ForEach-Object {
							('{0}: {1} (required {2}) [{3}]' -f [string]$_.FeatureName, [string]$_.CurrentMaturity, [string]$_.RequiredMaturity, $(if ([bool]$_.Allowed) { 'Open' } else { 'Blocked' }))
						})
					)
					if ($gateParts.Count -gt 0)
					{
						$enterpriseGateSummary = ($gateParts -join ' | ')
					}
				}
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch934' -Severity Debug }

			$featureMaturitySummary = 'Unavailable'
			$enterpriseGateSummary = 'Unavailable'
		}
		$pinnedVersion = $null
		try
		{
			if ($Script:Ctx -and $Script:Ctx.ContainsKey('UI') -and $Script:Ctx.UI.PSObject.Properties['PinnedBaselineVersion'])
			{
				$pinnedVersion = [string]$Script:Ctx.UI.PinnedBaselineVersion
			}
			elseif ($Script:PinnedBaselineVersion)
			{
				$pinnedVersion = [string]$Script:PinnedBaselineVersion
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch951' -Severity Debug }

			$pinnedVersion = $null
		}
		$exePaths = @(
			$(if ($resolvedRepoRoot) { Join-Path $resolvedRepoRoot 'Baseline.exe' }),
			$(if ($resolvedRepoRoot) { Join-Path $resolvedRepoRoot 'Baseline-1.0.0-setup.exe' }),
			$(if ($resolvedRepoRoot) { Join-Path $resolvedRepoRoot 'Baseline-1.0.0-stable.zip' })
		)
		$artifactVerificationCmd = Get-GuiRuntimeCommand -Name 'Get-BaselineReleaseArtifactVerification' -CommandType 'Function'

		. (Join-Path $PSScriptRoot 'AuditOperatorDialogs\Show-GuiReleaseStatusDialog\Show-GuiReleaseStatusDialog.ps1')

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

		$btnClose = $dlg.FindName('BtnClose')
		$btnPinVersion = $dlg.FindName('BtnPinVersion')
		$btnClearPin = $dlg.FindName('BtnClearPin')
		$contentPanel = $dlg.FindName('ContentPanel')
		if ($btnClose)
		{
			$btnClose.Content = $closeLabel
			Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
			$btnClose.IsDefault = $true
			$btnClose.IsCancel = $true
			$btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())
		}
		if ($btnPinVersion)
		{
			$pinLabel = Get-UxLocalizedString -Key 'GuiReleaseStatusPinCurrent' -Fallback 'Pin Current Version'
			$btnPinVersion.Content = $pinLabel
			Set-ButtonChrome -Button $btnPinVersion -Variant 'Subtle' -Compact
			$btnPinVersion.Add_Click({
				try
				{
					$currentVersion = $null
					try { $currentVersion = Get-BaselineDisplayVersion } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch999' -Severity Debug }
					 $currentVersion = $null }
					if ([string]::IsNullOrWhiteSpace($currentVersion))
					{
						return
					}
					$Script:PinnedBaselineVersion = [string]$currentVersion
					if ($Script:Ctx -and $Script:Ctx.ContainsKey('UI'))
					{
						$Script:Ctx.UI.PinnedBaselineVersion = [string]$currentVersion
					}
					[void](Show-ThemedDialog -Title $windowTitle -Message (('Pinned release version: {0}' -f [string]$currentVersion)) -Buttons @('OK') -AccentButton 'OK')
					$dlg.Close()
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch1012' -Severity Debug }

					[void](Show-ThemedDialog -Title $windowTitle -Message ("Failed to pin the current version.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
			}.GetNewClosure())
		}
		if ($btnClearPin)
		{
			$clearPinLabel = Get-UxLocalizedString -Key 'GuiReleaseStatusClearPin' -Fallback 'Clear Pin'
			$btnClearPin.Content = $clearPinLabel
			Set-ButtonChrome -Button $btnClearPin -Variant 'Subtle' -Compact
			$btnClearPin.Add_Click({
				try
				{
					$Script:PinnedBaselineVersion = $null
					if ($Script:Ctx -and $Script:Ctx.ContainsKey('UI'))
					{
						$Script:Ctx.UI.PinnedBaselineVersion = $null
					}
					[void](Show-ThemedDialog -Title $windowTitle -Message 'Pinned release version cleared.' -Buttons @('OK') -AccentButton 'OK')
					$dlg.Close()
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch1034' -Severity Debug }

					[void](Show-ThemedDialog -Title $windowTitle -Message ("Failed to clear the pinned version.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
			}.GetNewClosure())
		}

		$lines = [System.Collections.Generic.List[string]]::new()
		[void]$lines.Add(("Version: {0}" -f $version))
		[void]$lines.Add(("Pinned version: {0}" -f ($(if ($pinnedVersion) { $pinnedVersion } else { 'none' }))))
		[void]$lines.Add(("Icon system: {0}" -f $iconStatus))
		if ($iconFontPath)
		{
			[void]$lines.Add(("Icon font: {0}" -f $iconFontPath))
		}
		[void]$lines.Add(("Validation matrix: {0}" -f $matrixSummary))
		[void]$lines.Add(("Server validation outside CI: {0}" -f $serverValidationSummary))
		[void]$lines.Add(("Validation evidence: {0}" -f $validationEvidenceSummary))
		[void]$lines.Add(("Validation channels: {0}" -f $validationEvidenceChannels))
		[void]$lines.Add(("Build/test provenance: {0}" -f $validationEvidenceProvenance))
		[void]$lines.Add(("Feature maturity: {0}" -f $featureMaturitySummary))
		[void]$lines.Add(("Enterprise gates: {0}" -f $enterpriseGateSummary))
		[void]$lines.Add('Artifact verification:')
		foreach ($path in @($exePaths))
		{
			$verification = $null
			try
			{
				if ($artifactVerificationCmd)
				{
					$verification = Invoke-CapturedFunction -Name 'Get-BaselineReleaseArtifactVerification' -Parameters @{ Path = $path }
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditOperatorDialogs.Show-GuiReleaseStatusDialog:catch1068' -Severity Debug }

				$verification = $null
			}

			if (-not $verification)
			{
				$status = if (Test-Path -LiteralPath $path) { 'Present' } else { 'Missing' }
				$verification = [pscustomobject]@{
					VerificationState = if ($status -eq 'Present') { 'Unavailable' } else { 'Missing' }
					SignatureStatus   = $status
					TimestampStatus   = 'Unavailable'
					SignerSubject     = $null
					TimestampSubject  = $null
					FileHash          = $null
					VerificationMessage = if ($status -eq 'Present') { 'Artifact verification helper is not available.' } else { 'Artifact not found.' }
				}
			}

			[void]$lines.Add(("Artifact: {0}" -f $path))
			[void]$lines.Add(("Verification: {0} | Signature: {1} | Timestamp: {2}" -f $verification.VerificationState, $verification.SignatureStatus, $verification.TimestampStatus))
			[void]$lines.Add(("Signer: {0} | Timestamp signer: {1} | SHA256: {2}" -f ($(if ($verification.SignerSubject) { $verification.SignerSubject } else { 'n/a' })), ($(if ($verification.TimestampSubject) { $verification.TimestampSubject } else { 'n/a' })), ($(if ($verification.FileHash) { $verification.FileHash } else { 'n/a' }))))
			[void]$lines.Add(("Result: {0}" -f $verification.VerificationMessage))
		}

		foreach ($line in $lines)
		{
			$txt = New-Object System.Windows.Controls.TextBlock
			$txt.Text = $line
			$txt.TextWrapping = 'Wrap'
			$txt.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
			$txt.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			[void]$contentPanel.Children.Add($txt)
		}

		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		[void]($dlg.ShowDialog())
		return $null
	}
