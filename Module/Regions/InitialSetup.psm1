using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Initial Setup

<#
	.SYNOPSIS
	Create a restore point for the system drive before changes are applied.

	.DESCRIPTION
	Ensures System Restore is available on the system drive, temporarily allows
	immediate restore point creation, creates a restore point named for the
	current Windows version, and restores the prior System Restore state.

	.EXAMPLE
	CreateRestorePoint

	.NOTES
	Machine-wide
#>
function CreateRestorePoint
{
	LogInfo "Creating Restore Point"
	Write-Host "Creating System Restore Point - " -NoNewline
	try
	{
		$SystemDriveUniqueID = (Get-Volume | Where-Object -FilterScript {$_.DriveLetter -eq "$($env:SystemDrive[0])"}).UniqueID
		$SystemProtection = ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients" -ErrorAction Ignore)."{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}") | Where-Object -FilterScript {$_ -match [regex]::Escape($SystemDriveUniqueID)}

		$Script:ComputerRestorePoint = $false

		if ($null -eq $SystemProtection)
		{
			$ComputerRestorePoint = $true
			Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
		}

		# Never skip creating a restore point
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null

		$osName = (Get-OSInfo).OSName

		Checkpoint-Computer -Description "WinUtil Script for $osName" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null

		# Revert the System Restore checkpoint creation frequency to 1440 minutes
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 1440 -Force -ErrorAction Stop | Out-Null

		# Turn off System Protection for the system drive if it was turned off before without deleting the existing restore points
		if ($Script:ComputerRestorePoint)
		{
			LogInfo "Disabling System Restore again"
			Disable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop | Out-Null
		}
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to create a restore point: $($_.Exception.Message)"
	}
}
<#
	.SYNOPSIS
	Check whether WinGet is installed and install it if needed.

	.DESCRIPTION
	Validates that WinGet is present and functional. If it is missing or broken,
	the function downloads a bootstrap installer script, executes it, and
	validates the WinGet installation again before continuing.

	.EXAMPLE
	CheckWinGet

	.NOTES
	Machine-wide
#>
function CheckWinGet
{ 
<#
	.SYNOPSIS
	Get the current WinGet version if winget.exe can be resolved and executed.
#>
function Get-WinGetVersion
{
	$WingetPath = Resolve-WinGetExecutable
	if (-not $WingetPath)
	{
		return $null
	}

	try
	{
		$WingetVersion = & $WingetPath --version 2>$null
		if ($LASTEXITCODE -eq 0)
		{
			$ResolvedVersion = [string]($WingetVersion | Select-Object -First 1)
			if (-not [string]::IsNullOrWhiteSpace($ResolvedVersion))
			{
				return $ResolvedVersion.Trim()
			}
		}
	}
	catch
	{
		return $null
	}

	return $null
}  
    # Get OS information for compatibility checks.
    $osInfo = Get-OSInfo
    $osVersion = $osInfo.DisplayVersion
    $currentBuild = $osInfo.CurrentBuild
    $osName = $osInfo.OSName
    
    LogInfo "Detected OS: $osName (Build $currentBuild, Release $osVersion)"
    
    # Check if winget is already installed and working
    $wingetVersion = Get-WinGetVersion
    if ($wingetVersion) {
        Write-ConsoleStatus -Action "Checking WinGet"
        LogInfo "Checking WinGet"
        LogInfo "Winget is already installed and working. Version: $wingetVersion"
        Write-ConsoleStatus -Status success
        return
    }

    LogWarning "Winget not found or not functional"
    
    # If not working, use the asheroto installer script
    Write-ConsoleStatus -Action "Installing WinGet"
    LogInfo "Installing WinGet:"
    
    try {
        # Download the asheroto installer script from direct GitHub URL
        $installerUrl = "https://raw.githubusercontent.com/asheroto/winget-install/master/winget-install.ps1"
        $installerPath = Join-Path $env:TEMP "winget-install.ps1"
        
        LogInfo "Downloading winget installer from $installerUrl"
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        LogInfo "Download completed"
        
        LogInfo "Executing installer script..."
        
        # Create temporary log files to capture output
        $stdoutLog = Join-Path $env:TEMP "winget-install-stdout.log"
        $stderrLog = Join-Path $env:TEMP "winget-install-stderr.log"
        
        # Execute the installer and capture all output
        $process = Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$installerPath`"",
            "-Force"
        ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -ErrorAction Stop
        
        # Read and log the captured output
        if (Test-Path $stdoutLog) {
            Get-Content $stdoutLog | ForEach-Object {
                if ($_) { LogInfo "winget-installer: $_" }
            }
            Remove-Item $stdoutLog -Force -ErrorAction SilentlyContinue
        }
        
        if (Test-Path $stderrLog) {
            Get-Content $stderrLog | ForEach-Object {
                if ($_) { LogError "winget-installer: $_" }
            }
            Remove-Item $stderrLog -Force -ErrorAction SilentlyContinue
        }
        
        # Check process exit code
        $installerCompletedSuccessfully = ($process.ExitCode -eq 0 -or $null -eq $process.ExitCode)
        if ($installerCompletedSuccessfully) {
            LogInfo "Installer script completed successfully"
        } else {
            LogWarning "Installer script reported exit code: $($process.ExitCode)"
        }
        
        # Clean up installer script
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        
        # Final validation
        Start-Sleep -Seconds 5
        $wingetVersion = Get-WinGetVersion
        if ($wingetVersion) {
            LogInfo "Winget validation succeeded. Version: $wingetVersion"
            Write-ConsoleStatus -Status success
            return
        }

        if ($installerCompletedSuccessfully) {
            LogWarning "Winget installation completed, but winget.exe is not available in the current session yet. A new session may be required."
            Write-ConsoleStatus -Status success
            return
        }

        LogError "Winget installation failed validation after the installer completed."
        Write-ConsoleStatus -Status failed
        return
        
    } catch {
        LogError "Error during winget installation: $_"
        Write-ConsoleStatus -Status failed
        return
    }

<#
	.SYNOPSIS
	Resolve the local winget.exe path without assuming the current PATH is fresh.
#>
function Resolve-WinGetExecutable
{
	Update-ProcessPathFromRegistry

	$WingetCommand = Get-Command -Name winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source -ErrorAction SilentlyContinue
	if (-not [string]::IsNullOrWhiteSpace($WingetCommand))
	{
		return $WingetCommand
	}

	$CandidatePaths = @(
		(Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe")
		(Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\winget.exe")
	) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

	return ($CandidatePaths | Select-Object -First 1)
    }
}

<#
	.SYNOPSIS
	Install or update to the latest PowerShell 7 release.

	.DESCRIPTION
	Uses WinGet to install the latest stable PowerShell 7 release.
	Falls back to the official Microsoft install script if WinGet is unavailable.

	.EXAMPLE
	Update-Powershell

	.NOTES
	Machine-wide
#>
function Update-Powershell
{
	Write-ConsoleStatus -Action "Installing/Updating PowerShell 7"
	LogInfo "Installing/Updating PowerShell 7"
	try
	{
		$WingetPath = Resolve-WinGetExecutable
		if ($WingetPath)
		{
			$process = Start-Process -FilePath $WingetPath `
				-ArgumentList "install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements" `
				-WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
			if ($process.ExitCode -notin 0, -1978335189)
			{
				throw "winget returned exit code $($process.ExitCode)"
			}
		}
		else
		{
			LogWarning "WinGet not available, using the official install script"
			Invoke-Expression "& { $(Invoke-RestMethod -Uri 'https://aka.ms/install-powershell.ps1' -UseBasicParsing) } -UseMSI -Quiet" -ErrorAction SilentlyContinue
		}
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to install/update PowerShell 7: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Hide the Spotlight "About this picture" desktop icon.

	.DESCRIPTION
	Removes the Spotlight namespace entry from the desktop and sets the matching
	HideDesktopIcons value so the icon stays hidden for the current user.

	.EXAMPLE
	Update-DesktopRegistry

	.NOTES
	Current user
#>
function Update-DesktopRegistry
{
	Write-Host 'Removing "About this Picture" from Desktop - ' -NoNewline
	LogInfo 'Removing "About this Picture" from Desktop'
    # Define registry paths and key/value
    $namespaceKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"
    $hideIconsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    $valueName = "{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"
    $valueData = 1

    # Remove the specified namespace registry key
    try
	{
        Remove-Item -Path $namespaceKeyPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
	catch
	{
        LogError "Registry key not found or could not be removed: $namespaceKeyPath"
    }

    # Ensure the HideDesktopIcons path exists and set the DWORD value
    try
	{
        if (-not (Test-Path -Path $hideIconsPath))
		{
            New-Item -Path $hideIconsPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $hideIconsPath -Name $valueName -Value $valueData -Type DWord -ErrorAction Stop | Out-Null
		Write-ConsoleStatus -Status success
    }
	catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to set registry value: $valueName"
    }
}

<#
	.SYNOPSIS
	Refresh the current process PATH from the machine and user environment blocks.
#>
function Update-ProcessPathFromRegistry
{
	$MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
	$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
	$env:Path = (@($MachinePath, $UserPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";"
}

<#
	.SYNOPSIS
	Restart File Explorer so desktop and shell changes apply immediately.

	.DESCRIPTION
	Stops the Explorer foreground process so desktop, taskbar, and File Explorer
	changes can be reloaded by the shell.

	.EXAMPLE
	Stop-Foreground

	.NOTES
	Current user
#>
function Stop-Foreground
{
    Stop-Process -Name "explorer" -Force | Out-Null
}

#endregion Initial Setup
