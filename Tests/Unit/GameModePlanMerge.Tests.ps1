Set-StrictMode -Version Latest

BeforeAll {
    <#
        .SYNOPSIS
    #>

    function Test-GuiObjectField { param([object]$Object, [string]$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName]) }

    # Json helpers must load first — GameMode.Helpers calls ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    $gameModeUiPath = Join-Path $PSScriptRoot '../../Module/GUI/GameModeUI.ps1'
    $gameModeUiAst = [System.Management.Automation.Language.Parser]::ParseFile($gameModeUiPath, [ref]$null, [ref]$null)
    $gameModeUiFunctions = $gameModeUiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $gameModeUiFunctions) {
        if ($fn.Name -in @('Test-TweakEditableInGameModeTab', 'Sync-GameModePlanFromGamingControls', 'Set-GameModeProfile')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $gameModeHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/GameMode.Helpers.ps1'
    $gameModeHelpersAst = [System.Management.Automation.Language.Parser]::ParseFile($gameModeHelpersPath, [ref]$null, [ref]$null)
    $gameModeHelpersFunctions = $gameModeHelpersAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $gameModeHelpersFunctions) {
        if ($fn.Name -eq 'Test-GameModeAdvancedProfileDefaultSelection') {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $executionPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration/ExecutionStateSummary.ps1'
    $executionAst = [System.Management.Automation.Language.Parser]::ParseFile($executionPath, [ref]$null, [ref]$null)
    $executionFunctions = $executionAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $executionFunctions) {
        if ($fn.Name -in @('Get-GuiTweakRunListPrimaryTab', 'Test-GuiTweakRunListItemBelongsToUpdates', 'Test-GuiTweakRunListItemBelongsToGaming', 'Select-GuiModeScopedTweakRunList', 'Get-ActiveTweakRunList')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    <#
        .SYNOPSIS
    #>

    function Get-SelectedTweakRunList {
        return @($script:SelectedTweaks)
    }

    <#
        .SYNOPSIS
    #>
    function Get-ManifestEntryByFunction {
        param (
            [object[]]$Manifest,
            [string]$Function
        )

        return @($Manifest | Where-Object { [string]$_.Function -eq [string]$Function } | Select-Object -First 1)
    }

    <#
        .SYNOPSIS
    #>
    function Get-GameModePlan {
        return @($script:GameModePlan)
    }

    <#
        .SYNOPSIS
    #>

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
        $script:GuiSelectionBulkUpdateInProgress = $false
        $script:GameModePlanSyncPending = $false
        $script:GameModeAllowlist = @('GPUScheduling', 'PowerPlan', 'MouseAcceleration')
        $script:GamingCrossTabFunctions = [System.Collections.Generic.HashSet[string]]::new([string[]]@('PowerPlan'))
        $script:CategoryToPrimary = @{
            Gaming = 'Gaming'
            System = 'System'
        }
        Set-Variable -Name CategoryToPrimary -Scope Script -Value $script:CategoryToPrimary
        $script:SyncGameModeContextStateScript = {}
        <#
            .SYNOPSIS
        #>

        function Get-UxLocalizedString {
            param (
                [string]$Key,
                [string]$Fallback
            )

            return $Fallback
        }
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
        $script:PresetStatusMessage | Should -Match '3 action\(s\) selected'
    }

    It 'defers plan recompute while a bulk selection update is active' {
        $script:GuiSelectionBulkUpdateInProgress = $true
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'MouseAcceleration'
                Category = 'Gaming'
            }
        )
        $script:SelectedTweaks = @(
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

        $script:GameModePlanSyncPending | Should -BeTrue
        @($script:GameModePlan).Count | Should -Be 0
        $script:PresetStatusMessage | Should -BeNullOrEmpty
    }
}

Describe 'Set-GameModeProfile' {
    BeforeEach {
        $script:GameMode = $true
        $script:GameModeProfile = $null
        $script:GameModePlan = @()
        $script:GameModeCorePlan = @()
        $script:GameModeAdvancedSelections = @{}
        $script:GameModeDecisionOverrides = @{}
        $script:GameModeAllowlist = @('SystemResponsiveness', 'DirectXAutoHdr')
        $script:AdvancedEntries = @(
            [pscustomobject]@{
                Function = 'SystemResponsiveness'
                DefaultCheckedByProfile = [pscustomobject]@{
                    Competitive = $true
                    Streaming = $true
                    Casual = $false
                    Troubleshooting = $false
                }
            }
            [pscustomobject]@{
                Function = 'DirectXAutoHdr'
                DefaultCheckedByProfile = [pscustomobject]@{
                    Casual = $true
                    Competitive = $false
                    Streaming = $false
                    Troubleshooting = $false
                }
            }
        )

        <#
            .SYNOPSIS
        #>

        function Import-GameModeAdvancedData {
            return @($script:AdvancedEntries)
        }

        <#
            .SYNOPSIS
        #>
        function Get-UxLocalizedString {
            param (
                [string]$Key,
                [string]$Fallback
            )

            return $Fallback
        }

        <#
            .SYNOPSIS
        #>
        function LogInfo {
            param ([string]$Message)
        }

        <#
            .SYNOPSIS
        #>

        function Get-GameModeDecisionOverridesText {
            param ([hashtable]$Overrides)

            return 'none'
        }

        $script:SaveGuiUndoSnapshotScript = {}
        $script:BuildGameModePlanScript = {
            param ([string]$ProfileName)

            return @(
                [pscustomobject]@{
                    Function = 'CoreTweak'
                    RequiresRestart = $false
                }
            )
        }
        $script:BuildGameModeAdvancedPlanEntriesScript = {
            param ([string]$ProfileName)

            return @()
        }
        $script:SyncGameModeContextStateScript = {}
        $script:SyncGameModePlanToGamingControlsScript = {
            param ([object[]]$Plan)
        }
        $script:InvokeGuiStateTransitionScript = {
            param (
                [string]$Context,
                [switch]$ClearCache,
                [switch]$RebuildTab,
                [switch]$UpdatePresetBadge,
                [string]$StatusMessage,
                [string]$StatusTone
            )
        }
        $script:UpdateRunPathContextLabelScript = {}
        $script:PresetStatusBadge = $null
        $script:PresetStatusMessage = $null
    }

    It 'pre-checks advanced options from per-profile defaults' {
        Set-GameModeProfile -ProfileName 'Competitive'

        $script:GameModeProfile | Should -Be 'Competitive'
        $script:GameModeAdvancedSelections['SystemResponsiveness'] | Should -Be $true
        $script:GameModeAdvancedSelections['DirectXAutoHdr'] | Should -Be $false
    }

    It 'pre-checks different advanced options for another profile' {
        Set-GameModeProfile -ProfileName 'Casual'

        $script:GameModeProfile | Should -Be 'Casual'
        $script:GameModeAdvancedSelections['SystemResponsiveness'] | Should -Be $false
        $script:GameModeAdvancedSelections['DirectXAutoHdr'] | Should -Be $true
    }
}

Describe 'Get-ActiveTweakRunList' {
    BeforeEach {
        $script:GameMode = $true
        $script:GamingModeActive = $true
        $script:UpdatesModeActive = $false
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
                Category = 'Gaming'
                Selection = 'Ultimate'
            }
            [pscustomobject]@{
                Function = 'MouseAcceleration'
                Category = 'Gaming'
                Selection = 'Enable'
            }
        )

        $result = @(Get-ActiveTweakRunList)

        $result.Count | Should -Be 8
        @($result.Function) | Should -Contain 'PowerPlan'
        @($result.Function) | Should -Contain 'MouseAcceleration'
    }
}
