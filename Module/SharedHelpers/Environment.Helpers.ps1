
# Shared helpers for Baseline.

<#
    .SYNOPSIS
#>

function Initialize-ForegroundWindowInterop
{
	<# .SYNOPSIS Loads the WinAPI.ForegroundWindow P/Invoke type definition. #>
	if (-not ("WinAPI.ForegroundWindow" -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class ForegroundWindow
	{
		[DllImport("user32.dll")]
		public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool SetForegroundWindow(IntPtr hWnd);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
	}
}
"@ -ErrorAction Stop | Out-Null
	}
}

<#
    .SYNOPSIS
#>

function Initialize-ConsoleWindowInterop
{
	<# .SYNOPSIS Loads the WinAPI.ConsoleWindow P/Invoke type definition. #>
	if (-not ("WinAPI.ConsoleWindow" -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class ConsoleWindow
	{
		[DllImport("kernel32.dll")]
		public static extern IntPtr GetConsoleWindow();

		[DllImport("user32.dll")]
		public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
	}
}
"@ -ErrorAction Stop | Out-Null
	}
}

<#
    .SYNOPSIS
#>

function Get-ConsoleHandle
{
	<# .SYNOPSIS Returns the console window handle via kernel32 P/Invoke. #>
	Initialize-ConsoleWindowInterop
	return [WinAPI.ConsoleWindow]::GetConsoleWindow()
}

function Hide-ConsoleWindow
{
	<# .SYNOPSIS Hides the console window using ShowWindow(SW_HIDE). #>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$hwnd = Get-ConsoleHandle
	if ($hwnd -ne [System.IntPtr]::Zero)
	{
		[WinAPI.ConsoleWindow]::ShowWindow($hwnd, 0 <# SW_HIDE #>) | Out-Null
	}
}

<#
    .SYNOPSIS
#>

function Show-ConsoleWindow
{
	<# .SYNOPSIS Shows and restores the console window using ShowWindow(SW_RESTORE). #>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$hwnd = Get-ConsoleHandle
	if ($hwnd -ne [System.IntPtr]::Zero)
	{
		[WinAPI.ConsoleWindow]::ShowWindow($hwnd, 9 <# SW_RESTORE #>) | Out-Null
	}
}

function Test-InteractiveHost
{
	<# .SYNOPSIS Tests whether the current PowerShell host supports interactive UI. #>
	try
	{
		if ($null -eq $Host -or $null -eq $Host.UI)
		{
			return $false
		}

		$null = $Host.UI.RawUI
		return $true
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Test-InteractiveHost:catch119' -Severity Debug }

		return $false
	}
}

<#
    .SYNOPSIS
#>

function Write-EnvironmentLaunchTrace
{
	<# .SYNOPSIS Writes environment-helper startup diagnostics to the launcher trace. #>
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]
		$Message
	)

	try
	{
		if ([string]::IsNullOrWhiteSpace([string]$Message)) { return }
		$traceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
		if (-not [System.IO.Directory]::Exists($traceDirectory))
		{
			[void][System.IO.Directory]::CreateDirectory($traceDirectory)
		}
		$tracePath = Join-Path $traceDirectory 'Baseline-launch-trace.txt'
		$traceBytes = [System.Text.Encoding]::UTF8.GetBytes(("{0:o} {1}`r`n" -f [DateTime]::UtcNow, [string]$Message))
		$traceStream = [System.IO.FileStream]::new($tracePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
		try { $traceStream.Write($traceBytes, 0, $traceBytes.Length) }
		finally { $traceStream.Dispose() }
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Write-EnvironmentLaunchTrace:catch153' -Severity Debug }

		$null = $_
	}
}

<#
    .SYNOPSIS
#>

function Write-EnvironmentSwallowedException
{
	<# .SYNOPSIS Routes swallowed environment-helper exceptions without requiring the logging module to be in scope. #>
	param(
		[Parameter(Mandatory = $false)]
		[object]
		$ErrorRecord,

		[Parameter(Mandatory = $true)]
		[string]
		$Source
	)

	try
	{
		$debugWriter = $ExecutionContext.SessionState.InvokeCommand.GetCommand('Write-SwallowedException', [System.Management.Automation.CommandTypes]::Function)
		if ($debugWriter)
		{
			& $debugWriter -ErrorRecord $ErrorRecord -Source $Source
			return
		}

		$message = if ($ErrorRecord -and $ErrorRecord.Exception) { [string]$ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
		if (-not [string]::IsNullOrWhiteSpace($message))
		{
			Write-EnvironmentLaunchTrace ("{0}: {1}" -f $Source, $message)
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Write-EnvironmentSwallowedException:catch191' -Severity Debug }

		$null = $_
	}
}

<#
    .SYNOPSIS
#>

function ConvertFrom-EnvironmentPowerShellDataFileAst
{
	<# .SYNOPSIS Converts supported constant PowerShell data-file AST nodes to .NET values. #>
	param(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.Language.Ast]
		$Ast
	)

	if ($Ast -is [System.Management.Automation.Language.HashtableAst])
	{
		$result = @{}
		foreach ($pair in $Ast.KeyValuePairs)
		{
			$key = ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $pair.Item1
			if ([string]::IsNullOrWhiteSpace([string]$key))
			{
				throw 'PowerShell data file contains an empty hashtable key.'
			}

			$result[[string]$key] = ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $pair.Item2
		}

		return $result
	}

	if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst])
	{
		return ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $Ast.Expression
	}

	if ($Ast -is [System.Management.Automation.Language.PipelineAst])
	{
		if (@($Ast.PipelineElements).Count -ne 1)
		{
			throw 'PowerShell data file pipelines must contain exactly one constant expression.'
		}

		return ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $Ast.PipelineElements[0]
	}

	if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst])
	{
		return $Ast.Value
	}

	if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst])
	{
		return $Ast.Value
	}

	if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst])
	{
		switch -Exact ($Ast.VariablePath.UserPath)
		{
			'true'  { return $true }
			'false' { return $false }
			'null'  { return $null }
			default { throw ("PowerShell data file contains unsupported variable expression: {0}" -f $Ast.Extent.Text) }
		}
	}

	if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst])
	{
		$values = foreach ($element in $Ast.Elements)
		{
			ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $element
		}

		return @($values)
	}

	if ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst])
	{
		$values = foreach ($statement in $Ast.SubExpression.Statements)
		{
			ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $statement
		}

		return @($values)
	}

	if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst])
	{
		return ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $Ast.Pipeline
	}

	throw ("PowerShell data file contains unsupported expression: {0}" -f $Ast.Extent.Text)
}

<#
    .SYNOPSIS
#>

function Import-EnvironmentPowerShellDataFile
{
	<# .SYNOPSIS Imports a constant PowerShell data file on Windows PowerShell 5.1. #>
	param(
		[Parameter(Mandatory = $true)]
		[string]
		$Path
	)

	$tokens = $null
	$errors = $null
	$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
	if ($errors -and @($errors).Count -gt 0)
	{
		throw ("PowerShell data file parse failed: {0}" -f [string]$errors[0].Message)
	}

	if (-not $ast.EndBlock -or @($ast.EndBlock.Statements).Count -ne 1)
	{
		throw 'PowerShell data file must contain exactly one hashtable.'
	}

	$data = ConvertFrom-EnvironmentPowerShellDataFileAst -Ast $ast.EndBlock.Statements[0]
	if ($data -isnot [hashtable])
	{
		throw 'PowerShell data file root must be a hashtable.'
	}

	return $data
}

<#
    .SYNOPSIS
#>

function Initialize-WpfWindowForeground
{
	<# .SYNOPSIS Prepares a WPF window for normal display without forcing foreground focus. #>
	param
	(
		[Parameter(Mandatory = $true)]
		$Window
	)

	if (-not $Window) { return }

	try
	{
		if ($Window.WindowState -eq [System.Windows.WindowState]::Minimized)
		{
			$Window.WindowState = [System.Windows.WindowState]::Normal
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Initialize-WpfWindowForeground:catch348' -Severity Debug }

		# Ignore if the supplied object is not a WPF Window.
	}
}

<#
    .SYNOPSIS
#>

function Get-WindowsVersionData
{
	<# .SYNOPSIS Retrieves Windows version details from the registry (build, UBR, display version). #>
	$CurrentVersion = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
	$CurrentBuild = [string]$CurrentVersion.CurrentBuild
	$DisplayVersion = [string]$CurrentVersion.DisplayVersion
	$ProductName = [string]$CurrentVersion.ProductName
	$InstallationType = [string]$CurrentVersion.InstallationType
	$UBR = 0
	$IsWindowsServer = $false

	if ([string]::IsNullOrWhiteSpace($CurrentBuild))
	{
		$CurrentBuild = [string]$CurrentVersion.CurrentBuildNumber
	}

	if ([string]::IsNullOrWhiteSpace($DisplayVersion))
	{
		$DisplayVersion = [string]$CurrentVersion.ReleaseId
	}

	if ($null -ne $CurrentVersion.UBR)
	{
		$UBR = [int]$CurrentVersion.UBR
	}

	if (-not [string]::IsNullOrWhiteSpace($InstallationType))
	{
		$IsWindowsServer = $InstallationType -match "Server"
	}
	elseif (-not [string]::IsNullOrWhiteSpace($ProductName))
	{
		$IsWindowsServer = $ProductName -match "Server"
	}

	$buildNumber = 0
	if (-not [int]::TryParse([string]$CurrentBuild, [ref]$buildNumber)) { $buildNumber = 0 }

	[pscustomobject]@{
		IsWindows11      = ($buildNumber -ge 22000)
		IsWindowsServer  = $IsWindowsServer
		CurrentBuild     = $buildNumber
		UBR              = $UBR
		DisplayVersion   = $DisplayVersion
		ProductName      = $ProductName
		InstallationType = $InstallationType
	}
}

<#
    .SYNOPSIS
#>

function Get-OSInfo
{
	<# .SYNOPSIS Returns a summary object with OS name, build, UBR, and version data. #>
	$VersionData = Get-WindowsVersionData
	$OSName = if ($VersionData.IsWindowsServer)
	{
		if ([string]::IsNullOrWhiteSpace($VersionData.ProductName))
		{
			"Windows Server"
		}
		else
		{
			$VersionData.ProductName
		}
	}
	elseif ($VersionData.IsWindows11)
	{
		"Windows 11"
	}
	else
	{
		"Windows 10"
	}

	[pscustomobject]@{
		IsWindows11      = $VersionData.IsWindows11
		IsWindowsServer  = $VersionData.IsWindowsServer
		OSName           = $OSName
		CurrentBuild     = $VersionData.CurrentBuild
		UBR              = $VersionData.UBR
		DisplayVersion   = $VersionData.DisplayVersion
		ProductName      = $VersionData.ProductName
		InstallationType = $VersionData.InstallationType
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineValidationMatrixSummary
{
	[CmdletBinding()]
	param (
		[string]$RepoRoot = $null
	)

	$resolvedRepoRoot = $RepoRoot
	if ([string]::IsNullOrWhiteSpace($resolvedRepoRoot))
	{
		if ($Script:SharedHelpersRepoRoot)
		{
			$resolvedRepoRoot = [string]$Script:SharedHelpersRepoRoot
		}
		elseif ($PSScriptRoot)
		{
			$resolvedRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
		}
	}

	$matrixPath = if (-not [string]::IsNullOrWhiteSpace($resolvedRepoRoot)) { Join-Path $resolvedRepoRoot 'Tests/Integration/DesktopMatrixResults.json' } else { $null }
	$summary = [ordered]@{
		SourcePath                 = $matrixPath
		ValidatedDesktopEditions    = @()
		PendingDesktopEditions      = @()
		ServerEditions              = @()
		Summary                    = 'Unavailable'
		ServerValidationSummary    = 'Unavailable'
		ServerCoverageStatus       = 'Unavailable'
		HasServerCoverage          = $false
		ServerCIOnly               = $false
	}

	if ($matrixPath -and (Test-Path -LiteralPath $matrixPath))
	{
		try
		{
			$matrixJson = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
			$validated = @($matrixJson.summary.testedDesktopEditions)
			$pending = @($matrixJson.summary.pendingDesktopEditions)
			$server = @($matrixJson.summary.serverEditions)
			$serverCount = @($server).Count
			$serverCIOnly = $serverCount -gt 0 -and (@($server | Where-Object { [string]$_ -match '(?i)\bCI only\b' }).Count -eq $serverCount)

			$summary.ValidatedDesktopEditions = @($validated)
			$summary.PendingDesktopEditions = @($pending)
			$summary.ServerEditions = @($server)
			$summary.HasServerCoverage = ($serverCount -gt 0)
			$summary.ServerCIOnly = $serverCIOnly
			$summary.ServerCoverageStatus = if ($serverCount -gt 0) { if ($serverCIOnly) { 'CIOnly' } else { 'Validated' } } else { 'Unavailable' }
			$summary.ServerValidationSummary = if ($serverCount -gt 0) {
				$serverText = if ($server.Count -gt 0) { $server -join ', ' } else { 'none' }
				if ($serverCIOnly)
				{
					('CI only: {0}' -f $serverText)
				}
				else
				{
					('Validated outside CI: {0}' -f $serverText)
				}
			}
			else
			{
				'No server editions recorded'
			}
			$summary.Summary = @(
				('Validated: {0}' -f ($(if ($validated.Count -gt 0) { $validated -join ', ' } else { 'none' }))),
				('Pending: {0}' -f ($(if ($pending.Count -gt 0) { $pending -join ', ' } else { 'none' }))),
				('Server: {0}' -f ($(if ($server.Count -gt 0) { $server -join ', ' } else { 'none' })))
			) -join ' | '
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineValidationMatrixSummary:catch522' -Severity Debug }

			$summary.Summary = 'Unavailable'
			$summary.ServerValidationSummary = 'Unavailable'
			$summary.ServerCoverageStatus = 'Unavailable'
			$summary.HasServerCoverage = $false
			$summary.ServerCIOnly = $false
		}
	}

	[pscustomobject]$summary
}

<#
    .SYNOPSIS
#>

function Get-BaselineValidationEvidenceReport
{
	[CmdletBinding()]
	param (
		[string]$RepoRoot = $null
	)

	$resolvedRepoRoot = $RepoRoot
	if ([string]::IsNullOrWhiteSpace($resolvedRepoRoot))
	{
		if ($Script:SharedHelpersRepoRoot)
		{
			$resolvedRepoRoot = [string]$Script:SharedHelpersRepoRoot
		}
		elseif ($PSScriptRoot)
		{
			$resolvedRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
		}
	}

	$testReportPath = if (-not [string]::IsNullOrWhiteSpace($resolvedRepoRoot)) { Join-Path $resolvedRepoRoot 'Tests/TestReport.json' } else { $null }
	$matrixPath = if (-not [string]::IsNullOrWhiteSpace($resolvedRepoRoot)) { Join-Path $resolvedRepoRoot 'Tests/Integration/DesktopMatrixResults.json' } else { $null }
	$report = [ordered]@{
		Schema = 'Baseline.ValidationEvidence'
		SchemaVersion = 1
		GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
		SourcePath = [ordered]@{
			RepoRoot = $resolvedRepoRoot
			TestReport = $testReportPath
			ValidationMatrix = $matrixPath
		}
		Build = [ordered]@{
			BaselineVersion = $null
			TestReportGeneratedAt = $null
			TestPlatform = $null
			TestPowerShell = $null
		}
		ValidationChannels = @()
		Summary = 'Unavailable'
	}

	$channelRows = [System.Collections.Generic.List[pscustomobject]]::new()
	$summaryParts = [System.Collections.Generic.List[string]]::new()

	$baselineVersion = $null
	if (Get-Command -Name 'Get-BaselineDisplayVersion' -ErrorAction SilentlyContinue)
	{
		try { $baselineVersion = Get-BaselineDisplayVersion } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineValidationEvidenceReport:catch586' -Severity Debug }
		 $baselineVersion = $null }
	}
	if (-not [string]::IsNullOrWhiteSpace([string]$baselineVersion))
	{
		$report.Build.BaselineVersion = [string]$baselineVersion
	}

	if ($testReportPath -and (Test-Path -LiteralPath $testReportPath))
	{
		try
		{
			$testReport = Get-Content -LiteralPath $testReportPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
			if ($testReport.PSObject.Properties['generated'])
			{
				$report.Build.TestReportGeneratedAt = [string]$testReport.generated
			}
			if ($testReport.PSObject.Properties['platform'])
			{
				$platform = $testReport.platform
				if ($platform.PSObject.Properties['os'])
				{
					$report.Build.TestPlatform = [string]$platform.os
				}
				if ($platform.PSObject.Properties['psVersion'])
				{
					$report.Build.TestPowerShell = [string]$platform.psVersion
				}
			}

			$unitLayer = $null
			$compositionLayer = $null
			if ($testReport.PSObject.Properties['layers'])
			{
				$layers = $testReport.layers
				if ($layers.PSObject.Properties['unit']) { $unitLayer = $layers.unit }
				if ($layers.PSObject.Properties['composition']) { $compositionLayer = $layers.composition }
			}

			if ($unitLayer)
			{
				$unitResult = if ($unitLayer.PSObject.Properties['result']) { [string]$unitLayer.result } else { 'Unknown' }
				$unitPassed = if ($unitLayer.PSObject.Properties['passed']) { [int]$unitLayer.passed } else { 0 }
				$unitFailed = if ($unitLayer.PSObject.Properties['failed']) { [int]$unitLayer.failed } else { 0 }
				$unitSkipped = if ($unitLayer.PSObject.Properties['skipped']) { [int]$unitLayer.skipped } else { 0 }
				$channelRows.Add([pscustomobject]@{
					Channel = 'unit-tested'
					Status = $unitResult
					Source = $testReportPath
					Detail = ('Unit layer result: {0} (passed {1}, failed {2}, skipped {3})' -f $unitResult, $unitPassed, $unitFailed, $unitSkipped)
				})
				if ($unitResult -eq 'Passed')
				{
					[void]$summaryParts.Add('unit-tested')
				}
			}

			if ($compositionLayer)
			{
				$compositionResult = if ($compositionLayer.PSObject.Properties['result']) { [string]$compositionLayer.result } else { 'Unknown' }
				$compositionPassed = if ($compositionLayer.PSObject.Properties['passed']) { [int]$compositionLayer.passed } else { 0 }
				$compositionFailed = if ($compositionLayer.PSObject.Properties['failed']) { [int]$compositionLayer.failed } else { 0 }
				$channelRows.Add([pscustomobject]@{
					Channel = 'desktop-session CI validated'
					Status = $compositionResult
					Source = $testReportPath
					Detail = ('Desktop-session layer result: {0} (passed {1}, failed {2})' -f $compositionResult, $compositionPassed, $compositionFailed)
				})
				if ($compositionResult -eq 'Passed')
				{
					[void]$summaryParts.Add('desktop-session CI validated')
				}
			}

			$manualChannel = $null
			if ($testReport.PSObject.Properties['validationChannel'] -and -not [string]::IsNullOrWhiteSpace([string]$testReport.validationChannel))
			{
				$manualChannel = [string]$testReport.validationChannel
			}
			elseif ($testReport.PSObject.Properties['manualValidation'])
			{
				$manualValidationValue = $testReport.manualValidation
				if (($manualValidationValue -is [bool] -and $manualValidationValue) -or ($manualValidationValue -isnot [bool] -and -not [string]::IsNullOrWhiteSpace([string]$manualValidationValue)))
				{
					$manualChannel = 'manually validated'
				}
			}
			elseif ($testReport.PSObject.Properties['summary'] -and $testReport.summary.PSObject.Properties['validationChannel'] -and -not [string]::IsNullOrWhiteSpace([string]$testReport.summary.validationChannel))
			{
				$manualChannel = [string]$testReport.summary.validationChannel
			}

			if (-not [string]::IsNullOrWhiteSpace($manualChannel))
			{
				$normalizedManualChannel = [string]$manualChannel.Trim()
				$channelRows.Add([pscustomobject]@{
					Channel = 'manually validated'
					Status = 'Passed'
					Source = $testReportPath
					Detail = ('Explicit validation channel recorded: {0}' -f $normalizedManualChannel)
				})
				[void]$summaryParts.Add('manually validated')
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineValidationEvidenceReport:catch689' -Severity Debug }

			# Keep the report deterministic when the test report cannot be parsed.
		}
	}

	$matrix = $null
	if (Get-Command -Name 'Get-BaselineValidationMatrixSummary' -ErrorAction SilentlyContinue)
	{
		try { $matrix = Get-BaselineValidationMatrixSummary -RepoRoot $resolvedRepoRoot } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineValidationEvidenceReport:catch698' -Severity Debug }
		 $matrix = $null }
	}
	if ($matrix)
	{
		$channelRows.Add([pscustomobject]@{
			Channel = 'server CI only'
			Status = if ($matrix.HasServerCoverage) { if ($matrix.ServerCIOnly) { 'CI only' } else { 'Outside CI' } } else { 'Unavailable' }
			Source = $matrix.SourcePath
			Detail = [string]$matrix.ServerValidationSummary
		})
		if ($matrix.HasServerCoverage -and $matrix.ServerCIOnly)
		{
			[void]$summaryParts.Add('server CI only')
		}
	}

	$report.ValidationChannels = @($channelRows)
	if ($summaryParts.Count -gt 0)
	{
		$report.Summary = ($summaryParts -join '; ')
	}

	[pscustomobject]$report
}

<#
    .SYNOPSIS
#>

function ConvertTo-WindowsDisplayVersionComparable
{
	<# .SYNOPSIS Converts a display version string (e.g. 23H2) to a sortable integer. #>
	param
	(
		[string]
		$DisplayVersion
	)

	if ([string]::IsNullOrWhiteSpace($DisplayVersion))
	{
		return $null
	}

	if ($DisplayVersion -match '^(?<Year>\d{2})H(?<Half>\d)$')
	{
		return ([int]$Matches.Year * 10) + [int]$Matches.Half
	}

	return $null
}

<#
    .SYNOPSIS
#>

function Test-Windows11FeatureBranchSupport
{
	<# .SYNOPSIS Tests whether Windows 11 meets the feature branch threshold. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[hashtable[]]
		$Thresholds
	)

	$VersionData = Get-WindowsVersionData
	if (-not $VersionData.IsWindows11)
	{
		return $false
	}

	$ParsedThresholds = $Thresholds | ForEach-Object {
		[pscustomobject]@{
			DisplayVersion = [string]$_.DisplayVersion
			Build          = [int]$_.Build
			UBR            = if ($null -ne $_.UBR) { [int]$_.UBR } else { 0 }
		}
	} | Sort-Object Build, UBR

	if (-not $ParsedThresholds)
	{
		return $false
	}

	$ApplicableThreshold = $ParsedThresholds | Where-Object -FilterScript {
		$VersionData.CurrentBuild -ge $_.Build
	} | Select-Object -Last 1

	if (-not $ApplicableThreshold)
	{
		return $false
	}

	if ($VersionData.CurrentBuild -gt $ApplicableThreshold.Build)
	{
		return $true
	}

	return ($VersionData.UBR -ge $ApplicableThreshold.UBR)
}

<#
    .SYNOPSIS
#>

function Get-BaselineWindowsThemePreference
{
	param ()

	$personalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
	try
	{
		$themeSettings = Get-ItemProperty -LiteralPath $personalizePath -ErrorAction Stop
		foreach ($propertyName in @('AppsUseLightTheme', 'SystemUsesLightTheme'))
		{
			if ($themeSettings.PSObject.Properties[$propertyName])
			{
				if ([int]$themeSettings.$propertyName -eq 1)
				{
					return 'Light'
				}

				return 'Dark'
			}
		}
	}
	catch
	{
		Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineWindowsThemePreference.LoadTheme'
	}

	return $null
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineStartupThemePreference
{
	param (
		[string]$Preference
	)

	if ($Preference -in @('Light', 'Dark', 'System'))
	{
		return [string]$Preference
	}

	return 'System'
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineConcreteStartupThemeName
{
	param (
		[string]$Preference
	)

	$normalizedPreference = Resolve-BaselineStartupThemePreference -Preference $Preference
	if ($normalizedPreference -in @('Light', 'Dark'))
	{
		return $normalizedPreference
	}

	$windowsTheme = Get-BaselineWindowsThemePreference
	if ($windowsTheme -in @('Light', 'Dark'))
	{
		return $windowsTheme
	}

	return 'Light'
}

<#
    .SYNOPSIS
#>

function Get-BaselineStartupThemePreference
{
	param ()

	$sessionBaseDir = $null
	try
	{
		$stateRoot = [System.Environment]::GetEnvironmentVariable('BASELINE_STATE_ROOT')
		if (-not [string]::IsNullOrWhiteSpace([string]$stateRoot))
		{
			$sessionBaseDir = Join-Path $stateRoot 'Profiles'
			$userPreferencesPath = Join-Path $sessionBaseDir 'Baseline-user-prefs.json'
		}
		elseif ($env:LOCALAPPDATA)
		{
			$sessionBaseDir = Join-Path $env:LOCALAPPDATA 'Baseline\Profiles'
			$userPreferencesPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Baseline\UserState\Profiles') 'Baseline-user-prefs.json'
		}
		else
		{
			$sessionBaseDir = Join-Path $env:TEMP 'Baseline\Profiles'
			$userPreferencesPath = Join-Path $sessionBaseDir 'Baseline-user-prefs.json'
		}

		if (Test-Path -LiteralPath $userPreferencesPath -PathType Leaf)
		{
			$preferencesJson = Get-Content -LiteralPath $userPreferencesPath -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16
			if ($preferencesJson -and $preferencesJson.Values -and $preferencesJson.Values.Theme)
			{
				return (Resolve-BaselineStartupThemePreference -Preference ([string]$preferencesJson.Values.Theme))
			}
		}
	}
	catch
	{
		Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStartupThemePreference.LoadPreferences'
	}

	try
	{
		if (-not $sessionBaseDir)
		{
			if ($env:LOCALAPPDATA) { $sessionBaseDir = Join-Path $env:LOCALAPPDATA 'Baseline\Profiles' }
			else { $sessionBaseDir = Join-Path $env:TEMP 'Baseline\Profiles' }
		}

		$sessionPath = Join-Path $sessionBaseDir 'Baseline-last-session.json'
		if (Test-Path -LiteralPath $sessionPath -PathType Leaf)
		{
			$sessionJson = Get-Content -LiteralPath $sessionPath -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16
			$sessionTheme = $null
			if ($sessionJson -and $sessionJson.State -and $sessionJson.State.Theme)
			{
				$sessionTheme = [string]$sessionJson.State.Theme
			}
			elseif ($sessionJson -and $sessionJson.Theme)
			{
				$sessionTheme = [string]$sessionJson.Theme
			}

			if ($sessionTheme -in @('Light', 'Dark', 'System'))
			{
				return (Resolve-BaselineStartupThemePreference -Preference $sessionTheme)
			}
		}
	}
	catch
	{
		Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStartupThemePreference.LoadSession'
	}

	return 'System'
}

<#
    .SYNOPSIS
#>

function Get-BaselineStartupThemeName
{
	param ()

	return (Resolve-BaselineConcreteStartupThemeName -Preference (Get-BaselineStartupThemePreference))
}

<#
    .SYNOPSIS
#>

function Show-BootstrapLoadingSplash
{
	<# .SYNOPSIS Displays a loading splash window in a background runspace. #>
	[CmdletBinding()]
	[OutputType([System.Object])]
	param (
		[switch]$StartUpdatesPulse,

		[string[]]$StepOrder = @()
	)

		$__baselineExtractedPartDidReturn = $false
		$__baselineExtractedPartHasReturnValue = $false
		$__baselineExtractedPartReturnValue = $null
		. (Join-Path $PSScriptRoot 'Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1')
		if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }
}

<#
    .SYNOPSIS
#>

function Get-BaselineSplashProgressWidth
{
	<# .SYNOPSIS Returns the splash progress bar width in device-independent pixels. #>
	param(
		[Parameter(Mandatory = $true)]
		[object]
		$ProgressBar
	)

	$width = 0.0
	try
	{
		$width = [double]$ProgressBar.ActualWidth
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineSplashProgressWidth:catch1002' -Severity Debug }

		$width = 0.0
	}

	if ([double]::IsNaN($width) -or $width -le 0)
	{
		try
		{
			$width = [double]$ProgressBar.Width
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineSplashProgressWidth:catch1013' -Severity Debug }

			$width = 0.0
		}
	}

	if ([double]::IsNaN($width) -or $width -le 0)
	{
		$width = 330.0
	}

	return $width
}

<#
    .SYNOPSIS
#>

function Initialize-BaselineProcessIdentity
{
	<# .SYNOPSIS Applies a Baseline app identity to the current process for shell chrome. #>
	[CmdletBinding()]
	param(
		[string]$AppUserModelId = 'sdmanson8.Baseline'
	)

	if ([string]::IsNullOrWhiteSpace($AppUserModelId))
	{
		return $false
	}

	try
	{
		if (-not ('WinAPI.BaselineShellIdentity' -as [type]))
		{
			Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class BaselineShellIdentity
	{
		[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
		public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
	}
}
"@ -ErrorAction Stop | Out-Null
		}

		$result = [WinAPI.BaselineShellIdentity]::SetCurrentProcessExplicitAppUserModelID($AppUserModelId)
		return ($result -ge 0)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Initialize-BaselineProcessIdentity:catch1066' -Severity Debug }

		return $false
	}
}

<#
    .SYNOPSIS
#>

function Format-BaselineDownloadStatus
{
	<# .SYNOPSIS Formats the update download status with transfer rate and remaining time. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$VersionTag,

		[Parameter(Mandatory = $true)]
		[long]$BytesReceived,

		[long]$TotalBytes = 0,

		[double]$ElapsedSeconds = 0
	)

	$speedBytesPerSecond = if ($ElapsedSeconds -gt 0)
	{
		[double]$BytesReceived / [double]$ElapsedSeconds
	}
	else
	{
		0.0
	}

	if ($TotalBytes -le 0 -or $BytesReceived -le 0 -or $speedBytesPerSecond -le 0)
	{
		return ''
	}

	$remainingBytes = [Math]::Max([long]0, ([long]$TotalBytes - [long]$BytesReceived))
	$remainingSeconds = [int][Math]::Ceiling([double]$remainingBytes / $speedBytesPerSecond)
	$downloadRate = [Math]::Round(($speedBytesPerSecond / 1MB), 2)
	$timeSpan = [TimeSpan]::FromSeconds($remainingSeconds)
	$remainingText = if ($timeSpan.TotalHours -ge 1)
	{
		'{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($timeSpan.TotalHours), $timeSpan.Minutes, $timeSpan.Seconds
	}
	else
	{
		'{0:00}:{1:00}' -f [int]$timeSpan.Minutes, $timeSpan.Seconds
	}

	return ('{0} MB/s - {1} remaining' -f $downloadRate, $remainingText)
}

function Get-BaselineUpdateAsset
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[object[]]
		$Assets,

		[Parameter(Mandatory = $false)]
		[string]
		$Name,

		[Parameter(Mandatory = $false)]
		[string]
		$Pattern
	)

	foreach ($asset in @($Assets))
	{
		if ($null -eq $asset)
		{
			continue
		}

		$assetName = [string]$asset.name
		if (-not [string]::IsNullOrWhiteSpace($Name) -and $assetName -eq $Name)
		{
			return $asset
		}

		if (-not [string]::IsNullOrWhiteSpace($Pattern) -and $assetName -like $Pattern)
		{
			return $asset
		}
	}

	return $null
}

function Get-BaselineUpdateAssetPattern
{
	[CmdletBinding()]
	param (
		[string]$Branch
	)

	$normalizedBranch = if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue)
	{
		ConvertTo-BaselineUpdateBranch -Branch $Branch
	}
	else
	{
		[string]$Branch
	}

	if ([string]::Equals($normalizedBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase))
	{
		return 'Baseline-*-beta.zip'
	}

	return 'Baseline-*-stable.zip'
}

function Get-BaselineUpdateFileSha256
{
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[string]
		$Path
	)

	if (Get-Command -Name 'Get-FileHash' -ErrorAction SilentlyContinue)
	{
		return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
	}

	$stream = [System.IO.File]::OpenRead($Path)
	try
	{
		$sha256 = [System.Security.Cryptography.SHA256]::Create()
		try
		{
			$hashBytes = $sha256.ComputeHash($stream)
		}
		finally
		{
			$sha256.Dispose()
		}
	}
	finally
	{
		$stream.Dispose()
	}

	return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToUpperInvariant()
}

function Get-BaselineUpdateManifestFileHash
{
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[object]
		$Manifest,

		[Parameter(Mandatory = $true)]
		[string]
		$Name
	)

	if (-not $Manifest.PSObject.Properties['files'])
	{
		return $null
	}

	$files = $Manifest.files
	if ($null -eq $files)
	{
		return $null
	}

	$property = $files.PSObject.Properties[$Name]
	if ($property)
	{
		return ([string]$property.Value).ToUpperInvariant()
	}

	$normalizedName = $Name.Replace('\', '/')
	foreach ($entry in @($files.PSObject.Properties))
	{
		if ([string]::Equals(([string]$entry.Name).Replace('\', '/'), $normalizedName, [System.StringComparison]::OrdinalIgnoreCase))
		{
			return ([string]$entry.Value).ToUpperInvariant()
		}
	}

	return $null
}

function Assert-BaselineUpdateFileHash
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[Parameter(Mandatory = $true)]
		[object]
		$Manifest,

		[Parameter(Mandatory = $true)]
		[string]
		$Name
	)

	$expectedHash = Get-BaselineUpdateManifestFileHash -Manifest $Manifest -Name $Name
	if ([string]::IsNullOrWhiteSpace($expectedHash))
	{
		throw "Release hash manifest does not contain an entry for $Name."
	}

	$actualHash = Get-BaselineUpdateFileSha256 -Path $Path
	if (-not [string]::Equals($actualHash, $expectedHash, [System.StringComparison]::OrdinalIgnoreCase))
	{
		throw "Hash mismatch for $Name. Expected $expectedHash, got $actualHash."
	}
}

function Get-BaselineUpdateInstallMode
{
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[string]
		$ExecutablePath
	)

	$directory = [System.IO.Path]::GetFullPath((Split-Path -Path $ExecutablePath -Parent)).TrimEnd('\')
	$registeredInstallKeys = @(
		'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D5A779F1-8936-4E66-A24D-9A4E43A2A4D9}',
		'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D5A779F1-8936-4E66-A24D-9A4E43A2A4D9}_is1'
	)
	$registryRoots = @('HKEY_CURRENT_USER', 'HKEY_LOCAL_MACHINE')

	foreach ($registryRoot in $registryRoots)
	{
		foreach ($registeredInstallKey in $registeredInstallKeys)
		{
			$registryPath = 'Registry::{0}\{1}' -f $registryRoot, $registeredInstallKey
			try
			{
				$installRecord = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineUpdateInstallMode:catch1320' -Severity Debug }

				continue
			}

			$installLocation = [string]$installRecord.InstallLocation
			if ([string]::IsNullOrWhiteSpace($installLocation))
			{
				continue
			}

			$registeredDirectory = [System.IO.Path]::GetFullPath($installLocation).TrimEnd('\')
			if ([string]::Equals($directory, $registeredDirectory, [System.StringComparison]::OrdinalIgnoreCase))
			{
				return 'Install'
			}
		}
	}

	return 'Portable'
}

<#
    .SYNOPSIS
#>

function Set-BootstrapLoadingSplashState
{
	<# .SYNOPSIS Updates the bootstrap loading splash text and progress bar. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[object]
		$Splash = $null,

		[Parameter(Mandatory = $false)]
		[string]
		$StatusText = $null,

		[Parameter(Mandatory = $false)]
		[int]
		$Completed = 0,

		[Parameter(Mandatory = $false)]
		[int]
		$Total = 0,

		[Parameter(Mandatory = $false)]
		[switch]
		$Indeterminate,

		[Parameter(Mandatory = $false)]
		[switch]
		$HideProgressBar
	)

	if ($null -eq $Splash)
	{
		$loadingSplashVariable = Get-Variable -Name 'LoadingSplash' -Scope Global -ErrorAction SilentlyContinue
		if ($loadingSplashVariable)
		{
			$Splash = $loadingSplashVariable.Value
		}
	}

	if (-not $Splash)
	{
		return $false
	}

	$window = $null
	$dispatcher = $null
	$statusControl = $null
	$subActionPanel = $null
	$progressBar = $null
	$checklistProgressActive = $false

	if ($Splash -is [hashtable])
	{
		if ($Splash.ContainsKey('Window')) { $window = $Splash['Window'] }
		if ($Splash.ContainsKey('Dispatcher')) { $dispatcher = $Splash['Dispatcher'] }
		if ($Splash.ContainsKey('StatusText')) { $statusControl = $Splash['StatusText'] }
		if ($Splash.ContainsKey('SubActionPanel')) { $subActionPanel = $Splash['SubActionPanel'] }
		if ($Splash.ContainsKey('ProgressBar')) { $progressBar = $Splash['ProgressBar'] }
		if ($Splash.ContainsKey('ChecklistProgressActive')) { $checklistProgressActive = [bool]$Splash['ChecklistProgressActive'] }
	}
	else
	{
		$window = $Splash
		if ($window -and $window.PSObject.Properties['Dispatcher'])
		{
			$dispatcher = $window.Dispatcher
		}
	}

	if (-not $window -or -not $dispatcher -or $dispatcher.HasShutdownStarted)
	{
		return $false
	}

	try
	{
		$updateAction = {
			try
			{
				if (-not $statusControl -and $window)
				{
					$statusControl = $window.FindName('StatusText')
				}
				if (-not $subActionPanel -and $window)
				{
					$subActionPanel = $window.FindName('SubActionPanel')
				}
				if (-not $progressBar -and $window)
				{
					$progressBar = $window.FindName('ProgressBar')
				}

				$hasStatusText = -not [string]::IsNullOrWhiteSpace([string]$StatusText)

				if ($statusControl -and $hasStatusText)
				{
					$statusControl.Text = [string]$StatusText
				}

				if ($hasStatusText)
				{
					if ($subActionPanel)
					{
						$subActionPanel.Visibility = [System.Windows.Visibility]::Visible
					}
					elseif ($statusControl)
					{
						$statusControl.Visibility = [System.Windows.Visibility]::Visible
					}
				}
				else
				{
					if ($statusControl) { $statusControl.Text = '' }
					if ($subActionPanel)
					{
						$subActionPanel.Visibility = [System.Windows.Visibility]::Collapsed
					}
					elseif ($statusControl)
					{
						$statusControl.Visibility = [System.Windows.Visibility]::Collapsed
					}
				}

				if ($progressBar)
				{
					if ($HideProgressBar)
					{
						$progressBar.Visibility = [System.Windows.Visibility]::Collapsed
						$progressBar.IsIndeterminate = $false
						$progressBar.Value = 0
						$progressBar.Maximum = 1
					}
					else
					{
						$showProgress = [bool]$Indeterminate -or ($Total -gt 0)
						$progressBar.Visibility = if ($showProgress) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }

						if (-not $showProgress)
						{
							$progressBar.IsIndeterminate = $false
						}
						elseif ($Indeterminate -or $Total -le 0)
						{
							$progressBar.IsIndeterminate = -not $checklistProgressActive
						}
						else
						{
							$safeTotal = [Math]::Max(1, $Total)
							$safeCompleted = [Math]::Min([Math]::Max(0, $Completed), $safeTotal)
							$barWidth = Get-BaselineSplashProgressWidth -ProgressBar $progressBar
							$progressBar.IsIndeterminate = $false
							$progressBar.Maximum = $barWidth
							$progressBar.Value = [Math]::Round((($safeCompleted / $safeTotal) * $barWidth), 3)
						}
					}
				}
			}
			catch
			{
				Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.SetBootstrapLoadingSplashState.DispatcherUpdate'
			}
		}.GetNewClosure()

		$dispatcherHasCheckAccess = $false
		try { $dispatcherHasCheckAccess = ($null -ne $dispatcher.PSObject.Methods['CheckAccess']) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Set-BootstrapLoadingSplashState:catch1510' -Severity Debug }
		 $dispatcherHasCheckAccess = $false }
		if ($dispatcherHasCheckAccess -and $dispatcher.CheckAccess())
		{
			& $updateAction
		}
		else
		{
			[void]$dispatcher.Invoke([System.Action]$updateAction)
		}

		return $true
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Set-BootstrapLoadingSplashState:catch1522' -Severity Debug }

		return $false
	}
}

<#
    .SYNOPSIS
#>

function Set-BootstrapLoadingSplashStep
{
	<# .SYNOPSIS Advances a step in the bootstrap splash checklist (pending/in_progress/completed) and optionally sets its sub-action text. #>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $false)]
		[object]
		$Splash = $null,

		[Parameter(Mandatory = $true)]
		[ValidateSet('updates','system','winget','chocolatey','finalize')]
		[string]
		$StepId,

		[Parameter(Mandatory = $true)]
		[ValidateSet('pending','in_progress','completed')]
		[string]
		$Status,

		[Parameter(Mandatory = $false)]
		[AllowEmptyString()]
		[AllowNull()]
		[string]
		$SubAction
	)

	if ($null -eq $Splash)
	{
		$loadingSplashVariable = Get-Variable -Name 'LoadingSplash' -Scope Global -ErrorAction SilentlyContinue
		if ($loadingSplashVariable)
		{
			$Splash = $loadingSplashVariable.Value
		}
	}

	if (-not $Splash) { return $false }

	$window = $null
	$dispatcher = $null
	$stepGlyphs = $null
	$stepIdleDots = $null
	$stepPulseDots = $null
	$stepChecks = $null
	$stepLabels = $null
	$stepStates = $null
	$statusControl = $null
	$subActionPanel = $null
	$progressBar = $null
	$theme = $null
	$stepOrder = @('updates','system','winget','chocolatey','finalize')

		. (Join-Path $PSScriptRoot 'Environment\Set-BootstrapLoadingSplashStep\SplashControlResolution.ps1')

	if (-not $window -or -not $dispatcher -or $dispatcher.HasShutdownStarted) { return $false }
	if (-not $stepGlyphs -or -not $stepLabels -or -not $stepStates) { return $false }

	$hasSubActionArg = $PSBoundParameters.ContainsKey('SubAction')
		. (Join-Path $PSScriptRoot 'Environment\Set-BootstrapLoadingSplashStep\SplashProgressState.ps1')

		$__baselineExtractedPartDidReturn = $false
		$__baselineExtractedPartHasReturnValue = $false
		$__baselineExtractedPartReturnValue = $null
		. (Join-Path $PSScriptRoot 'Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1')
		if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }
}

<#
    .SYNOPSIS
#>

function Close-LoadingSplashWindow
{
	<# .SYNOPSIS Closes a splash window and optionally disposes background resources. #>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $false)]
		[object]
		$Splash,

		[Parameter(Mandatory = $false)]
		[switch]
		$DisposeResources,

		[Parameter(Mandatory = $false)]
		[int]
		$CloseTimeoutMilliseconds = 2000
	)

	if (-not $Splash) { return $false }

	$closeRequested = $false

	try
	{
		if ($Splash -is [hashtable])
		{
			if (-not $Splash.ContainsKey('ProgrammaticClose')) { $Splash['ProgrammaticClose'] = $false }
			$Splash['ProgrammaticClose'] = $true
			$splashDispatcher = if ($Splash.ContainsKey('Dispatcher')) { $Splash['Dispatcher'] } else { $null }
			$splashWindow = if ($Splash.ContainsKey('Window')) { $Splash['Window'] } else { $null }
			if ([bool]$Splash['IsAlive'] -and $splashDispatcher -and (-not $splashDispatcher.HasShutdownStarted))
			{
				$splashDispatcher.Invoke([System.Action]{
					if ($splashWindow)
					{
						try { $splashWindow.Hide() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.WindowHide' }
						try { $splashWindow.Close() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.WindowClose' }
					}
					$Splash['IsAlive'] = $false
				})
				$closeRequested = $true
			}
		}
		elseif ($Splash.Dispatcher -and (-not $Splash.Dispatcher.HasShutdownStarted))
		{
			$Splash.Dispatcher.Invoke([System.Action]{
				try { $Splash.Hide() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.Hide' }
				try { $Splash.Close() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.Close' }
			})
			$closeRequested = $true
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.DispatcherInvoke'
	}

	if ($DisposeResources -and $Splash -is [hashtable])
	{
		$closeDeadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max($CloseTimeoutMilliseconds, 0))
		while ([bool]$Splash['IsAlive'] -and [datetime]::UtcNow -lt $closeDeadline)
		{
			Start-Sleep -Milliseconds 50
		}

		$splashDispatcher = if ($Splash.ContainsKey('Dispatcher')) { $Splash['Dispatcher'] } else { $null }
		if ([bool]$Splash['IsAlive'] -and $splashDispatcher -and (-not $splashDispatcher.HasShutdownStarted))
		{
			try { $splashDispatcher.InvokeShutdown() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.DispatcherInvokeShutdown' }
		}

		try
		{
			$splashPowerShell = if ($Splash.ContainsKey('_PowerShell')) { $Splash['_PowerShell'] } else { $null }
			$splashAsyncResult = if ($Splash.ContainsKey('_AsyncResult')) { $Splash['_AsyncResult'] } else { $null }
			if ($splashPowerShell -and $splashAsyncResult)
			{
				$splashPowerShell.EndInvoke($splashAsyncResult)
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.EndInvoke'
		}

		try { if ($Splash.ContainsKey('_PowerShell') -and $Splash['_PowerShell']) { $Splash['_PowerShell'].Dispose() } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.PowerShellDispose' }
		try { if ($Splash.ContainsKey('_Runspace') -and $Splash['_Runspace']) { $Splash['_Runspace'].Close(); $Splash['_Runspace'].Dispose() } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.CloseLoadingSplashWindow.RunspaceDispose' }
	}

	return $closeRequested
}

<#
    .SYNOPSIS
#>

function Compare-BaselineReleaseVersions
{
	<# .SYNOPSIS Compares two Baseline release tags using semantic-version precedence. #>
	param(
		[AllowNull()]
		[string]$LeftVersion,

		[AllowNull()]
		[string]$RightVersion
	)

	$parseVersionInfo = {
		param([AllowNull()][string]$VersionText)

		if ([string]::IsNullOrWhiteSpace([string]$VersionText))
		{
			return $null
		}

		$originalText = [string]$VersionText
		$trimmedText = $originalText.Trim()
		$coreText = $trimmedText.Split('+')[0].Trim()
		$match = [regex]::Match($coreText, '\d+(?:\.\d+){1,3}')
		if (-not $match.Success)
		{
			return [pscustomobject]@{
				OriginalText      = $trimmedText
				ComparableText    = $coreText
				Parsed            = $false
				CoreVersion       = $null
				PrereleaseLabel   = $null
				PrereleaseTokens  = @()
				IsPrerelease      = $false
			}
		}

		$parts = $match.Value.Split('.')
		while ($parts.Count -lt 4)
		{
			$parts += '0'
		}
		if ($parts.Count -gt 4)
		{
			$parts = $parts[0..3]
		}

		$coreVersion = $null
		try
		{
			$coreVersion = [System.Version]($parts -join '.')
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Compare-BaselineReleaseVersions:catch1751' -Severity Debug }

			return [pscustomobject]@{
				OriginalText      = $trimmedText
				ComparableText    = $coreText
				Parsed            = $false
				CoreVersion       = $null
				PrereleaseLabel   = $null
				PrereleaseTokens  = @()
				IsPrerelease      = $false
			}
		}

		$prereleaseLabel = $coreText.Substring($match.Index + $match.Length).Trim()
		if ($prereleaseLabel -match '^\((.+)\)$')
		{
			$prereleaseLabel = [string]$Matches[1]
		}
		$prereleaseLabel = [regex]::Replace($prereleaseLabel, '^[\s\-\._\(\[\{]+', '')
		$prereleaseLabel = [regex]::Replace($prereleaseLabel, '[\s\)\]\}]+$', '')
		if ([string]::IsNullOrWhiteSpace([string]$prereleaseLabel))
		{
			$prereleaseLabel = $null
		}

		$prereleaseTokens = @()
		if ($prereleaseLabel)
		{
			$tokenMatches = [regex]::Matches($prereleaseLabel.ToLowerInvariant(), '[0-9]+|[A-Za-z]+')
			if ($tokenMatches.Count -gt 0)
			{
				$prereleaseTokens = @($tokenMatches | ForEach-Object { [string]$_.Value })
			}
			else
			{
				$prereleaseTokens = @([string]$prereleaseLabel.ToLowerInvariant())
			}
		}

		return [pscustomobject]@{
			OriginalText      = $trimmedText
			ComparableText    = $coreText
			Parsed            = $true
			CoreVersion       = $coreVersion
			PrereleaseLabel   = $prereleaseLabel
			PrereleaseTokens  = $prereleaseTokens
			IsPrerelease      = (-not [string]::IsNullOrWhiteSpace([string]$prereleaseLabel))
		}
	}

	$leftInfo = & $parseVersionInfo $LeftVersion
	$rightInfo = & $parseVersionInfo $RightVersion

	if ($null -eq $leftInfo -and $null -eq $rightInfo)
	{
		return 0
	}
	if ($null -eq $leftInfo)
	{
		return -1
	}
	if ($null -eq $rightInfo)
	{
		return 1
	}

	if (-not $leftInfo.Parsed -and -not $rightInfo.Parsed)
	{
		return [Math]::Sign([string]::Compare($leftInfo.OriginalText, $rightInfo.OriginalText, [System.StringComparison]::OrdinalIgnoreCase))
	}
	if (-not $leftInfo.Parsed)
	{
		return -1
	}
	if (-not $rightInfo.Parsed)
	{
		return 1
	}

	$coreComparison = $leftInfo.CoreVersion.CompareTo($rightInfo.CoreVersion)
	if ($coreComparison -ne 0)
	{
		return [Math]::Sign($coreComparison)
	}

	if ($leftInfo.IsPrerelease -and -not $rightInfo.IsPrerelease)
	{
		return -1
	}
	if (-not $leftInfo.IsPrerelease -and $rightInfo.IsPrerelease)
	{
		return 1
	}
	if (-not $leftInfo.IsPrerelease -and -not $rightInfo.IsPrerelease)
	{
		return 0
	}

	$maxTokenCount = [Math]::Max($leftInfo.PrereleaseTokens.Count, $rightInfo.PrereleaseTokens.Count)
	for ($index = 0; $index -lt $maxTokenCount; $index++)
	{
		if ($index -ge $leftInfo.PrereleaseTokens.Count)
		{
			return -1
		}
		if ($index -ge $rightInfo.PrereleaseTokens.Count)
		{
			return 1
		}

		$leftToken = [string]$leftInfo.PrereleaseTokens[$index]
		$rightToken = [string]$rightInfo.PrereleaseTokens[$index]
		$leftTokenIsNumber = ($leftToken -match '^\d+$')
		$rightTokenIsNumber = ($rightToken -match '^\d+$')

		if ($leftTokenIsNumber -and $rightTokenIsNumber)
		{
			$leftNumber = [int64]$leftToken
			$rightNumber = [int64]$rightToken
			if ($leftNumber -ne $rightNumber)
			{
				return [Math]::Sign($leftNumber.CompareTo($rightNumber))
			}
			continue
		}
		if ($leftTokenIsNumber -and -not $rightTokenIsNumber)
		{
			return -1
		}
		if (-not $leftTokenIsNumber -and $rightTokenIsNumber)
		{
			return 1
		}

		$tokenComparison = [string]::Compare($leftToken, $rightToken, [System.StringComparison]::OrdinalIgnoreCase)
		if ($tokenComparison -ne 0)
		{
			return [Math]::Sign($tokenComparison)
		}
	}

	return 0
}

function Get-BaselineReleaseCoreVersion
{
	[CmdletBinding()]
	[OutputType([System.Version])]
	param (
		[AllowNull()]
		[string]$VersionText
	)

	if ([string]::IsNullOrWhiteSpace([string]$VersionText))
	{
		return $null
	}

	$coreText = ([string]$VersionText).Trim().Split('+')[0].Trim()
	$match = [regex]::Match($coreText, '\d+(?:\.\d+){1,3}')
	if (-not $match.Success)
	{
		return $null
	}

	$parts = $match.Value.Split('.')
	while ($parts.Count -lt 4)
	{
		$parts += '0'
	}
	if ($parts.Count -gt 4)
	{
		$parts = $parts[0..3]
	}

	try
	{
		return [System.Version]($parts -join '.')
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineReleaseCoreVersion'
		return $null
	}
}

function Test-BaselineReleaseVersionPrerelease
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[string]$VersionText
	)

	if ([string]::IsNullOrWhiteSpace([string]$VersionText))
	{
		return $false
	}

	$coreText = ([string]$VersionText).Trim().Split('+')[0].Trim()
	$match = [regex]::Match($coreText, '\d+(?:\.\d+){1,3}')
	if (-not $match.Success)
	{
		return $false
	}

	$label = $coreText.Substring($match.Index + $match.Length).Trim()
	if ($label -match '^\((.+)\)$')
	{
		$label = [string]$Matches[1]
	}
	$label = [regex]::Replace($label, '^[\s\-\._\(\[\{]+', '')
	$label = [regex]::Replace($label, '[\s\)\]\}]+$', '')
	return (-not [string]::IsNullOrWhiteSpace([string]$label))
}

function Test-BaselineReleaseUpdateRequired
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$LatestVersion,

		[Parameter(Mandatory = $true)]
		[string]$CurrentVersion,

		[string]$UpdateBranch = 'Stable',

		[AllowNull()]
		[string]$CurrentBuildBranch
	)

	$normalizedBranch = ConvertTo-BaselineUpdateBranch -Branch $UpdateBranch
	$latestVersionIsPrerelease = Test-BaselineReleaseVersionPrerelease -VersionText $LatestVersion
	$currentVersionIsPrerelease = Test-BaselineReleaseVersionPrerelease -VersionText $CurrentVersion
	$normalizedCurrentBuildBranch = if ($currentVersionIsPrerelease)
	{
		'Beta'
	}
	elseif (-not [string]::IsNullOrWhiteSpace([string]$CurrentBuildBranch))
	{
		ConvertTo-BaselineUpdateBranch -Branch $CurrentBuildBranch
	}
	else
	{
		'Stable'
	}
	$currentBuildIsPrerelease = (
		$currentVersionIsPrerelease -or
		[string]::Equals($normalizedCurrentBuildBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase)
	)

	$comparison = Compare-BaselineReleaseVersions -LeftVersion $LatestVersion -RightVersion $CurrentVersion
	if ($comparison -gt 0)
	{
		return $true
	}

	if (-not [string]::Equals($normalizedBranch, $normalizedCurrentBuildBranch, [System.StringComparison]::OrdinalIgnoreCase))
	{
		if ([string]::Equals($normalizedBranch, 'Stable', [System.StringComparison]::OrdinalIgnoreCase))
		{
			return (-not $latestVersionIsPrerelease)
		}

		if ([string]::Equals($normalizedBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase))
		{
			return $latestVersionIsPrerelease
		}
	}

	if ([string]::Equals($normalizedBranch, 'Stable', [System.StringComparison]::OrdinalIgnoreCase))
	{
		return (
			-not $latestVersionIsPrerelease -and
			$currentBuildIsPrerelease
		)
	}

	if (-not [string]::Equals($normalizedBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase))
	{
		return $false
	}

	$latestCore = Get-BaselineReleaseCoreVersion -VersionText $LatestVersion
	$currentCore = Get-BaselineReleaseCoreVersion -VersionText $CurrentVersion
	if ($null -eq $latestCore -or $null -eq $currentCore)
	{
		return $false
	}

	return (
		$latestCore.CompareTo($currentCore) -eq 0 -and
		$latestVersionIsPrerelease -and
		-not $currentBuildIsPrerelease
	)
}

<#
    .SYNOPSIS
#>

function Get-BaselineLatestReleaseEntry
{
	<# .SYNOPSIS Selects the highest Baseline GitHub release from a release list. #>
	param(
		[AllowNull()]
		[object[]]$Releases,

		[switch]$IncludePrerelease,

		[string]$AssetPattern
	)

	$bestRelease = $null
	$bestPublishedAt = [DateTimeOffset]::MinValue

	foreach ($release in @($Releases))
	{
		if ($null -eq $release)
		{
			continue
		}

		$isDraft = $false
		try
		{
			$isDraft = [bool]$release.draft
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineLatestReleaseEntry:catch1924' -Severity Debug }

			$isDraft = $false
		}
		if ($isDraft)
		{
			continue
		}

		$isPrerelease = $false
		try
		{
			$isPrerelease = [bool]$release.prerelease
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineLatestReleaseEntry:catch1938' -Severity Debug }

			$isPrerelease = $false
		}
		if ($isPrerelease -and -not $IncludePrerelease)
		{
			continue
		}

		if (-not [string]::IsNullOrWhiteSpace($AssetPattern))
		{
			$matchingAsset = $null
			try
			{
				$matchingAsset = Get-BaselineUpdateAsset -Assets @($release.assets) -Pattern $AssetPattern
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineLatestReleaseEntry.MatchAssetPattern'
				$matchingAsset = $null
			}
			if (-not $matchingAsset)
			{
				continue
			}
		}

		$candidateTag = [string]$release.tag_name
		if ([string]::IsNullOrWhiteSpace([string]$candidateTag))
		{
			continue
		}

		$candidatePublishedAt = [DateTimeOffset]::MinValue
		foreach ($propertyName in @('published_at', 'created_at'))
		{
			$rawPublishedAt = $null
			try
			{
				if ($release.PSObject.Properties[$propertyName])
				{
					$rawPublishedAt = [string]$release.$propertyName
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineLatestReleaseEntry:catch1964' -Severity Debug }

				$rawPublishedAt = $null
			}

			if ([string]::IsNullOrWhiteSpace([string]$rawPublishedAt))
			{
				continue
			}

			try
			{
				$candidatePublishedAt = [DateTimeOffset]::Parse($rawPublishedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
				break
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineLatestReleaseEntry.ParsePublishedAt' }
		}

		if ($null -eq $bestRelease)
		{
			$bestRelease = $release
			$bestPublishedAt = $candidatePublishedAt
			continue
		}

		$comparison = Compare-BaselineReleaseVersions -LeftVersion $candidateTag -RightVersion ([string]$bestRelease.tag_name)
		if ($comparison -gt 0 -or ($comparison -eq 0 -and $candidatePublishedAt -gt $bestPublishedAt))
		{
			$bestRelease = $release
			$bestPublishedAt = $candidatePublishedAt
		}
	}

	return $bestRelease
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineLocalApplicationDataPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[AllowNull()]
		[string]$LocalAppData = $null
	)

	if ([string]::IsNullOrWhiteSpace($LocalAppData))
	{
		$LocalAppData = $env:LOCALAPPDATA
	}

	if ([string]::IsNullOrWhiteSpace($LocalAppData))
	{
		$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
	}

	return $LocalAppData
}

function Get-BaselineAutoUpdateThrottlePath
{
	<#
	.SYNOPSIS
	Returns the per-user state file used to throttle automatic startup
	update checks.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$LocalAppData = $null
	)

	$LocalAppData = Resolve-BaselineLocalApplicationDataPath -LocalAppData $LocalAppData
	if ([string]::IsNullOrWhiteSpace($LocalAppData))
	{
		throw 'LocalApplicationData is not available; cannot persist the Baseline auto-update throttle state.'
	}

	return (Join-Path (Join-Path (Join-Path $LocalAppData 'Baseline') 'UserState') 'auto-update-check.json')
}

function Get-BaselineStartupPackageManagerCheckStatePath
{
	<#
	.SYNOPSIS
	Returns the per-user state file used to schedule startup package-manager checks.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$LocalAppData = $null
	)

	$LocalAppData = Resolve-BaselineLocalApplicationDataPath -LocalAppData $LocalAppData
	if ([string]::IsNullOrWhiteSpace($LocalAppData))
	{
		throw 'LocalApplicationData is not available; cannot persist the Baseline startup package-manager check state.'
	}

	return (Join-Path (Join-Path (Join-Path $LocalAppData 'Baseline') 'UserState') 'startup-package-manager-checks.json')
}

function Get-BaselineUpdatePreferencePath
{
	<#
	.SYNOPSIS
	Returns the per-user preference file path used by the GUI settings store.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$LocalAppData = $null
	)

	$LocalAppData = Resolve-BaselineLocalApplicationDataPath -LocalAppData $LocalAppData
	if ([string]::IsNullOrWhiteSpace($LocalAppData))
	{
		throw 'LocalApplicationData is not available; cannot read Baseline update preferences.'
	}

	return (Join-Path (Join-Path (Join-Path (Join-Path $LocalAppData 'Baseline') 'UserState') 'Profiles') 'Baseline-user-prefs.json')
}

function Get-BaselineStartupPackageManagerCheckState
{
	<#
	.SYNOPSIS
	Reads the persisted timestamps used to schedule startup package-manager checks.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$Path = (Get-BaselineStartupPackageManagerCheckStatePath)
	)

	$defaultState = [pscustomobject]@{
		WinGetLastCheckedUtc = $null
		ChocolateyLastCheckedUtc = $null
	}

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path))
	{
		return $defaultState
	}

	try
	{
		$raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return $defaultState }
		$state = $raw | ConvertFrom-BaselineJson -Depth 8 -ErrorAction Stop
		$parseTimestamp = {
			param ([AllowNull()] [object]$Value)

			if ($null -eq $Value) { return $null }
			$text = ([string]$Value).Trim()
			if ([string]::IsNullOrWhiteSpace($text)) { return $null }
			$parsed = [datetime]::MinValue
			if ([datetime]::TryParse($text, [ref]$parsed))
			{
				return $parsed.ToUniversalTime()
			}
			return $null
		}

		return [pscustomobject]@{
			WinGetLastCheckedUtc = if ($state -and $state.PSObject.Properties['WinGetLastCheckedUtc']) { & $parseTimestamp $state.WinGetLastCheckedUtc } else { $null }
			ChocolateyLastCheckedUtc = if ($state -and $state.PSObject.Properties['ChocolateyLastCheckedUtc']) { & $parseTimestamp $state.ChocolateyLastCheckedUtc } else { $null }
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStartupPackageManagerCheckState'
		return $defaultState
	}
}

function Set-BaselineStartupPackageManagerCheckState
{
	<#
	.SYNOPSIS
	Updates persisted startup package-manager check timestamps.
	#>
	[CmdletBinding()]
	param (
		[switch]$WinGet,

		[switch]$Chocolatey,

		[string]$Path = (Get-BaselineStartupPackageManagerCheckStatePath),

		[datetime]$NowUtc = [DateTime]::UtcNow
	)

	if (-not ([bool]$WinGet -or [bool]$Chocolatey))
	{
		return
	}

	$directory = Split-Path -Path $Path -Parent
	if (-not (Test-Path -LiteralPath $directory))
	{
		$null = New-Item -Path $directory -ItemType Directory -Force
	}

	$existing = Get-BaselineStartupPackageManagerCheckState -Path $Path
	$payload = [ordered]@{
		Schema = 'Baseline.StartupPackageManagerChecks'
		SchemaVersion = 1
		WinGetLastCheckedUtc = if ($existing -and $existing.WinGetLastCheckedUtc) { ([datetime]$existing.WinGetLastCheckedUtc).ToUniversalTime().ToString('o') } else { $null }
		ChocolateyLastCheckedUtc = if ($existing -and $existing.ChocolateyLastCheckedUtc) { ([datetime]$existing.ChocolateyLastCheckedUtc).ToUniversalTime().ToString('o') } else { $null }
	}

	$timestamp = $NowUtc.ToUniversalTime().ToString('o')
	if ($WinGet) { $payload.WinGetLastCheckedUtc = $timestamp }
	if ($Chocolatey) { $payload.ChocolateyLastCheckedUtc = $timestamp }

	[System.IO.File]::WriteAllText($Path, ([pscustomobject]$payload | ConvertTo-Json -Depth 6), [System.Text.Encoding]::UTF8)
	try
	{
		if (Get-Command -Name 'LogDebug' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogDebug ('Startup package-manager check state persisted. Path="{0}"; WinGetUpdated={1}; ChocolateyUpdated={2}; TimestampUtc="{3}"' -f $Path, [bool]$WinGet, [bool]$Chocolatey, $timestamp)
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.SetBaselineStartupPackageManagerCheckState.LogDebug' -Severity Warning
	}
}

function Get-BaselineStartupPackageManagerCheckDecision
{
	<#
	.SYNOPSIS
	Determines whether a startup package-manager check is due.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('WinGet', 'Chocolatey')]
		[string]$PackageManager,

		[bool]$Enabled = $true,

		[string]$Frequency = 'Startup',

		[string]$Path = (Get-BaselineStartupPackageManagerCheckStatePath),

		[datetime]$NowUtc = [DateTime]::UtcNow
	)

	$normalizedFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $Frequency
	if (-not $Enabled)
	{
		try
		{
			if (Get-Command -Name 'LogDebug' -CommandType Function -ErrorAction SilentlyContinue)
			{
				LogDebug ('Startup package-manager check decision resolved. PackageManager="{0}"; Enabled=False; Frequency="{1}"; StatePath="{2}"; LastCheckedUtc=""; NextEligibleUtc=""; ShouldCheck=False; Reason="{3} startup check is disabled by user preference."' -f $PackageManager, $normalizedFrequency, $Path, $PackageManager)
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStartupPackageManagerCheckDecision.DisabledLogDebug' -Severity Warning
		}
		return [pscustomobject]@{
			PackageManager = $PackageManager
			ShouldCheck = $false
			Frequency = $normalizedFrequency
			LastCheckedUtc = $null
			NextEligibleUtc = $null
			Reason = ('{0} startup check is disabled by user preference.' -f $PackageManager)
		}
	}

	$state = Get-BaselineStartupPackageManagerCheckState -Path $Path
	$lastCheckedUtc = if ($PackageManager -eq 'Chocolatey') { $state.ChocolateyLastCheckedUtc } else { $state.WinGetLastCheckedUtc }
	$decision = Get-BaselineUpdateFrequencyDecision -Frequency $normalizedFrequency -State ([pscustomobject]@{ LastCheckedUtc = $lastCheckedUtc }) -NowUtc $NowUtc
	try
	{
		if (Get-Command -Name 'LogDebug' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogDebug ('Startup package-manager check decision resolved. PackageManager="{0}"; Enabled={1}; Frequency="{2}"; StatePath="{3}"; LastCheckedUtc="{4}"; NextEligibleUtc="{5}"; ShouldCheck={6}; Reason="{7}"' -f $PackageManager, [bool]$Enabled, $normalizedFrequency, $Path, $(if ($lastCheckedUtc) { ([datetime]$lastCheckedUtc).ToUniversalTime().ToString('o') } else { '' }), $(if ($decision.NextEligibleUtc) { ([datetime]$decision.NextEligibleUtc).ToUniversalTime().ToString('o') } else { '' }), [bool]$decision.ShouldCheck, [string]$decision.Reason)
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStartupPackageManagerCheckDecision.LogDebug' -Severity Warning
	}

	return [pscustomobject]@{
		PackageManager = $PackageManager
		ShouldCheck = [bool]$decision.ShouldCheck
		Frequency = $normalizedFrequency
		LastCheckedUtc = $lastCheckedUtc
		NextEligibleUtc = $decision.NextEligibleUtc
		Reason = [string]$decision.Reason
	}
}

function Get-BaselineStartupSplashSettings
{
	<#
	.SYNOPSIS
	Reads the GUI preferences that control startup splash work.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$PreferencePath = $null
	)

	$settings = [ordered]@{
		RunInitialActions = $true
		CheckWinGet = $true
		CheckChocolatey = $true
		WinGetCheckFrequency = 'Startup'
		ChocolateyCheckFrequency = 'Startup'
	}

	try
	{
		if ([string]::IsNullOrWhiteSpace($PreferencePath))
		{
			$PreferencePath = Get-BaselineUpdatePreferencePath
		}

		if (-not (Test-Path -LiteralPath $PreferencePath -PathType Leaf))
		{
			return [pscustomobject]$settings
		}

		$preferencesJson = Get-Content -LiteralPath $PreferencePath -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16
		if (-not $preferencesJson -or -not $preferencesJson.Values)
		{
			return [pscustomobject]$settings
		}

		if ($preferencesJson.Values.PSObject.Properties['StartupRunInitialActions'])
		{
			$settings.RunInitialActions = ConvertTo-BaselineUpdateBoolean -Value $preferencesJson.Values.StartupRunInitialActions -Default $true
		}
		if ($preferencesJson.Values.PSObject.Properties['StartupCheckWinGet'])
		{
			$settings.CheckWinGet = ConvertTo-BaselineUpdateBoolean -Value $preferencesJson.Values.StartupCheckWinGet -Default $true
		}
		if ($preferencesJson.Values.PSObject.Properties['StartupCheckChocolatey'])
		{
			$settings.CheckChocolatey = ConvertTo-BaselineUpdateBoolean -Value $preferencesJson.Values.StartupCheckChocolatey -Default $true
		}
		if ($preferencesJson.Values.PSObject.Properties['StartupWinGetCheckFrequency'])
		{
			$settings.WinGetCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $preferencesJson.Values.StartupWinGetCheckFrequency
		}
		if ($preferencesJson.Values.PSObject.Properties['StartupChocolateyCheckFrequency'])
		{
			$settings.ChocolateyCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $preferencesJson.Values.StartupChocolateyCheckFrequency
		}
	}
	catch
	{
		Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStartupSplashSettings.LoadPreferences'
	}

	return [pscustomobject]$settings
}

function ConvertTo-BaselineUpdateBoolean
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[object]$Value,

		[bool]$Default = $false
	)

	if ($null -eq $Value) { return $Default }
	if ($Value -is [bool]) { return [bool]$Value }
	$text = ([string]$Value).Trim()
	if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
	if ($text -in @('1', 'true', 'yes', 'on')) { return $true }
	if ($text -in @('0', 'false', 'no', 'off')) { return $false }
	return $Default
}

function ConvertTo-BaselineUpdateCheckFrequency
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[AllowNull()]
		[object]$Frequency
	)

	switch -Regex ([string]$Frequency)
	{
		'(?i)^daily$' { return 'Daily' }
		'(?i)^weekly$' { return 'Weekly' }
		default { return 'Startup' }
	}
}

function ConvertTo-BaselineUpdateBranch
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[AllowNull()]
		[object]$Branch
	)

	switch -Regex ([string]$Branch)
	{
		'(?i)^beta$' { return 'Beta' }
		default { return 'Stable' }
	}
}

function Get-BaselineDefaultUpdateBranch
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$ModuleManifestPath
	)

	if ([string]::IsNullOrWhiteSpace($ModuleManifestPath) -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot))
	{
		$ModuleManifestPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Baseline.psd1'
	}

	if ([string]::IsNullOrWhiteSpace($ModuleManifestPath) -or -not (Test-Path -LiteralPath $ModuleManifestPath -PathType Leaf))
	{
		return 'Stable'
	}

	try
	{
		$moduleManifest = Import-PowerShellDataFile -Path $ModuleManifestPath -ErrorAction Stop
		if ($moduleManifest -and $moduleManifest.ContainsKey('PrivateData') -and $moduleManifest.PrivateData -is [hashtable] -and $moduleManifest.PrivateData.ContainsKey('Prerelease'))
		{
			$prerelease = [string]$moduleManifest.PrivateData.Prerelease
			if ($prerelease -match '(?i)\bbeta\b')
			{
				return 'Beta'
			}
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineDefaultUpdateBranch'
	}

	return 'Stable'
}

function Get-BaselineUpdateRepositoryName
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$Branch = 'Stable'
	)

	$normalizedBranch = ConvertTo-BaselineUpdateBranch -Branch $Branch
	if ([string]::Equals($normalizedBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase))
	{
		return 'baseline_dev'
	}

	return 'Baseline'
}

function Get-BaselineUpdateRepositoryUrl
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$Branch = 'Stable'
	)

	$repositoryName = Get-BaselineUpdateRepositoryName -Branch $Branch
	return ('https://github.com/sdmanson8/{0}' -f $repositoryName)
}

function Get-BaselineUpdateReleaseApiUri
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$Branch = 'Stable'
	)

	$repositoryName = Get-BaselineUpdateRepositoryName -Branch $Branch
	return ('https://api.github.com/repos/sdmanson8/{0}/releases' -f $repositoryName)
}

function Get-BaselineUpdateReleasePageUrl
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$Branch = 'Stable'
	)

	return ('{0}/releases/latest' -f (Get-BaselineUpdateRepositoryUrl -Branch $Branch))
}

function Test-BaselineUpdatePrereleaseAllowed
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[string]$Branch = 'Stable',

		[bool]$IncludePrerelease = $false
	)

	$normalizedBranch = ConvertTo-BaselineUpdateBranch -Branch $Branch
	return ([bool]$IncludePrerelease -or [string]::Equals($normalizedBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-BaselineStoredUpdatePreference
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Key,

		[AllowNull()]
		[object]$Default = $null,

		[string]$Path = (Get-BaselineUpdatePreferencePath)
	)

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path))
	{
		return $Default
	}

	try
	{
		$raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
		$parsed = $raw | ConvertFrom-BaselineJson -Depth 12 -ErrorAction Stop
		if (-not $parsed -or -not $parsed.Values -or -not $parsed.Values.PSObject.Properties[$Key])
		{
			return $Default
		}
		return $parsed.Values.$Key
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineStoredUpdatePreference'
		return $Default
	}
}

function Get-BaselineUpdateSettings
{
	<#
	.SYNOPSIS
	Reads persisted update behavior settings without loading the GUI preference module.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$PreferencePath = (Get-BaselineUpdatePreferencePath),

		[string]$StatePath = (Get-BaselineAutoUpdateThrottlePath)
	)

	$autoCheckPreference = Get-BaselineStoredUpdatePreference -Key 'AutoCheckUpdates' -Default $null -Path $PreferencePath
	$autoCheck = ConvertTo-BaselineUpdateBoolean -Value $autoCheckPreference -Default $true
	if ($null -eq $autoCheckPreference)
	{
		$checkState = Get-BaselineUpdateCheckState -Path $StatePath
		if ($checkState -and [string]::Equals([string]$checkState.Status, 'Disabled', [System.StringComparison]::OrdinalIgnoreCase))
		{
			$autoCheck = $false
		}
	}
	$frequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency (Get-BaselineStoredUpdatePreference -Key 'UpdateCheckFrequency' -Default 'Startup' -Path $PreferencePath)
	$defaultUpdateBranch = Get-BaselineDefaultUpdateBranch
	$updateBranch = ConvertTo-BaselineUpdateBranch -Branch (Get-BaselineStoredUpdatePreference -Key 'UpdateBranch' -Default $defaultUpdateBranch -Path $PreferencePath)
	$includePrerelease = ConvertTo-BaselineUpdateBoolean -Value (Get-BaselineStoredUpdatePreference -Key 'IncludePrereleaseUpdates' -Default $false -Path $PreferencePath) -Default $false

	return [pscustomobject]@{
		AutoCheckUpdates = $autoCheck
		CheckFrequency = $frequency
		IncludePrereleaseBuilds = $includePrerelease
		UpdateBranch = $updateBranch
		RepositoryName = Get-BaselineUpdateRepositoryName -Branch $updateBranch
		RepositoryUrl = Get-BaselineUpdateRepositoryUrl -Branch $updateBranch
		ReleaseApiUri = Get-BaselineUpdateReleaseApiUri -Branch $updateBranch
	}
}

function Get-BaselineUpdateCheckState
{
	<#
	.SYNOPSIS
	Reads the persisted update check state displayed in Settings.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$Path = (Get-BaselineAutoUpdateThrottlePath)
	)

	$defaultState = [pscustomobject]@{
		LastCheckedUtc = $null
		Status = 'Not checked'
		LatestVersion = ''
		Message = ''
	}

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path))
	{
		return $defaultState
	}

	try
	{
		$raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return $defaultState }
		$state = $raw | ConvertFrom-BaselineJson -Depth 8 -ErrorAction Stop
		$lastCheckedUtc = $null
		$lastCheckedRaw = if ($state -and $state.PSObject.Properties['LastCheckedUtc']) { [string]$state.LastCheckedUtc } else { '' }
		if (-not [string]::IsNullOrWhiteSpace($lastCheckedRaw))
		{
			$parsedLastCheckedUtc = [datetime]::MinValue
			if ([datetime]::TryParse($lastCheckedRaw, [ref]$parsedLastCheckedUtc))
			{
				$lastCheckedUtc = $parsedLastCheckedUtc.ToUniversalTime()
			}
		}

		return [pscustomobject]@{
			LastCheckedUtc = $lastCheckedUtc
			Status = if ($state -and $state.PSObject.Properties['Status'] -and -not [string]::IsNullOrWhiteSpace([string]$state.Status)) { [string]$state.Status } else { 'Not checked' }
			LatestVersion = if ($state -and $state.PSObject.Properties['LatestVersion']) { [string]$state.LatestVersion } else { '' }
			Message = if ($state -and $state.PSObject.Properties['Message']) { [string]$state.Message } else { '' }
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineUpdateCheckState'
		return $defaultState
	}
}

function Set-BaselineUpdateCheckState
{
	<#
	.SYNOPSIS
	Persists update check state for Settings and startup gating.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Status,

		[string]$LatestVersion = '',

		[string]$Message = '',

		[string]$Path = (Get-BaselineAutoUpdateThrottlePath),

		[datetime]$NowUtc = [DateTime]::UtcNow,

		[switch]$PreserveLastChecked
	)

	$directory = Split-Path -Path $Path -Parent
	if (-not (Test-Path -LiteralPath $directory))
	{
		$null = New-Item -Path $directory -ItemType Directory -Force
	}

	$lastCheckedUtc = $NowUtc.ToUniversalTime()
	if ($PreserveLastChecked)
	{
		$existing = Get-BaselineUpdateCheckState -Path $Path
		if ($existing -and $existing.LastCheckedUtc)
		{
			$lastCheckedUtc = ([datetime]$existing.LastCheckedUtc).ToUniversalTime()
		}
		else
		{
			$lastCheckedUtc = $null
		}
	}

	$payload = [pscustomobject]@{
		Schema = 'Baseline.AutoUpdateCheck'
		SchemaVersion = 2
		LastCheckedUtc = if ($lastCheckedUtc) { $lastCheckedUtc.ToString('o') } else { $null }
		Status = [string]$Status
		LatestVersion = [string]$LatestVersion
		Message = [string]$Message
		MinimumIntervalHours = 4
	}
	[System.IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 6), [System.Text.Encoding]::UTF8)
}

function Format-BaselineUpdateLastChecked
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[AllowNull()]
		[object]$LastCheckedUtc,

		[string]$NeverText = 'Never'
	)

	if ($null -eq $LastCheckedUtc) { return $NeverText }
	$parsed = [datetime]::MinValue
	if (-not [datetime]::TryParse([string]$LastCheckedUtc, [ref]$parsed)) { return $NeverText }
	return $parsed.ToLocalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-BaselineUpdateFrequencyDecision
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$Frequency = 'Startup',

		[AllowNull()]
		[object]$State = $null,

		[datetime]$NowUtc = [DateTime]::UtcNow
	)

	$normalizedFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $Frequency
	if ($normalizedFrequency -eq 'Startup')
	{
		return [pscustomobject]@{
			ShouldCheck = $true
			NextEligibleUtc = $NowUtc.ToUniversalTime()
			Reason = 'Startup update check is enabled.'
		}
	}

	$lastCheckedUtc = $null
	if ($State -and $State.PSObject.Properties['LastCheckedUtc'] -and $State.LastCheckedUtc)
	{
		$lastCheckedUtc = ([datetime]$State.LastCheckedUtc).ToUniversalTime()
	}
	if (-not $lastCheckedUtc)
	{
		return [pscustomobject]@{
			ShouldCheck = $true
			NextEligibleUtc = $NowUtc.ToUniversalTime()
			Reason = 'No previous update check was recorded.'
		}
	}

	$interval = if ($normalizedFrequency -eq 'Weekly') { [TimeSpan]::FromDays(7) } else { [TimeSpan]::FromDays(1) }
	$nextEligibleUtc = $lastCheckedUtc.Add($interval)
	return [pscustomobject]@{
		ShouldCheck = ($NowUtc.ToUniversalTime() -ge $nextEligibleUtc)
		NextEligibleUtc = $nextEligibleUtc
		Reason = if ($NowUtc.ToUniversalTime() -ge $nextEligibleUtc) { 'Update check frequency interval elapsed.' } else { 'Update check frequency interval has not elapsed.' }
	}
}

function Test-BaselineAutoUpdateStartupEnabled
{
	<#
	.SYNOPSIS
	Determines whether startup should visually prime and run the update check.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	if ($env:BASELINE_INSTALLER_MODE -eq '1') { return $false }
	if ($env:BASELINE_SKIP_UPDATE -eq '1') { return $false }
	if ($env:BASELINE_EMBEDDED_HOST -ne '1') { return $false }

	$settings = Get-BaselineUpdateSettings
	if (-not [bool]$settings.AutoCheckUpdates) { return $false }

	$state = Get-BaselineUpdateCheckState
	$decision = Get-BaselineUpdateFrequencyDecision -Frequency $settings.CheckFrequency -State $state
	return [bool]$decision.ShouldCheck
}

function Test-BaselineOfflineUpdateException
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[object]$ErrorRecord
	)

	$exception = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } elseif ($ErrorRecord -is [System.Exception]) { $ErrorRecord } else { $null }
	while ($exception)
	{
		if ($exception -is [System.Net.WebException])
		{
			$status = $exception.Status
			if ($status -in @(
				[System.Net.WebExceptionStatus]::NameResolutionFailure,
				[System.Net.WebExceptionStatus]::ConnectFailure,
				[System.Net.WebExceptionStatus]::ProxyNameResolutionFailure,
				[System.Net.WebExceptionStatus]::ReceiveFailure,
				[System.Net.WebExceptionStatus]::SendFailure,
				[System.Net.WebExceptionStatus]::Timeout
			))
			{
				return $true
			}
		}
		$exception = $exception.InnerException
	}

	return $false
}

function Test-BaselineUpdateEndpointAvailable
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[string]$HostName = 'api.github.com',

		[int]$Port = 443,

		[int]$TimeoutMilliseconds = 1500
	)

	$client = [System.Net.Sockets.TcpClient]::new()
	try
	{
		$async = $client.BeginConnect($HostName, $Port, $null, $null)
		if (-not $async.AsyncWaitHandle.WaitOne([Math]::Max(250, [int]$TimeoutMilliseconds), $false))
		{
			return $false
		}
		$client.EndConnect($async)
		return $true
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Environment.TestBaselineUpdateEndpointAvailable'
		return $false
	}
	finally
	{
		try { $client.Close() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.TestBaselineUpdateEndpointAvailable.Close' }
	}
}

function Invoke-BaselineUpdateCheck
{
	<#
	.SYNOPSIS
	Runs an immediate GitHub release metadata check and persists the visible
	update state.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$CurrentVersion = '0.0.0',

		[string]$UpdateBranch = 'Stable',

		[switch]$IncludePrerelease
	)

	$statePath = Get-BaselineAutoUpdateThrottlePath
	$normalizedUpdateBranch = ConvertTo-BaselineUpdateBranch -Branch $UpdateBranch
	$allowPrerelease = Test-BaselineUpdatePrereleaseAllowed -Branch $normalizedUpdateBranch -IncludePrerelease ([bool]$IncludePrerelease)
	$releaseAssetPattern = Get-BaselineUpdateAssetPattern -Branch $normalizedUpdateBranch
	$releaseApiUri = Get-BaselineUpdateReleaseApiUri -Branch $normalizedUpdateBranch
	$repositoryName = Get-BaselineUpdateRepositoryName -Branch $normalizedUpdateBranch
	$repositoryUrl = Get-BaselineUpdateRepositoryUrl -Branch $normalizedUpdateBranch
	$currentBuildBranch = Get-BaselineDefaultUpdateBranch
	try
	{
		Set-DownloadSecurityProtocol
		$headers = @{ 'User-Agent' = "Baseline/$CurrentVersion" }
		$releases = Invoke-RestMethod -Uri $releaseApiUri -Headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop
		$release = Get-BaselineLatestReleaseEntry -Releases $releases -IncludePrerelease:$allowPrerelease -AssetPattern $releaseAssetPattern
		if (-not $release)
		{
			Set-BaselineUpdateCheckState -Path $statePath -Status 'Up to date' -LatestVersion $CurrentVersion -Message 'No published release newer than the current build was found.'
			return [pscustomobject]@{
				Status = 'Up to date'
				LatestVersion = $CurrentVersion
				IsUpdateAvailable = $false
				Release = $null
				LastCheckedUtc = (Get-BaselineUpdateCheckState -Path $statePath).LastCheckedUtc
				Message = ''
				UpdateBranch = $normalizedUpdateBranch
				RepositoryName = $repositoryName
				RepositoryUrl = $repositoryUrl
			}
		}

		$latestTag = [string]$release.tag_name
		$isNewer = Test-BaselineReleaseUpdateRequired -LatestVersion $latestTag -CurrentVersion $CurrentVersion -UpdateBranch $normalizedUpdateBranch -CurrentBuildBranch $currentBuildBranch
		if ($isNewer)
		{
			Set-BaselineUpdateCheckState -Path $statePath -Status 'Update available' -LatestVersion $latestTag -Message ''
			return [pscustomobject]@{
				Status = 'Update available'
				LatestVersion = $latestTag
				IsUpdateAvailable = $true
				Release = $release
				LastCheckedUtc = (Get-BaselineUpdateCheckState -Path $statePath).LastCheckedUtc
				Message = ''
				UpdateBranch = $normalizedUpdateBranch
				RepositoryName = $repositoryName
				RepositoryUrl = $repositoryUrl
			}
		}

		Set-BaselineUpdateCheckState -Path $statePath -Status 'Up to date' -LatestVersion $latestTag -Message ''
		return [pscustomobject]@{
			Status = 'Up to date'
			LatestVersion = $latestTag
			IsUpdateAvailable = $false
			Release = $release
			LastCheckedUtc = (Get-BaselineUpdateCheckState -Path $statePath).LastCheckedUtc
			Message = ''
			UpdateBranch = $normalizedUpdateBranch
			RepositoryName = $repositoryName
			RepositoryUrl = $repositoryUrl
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Invoke-BaselineUpdateCheck:catch2620' -Severity Debug }

		$status = if (Test-BaselineOfflineUpdateException -ErrorRecord $_) { 'Skipped (offline)' } else { 'Failed' }
		$message = [string]$_.Exception.Message
		Set-BaselineUpdateCheckState -Path $statePath -Status $status -LatestVersion '' -Message $message
		return [pscustomobject]@{
			Status = $status
			LatestVersion = ''
			IsUpdateAvailable = $false
			Release = $null
			LastCheckedUtc = (Get-BaselineUpdateCheckState -Path $statePath).LastCheckedUtc
			Message = $message
			UpdateBranch = $normalizedUpdateBranch
			RepositoryName = $repositoryName
			RepositoryUrl = $repositoryUrl
		}
	}
}

function Get-BaselineAutoUpdateThrottleDecision
{
	<#
	.SYNOPSIS
	Determines whether the startup auto-update check is eligible to run.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[datetime]$NowUtc = [DateTime]::UtcNow,

		[int]$MinimumIntervalHours = 4
	)

	$minimumInterval = [TimeSpan]::FromHours([Math]::Max(1, [int]$MinimumIntervalHours))
	if (-not (Test-Path -LiteralPath $Path))
	{
		return [pscustomobject]@{
			ShouldCheck = $true
			LastCheckedUtc = $null
			NextEligibleUtc = $NowUtc
			Reason = 'No previous auto-update check was recorded.'
		}
	}

	try
	{
		$raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
		$state = ConvertFrom-BaselineJson -InputObject $raw
		$lastCheckedRaw = if ($state -and $state.PSObject.Properties['LastCheckedUtc']) { [string]$state.LastCheckedUtc } else { '' }
		$lastCheckedUtc = [datetime]::MinValue
		if ([string]::IsNullOrWhiteSpace($lastCheckedRaw) -or -not [datetime]::TryParse($lastCheckedRaw, [ref]$lastCheckedUtc))
		{
			throw 'LastCheckedUtc is missing or invalid.'
		}

		$lastCheckedUtc = $lastCheckedUtc.ToUniversalTime()
		$nextEligibleUtc = $lastCheckedUtc.Add($minimumInterval)
		return [pscustomobject]@{
			ShouldCheck = ($NowUtc.ToUniversalTime() -ge $nextEligibleUtc)
			LastCheckedUtc = $lastCheckedUtc
			NextEligibleUtc = $nextEligibleUtc
			Reason = if ($NowUtc.ToUniversalTime() -ge $nextEligibleUtc) { 'Auto-update throttle interval elapsed.' } else { 'Auto-update check was already performed inside the throttle interval.' }
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-BaselineAutoUpdateThrottleDecision:catch2687' -Severity Debug }

		return [pscustomobject]@{
			ShouldCheck = $true
			LastCheckedUtc = $null
			NextEligibleUtc = $NowUtc
			Reason = 'Auto-update throttle state could not be read.'
		}
	}
}

function Set-BaselineAutoUpdateThrottleTimestamp
{
	<#
	.SYNOPSIS
	Records that the startup auto-update check was attempted.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[datetime]$NowUtc = [DateTime]::UtcNow
	)

	$directory = Split-Path -Path $Path -Parent
	if (-not (Test-Path -LiteralPath $directory))
	{
		$null = New-Item -Path $directory -ItemType Directory -Force
	}

	$payload = [pscustomobject]@{
		Schema = 'Baseline.AutoUpdateCheck'
		SchemaVersion = 1
		LastCheckedUtc = $NowUtc.ToUniversalTime().ToString('o')
		MinimumIntervalHours = 4
	}
	[System.IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 4), [System.Text.Encoding]::UTF8)
}

function Invoke-BaselineAutoUpdate
{
	<#
	.SYNOPSIS
	Checks GitHub for a newer Baseline release zip and, if found, downloads it
	using the existing splash progress bar then runs the setup update flow.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[object]$Splash = $null,

		[Parameter(Mandatory = $false)]
		[string]$CurrentVersion = '0.0.0'
	)

	if ($null -eq $Splash)
	{
		$loadingSplashVariable = Get-Variable -Name 'LoadingSplash' -Scope Global -ErrorAction SilentlyContinue
		if ($loadingSplashVariable)
		{
			$Splash = $loadingSplashVariable.Value
		}
	}

	# Skip if launched by the installer or already updated this session
	if ($env:BASELINE_INSTALLER_MODE -eq '1') { return }
	if ($env:BASELINE_SKIP_UPDATE    -eq '1') { return }
	if ($env:BASELINE_EMBEDDED_HOST -ne '1') { return }
	$updateSettings = Get-BaselineUpdateSettings
	$statePath = Get-BaselineAutoUpdateThrottlePath
	$currentBuildBranch = Get-BaselineDefaultUpdateBranch
	$updateBranch = if ($updateSettings -and $updateSettings.PSObject.Properties['UpdateBranch'] -and -not [string]::IsNullOrWhiteSpace([string]$updateSettings.UpdateBranch)) { ConvertTo-BaselineUpdateBranch -Branch $updateSettings.UpdateBranch } else { $currentBuildBranch }
	if (-not [bool]$updateSettings.AutoCheckUpdates)
	{
		Set-BaselineUpdateCheckState -Path $statePath -Status 'Disabled' -PreserveLastChecked
		LogInfo 'Skipping auto-update check: automatic update checks are disabled.'
		return
	}

	$exePath = [string]$env:BASELINE_LAUNCHER_PATH
	if ([string]::IsNullOrWhiteSpace($exePath) -or -not [System.IO.Path]::IsPathRooted($exePath))
	{
		Set-BaselineUpdateCheckState -Path $statePath -Status 'Failed' -Message 'Launcher path was not available to the embedded host.'
		LogWarning 'Skipping auto-update check: launcher path was not available to the embedded host.'
		return
	}

	# If we couldn't determine our own version, refuse to auto-update. Without a
	# trustworthy current version every published release looks "newer" and we
	# would silently downgrade the user.
	if ([string]::IsNullOrWhiteSpace([string]$CurrentVersion) -or $CurrentVersion -eq '0.0.0')
	{
		Set-BaselineUpdateCheckState -Path $statePath -Status 'Failed' -Message ('Current Baseline version could not be determined (reported: "{0}").' -f $CurrentVersion)
		LogWarning ('Skipping auto-update check: current Baseline version could not be determined (reported: "{0}"). Refusing to compare against GitHub releases to avoid downgrading.' -f $CurrentVersion)
		return
	}

	try
	{
		$updateState = Get-BaselineUpdateCheckState -Path $statePath
		$frequencyDecision = Get-BaselineUpdateFrequencyDecision -Frequency $updateSettings.CheckFrequency -State $updateState
		if (-not [bool]$frequencyDecision.ShouldCheck)
		{
			LogInfo ('Skipping auto-update check: {0} Next eligible UTC: {1:o}.' -f $frequencyDecision.Reason, $frequencyDecision.NextEligibleUtc)
			return
		}

		if (-not (Test-BaselineUpdateEndpointAvailable))
		{
			Set-BaselineUpdateCheckState -Path $statePath -Status 'Skipped (offline)' -Message 'GitHub release endpoint is not reachable.'
			LogInfo 'Skipping auto-update check: GitHub release endpoint is not reachable.'
			return
		}

		Set-DownloadSecurityProtocol
		[void](Set-BootstrapLoadingSplashState -Splash $Splash -Completed 0 -Total 5)
		if (Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction SilentlyContinue)
		{
			[void](Set-BootstrapLoadingSplashStep -Splash $Splash -StepId 'updates' -Status 'in_progress' -SubAction '')
		}
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingForUpdatesVerbose' -Fallback 'Checking for updates (current version: {0})...' -FormatArgs @($CurrentVersion))

		$apiUrl  = Get-BaselineUpdateReleaseApiUri -Branch $updateBranch
		$headers = @{ 'User-Agent' = "Baseline/$CurrentVersion" }

		$releases = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -TimeoutSec 8 -ErrorAction Stop
		$allowPrerelease = Test-BaselineUpdatePrereleaseAllowed -Branch $updateBranch -IncludePrerelease ([bool]$updateSettings.IncludePrereleaseBuilds)
		$releaseAssetPattern = Get-BaselineUpdateAssetPattern -Branch $updateBranch
		$release = Get-BaselineLatestReleaseEntry -Releases $releases -IncludePrerelease:$allowPrerelease -AssetPattern $releaseAssetPattern
		if (-not $release)
		{
			Set-BaselineUpdateCheckState -Path $statePath -Status 'Up to date' -LatestVersion $CurrentVersion -Message 'No published release newer than the current build was found.'
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_NoReleasesFound' -Fallback 'No releases found on GitHub; skipping update.')
			return
		}

		$latestTag = [string]$release.tag_name
		$isNewer = Test-BaselineReleaseUpdateRequired -LatestVersion $latestTag -CurrentVersion $CurrentVersion -UpdateBranch $updateBranch -CurrentBuildBranch $currentBuildBranch

		if (-not $isNewer)
		{
			Set-BaselineUpdateCheckState -Path $statePath -Status 'Up to date' -LatestVersion $latestTag -Message ''
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_AlreadyUpToDate' -Fallback 'Already up to date (latest: {0}).' -FormatArgs @($latestTag))
			[void](Set-BootstrapLoadingSplashState -Splash $Splash -Indeterminate)
			return
		}

		Set-BaselineUpdateCheckState -Path $statePath -Status 'Update available' -LatestVersion $latestTag -Message ''

		$releaseAsset = Get-BaselineUpdateAsset -Assets @($release.assets) -Pattern $releaseAssetPattern
		$downloadUrl = if ($releaseAsset) { [string]$releaseAsset.browser_download_url } else { $null }
		if ([string]::IsNullOrWhiteSpace($downloadUrl)) { LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_NoMatchingUpdateAsset' -Fallback 'Update {0} found but no matching release zip asset; skipping.' -FormatArgs @($latestTag)); return }

		$releaseAssetName = [string]$releaseAsset.name
		$releaseHashAssetName = $releaseAssetName + '.sha256.json'
		$releaseHashAsset = Get-BaselineUpdateAsset -Assets @($release.assets) -Name $releaseHashAssetName
		$releaseHashDownloadUrl = if ($releaseHashAsset) { [string]$releaseHashAsset.browser_download_url } else { $null }
		if ([string]::IsNullOrWhiteSpace($releaseHashDownloadUrl))
		{
			LogWarning ('Update {0} found but no matching SHA-256 manifest asset ({1}); skipping.' -f $latestTag, $releaseHashAssetName)
			return
		}

		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_UpdateAvailable' -Fallback 'Update available: {0}. Downloading...' -FormatArgs @($latestTag))
		# Download with progress bar
		[void](Set-BootstrapLoadingSplashState -Splash $Splash -Completed 0 -Total 100)

		$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("BaselineUpdate_" + [System.Guid]::NewGuid().ToString('N'))
		$zipPath = Join-Path $tmpDir $releaseAssetName
		$manifestPath = Join-Path $tmpDir ($releaseAssetName + '.sha256.json')
		$extractPath = Join-Path $tmpDir 'extract'
		[void](New-Item -ItemType Directory -Path $tmpDir -Force)

		try
		{
			$manifestClient = New-Object System.Net.WebClient
			try
			{
				$manifestClient.Headers['User-Agent'] = "Baseline/$CurrentVersion"
				$manifestClient.DownloadFile($releaseHashDownloadUrl, $manifestPath)
			}
			finally
			{
				$manifestClient.Dispose()
			}

			$request  = [System.Net.HttpWebRequest]::Create($downloadUrl)
			$request.UserAgent = "Baseline/$CurrentVersion"
			$request.Timeout   = 300000
			$response = $request.GetResponse()
			$total    = $response.ContentLength
			if ($total -le 0 -and $releaseAsset.SizeBytes -gt 0)
			{
				$total = [long]$releaseAsset.SizeBytes
			}

			$srcStream  = $response.GetResponseStream()
			$destStream = [System.IO.File]::Create($zipPath)
			$buffer     = New-Object byte[] 81920
			$received   = 0L
			$downloadTimer = [System.Diagnostics.Stopwatch]::StartNew()
			$lastUiUpdateMs = -1.0
			$lastPercent = -1

			try
			{
				$read = $srcStream.Read($buffer, 0, $buffer.Length)
				while ($read -gt 0)
				{
					$destStream.Write($buffer, 0, $read)
					$received += $read
					if ($total -gt 0)
					{
						$pct = [int]([Math]::Min(99, ($received * 100 / $total)))
						if (($pct -ne $lastPercent) -or (($downloadTimer.Elapsed.TotalMilliseconds - $lastUiUpdateMs) -ge 250))
						{
							$statusText = Format-BaselineDownloadStatus -VersionTag $latestTag -BytesReceived $received -TotalBytes $total -ElapsedSeconds $downloadTimer.Elapsed.TotalSeconds
							[void](Set-BootstrapLoadingSplashState -Splash $Splash -StatusText $statusText -Completed $pct -Total 100)
							$lastPercent = $pct
							$lastUiUpdateMs = $downloadTimer.Elapsed.TotalMilliseconds
						}
					}
					elseif (($downloadTimer.Elapsed.TotalMilliseconds - $lastUiUpdateMs) -ge 250)
					{
						$statusText = Format-BaselineDownloadStatus -VersionTag $latestTag -BytesReceived $received -TotalBytes 0 -ElapsedSeconds $downloadTimer.Elapsed.TotalSeconds
						[void](Set-BootstrapLoadingSplashState -Splash $Splash -StatusText $statusText -Indeterminate)
						$lastUiUpdateMs = $downloadTimer.Elapsed.TotalMilliseconds
					}
					$read = $srcStream.Read($buffer, 0, $buffer.Length)
				}
			}
			finally
			{
				$destStream.Close()
				$srcStream.Close()
				$response.Close()
			}

			[void](Set-BootstrapLoadingSplashState -Splash $Splash -Completed 100 -Total 100)

			$releaseManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson
			Assert-BaselineUpdateFileHash -Path $zipPath -Manifest $releaseManifest -Name $releaseAssetName
			New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
			Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
			$setupCandidates = @(Get-ChildItem -Path $extractPath -Filter 'Baseline-*-setup.exe' -Recurse -File -ErrorAction Stop)
			if ($setupCandidates.Count -ne 1)
			{
				throw "Release zip must contain exactly one Baseline-*-setup.exe. Found $($setupCandidates.Count)."
			}
			$setupPath = [string]$setupCandidates[0].FullName
			$setupFileName = [System.IO.Path]::GetFileName($setupPath)
			Assert-BaselineUpdateFileHash -Path $setupPath -Manifest $releaseManifest -Name $setupFileName

			$updateInstallMode = Get-BaselineUpdateInstallMode -ExecutablePath $exePath
			$updateTargetDirectory = Split-Path -Path $exePath -Parent
			$setupArguments = @(
				'/SP-'
				'/VERYSILENT'
				'/SUPPRESSMSGBOXES'
				'/NORESTART'
				'/BASELINEUPDATE=1'
				('/BASELINEUPDATEMODE={0}' -f $updateInstallMode)
				('/BASELINEUPDATETARGETDIR="{0}"' -f $updateTargetDirectory)
				('/RELAUNCH="{0}"' -f $exePath)
			)
			if ($updateInstallMode -eq 'Install')
			{
				$installDirectory = $updateTargetDirectory
				$setupArguments += ('/DIR="{0}"' -f $installDirectory)
				if ($installDirectory.StartsWith([System.Environment]::GetFolderPath('LocalApplicationData'), [System.StringComparison]::OrdinalIgnoreCase))
				{
					$setupArguments += '/CURRENTUSER'
				}
			}
			else
			{
				$setupArguments += '/CURRENTUSER'
			}

			$cmdPath = Join-Path $tmpDir 'apply-update.cmd'
			$setupArgumentText = [string]::Join(' ', $setupArguments)
			$cmdContent = @"
@echo off
timeout /t 2 /nobreak >nul
set BASELINE_SKIP_UPDATE=1
start /wait "" "$setupPath" $setupArgumentText
del /f /q "$manifestPath"
del /f /q "$zipPath"
del /f /q "$setupPath"
del /f /q "%~f0"
"@
			[System.IO.File]::WriteAllText($cmdPath, $cmdContent)

			$cmdExe = [System.Environment]::GetEnvironmentVariable('ComSpec')
			if ([string]::IsNullOrWhiteSpace($cmdExe))
			{
				$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
			}

			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = $cmdExe
			$psi.CreateNoWindow  = $true
			$psi.UseShellExecute = $false
			$psi.Arguments = ('/c "{0}"' -f $cmdPath)
			[void]([System.Diagnostics.Process]::Start($psi))

			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_UpdateDownloadedRelaunching' -Fallback 'Update {0} downloaded. Relaunching to apply...' -FormatArgs @($latestTag))
			[void](Close-LoadingSplashWindow -Splash $Splash -DisposeResources)
			[System.Environment]::Exit(0)
		}
		catch
		{
			Set-BaselineUpdateCheckState -Path $statePath -Status 'Failed' -LatestVersion $latestTag -Message ([string]$_.Exception.Message)
			LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_UpdateDownloadOrApplyFailed' -Fallback 'Failed to download or apply update {0}: {1}' -FormatArgs @($latestTag, $_.Exception.Message))
			try { if (Test-Path $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InvokeBaselineAutoUpdate.CleanupTempDir' }
		}
	}
	catch
	{
		try
		{
			$autoUpdateStatePath = Get-BaselineAutoUpdateThrottlePath
			$autoUpdateStatus = if (Test-BaselineOfflineUpdateException -ErrorRecord $_) { 'Skipped (offline)' } else { 'Failed' }
			Set-BaselineUpdateCheckState -Path $autoUpdateStatePath -Status $autoUpdateStatus -Message ([string]$_.Exception.Message)
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InvokeBaselineAutoUpdate.PersistFailureState' }
		# Never block startup - silently fall through on any update failure
		LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_AutoUpdateCheckFailed' -Fallback 'Auto-update check failed: {0}' -FormatArgs @($_.Exception.Message))
	}
	finally
	{
		# Restore the checklist row to a completed state if the process stayed alive.
		try
		{
			if (Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction SilentlyContinue)
			{
				[void](Set-BootstrapLoadingSplashStep -Splash $Splash -StepId 'updates' -Status 'completed' -SubAction '')
			}
			else
			{
				[void](Set-BootstrapLoadingSplashState -Splash $Splash -Indeterminate)
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InvokeBaselineAutoUpdate.RestoreSplashState' }
	}
}

<#
    .SYNOPSIS
#>

function Show-Menu
{
	<# .SYNOPSIS Displays an interactive console menu with arrow key navigation. #>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[array]
		$Menu,

		[Parameter(Mandatory = $true)]
		[int]
		$Default,

		[Parameter(Mandatory = $false)]
		[switch]
		$AddSkip
	)

	$Menu = @($Menu)

	if ($Localization -and $Localization.KeyboardArrows)
	{
		$Menu += ($Localization.KeyboardArrows -f [System.Char]::ConvertFromUtf32(0x2191), [System.Char]::ConvertFromUtf32(0x2193))
	}
	else
	{
		$Menu += ("Please use the arrow keys {0} and {1} on your keyboard to select your answer" -f [System.Char]::ConvertFromUtf32(0x2191), [System.Char]::ConvertFromUtf32(0x2193))
	}

	if ($AddSkip)
	{
		$Menu += Get-LocalizedShellString -ResourceId 16956 -Fallback 'Skip'
	}

	if ($env:WT_SESSION)
	{
		[System.Console]::BufferHeight += $Menu.Count
	}

	$minY = [Console]::CursorTop
	$y = [Math]::Max([Math]::Min(($Default - 1), ($Menu.Count - 1)), 0)

	# Returns selected menu item on Enter, or $null on Escape (callers must handle $null).
	do
	{
		[Console]::CursorTop = $minY
		[Console]::CursorLeft = 0
		$i = 0

		foreach ($item in $Menu)
		{
			if ($i -ne $y)
			{
				Write-Host ('  {0}  ' -f $item)
			}
			else
			{
				Write-Host ('[ {0} ]' -f $item)
			}

			$i++
		}

		$k = [Console]::ReadKey($true)
		switch ($k.Key)
		{
			'UpArrow'
			{
				if ($y -gt 0)
				{
					$y--
				}
			}
			'DownArrow'
			{
				if ($y -lt ($Menu.Count - 1))
				{
					$y++
				}
			}
			'Enter'
			{
				return $Menu[$y]
			}
		}
	}
	while ($k.Key -notin ([ConsoleKey]::Escape, [ConsoleKey]::Enter))
}

<#
    .SYNOPSIS
#>

function Get-LocalizedShellString
{
	<# .SYNOPSIS Retrieves a localized Windows shell string by resource ID. #>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[uint32]
		$ResourceId,

		[Parameter(Mandatory = $true)]
		[string]
		$Fallback,

		[Parameter(Mandatory = $false)]
		[switch]
		$StripAccelerators
	)

	$value = $null

	try
	{
		if ("WinAPI.GetStrings" -as [type])
		{
			$value = [WinAPI.GetStrings]::GetString($ResourceId)
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Get-LocalizedShellString:catch3160' -Severity Debug }

		$value = $null
	}

	if ([string]::IsNullOrWhiteSpace($value))
	{
		$value = $Fallback
	}

	if ($StripAccelerators -and -not [string]::IsNullOrEmpty($value))
	{
		$value = $value.Replace("&", "")
	}

	return $value
}

<#
    .SYNOPSIS
#>

function Restart-Script
{
	<# .SYNOPSIS Restarts the script under Windows PowerShell 5.1 unless it is already running there. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$ScriptPath,

		[string]
		$Preset,

		[string]
		$GameModeProfile,

		[string]
		$ScenarioProfile,

		[string[]]
		$Functions,

		[string[]]
		$Include,

		[switch]
		$DryRun
	)
	if ([System.Environment]::GetEnvironmentVariable('BASELINE_EMBEDDED_HOST') -eq '1')
	{
		return
	}

	$runningWindowsPowerShell51 = (
		$PSVersionTable.PSEdition -eq 'Desktop' -and
		$PSVersionTable.PSVersion.Major -eq 5 -and
		$PSVersionTable.PSVersion.Minor -eq 1
	)

	if (-not $runningWindowsPowerShell51)
	{
		$powershell51 = (Get-Command -Name powershell.exe -ErrorAction SilentlyContinue).Source

		if (-not $powershell51)
		{
			LogError "PowerShell 5.1 not found."
			[Environment]::Exit(1)
		}

		if (-not (Test-Path -LiteralPath $ScriptPath))
		{
			LogError "Script not found: $ScriptPath"
			[Environment]::Exit(1)
		}

		LogInfo "Restarting script in Windows PowerShell 5.1 from host $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))."

		$currentPolicy = (Get-ExecutionPolicy).ToString()
		$argList = @(
			'-ExecutionPolicy', $currentPolicy,
			'-NoProfile',
			'-File', $ScriptPath
		)

		if ($Preset)
		{
			$argList += '-Preset'
			$argList += $Preset
		}
		elseif ($GameModeProfile)
		{
			$argList += '-GameModeProfile'
			$argList += $GameModeProfile
		}
		elseif ($ScenarioProfile)
		{
			$argList += '-ScenarioProfile'
			$argList += $ScenarioProfile
		}
		elseif ($Functions)
		{
			$argList += '-Functions'
			$argList += $Functions
		}

		if ($Include)
		{
			$argList += '-Include'
			$argList += $Include
		}

		if ($DryRun)
		{
			$argList += '-DryRun'
		}

		Start-Process -FilePath $powershell51 -ArgumentList $argList -WindowStyle Hidden
		[Environment]::Exit(0)
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineDisplayVersion
{
	<# .SYNOPSIS Reads the module version string from Baseline.psd1. #>
	param ([string]$ModuleRoot)

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$moduleManifestPath = Join-Path $resolvedRoot 'Baseline.psd1'
	if (-not (Test-Path -LiteralPath $moduleManifestPath))
	{
		return $null
	}

	try
	{
		$moduleManifest = Import-EnvironmentPowerShellDataFile -Path $moduleManifestPath
		if ($moduleManifest.ContainsKey('ModuleVersion') -and -not [string]::IsNullOrWhiteSpace([string]$moduleManifest.ModuleVersion))
		{
			$version = "v{0}" -f [string]$moduleManifest.ModuleVersion
			if ($moduleManifest.ContainsKey('PrivateData') -and $moduleManifest.PrivateData -is [hashtable] -and $moduleManifest.PrivateData.ContainsKey('Prerelease') -and -not [string]::IsNullOrWhiteSpace([string]$moduleManifest.PrivateData.Prerelease))
			{
				$version = "{0} ({1})" -f $version, [string]$moduleManifest.PrivateData.Prerelease
			}
			return $version
		}
	}
	catch { Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.GetBaselineDisplayVersion.LoadManifest' }

	return $null
}

<#
    .SYNOPSIS
#>

function Get-TweakSkipLabel
{
	<# .SYNOPSIS Returns the current tweak or caller name for skip log labels. #>
	param (
		[System.Management.Automation.InvocationInfo]$CallerInvocation
	)

	if ($Global:CurrentTweakName) { return $Global:CurrentTweakName }
	if ($CallerInvocation -and $CallerInvocation.MyCommand) { return $CallerInvocation.MyCommand.Name }
	return "this item"
}

<#
.SYNOPSIS
Kill all explorer.exe processes to apply shell/taskbar changes.

.DESCRIPTION
Terminates explorer.exe (taskbar, desktop shell, all File Explorer windows).
The shell restarts automatically. Used during tweak execution to force
registry changes to take immediate effect.
#>
function Stop-Foreground
{
	LogInfo "Stopping explorer.exe to apply shell changes"
	Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue | Out-Null
}

<#
.SYNOPSIS
Execute a temporary script via a UCPD-bypassed PowerShell copy with guaranteed cleanup.

.DESCRIPTION
Copies powershell.exe to a temporary name to bypass the Windows UCPD driver
which blocks certain registry writes. The copied executable and generated
script file are removed in a finally block to guarantee cleanup even if the
command fails.

.PARAMETER ScriptText
The PowerShell source text to execute from a temporary .ps1 file.

.PARAMETER ScriptBlock
The PowerShell script block to execute from a temporary .ps1 file.
#>
function Invoke-UCPDBypassed
{
	[CmdletBinding(DefaultParameterSetName = 'ScriptText')]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'ScriptText')]
		[string]$ScriptText,

		[Parameter(Mandatory = $true, ParameterSetName = 'ScriptBlock')]
		[scriptblock]$ScriptBlock
	)

	$sourcePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
	$tempPath = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath
	$tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ('Baseline-UCPD-{0}.ps1' -f ([guid]::NewGuid().ToString('N')))

	# UCPD blocks some registry writes by process image name; this temporary copy
	# preserves Windows PowerShell 5.1 semantics without inline command text.
	LogInfo "Running UCPD-protected registry operation through a temporary Windows PowerShell copy."
	Copy-Item -Path $sourcePath -Destination $tempPath -Force -ErrorAction Stop | Out-Null
	try
	{
		if ($PSCmdlet.ParameterSetName -eq 'ScriptBlock')
		{
			$ScriptText = $ScriptBlock.ToString()
		}

		Set-Content -LiteralPath $tempScript -Value $ScriptText -Encoding UTF8 -Force -ErrorAction Stop
		$null = Invoke-BaselineProcess `
			-FilePath $tempPath `
			-ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $tempScript) `
			-TimeoutSeconds 300 `
			-AllowedExitCodes @(0)
	}
	finally
	{
		Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue | Out-Null
		Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue | Out-Null
	}
}

<#
    .SYNOPSIS
#>

function Get-UCPDTemporaryPowerShellPath
{
	<# .SYNOPSIS Generates a unique temporary PowerShell executable path for UCPD bypass. #>
	param (
		[string]$SourcePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
	)

	$sourceDirectory = Split-Path -Path $SourcePath -Parent
	$sourceLeaf = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
	$uniqueName = '{0}_{1}.exe' -f $sourceLeaf, ([guid]::NewGuid().ToString('N'))
	return (Join-Path -Path $sourceDirectory -ChildPath $uniqueName)
}

function Set-BaselineOperationMode
{
	<#
		.SYNOPSIS
		Sets the global operation mode. Valid: 'ReadWrite' (default) or 'ReadOnly'.
		ReadOnly mode causes Persistence/Audit/Registry write helpers to throw.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('ReadWrite', 'ReadOnly')]
		[string]$Mode
	)

	$Global:BaselineOperationMode = $Mode
	[System.Environment]::SetEnvironmentVariable('BASELINE_OPERATION_MODE', $Mode, [System.EnvironmentVariableTarget]::Process)
}

function Get-BaselineOperationMode
{
	<#
		.SYNOPSIS
		Returns the active operation mode. Defaults to 'ReadWrite'.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$globalModeVariable = Get-Variable -Name BaselineOperationMode -Scope Global -ErrorAction SilentlyContinue
	if ($globalModeVariable -and -not [string]::IsNullOrWhiteSpace([string]$globalModeVariable.Value)) { return [string]$globalModeVariable.Value }
	$envMode = [System.Environment]::GetEnvironmentVariable('BASELINE_OPERATION_MODE')
	if (-not [string]::IsNullOrWhiteSpace([string]$envMode)) { return [string]$envMode }
	return 'ReadWrite'
}

function Test-BaselineReadOnlyMode
{
	<# .SYNOPSIS Returns $true when Baseline is in ReadOnly mode. #>
	return ((Get-BaselineOperationMode) -eq 'ReadOnly')
}

function Assert-BaselineWriteAllowed
{
	<#
		.SYNOPSIS
		Throws when the active mode is ReadOnly. Used by canonical write helpers.
	#>
	[CmdletBinding()]
	param (
		[string]$Operation = 'write'
	)

	if (Test-BaselineReadOnlyMode)
	{
		throw [System.InvalidOperationException]::new(("Baseline is running in ReadOnly mode; '{0}' is not permitted." -f $Operation))
	}
}

function Initialize-BaselineMarkdownRuntime
{
	<# .SYNOPSIS Loads the embedded Markdig + Markdig.Wpf assemblies into the current runspace. #>
	[CmdletBinding()]
	param (
		[string]$ModuleRoot
	)

	if ($Script:CachedBaselineMarkdownRuntimeLoaded) { return $true }

	if ([string]::IsNullOrWhiteSpace($ModuleRoot))
	{
		$ModuleRoot = $Script:SharedHelpersModuleRoot
	}

	if ([string]::IsNullOrWhiteSpace($ModuleRoot) -or -not (Test-Path -LiteralPath $ModuleRoot -PathType Container))
	{
		return $false
	}

	$librariesRoot = Join-Path $ModuleRoot 'Libraries'
	if (-not (Test-Path -LiteralPath $librariesRoot -PathType Container))
	{
		return $false
	}

	# Load dependencies before Markdig / Markdig.Wpf so their references resolve.
	$loadOrder = @(
		'System.Buffers.dll',
		'System.Runtime.CompilerServices.Unsafe.dll',
		'System.Numerics.Vectors.dll',
		'System.Memory.dll',
		'Markdig.dll',
		'Markdig.Wpf.dll'
	)

	foreach ($dllName in $loadOrder)
	{
		$dllPath = Join-Path $librariesRoot $dllName
		if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { continue }
		try { Add-Type -Path $dllPath -ErrorAction Stop } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InitializeBaselineMarkdownRuntime.AddAssembly' }
	}

	$Script:CachedBaselineMarkdownRuntimeLoaded = (Test-BaselineMarkdownRuntimeReady)
	return [bool]$Script:CachedBaselineMarkdownRuntimeLoaded
}

<#
    .SYNOPSIS
#>
function Initialize-BaselineWinRtRuntimeDependencies
{
	<# .SYNOPSIS Loads bundled assemblies required by Windows Runtime projections in the embedded host. #>
	[CmdletBinding()]
	param (
		[string]$ModuleRoot
	)

	if ($Script:CachedBaselineWinRtRuntimeDependenciesLoaded) { return $true }

	if ([string]::IsNullOrWhiteSpace($ModuleRoot))
	{
		$ModuleRoot = $Script:SharedHelpersModuleRoot
	}

	if ([string]::IsNullOrWhiteSpace($ModuleRoot) -or -not (Test-Path -LiteralPath $ModuleRoot -PathType Container))
	{
		return $false
	}

	$librariesRoot = Join-Path $ModuleRoot 'Libraries'
	if (-not (Test-Path -LiteralPath $librariesRoot -PathType Container))
	{
		return $false
	}

	$isAssemblyLoaded = {
		param ([string]$AssemblyName)
		foreach ($assembly in [System.AppDomain]::CurrentDomain.GetAssemblies())
		{
			$name = $null
			try { $name = $assembly.GetName().Name } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Initialize-BaselineWinRtRuntimeDependencies:catch3561' -Severity Debug }
			 $name = $null }
			if ([string]::Equals([string]$name, $AssemblyName, [System.StringComparison]::OrdinalIgnoreCase))
			{
				return $true
			}
		}
		return $false
	}

	foreach ($dllName in @(
		'System.Runtime.CompilerServices.Unsafe.dll',
		'System.Numerics.Vectors.dll'
	))
	{
		$assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($dllName)
		if (& $isAssemblyLoaded $assemblyName) { continue }

		$dllPath = Join-Path $librariesRoot $dllName
		if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { continue }
		try { Add-Type -Path $dllPath -ErrorAction Stop } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InitializeBaselineWinRtRuntimeDependencies.AddAssembly' }
	}

	$Script:CachedBaselineWinRtRuntimeDependenciesLoaded = (& $isAssemblyLoaded 'System.Numerics.Vectors')
	return [bool]$Script:CachedBaselineWinRtRuntimeDependenciesLoaded
}

<#
    .SYNOPSIS
#>

function Test-BaselineMarkdownRuntimeReady
{
	<# .SYNOPSIS Returns $true once Markdig + Markdig.Wpf have been loaded into the runspace. #>
	$markdigAssembly = $null
	$markdigWpfAssembly = $null

	foreach ($assembly in [System.AppDomain]::CurrentDomain.GetAssemblies())
	{
		$assemblyName = $null
		try { $assemblyName = $assembly.GetName().Name } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Test-BaselineMarkdownRuntimeReady:catch3600' -Severity Debug }
		 $assemblyName = $null }
		if ([string]::IsNullOrWhiteSpace([string]$assemblyName)) { continue }

		if ($assemblyName -eq 'Markdig')
		{
			$markdigAssembly = $assembly
		}
		elseif ($assemblyName -eq 'Markdig.Wpf')
		{
			$markdigWpfAssembly = $assembly
		}

		if ($markdigAssembly -and $markdigWpfAssembly) { break }
	}

	if (-not $markdigAssembly -or -not $markdigWpfAssembly)
	{
		return $false
	}

	return (($null -ne $markdigAssembly.GetType('Markdig.Markdown', $false, $false)) -and
		($null -ne $markdigWpfAssembly.GetType('Markdig.Wpf.Markdown', $false, $false)))
}

<#
    .SYNOPSIS
#>
function Get-BaselineMarkdownPipeline
{
	<# .SYNOPSIS Returns a cached MarkdownPipeline configured with GitHub-style heading identifiers. #>
	$cachedPipelineVariable = Get-Variable -Name 'CachedBaselineMarkdownPipeline' -Scope Script -ErrorAction SilentlyContinue
	if ($cachedPipelineVariable -and $cachedPipelineVariable.Value) { return $cachedPipelineVariable.Value }

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		[void](Initialize-BaselineMarkdownRuntime)
	}

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		throw 'Markdig runtime is not available.'
	}

	$builder = New-Object Markdig.MarkdownPipelineBuilder
	$builder = [Markdig.MarkdownExtensions]::UseAutoIdentifiers($builder, [Markdig.Extensions.AutoIdentifiers.AutoIdentifierOptions]::GitHub)
	$Script:CachedBaselineMarkdownPipeline = $builder.Build()
	return $Script:CachedBaselineMarkdownPipeline
}

function ConvertFrom-BaselineMarkdownToFlowDocument
{
	<# .SYNOPSIS Renders a Markdown string into a WPF FlowDocument using Markdig.Wpf. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Markdown
	)

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		[void](Initialize-BaselineMarkdownRuntime)
	}

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		throw 'Markdig runtime is not available.'
	}

	return [Markdig.Wpf.Markdown]::ToFlowDocument([string]$Markdown)
}

<#
    .SYNOPSIS
#>
function ConvertFrom-BaselineMarkdownToAnchoredFlowDocument
{
	<#
		.SYNOPSIS
		Renders Markdown into a FlowDocument with anchor map and repaired hyperlinks.
		.DESCRIPTION
		Markdig.Wpf can drop fragment-only URLs from anchor links. This helper
		parses the Markdown AST with the same pipeline, pairs AST links/headings
		with the rendered FlowDocument, and returns enough metadata for callers to
		handle in-document navigation without replacing the README body.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Markdown
	)

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		[void](Initialize-BaselineMarkdownRuntime)
	}

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		throw 'Markdig runtime is not available.'
	}

	$pipeline = Get-BaselineMarkdownPipeline
	$ast = [Markdig.Markdown]::Parse([string]$Markdown, $pipeline)

	$allNodes = @([Markdig.Syntax.MarkdownObjectExtensions]::Descendants($ast))
	$astHeadings = @($allNodes | Where-Object { $_ -is [Markdig.Syntax.HeadingBlock] })
	$astLinks = @($allNodes | Where-Object { $_ -is [Markdig.Syntax.Inlines.LinkInline] })

	$astHeadingIds = New-Object System.Collections.Generic.List[string]
	foreach ($heading in $astHeadings)
	{
		$attributes = [Markdig.Renderers.Html.HtmlAttributesExtensions]::GetAttributes($heading)
		$id = if ($attributes -and $attributes.Id) { [string]$attributes.Id } else { $null }
		[void]$astHeadingIds.Add($id)
	}

	$astLinkUrls = New-Object System.Collections.Generic.List[string]
	foreach ($link in $astLinks)
	{
		[void]$astLinkUrls.Add([string]$link.Url)
	}

	$document = [Markdig.Wpf.Markdown]::ToFlowDocument([string]$Markdown)
	$docHeadings = New-Object System.Collections.Generic.List[System.Windows.Documents.Paragraph]
	$docHyperlinks = New-Object System.Collections.Generic.List[System.Windows.Documents.Hyperlink]
	$defaultFontSize = [double]$document.FontSize
	if ($defaultFontSize -le 0) { $defaultFontSize = 14.0 }

	$blockStack = New-Object System.Collections.Generic.Stack[object]
	foreach ($block in ($document.Blocks | ForEach-Object { $_ })) { $blockStack.Push($block) }
	$orderedBlocks = New-Object System.Collections.Generic.List[object]
	while ($blockStack.Count -gt 0)
	{
		$block = $blockStack.Pop()
		[void]$orderedBlocks.Insert(0, $block)
		if ($block -is [System.Windows.Documents.Section])
		{
			foreach ($subBlock in ($block.Blocks | ForEach-Object { $_ })) { $blockStack.Push($subBlock) }
		}
		elseif ($block -is [System.Windows.Documents.List])
		{
			foreach ($listItem in ($block.ListItems | ForEach-Object { $_ }))
			{
				foreach ($subBlock in ($listItem.Blocks | ForEach-Object { $_ })) { $blockStack.Push($subBlock) }
			}
		}
		elseif ($block -is [System.Windows.Documents.Table])
		{
			foreach ($rowGroup in ($block.RowGroups | ForEach-Object { $_ }))
			{
				foreach ($row in ($rowGroup.Rows | ForEach-Object { $_ }))
				{
					foreach ($cell in ($row.Cells | ForEach-Object { $_ }))
					{
						foreach ($subBlock in ($cell.Blocks | ForEach-Object { $_ })) { $blockStack.Push($subBlock) }
					}
				}
			}
		}
	}

	foreach ($block in $orderedBlocks)
	{
		if (-not ($block -is [System.Windows.Documents.Paragraph])) { continue }
		$paragraph = [System.Windows.Documents.Paragraph]$block
		try { $paragraphFontSize = [double]$paragraph.FontSize } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.ConvertFrom-BaselineMarkdownToAnchoredFlowDocument:catch3767' -Severity Debug }
		 $paragraphFontSize = 0.0 }
		if ($paragraphFontSize -gt ($defaultFontSize + 0.5))
		{
			[void]$docHeadings.Add($paragraph)
		}

		$inlineStack = New-Object System.Collections.Generic.Stack[object]
		foreach ($inline in ($paragraph.Inlines | ForEach-Object { $_ })) { $inlineStack.Push($inline) }
		$inlineOrdered = New-Object System.Collections.Generic.List[object]
		while ($inlineStack.Count -gt 0)
		{
			$inline = $inlineStack.Pop()
			[void]$inlineOrdered.Insert(0, $inline)
			if ($inline -is [System.Windows.Documents.Span])
			{
				foreach ($child in ($inline.Inlines | ForEach-Object { $_ })) { $inlineStack.Push($child) }
			}
		}
		foreach ($inline in $inlineOrdered)
		{
			if ($inline -is [System.Windows.Documents.Hyperlink]) { [void]$docHyperlinks.Add($inline) }
		}
	}

	$anchorMap = New-Object "System.Collections.Generic.Dictionary[string, System.Windows.Documents.Paragraph]"
	$headingPairs = [Math]::Min($astHeadingIds.Count, $docHeadings.Count)
	for ($i = 0; $i -lt $headingPairs; $i++)
	{
		$id = $astHeadingIds[$i]
		if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
		$docHeadings[$i].Tag = $id
		if (-not $anchorMap.ContainsKey($id)) { $anchorMap[$id] = $docHeadings[$i] }
	}

	$linkPairs = [Math]::Min($astLinkUrls.Count, $docHyperlinks.Count)
	for ($i = 0; $i -lt $linkPairs; $i++)
	{
		$url = $astLinkUrls[$i]
		if ([string]::IsNullOrWhiteSpace([string]$url)) { continue }
		$docHyperlinks[$i].Tag = $url
		try
		{
			$docHyperlinks[$i].NavigateUri = [System.Uri]::new([string]$url, [System.UriKind]::RelativeOrAbsolute)
		}
		catch
		{
			Write-EnvironmentSwallowedException -ErrorRecord $_ -Source 'Environment.Markdown.AssignHyperlinkUri'
		}
	}

	return [PSCustomObject]@{
		Document = $document
		AnchorMap = $anchorMap
		Hyperlinks = $docHyperlinks
	}
}

<#
    .SYNOPSIS
#>
function ConvertFrom-BaselineMarkdownToHtml
{
	<# .SYNOPSIS Renders Markdown to a complete HTML document using Markdig. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Markdown,

		[string]$BackgroundColor = '#1e1e2e',
		[string]$ForegroundColor = '#e6e6e6',
		[string]$MutedForegroundColor = '#a0a0a0',
		[string]$LinkColor = '#4da3ff',
		[string]$CodeBackgroundColor = '#2a2a3d'
	)

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		[void](Initialize-BaselineMarkdownRuntime)
	}

	if (-not (Test-BaselineMarkdownRuntimeReady))
	{
		throw 'Markdig runtime is not available.'
	}

	$bodyHtml = [Markdig.Markdown]::ToHtml([string]$Markdown, (Get-BaselineMarkdownPipeline))
	return @"
<!doctype html>
<html>
<head>
	<meta charset="utf-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1" />
	<style>
		:root {
			color-scheme: dark;
		}
		html, body {
			margin: 0;
			padding: 0;
			background: $BackgroundColor;
			color: $ForegroundColor;
			font-family: "Segoe UI", Arial, sans-serif;
			font-size: 14px;
			line-height: 1.6;
		}
		body {
			padding: 20px 24px;
		}
		main {
			max-width: 1100px;
			margin: 0 auto;
		}
		a {
			color: $LinkColor;
		}
		h1, h2, h3, h4, h5, h6 {
			color: $ForegroundColor;
			line-height: 1.2;
			margin-top: 1.4em;
			margin-bottom: 0.5em;
		}
		p, ul, ol, blockquote, table, pre {
			margin-top: 0;
			margin-bottom: 1em;
		}
		blockquote {
			margin-left: 0;
			padding: 0.75em 1em;
			border-left: 4px solid $LinkColor;
			background: rgba(255,255,255,0.04);
		}
		code {
			background: $CodeBackgroundColor;
			border-radius: 4px;
			padding: 0.15em 0.35em;
			color: $ForegroundColor;
			font-family: Consolas, "Courier New", monospace;
		}
		pre {
			background: $CodeBackgroundColor;
			border-radius: 8px;
			padding: 16px;
			overflow: auto;
		}
		pre code {
			background: transparent;
			padding: 0;
		}
		table {
			border-collapse: collapse;
			width: 100%;
		}
		th, td {
			border: 1px solid rgba(255,255,255,0.12);
			padding: 8px 10px;
			vertical-align: top;
		}
		th {
			background: rgba(255,255,255,0.06);
		}
		img {
			max-width: 100%;
			height: auto;
		}
		hr {
			border: 0;
			border-top: 1px solid rgba(255,255,255,0.12);
			margin: 1.5em 0;
		}
		.muted {
			color: $MutedForegroundColor;
		}
	</style>
</head>
<body>
	<main>
$bodyHtml
	</main>
</body>
</html>
"@
}

<#
    .SYNOPSIS
#>
function Initialize-BaselineWebView2Runtime
{
	<# .SYNOPSIS Loads the WebView2 assemblies from the hydrated runtime. #>
	[CmdletBinding()]
	param (
		[string]$ModuleRoot
	)

	if ($Script:CachedBaselineWebView2RuntimeLoaded) { return $true }

	if ([string]::IsNullOrWhiteSpace($ModuleRoot))
	{
		$ModuleRoot = $Script:SharedHelpersModuleRoot
	}

	if ([string]::IsNullOrWhiteSpace($ModuleRoot) -or -not (Test-Path -LiteralPath $ModuleRoot -PathType Container))
	{
		return $false
	}

	$librariesRoot = Join-Path $ModuleRoot 'Libraries'
	if (-not (Test-Path -LiteralPath $librariesRoot -PathType Container))
	{
		$librariesRoot = $null
	}

	$searchRoots = [System.Collections.Generic.List[string]]::new()
	if (-not [string]::IsNullOrWhiteSpace($librariesRoot))
	{
		[void]$searchRoots.Add($librariesRoot)
	}

	$commonRoots = @(
		'%ProgramFiles%\Microsoft Office\root\Office16\ADDINS\Microsoft Power Query for Excel Integrated\bin',
		'%ProgramFiles(x86)%\Microsoft Office\root\Office16\ADDINS\Microsoft Power Query for Excel Integrated\bin',
		'%WINDIR%\SystemApps\Shared\WebView2SDK',
		'%WINDIR%\WinSxS'
	)

	foreach ($rootTemplate in $commonRoots)
	{
		try
		{
			$rootPath = [Environment]::ExpandEnvironmentVariables($rootTemplate)
			if (-not [string]::IsNullOrWhiteSpace($rootPath) -and (Test-Path -LiteralPath $rootPath -PathType Container))
			{
				[void]$searchRoots.Add($rootPath)
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InitializeBaselineWebView2Runtime.ExpandSearchRoot' }
	}

	$loadOrder = @(
		'Microsoft.Web.WebView2.Core.dll',
		'Microsoft.Web.WebView2.WinForms.dll'
	)

	foreach ($dllName in $loadOrder)
	{
		$dllPath = $null
		foreach ($searchRoot in @($searchRoots))
		{
			$candidate = Join-Path $searchRoot $dllName
			if (Test-Path -LiteralPath $candidate -PathType Leaf)
			{
				$dllPath = $candidate
				break
			}
		}

		if (-not $dllPath) { continue }
		try { Add-Type -Path $dllPath -ErrorAction Stop } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.InitializeBaselineWebView2Runtime.AddAssembly' }
	}

	$Script:CachedBaselineWebView2RuntimeLoaded = ([System.Type]::GetType('Microsoft.Web.WebView2.WinForms.WebView2, Microsoft.Web.WebView2.WinForms') -ne $null)
	return [bool]$Script:CachedBaselineWebView2RuntimeLoaded
}

<#
    .SYNOPSIS
#>
function Test-BaselineWebView2RuntimeReady
{
	<# .SYNOPSIS Returns $true once WebView2 has been loaded into the runspace. #>
	return ([System.Type]::GetType('Microsoft.Web.WebView2.WinForms.WebView2, Microsoft.Web.WebView2.WinForms') -ne $null)
}

<#
    .SYNOPSIS
    Detect whether the current host is a virtual machine.

    .DESCRIPTION
    Returns $true when the Win32_ComputerSystem Model reports a known
    hypervisor signature. Used by guardrails that must not run on VMs (e.g.
    hardware-accelerated GPU scheduling). Production code and tests share this
    single helper so detection behavior stays aligned.
#>
function Test-IsVirtualMachine
{
	[CmdletBinding()]
	param()

	try
	{
		$model = [string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Model
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Environment.Helpers.Test-IsVirtualMachine:catch4060' -Severity Debug }

		return $false
	}

	return ($model -match 'Virtual|VMware|VBOX|KVM|QEMU|Xen|Hyper-V')
}
