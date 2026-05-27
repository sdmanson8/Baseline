switch ($PSCmdlet.ParameterSetName)
	{
		"Dark"
		{
			Write-ConsoleStatus -Action "Installing dark cursors"
			LogInfo "Installing dark cursors"
			try
			{
				if (-not (Test-Path -Path "$env:SystemRoot\Cursors\W11 Cursor Dark Free"))
				{
					New-Item -Path "$env:SystemRoot\Cursors\W11 Cursor Dark Free" -ItemType Directory -Force -ErrorAction Stop | Out-Null
				}

				Expand-CursorArchiveFolder -ArchivePath $cursorArchivePath -DestinationPath "$env:SystemRoot\Cursors\W11 Cursor Dark Free" -FolderName 'dark'

				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "(default)" `
					-Value "W11 Cursor Dark Free" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "AppStarting" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\appstarting.ani" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Arrow" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\arrow.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Crosshair" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\crosshair.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Hand" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\hand.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Help" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\help.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "IBeam" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\ibeam.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "No" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\no.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "NWPen" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\nwpen.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Person" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\person.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Pin" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\pin.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Scheme Source" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeAll" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizeall.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNESW" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizenesw.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNS" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizens.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNWSE" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizenwse.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeWE" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\sizewe.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "UpArrow" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\uparrow.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Wait" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Dark Free\wait.ani" `
					-Type ExpandString

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
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors\Schemes" `
					-Name "W11 Cursor Dark Free" `
					-Value $Schemes `
					-Type String

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
			Write-ConsoleStatus -Action "Installing light cursors"
			LogInfo "Installing light cursors"
			try
			{
				if (-not (Test-Path -Path "$env:SystemRoot\Cursors\W11 Cursor Light Free"))
				{
					New-Item -Path "$env:SystemRoot\Cursors\W11 Cursor Light Free" -ItemType Directory -Force -ErrorAction Stop | Out-Null
				}

				Expand-CursorArchiveFolder -ArchivePath $cursorArchivePath -DestinationPath "$env:SystemRoot\Cursors\W11 Cursor Light Free" -FolderName 'light'

				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "(default)" `
					-Value "W11 Cursor Light Free" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "AppStarting" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\appstarting.ani" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Arrow" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\arrow.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Crosshair" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\crosshair.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Hand" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\hand.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Help" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\help.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "IBeam" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\ibeam.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "No" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\no.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "NWPen" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\nwpen.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Person" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\person.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Pin" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\pin.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Scheme Source" `
					-Value 1 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeAll" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizeall.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNESW" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizenesw.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNS" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizens.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNWSE" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizenwse.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeWE" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\sizewe.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "UpArrow" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\uparrow.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Wait" `
					-Value "%SystemRoot%\Cursors\W11 Cursor Light Free\wait.ani" `
					-Type ExpandString

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
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors\Schemes" `
					-Name "W11 Cursor Light Free" `
					-Value $Schemes `
					-Type String

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
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "(default)" `
					-Value "" `
					-Type String
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "AppStarting" `
					-Value "%SystemRoot%\cursors\aero_working.ani" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Arrow" `
					-Value "%SystemRoot%\cursors\aero_arrow.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Crosshair" `
					-Value "" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Hand" `
					-Value "%SystemRoot%\cursors\aero_link.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Help" `
					-Value "%SystemRoot%\cursors\aero_helpsel.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "IBeam" `
					-Value "" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "No" `
					-Value "%SystemRoot%\cursors\aero_unavail.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "NWPen" `
					-Value "%SystemRoot%\cursors\aero_pen.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Person" `
					-Value "%SystemRoot%\cursors\aero_person.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Pin" `
					-Value "%SystemRoot%\cursors\aero_pin.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Scheme Source" `
					-Value 2 `
					-Type DWord
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeAll" `
					-Value "%SystemRoot%\cursors\aero_move.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNESW" `
					-Value "%SystemRoot%\cursors\aero_nesw.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNS" `
					-Value "%SystemRoot%\cursors\aero_ns.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeNWSE" `
					-Value "%SystemRoot%\cursors\aero_nwse.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "SizeWE" `
					-Value "%SystemRoot%\cursors\aero_ew.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "UpArrow" `
					-Value "%SystemRoot%\cursors\aero_up.cur" `
					-Type ExpandString
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\Cursors" `
					-Name "Wait" `
					-Value "%SystemRoot%\cursors\aero_up.cur" `
					-Type ExpandString
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore the default cursor scheme: $($_.Exception.Message)"
			}
		}
	}
