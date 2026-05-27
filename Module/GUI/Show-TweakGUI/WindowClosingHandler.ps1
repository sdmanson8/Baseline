Register-GuiEventHandler -Source $Form -EventName 'Closing' -Handler ({
			param($windowSource, $e)
			if ($Script:SuppressRunClosePrompt) { return }
			if ($Script:AbortRequested -and (Get-RunAbortDisposition) -eq 'Return')
			{
				$e.Cancel = $true
				return
			}
			if (& $Script:TestGuiRunInProgressScript)
			{
				$e.Cancel = $true
			# Trigger the abort prompt if user attempts to close while running
			& $Script:PromptRunAbortFn
			return
		}

			if (-not $Script:ForceCloseCompleted)
			{
				# Persist the current GUI session silently; restore-on-launch is
				# controlled by the GUI settings toggle.
				$null = Save-GuiSessionState
				if (Get-Command -Name 'Save-GuiDetectCache' -CommandType Function -ErrorAction SilentlyContinue)
				{
					try { Save-GuiDetectCache } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.DetectCache.SaveOnClosing' }
				}
			}
		}) | Out-Null

	Register-GuiEventHandler -Source $Form -EventName 'Closed' -Handler ({
			param($closedSender, $e)

			$dispatcher = if ($closedSender -and $closedSender.Dispatcher)
			{
				$closedSender.Dispatcher
			}
			elseif ($Script:MainForm -and $Script:MainForm.Dispatcher)
			{
				$Script:MainForm.Dispatcher
			}
			else
			{
				$null
			}

			if ($Script:GuiUnhandledExceptionHooked -and $Script:GuiUnhandledExceptionHandler -and $dispatcher)
			{
				try
				{
					$dispatcher.remove_UnhandledException($Script:GuiUnhandledExceptionHandler)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\WindowClosingHandler.ps1:51' -Severity Debug }

					$null = $_
				}
			}

			if ($Script:SearchRefreshTimer)
			{
				try { $Script:SearchRefreshTimer.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.SearchRefreshTimer.Stop' }
				$Script:SearchRefreshTimer = $null
			}
			if ($Script:FilterRefreshTimer)
			{
				try { $Script:FilterRefreshTimer.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.FilterRefreshTimer.Stop' }
				$Script:FilterRefreshTimer = $null
			}

			$stopSupportBundleExportVariable = Get-Variable -Scope Script -Name 'StopGuiSupportBundleExportWorkerScript' -ErrorAction SilentlyContinue
			$stopSupportBundleExportCommand = if ($stopSupportBundleExportVariable) { $stopSupportBundleExportVariable.Value } else { $null }
			if (-not $stopSupportBundleExportCommand -and (Get-Command -Name 'Get-GuiFunctionCapture' -CommandType Function -ErrorAction SilentlyContinue))
			{
				$stopSupportBundleExportCommand = Get-GuiFunctionCapture -Name 'Stop-GuiSupportBundleExportWorker'
			}
			if ($stopSupportBundleExportCommand)
			{
				try { & $stopSupportBundleExportCommand -Reason 'Support bundle export stopped because the GUI closed.' -StopPowerShell -SkipEndInvoke }
				catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.SupportBundleExport.StopOnClose' }
			}

			Clear-GuiWindowRuntimeState

			$Script:GuiUnhandledExceptionHooked = $false
			$Script:GuiUnhandledExceptionHandler = $null
			if ($Script:MainForm -eq $closedSender)
			{
				$Script:MainForm = $null
			}
		}) | Out-Null
