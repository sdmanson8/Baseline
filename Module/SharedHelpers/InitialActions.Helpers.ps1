<#
    .SYNOPSIS
    Initial action helpers for Baseline.

    .DESCRIPTION
    Separate startup decision logic from side-effecting shell work so this file
    can be exercised in unit tests.
#>

<#
    .SYNOPSIS
    Formats the startup label that InitialActions logs on entry.
#>
function Get-BaselineStartupLabel
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$OSName,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$DisplayVersion = $null
    )

    $label = "Baseline | Utility for $OSName"
    if (-not [string]::IsNullOrWhiteSpace([string]$DisplayVersion))
    {
        $label = "$label $DisplayVersion"
    }

    return $label
}

<#
    .SYNOPSIS
    Indicates whether the current PowerShell host is unsupported by InitialActions.

    .DESCRIPTION
    InitialActions warns about PowerShell ISE and VS Code hosts because the
    interactive shell affordances they use conflict with Baseline's custom host
    and progress rendering.
#>
function Test-BaselineUnsupportedHost
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$HostName,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$TermProgram
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$HostName) -and ([string]$HostName -match 'ISE'))
    {
        return $true
    }

    if ([string]$TermProgram -eq 'vscode')
    {
        return $true
    }

    return $false
}

<#
    .SYNOPSIS
    Tests whether a hosts-file entry matches the expected IP-plus-name pattern.

    .DESCRIPTION
    Downloaded hosts-file entries are validated before Baseline rewrites the
    system hosts file. Entries that do not match the pattern are skipped so a
    corrupted download cannot inject arbitrary text.
#>
function Test-BaselineHostsEntry
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Line
    )

    if ($null -eq $Line)
    {
        return $false
    }

    return ([string]$Line -match '^\s*[\d.:a-fA-F]+\s+\S+')
}

<#
    .SYNOPSIS
    Splits hosts-file content into comment-stripped candidate entries.
#>
function Get-BaselineHostsCandidateEntries
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [string[]]$Content
    )

    if ($null -eq $Content -or $Content.Count -eq 0)
    {
        return @()
    }

    $result = @($Content | Where-Object { $_ -and ($_ -notmatch '^\s*#') })
    return $result
}

<#
    .SYNOPSIS
    Indicates whether the proportion of invalid hosts entries crosses the trust
    threshold, in which case the caller should skip the Baseline hosts
    cleanup entirely.
#>
function Test-BaselineHostsDownloadSuspect
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [int]$InvalidCount,

        [Parameter(Mandatory)]
        [int]$TotalCount,

        [double]$Threshold = 0.5
    )

    if ($TotalCount -le 0)
    {
        return $false
    }

    return (([double]$InvalidCount / [double]$TotalCount) -gt $Threshold)
}

<#
    .SYNOPSIS
    Parses a SecurityCenter2 AntiVirusProduct product state integer into the
    middle-byte substring that InitialActions uses to classify Defender.

    .DESCRIPTION
    Windows encodes the running/up-to-date state of a registered AV product in
    the second byte of the productState DWORD. A value whose second byte is
    "00" or "01" means Defender is not the active scanner.
#>
function Get-BaselineDefenderProductStateCode
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$ProductState
    )

    if ($null -eq $ProductState)
    {
        return $null
    }

    try
    {
        $hex = '0x{0:x}' -f ([int]$ProductState)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Get-BaselineDefenderProductStateCode:catch178' -Severity Debug }

        return $null
    }

    if ($hex.Length -lt 5)
    {
        return $null
    }

    return $hex.Substring(3, 2)
}

<#
    .SYNOPSIS
    Indicates whether the parsed Defender product-state code represents an
    active scanner.
#>
function Test-BaselineDefenderActiveByProductState
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$StateCode
    )

    if ([string]::IsNullOrWhiteSpace([string]$StateCode))
    {
        return $false
    }

    return ([string]$StateCode -notmatch '00|01')
}

<#
    .SYNOPSIS
    Aggregates the five Defender-status booleans into a single enabled flag.

    .DESCRIPTION
    InitialActions treats Defender as enabled only when the services are
    running, SecurityCenter2 reports an active product state, and each GPO
    override is absent. A single false flag flips the overall state to false.
#>
function Test-BaselineDefenderFullyEnabled
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [bool]$ServicesRunning,

        [Parameter(Mandatory)]
        [bool]$ProductStateActive,

        [Parameter(Mandatory)]
        [bool]$AntiSpywareEnabled,

        [Parameter(Mandatory)]
        [bool]$RealtimeMonitoringEnabled,

        [Parameter(Mandatory)]
        [bool]$BehaviorMonitoringEnabled
    )

    return ($ServicesRunning -and $ProductStateActive -and $AntiSpywareEnabled -and $RealtimeMonitoringEnabled -and $BehaviorMonitoringEnabled)
}

<#
    .SYNOPSIS
    Indicates whether at least one Defender service is running.

    .DESCRIPTION
    InitialActions considers Defender's service layer healthy if any of the
    sampled services is running — a full-shutdown of every service is the
    broken state that harmful tweakers produce.
#>
function Test-BaselineDefenderServicesHealthy
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object[]]$Services
    )

    if ($null -eq $Services -or $Services.Count -eq 0)
    {
        return $false
    }

    $stopped = @($Services | Where-Object { $_.Status -ne 'Running' }).Count
    return ($stopped -lt $Services.Count)
}

<#
    .SYNOPSIS
    Probes whether the Settings app responds on the Apps & features page after a run.

    .DESCRIPTION
    Launches `ms-settings:appsfeatures` through `cmd /c start`, then watches for
    `SystemSettings.exe` to appear. Returns a structured assessment so callers can
    surface a visible warning without guessing at recovery behavior.
#>
function Resolve-BaselineSettingsAppsFeaturesHealthAssessment
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$TimeoutSeconds = 5,
        [int]$PollIntervalMilliseconds = 200
    )

    $launchSucceeded = $false
    $settingsProcessDetected = $false
    $serviceStates = @()
    $launchError = $null
    $serviceError = $null

    try
    {
        $null = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c', 'start', 'ms-settings:appsfeatures' -WindowStyle Hidden -ErrorAction Stop
        $launchSucceeded = $true
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Resolve-BaselineSettingsAppsFeaturesHealthAssessment:catch303' -Severity Debug }

        $launchError = $_.Exception.Message
    }

    if ($launchSucceeded)
    {
        try
        {
            $settingsProcessDetected = [bool](Get-Process -Name 'SystemSettings' -ErrorAction SilentlyContinue)
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Resolve-BaselineSettingsAppsFeaturesHealthAssessment:catch314' -Severity Debug }

            $settingsProcessDetected = $false
        }

        if (-not $settingsProcessDetected -and $TimeoutSeconds -gt 0)
        {
            $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds, 0))
            while (-not $settingsProcessDetected -and [DateTime]::UtcNow -lt $deadline)
            {
                if ($PollIntervalMilliseconds -gt 0)
                {
                    Start-Sleep -Milliseconds $PollIntervalMilliseconds
                }

                try
                {
                    $settingsProcessDetected = [bool](Get-Process -Name 'SystemSettings' -ErrorAction SilentlyContinue)
                }
                catch
                {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Resolve-BaselineSettingsAppsFeaturesHealthAssessment:catch333' -Severity Debug }

                    $settingsProcessDetected = $false
                }
            }
        }
    }

    try
    {
        $serviceStates = @(
            Get-Service -Name @('InstallService', 'AppXSvc', 'StateRepository', 'ClipSVC', 'LicenseManager') -ErrorAction SilentlyContinue |
                Sort-Object -Property Name |
                Select-Object Name, Status
        )
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Resolve-BaselineSettingsAppsFeaturesHealthAssessment:catch349' -Severity Debug }

        $serviceError = $_.Exception.Message
        $serviceStates = @()
    }

    $healthy = ($launchSucceeded -and $settingsProcessDetected)
    $serviceSummary = if ($serviceStates.Count -gt 0)
    {
        ($serviceStates | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Status }) -join ', '
    }
    else
    {
        'n/a'
    }

    $message = if ($healthy)
    {
        'Settings appsfeatures health check passed.'
    }
    elseif ($launchSucceeded)
    {
        'Settings appsfeatures health check failed; SystemSettings did not appear.'
    }
    else
    {
        "Settings appsfeatures health check failed; could not launch ms-settings:appsfeatures: $launchError"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$serviceError))
    {
        $message += " Service probe failed: $serviceError"
    }
    elseif ($serviceStates.Count -gt 0)
    {
        $message += " Service states: $serviceSummary"
    }

    return [pscustomobject]@{
        Healthy = $healthy
        LaunchSucceeded = $launchSucceeded
        SettingsProcessDetected = $settingsProcessDetected
        ServiceStates = $serviceStates
        LaunchError = $launchError
        ServiceError = $serviceError
        ServiceSummary = $serviceSummary
        Message = $message
    }
}

<#
    .SYNOPSIS
    Probes whether the ScreenSketch / SnipAndSketch regression remains cleared after a run.

    .DESCRIPTION
    Checks for the ScreenSketch family of AppX packages and the current Print
    Screen snipping toggle. Returns a structured assessment so callers can
    surface a visible warning without inventing a fallback result.
#>
function Resolve-BaselineScreenSnippingHealthAssessment
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $packagePatterns = @('*ScreenSketch*', '*SnipAndSketch*')
    $installedPackages = @()
    $packageError = $null
    $printScreenKeyForSnippingEnabled = $null
    $registryError = $null

    foreach ($packagePattern in $packagePatterns)
    {
        try
        {
            $installedPackages += @(
                Get-AppxPackage -Name $packagePattern -ErrorAction SilentlyContinue
            )
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Resolve-BaselineScreenSnippingHealthAssessment:catch428' -Severity Debug }

            $packageError = $_.Exception.Message
        }
    }
    $installedPackages = @($installedPackages | Sort-Object -Property Name -Unique)

    try
    {
        $keyboardSettings = Get-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name 'PrintScreenKeyForSnippingEnabled' -ErrorAction SilentlyContinue
        if ($keyboardSettings -and $keyboardSettings.PSObject.Properties['PrintScreenKeyForSnippingEnabled'])
        {
            $printScreenKeyForSnippingEnabled = [int]$keyboardSettings.PrintScreenKeyForSnippingEnabled
        }
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Helpers.Resolve-BaselineScreenSnippingHealthAssessment:catch443' -Severity Debug }

        $registryError = $_.Exception.Message
    }

    $packageSummary = if ($installedPackages.Count -gt 0)
    {
        ($installedPackages | ForEach-Object { [string]$_.Name }) -join ', '
    }
    else
    {
        'n/a'
    }

    $packagesHealthy = ($installedPackages.Count -eq 0)
    $registryHealthy = ($printScreenKeyForSnippingEnabled -eq 1)
    $healthy = ($packagesHealthy -and $registryHealthy)

    $message = if ($healthy)
    {
        "Screen snipping health check passed. Packages: $packageSummary. PrintScreenKeyForSnippingEnabled=$printScreenKeyForSnippingEnabled"
    }
    elseif (-not $packagesHealthy)
    {
        "Screen snipping health check failed; ScreenSketch/SnipAndSketch packages are still installed: $packageSummary"
    }
    else
    {
        'Screen snipping health check failed; PrintScreenKeyForSnippingEnabled is not enabled.'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$packageError))
    {
        $message += " Package probe failed: $packageError"
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$registryError))
    {
        $message += " Registry probe failed: $registryError"
    }
    elseif (-not $registryHealthy)
    {
        $message += " Current PrintScreenKeyForSnippingEnabled value: $printScreenKeyForSnippingEnabled"
    }

    return [pscustomobject]@{
        Healthy = $healthy
        InstalledPackages = $installedPackages
        PackageSummary = $packageSummary
        PrintScreenKeyForSnippingEnabled = $printScreenKeyForSnippingEnabled
        PackageError = $packageError
        RegistryError = $registryError
        Message = $message
    }
}

<#
    .SYNOPSIS
    Reduces a list of detected harmful-tweaker names into a structured
    assessment that other Baseline regions and the GUI can react to.

    .DESCRIPTION
    Baseline runs as a GUI tool a user invoked deliberately, so the equivalent control point is
    a structured signal that the orchestrator (and a later GUI banner slice)
    can read instead of the current advisory-only LogWarning. The Win 10
    Tweaker entry is special because it ships a documented kernel backdoor —
    detection of that one means the host is compromised, not merely
    over-tweaked. Returns a record with:
      * Level          — 'None' / 'Warning' / 'Blocked'.
      * BackdoorFound  — $true when the Win 10 Tweaker registry key was hit.
      * Detected       — sorted, de-duplicated list of detected tweaker names.
      * AdvisoryUrls   — the "what now" URLs, surfaced once at Blocked
                         level so users have a clear remediation path.
#>
function Resolve-BaselineHostTaintAssessment
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [string[]]$DetectedTweakerNames,

        [string]$BackdoorTweakerName = 'Win 10 Tweaker'
    )

    $names = @()
    if ($null -ne $DetectedTweakerNames)
    {
        $names = @(
            $DetectedTweakerNames |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                ForEach-Object { ([string]$_).Trim() } |
                Sort-Object -Unique
        )
    }

    $backdoor = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$BackdoorTweakerName))
    {
        $backdoor = ($names -contains ([string]$BackdoorTweakerName).Trim())
    }

    $level = 'None'
    if ($backdoor)
    {
        $level = 'Blocked'
    }
    elseif ($names.Count -gt 0)
    {
        $level = 'Warning'
    }

    $advisoryUrls = @()
    if ($backdoor)
    {
        $advisoryUrls = @(
            'https://youtu.be/na93MS-1EkM'
            'https://pikabu.ru/story/byekdor_v_win_10_tweaker_ili_sovremennyie_metodyi_borbyi_s_piratstvom_8227558'
            'https://massgrave.dev/genuine-installation-media'
        )
    }

    return [pscustomobject]@{
        Level         = $level
        BackdoorFound = [bool]$backdoor
        Detected      = [string[]]$names
        AdvisoryUrls  = [string[]]$advisoryUrls
    }
}

<#
    .SYNOPSIS
    Resolves whether InitialActions should automatically strip detected
    Baseline hosts entries or warn the user and leave them in place.

    .DESCRIPTION
    Earlier versions silently rewrote the system hosts file and popped Notepad
    whenever Baseline hosts entries were detected, which surprised users who
    had intentionally added third-party telemetry blocks. This helper returns
    the resolved policy from two opt-in sources, in priority order:
      1. The BASELINE_AUTO_STRIP_HOSTS environment variable (for unattended /
         CI runs).
      2. The AutoStripBaselineHosts user preference (set via the GUI).
    When neither source supplies a truthy value the default policy is to warn
    and skip the strip — destructive cleanup remains opt-in.
#>
function Resolve-BaselineHostsCleanupPolicy
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$EnvValue,

        [AllowNull()]
        [object]$PreferenceValue
    )

    $isTruthy = {
        param($value)
        if ($null -eq $value) { return $false }
        if ($value -is [bool]) { return [bool]$value }
        if ($value -is [int] -or $value -is [long] -or $value -is [double]) { return ([double]$value -ne 0) }
        $text = ([string]$value).Trim()
        if ([string]::IsNullOrEmpty($text)) { return $false }
        return ($text -match '^(?i:1|true|yes|on|enable|enabled)$')
    }

    if ($null -ne $EnvValue -and -not [string]::IsNullOrWhiteSpace([string]$EnvValue))
    {
        $envBool = & $isTruthy $EnvValue
        return [pscustomobject]@{
            AutoStrip = [bool]$envBool
            Source    = 'env'
        }
    }

    if ($null -ne $PreferenceValue)
    {
        $prefBool = & $isTruthy $PreferenceValue
        return [pscustomobject]@{
            AutoStrip = [bool]$prefBool
            Source    = 'preference'
        }
    }

    return [pscustomobject]@{
        AutoStrip = $false
        Source    = 'default'
    }
}
