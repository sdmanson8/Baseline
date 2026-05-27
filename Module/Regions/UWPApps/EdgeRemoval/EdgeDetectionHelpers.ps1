function Test-LegacyEdgeInstalled
	{
		$packages = Get-LegacyEdgePackages
		if ($packages)
		{
			foreach ($pkg in $packages)
			{
				$info = & dism /online /Get-PackageInfo /PackageName:$pkg 2>$null
				if ($info -match 'State.*Installed') { return $true }
			}
		}
		return $false
	}
	<#
	    .SYNOPSIS
	    Return whether Chromium-based Edge is installed.

	    .DESCRIPTION
	    Checks the standard Edge folders and a store-program probe to decide whether the Chromium Edge build is still present.

	    .EXAMPLE
	    Test-ChromiumEdgeInstalled
	#>
	function Test-ChromiumEdgeInstalled
	{
		$folders = @('Edge', 'EdgeCore', 'EdgeUpdate')
		$programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
		foreach ($pf in $programFiles)
		{
			foreach ($f in $folders)
			{
				if (Test-Path "$pf\Microsoft\$f") { return $true }
			}
		}
		try
		{
			$app = Get-WmiObject -Class Win32_InstalledStoreProgram -Filter "Name like '%Microsoft.MicrosoftEdge.Stable%'" -ErrorAction SilentlyContinue
			return $app -ne $null
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EdgeDetectionHelpers.Test-ChromiumEdgeInstalled:catch40' -Severity Debug }

			return $false
		}
	}
	<#
	    .SYNOPSIS
	    Back up selected UserChoice file associations before Edge removal.

	    .DESCRIPTION
	    Captures ProgId and Hash values for the HTML, HTM, XML, and PDF UserChoice associations so non-Edge defaults can be restored later.

	    .EXAMPLE
	    Backup-UserChoiceAssociations
	#>
	function Backup-UserChoiceAssociations
	{
		Write-EdgeRemovalLog 'Backing up HKCU UserChoice ProgId/Hash for .html/.htm/.xml/.pdf'
		$backup = @{}
		$exts = @('.html', '.htm', '.xml', '.pdf')
		foreach ($ext in $exts)
		{
			$keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
			if (Test-Path $keyPath)
			{
				try
				{
					$props = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue
					if ($props -and $props.ProgId)
					{
						$backup[$ext] = @{ ProgId = $props.ProgId; Hash = $props.Hash }
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'EdgeDetectionHelpers.Backup-UserChoiceAssociations:catch73' -Severity Debug }

					# Best-effort backup
				}
			}
		}
		Write-EdgeRemovalLog "Captured UserChoice for $($backup.Count) extension(s)"
		return $backup
	}
	<#
	    .SYNOPSIS
	    Restore saved UserChoice file associations after Edge removal.

	    .DESCRIPTION
	    Replays the saved non-Edge ProgId values for the backed-up UserChoice extensions when a backup payload is available.

	    .PARAMETER Backup
	    Hashtable returned by Backup-UserChoiceAssociations.

	    .EXAMPLE
	    Restore-UserChoiceAssociations -Backup $backup
	#>
	function Restore-UserChoiceAssociations
	{
		param($Backup)
		if (-not $Backup -or $Backup.Count -eq 0) { return }
		foreach ($ext in $Backup.Keys)
		{
			$entry = $Backup[$ext]
			if (-not $entry.ProgId -or $entry.ProgId -eq 'MSEdgeHTM') { continue }
			$keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice"
			if (Test-Path $keyPath)
			{
				try
				{
					Set-ItemProperty -Path $keyPath -Name ProgId -Value $entry.ProgId -Force -ErrorAction SilentlyContinue
					Write-EdgeRemovalLog "Restored UserChoice for $ext -> $($entry.ProgId)"
				}
				catch
				{
					Write-EdgeRemovalLog "Failed to restore UserChoice for $ext"
				}
			}
		}
	}
	<#
	    .SYNOPSIS
	    Stop running Edge-related processes.

	    .DESCRIPTION
	    Stops the updater, browser, widgets, resume, and related Edge processes so uninstall and cleanup operations can proceed.

	    .EXAMPLE
	    Stop-EdgeProcesses
	#>
	function Stop-EdgeProcesses
	{
		Write-EdgeRemovalLog 'Stopping Edge-related processes'
		$names = @('MicrosoftEdgeUpdate', 'OneDrive', 'WidgetService', 'Widgets', 'msedge', 'Resume', 'CrossDeviceResume', 'msedgewebview2')
		foreach ($n in $names)
		{
			$count = (Get-Process -Name $n -ErrorAction SilentlyContinue).Count
			if ($count -gt 0)
			{
				Stop-Process -Name $n -Force -ErrorAction SilentlyContinue
				Write-EdgeRemovalLog "Stopped $count instance(s) of $n"
			}
		}
	}
	<#
	    .SYNOPSIS
	    Remove the legacy UWP Edge package.

	    .DESCRIPTION
	    Makes the legacy Edge package visible in CBS, removes ownership blockers, and calls DISM to uninstall the package.

	    .EXAMPLE
	    Remove-LegacyEdge
	#>
	function Remove-LegacyEdge
	{
		Write-EdgeRemovalLog 'Starting Legacy Edge/UWP Edge removal'
		$packages = Get-LegacyEdgePackages
		$first = $packages | Select-Object -First 1
		if (-not $first)
		{
			Write-EdgeRemovalLog 'No Legacy Edge packages found in CBS registry'
			return
		}
		$pkgPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\$first"
		Set-ItemProperty -Path $pkgPath -Name 'Visibility' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
		$ownersPath = "$pkgPath\Owners"
		if (Test-Path $ownersPath)
		{
			Remove-Item -Path $ownersPath -Recurse -Force -ErrorAction SilentlyContinue
		}
		Write-EdgeRemovalLog 'Removing Legacy Edge package via DISM (30s timeout)'
		try
		{
			$null = Invoke-BaselineProcess -FilePath 'dism.exe' -ArgumentList @('/online', '/Remove-Package', "/PackageName:$first") -TimeoutSeconds 30
			Write-EdgeRemovalLog 'DISM completed successfully'
		}
		catch
		{
			Write-EdgeRemovalLog "DISM failed or timed out: $($_.Exception.Message). Retrying once."
			Start-Sleep -Seconds 2
			try
			{
				$null = Invoke-BaselineProcess -FilePath 'dism.exe' -ArgumentList @('/online', '/Remove-Package', "/PackageName:$first") -TimeoutSeconds 30
				Write-EdgeRemovalLog 'DISM retry completed successfully'
			}
			catch
			{
				Write-EdgeRemovalLog "DISM retry failed or timed out; continuing with Appx cleanup: $($_.Exception.Message)"
			}
		}
		Write-EdgeRemovalLog 'Removing Legacy UWP Edge AppxPackage'
		Get-AppxPackage -AllUsers Microsoft.MicrosoftEdge | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
		Write-EdgeRemovalLog 'Legacy Edge/UWP Edge removal completed'
	}
	<#
	    .SYNOPSIS
	    Remove Edge shortcuts from user and common locations.

	    .DESCRIPTION
	    Deletes known Microsoft Edge shortcut files from user profiles, Quick Launch, taskbar pins, and shared Start Menu locations.

	    .EXAMPLE
	    Remove-EdgeShortcuts
	#>
	function Remove-EdgeShortcuts
	{
		Write-EdgeRemovalLog 'Starting Edge shortcut cleanup'
		$userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
			Where-Object { Test-Path "$($_.FullName)\NTUSER.DAT" }
		$paths = @()
		foreach ($p in $userProfiles)
		{
			$paths += @(
				"$($p.FullName)\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk",
				"$($p.FullName)\Desktop\Microsoft Edge.lnk",
				"$($p.FullName)\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk",
				"$($p.FullName)\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Tombstones\Microsoft Edge.lnk",
				"$($p.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
			)
		}
		$paths += 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'
		$count = 0
		foreach ($shortcut in $paths)
		{
			if (Test-Path -Path $shortcut -PathType Leaf)
			{
				Remove-Item -Path $shortcut -Force -ErrorAction SilentlyContinue
				$count++
			}
		}
		Write-EdgeRemovalLog "Removed $count Edge shortcut(s)"
	}
	<#
	    .SYNOPSIS
	    Install the Edge protocol redirect helper.

	    .DESCRIPTION
	    Creates the OpenWebSearch redirect assets Baseline uses to intercept Edge-targeted URL launches after browser removal.

	    .EXAMPLE
	    Install-EdgeProtocolRedirect
	#>
	function Install-EdgeProtocolRedirect
	{
		Write-EdgeRemovalLog 'Installing Edge protocol redirect via OpenWebSearch'
		New-Item -ItemType Directory -Path $scriptsDir -Force -ErrorAction SilentlyContinue | Out-Null

		$stubTarget = Join-Path $scriptsDir 'ie_to_edge_stub.exe'
		if (-not (Test-Path $stubTarget))
		{
			Write-EdgeRemovalLog "Warning: ie_to_edge_stub.exe not found at $stubTarget; skipping redirect install"
			return
		}

		$openWebSearchPath = Join-Path $scriptsDir 'OpenWebSearch.cmd'
		$openWebSearchContent = @'
@title OpenWebSearch 2023 & echo off
for /f %%E in ('"prompt $E$S& for %%e in (1) do rem"') do echo;%%E[2t 2>nul

call :reg_var "HKCU\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoiceLatest\ProgId" ProgID ProgID
if not defined ProgID call :reg_var "HKCU\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" ProgID ProgID
if /i "%ProgID%" neq "MSEdgeHTM" if defined ProgID goto :browser_found
for %%P in ("%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe") do if exist %%P (set "Choice=%%~P"& goto :skip_browser)
set "Choice="
for %%R in (HKCU HKLM) do (
    for /f "delims=" %%K in ('reg query "%%R\SOFTWARE\Clients\StartMenuInternet" 2^>nul') do (
        for /f "skip=1 tokens=2*" %%A in ('reg query "%%K\shell\open\command" /ve 2^>nul') do (
            echo "%%B" | findstr /i "msedge ie_to_edge_stub iexplore" >nul || (set "Choice=%%~B" & goto :skip_browser)
        )
    )
)
if not defined Choice exit /b
:browser_found
call :reg_var "HKCR\%ProgID%\shell\open\command" "" Browser
set Choice=& for %%. in (%Browser%) do if not defined Choice set "Choice=%%~."
:skip_browser

set "URI=" & set "URL=" & set "NOOP="

set "CLI=%CMDCMDLINE:"=``%"
if defined CLI set "CLI=%CLI:*ie_to_edge_stub.exe`` =%"
if defined CLI set "CLI=%CLI:*ie_to_edge_stub.exe =%"
if defined CLI set "CLI=%CLI:*msedge.exe`` =%"
if defined CLI set "CLI=%CLI:*msedge.exe =%"
set "FIX=%CLI:~-1%"
if defined CLI if "%FIX%"==" " set "CLI=%CLI:~0,-1%"
if defined CLI set "RED=%CLI:microsoft-edge=%"
if defined CLI set "URL=%CLI:http=%"
if "%CLI%" equ "%RED%" (set NOOP=1) else if "%CLI%" equ "%URL%" (set NOOP=1)
if defined NOOP exit /b

set "URL=%CLI:*microsoft-edge=%"
set "URL=http%URL:*http=%"
set "FIX=%URL:~-2%"
if defined URL if "%FIX%"=="``" set "URL=%URL:~0,-2%"
call :dec_url
start "" "%Choice%" "%URL%"
exit

:reg_var
set {var}=& set {reg}=reg query "%~1" /v %2 /z /se "," /f /e& if %2=="" set {reg}=reg query "%~1" /ve /z /se "," /f /e
for /f "skip=2 tokens=* delims=" %%V in ('%{reg}% %4 %5 %6 %7 %8 %9 2^>nul') do if not defined {var} set "{var}=%%V"
if not defined {var} (set {reg}=& set "%~3="& exit /b) else if %2=="" set "{var}=%{var}:*)    =%"
if not defined {var} (set {reg}=& set "%~3="& exit /b) else set {reg}=& set "%~3=%{var}:*)    =%"& set {var}=& exit /b

:dec_url
set ".=%URL:!=}%" & setlocal enabledelayedexpansion
set ".=!.:%%={!" &set ".=!.:{3A=:!" &set ".=!.:{2F=/!" &set ".=!.:{3F=?!" &set ".=!.:{23=#!" &set ".=!.:{5B=[!" &set ".=!.:{5D=]!"
set ".=!.:{40=@!"&set ".=!.:{21=}!" &set ".=!.:{24=$!" &set ".=!.:{26=&!" &set ".=!.:{27='!" &set ".=!.:{28=(!" &set ".=!.:{29=)!"
set ".=!.:{2A=*!"&set ".=!.:{2B=+!" &set ".=!.:{2C=,!" &set ".=!.:{3B=;!" &set ".=!.:{3D==!" &set ".=!.:{25=%%!"&set ".=!.:{20= !"
set ".=!.:{=%%!" & endlocal& set "URL=%.:}=!%" & exit /b
'@

		$openWebSearchContent | Out-File -FilePath $openWebSearchPath -Encoding ASCII -Force
		Write-EdgeRemovalLog "Created OpenWebSearch.cmd at $openWebSearchPath"

		$buildNumber = [Environment]::OSVersion.Version.Build
		$conhostFlags = if ($buildNumber -gt 25179) { '--width 1 --height 1' } else { '--headless' }
		$conhostDebugger = "$env:SystemRoot\system32\conhost.exe $conhostFlags $openWebSearchPath"

		Write-EdgeRemovalLog 'Configuring registry entries for Edge protocol redirect'
		reg.exe add 'HKCR\microsoft-edge' /f /ve /d 'URL:microsoft-edge' 2>&1 | Out-Null
		reg.exe add 'HKCR\microsoft-edge' /f /v 'URL Protocol' /d '' 2>&1 | Out-Null
		reg.exe add 'HKCR\microsoft-edge' /f /v 'NoOpenWith' /d '' 2>&1 | Out-Null
		reg.exe add 'HKCR\microsoft-edge\shell\open\command' /f /ve /d "$stubTarget %1" 2>&1 | Out-Null
		reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ie_to_edge_stub.exe' /f /v UseFilter /d 1 /t reg_dword 2>&1 | Out-Null
		reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ie_to_edge_stub.exe\0' /f /v FilterFullPath /d "$stubTarget" 2>&1 | Out-Null
		reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ie_to_edge_stub.exe\0' /f /v Debugger /d "$conhostDebugger" 2>&1 | Out-Null
		reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe' /f 2>&1 | Out-Null
		Write-EdgeRemovalLog 'Registry configuration completed'

		$repairTemplate = @'
# OpenWebSearch Repair - re-sets protocol handler and MSEdgeHTM registry if Edge overwrites them
$stubPath = "{0}"
$owsPath = "{1}"
if (-not (Test-Path $stubPath)) {{ exit }}
if (-not (Test-Path $owsPath)) {{ exit }}
$cmd = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\microsoft-edge\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
if ($cmd -and $cmd -notlike "*ie_to_edge_stub*") {{
    reg.exe add "HKCR\microsoft-edge\shell\open\command" /f /ve /d "$stubPath %1" 2>&1 | Out-Null
}}
$htm = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\MSEdgeHTM\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
if ($htm -and $htm -notlike "*ie_to_edge_stub*") {{
    reg.exe add "HKCR\MSEdgeHTM\shell\open\command" /f /ve /d "`"$stubPath`" %1" 2>&1 | Out-Null
}}
'@
		$repairContent = $repairTemplate -f $stubTarget, $openWebSearchPath
		$repairScriptPath = Join-Path $scriptsDir 'OpenWebSearchRepair.ps1'
		$repairContent | Out-File -FilePath $repairScriptPath -Encoding UTF8 -Force
		Write-EdgeRemovalLog "Created OpenWebSearchRepair.ps1 at $repairScriptPath"

		try
		{
			$repairAction    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-ExecutionPolicy Bypass -NoProfile -File "{0}"' -f $repairScriptPath)
			$repairTrigger   = New-ScheduledTaskTrigger -AtLogon
			$repairSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
			$repairPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
			Register-ScheduledTask -TaskName 'OpenWebSearchRepair' -TaskPath '\Baseline\' -Action $repairAction -Trigger $repairTrigger -Settings $repairSettings -Principal $repairPrincipal -Force | Out-Null
			Write-EdgeRemovalLog 'Registered OpenWebSearchRepair scheduled task (runs at logon)'
		}
		catch
		{
			Write-EdgeRemovalLog "Failed to register OpenWebSearchRepair task: $($_.Exception.Message)"
		}
	}
