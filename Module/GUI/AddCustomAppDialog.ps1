# AddCustomAppDialog.ps1
#
# Themed WPF form for adding a user-defined external software entry.
# Lets the user supply Name / SubCategory / WinGetId / ChocoId / Description,
# validates via Test-BaselineUserAppEntry, and persists the entry as JSON
# under Get-BaselineUserAppsDirectory. Get-BaselineApplicationsCatalog -Force
# picks the new file up on the next refresh.
#
# Public surface:
#   * Show-GuiAddCustomAppDialog
#       Returns @{ Cancelled = [bool]; Saved = [bool]; Path = [string]; Entry = [pscustomobject] }
#       Cancelled=$true when the user closes via Cancel / Esc / X.
#       Saved=$true when validation passed and the JSON file was written.

function Get-BaselineUserAppFileName
{
	<#
		.SYNOPSIS
		Sanitizes a user-supplied app name into a safe JSON filename
		under Get-BaselineUserAppsDirectory.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ([Parameter(Mandatory)][string]$Name)

	$invalid = [System.IO.Path]::GetInvalidFileNameChars()
	$builder = New-Object System.Text.StringBuilder
	foreach ($ch in $Name.ToCharArray())
	{
		if ($invalid -contains $ch -or $ch -eq ' ') { [void]$builder.Append('_') }
		else { [void]$builder.Append($ch) }
	}
	$slug = $builder.ToString().Trim('_')
	if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'custom-app' }
	return ($slug + '.json')
}

function Save-BaselineUserAppEntry
{
	<#
		.SYNOPSIS
		Writes a validated user-app entry to disk under
		Get-BaselineUserAppsDirectory as a single-entry catalog file.

		.DESCRIPTION
		Creates the user-apps directory if missing, picks a non-colliding
		filename derived from the entry's Name (suffixes -2, -3, ... when
		the slug already exists), and writes the file via
		[System.IO.File]::WriteAllText with UTF-8 (no BOM). Returns the
		written path.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)][object]$Entry,
		[string]$Directory
	)

	if ([string]::IsNullOrWhiteSpace($Directory))
	{
		$Directory = Get-BaselineUserAppsDirectory
	}
	if (-not (Test-Path -LiteralPath $Directory))
	{
		[void](New-Item -Path $Directory -ItemType Directory -Force)
	}

	$baseName = Get-BaselineUserAppFileName -Name ([string]$Entry.Name)
	$candidate = Join-Path -Path $Directory -ChildPath $baseName
	if (Test-Path -LiteralPath $candidate)
	{
		$stem = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
		$ext = [System.IO.Path]::GetExtension($baseName)
		$suffix = 2
		do
		{
			$candidate = Join-Path -Path $Directory -ChildPath ('{0}-{1}{2}' -f $stem, $suffix, $ext)
			$suffix++
		}
		while ((Test-Path -LiteralPath $candidate) -and $suffix -lt 1000)
	}

	$payload = [pscustomobject]@{
		Tab     = 'Applications'
		Entries = @($Entry)
	}
	$json = $payload | ConvertTo-Json -Depth 6
	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	[System.IO.File]::WriteAllText($candidate, $json, $utf8NoBom)
	return $candidate
}

function Show-GuiAddCustomAppDialog
{
	<#
		.SYNOPSIS
		Themed WPF dialog for adding a user-defined external software entry.

		.DESCRIPTION
		Gathers Name / SubCategory / WinGetId / ChocoId / Description, runs
		Test-BaselineUserAppEntry, and on success writes the entry to disk
		via Save-BaselineUserAppEntry. Returns a result hashtable carrying
		Cancelled / Saved / Path / Entry so the caller can refresh the
		catalog and surface the new entry.

		Headless harness fallback: when $Script:CurrentTheme is not set the
		dialog short-circuits and returns Cancelled=$true so automated
		callers can exercise the wiring without a WPF host.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	if (-not $Script:CurrentTheme)
	{
		return @{ Cancelled = $true; Saved = $false; Path = $null; Entry = $null }
	}

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'AddCustomAppDialog'

	$titleText       = Get-UxLocalizedString -Key 'GuiAddCustomAppTitle'        -Fallback 'Add custom app'
	$subtitleText    = Get-UxLocalizedString -Key 'GuiAddCustomAppSubtitle'     -Fallback 'Define a user-added entry for the External Software tab. At least one of WinGet ID or Chocolatey ID is required.'
	$nameLabel       = Get-UxLocalizedString -Key 'GuiAddCustomAppName'         -Fallback 'Name'
	$subCatLabel     = Get-UxLocalizedString -Key 'GuiAddCustomAppSubCategory'  -Fallback 'SubCategory'
	$wingetLabel     = Get-UxLocalizedString -Key 'GuiAddCustomAppWinGetId'     -Fallback 'WinGet ID'
	$chocoLabel      = Get-UxLocalizedString -Key 'GuiAddCustomAppChocoId'      -Fallback 'Chocolatey ID'
	$descriptionLabel = Get-UxLocalizedString -Key 'GuiAddCustomAppDescription' -Fallback 'Description (optional)'
	$saveLabel       = Get-UxLocalizedString -Key 'GuiAddCustomAppSave'         -Fallback 'Save'
	$cancelLabel     = Get-UxLocalizedString -Key 'GuiAddCustomAppCancel'       -Fallback 'Cancel'
	$validationHeading = Get-UxLocalizedString -Key 'GuiAddCustomAppValidationHeading' -Fallback 'Please fix the following:'

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$titleText"
	Width="560" Height="560"
	MinWidth="480" MinHeight="480"
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
					<TextBlock Text="$titleText" FontSize="16" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Text="$subtitleText" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,16,20,8">
				<StackPanel Orientation="Vertical">
					<TextBlock Text="$nameLabel" FontSize="12" Foreground="$($theme.TextSecondary)" Margin="0,0,0,2"/>
					<TextBox Name="TxtAppName" Height="28" FontSize="12" Margin="0,0,0,12"/>

					<TextBlock Text="$subCatLabel" FontSize="12" Foreground="$($theme.TextSecondary)" Margin="0,0,0,2"/>
					<TextBox Name="TxtAppSubCategory" Height="28" FontSize="12" Margin="0,0,0,12"/>

					<TextBlock Text="$wingetLabel" FontSize="12" Foreground="$($theme.TextSecondary)" Margin="0,0,0,2"/>
					<TextBox Name="TxtAppWinGetId" Height="28" FontSize="12" Margin="0,0,0,12"/>

					<TextBlock Text="$chocoLabel" FontSize="12" Foreground="$($theme.TextSecondary)" Margin="0,0,0,2"/>
					<TextBox Name="TxtAppChocoId" Height="28" FontSize="12" Margin="0,0,0,12"/>

					<TextBlock Text="$descriptionLabel" FontSize="12" Foreground="$($theme.TextSecondary)" Margin="0,0,0,2"/>
					<TextBox Name="TxtAppDescription" Height="64" FontSize="12" Margin="0,0,0,12"
						AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
				</StackPanel>
			</ScrollViewer>

			<Border Grid.Row="3" Padding="20,4,20,8" Visibility="Collapsed" Name="ValidationPanel">
				<StackPanel Orientation="Vertical">
					<TextBlock Name="TxtValidationHeading" Text="$validationHeading" FontSize="12" FontWeight="SemiBold" Foreground="#D13438"/>
					<TextBlock Name="TxtValidationErrors" FontSize="11" Foreground="#D13438" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<Border Grid.Row="4" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
						<Button Name="BtnCancel" Content="$cancelLabel" Padding="20,6" FontSize="13" Margin="0,0,8,0"/>
						<Button Name="BtnSave"   Content="$saveLabel"   Padding="20,6" FontSize="13"/>
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
	$txtAppName = $dlg.FindName('TxtAppName')
	$txtAppSubCategory = $dlg.FindName('TxtAppSubCategory')
	$txtAppWinGetId = $dlg.FindName('TxtAppWinGetId')
	$txtAppChocoId = $dlg.FindName('TxtAppChocoId')
	$txtAppDescription = $dlg.FindName('TxtAppDescription')
	$validationPanel = $dlg.FindName('ValidationPanel')
	$txtValidationErrors = $dlg.FindName('TxtValidationErrors')
	$btnSave = $dlg.FindName('BtnSave')
	$btnCancel = $dlg.FindName('BtnCancel')

	if ($dlgTitleBar)
	{
		$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
	}
	if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

	$state = @{
		Cancelled = $true
		Saved     = $false
		Path      = $null
		Entry     = $null
	}

	if ($btnSave)
	{
		$st = $state
		$dlgRef = $dlg
		$nameRef = $txtAppName
		$subRef = $txtAppSubCategory
		$wingetRef = $txtAppWinGetId
		$chocoRef = $txtAppChocoId
		$descRef = $txtAppDescription
		$panelRef = $validationPanel
		$errBlockRef = $txtValidationErrors

		$btnSave.Add_Click({
			$nameValue = if ($nameRef) { [string]$nameRef.Text } else { '' }
			$subValue = if ($subRef) { [string]$subRef.Text } else { '' }
			$wingetValue = if ($wingetRef) { [string]$wingetRef.Text } else { '' }
			$chocoValue = if ($chocoRef) { [string]$chocoRef.Text } else { '' }
			$descValue = if ($descRef) { [string]$descRef.Text } else { '' }

			$extraArgs = [ordered]@{}
			if (-not [string]::IsNullOrWhiteSpace($wingetValue)) { $extraArgs['WinGetId'] = $wingetValue.Trim() }
			if (-not [string]::IsNullOrWhiteSpace($chocoValue)) { $extraArgs['ChocoId'] = $chocoValue.Trim() }

			$entry = [ordered]@{
				Name        = $nameValue.Trim()
				SubCategory = $subValue.Trim()
				Function    = 'AppInstall'
				Risk        = 'Low'
				Safe        = $true
				Source      = 'User'
				ExtraArgs   = [pscustomobject]$extraArgs
			}
			if (-not [string]::IsNullOrWhiteSpace($descValue))
			{
				$entry['Description'] = $descValue.Trim()
			}
			$entryObject = [pscustomobject]$entry

			$validation = Test-BaselineUserAppEntry -Entry $entryObject
			if (-not $validation.IsValid)
			{
				if ($errBlockRef) { $errBlockRef.Text = ($validation.Errors -join [Environment]::NewLine) }
				if ($panelRef) { $panelRef.Visibility = 'Visible' }
				return
			}

			try
			{
				$path = Save-BaselineUserAppEntry -Entry $entryObject
				$st.Cancelled = $false
				$st.Saved = $true
				$st.Path = $path
				$st.Entry = $entryObject
				$dlgRef.Close()
			}
			catch
			{
				$msg = "Failed to write user app file: $($_.Exception.Message)"
				if ($errBlockRef) { $errBlockRef.Text = $msg }
				if ($panelRef) { $panelRef.Visibility = 'Visible' }
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'AddCustomAppDialog.Save'
				}
			}
		}.GetNewClosure())
	}

	if ($btnCancel)
	{
		$dlgRef = $dlg
		$btnCancel.IsCancel = $true
		$btnCancel.Add_Click({ $dlgRef.Close() }.GetNewClosure())
	}

	$dlg.Add_KeyDown({
		$eventArgs = $args[1]
		if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
	})

	[void]($dlg.ShowDialog())

	return @{
		Cancelled = [bool]$state.Cancelled
		Saved     = [bool]$state.Saved
		Path      = $state.Path
		Entry     = $state.Entry
	}
}
