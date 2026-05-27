$traceGuiStartup = {
		param([string]$Message)
		try
		{
			$traceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
			if (-not [System.IO.Directory]::Exists($traceDirectory))
			{
				[void][System.IO.Directory]::CreateDirectory($traceDirectory)
			}
			$tracePath = Join-Path $traceDirectory 'Baseline-launch-trace.txt'
			[System.IO.File]::AppendAllText($tracePath, ("{0:o} [GUI] {1}`r`n" -f [DateTime]::UtcNow, $Message), [System.Text.Encoding]::UTF8)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\StartupTrace.ps1:13' -Severity Debug }

			$null = $_
		}
	}.GetNewClosure()
