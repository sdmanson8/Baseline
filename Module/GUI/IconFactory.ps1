function Initialize-GuiIconSystem
{
    <# .SYNOPSIS Initializes the icon font and enables text-only fallback if loading fails. #>
    [CmdletBinding()]
    param(
        [string]$ModuleRoot = $Script:GuiModuleBasePath
    )

    $Script:GuiIconFontPath = Get-GuiIconFontPath -ModuleRoot $ModuleRoot
    $Script:GuiIconFontFamily = $null
    $Script:GuiIconEnabled = $false

    if ([string]::IsNullOrWhiteSpace([string]$Script:GuiIconFontPath))
    {
        return
    }

    try
    {
        $fontDirectory = (Split-Path -Parent $Script:GuiIconFontPath) + '\'
        $fontFamilyName = Get-GuiIconFontFamilyName
        # WPF private font: FontFamily(baseUri, familyName) where baseUri points to directory
        # and familyName is "./#Family Name"
        $baseUri = [System.Uri]::new($fontDirectory)
        $Script:GuiIconFontFamily = [System.Windows.Media.FontFamily]::new($baseUri, './#' + $fontFamilyName)
        $Script:GuiIconEnabled = $true
        Write-Verbose ("Icon system initialized: font='{0}', dir='{1}', uri='{2}'" -f $fontFamilyName, $fontDirectory, $baseUri.AbsoluteUri) -Verbose
    }
    catch
    {
        $Script:GuiIconFontFamily = $null
        $Script:GuiIconEnabled = $false

        if (Get-Command -Name 'Write-GuiRuntimeWarning' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-GuiRuntimeWarning -Context 'Initialize-GuiIconSystem' -Message ("Failed to load icon font '{0}': {1}" -f $Script:GuiIconFontPath, $_.Exception.Message)
        }
    }
}

function Test-GuiIconsAvailable
{
    <# .SYNOPSIS Returns true when the icon system is fully available. #>
    [CmdletBinding()]
    param()

    return ($Script:GuiIconEnabled -and $null -ne $Script:GuiIconFontFamily)
}

function Get-GuiStatusBrushByKind
{
    <# .SYNOPSIS Returns a theme brush for semantic icon/status rendering. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Default','Success','Warning','Error','Info','Disabled')]
        [string]$Kind,

        [hashtable]$Theme = $Script:CurrentTheme
    )

    if ($null -eq $Theme)
    {
        return $null
    }

    switch ($Kind)
    {
        'Success'  { return ConvertTo-GuiBrush -Color $Theme.LowRiskBadge -Context 'Get-GuiStatusBrushByKind/Success' }
        'Warning'  { return ConvertTo-GuiBrush -Color $Theme.RiskMediumBadge -Context 'Get-GuiStatusBrushByKind/Warning' }
        'Error'    { return ConvertTo-GuiBrush -Color $Theme.RiskHighBadge -Context 'Get-GuiStatusBrushByKind/Error' }
        'Info'     { return ConvertTo-GuiBrush -Color $Theme.AccentBlue -Context 'Get-GuiStatusBrushByKind/Info' }
        'Disabled' { return ConvertTo-GuiBrush -Color $Theme.TextMuted -Context 'Get-GuiStatusBrushByKind/Disabled' }
        default    { return ConvertTo-GuiBrush -Color $Theme.TextPrimary -Context 'Get-GuiStatusBrushByKind/Default' }
    }
}

function New-GuiIconTextBlock
{
    <# .SYNOPSIS Creates a TextBlock that renders a Fluent icon glyph. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IconName,

        [double]$Size = 16,
        [object]$Foreground = $null,
        [string]$ToolTip = $null,
        [double]$Opacity = 1.0,
        [string]$VerticalAlignment = 'Center'
    )

    if (-not (Test-GuiIconsAvailable))
    {
        return $null
    }

    $glyph = Get-GuiIconGlyph -Name $IconName
    if ($null -eq $glyph)
    {
        return $null
    }

    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text = [string]$glyph
    $tb.FontFamily = $Script:GuiIconFontFamily
    $tb.FontSize = $Size
    $tb.VerticalAlignment = $VerticalAlignment
    $tb.TextAlignment = 'Center'
    $tb.TextWrapping = 'NoWrap'
    $tb.Opacity = $Opacity
    $tb.UseLayoutRounding = $true
    $tb.SnapsToDevicePixels = $true

    if ($null -ne $Foreground)
    {
        $tb.Foreground = $Foreground
    }

    if (-not [string]::IsNullOrWhiteSpace($ToolTip))
    {
        $tb.ToolTip = $ToolTip
    }

    return $tb
}

function New-GuiLabeledIconContent
{
    <# .SYNOPSIS Creates a horizontal icon + text content container with text-only fallback. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IconName,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [double]$IconSize = 16,
        [double]$Gap = 8,
        [double]$TextFontSize = 12,
        [object]$Foreground = $null,
        [switch]$AllowTextOnlyFallback,
        [string]$ToolTip = $null,
        [string]$VerticalAlignment = 'Center',
        [switch]$Bold
    )

    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.Orientation = 'Horizontal'
    $panel.VerticalAlignment = $VerticalAlignment
    $panel.UseLayoutRounding = $true
    $panel.SnapsToDevicePixels = $true

    $icon = New-GuiIconTextBlock -IconName $IconName -Size $IconSize -Foreground $Foreground -ToolTip $ToolTip -VerticalAlignment $VerticalAlignment
    if ($icon)
    {
        $icon.Margin = [System.Windows.Thickness]::new(0, 0, $Gap, 0)
        [void]$panel.Children.Add($icon)
    }
    elseif (-not $AllowTextOnlyFallback)
    {
        return $null
    }

    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = $Text
    $label.FontSize = $TextFontSize
    $label.VerticalAlignment = $VerticalAlignment
    $label.TextWrapping = 'NoWrap'
    $label.TextTrimming = 'CharacterEllipsis'
    if ($Bold)
    {
        $label.FontWeight = [System.Windows.FontWeights]::SemiBold
    }

    if ($null -ne $Foreground)
    {
        $label.Foreground = $Foreground
    }

    if (-not [string]::IsNullOrWhiteSpace($ToolTip))
    {
        $label.ToolTip = $ToolTip
    }

    [void]$panel.Children.Add($label)
    return $panel
}

function Set-GuiButtonIconContent
{
    <# .SYNOPSIS Sets a WPF button's content to a standardized icon+label layout. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.Button]$Button,

        [Parameter(Mandatory = $true)]
        [string]$IconName,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [double]$IconSize = 16,
        [double]$Gap = 8,
        [double]$TextFontSize = 12,
        [object]$Foreground = $null,
        [string]$ToolTip = $null
    )

    $content = New-GuiLabeledIconContent -IconName $IconName -Text $Text -IconSize $IconSize -Gap $Gap -TextFontSize $TextFontSize -Foreground $Foreground -AllowTextOnlyFallback -ToolTip $ToolTip
    $Button.Content = if ($content) { $content } else { $Text }
}

function New-GuiStatusIconLabel
{
    <# .SYNOPSIS Creates a compact semantic icon+label for preview badges and log rows. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Success','Skipped','Failed','Warning','Info','Safe','MediumRisk','HighRisk','RestartRequired','NotReversible')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [double]$IconSize = 12,
        [double]$Gap = 6,
        [double]$TextFontSize = 11,
        [hashtable]$Theme = $Script:CurrentTheme
    )

    $brushKind = switch ($Kind)
    {
        'Success'         { 'Success' }
        'Safe'            { 'Success' }
        'Skipped'         { 'Disabled' }
        'Warning'         { 'Warning' }
        'MediumRisk'      { 'Warning' }
        'Failed'          { 'Error' }
        'HighRisk'        { 'Error' }
        'Info'            { 'Info' }
        'RestartRequired' { 'Info' }
        'NotReversible'   { 'Disabled' }
        default           { 'Default' }
    }

    $foreground = Get-GuiStatusBrushByKind -Kind $brushKind -Theme $Theme
    return New-GuiLabeledIconContent -IconName $Kind -Text $Text -IconSize $IconSize -Gap $Gap -TextFontSize $TextFontSize -Foreground $foreground -AllowTextOnlyFallback
}

function Set-GuiTabHeaderWithIcon
{
    <# .SYNOPSIS Applies a standardized icon+label header to a TabItem. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.TabItem]$Tab,

        [Parameter(Mandatory = $true)]
        [string]$IconName,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [double]$IconSize = 16,
        [double]$Gap = 6
    )

    $Tab.Header = New-GuiLabeledIconContent -IconName $IconName -Text $Text -IconSize $IconSize -Gap $Gap -AllowTextOnlyFallback
}

function Get-GuiPrimaryTabIconName
{
    <# .SYNOPSIS Maps a primary tab label to its logical icon name. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrimaryTab
    )

    switch ($PrimaryTab)
    {
        'Initial Setup'        { return 'InitialSetupTab' }
        'Privacy & Telemetry'  { return 'PrivacyTab' }
        'Security'             { return 'SecurityTab' }
        'System'               { return 'SystemTab' }
        'UI & Personalization' { return 'UIPersonalizationTab' }
        'UWP Apps'             { return 'AppsTab' }
        'Gaming'               { return 'GamingTab' }
        'Context Menu'         { return 'ContextMenuTab' }
        default                { return $null }
    }
}

function Set-TextOrIconContent
{
    <# .SYNOPSIS Safe content assignment with icon-or-text fallback. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$IconName = $null,
        [switch]$IsButton
    )

    $content = $null
    if (-not [string]::IsNullOrWhiteSpace($IconName))
    {
        $content = New-GuiLabeledIconContent -IconName $IconName -Text $Text -AllowTextOnlyFallback
    }

    if ($IsButton)
    {
        $Target.Content = if ($content) { $content } else { $Text }
    }
    else
    {
        if ($Target -is [System.Windows.Controls.ContentControl])
        {
            $Target.Content = if ($content) { $content } else { $Text }
        }
        elseif ($Target -is [System.Windows.Controls.TextBlock])
        {
            $Target.Text = $Text
        }
    }
}

function New-GamingGroupHeader
{
    <# .SYNOPSIS Creates an icon+label header for gaming group sections. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    $iconName = switch ($GroupName)
    {
        'Core Performance'                 { 'PerformanceGroup' }
        'Input'                            { 'InputGroup' }
        'Capture & Overlay'                { 'CaptureGroup' }
        'Compatibility & Troubleshooting'  { 'CompatibilityGroup' }
        default                            { $null }
    }

    if ($iconName)
    {
        $content = New-GuiLabeledIconContent -IconName $iconName -Text $GroupName -IconSize 14 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback -Bold
        if ($content) { return $content }
    }

    return $null
}

function Get-GuiPresetIconName
{
    <# .SYNOPSIS Maps a preset name to its logical icon name. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PresetName
    )

    switch ($PresetName)
    {
        'Minimal'   { return 'Minimal' }
        'Basic'     { return 'Basic' }
        'Balanced'  { return 'Balanced' }
        'Advanced'  { return 'Advanced' }
        default     { return $null }
    }
}

function Get-GuiPreflightIconGlyph
{
    <# .SYNOPSIS Returns the icon glyph character for a pre-flight check status. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    switch ($Status)
    {
        'Passed'  { return Get-GuiIconGlyph -Name 'Success' }
        'Failed'  { return Get-GuiIconGlyph -Name 'Failed' }
        'Warning' { return Get-GuiIconGlyph -Name 'Warning' }
        default   { return $null }
    }
}

function Get-GuiSummaryCardIconName
{
    <# .SYNOPSIS Maps a summary card label to its logical icon name. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    switch ($Label)
    {
        'Will Change'       { return 'WillChange' }
        'Already Set'       { return 'AlreadySet' }
        'Requires Restart'  { return 'RestartRequired' }
        'High Risk'         { return 'HighRisk' }
        'Selected'          { return 'Selected' }
        default             { return $null }
    }
}
