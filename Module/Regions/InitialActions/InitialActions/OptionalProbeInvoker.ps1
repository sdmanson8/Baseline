$InvokeOptionalProbe = {
			param([scriptblock]$ScriptBlock)

			try
			{
				& $ScriptBlock
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\InitialActions\InitialActions\OptionalProbeInvoker.ps1:8' -Severity Debug }

				$null
			}
		}
