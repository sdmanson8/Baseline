# Persistence helper slice for Baseline.
# Provides standardized JSON document persistence with schema versioning.
# All writes use UTF-8 no BOM (project convention from L-6 fix).
# JSON serialization uses -Depth 16 (project convention from D-45 fix).

function Get-BaselineDataDirectory
{
	<#
		.SYNOPSIS
		Returns the path to the Baseline persistent data directory under LOCALAPPDATA.
		Creates the directory if it does not exist.
	#>
	[CmdletBinding()]
	param ()

	$dataDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Baseline')
	if (-not (Test-Path -LiteralPath $dataDir))
	{
		try
		{
			[void](New-Item -Path $dataDir -ItemType Directory -Force)
		}
		catch
		{
			LogWarning "Failed to create Baseline data directory '$dataDir': $_"
			throw
		}
	}
	return $dataDir
}

function Write-BaselineDocument
{
	<#
		.SYNOPSIS
		Writes an object as a versioned JSON document with a standard envelope.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$FilePath,

		[Parameter(Mandatory)]
		[string]$Schema,

		[Parameter(Mandatory)]
		[int]$SchemaVersion,

		[Parameter(Mandatory)]
		[object]$Data
	)

	$baselineVersion = $null
	if (Get-Command -Name 'Get-BaselineDisplayVersion' -ErrorAction SilentlyContinue)
	{
		try { $baselineVersion = Get-BaselineDisplayVersion } catch { }
	}

	$envelope = [ordered]@{
		Schema          = $Schema
		SchemaVersion   = $SchemaVersion
		CreatedAt       = [System.DateTime]::UtcNow.ToString('o')
		MachineName     = $env:COMPUTERNAME
		BaselineVersion = $baselineVersion
		Data            = $Data
	}

	$parentDir = Split-Path -Path $FilePath -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		[void](New-Item -Path $parentDir -ItemType Directory -Force)
	}

	$json = ConvertTo-Json -InputObject $envelope -Depth 16
	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	[System.IO.File]::WriteAllText($FilePath, $json, $utf8NoBom)
}

function Read-BaselineDocument
{
	<#
		.SYNOPSIS
		Reads a versioned JSON document and optionally validates the schema field.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$FilePath,

		[string]$ExpectedSchema
	)

	if (-not (Test-Path -LiteralPath $FilePath))
	{
		throw "Baseline document not found: $FilePath"
	}

	try
	{
		$content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
		$document = $content | ConvertFrom-Json
	}
	catch
	{
		throw "Failed to read or parse Baseline document '$FilePath': $_"
	}

	if (-not [string]::IsNullOrWhiteSpace($ExpectedSchema))
	{
		$actualSchema = if ($document.PSObject.Properties['Schema']) { $document.Schema } else { $null }
		if ($actualSchema -ne $ExpectedSchema)
		{
			throw "Schema mismatch in '$FilePath': expected '$ExpectedSchema', found '$actualSchema'."
		}
	}

	return $document
}

function Add-BaselineAuditRecord
{
	<#
		.SYNOPSIS
		Appends a single timestamped record as a JSON line to an audit log file.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$FilePath,

		[Parameter(Mandatory)]
		[object]$Record
	)

	$parentDir = Split-Path -Path $FilePath -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		[void](New-Item -Path $parentDir -ItemType Directory -Force)
	}

	# Build a line object with Timestamp prepended, then the Record's properties.
	$lineObj = [ordered]@{
		Timestamp = [System.DateTime]::UtcNow.ToString('o')
	}

	if ($Record -is [hashtable] -or $Record -is [System.Collections.Specialized.OrderedDictionary])
	{
		foreach ($key in $Record.Keys)
		{
			$lineObj[$key] = $Record[$key]
		}
	}
	else
	{
		foreach ($prop in $Record.PSObject.Properties)
		{
			$lineObj[$prop.Name] = $prop.Value
		}
	}

	$jsonLine = ConvertTo-Json -InputObject $lineObj -Depth 16 -Compress
	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

	try
	{
		# Append with newline. Using StreamWriter to ensure append mode with UTF-8 no BOM.
		$stream = New-Object System.IO.StreamWriter($FilePath, $true, $utf8NoBom)
		try
		{
			$stream.WriteLine($jsonLine)
		}
		finally
		{
			$stream.Close()
		}
	}
	catch
	{
		LogWarning "Failed to append audit record to '$FilePath': $_"
		throw
	}
}

function Read-BaselineAuditLog
{
	<#
		.SYNOPSIS
		Reads a JSON Lines audit log file, with optional timestamp filtering and record limit.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$FilePath,

		[System.DateTime]$Since,

		[int]$MaxRecords = 1000
	)

	if (-not (Test-Path -LiteralPath $FilePath))
	{
		return @()
	}

	$results = [System.Collections.ArrayList]::new()

	try
	{
		$lines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
		foreach ($line in $lines)
		{
			if ([string]::IsNullOrWhiteSpace($line)) { continue }

			try
			{
				$record = $line | ConvertFrom-Json
			}
			catch
			{
				LogWarning "Skipping malformed audit line in '$FilePath': $_"
				continue
			}

			if ($PSBoundParameters.ContainsKey('Since') -and $record.PSObject.Properties['Timestamp'])
			{
				$ts = [System.DateTime]::MinValue
				if ([System.DateTime]::TryParse($record.Timestamp, [ref]$ts))
				{
					if ($ts -lt $Since) { continue }
				}
			}

			[void]$results.Add($record)
			if ($results.Count -ge $MaxRecords) { break }
		}
	}
	catch
	{
		LogWarning "Failed to read audit log '$FilePath': $_"
		return @()
	}

	return @($results)
}

function Test-BaselineDocumentSchema
{
	<#
		.SYNOPSIS
		Validates that a parsed document matches the expected schema name and minimum version.
	#>
	param (
		[Parameter(Mandatory)]
		[object]$Document,

		[Parameter(Mandatory)]
		[string]$ExpectedSchema,

		[int]$MinVersion
	)

	if ($null -eq $Document) { return $false }

	$actualSchema = if ($Document.PSObject.Properties['Schema']) { $Document.Schema } else { $null }
	if ($actualSchema -ne $ExpectedSchema)
	{
		return $false
	}

	if ($PSBoundParameters.ContainsKey('MinVersion'))
	{
		$actualVersion = if ($Document.PSObject.Properties['SchemaVersion']) { [int]$Document.SchemaVersion } else { 0 }
		if ($actualVersion -lt $MinVersion)
		{
			return $false
		}
	}

	return $true
}
