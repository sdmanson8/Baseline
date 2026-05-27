function Get-UIPersonalizationTaskbarPinnedItems
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

	<#
	    .SYNOPSIS
	    Gets taskbar pinned matches.

		#>

	function Get-UIPersonalizationTaskbarPinnedMatches
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

		return @(Get-UIPersonalizationTaskbarPinnedItems | Where-Object {
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

	<#
	    .SYNOPSIS
	    Runs taskbar unpin.

		#>

	function Invoke-UIPersonalizationTaskbarUnpin
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

	<#
	    .SYNOPSIS
	    Removes taskbar pinned link.

		#>

	function Remove-UIPersonalizationTaskbarPinnedLink
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

	<#
	    .SYNOPSIS
	    Runs taskbar unpin with fallback.

		#>

	function Invoke-UIPersonalizationTaskbarUnpinWithFallback
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		if (Invoke-UIPersonalizationTaskbarUnpin -ShellItem $ShellItem)
		{
			return $true
		}

		return (Remove-UIPersonalizationTaskbarPinnedLink -ShellItem $ShellItem)
	}

	<#
	    .SYNOPSIS
	    Removes taskbar pinned links by pattern.

		#>

	function Remove-UIPersonalizationTaskbarPinnedLinksByPattern
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

	<#
	    .SYNOPSIS
	    Runs ARM64 shell unpin.

		#>

	function Invoke-UIPersonalizationARM64ShellUnpin
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
						try { $UnpinVerb.DoIt() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UIPersonalization.Taskbar.Invoke-UIPersonalizationTaskbarShortcutUnpin.DoIt' }
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
			try { $PS.EndInvoke($AsyncResult) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UIPersonalization.Taskbar.Invoke-UIPersonalizationTaskbarShortcutUnpin.EndInvoke' }
		}

		$PS.Dispose()
		$Runspace.Dispose()
	}
