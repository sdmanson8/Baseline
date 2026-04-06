Set-StrictMode -Version Latest

BeforeAll {
    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }
    $gameModeUiPath = Join-Path $PSScriptRoot '../../Module/GUI/GameModeUI.ps1'
    $gameModeUiAst = [System.Management.Automation.Language.Parser]::ParseFile($gameModeUiPath, [ref]$null, [ref]$null)
    $gameModeUiFunctions = $gameModeUiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $gameModeUiFunctions) {
        if ($fn.Name -in @('Test-TweakEditableInGameModeTab', 'Sync-GameModePlanFromGamingControls')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $executionPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration.ps1'
    $executionAst = [System.Management.Automation.Language.Parser]::ParseFile($executionPath, [ref]$null, [ref]$null)
    $executionFunctions = $executionAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $executionFunctions) {
        if ($fn.Name -eq 'Get-ActiveTweakRunList') {
            Invoke-Expression $fn.Extent.Text
        }
    }

    function Get-SelectedTweakRunList {
        return @($script:SelectedTweaks)
    }

    function Get-ManifestEntryByFunction {
        param (
            [object[]]$Manifest,
            [string]$Function
        )

        return @($Manifest | Where-Object { [string]$_.Function -eq [string]$Function } | Select-Object -First 1)
    }

    function Get-GameModePlan {
        return @($script:GameModePlan)
    }

    function Update-GameModeStatusText {
        param (
            [string]$Message,
            [string]$Tone
        )

        $script:LastGameModeStatus = $Message
        $script:LastGameModeTone = $Tone
    }
}

Describe 'Game Mode plan merge' {
    BeforeEach {
        $script:GameMode = $true
        $script:GameModeProfile = 'Competitive'
        $script:GameModePlan = @()
        $script:TweakManifest = @()
        $script:Controls = @{ 0 = [pscustomobject]@{ IsEnabled = $true } }
        $script:SelectedTweaks = @()
        $script:GameModeControlSyncInProgress = $false
        $script:GameModeAllowlist = @('GPUScheduling', 'PowerPlan', 'MouseAcceleration')
        $script:GamingCrossTabFunctions = [System.Collections.Generic.HashSet[string]]::new([string[]]@('PowerPlan'))
        $script:CategoryToPrimary = @{
            Gaming = 'Gaming'
            System = 'System'
        }
        Set-Variable -Name CategoryToPrimary -Scope Script -Value $script:CategoryToPrimary
        $script:SyncGameModeContextStateScript = {}
        $script:UpdateGameModeStatusTextScript = {
            param(
                [string]$Message,
                [string]$Tone
            )

            $script:LastGameModeStatus = $Message
            $script:LastGameModeTone = $Tone
        }
        $script:PresetStatusBadge = $null
        $script:PresetStatusMessage = $null
        $script:LastGameModeStatus = $null
        $script:LastGameModeTone = $null
    }

    It 'treats reviewed cross-tab entries as editable from the Gaming tab' {
        Test-TweakEditableInGameModeTab -Tweak ([pscustomobject]@{
            Function = 'PowerPlan'
            Category = 'System'
        }) | Should -Be $true

        Test-TweakEditableInGameModeTab -Tweak ([pscustomobject]@{
            Function = 'SomeOtherSystemTweak'
            Category = 'System'
        }) | Should -Be $false
    }

    It 'merges profile actions with manual Gaming-tab selections including cross-tab functions' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'GPUScheduling'
                Category = 'Gaming'
            }
            [pscustomobject]@{
                Function = 'PowerPlan'
                Category = 'System'
            }
            [pscustomobject]@{
                Function = 'MouseAcceleration'
                Category = 'Gaming'
            }
        )

        $script:GameModePlan = @(
            [pscustomobject]@{
                Function = 'GPUScheduling'
                Category = 'Gaming'
                Selection = 'Enable'
                ToggleParam = 'Enable'
                RequiresRestart = $false
            }
            [pscustomobject]@{
                Function = 'PowerPlan'
                Category = 'System'
                Selection = 'High'
                Value = 'High'
                SelectedValue = 'High'
                RequiresRestart = $false
            }
        )

        $script:SelectedTweaks = @(
            [pscustomobject]@{
                Name = 'GPU Scheduling'
                Function = 'GPUScheduling'
                Category = 'Gaming'
                Type = 'Toggle'
                Selection = 'Enable'
                ToggleParam = 'Enable'
                OnParam = 'Enable'
                OffParam = 'Disable'
                IsChecked = $true
                RequiresRestart = $false
            }
            [pscustomobject]@{
                Name = 'Power Plan'
                Function = 'PowerPlan'
                Category = 'System'
                Type = 'Choice'
                Selection = 'Ultimate'
                Value = 'Ultimate'
                SelectedIndex = 2
                SelectedValue = 'Ultimate'
                RequiresRestart = $false
            }
            [pscustomobject]@{
                Name = 'Mouse Acceleration'
                Function = 'MouseAcceleration'
                Category = 'Gaming'
                Type = 'Toggle'
                Selection = 'Enable'
                ToggleParam = 'Enable'
                OnParam = 'Enable'
                OffParam = 'Disable'
                IsChecked = $true
                RequiresRestart = $false
            }
        )

        Sync-GameModePlanFromGamingControls

        @($script:GameModePlan).Count | Should -Be 3
        @($script:GameModePlan | Where-Object Function -eq 'PowerPlan') | Should -HaveCount 1
        (@($script:GameModePlan | Where-Object Function -eq 'PowerPlan'))[0].Selection | Should -Be 'Ultimate'
        @($script:GameModePlan | Where-Object Function -eq 'MouseAcceleration') | Should -HaveCount 1
        $script:PresetStatusMessage | Should -Match '3 actions selected'
    }
}

Describe 'Get-ActiveTweakRunList' {
    BeforeEach {
        $script:GameMode = $true
        $script:GameModePlan = @()
        $script:GameModeAllowlist = @(
            'Profile01', 'Profile02', 'Profile03', 'Profile04', 'Profile05', 'Profile06',
            'PowerPlan', 'MouseAcceleration'
        )
        $script:SelectedTweaks = @()
    }

    It 'returns the union of the profile plan and extra Gaming-tab selections for preview and run counts' {
        $script:GameModePlan = @(
            1..6 | ForEach-Object {
                [pscustomobject]@{
                    Function = ('Profile{0:D2}' -f $_)
                    FromGameMode = $true
                    GameModeProfile = 'Competitive'
                }
            }
        )

        $script:SelectedTweaks = @(
            [pscustomobject]@{
                Function = 'PowerPlan'
                Selection = 'Ultimate'
            }
            [pscustomobject]@{
                Function = 'MouseAcceleration'
                Selection = 'Enable'
            }
        )

        $result = @(Get-ActiveTweakRunList)

        $result.Count | Should -Be 8
        @($result.Function) | Should -Contain 'PowerPlan'
        @($result.Function) | Should -Contain 'MouseAcceleration'
    }
}
