try
	{
		$ipconfigPath = Join-Path $env:SystemRoot 'System32\ipconfig.exe'
		$null = Invoke-BaselineProcess -FilePath $ipconfigPath -ArgumentList @('/flushdns') -TimeoutSeconds 60 -AllowedExitCodes @(0)
		LogInfo "DNS cache flushed"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "ipconfig /flushdns failed: $($_.Exception.Message)"
	}

try
	{
		$nbtstatPath = Join-Path $env:SystemRoot 'System32\nbtstat.exe'
		$null = Invoke-BaselineProcess -FilePath $nbtstatPath -ArgumentList @('-R') -TimeoutSeconds 60 -AllowedExitCodes @(0)
		LogInfo "NetBIOS cache purged (nbtstat -R)"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "nbtstat -R failed: $($_.Exception.Message)"
	}

try
	{
		$nbtstatPath = Join-Path $env:SystemRoot 'System32\nbtstat.exe'
		$null = Invoke-BaselineProcess -FilePath $nbtstatPath -ArgumentList @('-RR') -TimeoutSeconds 60 -AllowedExitCodes @(0)
		LogInfo "NetBIOS names re-registered (nbtstat -RR)"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "nbtstat -RR failed: $($_.Exception.Message)"
	}

	try
	{
		$nicConfigs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue
		if ($nicConfigs)
		{
			foreach ($nic in $nicConfigs)
			{
				$result = Invoke-CimMethod -InputObject $nic -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 1 } -ErrorAction SilentlyContinue
				if ($result.ReturnValue -eq 0)
				{
					LogInfo "NetBIOS enabled on adapter: $($nic.Description)"
				}
				else
				{
					$hadIssue = $true
					LogWarning "NetBIOS set returned $($result.ReturnValue) on: $($nic.Description)"
				}
			}
		}
		elseif (Get-Command wmic -ErrorAction SilentlyContinue)
		{
			$wmicPath = Join-Path $env:SystemRoot 'System32\wbem\wmic.exe'
			$null = Invoke-BaselineProcess -FilePath $wmicPath -ArgumentList @('nicconfig', 'where', '(IPEnabled=TRUE)', 'call', 'SetTcpipNetbios', '1') -TimeoutSeconds 120 -AllowedExitCodes @(0)
			LogInfo "NetBIOS over TCP/IP enabled via wmic"
		}
		else
		{
			LogInfo "NetBIOS enable skipped because the WMI and wmic paths were unavailable"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "NetBIOS enable failed: $($_.Exception.Message)"
	}
