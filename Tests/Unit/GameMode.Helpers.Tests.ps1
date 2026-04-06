Set-StrictMode -Version Latest

BeforeAll {
    # Extract inner functions from both Manifest.Helpers.ps1 (for Get-TweakManifestEntryValue
    # and Test-TweakManifestEntryField) and GameMode.Helpers.ps1 via AST.
    # Uses Invoke-Expression on function definition AST nodes - safe because
    # ParseFile only parses (no execution) and we only evaluate FunctionDefinitionAst
    # nodes, which merely define functions without side effects.

    $Script:SharedHelpersModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../Module')).Path
    $Script:CachedGameModeAllowlistData = $null
    $Script:CachedGameModeAdvancedData = $null
    $Script:CachedGameModeProfileData = $null

    $manifestPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Manifest.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($manifestPath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $neededFromManifest = @('Get-TweakManifestEntryValue', 'Test-TweakManifestEntryField')
    foreach ($fn in $functions) {
        if ($neededFromManifest -contains $fn.Name) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $gameModeHelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/GameMode.Helpers.ps1'
    $ast2 = [System.Management.Automation.Language.Parser]::ParseFile($gameModeHelperPath, [ref]$null, [ref]$null)
    $functions2 = $ast2.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions2) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Get-GameModeAllowlist' {
    It 'returns a non-empty array of function names' {
        $allowlist = Get-GameModeAllowlist

        $allowlist | Should -Not -BeNullOrEmpty
        $allowlist.Count | Should -BeGreaterThan 0
    }

    It 'contains the core gaming functions' {
        $allowlist = Get-GameModeAllowlist

        $allowlist | Should -Contain 'GPUScheduling'
        $allowlist | Should -Contain 'XboxGameBar'
        $allowlist | Should -Contain 'FullscreenOptimizations'
    }

    It 'contains only unique entries' {
        $allowlist = Get-GameModeAllowlist
        $unique = @($allowlist | Select-Object -Unique)

        $unique.Count | Should -Be $allowlist.Count
    }

    It 'contains the cross-category reviewed entries' {
        $allowlist = Get-GameModeAllowlist
        $reviewed = Get-GameModeReviewedCrossCategoryAllowlist

        foreach ($fn in $reviewed) {
            $allowlist | Should -Contain $fn
        }
    }
}

Describe 'Test-GameModeAllowlistEntryReviewed' {
    It 'returns true for an entry in the Gaming category' {
        $entry = [pscustomobject]@{
            Function = 'GPUScheduling'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
        }

        Test-GameModeAllowlistEntryReviewed -Entry $entry | Should -Be $true
    }

    It 'returns true for a cross-category entry on the reviewed list' {
        $entry = [pscustomobject]@{
            Function = 'PowerPlan'
            Category = 'System'
            SourceRegion = 'System'
        }

        Test-GameModeAllowlistEntryReviewed -Entry $entry | Should -Be $true
    }

    It 'returns false for a cross-category entry not on the reviewed list' {
        $entry = [pscustomobject]@{
            Function = 'SomeOtherTweak'
            Category = 'System'
            SourceRegion = 'System'
        }

        Test-GameModeAllowlistEntryReviewed -Entry $entry | Should -Be $false
    }

    It 'returns false for null entry' {
        Test-GameModeAllowlistEntryReviewed -Entry $null | Should -Be $false
    }

    It 'returns false when Function is empty' {
        $entry = [pscustomobject]@{
            Function = ''
            Category = 'Gaming'
        }

        Test-GameModeAllowlistEntryReviewed -Entry $entry | Should -Be $false
    }

    It 'returns true when SourceRegion is absent but Category is Gaming' {
        $entry = [pscustomobject]@{
            Function = 'XboxGameBar'
            Category = 'Gaming'
        }

        Test-GameModeAllowlistEntryReviewed -Entry $entry | Should -Be $true
    }
}

Describe 'Test-GameModeProfileDefaultEligible' {
    It 'returns true for a low-risk, safe, Toggle entry in Gaming category' {
        $entry = [pscustomobject]@{
            Function = 'XboxGameTips'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
            Type = 'Toggle'
            Risk = 'Low'
            Safe = $true
            WorkflowSensitivity = 'Low'
        }

        Test-GameModeProfileDefaultEligible -Entry $entry | Should -Be $true
    }

    It 'returns false for a non-Toggle entry' {
        $entry = [pscustomobject]@{
            Function = 'XboxGameBar'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
            Type = 'Action'
            Risk = 'Low'
            Safe = $true
        }

        Test-GameModeProfileDefaultEligible -Entry $entry | Should -Be $false
    }

    It 'returns false for a high-risk entry' {
        $entry = [pscustomobject]@{
            Function = 'GPUScheduling'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
            Type = 'Toggle'
            Risk = 'High'
            Safe = $true
        }

        Test-GameModeProfileDefaultEligible -Entry $entry | Should -Be $false
    }

    It 'returns false when Safe is false' {
        $entry = [pscustomobject]@{
            Function = 'SomeTweak'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
            Type = 'Toggle'
            Risk = 'Low'
            Safe = $false
        }

        Test-GameModeProfileDefaultEligible -Entry $entry | Should -Be $false
    }

    It 'returns false for high WorkflowSensitivity' {
        $entry = [pscustomobject]@{
            Function = 'SomeTweak'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
            Type = 'Toggle'
            Risk = 'Low'
            Safe = $true
            WorkflowSensitivity = 'High'
        }

        Test-GameModeProfileDefaultEligible -Entry $entry | Should -Be $false
    }

    It 'defaults WorkflowSensitivity to Low when absent, making entry eligible' {
        $entry = [pscustomobject]@{
            Function = 'XboxGameTips'
            Category = 'Gaming'
            SourceRegion = 'Gaming'
            Type = 'Toggle'
            Risk = 'Low'
            Safe = $true
        }

        Test-GameModeProfileDefaultEligible -Entry $entry | Should -Be $true
    }

    It 'returns false for null entry' {
        Test-GameModeProfileDefaultEligible -Entry $null | Should -Be $false
    }
}

Describe 'Merge-GameModeSelectionState' {
    It 'returns empty ordered hashtable when Manifest is null' {
        $result = Merge-GameModeSelectionState -Manifest $null -ProfileName 'Casual'

        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 0
    }

    It 'returns empty ordered hashtable when ProfileName is blank' {
        $result = Merge-GameModeSelectionState -Manifest @() -ProfileName ''

        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 0
    }

    It 'selects eligible entries from manifest for a given profile' {
        $manifest = @(
            [pscustomobject]@{
                Function = 'XboxGameTips'
                Category = 'Gaming'
                SourceRegion = 'Gaming'
                Type = 'Toggle'
                Risk = 'Low'
                Safe = $true
                OnParam = 'Enable'
                OffParam = 'Disable'
                WorkflowSensitivity = 'Low'
                GameModeDefault = $true
            }
        )

        $result = Merge-GameModeSelectionState -Manifest $manifest -ProfileName 'Casual' -Allowlist @('XboxGameTips')

        $result.Count | Should -Be 1
        $result['XboxGameTips'] | Should -Not -BeNullOrEmpty
        $result['XboxGameTips'].Function | Should -Be 'XboxGameTips'
        $result['XboxGameTips'].Profile | Should -Be 'Casual'
        $result['XboxGameTips'].ToggleParam | Should -Not -BeNullOrEmpty
    }

    It 'excludes entries not on the allowlist' {
        $manifest = @(
            [pscustomobject]@{
                Function = 'XboxGameTips'
                Category = 'Gaming'
                SourceRegion = 'Gaming'
                Type = 'Toggle'
                Risk = 'Low'
                Safe = $true
                OnParam = 'Enable'
                OffParam = 'Disable'
                GameModeDefault = $true
            }
        )

        $result = Merge-GameModeSelectionState -Manifest $manifest -ProfileName 'Casual' -Allowlist @('GPUScheduling')

        $result.Count | Should -Be 0
    }

    It 'applies DecisionOverrides when provided' {
        $manifest = @(
            [pscustomobject]@{
                Function = 'GPUScheduling'
                Category = 'Gaming'
                SourceRegion = 'Gaming'
                Type = 'Toggle'
                Risk = 'Low'
                Safe = $true
                OnParam = 'Enable'
                OffParam = 'Disable'
                DecisionPromptKey = 'GPUScheduling'
            }
        )
        $overrides = @{ 'GPUScheduling' = 'Enable' }

        $result = Merge-GameModeSelectionState -Manifest $manifest -ProfileName 'Casual' -DecisionOverrides $overrides -Allowlist @('GPUScheduling')

        $result.Count | Should -Be 1
        $result['GPUScheduling'].SelectionSource | Should -Be 'DecisionOverride'
        $result['GPUScheduling'].ToggleParam | Should -Be 'Enable'
    }
}

Describe 'Resolve-GameModeAllowlistToggleParam' {
    It 'returns null when AllowlistEntry is null' {
        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $null -ManifestEntry @{} -ProfileName 'Casual'

        $result | Should -BeNullOrEmpty
    }

    It 'returns null when ProfileName is blank' {
        $entry = [pscustomobject]@{ ApplyValueByProfile = [pscustomobject]@{ Casual = $true } }

        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $entry -ManifestEntry @{} -ProfileName ''

        $result | Should -BeNullOrEmpty
    }

    It 'returns string value when ApplyValueByProfile has a string for the profile' {
        $entry = [pscustomobject]@{
            ApplyValueByProfile = [pscustomobject]@{ Casual = 'High' }
        }

        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $entry -ManifestEntry @{} -ProfileName 'Casual'

        $result | Should -Be 'High'
    }

    It 'returns null when ApplyValueByProfile is false for the profile' {
        $entry = [pscustomobject]@{
            ApplyValueByProfile = [pscustomobject]@{ Casual = $false }
        }

        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $entry -ManifestEntry @{} -ProfileName 'Casual'

        $result | Should -BeNullOrEmpty
    }

    It 'returns null when the profile is not in ApplyValueByProfile' {
        $entry = [pscustomobject]@{
            ApplyValueByProfile = [pscustomobject]@{ Competitive = $true }
        }

        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $entry -ManifestEntry @{} -ProfileName 'Casual'

        $result | Should -BeNullOrEmpty
    }

    It 'uses ApplyChoiceValueByProfile when ApplyValueByProfile is boolean true' {
        $manifestEntry = [pscustomobject]@{ OffParam = 'Disable' }
        $entry = [pscustomobject]@{
            ApplyValueByProfile = [pscustomobject]@{ Casual = $true }
            ApplyChoiceValueByProfile = [pscustomobject]@{ Casual = 'CustomChoice' }
        }

        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $entry -ManifestEntry $manifestEntry -ProfileName 'Casual'

        $result | Should -Be 'CustomChoice'
    }

    It 'falls back to OffParam when boolean true and no ApplyChoiceValueByProfile' {
        $manifestEntry = [pscustomobject]@{ OffParam = 'Disable' }
        $entry = [pscustomobject]@{
            ApplyValueByProfile = [pscustomobject]@{ Casual = $true }
        }

        $result = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $entry -ManifestEntry $manifestEntry -ProfileName 'Casual'

        $result | Should -Be 'Disable'
    }
}
