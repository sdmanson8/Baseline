Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/FilteringLogic.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        # Rewrite to script: scope so $Script: variables resolve correctly in Pester 5 on PS 5.1
        $fnText = $fn.Extent.Text -replace "^(\s*)function\s+$([regex]::Escape($fn.Name))", "`$1function script:$($fn.Name)"
        Invoke-Expression $fnText
    }

    # Stub helper functions referenced by FilteringLogic
    function script:Test-GuiObjectField { param([object]$Object, [string]$FieldName) return ($null -ne $Object -and $Object.PSObject.Properties[$FieldName]) }
    function script:Test-TweakRemovalOperation { param([object]$Tweak) return ($Tweak.Tags -contains 'removal') }
    function script:Test-TweakIsSelected { param([object]$Tweak, [object]$StateSource) return ($StateSource.IsChecked -eq $true) }
    function script:Test-TweakIsRestorable { param([object]$Tweak) return ($Tweak.Restorable -eq $true) }
    function script:Test-TweakIsGamingRelated { param([object]$Tweak) return ($Tweak.Tags -contains 'gaming') }

    # Initialize $Script: filter state so functions can resolve them under StrictMode
    $Script:RiskFilter = 'All'
    $Script:CategoryFilter = 'All'
    $Script:SelectedOnlyFilter = $false
    $Script:HighRiskOnlyFilter = $false
    $Script:RestorableOnlyFilter = $false
    $Script:GamingOnlyFilter = $false
    $Script:SafeMode = $false
    $Script:AdvancedMode = $false
}

Describe 'Test-TweakVisibleInSafeMode' {
    It 'returns false for null tweak' {
        Test-TweakVisibleInSafeMode -Tweak $null | Should -Be $false
    }

    It 'returns true for low-risk Basic-tier safe tweak' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $true
    }

    It 'returns false for medium-risk tweak' {
        $tweak = [pscustomobject]@{ Risk = 'Medium'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }

    It 'returns false for high-risk tweak' {
        $tweak = [pscustomobject]@{ Risk = 'High'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }

    It 'returns false for Advanced preset tier' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Advanced'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }

    It 'returns false for Balanced preset tier' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Balanced'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }

    It 'returns true for Minimal preset tier' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Minimal'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $true
    }

    It 'returns false when Safe is explicitly false' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $false; Type = 'Toggle'; Restorable = $true; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }

    It 'returns false for non-restorable non-action toggle' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $false; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }

    It 'allows non-restorable action items (low-risk setup actions)' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $true; Type = 'Action'; Restorable = $false; Tags = @() }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $true
    }

    It 'returns false for removal operations' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @('removal') }
        Test-TweakVisibleInSafeMode -Tweak $tweak | Should -Be $false
    }
}

Describe 'Test-TweakVisibleInCurrentMode' {
    BeforeEach {
        $Script:GameMode = $false
        $Script:GameModeAllowlist = @()
        $Script:SafeMode = $false
        $Script:AdvancedMode = $false
    }

    It 'returns false for null tweak' {
        Test-TweakVisibleInCurrentMode -Tweak $null | Should -Be $false
    }

    It 'hides high-risk tweaks in standard mode' {
        $tweak = [pscustomobject]@{ Risk = 'High'; PresetTier = 'Advanced'; Safe = $false; Type = 'Toggle'; Restorable = $true; Tags = @(); Function = 'TestFunc' }
        Test-TweakVisibleInCurrentMode -Tweak $tweak | Should -Be $false
    }

    It 'shows all tweaks in advanced mode' {
        $Script:AdvancedMode = $true
        $tweak = [pscustomobject]@{ Risk = 'High'; PresetTier = 'Advanced'; Safe = $false; Type = 'Toggle'; Restorable = $true; Tags = @(); Function = 'TestFunc' }
        Test-TweakVisibleInCurrentMode -Tweak $tweak | Should -Be $true
    }

    It 'hides advanced-tagged tweaks in standard mode' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @('advanced'); Function = 'TestFunc' }
        Test-TweakVisibleInCurrentMode -Tweak $tweak | Should -Be $false
    }

    It 'shows game mode allowlist items regardless of safe mode' {
        $Script:SafeMode = $true
        $Script:GameMode = $true
        $Script:GameModeAllowlist = @('GPUScheduling')
        $tweak = [pscustomobject]@{ Risk = 'Medium'; PresetTier = 'Balanced'; Safe = $false; Type = 'Toggle'; Restorable = $true; Tags = @(); Function = 'GPUScheduling' }
        Test-TweakVisibleInCurrentMode -Tweak $tweak | Should -Be $true
    }

    It 'delegates to safe mode filter when safe mode is on' {
        $Script:SafeMode = $true
        $safetweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Safe = $true; Type = 'Toggle'; Restorable = $true; Tags = @(); Function = 'SafeFunc' }
        Test-TweakVisibleInCurrentMode -Tweak $safetweak | Should -Be $true

        $unsafetweak = [pscustomobject]@{ Risk = 'Medium'; PresetTier = 'Advanced'; Safe = $false; Type = 'Toggle'; Restorable = $true; Tags = @(); Function = 'UnsafeFunc' }
        Test-TweakVisibleInCurrentMode -Tweak $unsafetweak | Should -Be $false
    }
}

Describe 'Get-CurrentFilterSummaryItems' {
    BeforeEach {
        $Script:RiskFilter = 'All'
        $Script:CategoryFilter = 'All'
        $Script:SelectedOnlyFilter = $false
        $Script:HighRiskOnlyFilter = $false
        $Script:RestorableOnlyFilter = $false
        $Script:GamingOnlyFilter = $false
        $Script:SafeMode = $false
        $Script:AdvancedMode = $false
    }

    It 'returns empty array when no filters active' {
        $result = Get-CurrentFilterSummaryItems
        $result.Count | Should -Be 0
    }

    It 'includes risk filter item' {
        $Script:RiskFilter = 'High'
        $result = @(Get-CurrentFilterSummaryItems)
        $result.Count | Should -Be 1
        $result[0].Label | Should -Be 'Risk: High'
        $result[0].Tone | Should -Be 'Danger'
    }

    It 'includes search query item' {
        $result = @(Get-CurrentFilterSummaryItems -SearchQuery 'firewall')
        $result.Count | Should -Be 1
        $result[0].Label | Should -Be 'Search: firewall'
    }

    It 'includes safe mode item' {
        $Script:SafeMode = $true
        $result = @(Get-CurrentFilterSummaryItems)
        $result.Count | Should -Be 1
        $result[0].Label | Should -Be 'Safe mode'
        $result[0].Tone | Should -Be 'Success'
    }

    It 'includes expert mode item' {
        $Script:AdvancedMode = $true
        $result = @(Get-CurrentFilterSummaryItems)
        $result.Count | Should -Be 1
        $result[0].Label | Should -Be 'Expert mode'
        $result[0].Tone | Should -Be 'Danger'
    }

    It 'includes multiple active filters' {
        $Script:RiskFilter = 'Medium'
        $Script:SelectedOnlyFilter = $true
        $Script:RestorableOnlyFilter = $true
        $result = Get-CurrentFilterSummaryItems
        $result.Count | Should -Be 3
    }

    It 'maps risk tones correctly' {
        $Script:RiskFilter = 'Low'
        $result = Get-CurrentFilterSummaryItems
        $result[0].Tone | Should -Be 'Success'

        $Script:RiskFilter = 'Medium'
        $result = Get-CurrentFilterSummaryItems
        $result[0].Tone | Should -Be 'Caution'
    }
}

Describe 'Test-TweakMatchesCurrentFilters' {
    BeforeEach {
        $Script:RiskFilter = 'All'
        $Script:CategoryFilter = 'All'
        $Script:SelectedOnlyFilter = $false
        $Script:HighRiskOnlyFilter = $false
        $Script:RestorableOnlyFilter = $false
        $Script:GamingOnlyFilter = $false
        $Script:SafeMode = $false
        $Script:AdvancedMode = $true
        $Script:TweakSearchHaystacks = @{}
        $Script:GameMode = $false
        $Script:GameModeAllowlist = @()
        $Script:CategoryToPrimary = @{ 'System' = 'System'; 'Privacy' = 'Privacy' }
    }

    It 'matches tweak in correct tab with no filters' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Category = 'System'; Tags = @(); Function = 'Test'; Name = 'Test'; Description = ''; Detail = ''; WhyThisMatters = ''; SubCategory = ''; Safe = $true; Impact = ''; RequiresRestart = $false; Type = 'Toggle'; Restorable = $true }
        Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab 'System' -SearchQuery '' | Should -Be $true
    }

    It 'rejects tweak in wrong tab' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Category = 'Privacy'; Tags = @(); Function = 'Test'; Name = 'Test'; Description = ''; Detail = ''; WhyThisMatters = ''; SubCategory = ''; Safe = $true; Impact = ''; RequiresRestart = $false; Type = 'Toggle'; Restorable = $true }
        Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab 'System' -SearchQuery '' | Should -Be $false
    }

    It 'filters by risk level' {
        $Script:RiskFilter = 'High'
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Category = 'System'; Tags = @(); Function = 'Test'; Name = 'Test'; Description = ''; Detail = ''; WhyThisMatters = ''; SubCategory = ''; Safe = $true; Impact = ''; RequiresRestart = $false; Type = 'Toggle'; Restorable = $true }
        Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab 'System' -SearchQuery '' | Should -Be $false
    }

    It 'filters by search query' {
        $tweak = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Category = 'System'; Tags = @(); Function = 'Test'; Name = 'Firewall Settings'; Description = 'Configure firewall'; Detail = ''; WhyThisMatters = ''; SubCategory = ''; Safe = $true; Impact = ''; RequiresRestart = $false; Type = 'Toggle'; Restorable = $true }
        Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab 'System' -SearchQuery 'firewall' | Should -Be $true
        Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab 'System' -SearchQuery 'nonexistent' | Should -Be $false
    }

    It 'filters by high-risk only' {
        $Script:HighRiskOnlyFilter = $true
        $lowRisk = [pscustomobject]@{ Risk = 'Low'; PresetTier = 'Basic'; Category = 'System'; Tags = @(); Function = 'Test'; Name = 'Test'; Description = ''; Detail = ''; WhyThisMatters = ''; SubCategory = ''; Safe = $true; Impact = ''; RequiresRestart = $false; Type = 'Toggle'; Restorable = $true }
        Test-TweakMatchesCurrentFilters -Tweak $lowRisk -PrimaryTab 'System' -SearchQuery '' | Should -Be $false

        $highRisk = [pscustomobject]@{ Risk = 'High'; PresetTier = 'Advanced'; Category = 'System'; Tags = @(); Function = 'TestHigh'; Name = 'Test'; Description = ''; Detail = ''; WhyThisMatters = ''; SubCategory = ''; Safe = $false; Impact = ''; RequiresRestart = $false; Type = 'Toggle'; Restorable = $true }
        Test-TweakMatchesCurrentFilters -Tweak $highRisk -PrimaryTab 'System' -SearchQuery '' | Should -Be $true
    }
}
