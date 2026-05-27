Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:UWPAppsPath = Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1'
    $script:UWPAppsJsonPath = Join-Path $PSScriptRoot '../../Module/Data/UWPApps.json'

    $script:UWPAppsAst = [System.Management.Automation.Language.Parser]::ParseFile($script:UWPAppsPath, [ref]$null, [ref]$null)
    $script:UWPAppsSourceText = Get-BaselineTestSourceText -Path $script:UWPAppsPath
    $script:UWPAppsSourceAst = [scriptblock]::Create($script:UWPAppsSourceText).Ast
    $script:EdgeRemovalAst = $script:UWPAppsAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'EdgeRemoval'
        }, $true) | Select-Object -First 1
    $script:EdgeRemovalText = $script:UWPAppsSourceText

    $script:UWPAppsJson = Get-Content $script:UWPAppsJsonPath -Raw | ConvertFrom-Json
    $script:EdgeRemovalEntry = $script:UWPAppsJson.Entries | Where-Object { $_.Function -eq 'EdgeRemoval' } | Select-Object -First 1
}

Describe 'EdgeRemoval function (#540 / #538 / #567)' {

    It 'is defined in UWPApps.psm1' {
        $script:EdgeRemovalAst | Should -Not -BeNullOrEmpty
    }

    It 'declares a single Mandatory Remove switch parameter set' {
        $params = $script:EdgeRemovalAst.Body.ParamBlock.Parameters
        $params.Count | Should -Be 1
        $params[0].Name.VariablePath.UserPath | Should -Be 'Remove'
        ($params[0].StaticType.Name) | Should -Be 'SwitchParameter'

        $paramAttr = $params[0].Attributes |
            Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] -and $_.TypeName.Name -eq 'Parameter' } |
            Select-Object -First 1
        $paramAttr | Should -Not -BeNullOrEmpty

        $namedArgs = @{}
        foreach ($na in $paramAttr.NamedArguments) { $namedArgs[$na.ArgumentName] = $na.Argument.Extent.Text }
        $namedArgs['Mandatory'] | Should -Match '\$true'
        $namedArgs['ParameterSetName'] | Should -Match '"Remove"|''Remove'''
    }

    It 'declares all required nested helper functions' {
        $expected = @(
            'Write-EdgeRemovalLog',
            'Get-LegacyEdgePackages',
            'Test-LegacyEdgeInstalled',
            'Test-ChromiumEdgeInstalled',
            'Backup-UserChoiceAssociations',
            'Restore-UserChoiceAssociations',
            'Stop-EdgeProcesses',
            'Remove-LegacyEdge',
            'Remove-EdgeShortcuts',
            'Install-EdgeProtocolRedirect',
            'Remove-ChromiumEdge',
            'Remove-EdgeRegistryKeys',
            'Remove-AdditionalEdgeFolders'
        )
        $nested = $script:UWPAppsSourceAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) | ForEach-Object { $_.Name }

        foreach ($name in $expected) {
            $nested | Should -Contain $name -Because "EdgeRemoval must define helper $name"
        }
    }

    It 'logs to %ProgramData%\Baseline\Logs' {
        $script:EdgeRemovalText | Should -Match 'Baseline\\Logs'
        $script:EdgeRemovalText | Should -Not -Match 'Legacy\\Logs'
    }

    It 'caches stub and writes redirect under %ProgramData%\Baseline\OpenWebSearch (rebranded)' {
        $script:EdgeRemovalText | Should -Match 'Baseline\\OpenWebSearch'
        $script:EdgeRemovalText | Should -Not -Match 'Legacy\\OpenWebSearch'
    }

    It 'registers OpenWebSearchRepair scheduled task under \Baseline\ (rebranded)' {
        $script:EdgeRemovalText | Should -Match "TaskPath\s+'\\Baseline\\'"
        $script:EdgeRemovalText | Should -Not -Match "TaskPath\s+'\\Legacy\\'"
    }
}

Describe 'EdgeRemoval preserves EdgeWebView2 (#538)' {

    It 'excludes *EdgeWebView* from the post-removal folder cleanup pattern' {
        $script:EdgeRemovalText | Should -Match 'notlike\s+''\*EdgeWebView\*'''
    }

    It 'never directly removes any EdgeWebView path' {
        # Allow comments mentioning EdgeWebView (to document the preservation), but no Remove-Item against an EdgeWebView path
        if ($script:EdgeRemovalText -match 'Remove-Item[^\r\n]*EdgeWebView') {
            throw "Found Remove-Item line targeting EdgeWebView path: $matches[0]"
        }
    }

    It 'backs up and restores EdgeUpdate ClientState registry (required for EdgeWebView2)' {
        $script:EdgeRemovalText | Should -Match 'Invoke-BaselineProcess -FilePath ''reg\.exe'' -ArgumentList @\(''export'', ''HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\ClientState'''
        $script:EdgeRemovalText | Should -Match 'Invoke-BaselineProcess -FilePath ''reg\.exe'' -ArgumentList @\(''import'', \$backupRegFile\)'
    }

    It 'mentions EdgeWebView2 preservation in comments' {
        $script:EdgeRemovalText | Should -Match 'EdgeWebView'
    }
}

Describe 'EdgeRemoval honours UserChoice gotcha (.html/.htm/.xml/.pdf)' {

    It 'backs up FileExts UserChoice for the four documented extensions' {
        $script:EdgeRemovalText | Should -Match "'\.html'"
        $script:EdgeRemovalText | Should -Match "'\.htm'"
        $script:EdgeRemovalText | Should -Match "'\.xml'"
        $script:EdgeRemovalText | Should -Match "'\.pdf'"
        $script:EdgeRemovalText | Should -Match 'FileExts'
        $script:EdgeRemovalText | Should -Match 'UserChoice'
    }

    It 'skips restoring entries that pointed to MSEdgeHTM' {
        $script:EdgeRemovalText | Should -Match "ProgId\s+-eq\s+'MSEdgeHTM'"
    }

    It 'backs up before removal and restores after removal' {
        $backupIdx = $script:EdgeRemovalText.IndexOf('Backup-UserChoiceAssociations')
        $restoreIdx = $script:EdgeRemovalText.IndexOf('Restore-UserChoiceAssociations -Backup')
        $backupIdx | Should -BeGreaterThan -1
        $restoreIdx | Should -BeGreaterThan $backupIdx
    }
}

Describe 'EdgeRemoval JSON entry (UWPApps.json)' {

    It 'is present in UWPApps.json' {
        $script:EdgeRemovalEntry | Should -Not -BeNullOrEmpty
    }

    It 'is an Action-type entry with Remove OnParam and no OffParam' {
        $script:EdgeRemovalEntry.Type | Should -Be 'Action'
        $script:EdgeRemovalEntry.OnParam | Should -Be 'Remove'
        $script:EdgeRemovalEntry.OffParam | Should -BeNullOrEmpty
    }

    It 'is flagged Caution=true with non-empty CautionReason' {
        $script:EdgeRemovalEntry.Caution | Should -BeTrue
        [string]::IsNullOrWhiteSpace($script:EdgeRemovalEntry.CautionReason) | Should -BeFalse
    }

    It 'is Restorable=false (one-way destructive)' {
        $script:EdgeRemovalEntry.Restorable | Should -BeFalse
    }

    It 'returns the UWPApps entry' {
        $script:EdgeRemovalEntry.SourceRegion | Should -Be 'UWPApps'
    }

    It 'mentions EdgeWebView2 preservation in Detail or WhyThisMatters' {
        $combined = "$($script:EdgeRemovalEntry.Detail) $($script:EdgeRemovalEntry.WhyThisMatters)"
        $combined | Should -Match 'EdgeWebView2'
    }

    It 'tags the entry as edge/removal' {
        $script:EdgeRemovalEntry.Tags | Should -Contain 'edge'
        $script:EdgeRemovalEntry.Tags | Should -Contain 'removal'
    }

    It 'is a High-risk Advanced-tier entry' {
        $script:EdgeRemovalEntry.Risk | Should -Be 'High'
        $script:EdgeRemovalEntry.PresetTier | Should -Be 'Advanced'
    }
}

Describe 'EdgeRemoval vendor fidelity' {

    It 'uses 30-second DISM timeout with one retry' {
        ($script:EdgeRemovalText.Split("`n") | Where-Object { $_ -match "Invoke-BaselineProcess -FilePath 'dism\.exe'.*-TimeoutSeconds 30" }).Count | Should -BeGreaterOrEqual 2
    }

    It 'preserves the OpenWebSearch.cmd CMDCMDLINE backtick-pair sequence' {
        # Final .cmd content must contain `` (two backticks) for the CMD substitution to work
        $script:EdgeRemovalText | Should -Match 'CMDCMDLINE:"=``%'
    }

    It 'redirects MSEdgeHTM via the cached stub' {
        $script:EdgeRemovalText | Should -Match 'HKCR\\MSEdgeHTM\\shell\\open\\command'
    }

    It 'skips deleting EdgeRemoval and OpenWebSearchRepair when sweeping Edge scheduled tasks' {
        $script:EdgeRemovalText | Should -Match "TaskName\s+-eq\s+'EdgeRemoval'"
        $script:EdgeRemovalText | Should -Match "TaskName\s+-eq\s+'OpenWebSearchRepair'"
    }
}
