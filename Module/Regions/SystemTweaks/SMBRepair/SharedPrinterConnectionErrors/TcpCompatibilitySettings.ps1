try
	{
		$netshPath = Join-Path $env:SystemRoot 'System32\netsh.exe'
		$null = Invoke-BaselineProcess -FilePath $netshPath -ArgumentList @('int', 'tcp', 'set', 'global', 'autotuninglevel=normal') -TimeoutSeconds 120 -AllowedExitCodes @(0)
		LogInfo "TCP autotuninglevel = normal"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "netsh tcp autotuninglevel failed: $($_.Exception.Message)"
	}

try
	{
		$netshPath = Join-Path $env:SystemRoot 'System32\netsh.exe'
		$null = Invoke-BaselineProcess -FilePath $netshPath -ArgumentList @('int', 'tcp', 'set', 'global', 'rss=enabled') -TimeoutSeconds 120 -AllowedExitCodes @(0)
		LogInfo "TCP RSS = enabled"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "netsh tcp rss failed: $($_.Exception.Message)"
	}

try
	{
		$netshPath = Join-Path $env:SystemRoot 'System32\netsh.exe'
		$null = Invoke-BaselineProcess -FilePath $netshPath -ArgumentList @('int', 'tcp', 'set', 'global', 'chimney=enabled') -TimeoutSeconds 120 -AllowedExitCodes @(0)
		LogInfo "TCP chimney = enabled"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "netsh tcp chimney failed (not supported on all hardware): $($_.Exception.Message)"
	}
