Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1'
    $aiRemovalPath = Join-Path $PSScriptRoot '../../Module/Regions/UWPApps/AIRemoval.ps1'
    $uwpAppsManifestPath = Join-Path $PSScriptRoot '../../Module/Data/UWPApps.json'
    $script:UWPAppsContent = Get-BaselineTestSourceText -Path $filePath
    $script:AIRemovalContent = Get-BaselineTestSourceText -Path $aiRemovalPath
    $script:UWPAppsManifest = Get-BaselineTestSourceText -Path $uwpAppsManifestPath | ConvertFrom-Json
    $script:CopilotManifestEntry = $script:UWPAppsManifest.Entries | Where-Object { $_.Function -eq 'Copilot' } | Select-Object -First 1
    foreach ($sourcePath in @(Get-BaselineTestSourcePathSet -Path $filePath)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'UWPApps protected package guard' {
    It 'treats Windows Security packages as protected' {
        Test-UWPAppsProtectedPackage -PackageName 'Microsoft.SecHealthUI_1000.26100.1.0_x64__8wekyb3d8bbwe' | Should -BeTrue
        Test-UWPAppsProtectedPackage -PackageName 'Microsoft.Windows.SecHealthUI_cw5n1h2txyewy' | Should -BeTrue
        Test-UWPAppsProtectedPackage -PackageName 'Microsoft.WindowsCalculator_11.0.0.0_x64__8wekyb3d8bbwe' | Should -BeFalse
    }

    It 'excludes and skips protected Windows Security packages before removal' {
        $script:UWPAppsContent | Should -Match '"Microsoft\.SecHealthUI"'
        $script:UWPAppsContent | Should -Match '"Microsoft\.Windows\.SecHealthUI"'
        $script:UWPAppsContent | Should -Match 'Test-UWPAppsProtectedPackage -PackageName \$_.Name'
        $script:UWPAppsContent | Should -Match 'Test-UWPAppsProtectedPackage -PackageName \$Package'
        $script:UWPAppsContent | Should -Match 'Skipped protected Windows Security package'
    }
}

Describe 'UWPApps GUI selection cancellation' {
    It 'returns no confirmed packages when the bulk picker closes without a selection' {
        @(Get-UWPAppsConfirmedSelectionPackages -SelectionResult $null).Count | Should -Be 0
        @(Get-UWPAppsConfirmedSelectionPackages -SelectionResult ([pscustomobject]@{ SelectedPackages = @() })).Count | Should -Be 0

        $packages = @(Get-UWPAppsConfirmedSelectionPackages -SelectionResult ([pscustomobject]@{ SelectedPackages = @('  ', 'Microsoft.WindowsCalculator') }))
        $packages.Count | Should -Be 1
        $packages[0] | Should -Be 'Microsoft.WindowsCalculator'
    }

    It 'short-circuits GUI install and uninstall before execution when no packages are confirmed' {
        $installMessageIndex = $script:UWPAppsContent.IndexOf('Skipping UWP app install because the package picker was closed without a confirmed selection.')
        $installPickerIndex = $script:UWPAppsContent.IndexOf('# Show the app picker and install the packages the user selects.')
        $uninstallMessageIndex = $script:UWPAppsContent.IndexOf('Skipping UWP app uninstall because the package picker was closed without a confirmed selection.')
        $uninstallPickerIndex = $script:UWPAppsContent.IndexOf('# Show the app picker and remove the packages the user selects.')

        $installMessageIndex | Should -BeGreaterThan -1
        $installMessageIndex | Should -BeLessThan $installPickerIndex
        $uninstallMessageIndex | Should -BeGreaterThan -1
        $uninstallMessageIndex | Should -BeLessThan $uninstallPickerIndex
    }
}

Describe 'AIRemoval scrollbars' {
    It 'uses subtle line-scroll chevrons in the custom scroll viewer template' {
        $script:AIRemovalContent | Should -Match 'AiScrollBarArrowButtonStyle'
        $script:AIRemovalContent | Should -Match 'Command="ScrollBar\.LineUpCommand"'
        $script:AIRemovalContent | Should -Match 'Command="ScrollBar\.LineDownCommand"'
        $script:AIRemovalContent | Should -Match 'Command="ScrollBar\.PageUpCommand"'
        $script:AIRemovalContent | Should -Match 'Command="ScrollBar\.PageDownCommand"'
        $script:AIRemovalContent | Should -Match '<RowDefinition Height="16"/>'
        $script:AIRemovalContent | Should -Match 'Opacity" Value="0\.14"'
    }

    It 'returns after elevated relaunch instead of issuing a host exit' {
        $script:AIRemovalContent | Should -Match 'Start-Process -FilePath ''powershell\.exe'' -ArgumentList \$arguments -Verb RunAs\r?\n\s*return\b'
        $script:AIRemovalContent | Should -Not -Match 'Start-Process -FilePath ''powershell\.exe'' -ArgumentList \$arguments -Verb RunAs\r?\n\s*Exit\b'
    }
}

Describe 'AIRemoval privileged operation safeguards' {
    It 'requires TrustedInstaller completion markers and hard-fails restore failures' {
        $script:AIRemovalContent | Should -Match '\$trustedMarkerPath'
        $script:AIRemovalContent | Should -Match '\$trustedErrorPath'
        $script:AIRemovalContent | Should -Match 'TrustedInstaller AIRemoval command did not report completion'
        $script:AIRemovalContent | Should -Match 'TrustedInstaller AIRemoval command returned exit code'
        $script:AIRemovalContent | Should -Match "-ArgumentList @\('start', 'TrustedInstaller'\).*?-AllowedExitCodes @\(0, 1053\)"
        $script:AIRemovalContent | Should -Match '\$restoreFailure = \$_'
        $script:AIRemovalContent | Should -Match 'Failed to restore the TrustedInstaller service command after AIRemoval privileged cleanup'
    }

    It 'logs skip-on-access-denied registry writes as informational' {
        $script:AIRemovalContent | Should -Match 'LogInfo "Skipping registry value ''\$DeniedName'' at ''\$DeniedPath'' because access was denied\."'
        $script:AIRemovalContent | Should -Not -Match 'LogWarning "Skipping registry value ''\$DeniedName'' at ''\$DeniedPath'' because access was denied\."'
    }

    It 'verifies Voice Access removal before reporting success' {
        $postconditionIndex = $script:AIRemovalContent.IndexOf('Voice Access removal did not meet postconditions.')
        $failedIndex = $script:AIRemovalContent.IndexOf('Write-ConsoleStatus -Status failed', $postconditionIndex)
        $successIndex = $script:AIRemovalContent.IndexOf('Write-ConsoleStatus -Status success', $postconditionIndex)

        $postconditionIndex | Should -BeGreaterThan -1
        $failedIndex | Should -BeGreaterThan $postconditionIndex
        $successIndex | Should -BeGreaterThan $failedIndex
    }

    It 'verifies Recall and Office AI scheduled tasks before reporting success' {
        $postconditionIndex = $script:AIRemovalContent.IndexOf('Recall or Office AI scheduled tasks remained enabled after removal.')
        $failedIndex = $script:AIRemovalContent.IndexOf('Write-ConsoleStatus -Status failed', $postconditionIndex)
        $successIndex = $script:AIRemovalContent.IndexOf('Write-ConsoleStatus -Status success', $postconditionIndex)

        $script:AIRemovalContent | Should -Match '\$remainingEnabledTasks = @\('
        $postconditionIndex | Should -BeGreaterThan -1
        $failedIndex | Should -BeGreaterThan $postconditionIndex
        $successIndex | Should -BeGreaterThan $failedIndex
    }
}

Describe 'BackgroundApps' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'requires Enable or Disable (parameter set validation)' {
        { BackgroundApps } | Should -Throw
    }

    It 'writes GlobalUserDisabled=0 when enabling' {
        BackgroundApps -Enable

        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Path | Should -Match 'BackgroundAccessApplications$'
        $script:setItemPropertyCalls[0].Name | Should -Be 'GlobalUserDisabled'
        $script:setItemPropertyCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes GlobalUserDisabled=1 when disabling' {
        BackgroundApps -Disable

        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failure when Set-ItemProperty throws' {
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            throw 'registry error'
        }

        BackgroundApps -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'registry error'
    }
}

Describe 'CortanaAutostart' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:cortanaInstalled = $true
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-AppxPackage {
            param([string]$Name, [object]$WarningAction)
            if ($script:cortanaInstalled) { return [pscustomobject]@{ Name = $Name } }
            return $null
        }
        function Get-TweakSkipLabel { param($Invocation) return 'CortanaAutostart' }
        function Test-Path {
            param([string]$Path)
            return $true
        }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-AppxPackage -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'skips when Cortana is not installed' {
        $script:cortanaInstalled = $false

        CortanaAutostart -Enable

        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Skipped'
        $script:newItemPropertyCalls.Count | Should -Be 0
    }

    It 'writes State=2 when Cortana is installed and enabling' {
        $script:cortanaInstalled = $true

        CortanaAutostart -Enable

        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'State'
        $script:newItemPropertyCalls[0].Value | Should -Be 2
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes State=1 when Cortana is installed and disabling' {
        $script:cortanaInstalled = $true

        CortanaAutostart -Disable

        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'State'
        $script:newItemPropertyCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'EdgeDebloat' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $false }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'requires Enable or Disable' {
        { EdgeDebloat } | Should -Throw
    }

    It 'creates policy keys and sets values when enabling' {
        EdgeDebloat -Enable

        # 3 keys created because Test-Path returns false for all
        $script:newItemCalls.Count | Should -Be 3
        $script:setItemPropertyCalls.Count | Should -BeGreaterThan 10
        $names = @($script:setItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'PersonalizationReportingEnabled'
        $names | Should -Contain 'EdgeShoppingAssistantEnabled'
        $names | Should -Contain 'DiagnosticData'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'blocks the Copilot sidebar extension via blocklist entry' {
        EdgeDebloat -Enable

        $blocklist = @($script:setItemPropertyCalls | Where-Object { $_.Path -match 'ExtensionInstallBlocklist' })
        $blocklist.Count | Should -BeGreaterThan 0
        $blocklist[0].Name | Should -Be '1'
        $blocklist[0].Value | Should -Be 'ofefcgjbeghpigppfmkologfjadafddi'
    }

    It 'removes policy values when disabling' {
        EdgeDebloat -Disable

        $script:removeItemPropertyCalls.Count | Should -BeGreaterThan 10
        $names = @($script:removeItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'PersonalizationReportingEnabled'
        $names | Should -Contain 'EdgeShoppingAssistantEnabled'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'NewOutlook' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Remove-RegistryValueSafe {
            param([string[]]$Path, [string[]]$Name)
            foreach ($singlePath in @($Path)) {
                foreach ($singleName in @($Name)) {
                    [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $singlePath; Name = $singleName })
                }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'enables New Outlook by writing UseNewOutlook=1' {
        NewOutlook -Enable

        $useNew = @($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'UseNewOutlook' })
        $useNew.Count | Should -Be 1
        $useNew[0].Value | Should -Be 1

        $hide = @($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'HideNewOutlookToggle' })
        $hide[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'disables New Outlook by writing UseNewOutlook=0 and hides the toggle' {
        NewOutlook -Disable

        $useNew = @($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'UseNewOutlook' })
        $useNew[0].Value | Should -Be 0

        $hide = @($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'HideNewOutlookToggle' })
        $hide[0].Value | Should -Be 1

        $script:removeItemPropertyCalls.Count | Should -Be 1
        $script:removeItemPropertyCalls[0].Name | Should -Be 'NewOutlookMigrationUserSetting'
    }
}

Describe 'Notifications' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:policyKeyExists = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path {
            param([string]$Path)
            return $script:policyKeyExists
        }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Remove-RegistryValueSafe {
            param([string[]]$Path, [string[]]$Name)
            foreach ($singlePath in @($Path)) {
                foreach ($singleName in @($Name)) {
                    [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $singlePath; Name = $singleName })
                }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'enables notifications by removing policy and setting ToastEnabled=1' {
        Notifications -Enable

        $script:removeItemPropertyCalls.Count | Should -Be 1
        $script:removeItemPropertyCalls[0].Name | Should -Be 'DisableNotificationCenter'
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Name | Should -Be 'ToastEnabled'
        $script:setItemPropertyCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'disables notifications by writing policy values and ToastEnabled=0' {
        $script:policyKeyExists = $true

        Notifications -Disable

        $script:newItemCalls.Count | Should -Be 0
        $script:setItemPropertyCalls.Count | Should -Be 2
        $names = @($script:setItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'DisableNotificationCenter'
        $names | Should -Contain 'ToastEnabled'
        $toast = @($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'ToastEnabled' })
        $toast[0].Value | Should -Be 0
    }

    It 'creates the Explorer policy key when disabling on a system that lacks it' {
        $script:policyKeyExists = $false

        Notifications -Disable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Match 'Policies\\Microsoft\\Windows\\Explorer$'
    }
}

Describe 'Copilot' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:isServer = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-OSInfo { return [pscustomobject]@{ IsWindowsServer = $script:isServer } }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-OSInfo -ErrorAction SilentlyContinue
    }

    It 'skips Install on Windows Server with warning status' {
        $script:isServer = $true

        Copilot -Install

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Windows Server'
    }

    It 'skips Uninstall on Windows Server with warning status' {
        $script:isServer = $true

        Copilot -Uninstall

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Windows Server'
    }

    It 'is available on Windows 10 and Windows 11 client manifests' {
        $script:CopilotManifestEntry | Should -Not -BeNullOrEmpty
        $script:CopilotManifestEntry.PlatformSupport.Windows10 | Should -BeTrue
        $script:CopilotManifestEntry.PlatformSupport.Windows11 | Should -BeTrue
        $script:CopilotManifestEntry.PlatformSupport.Server | Should -BeFalse
        $script:CopilotManifestEntry.PlatformSupport.PSObject.Properties['MinBuild'] | Should -BeNullOrEmpty
    }

    It 'declares enough GUI execution time for privileged AI component cleanup' {
        $script:CopilotManifestEntry | Should -Not -BeNullOrEmpty
        [int]$script:CopilotManifestEntry.TimeoutSeconds | Should -BeGreaterOrEqual 900
    }
}

Describe 'RevertStartMenu' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:supportReturn = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Test-Windows11FeatureBranchSupport { param([object[]]$Thresholds) return $script:supportReturn }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Windows11FeatureBranchSupport -ErrorAction SilentlyContinue
    }

    It 'short-circuits with a warning when the build is not supported (Enable)' {
        $script:supportReturn = $false

        RevertStartMenu -Enable

        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'only supported'
    }

    It 'short-circuits with a warning when the build is not supported (Disable)' {
        $script:supportReturn = $false

        RevertStartMenu -Disable

        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'only supported'
    }
}
