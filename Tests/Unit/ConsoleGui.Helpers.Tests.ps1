Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Manifest.Helpers.ps1')
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Preset.Helpers.ps1')
    . (Join-Path $PSScriptRoot '../../Bootstrap/Helpers/Bootstrap.Helpers.ps1')
}

Describe 'Console GUI helper catalog' {
    BeforeEach {
        $script:Manifest = @(
            [ordered]@{
                Name     = 'CAB Install Context Menu'
                Function = 'CABInstallContext'
                Category = 'Context Menu'
                Type     = 'Toggle'
                Default  = $true
                OnParam  = 'Show'
                OffParam = 'Hide'
                Risk     = 'Low'
            },
            [ordered]@{
                Name     = 'Diagnostic Data Level'
                Function = 'DiagnosticDataLevel'
                Category = 'Privacy & Telemetry'
                Type     = 'Choice'
                Default  = 'Minimal'
                Options  = @('Security', 'Minimal', 'Required')
                Risk     = 'Medium'
            },
            [ordered]@{
                Name     = 'Windows Tips'
                Function = 'WindowsTips'
                Category = 'Privacy & Telemetry'
                Type     = 'Toggle'
                Default  = $false
                OnParam  = 'Enable'
                OffParam = 'Disable'
                Risk     = 'Low'
            }
        )
    }

    It 'uses exact preset command lines for preselected manifest items' {
        $catalog = New-BaselineConsoleGuiCatalog -Manifest $script:Manifest -PreselectedCommands @('CABInstallContext -Hide')

        $cab = $catalog.Items | Where-Object { $_.Function -eq 'CABInstallContext' } | Select-Object -First 1
        $cab.Selected | Should -BeTrue
        $cab.CommandLine | Should -Be 'CABInstallContext -Hide'
    }

    It 'uses manifest default commands for newly selected items' {
        $catalog = New-BaselineConsoleGuiCatalog -Manifest $script:Manifest

        $choice = $catalog.Items | Where-Object { $_.Function -eq 'DiagnosticDataLevel' } | Select-Object -First 1
        $toggle = $catalog.Items | Where-Object { $_.Function -eq 'WindowsTips' } | Select-Object -First 1

        $choice.Selected | Should -BeFalse
        $choice.CommandLine | Should -Be 'DiagnosticDataLevel -Minimal'
        $toggle.CommandLine | Should -Be 'WindowsTips -Disable'
    }

    It 'selects all items in a category and returns commands in manifest order' {
        $catalog = New-BaselineConsoleGuiCatalog -Manifest $script:Manifest -PreselectedCommands @('CABInstallContext -Hide')

        Set-BaselineConsoleGuiCategorySelection -Catalog $catalog -Category 'Privacy & Telemetry' -Selected $true
        $commands = @(Get-BaselineConsoleGuiSelectedCommands -Catalog $catalog)

        $commands | Should -Be @(
            'CABInstallContext -Hide'
            'DiagnosticDataLevel -Minimal'
            'WindowsTips -Disable'
        )
    }

    It 'builds collapsible category rows with selection counts' {
        $catalog = New-BaselineConsoleGuiCatalog -Manifest $script:Manifest -PreselectedCommands @('CABInstallContext -Hide')
        $catalog.Expanded['Privacy & Telemetry'] = $false

        $rows = @(Get-BaselineConsoleGuiRowList -Catalog $catalog)
        $privacy = $rows | Where-Object { $_.Kind -eq 'Category' -and $_.Category -eq 'Privacy & Telemetry' } | Select-Object -First 1
        $privacyItems = @($rows | Where-Object { $_.Kind -eq 'Item' -and $_.Category -eq 'Privacy & Telemetry' })

        $privacy.Expanded | Should -BeFalse
        $privacy.Selected | Should -Be 0
        $privacy.Total | Should -Be 2
        $privacyItems.Count | Should -Be 0
    }
}

Describe 'PowerShell Remoting session detection' {
    It 'returns true when remoting sender info is present' {
        Test-BaselinePowerShellRemotingSession -SenderInfo ([pscustomobject]@{ UserInfo = 'operator' }) | Should -BeTrue
    }

    It 'returns false when remoting sender info is absent' {
        Test-BaselinePowerShellRemotingSession -SenderInfo $null | Should -BeFalse
    }
}
