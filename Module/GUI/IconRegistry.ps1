<#
    .SYNOPSIS
#>

function Get-GuiIconFontPath
{
    <# .SYNOPSIS Resolves the FluentSystemIcons font path for the current GUI session. #>
    [CmdletBinding()]
    param(
        [string]$ModuleRoot = $Script:GuiModuleBasePath
    )

    $candidateRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @($ModuleRoot, $PSScriptRoot))
    {
        if ([string]::IsNullOrWhiteSpace([string]$root))
        {
            continue
        }

        [void]$candidateRoots.Add($root)

        $parentRoot = Split-Path -Path $root -Parent
        if (-not [string]::IsNullOrWhiteSpace([string]$parentRoot))
        {
            [void]$candidateRoots.Add($parentRoot)
        }
    }

    $candidateRoots = $candidateRoots | Select-Object -Unique
    if (-not $candidateRoots)
    {
        return $null
    }

    $candidatePaths = foreach ($root in $candidateRoots)
    {
        Join-Path -Path $root -ChildPath 'FluentSystemIcons.ttf'
        Join-Path -Path (Join-Path -Path $root -ChildPath 'Assets') -ChildPath 'FluentSystemIcons.ttf'
        Join-Path -Path (Join-Path -Path $root -ChildPath 'Fonts') -ChildPath 'FluentSystemIcons.ttf'
    }

    foreach ($path in $candidatePaths)
    {
        if (Test-Path -LiteralPath $path -PathType Leaf)
        {
            return $path
        }
    }

    return $null
}

<#
    .SYNOPSIS
#>

function Get-GuiIconFontFamilyName
{
    <# .SYNOPSIS Returns the expected display name of the Fluent icon font family. #>
    [CmdletBinding()]
    param()

    return 'Fluent System Icons'
}

function ConvertTo-GuiIconGlyph
{
    <# .SYNOPSIS Converts a Unicode scalar value into a glyph string for WPF text rendering. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$CodePoint
    )

    if ($CodePoint -lt 0 -or $CodePoint -gt 0x10FFFF)
    {
        return $null
    }

    if ($CodePoint -le 0xFFFF)
    {
        return [string][char]$CodePoint
    }

    return [System.Char]::ConvertFromUtf32($CodePoint)
}

<#
    .SYNOPSIS
#>

function Get-GuiIconGlyph
{
    <# .SYNOPSIS Returns the icon glyph string for a logical icon name. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    switch ($Name)
    {
        # Primary actions
        'RunTweaks'           { return [char]0xE768 }
        'PreviewRun'          { return [char]0xE7C3 }
        'RestoreDefaults'     { return [char]0xE72C }
        'Undo'                { return [char]0xE7A7 }
        'Export'              { return [char]0xEDE1 }
        'Help'                { return [char]0xE946 }
        'OpenLog'             { return [char]0xE9D9 }
        'QuickStart'          { return [char]0xE734 }
        'ArrowDownload'       { return ConvertTo-GuiIconGlyph -CodePoint 0xF025B }
        'ArrowSync'           { return ConvertTo-GuiIconGlyph -CodePoint 0xF03F8 }
        'Delete'              { return ConvertTo-GuiIconGlyph -CodePoint 0xF11B5 }

        # Navigation
        'InitialSetupTab'     { return [char]0xE80F }
        'PrivacyTab'          { return [char]0xE72E }
        'SecurityTab'         { return [char]0xEA18 }
        'SystemTab'           { return [char]0xE713 }
        'UIPersonalizationTab'{ return [char]0xE790 }
        'AppsTab'             { return [char]0xE8FD }
        'GamingTab'           { return [char]0xE7FC }
        'ContextMenuTab'      { return [char]0xE8B7 }

        # Presets / modes
        'Balanced'            { return [char]0xE945 }
        'Advanced'            { return [char]0xE9CA }
        'CustomSelection'     { return [char]0xEA86 }
        'Scenario'            { return [char]0xE7EF }
        'SafeMode'            { return [char]0xE73E }
        'ExpertMode'          { return [char]0xE9CA }
        'GameMode'            { return [char]0xE7FC }
        'Theme'               { return [char]0xE706 }

        # Tools / filters
        'Search'              { return [char]0xE721 }
        'Filter'              { return [char]0xE71C }
        'Clear'               { return [char]0xE894 }
        'Archive'             { return ConvertTo-GuiIconGlyph -CodePoint 0xF0165 }
        'AppGeneric'          { return ConvertTo-GuiIconGlyph -CodePoint 0xF0129 }
        'Apps'                { return ConvertTo-GuiIconGlyph -CodePoint 0xF0143 }
        'Box'                 { return ConvertTo-GuiIconGlyph -CodePoint 0xF0743 }
        'Camera'              { return ConvertTo-GuiIconGlyph -CodePoint 0xF0A5B }
        'Chat'                { return ConvertTo-GuiIconGlyph -CodePoint 0xF0B4F }
        'Clock'               { return ConvertTo-GuiIconGlyph -CodePoint 0xF0DCB }
        'Cloud'               { return ConvertTo-GuiIconGlyph -CodePoint 0xF0E0F }
        'Desktop'             { return ConvertTo-GuiIconGlyph -CodePoint 0xF11E7 }
        'Document'            { return ConvertTo-GuiIconGlyph -CodePoint 0xF12DB }
        'Folder'              { return ConvertTo-GuiIconGlyph -CodePoint 0xF18B3 }
        'Games'               { return [char]0xE7FC }
        'Globe'               { return ConvertTo-GuiIconGlyph -CodePoint 0xF1A63 }
        'Image'               { return ConvertTo-GuiIconGlyph -CodePoint 0xF1C67 }
        'Mail'                { return ConvertTo-GuiIconGlyph -CodePoint 0xF20A3 }
        'Person'              { return ConvertTo-GuiIconGlyph -CodePoint 0xF262B }
        'PhoneDesktop'        { return ConvertTo-GuiIconGlyph -CodePoint 0xF27A7 }
        'Shield'              { return ConvertTo-GuiIconGlyph -CodePoint 0xF2D5F }
        'StoreMicrosoft'      { return ConvertTo-GuiIconGlyph -CodePoint 0xF30D7 }
        'Toolbox'             { return ConvertTo-GuiIconGlyph -CodePoint 0xF383D }
        'Video'               { return ConvertTo-GuiIconGlyph -CodePoint 0xF3951 }
        'Window'              { return ConvertTo-GuiIconGlyph -CodePoint 0xF3B5B }
        'WindowConsole'       { return ConvertTo-GuiIconGlyph -CodePoint 0xF3BA5 }
        'WindowDevTools'      { return ConvertTo-GuiIconGlyph -CodePoint 0xF3BB7 }
        'WindowSettings'      { return ConvertTo-GuiIconGlyph -CodePoint 0xF3C05 }
        'MusicNote1'          { return ConvertTo-GuiIconGlyph -CodePoint 0xF22E5 }
        'MusicNote2'          { return ConvertTo-GuiIconGlyph -CodePoint 0xF22EB }

        # Summary / preview
        'Selected'            { return [char]0xEA86 }
        'WillChange'          { return [char]0xE7C3 }
        'AlreadySet'          { return [char]0xE73E }
        'RestorePoint'        { return [char]0xE777 }

        # Status / risk
        'Success'             { return [char]0xE73E }
        'Skipped'             { return [char]0xE892 }
        'Failed'              { return [char]0xEA39 }
        'Warning'             { return [char]0xE7BA }
        'Info'                { return [char]0xE946 }
        'Safe'                { return [char]0xE73E }
        'MediumRisk'          { return [char]0xE7BA }
        'HighRisk'            { return [char]0xEA39 }
        'RestartRequired'     { return [char]0xE895 }
        'NotReversible'       { return [char]0xE72E }

        # Gaming groups
        'PerformanceGroup'    { return [char]0xE945 }
        'InputGroup'          { return [char]0xE962 }
        'CaptureGroup'        { return [char]0xE722 }
        'CompatibilityGroup'  { return [char]0xE7BA }

        # Preset buttons
        'Minimal'             { return [char]0xE73E }
        'Basic'               { return [char]0xE734 }

        # Language
        'Language'            { return [char]0xE774 }

        # Pre-flight status
        'Passed'              { return [char]0xE73E }

        default               { return $null }
    }
}

<#
    .SYNOPSIS
#>

function Get-GuiApplicationIconName
{
    <# .SYNOPSIS Maps an application catalog row to a Fluent icon name. #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$SubCategory,
        [object[]]$Tags,
        [string]$SourceRegion
    )

    $normalizedName = if ([string]::IsNullOrWhiteSpace([string]$Name)) { '' } else { [string]$Name.Trim() }

    switch ($normalizedName)
    {
        'Microsoft Store' { return 'StoreMicrosoft' }
        'OneDrive' { return 'Cloud' }
        'Phone Link' { return 'PhoneDesktop' }
        'Quick Assist' { return 'Desktop' }
        'Dev Home' { return 'WindowDevTools' }
        'Copilot' { return 'AppGeneric' }
        'Clipchamp' { return 'Video' }
        'Camera' { return 'Camera' }
        'Photos' { return 'Image' }
        'Mail and Calendar' { return 'Mail' }
        'Feedback Hub' { return 'Chat' }
        'Alarms & Clock' { return 'Clock' }
        'Cortana' { return 'Person' }
        'Microsoft Teams' { return 'Chat' }
        'Skype' { return 'Chat' }
        'Microsoft Edge' { return 'Globe' }
        default { }
    }

    switch ([string]$SubCategory)
    {
        'Browsers'      { return 'Globe' }
        'Communication' { return 'Chat' }
        'Compression'   { return 'Archive' }
        'Development'   { return 'WindowDevTools' }
        'Documents'     { return 'Document' }
        'FileManagement'{ return 'Folder' }
        'Gaming'        { return 'Games' }
        'Imaging'       { return 'Image' }
        'Media'         { return 'Video' }
        'RemoteAccess'  { return 'PhoneDesktop' }
        'Runtimes'      { return 'Box' }
        'Security'      { return 'Shield' }
        'Utilities'     { return 'Toolbox' }
    }

    if ($Tags)
    {
        $tagText = ($Tags | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
        if ($tagText -match '\bgame\b') { return 'Games' }
        if ($tagText -match '\bbrowser\b') { return 'Globe' }
        if ($tagText -match '\bcloud\b') { return 'Cloud' }
        if ($tagText -match '\bsecurity\b') { return 'Shield' }
    }

    if ([string]::IsNullOrWhiteSpace([string]$SourceRegion))
    {
        return 'AppGeneric'
    }

    return 'AppGeneric'
}
