using module ..\Logging.psm1
using module ..\SharedHelpers.psm1


#region Cursors

<#
	.SYNOPSIS
	Free Windows 11 cursors



.DESCRIPTION

Applies the Baseline behavior for free Windows 11 cursors.
	.PARAMETER Dark
	Download and install the dark cursor pack

	.PARAMETER Light
	Download and install the light cursor pack

	.PARAMETER Default
	Set default cursors

	.EXAMPLE
	Cursors -Dark

	.EXAMPLE
	Cursors -Light

	.EXAMPLE
	Cursors -Default

	.NOTES
	The 14/12/24 version

	.NOTES
	Current user
#>
function Expand-CursorArchiveFolder
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$ArchivePath,

		[Parameter(Mandatory = $true)]
		[string]
		$DestinationPath,

		[Parameter(Mandatory = $true)]
		[string]
		$FolderName
	)

	& "$env:SystemRoot\System32\tar.exe" -xf $ArchivePath -C $DestinationPath --strip-components=1 "$FolderName/" | Out-Null
	if ($LASTEXITCODE -ne 0)
	{
		throw "tar.exe returned exit code $LASTEXITCODE"
	}
}
<#
    .SYNOPSIS
    Return the cursor archive URL configured for Baseline.

    .DESCRIPTION
    Reads BASELINE_CURSOR_ARCHIVE_URL from the process environment and throws when it is not set so cursor installation fails with a clear error.

    .EXAMPLE
    Get-BaselineCursorArchiveUrl
#>
function Get-BaselineCursorArchiveUrl
{
	$cursorArchiveUrl = [string]$env:BASELINE_CURSOR_ARCHIVE_URL
	if ([string]::IsNullOrWhiteSpace($cursorArchiveUrl))
	{
		throw 'BASELINE_CURSOR_ARCHIVE_URL is not set.'
	}

	return $cursorArchiveUrl
}

<#
    .SYNOPSIS
    Runs cursors.

    #>

function Cursors
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Dark"
		)]
		[switch]
		$Dark,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Light"
		)]
		[switch]
		$Light,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	if (-not $Default)
	{
		$DownloadsFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
		$cursorArchivePath = Join-Path $DownloadsFolder 'Windows11Cursors.zip'
		$cursorArchiveUrl = Get-BaselineCursorArchiveUrl

		try
		{
			# Download cursors, then verify the
			Invoke-DownloadFile `
				-Uri $cursorArchiveUrl `
				-OutFile $cursorArchivePath
			$null = Assert-FileHash `
				-Path $cursorArchivePath `
				-ExpectedSha256 '04C9A4797F02AB88FD5DF15A9377A32B3F66497F05CAF89460F3441968A7024C' `
				-Label 'Windows 11 cursor archive'
		}
		catch
		{
			LogError ("Failed to download or verify the Windows cursor archive: {0}" -f $_.Exception.Message)
			return
		}
	}

		. (Join-Path $PSScriptRoot 'Cursors\Cursors\Cursors.ps1')

	# Reload cursor on-the-fly
	$Signature = @{
		Namespace          = "WinAPI"
		Name               = "Cursor"
		Language           = "CSharp"
		CompilerParameters = $CompilerParameters
		MemberDefinition   = @"
[DllImport("user32.dll", EntryPoint = "SystemParametersInfo")]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, uint pvParam, uint fWinIni);
"@
	}
	if (-not ("WinAPI.Cursor" -as [type]))
	{
		Add-Type @Signature
	}
	[void][WinAPI.Cursor]::SystemParametersInfo(0x0057, 0, $null, 0)
}

#endregion Cursors
$ExportedFunctions = @(
    'Cursors',
    'Expand-CursorArchiveFolder',
    'Get-BaselineCursorArchiveUrl'
)
Export-ModuleMember -Function $ExportedFunctions
