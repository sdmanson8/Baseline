using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Taskbar

function NewsInterests
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable,

		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable
	)

	# Remove old policies silently
	$null = Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name EnableFeeds -Force -ErrorAction SilentlyContinue
	$null = Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests" -Name value -Force -ErrorAction SilentlyContinue

	# Skip if Edge is not installed
	if (-not (Get-Package -Name "Microsoft Edge" -ProviderName Programs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue))
	{
		LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	# Get MachineId
	$MachineId = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient", "MachineId", $null)
	if (-not $MachineId)
	{
		LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'News and Interests' on the taskbar"
			LogInfo "Disabling 'News and Interests' on the taskbar"

			try
			{
				Set-NewsInterestsTaskbarViewMode -MachineId $MachineId -ViewMode 2
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Unable to fully update 'News and Interests' taskbar settings: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}

		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'News and Interests' on the taskbar"
			LogInfo "Enabling 'News and Interests' on the taskbar"

			try
			{
				Set-NewsInterestsTaskbarViewMode -MachineId $MachineId -ViewMode 0
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Unable to fully update 'News and Interests' taskbar settings: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}
	}
}

function TaskbarAlignment
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Left"
		)]
		[switch]
		$Left,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Center"
		)]
		[switch]
		$Center
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Center"
		{
			Write-ConsoleStatus -Action "Setting the taskbar alignment to the Center"
			LogInfo "Setting the taskbar alignment to the Center"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarAl -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set taskbar alignment to the center: $($_.Exception.Message)"
			}
		}
		"Left"
		{
			Write-ConsoleStatus -Action "Setting the taskbar alignment to the Left"
			LogInfo "Setting the taskbar alignment to the Left"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarAl -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set taskbar alignment to the left: $($_.Exception.Message)"
			}
		}
	}
}

function TaskbarWidgets
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	if (-not (Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -WarningAction SilentlyContinue))
	{
		LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		#LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
	}

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests -Name value -Force -ErrorAction Ignore | Out-Null
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Dsh -Name AllowNewsAndInterests -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Dsh -Name AllowNewsAndInterests -Type CLEAR | Out-Null

	# UCPD driver blocks TaskbarDa registry writes from known executables.
	# Use copied PowerShell with guaranteed cleanup via shared helper.
	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the widgets icon on the taskbar"
			LogInfo "Disabling the widgets icon on the taskbar"
			Invoke-UCPDBypassed -ScriptBlock {New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -PropertyType DWord -Value 0 -Force}
			Write-ConsoleStatus -Status success
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the widgets icon on the taskbar"
			LogInfo "Enabling the widgets icon on the taskbar"
			Invoke-UCPDBypassed -ScriptBlock {New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -PropertyType DWord -Value 1 -Force}
			Write-ConsoleStatus -Status success
		}
	}
}

function TaskbarSearch
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchIcon"
		)]
		[switch]
		$SearchIcon,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchIconLabel"
		)]
		[switch]
		$SearchIconLabel,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchBox"
		)]
		[switch]
		$SearchBox
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Search\DisableSearch -Name value -PropertyType DWord -Value 0 -Force -ErrorAction Ignore | Out-Null
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name DisableSearch, SearchOnTaskbarMode -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name DisableSearch -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name SearchOnTaskbarMode -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the search on the taskbar"
			LogInfo "Disabling the search on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide search on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchIcon"
		{
			Write-ConsoleStatus -Action "Enabling the search icon on the taskbar"
			LogInfo "Enabling the search icon on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search icon on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchIconLabel"
		{
			Write-ConsoleStatus -Action "Enabling the search icon label on the taskbar"
			LogInfo "Enabling the search icon label on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 3 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search icon label on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchBox"
		{
			Write-ConsoleStatus -Action "Enabling the search box on the taskbar"
			LogInfo "Enabling the search box on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search box on the taskbar: $($_.Exception.Message)"
			}
		}
	}
}

function SearchHighlights
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name EnableDynamicContentInWSB -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name EnableDynamicContentInWSB -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling search highlights"
			LogInfo "Disabling search highlights"
			# Checking whether "Ask Copilot" and "Find results in Web" were disabled. They also disable Search Highlights automatically
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			$BingSearchEnabled = ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search", "BingSearchEnabled", $null))
			$DisableSearchBoxSuggestions = ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer", "DisableSearchBoxSuggestions", $null))
			if (($BingSearchEnabled -eq 1) -or ($DisableSearchBoxSuggestions -eq 1))
			{
				LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
				Write-ConsoleStatus -Status warning
			}
			else
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings -Name IsDynamicSearchBoxEnabled -PropertyType DWord -Value 0 -Force | Out-Null
				Write-ConsoleStatus -Status success
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling search highlights"
			LogInfo "Enabling search highlights"
			# Enable "Ask Copilot" and "Find results in Web" icons in Windows Search in order to enable Search Highlights
			Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name BingSearchEnabled -Force -ErrorAction Ignore | Out-Null
			Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions -Force -ErrorAction Ignore | Out-Null
			New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings -Name IsDynamicSearchBoxEnabled -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

function TaskViewButton
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the Task view button on the taskbar"
			LogInfo "Disabling the Task view button on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the Task View button on the taskbar: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the Task view button on the taskbar"
			LogInfo "Enabling the Task view button on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the Task View button on the taskbar: $($_.Exception.Message)"
			}
		}
	}
}

function TaskbarCombine
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Always"
		)]
		[switch]
		$Always,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Full"
		)]
		[switch]
		$Full,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Never"
		)]
		[switch]
		$Never
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Always"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and always hide labels"
			LogInfo "Combine taskbar buttons and always hide labels"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to always combine taskbar buttons and hide labels: $($_.Exception.Message)"
			}
		}
		"Full"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and hide labels when taskbar is full"
			LogInfo "Combine taskbar buttons and hide labels when taskbar is full"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to combine taskbar buttons when the taskbar is full: $($_.Exception.Message)"
			}
		}
		"Never"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and never hide labels"
			LogInfo "Combine taskbar buttons and never hide labels"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to never combine taskbar buttons and labels: $($_.Exception.Message)"
			}
		}
	}
}

function UnpinTaskbarShortcuts
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet("Edge", "Store", "Outlook", "Mail", "Copilot", "Microsoft365")]
		[string[]]
		$Shortcuts
	)

	$TaskbarPinnedPath = Join-Path $env:AppData "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
	$IsARM64 = ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") -or
		($env:PROCESSOR_ARCHITEW6432 -eq "ARM64") -or
		([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64)
	$IsWindows10 = [System.Environment]::OSVersion.Version.Build -lt 22000
	# ARM64 and Windows 10 already needed the STA-runspace path (original condition).
	# AMD64 Windows 11 also needs it - direct COM shell verb calls silently do nothing on Win11 x64.
	$NeedsDeferredUnpin = $IsARM64 -or $IsWindows10 -or (-not $IsWindows10 -and -not $IsARM64)
	$AppsFolder = (New-Object -ComObject Shell.Application).NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")

	Write-ConsoleStatus -Action "Unpin taskbar apps"
	LogInfo "Unpin taskbar apps"
	$UnpinFailures = 0
	$UnpinMisses = 0

	# Always initialize the list; populated on ARM64 and Windows 10
	$DeferredUnpinNames = [System.Collections.Generic.List[string]]::new()

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
					$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $MailFallbackPatterns
					$DeferredUnpinNames.Add('^Mail$')
					$DeferredUnpinNames.Add('Mail and Calendar')
					$DeferredUnpinNames.Add('Outlook \(new\)')
					$DeferredUnpinNames.Add('Outlook for Windows')
				}
				else
				{
					$MailItems = @(
						Get-TaskbarPinnedMatches -PinnedPath $TaskbarPinnedPath -Patterns $MailPatterns
						$AppsFolder.Items() | Where-Object {
							$_.Name -match 'Mail' -or
							$_.Name -match 'Outlook \(new\)' -or
							$_.Name -match 'Outlook for Windows'
						}
					) | Select-Object -Unique

					if ($MailItems)
					{
						$MailItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $MailFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Mail' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $MailFallbackPatterns
					}
				}
			}
			Edge
			{
				$EdgeFallbackPatterns = @('Microsoft Edge*.lnk', 'Edge*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $EdgeFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Edge')
				}
				else
				{
					$EdgeItems = @(Get-TaskbarPinnedMatches -PinnedPath $TaskbarPinnedPath -Patterns @('Microsoft Edge', '^Edge$'))
					if ($EdgeItems)
					{
						$EdgeItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $EdgeFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Edge' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $EdgeFallbackPatterns
					}
				}
			}
			Store
			{
				$StoreFallbackPatterns = @('Microsoft Store*.lnk', '*Store*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $StoreFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Store')
				}
				else
				{
					$StoreItems = @(
						Get-TaskbarPinnedMatches -PinnedPath $TaskbarPinnedPath -Patterns @('Microsoft Store', '^Store$')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -eq "Microsoft Store" -or
							$_.Name -eq "Store"
						}
					) | Select-Object -Unique
					if ($StoreItems)
					{
						$StoreItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $StoreFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Store' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $StoreFallbackPatterns
					}
				}
			}
			Outlook
			{
				$OutlookPatterns = @('Outlook', 'Mail and Calendar')
				$OutlookFallbackPatterns = @('*Outlook*.lnk', 'Mail*.lnk', '*Office*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $OutlookFallbackPatterns
					$DeferredUnpinNames.Add('Outlook')
					$DeferredUnpinNames.Add('Mail and Calendar')
				}
				else
				{
					$OutlookItems = @(
						Get-TaskbarPinnedMatches -PinnedPath $TaskbarPinnedPath -Patterns $OutlookPatterns
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match 'Outlook' -or
							$_.Name -eq 'Mail and Calendar'
						}
					) | Select-Object -Unique
					if ($OutlookItems)
					{
						$OutlookItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $OutlookFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Outlook' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $OutlookFallbackPatterns
					}
				}
			}
			Copilot
			{
				# Disable the dedicated Copilot taskbar button
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -PropertyType DWord -Value 0 -Force | Out-Null

				# Disable Copilot companion in taskbar search
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarCompanion" -PropertyType DWord -Value 0 -Force | Out-Null

				$CopilotPinPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins"

				if (-not (Test-Path -Path $CopilotPinPath))
				{
					New-Item -Path $CopilotPinPath -Force | Out-Null
				}

				New-ItemProperty -Path $CopilotPinPath -Name "CopilotPWAPin" -PropertyType DWord -Value 0 -Force | Out-Null
				New-ItemProperty -Path $CopilotPinPath -Name "RecallPin" -PropertyType DWord -Value 0 -Force | Out-Null

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns @('*Copilot*.lnk', '*Recall*.lnk')
					$DeferredUnpinNames.Add('Copilot')
				}
				else
				{
					$CopilotItems = @(
						Get-TaskbarPinnedMatches -PinnedPath $TaskbarPinnedPath -Patterns @('Copilot', 'Recall')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match 'Copilot'
						}
					) | Select-Object -Unique
					if ($CopilotItems)
					{
						$CopilotItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
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
					$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $Microsoft365FallbackPatterns
					$DeferredUnpinNames.Add('Microsoft 365')
					$DeferredUnpinNames.Add('^Office$')
				}
				else
				{
					$Microsoft365Items = @(
						Get-TaskbarPinnedMatches -PinnedPath $TaskbarPinnedPath -Patterns @('Microsoft 365', 'Office')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match "Microsoft 365" -or
							$_.Name -match "Office"
						}
					) | Select-Object -Unique

					if ($Microsoft365Items)
					{
						$Microsoft365Items | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $Microsoft365FallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Microsoft365' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -PinnedPath $TaskbarPinnedPath -Patterns $Microsoft365FallbackPatterns
					}
				}
			}
		}
	}

	# ARM64 and Windows 10: run COM unpin in a background STA runspace with timeout
	if ($NeedsDeferredUnpin -and $DeferredUnpinNames.Count -gt 0)
	{
		Invoke-ARM64ShellUnpin -AppNames $DeferredUnpinNames.ToArray() -PinnedPath $TaskbarPinnedPath -TimeoutSeconds 15
	}

	# Restart Explorer to apply taskbar changes.
	# In GUI mode PostActions handles the Explorer restart after all tweaks finish,
	# so skip the mid-execution restart that can leave the shell unstable for
	# subsequent tweaks.
	if (-not $Global:GUIMode)
	{
		try
		{
			Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
			Start-Sleep -Seconds 3
			Start-Process "explorer.exe" -ErrorAction SilentlyContinue
			# Wait for Explorer to be ready
			for ($w = 0; $w -lt 20; $w++)
			{
				if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { break }
				Start-Sleep -Milliseconds 500
			}
		}
		catch
		{
			LogWarning "Failed to restart Explorer after taskbar unpin: $($_.Exception.Message)"
		}
	}

	if ($UnpinFailures -gt 0)
	{
		Write-ConsoleStatus -Status warning
	}
	else
	{
		Write-ConsoleStatus -Status success
	}
}

function TaskbarEndTask
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'End task in taskbar by right click'"
			LogInfo "Enabling 'End task in taskbar by right click'"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Name TaskbarEndTask -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable 'End task in taskbar by right click': $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'End task in taskbar by right click'"
			LogInfo "Disabling 'End task in taskbar by right click'"
			try
			{
				Remove-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable 'End task in taskbar by right click': $($_.Exception.Message)"
			}
		}
	}
}

function MeetNow
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name HideSCAMeetNow -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name HideSCAMeetNow -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name HideSCAMeetNow -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the Meet Now icon in the notification area"
			LogInfo "Disabling the Meet Now icon in the notification area"
			try
			{
				$Script:MeetNow = $false
				$Settings = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -ErrorAction Stop
				$Settings[9] = 128
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -PropertyType Binary -Value $Settings -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the Meet Now icon in the notification area: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the Meet Now icon in the notification area"
			LogInfo "Enabling the Meet Now icon in the notification area"
			try
			{
				$Script:MeetNow = $true
				$Settings = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -ErrorAction Stop
				$Settings[9] = 0
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -PropertyType Binary -Value $Settings -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the Meet Now icon in the notification area: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function '*'
