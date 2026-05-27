Register-GuiEventHandler -Source $Form -EventName 'ContentRendered' -Handler ({
		if ($startupPresentationCompleted) { return }
		$startupPresentationCompleted = $true

		# Run initial adaptive tab layout check now that the window has its actual size
		if ($Script:AdaptiveTabLayoutScript) { & $Script:AdaptiveTabLayoutScript }

		# Schedule splash close via a dedicated background runspace.
		#
		# Why not a dispatcher: the GUI dispatcher is busy for ~50 s after
		# ContentRendered with deferred ApplicationIdle Build-TabContent work,
		# so anything queued at Background/ApplicationIdle on the GUI is
		# starved until that backlog drains.
		#
		# Why not Register-ObjectEvent: PowerShell event subscribers run on
		# the main runspace thread, which is blocked inside Form.ShowDialog()
		# until the user closes the GUI - the action never fires.
		#
		# A fresh runspace gives us a completely independent thread that can
		# poll the splash's GuiReady flag (flipped by Build-TabContent once the
		# foreground tab is interactive) and then close the splash via its OWN
		# dispatcher (separate STA, idle, uncontended). This keeps the splash
		# visible until the GUI is actually usable, while background work keeps
		# draining on the main dispatcher.
		try
		{
			$splashHandle = $Global:LoadingSplash
			if (& $testGuiStartupSplashLiveBlock -Splash $splashHandle)
			{
				if (-not $splashHandle.ContainsKey('GuiReady')) { $splashHandle['GuiReady'] = $false }
				$applyStartupSplashMainWindowStateAction = [System.Action[bool]]({
					param([bool]$WindowMaximized)

					if ($WindowMaximized)
					{
						Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true -PreserveRestoreBounds
					}
				}.GetNewClosure())
				$closeRunspace = [runspacefactory]::CreateRunspace()
				$closeRunspace.ApartmentState = 'MTA'
				$closeRunspace.Open()
				$closeRunspace.SessionStateProxy.SetVariable('splash', $splashHandle)
				$closeRunspace.SessionStateProxy.SetVariable('mainWindow', $Form)
				$closeRunspace.SessionStateProxy.SetVariable('applyStartupSplashMainWindowStateAction', $applyStartupSplashMainWindowStateAction)
				$closePs = [powershell]::Create()
				$closePs.Runspace = $closeRunspace
				[void]$closePs.AddScript({
					$traceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
					$tracePath = Join-Path $traceDirectory 'Baseline-launch-trace.txt'
					$trace = {
						param([string]$Message)
						try
						{
							if (-not [System.IO.Directory]::Exists($traceDirectory)) { [void][System.IO.Directory]::CreateDirectory($traceDirectory) }
							$line = ("{0:o} {1}`r`n" -f [DateTime]::UtcNow, $Message)
							$bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
							$stream = [System.IO.FileStream]::new($tracePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
							try { $stream.Write($bytes, 0, $bytes.Length) }
							finally { $stream.Dispose() }
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:61' -Severity Debug }
						 $null = $_ }
					}
					& $trace 'SplashClose runspace: started polling GuiReady'
					try
					{
					# Wait for the GUI-ready signal from Build-TabContent.
					# Cap at 180 s as a safety net so the splash is never
					# stuck if the signal is missed.
						$deadline = [datetime]::UtcNow.AddSeconds(180)
						while ($splash -is [hashtable] -and (-not ($splash.ContainsKey('GuiReady') -and [bool]$splash['GuiReady'])) -and [datetime]::UtcNow -lt $deadline)
						{
							if ($splash.ContainsKey('IsAlive') -and (-not [bool]$splash['IsAlive'])) { break }
							Start-Sleep -Milliseconds 200
						}

						$abortRequested = $false
						if ($splash -is [hashtable])
						{
							if ($splash.ContainsKey('AbortRequested') -and [bool]$splash['AbortRequested']) { $abortRequested = $true }
							elseif ($splash.ContainsKey('UserClosed') -and [bool]$splash['UserClosed']) { $abortRequested = $true }
							elseif ($splash.ContainsKey('ProgrammaticClose') -and [bool]$splash['ProgrammaticClose']) { $abortRequested = $false }
							elseif ($splash.ContainsKey('GuiReady') -and [bool]$splash['GuiReady']) { $abortRequested = $false }
							elseif ($splash.ContainsKey('IsAlive') -and (-not [bool]$splash['IsAlive'])) { $abortRequested = $true }
						}
						if ($abortRequested)
						{
							& $trace 'SplashClose runspace: startup splash closed before GuiReady; aborting process'
							[System.Environment]::Exit(0)
							try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:89' -Severity Debug }
							 $null = $_ }
							return
						}

						& $trace 'SplashClose runspace: GuiReady signaled, revealing GUI before splash close'

						$setMainWindowPresentation = {
							if (-not $mainWindow -or -not $mainWindow.Dispatcher -or $mainWindow.Dispatcher.HasShutdownStarted)
							{
								return
							}

							$splashWindowMaximizedAtReveal = $false
							try
							{
								if ($splash -is [hashtable] -and $splash.ContainsKey('WindowMaximized'))
								{
									$splashWindowMaximizedAtReveal = [bool]$splash['WindowMaximized']
								}
							}
							catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:109' -Severity Debug }
							 $splashWindowMaximizedAtReveal = $false }
							try { & $trace ("SplashClose runspace: WindowMaximized at reveal = {0}" -f [bool]$splashWindowMaximizedAtReveal) } catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:110' -Severity Debug }
							 $null = $_ }

							$splashWindowActiveAtReveal = $false
							try
							{
								if ($splash -is [hashtable] -and $splash.ContainsKey('WindowActive'))
								{
									$splashWindowActiveAtReveal = [bool]$splash['WindowActive']
								}
							}
							catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:120' -Severity Debug }
							 $splashWindowActiveAtReveal = $false }
							try { & $trace ("SplashClose runspace: WindowActive at reveal = {0}" -f [bool]$splashWindowActiveAtReveal) } catch {
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:121' -Severity Debug }
							 $null = $_ }

							$mainWindow.Dispatcher.Invoke([System.Action]{
								try
								{
									if ([bool]$splashWindowMaximizedAtReveal)
									{
										if ($applyStartupSplashMainWindowStateAction)
										{
											$applyStartupSplashMainWindowStateAction.Invoke($true)
										}
									}
								}
								catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:134' -Severity Debug }
								 try { & $trace ("SplashClose runspace: mainWindow maximize handoff failed: {0}" -f $_.Exception.Message) } catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:134' -Severity Debug }
								 $null = $_ }; $null = $_ }
								try { $mainWindow.ShowInTaskbar = $true } catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:135' -Severity Debug }
								 $null = $_ }
								try
								{
									if ($mainWindow.WindowState -eq [System.Windows.WindowState]::Minimized)
									{
										$mainWindow.WindowState = [System.Windows.WindowState]::Normal
									}
								}
								catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:143' -Severity Debug }
								 $null = $_ }
								try { $mainWindow.Opacity = 1 } catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:144' -Severity Debug }
								 $null = $_ }
								try
								{
									if ($mainWindow.Visibility -ne [System.Windows.Visibility]::Visible)
									{
										$mainWindow.Visibility = [System.Windows.Visibility]::Visible
									}
								}
								catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:152' -Severity Debug }
								 $null = $_ }
								try { $mainWindow.ShowActivated = [bool]$splashWindowActiveAtReveal } catch {
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:153' -Severity Debug }
								 $null = $_ }
							})
						}.GetNewClosure()

						try
						{
							if ($splash -is [hashtable] -and $splash.ContainsKey('CompletionAnimationDeadlineUtc') -and $splash['CompletionAnimationDeadlineUtc'] -is [datetime])
							{
								while (($splash.ContainsKey('IsAlive') -and [bool]$splash['IsAlive']) -and [datetime]::UtcNow -lt $splash['CompletionAnimationDeadlineUtc'])
								{
									Start-Sleep -Milliseconds 50
								}
							}
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:167' -Severity Debug }
						 & $trace ("SplashClose runspace: completion animation wait failed: {0}" -f $_.Exception.Message); $null = $_ }

						# Reveal the GUI BEFORE closing the splash so the
						# transition is instant: the GUI is already painted
						# before the splash disappears, so the main window is
						# ready the moment the splash is hidden. If we close
						# the splash first, there's a gap where neither window
						# is visible (desktop flashes).
						try
						{
							& $setMainWindowPresentation
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:179' -Severity Debug }
						 & $trace ("SplashClose runspace: mainWindow presentation transition failed: {0}" -f $_.Exception.Message); $null = $_ }

						$splashDispatcher = if ($splash -is [hashtable] -and $splash.ContainsKey('Dispatcher')) { $splash['Dispatcher'] } else { $null }
						if ($splashDispatcher -and -not $splashDispatcher.HasShutdownStarted)
						{
							$splashDispatcher.Invoke([System.Action]{
								if ($splash -is [hashtable] -and $splash.ContainsKey('ProgrammaticClose')) { $splash['ProgrammaticClose'] = $true }
								$splashWindow = if ($splash -is [hashtable] -and $splash.ContainsKey('Window')) { $splash['Window'] } else { $null }
								if ($splashWindow)
								{
									try { $splashWindow.Hide() } catch {
										if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:189' -Severity Debug }
									 $null = $_ }
									try { $splashWindow.Close() } catch {
										if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:190' -Severity Debug }
									 $null = $_ }
								}
								if ($splash -is [hashtable] -and $splash.ContainsKey('IsAlive')) { $splash['IsAlive'] = $false }
							})
						}

						& $trace 'SplashClose runspace: splash window closed'
						& $trace 'SplashClose runspace: mainWindow left at inherited activation state'

						# Brief wait for window close to propagate, then shut
						# down the splash's runspace so it doesn't leak.
						Start-Sleep -Milliseconds 250
						try
						{
							$splashDispatcher = if ($splash -is [hashtable] -and $splash.ContainsKey('Dispatcher')) { $splash['Dispatcher'] } else { $null }
							if ($splashDispatcher -and -not $splashDispatcher.HasShutdownStarted)
							{
								$splashDispatcher.InvokeShutdown()
							}
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:210' -Severity Debug }
						 & $trace ("SplashClose runspace: dispatcher InvokeShutdown failed: {0}" -f $_.Exception.Message); $null = $_ }
						try
						{
							$splashPowerShell = if ($splash -is [hashtable] -and $splash.ContainsKey('_PowerShell')) { $splash['_PowerShell'] } else { $null }
							$splashAsyncResult = if ($splash -is [hashtable] -and $splash.ContainsKey('_AsyncResult')) { $splash['_AsyncResult'] } else { $null }
							if ($splashPowerShell -and $splashAsyncResult)
							{
								$splashPowerShell.EndInvoke($splashAsyncResult)
							}
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:220' -Severity Debug }
						 & $trace ("SplashClose runspace: PowerShell.EndInvoke failed: {0}" -f $_.Exception.Message); $null = $_ }
						try
						{
							$splashPowerShell = if ($splash -is [hashtable] -and $splash.ContainsKey('_PowerShell')) { $splash['_PowerShell'] } else { $null }
							if ($splashPowerShell) { $splashPowerShell.Dispose() }
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:226' -Severity Debug }
						 & $trace ("SplashClose runspace: PowerShell.Dispose failed: {0}" -f $_.Exception.Message); $null = $_ }
						try
						{
							$splashRunspace = if ($splash -is [hashtable] -and $splash.ContainsKey('_Runspace')) { $splash['_Runspace'] } else { $null }
							if ($splashRunspace) { $splashRunspace.Close(); $splashRunspace.Dispose() }
						}
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:232' -Severity Debug }
						 & $trace ("SplashClose runspace: Runspace.Dispose failed: {0}" -f $_.Exception.Message); $null = $_ }
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:234' -Severity Debug }

						& $trace ("SplashClose runspace failed: {0}" -f $_.Exception.Message)
						$null = $_
					}
				})
				[void]$closePs.BeginInvoke()
			}
		}
		catch
		{
			try { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'splash close orchestration failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.SplashClose.LogWarning.Orchestration' }
			$null = $_
		}

		try
		{
			& $hideConsoleWindowBlock
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:253' -Severity Debug }

			$null = $_
		}

		if (Get-Command -Name 'Update-WindowMinWidthFromHeader' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-WindowMinWidthFromHeader
		}

		if ([bool]$Script:AutoScanOnLaunch -and $invokeGuiSystemScanOnLaunchScript)
		{
			$autoScanAction = {
				try
				{
					& $invokeGuiSystemScanOnLaunchScript
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.AutoScanOnLaunch'
				}
			}.GetNewClosure()
			$null = $Form.Dispatcher.BeginInvoke(
				[System.Action]$autoScanAction,
				[System.Windows.Threading.DispatcherPriority]::ApplicationIdle
			)
		}

		if (-not $shouldShowFirstRunWelcome)
		{
			return
		}

		# Recheck concrete marker path in case another path created it during startup.
		if (Test-Path -LiteralPath $firstRunMarkerPath)
		{
			return
		}

		try
		{
			$openHelpAction = {
				if ($firstRunShowHelpDialogCommand)
				{
					if ($firstRunDialogDispatcher -and $firstRunDialogDispatcher.PSObject.Methods['BeginInvoke'])
					{
						$showHelpDialogAction = {
							& $firstRunShowHelpDialogCommand
						}.GetNewClosure()
						$null = $firstRunDialogDispatcher.BeginInvoke(
							[System.Action]$showHelpDialogAction,
							[System.Windows.Threading.DispatcherPriority]::ApplicationIdle
						)
					}
					else
					{
						& $firstRunShowHelpDialogCommand
					}
				}
			}.GetNewClosure()

			$chooseRecommendedPresetAction = {
				$presetToApply = $firstRunRecommendedPreset
				& $firstRunSetGuiPresetSelectionCommand -PresetName $presetToApply
				& $firstRunSetGuiStatusTextCommand -Text $firstRunPresetLoadedStatusText -Tone 'accent'
			}.GetNewClosure()

			$guidedSetupWizardItem = Get-Item function:Show-GuidedSetupWizard -ErrorAction SilentlyContinue
			$guidedSetupWizardBlock = if ($guidedSetupWizardItem) { $guidedSetupWizardItem.ScriptBlock } else { $null }
			$guidedSetupAction = if ($guidedSetupWizardBlock)
			{
				{
					& $guidedSetupWizardBlock `
						-ShowThemedDialogCapture $showThemedDialogBlock `
						-SetGuiPresetSelectionAction { param($PresetName) & $firstRunSetGuiPresetSelectionCommand -PresetName $PresetName } `
						-SetGuiStatusTextAction { param($Text, $Tone) & $firstRunSetGuiStatusTextCommand -Text $Text -Tone $Tone } `
						-Theme $firstRunTheme `
						-ApplyButtonChrome $firstRunApplyButtonChrome `
						-OwnerWindow $firstRunOwnerWindow `
						-UseDarkMode $firstRunUseDarkMode
				}.GetNewClosure()
			}
			else { $null }

			$dialogResult = & $showWelcomeDialogBlock `
				-RecommendedPreset $firstRunRecommendedPreset `
				-PrimaryActionLabel $firstRunPrimaryActionLabel `
				-WelcomeMessage $firstRunWelcomeMessage `
				-DialogTitle $firstRunDialogTitle `
				-ShowThemedDialogCapture $showThemedDialogBlock `
				-OpenHelpAction $openHelpAction `
				-ChooseRecommendedPresetAction $chooseRecommendedPresetAction `
				-GuidedSetupAction $guidedSetupAction `
				-Theme $firstRunTheme `
				-ApplyButtonChrome $firstRunApplyButtonChrome `
				-OwnerWindow $firstRunOwnerWindow `
				-UseDarkMode $firstRunUseDarkMode

			if ($dialogResult)
			{
				# Do NOT call Complete-GuiFirstRunWelcome here.
				# Write the marker directly using the already-validated concrete path.
				if (-not (Test-Path -LiteralPath $firstRunMarkerDirectory))
				{
					$null = New-Item -ItemType Directory -Path $firstRunMarkerDirectory -Force -ErrorAction Stop
				}

				Set-Content -LiteralPath $firstRunMarkerPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding UTF8 -Force
			}
		}
		catch
		{
			throw "First-run welcome failed: $($_.Exception.Message)"
		}
	}.GetNewClosure()) | Out-Null
