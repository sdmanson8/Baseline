Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:SystemMiscPath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.SystemMisc.psm1'
    $script:SystemMiscContent = Get-BaselineTestSourceText -Path $script:SystemMiscPath
}

Describe 'System miscellaneous cleanup' {
    It 'routes reserved storage cleanup failures through LogWarning' {
        $script:SystemMiscContent | Should -Match 'Reserved storage cleanup \(disable\) PowerShell dispose failed:'
        $script:SystemMiscContent | Should -Match 'Reserved storage cleanup \(enable\) PowerShell dispose failed:'
        $script:SystemMiscContent | Should -Match 'Reserved storage cleanup \(\{0\}\) runspace dispose failed:'
        $script:SystemMiscContent | Should -Match 'Close-ReservedStorageRunspace -Runspace \$storageRs -Completed:\$storageCompleted -Source ''disable'''
        $script:SystemMiscContent | Should -Match 'Close-ReservedStorageRunspace -Runspace \$storageRs -Completed:\$storageCompleted -Source ''enable'''
    }

    It 'uses asynchronous stop and runspace close on reserved storage timeout' {
        $script:SystemMiscContent | Should -Match 'function Stop-ReservedStorageWorkerAsync'
        $script:SystemMiscContent | Should -Match '\$PowerShell\.BeginStop\(\$null, \$null\)'
        $script:SystemMiscContent | Should -Match '\$Runspace\.CloseAsync\(\)'
        $script:SystemMiscContent | Should -Not -Match '\$storagePs\.Stop\(\)'
    }
}
