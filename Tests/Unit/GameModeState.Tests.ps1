Set-StrictMode -Version Latest

BeforeAll {
    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/GameModeState.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @(
            'Sync-GameModeContextState',
            'Test-HasGameModeTweaks',
            'Test-IsGameModeRun',
            'Test-IsGameModeActive',
            'Get-GameModeProfile',
            'Get-GameModePlan'
        )) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'GameModeState' {
    BeforeEach {
        $script:GameMode = $false
        $script:GameModeProfile = $null
        $script:GameModeCorePlan = @()
        $script:GameModePlan = @()
        $script:GameModeControlSyncInProgress = $false
        $script:GameModeDecisionOverrides = @{}
        $script:GameModeAdvancedSelections = @{}
        $script:GameModePreviousPrimaryTab = $null
        $script:GameModeAllowlist = @()
        $script:ExecutionGameModeContext = $null
        $script:Ctx = @{
            GameMode = @{
                Active = $false
                Profile = $null
                CorePlan = @()
                Plan = @()
                ControlSyncInProgress = $false
                DecisionOverrides = @{}
                AdvancedSelections = @{}
                PreviousPrimaryTab = $null
                Allowlist = @()
                ExecutionContext = $null
            }
        }
    }

    It 'syncs the active Game Mode plan into the shared context used by run accessors' {
        $script:GameMode = $true
        $script:GameModeProfile = 'Casual'
        $script:GameModeCorePlan = @(
            [pscustomobject]@{
                Function = 'EnableGameBar'
                FromGameMode = $true
                GameModeProfile = 'Casual'
            }
        )
        $script:GameModePlan = @(
            [pscustomobject]@{
                Function = 'EnableGameBar'
                FromGameMode = $true
                GameModeProfile = 'Casual'
            }
        )
        $script:GameModeDecisionOverrides = @{ Overlay = 'Keep' }
        $script:GameModeAdvancedSelections = @{ EnableGameBar = $true }
        $script:GameModePreviousPrimaryTab = 'System'
        $script:GameModeAllowlist = @('EnableGameBar')

        Sync-GameModeContextState

        Test-IsGameModeActive | Should -Be $true
        Get-GameModeProfile | Should -Be 'Casual'
        @(Get-GameModePlan) | Should -HaveCount 1
        (Get-GameModePlan)[0].Function | Should -Be 'EnableGameBar'
        (Test-IsGameModeRun -TweakList @(Get-GameModePlan)) | Should -Be $true
        $script:Ctx.GameMode.DecisionOverrides['Overlay'] | Should -Be 'Keep'
        $script:Ctx.GameMode.AdvancedSelections['EnableGameBar'] | Should -Be $true
        $script:Ctx.GameMode.PreviousPrimaryTab | Should -Be 'System'
    }
}
