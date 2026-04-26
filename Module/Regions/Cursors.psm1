using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Cursors

<#
	.SYNOPSIS
	Free "Windows 11 Cursors Concept" cursors from Jepri Creations

	.PARAMETER Dark
	Download and install free dark "Windows 11 Cursors Concept" cursors from Jepri Creations

	.PARAMETER Light
	Download and install free light "Windows 11 Cursors Concept" cursors from Jepri Creations

	.PARAMETER Default
	Set default cursors

	.EXAMPLE
	Install-Cursors -Dark

	.EXAMPLE
	Install-Cursors -Light

	.EXAMPLE
	Install-Cursors -Default

	.LINK
	https://www.deviantart.com/jepricreations/art/Windows-11-Cursors-Concept-886489356

	.NOTES
	The 14/12/24 version

	.NOTES
	Current user
#>
function Install-Cursors
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Dark"
		)]
		[switch]
		$Dark,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Light"
		)]
		[switch]
		$Light,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	if (-not $Default)
	{
		$DownloadsFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
		$cursorArchivePath = Join-Path $DownloadsFolder 'Windows11Cursors.zip'

		try
		{
			# Download cursors from the curated upstream mirror, then verify the
			# archive fingerprint before extraction.
			Invoke-DownloadFile `
				-Uri 'https://raw.githubusercontent.com/farag2/Sophia-Script-for-Windows/refs/heads/master/Cursors/Windows11Cursors.zip' `
				-OutFile $cursorArchivePath
			$null = Assert-FileHash `
				-Path $cursorArchivePath `
				-ExpectedSha256 '04C9A4797F02AB88FD5DF15A9377A32B3F66497F05CAF89460F3441968A7024C' `
				-Label 'Windows 11 cursor archive'
		}
		catch
		{
			LogError ("Failed to download or verify the Windows cursor archive: {0}" -f $_.Exception.Message)
			return
		}
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Dark"
		{
			Write-ConsoleStatus -Action "Installing 'Windows 11 Cursors Concept' dark cursors"
			LogInfo "Installing 'Windows 11 Cursors Concept' dark cursors"
			try
			{
				if (-not (Test-Path -Path "$env:SystemRoot\Cursors\W11 Cursor Dark Free"))
				{
					New-Item -Path "$env:SystemRoot\Cursors\W11 Cursor Dark Free" -ItemType Directory -Force -ErrorAction Stop | Out-Null
				}

				# Extract archive from "dark" folder only
				& "$env:SystemRoot\System32\tar.exe" -xf $cursorArchivePath -C "$env:SystemRoot\Cursors\W11 Cursor Dark Free" --strip-components=1 dark/ | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "tar.exe returned exit code $LASTEXITCODE"
				}

				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name '(default)' -Value "W11 Cursor Dark Free by Jepri Creations" -Type String | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'AppStarting' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\appstarting.ani" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Arrow' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\arrow.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Crosshair' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\crosshair.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Hand' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\hand.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Help' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\help.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'IBeam' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\ibeam.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'No' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\no.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'NWPen' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\nwpen.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Person' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\person.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Pin' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\pin.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Scheme Source' -Value 1 -Type DWord | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeAll' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizeall.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNESW' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizenesw.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNS' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizens.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNWSE' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizenwse.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeWE' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizewe.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'UpArrow' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\uparrow.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Wait' -Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\wait.ani" -Type ExpandString | Out-Null

				if (-not (Test-Path -Path "HKCU:\Control Panel\Cursors\Schemes"))
				{
					New-Item -Path "HKCU:\Control Panel\Cursors\Schemes" -Force -ErrorAction Stop | Out-Null
				}
				[string[]]$Schemes = (
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\arrow.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\help.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\appstarting.ani",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\wait.ani",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\crosshair.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\ibeam.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\nwpen.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\no.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\sizens.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\sizewe.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\sizenwse.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\sizenesw.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\sizeall.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\uparrow.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\hand.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\person.cur",
					"%SystemRoot%\Cursors\W11 Cursor Dark Free\pin.cur"
				) -join ","
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors\Schemes' -Name 'W11 Cursor Dark Free by Jepri Creations' -Value $Schemes -Type String | Out-Null

				Start-Sleep -Seconds 1

				Remove-Item -Path $cursorArchivePath, "$env:SystemRoot\Cursors\W11 Cursor Dark Free\Install.inf" -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to install the dark cursor theme: $($_.Exception.Message)"
			}
		}
		"Light"
		{
			Write-ConsoleStatus -Action "Installing 'Windows 11 Cursors Concept' light cursors"
			LogInfo "Installing 'Windows 11 Cursors Concept' light cursors"
			try
			{
				if (-not (Test-Path -Path "$env:SystemRoot\Cursors\W11 Cursor Light Free"))
				{
					New-Item -Path "$env:SystemRoot\Cursors\W11 Cursor Light Free" -ItemType Directory -Force -ErrorAction Stop | Out-Null
				}

				# Extract archive from "light" folder only
				& "$env:SystemRoot\System32\tar.exe" -xf $cursorArchivePath -C "$env:SystemRoot\Cursors\W11 Cursor Light Free" --strip-components=1 light/ | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "tar.exe returned exit code $LASTEXITCODE"
				}

				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name '(default)' -Value "W11 Cursor Light Free by Jepri Creations" -Type String | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'AppStarting' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\appstarting.ani" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Arrow' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\arrow.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Crosshair' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\crosshair.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Hand' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\hand.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Help' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\help.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'IBeam' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\ibeam.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'No' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\no.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'NWPen' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\nwpen.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Person' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\person.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Pin' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\pin.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Scheme Source' -Value 1 -Type DWord | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeAll' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizeall.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNESW' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizenesw.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNS' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizens.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNWSE' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizenwse.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeWE' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizewe.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'UpArrow' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\uparrow.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Wait' -Value "%SystemRoot%\Cursors\W11 Cursor Light Free\wait.ani" -Type ExpandString | Out-Null

				if (-not (Test-Path -Path "HKCU:\Control Panel\Cursors\Schemes"))
				{
					New-Item -Path "HKCU:\Control Panel\Cursors\Schemes" -Force -ErrorAction Stop | Out-Null
				}
				[string[]]$Schemes = (
					"%SystemRoot%\Cursors\W11 Cursor Light Free\arrow.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\help.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\appstarting.ani",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\wait.ani",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\crosshair.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\ibeam.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\nwpen.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\no.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\sizens.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\sizewe.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\sizenwse.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\sizenesw.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\sizeall.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\uparrow.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\hand.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\person.cur",
					"%SystemRoot%\Cursors\W11 Cursor Light Free\pin.cur"
				) -join ","
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors\Schemes' -Name 'W11 Cursor Light Free by Jepri Creations' -Value $Schemes -Type String | Out-Null

				Start-Sleep -Seconds 1

				Remove-Item -Path $cursorArchivePath, "$env:SystemRoot\Cursors\W11 Cursor Light Free\Install.inf" -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to install the light cursor theme: $($_.Exception.Message)"
			}
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Setting default cursors"
			LogInfo "Setting default cursors"
			try
			{
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name '(default)' -Value "" -Type String | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'AppStarting' -Value "%SystemRoot%\cursors\aero_working.ani" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Arrow' -Value "%SystemRoot%\cursors\aero_arrow.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Crosshair' -Value "" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Hand' -Value "%SystemRoot%\cursors\aero_link.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Help' -Value "%SystemRoot%\cursors\aero_helpsel.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'IBeam' -Value "" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'No' -Value "%SystemRoot%\cursors\aero_unavail.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'NWPen' -Value "%SystemRoot%\cursors\aero_pen.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Person' -Value "%SystemRoot%\cursors\aero_person.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Pin' -Value "%SystemRoot%\cursors\aero_pin.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Scheme Source' -Value 2 -Type DWord | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeAll' -Value "%SystemRoot%\cursors\aero_move.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNESW' -Value "%SystemRoot%\cursors\aero_nesw.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNS' -Value "%SystemRoot%\cursors\aero_ns.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeNWSE' -Value "%SystemRoot%\cursors\aero_nwse.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'SizeWE' -Value "%SystemRoot%\cursors\aero_ew.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'UpArrow' -Value "%SystemRoot%\cursors\aero_up.cur" -Type ExpandString | Out-Null
				Set-RegistryValueSafe -Path 'HKCU:\Control Panel\Cursors' -Name 'Wait' -Value "%SystemRoot%\cursors\aero_up.cur" -Type ExpandString | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore the default cursor scheme: $($_.Exception.Message)"
			}
		}
	}

	# Reload cursor on-the-fly
	$Signature = @{
		Namespace          = "WinAPI"
		Name               = "Cursor"
		Language           = "CSharp"
		CompilerParameters = $CompilerParameters
		MemberDefinition   = @"
[DllImport("user32.dll", EntryPoint = "SystemParametersInfo")]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, uint pvParam, uint fWinIni);
"@
	}
	if (-not ("WinAPI.Cursor" -as [type]))
	{
		Add-Type @Signature
	}
	[void][WinAPI.Cursor]::SystemParametersInfo(0x0057, 0, $null, 0)
}

#endregion Cursors

Export-ModuleMember -Function '*'
