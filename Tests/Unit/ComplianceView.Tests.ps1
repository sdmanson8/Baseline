Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $compliancePath = Join-Path $PSScriptRoot '../../Module/GUI/ComplianceView.ps1'
    $complianceHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Compliance.Helpers.ps1'
    $script:ComplianceContent = Get-BaselineTestSourceText -Path $compliancePath
    $script:ComplianceHelpersContent = Get-BaselineTestSourceText -Path $complianceHelpersPath
}

Describe 'Compliance view remote targeting' {
    It 'checks the connected remote target before running compliance locally' {
        $script:ComplianceContent | Should -Match 'Get-GuiRemoteTargetContext'
        $script:ComplianceContent | Should -Match 'Invoke-BaselineRemoteCompliance'
        $script:ComplianceContent | Should -Match 'Remote compliance: Compliant targets'
    }

    It 'routes compliance dialog setup and remote-context lookup failures through Write-SwallowedException' {
        $script:ComplianceContent | Should -Match "ComplianceView\.ShowComplianceDialog\.SetOwner"
        $script:ComplianceContent | Should -Match "ComplianceView\.ShowComplianceDialog\.DispatcherYield"
        $script:ComplianceContent | Should -Match "ComplianceView\.ShowComplianceDialog\.GetRemoteTargetContext"
    }

    It 'routes compliance dispatcher yields through Write-SwallowedException' {
        $script:ComplianceHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ComplianceHelpers\.Test-SystemCompliance\.DispatcherYield'''
    }
}
