# Pre-flight validation checks that run before execution begins.
# Catches system-level problems early instead of mid-run.

function New-PreflightCheckResult
{
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Passed', 'Failed', 'Warning')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('System', 'Storage', 'Services', 'Security', 'Recovery')]
        [string]$Category
    )

    [pscustomobject]@{
        Name     = $Name
        Status   = $Status
        Message  = $Message
        Category = $Category
    }
}

function Test-PreflightAdminElevation
{
    try
    {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin)
        {
            return (New-PreflightCheckResult -Name 'Administrator' -Status 'Passed' -Message 'Running as administrator' -Category 'Security')
        }
        return (New-PreflightCheckResult -Name 'Administrator' -Status 'Failed' -Message 'Not running as administrator' -Category 'Security')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'Administrator' -Status 'Failed' -Message "Could not verify elevation: $($_.Exception.Message)" -Category 'Security')
    }
}

function Test-PreflightDiskSpace
{
    $minFreeBytes = 500MB
    try
    {
        $systemDriveLetter = $env:SystemDrive[0]
        $volume = Get-Volume -DriveLetter $systemDriveLetter -ErrorAction Stop
        $freeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)

        if ($volume.SizeRemaining -ge $minFreeBytes)
        {
            return (New-PreflightCheckResult -Name 'Disk space' -Status 'Passed' -Message "$freeGB GB free" -Category 'Storage')
        }
        return (New-PreflightCheckResult -Name 'Disk space' -Status 'Failed' -Message "Only $freeGB GB free on ${systemDriveLetter}: (minimum 500 MB required)" -Category 'Storage')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'Disk space' -Status 'Warning' -Message "Could not verify disk space: $($_.Exception.Message)" -Category 'Storage')
    }
}

function Test-PreflightVSS
{
    try
    {
        $vssSvc = Get-Service -Name VSS -ErrorAction Stop
        if ($vssSvc.Status -eq 'Running')
        {
            return (New-PreflightCheckResult -Name 'Volume Shadow Copy' -Status 'Passed' -Message 'Service is running' -Category 'Services')
        }
        if ($vssSvc.StartType -eq 'Disabled')
        {
            return (New-PreflightCheckResult -Name 'Volume Shadow Copy' -Status 'Warning' -Message 'Service is disabled (will be enabled and started)' -Category 'Services')
        }
        return (New-PreflightCheckResult -Name 'Volume Shadow Copy' -Status 'Warning' -Message "Service not running (status: $($vssSvc.Status), will be started)" -Category 'Services')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'Volume Shadow Copy' -Status 'Failed' -Message "VSS service not found: $($_.Exception.Message)" -Category 'Services')
    }
}

function Test-PreflightEventLog
{
    try
    {
        $eventLogSvc = Get-Service -Name EventLog -ErrorAction Stop
        if ($eventLogSvc.Status -eq 'Running')
        {
            return (New-PreflightCheckResult -Name 'EventLog service' -Status 'Passed' -Message 'Service is running' -Category 'Services')
        }
        return (New-PreflightCheckResult -Name 'EventLog service' -Status 'Warning' -Message "Service is $($eventLogSvc.Status)" -Category 'Services')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'EventLog service' -Status 'Warning' -Message "Could not query EventLog service: $($_.Exception.Message)" -Category 'Services')
    }
}

function Test-PreflightWMI
{
    try
    {
        $null = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return (New-PreflightCheckResult -Name 'WMI health' -Status 'Passed' -Message 'CIM/WMI responding' -Category 'System')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'WMI health' -Status 'Failed' -Message "CIM/WMI query failed: $($_.Exception.Message)" -Category 'System')
    }
}

function Test-PreflightSystemRestore
{
    try
    {
        $systemDriveLetter = $env:SystemDrive[0]
        $systemDriveUniqueID = (Get-Volume | Where-Object { $_.DriveLetter -eq $systemDriveLetter }).UniqueID
        $systemProtection = ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients" -ErrorAction Ignore)."{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}") | Where-Object { $_ -match [regex]::Escape($systemDriveUniqueID) }

        if ($null -ne $systemProtection)
        {
            return (New-PreflightCheckResult -Name 'System Restore' -Status 'Passed' -Message "Enabled for ${env:SystemDrive}" -Category 'System')
        }

        # CIM fallback: the SPP\Clients registry check can return null on newer Windows 11 builds
        # even when System Protection is already on.
        $srpEnabled = $false
        try
        {
            $srpStatus = Get-CimInstance -ClassName SystemRestoreConfig -Namespace 'root\default' -ErrorAction Stop
            if ($srpStatus -and $srpStatus.RPSessionInterval -eq 1) { $srpEnabled = $true }
        }
        catch { $srpEnabled = $false }

        if ($srpEnabled)
        {
            return (New-PreflightCheckResult -Name 'System Restore' -Status 'Passed' -Message "Enabled for ${env:SystemDrive}" -Category 'System')
        }

        return (New-PreflightCheckResult -Name 'System Restore' -Status 'Warning' -Message "Not enabled for ${env:SystemDrive}" -Category 'System')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'System Restore' -Status 'Warning' -Message "Could not verify System Protection: $($_.Exception.Message)" -Category 'System')
    }
}

function Test-PreflightRestorePointCreation
{
    try
    {
        $createCommand = Get-Command -Name 'CreateRestorePoint' -CommandType Function -ErrorAction SilentlyContinue
        if (-not $createCommand)
        {
            return (New-PreflightCheckResult -Name 'Restore Point' -Status 'Warning' -Message 'CreateRestorePoint function not available' -Category 'Recovery')
        }

        $created = [bool](& $createCommand)
        if ($created)
        {
            return (New-PreflightCheckResult -Name 'Restore Point' -Status 'Passed' -Message 'Restore point created successfully' -Category 'Recovery')
        }
        return (New-PreflightCheckResult -Name 'Restore Point' -Status 'Warning' -Message 'Restore point creation returned false (System Protection may be disabled or insufficient disk space)' -Category 'Recovery')
    }
    catch
    {
        return (New-PreflightCheckResult -Name 'Restore Point' -Status 'Warning' -Message "Restore point creation failed: $($_.Exception.Message)" -Category 'Recovery')
    }
}

function Invoke-PreflightChecks
{
    <#
    .SYNOPSIS
        Runs all pre-flight validation checks before execution begins.
    .DESCRIPTION
        Returns an object with Passed (bool), CriticalFailures (array),
        Warnings (array), and AllResults (array of check results).
        Also attempts to create a restore point as part of pre-flight.
    #>
    [CmdletBinding()]
    param ()

    $allResults = @(
        Test-PreflightAdminElevation
        Test-PreflightDiskSpace
        Test-PreflightVSS
        Test-PreflightEventLog
        Test-PreflightWMI
        Test-PreflightSystemRestore
    )

    $criticalFailures = @($allResults | Where-Object { $_.Status -eq 'Failed' })
    $warnings = @($allResults | Where-Object { $_.Status -eq 'Warning' })
    $passed = ($criticalFailures.Count -eq 0) -and ($warnings.Count -eq 0)

    [pscustomobject]@{
        Passed           = $passed
        CriticalFailures = $criticalFailures
        Warnings         = $warnings
        AllResults       = $allResults
    }
}

function Show-PreflightResultsDialog
{
    <#
    .SYNOPSIS
        Displays pre-flight check results and returns the user's choice.
    .DESCRIPTION
        If all passed, returns 'Continue'. If critical failures exist, shows dialog
        with only 'Cancel'. If warnings only, shows 'Cancel' and 'Continue Anyway'.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Results
    )

    if ($Results.Passed)
    {
        return 'Continue'
    }

    # Build the formatted message
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Pre-flight check results:')
    $lines.Add('')

    foreach ($check in $Results.AllResults)
    {
        switch ($check.Status)
        {
            'Passed'
            {
                $detailSuffix = ''
                # Include detail for disk space even on pass
                if ($check.Message -and $check.Message -ne 'Running as administrator' -and
                    $check.Message -ne 'CIM/WMI responding' -and $check.Message -ne 'Service is running')
                {
                    $detailSuffix = " ($($check.Message))"
                }
                $lines.Add([char]0x2713 + " $($check.Name): Passed$detailSuffix")
            }
            'Failed'
            {
                $lines.Add([char]0x2717 + " $($check.Name): $($check.Message)")
            }
            'Warning'
            {
                $lines.Add([char]0x26A0 + " $($check.Name): $($check.Message)")
            }
        }
    }

    $issueCount = $Results.CriticalFailures.Count + $Results.Warnings.Count
    $lines.Add('')

    if ($Results.CriticalFailures.Count -gt 0)
    {
        $noun = if ($issueCount -eq 1) { 'issue' } else { 'issues' }
        $lines.Add("$issueCount $noun must be resolved before continuing.")
    }
    else
    {
        $noun = if ($issueCount -eq 1) { 'issue' } else { 'issues' }
        $lines.Add("$issueCount $noun requires attention before continuing.")
    }

    $message = $lines -join "`n"

    if ($Results.CriticalFailures.Count -gt 0)
    {
        Show-ThemedDialog -Title 'Pre-flight Checks' -Message $message -Buttons @('Cancel')
        return 'Cancel'
    }

    # Warnings only - allow the user to continue
    $choice = Show-ThemedDialog -Title 'Pre-flight Checks' -Message $message -Buttons @('Cancel', 'Continue Anyway') -AccentButton 'Continue Anyway'
    return $choice
}
