Set-StrictMode -Version Latest

BeforeAll {
    $helpersDir = Join-Path $PSScriptRoot '../../Module/SharedHelpers'
    . (Join-Path $helpersDir 'Json.Helpers.ps1')
    . (Join-Path $helpersDir 'Integrity.Helpers.ps1')
}

Describe 'Integrity helper — manifest generation' {
    BeforeEach {
        $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-integrity-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null

        $script:scriptA = Join-Path $script:fixtureRoot 'a.psm1'
        $script:scriptB = Join-Path $script:fixtureRoot 'sub/b.ps1'
        $script:dataC   = Join-Path $script:fixtureRoot 'data.json'

        New-Item -ItemType Directory -Path (Split-Path $script:scriptB) -Force | Out-Null
        Set-Content -LiteralPath $script:scriptA -Value 'function A { 1 }' -Encoding UTF8 -NoNewline
        Set-Content -LiteralPath $script:scriptB -Value 'function B { 2 }' -Encoding UTF8 -NoNewline
        Set-Content -LiteralPath $script:dataC   -Value '{}'              -Encoding UTF8 -NoNewline
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:fixtureRoot) {
            Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force
        }
    }

    It 'covers script files (psm1/psd1/ps1) and ignores data files' {
        $covered = Get-BaselineIntegrityCoveredFiles -ModuleRoot $script:fixtureRoot
        $covered | Should -HaveCount 2
        ($covered -join ';') | Should -Match 'a\.psm1'
        ($covered -join ';') | Should -Match 'b\.ps1'
        ($covered -join ';') | Should -Not -Match 'data\.json'
    }

    It 'produces a manifest with sha256 hashes keyed by forward-slash relative paths' {
        $manifest = New-BaselineIntegrityManifest -ModuleRoot $script:fixtureRoot
        $manifest.algorithm | Should -Be 'sha256'
        $manifest.fileCount | Should -Be 2
        $manifest.files['a.psm1']     | Should -Match '^[0-9a-f]{64}$'
        $manifest.files['sub/b.ps1']  | Should -Match '^[0-9a-f]{64}$'
    }

    It 'verifies a freshly generated manifest as intact' {
        $manifestPath = Join-Path $script:fixtureRoot 'integrity.manifest.json'
        $manifest = New-BaselineIntegrityManifest -ModuleRoot $script:fixtureRoot
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        Test-BaselineModuleIntegrity -ModuleRoot $script:fixtureRoot -ManifestPath $manifestPath | Should -BeTrue
    }

    It 'treats a UTF-8 BOM on PowerShell text files as runtime-equivalent content' {
        $manifestPath = Join-Path $script:fixtureRoot 'integrity.manifest.json'
        $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
        $utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
        $nonAsciiText = "function A { '$([char]0x017E)' }"

        [System.IO.File]::WriteAllText($script:scriptA, $nonAsciiText, $utf8NoBom)
        $manifest = New-BaselineIntegrityManifest -ModuleRoot $script:fixtureRoot
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        [System.IO.File]::WriteAllText($script:scriptA, $nonAsciiText, $utf8Bom)

        Test-BaselineModuleIntegrity -ModuleRoot $script:fixtureRoot -ManifestPath $manifestPath | Should -BeTrue
    }

    It 'throws when a tracked file is modified after manifest generation' {
        $manifestPath = Join-Path $script:fixtureRoot 'integrity.manifest.json'
        $manifest = New-BaselineIntegrityManifest -ModuleRoot $script:fixtureRoot
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        Set-Content -LiteralPath $script:scriptA -Value 'function A { 999 }' -Encoding UTF8 -NoNewline

        { Test-BaselineModuleIntegrity -ModuleRoot $script:fixtureRoot -ManifestPath $manifestPath } |
            Should -Throw -ErrorId '*' -Because 'a modified script file must be flagged as a tampered manifest entry.'
    }

    It 'throws when a new untracked script file appears after manifest generation' {
        $manifestPath = Join-Path $script:fixtureRoot 'integrity.manifest.json'
        $manifest = New-BaselineIntegrityManifest -ModuleRoot $script:fixtureRoot
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        Set-Content -LiteralPath (Join-Path $script:fixtureRoot 'rogue.ps1') -Value 'function Rogue {}' -Encoding UTF8 -NoNewline

        { Test-BaselineModuleIntegrity -ModuleRoot $script:fixtureRoot -ManifestPath $manifestPath } |
            Should -Throw -Because 'an unexpected script file in the module tree must be flagged.'
    }

    It 'throws FileNotFoundException when the manifest is missing' {
        $manifestPath = Join-Path $script:fixtureRoot 'integrity.manifest.json'
        { Test-BaselineModuleIntegrity -ModuleRoot $script:fixtureRoot -ManifestPath $manifestPath } |
            Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
    }

    It 'validates the checked-in module integrity manifest' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $moduleRoot = Join-Path $repoRoot 'Module'

        Test-BaselineModuleIntegrity -ModuleRoot $moduleRoot | Should -BeTrue
    }
}

Describe 'Integrity helper — mode resolution' {
    AfterEach {
        Remove-Item Env:BASELINE_INTEGRITY_MODE -ErrorAction SilentlyContinue
    }

    It 'defaults to Off when env var is unset' {
        Remove-Item Env:BASELINE_INTEGRITY_MODE -ErrorAction SilentlyContinue
        Get-BaselineIntegrityMode | Should -Be 'Off'
    }

    It 'parses Strict and Audit case-insensitively' {
        $env:BASELINE_INTEGRITY_MODE = 'strict'
        Get-BaselineIntegrityMode | Should -Be 'Strict'
        $env:BASELINE_INTEGRITY_MODE = 'AUDIT'
        Get-BaselineIntegrityMode | Should -Be 'Audit'
    }

    It 'throws for unknown values instead of silently disabling integrity' {
        $env:BASELINE_INTEGRITY_MODE = 'whatever'
        { Get-BaselineIntegrityMode } | Should -Throw '*Invalid BASELINE_INTEGRITY_MODE*'
    }
}

Describe 'Integrity gate — opt-in behaviour' {
    BeforeEach {
        $script:gateRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-integrity-gate-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:gateRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:gateRoot 'a.psm1') -Value 'function A {}' -Encoding UTF8 -NoNewline
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:gateRoot) {
            Remove-Item -LiteralPath $script:gateRoot -Recurse -Force
        }
        Remove-Item Env:BASELINE_INTEGRITY_MODE -ErrorAction SilentlyContinue
    }

    It 'is a no-op when mode is Off, even without a manifest' {
        Remove-Item Env:BASELINE_INTEGRITY_MODE -ErrorAction SilentlyContinue
        { Invoke-BaselineModuleIntegrityGate -ModuleRoot $script:gateRoot } | Should -Not -Throw
    }

    It 'is a no-op in Audit mode when manifest is absent' {
        $env:BASELINE_INTEGRITY_MODE = 'Audit'
        $script:auditWarning = $null
        Mock -CommandName Write-Warning -MockWith {
            param([string]$Message)
            $script:auditWarning = $Message
        }

        { Invoke-BaselineModuleIntegrityGate -ModuleRoot $script:gateRoot } | Should -Not -Throw

        Should -Invoke -CommandName Write-Warning -Exactly -Times 1 -Scope It
        $script:auditWarning | Should -Match 'BASELINE_INTEGRITY_MODE=Audit will skip verification'
    }

    It 'throws in Strict mode when manifest is absent' {
        $env:BASELINE_INTEGRITY_MODE = 'Strict'
        { Invoke-BaselineModuleIntegrityGate -ModuleRoot $script:gateRoot } |
            Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
    }
}
