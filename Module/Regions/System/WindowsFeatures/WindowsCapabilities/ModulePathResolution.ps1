function Resolve-SystemPickerModulePath
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$StartPath
	)

	$cursor = if (Test-Path -LiteralPath $StartPath -PathType Leaf) { Split-Path -Path $StartPath -Parent } else { $StartPath }
	while (-not [string]::IsNullOrWhiteSpace([string]$cursor))
	{
		$candidate = Join-Path -Path $cursor -ChildPath 'System.WindowsFeatures.psm1'
		if (Test-Path -LiteralPath $candidate -PathType Leaf)
		{
			return $candidate
		}

		$parent = Split-Path -Path $cursor -Parent
		if ([string]::Equals([string]$parent, [string]$cursor, [System.StringComparison]::OrdinalIgnoreCase))
		{
			break
		}
		$cursor = $parent
	}

	return $null
}

$systemPickerSeedPath = if (-not [string]::IsNullOrWhiteSpace([string]$PSCommandPath))
	{
		[string]$PSCommandPath
	}
	elseif ($MyInvocation.MyCommand.Module -and -not [string]::IsNullOrWhiteSpace([string]$MyInvocation.MyCommand.Module.Path))
	{
		[string]$MyInvocation.MyCommand.Module.Path
	}
	else
	{
		$null
	}
$modulePath = if ($systemPickerSeedPath) { Resolve-SystemPickerModulePath -StartPath $systemPickerSeedPath } else { $null }
