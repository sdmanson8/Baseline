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
	# Write-Host: intentional — user-visible progress indicator
	Write-Host "Creating System Restore Point - " -NoNewline
	$restoreSystemProtection = $false
	$createdSuccessfully = $false
	try
	{
		# Ensure the Volume Shadow Copy service is running — both Checkpoint-Computer
		# and the WMI fallback depend on it. On VMs or hardened systems it may be
		# set to Manual/Disabled and not started.
		try
		{
			$vssSvc = Get-Service -Name VSS -ErrorAction Stop
			if ($vssSvc.Status -ne 'Running')
			{
				LogInfo "Starting Volume Shadow Copy (VSS) service (was $($vssSvc.Status))."
				if ($vssSvc.StartType -eq 'Disabled')
				{
					Set-Service -Name VSS -StartupType Manual -ErrorAction Stop
				}
				Start-Service -Name VSS -ErrorAction Stop
			}
		}
		catch
		{
			LogWarning "Could not ensure VSS service is running: $($_.Exception.Message)"
		}

		$SystemDriveUniqueID = (Get-Volume | Where-Object -FilterScript {$_.DriveLetter -eq "$($env:SystemDrive[0])"}).UniqueID
		$SystemProtection = ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients" -ErrorAction Ignore)."{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}") | Where-Object -FilterScript {$_ -match [regex]::Escape($SystemDriveUniqueID)}

		if ($null -eq $SystemProtection)
		{
			# Verify whether System Protection is actually disabled before attempting to enable it,
			# because the SPP\Clients registry check can return null on newer Windows 11 builds
			# even when System Protection is already on.
			$srpEnabled = $false
			try
			{
				$srpStatus = Get-CimInstance -ClassName SystemRestoreConfig -Namespace 'root\default' -ErrorAction Stop
				if ($srpStatus -and $srpStatus.RPSessionInterval -eq 1) { $srpEnabled = $true }
			}
			catch { $srpEnabled = $false }

			if (-not $srpEnabled)
			{
				$restoreSystemProtection = $true
				Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
			}
		}

		# Never skip creating a restore point
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null

		$osName = (Get-OSInfo).OSName
		$displayVersion = Get-BaselineDisplayVersion

		$restorePointDescription = "Baseline | Utility for $osName"
		if (-not [string]::IsNullOrWhiteSpace([string]$displayVersion))
		{
			$restorePointDescription = "$restorePointDescription $displayVersion"
		}

		# Try Checkpoint-Computer in a background job with a timeout to prevent hanging
		$checkpointSucceeded = $false
		$restorePointTimeoutSeconds = 120
		try
		{
			$job = Start-Job -ScriptBlock {
				param ($Desc)
				Checkpoint-Computer -Description $Desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
			} -ArgumentList $restorePointDescription
			$finished = $job | Wait-Job -Timeout $restorePointTimeoutSeconds
			if ($finished)
			{
				$job | Receive-Job -ErrorAction Stop | Out-Null
				$checkpointSucceeded = $true
			}
			else
			{
				$job | Stop-Job -ErrorAction SilentlyContinue
				LogWarning "Checkpoint-Computer timed out after $restorePointTimeoutSeconds seconds. Trying WMI fallback."
			}
			$job | Remove-Job -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			LogWarning "Checkpoint-Computer failed: $($_.Exception.Message). Trying WMI fallback."
			if ($job) { $job | Remove-Job -Force -ErrorAction SilentlyContinue }
		}

		if (-not $checkpointSucceeded)
		{
			try
			{
				$sr = [wmiclass]'\\.\root\default:SystemRestore'
				$result = $sr.CreateRestorePoint($restorePointDescription, 12, 100)
				if ($result.ReturnValue -ne 0)
				{
					throw "WMI SystemRestore.CreateRestorePoint failed with return code $($result.ReturnValue)"
				}
				$checkpointSucceeded = $true
			}
			catch
			{
				throw "Restore point creation failed: $($_.Exception.Message)"
			}
		}

		# Revert the System Restore checkpoint creation frequency to 1440 minutes
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 1440 -Force -ErrorAction Stop | Out-Null

		# Turn off System Protection for the system drive if it was turned off before without deleting the existing restore points
		if ($restoreSystemProtection)
		{
			LogInfo "Disabling System Restore again"
			Disable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop | Out-Null
		}
		Write-ConsoleStatus -Status success
		$createdSuccessfully = $true
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to create a restore point: $($_.Exception.Message)"
	}

	return $createdSuccessfully
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
        $resolvedWingetPath = Resolve-WinGetExecutable
        Write-ConsoleStatus -Action "Checking WinGet"
        LogInfo "Checking WinGet"
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedWingetPath))
        {
            LogInfo "Resolved winget executable: $resolvedWingetPath"
        }
        LogInfo "Winget is already installed and working. Version: $wingetVersion"
        Write-ConsoleStatus -Status success
        return
    }

    LogWarning "Winget not found or not functional"
    
    # If not working, use the asheroto installer script
    Write-ConsoleStatus -Action "Installing WinGet"
    LogInfo "Installing WinGet:"
    
    try {
        $installerVersion = '5.3.1'
        $installerSha256 = '029094EFD9D26A83AEA184B16D15C772D35D64E1288010741F50FD33A1E1F40F'
        $installerUrl = "https://github.com/asheroto/winget-install/releases/download/$installerVersion/winget-install.ps1"
        $installerPath = Join-Path $env:TEMP ("winget-install-{0}.ps1" -f $installerVersion)
        $stdoutLog = Join-Path $env:TEMP "winget-install-stdout.log"
        $stderrLog = Join-Path $env:TEMP "winget-install-stderr.log"

        LogInfo "Downloading winget installer from $installerUrl"
        Invoke-DownloadFile -Uri $installerUrl -OutFile $installerPath

        if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -eq 0)
        {
            throw "winget installer download failed or produced an empty file at $installerPath"
        }

        $null = Assert-FileHash `
            -Path $installerPath `
            -ExpectedSha256 $installerSha256 `
            -Label ("winget-install.ps1 v{0}" -f $installerVersion)
        LogInfo ("Download and SHA-256 verification completed for winget-install.ps1 v{0}" -f $installerVersion)

        LogInfo "Executing installer script..."

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
    } finally {
        if ($installerPath -and (Test-Path -LiteralPath $installerPath))
        {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
        if ($stdoutLog -and (Test-Path -LiteralPath $stdoutLog))
        {
            Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue
        }
        if ($stderrLog -and (Test-Path -LiteralPath $stderrLog))
        {
            Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue
        }
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
		if (-not [string]::IsNullOrWhiteSpace([string]$WingetPath))
		{
			LogInfo "Using winget executable: $WingetPath"
		}
		if ($WingetPath)
		{
			$wingetSucceeded = $false
			$process = Start-Process -FilePath $WingetPath `
				-ArgumentList "install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent" `
				-WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
			if ($process.ExitCode -in 0, -1978335189)
			{
				$wingetSucceeded = $true
			}
			else
			{
				LogWarning "winget install returned exit code $($process.ExitCode), falling back to MSI installer"
			}
		}
		if (-not $WingetPath -or -not $wingetSucceeded)
		{
			$installerPath = $null
			try
			{
				LogInfo "Downloading the official PowerShell MSI package from GitHub"
				$installerUri = Resolve-PowerShellInstallerUri
				$installerFileName = Split-Path -Path $installerUri -Leaf
				$installerPath = Join-Path $env:TEMP $installerFileName
				Invoke-DownloadFile -Uri $installerUri -OutFile $installerPath
				$null = Assert-AuthenticodeSignature -Path $installerPath -AllowedSubjects @('CN=Microsoft Corporation')
				$process = Start-Process -FilePath 'msiexec.exe' `
					-ArgumentList "/i `"$installerPath`" /qn /norestart" `
					-WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
				if ($process.ExitCode -notin 0, 3010)
				{
					throw "msiexec returned exit code $($process.ExitCode)"
				}
			}
			finally
			{
				if ($installerPath -and (Test-Path -LiteralPath $installerPath))
				{
					Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
				}
			}
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
	# Write-Host: intentional — user-visible progress indicator
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
	LogInfo "Stopping explorer.exe to apply shell changes"
	Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue | Out-Null
}

#endregion Initial Setup

Export-ModuleMember -Function '*'
