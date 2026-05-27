
<#
    .SYNOPSIS
#>

function Ensure-SheenProgressBarType
{
	[CmdletBinding()]
	param ()

	if ('SheenProgressBar' -as [type])
	{
		return
	}

	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Drawing
	Add-Type -AssemblyName WindowsFormsIntegration

	$csharpCode = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class SheenProgressBar : Control
{
    private int _minimum = 0;
    private int _maximum = 100;
    private int _value = 0;
    private bool _isIndeterminate = false;
    private float _highlightPhase = 0f;
    private Timer _animTimer;

    public int Minimum
    {
        get { return _minimum; }
        set { _minimum = Math.Max(0, Math.Min(value, _maximum)); Invalidate(); }
    }

    public int Maximum
    {
        get { return _maximum; }
        set
        {
            _maximum = Math.Max(1, value);
            if (_minimum > _maximum) { _minimum = _maximum; }
            if (_value > _maximum) { _value = _maximum; }
            Invalidate();
        }
    }

    public int Value
    {
        get { return _value; }
        set { _value = Math.Max(_minimum, Math.Min(value, _maximum)); Invalidate(); }
    }

    public bool IsIndeterminate
    {
        get { return _isIndeterminate; }
        set { _isIndeterminate = value; Invalidate(); }
    }

	public int SheenWidth { get; set; }
	public int SheenAlphaPeak { get; set; }
	public Color BarColor { get; set; }
	public Color BackgroundColor { get; set; }

    public SheenProgressBar()
    {
        this.DoubleBuffered = true;
        this.MinimumSize = new Size(1, 1);
		this.SheenWidth = 80;
		this.SheenAlphaPeak = 150;
		this.BarColor = Color.FromArgb(0, 120, 215);
		this.BackgroundColor = Color.FromArgb(40, 40, 40);
        _animTimer = new Timer();
        _animTimer.Interval = 30;
        _animTimer.Tick += (s, e) =>
        {
            _highlightPhase += 0.03f;
            if (_highlightPhase > 1.2f) _highlightPhase = -0.2f;
            Invalidate();
        };
        _animTimer.Start();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        Rectangle bounds = new Rectangle(0, 0, this.Width, this.Height);
        using (SolidBrush bgBrush = new SolidBrush(BackgroundColor))
        {
            g.FillRectangle(bgBrush, bounds);
        }

        if (this.Width <= 0 || this.Height <= 0)
        {
            return;
        }

        if (_isIndeterminate)
        {
            int sweepWidth = Math.Max(SheenWidth * 2, Math.Max(30, this.Width / 3));
            int travelWidth = this.Width + sweepWidth + SheenWidth;
            int sweepX = (int)(((_highlightPhase + 0.2f) / 1.4f) * travelWidth) - sweepWidth;
            Rectangle sweepRect = new Rectangle(sweepX, 0, sweepWidth, this.Height);

            using (SolidBrush barBrush = new SolidBrush(BarColor))
            {
                g.FillRectangle(barBrush, sweepRect);
            }

            using (LinearGradientBrush sheenBrush = new LinearGradientBrush(
                sweepRect, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend blend = new ColorBlend();
                blend.Positions = new float[] { 0f, 0.35f, 0.5f, 0.65f, 1f };
                blend.Colors = new Color[]
                {
                    Color.FromArgb(0, 255, 255, 255),
                    Color.FromArgb(SheenAlphaPeak / 2, 255, 255, 255),
                    Color.FromArgb(SheenAlphaPeak, 255, 255, 255),
                    Color.FromArgb(SheenAlphaPeak / 2, 255, 255, 255),
                    Color.FromArgb(0, 255, 255, 255)
                };
                sheenBrush.InterpolationColors = blend;

                Region prev = g.Clip;
                g.SetClip(bounds);
                g.FillRectangle(sheenBrush, sweepRect);
                g.Clip = prev;
            }

            return;
        }

        int range = Math.Max(1, _maximum - _minimum);
        int fillWidth = (int)(((float)(_value - _minimum) / range) * this.Width);
        fillWidth = Math.Max(0, Math.Min(fillWidth, this.Width));
        if (fillWidth <= 0) return;

        Rectangle fillRect = new Rectangle(0, 0, fillWidth, this.Height);
        using (SolidBrush barBrush = new SolidBrush(BarColor))
        {
            g.FillRectangle(barBrush, fillRect);
        }

        if (fillWidth > 4)
        {
            int sheenX = (int)(_highlightPhase * (fillRect.Width + SheenWidth)) - SheenWidth + fillRect.X;
            Rectangle sheenRect = new Rectangle(sheenX, fillRect.Y, SheenWidth, fillRect.Height);

            using (LinearGradientBrush sheenBrush = new LinearGradientBrush(
                sheenRect, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend blend = new ColorBlend();
                blend.Positions = new float[] { 0f, 0.35f, 0.5f, 0.65f, 1f };
                blend.Colors = new Color[]
                {
                    Color.FromArgb(0, 255, 255, 255),
                    Color.FromArgb(SheenAlphaPeak / 2, 255, 255, 255),
                    Color.FromArgb(SheenAlphaPeak, 255, 255, 255),
                    Color.FromArgb(SheenAlphaPeak / 2, 255, 255, 255),
                    Color.FromArgb(0, 255, 255, 255)
                };
                sheenBrush.InterpolationColors = blend;

                Region prev = g.Clip;
                g.SetClip(fillRect);
                g.FillRectangle(sheenBrush, sheenRect);
                g.Clip = prev;
            }
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && _animTimer != null)
        {
            _animTimer.Stop();
            _animTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
"@

	Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies "System.Windows.Forms", "System.Drawing"
}

<#
    .SYNOPSIS
#>

function New-GuiExecutionProgressBarTemplate
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$templateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type ProgressBar}">
	<Grid ClipToBounds="True" SnapsToDevicePixels="True">
		<Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="3" Opacity="0.82"/>
		<Border x:Name="PART_Indicator" HorizontalAlignment="Left" Background="{TemplateBinding Foreground}" CornerRadius="3" Opacity="0.92">
			<Border.Effect>
				<DropShadowEffect Color="{DynamicResource Color.Progress}" BlurRadius="10" ShadowDepth="0" Opacity="0.35"/>
			</Border.Effect>
			<Border.Triggers>
				<EventTrigger RoutedEvent="FrameworkElement.Loaded">
					<BeginStoryboard>
						<Storyboard RepeatBehavior="Forever" AutoReverse="True">
							<DoubleAnimation Storyboard.TargetProperty="Opacity" From="0.82" To="1" Duration="0:0:0.85"/>
						</Storyboard>
					</BeginStoryboard>
				</EventTrigger>
			</Border.Triggers>
		</Border>
		<Border x:Name="PART_BusyIndicator" Width="180" HorizontalAlignment="Left" Background="{TemplateBinding Foreground}" CornerRadius="3" Opacity="0">
			<Border.RenderTransform>
				<TranslateTransform x:Name="BusyIndicatorTransform" X="-180"/>
			</Border.RenderTransform>
			<Border.Effect>
				<DropShadowEffect Color="{DynamicResource Color.Progress}" BlurRadius="12" ShadowDepth="0" Opacity="0.42"/>
			</Border.Effect>
		</Border>
	</Grid>
	<ControlTemplate.Triggers>
		<Trigger Property="IsIndeterminate" Value="True">
			<Setter TargetName="PART_Indicator" Property="Opacity" Value="0"/>
			<Setter TargetName="PART_BusyIndicator" Property="Opacity" Value="0.96"/>
			<Trigger.EnterActions>
				<BeginStoryboard x:Name="BusyIndicatorStoryboard">
					<Storyboard RepeatBehavior="Forever">
						<DoubleAnimation Storyboard.TargetName="BusyIndicatorTransform" Storyboard.TargetProperty="X" From="-180" To="900" Duration="0:0:1.05"/>
					</Storyboard>
				</BeginStoryboard>
			</Trigger.EnterActions>
			<Trigger.ExitActions>
				<StopStoryboard BeginStoryboardName="BusyIndicatorStoryboard"/>
			</Trigger.ExitActions>
		</Trigger>
	</ControlTemplate.Triggers>
</ControlTemplate>
'@
	return [System.Windows.Markup.XamlReader]::Parse($templateXaml)
}

<#
    .SYNOPSIS
#>

function New-SharedProgressBarHost
{
	[CmdletBinding()]
	param (
		[int]$Maximum = 100,
		[int]$Value = 0,
		[switch]$Indeterminate,
		[double]$Height = $Script:GuiLayout.ProgressBarHeight,
		[double]$MinWidth = $Script:GuiLayout.ProgressBarMinWidth
	)

	$progressBar = New-Object System.Windows.Controls.ProgressBar
	$progressBar.Minimum = 0
	$progressBar.Maximum = [Math]::Max(1, $Maximum)
	$progressBar.Value = [Math]::Min([Math]::Max(0, $Value), $progressBar.Maximum)
	$progressBar.IsIndeterminate = [bool]$Indeterminate
	$progressBar.Height = $Height
	$progressBar.MinHeight = $Height
	$progressBar.MinWidth = $MinWidth
	$progressBar.HorizontalAlignment = 'Stretch'
	$progressBar.VerticalAlignment = 'Center'
	$progressBar.BorderThickness = [System.Windows.Thickness]::new(0)
	$progressBar.Template = New-GuiExecutionProgressBarTemplate
	Set-SheenProgressBarTheme -ProgressBar $progressBar

	return @{
		Host        = $progressBar
		ProgressBar = $progressBar
	}
}

<#
    .SYNOPSIS
#>

function Set-SheenProgressBarTheme
{
	[CmdletBinding()]
	param (
		[object]$ProgressBar,
		[hashtable]$Theme = $null
	)

	if (-not $ProgressBar)
	{
		return
	}

	if (-not $Theme)
	{
		$Theme = Get-GuiCurrentTheme
	}

	if (-not $Theme)
	{
		return
	}

	try
	{
		$progressColor = if ($Theme.ContainsKey('ProgressGreen') -and -not [string]::IsNullOrWhiteSpace([string]$Theme.ProgressGreen)) { [string]$Theme.ProgressGreen } else { [string]$Theme.AccentBlue }
		$progressTrack = if ($Theme.ContainsKey('ProgressGreenTrack') -and -not [string]::IsNullOrWhiteSpace([string]$Theme.ProgressGreenTrack)) { [string]$Theme.ProgressGreenTrack } else { [string]$Theme.CardBorder }
		if ($ProgressBar -is [System.Windows.Controls.ProgressBar])
		{
			$ProgressBar.Foreground = ConvertTo-GuiBrush -Color $progressColor -Context 'SharedProgress.ProgressBar.Foreground'
			$ProgressBar.Background = ConvertTo-GuiBrush -Color $progressTrack -Context 'SharedProgress.ProgressBar.Background'
			return
		}
		$ProgressBar.BarColor = [System.Drawing.ColorTranslator]::FromHtml($progressColor)
		$ProgressBar.BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml($progressTrack)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ProgressNavChrome.Set-SheenProgressBarTheme:catch330' -Severity Debug }

		$null = $_
	}
}

<#
    .SYNOPSIS
#>

function Set-SharedProgressBarState
{
	[CmdletBinding()]
	param (
		[object]$ProgressBar,
		[object]$ProgressText,
		[int]$Completed = 0,
		[int]$Total = 0,
		[string]$CurrentAction = $null,
		[switch]$Indeterminate,
		[switch]$PassThruText
	)

	$displayText = $null
	if ($ProgressBar)
	{
		if ($Indeterminate -or $Total -le 0)
		{
			if ($ProgressBar.PSObject.Properties['IsIndeterminate'])
			{
				$ProgressBar.IsIndeterminate = $true
			}
			if ($ProgressBar.PSObject.Properties['Maximum'])
			{
				$ProgressBar.Maximum = 1
			}
			if ($ProgressBar.PSObject.Properties['Value'])
			{
				$ProgressBar.Value = 0
			}
		}
		else
		{
			$safeTotal = [Math]::Max(1, $Total)
			$safeCompleted = [Math]::Min([Math]::Max(0, $Completed), $safeTotal)
			if ($ProgressBar.PSObject.Properties['IsIndeterminate'])
			{
				$ProgressBar.IsIndeterminate = $false
			}
			if ($ProgressBar.PSObject.Properties['Maximum'])
			{
				$ProgressBar.Maximum = $safeTotal
			}
			if ($ProgressBar.PSObject.Properties['Value'])
			{
				$ProgressBar.Value = $safeCompleted
			}
		}
	}

	if ($ProgressText)
	{
		if ($Indeterminate -or $Total -le 0)
		{
			$displayText = if ([string]::IsNullOrWhiteSpace([string]$CurrentAction))
			{
				Get-UxExecutionPlaceholderText -Kind 'Working'
			}
			else
			{
				[string]$CurrentAction
			}
			$ProgressText.Text = $displayText
		}
		else
		{
			$safeTotal = [Math]::Max(1, $Total)
			$safeCompleted = [Math]::Min([Math]::Max(0, $Completed), $safeTotal)
			$pct = [Math]::Round(($safeCompleted / [double]$safeTotal) * 100)
			$displayText = '{0}/{1} ({2}%)' -f $safeCompleted, $safeTotal, $pct
			$ProgressText.Text = $displayText
			if (-not [string]::IsNullOrWhiteSpace([string]$CurrentAction))
			{
				$ProgressText.Text += " - $CurrentAction"
			}
			$displayText = $ProgressText.Text
		}
	}
	elseif (-not $Indeterminate -and $Total -gt 0)
	{
		$safeTotal = [Math]::Max(1, $Total)
		$safeCompleted = [Math]::Min([Math]::Max(0, $Completed), $safeTotal)
		$pct = [Math]::Round(($safeCompleted / [double]$safeTotal) * 100)
		$displayText = '{0}/{1} ({2}%)' -f $safeCompleted, $safeTotal, $pct
		if (-not [string]::IsNullOrWhiteSpace([string]$CurrentAction))
		{
			$displayText += " - $CurrentAction"
		}
	}

	if ($PassThruText)
	{
		return $displayText
	}
}

<#
    .SYNOPSIS
    Applies active/inactive chrome to the top-nav mode radio buttons so the
    segmented-control state is visually unambiguous.
#>

function Set-GuiNavButtonChrome
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Button,
		[Parameter(Mandatory = $true)]
		[bool]$IsActive
	)

	if (-not $Button) { return }

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'Set-GuiNavButtonChrome'

	if ($IsActive)
	{
		$bgColor     = if ($theme -and $theme.ContainsKey('AccentBlue'))         { [string]$theme.AccentBlue }         else { '#3B82F6' }
		$hoverColor  = if ($theme -and $theme.ContainsKey('AccentHover'))        { [string]$theme.AccentHover }        else { '#60A5FA' }
		$borderColor = if ($theme -and $theme.ContainsKey('ActiveTabIndicator')) { [string]$theme.ActiveTabIndicator } else { '#7CB7FF' }
		$fgColor     = '#FFFFFF'
		$thickness   = 2
		$fontWeight  = [System.Windows.FontWeights]::SemiBold
	}
	else
	{
		$bgColor     = 'Transparent'
		$hoverColor  = if ($theme -and $theme.ContainsKey('TabHoverBg'))      { [string]$theme.TabHoverBg }      else { '#3670B8' }
		$borderColor = if ($theme -and $theme.ContainsKey('BorderColor'))     { [string]$theme.BorderColor }     else { '#293044' }
		$fgColor     = if ($theme -and $theme.ContainsKey('TextSecondary'))   { [string]$theme.TextSecondary }   else { '#9CA3AF' }
		$thickness   = 1
		$fontWeight  = [System.Windows.FontWeights]::Normal
	}

	$bgBrush = $bc.ConvertFromString($bgColor)
	$hoverBrush = $bc.ConvertFromString($hoverColor)
	$borderBrush = $bc.ConvertFromString($borderColor)
	$fgBrush = $bc.ConvertFromString($fgColor)

	$Button.Template = $null
	$Button.Background = $bgBrush
	$Button.BorderBrush = $borderBrush
	$Button.BorderThickness = [System.Windows.Thickness]::new($thickness)
	$Button.Foreground = $fgBrush
	$Button.FontWeight = $fontWeight
	$Button.Cursor = [System.Windows.Input.Cursors]::Hand
	$Button.FocusVisualStyle = $null

	$tmpl = New-Object System.Windows.Controls.ControlTemplate($Button.GetType())
	$bd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
	$bd.Name = 'Bd'
	$bd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(5))
	$bd.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(12, 5, 12, 5))
	$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bgBrush)
	$bd.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $borderBrush)
	$bd.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new($thickness))
	$cp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
	$cp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
	$cp.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
	$bd.AppendChild($cp)
	$tmpl.VisualTree = $bd

	$hoverTrigger = New-Object System.Windows.Trigger
	$hoverTrigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
	$hoverTrigger.Value = $true
	[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $hoverBrush -TargetName 'Bd')))
	[void]($tmpl.Triggers.Add($hoverTrigger))

	$Button.Template = $tmpl
}

function Update-GuiNavModeChrome
{
	[CmdletBinding()]
	param ()

	$appsActive = [bool]$Script:AppsModeActive
	$gamingActive = [bool]$Script:GamingModeActive
	$updatesActive = [bool]$Script:UpdatesModeActive
	$deploymentMediaActive = [bool]$Script:DeploymentMediaModeActive
	if ($Script:NavModeTweaks) { Set-GuiNavButtonChrome -Button $Script:NavModeTweaks -IsActive (-not $appsActive -and -not $gamingActive -and -not $updatesActive -and -not $deploymentMediaActive) }
	if ($Script:NavModeGaming) { Set-GuiNavButtonChrome -Button $Script:NavModeGaming -IsActive $gamingActive }
	if ($Script:NavModeApps) { Set-GuiNavButtonChrome -Button $Script:NavModeApps -IsActive $appsActive }
	if ($Script:NavModeUpdates) { Set-GuiNavButtonChrome -Button $Script:NavModeUpdates -IsActive $updatesActive }
	if ($Script:NavModeDeploymentMedia) { Set-GuiNavButtonChrome -Button $Script:NavModeDeploymentMedia -IsActive $deploymentMediaActive }
}

function Set-GuiNavModeCheckedState
{
	[CmdletBinding()]
	param ()

	$previousSuppressNavModeSelectionChanged = [bool]$Script:SuppressNavModeSelectionChanged
	$Script:SuppressNavModeSelectionChanged = $true
	try
	{
		$appsActive = [bool]$Script:AppsModeActive
		$gamingActive = [bool]$Script:GamingModeActive
		$updatesActive = [bool]$Script:UpdatesModeActive
		$deploymentMediaActive = [bool]$Script:DeploymentMediaModeActive
		if ($Script:NavModeTweaks) { $Script:NavModeTweaks.IsChecked = (-not $appsActive -and -not $gamingActive -and -not $updatesActive -and -not $deploymentMediaActive) }
		if ($Script:NavModeGaming) { $Script:NavModeGaming.IsChecked = $gamingActive }
		if ($Script:NavModeApps) { $Script:NavModeApps.IsChecked = $appsActive }
		if ($Script:NavModeUpdates) { $Script:NavModeUpdates.IsChecked = $updatesActive }
		if ($Script:NavModeDeploymentMedia) { $Script:NavModeDeploymentMedia.IsChecked = $deploymentMediaActive }
	}
	finally
	{
		$Script:SuppressNavModeSelectionChanged = $previousSuppressNavModeSelectionChanged
	}

	try { Update-GuiNavModeChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-GuiNavModeCheckedState.UpdateGuiNavModeChrome' }
}

function Clear-GuiTabContentIfOwnedBy
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$PrimaryTab
	)

	if (-not $ContentScroll)
	{
		return
	}

	if ([string]$Script:VisibleTabContentPrimaryTab -ne $PrimaryTab)
	{
		return
	}

	try
	{
		if ($null -eq $Script:TabContentBuildGeneration)
		{
			$Script:TabContentBuildGeneration = 0
		}
		$Script:TabContentBuildGeneration = [int]$Script:TabContentBuildGeneration + 1
		$ContentScroll.Content = $null
		$Script:VisibleTabContentPrimaryTab = $null
		if ($Script:PresetStatusBadge)
		{
			$Script:PresetStatusBadge = $null
		}
		if ($Script:UpdateGuiBackToTopButtonScript)
		{
			& $Script:UpdateGuiBackToTopButtonScript
		}
		if ($ContentScroll.Dispatcher)
		{
			$ContentScroll.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [System.Action]{})
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Clear-GuiTabContentIfOwnedBy'
	}
}

function Copy-GuiControlSelectionState
{
	[CmdletBinding()]
	param (
		[object]$Control
	)

	if (-not $Control)
	{
		return $null
	}

	$state = [ordered]@{}
	foreach ($fieldName in @('IsChecked', 'SelectedIndex', 'SelectedDate', 'Value', 'NumericValue', 'ACValue', 'DCValue', 'Run', 'Text'))
	{
		if (Test-GuiObjectField -Object $Control -FieldName $fieldName)
		{
			$state[$fieldName] = $Control.$fieldName
		}
	}

	$children = @{}
	foreach ($childField in @('CheckBox', 'ComboBox', 'DatePicker', 'ACSlider', 'DCSlider'))
	{
		if (-not (Test-GuiObjectField -Object $Control -FieldName $childField) -or -not $Control.$childField)
		{
			continue
		}

		$childState = [ordered]@{}
		foreach ($fieldName in @('IsChecked', 'SelectedIndex', 'SelectedDate', 'Value', 'Text'))
		{
			if (Test-GuiObjectField -Object $Control.$childField -FieldName $fieldName)
			{
				$childState[$fieldName] = $Control.$childField.$fieldName
			}
		}
		if ($childState.Count -gt 0)
		{
			$children[$childField] = [pscustomobject]$childState
		}
	}
	if ($children.Count -gt 0)
	{
		$state.Children = $children
	}

	if ($state.Count -eq 0)
	{
		return $null
	}

	return [pscustomobject]$state
}

function Set-GuiControlSelectionState
{
	[CmdletBinding()]
	param (
		[object]$Control,
		[object]$State
	)

	if (-not $Control -or -not $State)
	{
		return
	}

	$hadRestoringFlag = (Test-GuiObjectField -Object $Control -FieldName 'IsRestoring')
	$previousRestoring = $false
	if ($hadRestoringFlag)
	{
		$previousRestoring = [bool]$Control.IsRestoring
		$Control.IsRestoring = $true
	}

	try
	{
		foreach ($fieldName in @('IsChecked', 'SelectedIndex', 'SelectedDate', 'Value', 'NumericValue', 'ACValue', 'DCValue', 'Run', 'Text'))
		{
			if ((Test-GuiObjectField -Object $Control -FieldName $fieldName) -and (Test-GuiObjectField -Object $State -FieldName $fieldName))
			{
				$Control.$fieldName = $State.$fieldName
			}
		}

		if ((Test-GuiObjectField -Object $State -FieldName 'Children') -and $State.Children -is [System.Collections.IDictionary])
		{
			foreach ($childName in @($State.Children.Keys))
			{
				if (-not (Test-GuiObjectField -Object $Control -FieldName ([string]$childName)) -or -not $Control.$childName)
				{
					continue
				}

				$childState = $State.Children[$childName]
				foreach ($fieldName in @('IsChecked', 'SelectedIndex', 'SelectedDate', 'Value', 'Text'))
				{
					if ((Test-GuiObjectField -Object $Control.$childName -FieldName $fieldName) -and (Test-GuiObjectField -Object $childState -FieldName $fieldName))
					{
						$Control.$childName.$fieldName = $childState.$fieldName
					}
				}
			}
		}
	}
	finally
	{
		if ($hadRestoringFlag)
		{
			$Control.IsRestoring = $previousRestoring
		}
	}
}

function Clear-GuiControlSelectionState
{
	[CmdletBinding()]
	param (
		[object]$Control
	)

	if (-not $Control)
	{
		return
	}

	$hadRestoringFlag = (Test-GuiObjectField -Object $Control -FieldName 'IsRestoring')
	$previousRestoring = $false
	if ($hadRestoringFlag)
	{
		$previousRestoring = [bool]$Control.IsRestoring
		$Control.IsRestoring = $true
	}

	try
	{
		if (Test-GuiObjectField -Object $Control -FieldName 'IsChecked') { $Control.IsChecked = $false }
		if (Test-GuiObjectField -Object $Control -FieldName 'SelectedIndex') { $Control.SelectedIndex = [int]-1 }
		if (Test-GuiObjectField -Object $Control -FieldName 'SelectedDate') { $Control.SelectedDate = $null }
		foreach ($childField in @('CheckBox', 'ComboBox', 'DatePicker', 'ACSlider', 'DCSlider'))
		{
			if (-not (Test-GuiObjectField -Object $Control -FieldName $childField) -or -not $Control.$childField)
			{
				continue
			}
			if (Test-GuiObjectField -Object $Control.$childField -FieldName 'IsChecked') { $Control.$childField.IsChecked = $false }
			if (Test-GuiObjectField -Object $Control.$childField -FieldName 'SelectedIndex') { $Control.$childField.SelectedIndex = [int]-1 }
			if (Test-GuiObjectField -Object $Control.$childField -FieldName 'SelectedDate') { $Control.$childField.SelectedDate = $null }
		}
	}
	finally
	{
		if ($hadRestoringFlag)
		{
			$Control.IsRestoring = $previousRestoring
		}
	}
}

function Save-GuiStandardSelectionStateForGaming
{
	[CmdletBinding()]
	param ()

	if ($Script:StandardSelectionStateBeforeGaming)
	{
		return
	}

	$controlStates = @{}
	if ($Script:Controls -is [System.Collections.IDictionary])
	{
		foreach ($controlKey in @($Script:Controls.Keys))
		{
			$controlState = Copy-GuiControlSelectionState -Control $Script:Controls[$controlKey]
			if ($controlState)
			{
				$controlStates[$controlKey] = $controlState
			}
		}
	}

	$explicitDefinitions = @{}
	if (Get-Command -Name 'Initialize-GuiSelectionStateStores' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Initialize-GuiSelectionStateStores
	}
	if ($Script:ExplicitPresetSelectionDefinitions -is [System.Collections.IDictionary])
	{
		foreach ($definitionKey in @($Script:ExplicitPresetSelectionDefinitions.Keys))
		{
			$definition = $Script:ExplicitPresetSelectionDefinitions[$definitionKey]
			if (-not $definition) { continue }
			$definitionCopy = if (Get-Command -Name 'Copy-GuiExplicitSelectionDefinition' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Copy-GuiExplicitSelectionDefinition -Definition $definition -FunctionName ([string]$definitionKey)
			}
			else
			{
				$definition
			}
			if ($definitionCopy)
			{
				$explicitDefinitions[[string]$definitionKey] = $definitionCopy
			}
		}
	}

	$Script:StandardSelectionStateBeforeGaming = [pscustomobject]@{
		ControlStates = $controlStates
		ExplicitDefinitions = $explicitDefinitions
	}
}

function Restore-GuiStandardSelectionStateAfterGaming
{
	[CmdletBinding()]
	param ()

	$snapshot = $Script:StandardSelectionStateBeforeGaming
	if (-not $snapshot)
	{
		return
	}

	$previousGameModeControlSync = [bool]$Script:GameModeControlSyncInProgress
	$previousBulkUpdate = [bool]$Script:GuiSelectionBulkUpdateInProgress
	$Script:GameModeControlSyncInProgress = $true
	$Script:GuiSelectionBulkUpdateInProgress = $true
	try
	{
		$controlStates = if ((Test-GuiObjectField -Object $snapshot -FieldName 'ControlStates') -and $snapshot.ControlStates -is [System.Collections.IDictionary]) { $snapshot.ControlStates } else { @{} }
		if ($Script:Controls -is [System.Collections.IDictionary])
		{
			foreach ($controlKey in @($Script:Controls.Keys))
			{
				if ($controlStates.ContainsKey($controlKey))
				{
					Set-GuiControlSelectionState -Control $Script:Controls[$controlKey] -State $controlStates[$controlKey]
				}
				else
				{
					Clear-GuiControlSelectionState -Control $Script:Controls[$controlKey]
				}
			}
		}

		if (Get-Command -Name 'Initialize-GuiSelectionStateStores' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Initialize-GuiSelectionStateStores
		}

		if ($Script:ExplicitPresetSelectionDefinitions -is [System.Collections.IDictionary])
		{
			foreach ($definitionKey in @($Script:ExplicitPresetSelectionDefinitions.Keys))
			{
				$definition = $Script:ExplicitPresetSelectionDefinitions[$definitionKey]
				if ($definition -and (Test-GuiObjectField -Object $definition -FieldName 'Source') -and [string]$definition.Source -eq 'GameMode')
				{
					Remove-GuiExplicitSelectionDefinition -FunctionName ([string]$definitionKey)
				}
			}
		}

		$explicitDefinitions = if ((Test-GuiObjectField -Object $snapshot -FieldName 'ExplicitDefinitions') -and $snapshot.ExplicitDefinitions -is [System.Collections.IDictionary]) { $snapshot.ExplicitDefinitions } else { @{} }
		foreach ($definitionKey in @($explicitDefinitions.Keys))
		{
			Set-GuiExplicitSelectionDefinition -FunctionName ([string]$definitionKey) -Definition $explicitDefinitions[$definitionKey]
		}
	}
	finally
	{
		$Script:GameModeControlSyncInProgress = $previousGameModeControlSync
		$Script:GuiSelectionBulkUpdateInProgress = $previousBulkUpdate
		$Script:StandardSelectionStateBeforeGaming = $null
	}
}

function Set-GuiGamingRuntimeState
{
	[CmdletBinding()]
	param (
		[bool]$Enabled
	)

	$Script:GameMode = [bool]$Enabled
	if ($Script:Ctx -and $Script:Ctx.ContainsKey('Mode'))
	{
		$Script:Ctx.Mode.Game = [bool]$Enabled
	}

	if (Get-Command -Name 'Update-SessionStatistics' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-SessionStatistics -Values @{
			GameModeActive  = [bool]$Enabled
			GameModeProfile = if ($Enabled -and -not [string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { [string]$Script:GameModeProfile } else { $null }
		}
	}

	if ($Script:SyncGameModeContextStateScript)
	{
		& $Script:SyncGameModeContextStateScript
	}
	elseif (Get-Command -Name 'Sync-GameModeContextState' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Sync-GameModeContextState
	}
}

function Set-GuiOptimizeFilterChromeVisible
{
	[CmdletBinding()]
	param (
		[bool]$Visible
	)

	$collapsed = [System.Windows.Visibility]::Collapsed
	$visibleState = [System.Windows.Visibility]::Visible
	$safeModeActive = $false
	if (Get-Command -Name 'Test-IsSafeModeUX' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$safeModeActive = [bool](Test-IsSafeModeUX)
	}

	$shouldShow = [bool]$Visible -and -not $safeModeActive
	$panel = $Script:FilterOptionsPanel
	if (-not $shouldShow)
	{
		if ($panel -and -not $safeModeActive)
		{
			$Script:OptimizeFilterPanelExpandedBeforeModeHide = ($panel.Visibility -eq $visibleState)
		}
		if ($Script:BtnFilterToggle) { $Script:BtnFilterToggle.Visibility = $collapsed }
		if ($panel) { $panel.Visibility = $collapsed }
		if ($Script:MenuViewFilters)
		{
			try { $Script:MenuViewFilters.IsChecked = $false } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.SetGuiOptimizeFilterChromeVisible.MenuViewFilters.Hide' }
		}
		return
	}

	if ($Script:BtnFilterToggle) { $Script:BtnFilterToggle.Visibility = $visibleState }

	$rememberedState = Get-Variable -Name 'OptimizeFilterPanelExpandedBeforeModeHide' -Scope Script -ErrorAction SilentlyContinue
	if ($rememberedState)
	{
		$expanded = [bool]$rememberedState.Value
		Remove-Variable -Name 'OptimizeFilterPanelExpandedBeforeModeHide' -Scope Script -ErrorAction SilentlyContinue
	}
	else
	{
		$expanded = ($panel -and $panel.Visibility -eq $visibleState)
	}

	if (Get-Command -Name 'Set-GuiFilterPanelExpandedState' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $expanded
		return
	}

	if ($panel)
	{
		$panel.Visibility = if ($expanded) { $visibleState } else { $collapsed }
	}
	if ($Script:MenuViewFilters)
	{
		try { $Script:MenuViewFilters.IsChecked = [bool]$expanded } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.SetGuiOptimizeFilterChromeVisible.MenuViewFilters.Show' }
	}
}

<#
    .SYNOPSIS
#>

function Set-GuiGamingMode
{
	[CmdletBinding()]
	param (
		[bool]$Enable = $false,
		[switch]$SkipContentRestore
	)

	if ([bool]$Script:GamingModeActive -eq $Enable)
	{
		if ($Enable -and -not [bool]$Script:GameMode)
		{
			Save-GuiStandardSelectionStateForGaming
			Set-GuiGamingRuntimeState -Enabled:$true
			if ($Script:SyncGameModePlanToGamingControlsScript)
			{
				& $Script:SyncGameModePlanToGamingControlsScript
			}
		}
		elseif (-not $Enable)
		{
			Restore-GuiStandardSelectionStateAfterGaming
			Clear-GuiTabContentIfOwnedBy -PrimaryTab 'Gaming'
		}
		return
	}

	$collapsed = [System.Windows.Visibility]::Collapsed
	$visible = [System.Windows.Visibility]::Visible

	if ($Enable)
	{
		if (Get-Command -Name 'Stop-GuiTabContentBackgroundBuilds' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Stop-GuiTabContentBackgroundBuilds
		}
		$selectedPrimaryTab = if ($Script:PrimaryTabs -and $Script:PrimaryTabs.SelectedItem -and $Script:PrimaryTabs.SelectedItem.Tag) { [string]$Script:PrimaryTabs.SelectedItem.Tag } else { $null }
		$Script:GamingReturnPrimaryTab = if (-not [string]::IsNullOrWhiteSpace($selectedPrimaryTab) -and $selectedPrimaryTab -ne $Script:SearchResultsTabTag) { $selectedPrimaryTab } elseif (-not [string]::IsNullOrWhiteSpace([string]$Script:LastStandardPrimaryTab)) { [string]$Script:LastStandardPrimaryTab } else { 'Initial Setup' }
		Save-GuiStandardSelectionStateForGaming
		$Script:GamingModeActive = $true
		Set-GuiGamingRuntimeState -Enabled:$true
		if ([bool]$Script:AppsModeActive)
		{
			Set-GuiAppsMode -Enable:$false
		}
		if ([bool]$Script:DeploymentMediaModeActive -and (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-GuiDeploymentMediaMode -Enable:$false
		}
		if ([bool]$Script:UpdatesModeActive -and (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-GuiUpdatesMode -Enable:$false
		}
	}
	else
	{
		$Script:GamingModeActive = $false
		Set-GuiGamingRuntimeState -Enabled:$false
		Restore-GuiStandardSelectionStateAfterGaming
		Clear-GuiTabContentIfOwnedBy -PrimaryTab 'Gaming'
	}

	if ($Enable)
	{
		$Script:AppsModeActive = $false
		$Script:UpdatesModeActive = $false
		$Script:DeploymentMediaModeActive = $false
	}

	Set-GuiNavModeCheckedState

	if ($Script:ModeSubtitle)
	{
		$subtitleKey = if ($Enable) { 'GuiGameModeHeader' } else { 'Nav_OptimizeSubtitle' }
		$subtitleFallback = if ($Enable) { 'Game Mode' } else { 'Configure system behavior' }
		$Script:ModeSubtitle.Text = (Get-UxLocalizedString -Key $subtitleKey -Fallback $subtitleFallback)
		$Script:ModeSubtitle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
	}

	if ($Script:TweaksView) { $Script:TweaksView.Visibility = $visible }
	if ($Script:AppsView) { $Script:AppsView.Visibility = $collapsed }
	if ($Script:DeploymentMediaView) { $Script:DeploymentMediaView.Visibility = $collapsed }
	if ($Script:PrimaryTabHost) { $Script:PrimaryTabHost.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:ExpertModeBanner)
	{
		$Script:ExpertModeBanner.Visibility = if ($Enable)
		{
			$collapsed
		}
		elseif ((Get-Command -Name 'Test-IsExpertModeUX' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-IsExpertModeUX))
		{
			$visible
		}
		else
		{
			$collapsed
		}
	}
	Set-GuiOptimizeFilterChromeVisible -Visible $true
	if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.Visibility = $visible }
	if ($Script:BtnDefaults) { $Script:BtnDefaults.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnRun) { $Script:BtnRun.Visibility = $visible }
	if ($Script:BtnApplyQueuedActions) { $Script:BtnApplyQueuedActions.Visibility = $collapsed }
	if ($Script:BtnDeploymentMediaPreviewPlan) { $Script:BtnDeploymentMediaPreviewPlan.Visibility = $collapsed }
	if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.Visibility = $collapsed }

	if ($Enable)
	{
		if (Get-Command -Name 'Build-TabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Build-TabContent -PrimaryTab 'Gaming' -SkipIdlePrebuild
		}
		if ($Script:SyncGameModePlanToGamingControlsScript)
		{
			& $Script:SyncGameModePlanToGamingControlsScript
		}
		if ([string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile))
		{
			$message = Get-UxLocalizedString -Key 'GuiGamingWorkflowReadyStatus' -Fallback 'Gaming workflow ready. Choose a profile to build a gaming plan.'
			$Script:PresetStatusMessage = $message
			if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
			{
				$Script:PresetStatusBadge.Child.Text = $message
			}
			if ($Script:UpdateGameModeStatusTextScript)
			{
				& $Script:UpdateGameModeStatusTextScript -Message $message -Tone 'Accent'
			}
		}
	}
	elseif (-not $SkipContentRestore -and -not [bool]$Script:AppsModeActive -and -not [bool]$Script:UpdatesModeActive -and -not [bool]$Script:DeploymentMediaModeActive)
	{
		$restoreTab = if (-not [string]::IsNullOrWhiteSpace([string]$Script:GamingReturnPrimaryTab)) { [string]$Script:GamingReturnPrimaryTab } else { 'Initial Setup' }
		if ($Script:PrimaryTabs)
		{
			foreach ($tab in $Script:PrimaryTabs.Items)
			{
				if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -eq $restoreTab))
				{
					$Script:PrimaryTabs.SelectedItem = $tab
					break
				}
			}
		}
		if (Get-Command -Name 'Build-TabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Build-TabContent -PrimaryTab $restoreTab -SkipIdlePrebuild
		}
	}

	if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if ($Script:SyncUxActionButtonTextScript)
		{
			& $Script:SyncUxActionButtonTextScript
		}
		else
		{
			Sync-UxActionButtonText
		}
	}
	if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-GuiScopedRunActionAvailability
	}
	if ($Script:UpdateGuiBackToTopButtonScript)
	{
		try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-GuiGamingMode.UpdateBackToTopButton' }
	}
}

<#
    .SYNOPSIS
#>

function Set-GuiUpdatesMode
{
	[CmdletBinding()]
	param (
		[bool]$Enable = $false
	)

	if ($Script:UpdatesModeActive -eq $Enable)
	{
		return
	}

	$collapsed = [System.Windows.Visibility]::Collapsed
	$visible = [System.Windows.Visibility]::Visible

	if ($Enable)
	{
		if (Get-Command -Name 'Stop-GuiTabContentBackgroundBuilds' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Stop-GuiTabContentBackgroundBuilds
		}
		$selectedPrimaryTab = if ($Script:PrimaryTabs -and $Script:PrimaryTabs.SelectedItem -and $Script:PrimaryTabs.SelectedItem.Tag) { [string]$Script:PrimaryTabs.SelectedItem.Tag } else { $null }
		$Script:UpdatesReturnPrimaryTab = if (-not [string]::IsNullOrWhiteSpace($selectedPrimaryTab) -and $selectedPrimaryTab -ne $Script:SearchResultsTabTag) { $selectedPrimaryTab } elseif (-not [string]::IsNullOrWhiteSpace([string]$Script:LastStandardPrimaryTab)) { [string]$Script:LastStandardPrimaryTab } else { 'Initial Setup' }
		if ([bool]$Script:AppsModeActive)
		{
			Set-GuiAppsMode -Enable:$false
		}
		if ([bool]$Script:GamingModeActive -and (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-GuiGamingMode -Enable:$false -SkipContentRestore
		}
		if ([bool]$Script:DeploymentMediaModeActive -and (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-GuiDeploymentMediaMode -Enable:$false
		}
	}

	$Script:UpdatesModeActive = $Enable
	if ($Enable)
	{
		$Script:AppsModeActive = $false
		$Script:GamingModeActive = $false
		$Script:DeploymentMediaModeActive = $false
	}

	Set-GuiNavModeCheckedState

	if ($Script:ModeSubtitle)
	{
		$subtitleKey = if ($Enable) { 'Nav_WindowsUpdatesSubtitle' } else { 'Nav_OptimizeSubtitle' }
		$subtitleFallback = if ($Enable) { 'Manage Windows Update' } else { 'Configure system behavior' }
		$Script:ModeSubtitle.Text = (Get-UxLocalizedString -Key $subtitleKey -Fallback $subtitleFallback)
		$Script:ModeSubtitle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
	}

	if ($Script:TweaksView) { $Script:TweaksView.Visibility = $visible }
	if ($Script:AppsView) { $Script:AppsView.Visibility = $collapsed }
	if ($Script:DeploymentMediaView) { $Script:DeploymentMediaView.Visibility = $collapsed }
	if ($Script:PrimaryTabHost) { $Script:PrimaryTabHost.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:ExpertModeBanner)
	{
		$Script:ExpertModeBanner.Visibility = $collapsed
	}
	Set-GuiOptimizeFilterChromeVisible -Visible $true
	if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.Visibility = $visible }
	if ($Script:BtnDefaults) { $Script:BtnDefaults.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnRun) { $Script:BtnRun.Visibility = $visible }
	if ($Script:BtnApplyQueuedActions) { $Script:BtnApplyQueuedActions.Visibility = $collapsed }
	if ($Script:BtnDeploymentMediaPreviewPlan) { $Script:BtnDeploymentMediaPreviewPlan.Visibility = $collapsed }
	if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.Visibility = $collapsed }

	if ($Enable)
	{
		if (Get-Command -Name 'Build-TabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Build-TabContent -PrimaryTab 'Updates' -SkipIdlePrebuild
		}
	}
	elseif (-not [bool]$Script:DeploymentMediaModeActive -and -not [bool]$Script:GamingModeActive)
	{
		$restoreTab = if (-not [string]::IsNullOrWhiteSpace([string]$Script:UpdatesReturnPrimaryTab)) { [string]$Script:UpdatesReturnPrimaryTab } else { 'Initial Setup' }
		if ($Script:PrimaryTabs)
		{
			foreach ($tab in $Script:PrimaryTabs.Items)
			{
				if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -eq $restoreTab))
				{
					$Script:PrimaryTabs.SelectedItem = $tab
					break
				}
			}
		}
		if (Get-Command -Name 'Build-TabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Build-TabContent -PrimaryTab $restoreTab -SkipIdlePrebuild
		}
	}

	if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if ($Script:SyncUxActionButtonTextScript)
		{
			& $Script:SyncUxActionButtonTextScript
		}
		else
		{
			Sync-UxActionButtonText
		}
	}
	if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-GuiScopedRunActionAvailability
	}
	if ($Script:UpdateGuiBackToTopButtonScript)
	{
		try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-GuiUpdatesMode.UpdateBackToTopButton' }
	}
}

<#
    .SYNOPSIS
#>

function Set-GuiDeploymentMediaMode
{
	[CmdletBinding()]
	param (
		[bool]$Enable = $false
	)

	if ($Script:DeploymentMediaModeActive -eq $Enable)
	{
		return
	}

	$collapsed = [System.Windows.Visibility]::Collapsed
	$visible = [System.Windows.Visibility]::Visible

	if ($Enable)
	{
		if (Get-Command -Name 'Stop-GuiTabContentBackgroundBuilds' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Stop-GuiTabContentBackgroundBuilds
		}
		$selectedPrimaryTab = if ($Script:PrimaryTabs -and $Script:PrimaryTabs.SelectedItem -and $Script:PrimaryTabs.SelectedItem.Tag) { [string]$Script:PrimaryTabs.SelectedItem.Tag } else { $null }
		$Script:DeploymentMediaReturnPrimaryTab = if (-not [string]::IsNullOrWhiteSpace($selectedPrimaryTab) -and $selectedPrimaryTab -ne $Script:SearchResultsTabTag) { $selectedPrimaryTab } elseif (-not [string]::IsNullOrWhiteSpace([string]$Script:LastStandardPrimaryTab)) { [string]$Script:LastStandardPrimaryTab } else { 'Initial Setup' }
		$Script:DeploymentMediaModeActive = $true
		if ([bool]$Script:AppsModeActive)
		{
			Set-GuiAppsMode -Enable:$false
		}
		if ([bool]$Script:GamingModeActive -and (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Set-GuiGamingMode -Enable:$false -SkipContentRestore
		}
		if ([bool]$Script:UpdatesModeActive)
		{
			Set-GuiUpdatesMode -Enable:$false
		}
	}

	$Script:DeploymentMediaModeActive = $Enable
	if ($Enable)
	{
		$Script:AppsModeActive = $false
		$Script:GamingModeActive = $false
		$Script:UpdatesModeActive = $false
	}

	Set-GuiNavModeCheckedState

	if ($Script:ModeSubtitle)
	{
		$subtitleKey = if ($Enable) { 'Nav_DeploymentMediaSubtitle' } else { 'Nav_OptimizeSubtitle' }
		$subtitleFallback = if ($Enable) { 'Build Windows setup media' } else { 'Configure system behavior' }
		$Script:ModeSubtitle.Text = (Get-UxLocalizedString -Key $subtitleKey -Fallback $subtitleFallback)
		$Script:ModeSubtitle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
	}

	if ($Script:TweaksView) { $Script:TweaksView.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:AppsView) { $Script:AppsView.Visibility = $collapsed }
	if ($Script:DeploymentMediaView) { $Script:DeploymentMediaView.Visibility = if ($Enable) { $visible } else { $collapsed } }
	if ($Script:PrimaryTabHost) { $Script:PrimaryTabHost.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:ExpertModeBanner)
	{
		$Script:ExpertModeBanner.Visibility = if ($Enable)
		{
			$collapsed
		}
		elseif ((Get-Command -Name 'Test-IsExpertModeUX' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-IsExpertModeUX))
		{
			$visible
		}
		else
		{
			$collapsed
		}
	}

	if ($Script:ThemeToggleGroup) { $Script:ThemeToggleGroup.Visibility = $collapsed }

	Set-GuiOptimizeFilterChromeVisible -Visible:(-not $Enable)

	foreach ($control in @($Script:TxtSearch, $Script:TxtSearchPlaceholder, $Script:BtnClearSearch))
	{
		if ($control) { $control.Visibility = if ($Enable) { $collapsed } else { $visible } }
	}
	if (-not $Enable -and (Get-Command -Name 'Sync-GuiSearchInputChrome' -CommandType Function -ErrorAction SilentlyContinue))
	{
		Sync-GuiSearchInputChrome
	}

	if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnDefaults) { $Script:BtnDefaults.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnRun) { $Script:BtnRun.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnApplyQueuedActions) { $Script:BtnApplyQueuedActions.Visibility = $collapsed }
	if ($Script:BtnDeploymentMediaPreviewPlan) { $Script:BtnDeploymentMediaPreviewPlan.Visibility = if ($Enable) { $visible } else { $collapsed } }
	if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.Visibility = if ($Enable) { $visible } else { $collapsed } }

	if ($Enable)
	{
		if (Get-Command -Name 'Initialize-GuiDeploymentMediaBuilderView' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Initialize-GuiDeploymentMediaBuilderView
		}
		if (Get-Command -Name 'Sync-GuiDeploymentMediaBuilderViewText' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-GuiDeploymentMediaBuilderViewText
		}
	}
	elseif (-not [bool]$Script:GamingModeActive)
	{
		$restoreTab = if (-not [string]::IsNullOrWhiteSpace([string]$Script:DeploymentMediaReturnPrimaryTab)) { [string]$Script:DeploymentMediaReturnPrimaryTab } else { 'Initial Setup' }
		if ($Script:PrimaryTabs)
		{
			foreach ($tab in $Script:PrimaryTabs.Items)
			{
				if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -eq $restoreTab))
				{
					$Script:PrimaryTabs.SelectedItem = $tab
					break
				}
			}
		}
		if (Get-Command -Name 'Build-TabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Build-TabContent -PrimaryTab $restoreTab -SkipIdlePrebuild
		}
	}

	if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if ($Script:SyncUxActionButtonTextScript)
		{
			& $Script:SyncUxActionButtonTextScript
		}
		else
		{
			Sync-UxActionButtonText
		}
	}
	if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-GuiScopedRunActionAvailability
	}
	if ($Script:UpdateGuiBackToTopButtonScript)
	{
		try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-GuiDeploymentMediaMode.UpdateBackToTopButton' }
	}
}

<#
    .SYNOPSIS
#>

function Set-GuiAppsMode
{
	[CmdletBinding()]
	param (
		[bool]$Enable = $false
	)

	if ($Script:AppsModeActive -eq $Enable)
	{
		return
	}

	if ($Enable -and (Get-Command -Name 'Stop-GuiTabContentBackgroundBuilds' -CommandType Function -ErrorAction SilentlyContinue))
	{
		Stop-GuiTabContentBackgroundBuilds
	}

	if ($Enable -and [bool]$Script:DeploymentMediaModeActive -and (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue))
	{
		Set-GuiDeploymentMediaMode -Enable:$false
	}
	if ($Enable -and [bool]$Script:GamingModeActive -and (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue))
	{
		Set-GuiGamingMode -Enable:$false -SkipContentRestore
	}

	$Script:AppsModeActive = $Enable
	if ($Enable)
	{
		$Script:UpdatesModeActive = $false
		$Script:GamingModeActive = $false
		$Script:DeploymentMediaModeActive = $false
	}
	Set-GuiNavModeCheckedState
	if ($Script:ModeSubtitle)
	{
		$subtitleKey = if ($Enable) { 'Nav_SoftwareAndAppsSubtitle' } else { 'Nav_OptimizeSubtitle' }
		$subtitleFallback = if ($Enable) { 'Manage installed applications' } else { 'Configure system behavior' }
		$Script:ModeSubtitle.Text = (Get-UxLocalizedString -Key $subtitleKey -Fallback $subtitleFallback)
		$Script:ModeSubtitle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
	}
	if ($Enable -and -not $Script:AppsOperationInProgress -and -not $Script:AppsCacheRefreshInProgress)
	{
		$appsViewAlreadyRendered = [bool]($Script:AppsWrapPanel -and $Script:AppsWrapPanel.Children -and $Script:AppsWrapPanel.Children.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Script:AppsViewBuildSignature))
		if (-not $appsViewAlreadyRendered)
		{
			if (Get-Command -Name 'Update-AppsPackageManagerBanner' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try { Update-AppsPackageManagerBanner } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-GuiAppsMode.UpdateAppsPackageManagerBanner' }
			}
		}
	}

	$collapsed = [System.Windows.Visibility]::Collapsed
	$visible = [System.Windows.Visibility]::Visible

	if ($Script:TweaksView) { $Script:TweaksView.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:AppsView) { $Script:AppsView.Visibility = if ($Enable) { $visible } else { $collapsed } }
	if ($Script:DeploymentMediaView) { $Script:DeploymentMediaView.Visibility = $collapsed }
	if ($Script:PrimaryTabHost) { $Script:PrimaryTabHost.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:ExpertModeBanner)
	{
		$Script:ExpertModeBanner.Visibility = if ($Enable)
		{
			$collapsed
		}
		elseif ((Get-Command -Name 'Test-IsExpertModeUX' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-IsExpertModeUX))
		{
			$visible
		}
		else
		{
			$collapsed
		}
	}

	if ($Script:ThemeToggleGroup)
	{
		$Script:ThemeToggleGroup.Visibility = $collapsed
	}

	if ($Script:TxtSearch)
	{
		$desiredSearchText = if ($Enable) { [string]$Script:AppsSearchText } else { [string]$Script:SearchText }
		if ($Script:TxtSearch.Text -ne $desiredSearchText)
		{
			$Script:SearchUiUpdating = $true
			try
			{
				$Script:TxtSearch.Text = $desiredSearchText
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

	if ($Enable)
	{
		if (Get-Command -Name 'Resolve-AppsCatalogCategory' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$Script:AppsCategoryFilter = Resolve-AppsCatalogCategory -Category $Script:AppsCategoryFilter
		}
		elseif ([string]::IsNullOrWhiteSpace([string]$Script:AppsCategoryFilter) -or [string]$Script:AppsCategoryFilter -eq 'All')
		{
			$Script:AppsCategoryFilter = 'Browsers'
		}
		Initialize-AppPackageSourcePreferenceState
		Update-AppPackageSourcePreferenceControls
		if (Get-Command -Name 'Update-AppSourceFilterControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppSourceFilterControls
		}
	}

	Set-GuiOptimizeFilterChromeVisible -Visible:(-not $Enable)

	if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnDefaults) { $Script:BtnDefaults.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnRun) { $Script:BtnRun.Visibility = if ($Enable) { $collapsed } else { $visible } }
	if ($Script:BtnApplyQueuedActions) { $Script:BtnApplyQueuedActions.Visibility = if ($Enable) { $visible } else { $collapsed } }
	if ($Script:BtnDeploymentMediaPreviewPlan) { $Script:BtnDeploymentMediaPreviewPlan.Visibility = $collapsed }
	if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.Visibility = $collapsed }

	if ($Enable)
	{
		Build-AppsViewCards
	}
	elseif (-not [bool]$Script:GamingModeActive -and -not [bool]$Script:UpdatesModeActive -and -not [bool]$Script:DeploymentMediaModeActive)
	{
		if (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-CurrentTabContent -SkipIdlePrebuild
		}
	}

	if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if ($Script:SyncUxActionButtonTextScript)
		{
			& $Script:SyncUxActionButtonTextScript
		}
		else
		{
			Sync-UxActionButtonText
		}
	}
	if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-GuiScopedRunActionAvailability
	}
	if ($Script:UpdateGuiBackToTopButtonScript)
	{
		try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-GuiAppsMode.UpdateBackToTopButton' }
	}
}
