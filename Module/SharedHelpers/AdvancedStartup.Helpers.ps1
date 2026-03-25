# Shared helper slice for Win10_11Util.

function Get-AdvancedStartupDesktopDirectory
{
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
	if (Test-Path -LiteralPath $bundledIconPath)
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
		Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/sdmanson8/Win10_11Util/main/files/troubleshoot.ico' `
			-OutFile $downloadedIconPath -UseBasicParsing -ErrorAction Stop
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
	$commandDirectory = Join-Path $env:ProgramData 'Win10_11Util'
	if (-not (Test-Path -LiteralPath $commandDirectory))
	{
		New-Item -Path $commandDirectory -ItemType Directory -Force | Out-Null
	}

	return (Join-Path $commandDirectory 'AdvancedStartup.cmd')
}

function Set-AdvancedStartupCommandFile
{
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
	param(
		[Parameter(Mandatory = $true)]
		[string]$CommandPath
	)

	$launcherScript = @"
`$shell = New-Object -ComObject Shell.Application
`$shell.ShellExecute('$CommandPath', '', '', 'runas', 0)
"@

	$encodedLauncherScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($launcherScript))
	return "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedLauncherScript"
}
