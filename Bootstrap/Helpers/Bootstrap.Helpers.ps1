<#
    .SYNOPSIS
    Bootstrap startup helpers for Baseline.

    .DESCRIPTION
    Contains helper functions used by Bootstrap\Baseline.ps1 during startup.
    Public function names, signatures, defaults, and return shapes stay owned by the parent startup flow.
#>

<#
    .SYNOPSIS
#>

function Get-BaselineBootstrapSessionStatePath
{
	param([string]$AppName = 'Baseline')

	$stateRoot = [System.Environment]::GetEnvironmentVariable('BASELINE_STATE_ROOT')
	if (-not [string]::IsNullOrWhiteSpace([string]$stateRoot))
	{
		$profileRoot = Join-Path $stateRoot 'Profiles'
	}
	elseif ($env:LOCALAPPDATA)
	{
		$profileRoot = Join-Path $env:LOCALAPPDATA "$AppName\Profiles"
	}
	else
	{
		$profileRoot = Join-Path $env:TEMP "$AppName\Profiles"
	}

	return (Join-Path $profileRoot "$AppName-last-session.json")
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineBootstrapUICulture
{
	param([string]$FallbackUICulture = $PSUICulture)

	$envLanguage = [string]([System.Environment]::GetEnvironmentVariable('BASELINE_LANGUAGE'))
	if (-not [string]::IsNullOrWhiteSpace($envLanguage))
	{
		return $envLanguage.Trim()
	}

	$sessionPath = Get-BaselineBootstrapSessionStatePath
	if (Test-Path -LiteralPath $sessionPath -PathType Leaf)
	{
		try
		{
			$sessionPayload = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
			$sessionLanguage = $null
			if ($sessionPayload -and $sessionPayload.State -and $sessionPayload.State.Language)
			{
				$sessionLanguage = [string]$sessionPayload.State.Language
			}
			elseif ($sessionPayload -and $sessionPayload.Language)
			{
				$sessionLanguage = [string]$sessionPayload.Language
			}

			if (-not [string]::IsNullOrWhiteSpace($sessionLanguage))
			{
				return $sessionLanguage.Trim()
			}
		}
		catch
		{
			$null = $_
		}
	}

	if ([string]::IsNullOrWhiteSpace([string]$FallbackUICulture))
	{
		return 'en-US'
	}

	return [string]$FallbackUICulture
}

function Resolve-BaselineCurrentVersion
{
	$psdPath = Join-Path $Script:ModuleRoot 'Baseline.psd1'
	try
	{
		if (Test-Path -LiteralPath $psdPath -PathType Leaf)
		{
			$data = Import-PowerShellDataFile -LiteralPath $psdPath
			if ($data -and -not [string]::IsNullOrWhiteSpace([string]$data.ModuleVersion))
			{
				return [string]$data.ModuleVersion
			}
			Write-LaunchTrace ('Version lookup: Baseline.psd1 at {0} missing ModuleVersion' -f $psdPath)
		}
		else
		{
			Write-LaunchTrace ('Version lookup: Baseline.psd1 not found at {0}' -f $psdPath)
		}
	}
	catch
	{
		Write-LaunchTrace ('Version lookup via Baseline.psd1 failed: {0}' -f $_.Exception.Message)
	}

	# Fall back to the launcher assembly metadata. The Baseline.exe PE stamps
	# AssemblyInformationalVersion at build time, so even if the embedded
	# Baseline.psd1 cannot be read we can still recover the real version.
	try
	{
		$exePath = [string]$env:BASELINE_LAUNCHER_PATH
		if (-not [string]::IsNullOrWhiteSpace($exePath) -and (Test-Path -LiteralPath $exePath -PathType Leaf))
		{
			$info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
			$candidate = $info.ProductVersion
			if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = $info.FileVersion }
			if (-not [string]::IsNullOrWhiteSpace($candidate))
			{
				$plus = $candidate.IndexOf('+')
				if ($plus -gt 0) { $candidate = $candidate.Substring(0, $plus) }
				return [string]$candidate
			}
		}
	}
	catch
	{
		Write-LaunchTrace ('Version lookup via launcher assembly failed: {0}' -f $_.Exception.Message)
	}

	return '0.0.0'
}

<#
    .SYNOPSIS
#>

function Import-BaselineIncludedTweakLibraries
{
	param (
		[string[]]$IncludePaths = @()
	)

	$resolvedIncludePaths = @(
		@($IncludePaths) |
			Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
			ForEach-Object { ([string]$_).Trim() }
	)

	Set-HeadlessPresetIncludedFunctionSet -FunctionNames @()
	Set-HeadlessPresetIncludedTweakLibraryPathSet -IncludePaths @()
	if ($resolvedIncludePaths.Count -eq 0)
	{
		Write-LaunchTrace 'No included tweak libraries were supplied.'
		return
	}

	$includedFunctionNames = [System.Collections.Generic.List[string]]::new()
	foreach ($includePath in $resolvedIncludePaths)
	{
		if ($includePath -notmatch '\.(psd1|psm1)$')
		{
			throw "Included tweak library must be a .psd1 or .psm1 file: $includePath"
		}

		$resolvedIncludePath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $includePath -ErrorAction Stop).Path)
		Write-LaunchTrace ("Importing included tweak library: {0}" -f $resolvedIncludePath)

		$importedModule = Import-Module -Name $resolvedIncludePath -Force -Global -PassThru -ErrorAction Stop
		if ($null -eq $importedModule -or -not $importedModule.ExportedFunctions)
		{
			continue
		}

		foreach ($functionName in @($importedModule.ExportedFunctions.Keys))
		{
			if ([string]::IsNullOrWhiteSpace([string]$functionName))
			{
				continue
			}

			[void]$includedFunctionNames.Add(([string]$functionName).Trim())
		}
	}

	Set-HeadlessPresetIncludedTweakLibraryPathSet -IncludePaths @($resolvedIncludePaths)
	Set-HeadlessPresetIncludedFunctionSet -FunctionNames @($includedFunctionNames)
}

<#
    .SYNOPSIS
#>

function Get-ErrorDetailText
{
	param(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.ErrorRecord]
		$ErrorRecord
	)

	$detailParts = @()
	if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.Exception.Message))
	{
		$detailParts += $ErrorRecord.Exception.Message
	}

	if ($ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage))
	{
		$detailParts += $ErrorRecord.InvocationInfo.PositionMessage.Trim()
	}

	if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace))
	{
		$detailParts += "Stack:`n$($ErrorRecord.ScriptStackTrace.Trim())"
	}

	return ($detailParts -join "`n`n")
}

<#
    .SYNOPSIS
#>

function Get-HeadlessCommandInvocation
{
	param
	(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.Language.CommandAst]
		$CommandAst
	)

	$namedArguments = @{}
	$positionalArguments = [System.Collections.Generic.List[object]]::new()
	$displayArguments = [System.Collections.Generic.List[string]]::new()

	for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++)
	{
		$element = $CommandAst.CommandElements[$i]

		if ($element -is [System.Management.Automation.Language.CommandParameterAst])
		{
			$parameterName = $element.ParameterName
			$valueAst = $null

			if ($element.Argument)
			{
				$valueAst = $element.Argument
			}
			elseif (($i + 1) -lt $CommandAst.CommandElements.Count -and $CommandAst.CommandElements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst])
			{
				$i++
				$valueAst = $CommandAst.CommandElements[$i]
			}

			if ($null -ne $valueAst)
			{
				$namedArguments[$parameterName] = $valueAst.SafeGetValue()
				$displayArguments.Add("-$parameterName $($valueAst.Extent.Text)")
			}
			else
			{
				$namedArguments[$parameterName] = $true
				$displayArguments.Add("-$parameterName")
			}

			continue
		}

		$positionalArguments.Add($element.SafeGetValue())
		$displayArguments.Add($element.Extent.Text)
	}

	[pscustomobject]@{
		NamedArguments = $namedArguments
		PositionalArguments = $positionalArguments.ToArray()
		DisplayArguments = $displayArguments.ToArray()
	}
}

function ConvertTo-HeadlessCommandArgumentLiteral
{
	[CmdletBinding()]
	[OutputType([string])]
	param
	(
		[AllowNull()]
		[object]
		$Value
	)

	if ($null -eq $Value)
	{
		return '$null'
	}

	if ($Value -is [bool])
	{
		if ([bool]$Value) { return '$true' }
		return '$false'
	}

	if ($Value -is [System.Array])
	{
		$items = @($Value | ForEach-Object { ConvertTo-HeadlessCommandArgumentLiteral -Value $_ })
		return ('@({0})' -f ($items -join ', '))
	}

	if ($Value -is [byte] -or
		$Value -is [sbyte] -or
		$Value -is [int16] -or
		$Value -is [uint16] -or
		$Value -is [int] -or
		$Value -is [uint32] -or
		$Value -is [long] -or
		$Value -is [uint64] -or
		$Value -is [single] -or
		$Value -is [double] -or
		$Value -is [decimal])
	{
		return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture))
	}

	$text = [string]$Value
	return ("'{0}'" -f ($text -replace "'", "''"))
}

function Test-BaselinePowerShellRemotingSession
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[object]$SenderInfo = $(Get-Variable -Name 'PSSenderInfo' -ValueOnly -ErrorAction SilentlyContinue)
	)

	return ($null -ne $SenderInfo)
}

function Show-BaselineConsoleSplash
{
	[CmdletBinding()]
	param (
		[string]$PresetName
	)

	$subtitle = if ([string]::IsNullOrWhiteSpace([string]$PresetName))
	{
		'Loading local interactive console'
	}
	else
	{
		"Loading local interactive console with preset '$PresetName'"
	}

	try { Clear-Host } catch { $null = $_ }
	Write-Host ''
	Write-Host '  Baseline' -ForegroundColor Cyan
	Write-Host "  $subtitle" -ForegroundColor DarkGray
	Write-Host ''

	$frames = @('|', '/', '-', '\')
	for ($i = 0; $i -lt 16; $i++)
	{
		$frame = $frames[$i % $frames.Count]
		$dotCount = ($i % 4)
		$dots = ''.PadRight($dotCount, '.')
		Write-Host ("`r  [{0}] Preparing menu{1}   " -f $frame, $dots) -NoNewline -ForegroundColor Cyan
		Start-Sleep -Milliseconds 55
	}

	Write-Host "`r  [*] Console menu ready       " -ForegroundColor Green
	Start-Sleep -Milliseconds 120
}

function New-BaselineConsoleGuiCatalog
{
	[CmdletBinding()]
	param (
		[object[]]$Manifest,
		[string[]]$PreselectedCommands = @()
	)

	$commandByFunction = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($commandLine in @($PreselectedCommands))
	{
		if ([string]::IsNullOrWhiteSpace([string]$commandLine)) { continue }
		$functionName = Get-HeadlessPresetCommandFunctionName -CommandLine ([string]$commandLine)
		if ([string]::IsNullOrWhiteSpace([string]$functionName)) { continue }
		$commandByFunction[[string]$functionName] = ([string]$commandLine).Trim()
	}

	$items = [System.Collections.Generic.List[object]]::new()
	$categories = [System.Collections.Generic.List[string]]::new()
	$categorySeen = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
	$expanded = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
	$index = 0

	foreach ($entry in @($Manifest))
	{
		if ($null -eq $entry) { continue }

		$functionName = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Function')
		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		$defaultCommand = Get-TweakManifestDefaultCommand -Entry $entry
		if ([string]::IsNullOrWhiteSpace([string]$defaultCommand)) { continue }

		$name = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Name')
		if ([string]::IsNullOrWhiteSpace($name)) { $name = $functionName }

		$category = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Category')
		if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Other' }

		if (-not $categorySeen.Contains($category))
		{
			$categorySeen[$category] = $true
			[void]$categories.Add($category)
			$expanded[$category] = $true
		}

		$preselected = [bool]$commandByFunction.Contains($functionName)
		$command = if ($preselected) { [string]$commandByFunction[$functionName] } else { [string]$defaultCommand }
		$risk = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Risk')
		$type = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Type')

		[void]$items.Add([pscustomobject]@{
			Index       = $index
			Name        = $name
			Function    = $functionName
			Category    = $category
			Type        = $type
			Risk        = $risk
			CommandLine = $command
			Selected    = $preselected
		})
		$index++
	}

	return [pscustomobject]@{
		Categories = $categories.ToArray()
		Items      = $items.ToArray()
		Expanded   = $expanded
	}
}

function Get-BaselineConsoleGuiCategoryStats
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Catalog,
		[Parameter(Mandatory = $true)]
		[string]$Category
	)

	$total = 0
	$selected = 0
	foreach ($item in @($Catalog.Items))
	{
		if ($null -eq $item -or -not ([string]$item.Category).Equals($Category, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
		$total++
		if ([bool]$item.Selected) { $selected++ }
	}

	return [pscustomobject]@{
		Total = $total
		Selected = $selected
	}
}

function Get-BaselineConsoleGuiRowList
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Catalog
	)

	$rows = [System.Collections.Generic.List[object]]::new()
	foreach ($category in @($Catalog.Categories))
	{
		if ([string]::IsNullOrWhiteSpace([string]$category)) { continue }
		$expanded = if ($Catalog.Expanded.Contains($category)) { [bool]$Catalog.Expanded[$category] } else { $true }
		$stats = Get-BaselineConsoleGuiCategoryStats -Catalog $Catalog -Category ([string]$category)
		[void]$rows.Add([pscustomobject]@{
			Kind     = 'Category'
			Category = [string]$category
			Expanded = $expanded
			Selected = [int]$stats.Selected
			Total    = [int]$stats.Total
			Item     = $null
		})

		if (-not $expanded) { continue }
		foreach ($item in @($Catalog.Items))
		{
			if ($null -eq $item -or -not ([string]$item.Category).Equals([string]$category, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
			[void]$rows.Add([pscustomobject]@{
				Kind     = 'Item'
				Category = [string]$category
				Expanded = $true
				Selected = if ([bool]$item.Selected) { 1 } else { 0 }
				Total    = 1
				Item     = $item
			})
		}
	}

	return $rows.ToArray()
}

function Set-BaselineConsoleGuiCategorySelection
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Catalog,
		[Parameter(Mandatory = $true)]
		[string]$Category,
		[Parameter(Mandatory = $true)]
		[bool]$Selected
	)

	foreach ($item in @($Catalog.Items))
	{
		if ($null -eq $item -or -not ([string]$item.Category).Equals($Category, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
		$item.Selected = [bool]$Selected
	}
}

function Get-BaselineConsoleGuiSelectedCommands
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Catalog
	)

	$commands = [System.Collections.Generic.List[string]]::new()
	foreach ($item in @($Catalog.Items | Sort-Object Index))
	{
		if ($null -eq $item -or -not [bool]$item.Selected) { continue }
		if ([string]::IsNullOrWhiteSpace([string]$item.CommandLine)) { continue }
		[void]$commands.Add([string]$item.CommandLine)
	}

	return $commands.ToArray()
}

function Write-BaselineConsoleGuiView
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Catalog,
		[Parameter(Mandatory = $true)]
		[object[]]$Rows,
		[int]$CursorIndex = 0,
		[string]$PresetName
	)

	$selectedCount = @(Get-BaselineConsoleGuiSelectedCommands -Catalog $Catalog).Count
	$totalCount = @($Catalog.Items).Count

	try { Clear-Host } catch { $null = $_ }
	Write-Host ''
	Write-Host '  Baseline Console' -ForegroundColor Cyan
	if ([string]::IsNullOrWhiteSpace([string]$PresetName))
	{
		Write-Host "  Selected: $selectedCount / $totalCount" -ForegroundColor DarkGray
	}
	else
	{
		Write-Host "  Preset: $PresetName    Selected: $selectedCount / $totalCount" -ForegroundColor DarkGray
	}
	Write-Host '  Up/Down navigate  Space select  Enter run  A select category  C collapse/expand  Q quit' -ForegroundColor DarkGray
	Write-Host ''

	$height = 24
	try
	{
		if ([Console]::WindowHeight -gt 10)
		{
			$height = [Math]::Max(8, [Console]::WindowHeight - 8)
		}
	}
	catch
	{
		$height = 24
	}

	$start = 0
	if ($CursorIndex -ge $height)
	{
		$start = $CursorIndex - $height + 1
	}
	$end = [Math]::Min($Rows.Count - 1, $start + $height - 1)

	for ($i = $start; $i -le $end; $i++)
	{
		$row = $Rows[$i]
		$isCurrent = ($i -eq $CursorIndex)
		$prefix = if ($isCurrent) { '>' } else { ' ' }

		if ([string]$row.Kind -eq 'Category')
		{
			$marker = if ([bool]$row.Expanded) { '[-]' } else { '[+]' }
			$text = (' {0} {1} {2} ({3}/{4})' -f $prefix, $marker, [string]$row.Category, [int]$row.Selected, [int]$row.Total)
			Write-Host $text -ForegroundColor $(if ($isCurrent) { 'Cyan' } else { 'Yellow' })
			continue
		}

		$item = $row.Item
		$check = if ([bool]$item.Selected) { '[x]' } else { '[ ]' }
		$risk = if ([string]::IsNullOrWhiteSpace([string]$item.Risk)) { '?' } else { [string]$item.Risk }
		$text = (' {0}   {1} {2}  ({3}, {4})' -f $prefix, $check, [string]$item.Name, [string]$item.Function, $risk)
		$color = if ($isCurrent) { 'Cyan' } elseif ([bool]$item.Selected) { 'Green' } else { 'Gray' }
		Write-Host $text -ForegroundColor $color
	}

	if ($Rows.Count -gt $height)
	{
		Write-Host ''
		Write-Host ("  Showing {0}-{1} of {2}" -f ($start + 1), ($end + 1), $Rows.Count) -ForegroundColor DarkGray
	}
}

function Show-BaselineConsoleGui
{
	[CmdletBinding()]
	param (
		[object[]]$Manifest,
		[string[]]$PreselectedCommands = @(),
		[string]$PresetName
	)

	try
	{
		if ([Console]::IsInputRedirected)
		{
			throw '-ConsoleGui requires an interactive console. Use -NoGui with -Preset, -Functions, or -ProfilePath for automation.'
		}
	}
	catch [System.InvalidOperationException]
	{
		throw '-ConsoleGui requires an interactive console. Use -NoGui with -Preset, -Functions, or -ProfilePath for automation.'
	}

	Show-BaselineConsoleSplash -PresetName $PresetName
	$catalog = New-BaselineConsoleGuiCatalog -Manifest $Manifest -PreselectedCommands $PreselectedCommands
	if (-not $catalog -or -not $catalog.Items -or @($catalog.Items).Count -eq 0)
	{
		throw 'No executable manifest entries are available for the console menu.'
	}

	$cursor = 0
	while ($true)
	{
		$rows = @(Get-BaselineConsoleGuiRowList -Catalog $catalog)
		if ($rows.Count -eq 0)
		{
			return @()
		}
		if ($cursor -lt 0) { $cursor = 0 }
		if ($cursor -ge $rows.Count) { $cursor = $rows.Count - 1 }

		Write-BaselineConsoleGuiView -Catalog $catalog -Rows $rows -CursorIndex $cursor -PresetName $PresetName
		$key = [Console]::ReadKey($true)

		switch ($key.Key)
		{
			'UpArrow'
			{
				if ($cursor -gt 0) { $cursor-- }
				continue
			}
			'DownArrow'
			{
				if ($cursor -lt ($rows.Count - 1)) { $cursor++ }
				continue
			}
			'Spacebar'
			{
				$row = $rows[$cursor]
				if ([string]$row.Kind -eq 'Category')
				{
					$selectCategory = ([int]$row.Selected -lt [int]$row.Total)
					Set-BaselineConsoleGuiCategorySelection -Catalog $catalog -Category ([string]$row.Category) -Selected $selectCategory
				}
				elseif ($row.Item)
				{
					$row.Item.Selected = -not [bool]$row.Item.Selected
				}
				continue
			}
			'Enter'
			{
				return @(Get-BaselineConsoleGuiSelectedCommands -Catalog $catalog)
			}
			'A'
			{
				$row = $rows[$cursor]
				$category = [string]$row.Category
				if (-not [string]::IsNullOrWhiteSpace($category))
				{
					Set-BaselineConsoleGuiCategorySelection -Catalog $catalog -Category $category -Selected $true
				}
				continue
			}
			'C'
			{
				$row = $rows[$cursor]
				$category = [string]$row.Category
				if (-not [string]::IsNullOrWhiteSpace($category))
				{
					$current = if ($catalog.Expanded.Contains($category)) { [bool]$catalog.Expanded[$category] } else { $true }
					$catalog.Expanded[$category] = -not $current
				}
				continue
			}
			'Q'
			{
				return $null
			}
			'Escape'
			{
				return $null
			}
		}
	}
}

<#
    .SYNOPSIS
    Resolves the bootstrap preset token.

    .DESCRIPTION
    Selects the explicit preset value or BASELINE_PRESET environment value and validates that it is safe to forward to the installed launcher.
#>
function Resolve-BootstrapPreset
{
    param(
        [string]$Preset,
        [string]$EnvironmentPreset = $env:BASELINE_PRESET
    )

    $candidate = if ([string]::IsNullOrWhiteSpace($Preset)) { $EnvironmentPreset } else { $Preset }
    if ([string]::IsNullOrWhiteSpace($candidate))
    {
        return $null
    }

    if ($candidate -notmatch '^[A-Za-z0-9_.-]+$')
    {
        throw ("Invalid preset token '{0}'. Use letters, numbers, dots, underscores, or hyphens only." -f $candidate)
    }

    return [string]$candidate
}

<#
    .SYNOPSIS
    Computes a SHA-256 hash for a bootstrap file.

    .DESCRIPTION
    Returns an uppercase SHA-256 hash for a file using Get-FileHash when available, with a .NET cryptography path for older hosts.
#>
function Get-BootstrapFileSha256
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "File was not found: $Path"
    }

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

<#
    .SYNOPSIS
    Reads the release integrity manifest.

    .DESCRIPTION
    Loads the release SHA-256 manifest and verifies that it uses the expected schema shape and algorithm.
#>
function Get-BootstrapReleaseIntegrityManifest
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf))
    {
        throw "Release integrity manifest was not found: $ManifestPath"
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.algorithm -ne 'sha256')
    {
        throw "Unsupported release integrity manifest algorithm '$([string]$manifest.algorithm)'."
    }

    if (-not $manifest.PSObject.Properties['files'] -or -not $manifest.files)
    {
        throw "Release integrity manifest does not contain a files map: $ManifestPath"
    }

    return $manifest
}

<#
    .SYNOPSIS
    Gets the expected SHA-256 hash for a release asset.

    .DESCRIPTION
    Looks up an asset name in the release integrity manifest and returns its expected uppercase SHA-256 hash.
#>
function Get-BootstrapReleaseAssetSha256
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    $manifest = Get-BootstrapReleaseIntegrityManifest -ManifestPath $ManifestPath
    $assetProperty = $manifest.files.PSObject.Properties[$AssetName]
    if (-not $assetProperty -or [string]::IsNullOrWhiteSpace([string]$assetProperty.Value))
    {
        throw "Release integrity manifest '$ManifestPath' does not contain a SHA-256 entry for '$AssetName'."
    }

    return ([string]$assetProperty.Value).Trim().ToUpperInvariant()
}

<#
    .SYNOPSIS
    Verifies a release asset hash.

    .DESCRIPTION
    Compares the local file SHA-256 hash with the expected hash recorded in the release integrity manifest.
#>
function Assert-BootstrapReleaseAssetHash
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$AssetName,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$Label = 'Downloaded file'
    )

    $expected = Get-BootstrapReleaseAssetSha256 -ManifestPath $ManifestPath -AssetName $AssetName
    $actual = Get-BootstrapFileSha256 -Path $FilePath
    if ($actual -ne $expected)
    {
        throw "$Label failed SHA-256 verification. Expected $expected but received $actual."
    }

    return $actual
}

<#
    .SYNOPSIS
    Finds the Baseline setup executable in an extracted release archive.

    .DESCRIPTION
    Searches the verified extracted archive for the Baseline setup executable and returns its full path.
#>
function Find-BootstrapSetupExecutable
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractRoot
    )

    $matches = @(Get-ChildItem -Path $ExtractRoot -Filter 'Baseline-*-setup.exe' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue)
    if ($matches.Count -ne 1)
    {
        throw "Expected exactly one Baseline-*-setup.exe under $ExtractRoot. Found $($matches.Count)."
    }

    return $matches[0].FullName
}

<#
    .SYNOPSIS
    Finds the installed Baseline executable.

    .DESCRIPTION
    Checks the common per-machine and per-user install locations and returns the first installed Baseline.exe path found.
#>
function Find-InstalledBaselineExecutable
{
    $candidates = @()
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')))
    {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $candidates += (Join-Path $root 'Baseline\Baseline.exe')
    }

    foreach ($candidate in $candidates)
    {
        if (Test-Path -LiteralPath $candidate -PathType Leaf)
        {
            return $candidate
        }
    }

    return $null
}

