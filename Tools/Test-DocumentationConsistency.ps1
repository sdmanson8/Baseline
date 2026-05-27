<#
    .SYNOPSIS
    Validates that selected documentation claims still match code and test evidence.

    .DESCRIPTION
    This maintainer-only check compares a curated set of documentation claims
    against the code paths and unit tests that prove those claims in Baseline.
    It is intentionally narrow and deterministic so documentation signoff fails
    when a release, support, or remote-automation claim is described but not
    implemented or covered.

    .EXAMPLE
    powershell -File .\Tools\Test-DocumentationConsistency.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

function Get-ResolvedText
{
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Test-AnyPatternMatch
{
    param(
        [string]$Text,
        [string[]]$Patterns
    )

    foreach ($pattern in @($Patterns))
    {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($Text -match $pattern)
        {
            return $true
        }
    }

    return $false
}

function Test-EvidenceSet
{
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [object[]]$Sources
    )

    $matched = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($source in @($Sources))
    {
        $sourcePath = Join-Path $repoRoot ([string]$source.Path)
        $text = Get-ResolvedText -Path $sourcePath
        if ($null -eq $text)
        {
            [void]$missing.Add($source.Path)
            continue
        }

        if (Test-AnyPatternMatch -Text $text -Patterns @($source.Patterns))
        {
            [void]$matched.Add($source.Path)
        }
        else
        {
            [void]$missing.Add($source.Path)
        }
    }

    [pscustomobject]@{
        Label   = $Label
        Passed  = ($matched.Count -gt 0)
        Matched = @($matched)
        Missing = @($missing)
    }
}

$checks = @(
    [pscustomobject]@{
        Name = 'Release artifact verification'
        DocSources = @(
            [pscustomobject]@{
                Path = 'README.md'
                Patterns = @(
                    'artifact trust contract'
                    'Installer-Signing-Policy'
                    'release-signing policy'
                )
            },
            [pscustomobject]@{
                Path = 'dev_docs/Installer-Signing-Policy.md'
                Patterns = @(
                    'release artifacts are treated as trust-boundary inputs'
                    'release status dialog'
                )
            }
        )
        CodeSources = @(
            [pscustomobject]@{
                Path = 'Module/SharedHelpers/Lifecycle.Helpers.ps1'
                Patterns = @(
                    'function Get-BaselineReleaseArtifactVerification'
                    'function Assert-BaselineReleaseArtifactVerification'
                )
            },
            [pscustomobject]@{
                Path = 'Module/SharedHelpers.psm1'
                Patterns = @(
                    "'Get-BaselineReleaseArtifactVerification'"
                    "'Assert-BaselineReleaseArtifactVerification'"
                )
            }
        )
        TestSources = @(
            [pscustomobject]@{
                Path = 'Tests/Unit/Lifecycle.Helpers.Tests.ps1'
                Patterns = @(
                    'Get-BaselineReleaseArtifactVerification'
                    'Assert-BaselineReleaseArtifactVerification'
                    'timestamp countersignature is missing'
                )
            }
        )
    },
    [pscustomobject]@{
        Name = 'Support bundle export'
        DocSources = @(
            [pscustomobject]@{
                Path = 'README.md'
                Patterns = @(
                    'support bundle export'
                    'support bundle'
                )
            },
            [pscustomobject]@{
                Path = 'dev_docs/Installer-Signing-Policy.md'
                Patterns = @(
                    'Export-BaselineSupportBundle'
                    'support bundle'
                )
            }
        )
        CodeSources = @(
            [pscustomobject]@{
                Path = 'Module/SharedHelpers/SupportBundle.Helpers.ps1'
                Patterns = @(
                    'function Export-BaselineSupportBundle'
                )
            },
            [pscustomobject]@{
                Path = 'Module/SharedHelpers.psm1'
                Patterns = @(
                    "'Export-BaselineSupportBundle'"
                )
            }
        )
        TestSources = @(
            [pscustomobject]@{
                Path = 'Tests/Unit/SupportBundle.Helpers.Tests.ps1'
                Patterns = @(
                    'Export-BaselineSupportBundle'
                    'validation-evidence\.json'
                )
            },
            [pscustomobject]@{
                Path = 'Tests/Unit/SupportBundleMenu.Tests.ps1'
                Patterns = @(
                    'Export-BaselineSupportBundle'
                )
            }
        )
    },
    [pscustomobject]@{
        Name = 'Incident reproduction pack'
        DocSources = @(
            [pscustomobject]@{
                Path = 'README.md'
                Patterns = @(
                    'incident reproduction pack'
                )
            },
            [pscustomobject]@{
                Path = 'docs/Baseline-Validation-Lifecycle-Quality-Improvements.md'
                Patterns = @(
                    'incident reproduction pack'
                    'documentation-to-code consistency checks'
                )
            }
        )
        CodeSources = @(
            [pscustomobject]@{
                Path = 'Module/SharedHelpers/Lifecycle.Helpers.ps1'
                Patterns = @(
                    'function New-BaselineIncidentReproductionPack'
                )
            },
            [pscustomobject]@{
                Path = 'Module/SharedHelpers.psm1'
                Patterns = @(
                    "'New-BaselineIncidentReproductionPack'"
                )
            }
        )
        TestSources = @(
            [pscustomobject]@{
                Path = 'Tests/Unit/Lifecycle.Helpers.Tests.ps1'
                Patterns = @(
                    'New-BaselineIncidentReproductionPack'
                    'incident reproduction'
                )
            },
            [pscustomobject]@{
                Path = 'Tests/Unit/SupportBundle.Helpers.Tests.ps1'
                Patterns = @(
                    'validation-evidence\.json'
                )
            }
        )
    },
    [pscustomobject]@{
        Name = 'Remote automation evidence'
        DocSources = @(
            [pscustomobject]@{
                Path = 'README.md'
                Patterns = @(
                    'remote compliance checks'
                    'remote apply workflows'
                    'approval policies'
                )
            },
            [pscustomobject]@{
                Path = 'docs/FAQ.md'
                Patterns = @(
                    'Remote Console'
                    'approval-policy'
                    'support bundle export'
                )
            }
        )
        CodeSources = @(
            [pscustomobject]@{
                Path = 'Module/SharedHelpers/RemoteTarget.Helpers.ps1'
                Patterns = @(
                    'function Invoke-BaselineRemoteCompliance'
                    'function Invoke-BaselineRemoteApply'
                )
            },
            [pscustomobject]@{
                Path = 'Module/SharedHelpers/FeatureMaturity.Helpers.ps1'
                Patterns = @(
                    'function Test-BaselineEnterpriseActionMaturityGate'
                )
            },
            [pscustomobject]@{
                Path = 'Module/SharedHelpers.psm1'
                Patterns = @(
                    "'Invoke-BaselineRemoteCompliance'"
                    "'Invoke-BaselineRemoteApply'"
                    "'Test-BaselineEnterpriseActionMaturityGate'"
                )
            }
        )
        TestSources = @(
            [pscustomobject]@{
                Path = 'Tests/Unit/RemoteTarget.Helpers.Tests.ps1'
                Patterns = @(
                    'Invoke-BaselineRemoteCompliance'
                    'Invoke-BaselineRemoteApply'
                    'Test-BaselineEnterpriseActionMaturityGate'
                )
            },
            [pscustomobject]@{
                Path = 'Tests/Unit/ComplianceView.Tests.ps1'
                Patterns = @(
                    'Invoke-BaselineRemoteCompliance'
                )
            },
            [pscustomobject]@{
                Path = 'Tests/Unit/ExecutionOrchestration.Tests.ps1'
                Patterns = @(
                    'Invoke-BaselineRemoteApply'
                )
            }
        )
    }
)

$results = [System.Collections.Generic.List[pscustomobject]]::new()
$issues = [System.Collections.Generic.List[string]]::new()

foreach ($check in $checks)
{
    $docEvidence = Test-EvidenceSet -Label 'Docs' -Sources $check.DocSources
    $codeEvidence = Test-EvidenceSet -Label 'Code' -Sources $check.CodeSources
    $testEvidence = Test-EvidenceSet -Label 'Tests' -Sources $check.TestSources

    $checkPassed = ($docEvidence.Passed -and $codeEvidence.Passed -and $testEvidence.Passed)
    if (-not $checkPassed)
    {
        if (-not $docEvidence.Passed)
        {
            [void]$issues.Add(("Missing doc evidence for {0}: {1}" -f $check.Name, ($docEvidence.Missing -join ', ')))
        }
        if (-not $codeEvidence.Passed)
        {
            [void]$issues.Add(("Missing code evidence for {0}: {1}" -f $check.Name, ($codeEvidence.Missing -join ', ')))
        }
        if (-not $testEvidence.Passed)
        {
            [void]$issues.Add(("Missing test evidence for {0}: {1}" -f $check.Name, ($testEvidence.Missing -join ', ')))
        }
    }

    [void]$results.Add([pscustomobject]@{
        Check = $check.Name
        Docs  = [bool]$docEvidence.Passed
        Code  = [bool]$codeEvidence.Passed
        Tests = [bool]$testEvidence.Passed
        Passed = [bool]$checkPassed
    })
}

$summary = [pscustomobject]@{
    Schema = 'Baseline.DocumentationConsistency'
    SchemaVersion = 1
    GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
    RepoRoot = $repoRoot
    Checks = @($results)
    Passed = ($issues.Count -eq 0)
    FailureCount = $issues.Count
}

Write-Host ('Documentation consistency checks: {0}/{1} passed' -f (@($results | Where-Object Passed).Count), $results.Count)
foreach ($result in $results)
{
    Write-Host ('  {0}: {1}' -f $result.Check, ($(if ($result.Passed) { 'PASS' } else { 'FAIL' })))
}

if ($issues.Count -gt 0)
{
    $issueText = ($issues -join [System.Environment]::NewLine)
    throw "Documentation-to-code consistency checks failed.`n$issueText"
}

if ($PassThru)
{
    $summary
}
else
{
    [void]$summary
}
