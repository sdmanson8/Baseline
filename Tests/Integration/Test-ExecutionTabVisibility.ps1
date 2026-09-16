# Verify that responsive layout cannot reveal navigation hidden by execution.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$parseErrors = $null
$tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Module/GUI/BuildPrimaryTabs.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
$assignment = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$adaptiveTabLayoutScript'
}, $true)
if (-not $assignment) { throw 'Responsive layout handler not found.' }
$layoutExpression = $assignment.Right.Find({ param($node) $node -is [Management.Automation.Language.ScriptBlockExpressionAst] }, $true)
$layout = $layoutExpression.ScriptBlock.GetScriptBlock()
$PrimaryTabs = New-Object System.Windows.Controls.TabControl
$tab = New-Object System.Windows.Controls.TabItem
$tab.Header = 'Initial Setup'
[void]$PrimaryTabs.Items.Add($tab)
$PrimaryTabs.SelectedIndex = 0
$PrimaryTabDropdown = New-Object System.Windows.Controls.ComboBox
$PrimaryTabHost = [pscustomobject]@{ ActualWidth = 1600.0 }
$Form = [pscustomobject]@{ ActualWidth = 1600.0 }
foreach ($visibility in @('Visible', 'Collapsed', 'Hidden')) {
    $PrimaryTabs.Visibility = $visibility
    foreach ($width in @(1600.0, 900.0, 1600.0)) {
        $PrimaryTabHost.ActualWidth = $width
        & $layout
        if ([string]$PrimaryTabs.Visibility -ne $visibility) { throw "Resize revealed or hid tabs: expected $visibility at width $width." }
        $expectedPadding = if ($width -ge 1400) { 16 } else { 8 }
        if ($tab.Padding.Left -ne $expectedPadding) { throw "Incorrect tab spacing at width $width." }
    }
}
Write-Host 'PASS: responsive tab layout preserves view visibility at wide and narrow widths.'
