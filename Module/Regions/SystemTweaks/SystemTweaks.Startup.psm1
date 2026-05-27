<#
.SYNOPSIS
Startup-folder / Run-key enumerator and per-entry enable / disable.

.DESCRIPTION
Closes the tracked startup issue.
Baseline already manages service startup type per-row and per-app autostart
suppression for Windows-bundled apps, but had no general "manage which
third-party apps run on boot" surface like Task Manager -> Startup. The original
does not ship this either.

This module provides the back-end enumerator and bit-flip primitives the
Customizations tab and Startup Manager dialog use:

  Get-BaselineStartupEntries     Enumerates HKLM\...\Run / RunOnce, HKCU\...\Run /
                                 RunOnce, the per-user and per-machine Startup
                                 folders' .lnk files, and merges in the
                                 StartupApproved status bytes (the same
                                 'Disabled' bit Task Manager flips on the
                                 Startup tab) so each entry reports its
                                 effective Enabled state plus the registry /
                                 file path needed to round-trip a flip.

  Set-BaselineStartupEntryEnabled -EntryId <Source|Scope|Name> -Enable / -Disable
                                 Round-trips the StartupApproved bit:
                                 toggling 'Off' writes 03 00 00 00 + FILETIME
                                 into the matching StartupApproved value
                                 (Run, Run32, or StartupFolder). Toggling
                                 'On' writes 02 00 00 00 + zeros. The Run
                                 entry itself is never deleted -- Task Manager
                                 behaviour, recoverable from the StartupApproved
                                 key alone, never destructive.

  Reset-BaselineStartupEntries   Restore-defaults path: re-enables every
                                 entry this run had disabled and only ever
                                 removes StartupApproved values it created
                                 itself (it never touches the Run / RunOnce
                                 entries themselves; those remain untouched
                                 even on Restore Defaults).

The enumerator is pure (returns objects, no side effects) so the GUI dynamic
list and Pester both consume it through the same surface.
#>

$script:BaselineStartupRunPaths = @(
    [pscustomobject]@{
        Source           = 'HKLM\Run'
        Scope            = 'Machine'
        Path             = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
        ApprovedKey      = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        IsRunOnce        = $false
    }
    [pscustomobject]@{
        Source           = 'HKLM\RunOnce'
        Scope            = 'Machine'
        Path             = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        ApprovedKey      = $null
        IsRunOnce        = $true
    }
    [pscustomobject]@{
        Source           = 'HKLM\Run32'
        Scope            = 'Machine'
        Path             = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        ApprovedKey      = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
        IsRunOnce        = $false
    }
    [pscustomobject]@{
        Source           = 'HKCU\Run'
        Scope            = 'CurrentUser'
        Path             = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        ApprovedKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        IsRunOnce        = $false
    }
    [pscustomobject]@{
        Source           = 'HKCU\RunOnce'
        Scope            = 'CurrentUser'
        Path             = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        ApprovedKey      = $null
        IsRunOnce        = $true
    }
)

$script:BaselineStartupFolderPaths = @(
    [pscustomobject]@{
        Source           = 'StartupFolder\CurrentUser'
        Scope            = 'CurrentUser'
        FolderEnvVar     = 'APPDATA'
        FolderRelative   = 'Microsoft\Windows\Start Menu\Programs\Startup'
        ApprovedKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    }
    [pscustomobject]@{
        Source           = 'StartupFolder\AllUsers'
        Scope            = 'Machine'
        FolderEnvVar     = 'ProgramData'
        FolderRelative   = 'Microsoft\Windows\Start Menu\Programs\Startup'
        ApprovedKey      = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    }
)
<#
    .SYNOPSIS
    Return the current StartupApproved state for a startup entry.

    .DESCRIPTION
    Reads the StartupApproved bytes for a Run or RunOnce value and returns the normalized Baseline state string used by the GUI.

    .PARAMETER ApprovedKey
    Registry path under StartupApproved to read.

    .PARAMETER ValueName
    Startup value name to inspect.

    .EXAMPLE
    Get-BaselineStartupApprovedState -ApprovedKey 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -ValueName 'MyApp'
#>
function Get-BaselineStartupApprovedState
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][string]$ApprovedKey,
        [Parameter(Mandatory = $true)][string]$ValueName
    )

    if ([string]::IsNullOrWhiteSpace($ApprovedKey)) { return 'enabled' }
    if (-not (Test-Path -LiteralPath $ApprovedKey)) { return 'enabled' }

    try
    {
        $val = Get-ItemProperty -LiteralPath $ApprovedKey -Name $ValueName -ErrorAction Stop
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.Startup.Get-BaselineStartupApprovedState:catch131' -Severity Debug }

        return 'enabled'
    }

    if (-not $val.PSObject.Properties[$ValueName]) { return 'enabled' }
    $bytes = $val.$ValueName
    if (-not $bytes -or $bytes.Length -eq 0) { return 'enabled' }

    if (($bytes[0] -band 0x01) -eq 0) { 'enabled' } else { 'disabled' }
}
<#
    .SYNOPSIS
    Build the StartupApproved byte payload for an enabled or disabled entry.

    .DESCRIPTION
    Creates the 12-byte StartupApproved structure Baseline writes when toggling a startup entry on or off.

    .PARAMETER Enable
    Pass $true to build the enabled byte pattern or $false to build the disabled byte pattern.

    .EXAMPLE
    New-BaselineStartupApprovedBytes -Enable $false
#>
function New-BaselineStartupApprovedBytes
{
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)][bool]$Enable
    )

    $bytes = New-Object 'byte[]' 12
    if ($Enable)
    {
        $bytes[0] = 0x02
        return ,$bytes
    }

    $bytes[0] = 0x03
    $ft = [DateTime]::UtcNow.ToFileTimeUtc()
    $ftBytes = [BitConverter]::GetBytes($ft)
    for ($i = 0; $i -lt 8; $i++) { $bytes[$i + 4] = $ftBytes[$i] }
    return ,$bytes
}
<#
    .SYNOPSIS
    Enumerate startup entries and their approval state.

    .DESCRIPTION
    Collects startup entries from the configured Run and RunOnce sources and annotates each one with its current StartupApproved state.

    .EXAMPLE
    Get-BaselineStartupEntries
#>
function Get-BaselineStartupEntries
{
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $entries = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($source in $script:BaselineStartupRunPaths)
    {
        if (-not (Test-Path -LiteralPath $source.Path)) { continue }

        try
        {
            $values = Get-Item -LiteralPath $source.Path -ErrorAction Stop
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.Startup.Get-BaselineStartupEntries:catch202' -Severity Debug }

            continue
        }

        foreach ($valueName in @($values.GetValueNames()))
        {
            if ([string]::IsNullOrWhiteSpace($valueName)) { continue }
            $command = $values.GetValue($valueName, $null, 'DoNotExpandEnvironmentNames')
            $state = Get-BaselineStartupApprovedState -ApprovedKey $source.ApprovedKey -ValueName $valueName

            $entries.Add([pscustomobject]@{
                EntryId     = "$($source.Source)|$valueName"
                Source      = $source.Source
                Scope       = $source.Scope
                Name        = $valueName
                Command     = $command
                Path        = $source.Path
                ApprovedKey = $source.ApprovedKey
                IsRunOnce   = $source.IsRunOnce
                Enabled     = ($state -eq 'enabled')
                Kind        = 'RegistryRun'
            })
        }
    }

    foreach ($folder in $script:BaselineStartupFolderPaths)
    {
        $envVal = [Environment]::GetEnvironmentVariable($folder.FolderEnvVar)
        if ([string]::IsNullOrWhiteSpace($envVal)) { continue }
        $folderPath = Join-Path $envVal $folder.FolderRelative
        if (-not (Test-Path -LiteralPath $folderPath)) { continue }

        try
        {
            $items = Get-ChildItem -LiteralPath $folderPath -Filter '*.lnk' -File -ErrorAction Stop
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.Startup.Get-BaselineStartupEntries:catch239' -Severity Debug }

            continue
        }

        foreach ($item in $items)
        {
            $state = Get-BaselineStartupApprovedState -ApprovedKey $folder.ApprovedKey -ValueName $item.Name

            $entries.Add([pscustomobject]@{
                EntryId     = "$($folder.Source)|$($item.Name)"
                Source      = $folder.Source
                Scope       = $folder.Scope
                Name        = $item.Name
                Command     = $item.FullName
                Path        = $folderPath
                ApprovedKey = $folder.ApprovedKey
                IsRunOnce   = $false
                Enabled     = ($state -eq 'enabled')
                Kind        = 'StartupFolder'
            })
        }
    }

    return $entries.ToArray()
}
<#
    .SYNOPSIS
    Enable or disable a startup entry by EntryId.

    .DESCRIPTION
    Finds a startup entry from the Baseline entry list and updates its StartupApproved bytes to reflect the requested enabled state.

    .PARAMETER EntryId
    Entry identifier returned by Get-BaselineStartupEntries.

    .PARAMETER Enable
    Mark the startup entry as enabled.

    .PARAMETER Disable
    Mark the startup entry as disabled.

    .EXAMPLE
    Set-BaselineStartupEntryEnabled -EntryId 'Run|MyApp' -Disable
#>
function Set-BaselineStartupEntryEnabled
{
    [CmdletBinding(DefaultParameterSetName = 'Disable')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$EntryId,
        [Parameter(Mandatory = $true, ParameterSetName = 'Enable')][switch]$Enable,
        [Parameter(Mandatory = $true, ParameterSetName = 'Disable')][switch]$Disable
    )

    $entry = Get-BaselineStartupEntries | Where-Object { $_.EntryId -eq $EntryId } | Select-Object -First 1
    if (-not $entry)
    {
        LogError "Set-BaselineStartupEntryEnabled: no entry with EntryId '$EntryId'"
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($entry.ApprovedKey))
    {
        LogError "Set-BaselineStartupEntryEnabled: entry '$EntryId' has no StartupApproved key (RunOnce entries are not toggleable; remove the value to disable)"
        return $false
    }

    $shouldEnable = $PSCmdlet.ParameterSetName -eq 'Enable'

    try
    {
        if (-not (Test-Path -LiteralPath $entry.ApprovedKey))
        {
            New-Item -Path $entry.ApprovedKey -Force -ErrorAction Stop | Out-Null
        }

        $bytes = New-BaselineStartupApprovedBytes -Enable:$shouldEnable
        Set-ItemProperty -LiteralPath $entry.ApprovedKey -Name $entry.Name -Value $bytes -Type Binary -ErrorAction Stop
        return $true
    }
    catch
    {
        LogError "Set-BaselineStartupEntryEnabled: failed to write StartupApproved value '$($entry.Name)' under '$($entry.ApprovedKey)': $($_.Exception.Message)"
        return $false
    }
}
<#
    .SYNOPSIS
    Re-enable startup entries disabled by the current run.

    .DESCRIPTION
    Iterates the stored entry identifiers from the current run and calls the startup toggle helper to turn them back on.

    .PARAMETER EntryIdsDisabledByThisRun
    Entry identifiers collected during the current run.

    .EXAMPLE
    Reset-BaselineStartupEntries -EntryIdsDisabledByThisRun @('Run|MyApp')
#>
function Reset-BaselineStartupEntries
{
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowNull()]
        [AllowEmptyString()]
        [string[]]$EntryIdsDisabledByThisRun
    )

    $reEnabled = 0
    foreach ($id in $EntryIdsDisabledByThisRun)
    {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $ok = Set-BaselineStartupEntryEnabled -EntryId $id -Enable
        if ($ok) { $reEnabled++ }
    }

    return $reEnabled
}

Export-ModuleMember -Function Get-BaselineStartupEntries, Set-BaselineStartupEntryEnabled, Reset-BaselineStartupEntries, Get-BaselineStartupApprovedState, New-BaselineStartupApprovedBytes
