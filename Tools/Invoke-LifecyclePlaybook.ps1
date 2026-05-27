<#
    .SYNOPSIS
    Generates or executes a Baseline upgrade, downgrade, or rollback playbook.

    .DESCRIPTION
    Uses the shared lifecycle helpers to build a structured playbook from the
    current Baseline version, installer artifact, or rollback profile. When
    -Execute is supplied, the script runs the requested installer or rollback
    command set.

    .EXAMPLE
    powershell -File .\Tools\Invoke-LifecyclePlaybook.ps1 -Operation Upgrade -InstallerPath .\dist\Baseline-1.0.0-setup.exe

    .EXAMPLE
    powershell -File .\Tools\Invoke-LifecyclePlaybook.ps1 -Operation Rollback -RollbackProfilePath .\bundle\rollback.json -Execute
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Upgrade', 'Downgrade', 'Rollback')]
    [string]$Operation,

    [string]$CurrentVersion,
    [string]$TargetVersion,
    [string]$InstallerPath,
    [string]$RollbackProfilePath,
    [string]$OutputPath,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path $repoRoot 'Module\Baseline.psd1'
Import-Module -LiteralPath $modulePath -Force -ErrorAction Stop

try
{
    $playbook = New-BaselineLifecyclePlaybook `
        -Operation $Operation `
        -CurrentVersion $CurrentVersion `
        -TargetVersion $TargetVersion `
        -InstallerPath $InstallerPath `
        -RollbackProfilePath $RollbackProfilePath

    if ($WhatIfPreference)
    {
        $Execute = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath))
    {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -LiteralPath $outputDir))
        {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        $exportPath = if ($OutputPath.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) { $OutputPath } else { '{0}.json' -f $OutputPath }
        $playbook | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $exportPath -Encoding UTF8
    }

    $result = Invoke-BaselineLifecyclePlaybook -Playbook $playbook -Execute:$Execute
    $result | Add-Member -NotePropertyName Playbook -NotePropertyValue $playbook -Force

    try
    {
        if (Get-Command -Name 'Write-AuditRecord' -ErrorAction SilentlyContinue)
        {
            $auditDetails = [ordered]@{
                Operation           = $playbook.Operation
                Direction           = $playbook.Direction
                Executed            = [bool]$Execute
                Verification        = $playbook.Verification
                ResultVerification   = $result.Verification
                VerificationChanged  = [bool]$result.VerificationChanged
            }

            Write-AuditRecord `
                -Action $(if ($Execute) { 'LifecyclePlaybookExecuted' } else { 'LifecyclePlaybookPlanned' }) `
                -Mode 'Deployment' `
                -ProfilePath $(if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $exportPath } else { $playbook.InstallerPath }) `
                -Details $auditDetails
        }

        if ($Execute -and (Get-Command -Name 'Write-BaselineRemoteRolloutOutcome' -ErrorAction SilentlyContinue))
        {
            $verificationForRecord = if ($result.Verification) { $result.Verification } else { $playbook.Verification }
            $outcome = if ($result.Success) { 'Succeeded' } elseif ($result.VerificationChanged -and -not $result.Success) { 'Aborted' } else { 'Failed' }
            $rolloutDetails = [ordered]@{
                PlaybookVerification = $playbook.Verification
                ResultVerification = $result.Verification
                VerificationChanged = [bool]$result.VerificationChanged
            }

            $null = Write-BaselineRemoteRolloutOutcome `
                -RunId ([guid]::NewGuid().ToString('N')) `
                -Operation $playbook.Operation `
                -Outcome $outcome `
                -TargetCount 1 `
                -SucceededCount $(if ($result.Success) { 1 } else { 0 }) `
                -FailedCount $(if ($result.Success) { 0 } else { 1 }) `
                -StartedUtc ([datetime]::UtcNow) `
                -CompletedUtc ([datetime]::UtcNow) `
                -ArtifactVerification $verificationForRecord `
                -Details $rolloutDetails
        }
    }
    catch
    {
        Write-Warning ("Failed to record lifecycle verification metadata: {0}" -f $_.Exception.Message)
    }

    $result
}
catch
{
    $message = [string]$_.Exception.Message
    if ($message -match '(?i)Artifact verification failed')
    {
        if ($playbook -and (Get-Command -Name 'Write-BaselineRemoteRolloutOutcome' -ErrorAction SilentlyContinue))
        {
            try
            {
                $verificationForRecord = if ($playbook.PSObject.Properties['Verification']) { $playbook.Verification } else { $null }
                $null = Write-BaselineRemoteRolloutOutcome `
                    -RunId ([guid]::NewGuid().ToString('N')) `
                    -Operation $playbook.Operation `
                    -Outcome 'Aborted' `
                    -TargetCount 1 `
                    -SucceededCount 0 `
                    -FailedCount 1 `
                    -StartedUtc ([datetime]::UtcNow) `
                    -CompletedUtc ([datetime]::UtcNow) `
                    -ArtifactVerification $verificationForRecord `
                    -Details ([ordered]@{
                        PlaybookVerification = $verificationForRecord
                        FailureMessage = $message
                    })
            }
            catch
            {
                Write-Warning ("Failed to record blocked lifecycle rollout metadata: {0}" -f $_.Exception.Message)
            }
        }
        Write-Error ("Lifecycle execution blocked because the artifact could not be verified.`n{0}" -f $message)
        exit 1
    }

    throw
}
