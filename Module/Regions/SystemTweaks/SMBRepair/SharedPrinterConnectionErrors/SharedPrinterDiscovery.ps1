try
	{
		if (Get-Command Get-Printer -ErrorAction SilentlyContinue)
		{
			$printers = Get-Printer -ErrorAction SilentlyContinue
			$shared = $printers | Where-Object { $_.Shared }
			if ($shared)
			{
				LogInfo "Shared printers on this host:"
				$shared | ForEach-Object {
					LogInfo "  -> '$($_.Name)' share='$($_.ShareName)'"
				}
			}
			else
			{
				LogInfo "No printers are currently shared on this host."
			}
		}
		else
		{
			LogInfo "Get-Printer not available on this system"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not enumerate printers: $($_.Exception.Message)"
	}

	if ($ClientMode)
	{
		LogInfo "Applying optional client-side printer cleanup"

		try
		{
			switch ($osInfo.CurrentBuild)
			{
				19041 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				19042 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				19043 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				19044 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				18363 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "1921033356" -Value 0 -Type DWord }
				17763 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "3598754956" -Value 0 -Type DWord }
				22000 { LogInfo "Win11 21H2 - ensure the relevant printer update is installed." }
				default
				{
					if ($osInfo.CurrentBuild -ge 22621)
					{
						LogInfo "Win11 22H2+ - RPC Named Pipes fix is usually the main resolution for 0x7C."
					}
					else
					{
						LogWarning "Unrecognised build $($osInfo.CurrentBuild) - applying all known KIR values"
						Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord
						Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "1921033356" -Value 0 -Type DWord
						Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "3598754956" -Value 0 -Type DWord
					}
				}
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to apply client KIR values: $($_.Exception.Message)"
		}

		LogInfo "KIR reboot required for this change to take effect."

		LogInfo "Stopping the Print Spooler for client-side CSR cleanup"
		if (-not (Stop-SharedPrinterSpoolerService -Reason 'client-side CSR cleanup'))
		{
			$hadIssue = $true
		}

		try
		{
			$clientCsrPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Providers\Client Side Rendering Print Provider"
			if (Test-Path $clientCsrPath)
			{
				$bak = Join-Path $env:TEMP "CSR_Client_backup.reg"
				$native = $clientCsrPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
				$regExePath = Join-Path $env:SystemRoot 'System32\reg.exe'
				$null = Invoke-BaselineProcess -FilePath $regExePath -ArgumentList @('export', $native, $bak, '/y') -TimeoutSeconds 120 -AllowedExitCodes @(0)
				Remove-Item -Path $clientCsrPath -Recurse -Force -ErrorAction Stop
				LogInfo "Deleted CSR Print Provider key on client (backed up to $bak)"
			}
			else
			{
				LogInfo "CSR key not present on client -- OK"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Could not remove client CSR key: $($_.Exception.Message)"
		}

		LogInfo "mscms.dll copy on client"
		$clientSrc = Join-Path $env:SystemRoot "System32\mscms.dll"
		if (Test-Path $clientSrc)
		{
			foreach ($f in @(
				"$env:SystemRoot\System32\spool\drivers\x64\3",
				"$env:SystemRoot\System32\spool\drivers\x64\4",
				"$env:SystemRoot\System32\spool\drivers\W32X86\3",
				"$env:SystemRoot\System32\spool\drivers\arm64\3",
				"$env:SystemRoot\System32\spool\drivers\arm64\4"
			))
			{
				if (Test-Path $f)
				{
					try
					{
						Copy-Item -Path $clientSrc -Destination (Join-Path $f "mscms.dll") -Force -ErrorAction Stop
						LogInfo "Copied mscms.dll -> $f"
					}
					catch
					{
						$hadIssue = $true
						LogWarning "Could not copy mscms.dll to $f : $($_.Exception.Message)"
					}
				}
			}
		}
		else
		{
			$hadIssue = $true
			LogWarning "mscms.dll not found at $clientSrc -- run sfc /scannow"
		}

		if ($RunSystemFileCheck)
		{
			LogInfo "Client-side SFC system file check"
			try
			{
				$sfc = Invoke-BaselineProcess -FilePath 'sfc.exe' -ArgumentList @('/scannow') -TimeoutSeconds 1800
				if ($sfc.ExitCode -eq 0)
				{
					LogInfo "SFC completed -- no violations found"
				}
				else
				{
					LogWarning "SFC ExitCode $($sfc.ExitCode) -- check CBS.log for details"
				}
			}
			catch
			{
				$hadIssue = $true
				LogWarning "SFC could not be run: $($_.Exception.Message)"
			}
		}
		else
		{
			LogInfo "Skipped client-side SFC check during shared printer repair. Use -RunSystemFileCheck when a full system file repair scan is explicitly required."
		}

		LogInfo "Final client spooler restart"
		if (-not (Stop-SharedPrinterSpoolerService -Reason 'final client restart'))
		{
			$hadIssue = $true
		}

		if (-not (Start-SharedPrinterSpoolerService -Reason 'final client restart'))
		{
			$hadIssue = $true
		}
	}
