function Remove-ChromiumEdge
	{
		Write-EdgeRemovalLog 'Starting Edge Chromium uninstall'
		$edgePath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
		New-Item -Path $edgePath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
		New-Item -Path $edgePath -ItemType File -Name 'MicrosoftEdge.exe' -ErrorAction SilentlyContinue | Out-Null

		Write-EdgeRemovalLog 'Searching registry for Edge uninstall strings'
		$uninstallKeys = Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue
		$edgeUninstallCount = 0
		foreach ($key in $uninstallKeys)
		{
			$displayName = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).DisplayName
			if ($displayName -like '*Microsoft Edge*')
			{
				$uninstallString = (Get-ItemProperty $key.PSPath).UninstallString
				if ($uninstallString)
				{
					$edgeUninstallCount++
					Stop-EdgeProcesses
					if ($uninstallString -like '*msiexec*')
					{
						Write-EdgeRemovalLog 'Executing MSI uninstaller for Edge'
						$null = Invoke-BaselineProcess -FilePath 'cmd.exe' -ArgumentList @('/c', "$uninstallString /quiet") -TimeoutSeconds 900
					}
					else
					{
						Write-EdgeRemovalLog 'Executing standard uninstaller for Edge'
						$null = Invoke-BaselineProcess -FilePath 'cmd.exe' -ArgumentList @('/c', "$uninstallString --force-uninstall --silent") -TimeoutSeconds 900
					}
				}
			}
		}
		if ($edgeUninstallCount -eq 0)
		{
			Write-EdgeRemovalLog 'No Edge uninstall entries found in registry'
		}
		else
		{
			Write-EdgeRemovalLog "Executed $edgeUninstallCount Edge uninstaller(s)"
		}

		Write-EdgeRemovalLog 'Removing UWP Edge Chromium AppxPackage'
		Get-AppxPackage -AllUsers Microsoft.MicrosoftEdge.Stable | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null

		Write-EdgeRemovalLog 'Cleaning up temporary Edge directory'
		Remove-Item -Recurse -Force $edgePath -ErrorAction SilentlyContinue | Out-Null
		Write-EdgeRemovalLog 'Edge Chromium uninstall completed'

		Write-EdgeRemovalLog 'Starting EdgeUpdate removal'
		$edgeupdate = @()
		$searchPaths = @('LocalApplicationData', 'ProgramFilesX86', 'ProgramFiles')
		foreach ($pathType in $searchPaths)
		{
			$folder = [Environment]::GetFolderPath($pathType)
			$pattern = "$folder\Microsoft\EdgeUpdate\*.*.*.*\MicrosoftEdgeUpdate.exe"
			$found = Get-ChildItem $pattern -Recurse -ErrorAction SilentlyContinue
			if ($found) { $edgeupdate += $found.FullName }
		}
		if ($edgeupdate.Count -gt 0)
		{
			Write-EdgeRemovalLog "Found $($edgeupdate.Count) EdgeUpdate executable(s)"
		}
		else
		{
			Write-EdgeRemovalLog 'No EdgeUpdate executables found'
		}

		# Backup ClientState -- required for EdgeWebView2 to keep working post-removal
		$backupRegFile = Join-Path $env:TEMP ("EdgeUpdate_ClientState_Backup_{0}.reg" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
		$clientStatePath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState'
		if (Test-Path $clientStatePath)
		{
			Write-EdgeRemovalLog 'Backing up EdgeUpdate ClientState (preserves EdgeWebView2)'
			$null = Invoke-BaselineProcess -FilePath 'reg.exe' -ArgumentList @('export', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState', $backupRegFile, '/y') -TimeoutSeconds 120
			if (Test-Path $backupRegFile)
			{
				Write-EdgeRemovalLog "Created registry backup at $backupRegFile"
			}
			else
			{
				Write-EdgeRemovalLog 'Warning: failed to create ClientState registry backup'
			}
		}
		else
		{
			Write-EdgeRemovalLog 'No EdgeUpdate ClientState registry found to backup'
		}

		foreach ($exePath in $edgeupdate)
		{
			if (Test-Path $exePath)
			{
				Write-EdgeRemovalLog "Unregistering EdgeUpdate service from $exePath"
				$null = Invoke-BaselineProcess -FilePath $exePath -ArgumentList @('/unregsvc') -TimeoutSeconds 300
				$waitCount = 0
				do
				{
					Start-Sleep -Seconds 3
					$running = Get-Process -Name 'setup', 'MicrosoftEdge*' -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Microsoft\Edge*' }
				}
				while ($running -and $waitCount++ -lt 20)
				if (Test-Path $exePath)
				{
					Write-EdgeRemovalLog "Running EdgeUpdate uninstaller from $exePath"
					$null = Invoke-BaselineProcess -FilePath $exePath -ArgumentList @('/uninstall') -TimeoutSeconds 900
				}
			}
		}

		if (Test-Path $backupRegFile)
		{
			Write-EdgeRemovalLog 'Restoring EdgeUpdate ClientState (re-arms EdgeWebView2)'
			$null = Invoke-BaselineProcess -FilePath 'reg.exe' -ArgumentList @('import', $backupRegFile) -TimeoutSeconds 120
			Remove-Item $backupRegFile -ErrorAction SilentlyContinue
		}
		else
		{
			Write-EdgeRemovalLog 'No registry backup file found to restore'
		}
		Write-EdgeRemovalLog 'EdgeUpdate removal completed'
	}
	<#
	    .SYNOPSIS
	    Remove Edge registry keys and registration leftovers.

	    .DESCRIPTION
	    Deletes direct Edge registry keys and selected registration values that remain after Edge removal.

	    .EXAMPLE
	    Remove-EdgeRegistryKeys
	#>
	function Remove-EdgeRegistryKeys
	{
		Write-EdgeRemovalLog 'Starting Edge registry cleanup'
		$directPaths = @(
			'HKLM:\SOFTWARE\Microsoft\Edge',
			'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge',
			'HKCU:\Software\Microsoft\Edge',
			'HKCU:\Software\Microsoft\EdgeUpdate',
			'HKLM:\SOFTWARE\Clients\StartMenuInternet\Microsoft Edge',
			'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
			'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MicrosoftEdge',
			'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge',
			'HKLM:\SYSTEM\CurrentControlSet\Services\Eventlog\Application\Edge',
			'HKLM:\SYSTEM\CurrentControlSet\Services\Eventlog\Application\edgeupdate',
			'HKLM:\SYSTEM\CurrentControlSet\Services\Eventlog\Application\edgeupdatem'
		)
		$removed = 0
		foreach ($p in $directPaths)
		{
			if (Test-Path $p)
			{
				Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
				$removed++
			}
		}
		Write-EdgeRemovalLog "Removed $removed direct registry key(s)"

		$valuesToRemove = @(
			@{ Path = 'HKLM:\SOFTWARE\RegisteredApplications'; Name = 'Microsoft Edge' },
			@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppLaunch'; Name = 'MSEdge' },
			@{ Path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'; Name = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
		)
		$removedValues = 0
		foreach ($item in $valuesToRemove)
		{
			if ((Test-Path $item.Path) -and (Get-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue))
			{
				Remove-ItemProperty -Path $item.Path -Name $item.Name -Force -ErrorAction SilentlyContinue
				$removedValues++
			}
		}
		Write-EdgeRemovalLog "Removed $removedValues registry value(s)"

		$patterns = @(
			@{ Root = 'HKLM:\SOFTWARE\Classes'; Pattern = 'MicrosoftEdgeUpdate*' },
			@{ Root = 'HKLM:\SOFTWARE\Classes'; Pattern = 'MSEdge*' },
			@{ Root = 'HKLM:\SOFTWARE\Classes\WOW6432Node'; Pattern = 'MicrosoftEdgeUpdate*' },
			@{ Root = 'HKLM:\SOFTWARE\WOW6432Node\Classes'; Pattern = 'MicrosoftEdgeUpdate*' }
		)
		$removedPattern = 0
		foreach ($pi in $patterns)
		{
			if (Test-Path $pi.Root)
			{
				$matched = Get-ChildItem -Path $pi.Root -ErrorAction SilentlyContinue |
					Where-Object { $_.PSChildName -like $pi.Pattern }
				foreach ($key in $matched)
				{
					Remove-Item $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
					$removedPattern++
				}
			}
		}
		Write-EdgeRemovalLog "Removed $removedPattern pattern-matched key(s)"

		$muiCachePath = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
		if (Test-Path $muiCachePath)
		{
			$properties = Get-ItemProperty -Path $muiCachePath -ErrorAction SilentlyContinue
			$removedMui = 0
			if ($properties)
			{
				foreach ($prop in $properties.PSObject.Properties)
				{
					if ($prop.Name -like '*Edge*' -or $prop.Name -like '*EdgeUpdate*')
					{
						Remove-ItemProperty -Path $muiCachePath -Name $prop.Name -Force -ErrorAction SilentlyContinue
						$removedMui++
					}
				}
			}
			Write-EdgeRemovalLog "Removed $removedMui MuiCache entry(ies)"
		}
	}
	<#
	    .SYNOPSIS
	    Remove leftover Edge folders while preserving WebView2.

	    .DESCRIPTION
	    Deletes the extra system and per-user Edge folders Baseline cleans after browser removal without touching EdgeWebView2.

	    .EXAMPLE
	    Remove-AdditionalEdgeFolders
	#>
	function Remove-AdditionalEdgeFolders
	{
		Write-EdgeRemovalLog 'Starting additional Edge folder cleanup (preserves EdgeWebView2)'
		$systemPaths = @(
			'C:\ProgramData\Microsoft\EdgeUpdate',
			'C:\Windows\Temp\MsEdgeCrashpad'
		)
		$removed = 0
		foreach ($p in $systemPaths)
		{
			if (Test-Path $p)
			{
				Write-EdgeRemovalLog "Removing $p"
				Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
				$removed++
			}
		}
		$userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
			Where-Object { Test-Path "$($_.FullName)\NTUSER.DAT" }
		foreach ($p in $userProfiles)
		{
			$edgeLocal = "$($p.FullName)\AppData\Local\Microsoft\Edge"
			if (Test-Path $edgeLocal)
			{
				Write-EdgeRemovalLog "Removing $edgeLocal"
				Remove-Item $edgeLocal -Recurse -Force -ErrorAction SilentlyContinue
				$removed++
			}
		}
		Write-EdgeRemovalLog "Removed $removed additional Edge folder(s)"
	}
