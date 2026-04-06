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

function Get-GuiIconFontFamilyName
{
    <# .SYNOPSIS Returns the expected display name of the Fluent icon font family. #>
    [CmdletBinding()]
    param()

    return 'Fluent System Icons'
}

function Get-GuiIconGlyph
{
    <# .SYNOPSIS Returns the icon glyph character for a logical icon name. #>
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
