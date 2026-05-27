foreach ($Shortcut in $Shortcuts)
	{
		switch ($Shortcut)
		{
			Mail
			{
				$MailPatterns = @('^Mail$', 'Mail and Calendar', 'Outlook \(new\)', 'Outlook for Windows')
				$MailFallbackPatterns = @('Mail*.lnk', '*Outlook*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					$DeferredUnpinNames.Add('^Mail$')
					$DeferredUnpinNames.Add('Mail and Calendar')
					$DeferredUnpinNames.Add('Outlook \(new\)')
					$DeferredUnpinNames.Add('Outlook for Windows')
				}
				else
				{
					$MailItems = @(
						Get-UIPersonalizationTaskbarPinnedMatches -Patterns $MailPatterns
						$AppsFolder.Items() | Where-Object {
							$_.Name -match 'Mail' -or
							$_.Name -match 'Outlook \(new\)' -or
							$_.Name -match 'Outlook for Windows'
						}
					) | Select-Object -Unique

					if ($MailItems)
					{
						$MailItems | ForEach-Object {
							if (-not (Invoke-UIPersonalizationTaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Mail' was not found."
						$UnpinMisses++
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					}
				}
			}
			Edge
			{
				$EdgeFallbackPatterns = @('Microsoft Edge*.lnk', 'Edge*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Edge')
				}
				else
				{
					$EdgeItems = @(Get-UIPersonalizationTaskbarPinnedMatches -Patterns @('Microsoft Edge', '^Edge$'))
					if ($EdgeItems)
					{
						$EdgeItems | ForEach-Object {
							if (-not (Invoke-UIPersonalizationTaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Edge' was not found."
						$UnpinMisses++
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					}
				}
			}
			Store
			{
				$StoreFallbackPatterns = @('Microsoft Store*.lnk', '*Store*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Store')
				}
				else
				{
					$StoreItems = @(
						Get-UIPersonalizationTaskbarPinnedMatches -Patterns @('Microsoft Store', '^Store$')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -eq "Microsoft Store" -or
							$_.Name -eq "Store"
						}
					) | Select-Object -Unique
					if ($StoreItems)
					{
						$StoreItems | ForEach-Object {
							if (-not (Invoke-UIPersonalizationTaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Store' was not found."
						$UnpinMisses++
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					}
				}
			}
			Outlook
			{
				$OutlookPatterns = @('Outlook', 'Mail and Calendar')
				$OutlookFallbackPatterns = @('*Outlook*.lnk', 'Mail*.lnk', '*Office*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					$DeferredUnpinNames.Add('Outlook')
					$DeferredUnpinNames.Add('Mail and Calendar')
				}
				else
				{
					$OutlookItems = @(
						Get-UIPersonalizationTaskbarPinnedMatches -Patterns $OutlookPatterns
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match 'Outlook' -or
							$_.Name -eq 'Mail and Calendar'
						}
					) | Select-Object -Unique
					if ($OutlookItems)
					{
						$OutlookItems | ForEach-Object {
							if (-not (Invoke-UIPersonalizationTaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Outlook' was not found."
						$UnpinMisses++
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					}
				}
			}
			Copilot
			{
				# Disable the dedicated Copilot taskbar button
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "ShowCopilotButton" `
					-Value 0 `
					-Type DWord

				# Disable Copilot companion in taskbar search
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TaskbarCompanion" `
					-Value 0 `
					-Type DWord

				$CopilotPinPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins"

				if (-not (Test-Path -Path $CopilotPinPath))
				{
					New-Item -Path $CopilotPinPath -Force | Out-Null
				}

				Set-RegistryValueSafe -Path $CopilotPinPath `
					-Name "CopilotPWAPin" `
					-Value 0 `
					-Type DWord
				Set-RegistryValueSafe -Path $CopilotPinPath `
					-Name "RecallPin" `
					-Value 0 `
					-Type DWord

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns @('*Copilot*.lnk', '*Recall*.lnk')
					$DeferredUnpinNames.Add('Copilot')
				}
				else
				{
					$CopilotItems = @(
						Get-UIPersonalizationTaskbarPinnedMatches -Patterns @('Copilot', 'Recall')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match 'Copilot'
						}
					) | Select-Object -Unique
					if ($CopilotItems)
					{
						$CopilotItems | ForEach-Object {
							if (-not (Invoke-UIPersonalizationTaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Copilot' was not found."
						$UnpinMisses++
					}
				}
			}
			Microsoft365
			{
				$Microsoft365FallbackPatterns = @('*Microsoft 365*.lnk', '*Office*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					$DeferredUnpinNames.Add('Microsoft 365')
					$DeferredUnpinNames.Add('^Office$')
				}
				else
				{
					$Microsoft365Items = @(
						Get-UIPersonalizationTaskbarPinnedMatches -Patterns @('Microsoft 365', 'Office')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match "Microsoft 365" -or
							$_.Name -match "Office"
						}
					) | Select-Object -Unique

					if ($Microsoft365Items)
					{
						$Microsoft365Items | ForEach-Object {
							if (-not (Invoke-UIPersonalizationTaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Microsoft365' was not found."
						$UnpinMisses++
						$null = Remove-UIPersonalizationTaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					}
				}
			}
		}
	}
