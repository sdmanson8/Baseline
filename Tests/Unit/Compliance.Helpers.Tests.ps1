Set-StrictMode -Version Latest

BeforeAll {
    $script:HelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Compliance.Helpers.ps1'
    . $script:HelperPath

    $script:TempRoot = Join-Path $env:TEMP ('BaselineComplianceHelperTests_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -Path Function:\Get-WindowsUpdateCompliance -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Export-ComplianceReport' {
    BeforeEach {
        Remove-Item -Path Function:\Get-WindowsUpdateCompliance -ErrorAction SilentlyContinue
    }

    It 'adds Windows Update compliance to JSON exports when the helper is available' {
        function Get-WindowsUpdateCompliance {
            return [pscustomobject]@{
                Schema          = 'Baseline.WindowsUpdateCompliance'
                GeneratedAt     = [System.DateTime]::UtcNow.ToString('o')
                Status          = 'NonCompliant'
                SecurityPending = 2
                CriticalPending = 1
            }
        }

        $report = [pscustomobject]@{
            Timestamp    = [System.DateTime]::UtcNow.ToString('o')
            MachineName  = 'TESTHOST'
            ProfileName  = 'Default'
            TotalChecked = 0
            Compliant    = 0
            Drifted      = 0
            Unknown      = 0
            Entries      = @()
        }
        $outputPath = Join-Path $script:TempRoot 'compliance-report.json'

        Export-ComplianceReport -Report $report -FilePath $outputPath -Format Json

        $payload = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $payload.WindowsUpdateCompliance.Schema | Should -Be 'Baseline.WindowsUpdateCompliance'
        $payload.WindowsUpdateCompliance.Status | Should -Be 'NonCompliant'
        $payload.WindowsUpdateCompliance.SecurityPending | Should -Be 2
        $payload.WindowsUpdateCompliance.CriticalPending | Should -Be 1
    }

    It 'records a structured Windows Update compliance failure instead of omitting the section' {
        function Get-WindowsUpdateCompliance {
            throw 'WUA unavailable'
        }

        $report = [pscustomobject]@{
            Timestamp    = [System.DateTime]::UtcNow.ToString('o')
            MachineName  = 'TESTHOST'
            ProfileName  = 'Default'
            TotalChecked = 0
            Compliant    = 0
            Drifted      = 0
            Unknown      = 0
            Entries      = @()
        }
        $outputPath = Join-Path $script:TempRoot 'compliance-report-error.json'

        Export-ComplianceReport -Report $report -FilePath $outputPath -Format Json

        $payload = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $payload.WindowsUpdateCompliance.Schema | Should -Be 'Baseline.WindowsUpdateCompliance'
        $payload.WindowsUpdateCompliance.Status | Should -Be 'Unknown'
        $payload.WindowsUpdateCompliance.Error | Should -Match 'WUA unavailable'
    }
}
