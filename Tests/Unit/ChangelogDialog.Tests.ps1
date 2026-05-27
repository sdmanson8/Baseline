Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    foreach ($assemblyName in @('WindowsBase', 'PresentationCore', 'PresentationFramework'))
    {
        try { Add-Type -AssemblyName $assemblyName -ErrorAction Stop } catch { $null = $_ }
    }

    $script:DialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $script:DialogHelpersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers'
    $script:GuiCommonPath = Join-Path $PSScriptRoot '../../Module/GUICommon.psm1'
    $script:PopupWindowsPath = Join-Path $PSScriptRoot '../../Module/GUICommon/PopupWindows.ps1'
    $script:RegionGuiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:ActionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $script:GuiCommonContent = Get-BaselineTestSourceText -Path $script:GuiCommonPath
    $script:PopupWindowsContent = Get-BaselineTestSourceText -Path $script:PopupWindowsPath
    $script:DialogHelpersContent = Get-BaselineTestSourceText -Path @(
        $script:DialogHelpersPath
        (Join-Path $script:DialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'SettingsDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'RemoteDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'ContentDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
    )
    $script:RegionGuiContent = Get-BaselineTestSourceText -Path $script:RegionGuiPath
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )

    $helperAstFiles = @(
        (Join-Path $script:DialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'ContentDialogs.ps1')
    )
    $helperFunctionNames = @(
        'Set-BaselineReadmeInlineTheme',
        'Set-BaselineReadmeBlockTheme',
        'Set-BaselineReadmeFlowDocumentTheme',
        'Resolve-BaselineChangelogVersionLabel',
        'Select-BaselineChangelogVersionSection'
    )
    foreach ($functionName in $helperFunctionNames)
    {
        $helperFunction = $null
        foreach ($helperAstFile in $helperAstFiles)
        {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($helperAstFile, [ref]$null, [ref]$null)
            $helperFunction = $ast.Find({
                    param($node)
                    ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
                    $node.Name -eq $functionName
                }, $true)
            if ($helperFunction) { break }
        }
        if ($helperFunction)
        {
            Invoke-Expression $helperFunction.Extent.Text
        }
    }
}

Describe 'Documentation viewer wiring' {
    It 'defines dedicated themed changelog and README viewers with installed-path resolvers' {
        $script:DialogHelpersContent | Should -Match 'function Resolve-BaselineChangelogPath'
        $script:DialogHelpersContent | Should -Match 'function Resolve-BaselineReadmePath'
        $script:DialogHelpersContent | Should -Match 'BASELINE_LAUNCHER_PATH'
        $script:DialogHelpersContent | Should -Match '\[System\.AppContext\]::BaseDirectory'
        $script:DialogHelpersContent | Should -Match 'function Show-ChangelogDialog'
        $script:DialogHelpersContent | Should -Match 'function Show-ReadmeDialog'
        $script:DialogHelpersContent | Should -Match 'TxtChangelogContent'
        $script:DialogHelpersContent | Should -Match 'TxtReadmeContent'
        $script:DialogHelpersContent | Should -Match 'ReadAllText'
    }

    It 'routes changelog and readme viewer fallbacks through Write-SwallowedException' {
        $script:DialogHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''DialogHelpers\.Show-ChangelogDialog\.SetGuiWindowChromeTheme'''
        $script:DialogHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''DialogHelpers\.Show-ChangelogDialog\.ResolveCurrentChangelogVersion'''
        $script:DialogHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''DialogHelpers\.Show-ReadmeDialog\.ApplyBlockFormatting'''
    }

    It 'normalizes display versions to exact changelog version labels' {
        Resolve-BaselineChangelogVersionLabel -DisplayVersion '4.0.0' | Should -Be 'v4.0.0'
        Resolve-BaselineChangelogVersionLabel -DisplayVersion 'v4.0.0-beta' | Should -Be 'v4.0.0-beta'
        Resolve-BaselineChangelogVersionLabel -DisplayVersion 'v4.0.0 (beta)' | Should -Be 'v4.0.0-beta'
    }

    It 'selects only the exact matching release section from the changelog' {
        $raw = @'
# Full Change Log

# v4.0.0-beta

## Changed

- Current beta change.

## Fixed

- Current beta fix.

---

## 3.1.0-beta | 2026-04-26

### Changed

- Old beta change.

---

## 3.0.0-beta | 2026-04-06

### Fixed

- Older beta fix.
'@

        $section = Select-BaselineChangelogVersionSection -Raw $raw -Version 'v4.0.0-beta'

        $section | Should -Match '^# v4\.0\.0-beta'
        $section | Should -Match 'Current beta change'
        $section | Should -Match 'Current beta fix'
        $section | Should -Not -Match '3\.1\.0-beta'
        $section | Should -Not -Match 'Old beta change'
    }

    It 'does not match a stable version against a beta changelog section' {
        $raw = @'
# v4.0.0-beta

- Beta-only change.

---

## 3.1.0-beta | 2026-04-26

- Old change.
'@

        Select-BaselineChangelogVersionSection -Raw $raw -Version 'v4.0.0' |
            Should -Be 'No changelog entry found for v4.0.0.'
    }

    It 'routes the Help menu changelog and documentation actions through themed dialogs instead of launching external apps' {
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-ChangelogDialog'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-ReadmeDialog'"
        $script:ActionHandlersContent | Should -Match '& \$showChangelogDialogCommand'
        $script:ActionHandlersContent | Should -Match '& \$showReadmeDialogCommand'
        $script:ActionHandlersContent | Should -Not -Match 'Start-Process -FilePath \$docsUrl'
    }

    It 'reapplies the README viewer theme through the shared popup theme registry' {
        $script:DialogHelpersContent | Should -Match 'Register-GuiPopupThemeWindow -Window \$dlg -ThemeCallback \$readmeThemeCallback'
        $script:DialogHelpersContent | Should -Match '\$readmeThemeCallback = \{'
        $script:DialogHelpersContent | Should -Match '& \$loadReadmeContent -ThemeOverride \$Theme'
        $script:DialogHelpersContent | Should -Match 'ReadmeHeaderBorder'
        $script:DialogHelpersContent | Should -Match 'ReadmeContentBorder'
        $script:DialogHelpersContent | Should -Match 'ReadmeFooterBorder'
    }

    It 'exports the GUI activation helper used by module-qualified dialog callers' {
        $script:PopupWindowsContent | Should -Match 'function Show-GuiActivatedDialog'
        $script:GuiCommonContent | Should -Match "'Show-GuiActivatedDialog'"
    }

    It 'captures Set-ButtonChrome at module scope so menu-driven dialogs can theme their buttons' {
        $script:RegionGuiContent | Should -Match '\$Script:SetButtonChromeScript = \$null'
        $script:RegionGuiContent | Should -Match 'function Set-ButtonChrome'
        $script:RegionGuiContent | Should -Match '\$Script:SetButtonChromeScript = \$\{function:Set-GuiButtonChrome\}'
    }

    It 'uses the module-captured button chrome helper in the README dialog callbacks' {
        $script:DialogHelpersContent | Should -Match 'if \(\$Script:SetButtonChromeScript\)'
        $script:DialogHelpersContent | Should -Match '& \$Script:SetButtonChromeScript -Button \$btnRefresh -Variant ''Subtle'' -Compact -Muted'
        $script:DialogHelpersContent | Should -Match '& \$Script:SetButtonChromeScript -Button \$btnClose -Variant ''Primary'' -Compact'
    }

    It 'adds live filtering controls to the log viewer without removing refresh or Notepad actions' {
        $script:DialogHelpersContent | Should -Match 'Name="CmbLogLevelFilter"'
        $script:DialogHelpersContent | Should -Match 'Name="TxtLogSearch"'
        $script:DialogHelpersContent | Should -Match 'GuiLogFilterErrors'
        $script:DialogHelpersContent | Should -Match 'GuiLogFilterWarnings'
        $script:DialogHelpersContent | Should -Match 'GuiLogFilterDebug'
        $script:DialogHelpersContent | Should -Match 'GuiLogFilterSuccess'
        $script:DialogHelpersContent | Should -Match "Pattern = '\\bDEBUG:'"
        $script:DialogHelpersContent | Should -Match 'LogDebug'
        $script:DialogHelpersContent | Should -Match '\$selectedFilter -eq \$filterDebugLabel -and \$severity -ne ''Debug'''
        $script:DialogHelpersContent | Should -Match 'Register-GuiEventHandler -Source \$cmbLogLevelFilter -EventName ''SelectionChanged'''
        $script:DialogHelpersContent | Should -Match 'Register-GuiEventHandler -Source \$txtLogSearch -EventName ''TextChanged'''
        $script:DialogHelpersContent | Should -Match 'BtnRefresh'
        $script:DialogHelpersContent | Should -Match 'BtnOpenExternal'
    }

    It 'themes rendered README FlowDocuments after markdown conversion so code content stays readable' {
        $script:DialogHelpersContent | Should -Match 'function Set-BaselineReadmeInlineTheme'
        $script:DialogHelpersContent | Should -Match 'function Set-BaselineReadmeBlockTheme'
        $script:DialogHelpersContent | Should -Match 'function Set-BaselineReadmeFlowDocumentTheme'
        $script:DialogHelpersContent | Should -Match 'Markdig\.Wpf resolves its code styles during ToFlowDocument\(\)'
        $script:DialogHelpersContent | Should -Match '\$codeBackgroundBrush = \$BrushConverter\.ConvertFromString\(\$ActiveTheme\.HeaderBg\)'
        $script:DialogHelpersContent | Should -Match '\$Inline\.Background = if \(\$WithinCodeBlock\) \{ \[System\.Windows\.Media\.Brushes\]::Transparent \} else \{ \$CodeBackgroundBrush \}'
        $script:DialogHelpersContent | Should -Match '\$Block\.BorderThickness = \[System\.Windows\.Thickness\]::new\(1\)'
        $script:DialogHelpersContent | Should -Match '& \$setReadmeFlowThemeScript -Document \$Document -ActiveTheme \$activeTheme -BrushConverter \$bc -ReadmeFontSize \$readmeFontSize'
        $script:DialogHelpersContent | Should -Match 'ConvertFrom-BaselineMarkdownToAnchoredFlowDocument -Markdown \$markdownText'
        $script:DialogHelpersContent | Should -Match '\$wireFlowDocumentNavigation = \{'

        $brushConverter = [System.Windows.Media.BrushConverter]::new()
        $theme = @{
            TextPrimary = '#EDEDED'
            HeaderBg = '#1F2937'
            BorderColor = '#475569'
        }

        $document = [System.Windows.Documents.FlowDocument]::new()

        $paragraph = [System.Windows.Documents.Paragraph]::new()
        $paragraph.Inlines.Add([System.Windows.Documents.Run]::new('Prefix ')) | Out-Null
        $inlineCode = [System.Windows.Documents.Span]::new()
        $inlineCode.Background = [System.Windows.Media.Brushes]::Khaki
        $inlineRun = [System.Windows.Documents.Run]::new('Get-Process')
        $inlineCode.Inlines.Add($inlineRun) | Out-Null
        $paragraph.Inlines.Add($inlineCode) | Out-Null

        $codeParagraph = [System.Windows.Documents.Paragraph]::new()
        $codeParagraph.Background = [System.Windows.Media.Brushes]::LightGray
        $codeRun = [System.Windows.Documents.Run]::new('winget list')
        $codeParagraph.Inlines.Add($codeRun) | Out-Null

        $list = [System.Windows.Documents.List]::new()
        $listItem = [System.Windows.Documents.ListItem]::new()
        $listCodeParagraph = [System.Windows.Documents.Paragraph]::new()
        $listCodeParagraph.Background = [System.Windows.Media.Brushes]::LightGray
        $listCodeRun = [System.Windows.Documents.Run]::new('Nested code item')
        $listCodeParagraph.Inlines.Add($listCodeRun) | Out-Null
        $listItem.Blocks.Add($listCodeParagraph) | Out-Null
        $list.ListItems.Add($listItem) | Out-Null

        $document.Blocks.Add($paragraph) | Out-Null
        $document.Blocks.Add($codeParagraph) | Out-Null
        $document.Blocks.Add($list) | Out-Null

        { Set-BaselineReadmeFlowDocumentTheme -Document $document -ActiveTheme $theme -BrushConverter $brushConverter -ReadmeFontSize 15 } | Should -Not -Throw

        $expectedCodeBackground = $brushConverter.ConvertFromString($theme.HeaderBg).ToString()
        $expectedCodeForeground = $brushConverter.ConvertFromString($theme.TextPrimary).ToString()
        $expectedBorder = $brushConverter.ConvertFromString($theme.BorderColor).ToString()

        $document.FontFamily.Source | Should -Be 'Segoe UI'
        $document.FontSize | Should -Be 15
        $inlineCode.Background.ToString() | Should -Be $expectedCodeBackground
        $inlineRun.FontFamily.Source | Should -Match 'Consolas'
        $codeParagraph.Background.ToString() | Should -Be $expectedCodeBackground
        $codeParagraph.BorderBrush.ToString() | Should -Be $expectedBorder
        $codeParagraph.BorderThickness.Left | Should -Be 1
        $codeParagraph.Padding.Left | Should -Be 8
        $codeRun.Background.ToString() | Should -Be ([System.Windows.Media.Brushes]::Transparent.ToString())
        $codeRun.Foreground.ToString() | Should -Be $expectedCodeForeground
        $listCodeParagraph.Background.ToString() | Should -Be $expectedCodeBackground
        $listCodeRun.FontFamily.Source | Should -Match 'Consolas'
    }
}
