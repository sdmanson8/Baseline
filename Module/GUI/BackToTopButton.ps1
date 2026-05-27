# Floating Back to Top control for long tweak tab scroll surfaces.

$Script:BackToTopScrollThreshold = 500.0
$Script:BackToTopVisible = $false
$Script:BackToTopFadeGeneration = 0
$Script:BackToTopScrollAnimationState = $null

function Stop-GuiBackToTopScrollAnimation
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$state = $Script:BackToTopScrollAnimationState
	$Script:BackToTopScrollAnimationState = $null
	if (-not $state) { return }

	try
	{
		if ($state.Proxy)
		{
			$state.Proxy.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null)
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'BackToTop.StopScrollAnimation.BeginAnimation'
	}

	try
	{
		if ($state.Descriptor -and $state.Proxy -and $state.ValueChangedHandler)
		{
			$state.Descriptor.RemoveValueChanged($state.Proxy, $state.ValueChangedHandler)
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'BackToTop.StopScrollAnimation.RemoveValueChanged'
	}
}

function Start-GuiBackToTopOpacityAnimation
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.Button]$Button,

		[Parameter(Mandatory = $true)]
		[double]$To,

		[switch]$CollapseWhenComplete
	)

	$Script:BackToTopFadeGeneration++
	$currentGeneration = [int]$Script:BackToTopFadeGeneration

	$animation = [System.Windows.Media.Animation.DoubleAnimation]::new()
	$animation.From = [double]$Button.Opacity
	$animation.To = $To
	$animation.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(160))
	$easing = [System.Windows.Media.Animation.CubicEase]::new()
	$easing.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
	$animation.EasingFunction = $easing

	if ($CollapseWhenComplete)
	{
		$completedHandler = [EventHandler]{
			if ($currentGeneration -ne [int]$Script:BackToTopFadeGeneration) { return }
			$Button.Visibility = [System.Windows.Visibility]::Collapsed
			$Button.Opacity = 0
		}.GetNewClosure()
		$animation.add_Completed($completedHandler)
	}

	$Button.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
}

function Set-GuiBackToTopButtonVisible
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[bool]$Visible
	)

	$button = $Script:BtnBackToTop
	if (-not $button) { return }
	if ([bool]$Script:BackToTopVisible -eq $Visible) { return }

	$Script:BackToTopVisible = $Visible
	if ($Visible)
	{
		$button.Visibility = [System.Windows.Visibility]::Visible
		$button.IsHitTestVisible = $true
		Start-GuiBackToTopOpacityAnimation -Button $button -To 1.0
		return
	}

	$button.IsHitTestVisible = $false
	Start-GuiBackToTopOpacityAnimation -Button $button -To 0.0 -CollapseWhenComplete
}

function Test-GuiBackToTopButtonShouldShow
{
	param ()

	$scrollViewer = Get-GuiBackToTopActiveScrollViewer
	if (-not $scrollViewer) { return $false }
	if ($Script:RunInProgress) { return $false }
	if ($Script:UpdateDialogOverlay -and $Script:UpdateDialogOverlay.Visibility -eq [System.Windows.Visibility]::Visible) { return $false }

	$scrollableHeight = [double]$scrollViewer.ScrollableHeight
	if ($scrollableHeight -le 0.5) { return $false }

	return ([double]$scrollViewer.VerticalOffset -gt [double]$Script:BackToTopScrollThreshold)
}

function Update-GuiBackToTopButton
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	if (-not $Script:BtnBackToTop) { return }
	Set-GuiBackToTopButtonVisible -Visible (Test-GuiBackToTopButtonShouldShow)
}

function Get-GuiBackToTopActiveScrollViewer
{
	param ()

	if ([bool]$Script:AppsModeActive -and $Script:AppsScroll -and $Script:AppsView -and $Script:AppsView.Visibility -eq [System.Windows.Visibility]::Visible)
	{
		return $Script:AppsScroll
	}

	if ([bool]$Script:DeploymentMediaModeActive -and $Script:DeploymentMediaScroll -and $Script:DeploymentMediaView -and $Script:DeploymentMediaView.Visibility -eq [System.Windows.Visibility]::Visible)
	{
		return $Script:DeploymentMediaScroll
	}

	if ($Script:BackToTopScrollViewer -and $Script:TweaksView -and $Script:TweaksView.Visibility -eq [System.Windows.Visibility]::Visible)
	{
		return $Script:BackToTopScrollViewer
	}

	return $null
}

function Invoke-GuiBackToTopScroll
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$scrollViewer = Get-GuiBackToTopActiveScrollViewer
	if (-not $scrollViewer) { return }
	$updateScript = $Script:UpdateGuiBackToTopButtonScript

	Stop-GuiBackToTopScrollAnimation

	$startOffset = [double]$scrollViewer.VerticalOffset
	if ($startOffset -le 0.5)
	{
		$scrollViewer.ScrollToVerticalOffset(0)
		if ($updateScript) { & $updateScript }
		return
	}

	$proxy = [System.Windows.Controls.Border]::new()
	$proxy.Width = $startOffset
	$descriptor = [System.ComponentModel.DependencyPropertyDescriptor]::FromProperty(
		[System.Windows.FrameworkElement]::WidthProperty,
		[System.Windows.FrameworkElement]
	)
	if (-not $descriptor) { throw 'Could not resolve Width dependency property descriptor for Back to Top animation.' }

	$valueChangedHandler = [EventHandler]{
		$currentOffset = [double]$proxy.Width
		if ([double]::IsNaN($currentOffset)) { return }
		$scrollViewer.ScrollToVerticalOffset([Math]::Max(0.0, $currentOffset))
	}.GetNewClosure()
	$descriptor.AddValueChanged($proxy, $valueChangedHandler)

	$animation = [System.Windows.Media.Animation.DoubleAnimation]::new()
	$animation.From = $startOffset
	$animation.To = 0.0
	$animation.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(280))
	$easing = [System.Windows.Media.Animation.CubicEase]::new()
	$easing.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
	$animation.EasingFunction = $easing

	$completedHandler = [EventHandler]{
		try
		{
			$scrollViewer.ScrollToVerticalOffset(0)
			if ($descriptor -and $proxy -and $valueChangedHandler)
			{
				$descriptor.RemoveValueChanged($proxy, $valueChangedHandler)
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'BackToTop.ScrollAnimation.Completed'
		}
		finally
		{
			if ($Script:BackToTopScrollAnimationState -and $Script:BackToTopScrollAnimationState.Proxy -eq $proxy)
			{
				$Script:BackToTopScrollAnimationState = $null
			}
			if ($updateScript) { & $updateScript }
		}
	}.GetNewClosure()
	$animation.add_Completed($completedHandler)

	$Script:BackToTopScrollAnimationState = [pscustomobject]@{
		Proxy = $proxy
		Descriptor = $descriptor
		ValueChangedHandler = $valueChangedHandler
		CompletedHandler = $completedHandler
	}
	$proxy.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $animation, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
}

function Test-GuiBackToTopShortcutTarget
{
	param ()

	$focused = [System.Windows.Input.Keyboard]::FocusedElement
	if (-not $focused) { return $true }
	if ($focused -is [System.Windows.Controls.TextBox]) { return $false }
	if ($focused -is [System.Windows.Controls.PasswordBox]) { return $false }

	$current = $focused
	while ($current)
	{
		if ($current -is [System.Windows.Controls.ComboBox]) { return $false }
		try { $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current) }
		catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'BackToTopButton.Test-GuiBackToTopShortcutTarget:catch239' -Severity Debug }
		 $current = $null }
	}
	return $true
}

function Initialize-GuiBackToTopButton
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.ScrollViewer]$ScrollViewer,

		[System.Windows.Controls.ScrollViewer[]]$AdditionalScrollViewers = @(),

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.Button]$Button
	)

	$Script:BackToTopScrollViewer = $ScrollViewer
	$Script:BackToTopScrollViewers = [System.Collections.Generic.List[System.Windows.Controls.ScrollViewer]]::new()
	[void]$Script:BackToTopScrollViewers.Add($ScrollViewer)
	foreach ($candidate in $AdditionalScrollViewers)
	{
		if ($candidate -and -not $Script:BackToTopScrollViewers.Contains($candidate))
		{
			[void]$Script:BackToTopScrollViewers.Add($candidate)
		}
	}
	$Script:BtnBackToTop = $Button
	$Script:UpdateGuiBackToTopButtonScript = ${function:Update-GuiBackToTopButton}
	$Script:InvokeGuiBackToTopScrollScript = ${function:Invoke-GuiBackToTopScroll}
	$Script:TestGuiBackToTopShortcutTargetScript = ${function:Test-GuiBackToTopShortcutTarget}

	$Button.Visibility = [System.Windows.Visibility]::Collapsed
	$Button.Opacity = 0
	$Button.IsHitTestVisible = $false
	$Button.Focusable = $false
	$Button.IsTabStop = $false

	$updateScript = $Script:UpdateGuiBackToTopButtonScript
	$scrollScript = $Script:InvokeGuiBackToTopScrollScript
	$shortcutTargetScript = $Script:TestGuiBackToTopShortcutTargetScript

	$null = Register-GuiEventHandler -Source $Button -EventName 'Click' -Handler ({
		& $scrollScript
	}.GetNewClosure())

	foreach ($registeredScrollViewer in $Script:BackToTopScrollViewers)
	{
		$null = Register-GuiEventHandler -Source $registeredScrollViewer -EventName 'ScrollChanged' -Handler ({
			& $updateScript
		}.GetNewClosure())

		$null = Register-GuiEventHandler -Source $registeredScrollViewer -EventName 'SizeChanged' -Handler ({
			& $updateScript
		}.GetNewClosure())
	}

	$null = Register-GuiEventHandler -Source $Window -EventName 'KeyDown' -Handler ({
		param($sender, $eventArgs)
		if (-not $eventArgs) { return }
		if ($eventArgs.Key -ne [System.Windows.Input.Key]::Home) { return }
		if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne [System.Windows.Input.ModifierKeys]::Control) { return }
		if (-not (& $shortcutTargetScript)) { return }

		& $scrollScript
		$eventArgs.Handled = $true
	}.GetNewClosure())

	Update-GuiBackToTopButton
}
