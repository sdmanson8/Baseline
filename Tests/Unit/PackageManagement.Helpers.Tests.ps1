Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/PackageManagement.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Assert-FileHash' {
    It 'returns the computed SHA-256 when the file matches the expected value' {
        $filePath = Join-Path $TestDrive 'sample.txt'
        Set-Content -LiteralPath $filePath -Value 'baseline' -Encoding ASCII
        $expectedHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToUpperInvariant()

        $result = Assert-FileHash -Path $filePath -ExpectedSha256 $expectedHash -Label 'Sample file'

        $result | Should -Be $expectedHash
    }

    It 'throws when the hash does not match' {
        $filePath = Join-Path $TestDrive 'sample.txt'
        Set-Content -LiteralPath $filePath -Value 'baseline' -Encoding ASCII

        { Assert-FileHash -Path $filePath -ExpectedSha256 ('0' * 64) -Label 'Sample file' } | Should -Throw '*SHA-256 verification*'
    }
}

Describe 'Resolve-PowerShellInstallerUri' {
    BeforeEach {
        Mock Set-DownloadSecurityProtocol {}
        Mock Get-PowerShellInstallerArchitecture { 'win-x64' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                assets = @(
                    [pscustomobject]@{ name = 'PowerShell-7.5.0-win-arm64.msi'; browser_download_url = 'https://example.test/arm64.msi' }
                    [pscustomobject]@{ name = 'PowerShell-7.5.0-win-x64.msi'; browser_download_url = 'https://example.test/x64.msi' }
                )
            }
        }
    }

    It 'selects the MSI that matches the resolved architecture' {
        $result = Resolve-PowerShellInstallerUri -ReleaseApiUri 'https://example.test/latest'

        $result | Should -Be 'https://example.test/x64.msi'
    }

    It 'throws when no matching MSI asset exists' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                assets = @(
                    [pscustomobject]@{ name = 'PowerShell-7.5.0-linux-x64.tar.gz'; browser_download_url = 'https://example.test/linux.tar.gz' }
                )
            }
        }

        { Resolve-PowerShellInstallerUri -ReleaseApiUri 'https://example.test/latest' } | Should -Throw '*Could not find a PowerShell MSI installer*'
    }
}
