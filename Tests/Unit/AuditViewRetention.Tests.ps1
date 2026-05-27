Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:AuditViewPath = Join-Path $PSScriptRoot '../../Module/GUI/AuditView.ps1'
    $script:AuditViewContent = Get-BaselineTestSourceText -Path $script:AuditViewPath
}

Describe 'Audit view retention controls' {
    It 'exposes a retention selector and uses it for export and cleanup' {
        $script:AuditViewContent | Should -Match 'Retention:'
        $script:AuditViewContent | Should -Match '30 days'
        $script:AuditViewContent | Should -Match '90 days'
        $script:AuditViewContent | Should -Match '180 days'
        $script:AuditViewContent | Should -Match '365 days'
        $script:AuditViewContent | Should -Match 'Get-AuditLog -Since'
        $script:AuditViewContent | Should -Match 'Export-AuditReport -OutputPath \$outputPath -Format \$format -Since \$retentionSince'
        $script:AuditViewContent | Should -Match 'Clear-AuditLog -OlderThan \$cutoff'
        $script:AuditViewContent | Should -Match 'Entries older than \{0\} days have been removed'
        $script:AuditViewContent | Should -Match "AuditView\.ShowAuditLogDialog\.SetOwner"
    }
}
