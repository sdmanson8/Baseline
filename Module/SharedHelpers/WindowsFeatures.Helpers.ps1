<#
    .SYNOPSIS
    Windows features helpers for Baseline.

    .DESCRIPTION
    Keep selection and naming rules here so feature-related tests can run
    without loading the GUI runtime.
#>

<#
    .SYNOPSIS
    Returns the default pattern list of capabilities that should appear
    pre-checked in the WindowsCapabilities picker.
#>
function Get-WindowsCapabilityCheckedDefaults
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        # Steps Recorder
        'App.StepsRecorder*'
    )
}

<#
    .SYNOPSIS
    Returns the default pattern list of capabilities that should appear
    pre-unchecked in the WindowsCapabilities picker.
#>
function Get-WindowsCapabilityUncheckedDefaults
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        # Internet Explorer mode
        'Browser.InternetExplorer*',

        # Windows Media Player
        # If you want to leave "Multimedia settings" element in the advanced settings of Power Options do not uninstall this feature
        'Media.WindowsMediaPlayer*',

        # Voice Access / related speech capability entries
        '*VoiceAccess*'
    )
}

<#
    .SYNOPSIS
    Returns the default pattern list of capabilities that must be hidden from
    the WindowsCapabilities picker entirely.

    .DESCRIPTION
    These entries are critical to Windows or out-of-scope for Baseline's
    capability flow (language packs, system shell components, etc.). They are
    excluded from the rendered list rather than just unchecked.
#>
function Get-WindowsCapabilityExcludedDefaults
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        # The DirectX Database to configure and optimize apps when multiple Graphics Adapters are present
        'DirectX.Configuration.Database*',

        # Language components
        'Language.*',

        # Notepad
        'Microsoft.Windows.Notepad*',

        # Mail, contacts, and calendar sync component
        'OneCoreUAP.OneSync*',

        # Windows PowerShell Intergrated Scripting Enviroment
        'Microsoft.Windows.PowerShell.ISE*',

        # Management of printers, printer drivers, and printer servers
        'Print.Management.Console*',

        # Features critical to Windows functionality
        'Windows.Client.ShellComponents*'
    )
}

<#
    .SYNOPSIS
    Returns the friendly-name lookup map used to humanize bare capability IDs.
#>
function Get-WindowsCapabilityFriendlyNameMap
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        'App.StepsRecorder'                = 'Steps Recorder'
        'App.WiredNetworkDriverInstaller'  = 'Wired Network Driver Installer'
        'Browser.InternetExplorer'         = 'Internet Explorer Mode'
        'Hello.Face'                       = 'Windows Hello Face'
        'MathRecognizer'                   = 'Math Recognizer'
        'Media.WindowsMediaPlayer'         = 'Windows Media Player'
        'Microsoft.Wallpapers.Extended'    = 'Extended Wallpapers'
        'Microsoft.Windows.MSPaint'        = 'Microsoft Paint'
        'Microsoft.Windows.Notepad.System' = 'Notepad (System)'
        'Microsoft.Windows.WordPad'        = 'WordPad'
        'OpenSSH.Client'                   = 'OpenSSH Client'
        'OpenSSH.Server'                   = 'OpenSSH Server'
        'Print.Fax.Scan'                   = 'Windows Fax and Scan'
        'Accessibility.Braille'            = 'Accessibility - Braille Support'
        'App.Support.QuickAssist'          = 'Quick Assist'
        'VoiceAccess'                      = 'Voice Access'
    }
}

<#
    .SYNOPSIS
    Returns the default list of Windows optional features that should appear
    pre-checked in the WindowsFeatures picker.
#>
function Get-WindowsFeatureCheckedDefaults
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        # Legacy Components
        'LegacyComponents',

        # PowerShell 2.0
        'MicrosoftWindowsPowerShellV2',
        'MicrosoftWindowsPowershellV2Root',

        # Microsoft XPS Document Writer
        'Printing-XPSServices-Features',

        # Recall
        'Recall',

        # Work Folders Client
        'WorkFolders-Client'
    )
}

<#
    .SYNOPSIS
    Returns the default list of Windows optional features that should appear
    pre-unchecked in the WindowsFeatures picker.
#>
function Get-WindowsFeatureUncheckedDefaults
{
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        # Media Features
        # If you want to leave "Multimedia settings" in the advanced settings of Power Options do not disable this feature
        'MediaPlayback',

        # Windows Sandbox
        'Containers-DisposableClientVM',

        # Windows Defender Application Guard
        'Windows-Defender-ApplicationGuard'
    )
}

<#
    .SYNOPSIS
    Indicates whether the supplied name matches any wildcard pattern in the
    list (PowerShell -like semantics).
#>
function Test-WindowsCapabilityPatternMatch
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name,

        [AllowNull()]
        [string[]]$Patterns
    )

    if ($null -eq $Patterns -or $Patterns.Count -eq 0)
    {
        return $false
    }

    foreach ($pattern in $Patterns)
    {
        if ($Name -like $pattern)
        {
            return $true
        }
    }

    return $false
}

<#
    .SYNOPSIS
    Resolves a capability's friendly display name, preferring the DISM-supplied
    DisplayName and falling back to the curated friendly-name map.

    .DESCRIPTION
    DISM sometimes returns capability records with empty or unhelpful
    DisplayName fields. The fallback map covers the cases Baseline's UI must
    present to users; everything else is reduced to the version-stripped
    capability identifier.
#>
function Get-WindowsCapabilityFriendlyName
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$DisplayName,

        [hashtable]$FriendlyNameMap = (Get-WindowsCapabilityFriendlyNameMap)
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$DisplayName))
    {
        return [string]$DisplayName
    }

    $baseName = ([string]$Name -replace '~.*$', '').TrimEnd('~')
    foreach ($pattern in $FriendlyNameMap.Keys)
    {
        if ($baseName -like ('{0}*' -f $pattern))
        {
            return [string]$FriendlyNameMap[$pattern]
        }
    }

    return $baseName
}

<#
    .SYNOPSIS
    Indicates whether a capability should appear pre-selected when no explicit
    SelectedCapabilityNames argument was provided.

    .DESCRIPTION
    Mirrors the Test-CapabilitySeedSelected logic embedded in
    System.WindowsFeatures.psm1: when the caller supplied a name list, only
    those names seed; otherwise the curated CheckedCapabilities patterns
    drive selection.
#>
function Test-WindowsCapabilitySeedSelected
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CapabilityName,

        [AllowNull()]
        [string[]]$SelectedNames,

        [switch]$SelectedNamesProvided,

        [AllowNull()]
        [string[]]$CheckedPatterns
    )

    if ($SelectedNamesProvided)
    {
        if ($null -eq $SelectedNames)
        {
            return $false
        }

        return [bool](@($SelectedNames | Where-Object { $_ -eq $CapabilityName }).Count -gt 0)
    }

    return Test-WindowsCapabilityPatternMatch -Name $CapabilityName -Patterns $CheckedPatterns
}

<#
    .SYNOPSIS
    Returns the subset of capabilities that should be displayed (i.e., not
    matched by any pattern in the excluded list).
#>
function Select-WindowsCapabilityVisible
{
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowNull()]
        [object[]]$Capabilities,

        [AllowNull()]
        [string[]]$ExcludedPatterns
    )

    if ($null -eq $Capabilities -or $Capabilities.Count -eq 0)
    {
        return @()
    }

    if ($null -eq $ExcludedPatterns -or $ExcludedPatterns.Count -eq 0)
    {
        return @($Capabilities)
    }

    return @(
        $Capabilities | Where-Object {
            -not (Test-WindowsCapabilityPatternMatch -Name ([string]$_.Name) -Patterns $ExcludedPatterns)
        }
    )
}
