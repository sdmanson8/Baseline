

	<#
	    .SYNOPSIS
	#>

	function Resolve-BaselineChangelogPath
	{
		$candidates = [System.Collections.Generic.List[string]]::new()

		$launcherPath = [string]([System.Environment]::GetEnvironmentVariable('BASELINE_LAUNCHER_PATH'))
		if (-not [string]::IsNullOrWhiteSpace($launcherPath))
		{
			try
			{
				[void]$candidates.Add((Join-Path -Path (Split-Path -Path $launcherPath -Parent) -ChildPath 'CHANGELOG.md'))
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineChangelogPath.AddLauncherCandidate' }
		}

		try
		{
			$appBaseDirectory = [System.AppContext]::BaseDirectory
			if (-not [string]::IsNullOrWhiteSpace([string]$appBaseDirectory))
			{
				[void]$candidates.Add((Join-Path -Path $appBaseDirectory -ChildPath 'CHANGELOG.md'))
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineChangelogPath.AddAppBaseCandidate' }

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
		{
			try
			{
				[void]$candidates.Add((Join-Path -Path (Split-Path -Path $Script:GuiModuleBasePath -Parent) -ChildPath 'CHANGELOG.md'))
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineChangelogPath.AddModuleCandidate' }
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:DialogHelpersRoot))
		{
			try
			{
				$dialogHelpersRoot = Split-Path -Path (Split-Path -Path $Script:DialogHelpersRoot -Parent) -Parent
				if (-not [string]::IsNullOrWhiteSpace([string]$dialogHelpersRoot))
				{
					[void]$candidates.Add((Join-Path -Path $dialogHelpersRoot -ChildPath 'CHANGELOG.md'))
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineChangelogPath.AddDialogHelpersRootCandidate' }
		}

		try
		{
			$currentDirectory = (Get-Location).Path
			if (-not [string]::IsNullOrWhiteSpace([string]$currentDirectory))
			{
				[void]$candidates.Add((Join-Path -Path $currentDirectory -ChildPath 'CHANGELOG.md'))
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineChangelogPath.AddCurrentDirectoryCandidate' }

		foreach ($candidate in @($candidates | Select-Object -Unique))
		{
			if ([string]::IsNullOrWhiteSpace([string]$candidate))
			{
				continue
			}

			try
			{
				if (Test-Path -LiteralPath $candidate -PathType Leaf)
				{
					return [System.IO.Path]::GetFullPath($candidate)
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineChangelogPath.TestCandidatePath' }
		}

		return ($candidates | Select-Object -First 1)
	}

	<#
	    .SYNOPSIS
	#>

	function Resolve-BaselineChangelogVersionLabel
	{
		[CmdletBinding()]
		param (
			[string]$DisplayVersion
		)

		if ([string]::IsNullOrWhiteSpace([string]$DisplayVersion))
		{
			return $null
		}

		$match = [regex]::Match([string]$DisplayVersion, 'v?(\d+\.\d+\.\d+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?)(?:\s*\(([^)]+)\))?')
		if (-not $match.Success)
		{
			return $null
		}

		$baseVersion = $match.Groups[1].Value.Trim()
		if ($match.Groups[2].Success -and -not [string]::IsNullOrWhiteSpace($match.Groups[2].Value))
		{
			return ('v{0}-{1}' -f $baseVersion, $match.Groups[2].Value.Trim())
		}

		return ('v{0}' -f $baseVersion)
	}

	<#
	    .SYNOPSIS
	#>

	function Select-BaselineChangelogVersionSection
	{
		[CmdletBinding()]
		param (
			[string]$Raw,
			[string]$Version
		)

		if ([string]::IsNullOrWhiteSpace($Raw) -or [string]::IsNullOrWhiteSpace($Version))
		{
			return $Raw
		}

		$versionLabel = Resolve-BaselineChangelogVersionLabel -DisplayVersion $Version
		if ([string]::IsNullOrWhiteSpace([string]$versionLabel))
		{
			return $Raw
		}

		$targetVersion = $versionLabel.TrimStart('v', 'V')
		$releaseHeadingPattern = '^\s{0,3}#{1,2}\s+v?(\d+\.\d+\.\d+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?)(?:\s*\|.*)?\s*$'
		$lines = $Raw -split "`r?`n"
		$startIdx = -1

		for ($i = 0; $i -lt $lines.Length; $i++)
		{
			$headingMatch = [regex]::Match($lines[$i], $releaseHeadingPattern)
			if ($headingMatch.Success -and [string]::Equals($headingMatch.Groups[1].Value, $targetVersion, [System.StringComparison]::OrdinalIgnoreCase))
			{
				$startIdx = $i
				break
			}
		}

		if ($startIdx -lt 0)
		{
			return ('No changelog entry found for v{0}.' -f $targetVersion)
		}

		$endIdx = $lines.Length - 1
		for ($j = $startIdx + 1; $j -lt $lines.Length; $j++)
		{
			if ([regex]::IsMatch($lines[$j], $releaseHeadingPattern))
			{
				$endIdx = $j - 1
				break
			}
		}

		while ($endIdx -gt $startIdx -and ($lines[$endIdx].Trim() -eq '---' -or [string]::IsNullOrWhiteSpace($lines[$endIdx])))
		{
			$endIdx--
		}

		return ($lines[$startIdx..$endIdx] -join "`r`n")
	}

	<#
	    .SYNOPSIS
	#>

	function Resolve-BaselineReadmePath
	{
		$candidates = [System.Collections.Generic.List[string]]::new()

		$launcherPath = [string]([System.Environment]::GetEnvironmentVariable('BASELINE_LAUNCHER_PATH'))
		if (-not [string]::IsNullOrWhiteSpace($launcherPath))
		{
			try
			{
				[void]$candidates.Add((Join-Path -Path (Split-Path -Path $launcherPath -Parent) -ChildPath 'README.md'))
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineReadmePath.AddLauncherCandidate' }
		}

		try
		{
			$appBaseDirectory = [System.AppContext]::BaseDirectory
			if (-not [string]::IsNullOrWhiteSpace([string]$appBaseDirectory))
			{
				[void]$candidates.Add((Join-Path -Path $appBaseDirectory -ChildPath 'README.md'))
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineReadmePath.AddAppBaseCandidate' }

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
		{
			try
			{
				[void]$candidates.Add((Join-Path -Path (Split-Path -Path $Script:GuiModuleBasePath -Parent) -ChildPath 'README.md'))
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineReadmePath.AddModuleCandidate' }
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:DialogHelpersRoot))
		{
			try
			{
				$dialogHelpersRoot = Split-Path -Path (Split-Path -Path $Script:DialogHelpersRoot -Parent) -Parent
				if (-not [string]::IsNullOrWhiteSpace([string]$dialogHelpersRoot))
				{
					[void]$candidates.Add((Join-Path -Path $dialogHelpersRoot -ChildPath 'README.md'))
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineReadmePath.AddDialogHelpersRootCandidate' }
		}

		try
		{
			$currentDirectory = (Get-Location).Path
			if (-not [string]::IsNullOrWhiteSpace([string]$currentDirectory))
			{
				[void]$candidates.Add((Join-Path -Path $currentDirectory -ChildPath 'README.md'))
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineReadmePath.AddCurrentDirectoryCandidate' }

		foreach ($candidate in @($candidates | Select-Object -Unique))
		{
			if ([string]::IsNullOrWhiteSpace([string]$candidate))
			{
				continue
			}

			try
			{
				if (Test-Path -LiteralPath $candidate -PathType Leaf)
				{
					return [System.IO.Path]::GetFullPath($candidate)
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Resolve-BaselineReadmePath.TestCandidatePath' }
		}

		return ($candidates | Select-Object -First 1)
	}

	<#
	    .SYNOPSIS
	#>

	function Show-GuiTroubleshootingGuideDialog
	{
		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-Troubleshooting'
		$windowTitle = Get-UxLocalizedString -Key 'GuiTroubleshootingTitle' -Fallback 'Troubleshooting Guide'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiTroubleshootingSubtitle' -Fallback 'Use this guide to reproduce, capture, and report issues.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$bundleLabel = Get-UxLocalizedString -Key 'GuiMenuToolsExportSupportBundle' -Fallback 'Export Support Bundle...'

		$errorCatalog = $null
		try
		{
			if (Get-Command -Name 'Get-BaselineErrorCatalog' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$errorCatalog = Get-BaselineErrorCatalog
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.Show-GuiTroubleshootingGuideDialog:catch281' -Severity Debug }

			$errorCatalog = $null
		}
		if (-not $errorCatalog)
		{
			$errorCatalog = @{}
		}

		$sections = [System.Collections.Generic.List[object]]::new()
		$sections.Add([pscustomobject]@{
			Title = '1. Reproduce the issue'
			Lines = @(
				'Repeat the same action in the same mode (local, connected remote, or apply / preview).',
				'Keep the same target list, profile, and approval state if the issue is remote.',
				'Note the exact time, command, and any dialog that appears.'
			)
		}) | Out-Null
		$sections.Add([pscustomobject]@{
			Title = '2. Capture evidence'
			Lines = @(
				'Open Release Status to confirm the running build, artifact state, and validation matrix.',
				'Export a support bundle so the log, snapshot, and audit trail are captured together.',
				'Include the error code shown below if Baseline surfaces one.'
			)
		}) | Out-Null
		$guiStartError004Message = if ($errorCatalog.ContainsKey('GUI-STARTUP-004')) { [string]$errorCatalog['GUI-STARTUP-004'].Message } else { 'Installation looks incomplete.' }
		$guiStartError005Message = if ($errorCatalog.ContainsKey('GUI-STARTUP-005')) { [string]$errorCatalog['GUI-STARTUP-005'].Message } else { 'Missing or empty startup data.' }
		$guiGenericErrorMessage = if ($errorCatalog.ContainsKey('GUI-GENERIC-001')) { [string]$errorCatalog['GUI-GENERIC-001'].Message } else { 'Unexpected problem.' }

		$sections.Add([pscustomobject]@{
			Title = '3. Common error codes'
			Lines = @(
				('GUI-STARTUP-004 - {0}' -f $guiStartError004Message),
				('GUI-STARTUP-005 - {0}' -f $guiStartError005Message),
				('GUI-GENERIC-001 - {0}' -f $guiGenericErrorMessage)
			)
		}) | Out-Null
		$sections.Add([pscustomobject]@{
			Title = '4. Next steps for support'
			Lines = @(
				'Send the support bundle, the error code, and the exact reproduction steps to the operator or IT admin.',
				'If the issue is remote, include the approved target list and the remote console status.',
				'If the issue follows a policy change, include the release-status report and audit time window.'
			)
		}) | Out-Null
		$sections.Add([pscustomobject]@{
			Title = '5. Managed endpoint review'
			Lines = @(
				'Managed endpoints can surface domain join status and active policy hives in preflight.',
				'If the policy environment is flagged, review GPO-enforced settings before a remote apply run and confirm the GPO scope in the remote console.',
				'Export the relevant policy hives or document enforced settings before any high-risk change.',
				'Use the preflight output together with the support bundle to confirm the endpoint state.'
			)
		}) | Out-Null

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="820" Height="620"
	MinWidth="720" MinHeight="520"
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
					<TextBlock Text="$windowTitle" FontSize="16" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Text="$windowSubtitle" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,18,20,18">
				<StackPanel Name="ContentPanel"/>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<Button Name="BtnExportBundle" Content="" HorizontalAlignment="Left" Padding="18,6" FontSize="13"/>
					<Button Name="BtnClose" Content="" HorizontalAlignment="Right" Padding="20,6" FontSize="13"/>
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

		$btnClose = $dlg.FindName('BtnClose')
		$btnExportBundle = $dlg.FindName('BtnExportBundle')
		$contentPanel = $dlg.FindName('ContentPanel')
		if ($btnClose)
		{
			$btnClose.Content = $closeLabel
			Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
			$btnClose.IsDefault = $true
			$btnClose.IsCancel = $true
			$btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())
		}
		if ($btnExportBundle)
		{
			$btnExportBundle.Content = $bundleLabel
			Set-ButtonChrome -Button $btnExportBundle -Variant 'Primary' -Compact
			$btnExportBundle.Add_Click({
				try
				{
					if ($Script:MenuToolsExportSupportBundle)
					{
						$eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent)
						$Script:MenuToolsExportSupportBundle.RaiseEvent($eventArgs)
					}
				}
				catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiTroubleshootingGuideDialog.RaiseExportSupportBundleClick' }
			}.GetNewClosure())
		}

		foreach ($section in $sections)
		{
			$card = New-Object System.Windows.Controls.Border
			$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
			$card.BorderThickness = [System.Windows.Thickness]::new(1)
			$card.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$card.Background = $bc.ConvertFromString($theme.CardBg)
			$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
			$card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)

			$stack = New-Object System.Windows.Controls.StackPanel
			$title = New-Object System.Windows.Controls.TextBlock
			$title.Text = [string]$section.Title
			$title.FontSize = 13
			$title.FontWeight = 'SemiBold'
			$title.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$title.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
			[void]$stack.Children.Add($title)

			foreach ($line in @($section.Lines))
			{
				$txt = New-Object System.Windows.Controls.TextBlock
				$txt.Text = [string]$line
				$txt.TextWrapping = 'Wrap'
				$txt.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
				$txt.Foreground = $bc.ConvertFromString($theme.TextPrimary)
				[void]$stack.Children.Add($txt)
			}

			$card.Child = $stack
			[void]$contentPanel.Children.Add($card)
		}

		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		[void]($dlg.ShowDialog())
		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Show-GuiFaqDialog
	{
		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-FAQ'
		$windowTitle = Get-UxLocalizedString -Key 'GuiMenuHelpFAQ' -Fallback 'FAQ'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiMenuHelpFAQSubtitle' -Fallback 'Common questions and quick answers.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'

		$faqItems = @(
			[pscustomobject]@{
				Title = 'Which preset should I start with?'
				Lines = @(
					'In Safe Mode, start with Minimal for the most conservative first run.',
					'Outside Safe Mode, Basic remains the default recommendation for most users.'
				)
			}
			[pscustomobject]@{
				Title = 'When should I use Advanced?'
				Lines = @(
					'Use Advanced only after reviewing Preview Run and after you are comfortable with harder-to-reverse changes.',
					'Keep a recovery plan ready before applying it.'
				)
			}
			[pscustomobject]@{
				Title = 'A tweak failed. What should I try first?'
				Lines = @(
					'Rerun Baseline as administrator, reboot if needed, and review Preview Run plus the detailed log before trying again.'
				)
			}
			[pscustomobject]@{
				Title = 'Can Baseline automatically undo everything?'
				Lines = @(
					'No. Some changes expose direct undo commands, some revert to recorded default values, and some still rely on restore points or manual recovery.'
				)
			}
			[pscustomobject]@{
				Title = 'How do I run a compliance check?'
				Lines = @(
					'Export a configuration profile from the GUI or create one from a preset, then run the compliance check against that profile.'
				)
			}
		)

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="820" Height="620"
	MinWidth="720" MinHeight="520"
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
					<TextBlock Text="$windowTitle" FontSize="16" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Text="$windowSubtitle" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,18,20,18">
				<StackPanel Name="ContentPanel"/>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<Button Name="BtnClose" Content="" HorizontalAlignment="Right" Padding="20,6" FontSize="13"/>
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
		$contentPanel = $dlg.FindName('ContentPanel')
		$btnClose = $dlg.FindName('BtnClose')
		if ($dlgTitleBar)
		{
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
			$faqCtx = New-Object System.Windows.Controls.ContextMenu
			$faqCtxClose = New-Object System.Windows.Controls.MenuItem
			$faqCtxClose.Header = $closeLabel
			$faqCtxClose.InputGestureText = 'Alt+F4'
			$faqCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
			$faqCtxClose.Add_Click({ $dlg.Close() }.GetNewClosure())
			[void]$faqCtx.Items.Add($faqCtxClose)
			$dlgTitleBar.ContextMenu = $faqCtx
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
		$btnClose.Content = $closeLabel
		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
		$btnClose.IsDefault = $true
		$btnClose.IsCancel = $true
		$btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())

		foreach ($item in $faqItems)
		{
			$card = New-Object System.Windows.Controls.Border
			$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
			$card.BorderThickness = [System.Windows.Thickness]::new(1)
			$card.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$card.Background = $bc.ConvertFromString($theme.CardBg)
			$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
			$card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)

			$stack = New-Object System.Windows.Controls.StackPanel
			$title = New-Object System.Windows.Controls.TextBlock
			$title.Text = [string]$item.Title
			$title.FontSize = 13
			$title.FontWeight = 'SemiBold'
			$title.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$title.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
			[void]$stack.Children.Add($title)

			foreach ($line in @($item.Lines))
			{
				$txt = New-Object System.Windows.Controls.TextBlock
				$txt.Text = [string]$line
				$txt.TextWrapping = 'Wrap'
				$txt.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
				$txt.Foreground = $bc.ConvertFromString($theme.TextPrimary)
				[void]$stack.Children.Add($txt)
			}

			$card.Child = $stack
			[void]$contentPanel.Children.Add($card)
		}

		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		[void]($dlg.ShowDialog())
		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Show-HelpDialog
	{
		param (
			[switch]$StartUpdateCheck
		)

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DialogHelpers-AboutPanel'
		$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme $theme
		$helpDialogTitle = Get-UxHelpDialogTitle
		$helpDialogSubtitle = Get-UxHelpDialogSubtitle
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$downloadLabel = Get-UxLocalizedString -Key 'GuiDownloadBaselineButton' -Fallback 'Check for Update'
		$downloadFailedTitle = Get-UxLocalizedString -Key 'GuiDownloadBaselineFailedTitle' -Fallback 'Download Failed'
		$downloadCompletedTitle = Get-UxLocalizedString -Key 'GuiDownloadBaselineCompletedTitle' -Fallback 'Download Complete'
		$downloadingLabel = Get-UxLocalizedString -Key 'GuiDownloadBaselineInProgress' -Fallback 'Downloading...'
		$downloadPreparingLabel = Get-UxLocalizedString -Key 'GuiDownloadBaselinePreparing' -Fallback 'Preparing download...'
		$downloadProgressLabel = Get-UxLocalizedString -Key 'GuiDownloadBaselineProgressLabel' -Fallback 'Downloading Baseline...'
		$downloadCompleteLabel = Get-UxLocalizedString -Key 'GuiDownloadBaselineProgressComplete' -Fallback 'Download complete.'
		$downloadFailedLabel = Get-UxLocalizedString -Key 'GuiDownloadBaselineProgressFailed' -Fallback 'Download failed.'
		$okLabel = Get-UxLocalizedString -Key 'GuiOkButton' -Fallback 'OK'
		$getBaselineBilingualString = ${function:Get-BaselineBilingualString}

		$sections = Get-UxHelpSections
		if ($null -eq $sections)
		{
			$sections = [ordered]@{
				(Get-UxLocalizedString -Key 'GuiHelpSectionStartGuide' -Fallback 'Start Guide') = @(Get-UxQuickStartSteps)
				(Get-UxLocalizedString -Key 'GuiHelpSectionUndoRestore' -Fallback 'Undo and Restore') = @(Get-UxUndoAndRestoreLines)
				(Get-UxLocalizedString -Key 'GuiHelpSectionImportExport' -Fallback 'Import / Export') = @(Get-UxImportExportLines)
			}
		}

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$helpDialogTitle"
	Width="$($Script:GuiLayout.HelpDialogWidth)" Height="$($Script:GuiLayout.HelpDialogHeight)"
	MinWidth="$($Script:GuiLayout.HelpDialogMinWidth)" MinHeight="$($Script:GuiLayout.HelpDialogMinHeight)"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="Segoe UI"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8">
	<Border.Resources>
		$scrollBarStyleXaml
	</Border.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
			<Grid>
				<TextBlock Text="$helpDialogTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
				<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
					Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
					HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
			</Grid>
		</Border>

		<Border Grid.Row="1" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<StackPanel>
				<TextBlock Text="$helpDialogTitle" FontSize="16" FontWeight="SemiBold"
						   Foreground="$($theme.TextPrimary)"/>
				<TextBlock Text="$helpDialogSubtitle"
						   FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0"/>
			</StackPanel>
		</Border>

		<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"
					  HorizontalScrollBarVisibility="Disabled"
					  Padding="0,0,4,0">
			<StackPanel Name="ContentPanel" Margin="20,16,20,16"/>
		</ScrollViewer>

		<Border Grid.Row="3" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<StackPanel>
				<StackPanel Name="DownloadProgressPanel" Margin="0,0,0,10" Visibility="Collapsed">
					<Grid>
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="*"/>
							<ColumnDefinition Width="Auto"/>
						</Grid.ColumnDefinitions>
						<TextBlock Name="TxtDownloadProgressLabel" Grid.Column="0" Text="" FontSize="12" Foreground="$($theme.TextSecondary)"/>
						<TextBlock Name="TxtDownloadProgressPct" Grid.Column="1" Text="0%" FontSize="12" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					</Grid>
					<ProgressBar Name="DownloadProgressBar" Height="18" Minimum="0" Maximum="100" Value="0" Margin="0,6,0,0"/>
				</StackPanel>
				<Grid>
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<Button Name="BtnDownloadBaseline" Grid.Column="0" Content=""
							HorizontalAlignment="Left"
							Padding="20,6" FontSize="13" Margin="0,0,8,0"/>
					<Button Name="BtnClose" Grid.Column="2" Content=""
							HorizontalAlignment="Right"
							Padding="20,6" FontSize="13"/>
				</Grid>
			</StackPanel>
		</Border>
	</Grid>
	</Border>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form

		$rootBorder = $dlg.FindName('RootBorder')
		$useDarkMode = if (Test-Path -Path Variable:\Script:CurrentThemeName) { $Script:CurrentThemeName -eq 'Dark' } else { $false }
		if (Test-Path -Path Variable:\Script:CurrentTheme)
		{
			$theme = $Script:CurrentTheme
			if ($rootBorder)
			{
				$rootBorder.Background = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, [System.Convert]::ToInt32($theme.WindowBg.Substring(1, 2), 16), [System.Convert]::ToInt32($theme.WindowBg.Substring(3, 2), 16), [System.Convert]::ToInt32($theme.WindowBg.Substring(5, 2), 16))))
				$rootBorder.BorderBrush = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, [System.Convert]::ToInt32($theme.BorderColor.Substring(1, 2), 16), [System.Convert]::ToInt32($theme.BorderColor.Substring(3, 2), 16), [System.Convert]::ToInt32($theme.BorderColor.Substring(5, 2), 16))))
				$rootBorder.BorderThickness = '1'
			}
		}
		else
		{
			if ($rootBorder)
			{
				$rootBorder.Background = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, 241, 241, 241)))
				$rootBorder.BorderBrush = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, 200, 200, 200)))
				$rootBorder.BorderThickness = '1'
			}
		}
		if (Test-Path -Path Function:\Set-GuiWindowChromeTheme)
		{
			[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode $useDarkMode)
		}

		# Wire help dialog title bar
		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		if ($dlgTitleBar) {
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
			$dhCtx = New-Object System.Windows.Controls.ContextMenu
			$dhCtxClose = New-Object System.Windows.Controls.MenuItem
			$dhCtxClose.Header = $closeLabel; $dhCtxClose.InputGestureText = 'Alt+F4'; $dhCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
			$dhCtxRef = $dlg
			$dhCtxClose.Add_Click({ $dhCtxRef.Close() }.GetNewClosure())
			[void]$dhCtx.Items.Add($dhCtxClose)
			$dlgTitleBar.ContextMenu = $dhCtx
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$panel = $dlg.FindName('ContentPanel')
		$btnClose = $dlg.FindName('BtnClose')
		$btnDownloadBaseline = $dlg.FindName('BtnDownloadBaseline')
		$downloadProgressPanel = $dlg.FindName('DownloadProgressPanel')
		$txtDownloadProgressLabel = $dlg.FindName('TxtDownloadProgressLabel')
		$txtDownloadProgressPct = $dlg.FindName('TxtDownloadProgressPct')
		$downloadProgressBar = $dlg.FindName('DownloadProgressBar')
		$btnClose.Content = $closeLabel

		Set-ButtonChrome -Button $btnClose -Variant 'Subtle' -Compact
		$btnClose.IsDefault = $true
		$btnClose.IsCancel = $true

		. (Join-Path $PSScriptRoot 'ContentDialogs\Show-HelpDialog\Show-HelpDialog.ps1')

		Register-GuiEventHandler -Source $btnClose -EventName 'Click' -Handler { $dlg.Close() }
		Register-GuiEventHandler -Source $dlg -EventName 'KeyDown' -Handler {
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		}

		[void]($dlg.ShowDialog())
	}

	<#
	    .SYNOPSIS
	#>

	function Show-FirstRunWelcomeDialog
	{
		param (
			[string]$RecommendedPreset,
			[string]$PrimaryActionLabel,
			[string]$WelcomeMessage,
			[string]$DialogTitle,
			[object]$ShowThemedDialogCapture,
			[scriptblock]$OpenHelpAction,
			[scriptblock]$ChooseRecommendedPresetAction,
			[scriptblock]$GuidedSetupAction,
			[hashtable]$Theme,
			[scriptblock]$ApplyButtonChrome,
			[object]$OwnerWindow,
			[object]$UseDarkMode = $true
		)

		$resolvedUseDarkMode = GUICommon\Get-GuiBooleanValue -Value $UseDarkMode -Default $(if (Test-Path -Path Variable:\Script:CurrentThemeName) { $Script:CurrentThemeName -eq 'Dark' } else { $true }) -Context 'Show-FirstRunWelcomeDialog'

		$guidedSetupLabel = Get-UxLocalizedString -Key 'GuiGuidedSetupButton' -Fallback 'Guided Setup'
		$chooseButton  = if ([string]::IsNullOrWhiteSpace($PrimaryActionLabel)) { (Get-UxLocalizedString -Key 'GuiFirstRunStartWith' -Fallback "Start with {0}" -FormatArgs @($RecommendedPreset)) } else { $PrimaryActionLabel }
		$resolvedTitle = if ([string]::IsNullOrWhiteSpace($DialogTitle)) { (Get-UxLocalizedString -Key 'GuiFirstRunDialogTitle' -Fallback 'Welcome to Baseline') } else { $DialogTitle }
		$closeLabel    = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$openHelpLabel = Get-UxLocalizedString -Key 'GuiOpenHelpActionLabel' -Fallback 'Open Help'

		# Guided Setup is the primary CTA on first run; preset shortcut is secondary
		$choice = & $ShowThemedDialogCapture -Title $resolvedTitle `
			-Message $WelcomeMessage `
			-Buttons @($closeLabel, $openHelpLabel, $chooseButton, $guidedSetupLabel) `
			-AccentButton $guidedSetupLabel `
			-Theme $Theme `
			-ApplyButtonChrome $ApplyButtonChrome `
			-OwnerWindow $OwnerWindow `
			-UseDarkMode $resolvedUseDarkMode

		switch ($choice)
		{
			$openHelpLabel
			{
				if ($OpenHelpAction) { & $OpenHelpAction }
				break
			}
			$guidedSetupLabel
			{
				if ($GuidedSetupAction) { & $GuidedSetupAction }
				break
			}
			default
			{
				if ($choice -eq $chooseButton -and $ChooseRecommendedPresetAction)
				{
					& $ChooseRecommendedPresetAction
				}
				break
			}
		}

		return $choice
	}

	<#
	    .SYNOPSIS
	#>

	function Show-LogDialog
	{
		param([string]$LogPath)

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DialogHelpers-PresetWarning'
		$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme $theme
		$logViewerTitle = Get-UxLocalizedString -Key 'GuiLogViewerTitle' -Fallback 'Log Viewer'
		$refreshLabel = Get-UxLocalizedString -Key 'GuiRefreshButton' -Fallback 'Refresh'
		$openExternalLabel = Get-UxLocalizedString -Key 'GuiOpenInNotepad' -Fallback 'Open in Notepad'
		$successLabel = Get-UxLocalizedString -Key 'GuiLogSuccess' -Fallback 'success'
		$failedLabel = Get-UxLocalizedString -Key 'GuiLogFailed' -Fallback 'failed'
		$skippedWarningLabel = Get-UxLocalizedString -Key 'GuiLogSkippedWarning' -Fallback 'skipped / warning'
		$infoLabel = Get-UxLocalizedString -Key 'GuiLogInfo' -Fallback 'info'
		$filterAllLabel = Get-UxLocalizedString -Key 'GuiLogFilterAll' -Fallback 'All'
		$filterErrorsLabel = Get-UxLocalizedString -Key 'GuiLogFilterErrors' -Fallback 'Errors'
		$filterWarningsLabel = Get-UxLocalizedString -Key 'GuiLogFilterWarnings' -Fallback 'Warnings'
		$filterInfoLabel = Get-UxLocalizedString -Key 'GuiLogFilterInfo' -Fallback 'Info'
		$filterDebugLabel = Get-UxLocalizedString -Key 'GuiLogFilterDebug' -Fallback 'Debug'
		$filterSuccessLabel = Get-UxLocalizedString -Key 'GuiLogFilterSuccess' -Fallback 'Success'
		$searchLogsLabel = Get-UxLocalizedString -Key 'GuiLogSearchPlaceholder' -Fallback 'Search logs'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$logViewerTitle"
	Width="$($Script:GuiLayout.LogDialogWidth)" Height="$($Script:GuiLayout.LogDialogHeight)"
	MinWidth="$($Script:GuiLayout.LogDialogMinWidth)" MinHeight="$($Script:GuiLayout.LogDialogMinHeight)"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8">
	<Border.Resources>
		$scrollBarStyleXaml
	</Border.Resources>
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
				<TextBlock Text="$logViewerTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
				<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
					Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
					HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
			</Grid>
		</Border>

		<Border Grid.Row="1" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0">
					<TextBlock Text="$logViewerTitle" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtLogPath" FontSize="11"
							   Foreground="$($theme.TextMuted)" Margin="0,2,0,0"
							   TextTrimming="CharacterEllipsis"/>
				</StackPanel>
				<StackPanel Grid.Column="1" Orientation="Horizontal"
							VerticalAlignment="Center" HorizontalAlignment="Right">
					<Button Name="BtnRefresh" Content="$refreshLabel" Margin="0,0,8,0"
							Padding="12,5" FontSize="12"/>
					<Button Name="BtnOpenExternal" Content="$openExternalLabel"
							Padding="12,5" FontSize="12"/>
				</StackPanel>
			</Grid>
		</Border>

		<Border Grid.Row="2" Background="$($theme.WindowBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,10,20,10">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="16"/>
					<ColumnDefinition Width="*"/>
				</Grid.ColumnDefinitions>
				<ComboBox Name="CmbLogLevelFilter" Grid.Column="0" Width="150" MinHeight="30" SelectedIndex="0">
					<ComboBoxItem Content="$filterAllLabel"/>
					<ComboBoxItem Content="$filterErrorsLabel"/>
					<ComboBoxItem Content="$filterWarningsLabel"/>
					<ComboBoxItem Content="$filterInfoLabel"/>
					<ComboBoxItem Content="$filterDebugLabel"/>
					<ComboBoxItem Content="$filterSuccessLabel"/>
				</ComboBox>
				<TextBox Name="TxtLogSearch" Grid.Column="2" MinHeight="30" Padding="10,5"
						 Text="" ToolTip="$searchLogsLabel"/>
			</Grid>
		</Border>

		<ScrollViewer Name="LogScroll" Grid.Row="3"
					  VerticalScrollBarVisibility="Auto"
					  HorizontalScrollBarVisibility="Auto"
					  Background="$($theme.SearchBg)"
					  Padding="0,0,4,0">
			<StackPanel Name="LogPanel" Margin="16,12,16,12"/>
		</ScrollViewer>

		<Border Grid.Row="4" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
					<Ellipse Width="8" Height="8" Fill="$($theme.LowRiskBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="$successLabel" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.RiskHighBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="$failedLabel" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.RiskMediumBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="$skippedWarningLabel" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.TextMuted)" Margin="0,0,5,0"/>
					<TextBlock Text="$infoLabel" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$(if ($theme.ContainsKey('LogDebug')) { $theme.LogDebug } else { $theme.TextMuted })" Margin="0,0,5,0"/>
					<TextBlock Text="$filterDebugLabel" FontSize="11" Foreground="$($theme.TextMuted)"/>
				</StackPanel>
				<Button Name="BtnClose" Grid.Column="1" Content=""
						Padding="20,6" FontSize="13"/>
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
		$useDarkMode = if (Test-Path -Path Variable:\Script:CurrentThemeName) { $Script:CurrentThemeName -eq 'Dark' } else { $false }
		if (Test-Path -Path Variable:\Script:CurrentTheme)
		{
			$theme = $Script:CurrentTheme
			if ($rootBorder)
			{
				$rootBorder.Background = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, [System.Convert]::ToInt32($theme.WindowBg.Substring(1, 2), 16), [System.Convert]::ToInt32($theme.WindowBg.Substring(3, 2), 16), [System.Convert]::ToInt32($theme.WindowBg.Substring(5, 2), 16))))
				$rootBorder.BorderBrush = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, [System.Convert]::ToInt32($theme.BorderColor.Substring(1, 2), 16), [System.Convert]::ToInt32($theme.BorderColor.Substring(3, 2), 16), [System.Convert]::ToInt32($theme.BorderColor.Substring(5, 2), 16))))
				$rootBorder.BorderThickness = '1'
			}
		}
		else
		{
			if ($rootBorder)
			{
				$rootBorder.Background = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, 241, 241, 241)))
				$rootBorder.BorderBrush = [System.Windows.Media.Brush](New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color]::FromArgb(255, 200, 200, 200)))
				$rootBorder.BorderThickness = '1'
			}
		}
		if (Test-Path -Path Function:\Set-GuiWindowChromeTheme)
		{
			[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode $useDarkMode)
		}

		# Wire log dialog title bar
		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		if ($dlgTitleBar) {
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
			$dhCtx = New-Object System.Windows.Controls.ContextMenu
			$dhCtxClose = New-Object System.Windows.Controls.MenuItem
			$dhCtxClose.Header = $closeLabel; $dhCtxClose.InputGestureText = 'Alt+F4'; $dhCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
			$dhCtxRef = $dlg
			$dhCtxClose.Add_Click({ $dhCtxRef.Close() }.GetNewClosure())
			[void]$dhCtx.Items.Add($dhCtxClose)
			$dlgTitleBar.ContextMenu = $dhCtx
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$logPanel = $dlg.FindName('LogPanel')
		$logScroll = $dlg.FindName('LogScroll')
		$txtLogPath = $dlg.FindName('TxtLogPath')
		$btnClose = $dlg.FindName('BtnClose')
		$btnRefresh = $dlg.FindName('BtnRefresh')
		$btnExternal = $dlg.FindName('BtnOpenExternal')
		$cmbLogLevelFilter = $dlg.FindName('CmbLogLevelFilter')
		$txtLogSearch = $dlg.FindName('TxtLogSearch')

		$btnClose.Content = $closeLabel
		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
		Set-ButtonChrome -Button $btnRefresh -Variant 'Subtle' -Compact -Muted
		Set-ButtonChrome -Button $btnExternal -Variant 'Subtle' -Compact -Muted
		$btnClose.IsCancel = $true

		$txtLogPath.Text = $LogPath
		$logBg = if ($theme.ContainsKey('LogBg') -and -not [string]::IsNullOrWhiteSpace([string]$theme.LogBg)) { [string]$theme.LogBg } else { [string]$theme.SearchBg }
		if ($logScroll)
		{
			$logScroll.Background = $bc.ConvertFromString($logBg)
		}

		$colorRules = @(
			@{ Pattern = '- success[!]?$';          Color = $(if ($theme.ContainsKey('LogSuccess')) { $theme.LogSuccess } else { $theme.LowRiskBadge }) }
			@{ Pattern = '- failed[!]?$';           Color = $(if ($theme.ContainsKey('LogError')) { $theme.LogError } else { $theme.RiskHighBadge }) }
			@{ Pattern = '- skipped[.]?$';          Color = $(if ($theme.ContainsKey('LogWarning')) { $theme.LogWarning } else { $theme.RiskMediumBadge }) }
			@{ Pattern = '- already applied[.]?$';  Color = $(if ($theme.ContainsKey('LogInfo')) { $theme.LogInfo } else { $theme.AccentBlue }) }
			@{ Pattern = '\bERROR\b|\bFAIL\b';      Color = $(if ($theme.ContainsKey('LogError')) { $theme.LogError } else { $theme.RiskHighBadge }) }
			@{ Pattern = '\bWARN\b|\bWARNING\b';    Color = $(if ($theme.ContainsKey('LogWarning')) { $theme.LogWarning } else { $theme.RiskMediumBadge }) }
			@{ Pattern = '\bDEBUG:';               Color = $(if ($theme.ContainsKey('LogDebug')) { $theme.LogDebug } else { $theme.TextMuted }) }
			@{ Pattern = '^={3}';                   Color = $(if ($theme.ContainsKey('LogInfo')) { $theme.LogInfo } else { $theme.AccentBlue }) }
		)
		$getLogSeverity = {
			param([string]$Line)
			if ($Line -match '\bERROR\b|\bFAIL\b|- failed[!]?$') { return 'Errors' }
			if ($Line -match '\bWARN\b|\bWARNING\b|- skipped[.]?$') { return 'Warnings' }
			if ($Line -match '\bDEBUG:') { return 'Debug' }
			if ($Line -match '- success[!]?$') { return 'Success' }
			return 'Info'
		}

		$uiDensityTokens = if (Get-Command -Name 'Get-BaselineUiDensityTokens' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineUiDensityTokens } else { $null }
		$logFontSizeLabel = if ($uiDensityTokens) { [double]$uiDensityTokens.LabelFontSize } else { $Script:GuiLayout.FontSizeLabel }
		$logFontSizeSubheading = if ($uiDensityTokens) { [double]$uiDensityTokens.NameFontSize } else { $Script:GuiLayout.FontSizeSubheading }
		$logLineHeight = if ($uiDensityTokens) { [double]$uiDensityTokens.LabelLineHeight } else { 16 }
		$logRowMargin = switch ($(if ($uiDensityTokens) { [string]$uiDensityTokens.Density } else { 'Comfort' }))
		{
			'High' { [System.Windows.Thickness]::new(0, 0, 0, 0); break }
			'Compact' { [System.Windows.Thickness]::new(0, 1, 0, 0); break }
			default { [System.Windows.Thickness]::new(0, 2, 0, 2) }
		}
		$logIconMargin = switch ($(if ($uiDensityTokens) { [string]$uiDensityTokens.Density } else { 'Comfort' }))
		{
			'High' { [System.Windows.Thickness]::new(0, 0, 4, 0); break }
			'Compact' { [System.Windows.Thickness]::new(0, 1, 5, 0); break }
			default { [System.Windows.Thickness]::new(0, 1, 6, 0) }
		}
		$loadLogContent = {
			$logPanel.Children.Clear()

			if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue))
			{
				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = (& $getBaselineBilingualString -Key 'GuiActionLogNotFound' -Fallback "Log file not found.`n{0}" -FormatArgs @($LogPath))
				$tb.FontSize = $logFontSizeSubheading
				$tb.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
				[void]($logPanel.Children.Add($tb))
				return
			}

			try
			{
				$lines = [System.IO.File]::ReadAllLines($LogPath)
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.Show-LogDialog:catch1191' -Severity Debug }

				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = "Failed to read log file: $($_.Exception.Message)"
				$tb.FontSize = $logFontSizeSubheading
				$tb.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
				[void]($logPanel.Children.Add($tb))
				return
			}

			$selectedFilter = 'All'
			if ($cmbLogLevelFilter -and $cmbLogLevelFilter.SelectedItem)
			{
				$selectedFilter = [string]$cmbLogLevelFilter.SelectedItem.Content
			}
			$searchText = if ($txtLogSearch) { [string]$txtLogSearch.Text } else { '' }
			$searchText = $searchText.Trim()

			foreach ($line in $lines)
			{
				$severity = & $getLogSeverity $line
				if ($selectedFilter -ne $filterAllLabel)
				{
					if ($selectedFilter -eq $filterErrorsLabel -and $severity -ne 'Errors') { continue }
					if ($selectedFilter -eq $filterWarningsLabel -and $severity -ne 'Warnings') { continue }
					if ($selectedFilter -eq $filterInfoLabel -and $severity -ne 'Info') { continue }
					if ($selectedFilter -eq $filterDebugLabel -and $severity -ne 'Debug') { continue }
					if ($selectedFilter -eq $filterSuccessLabel -and $severity -ne 'Success') { continue }
				}
				if (-not [string]::IsNullOrWhiteSpace($searchText) -and $line.IndexOf($searchText, [System.StringComparison]::OrdinalIgnoreCase) -lt 0)
				{
					continue
				}

				$color = $theme.TextSecondary
				foreach ($rule in $colorRules)
				{
					if ($line -match $rule.Pattern)
					{
						$color = $rule.Color
						break
					}
				}

				$row = [System.Windows.Controls.Grid]::new()
				$colIcon = [System.Windows.Controls.ColumnDefinition]::new()
				$colIcon.Width = [System.Windows.GridLength]::Auto
				$colText = [System.Windows.Controls.ColumnDefinition]::new()
				$colText.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				[void]$row.ColumnDefinitions.Add($colIcon)
				[void]$row.ColumnDefinitions.Add($colText)
				$row.Margin = $logRowMargin

				$icon = [System.Windows.Controls.TextBlock]::new()
				$icon.Text = [char]0xF4F5
				$icon.FontFamily = [System.Windows.Media.FontFamily]::new('FluentSystemIcons')
				$icon.FontSize = $logFontSizeLabel
				$icon.Foreground = $bc.ConvertFromString($color)
				$icon.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
				$icon.Margin = $logIconMargin
				[System.Windows.Controls.Grid]::SetColumn($icon, 0)

				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = $line
				$tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas, Courier New')
				$tb.FontSize = $logFontSizeLabel
				$tb.LineHeight = $logLineHeight
				$tb.LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
				$tb.Foreground = $bc.ConvertFromString($color)
				$tb.TextWrapping = [System.Windows.TextWrapping]::NoWrap
				$tb.Margin = [System.Windows.Thickness]::new(0)
				[System.Windows.Controls.Grid]::SetColumn($tb, 1)

				[void]$row.Children.Add($icon)
				[void]$row.Children.Add($tb)
				[void]($logPanel.Children.Add($row))
			}

			$logScroll.ScrollToEnd()
		}.GetNewClosure()

		& $loadLogContent

		Register-GuiEventHandler -Source $btnClose -EventName 'Click' -Handler { $dlg.Close() }
		Register-GuiEventHandler -Source $btnRefresh -EventName 'Click' -Handler ({
			& $loadLogContent
			$txtLogPath.Text = $LogPath
		}.GetNewClosure())
		if ($cmbLogLevelFilter)
		{
			Register-GuiEventHandler -Source $cmbLogLevelFilter -EventName 'SelectionChanged' -Handler ({
				& $loadLogContent
			}.GetNewClosure())
		}
		if ($txtLogSearch)
		{
			Register-GuiEventHandler -Source $txtLogSearch -EventName 'TextChanged' -Handler ({
				& $loadLogContent
			}.GetNewClosure())
		}
		Register-GuiEventHandler -Source $btnExternal -EventName 'Click' -Handler ({
			if ($LogPath -and (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue))
			{
				[void](Invoke-UserLaunch -FilePath 'notepad.exe' -ArgumentList @($LogPath) -Description 'Baseline log file')
			}
		}.GetNewClosure())
		Register-GuiEventHandler -Source $dlg -EventName 'KeyDown' -Handler {
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		}

		[void]($dlg.ShowDialog())
	}

	<#
	    .SYNOPSIS
	#>

	function Show-ChangelogDialog
	{
		param (
			[string]$ChangelogPath = $(Resolve-BaselineChangelogPath)
		)

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DialogHelpers-ChangelogViewer'
		$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme $theme
		$changelogTitle = Get-UxLocalizedString -Key 'GuiMenuHelpChangelog' -Fallback 'Changelog'
		$refreshLabel = Get-UxLocalizedString -Key 'GuiRefreshButton' -Fallback 'Refresh'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$missingMessage = Get-UxLocalizedString -Key 'GuiMenuHelpChangelogMissing' -Fallback 'Changelog file not found.'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$changelogTitle"
	Width="$($Script:GuiLayout.LogDialogWidth)" Height="$($Script:GuiLayout.LogDialogHeight)"
	MinWidth="$($Script:GuiLayout.LogDialogMinWidth)" MinHeight="$($Script:GuiLayout.LogDialogMinHeight)"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8">
	<Border.Resources>
		$scrollBarStyleXaml
	</Border.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
			<Grid>
				<TextBlock Text="$changelogTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
				<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
					Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
					HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
			</Grid>
		</Border>

		<Border Grid.Row="1" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0">
					<TextBlock Text="$changelogTitle" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtChangelogPath" FontSize="11"
							   Foreground="$($theme.TextMuted)" Margin="0,2,0,0"
							   TextWrapping="Wrap"/>
				</StackPanel>
				<Button Name="BtnRefresh" Grid.Column="1" Content="$refreshLabel"
						Padding="12,5" FontSize="12" VerticalAlignment="Center"/>
			</Grid>
		</Border>

		<Border Grid.Row="2" Background="$($theme.SearchBg)" Padding="16,12,16,12">
			<TextBox Name="TxtChangelogContent"
					 IsReadOnly="True"
					 AcceptsReturn="True"
					 AcceptsTab="True"
					 TextWrapping="Wrap"
					 VerticalScrollBarVisibility="Auto"
					 HorizontalScrollBarVisibility="Disabled"
					 Background="Transparent"
					 BorderThickness="0"
					 Foreground="$($theme.TextSecondary)"
					 FontFamily="Consolas"
					 FontSize="$($Script:GuiLayout.FontSizeLabel)"/>
		</Border>

		<Border Grid.Row="3" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Button Name="BtnClose" Content=""
						HorizontalAlignment="Right"
						Padding="20,6" FontSize="13"/>
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

		try
		{
			[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Show-ChangelogDialog.SetGuiWindowChromeTheme'
		}

		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		$txtChangelogPath = $dlg.FindName('TxtChangelogPath')
		$txtChangelogContent = $dlg.FindName('TxtChangelogContent')
		$btnRefresh = $dlg.FindName('BtnRefresh')
		$btnClose = $dlg.FindName('BtnClose')

		if ($dlgTitleBar)
		{
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
			$dlgCtx = New-Object System.Windows.Controls.ContextMenu
			$dlgCtxClose = New-Object System.Windows.Controls.MenuItem
			$dlgCtxClose.Header = $closeLabel
			$dlgCtxClose.InputGestureText = 'Alt+F4'
			$dlgCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
			$dlgRefForContext = $dlg
			$dlgCtxClose.Add_Click({ $dlgRefForContext.Close() }.GetNewClosure())
			[void]$dlgCtx.Items.Add($dlgCtxClose)
			$dlgTitleBar.ContextMenu = $dlgCtx
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$btnClose.Content = $closeLabel
		Set-ButtonChrome -Button $btnRefresh -Variant 'Subtle' -Compact -Muted
		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
		$btnClose.IsCancel = $true

		$resolveCurrentChangelogVersion = {
			try
			{
				$versionCmd = Get-Command -Name 'Get-BaselineDisplayVersion' -CommandType Function -ErrorAction SilentlyContinue
				if ($versionCmd)
				{
					$displayVersion = & $versionCmd
					return (Resolve-BaselineChangelogVersionLabel -DisplayVersion ([string]$displayVersion))
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Show-ChangelogDialog.ResolveCurrentChangelogVersion' }
			return $null
		}

		$extractChangelogVersionSection = {
			param (
				[string]$Raw,
				[string]$Version
			)
			return (Select-BaselineChangelogVersionSection -Raw $Raw -Version $Version)
		}

		$loadChangelogContent = {
			$resolvedPath = if ([string]::IsNullOrWhiteSpace([string]$ChangelogPath)) { Resolve-BaselineChangelogPath } else { $ChangelogPath }
			$txtChangelogPath.Text = if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) { '' } else { $resolvedPath }

			if ([string]::IsNullOrWhiteSpace([string]$resolvedPath) -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf -ErrorAction SilentlyContinue))
			{
				$txtChangelogContent.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$txtChangelogContent.Text = if ([string]::IsNullOrWhiteSpace([string]$resolvedPath))
				{
					$missingMessage
				}
				else
				{
					"{0}`r`n`r`n{1}" -f $missingMessage, $resolvedPath
				}
				return
			}

			try
			{
				$resolvedFullPath = [System.IO.Path]::GetFullPath($resolvedPath)
				$txtChangelogPath.Text = $resolvedFullPath
				$txtChangelogContent.Foreground = $bc.ConvertFromString($theme.TextSecondary)
				$rawContent = [System.IO.File]::ReadAllText($resolvedFullPath)
				$currentVersion = & $resolveCurrentChangelogVersion
				$displayContent = if (-not [string]::IsNullOrWhiteSpace([string]$currentVersion))
				{
					& $extractChangelogVersionSection -Raw $rawContent -Version $currentVersion
				}
				else
				{
					$rawContent
				}
				$txtChangelogContent.Text = $displayContent
				$txtChangelogContent.ScrollToHome()
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.Show-ChangelogDialog:catch1514' -Severity Debug }

				$txtChangelogContent.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$txtChangelogContent.Text = "Failed to read changelog.`r`n`r`n$($_.Exception.Message)"
			}
		}.GetNewClosure()

		& $loadChangelogContent

		Register-GuiEventHandler -Source $btnRefresh -EventName 'Click' -Handler ({
			$ChangelogPath = Resolve-BaselineChangelogPath
			& $loadChangelogContent
		}.GetNewClosure())
		Register-GuiEventHandler -Source $btnClose -EventName 'Click' -Handler { $dlg.Close() }
		Register-GuiEventHandler -Source $dlg -EventName 'KeyDown' -Handler {
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		}

		[void]($dlg.ShowDialog())
	}

	<#
	    .SYNOPSIS
	#>

	function Show-ReadmeDialog
	{
		param (
			[string]$ReadmePath
		)

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DialogHelpers-ReadmeViewer'
		$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme $theme
		$readmeTitle = Get-UxLocalizedString -Key 'GuiMenuHelpReadme' -Fallback 'Readme'
		$readmeFontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
		$refreshLabel = Get-UxLocalizedString -Key 'GuiRefreshButton' -Fallback 'Refresh'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$missingMessage = Get-UxLocalizedString -Key 'GuiMenuHelpReadmeMissing' -Fallback 'README.md file not found.'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	xmlns:wfi="clr-namespace:System.Windows.Forms.Integration;assembly=WindowsFormsIntegration"
	Title="$readmeTitle"
	Width="$($Script:GuiLayout.LogDialogWidth)" Height="$($Script:GuiLayout.LogDialogHeight)"
	MinWidth="$($Script:GuiLayout.LogDialogMinWidth)" MinHeight="$($Script:GuiLayout.LogDialogMinHeight)"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8">
	<Border.Resources>
		$scrollBarStyleXaml
	</Border.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
			<Grid>
				<TextBlock Name="TxtDlgTitle" Text="$readmeTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
				<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
					Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
					HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
			</Grid>
		</Border>

		<Border Name="ReadmeHeaderBorder" Grid.Row="1" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0">
					<TextBlock Name="TxtReadmeTitle" Text="$readmeTitle" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtReadmePath" FontSize="11"
							   Foreground="$($theme.TextMuted)" Margin="0,2,0,0"
							   TextWrapping="Wrap"/>
				</StackPanel>
				<Button Name="BtnRefresh" Grid.Column="1" Content="$refreshLabel"
						Padding="12,5" FontSize="12" VerticalAlignment="Center"/>
			</Grid>
		</Border>

		<Border Name="ReadmeContentBorder" Grid.Row="2" Background="$($theme.SearchBg)" Padding="16,12,16,12">
			<Grid>
				<wfi:WindowsFormsHost Name="ReadmeWebHost" Visibility="Collapsed"/>
				<FlowDocumentScrollViewer Name="ReadmeFlowViewer"
										  IsToolBarVisible="False"
										  Background="Transparent"
										  BorderThickness="0"
										  VerticalScrollBarVisibility="Auto"
										  HorizontalScrollBarVisibility="Disabled"
										  Visibility="Visible"/>
			</Grid>
		</Border>

		<Border Name="ReadmeFooterBorder" Grid.Row="3" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Button Name="BtnClose" Content=""
						HorizontalAlignment="Right"
						Padding="20,6" FontSize="13"/>
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
		$txtDlgTitle = $dlg.FindName('TxtDlgTitle')
		$readmeHeaderBorder = $dlg.FindName('ReadmeHeaderBorder')
		$txtReadmeTitle = $dlg.FindName('TxtReadmeTitle')
		$txtReadmePath = $dlg.FindName('TxtReadmePath')
		$txtReadmeContent = $null
		$readmeContentBorder = $dlg.FindName('ReadmeContentBorder')
		$readmeWebHost = $dlg.FindName('ReadmeWebHost')
		$readmeFlowViewer = $dlg.FindName('ReadmeFlowViewer')
		$readmeFooterBorder = $dlg.FindName('ReadmeFooterBorder')
		$btnRefresh = $dlg.FindName('BtnRefresh')
		$btnClose = $dlg.FindName('BtnClose')

		if ($dlgTitleBar)
		{
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
			$dlgCtx = New-Object System.Windows.Controls.ContextMenu
			$dlgCtxClose = New-Object System.Windows.Controls.MenuItem
			$dlgCtxClose.Header = $closeLabel
			$dlgCtxClose.InputGestureText = 'Alt+F4'
			$dlgCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
			$dlgCtxClose.Add_Click({ $dlg.Close() }.GetNewClosure())
			[void]$dlgCtx.Items.Add($dlgCtxClose)
			$dlgTitleBar.ContextMenu = $dlgCtx
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$btnClose.Content = $closeLabel
		if ($Script:SetButtonChromeScript)
		{
			& $Script:SetButtonChromeScript -Button $btnRefresh -Variant 'Subtle' -Compact -Muted
			& $Script:SetButtonChromeScript -Button $btnClose -Variant 'Primary' -Compact
		}
		$btnClose.IsCancel = $true

		if ([string]::IsNullOrWhiteSpace([string]$ReadmePath))
		{
			try { $ReadmePath = Resolve-BaselineReadmePath } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.Show-ReadmeDialog:catch1690' -Severity Debug }
			 $ReadmePath = $null }
		}

		$getReadmeTheme = {
			param([hashtable]$ThemeOverride = $null)

			if ($ThemeOverride -and ($ThemeOverride -is [System.Collections.IDictionary]) -and $ThemeOverride.Count -gt 0)
			{
				return $ThemeOverride
			}

			if (Test-Path -Path Variable:\Script:CurrentTheme)
			{
				return $Script:CurrentTheme
			}

			return $theme
		}.GetNewClosure()

		$applyReadmeDialogTheme = {
			param([hashtable]$ThemeOverride = $null)

			$activeTheme = & $getReadmeTheme -ThemeOverride $ThemeOverride

			if ($rootBorder)
			{
				$rootBorder.Background = $bc.ConvertFromString($activeTheme.WindowBg)
				$rootBorder.BorderBrush = $bc.ConvertFromString($activeTheme.BorderColor)
				$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
			}
			if ($dlgTitleBar)
			{
				$dlgTitleBar.Background = $bc.ConvertFromString($activeTheme.HeaderBg)
			}
			if ($txtDlgTitle)
			{
				$txtDlgTitle.Foreground = $bc.ConvertFromString($activeTheme.TextPrimary)
			}
			if ($btnDlgClose)
			{
				$btnDlgClose.Background = [System.Windows.Media.Brushes]::Transparent
				$btnDlgClose.Foreground = $bc.ConvertFromString($activeTheme.TextPrimary)
			}
			if ($readmeHeaderBorder)
			{
				$readmeHeaderBorder.Background = $bc.ConvertFromString($activeTheme.HeaderBg)
				$readmeHeaderBorder.BorderBrush = $bc.ConvertFromString($activeTheme.BorderColor)
				$readmeHeaderBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
			}
			if ($txtReadmeTitle)
			{
				$txtReadmeTitle.Foreground = $bc.ConvertFromString($activeTheme.TextPrimary)
			}
			if ($txtReadmePath)
			{
				$txtReadmePath.Foreground = $bc.ConvertFromString($activeTheme.TextMuted)
			}
			if ($readmeContentBorder)
			{
				$readmeContentBorder.Background = $bc.ConvertFromString($activeTheme.SearchBg)
			}
			if ($readmeFlowViewer)
			{
				$readmeFlowViewer.Background = $bc.ConvertFromString($activeTheme.SearchBg)
			}
			if ($readmeFooterBorder)
			{
				$readmeFooterBorder.Background = $bc.ConvertFromString($activeTheme.HeaderBg)
				$readmeFooterBorder.BorderBrush = $bc.ConvertFromString($activeTheme.BorderColor)
				$readmeFooterBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
			}
			if ($btnRefresh -and $Script:SetButtonChromeScript)
			{
				& $Script:SetButtonChromeScript -Button $btnRefresh -Variant 'Subtle' -Compact -Muted
			}
			if ($btnClose -and $Script:SetButtonChromeScript)
			{
				& $Script:SetButtonChromeScript -Button $btnClose -Variant 'Primary' -Compact
			}
		}.GetNewClosure()

		# Force the rendered markdown's foreground/opacity back to theme values.
		# Without this, Markdig.Wpf can emit block-level brushes (or residual
		# opacity) from its default stylesheet that render as unreadable washed
		# text against the dialog surface. Applied after every render and
		# rerun when the popup theme registry repaints an open README window.
		$setMarkdownViewerTheme = {
			param(
				[System.Windows.Controls.FlowDocumentScrollViewer]$Viewer,
				[string]$ForegroundHex,
				[hashtable]$ThemeOverride = $null
			)

			if (-not $Viewer) { return }
			$activeTheme = & $getReadmeTheme -ThemeOverride $ThemeOverride
			$Viewer.Background = $bc.ConvertFromString($activeTheme.SearchBg)
			if (-not $Viewer.Document) { return }

			$foregroundBrush = $bc.ConvertFromString($ForegroundHex)
			$Viewer.Document.Foreground = $foregroundBrush

			foreach ($block in $Viewer.Document.Blocks)
			{
				try
				{
					$block.Foreground = $foregroundBrush
					$block.Opacity    = 1.0
				}
				catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.Show-ReadmeDialog.ApplyBlockFormatting' }
			}
		}.GetNewClosure()

		$showReadmeAsText = {
			param(
				[string]$Content,
				[string]$ForegroundHex,
				[hashtable]$ThemeOverride = $null
			)
			$paragraph = [System.Windows.Documents.Paragraph]::new()
			$paragraph.Margin = [System.Windows.Thickness]::new(0)
			$run = [System.Windows.Documents.Run]::new($Content)
			$run.Foreground = $bc.ConvertFromString($ForegroundHex)
			$paragraph.Inlines.Add($run) | Out-Null
			$document = [System.Windows.Documents.FlowDocument]::new()
			$document.Background = [System.Windows.Media.Brushes]::Transparent
			$document.Foreground = $bc.ConvertFromString($ForegroundHex)
			$document.PagePadding = [System.Windows.Thickness]::new(0)
			$document.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			$document.FontSize = [double]$readmeFontSize
			$document.Blocks.Add($paragraph) | Out-Null
			$readmeFlowViewer.Document = $document
			$readmeFlowViewer.Visibility = [System.Windows.Visibility]::Visible
			if ($readmeWebHost) { $readmeWebHost.Visibility = [System.Windows.Visibility]::Collapsed }
			& $setMarkdownViewerTheme -Viewer $readmeFlowViewer -ForegroundHex $ForegroundHex -ThemeOverride $ThemeOverride
		}.GetNewClosure()

		$setReadmeFlowThemeScript = ${function:Set-BaselineReadmeFlowDocumentTheme}
		$resolveReadmePathScript = ${function:Resolve-BaselineReadmePath}

		$showReadmeAsFlowDocument = {
			param(
				[System.Windows.Documents.FlowDocument]$Document,
				[hashtable]$ThemeOverride = $null
			)
			$activeTheme = & $getReadmeTheme -ThemeOverride $ThemeOverride
			$Document.Background = [System.Windows.Media.Brushes]::Transparent
			$Document.Foreground = $bc.ConvertFromString($activeTheme.TextPrimary)
			$Document.PagePadding = [System.Windows.Thickness]::new(0)
			$Document.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			$Document.FontSize = [double]$readmeFontSize
			& $setReadmeFlowThemeScript -Document $Document -ActiveTheme $activeTheme -BrushConverter $bc -ReadmeFontSize $readmeFontSize
			$readmeFlowViewer.Document = $Document
			$readmeFlowViewer.Visibility = [System.Windows.Visibility]::Visible
			if ($readmeWebHost) { $readmeWebHost.Visibility = [System.Windows.Visibility]::Collapsed }
			& $setMarkdownViewerTheme -Viewer $readmeFlowViewer -ForegroundHex $activeTheme.TextPrimary -ThemeOverride $activeTheme
		}.GetNewClosure()

		$webView2Ready = $false
		$readmeWebView = $null
		. (Join-Path $PSScriptRoot 'ContentDialogs\Show-ReadmeDialog\Show-ReadmeDialog.ps1')

		$readmeThemeCallback = {
			param(
				[System.Windows.Window]$Window,
				[hashtable]$Theme,
				[object]$UseDarkMode
			)

			$null = $Window
			$null = $UseDarkMode
			& $loadReadmeContent -ThemeOverride $Theme
		}.GetNewClosure()

		[void](GUICommon\Register-GuiPopupThemeWindow -Window $dlg -ThemeCallback $readmeThemeCallback)
		& $loadReadmeContent

		Register-GuiEventHandler -Source $btnRefresh -EventName 'Click' -Handler ({
			$ReadmePath = & $resolveReadmePathScript
			& $loadReadmeContent
		}.GetNewClosure())
		Register-GuiEventHandler -Source $btnClose -EventName 'Click' -Handler { $dlg.Close() }
		Register-GuiEventHandler -Source $dlg -EventName 'KeyDown' -Handler {
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		}

		[void](GUICommon\Show-GuiActivatedDialog -Window $dlg)
	}

	<#
	    .SYNOPSIS
	#>

	function Show-GuidedSetupWizard
	{
		param (
			[object]$ShowThemedDialogCapture,
			[scriptblock]$SetGuiPresetSelectionAction,
			[scriptblock]$SetGuiStatusTextAction,
			[hashtable]$Theme,
			[scriptblock]$ApplyButtonChrome,
			[object]$OwnerWindow,
			[object]$UseDarkMode = $true
		)

		$resolvedUseDarkMode = GUICommon\Get-GuiBooleanValue -Value $UseDarkMode -Default $(if (Test-Path -Path Variable:\Script:CurrentThemeName) { $Script:CurrentThemeName -eq 'Dark' } else { $true }) -Context 'Show-GuidedSetupWizard'

		# -- Step 1: Goal selection -----------------------------------------------
		$privacyLabel     = Get-UxLocalizedString -Key 'GuiGuidedGoalPrivacy'    -Fallback 'Privacy first'
		$performanceLabel = Get-UxLocalizedString -Key 'GuiGuidedGoalPerformance' -Fallback 'Performance first'
		$balancedLabel    = Get-UxLocalizedString -Key 'GuiGuidedGoalBalanced'   -Fallback 'Balanced'
		$cancelLabel      = Get-UxLocalizedString -Key 'GuiCloseButton'          -Fallback 'Close'
		$step1Title       = Get-UxLocalizedString -Key 'GuiGuidedStep1Title'     -Fallback 'Guided Setup - Step 1 of 2'
		$step1Message     = Get-UxLocalizedString -Key 'GuiGuidedStep1Message'   -Fallback "What is your main goal?`n`n- Privacy first - disable telemetry, advertising IDs, activity tracking, and data collection`n- Performance first - tune system responsiveness, visual effects, and background services`n- Balanced - a broad selection covering privacy, performance, and quality-of-life improvements"

		$goalChoice = & $ShowThemedDialogCapture `
			-Title $step1Title `
			-Message $step1Message `
			-Buttons @($cancelLabel, $privacyLabel, $performanceLabel, $balancedLabel) `
			-AccentButton $balancedLabel `
			-Theme $Theme `
			-ApplyButtonChrome $ApplyButtonChrome `
			-OwnerWindow $OwnerWindow `
			-UseDarkMode $resolvedUseDarkMode

		if ([string]::IsNullOrWhiteSpace([string]$goalChoice) -or [string]$goalChoice -eq $cancelLabel)
		{
			return
		}

		# Map goal -> preset and impact description
		$presetName = switch ([string]$goalChoice)
		{
			{ $_ -eq $privacyLabel }     { 'Minimal' }
			{ $_ -eq $performanceLabel } { 'Basic'   }
			default                      { 'Basic'   }
		}

		$impactLines = switch ([string]$goalChoice)
		{
			{ $_ -eq $privacyLabel } {
				Get-UxLocalizedString -Key 'GuiGuidedImpactPrivacy' -Fallback "The Minimal preset will be loaded.`n`n- Disables telemetry and diagnostic data collection`n- Removes advertising ID and activity history`n- Turns off location tracking and app launch tracking`n- Low risk - all changes are reversible`n`nCategories touched: Privacy & Telemetry, Initial Setup"
			}
			{ $_ -eq $performanceLabel } {
				Get-UxLocalizedString -Key 'GuiGuidedImpactPerformance' -Fallback "The Basic preset will be loaded.`n`n- Includes all privacy tweaks from Minimal`n- Tunes visual effects and background services`n- Reduces startup overhead and notification noise`n- Low-to-medium risk - most changes are reversible`n`nCategories touched: Privacy & Telemetry, System, UI & Personalization"
			}
			default {
				Get-UxLocalizedString -Key 'GuiGuidedImpactBalanced' -Fallback "The Basic preset will be loaded.`n`n- Covers privacy, performance, and quality-of-life improvements`n- Broader selection than Privacy first, safer than Advanced`n- Low-to-medium risk - most changes are reversible`n`nCategories touched: Privacy & Telemetry, System, UI & Personalization, Initial Setup"
			}
		}

		# -- Step 2: Impact summary -----------------------------------------------
		$backLabel  = Get-UxLocalizedString -Key 'GuiGuidedBack'       -Fallback '<- Back'
		$applyLabel = Get-UxLocalizedString -Key 'GuiGuidedLoadPreset' -Fallback 'Load preset'
		$step2Title = Get-UxLocalizedString -Key 'GuiGuidedStep2Title' -Fallback 'Guided Setup - Step 2 of 2'

		$impactChoice = & $ShowThemedDialogCapture `
			-Title $step2Title `
			-Message $impactLines `
			-Buttons @($cancelLabel, $backLabel, $applyLabel) `
			-AccentButton $applyLabel `
			-Theme $Theme `
			-ApplyButtonChrome $ApplyButtonChrome `
			-OwnerWindow $OwnerWindow `
			-UseDarkMode $resolvedUseDarkMode

		if ([string]$impactChoice -eq $backLabel)
		{
			Show-GuidedSetupWizard `
				-ShowThemedDialogCapture $ShowThemedDialogCapture `
				-SetGuiPresetSelectionAction $SetGuiPresetSelectionAction `
				-SetGuiStatusTextAction $SetGuiStatusTextAction `
				-Theme $Theme `
				-ApplyButtonChrome $ApplyButtonChrome `
				-OwnerWindow $OwnerWindow `
				-UseDarkMode $resolvedUseDarkMode
			return
		}

		if ([string]::IsNullOrWhiteSpace([string]$impactChoice) -or [string]$impactChoice -eq $cancelLabel)
		{
			return
		}

		# -- Step 3: Load preset ---------------------------------------------------
		if ($SetGuiPresetSelectionAction)
		{
			& $SetGuiPresetSelectionAction -PresetName $presetName
		}

		if ($SetGuiStatusTextAction)
		{
			$statusText = Get-UxPresetLoadedStatusText -PresetName $presetName
			& $SetGuiStatusTextAction -Text $statusText -Tone 'accent'
		}
	}

