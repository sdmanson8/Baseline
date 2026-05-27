if ($shouldRestoreLastSession -and $Script:StartupSessionSnapshot)
	{
		$restoreGuiSessionStateScript = Get-GuiFunctionCapture -Name 'Restore-GuiSessionState'
		$setGuiStatusTextScript = Get-GuiFunctionCapture -Name 'Set-GuiStatusText'
		$refreshCurrentTabContentScript = Get-GuiFunctionCapture -Name 'Update-CurrentTabContent'
		$testVisibleTabContentCurrentScript = Get-GuiFunctionCapture -Name 'Test-GuiVisibleTabContentCurrent'
		$restoredSessionAction = {
			$restoredGuiSession = $false
			try
			{
				$restoredGuiSession = & $restoreGuiSessionStateScript -Snapshot $Script:StartupSessionSnapshot -PreserveDurablePreferences
				if ($restoredGuiSession)
				{
					if ($setGuiStatusTextScript) { & $setGuiStatusTextScript -Text $restoredSessionStatusText -Tone 'accent' }
				}
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.RestoreStartupSession'
			}
			finally
			{
				$hydrateVisibleTab = (-not $restoredGuiSession -and [bool]$Script:StartupRestoreSessionPending)
				if ($restoredGuiSession -and $testVisibleTabContentCurrentScript)
				{
					try
					{
						$hydrateVisibleTab = -not [bool](& $testVisibleTabContentCurrentScript)
					}
					catch
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.RestoreStartupSession.CheckVisibleTab'
						$hydrateVisibleTab = $true
					}
				}

				if ($hydrateVisibleTab)
				{
					try
					{
						if ($refreshCurrentTabContentScript)
						{
							& $refreshCurrentTabContentScript -SkipIdlePrebuild
						}
					}
					catch
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.RestoreStartupSession.HydrateVisibleTab'
					}
					finally
					{
						$Script:StartupRestoreSessionPending = $false
					}
				}
			}
		}.GetNewClosure()
		& $restoredSessionAction
	}
