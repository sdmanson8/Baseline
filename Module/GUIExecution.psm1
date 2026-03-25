using module .\Logging.psm1
using module .\SharedHelpers.psm1

function Start-GuiExecutionWorker
{
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$RunState,

		[Parameter(Mandatory = $true)]
		[object[]]$TweakList,

		[Parameter(Mandatory = $true)]
		[ValidateSet('Run', 'Defaults')]
		[string]$Mode,

		[Parameter(Mandatory = $true)]
		[string]$LoaderPath,

		[Parameter(Mandatory = $true)]
		[string]$LocalizationDirectory,

		[Parameter(Mandatory = $true)]
		[string]$UICulture,

		[Parameter(Mandatory = $true)]
		[string]$LogFilePath
	)

	$bgRunspace = [runspacefactory]::CreateRunspace()
	$bgRunspace.ApartmentState = 'STA'
	$bgRunspace.ThreadOptions = 'ReuseThread'
	$bgRunspace.Open()
	$bgRunspace.SessionStateProxy.SetVariable('runState', $RunState)
	$bgRunspace.SessionStateProxy.SetVariable('tweakList', @($TweakList))
	$bgRunspace.SessionStateProxy.SetVariable('executionMode', $Mode)
	$bgRunspace.SessionStateProxy.SetVariable('bgLoaderPath', $LoaderPath)
	$bgRunspace.SessionStateProxy.SetVariable('bgLocDir', $LocalizationDirectory)
	$bgRunspace.SessionStateProxy.SetVariable('bgUICulture', $UICulture)
	$bgRunspace.SessionStateProxy.SetVariable('bgLogFilePath', $LogFilePath)
	$bgRunspace.SessionStateProxy.SetVariable('GUIRunState', $RunState['LogQueue'])

	$worker = [powershell]::Create().AddScript({
		try
		{
			$Global:GUIMode = $true
			$Script:RunState = $runState

			try
			{
				Import-LocalizedData -BindingVariable Global:Localization -UICulture $bgUICulture -BaseDirectory $bgLocDir -FileName Win10_11Util -ErrorAction Stop
			}
			catch
			{
				Import-LocalizedData -BindingVariable Global:Localization -UICulture en-US -BaseDirectory $bgLocDir -FileName Win10_11Util
			}

			Import-Module $bgLoaderPath -Force -Global -ErrorAction Stop
			$global:LogFilePath = $bgLogFilePath
			Set-LogFile -Path $bgLogFilePath
			Set-UILogHandler { param($entry) $Script:RunState['LogQueue'].Enqueue($entry) }

			$missingFunctions = @(
				$tweakList |
					ForEach-Object { $_.Function } |
					Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
					Select-Object -Unique |
					Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) }
			)
			if ($missingFunctions.Count -gt 0)
			{
				throw ("Required tweak functions were not loaded: {0}" -f ($missingFunctions -join ', '))
			}

			foreach ($tweak in $tweakList)
			{
				while ($Script:RunState['Paused'] -and -not $Script:RunState['AbortRequested'])
				{
					Start-Sleep -Milliseconds 250
				}

				if ($Script:RunState['AbortRequested'])
				{
					$Script:RunState['AbortedRun'] = $true
					break
				}

				$Script:RunState['CurrentTweak'] = $tweak.Name
				$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
					Kind = '_TweakStarted'
					Key = $tweak.Key
					Name = $tweak.Name
				})

				$tweakErrorBaseline = if ($Global:Error) { $Global:Error.Count } else { 0 }
				$tweakErrorMessage = $null
				$tweakFailed = $false

				try
				{
					$tweakCommand = Get-Command -Name $tweak.Function -ErrorAction SilentlyContinue
					if (-not $tweakCommand)
					{
						throw "The tweak function '$($tweak.Function)' is not available in the current session."
					}

					switch ($tweak.Type)
					{
						'Toggle'
						{
							$splat = @{ $tweak.OnParam = $true }
							& $tweakCommand @splat
						}
						'Choice'
						{
							$splat = @{ $tweak.Value = $true }
							if ($tweak.ExtraArgs)
							{
								$tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $splat[$_.Key] = $_.Value }
							}
							& $tweakCommand @splat
						}
						'Action'
						{
							if ($tweak.ExtraArgs)
							{
								$argSplat = $tweak.ExtraArgs
								& $tweakCommand @argSplat
							}
							else
							{
								& $tweakCommand
							}
						}
					}
				}
				catch
				{
					$tweakFailed = $true
					$tweakErrorMessage = $_.Exception.Message
				}

				if (-not $tweakFailed)
				{
					$newErrors = @(Get-NewUnhandledErrorRecords -BaselineCount $tweakErrorBaseline)
					if ($newErrors.Count -gt 0)
					{
						$tweakFailed = $true
						$tweakErrorMessage = $newErrors[0].Exception.Message
					}
				}

				if (-not $tweakFailed)
				{
					$Script:RunState['AppliedFunctions'].Add($tweak.Function)
					$Script:RunState['CompletedCount'] = [int]$Script:RunState['CompletedCount'] + 1
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakCompleted'
						Key = $tweak.Key
						Name = $tweak.Name
						Status = 'success'
						Count = $Script:RunState['CompletedCount']
					})
				}
				else
				{
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakFailed'
						Key = $tweak.Key
						Name = $tweak.Name
						Error = $tweakErrorMessage
					})
					$Script:RunState['ErrorCount'] = [int]$Script:RunState['ErrorCount'] + 1
					$Script:RunState['CompletedCount'] = [int]$Script:RunState['CompletedCount'] + 1
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakCompleted'
						Key = $tweak.Key
						Name = $tweak.Name
						Status = 'failed'
						Count = $Script:RunState['CompletedCount']
					})
				}
			}

			if (-not $Script:RunState['AbortedRun'])
			{
				PostActions
				Errors
			}
			else
			{
				LogWarning "$executionMode execution aborted by user before all selected tweaks finished."
			}

			Stop-Foreground
		}
		catch
		{
			$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
				Kind = '_RunError'
				Error = $_.Exception.Message
			})
		}
		finally
		{
			$Script:RunState['Done'] = $true
		}
	})

	$worker.Runspace = $bgRunspace
	$asyncResult = $worker.BeginInvoke()

	return [pscustomobject]@{
		PowerShell = $worker
		AsyncResult = $asyncResult
		Runspace = $bgRunspace
	}
}

function Request-GuiExecutionWorkerStop
{
	param (
		[Parameter(Mandatory = $true)]
		$PowerShellInstance
	)

	if (-not $PowerShellInstance)
	{
		return
	}

	[System.Threading.ThreadPool]::QueueUserWorkItem(
		[System.Threading.WaitCallback]{
			param($state)
			try
			{
				if ($state)
				{
					$state.Stop()
				}
			}
			catch
			{
				$null = $_
			}
		},
		$PowerShellInstance
	) | Out-Null
}

function Stop-GuiExecutionWorkerAsync
{
	param (
		[Parameter(Mandatory = $true)]
		$Worker
	)

	if (-not $Worker)
	{
		return
	}

	[System.Threading.ThreadPool]::QueueUserWorkItem(
		[System.Threading.WaitCallback]{
			param($state)

			if (-not $state)
			{
				return
			}

			try
			{
				if ($state.PowerShell)
				{
					$state.PowerShell.Stop()
				}
			}
			catch
			{
				$null = $_
			}

			try
			{
				if ($state.PowerShell -and $state.AsyncResult)
				{
					$state.PowerShell.EndInvoke($state.AsyncResult)
				}
			}
			catch
			{
				$null = $_
			}

			try
			{
				if ($state.PowerShell)
				{
					$state.PowerShell.Dispose()
				}
			}
			catch
			{
				$null = $_
			}

			try
			{
				if ($state.Runspace)
				{
					$state.Runspace.Close()
					$state.Runspace.Dispose()
				}
			}
			catch
			{
				$null = $_
			}
		},
		$Worker
	) | Out-Null
}

function Complete-GuiExecutionWorker
{
	param (
		[Parameter(Mandatory = $true)]
		$Worker
	)

	if (-not $Worker)
	{
		return
	}

	try
	{
		if ($Worker.PowerShell -and $Worker.AsyncResult)
		{
			$Worker.PowerShell.EndInvoke($Worker.AsyncResult)
		}
	}
	catch
	{
		$null = $_
	}

	try
	{
		if ($Worker.PowerShell)
		{
			$Worker.PowerShell.Dispose()
		}
	}
	catch
	{
		$null = $_
	}

	try
	{
		if ($Worker.Runspace)
		{
			$Worker.Runspace.Close()
			$Worker.Runspace.Dispose()
		}
	}
	catch
	{
		$null = $_
	}
}

Export-ModuleMember -Function @(
	'Start-GuiExecutionWorker'
	'Request-GuiExecutionWorkerStop'
	'Stop-GuiExecutionWorkerAsync'
	'Complete-GuiExecutionWorker'
)
