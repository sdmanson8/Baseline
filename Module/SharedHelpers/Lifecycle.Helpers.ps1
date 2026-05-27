# Lifecycle helpers for Baseline.
# Provides release lifecycle playbooks, rollback execution, and incident
# reproduction pack generation from existing Baseline artifacts.

<#
    .SYNOPSIS
#>

function Get-BaselineLifecycleComparableVersion
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$VersionText
	)

	$text = ([string]$VersionText).Trim()
	if ([string]::IsNullOrWhiteSpace($text))
	{
		return $null
	}

	if (Get-Command -Name 'ConvertTo-NormalizedVersion' -ErrorAction SilentlyContinue)
	{
		try
		{
			return ConvertTo-NormalizedVersion -Version $text
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Lifecycle.Helpers.Get-BaselineLifecycleComparableVersion:catch29' -Severity Debug }

			# Fall through to the local parser below.
		}
	}

	$normalizedText = $text.TrimStart('v')
	$normalizedText = $normalizedText.Split('(')[0].Trim()
	$normalizedText = $normalizedText.Split('-')[0].Trim()

	$parsedVersion = $null
	if ([version]::TryParse($normalizedText, [ref]$parsedVersion))
	{
		return $parsedVersion
	}

	return $normalizedText
}

<#
    .SYNOPSIS
#>

function Get-BaselineReleaseArtifactVerification
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[string[]]$AllowedSubjects = @(),

		[switch]$RequireTimestamp = $true,

		[switch]$AllowUnsignedPreview
	)

	if (-not $PSBoundParameters.ContainsKey('AllowUnsignedPreview'))
	{
		$previewEnv = [string]$env:BASELINE_PREVIEW_UNSIGNED
		if (-not [string]::IsNullOrWhiteSpace($previewEnv) -and ($previewEnv -match '^(?i:1|true|yes|on)$'))
		{
			$AllowUnsignedPreview = $true
		}
	}

	$verification = [ordered]@{
		Path              = $Path
		Exists            = $false
		HashAlgorithm     = 'SHA256'
		FileHash          = $null
		SignatureStatus   = 'Missing'
		SignerSubject     = $null
		TimestampStatus   = 'Missing'
		TimestampSubject  = $null
		AllowedSubjects   = @($AllowedSubjects)
		PreviewAcknowledged = [bool]$AllowUnsignedPreview
		VerificationState = 'Missing'
		VerificationMessage = 'Artifact not found.'
		VerificationAt    = [System.DateTime]::UtcNow.ToString('o')
	}

	if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		return [pscustomobject]$verification
	}

	$verification.Exists = $true
	try
	{
		$fileHash = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop
		$verification.FileHash = [string]$fileHash.Hash
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Lifecycle.Helpers.Get-BaselineReleaseArtifactVerification:catch102' -Severity Debug }

		$verification.VerificationState = 'Invalid'
		$verification.VerificationMessage = "Failed to compute SHA-256 hash: $($_.Exception.Message)"
		return [pscustomobject]$verification
	}

	if (-not (Get-Command -Name 'Get-AuthenticodeSignature' -ErrorAction SilentlyContinue))
	{
		$verification.VerificationState = 'Unavailable'
		$verification.VerificationMessage = "Get-AuthenticodeSignature is not available to verify '$Path'."
		return [pscustomobject]$verification
	}

	try
	{
		$signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Lifecycle.Helpers.Get-BaselineReleaseArtifactVerification:catch120' -Severity Debug }

		$verification.VerificationState = 'Invalid'
		$verification.VerificationMessage = "Authenticode signature verification failed for '$Path': $($_.Exception.Message)"
		return [pscustomobject]$verification
	}

	$verification.SignatureStatus = [string]$signature.Status
	$verification.SignerSubject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { $null }
	$verification.TimestampStatus = if ($signature.TimeStamperCertificate) { 'Present' } else { 'Missing' }
	$verification.TimestampSubject = if ($signature.TimeStamperCertificate) { [string]$signature.TimeStamperCertificate.Subject } else { $null }

	$issues = [System.Collections.Generic.List[string]]::new()
	if ($signature.Status -ne 'Valid')
	{
		[void]$issues.Add(("signature status is {0}" -f [string]$signature.Status))
	}
	if ($RequireTimestamp -and -not $signature.TimeStamperCertificate)
	{
		[void]$issues.Add('timestamp countersignature is missing')
	}
	if ($AllowedSubjects.Count -gt 0)
	{
		$subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
		$subjectMatched = $false
		foreach ($allowedSubject in @($AllowedSubjects))
		{
			if ([string]::IsNullOrWhiteSpace([string]$allowedSubject)) { continue }
			if ($subject -like "*$allowedSubject*")
			{
				$subjectMatched = $true
				break
			}
		}
		if (-not $subjectMatched)
		{
			[void]$issues.Add(("signer subject '{0}' is not approved" -f $subject))
		}
	}

	if ($issues.Count -gt 0)
	{
		if ($AllowUnsignedPreview)
		{
			$verification.VerificationState = 'Preview'
			$verification.VerificationMessage = 'Unsigned preview release accepted: ' + ($issues -join '; ')
		}
		else
		{
			$verification.VerificationState = 'Invalid'
			$verification.VerificationMessage = ($issues -join '; ')
		}
	}
	else
	{
		$verification.VerificationState = 'Valid'
		$verification.VerificationMessage = 'Artifact signature and timestamp verification succeeded.'
	}

	return [pscustomobject]$verification
}

<#
    .SYNOPSIS
#>

function Assert-BaselineReleaseArtifactVerification
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path,

		[string[]]$AllowedSubjects = @(),

		[switch]$RequireTimestamp = $true,

		[switch]$AllowUnsignedPreview
	)

	if (-not $PSBoundParameters.ContainsKey('AllowUnsignedPreview'))
	{
		$previewEnv = [string]$env:BASELINE_PREVIEW_UNSIGNED
		if (-not [string]::IsNullOrWhiteSpace($previewEnv) -and ($previewEnv -match '^(?i:1|true|yes|on)$'))
		{
			$AllowUnsignedPreview = $true
		}
	}

	$verification = Get-BaselineReleaseArtifactVerification -Path $Path -AllowedSubjects $AllowedSubjects -RequireTimestamp:$RequireTimestamp -AllowUnsignedPreview:$AllowUnsignedPreview
	if ($verification.VerificationState -notin @('Valid', 'Preview'))
	{
		throw ("Artifact verification failed for '{0}': {1}" -f $verification.Path, $verification.VerificationMessage)
	}

	return $verification
}

<#
    .SYNOPSIS
#>

function Import-BaselineRollbackProfile
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		throw "Rollback profile not found: $Path"
	}

	$document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
	$entries = @()
	if ($document.PSObject.Properties['Entries'])
	{
		$entries = @($document.Entries)
	}
	elseif ($document.PSObject.Properties['Commands'])
	{
		$entries = @($document.Commands)
	}

	$commands = @(
		$entries |
			ForEach-Object { [string]$_ } |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
	)

	[pscustomobject]@{
		Path         = (Resolve-Path -LiteralPath $Path).Path
		Schema       = if ($document.PSObject.Properties['Schema']) { [string]$document.Schema } else { 'Baseline.RollbackProfile' }
		SchemaVersion = if ($document.PSObject.Properties['SchemaVersion']) { [int]$document.SchemaVersion } else { 1 }
		Name         = if ($document.PSObject.Properties['Name']) { [string]$document.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
		SourceMode   = if ($document.PSObject.Properties['SourceMode']) { [string]$document.SourceMode } else { $null }
		Commands     = $commands
		CommandCount = $commands.Count
		ExportedAt   = if ($document.PSObject.Properties['ExportedAt']) { [string]$document.ExportedAt } else { $null }
	}
}

<#
    .SYNOPSIS
#>

function New-BaselineLifecyclePlaybook
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[ValidateSet('Upgrade', 'Downgrade', 'Rollback')]
		[string]$Operation,

		[string]$CurrentVersion,
		[string]$TargetVersion,
		[string]$InstallerPath,
		[string]$RollbackProfilePath,
		[string]$BaselineExecutablePath
	)

	if ([string]::IsNullOrWhiteSpace($CurrentVersion))
	{
		try { $CurrentVersion = Get-BaselineDisplayVersion } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Lifecycle.Helpers.New-BaselineLifecyclePlaybook:catch285' -Severity Debug }
		 $CurrentVersion = $null }
	}

	$targetVersionText = $TargetVersion
	if ([string]::IsNullOrWhiteSpace($targetVersionText) -and -not [string]::IsNullOrWhiteSpace($InstallerPath))
	{
		$leaf = [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath)
		$match = [regex]::Match($leaf, '^Baseline-(?<Version>.+)-setup$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
		if (-not $match.Success)
		{
			$match = [regex]::Match($leaf, '^Baseline-portable-(?<Version>.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
		}
		if ($match.Success)
		{
			$targetVersionText = [string]$match.Groups['Version'].Value
		}
	}

	$commands = @()
	$rollbackProfile = $null
	$verification = $null
	if ($Operation -eq 'Rollback')
	{
		if ([string]::IsNullOrWhiteSpace($RollbackProfilePath))
		{
			throw 'RollbackProfilePath is required when Operation is Rollback.'
		}

		$rollbackProfile = Import-BaselineRollbackProfile -Path $RollbackProfilePath
		$commands = @($rollbackProfile.Commands)
		if ($commands.Count -eq 0)
		{
			throw "Rollback profile '$RollbackProfilePath' does not contain any rollback commands."
		}
	}
	elseif ($Operation -in @('Upgrade', 'Downgrade'))
	{
		if ([string]::IsNullOrWhiteSpace($InstallerPath))
		{
			throw 'InstallerPath is required for upgrade or downgrade playbooks.'
		}

		$verification = Assert-BaselineReleaseArtifactVerification -Path $InstallerPath
	}

	$currentComparable = if ([string]::IsNullOrWhiteSpace($CurrentVersion)) { $null } else { Get-BaselineLifecycleComparableVersion -VersionText $CurrentVersion }
	$targetComparable = if ([string]::IsNullOrWhiteSpace($targetVersionText)) { $null } else { Get-BaselineLifecycleComparableVersion -VersionText $targetVersionText }

	$direction = switch ($Operation)
	{
		'Upgrade' {
			if ($currentComparable -and $targetComparable -and $targetComparable -lt $currentComparable) { 'Downgrade' } else { 'Upgrade' }
			break
		}
		'Downgrade' {
			if ($currentComparable -and $targetComparable -and $targetComparable -gt $currentComparable) { 'Upgrade' } else { 'Downgrade' }
			break
		}
		default { 'Rollback' }
	}

	$steps = [System.Collections.Generic.List[string]]::new()
	switch ($Operation)
	{
		'Upgrade' {
			[void]$steps.Add('Verify the installer signature and release provenance.')
			[void]$steps.Add('Export a support bundle and keep the current configuration profile.')
			[void]$steps.Add('Run the installer silently and wait for completion.')
			[void]$steps.Add('Reopen Baseline and confirm the installed version.')
		}
		'Downgrade' {
			[void]$steps.Add('Verify the older installer signature and release provenance.')
			[void]$steps.Add('Export a support bundle and keep the current configuration profile.')
			[void]$steps.Add('Run the older installer silently and wait for completion.')
			[void]$steps.Add('Reopen Baseline and confirm the installed version rolled back.')
		}
		'Rollback' {
			[void]$steps.Add('Review the rollback profile and confirm the target commands.')
			[void]$steps.Add('Export a support bundle before applying the rollback profile.')
			[void]$steps.Add('Execute the rollback commands through the Baseline launcher.')
			[void]$steps.Add('Validate the resulting state and keep the support bundle with the incident record.')
		}
	}

	[pscustomobject]@{
		Operation         = $Operation
		Direction         = $direction
		CurrentVersion    = $CurrentVersion
		TargetVersion     = $targetVersionText
		InstallerPath     = if ($InstallerPath) { (Resolve-Path -LiteralPath $InstallerPath).Path } else { $null }
		RollbackProfile   = $rollbackProfile
		RollbackCommands  = $commands
		Verification      = $verification
		BaselineExecutable = if ($BaselineExecutablePath) { (Resolve-Path -LiteralPath $BaselineExecutablePath).Path } else { $null }
		Steps             = @($steps)
		GeneratedAt       = [System.DateTime]::UtcNow.ToString('o')
	}
}

<#
    .SYNOPSIS
#>

function Invoke-BaselineLifecyclePlaybook
{
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory)]
		[pscustomobject]$Playbook,

		[switch]$Execute
	)

	if ($null -eq $Playbook)
	{
		throw 'Playbook is required.'
	}

	$result = [ordered]@{
		Operation = [string]$Playbook.Operation
		Direction = [string]$Playbook.Direction
		Executed  = [bool]$Execute
		Success   = $false
		ExitCode  = $null
		Commands  = @()
		Verification = $null
		VerificationChanged = $false
	}

	if (-not $Execute)
	{
		if ($Playbook.PSObject.Properties['Verification'])
		{
			$result.Verification = $Playbook.Verification
		}
		$result.Success = $true
		return [pscustomobject]$result
	}

	switch ([string]$Playbook.Operation)
	{
		'Upgrade' { }
		'Downgrade' { }
		'Rollback' { }
		default { throw "Unsupported lifecycle operation '$($Playbook.Operation)'." }
	}

	if ($Playbook.Operation -in @('Upgrade', 'Downgrade'))
	{
		if ([string]::IsNullOrWhiteSpace([string]$Playbook.InstallerPath))
		{
			throw 'InstallerPath is required for upgrade or downgrade execution.'
		}

		$currentVerification = Assert-BaselineReleaseArtifactVerification -Path $Playbook.InstallerPath
		$result.Verification = $currentVerification
		if ($Playbook.PSObject.Properties['Verification'] -and $Playbook.Verification)
		{
			$recordedVerification = $Playbook.Verification
			$comparisonFields = @('VerificationState', 'SignatureStatus', 'TimestampStatus', 'SignerSubject', 'TimestampSubject', 'FileHash')
			$verificationChanged = $false
			foreach ($field in $comparisonFields)
			{
				$recordedValue = if ($recordedVerification.PSObject.Properties[$field]) { [string]$recordedVerification.$field } else { $null }
				$currentValue = if ($currentVerification.PSObject.Properties[$field]) { [string]$currentVerification.$field } else { $null }
				if ($recordedValue -ne $currentValue)
				{
					$verificationChanged = $true
					break
				}
			}

			if ($verificationChanged)
			{
				$changeMessage = @(
					'The artifact verification state changed after the playbook was created.',
					('Recorded: {0} | Status: {1} | Timestamp: {2} | Signer: {3}' -f $recordedVerification.VerificationState, $recordedVerification.SignatureStatus, $recordedVerification.TimestampStatus, $recordedVerification.SignerSubject),
					('Current: {0} | Status: {1} | Timestamp: {2} | Signer: {3}' -f $currentVerification.VerificationState, $currentVerification.SignatureStatus, $currentVerification.TimestampStatus, $currentVerification.SignerSubject)
				) -join [System.Environment]::NewLine
				if (-not $PSCmdlet.ShouldContinue($changeMessage, 'Release verification changed'))
				{
					throw 'Execution cancelled by operator.'
				}
				$result.VerificationChanged = $true
			}
		}

		$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS')
	if ($PSCmdlet.ShouldProcess($Playbook.InstallerPath, "$($Playbook.Operation) Baseline"))
	{
		$process = Invoke-BaselineProcess -FilePath $Playbook.InstallerPath -ArgumentList $arguments -TimeoutSeconds 1800
		$result.ExitCode = $process.ExitCode
		$result.Success = ($process.ExitCode -eq 0)
	}

		return [pscustomobject]$result
	}

	$commands = @($Playbook.RollbackCommands)
	if ($commands.Count -eq 0)
	{
		throw 'Rollback playbook does not contain any commands.'
	}

	$bootstrapPath = Join-Path $Script:SharedHelpersRepoRoot 'Baseline.exe'
	$useExe = Test-Path -LiteralPath $bootstrapPath -PathType Leaf
	if (-not $useExe)
	{
		$bootstrapPath = Join-Path $Script:SharedHelpersRepoRoot 'Bootstrap\Baseline.ps1'
		if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf))
		{
			throw 'Could not locate Baseline.exe or Bootstrap\Baseline.ps1 to execute rollback commands.'
		}
	}

	$argumentList = @()
	if ($useExe)
	{
		$argumentList += '-Functions'
		$argumentList += $commands
	}
	else
	{
		$argumentList += @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bootstrapPath, '-Functions')
		$argumentList += $commands
		$bootstrapPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
	}

	if ($PSCmdlet.ShouldProcess(($commands -join ', '), 'Execute rollback playbook'))
	{
		$process = Invoke-BaselineProcess -FilePath $bootstrapPath -ArgumentList $argumentList -TimeoutSeconds 1800
		$result.ExitCode = $process.ExitCode
		$result.Success = ($process.ExitCode -eq 0)
		$result.Commands = @($commands)
	}

	return [pscustomobject]$result
}

<#
    .SYNOPSIS
#>

function New-BaselineIncidentReproductionPack
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$SupportBundlePath,

		[string]$OutputDirectory,

		[string]$IncidentId
	)

	if (-not (Test-Path -LiteralPath $SupportBundlePath))
	{
		throw "Support bundle not found: $SupportBundlePath"
	}

	$resolvedBundlePath = (Resolve-Path -LiteralPath $SupportBundlePath).Path
	$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("BaselineIncident_{0}" -f [guid]::NewGuid().ToString('N'))
	$bundleRoot = $workRoot
	$createdTemp = $false

	try
	{
		if ((Get-Item -LiteralPath $resolvedBundlePath).PSIsContainer)
		{
			$bundleRoot = $resolvedBundlePath
		}
		else
		{
			$bundleRoot = Join-Path $workRoot 'bundle'
			New-Item -Path $bundleRoot -ItemType Directory -Force | Out-Null
			Expand-Archive -LiteralPath $resolvedBundlePath -DestinationPath $bundleRoot -Force
			$createdTemp = $true
		}

		if ([string]::IsNullOrWhiteSpace($OutputDirectory))
		{
			$bundleName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedBundlePath)
			$OutputDirectory = Join-Path (Split-Path -Path $resolvedBundlePath -Parent) ("{0}.repro" -f $bundleName)
		}

		$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path (Split-Path -Path $resolvedBundlePath -Parent) $OutputDirectory }
		New-Item -Path $resolvedOutput -ItemType Directory -Force | Out-Null

		$metadataPath = Join-Path $bundleRoot 'metadata.json'
		$preflightPath = Join-Path $bundleRoot 'preflight-report.json'
		$auditPath = Join-Path $bundleRoot 'audit.jsonl'
		$compliancePath = Join-Path $bundleRoot 'compliance-report.json'
		$validationEvidencePath = Join-Path $bundleRoot 'validation-evidence.json'
		$deepLinksPath = Join-Path $bundleRoot 'remote-orchestration-deeplinks.json'

		$metadata = if (Test-Path -LiteralPath $metadataPath) { Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction SilentlyContinue } else { $null }
		$preflight = if (Test-Path -LiteralPath $preflightPath) { Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction SilentlyContinue } else { $null }
		$compliance = if (Test-Path -LiteralPath $compliancePath) { Get-Content -LiteralPath $compliancePath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction SilentlyContinue } else { $null }
		$validationEvidence = if (Test-Path -LiteralPath $validationEvidencePath) { Get-Content -LiteralPath $validationEvidencePath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction SilentlyContinue } else { $null }
		$deepLinks = if (Test-Path -LiteralPath $deepLinksPath) { Get-Content -LiteralPath $deepLinksPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16 -ErrorAction SilentlyContinue } else { $null }

		$auditLines = @()
		if (Test-Path -LiteralPath $auditPath)
		{
			$auditLines = @(Get-Content -LiteralPath $auditPath -ErrorAction SilentlyContinue | Select-Object -First 20)
		}

		$recentAudit = @(
			foreach ($line in $auditLines)
			{
				if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
				try { $line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Lifecycle.Helpers.New-BaselineIncidentReproductionPack:catch596' -Severity Debug }
				 continue }
			}
		)

		$warningDetails = @()
		if ($preflight -and $preflight.PSObject.Properties['AllResults'])
		{
			$warningDetails = @(
				@($preflight.AllResults | Where-Object { $_.Status -in @('Warning', 'Failed') } | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Message })
			)
		}

		$reproSteps = [System.Collections.Generic.List[string]]::new()
		[void]$reproSteps.Add('Use the exact Baseline version recorded in the support bundle metadata.')
		[void]$reproSteps.Add('Reapply the same profile, approval policy, or rollback profile that was attached to the bundle.')
		[void]$reproSteps.Add('Match the same target scope, connectivity state, and preflight warnings before retrying.')
		[void]$reproSteps.Add('Capture a fresh support bundle immediately after the failure or deviation.')

		$incident = [ordered]@{
			Schema            = 'Baseline.IncidentRepro'
			SchemaVersion     = 1
			IncidentId        = if ([string]::IsNullOrWhiteSpace($IncidentId)) { [guid]::NewGuid().ToString('N') } else { $IncidentId }
			GeneratedAt       = [System.DateTime]::UtcNow.ToString('o')
			SupportBundlePath = $resolvedBundlePath
			BaselineVersion   = if ($metadata -and $metadata.PSObject.Properties['BaselineVersion']) { [string]$metadata.BaselineVersion } else { $null }
			MachineName       = if ($metadata -and $metadata.PSObject.Properties['MachineName']) { [string]$metadata.MachineName } else { $null }
			UserName          = if ($metadata -and $metadata.PSObject.Properties['UserName']) { [string]$metadata.UserName } else { $null }
			OS                = if ($metadata -and $metadata.PSObject.Properties['OS']) { [string]$metadata.OS } else { $null }
			ProfilePath       = if ($metadata -and $metadata.PSObject.Properties['ProfilePath']) { [string]$metadata.ProfilePath } else { $null }
			AuditRetention    = if ($metadata -and $metadata.PSObject.Properties['AuditRetention']) { $metadata.AuditRetention } else { $null }
			ValidationEvidence = if ($validationEvidence) { $validationEvidence } else { $null }
			PreflightWarnings = @($warningDetails)
			DeepLinks         = @($deepLinks)
			RecentAudit        = @($recentAudit | Select-Object -First 10)
			RecommendedSteps   = @($reproSteps)
			Attachments        = @(
				'metadata.json'
				'preflight-report.json'
				'compliance-report.json'
				'validation-evidence.json'
				'audit.jsonl'
			) | Where-Object { Test-Path -LiteralPath (Join-Path $bundleRoot $_) }
		}

		$jsonPath = Join-Path $resolvedOutput 'incident-reproduction.json'
		$mdPath = Join-Path $resolvedOutput 'incident-reproduction.md'
		[System.IO.File]::WriteAllText($jsonPath, ($incident | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

		$md = [System.Collections.Generic.List[string]]::new()
		[void]$md.Add('# Baseline Incident Reproduction Pack')
		[void]$md.Add('')
		[void]$md.Add(('Incident ID: {0}' -f $incident.IncidentId))
		[void]$md.Add(('Support bundle: {0}' -f $incident.SupportBundlePath))
		[void]$md.Add(('Baseline version: {0}' -f $(if ($incident.BaselineVersion) { $incident.BaselineVersion } else { 'unknown' })))
		[void]$md.Add(('Machine: {0}' -f $(if ($incident.MachineName) { $incident.MachineName } else { 'unknown' })))
		if ($incident.ValidationEvidence -and $incident.ValidationEvidence.Summary)
		{
			[void]$md.Add(('Validation evidence: {0}' -f [string]$incident.ValidationEvidence.Summary))
		}
		[void]$md.Add('')
		[void]$md.Add('## Reproduction Steps')
		foreach ($step in @($incident.RecommendedSteps))
		{
			[void]$md.Add(('- {0}' -f $step))
		}
		if ($incident.PreflightWarnings.Count -gt 0)
		{
			[void]$md.Add('')
			[void]$md.Add('## Preflight Warnings')
			foreach ($warning in @($incident.PreflightWarnings))
			{
				[void]$md.Add(('- {0}' -f $warning))
			}
		}
		if ($incident.RecentAudit.Count -gt 0)
		{
			[void]$md.Add('')
			[void]$md.Add('## Recent Audit Events')
			foreach ($record in @($incident.RecentAudit))
			{
				$action = if ($record.PSObject.Properties['Action']) { [string]$record.Action } else { 'Unknown' }
				$mode = if ($record.PSObject.Properties['Mode']) { [string]$record.Mode } else { 'Unknown' }
				[void]$md.Add(('- {0} ({1})' -f $action, $mode))
			}
		}
		if ($incident.DeepLinks.Count -gt 0)
		{
			[void]$md.Add('')
			[void]$md.Add('## Deep Links')
			foreach ($link in @($incident.DeepLinks))
			{
				$targetName = if ($link.PSObject.Properties['ComputerName'] -and $link.ComputerName) { [string]$link.ComputerName } else { 'unknown target' }
				$targetState = if ($link.PSObject.Properties['TargetState'] -and $link.TargetState) { [string]$link.TargetState } else { 'Unknown' }
				$terminalState = if ($link.PSObject.Properties['TerminalState'] -and $link.TerminalState) { [string]$link.TerminalState } else { 'Unknown' }
				[void]$md.Add(('- {0} | State: {1} | Terminal: {2}' -f $targetName, $targetState, $terminalState))
				if ($link.PSObject.Properties['Artifacts'] -and $link.Artifacts)
				{
					[void]$md.Add(('  Artifacts: {0}' -f (@($link.Artifacts) -join ', ')))
				}
			}
		}
		[System.IO.File]::WriteAllText($mdPath, ($md -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

		return [pscustomobject]@{
			OutputDirectory = $resolvedOutput
			JsonPath        = $jsonPath
			MarkdownPath    = $mdPath
			IncidentId      = $incident.IncidentId
			BaselineVersion = $incident.BaselineVersion
			WarningCount    = @($incident.PreflightWarnings).Count
			AuditEventCount = @($incident.RecentAudit).Count
		}
	}
	finally
	{
		if ($createdTemp -and (Test-Path -LiteralPath $workRoot))
		{
			Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}
