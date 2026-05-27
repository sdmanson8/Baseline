Set-StrictMode -Version Latest

BeforeAll {
    function Get-FunctionAst {
        param(
            [string]$Path,
            [string]$Name
        )

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "../../$Path"), [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw $errors[0].Message
        }

        return $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $Name
            }, $true)
    }
}

Describe 'Completed privacy telemetry safe-registry cleanup' {
    It 'clears FeedbackFrequency user values through Remove-RegistryValueSafe' {
        $fn = Get-FunctionAst -Path 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.PrivacySettings.psm1' -Name 'FeedbackFrequency'
        $safeRemovals = @($fn.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Remove-RegistryValueSafe'
                }, $true))

        foreach ($name in @('PeriodInNanoSeconds', 'NumberOfSIUFInPeriod')) {
            @($safeRemovals | Where-Object {
                    $_.Extent.Text -like '*HKCU:\Software\Microsoft\Siuf\Rules*' -and
                    $_.Extent.Text -like "*$name*"
                }).Count | Should -BeGreaterOrEqual 1
        }
    }

    It 'does not directly remove completed HKCU privacy telemetry values' {
        $checks = @(
            @{ Path = 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.PrivacySettings.psm1'; Function = 'FeedbackFrequency'; Pattern = 'HKCU:\Software\Microsoft\Siuf\Rules' },
            @{ Path = 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.SystemSettings.psm1'; Function = 'TailoredExperiences'; Pattern = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' },
            @{ Path = 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1'; Function = 'ErrorReporting'; Pattern = 'HKCU:\Software\Policies\Microsoft\Windows\Windows Error Reporting' }
        )

        foreach ($check in $checks) {
            $fn = Get-FunctionAst -Path $check.Path -Name $check.Function
            $directRemovals = @($fn.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'Remove-ItemProperty' -and
                        $node.Extent.Text -like "*$($check.Pattern)*"
                    }, $true))

            $directRemovals.Count | Should -Be 0
        }
    }
}
