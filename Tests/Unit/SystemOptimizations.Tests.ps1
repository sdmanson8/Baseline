Set-StrictMode -Version Latest

Describe 'SystemOptimizations module' {
    It 'exports Invoke-SystemOptimizations' {
        $modulePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemOptimizations.psm1'
        $module = Import-Module $modulePath -Force -PassThru -ErrorAction Stop

        try {
            $command = Get-Command -Module $module.Name -Name 'Invoke-SystemOptimizations' -ErrorAction Stop

            $command.Name | Should -Be 'Invoke-SystemOptimizations'
        }
        finally {
            Remove-Module $module.Name -Force -ErrorAction SilentlyContinue
        }
    }
}
