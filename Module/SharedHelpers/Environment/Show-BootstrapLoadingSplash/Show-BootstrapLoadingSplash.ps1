try
	{
		Write-EnvironmentLaunchTrace ('Bootstrap splash helper entered: embedded={0} startUpdatesPulse={1}' -f [System.Environment]::GetEnvironmentVariable('BASELINE_EMBEDDED_HOST'), [bool]$StartUpdatesPulse)
		Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

		# Match the main GUI's startup sizing logic so the splash and the
		# eventual main window hand off at the same physical footprint.
		$guiMinW = 940
		$guiMinH = 660
		try
		{
			$workArea = [System.Windows.SystemParameters]::WorkArea
			$widthRatio = if ($workArea.Width -ge 2560) { 0.55 } elseif ($workArea.Width -ge 1920) { 0.65 } else { 0.85 }
			$targetW = [Math]::Round($workArea.Width * $widthRatio)
			$targetH = [Math]::Round($workArea.Height * 0.85)
			$maxW = [Math]::Min(1400, $workArea.Width)
			$effectiveMinW = [Math]::Min($guiMinW, $workArea.Width)
			$effectiveMinH = [Math]::Min($guiMinH, $workArea.Height)
			$splashWindowWidth  = [int][Math]::Min([Math]::Max($targetW, $effectiveMinW), $maxW)
			$splashWindowHeight = [int][Math]::Min([Math]::Max($targetH, $effectiveMinH), $workArea.Height)
			$splashWindowLeft = [double]($workArea.Left + (([double]$workArea.Width - [double]$splashWindowWidth) / 2.0))
			$splashWindowTop = [double]($workArea.Top + (([double]$workArea.Height - [double]$splashWindowHeight) / 2.0))
			$splashWindowStartupLocation = 'Manual'
			$splashDefaultBounds = [pscustomobject]@{
				Left   = [double]$splashWindowLeft
				Top    = [double]$splashWindowTop
				Width  = [double]$splashWindowWidth
				Height = [double]$splashWindowHeight
			}
			$splashStartupWorkAreaBounds = [pscustomobject]@{
				Left   = [double]$workArea.Left
				Top    = [double]$workArea.Top
				Width  = [double]$workArea.Width
				Height = [double]$workArea.Height
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:37' -Severity Debug }

			$splashWindowWidth  = $guiMinW
			$splashWindowHeight = $guiMinH
			$splashWindowLeft = 0
			$splashWindowTop = 0
			$splashWindowStartupLocation = 'CenterScreen'
			$splashDefaultBounds = [pscustomobject]@{
				Left   = [double]$splashWindowLeft
				Top    = [double]$splashWindowTop
				Width  = [double]$splashWindowWidth
				Height = [double]$splashWindowHeight
			}
			$splashStartupWorkAreaBounds = $null
		}
		$testSplashStartupBoundsMatchWorkArea = {
			param([object]$Bounds)

			if (-not $Bounds -or -not $splashStartupWorkAreaBounds) { return $false }
			if ($null -eq $Bounds.Left -or $null -eq $Bounds.Top -or $null -eq $Bounds.Width -or $null -eq $Bounds.Height) { return $false }
			return (
				[Math]::Abs([double]$Bounds.Left - [double]$splashStartupWorkAreaBounds.Left) -le 1.0 -and
				[Math]::Abs([double]$Bounds.Top - [double]$splashStartupWorkAreaBounds.Top) -le 1.0 -and
				[Math]::Abs([double]$Bounds.Width - [double]$splashStartupWorkAreaBounds.Width) -le 1.0 -and
				[Math]::Abs([double]$Bounds.Height - [double]$splashStartupWorkAreaBounds.Height) -le 1.0
			)
		}.GetNewClosure()
		$splashWindowMaximized = $false
		try
		{
			if (Get-Command -Name 'Resolve-BaselineWindowPlacement' -ErrorAction SilentlyContinue)
			{
				$defaultRect = [pscustomobject]@{
					Left   = [double]$splashWindowLeft
					Top    = [double]$splashWindowTop
					Width  = [double]$splashWindowWidth
					Height = [double]$splashWindowHeight
				}
				$placement = Resolve-BaselineWindowPlacement -DefaultRect $defaultRect
				if ($placement)
				{
					$placementBounds = [pscustomobject]@{
						Left   = [double]$placement.Left
						Top    = [double]$placement.Top
						Width  = [double]$placement.Width
						Height = [double]$placement.Height
					}
					if (([string]$placement.Source -eq 'saved') -and (& $testSplashStartupBoundsMatchWorkArea -Bounds $placementBounds) -and (-not (& $testSplashStartupBoundsMatchWorkArea -Bounds $splashDefaultBounds)))
					{
						$placementBounds = $splashDefaultBounds
					}
					$splashWindowWidth = [int][Math]::Round([double]$placementBounds.Width)
					$splashWindowHeight = [int][Math]::Round([double]$placementBounds.Height)
					if ([string]$placement.Source -eq 'saved')
					{
						$splashWindowLeft = [double]$placementBounds.Left
						$splashWindowTop = [double]$placementBounds.Top
						$splashWindowMaximized = [bool]$placement.Maximized
						$splashWindowStartupLocation = 'Manual'
					}
				}
			}
		}
		catch
		{
			Write-EnvironmentLaunchTrace ('Bootstrap splash window placement restore failed: {0}' -f $_.Exception.Message)
			$splashWindowStartupLocation = 'CenterScreen'
			$splashWindowMaximized = $false
		}

		# Match the last saved session first, then fall back to the current Windows theme.
		$useLightTheme = ((Get-BaselineStartupThemeName) -eq 'Light')

			$allowedSplashSteps = @('updates', 'system', 'winget', 'chocolatey', 'finalize')
			$splashStepOrder = @()
			if ($StepOrder -and $StepOrder.Count -gt 0)
			{
				foreach ($requestedStep in @($StepOrder))
				{
					$normalizedStep = [string]$requestedStep
					if (($allowedSplashSteps -contains $normalizedStep) -and (-not ($splashStepOrder -contains $normalizedStep)))
					{
						if (($normalizedStep -ne 'updates') -or [bool]$StartUpdatesPulse)
						{
							$splashStepOrder += $normalizedStep
						}
					}
				}
			}
			else
			{
				$splashStepOrder = @('system', 'winget', 'chocolatey', 'finalize')
			}
			if ([bool]$StartUpdatesPulse -and (-not ($splashStepOrder -contains 'updates')))
			{
				$splashStepOrder = @('updates') + $splashStepOrder
			}
			if (-not ($splashStepOrder -contains 'finalize'))
			{
				$splashStepOrder += 'finalize'
			}

			$syncHash = [hashtable]::Synchronized(@{
				Window     = $null
				Dispatcher = $null
				StatusText = $null
				SubActionPanel = $null
				ProgressBar = $null
				StepGlyphs = $null
				StepIdleDots = $null
				StepPulseDots = $null
				StepChecks = $null
				StepLabels = $null
				StepStates = $null
				StepOrder  = $splashStepOrder
				SplashTheme = $null
				GuiReady   = $false
				IsReady    = $false
				IsAlive    = $true
				UserClosed = $false
				AbortRequested = $false
				ProgrammaticClose = $false
				WasLoaded  = $false
				WasShown   = $false
				WasRendered = $false
				WindowMaximized = $splashWindowMaximized
				WindowActive = $false
				InitialStepPrimeApplied = $false
				ChecklistProgressActive = $false
				WindowHandle = [IntPtr]::Zero
				ErrorType  = $null
				ErrorMessage = $null
			})

		# Theme colors
		if ($useLightTheme)
		{
			$splashBg = '#F0F2F6'; $splashBorder = '#E6EAF0'; $splashFg = '#1F2937'
			$splashSub = '#4B5563'; $splashAccent = '#1550AA'; $splashFooterBg = '#E9EDF3'
			$splashMuted = '#5F6B7A'; $splashBtnFg = '#4B5563'; $splashStepActive = '#1F2937'; $splashDarkMode = $false
		}
		else
		{
			$splashBg = '#10131C'; $splashBorder = '#293044'; $splashFg = '#F4F7FF'
			$splashSub = '#CDD6EA'; $splashAccent = '#7CB7FF'; $splashFooterBg = '#151824'
			$splashMuted = '#A3ADC6'; $splashBtnFg = '#CDD6EA'; $splashStepActive = '#E6EBFF'; $splashDarkMode = $true
		}
		$CurrentTheme = [ordered]@{
			WindowBg    = $splashBg
			BorderColor = $splashBorder
			TextPrimary = $splashFg
			TextSecondary = $splashSub
			Accent      = $splashAccent
			CardBg      = $splashFooterBg
			TextMuted   = $splashMuted
		}
		$SplashTheme = [ordered]@{
			Muted   = $splashMuted
			Sub     = $splashSub
			Primary = $splashStepActive
			Accent  = $splashAccent
		}

		$runspace = [runspacefactory]::CreateRunspace()
		$runspace.ApartmentState = 'STA'
		$runspace.ThreadOptions  = 'ReuseThread'
		$runspace.Open()
		$splashIconPath = $null
		$splashThemePath = $null
		try
		{
			$repoBasePath = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
			$candidateSplashIcon = Join-Path -Path $repoBasePath -ChildPath 'Assets\baseline.ico'
			if (Test-Path -LiteralPath $candidateSplashIcon -PathType Leaf)
			{
				$splashIconPath = [System.IO.Path]::GetFullPath($candidateSplashIcon)
			}
			$splashThemeFileName = if ($useLightTheme) { 'Light.xaml' } else { 'Dark.xaml' }
			$candidateSplashTheme = Join-Path -Path $repoBasePath -ChildPath ('Module\GUI\Themes\{0}' -f $splashThemeFileName)
			if (Test-Path -LiteralPath $candidateSplashTheme -PathType Leaf)
			{
				$splashThemePath = [System.IO.Path]::GetFullPath($candidateSplashTheme)
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:198' -Severity Debug }

			$splashIconPath = $null
			$splashThemePath = $null
		}
		$runspace.SessionStateProxy.SetVariable('syncHash', $syncHash)
		$runspace.SessionStateProxy.SetVariable('splashIconPath', $splashIconPath)
		$runspace.SessionStateProxy.SetVariable('splashThemePath', $splashThemePath)
		$runspace.SessionStateProxy.SetVariable('splashBg', $splashBg)
		$runspace.SessionStateProxy.SetVariable('splashBorder', $splashBorder)
		$runspace.SessionStateProxy.SetVariable('splashFg', $splashFg)
		$runspace.SessionStateProxy.SetVariable('splashSub', $splashSub)
		$runspace.SessionStateProxy.SetVariable('splashAccent', $splashAccent)
		$runspace.SessionStateProxy.SetVariable('splashFooterBg', $splashFooterBg)
		$runspace.SessionStateProxy.SetVariable('splashMuted', $splashMuted)
		$runspace.SessionStateProxy.SetVariable('splashBtnFg', $splashBtnFg)
		$runspace.SessionStateProxy.SetVariable('splashStepActive', $splashStepActive)
		$runspace.SessionStateProxy.SetVariable('splashDarkMode', $splashDarkMode)
		$runspace.SessionStateProxy.SetVariable('splashWindowLeft', $splashWindowLeft)
		$runspace.SessionStateProxy.SetVariable('splashWindowTop', $splashWindowTop)
		$runspace.SessionStateProxy.SetVariable('splashWindowWidth', $splashWindowWidth)
		$runspace.SessionStateProxy.SetVariable('splashWindowHeight', $splashWindowHeight)
		$runspace.SessionStateProxy.SetVariable('splashWindowStartupLocation', $splashWindowStartupLocation)
		$runspace.SessionStateProxy.SetVariable('splashWindowMaximized', $splashWindowMaximized)
		$runspace.SessionStateProxy.SetVariable('CurrentTheme', $CurrentTheme)
		$runspace.SessionStateProxy.SetVariable('SplashTheme', $SplashTheme)
		# Pass localization strings for splash screen
		$splashLocSubtitle = Get-BaselineLocalizedString -Key 'GuiSplashSubtitle' -Fallback 'Review, preview, and apply system changes safely'
		$splashLocLoading = Get-BaselineLocalizedString -Key 'GuiSplashLoading' -Fallback 'Please Wait...'
		$splashLocStepUpdates = Get-BaselineLocalizedString -Key 'Bootstrap_StepCheckingForUpdates' -Fallback 'Checking for Updates'
		$splashLocStepSystem     = Get-BaselineLocalizedString -Key 'Bootstrap_StepRunningSystemChecks' -Fallback 'Running System Checks'
		$splashLocStepWinget     = Get-BaselineLocalizedString -Key 'Bootstrap_StepCheckingWinget' -Fallback 'Checking WinGet'
		$splashLocStepChocolatey = Get-BaselineLocalizedString -Key 'Bootstrap_StepCheckingChocolatey' -Fallback 'Checking Chocolatey'
		$splashLocStepFinalize   = Get-BaselineLocalizedString -Key 'Bootstrap_StepFinalizing' -Fallback 'Finalizing Baseline Configuration'
		$runspace.SessionStateProxy.SetVariable('splashLocSubtitle', $splashLocSubtitle)
		$runspace.SessionStateProxy.SetVariable('splashLocLoading', $splashLocLoading)
		$runspace.SessionStateProxy.SetVariable('splashLocStepUpdates', $splashLocStepUpdates)
		$runspace.SessionStateProxy.SetVariable('splashLocStepSystem', $splashLocStepSystem)
		$runspace.SessionStateProxy.SetVariable('splashLocStepWinget', $splashLocStepWinget)
		$runspace.SessionStateProxy.SetVariable('splashLocStepChocolatey', $splashLocStepChocolatey)
		$runspace.SessionStateProxy.SetVariable('splashLocStepFinalize', $splashLocStepFinalize)
		$runspace.SessionStateProxy.SetVariable('startUpdatesPulse', [bool]$StartUpdatesPulse)
		$runspace.SessionStateProxy.SetVariable('splashStepOrder', $splashStepOrder)
		$runspace.SessionStateProxy.SetVariable('bootstrapSplashProgressWidthScriptBlock', (Get-Command -Name 'Get-BaselineSplashProgressWidth' -CommandType Function -ErrorAction Stop).ScriptBlock)
		$runspace.SessionStateProxy.SetVariable('bootstrapLoadingSplashStateScriptBlock', (Get-Command -Name 'Set-BootstrapLoadingSplashState' -CommandType Function -ErrorAction Stop).ScriptBlock)
		$runspace.SessionStateProxy.SetVariable('bootstrapLoadingSplashStepScriptBlock', (Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction Stop).ScriptBlock)
		$runspace.SessionStateProxy.SetVariable('environmentSwallowedExceptionScriptBlock', (Get-Command -Name 'Write-EnvironmentSwallowedException' -CommandType Function -ErrorAction Stop).ScriptBlock)

		$ps = [powershell]::Create()
		$ps.Runspace = $runspace
		[void]$ps.AddScript({
			try
			{
				Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

				$installSplashFunction = {
					param(
						[string]$Name,
						[scriptblock]$ScriptBlock
					)

					if ($null -eq $ScriptBlock)
					{
						throw "Bootstrap splash function script block is empty: $Name"
					}

					Set-Item -Path ('Function:\global:{0}' -f $Name) -Value $ScriptBlock -ErrorAction Stop
				}

				& $installSplashFunction 'Get-BaselineSplashProgressWidth' $bootstrapSplashProgressWidthScriptBlock
				& $installSplashFunction 'Set-BootstrapLoadingSplashState' $bootstrapLoadingSplashStateScriptBlock
				& $installSplashFunction 'Set-BootstrapLoadingSplashStep' $bootstrapLoadingSplashStepScriptBlock
				& $installSplashFunction 'Write-EnvironmentSwallowedException' $environmentSwallowedExceptionScriptBlock
				Set-Item -Path 'Function:\global:Write-SwallowedException' -Value {
					param(
						[Parameter(Mandatory = $false)]
						[object]$ErrorRecord,
						[Parameter(Mandatory = $true)]
						[string]$Source
					)
					Write-EnvironmentSwallowedException -ErrorRecord $ErrorRecord -Source $Source
				} -ErrorAction Stop
				$bootstrapLoadingSplashStateCommand = (Get-Command -Name 'Set-BootstrapLoadingSplashState' -CommandType Function -ErrorAction Stop).ScriptBlock
				$bootstrapLoadingSplashStepCommand = (Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction Stop).ScriptBlock

				$subtitleEsc = [System.Security.SecurityElement]::Escape($splashLocSubtitle)
				$loadingEsc = [System.Security.SecurityElement]::Escape($splashLocLoading)
				$stepUpdatesEsc = [System.Security.SecurityElement]::Escape($splashLocStepUpdates)
				$stepSystemEsc = [System.Security.SecurityElement]::Escape($splashLocStepSystem)
				$stepWingetEsc = [System.Security.SecurityElement]::Escape($splashLocStepWinget)
				$stepChocolateyEsc = [System.Security.SecurityElement]::Escape($splashLocStepChocolatey)
				$stepFinalizeEsc = [System.Security.SecurityElement]::Escape($splashLocStepFinalize)
				$stepLabelById = @{
					'updates'    = $stepUpdatesEsc
					'system'     = $stepSystemEsc
					'winget'     = $stepWingetEsc
					'chocolatey' = $stepChocolateyEsc
					'finalize'   = $stepFinalizeEsc
				}
				$lastSplashStepId = [string]$splashStepOrder[$splashStepOrder.Count - 1]
				$stepRows = foreach ($splashStepId in @($splashStepOrder))
				{
					$stepLabelEsc = [string]$stepLabelById[[string]$splashStepId]
					$stepMargin = if ([string]$splashStepId -eq $lastSplashStepId) { '0,0,0,0' } else { '0,0,0,7' }
					@"
					<Grid Margin="$stepMargin">
						<Grid.ColumnDefinitions>
							<ColumnDefinition Width="22"/>
							<ColumnDefinition Width="*"/>
						</Grid.ColumnDefinitions>
						<Grid Name="StepGlyph_$splashStepId" Grid.Column="0" Width="16" Height="16" VerticalAlignment="Center" HorizontalAlignment="Center">
							<Ellipse Name="StepIdle_$splashStepId" Width="8" Height="8" Stroke="{DynamicResource Brush.TextMuted}" StrokeThickness="1" Fill="Transparent" VerticalAlignment="Center" HorizontalAlignment="Center"/>
							<Ellipse Name="StepPulse_$splashStepId" Width="8" Height="8" Fill="{DynamicResource Brush.Accent}" Opacity="0.6" Visibility="Collapsed" VerticalAlignment="Center" HorizontalAlignment="Center" RenderTransformOrigin="0.5,0.5">
								<Ellipse.RenderTransform>
									<ScaleTransform/>
								</Ellipse.RenderTransform>
							</Ellipse>
							<TextBlock Name="StepCheck_$splashStepId" Text="&#x2714;" FontFamily="Segoe UI Symbol" FontSize="12" Foreground="{DynamicResource Brush.Accent}" VerticalAlignment="Center" HorizontalAlignment="Center" Visibility="Collapsed"/>
						</Grid>
						<TextBlock Name="StepLabel_$splashStepId" Grid.Column="1" Text="$stepLabelEsc" FontSize="13" Foreground="{DynamicResource Brush.TextMuted}" VerticalAlignment="Center" Margin="8,0,0,0"/>
					</Grid>
"@
				}
				$stepRowsXaml = ($stepRows -join [System.Environment]::NewLine)

				[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="Baseline | Windows Utility"
	Width="$splashWindowWidth"
	Height="$splashWindowHeight"
	MinWidth="940"
	MinHeight="660"
	ResizeMode="CanResizeWithGrip"
	WindowStartupLocation="$splashWindowStartupLocation"
	Background="Transparent"
	BorderBrush="Transparent"
	BorderThickness="0"
	Foreground="{DynamicResource Brush.TextPrimary}"
	FontFamily="Segoe UI"
	ShowInTaskbar="True"
	ShowActivated="True"
	Topmost="False"
	WindowStyle="None"
	AllowsTransparency="True"
	SnapsToDevicePixels="True"
	UseLayoutRounding="True">
	<Window.Resources>
		<Style x:Key="SplashCaptionButtonStyle" TargetType="Button">
			<Setter Property="Background" Value="Transparent"/>
			<Setter Property="Foreground" Value="{DynamicResource Brush.TextSecondary}"/>
			<Setter Property="BorderBrush" Value="Transparent"/>
			<Setter Property="BorderThickness" Value="0"/>
			<Setter Property="Padding" Value="0"/>
			<Setter Property="FocusVisualStyle" Value="{x:Null}"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="Button">
						<Border x:Name="CaptionBd"
							Background="{TemplateBinding Background}"
							BorderBrush="{TemplateBinding BorderBrush}"
							BorderThickness="{TemplateBinding BorderThickness}"
							CornerRadius="6"
							SnapsToDevicePixels="True">
							<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
						</Border>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
			<Style.Triggers>
				<Trigger Property="IsMouseOver" Value="True">
					<Setter Property="Background" Value="{DynamicResource Brush.SurfaceHover}"/>
					<Setter Property="Foreground" Value="{DynamicResource Brush.TextPrimary}"/>
				</Trigger>
				<Trigger Property="IsPressed" Value="True">
					<Setter Property="Background" Value="{DynamicResource Brush.ButtonPressBg}"/>
					<Setter Property="Foreground" Value="{DynamicResource Brush.TextPrimary}"/>
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style x:Key="SplashCloseButtonStyle" TargetType="Button" BasedOn="{StaticResource SplashCaptionButtonStyle}">
			<Style.Triggers>
				<Trigger Property="IsMouseOver" Value="True">
					<Setter Property="Background" Value="{DynamicResource Brush.Danger}"/>
					<Setter Property="Foreground" Value="White"/>
				</Trigger>
				<Trigger Property="IsPressed" Value="True">
					<Setter Property="Background" Value="{DynamicResource Brush.Danger}"/>
					<Setter Property="Foreground" Value="White"/>
				</Trigger>
			</Style.Triggers>
		</Style>
	</Window.Resources>
	<Border Name="RootBorder" CornerRadius="8" Background="{DynamicResource Brush.SplashBackdrop}" BorderBrush="{DynamicResource Brush.Border}" BorderThickness="1" Margin="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" SnapsToDevicePixels="True" ClipToBounds="True">
			<Grid Background="Transparent" Margin="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" SnapsToDevicePixels="True">
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="*"/>
				</Grid.RowDefinitions>
			<Grid Grid.Row="0" Background="{DynamicResource Brush.HeaderBg}" Margin="10,6,6,0">
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<DockPanel Grid.Column="0" LastChildFill="True" VerticalAlignment="Center" Margin="0,0,10,0">
					<Image Name="SplashTopLeftIcon" Width="20" Height="20" Stretch="Uniform" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="2,0,8,0"/>
					<TextBlock Name="TitleText"
						Text="{Binding RelativeSource={RelativeSource AncestorType=Window}, Path=Title}"
						FontSize="12"
						FontWeight="SemiBold"
						Foreground="{DynamicResource Brush.TextPrimary}"
						VerticalAlignment="Center"
						TextTrimming="CharacterEllipsis"/>
				</DockPanel>
				<StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
					<Button Name="BtnMinimize" Content="&#x2015;" Width="28" Height="24" FontSize="11"
						Cursor="Hand" ToolTip="Minimize" Margin="0,0,2,0" Style="{StaticResource SplashCaptionButtonStyle}"/>
					<Button Name="BtnMaximize" Content="&#x25A1;" Width="28" Height="24" FontSize="11"
						Cursor="Hand" ToolTip="Maximize" Margin="0,0,2,0" Style="{StaticResource SplashCaptionButtonStyle}"/>
					<Button Name="BtnClose" Content="&#x2715;" Width="28" Height="24" FontSize="11"
						Cursor="Hand" ToolTip="Close" Style="{StaticResource SplashCloseButtonStyle}"/>
				</StackPanel>
			</Grid>
			<Border Name="SplashContentCard" Grid.Row="1" Background="{DynamicResource Brush.SplashCard}" BorderThickness="0" CornerRadius="18" Padding="52,44" VerticalAlignment="Center" HorizontalAlignment="Center" SnapsToDevicePixels="True">
				<Border.Effect>
					<DropShadowEffect Color="#000000" BlurRadius="34" ShadowDepth="0" Opacity="0.18"/>
				</Border.Effect>
				<StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0">
				<StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,16">
					<Image Name="SplashCenterIcon" Width="58" Height="58" Stretch="Uniform" VerticalAlignment="Center" Margin="0,0,16,0"
						RenderOptions.BitmapScalingMode="HighQuality" UseLayoutRounding="True" SnapsToDevicePixels="True"/>
					<TextBlock Text="Baseline"
						FontWeight="SemiBold"
						FontSize="56"
						Foreground="{DynamicResource Brush.TextPrimary}"
						VerticalAlignment="Center"/>
				</StackPanel>
				<TextBlock Name="SubtitleText" Text="$subtitleEsc"
					FontSize="14" Foreground="{DynamicResource Brush.SplashSubtitle}"
					HorizontalAlignment="Center" Margin="0,0,0,32"/>
				<StackPanel Name="StepListPanel" HorizontalAlignment="Center" MinWidth="360" Margin="0,0,0,24">
$stepRowsXaml
				</StackPanel>
				<StackPanel Name="SubActionPanel" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,14" Visibility="Collapsed">
					<TextBlock Name="StatusText" Text="$loadingEsc" FontSize="11" Foreground="{DynamicResource Brush.TextMuted}"
						VerticalAlignment="Center"/>
				</StackPanel>
				<ProgressBar Name="ProgressBar"
					Width="360" Height="6"
					Visibility="Visible"
					Minimum="0" Maximum="330" Value="0"
					IsIndeterminate="False"
					Foreground="{DynamicResource Brush.Progress}"
					Background="{DynamicResource Brush.ProgressTrack}"
					BorderThickness="0">
					<ProgressBar.Template>
						<ControlTemplate TargetType="ProgressBar">
							<Grid SnapsToDevicePixels="True">
								<Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="3" Opacity="0.82"/>
								<Border x:Name="PART_Indicator" Width="{TemplateBinding Value}" HorizontalAlignment="Left" Background="{TemplateBinding Foreground}" CornerRadius="3">
									<Border.Effect>
										<DropShadowEffect Color="{DynamicResource Color.Progress}" BlurRadius="10" ShadowDepth="0" Opacity="0.35"/>
									</Border.Effect>
									<Grid ClipToBounds="True">
										<Rectangle x:Name="PART_GlowRect" Width="84" HorizontalAlignment="Left" RenderTransformOrigin="0,0">
											<Rectangle.Fill>
												<LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
													<GradientStop Color="#00FFFFFF" Offset="0"/>
													<GradientStop Color="#7FFFFFFF" Offset="0.5"/>
													<GradientStop Color="#00FFFFFF" Offset="1"/>
												</LinearGradientBrush>
											</Rectangle.Fill>
											<Rectangle.RenderTransform>
												<TranslateTransform x:Name="SplashSheenT" X="-100"/>
											</Rectangle.RenderTransform>
										</Rectangle>
									</Grid>
								</Border>
							</Grid>
							<ControlTemplate.Triggers>
								<EventTrigger RoutedEvent="FrameworkElement.Loaded">
									<BeginStoryboard>
										<Storyboard RepeatBehavior="Forever">
											<DoubleAnimation Storyboard.TargetName="SplashSheenT" Storyboard.TargetProperty="X" From="-100" To="400" Duration="0:0:1.4"/>
										</Storyboard>
									</BeginStoryboard>
								</EventTrigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</ProgressBar.Template>
				</ProgressBar>
				</StackPanel>
			</Border>
		</Grid>
	</Border>
</Window>
"@
				$splash = [System.Windows.Markup.XamlReader]::Load(
					(New-Object System.Xml.XmlNodeReader $xaml)
				)
				if ([string]::IsNullOrWhiteSpace([string]$splashThemePath))
				{
					throw 'Bootstrap splash theme resource dictionary was not found.'
				}

				$themeReader = [System.Xml.XmlReader]::Create($splashThemePath)
				try
				{
					$themeDictionary = [System.Windows.Markup.XamlReader]::Load($themeReader)
					if (-not ($themeDictionary -is [System.Windows.ResourceDictionary]))
					{
						throw "Bootstrap splash theme resource did not load as a ResourceDictionary: $splashThemePath"
					}
					[void]$splash.Resources.MergedDictionaries.Add($themeDictionary)
				}
				finally
				{
					if ($themeReader) { $themeReader.Close() }
				}

				$traceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
				if (-not [System.IO.Directory]::Exists($traceDirectory))
				{
					[void][System.IO.Directory]::CreateDirectory($traceDirectory)
				}
				$tracePath = Join-Path $traceDirectory 'Baseline-launch-trace.txt'
				$writeSplashTrace = {
					param([string]$Message)
					try
					{
						$traceBytes = [System.Text.Encoding]::UTF8.GetBytes(("{0:o} {1}`r`n" -f [DateTime]::UtcNow, $Message))
						$traceStream = [System.IO.FileStream]::new($tracePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
						try { $traceStream.Write($traceBytes, 0, $traceBytes.Length) }
						finally { $traceStream.Dispose() }
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:588' -Severity Debug }
					 $null = $_ }
				}

				if (-not [string]::IsNullOrWhiteSpace([string]$splashIconPath) -and (Test-Path -LiteralPath $splashIconPath -PathType Leaf))
				{
					try
					{
						$selectSplashIconFrame = {
							param(
								[Parameter(Mandatory = $true)]
								[System.Collections.IEnumerable]
								$Frames,
								[Parameter(Mandatory = $true)]
								[int]$TargetPixelWidth
							)

							$closest = $Frames |
								Sort-Object -Property @{ Expression = { [Math]::Abs($_.PixelWidth - $TargetPixelWidth) } } |
								Select-Object -First 1
							return $closest
						}

						$iconUri = [System.Uri]::new($splashIconPath, [System.UriKind]::Absolute)
						$iconDecoder = [System.Windows.Media.Imaging.IconBitmapDecoder]::new(
							$iconUri,
							[System.Windows.Media.Imaging.BitmapCreateOptions]::None,
							[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
						)
						$iconForWindow = if ($iconDecoder.Frames -and $iconDecoder.Frames.Count -gt 0)
						{
							& $selectSplashIconFrame -Frames $iconDecoder.Frames -TargetPixelWidth 32
						}
						else
						{
							$null
						}
						$iconForTitleBar = if ($iconDecoder.Frames -and $iconDecoder.Frames.Count -gt 0)
						{
							& $selectSplashIconFrame -Frames $iconDecoder.Frames -TargetPixelWidth 20
						}
						else
						{
							$null
						}
						$iconForCenterLogo = if ($iconDecoder.Frames -and $iconDecoder.Frames.Count -gt 0)
						{
							& $selectSplashIconFrame -Frames $iconDecoder.Frames -TargetPixelWidth 58
						}
						else
						{
							$null
						}
						if (-not $iconForWindow) { $iconForWindow = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri) }
						if (-not $iconForTitleBar) { $iconForTitleBar = $iconForWindow }
						if (-not $iconForCenterLogo) { $iconForCenterLogo = $iconForWindow }
						if ($iconForWindow -and $iconForWindow.CanFreeze) { $iconForWindow.Freeze() }
						if ($iconForTitleBar -and $iconForTitleBar.CanFreeze) { $iconForTitleBar.Freeze() }
						if ($iconForCenterLogo -and $iconForCenterLogo.CanFreeze) { $iconForCenterLogo.Freeze() }
						$splash.Icon = $iconForWindow
						$splashTopLeftIcon = $splash.FindName('SplashTopLeftIcon')
						if ($splashTopLeftIcon)
						{
							$splashTopLeftIcon.Source = $iconForTitleBar
							[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($splashTopLeftIcon, [System.Windows.Media.BitmapScalingMode]::HighQuality)
							$splashTopLeftIcon.SnapsToDevicePixels = $true
							$splashTopLeftIcon.UseLayoutRounding = $true
						}
						$splashCenterIcon = $splash.FindName('SplashCenterIcon')
						if ($splashCenterIcon)
						{
							$splashCenterIcon.Source = $iconForCenterLogo
							[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($splashCenterIcon, [System.Windows.Media.BitmapScalingMode]::HighQuality)
							$splashCenterIcon.SnapsToDevicePixels = $true
							$splashCenterIcon.UseLayoutRounding = $true
						}
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:664' -Severity Debug }
					 & $writeSplashTrace ('Environment.ShowBootstrapLoadingSplash.LoadSplashIcon: {0}' -f $_.Exception.Message) }
				}

				# Apply Windows 11 rounded corners and dark title bar
				$splash.Add_SourceInitialized({
					try
					{
						if (-not ('WinAPI.SplashChrome' -as [type]))
						{
							Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace WinAPI {
	public static class SplashChrome {
		[DllImport("dwmapi.dll")]
		public static extern int DwmSetWindowAttribute(IntPtr hwnd, int dwAttribute, ref int pvAttribute, int cbAttribute);
		[DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")] private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
		[DllImport("user32.dll", EntryPoint = "GetWindowLong")] private static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);
		[DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")] private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
		[DllImport("user32.dll", EntryPoint = "SetWindowLong")] private static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
		[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
		public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex) { return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, nIndex) : GetWindowLong32(hWnd, nIndex); }
		public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong) { return IntPtr.Size == 8 ? SetWindowLongPtr64(hWnd, nIndex, dwNewLong) : SetWindowLong32(hWnd, nIndex, dwNewLong); }
		public const int GWL_STYLE = -16;
		public const int WS_SYSMENU = 0x00080000;
		public const int WS_MINIMIZEBOX = 0x00020000;
		public const int WS_MAXIMIZEBOX = 0x00010000;
	}
}
"@ -ErrorAction Stop | Out-Null
						}
						$hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($splash)).Handle
						if ($hwnd -ne [IntPtr]::Zero)
						{
							$syncHash['WindowHandle'] = $hwnd
							$darkMode = if ($splashDarkMode) { 1 } else { 0 }
							$immAttr = if ([Environment]::OSVersion.Version.Build -ge 18362) { 20 } else { 19 }
							[void]([WinAPI.SplashChrome]::DwmSetWindowAttribute($hwnd, $immAttr, [ref]$darkMode, 4))
							if ([Environment]::OSVersion.Version.Build -ge 22000)
							{
								$cornerPref = 2
								[void]([WinAPI.SplashChrome]::DwmSetWindowAttribute($hwnd, 33, [ref]$cornerPref, 4))
							}
							# Restore system menu (right-click title bar: Restore/Move/Size/Minimize/Maximize/Close)
							$style = [WinAPI.SplashChrome]::GetWindowLongPtr($hwnd, [WinAPI.SplashChrome]::GWL_STYLE)
							$styleInt = $style.ToInt64()
							$styleInt = $styleInt -bor [WinAPI.SplashChrome]::WS_SYSMENU
							$styleInt = $styleInt -bor [WinAPI.SplashChrome]::WS_MINIMIZEBOX
							$styleInt = $styleInt -bor [WinAPI.SplashChrome]::WS_MAXIMIZEBOX
							[void]([WinAPI.SplashChrome]::SetWindowLongPtr($hwnd, [WinAPI.SplashChrome]::GWL_STYLE, [IntPtr]::new($styleInt)))
							[void]([WinAPI.SplashChrome]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x27))
							& $writeSplashTrace ('Bootstrap splash source initialized: hwnd={0}' -f $hwnd)
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:718' -Severity Debug }

						$syncHash['ErrorType'] = $_.Exception.GetType().FullName
						$syncHash['ErrorMessage'] = $_.Exception.Message
						& $writeSplashTrace ('Bootstrap splash chrome setup failed: {0}' -f $_.Exception.Message)
					}
				})

				$requestSplashAbortAction = {
					param([string]$Source)

					$shouldExit = $false
					try
					{
						if ([bool]$syncHash['ProgrammaticClose'] -or [bool]$syncHash['GuiReady'])
						{
							return
						}

						$syncHash['UserClosed'] = $true
						$syncHash['AbortRequested'] = $true
						$syncHash['IsAlive'] = $false
						$shouldExit = $true
						& $writeSplashTrace ('Bootstrap splash abort requested by user close: {0}' -f $Source)
					}
					finally
					{
						if ($shouldExit)
						{
							[System.Environment]::Exit(0)
							try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:748' -Severity Debug }
							 $null = $_ }
						}
					}
				}.GetNewClosure()

				# Wire up caption controls and drag-to-move
				$rootBorder = $splash.FindName('RootBorder')
				$btnMin = $splash.FindName('BtnMinimize')
				$btnMax = $splash.FindName('BtnMaximize')
				$btnCls = $splash.FindName('BtnClose')
				$splashWindowChromeState = @{
					NormalBounds = $null
					ApplyingState = $false
				}
				$readSplashNormalBoundsAction = {
					$width = [double]$splash.Width
					$height = [double]$splash.Height
					if ([double]::IsNaN($width) -or $width -le 0) { $width = [double]$splash.ActualWidth }
					if ([double]::IsNaN($height) -or $height -le 0) { $height = [double]$splash.ActualHeight }
					if ([double]::IsNaN($width) -or [double]::IsNaN($height) -or $width -le 0 -or $height -le 0) { return $null }

					return [pscustomobject]@{
						Left   = [double]$splash.Left
						Top    = [double]$splash.Top
						Width  = $width
						Height = $height
					}
				}.GetNewClosure()
				$captureSplashNormalBoundsAction = {
					if ($splash.WindowState -ne [System.Windows.WindowState]::Normal) { return }
					$bounds = & $readSplashNormalBoundsAction
					if ($bounds) { $splashWindowChromeState['NormalBounds'] = $bounds }
				}.GetNewClosure()
				$restoreSplashNormalBoundsAction = {
					$bounds = $splashWindowChromeState['NormalBounds']
					if (-not $bounds) { return }
					$splash.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
					if (-not [double]::IsNaN([double]$bounds.Left)) { $splash.Left = [double]$bounds.Left }
					if (-not [double]::IsNaN([double]$bounds.Top)) { $splash.Top = [double]$bounds.Top }
					$splash.Width = [double]$bounds.Width
					$splash.Height = [double]$bounds.Height
				}.GetNewClosure()
				$getSplashWindowWorkAreaBoundsAction = {
					try
					{
						Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
						$windowInterop = New-Object System.Windows.Interop.WindowInteropHelper($splash)
						$windowHandle = $windowInterop.Handle
						if ($windowHandle -eq [IntPtr]::Zero -and $windowInterop.PSObject.Methods['EnsureHandle'])
						{
							$windowHandle = $windowInterop.EnsureHandle()
						}
						if ($windowHandle -ne [IntPtr]::Zero)
						{
							$screen = [System.Windows.Forms.Screen]::FromHandle($windowHandle)
							if ($screen)
							{
								$rect = $screen.WorkingArea
								$left = [double]$rect.Left
								$top = [double]$rect.Top
								$right = [double]$rect.Right
								$bottom = [double]$rect.Bottom
								$source = [System.Windows.PresentationSource]::FromVisual($splash)
								if ($source -and $source.CompositionTarget)
								{
									$transform = $source.CompositionTarget.TransformFromDevice
									$topLeft = $transform.Transform([System.Windows.Point]::new($left, $top))
									$bottomRight = $transform.Transform([System.Windows.Point]::new($right, $bottom))
									return [pscustomobject]@{
										Left   = [double]$topLeft.X
										Top    = [double]$topLeft.Y
										Width  = [double]($bottomRight.X - $topLeft.X)
										Height = [double]($bottomRight.Y - $topLeft.Y)
									}
								}
								return [pscustomobject]@{
									Left   = $left
									Top    = $top
									Width  = [double]($right - $left)
									Height = [double]($bottom - $top)
								}
							}
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:832' -Severity Debug }

						$null = $_
					}

					$workArea = [System.Windows.SystemParameters]::WorkArea
					return [pscustomobject]@{
						Left   = [double]$workArea.Left
						Top    = [double]$workArea.Top
						Width  = [double]$workArea.Width
						Height = [double]$workArea.Height
					}
				}.GetNewClosure()

				# System-style right-click context menu for splash title area
				$splashMenu = New-Object System.Windows.Controls.ContextMenu
				$miRestore = New-Object System.Windows.Controls.MenuItem
				$miRestore.Header = 'Restore'
				$miMin = New-Object System.Windows.Controls.MenuItem
				$miMin.Header = 'Minimize'
				$miMax = New-Object System.Windows.Controls.MenuItem
				$miMax.Header = 'Maximize'
				$miCloseCtx = New-Object System.Windows.Controls.MenuItem
				$miCloseCtx.Header = 'Close'
				$miCloseCtx.InputGestureText = 'Alt+F4'
				$miCloseCtx.FontWeight = [System.Windows.FontWeights]::Bold
				$splashSep = New-Object System.Windows.Controls.Separator
				[void]$splashMenu.Items.Add($miRestore)
				[void]$splashMenu.Items.Add($miMin)
				[void]$splashMenu.Items.Add($miMax)
				[void]$splashMenu.Items.Add($splashSep)
				[void]$splashMenu.Items.Add($miCloseCtx)
				$splash.ContextMenu = $splashMenu

				$syncSplashWindowStateAction = {
					$isMaximized = [bool]$syncHash['WindowMaximized']
					$syncHash['WindowMaximized'] = $isMaximized
					if ($btnMax)
					{
						$btnMax.Content = if ($isMaximized) { [char]0x2750 } else { [char]0x25A1 }
						$btnMax.ToolTip = if ($isMaximized) { 'Restore' } else { 'Maximize' }
					}
					if ($rootBorder)
					{
						if ($isMaximized)
						{
							$rootBorder.CornerRadius = [System.Windows.CornerRadius]::new(0)
							$rootBorder.Margin = [System.Windows.Thickness]::new(0)
						}
						else
						{
							$rootBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
							$rootBorder.Margin = [System.Windows.Thickness]::new(0)
						}
					}
				}.GetNewClosure()

				$setSplashWindowMaximizedStateAction = {
					param([bool]$Maximized)

					$splashWindowChromeState['ApplyingState'] = $true
					try
					{
						if ($Maximized)
						{
							if (-not [bool]$syncHash['WindowMaximized']) { & $captureSplashNormalBoundsAction }
							$syncHash['WindowMaximized'] = $true
							if ($splash.WindowState -ne [System.Windows.WindowState]::Normal)
							{
								$splash.WindowState = [System.Windows.WindowState]::Normal
							}
							$workAreaBounds = & $getSplashWindowWorkAreaBoundsAction
							if ($workAreaBounds -and [double]$workAreaBounds.Width -gt 0 -and [double]$workAreaBounds.Height -gt 0)
							{
								$splash.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
								$splash.Left = [double]$workAreaBounds.Left
								$splash.Top = [double]$workAreaBounds.Top
								$splash.Width = [double]$workAreaBounds.Width
								$splash.Height = [double]$workAreaBounds.Height
							}
						}
						else
						{
							$syncHash['WindowMaximized'] = $false
							if ($splash.WindowState -ne [System.Windows.WindowState]::Normal)
							{
								$splash.WindowState = [System.Windows.WindowState]::Normal
							}
							& $restoreSplashNormalBoundsAction
						}
					}
					finally
					{
						$splashWindowChromeState['ApplyingState'] = $false
					}

					& $syncSplashWindowStateAction
				}.GetNewClosure()

				$toggleSplashMaximizeAction = {
					& $setSplashWindowMaximizedStateAction -Maximized (-not [bool]$syncHash['WindowMaximized'])
				}.GetNewClosure()

				if ($btnMin)
				{
					$btnMin.Add_Click({ $splash.WindowState = [System.Windows.WindowState]::Minimized })
				}
				if ($btnMax)
				{
					$btnMax.Add_Click({ & $toggleSplashMaximizeAction }.GetNewClosure())
				}
				if ($btnCls)
				{
					$btnCls.Add_Click({ & $requestSplashAbortAction 'caption button' }.GetNewClosure())
				}
				$splash.Add_MouseLeftButtonDown({
					param($s,$e)
					if ([bool]$syncHash['WindowMaximized'])
					{
						if ($e.ClickCount -eq 2) { & $toggleSplashMaximizeAction }
						return
					}
					if ($e.ClickCount -eq 2)
					{
						& $toggleSplashMaximizeAction
						return
					}
					try { $splash.DragMove() } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:959' -Severity Debug }
					 $null = $_ }
				}.GetNewClosure())

				$miRestore.Add_Click({ & $setSplashWindowMaximizedStateAction -Maximized $false }.GetNewClosure())
				$miMin.Add_Click({ $splash.WindowState = [System.Windows.WindowState]::Minimized })
				$miMax.Add_Click({ & $setSplashWindowMaximizedStateAction -Maximized $true }.GetNewClosure())
				$miCloseCtx.Add_Click({ & $requestSplashAbortAction 'context menu' }.GetNewClosure())
				$splashMenu.Add_Opened({
					$isMaximized = [bool]$syncHash['WindowMaximized']
					$miRestore.IsEnabled = $isMaximized
					$miMax.IsEnabled = -not $isMaximized
				}.GetNewClosure())
				$splash.Add_StateChanged({
					if ([bool]$splashWindowChromeState['ApplyingState'])
					{
						& $syncSplashWindowStateAction
						return
					}
					if ($splash.WindowState -eq [System.Windows.WindowState]::Maximized)
					{
						& $setSplashWindowMaximizedStateAction -Maximized $true
						return
					}
					elseif ($splash.WindowState -eq [System.Windows.WindowState]::Normal -and [bool]$syncHash['WindowMaximized'])
					{
						$syncHash['WindowMaximized'] = $false
						& $restoreSplashNormalBoundsAction
					}
					& $syncSplashWindowStateAction
				}.GetNewClosure())
				$rememberSplashNormalBoundsAction = {
					if ([bool]$splashWindowChromeState['ApplyingState']) { return }
					if ([bool]$syncHash['WindowMaximized']) { return }
					& $captureSplashNormalBoundsAction
				}.GetNewClosure()
				$splash.Add_LocationChanged($rememberSplashNormalBoundsAction)
				$splash.Add_SizeChanged($rememberSplashNormalBoundsAction)

				if ([string]$splashWindowStartupLocation -eq 'Manual')
				{
					$splash.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
					$splash.Left = [double]$splashWindowLeft
					$splash.Top = [double]$splashWindowTop
				}
				$splashWindowChromeState['NormalBounds'] = [pscustomobject]@{
					Left   = [double]$splashWindowLeft
					Top    = [double]$splashWindowTop
					Width  = [double]$splashWindowWidth
					Height = [double]$splashWindowHeight
				}
				if ([bool]$splashWindowMaximized)
				{
					& $setSplashWindowMaximizedStateAction -Maximized $true
				}
				& $syncSplashWindowStateAction

					$syncHash['Window']     = $splash
					$syncHash['Dispatcher'] = $splash.Dispatcher
					$syncHash['StatusText'] = $splash.FindName('StatusText')
					$syncHash['SubActionPanel'] = $splash.FindName('SubActionPanel')
					$syncHash['ProgressBar'] = $splash.FindName('ProgressBar')
					$stepGlyphs = @{
						'updates'    = $splash.FindName('StepGlyph_updates')
						'system'     = $splash.FindName('StepGlyph_system')
						'winget'     = $splash.FindName('StepGlyph_winget')
						'chocolatey' = $splash.FindName('StepGlyph_chocolatey')
						'finalize'   = $splash.FindName('StepGlyph_finalize')
					}
					$stepIdleDots = @{
						'updates'    = $splash.FindName('StepIdle_updates')
						'system'     = $splash.FindName('StepIdle_system')
						'winget'     = $splash.FindName('StepIdle_winget')
						'chocolatey' = $splash.FindName('StepIdle_chocolatey')
						'finalize'   = $splash.FindName('StepIdle_finalize')
					}
					$stepPulseDots = @{
						'updates'    = $splash.FindName('StepPulse_updates')
						'system'     = $splash.FindName('StepPulse_system')
						'winget'     = $splash.FindName('StepPulse_winget')
						'chocolatey' = $splash.FindName('StepPulse_chocolatey')
						'finalize'   = $splash.FindName('StepPulse_finalize')
					}
					$stepChecks = @{
						'updates'    = $splash.FindName('StepCheck_updates')
						'system'     = $splash.FindName('StepCheck_system')
						'winget'     = $splash.FindName('StepCheck_winget')
						'chocolatey' = $splash.FindName('StepCheck_chocolatey')
						'finalize'   = $splash.FindName('StepCheck_finalize')
					}
					$stepLabels = @{
						'updates'    = $splash.FindName('StepLabel_updates')
						'system'     = $splash.FindName('StepLabel_system')
						'winget'     = $splash.FindName('StepLabel_winget')
						'chocolatey' = $splash.FindName('StepLabel_chocolatey')
						'finalize'   = $splash.FindName('StepLabel_finalize')
					}
					$stepStates = @{
						'updates'    = 'pending'
						'system'     = 'pending'
						'winget'     = 'pending'
						'chocolatey' = 'pending'
						'finalize'   = 'pending'
					}
					$activeSplashStepIds = @{}
					foreach ($activeSplashStepId in @($splashStepOrder))
					{
						$activeSplashStepIds[[string]$activeSplashStepId] = $true
					}
					foreach ($knownStepId in @('updates', 'system', 'winget', 'chocolatey', 'finalize'))
					{
						if (-not $activeSplashStepIds.ContainsKey($knownStepId))
						{
							[void]$stepGlyphs.Remove($knownStepId)
							[void]$stepIdleDots.Remove($knownStepId)
							[void]$stepPulseDots.Remove($knownStepId)
							[void]$stepChecks.Remove($knownStepId)
							[void]$stepLabels.Remove($knownStepId)
							[void]$stepStates.Remove($knownStepId)
						}
					}
					$syncHash['StepGlyphs'] = $stepGlyphs
					$syncHash['StepIdleDots'] = $stepIdleDots
					$syncHash['StepPulseDots'] = $stepPulseDots
					$syncHash['StepChecks'] = $stepChecks
					$syncHash['StepLabels'] = $stepLabels
					$syncHash['StepStates'] = $stepStates
					$syncHash['StepOrder'] = @($splashStepOrder)
					$syncHash['SplashTheme'] = $SplashTheme
					$primeInitialStepAction = {
						param([string]$Source = 'unknown')
						if (-not [bool]$syncHash['InitialStepPrimeApplied'])
						{
							try
							{
								$initialStepId = if ($splashStepOrder.Count -gt 0) { [string]$splashStepOrder[0] } else { 'finalize' }
								$stateApplied = $true
								$stepApplied = $false
								if ($startUpdatesPulse)
								{
									$subActionPanelControl = if ($syncHash.ContainsKey('SubActionPanel')) { $syncHash['SubActionPanel'] } else { $null }
									if ($subActionPanelControl) { $subActionPanelControl.Visibility = [System.Windows.Visibility]::Collapsed }
								}

								$stateTable = if ($syncHash.ContainsKey('StepStates')) { $syncHash['StepStates'] } else { $null }
								$idleDots = if ($syncHash.ContainsKey('StepIdleDots')) { $syncHash['StepIdleDots'] } else { $null }
								$pulseDots = if ($syncHash.ContainsKey('StepPulseDots')) { $syncHash['StepPulseDots'] } else { $null }
								$checks = if ($syncHash.ContainsKey('StepChecks')) { $syncHash['StepChecks'] } else { $null }
								$labels = if ($syncHash.ContainsKey('StepLabels')) { $syncHash['StepLabels'] } else { $null }
								if ($stateTable -and $stateTable.ContainsKey($initialStepId))
								{
									$stateTable[$initialStepId] = 'in_progress'
									if ($idleDots -and $idleDots.ContainsKey($initialStepId) -and $idleDots[$initialStepId]) { $idleDots[$initialStepId].Visibility = [System.Windows.Visibility]::Collapsed }
									if ($checks -and $checks.ContainsKey($initialStepId) -and $checks[$initialStepId]) { $checks[$initialStepId].Visibility = [System.Windows.Visibility]::Collapsed }
									if ($pulseDots -and $pulseDots.ContainsKey($initialStepId) -and $pulseDots[$initialStepId])
									{
										$pulseDots[$initialStepId].Visibility = [System.Windows.Visibility]::Visible
									}
									if ($labels -and $labels.ContainsKey($initialStepId) -and $labels[$initialStepId])
									{
										$activeStepBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($splashStepActive))
										$labels[$initialStepId].Foreground = $activeStepBrush
									}
									$syncHash['ChecklistProgressActive'] = $true
									$progressBarControl = if ($syncHash.ContainsKey('ProgressBar')) { $syncHash['ProgressBar'] } else { $null }
									if ($progressBarControl)
									{
										try
										{
											$progressBarControl.Visibility = [System.Windows.Visibility]::Visible
											$progressBarControl.IsIndeterminate = $false
											$barWidth = 330.0
											try { $barWidth = Get-BaselineSplashProgressWidth -ProgressBar $progressBarControl } catch {
												if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1122' -Severity Debug }
											 $barWidth = 330.0 }
											$stepCount = [Math]::Max(1, [double]$splashStepOrder.Count)
											$activeIdx = [Array]::IndexOf($splashStepOrder, $initialStepId)
											if ($activeIdx -lt 0) { $activeIdx = 0 }
											$fillFrom = ([double]$activeIdx / $stepCount) * $barWidth
											$fillTo = (([double]$activeIdx + 0.35) / $stepCount) * $barWidth
											$progressBarControl.Maximum = $barWidth
											$progressBarControl.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $null)
											$progressBarControl.Value = $fillFrom
											$fill = New-Object System.Windows.Media.Animation.DoubleAnimation
											$fill.From = $fillFrom
											$fill.To = $fillTo
											$fill.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(2200))
											$fillEase = New-Object System.Windows.Media.Animation.CubicEase
											$fillEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
											$fill.EasingFunction = $fillEase
											$fill.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
											$progressBarControl.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $fill, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
										}
										catch
										{
											if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1141' -Severity Debug }

											& $writeSplashTrace ('Bootstrap splash initial progress failed: {0}' -f $_.Exception.Message)
										}
									}
									$stepApplied = $true
								}
								$syncHash['InitialStepPrimeApplied'] = $stepApplied
								& $writeSplashTrace ('Bootstrap splash initial step {0}: stepId={1} state={2} step={3}' -f $Source, $initialStepId, $stateApplied, $stepApplied)
							}
							catch
							{
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1151' -Severity Debug }

								$syncHash['ErrorType'] = $_.Exception.GetType().FullName
								$syncHash['ErrorMessage'] = $_.Exception.Message
								& $writeSplashTrace ('Bootstrap splash initial step failed: {0}' -f $_.Exception.Message)
							}
						}
					}.GetNewClosure()

					$recordSplashShownAction = {
						param([string]$Source)

						try
						{
							& $writeSplashTrace ('Bootstrap splash shown state recorded: {0}' -f $Source)
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1167' -Severity Debug }

							& $writeSplashTrace ('Bootstrap splash shown-state trace failed: {0}' -f $_.Exception.Message)
						}
					}.GetNewClosure()

					$splash.Add_Loaded({
						try
						{
							& $recordSplashShownAction 'Loaded'
							& $primeInitialStepAction 'Loaded'
							$syncHash['WasLoaded'] = $true
							& $writeSplashTrace 'Bootstrap splash loaded'
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1181' -Severity Debug }

							$syncHash['ErrorType'] = $_.Exception.GetType().FullName
							$syncHash['ErrorMessage'] = $_.Exception.Message
							$syncHash['IsReady'] = $true
							$syncHash['IsAlive'] = $false
							& $writeSplashTrace ('Bootstrap splash load failed: {0}' -f $_.Exception.Message)
							try { $splash.Close() } catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1188' -Severity Debug }
							 $null = $_ }
						}
					})

					$splash.Add_ContentRendered({
						try
						{
							$syncHash['WasShown'] = $true
							$syncHash['WasRendered'] = $true
							& $recordSplashShownAction 'ContentRendered'
							& $primeInitialStepAction 'ContentRendered'
							$syncHash['IsReady'] = $true
							& $writeSplashTrace 'Bootstrap splash content rendered'
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1202' -Severity Debug }

							$syncHash['ErrorType'] = $_.Exception.GetType().FullName
							$syncHash['ErrorMessage'] = $_.Exception.Message
							$syncHash['IsReady'] = $true
							$syncHash['IsAlive'] = $false
							& $writeSplashTrace ('Bootstrap splash content render failed: {0}' -f $_.Exception.Message)
							try { $splash.Close() } catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1209' -Severity Debug }
							 $null = $_ }
						}
					})

					$splash.Add_Activated({
						$syncHash['WindowActive'] = $true
						try { & $writeSplashTrace 'Bootstrap splash activated' } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1215' -Severity Debug }
						 $null = $_ }
					})

					$splash.Add_Deactivated({
						$syncHash['WindowActive'] = $false
						try { & $writeSplashTrace 'Bootstrap splash deactivated' } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1220' -Severity Debug }
						 $null = $_ }
					})

				$splash.Add_Closing({
					if ((-not [bool]$syncHash['ProgrammaticClose']) -and (-not [bool]$syncHash['GuiReady']))
					{
						& $requestSplashAbortAction 'window close'
					}
				}.GetNewClosure())

				$splash.Add_Closed({
					$syncHash['IsAlive'] = $false
					if ((-not [bool]$syncHash['ProgrammaticClose']) -and (-not [bool]$syncHash['GuiReady']))
					{
						$syncHash['UserClosed'] = $true
						$syncHash['AbortRequested'] = $true
						& $writeSplashTrace 'Bootstrap splash closed before GUI readiness; aborting process'
						[System.Environment]::Exit(0)
						try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1238' -Severity Debug }
						 $null = $_ }
					}
					& $writeSplashTrace 'Bootstrap splash closed'
					$splash.Dispatcher.InvokeShutdown()
				}.GetNewClosure())

				& $writeSplashTrace 'Bootstrap splash ShowDialog starting'
				$splash.ShowDialog() | Out-Null
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1247' -Severity Debug }

				$syncHash['ErrorType'] = $_.Exception.GetType().FullName
				$syncHash['ErrorMessage'] = $_.Exception.Message
				$syncHash['IsReady'] = $true
				$syncHash['IsAlive'] = $false
				try
				{
					$traceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
					if (-not [System.IO.Directory]::Exists($traceDirectory))
					{
						[void][System.IO.Directory]::CreateDirectory($traceDirectory)
					}
					$tracePath = Join-Path $traceDirectory 'Baseline-launch-trace.txt'
					$traceBytes = [System.Text.Encoding]::UTF8.GetBytes(("{0:o} Bootstrap splash runspace failed: {1}`r`n" -f [DateTime]::UtcNow, $_.Exception.Message))
					$traceStream = [System.IO.FileStream]::new($tracePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
					try { $traceStream.Write($traceBytes, 0, $traceBytes.Length) }
					finally { $traceStream.Dispose() }
				}
				catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1266' -Severity Debug }
				 $null = $_ }
			}
		})

		Write-EnvironmentLaunchTrace 'Bootstrap splash helper BeginInvoke starting'
		$asyncResult = $ps.BeginInvoke()
		$deadline = [datetime]::Now.AddSeconds(10)
		while (-not $syncHash['IsReady'] -and [datetime]::Now -lt $deadline)
		{
			Start-Sleep -Milliseconds 50
		}
		Write-EnvironmentLaunchTrace ('Bootstrap splash helper wait complete: IsReady={0} IsAlive={1} WasLoaded={2} WasRendered={3} Error={4}' -f [bool]$syncHash['IsReady'], [bool]$syncHash['IsAlive'], [bool]$syncHash['WasLoaded'], [bool]$syncHash['WasRendered'], [string]$syncHash['ErrorMessage'])

		$splashStartupFailed = -not $syncHash['IsAlive']
		if ($splashStartupFailed)
		{
			# Splash never became ready - clean up the background runspace.
			try
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$syncHash['ErrorMessage']))
				{
					Write-EnvironmentLaunchTrace ('Bootstrap splash failed before it became visible: {0}' -f [string]$syncHash['ErrorMessage'])
				}
				else
				{
					Write-EnvironmentLaunchTrace 'Bootstrap splash failed before it became visible.'
				}
			}
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:1294' -Severity Debug }
			 $null = $_ }
			try { $ps.Stop(); $ps.Dispose() } catch { Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.ShowBootstrapLoadingSplash.CleanupPowerShell' }
			try { $runspace.Close(); $runspace.Dispose() } catch { Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.ShowBootstrapLoadingSplash.CleanupRunspace' }
			$__baselineExtractedPartReturnValue = $null
			$__baselineExtractedPartHasReturnValue = $true
			$__baselineExtractedPartDidReturn = $true
		}
		elseif (-not $syncHash['WasRendered'])
		{
			Write-EnvironmentLaunchTrace 'Bootstrap splash render pending after readiness wait; leaving runspace active.'
		}

		if (-not $splashStartupFailed)
		{
			$syncHash['_PowerShell']  = $ps
			$syncHash['_AsyncResult'] = $asyncResult
			$syncHash['_Runspace']    = $runspace

			Write-EnvironmentLaunchTrace ('Bootstrap splash helper returning live splash: IsAlive={0} WasRendered={1} WindowHandle={2}' -f [bool]$syncHash['IsAlive'], [bool]$syncHash['WasRendered'], [string]$syncHash['WindowHandle'])
			$__baselineExtractedPartReturnValue = $syncHash
			$__baselineExtractedPartHasReturnValue = $true
			$__baselineExtractedPartDidReturn = $true
		}
	}
	catch
	{
		Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.ShowBootstrapLoadingSplash'
		Write-EnvironmentLaunchTrace ('Bootstrap splash helper failed: {0}' -f $_.Exception.Message)
		try { if ($ps) { $ps.Stop(); $ps.Dispose() } } catch { Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.ShowBootstrapLoadingSplash.StopPowerShell' }
		try { if ($runspace) { $runspace.Close(); $runspace.Dispose() } } catch { Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.ShowBootstrapLoadingSplash.StopRunspace' }
		$__baselineExtractedPartReturnValue = $null
		$__baselineExtractedPartHasReturnValue = $true
		$__baselineExtractedPartDidReturn = $true
	}
