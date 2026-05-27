<#
    .SYNOPSIS
    Module file integrity verification for Baseline.

    .DESCRIPTION
    Optional supply-chain hardening: when a manifest of expected file hashes
    ships alongside the module (Module/integrity.manifest.json), the loader
    can verify every covered file against its expected SHA-256 before
    importing. Tampered files cause the load to abort.

    Activation is opt-in via env var BASELINE_INTEGRITY_MODE. When unset or
    set to 'Off', verification is skipped entirely (zero overhead). Invalid
    values are configuration errors. When set to 'Strict', a missing manifest
    is a hard failure; when set to 'Audit', a missing manifest is logged and
    treated as a no-op, but an existing manifest with mismatched files still
    fails because the checked-in release integrity contract was violated.
#>

function Get-BaselineIntegrityManifestPath
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot
    )

    Join-Path -Path $ModuleRoot -ChildPath 'integrity.manifest.json'
}

function Get-BaselineIntegrityMode
{
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $value = [System.Environment]::GetEnvironmentVariable('BASELINE_INTEGRITY_MODE')
    if ([string]::IsNullOrWhiteSpace([string]$value))
    {
        return 'Off'
    }

    switch ($value.Trim().ToLowerInvariant())
    {
        'strict' { return 'Strict' }
        'audit'  { return 'Audit' }
        'off'    { return 'Off' }
        default
        {
            throw [System.ArgumentException]::new(
                "Invalid BASELINE_INTEGRITY_MODE value '$value'. Expected one of: Off, Audit, Strict.")
        }
    }
}

function Get-BaselineFileSha256
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $bytes  = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    $count  = $bytes.Length

    if ((Test-BaselineIntegrityPowerShellTextPath -Path $Path) -and $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    {
        $offset = 3
        $count = $bytes.Length - 3
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = $sha256.ComputeHash($bytes, $offset, $count)
    }
    finally
    {
        $sha256.Dispose()
    }

    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Test-BaselineIntegrityPowerShellTextPath
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path)
    return ($extension -in @('.ps1', '.psm1', '.psd1'))
}

function Get-BaselineIntegrityCoveredFiles
{
    <#
        Walks the module tree and returns the files that should be covered by
        the integrity manifest. The set is the same shape used by the runtime
        cache hydrator, but limited to script source files (no JSON data,
        fonts, assets).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot
    )

    $extensions = @('.psm1', '.psd1', '.ps1')
    $files = Get-ChildItem -LiteralPath $ModuleRoot -Recurse -File -ErrorAction Stop |
        Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName

    return @($files | ForEach-Object { $_.FullName })
}

function New-BaselineIntegrityManifest
{
    <#
        .SYNOPSIS
        Build a manifest of file hashes for the module tree.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot
    )

    $resolved = (Resolve-Path -LiteralPath $ModuleRoot).ProviderPath
    $files = Get-BaselineIntegrityCoveredFiles -ModuleRoot $resolved

    $entries = [ordered]@{}
    foreach ($filePath in $files)
    {
        $relative = $filePath.Substring($resolved.Length).TrimStart([char[]]@('\','/'))
        $relative = $relative -replace '\\', '/'
        $entries[$relative] = Get-BaselineFileSha256 -Path $filePath
    }

    return [ordered]@{
        schemaVersion = 1
        algorithm     = 'sha256'
        generatedUtc  = ([System.DateTime]::UtcNow.ToString('o'))
        fileCount     = $entries.Count
        files         = $entries
    }
}

function Test-BaselineModuleIntegrity
{
    <#
        .SYNOPSIS
        Verify every file listed in the manifest matches its recorded hash.

        .DESCRIPTION
        Returns $true when every file matches. Throws when files are missing,
        modified, or extra script files exist outside the manifest. The
        Integrity helper is the only place that decides what "tampered"
        means; the loader just calls this once and refuses to continue on a
        thrown exception.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot,

        [string]$ManifestPath
    )

    if (-not $PSBoundParameters.ContainsKey('ManifestPath') -or [string]::IsNullOrWhiteSpace($ManifestPath))
    {
        $ManifestPath = Get-BaselineIntegrityManifestPath -ModuleRoot $ModuleRoot
    }

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf))
    {
        throw [System.IO.FileNotFoundException]::new(
            "Baseline integrity manifest not found at '$ManifestPath'. Run Tools/New-ModuleIntegrityManifest.ps1 to generate one, or set BASELINE_INTEGRITY_MODE=Off to disable verification.",
            $ManifestPath)
    }

    $rawJson = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $manifest = $rawJson | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop

    if ([string]$manifest.algorithm -ne 'sha256')
    {
        throw [System.InvalidOperationException]::new("Unsupported integrity manifest algorithm '$([string]$manifest.algorithm)'. Only 'sha256' is recognised.")
    }

    $resolved = (Resolve-Path -LiteralPath $ModuleRoot).ProviderPath

    $expected = @{}
    foreach ($prop in $manifest.files.PSObject.Properties)
    {
        $expected[[string]$prop.Name] = [string]$prop.Value
    }

    $observed = @{}
    $coveredFiles = Get-BaselineIntegrityCoveredFiles -ModuleRoot $resolved
    foreach ($filePath in $coveredFiles)
    {
        $relative = $filePath.Substring($resolved.Length).TrimStart([char[]]@('\','/')) -replace '\\', '/'
        $observed[$relative] = Get-BaselineFileSha256 -Path $filePath
    }

    $missing = @($expected.Keys | Where-Object { -not $observed.ContainsKey($_) })
    $extra   = @($observed.Keys | Where-Object { -not $expected.ContainsKey($_) })
    $changed = @($expected.Keys | Where-Object { $observed.ContainsKey($_) -and ($observed[$_] -ne $expected[$_]) })

    if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $changed.Count -eq 0)
    {
        return $true
    }

    $details = @()
    if ($missing.Count -gt 0) { $details += ("Missing: " + ($missing -join ', ')) }
    if ($changed.Count -gt 0) { $details += ("Modified: " + ($changed -join ', ')) }
    if ($extra.Count   -gt 0) { $details += ("Unexpected: " + ($extra -join ', ')) }

    throw [System.Security.SecurityException]::new(
        ("Baseline module integrity check failed. {0}" -f ($details -join ' | ')))
}

function Invoke-BaselineModuleIntegrityGate
{
    <#
        .SYNOPSIS
        Loader entry point: respects BASELINE_INTEGRITY_MODE and only verifies
        when the operator has opted in.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleRoot
    )

    $mode = Get-BaselineIntegrityMode
    if ($mode -eq 'Off') { return }

    $manifestPath = Get-BaselineIntegrityManifestPath -ModuleRoot $ModuleRoot
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf))
    {
        if ($mode -eq 'Strict')
        {
            throw [System.IO.FileNotFoundException]::new(
                "Baseline integrity manifest not found at '$manifestPath' but BASELINE_INTEGRITY_MODE=Strict requires one.",
                $manifestPath)
        }
        $warningMessage = "Baseline integrity manifest not found at '$manifestPath'; BASELINE_INTEGRITY_MODE=Audit will skip verification."
        Write-Warning $warningMessage

        if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
        {
            LogWarning $warningMessage
        }
        return
    }

    [void](Test-BaselineModuleIntegrity -ModuleRoot $ModuleRoot -ManifestPath $manifestPath)
}
