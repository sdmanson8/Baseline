using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Post Actions
<#
	.SYNOPSIS
	Run the post-change refresh and cleanup actions after tweaks finish.

	.DESCRIPTION
	Refreshes shell state, applies any generated Local Group Policy text files,
	cleans up temporary policy files, restores previously opened folders where
	possible, and performs the extra post-run fixes expected by this preset.

	.EXAMPLE
	PostActions
#>
function PostActions
{
	Write-ConsoleStatus -Action "Performing post actions"
	LogInfo "Performing post actions"

	function Get-PostActionRequirement
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$Name
		)

		if (-not ($Global:BaselinePostActionRequirements -is [hashtable]))
		{
			return $false
		}

		if (-not $Global:BaselinePostActionRequirements.ContainsKey($Name))
		{
			return $false
		}

		return [bool]$Global:BaselinePostActionRequirements[$Name]
	}

	function Invoke-PostActionStep
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$Action,

			[Parameter(Mandatory = $true)]
			[scriptblock]$ScriptBlock,

			[switch]$ContinueOnFailure
		)

		Write-ConsoleStatus -Action $Action
		LogInfo $Action

		try
		{
			& $ScriptBlock
			Write-ConsoleStatus -Status success
		}
		catch
		{
			if ($ContinueOnFailure)
			{
				Remove-HandledErrorRecord -ErrorRecord $_
				LogWarning "$Action was skipped: $($_.Exception.Message)"
				Write-ConsoleStatus -Status warning
				return
			}

			Write-ConsoleStatus -Status failed
			throw
		}
	}

	function Invoke-PostActionProcess
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$FilePath,

			[string[]]$ArgumentList,

			[Parameter(Mandatory = $true)]
			[string]$Description,

			[int]$TimeoutSeconds = 120,

			[string]$StandardOutputPath,

			[string]$StandardErrorPath
		)

		$processSplat = @{
			FilePath    = $FilePath
			WindowStyle = 'Hidden'
			PassThru    = $true
			ErrorAction = 'Stop'
		}

		if ($ArgumentList)
		{
			$processSplat['ArgumentList'] = $ArgumentList
		}

		if (-not [string]::IsNullOrWhiteSpace($StandardOutputPath))
		{
			$processSplat['RedirectStandardOutput'] = $StandardOutputPath
		}

		if (-not [string]::IsNullOrWhiteSpace($StandardErrorPath))
		{
			$processSplat['RedirectStandardError'] = $StandardErrorPath
		}

		$process = Start-Process @processSplat
		try
		{
			if (-not $process.WaitForExit($TimeoutSeconds * 1000))
			{
				try
				{
					Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue | Out-Null
				}
				catch
				{
					# Ignore cleanup failures after a timeout.
				}

				throw "$Description timed out after $TimeoutSeconds seconds"
			}

			$process.Refresh()
			$exitCode = try { $process.ExitCode } catch { $null }
			if ($null -ne $exitCode -and $exitCode -ne 0)
			{
				throw "$Description returned exit code $exitCode"
			}
		}
		finally
		{
			try
			{
				$process.Dispose()
			}
			catch
			{
				# Ignore process disposal failures.
			}
		}
	}

	function Invoke-PostActionPowerShellProcess
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$Description,

			[Parameter(Mandatory = $true)]
			[string]$ScriptContent,

			[int]$TimeoutSeconds = 120
		)

		$processToken = [guid]::NewGuid().ToString('N')
		$standardOutputPath = Join-Path $env:TEMP "Baseline-$processToken-postaction.stdout.txt"
		$standardErrorPath = Join-Path $env:TEMP "Baseline-$processToken-postaction.stderr.txt"
		$powershellProcessPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
		$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ScriptContent))

		try
		{
			Invoke-PostActionProcess -FilePath $powershellProcessPath `
				-ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand) `
				-Description $Description `
				-TimeoutSeconds $TimeoutSeconds `
				-StandardOutputPath $standardOutputPath `
				-StandardErrorPath $standardErrorPath

			if (Test-Path -LiteralPath $standardOutputPath)
			{
				return [string](Get-Content -LiteralPath $standardOutputPath -Raw -ErrorAction SilentlyContinue)
			}

			return $null
		}
		finally
		{
			Remove-Item -LiteralPath $standardOutputPath, $standardErrorPath -Force -ErrorAction Ignore | Out-Null
		}
	}

	try
	{
	#region Refresh Environment
	# Refresh the shell so desktop, taskbar, and environment changes are visible immediately.
	$Signature = @{
		Namespace          = "WinAPI"
		Name               = "UpdateEnvironment"
		Language           = "CSharp"
		CompilerParameters = $CompilerParameters
		MemberDefinition   = @"
private static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);
private const int WM_SETTINGCHANGE = 0x1a;
private const int SMTO_ABORTIFHUNG = 0x0002;

[DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = false)]
private static extern int SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);

[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
private static extern IntPtr SendMessageTimeout(IntPtr hWnd, int Msg, IntPtr wParam, string lParam, int fuFlags, int uTimeout, IntPtr lpdwResult);

[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
static extern bool SendNotifyMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam);

public static void Refresh()
{
	// Update desktop icons
	SHChangeNotify(0x8000000, 0x1000, IntPtr.Zero, IntPtr.Zero);

	// Update environment variables
	SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, null, SMTO_ABORTIFHUNG, 100, IntPtr.Zero);

	// Update taskbar
	SendNotifyMessage(HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, "TraySettings");
}

private static readonly IntPtr hWnd = new IntPtr(65535);
private const int Msg = 273;
// Virtual key ID of the F5 in File Explorer
private static readonly UIntPtr UIntPtr = new UIntPtr(41504);

[DllImport("user32.dll", SetLastError=true)]
public static extern int PostMessageW(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam);

public static void PostMessage()
{
	// Simulate pressing F5 to refresh the desktop
	PostMessageW(hWnd, Msg, UIntPtr, IntPtr.Zero);
}
"@
	}
	if (-not ("WinAPI.UpdateEnvironment" -as [type]))
	{
		Add-Type @Signature -ErrorAction Stop
	}

	# Simulate pressing F5 to refresh the desktop
	[WinAPI.UpdateEnvironment]::PostMessage()

	# Refresh desktop icons, environment variables, taskbar
	[WinAPI.UpdateEnvironment]::Refresh()

	# Restart Start menu
	Stop-Process -Name StartMenuExperienceHost -Force -ErrorAction SilentlyContinue | Out-Null
	#endregion Refresh Environment

	#region Other actions
	# Rebuild Local Group Policy data if this run generated LGPO input files.
	# Apply policies found in registry to re-build database database because gpedit.msc relies in its own database
	if ((Test-Path -Path "$env:TEMP\Computer.txt") -or (Test-Path -Path "$env:TEMP\User.txt"))
	{
		Invoke-PostActionStep -Action "Applying Local Group Policy updates" -ScriptBlock {
			$lgpoPath = Join-Path $PSScriptRoot '..\Binaries\LGPO.exe'

			if (Test-Path -Path "$env:TEMP\Computer.txt")
			{
				LogInfo "Importing Local Group Policy computer settings"
				Invoke-PostActionProcess -FilePath $lgpoPath `
					-ArgumentList @('/t', "$env:TEMP\Computer.txt") `
					-Description 'LGPO import for Computer.txt' `
					-TimeoutSeconds 120 `
					-StandardOutputPath "$env:TEMP\LGPOOutput.txt" `
					-StandardErrorPath "$env:TEMP\LGPOError.txt"
			}

			if (Test-Path -Path "$env:TEMP\User.txt")
			{
				LogInfo "Importing Local Group Policy user settings"
				Invoke-PostActionProcess -FilePath $lgpoPath `
					-ArgumentList @('/t', "$env:TEMP\User.txt") `
					-Description 'LGPO import for User.txt' `
					-TimeoutSeconds 120 `
					-StandardOutputPath "$env:TEMP\LGPOOutput.txt" `
					-StandardErrorPath "$env:TEMP\LGPOError.txt"
			}

			LogInfo $Localization.GPOUpdate
			Invoke-PostActionProcess -FilePath (Join-Path $env:WINDIR 'System32\gpupdate.exe') `
				-ArgumentList @('/force') `
				-Description 'gpupdate /force' `
				-TimeoutSeconds 180 `
				-StandardOutputPath "$env:TEMP\gpupdate-output.txt" `
				-StandardErrorPath "$env:TEMP\gpupdate-error.txt"
		}
	}

	# PowerShell 5.1 (7.5 too) interprets 8.3 file name literally, if an environment variable contains a non-Latin word
	# https://github.com/PowerShell/PowerShell/issues/21070
	Get-ChildItem -Path "$env:TEMP\Computer.txt", "$env:TEMP\User.txt" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null

	Invoke-PostActionStep -Action "Restarting Explorer shell" -ScriptBlock {
		# Kill all explorer instances in case "launch folder windows in a separate process" enabled
		Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue | Out-Null
		Start-Sleep -Seconds 3

		# Restoring closed folders
		if (Get-Variable -Name OpenedFolders -ErrorAction Ignore)
		{
			foreach ($Script:OpenedFolder in $Script:OpenedFolders)
			{
				if (Test-Path -Path $Script:OpenedFolder)
				{
					Start-Process -FilePath explorer -ArgumentList $Script:OpenedFolder | Out-Null
				}
			}
		}
	}

	# Open Startup page - wait for the explorer shell to be fully running after the
	# restart above, then use cmd /c start which correctly dispatches ms-settings:
	# URIs from an elevated process without triggering the file-system error dialog.
	try
	{
		$shellReady = $false
		for ($w = 0; $w -lt 20; $w++)
		{
			if (Get-Process -Name explorer -ErrorAction SilentlyContinue)
			{
				$shellReady = $true
				break
			}
			Start-Sleep -Milliseconds 500
		}
		if ($shellReady)
		{
			Start-Sleep -Milliseconds 500  # brief extra settle time
			cmd /c "start ms-settings:startupapps" 2>$null | Out-Null
		}
	}
	catch
	{
		LogWarning "Failed to open the Startup apps settings page after post actions: $($_.Exception.Message)"
	}

<#
	# Checking whether any of scheduled tasks were created. Unless open Task Scheduler
	if ($Script:ScheduledTasks)
	{
		# Find and close taskschd.msc by its argument
		$taskschd_Process_ID = (Get-CimInstance -ClassName CIM_Process | Where-Object -FilterScript {$_.Name -eq "mmc.exe"} | Where-Object -FilterScript {
			$_.CommandLine -match "taskschd.msc"
		}).Handle
		# We have to check before executing due to "Set-StrictMode -Version Latest"
		if ($taskschd_Process_ID)
		{
			Get-Process -Id $taskschd_Process_ID | Stop-Process -Force
		}

		# Open Task Scheduler
		Start-Process -FilePath taskschd.msc
	}
	#endregion Other actions

	#region Toast notifications
	# Persist Baseline notifications to prevent to immediately disappear from Action Center
	# Enable notifications in Action Center
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name DisableNotificationCenter -Force -ErrorAction Ignore
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name DisableNotificationCenter -Type CLEAR
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name DisableNotificationCenter -Type CLEAR

	# Enable notifications
	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications -Name ToastEnabled -Force -ErrorAction Ignore
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications -Name NoToastApplicationNotification -Force -ErrorAction Ignore
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name DisableNotificationCenter -Type CLEAR

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Baseline))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Baseline -Force
	}
	New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Baseline -Name ShowInActionCenter -PropertyType DWord -Value 1 -Force

	if (-not (Test-Path -Path Registry::HKEY_CLASSES_ROOT\AppUserModelId\Baseline))
	{
		New-Item -Path Registry::HKEY_CLASSES_ROOT\AppUserModelId\Baseline -Force
	}
	Pause
#>

	if (Get-PostActionRequirement -Name 'EnsureSmbGuestAuth')
	{
		Invoke-PostActionStep -Action "Restoring guest SMB access" -ScriptBlock {
			New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
				-Name "AllowInsecureGuestAuth" `
				-PropertyType DWord `
				-Value 1 `
				-Force `
				-ErrorAction SilentlyContinue | Out-Null
		}
	}

	if (Get-PostActionRequirement -Name 'EnsurePrintManagementConsole')
	{
		Invoke-PostActionStep -Action "Ensuring Print Management Console is installed" -ContinueOnFailure -ScriptBlock {
			$PrintManagementCapability = $null
			$capabilityJson = Invoke-PostActionPowerShellProcess -Description 'Print Management Console capability lookup' `
				-ScriptContent @'
$ProgressPreference = 'SilentlyContinue'
$Capability = Get-WindowsCapability -Online -Name 'Print.Management.Console*' -ErrorAction Stop |
	Select-Object -First 1

if ($Capability)
{
	[PSCustomObject]@{
		Name = [string]$Capability.Name
		State = [string]$Capability.State
	} | ConvertTo-Json -Compress
}
'@ `
				-TimeoutSeconds 90

			if (-not [string]::IsNullOrWhiteSpace($capabilityJson))
			{
				$PrintManagementCapability = $capabilityJson | ConvertFrom-Json
			}

			if ($PrintManagementCapability)
			{
				if ([string]$PrintManagementCapability.State -ne 'Installed')
				{
					LogInfo "Installing Print Management Console capability: $($PrintManagementCapability.Name)"
					$installScript = @"
`$ProgressPreference = 'SilentlyContinue'
Add-WindowsCapability -Online -Name '$($PrintManagementCapability.Name)' -ErrorAction Stop | Out-Null
"@
					$null = Invoke-PostActionPowerShellProcess -Description 'Print Management Console install' `
						-ScriptContent $installScript `
						-TimeoutSeconds 300
				}
				else
				{
					LogInfo "Print Management Console is already installed."
				}
			}
			else
			{
				LogInfo "Print Management Console capability is not available on this machine. Skipping reinstall."
			}
		}
	}

		Write-ConsoleStatus -Action "Performing post actions" -Status success
	}
	catch
	{
		LogError "Post actions failed: $($_.Exception.Message)"
		Write-ConsoleStatus -Action "Performing post actions" -Status failed
	}
	finally
	{
		if ($Global:BaselinePostActionRequirements -is [hashtable])
		{
			$Global:BaselinePostActionRequirements['EnsurePrintManagementConsole'] = $false
			$Global:BaselinePostActionRequirements['EnsureSmbGuestAuth'] = $false
		}
	}
}
#endregion Post Actions

Export-ModuleMember -Function '*'
