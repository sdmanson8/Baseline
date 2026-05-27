Set-StrictMode -Version Latest

BeforeAll {
    $script:filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.Updates.psm1'
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:filePath, [ref]$null, [ref]$null)
    $script:recommendedTroubleshooting = $script:ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'RecommendedTroubleshooting'
        }, $true)
    $script:windowsUpdate = $script:ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'WindowsUpdate'
        }, $true)
}

Describe 'RecommendedTroubleshooting safe-registry cleanup' {
    It 'clears HKCU telemetry and error-reporting values through Remove-RegistryValueSafe' {
        $safeRemovals = @($script:recommendedTroubleshooting.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Remove-RegistryValueSafe'
                }, $true))

        foreach ($target in @(
                @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'; Name = 'ShowedToastAtLevel' },
                @{ Path = 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled' }
            )) {
            @($safeRemovals | Where-Object {
                    $_.Extent.Text -like "*$($target.Path)*" -and
                    $_.Extent.Text -like "*$($target.Name)*"
                }).Count | Should -Be 1
        }
    }

    It 'does not directly clear the migrated HKCU values' {
        $directRemovals = @($script:recommendedTroubleshooting.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Remove-ItemProperty' -and
                    ($node.Extent.Text -like '*HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack*' -or
                        $node.Extent.Text -like '*HKCU:\Software\Microsoft\Windows\Windows Error Reporting*')
                }, $true))

        $directRemovals.Count | Should -Be 0
    }
}

Describe 'WindowsUpdate repair safe-registry cleanup' {
    It 'does not directly remove broad policy hives in the standard repair path' {
        $forbiddenDirectRemovals = @($script:windowsUpdate.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Remove-Item' -and
                    (
                        $node.Extent.Text -like "*HKCU:\Software\Policies*" -or
                        $node.Extent.Text -like "*HKLM:\Software\Policies*" -or
                        $node.Extent.Text -like "*HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies*" -or
                        $node.Extent.Text -like "*HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies*"
                    )
                }, $true))

        $forbiddenDirectRemovals.Count | Should -Be 0
    }

    It 'requires explicit ResetAllPolicies confirmation and registry export before broad policy reset' {
        $functionText = $script:windowsUpdate.Extent.Text

        $functionText | Should -Match '\[switch\]\s*\$ResetAllPolicies'
        $functionText | Should -Match 'if\s*\(\$ResetAllPolicies\)'
        $functionText | Should -Match 'Export-WindowsUpdateRepairRegistryKey'
        $functionText | Should -Match 'explicit ResetAllPolicies aggressive repair'
    }

    It 'routes repair service, cache, registry value, and BITS operations through checked helpers' {
        $functionText = $script:windowsUpdate.Extent.Text

        $functionText | Should -Match 'Stop-WindowsUpdateRepairServiceIfPresent'
        $functionText | Should -Match 'Remove-WindowsUpdateRepairItemIfPresent'
        $functionText | Should -Match 'Rename-WindowsUpdateRepairItemIfPresent'
        $functionText | Should -Match 'Remove-WindowsUpdateRepairRegistryValueIfPresent'
        $functionText | Should -Match 'Remove-WindowsUpdateRepairBitsTransfersIfPresent'
        $functionText | Should -Match 'Set-WindowsUpdateRepairServiceStartupIfPresent'
        $functionText | Should -Match 'Start-WindowsUpdateRepairServiceIfPresent'
        $functionText | Should -Not -Match 'Stop-Service.*SilentlyContinue'
        $functionText | Should -Not -Match 'Start-Service.*SilentlyContinue'
        $functionText | Should -Not -Match 'Set-Service.*SilentlyContinue'
        $functionText | Should -Not -Match 'Remove-BitsTransfer.*SilentlyContinue'
    }
}
