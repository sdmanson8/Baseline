using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Taskbar alignment

	.PARAMETER Left
	Set the taskbar alignment to the left

	.PARAMETER Center
	Set the taskbar alignment to the center (default value)

	.EXAMPLE
	TaskbarAlignment -Center

	.EXAMPLE
	TaskbarAlignment -Left

	.NOTES
	Current user
#>
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

<#
	.SYNOPSIS
	The widgets icon on the taskbar

	.PARAMETER Hide
	Hide the widgets icon on the taskbar

	.PARAMETER Show
	Show the widgets icon on the taskbar (default value)

	.EXAMPLE
	TaskbarWidgets -Hide

	.EXAMPLE
	TaskbarWidgets -Show

	.NOTES
	Current user
#>
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

	# We cannot set a value to TaskbarDa, having called any of APIs, except of copying powershell.exe (or any other tricks) with a different name, due to a UCPD driver tracks all executables to block the access to the registry
	Copy-Item -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Force | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the widgets icon on the taskbar"
			LogInfo "Disabling the widgets icon on the taskbar"
			& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Command {New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -PropertyType DWord -Value 0 -Force} | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the widgets icon on the taskbar"
			LogInfo "Enabling the widgets icon on the taskbar"
			& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Command {New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -PropertyType DWord -Value 1 -Force} | Out-Null
			Write-ConsoleStatus -Status success
		}
	}

	Remove-Item -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Force | Out-Null
}

<#
	.SYNOPSIS
	Search on the taskbar

	.PARAMETER Hide
	Hide the search on the taskbar

	.PARAMETER SearchIcon
	Show the search icon on the taskbar

	.PARAMETER SearchBox
	Show the search box on the taskbar (default value)

	.EXAMPLE
	TaskbarSearch -Hide

	.EXAMPLE
	TaskbarSearch -SearchIcon

	.EXAMPLE
	TaskbarSearch -SearchIconLabel

	.EXAMPLE
	TaskbarSearch -SearchBox

	.NOTES
	Current user
#>
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

<#
	.SYNOPSIS
	Search highlights

	.PARAMETER Hide
	Hide search highlights

	.PARAMETER Show
	Show search highlights (default value)

	.EXAMPLE
	SearchHighlights -Hide

	.EXAMPLE
	SearchHighlights -Show

	.NOTES
	Current user
#>
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
			}
			else
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings -Name IsDynamicSearchBoxEnabled -PropertyType DWord -Value 0 -Force | Out-Null

			}
			Write-ConsoleStatus -Status success
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

<#
	.SYNOPSIS
	Task view button on the taskbar

	.PARAMETER Hide
	Hide the Task view button on the taskbar

	.PARAMETER Show
	Show the Task View button on the taskbar (default value)

	.EXAMPLE
	TaskViewButton -Hide

	.EXAMPLE
	TaskViewButton -Show

	.NOTES
	Current user
#>
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

<#
	.SYNOPSIS
	Combine taskbar buttons and hide labels

	.PARAMETER Always
	Combine taskbar buttons and always hide labels (default value)

	.PARAMETER Full
	Combine taskbar buttons and hide labels when taskbar is full

	.PARAMETER Never
	Combine taskbar buttons and never hide labels

	.EXAMPLE
	TaskbarCombine -Always

	.EXAMPLE
	TaskbarCombine -Full

	.EXAMPLE
	TaskbarCombine -Never

	.NOTES
	Current user
#>
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

<#
	.SYNOPSIS
	Unpin shortcuts from the taskbar

	.PARAMETER Edge
	Unpin Microsoft Edge shortcut from the taskbar

	.PARAMETER Store
	Unpin Microsoft Store from the taskbar

	.PARAMETER Outlook
	Unpin Outlook shortcut from the taskbar

	.PARAMETER Mail
	Unpin Mail shortcut from the taskbar

	.PARAMETER Copilot
	Unpin Copilot shortcut from the taskbar

	.PARAMETER Microsoft365
	Unpin Microsoft 365 shortcut from the taskbar

	.EXAMPLE
	UnpinTaskbarShortcuts -Shortcuts Edge, Store, Outlook, Mail, Copilot, Microsoft365

	.NOTES
	Current user
#>
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
	# AMD64 Windows 11 also needs it — direct COM shell verb calls silently do nothing on Win11 x64.
	$NeedsDeferredUnpin = $IsARM64 -or $IsWindows10 -or (-not $IsWindows10 -and -not $IsARM64)

	function Get-TaskbarPinnedItems
	{
		if (-not (Test-Path -Path $TaskbarPinnedPath))
		{
			return @()
		}

		$TaskbarShell = (New-Object -ComObject Shell.Application).NameSpace($TaskbarPinnedPath)
		if ($null -eq $TaskbarShell)
		{
			return @()
		}

		return @($TaskbarShell.Items())
	}

	function Get-TaskbarPinnedMatches
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string[]]$Patterns
		)

		$NormalizedPatterns = @($Patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
		if ($NormalizedPatterns.Count -eq 0)
		{
			return @()
		}

		return @(Get-TaskbarPinnedItems | Where-Object {
			$ItemName = $_.Name
			foreach ($Pattern in $NormalizedPatterns)
			{
				if ($ItemName -match $Pattern)
				{
					return $true
				}
			}

			return $false
		})
	}

	function Invoke-TaskbarUnpin
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		$verbCandidates = @($LocalizedString, 'Unpin from taskbar', 'Von Taskleiste losen', 'Desanclar de la barra de tareas') |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
			Select-Object -Unique

		$unpinVerb = $ShellItem.Verbs() | Where-Object {
			$verbName = (($_.Name -replace '&', '').Trim())
			($verbCandidates -contains $verbName) -or
			($verbName -like '*Unpin*') -or
			($verbName -like '*taskbar*')
		} | Select-Object -First 1

		if ($unpinVerb)
		{
			try
			{
				$unpinVerb.DoIt()
				return $true
			}
			catch [System.UnauthorizedAccessException]
			{
				LogWarning "Taskbar unpin verb was denied for '$($ShellItem.Name)'."
				return $false
			}
			catch
			{
				LogWarning "Taskbar unpin verb failed for '$($ShellItem.Name)': $($_.Exception.Message)"
				return $false
			}
		}

		return $false
	}

	function Remove-TaskbarPinnedLink
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		try
		{
			if ([string]::IsNullOrWhiteSpace($ShellItem.Path) -or -not (Test-Path -LiteralPath $ShellItem.Path))
			{
				return $false
			}

			Remove-Item -LiteralPath $ShellItem.Path -Force -ErrorAction Stop
			LogInfo "Removed taskbar pinned shortcut file '$($ShellItem.Name)' as fallback."
			return $true
		}
		catch
		{
			LogWarning "Taskbar shortcut fallback removal failed for '$($ShellItem.Name)': $($_.Exception.Message)"
			return $false
		}
	}

	function Invoke-TaskbarUnpinWithFallback
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		if (Invoke-TaskbarUnpin -ShellItem $ShellItem)
		{
			return $true
		}

		return (Remove-TaskbarPinnedLink -ShellItem $ShellItem)
	}

	function Remove-TaskbarPinnedLinksByPattern
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string[]]$Patterns
		)

		if (-not (Test-Path -Path $TaskbarPinnedPath))
		{
			return $false
		}

		$RemovedAny = $false
		$LinkFiles = Get-ChildItem -Path $TaskbarPinnedPath -Filter "*.lnk" -ErrorAction SilentlyContinue
		foreach ($LinkFile in $LinkFiles)
		{
			$MatchesPattern = $false
			foreach ($Pattern in $Patterns)
			{
				if ($LinkFile.Name -like $Pattern)
				{
					$MatchesPattern = $true
					break
				}
			}

			if (-not $MatchesPattern)
			{
				continue
			}

			try
			{
				Remove-Item -LiteralPath $LinkFile.FullName -Force -ErrorAction Stop
				LogInfo "Removed taskbar pinned shortcut file '$($LinkFile.Name)' by filename fallback."
				$RemovedAny = $true
			}
			catch
			{
				LogWarning "Filename fallback removal failed for '$($LinkFile.Name)': $($_.Exception.Message)"
			}
		}

		return $RemovedAny
	}

	function Invoke-ARM64ShellUnpin
	{
		<#
			.SYNOPSIS
			ARM64 fallback: Unpin apps using COM shell verb in an in-process STA runspace with timeout.
			On ARM64, direct COM calls can hang so we run them on a background thread.
		#>
		param
		(
			[Parameter(Mandatory = $true)]
			[string[]]$AppNames,

			[int]$TimeoutSeconds = 15
		)

		$Runspace = [runspacefactory]::CreateRunspace()
		$Runspace.ApartmentState = "STA"
		$Runspace.Open()

		$PS = [powershell]::Create()
		$PS.Runspace = $Runspace

		$null = $PS.AddScript({
			param ($Names, $PinnedPath)
			$Shell = New-Object -ComObject Shell.Application
			$AppsFolder = $Shell.NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
			$Pinned = $Shell.NameSpace($PinnedPath)

			$VerbCandidates = @('Unpin from taskbar', 'Von Taskleiste losen', 'Desanclar de la barra de tareas',
				'Detacher de la barre des taches', 'Rimuovi dalla barra delle applicazioni')

			$Items = @()
			if ($Pinned) { $Items += @($Pinned.Items()) }
			if ($AppsFolder) { $Items += @($AppsFolder.Items()) }

			foreach ($Name in $Names)
			{
				$MatchingItems = @($Items | Where-Object { $_.Name -match $Name })
				foreach ($Item in $MatchingItems)
				{
					$UnpinVerb = $Item.Verbs() | Where-Object {
						$VerbName = (($_.Name -replace '&', '').Trim())
						($VerbCandidates -contains $VerbName) -or ($VerbName -match 'Unpin.*taskbar') -or ($VerbName -match 'taskbar.*unpin')
					} | Select-Object -First 1

					if ($UnpinVerb)
					{
						try { $UnpinVerb.DoIt() } catch {}
					}
				}
			}
		}).AddArgument($AppNames).AddArgument($TaskbarPinnedPath)

		$AsyncResult = $PS.BeginInvoke()

		if (-not $AsyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)))
		{
			LogWarning "ARM64 shell unpin timed out after $TimeoutSeconds seconds."
		}
		else
		{
			try { $PS.EndInvoke($AsyncResult) } catch {}
		}

		$PS.Dispose()
		$Runspace.Dispose()
	}

	# Extract the localized "Unpin from taskbar" string from shell32.dll
	$LocalizedString = [WinAPI.GetStrings]::GetString(5387)
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
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					$DeferredUnpinNames.Add('^Mail$')
					$DeferredUnpinNames.Add('Mail and Calendar')
					$DeferredUnpinNames.Add('Outlook \(new\)')
					$DeferredUnpinNames.Add('Outlook for Windows')
				}
				else
				{
					$MailItems = @(
						Get-TaskbarPinnedMatches -Patterns $MailPatterns
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
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Mail' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					}
				}
			}
			Edge
			{
				$EdgeFallbackPatterns = @('Microsoft Edge*.lnk', 'Edge*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Edge')
				}
				else
				{
					$EdgeItems = @(Get-TaskbarPinnedMatches -Patterns @('Microsoft Edge', '^Edge$'))
					if ($EdgeItems)
					{
						$EdgeItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Edge' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					}
				}
			}
			Store
			{
				$StoreFallbackPatterns = @('Microsoft Store*.lnk', '*Store*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Store')
				}
				else
				{
					$StoreItems = @(
						Get-TaskbarPinnedMatches -Patterns @('Microsoft Store', '^Store$')
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
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Store' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					}
				}
			}
			Outlook
			{
				$OutlookPatterns = @('Outlook', 'Mail and Calendar')
				$OutlookFallbackPatterns = @('*Outlook*.lnk', 'Mail*.lnk', '*Office*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					$DeferredUnpinNames.Add('Outlook')
					$DeferredUnpinNames.Add('Mail and Calendar')
				}
				else
				{
					$OutlookItems = @(
						Get-TaskbarPinnedMatches -Patterns $OutlookPatterns
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
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Outlook' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
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
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns @('*Copilot*.lnk', '*Recall*.lnk')
					$DeferredUnpinNames.Add('Copilot')
				}
				else
				{
					$CopilotItems = @(
						Get-TaskbarPinnedMatches -Patterns @('Copilot', 'Recall')
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
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					$DeferredUnpinNames.Add('Microsoft 365')
					$DeferredUnpinNames.Add('^Office$')
				}
				else
				{
					$Microsoft365Items = @(
						Get-TaskbarPinnedMatches -Patterns @('Microsoft 365', 'Office')
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
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Microsoft365' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					}
				}
			}
		}
	}

	# ARM64 and Windows 10: run COM unpin in a background STA runspace with timeout
	if ($NeedsDeferredUnpin -and $DeferredUnpinNames.Count -gt 0)
	{
		Invoke-ARM64ShellUnpin -AppNames $DeferredUnpinNames.ToArray() -TimeoutSeconds 15
	}

	# Restart Explorer to apply taskbar changes
	try
	{
		Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 500
		Start-Process "explorer.exe" -ErrorAction SilentlyContinue
	}
	catch
	{
		LogWarning "Failed to restart Explorer after taskbar unpin: $($_.Exception.Message)"
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

<#
	.SYNOPSIS
	End task in taskbar by right click

	.PARAMETER Enable
	Enable end task in taskbar by right click

	.PARAMETER Disable
	Disable end task in taskbar by right click (default value)

	.EXAMPLE
	TaskbarEndTask -Enable

	.EXAMPLE
	TaskbarEndTask -Disable

	.NOTES
	Current user
#>
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
				if (Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Name TaskbarEndTask -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name "TaskbarEndTask"
				}
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

Export-ModuleMember -Function '*'
