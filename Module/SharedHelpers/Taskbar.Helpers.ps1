# Shared helper slice for Baseline -- taskbar pin/unpin and News & Interests helpers.

function Initialize-NewsInterestsTaskbarHashInterop
{
	<# .SYNOPSIS Loads the WinAPI.NewsInterestsTaskbarHash P/Invoke type definition. #>
	if ("WinAPI.NewsInterestsTaskbarHash" -as [type])
	{
		return
	}

	$signatureDefinition = @{
		Namespace = "WinAPI"
		Name = "NewsInterestsTaskbarHash"
		Language = "CSharp"
		MemberDefinition = @"
[DllImport("Shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = false)]
public static extern int HashData(byte[] pbData, int cbData, byte[] piet, int outputLen);
"@
	}

	Add-Type @signatureDefinition -ErrorAction Stop | Out-Null
}

function Get-NewsInterestsTaskbarHashValue
{
	<# .SYNOPSIS Computes the News and Interests taskbar hash via Shlwapi.dll. #>
	param (
		[Parameter(Mandatory = $true)]
		[string]$MachineId,

		[Parameter(Mandatory = $true)]
		[ValidateSet(0, 2)]
		[int]$ViewMode
	)

	if ([string]::IsNullOrWhiteSpace($MachineId))
	{
		throw "MachineId is required to calculate the News and Interests taskbar hash."
	}

	Initialize-NewsInterestsTaskbarHashInterop

	$combined = "{0}_{1}" -f $MachineId, $ViewMode
	$charArray = $combined.ToCharArray()
	[array]::Reverse($charArray)
	$reversedCombined = -join $charArray
	$bytesIn = [System.Text.Encoding]::Unicode.GetBytes($reversedCombined)
	$bytesOut = [byte[]]::new(4)
	[void][WinAPI.NewsInterestsTaskbarHash]::HashData($bytesIn, 0x53, $bytesOut, $bytesOut.Count)

	return [System.BitConverter]::ToUInt32($bytesOut, 0)
}

function Set-UCPDBypassedRegistryDWordValue
{
	<# .SYNOPSIS Sets a registry DWord value via a UCPD-bypassed PowerShell process. #>
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[int]$Value
	)

	$escapedPath = $Path -replace "'", "''"
	$escapedName = $Name -replace "'", "''"
	$scriptText = @"
if (-not (Test-Path -LiteralPath '$escapedPath'))
{
	New-Item -Path '$escapedPath' -Force -ErrorAction Stop | Out-Null
}

New-ItemProperty -Path '$escapedPath' -Name '$escapedName' -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
"@

	Invoke-UCPDBypassed -ScriptBlock ([scriptblock]::Create($scriptText))
	return $true
}

function Set-NewsInterestsTaskbarViewMode
{
	<# .SYNOPSIS Sets the News and Interests taskbar view mode with UCPD fallback. #>
	param (
		[Parameter(Mandatory = $true)]
		[string]$MachineId,

		[Parameter(Mandatory = $true)]
		[ValidateSet(0, 2)]
		[int]$ViewMode
	)

	$feedsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
	$dwordData = Get-NewsInterestsTaskbarHashValue -MachineId $MachineId -ViewMode $ViewMode
	$accessDeniedFallback = {
		param ($Path, $Name, $Value, $Type)

		if ($Type -ne 'DWord')
		{
			return $false
		}

		return (Set-UCPDBypassedRegistryDWordValue -Path $Path -Name $Name -Value ([int]$Value))
	}

	Set-RegistryValueSafe -Path $feedsPath -Name "ShellFeedsTaskbarViewMode" -Type DWord -Value $ViewMode -AccessDeniedFallback $accessDeniedFallback | Out-Null
	Set-RegistryValueSafe -Path $feedsPath -Name "EnShellFeedsTaskbarViewMode" -Type DWord -Value $dwordData -AccessDeniedFallback $accessDeniedFallback | Out-Null
}

function Get-TaskbarPinnedItems
{
	<# .SYNOPSIS Returns the Shell.Application enumerable list of pinned taskbar items. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$PinnedPath
	)

	if (-not (Test-Path -Path $PinnedPath))
	{
		return @()
	}

	$shellApplication = $null
	$taskbarShell = $null
	$folderItems = $null
	$pinnedItems = @()
	try
	{
		$shellApplication = New-Object -ComObject Shell.Application
		$taskbarShell = $shellApplication.NameSpace($PinnedPath)
		if ($null -eq $taskbarShell)
		{
			return @()
		}

		$folderItems = $taskbarShell.Items()
		$pinnedItems = @($folderItems)
	}
	finally
	{
		foreach ($comObject in @($folderItems, $taskbarShell, $shellApplication))
		{
			if ($null -ne $comObject -and [System.Runtime.InteropServices.Marshal]::IsComObject($comObject))
			{
				[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($comObject)
			}
		}
	}

	return $pinnedItems
}

function Get-TaskbarPinnedMatches
{
	<# .SYNOPSIS Filters taskbar pinned items by regex patterns. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$PinnedPath,

		[Parameter(Mandatory = $true)]
		[string[]]
		$Patterns
	)

	$NormalizedPatterns = @($Patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
	if ($NormalizedPatterns.Count -eq 0)
	{
		return @()
	}

	return @(Get-TaskbarPinnedItems -PinnedPath $PinnedPath | Where-Object {
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
	<# .SYNOPSIS Unpins a taskbar item via shell verb or fallback removal. #>
	param
	(
		[Parameter(Mandatory = $true)]
		$ShellItem,

		[string]
		$LocalizedString = ([WinAPI.GetStrings]::GetString(5387))
	)

	$verbCandidates = Get-TaskbarUnpinVerbCandidates -LocalizedString $LocalizedString

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

function Get-TaskbarUnpinVerbCandidates
{
	<# .SYNOPSIS Returns localized unpin verb candidates for multiple languages. #>
	param (
		[string]$LocalizedString
	)

	$frenchUnpinVerb = ('D{0}tacher de la barre des t{1}ches' -f [char]0x00E9, [char]0x00E2)

	return @(
		$LocalizedString
		'Unpin from taskbar'
		'Von Taskleiste losen'
		'Desanclar de la barra de tareas'
		'Desepicer da barra de tarefas'
		$frenchUnpinVerb
		'Sgancia dalla barra delle applicazioni'
		'Losmaken van de taakbalk'
		'Odepnij z paska zadan'
		'Unpin from Tasbar'
	) | Where-Object {
		-not [string]::IsNullOrWhiteSpace([string]$_)
	} | Select-Object -Unique
}

function Remove-TaskbarPinnedLink
{
	<# .SYNOPSIS Removes a taskbar pinned shortcut file as a fallback unpin method. #>
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
	<# .SYNOPSIS Unpins a taskbar item with fallback to shortcut file removal. #>
	param
	(
		[Parameter(Mandatory = $true)]
		$ShellItem,

		[string]
		$LocalizedString = ([WinAPI.GetStrings]::GetString(5387))
	)

	if (Invoke-TaskbarUnpin -ShellItem $ShellItem -LocalizedString $LocalizedString)
	{
		return $true
	}

	return (Remove-TaskbarPinnedLink -ShellItem $ShellItem)
}

function Remove-TaskbarPinnedLinksByPattern
{
	<# .SYNOPSIS Removes taskbar pinned shortcuts matching filename patterns. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$PinnedPath,

		[Parameter(Mandatory = $true)]
		[string[]]
		$Patterns
	)

	if (-not (Test-Path -Path $PinnedPath))
	{
		return $false
	}

	$RemovedAny = $false
	$LinkFiles = Get-ChildItem -Path $PinnedPath -Filter '*.lnk' -ErrorAction SilentlyContinue
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
	<# .SYNOPSIS Unpins taskbar items on ARM64 architecture via a background runspace. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string[]]$AppNames,

		[Parameter(Mandatory = $true)]
		[string]$PinnedPath,

		[int]$TimeoutSeconds = 15
	)

	$Runspace = [runspacefactory]::CreateRunspace()
	$Runspace.ApartmentState = 'STA'
	$Runspace.Open()

	$PS = [powershell]::Create()
	$PS.Runspace = $Runspace

	$null = $PS.AddScript({
		param ($Names, $TaskbarPinnedPath)
		$Shell = New-Object -ComObject Shell.Application
		$AppsFolder = $Shell.NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
		$Pinned = $Shell.NameSpace($TaskbarPinnedPath)

		# Hard-coded locale translations for the ARM64 runspace path where the
		# WinAPI.GetStrings P/Invoke type may not be available. The wildcard
		# fallback ($verbName -like '*Unpin*' -or '*taskbar*') in the verb
		# search covers most remaining locales. Add new translations as needed.
		$FrenchUnpinVerb = ('D{0}tacher de la barre des t{1}ches' -f [char]0x00E9, [char]0x00E2)
		$VerbCandidates = @('Unpin from taskbar', 'Von Taskleiste losen', 'Desanclar de la barra de tareas',
			$FrenchUnpinVerb, 'Detacher de la barre des taches', 'Rimuovi dalla barra delle applicazioni')

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
	}).AddArgument($AppNames).AddArgument($PinnedPath)

	$AsyncResult = $PS.BeginInvoke()

	if (-not $AsyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)))
	{
		LogWarning "ARM64 shell unpin timed out after $TimeoutSeconds seconds."
		try { $PS.Stop() } catch {}
	}
	else
	{
		try { $PS.EndInvoke($AsyncResult) } catch {}
	}

	try { $PS.Dispose() } catch {}
	try { $Runspace.Close(); $Runspace.Dispose() } catch {}
}
