function Resolve-UWPAppsParentPath
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$StartPath,

		[Parameter(Mandatory = $true)]
		[string]$FileName
	)

	$cursor = if (Test-Path -LiteralPath $StartPath -PathType Leaf) { Split-Path -Path $StartPath -Parent } else { $StartPath }
	while (-not [string]::IsNullOrWhiteSpace([string]$cursor))
	{
		$candidate = Join-Path -Path $cursor -ChildPath $FileName
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

function Resolve-UWPAppsGuiCommonPath
{
	param(
		[Parameter(Mandatory = $false)]
		[string]$StartPath
	)

	if ([string]::IsNullOrWhiteSpace([string]$StartPath))
	{
		return $null
	}

	return Resolve-UWPAppsParentPath -StartPath $StartPath -FileName 'GUICommon.psm1'
}

$uwpAppsSeedPath = if (-not [string]::IsNullOrWhiteSpace([string]$PSCommandPath))
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
$modulePath = if ($uwpAppsSeedPath) { Resolve-UWPAppsParentPath -StartPath $uwpAppsSeedPath -FileName 'UWPApps.psm1' } else { $null }
