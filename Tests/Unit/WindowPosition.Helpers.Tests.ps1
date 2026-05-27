Set-StrictMode -Version Latest

BeforeAll {
    # Load WindowPosition.Helpers via AST so we exercise the function bodies
    # without dragging in the full SharedHelpers module graph. Mirrors the
    # pattern used by GameMode.Helpers.Tests.ps1.

    $helperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/WindowPosition.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$null, [ref]$null)

    # Re-execute the top-level $Script:Baseline* assignments so module-private
    # state (default min visible thresholds, pref-key map) is initialised in
    # the test scope before the function definitions are evaluated.
    $assignments = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)
    foreach ($assignment in $assignments) {
        Invoke-Expression $assignment.Extent.Text
    }

    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    # Stub user-pref API used by Get/Save/Resolve placement helpers.
    $Script:WPTestPrefStore = @{}
    function Get-BaselineUserPreference {
        param([Parameter(Mandatory)][string]$Key, $Default = $null)
        if ($Script:WPTestPrefStore.ContainsKey($Key)) { return $Script:WPTestPrefStore[$Key] }
        return $Default
    }
    function Set-BaselineUserPreference {
        param([Parameter(Mandatory)][string]$Key, $Value)
        $Script:WPTestPrefStore[$Key] = $Value
    }
    function Write-SwallowedException { param($ErrorRecord, $Source) }
}

Describe 'Test-BaselineWindowRectVisible (bounds validation)' {
    BeforeAll {
        $Script:WA1080p = @(
            [pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 1920.0; Height = 1040.0 }
        )
    }
    BeforeEach { $Script:WPTestPrefStore = @{} }

    It 'returns true for a fully on-screen rectangle' {
        $rect = [pscustomobject]@{ Left = 100.0; Top = 80.0; Width = 1200.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $rect -WorkAreas $Script:WA1080p | Should -BeTrue
    }

    It 'returns false when the rectangle is entirely off the right edge' {
        $rect = [pscustomobject]@{ Left = 5000.0; Top = 0.0; Width = 1200.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $rect -WorkAreas $Script:WA1080p | Should -BeFalse
    }

    It 'returns false when only a 50px sliver remains visible (< 120px floor)' {
        $rect = [pscustomobject]@{ Left = 1870.0; Top = 0.0; Width = 1200.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $rect -WorkAreas $Script:WA1080p | Should -BeFalse
    }

    It 'returns true when at least 120w x 40h remains visible' {
        $rect = [pscustomobject]@{ Left = 1700.0; Top = 0.0; Width = 1200.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $rect -WorkAreas $Script:WA1080p | Should -BeTrue
    }

    It 'returns true when a multi-monitor secondary display covers the rect' {
        $waMulti = @(
            [pscustomobject]@{ Left = 0.0;    Top = 0.0; Width = 1920.0; Height = 1040.0 }
            [pscustomobject]@{ Left = 1920.0; Top = 0.0; Width = 1920.0; Height = 1040.0 }
        )
        $rect = [pscustomobject]@{ Left = 2200.0; Top = 100.0; Width = 1200.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $rect -WorkAreas $waMulti | Should -BeTrue
    }

    It 'returns false for an empty WorkAreas array' {
        $rect = [pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 1200.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $rect -WorkAreas @() | Should -BeFalse
    }

    It 'returns false for zero-width or zero-height rectangles' {
        $bad = [pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 0.0; Height = 800.0 }
        Test-BaselineWindowRectVisible -Rect $bad -WorkAreas $Script:WA1080p | Should -BeFalse
    }
}

Describe 'Get-BaselineSavedWindowPlacement' {
    BeforeEach { $Script:WPTestPrefStore = @{} }
    It 'returns $null when no preferences are set' {
        Get-BaselineSavedWindowPlacement | Should -BeNullOrEmpty
    }

    It 'returns the stored placement when all four numeric prefs are present' {
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 200.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 150.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1200.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 800.0
        Set-BaselineUserPreference -Key 'WindowMaximized' -Value $true

        $placement = Get-BaselineSavedWindowPlacement
        $placement | Should -Not -BeNullOrEmpty
        $placement.Left      | Should -Be 200.0
        $placement.Top       | Should -Be 150.0
        $placement.Width     | Should -Be 1200.0
        $placement.Height    | Should -Be 800.0
        $placement.Maximized | Should -BeTrue
    }

    It 'returns $null when width or height are non-positive' {
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 0.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 0.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 0.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 800.0
        Get-BaselineSavedWindowPlacement | Should -BeNullOrEmpty
    }

    It 'returns $null when a numeric pref is non-parseable junk' {
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 'not-a-number'
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 0.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1200.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 800.0
        Get-BaselineSavedWindowPlacement | Should -BeNullOrEmpty
    }
}

Describe 'Save-BaselineWindowPlacement' {
    BeforeEach { $Script:WPTestPrefStore = @{} }
    It 'writes all five pref keys when RememberWindowPosition is unset (default true)' {
        $ok = Save-BaselineWindowPlacement -Left 50 -Top 60 -Width 1100 -Height 700 -Maximized $false
        $ok | Should -BeTrue
        $Script:WPTestPrefStore['WindowLeft']      | Should -Be 50.0
        $Script:WPTestPrefStore['WindowTop']       | Should -Be 60.0
        $Script:WPTestPrefStore['WindowWidth']     | Should -Be 1100.0
        $Script:WPTestPrefStore['WindowHeight']    | Should -Be 700.0
        $Script:WPTestPrefStore['WindowMaximized'] | Should -BeFalse
    }

    It 'is a no-op when RememberWindowPosition is $false' {
        Set-BaselineUserPreference -Key 'RememberWindowPosition' -Value $false
        $ok = Save-BaselineWindowPlacement -Left 50 -Top 60 -Width 1100 -Height 700
        $ok | Should -BeFalse
        $Script:WPTestPrefStore.ContainsKey('WindowLeft') | Should -BeFalse
    }

    It 'rejects non-positive width/height without writing prefs' {
        $ok = Save-BaselineWindowPlacement -Left 0 -Top 0 -Width 0 -Height 700
        $ok | Should -BeFalse
        $Script:WPTestPrefStore.ContainsKey('WindowWidth') | Should -BeFalse
    }
}

Describe 'Resolve-BaselineWindowPlacement' {
    BeforeAll {
        $Script:WPDefaultRect = [pscustomobject]@{ Left = 100.0; Top = 100.0; Width = 1200.0; Height = 800.0 }
        $Script:WPSingle1080  = @([pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 1920.0; Height = 1040.0 })
    }
    BeforeEach { $Script:WPTestPrefStore = @{} }

    It "returns the default rect with Source='default-no-saved' when nothing is saved" {
        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $Script:WPSingle1080
        $r.Left   | Should -Be 100.0
        $r.Width  | Should -Be 1200.0
        $r.Source | Should -Be 'default-no-saved'
    }

    It "returns the saved rect with Source='saved' when bounds-validation passes" {
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 200.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 150.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1100.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 700.0
        Set-BaselineUserPreference -Key 'WindowMaximized' -Value $false

        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $Script:WPSingle1080
        $r.Source | Should -Be 'saved'
        $r.Left   | Should -Be 200.0
        $r.Width  | Should -Be 1100.0
    }

    It 'shrinks a saved rect that is larger than the current work area' {
        $smallWorkArea = @([pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 1366.0; Height = 728.0 })
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 0.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 0.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1800.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 1000.0

        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $smallWorkArea

        $r.Source | Should -Be 'saved'
        $r.Left   | Should -Be 0.0
        $r.Top    | Should -Be 0.0
        $r.Width  | Should -Be 1366.0
        $r.Height | Should -Be 728.0
    }

    It 'keeps a resized saved rect fully inside the selected work area' {
        $smallWorkArea = @([pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 1024.0; Height = 700.0 })
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 500.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 250.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1200.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 800.0

        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $smallWorkArea

        $r.Source | Should -Be 'saved'
        $r.Left   | Should -Be 0.0
        $r.Top    | Should -Be 0.0
        $r.Width  | Should -Be 1024.0
        $r.Height | Should -Be 700.0
    }

    It "falls back to default with Source='default-off-screen' when saved rect is no longer visible" {
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 9000.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 9000.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1100.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 700.0

        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $Script:WPSingle1080
        $r.Source | Should -Be 'default-off-screen'
        $r.Left   | Should -Be 100.0
    }

    It "returns Source='default-disabled' when RememberWindowPosition is false, even with valid saved rect" {
        Set-BaselineUserPreference -Key 'RememberWindowPosition' -Value $false
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 200.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 150.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1100.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 700.0

        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $Script:WPSingle1080
        $r.Source | Should -Be 'default-disabled'
        $r.Left   | Should -Be 100.0
    }

    It 'preserves the Maximized flag from the saved placement' {
        Set-BaselineUserPreference -Key 'WindowLeft'   -Value 200.0
        Set-BaselineUserPreference -Key 'WindowTop'    -Value 150.0
        Set-BaselineUserPreference -Key 'WindowWidth'  -Value 1100.0
        Set-BaselineUserPreference -Key 'WindowHeight' -Value 700.0
        Set-BaselineUserPreference -Key 'WindowMaximized' -Value $true

        $r = Resolve-BaselineWindowPlacement -DefaultRect $Script:WPDefaultRect -WorkAreas $Script:WPSingle1080
        $r.Maximized | Should -BeTrue
    }
}

Describe 'Window placement preferences before GUI user preferences load' {
    BeforeEach {
        $Script:WPPreviousStateRoot = [System.Environment]::GetEnvironmentVariable('BASELINE_STATE_ROOT')
        $Script:WPDirectStateRoot = Join-Path $TestDrive 'StateRoot'
        [System.Environment]::SetEnvironmentVariable('BASELINE_STATE_ROOT', $Script:WPDirectStateRoot, 'Process')
        Remove-Item -Path Function:\Get-BaselineUserPreference -ErrorAction SilentlyContinue
        Remove-Item -Path Function:\Set-BaselineUserPreference -ErrorAction SilentlyContinue
    }

    AfterEach {
        [System.Environment]::SetEnvironmentVariable('BASELINE_STATE_ROOT', $Script:WPPreviousStateRoot, 'Process')
        $Script:WPTestPrefStore = @{}
        function script:Get-BaselineUserPreference {
            param([Parameter(Mandatory)][string]$Key, $Default = $null)
            if ($Script:WPTestPrefStore.ContainsKey($Key)) { return $Script:WPTestPrefStore[$Key] }
            return $Default
        }
        function script:Set-BaselineUserPreference {
            param([Parameter(Mandatory)][string]$Key, $Value)
            $Script:WPTestPrefStore[$Key] = $Value
        }
    }

    It 'restores maximized placement from Baseline-user-prefs.json before UserPreferences.ps1 is loaded' {
        $profilesDirectory = Join-Path $Script:WPDirectStateRoot 'Profiles'
        $preferencesPath = Join-Path $profilesDirectory 'Baseline-user-prefs.json'
        New-Item -Path $profilesDirectory -ItemType Directory -Force | Out-Null
        @{
            Schema = 'Baseline.UserPreferences'
            SchemaVersion = 1
            SavedAtUtc = '2026-05-17T00:00:00.0000000Z'
            Values = @{
                RememberWindowPosition = $true
                WindowLeft = 20.0
                WindowTop = 30.0
                WindowWidth = 1200.0
                WindowHeight = 800.0
                WindowMaximized = $true
            }
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $preferencesPath -Encoding UTF8 -Force

        $defaultRect = [pscustomobject]@{ Left = 100.0; Top = 100.0; Width = 900.0; Height = 700.0 }
        $workAreas = @([pscustomobject]@{ Left = 0.0; Top = 0.0; Width = 1920.0; Height = 1040.0 })

        $placement = Resolve-BaselineWindowPlacement -DefaultRect $defaultRect -WorkAreas $workAreas

        $placement.Source | Should -Be 'saved'
        $placement.Maximized | Should -BeTrue
        $placement.Left | Should -Be 20.0
    }

    It 'writes maximized placement to Baseline-user-prefs.json when the GUI preference API is not loaded' {
        Save-BaselineWindowPlacement -Left 40 -Top 50 -Width 1100 -Height 720 -Maximized $true | Should -BeTrue

        $preferencesPath = Join-Path (Join-Path $Script:WPDirectStateRoot 'Profiles') 'Baseline-user-prefs.json'
        $preferences = Get-Content -LiteralPath $preferencesPath -Raw | ConvertFrom-Json

        $preferences.Values.WindowLeft | Should -Be 40.0
        $preferences.Values.WindowMaximized | Should -BeTrue
    }
}

Describe 'WindowPosition helpers exported via SharedHelpers wrapper' {
    It 'lists all five functions in the wrapper module' {
        $wrapperPath = Join-Path $PSScriptRoot '../../Module/SharedHelperModules/Baseline.SharedHelpers.WindowPosition.psm1'
        $contents = Get-Content -LiteralPath $wrapperPath -Raw
        $contents | Should -Match 'Get-BaselineDisplayWorkAreas'
        $contents | Should -Match 'Test-BaselineWindowRectVisible'
        $contents | Should -Match 'Get-BaselineSavedWindowPlacement'
        $contents | Should -Match 'Save-BaselineWindowPlacement'
        $contents | Should -Match 'Resolve-BaselineWindowPlacement'
    }

    It 'is registered in the SharedHelpers loader' {
        $loaderPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
        $contents = Get-Content -LiteralPath $loaderPath -Raw
        $contents | Should -Match "Baseline\.SharedHelpers\.WindowPosition"
        $contents | Should -Match "Resolve-BaselineWindowPlacement"
    }
}
