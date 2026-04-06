# Shared helper slice for Baseline -- Advanced Startup shortcut and recovery environment helpers.

function Get-AdvancedStartupDesktopDirectory
{
	<# .SYNOPSIS Returns the current user's Desktop folder path. #>
	try
	{
		return [Environment]::GetFolderPath('Desktop')
	}
	catch
	{
		return (Join-Path $env:USERPROFILE 'Desktop')
	}
}

function Get-AdvancedStartupDownloadsDirectory
{
	<# .SYNOPSIS Returns the Downloads folder path via Shell API or fallback. #>
	try
	{
		$downloadsFolder = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads')
		if ($downloadsFolder -and $downloadsFolder.Self -and -not [string]::IsNullOrWhiteSpace($downloadsFolder.Self.Path))
		{
			return $downloadsFolder.Self.Path
		}

		return (Join-Path $HOME 'Downloads')
	}
	catch
	{
		return (Join-Path $HOME 'Downloads')
	}
}

function Get-AdvancedStartupAssetPath
{
	<# .SYNOPSIS Searches for an asset file in files/, Assets/, or repo root directories. #>
	param(
		[Parameter(Mandatory = $true)]
		[string]$FileName
	)

	$repoRoot = $Script:SharedHelpersRepoRoot
	$candidatePaths = @(
		[System.IO.Path]::GetFullPath((Join-Path $repoRoot "files\$FileName")),
		[System.IO.Path]::GetFullPath((Join-Path $repoRoot "Assets\$FileName")),
		[System.IO.Path]::GetFullPath((Join-Path $repoRoot $FileName))
	)

	foreach ($candidatePath in $candidatePaths | Select-Object -Unique)
	{
		if (Test-Path -LiteralPath $candidatePath)
		{
			return $candidatePath
		}
	}

	return $null
}

function Get-AdvancedStartupIconLocation
{
	<# .SYNOPSIS Locates or downloads troubleshoot.ico with fallback to a system icon. #>
	param(
		[Parameter(Mandatory = $true)]
		[string]$DownloadsPath
	)

	$localIconPath = "$env:WINDIR\troubleshoot.ico"
	if (Test-Path -LiteralPath $localIconPath)
	{
		return "$localIconPath, 0"
	}

	$bundledIconPath = Get-AdvancedStartupAssetPath -FileName 'troubleshoot.ico'
	if ($bundledIconPath -and (Test-Path -LiteralPath $bundledIconPath))
	{
		try
		{
			Copy-Item -Path $bundledIconPath -Destination $localIconPath -Force -ErrorAction Stop
			LogInfo 'Copied bundled Advanced Startup shortcut icon'
			return "$localIconPath, 0"
		}
		catch
		{
			LogWarning "Failed to copy bundled Advanced Startup shortcut icon: $_"
		}
	}

	try
	{
		$downloadedIconPath = Join-Path $DownloadsPath 'troubleshoot.ico'
		Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/sdmanson8/Baseline/main/files/troubleshoot.ico' `
			-OutFile $downloadedIconPath -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
		if ((Get-Item -LiteralPath $downloadedIconPath).Length -gt 1MB)
		{
			Remove-Item -LiteralPath $downloadedIconPath -Force -ErrorAction SilentlyContinue
			throw "Downloaded icon file exceeds 1 MB safety limit"
		}
		Move-Item -Path $downloadedIconPath -Destination $localIconPath -Force -ErrorAction Stop
		LogInfo 'Downloaded Advanced Startup shortcut icon'
		return "$localIconPath, 0"
	}
	catch
	{
		LogInfo 'Using built-in system icon for Advanced Startup shortcut'
		return "$env:WINDIR\System32\shell32.dll,27"
	}
}

function Enable-AdvancedStartupWindowsRecoveryEnvironment
{
	<# .SYNOPSIS Enables Windows Recovery Environment via reagentc.exe. #>
	try
	{
		& reagentc.exe /enable *> $null
		if ($LASTEXITCODE -eq 0)
		{
			LogInfo 'Ensured Windows Recovery Environment is enabled'
			return $true
		}

		LogWarning "reagentc.exe /enable returned exit code $LASTEXITCODE"
	}
	catch
	{
		LogWarning "Failed to enable Windows Recovery Environment: $_"
	}

	return $false
}

function Get-AdvancedStartupCommandPath
{
	<# .SYNOPSIS Returns the ACL-restricted path for AdvancedStartup.cmd. #>
	$commandDirectory = Join-Path $env:ProgramData 'Baseline'
	if (-not (Test-Path -LiteralPath $commandDirectory))
	{
		$dir = New-Item -Path $commandDirectory -ItemType Directory -Force
		# Restrict ACLs so non-admin users cannot modify the .cmd that runs elevated.
		try
		{
			$acl = $dir.GetAccessControl()
			$acl.SetAccessRuleProtection($true, $false)
			$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
				'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
			$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
				'NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
			$acl.AddAccessRule($adminRule)
			$acl.AddAccessRule($systemRule)
			$dir.SetAccessControl($acl)
		}
		catch
		{
			LogWarning "Could not restrict ACLs on $commandDirectory`: $($_.Exception.Message)"
		}
	}

	return (Join-Path $commandDirectory 'AdvancedStartup.cmd')
}

function Set-AdvancedStartupCommandFile
{
	<# .SYNOPSIS Creates the AdvancedStartup.cmd file with recovery boot commands. #>
	$commandPath = Get-AdvancedStartupCommandPath
	$commandContent = @"
@echo off
"$env:WINDIR\System32\reagentc.exe" /boottore
"$env:WINDIR\System32\shutdown.exe" /r /f /t 00
"@

	Set-Content -Path $commandPath -Value $commandContent -Encoding ASCII -Force
	LogInfo "Created Advanced Startup command file at $commandPath"
	return $commandPath
}

function Get-AdvancedStartupShortcutArguments
{
	<# .SYNOPSIS Generates Base64-encoded PowerShell arguments for an elevated recovery shortcut. #>
	param(
		[Parameter(Mandatory = $true)]
		[string]$CommandPath
	)

	$safeCommandPath = $CommandPath.Replace("'", "''")
	$launcherScript = @"
`$shell = New-Object -ComObject Shell.Application
`$shell.ShellExecute('$safeCommandPath', '', '', 'runas', 0)
"@

	$encodedLauncherScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($launcherScript))
	return "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedLauncherScript"
}
