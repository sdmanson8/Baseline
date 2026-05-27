# Structured CLI output helpers for headless / pilot-friendly piping.
#
# These helpers honour a runtime-set output format ('Text' | 'Json' | 'Ndjson')
# so any verb that produces results can be piped into downstream tooling.

<#
    .SYNOPSIS
#>

function Set-BaselineCliOutputFormat
{
	<# .SYNOPSIS Sets the active CLI output format. #>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Text', 'Json', 'Ndjson')]
		[string]$Format
	)

	$Global:BaselineCliOutputFormat = $Format
	[System.Environment]::SetEnvironmentVariable('BASELINE_CLI_OUTPUT', $Format, [System.EnvironmentVariableTarget]::Process)
}

<#
    .SYNOPSIS
#>

function Get-BaselineCliOutputFormat
{
	<# .SYNOPSIS Returns the active CLI output format. Defaults to Text. #>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	if ($Global:BaselineCliOutputFormat) { return [string]$Global:BaselineCliOutputFormat }
	$envFormat = [System.Environment]::GetEnvironmentVariable('BASELINE_CLI_OUTPUT')
	if (-not [string]::IsNullOrWhiteSpace([string]$envFormat)) { return [string]$envFormat }
	return 'Text'
}

function Format-BaselineCliResult
{
	<#
		.SYNOPSIS
		Serialises a result object according to the active CLI format and
		writes it to the host. Json/Ndjson always go to stdout (Write-Output
		bypasses Information/Verbose buffering).
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[AllowNull()]
		[object]$InputObject,

		[string]$Format,

		[switch]$NoNewLine
	)

	begin
	{
		$resolvedFormat = if ([string]::IsNullOrWhiteSpace([string]$Format)) { Get-BaselineCliOutputFormat } else { [string]$Format }
		$buffer = [System.Collections.Generic.List[object]]::new()
	}

	process
	{
		[void]$buffer.Add($InputObject)
	}

	end
	{
		switch ($resolvedFormat)
		{
			'Json'
			{
				$payload = if ($buffer.Count -eq 1) { $buffer[0] } else { $buffer.ToArray() }
				$json = ConvertTo-Json -InputObject $payload -Depth 16 -Compress:$false
				if ($NoNewLine) { [Console]::Out.Write($json) } else { [Console]::Out.WriteLine($json) }
				return
			}
			'Ndjson'
			{
				foreach ($item in $buffer)
				{
					if ($null -eq $item) { continue }
					$line = ConvertTo-Json -InputObject $item -Depth 16 -Compress
					[Console]::Out.WriteLine($line)
				}
				return
			}
			default
			{
				foreach ($item in $buffer) { Write-Output $item }
			}
		}
	}
}

<#
    .SYNOPSIS
#>

function Write-BaselineCliEvent
{
	<#
		.SYNOPSIS
		Emits a structured event line. In Text mode it falls back to a coloured
		Write-Host; in Json/Ndjson it writes a single ndjson record so a wrapping
		tool can consume the entire run as a stream.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Info', 'Warn', 'Error', 'Result', 'Progress')]
		[string]$Kind,

		[Parameter(Mandatory = $true)]
		[string]$Message,

		[hashtable]$Data = @{}
	)

	$format = Get-BaselineCliOutputFormat
	if ($format -eq 'Text')
	{
		$prefix = switch ($Kind)
		{
			'Warn'    { 'WARN ' }
			'Error'   { 'ERROR' }
			'Result'  { 'RESULT' }
			'Progress'{ '...  ' }
			default   { 'INFO ' }
		}
		Write-Host ('[{0}] {1}' -f $prefix, $Message)
		return
	}

	$record = [ordered]@{
		ts      = [DateTimeOffset]::UtcNow.ToString('o')
		kind    = $Kind
		message = $Message
	}
	foreach ($k in $Data.Keys) { $record[[string]$k] = $Data[$k] }

	[Console]::Out.WriteLine((ConvertTo-Json -InputObject $record -Depth 12 -Compress))
}
