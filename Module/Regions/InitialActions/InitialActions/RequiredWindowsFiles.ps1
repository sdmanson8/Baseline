$Files = if ($osInfo.IsWindowsServer)
	{
		@(
			"$env:SystemRoot\System32\smartscreen.exe",
			"$env:SystemRoot\System32\CompatTelRunner.exe"
		)
	}
	else
	{
		@(
			"$env:SystemRoot\System32\smartscreen.exe",
			"$env:SystemRoot\System32\SecurityHealthSystray.exe",
			"$env:SystemRoot\System32\CompatTelRunner.exe"
		)
	}
