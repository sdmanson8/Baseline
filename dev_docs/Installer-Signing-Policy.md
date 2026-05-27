# Baseline Installer Signing Policy

Baseline release artifacts are treated as trust-boundary inputs. The policy below is the operational contract for installer and release validation.

## Current release posture

Baseline 1.0.0 stable releases currently ship **unsigned**. Code signing infrastructure (HSM-held certificate, approved signer list, timestamp authority) is planned but not yet in place, so the lifecycle helpers operate in a mode that accepts unsigned installers when the operator explicitly acknowledges the posture.

To run an upgrade or downgrade playbook against a preview (unsigned) artifact, acknowledge the posture before invoking the tooling:

```powershell
$env:BASELINE_PREVIEW_UNSIGNED = '1'
powershell -File .\Tools\Invoke-LifecyclePlaybook.ps1 -Operation Upgrade -InstallerPath .\dist\Baseline-setup-<version>-<channel>.exe
```

Or pass `-AllowUnsignedPreview` directly to `Get-BaselineReleaseArtifactVerification` / `Assert-BaselineReleaseArtifactVerification`. The verification record is surfaced with `VerificationState = 'Preview'` so that audit, support-bundle, and remote-rollout records honestly reflect that the artifact was unsigned.

The signed-release policy below is the target state. It becomes mandatory the moment a release is promoted to an enterprise deployment channel — at that point `BASELINE_PREVIEW_UNSIGNED` must not be set, and `-AllowUnsignedPreview` must not be used.

## Scope

- `Baseline-<version>-stable.zip`
- `Baseline-<version>-setup.exe`
- any release payload that is promoted to an enterprise deployment channel

## Policy (applies once signing is in place / to any promoted release)

1. Release artifacts must be generated from the tagged repository state that produced the release version.
2. Release artifacts must be Authenticode signed before they are published or promoted to an enterprise channel.
3. The signing certificate subject must match the approved release signer list for the environment (configured via `-AllowedSubjects`).
4. Operators must verify the artifact signature before execution on managed endpoints.
5. Unsigned, tampered, or unverifiable artifacts must not be used for upgrade, downgrade, or rollback workflows on promoted releases, and `BASELINE_PREVIEW_UNSIGNED` must not be set in that environment.

## Verification

Use the release status dialog or the lifecycle tooling to confirm:

- artifact status is `Valid`
- the signer subject matches the approved signer
- the version reported by the artifact matches the intended rollout target

If the signature check fails, treat the artifact as untrusted and replace it with a newly published release artifact.

## Enterprise controls

- Keep the approved signer list in the deployment runbook.
- Attach the release status output to change records when promoting a version.
- Re-run signature verification after downloading artifacts to an operator workstation.
- Record signature verification in the support bundle or incident record when a change is escalated.

## Related tools

- `Tools/New-ReleasePackage.ps1`
- `Tools/New-InstallerPackage.ps1`
- `Tools/Invoke-LifecyclePlaybook.ps1`
- `Tools/New-IncidentReproductionPack.ps1`

## Key custody

- Signing certificates must be held in an HSM, hardware token, or platform key store (Azure Key Vault, AWS KMS, Windows TPM with attestation). Plain `.pfx` files on disk are not acceptable for promoted releases.
- The release signer list is maintained alongside the deployment runbook and is reviewed each release cycle. Rotations require updating both the approved signer list and the embedded verification metadata in the lifecycle tooling.
- Access to the signing key is limited to release engineers with documented approval. Each signing event must be logged (signer identity, artifact hash, timestamp).

## Timestamp authority

- All signatures must include an RFC 3161 timestamp. The default authority is `http://timestamp.digicert.com`; alternate authorities require change-control approval.
- Timestamping is non-optional: an artifact whose signature lacks a valid countersignature is treated as untrusted regardless of certificate validity.
- Verification (`signtool verify /pa /tw <artifact>`) must succeed without warnings; warnings are treated as failures.

## Verification steps

The following sequence is the canonical verification path; it is also the sequence the lifecycle tooling expects:

1. Compute the SHA-256 hash of the artifact and confirm it matches the published release manifest asset (`Baseline-<version>-stable.zip.sha256.json`).
2. Run `signtool verify /pa /v /tw <artifact>`. The command must succeed with exit code 0.
3. Inspect the signer chain and confirm the leaf certificate subject matches the approved release signer.
4. Confirm the embedded version metadata matches the intended rollout target.
5. Record the verification result (artifact name, hash, signer, timestamp) in the change record.

For PowerShell-based pipelines, the equivalent of step 2 is:

```powershell
$signature = Get-AuthenticodeSignature -FilePath $artifactPath
if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
    throw "Artifact failed signature/timestamp validation: $artifactPath"
}
```

## Incident handling

When signature verification fails on an endpoint:

1. Stop the rollout to that endpoint immediately.
2. Open an incident, attach the failed artifact (or its hash) and the verification output.
3. Generate an incident reproduction pack via `Tools/New-IncidentReproductionPack.ps1` for the endpoint's support bundle so the failure context travels with the ticket.
4. Replace the artifact with a freshly published, re-verified copy from the release channel before any retry.

## Audit trail

- Every release event (signing, promotion, verification, rollback) writes a record to the audit trail via `Write-AuditRecord`. These records are exported with the support bundle (`Export-BaselineSupportBundle`).
- Audit retention is governed by `Get-BaselineAuditRetentionDays` and enforced by `Invoke-BaselineAuditRetentionPolicy`. Retention windows shorter than 90 days require formal sign-off.
