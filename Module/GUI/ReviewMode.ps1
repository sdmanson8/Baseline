# ReviewMode.ps1
#
# Per-row Accept / Reject banner dialog for previewing config-import or
# preset-apply changes before they hit the orchestrator.
#
# Public surface:
#   * Show-GuiReviewModeDialog -Diff $diff [...]
#       Renders a themed WPF window with one checkbox per Add/Remove/Change
#       row, plus Accept-All / Reject-All / Exit / Apply buttons and
#       per-row green/red action highlighting.
#       Returns @{ Cancelled = [bool]; Decisions = @(...) } where each
#       decision is [pscustomobject]@{ Id; Decision = 'Accept' | 'Reject' }.
#   * Invoke-GuiReviewModeGate -CurrentProfile -ImportedProfile [...]
#       Headless-friendly orchestrator. Composes
#       Compare-BaselineConfigForReview -> Show-GuiReviewModeDialog (or
#       auto-accept fallback if no theme) -> Resolve-BaselineConfigReviewDecisions.
#       Returns @{ Cancelled; Accepted; Rejected; Skipped; Diff }.
#
# Design notes:
#   * 'Same' rows are NOT shown to the user (the helpers strip them on
#     Resolve), but they are listed in a collapsed footer count so the
#     user can see how much was already in sync.
#   * Default decision per row mirrors the row's Action: Add/Change rows
#     default to Accept; Remove rows default to Reject (the user has to
#     explicitly opt in to having Baseline strip a tweak the imported
#     profile no longer carries). Accept-All / Reject-All overrides apply
#     to the visible rows only.

function ConvertTo-GuiReviewActionLabel
{
	[CmdletBinding()]
	[OutputType([string])]
	param ([Parameter(Mandatory)][string]$Action)

	switch ($Action)
	{
		'Add'    { return (Get-UxLocalizedString -Key 'GuiReviewModeActionAdd'    -Fallback 'Add') }
		'Remove' { return (Get-UxLocalizedString -Key 'GuiReviewModeActionRemove' -Fallback 'Remove') }
		'Change' { return (Get-UxLocalizedString -Key 'GuiReviewModeActionChange' -Fallback 'Change') }
		'Same'   { return (Get-UxLocalizedString -Key 'GuiReviewModeActionSame'   -Fallback 'Unchanged') }
		default  { return $Action }
	}
}

function Get-GuiReviewModeDefaultDecisionForRow
{
	[CmdletBinding()]
	[OutputType([string])]
	param ([Parameter(Mandatory)][string]$Action)

	switch ($Action)
	{
		'Add'    { return 'Accept' }
		'Change' { return 'Accept' }
		'Remove' { return 'Reject' }
		default  { return 'Reject' }
	}
}

function Get-GuiReviewModeRowTone
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)][string]$Action,
		[Parameter()][object]$Theme
	)

	$currentTheme = Get-Variable -Name 'CurrentTheme' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	$resolvedTheme = if ($Theme) { $Theme } else { $currentTheme }
	if (-not $resolvedTheme)
	{
		return [pscustomobject]@{
			Background = '#00000000'
			Border     = '#00000000'
		}
	}

	switch ($Action)
	{
		'Add' {
			return [pscustomobject]@{
				Background = [string]$resolvedTheme.LowRiskBadgeBg
				Border     = [string]$resolvedTheme.LowRiskBadge
			}
		}
		'Change' {
			return [pscustomobject]@{
				Background = [string]$resolvedTheme.LowRiskBadgeBg
				Border     = [string]$resolvedTheme.LowRiskBadge
			}
		}
		'Remove' {
			return [pscustomobject]@{
				Background = [string]$resolvedTheme.RiskHighBadgeBg
				Border     = [string]$resolvedTheme.RiskHighBadge
			}
		}
		default {
			return [pscustomobject]@{
				Background = [string]$resolvedTheme.HeaderBg
				Border     = [string]$resolvedTheme.BorderColor
			}
		}
	}
}

function Show-GuiReviewModeDialog
{
	<#
		.SYNOPSIS
		Themed WPF dialog that lets the user accept or reject each Add /
		Remove / Change row from a Compare-BaselineConfigForReview diff.

		.DESCRIPTION
		Returns @{ Cancelled = [bool]; Decisions = @(...) }. Decisions is
		an array of [pscustomobject]@{ Id; Decision = 'Accept' | 'Reject' }.
		Returns Cancelled=$true if the user closes the window via Cancel /
		Esc / X — caller should treat that as "abort the import / apply".

		Headless harness fallback: when $Script:CurrentTheme is not set
		(e.g. test runner), the dialog short-circuits and returns the
		default decisions for every actionable row. This keeps the gate
		callable from automated tests and from the CLI / unattended path
		without needing a WPF host.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param (
		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[object[]]$Diff,

		[string]$Title,
		[string]$Subtitle,

		[ValidateSet('Accept','Reject')]
		[string]$DefaultDecision
	)

	$titleText = if ($PSBoundParameters.ContainsKey('Title') -and -not [string]::IsNullOrWhiteSpace($Title)) {
		$Title
	} else {
		Get-UxLocalizedString -Key 'GuiReviewModeTitle' -Fallback 'Review Imported Changes'
	}
	$subtitleText = if ($PSBoundParameters.ContainsKey('Subtitle') -and -not [string]::IsNullOrWhiteSpace($Subtitle)) {
		$Subtitle
	} else {
		Get-UxLocalizedString -Key 'GuiReviewModeSubtitle' -Fallback 'Tick the rows you want to apply. Unchanged rows are listed for reference only.'
	}

	$summary = Get-BaselineConfigReviewSummary -Diff $Diff
	$visibleRows = @($Diff | Where-Object { $_ -and [string]$_.Action -ne 'Same' })

	# Headless / test path — no theme means no WPF host. Return default
	# decisions for every actionable row so callers can still exercise the
	# gate logic.
	$currentTheme = Get-Variable -Name 'CurrentTheme' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if (-not $currentTheme)
	{
		$decisions = New-Object System.Collections.Generic.List[object]
		foreach ($row in $visibleRows)
		{
			$verdict = if ($PSBoundParameters.ContainsKey('DefaultDecision')) {
				$DefaultDecision
			} else {
				Get-GuiReviewModeDefaultDecisionForRow -Action ([string]$row.Action)
			}
			$decisions.Add([pscustomobject]@{ Id = [string]$row.Id; Decision = $verdict }) | Out-Null
		}
		return @{ Cancelled = $false; Decisions = @($decisions.ToArray()) }
	}

	$theme = $currentTheme
	$bc = New-SafeBrushConverter -Context 'ReviewMode-Dialog'

	$acceptAllLabel = Get-UxLocalizedString -Key 'GuiReviewModeAcceptAll' -Fallback 'Accept all'
	$rejectAllLabel = Get-UxLocalizedString -Key 'GuiReviewModeRejectAll' -Fallback 'Reject all'
	$applyLabel     = Get-UxLocalizedString -Key 'GuiReviewModeApply'     -Fallback 'Apply selected'
	$exitLabel      = Get-UxLocalizedString -Key 'GuiReviewModeExit'      -Fallback 'Exit'
	$summaryFmt     = Get-UxLocalizedString -Key 'GuiReviewModeSummary'   -Fallback '{0} actionable changes ({1} Add / {2} Remove / {3} Change). {4} unchanged rows hidden.'
	$summaryText    = ($summaryFmt -f $summary.Actionable, $summary.Add, $summary.Remove, $summary.Change, $summary.Same)
	$emptyText      = Get-UxLocalizedString -Key 'GuiReviewModeEmpty' -Fallback 'No actionable differences found. The imported profile matches the current state.'
	$closeLabel     = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$titleText"
	Width="900" Height="640"
	MinWidth="720" MinHeight="480"
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
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>

			<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
				<Grid>
					<TextBlock Text="$titleText" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
						Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
						HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</Grid>
			</Border>

			<Border Grid.Row="1" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
					Padding="20,14,20,14">
				<StackPanel>
					<TextBlock Name="TxtDialogTitle" Text="$titleText" FontSize="16" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtDialogSubtitle" Text="$subtitleText" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
					<TextBlock Name="TxtSummary" Text="$summaryText" FontSize="11" Foreground="$($theme.TextSecondary)" Margin="0,8,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<Border Grid.Row="2" Background="$($theme.WindowBg)" Padding="20,10,20,10" BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1">
				<StackPanel Orientation="Horizontal">
					<Button Name="BtnAcceptAll" Content="$acceptAllLabel" Padding="14,5" FontSize="12" Margin="0,0,8,0"/>
					<Button Name="BtnRejectAll" Content="$rejectAllLabel" Padding="14,5" FontSize="12"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,16,20,16">
				<StackPanel Name="RowsPanel" Orientation="Vertical"/>
			</ScrollViewer>

			<Border Grid.Row="4" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
						<Button Name="BtnExit" Content="$exitLabel" Padding="20,6" FontSize="13" Margin="0,0,8,0"/>
						<Button Name="BtnApply"  Content="$applyLabel"  Padding="20,6" FontSize="13"/>
					</StackPanel>
				</Grid>
			</Border>
		</Grid>
	</Border>
</Window>
"@

	$reader = [System.Xml.XmlNodeReader]::new($xaml)
	$dlg = [Windows.Markup.XamlReader]::Load($reader)
	if ($Script:MainForm) { $dlg.Owner = $Script:MainForm }

	$rootBorder = $dlg.FindName('RootBorder')
	if ($rootBorder)
	{
		$rootBorder.Background = $bc.ConvertFromString($theme.WindowBg)
		$rootBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
		$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	}
	if (Get-Command -Name 'GUICommon\Set-GuiWindowChromeTheme' -ErrorAction SilentlyContinue)
	{
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
	}

	$dlgTitleBar = $dlg.FindName('DlgTitleBar')
	$btnDlgClose = $dlg.FindName('BtnDlgClose')
	$btnAcceptAll = $dlg.FindName('BtnAcceptAll')
	$btnRejectAll = $dlg.FindName('BtnRejectAll')
	$btnApply = $dlg.FindName('BtnApply')
	$btnExit = $dlg.FindName('BtnExit')
	$rowsPanel = $dlg.FindName('RowsPanel')

	if ($dlgTitleBar)
	{
		$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
	}
	if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

	# Per-row checkbox state lives in this dictionary, keyed by row Id.
	# Apply/Cancel collect from it on close.
	$state = @{
		Cancelled = $true
		CheckBoxes = @{}
	}

	if ($visibleRows.Count -eq 0)
	{
		$emptyBlock = New-Object System.Windows.Controls.TextBlock
		$emptyBlock.Text = $emptyText
		$emptyBlock.FontSize = 12
		$emptyBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
		$emptyBlock.TextWrapping = 'Wrap'
		$emptyBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
		[void]($rowsPanel.Children.Add($emptyBlock))
		if ($btnApply) { $btnApply.IsEnabled = $false }
		if ($btnAcceptAll) { $btnAcceptAll.IsEnabled = $false }
		if ($btnRejectAll) { $btnRejectAll.IsEnabled = $false }
	}
	else
	{
		foreach ($row in $visibleRows)
		{
			$rowTone = Get-GuiReviewModeRowTone -Action ([string]$row.Action) -Theme $theme
			$rowBorder = New-Object System.Windows.Controls.Border
			$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
			$rowBorder.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
			$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
			$rowBorder.Background = $bc.ConvertFromString($rowTone.Background)
			$rowBorder.BorderBrush = $bc.ConvertFromString($rowTone.Border)
			$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)

			$rowGrid = New-Object System.Windows.Controls.Grid
			$colAccent = New-Object System.Windows.Controls.ColumnDefinition
			$colAccent.Width = [System.Windows.GridLength]::new(8)
			$colCheck = New-Object System.Windows.Controls.ColumnDefinition
			$colCheck.Width = [System.Windows.GridLength]::new(28)
			$colMain = New-Object System.Windows.Controls.ColumnDefinition
			$colMain.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			[void]$rowGrid.ColumnDefinitions.Add($colAccent)
			[void]$rowGrid.ColumnDefinitions.Add($colCheck)
			[void]$rowGrid.ColumnDefinitions.Add($colMain)

			$accent = New-Object System.Windows.Controls.Border
			$accent.Background = $bc.ConvertFromString($rowTone.Border)
			$accent.CornerRadius = [System.Windows.CornerRadius]::new(4, 0, 0, 4)
			$accent.HorizontalAlignment = 'Stretch'
			$accent.VerticalAlignment = 'Stretch'
			[System.Windows.Controls.Grid]::SetColumn($accent, 0)
			[void]$rowGrid.Children.Add($accent)

			$cb = New-Object System.Windows.Controls.CheckBox
			$cb.VerticalAlignment = 'Center'
			[System.Windows.Controls.Grid]::SetColumn($cb, 1)
			$default = Get-GuiReviewModeDefaultDecisionForRow -Action ([string]$row.Action)
			$cb.IsChecked = ($default -eq 'Accept')
			[void]$rowGrid.Children.Add($cb)
			$state.CheckBoxes[[string]$row.Id] = $cb

			$mainStack = New-Object System.Windows.Controls.StackPanel
			$mainStack.Orientation = 'Vertical'
			[System.Windows.Controls.Grid]::SetColumn($mainStack, 2)

			$actionPill = New-Object System.Windows.Controls.Border
			$actionPill.Background = $bc.ConvertFromString($rowTone.Background)
			$actionPill.BorderBrush = $bc.ConvertFromString($rowTone.Border)
			$actionPill.BorderThickness = [System.Windows.Thickness]::new(1)
			$actionPill.CornerRadius = [System.Windows.CornerRadius]::new(10)
			$actionPill.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
			$actionPill.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
			$actionPill.HorizontalAlignment = 'Left'

			$actionPillText = New-Object System.Windows.Controls.TextBlock
			$actionPillText.Text = (ConvertTo-GuiReviewActionLabel -Action ([string]$row.Action))
			$actionPillText.FontSize = 10
			$actionPillText.FontWeight = [System.Windows.FontWeights]::SemiBold
			$actionPillText.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$actionPill.Child = $actionPillText
			[void]$mainStack.Children.Add($actionPill)

			$header = New-Object System.Windows.Controls.TextBlock
			$header.Text = [string]$row.Id
			$header.FontWeight = [System.Windows.FontWeights]::SemiBold
			$header.FontSize = 13
			$header.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			[void]$mainStack.Children.Add($header)

			$detail = New-Object System.Windows.Controls.TextBlock
			$cur = if ([string]::IsNullOrWhiteSpace([string]$row.CurrentValue))  { '(absent)' } else { [string]$row.CurrentValue }
			$imp = if ([string]::IsNullOrWhiteSpace([string]$row.ImportedValue)) { '(absent)' } else { [string]$row.ImportedValue }
			$detail.Text = ('{0}  →  {1}' -f $cur, $imp)
			$detail.FontSize = 11
			$detail.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$detail.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
			$detail.TextWrapping = 'Wrap'
			[void]$mainStack.Children.Add($detail)

			if (-not [string]::IsNullOrWhiteSpace([string]$row.GatedBy))
			{
				$gated = New-Object System.Windows.Controls.TextBlock
				$gated.Text = (Get-UxLocalizedString -Key 'GuiReviewModeGatedByFormat' -Fallback 'Gated by: {0}' -FormatArgs @([string]$row.GatedBy))
				$gated.FontSize = 10
				$gated.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$gated.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
				$gated.TextWrapping = 'Wrap'
				[void]$mainStack.Children.Add($gated)
			}

			[void]$rowGrid.Children.Add($mainStack)
			$rowBorder.Child = $rowGrid
			[void]$rowsPanel.Children.Add($rowBorder)
		}
	}

	if ($btnAcceptAll)
	{
		$cbMap = $state.CheckBoxes
		$btnAcceptAll.Add_Click({
			foreach ($k in @($cbMap.Keys)) { $cbMap[$k].IsChecked = $true }
		}.GetNewClosure())
	}
	if ($btnRejectAll)
	{
		$cbMap = $state.CheckBoxes
		$btnRejectAll.Add_Click({
			foreach ($k in @($cbMap.Keys)) { $cbMap[$k].IsChecked = $false }
		}.GetNewClosure())
	}

	if ($btnApply)
	{
		$st = $state
		$dlgRef = $dlg
		$btnApply.Add_Click({
			$st.Cancelled = $false
			$dlgRef.Close()
		}.GetNewClosure())
	}
	if ($btnExit)
	{
		$dlgRef = $dlg
		$btnExit.IsCancel = $true
		$btnExit.Add_Click({ $dlgRef.Close() }.GetNewClosure())
	}

	$dlg.Add_KeyDown({
		$eventArgs = $args[1]
		if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
	})

	[void]($dlg.ShowDialog())

	if ($state.Cancelled)
	{
		return @{ Cancelled = $true; Decisions = @() }
	}

	$decisions = New-Object System.Collections.Generic.List[object]
	foreach ($row in $visibleRows)
	{
		$id = [string]$row.Id
		$cb = $state.CheckBoxes[$id]
		$verdict = if ($cb -and $cb.IsChecked) { 'Accept' } else { 'Reject' }
		$decisions.Add([pscustomobject]@{ Id = $id; Decision = $verdict }) | Out-Null
	}
	return @{ Cancelled = $false; Decisions = @($decisions.ToArray()) }
}

function Invoke-GuiReviewModeGate
{
	<#
		.SYNOPSIS
		Composes the Compare-BaselineConfigForReview / Show-GuiReviewModeDialog
		/ Resolve-BaselineConfigReviewDecisions trio into a single
		caller-friendly gate.

		.DESCRIPTION
		Returns @{ Cancelled = [bool]; Accepted = @(...); Rejected = @(...);
		Skipped = @(...); Diff = @(...); Summary = pscustomobject }.

		Cancelled=$true means the user closed the dialog via Cancel / Esc.
		The orchestrator should treat Cancelled as a hard abort: no apply,
		no profile mutation, no undo overlay tear-down side effects.

		Accepted is the array of imported entries to feed Start-GuiExecutionRun
		($TweakList) — already filtered to the user's verdict.

		Headless: when $Script:CurrentTheme is unset, Show-GuiReviewModeDialog
		auto-confirms with default per-row verdicts; Cancelled is always
		$false on that path.

		.PARAMETER DefaultDecision
		Verdict applied to any visible row the user did not explicitly
		decide on. 'Reject' is fail-safe and is the default.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param (
		[Parameter()][AllowNull()][object]$CurrentProfile,
		[Parameter()][AllowNull()][object]$ImportedProfile,
		[string]$Title,
		[string]$Subtitle,
		[ValidateSet('Accept','Reject')]
		[string]$DefaultDecision = 'Reject'
	)

	$diff = Compare-BaselineConfigForReview -Current $CurrentProfile -Imported $ImportedProfile
	$summary = Get-BaselineConfigReviewSummary -Diff $diff

	$dialogArgs = @{ Diff = $diff }
	if ($PSBoundParameters.ContainsKey('Title'))    { $dialogArgs['Title']    = $Title }
	if ($PSBoundParameters.ContainsKey('Subtitle')) { $dialogArgs['Subtitle'] = $Subtitle }
	# Do NOT forward DefaultDecision into the dialog — that parameter is a
	# blanket override that flattens the smarter per-row defaults
	# (Add/Change → Accept, Remove → Reject). Reserve -DefaultDecision for
	# the Resolve step below, where it correctly fills in any row the user
	# left undecided.

	$dialogResult = Show-GuiReviewModeDialog @dialogArgs
	if (-not $dialogResult -or [bool]$dialogResult.Cancelled)
	{
		return @{
			Cancelled = $true
			Accepted  = @()
			Rejected  = @()
			Skipped   = @()
			Diff      = @($diff)
			Summary   = $summary
		}
	}

	$resolved = Resolve-BaselineConfigReviewDecisions -Diff $diff -Decisions $dialogResult.Decisions -DefaultDecision $DefaultDecision

	return @{
		Cancelled = $false
		Accepted  = @($resolved.Accepted)
		Rejected  = @($resolved.Rejected)
		Skipped   = @($resolved.Skipped)
		Diff      = @($diff)
		Summary   = $summary
	}
}

function Invoke-GuiReviewModePromptForRun
{
	<#
		.SYNOPSIS
		Orchestrator-side helper that gates a Start-GuiExecutionRun apply
		on the Review Mode dialog.

		.DESCRIPTION
		Given the current/imported profiles plus the live $TweakList that
		Start-GuiExecutionRun is about to execute, runs the Review Mode
		gate. Returns the filtered $TweakList — only the entries whose
		Function the user accepted survive — or $null if the user
		cancelled (in which case the caller must abort the run).

		The filter matches by Function name (the orchestrator key for
		tweaks) so the caller does not need to rebuild $TweakList from the
		Accepted array; we just keep the ordering and metadata the
		orchestrator already has.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param (
		[Parameter()][AllowNull()][object]$CurrentProfile,
		[Parameter()][AllowNull()][object]$ImportedProfile,
		[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$TweakList,
		[string]$Title,
		[string]$Subtitle,
		[ValidateSet('Accept','Reject')]
		[string]$DefaultDecision = 'Reject'
	)

	$gateArgs = @{
		CurrentProfile  = $CurrentProfile
		ImportedProfile = $ImportedProfile
		DefaultDecision = $DefaultDecision
	}
	if ($PSBoundParameters.ContainsKey('Title'))    { $gateArgs['Title']    = $Title }
	if ($PSBoundParameters.ContainsKey('Subtitle')) { $gateArgs['Subtitle'] = $Subtitle }

	$result = Invoke-GuiReviewModeGate @gateArgs
	if ([bool]$result.Cancelled) { return $null }

	$acceptedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($accepted in @($result.Accepted))
	{
		$key = ConvertTo-BaselineReviewEntryKey -Entry $accepted
		if ($key) { [void]$acceptedKeys.Add($key) }
	}

	$filtered = New-Object System.Collections.Generic.List[object]
	foreach ($tweak in @($TweakList))
	{
		$key = ConvertTo-BaselineReviewEntryKey -Entry $tweak
		if (-not $key -or $acceptedKeys.Contains($key))
		{
			$filtered.Add($tweak) | Out-Null
		}
	}
	return ,@($filtered.ToArray())
}
