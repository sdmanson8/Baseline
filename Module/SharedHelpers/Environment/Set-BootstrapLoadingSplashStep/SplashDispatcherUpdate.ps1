if ($Splash -is [hashtable])
{
	if ($Splash.ContainsKey('Window'))            { $window         = $Splash['Window'] }
	if ($Splash.ContainsKey('Dispatcher'))        { $dispatcher     = $Splash['Dispatcher'] }
	if ($Splash.ContainsKey('StepGlyphs'))        { $stepGlyphs     = $Splash['StepGlyphs'] }
	if ($Splash.ContainsKey('StepIdleDots'))      { $stepIdleDots   = $Splash['StepIdleDots'] }
	if ($Splash.ContainsKey('StepPulseDots'))     { $stepPulseDots  = $Splash['StepPulseDots'] }
	if ($Splash.ContainsKey('StepChecks'))        { $stepChecks     = $Splash['StepChecks'] }
	if ($Splash.ContainsKey('StepLabels'))        { $stepLabels     = $Splash['StepLabels'] }
	if ($Splash.ContainsKey('StepStates'))        { $stepStates     = $Splash['StepStates'] }
	if ($Splash.ContainsKey('StatusText'))        { $statusControl  = $Splash['StatusText'] }
	if ($Splash.ContainsKey('SubActionPanel'))    { $subActionPanel = $Splash['SubActionPanel'] }
	if ($Splash.ContainsKey('ProgressBar'))       { $progressBar    = $Splash['ProgressBar'] }
	if ($Splash.ContainsKey('SplashTheme'))       { $theme          = $Splash['SplashTheme'] }
	if ($Splash.ContainsKey('StepOrder') -and $Splash['StepOrder']) { $stepOrder = @($Splash['StepOrder']) }
}

if (-not $window -or -not $dispatcher -or $dispatcher.HasShutdownStarted -or -not $stepGlyphs -or -not $stepLabels -or -not $stepStates)
{
	$__baselineExtractedPartReturnValue = $false
	$__baselineExtractedPartHasReturnValue = $true
	$__baselineExtractedPartDidReturn = $true
}
else
{
	try
	{
		$dispatcherUpdateAction = {
			try
			{
				$writeStepException = {
					param(
						[object]$ErrorRecord,
						[string]$Source
					)
					try
					{
						$writer = Get-Command -Name 'Write-EnvironmentSwallowedException' -CommandType Function -ErrorAction SilentlyContinue
						if ($writer)
						{
							& $writer -ErrorRecord $ErrorRecord -Source $Source
						}
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:44' -Severity Debug }
					 $null = $_ }
				}
				$setProgressBarValue = {
					param(
						[object]$ProgressBarControl,
						[double]$Value
					)

					if (-not $ProgressBarControl) { return }

					$setCurrentValueMethod = $null
					try { $setCurrentValueMethod = $ProgressBarControl.PSObject.Methods['SetCurrentValue'] } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:55' -Severity Debug }
					 $setCurrentValueMethod = $null }
					if ($setCurrentValueMethod)
					{
						try
						{
							$ProgressBarControl.SetCurrentValue([System.Windows.Controls.ProgressBar]::ValueProperty, $Value)
							return
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:63' -Severity Debug }
						 & $writeStepException $_ 'Environment.Splash.ProgressBar.SetCurrentValue' }
					}

					$ProgressBarControl.Value = $Value
				}
				$getProgressBarWidth = {
					param(
						[object]$ProgressBarControl
					)

					$width = 0.0
					try
					{
						$width = [double]$ProgressBarControl.ActualWidth
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:78' -Severity Debug }

						$width = 0.0
					}

					if ([double]::IsNaN($width) -or $width -le 0)
					{
						try
						{
							$width = [double]$ProgressBarControl.Width
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:89' -Severity Debug }

							$width = 0.0
						}
					}

					if ([double]::IsNaN($width) -or $width -le 0)
					{
						$width = 330.0
					}

					return $width
				}
				$splashState = $Splash
				$mutedBrush   = $null
				$subBrush     = $null
				$primaryBrush = $null
				$accentBrush  = $null
				if ($theme)
				{
					$getThemeColor = {
						param([string]$Name)
						if ($theme -is [System.Collections.IDictionary] -and $theme.Contains($Name)) { return [string]$theme[$Name] }
						$psProperties = if ($theme -and $theme.PSObject) { $theme.PSObject.Properties } else { $null }
						$matchedProperties = if ($psProperties) { @($psProperties.Match($Name)) } else { @() }
						$property = if ($matchedProperties.Count -gt 0) { $matchedProperties[0] } else { $null }
						if ($property) { return [string]$property.Value }
						return $null
					}.GetNewClosure()
					$mutedColor = & $getThemeColor 'Muted'
					$subColor = & $getThemeColor 'Sub'
					$primaryColor = & $getThemeColor 'Primary'
					$accentColor = & $getThemeColor 'Accent'
					try { if (-not [string]::IsNullOrWhiteSpace($mutedColor))   { $mutedBrush   = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($mutedColor)) } } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:122' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.BrushConvert.Muted' }
					try { if (-not [string]::IsNullOrWhiteSpace($subColor))     { $subBrush     = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($subColor)) } } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:123' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.BrushConvert.Sub' }
					try { if (-not [string]::IsNullOrWhiteSpace($primaryColor)) { $primaryBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($primaryColor)) } } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:124' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.BrushConvert.Primary' }
					try { if (-not [string]::IsNullOrWhiteSpace($accentColor))  { $accentBrush  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($accentColor)) } } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:125' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.BrushConvert.Accent' }
				}

				$opacityProp   = [System.Windows.UIElement]::OpacityProperty
				$snapAndKeep   = [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace
				$holdEnd       = [System.Windows.Media.Animation.FillBehavior]::HoldEnd

				$animateOpacity = {
					param($element, $to, $durationMs)
					if (-not $element) { return }
					try
					{
						$a = New-Object System.Windows.Media.Animation.DoubleAnimation
						$a.To       = [double]$to
						$a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds([int]$durationMs))
						$e          = New-Object System.Windows.Media.Animation.QuadraticEase
						$e.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
						$a.EasingFunction = $e
						$a.FillBehavior   = $holdEnd
						$element.BeginAnimation($opacityProp, $a, $snapAndKeep)
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:146' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.OpacityAnimation.Begin' }
				}.GetNewClosure()

				$scaleXProp = [System.Windows.Media.ScaleTransform]::ScaleXProperty
				$scaleYProp = [System.Windows.Media.ScaleTransform]::ScaleYProperty
				$visVisible = [System.Windows.Visibility]::Visible
				$visCollapsed = [System.Windows.Visibility]::Collapsed
				$glyphsByStep = $stepGlyphs
				$idleDotsByStep = $stepIdleDots
				$pulseDotsByStep = $stepPulseDots
				$checksByStep = $stepChecks
				$labelsByStep = $stepLabels

				$startPulseDot = {
					param($pulseEllipse)
					if (-not $pulseEllipse) { return }
					try
					{
						& $stopPulseDot $pulseEllipse
						$rt = $pulseEllipse.RenderTransform
						if ($rt -is [System.Windows.Media.ScaleTransform])
						{
							$sxa = New-Object System.Windows.Media.Animation.DoubleAnimation
							$sxa.From = 1.0; $sxa.To = 1.4
							$sxa.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(360))
							$sxa.AutoReverse = $true
							$sxa.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
							$rt.BeginAnimation($scaleXProp, $sxa, $snapAndKeep)

							$sya = New-Object System.Windows.Media.Animation.DoubleAnimation
							$sya.From = 1.0; $sya.To = 1.4
							$sya.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(360))
							$sya.AutoReverse = $true
							$sya.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
							$rt.BeginAnimation($scaleYProp, $sya, $snapAndKeep)
						}
						$oa = New-Object System.Windows.Media.Animation.DoubleAnimation
						$oa.From = 0.6; $oa.To = 1.0
						$oa.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(360))
						$oa.AutoReverse = $true
						$oa.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
						$pulseEllipse.BeginAnimation($opacityProp, $oa, $snapAndKeep)
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:189' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.PulseDot.Start' }
				}

				$stopPulseDot = {
					param($pulseEllipse)
					if (-not $pulseEllipse) { return }
					try
					{
						$rt = $pulseEllipse.RenderTransform
						if ($rt -is [System.Windows.Media.ScaleTransform])
						{
							$rt.BeginAnimation($scaleXProp, $null)
							$rt.BeginAnimation($scaleYProp, $null)
							$rt.ScaleX = 1.0
							$rt.ScaleY = 1.0
						}
						$pulseEllipse.BeginAnimation($opacityProp, $null)
						$pulseEllipse.Opacity = 0.6
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:208' -Severity Debug }
					 & $writeStepException $_ 'Environment.Splash.PulseDot.Stop' }
				}.GetNewClosure()
				$startPulseDot = $startPulseDot.GetNewClosure()

				$stopInactivePulseDots = {
					param($activeStepId)
					if (-not $pulseDotsByStep) { return }
					foreach ($pulseId in @($pulseDotsByStep.Keys))
					{
						if ($pulseId -eq $activeStepId) { continue }
						$pulseDot = $pulseDotsByStep[$pulseId]
						if (-not $pulseDot) { continue }
						& $stopPulseDot $pulseDot
						$pulseDot.Visibility = $visCollapsed
					}
				}.GetNewClosure()

				$applyRowState = {
					param($id, $state)
					$g     = if ($glyphsByStep) { $glyphsByStep[$id] } else { $null }
					$idle  = if ($idleDotsByStep)  { $idleDotsByStep[$id] }  else { $null }
					$pulse = if ($pulseDotsByStep) { $pulseDotsByStep[$id] } else { $null }
					$check = if ($checksByStep)    { $checksByStep[$id] }    else { $null }
					$l     = if ($labelsByStep) { $labelsByStep[$id] } else { $null }

					switch ($state)
					{
						'pending'
						{
							if ($pulse)
							{
								& $stopPulseDot $pulse
								$pulse.Visibility = $visCollapsed
							}
							if ($check) { $check.Visibility = $visCollapsed }
							if ($idle)
							{
								if ($mutedBrush) { $idle.Stroke = $mutedBrush }
								$idle.Visibility = $visVisible
							}
							if ($g) { & $animateOpacity $g 1.0 220 }
						}
						'in_progress'
						{
							if ($idle)  { $idle.Visibility  = $visCollapsed }
							if ($check) { $check.Visibility = $visCollapsed }
							if ($pulse)
							{
								if ($accentBrush) { $pulse.Fill = $accentBrush }
								$pulse.Visibility = $visVisible
								& $startPulseDot $pulse
							}
							if ($g) { & $animateOpacity $g 1.0 220 }
						}
						'completed'
						{
							if ($pulse)
							{
								& $stopPulseDot $pulse
								$pulse.Visibility = $visCollapsed
							}
							if ($idle) { $idle.Visibility = $visCollapsed }
							if ($check)
							{
								if ($accentBrush) { $check.Foreground = $accentBrush }
								$check.Visibility = $visVisible
							}
							if ($g) { & $animateOpacity $g 0.85 280 }
						}
					}

					if ($l)
					{
						switch ($state)
						{
							'pending'
							{
								if ($mutedBrush) { $l.Foreground = $mutedBrush }
								& $animateOpacity $l 1.0 200
							}
							'in_progress'
							{
								if ($primaryBrush) { $l.Foreground = $primaryBrush }
								& $animateOpacity $l 1.0 200
							}
							'completed'
							{
								if ($subBrush) { $l.Foreground = $subBrush }
								& $animateOpacity $l 0.85 280
							}
						}
					}
				}.GetNewClosure()

				# Cascade earlier steps to completed when a later step starts. This
				# keeps the checklist coherent even if a caller skips a transition.
				if ($Status -in @('in_progress','completed'))
				{
					$foundIdx = [Array]::IndexOf($stepOrder, $StepId)
					if ($foundIdx -gt 0)
					{
						for ($i = 0; $i -lt $foundIdx; $i++)
						{
							$earlierId = $stepOrder[$i]
							if ($stepStates[$earlierId] -ne 'completed')
							{
								$stepStates[$earlierId] = 'completed'
								& $applyRowState $earlierId 'completed'
							}
						}
					}
				}

				$activePulseStepId = if ($Status -eq 'in_progress') { $StepId } else { $null }
				& $stopInactivePulseDots $activePulseStepId

				$stepStates[$StepId] = $Status
				& $applyRowState $StepId $Status

				$completedCount = 0
				foreach ($id in $stepOrder)
				{
					if ($stepStates[$id] -eq 'completed') { $completedCount++ }
				}

				# Snap on step completion; while the final handoff is active, keep
				# the bar moving slowly toward a reserved near-complete ceiling
				# until the foreground GUI tab signals readiness.
				if ($progressBar)
				{
					try
					{
						$progressBar.IsIndeterminate = $false
						$barWidth = & $getProgressBarWidth $progressBar
						$stepCount = [Math]::Max(1, [double]$stepOrder.Count)
						$current = [double]$progressBar.Value
						$progressBar.Maximum = $barWidth
						if ($Status -eq 'in_progress')
						{
							$activeIdx = [Array]::IndexOf($stepOrder, $StepId)
							if ($activeIdx -lt 0) { $activeIdx = $completedCount }
							$lastStepIndex = [Math]::Max(0, ([int]$stepOrder.Count) - 1)
							$isFinalHandoffStep = ([string]$StepId -eq [string]$stepOrder[$lastStepIndex])
							$snapTo = ([double]$activeIdx / $stepCount) * $barWidth
							$fillFrom = $snapTo
							$fillTo = (([double]$activeIdx + 0.35) / $stepCount) * $barWidth
							$fillDurationMs = 2200
							$fillEase = New-Object System.Windows.Media.Animation.CubicEase
							$fillEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
							if ($isFinalHandoffStep)
							{
								$handoffCeiling = $barWidth * 0.97
								if ($current -gt $snapTo -and $current -lt $handoffCeiling)
								{
									$fillFrom = $current
								}
								$fillTo = $handoffCeiling
								$fillDurationMs = 24000
								$fillEase = $null
							}

							$fill = New-Object System.Windows.Media.Animation.DoubleAnimation
							$fill.From = $fillFrom
							$fill.To   = $fillTo
							$fill.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($fillDurationMs))
							if ($fillEase) { $fill.EasingFunction = $fillEase }
							$fill.FillBehavior = $holdEnd
							# Clear any prior animation on Value before starting the step-owned fill.
							$progressBar.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $null)
							$progressBar.Value = $fillFrom
							$progressBar.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $fill, $snapAndKeep)
							& $setProgressBarValue $progressBar $fillTo
						}
						else
						{
							$anim = New-Object System.Windows.Media.Animation.DoubleAnimation
							$anim.From = $current
							$anim.To   = ([double]$completedCount / $stepCount) * $barWidth
							$anim.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(320))
							$ease = New-Object System.Windows.Media.Animation.QuadraticEase
							$ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
							$anim.EasingFunction = $ease
							$anim.FillBehavior = $holdEnd
							$progressBar.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $anim, $snapAndKeep)
							& $setProgressBarValue $progressBar (([double]$completedCount / $stepCount) * $barWidth)
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:395' -Severity Debug }

						try
						{
							$barWidth = & $getProgressBarWidth $progressBar
							$stepCount = [Math]::Max(1, [double]$stepOrder.Count)
							if ($Status -eq 'in_progress')
							{
								$activeIdx = [Array]::IndexOf($stepOrder, $StepId)
								if ($activeIdx -lt 0) { $activeIdx = $completedCount }
								$lastStepIndex = [Math]::Max(0, ([int]$stepOrder.Count) - 1)
								if ([string]$StepId -eq [string]$stepOrder[$lastStepIndex])
								{
									& $setProgressBarValue $progressBar ($barWidth * 0.97)
								}
								else
								{
									& $setProgressBarValue $progressBar ((([double]$activeIdx + 0.35) / $stepCount) * $barWidth)
								}
							}
							else
							{
								& $setProgressBarValue $progressBar (([double]$completedCount / $stepCount) * $barWidth)
							}
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:420' -Severity Debug }
						 & $writeStepException $_ 'Environment.Splash.ProgressBar.SetValueFallback' }
					}
				}

				# Sub-action visibility: panel toggles, not just the inner StatusText.
				if ($hasSubActionArg)
				{
					if ([string]::IsNullOrWhiteSpace([string]$SubAction))
					{
						if ($statusControl) { $statusControl.Text = '' }
						if ($subActionPanel)
						{
							$subActionPanel.Visibility = [System.Windows.Visibility]::Collapsed
						}
						elseif ($statusControl)
						{
							$statusControl.Visibility = [System.Windows.Visibility]::Collapsed
						}
					}
					else
					{
						if ($statusControl) { $statusControl.Text = [string]$SubAction }
						if ($subActionPanel)
						{
							$subActionPanel.Visibility = [System.Windows.Visibility]::Visible
						}
						elseif ($statusControl)
						{
							$statusControl.Visibility = [System.Windows.Visibility]::Visible
						}
					}
				}
				elseif ($Status -eq 'completed')
				{
					if ($statusControl) { $statusControl.Text = '' }
					if ($subActionPanel)
					{
						$subActionPanel.Visibility = [System.Windows.Visibility]::Collapsed
					}
					elseif ($statusControl)
					{
						$statusControl.Visibility = [System.Windows.Visibility]::Collapsed
					}
				}

				# Finish moment: when the last step lands as completed, brighten the
				# whole list back to full opacity for a beat of visual closure before
				# the splash window is dismissed.
				if ($StepId -eq 'finalize' -and $Status -eq 'completed')
				{
					foreach ($id in $stepOrder)
					{
						$gFin = $stepGlyphs[$id]
						$lFin = $stepLabels[$id]
						if ($gFin) { & $animateOpacity $gFin 1.0 350 }
						if ($lFin) { & $animateOpacity $lFin 1.0 350 }
					}
				}
			}
			catch
			{
				if ($splashState -is [hashtable])
				{
					$splashState['ErrorType'] = $_.Exception.GetType().FullName
					$splashState['ErrorMessage'] = $_.Exception.Message
				}
				& $writeStepException $_ 'Environment.SetBootstrapLoadingSplashStep.DispatcherUpdate'
				throw
			}
		}.GetNewClosure()

		$dispatcherHasCheckAccess = $false
		try { $dispatcherHasCheckAccess = ($null -ne $dispatcher.PSObject.Methods['CheckAccess']) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:492' -Severity Debug }
		 $dispatcherHasCheckAccess = $false }
		if ($dispatcherHasCheckAccess -and $dispatcher.CheckAccess())
		{
			& $dispatcherUpdateAction
		}
		else
		{
			[void]$dispatcher.Invoke([System.Action]$dispatcherUpdateAction)
		}

		$__baselineExtractedPartReturnValue = $true
		$__baselineExtractedPartHasReturnValue = $true
		$__baselineExtractedPartDidReturn = $true
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:506' -Severity Debug }

		$__baselineExtractedPartReturnValue = $false
		$__baselineExtractedPartHasReturnValue = $true
		$__baselineExtractedPartDidReturn = $true
	}
}
