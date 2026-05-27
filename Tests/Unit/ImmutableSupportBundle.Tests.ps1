Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    <#
        .SYNOPSIS
    #>

    function Get-BaselineDisplayVersion { return '1.0.0' }

    # Json helpers must load first - SupportBundle/RemoteTarget call ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    $auditHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/AuditTrail.Helpers.ps1'
    $bundleHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SupportBundle.Helpers.ps1'
    $remoteHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RemoteTarget.Helpers.ps1'
    $environmentHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $script:SharedHelpersRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:SharedHelpersModuleRoot = Join-Path $script:SharedHelpersRepoRoot 'Module'

    foreach ($filePath in @($remoteHelpersPath, $environmentHelpersPath, $bundleHelpersPath)) {
    }

    foreach ($filePath in @($auditHelpersPath, $remoteHelpersPath, $environmentHelpersPath, $bundleHelpersPath)) {
        $sourceText = Get-BaselineTestSourceText -Path $filePath
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:ImmutableSupportBundleProcessCaptureStub = {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [int]$TimeoutSeconds
        )

        $scriptText = if ($ArgumentList -contains '-File') { Get-Content -LiteralPath ([string]$ArgumentList[-1]) -Raw -Encoding UTF8 } else { [string]$ArgumentList[-1] }
        if ($scriptText -match 'Get-MpComputerStatus') {
            return [pscustomobject]@{
                ExitCode       = 0
                StandardOutput = '{"AMServiceEnabled":true,"AntivirusEnabled":true,"RealTimeProtectionEnabled":true,"IoavProtectionEnabled":true,"NISEnabled":true,"AntispywareEnabled":true}'
                StandardError  = ''
            }
        }

        if ($scriptText -match 'Get-WindowsOptionalFeature -Online') {
            return [pscustomobject]@{
                ExitCode       = 0
                StandardOutput = '[{"Name":"NetFx3","State":"Enabled"},{"Name":"SMB1Protocol","State":"Disabled"}]'
                StandardError  = ''
            }
        }

        return [pscustomobject]@{
            ExitCode       = 0
            StandardOutput = ''
            StandardError  = ''
        }
    }
    Set-Item -Path Function:\Invoke-BaselineSupportBundleProcessCapture -Value $script:ImmutableSupportBundleProcessCaptureStub
    Set-Item -Path Function:\Global:Invoke-BaselineSupportBundleProcessCapture -Value $script:ImmutableSupportBundleProcessCaptureStub

    $script:TempRoot = Join-Path $env:TEMP ('BaselineImmutableBundleTests_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
}

AfterAll {
    if ($null -ne $script:OriginalLocalAppData) {
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }
    if (Test-Path -LiteralPath $script:TempRoot) {
        # Remove read-only attributes before cleanup
        Get-ChildItem -LiteralPath $script:TempRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Export-BaselineSupportBundle -Immutable' {
    BeforeEach {
        $script:TestBundlePath = Join-Path $script:TempRoot ('immutable-bundle-{0}.zip' -f [guid]::NewGuid().ToString('N'))
        $script:HistoryRoot = Join-Path $script:TempRoot ('LocalAppData-{0}' -f [guid]::NewGuid().ToString('N'))
        $script:HistoryDir = Join-Path $script:HistoryRoot 'Baseline'
        New-Item -ItemType Directory -Path $script:HistoryDir -Force | Out-Null

        # Create minimal audit log
        $auditLogPath = Join-Path $script:HistoryDir 'audit.jsonl'
        @(
            ('{"Timestamp":"' + ([datetime]::UtcNow).AddDays(-10).ToString('o') + '","Action":"Run","Mode":"Run"}')
            ('{"Timestamp":"' + ([datetime]::UtcNow).AddHours(-1).ToString('o') + '","Action":"Compliance","Mode":"Compliance"}')
        ) | Set-Content -LiteralPath $auditLogPath -Encoding UTF8
    }

    AfterEach {
        # Clean up read-only files
        if (Test-Path -LiteralPath $script:TestBundlePath) {
            $item = Get-Item -LiteralPath $script:TestBundlePath -ErrorAction SilentlyContinue
            if ($item) { $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) }
            Remove-Item -LiteralPath $script:TestBundlePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates immutable bundle with integrity manifest' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            $result = Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -IncludeTestReport:$false
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result.Immutable | Should -BeTrue
        $result.IntegrityManifest | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $result.OutputPath | Should -BeTrue
    }

    It 'includes provenance information in immutable bundle' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            $result = Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -SignoffReason 'Production deployment signoff' -IncludeTestReport:$false
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result.IntegrityManifest.Provenance | Should -Not -BeNullOrEmpty
        $result.IntegrityManifest.Provenance.Reason | Should -Be 'Production deployment signoff'
        $result.IntegrityManifest.Provenance.SignedBy | Should -Be $env:USERNAME
        $result.IntegrityManifest.Provenance.SignedOn | Should -Be $env:COMPUTERNAME
    }

    It 'generates SHA256 checksums for all files' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            $result = Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -IncludeTestReport:$false
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result.IntegrityManifest.Files | Should -Not -BeNullOrEmpty
        $result.IntegrityManifest.Files.Count | Should -BeGreaterThan 0
        foreach ($file in $result.IntegrityManifest.Files) {
            $file.SHA256 | Should -Match '^[A-F0-9]{64}$'
        }
    }

    It 'sets read-only attribute on immutable bundle' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            $result = Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -IncludeTestReport:$false
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $zipItem = Get-Item -LiteralPath $result.OutputPath
        ($zipItem.Attributes -band [System.IO.FileAttributes]::ReadOnly) | Should -Not -Be 0
    }

    It 'metadata includes immutable and signoff flags' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            $result = Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -IncludeTestReport:$false
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $extractDir = Join-Path $script:TempRoot ('extract-{0}' -f [guid]::NewGuid().ToString('N'))
        $zipItem = Get-Item -LiteralPath $result.OutputPath
        $zipItem.Attributes = $zipItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $metadataPath = Join-Path $extractDir 'metadata.json'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json

        $metadata.Immutable | Should -BeTrue
        $metadata.SignoffBundle | Should -BeTrue
        $metadata.SignoffProvenance | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-BaselineSupportBundleIntegrity' {
    BeforeEach {
        $script:TestBundlePath = Join-Path $script:TempRoot ('verify-bundle-{0}.zip' -f [guid]::NewGuid().ToString('N'))
        $script:HistoryRoot = Join-Path $script:TempRoot ('LocalAppData-{0}' -f [guid]::NewGuid().ToString('N'))
        $script:HistoryDir = Join-Path $script:HistoryRoot 'Baseline'
        New-Item -ItemType Directory -Path $script:HistoryDir -Force | Out-Null

        $auditLogPath = Join-Path $script:HistoryDir 'audit.jsonl'
        @(
            ('{"Timestamp":"' + ([datetime]::UtcNow).AddHours(-1).ToString('o') + '","Action":"Test","Mode":"Run"}')
        ) | Set-Content -LiteralPath $auditLogPath -Encoding UTF8
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TestBundlePath) {
            $item = Get-Item -LiteralPath $script:TestBundlePath -ErrorAction SilentlyContinue
            if ($item) { $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) }
            Remove-Item -LiteralPath $script:TestBundlePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'verifies valid immutable bundle successfully' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -IncludeTestReport:$false | Out-Null
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        # Remove read-only for verification tool to read
        $zipItem = Get-Item -LiteralPath $script:TestBundlePath
        $zipItem.Attributes = $zipItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

        $result = Test-BaselineSupportBundleIntegrity -BundlePath $script:TestBundlePath
        $result.Valid | Should -BeTrue
        $result.Immutable | Should -BeTrue
        $result.FilesFailed | Should -Be 0
    }

    It 'returns $null Valid for non-immutable bundles' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -IncludeTestReport:$false | Out-Null
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result = Test-BaselineSupportBundleIntegrity -BundlePath $script:TestBundlePath
        $result.Immutable | Should -BeFalse
        $result.Valid | Should -BeNullOrEmpty
    }

    It 'includes provenance information from manifest' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -SignoffReason 'QA verification' -IncludeTestReport:$false | Out-Null
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $zipItem = Get-Item -LiteralPath $script:TestBundlePath
        $zipItem.Attributes = $zipItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

        $result = Test-BaselineSupportBundleIntegrity -BundlePath $script:TestBundlePath
        $result.Provenance | Should -Not -BeNullOrEmpty
        $result.Provenance.Reason | Should -Be 'QA verification'
    }

    It 'reports verification timestamp' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:HistoryRoot
        try {
            Export-BaselineSupportBundle -OutputPath $script:TestBundlePath -Immutable -IncludeTestReport:$false | Out-Null
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $zipItem = Get-Item -LiteralPath $script:TestBundlePath
        $zipItem.Attributes = $zipItem.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

        $result = Test-BaselineSupportBundleIntegrity -BundlePath $script:TestBundlePath
        $result.VerifiedAt | Should -Not -BeNullOrEmpty
        { [datetime]::Parse($result.VerifiedAt) } | Should -Not -Throw
    }
}
