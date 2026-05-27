try
	{
		$notifySupportBundleProgress = {
			param(
				[string]$Stage,
				[string]$Message
			)

			if (-not $ProgressCallback) { return }
			try
			{
				& $ProgressCallback -Stage $Stage -Message $Message
			}
			catch
			{
				Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.ProgressCallback' -Severity Debug
			}
		}.GetNewClosure()

		& $notifySupportBundleProgress -Stage 'Prepare' -Message 'Preparing support bundle staging area...'
		$null = New-Item -Path $stagingDir -ItemType Directory -Force

		& $notifySupportBundleProgress -Stage 'Version' -Message 'Collecting Baseline version metadata...'
		$baselineVersion = $null
		if (Get-Command -Name 'Get-BaselineDisplayVersion' -ErrorAction SilentlyContinue)
		{
			try { $baselineVersion = Get-BaselineDisplayVersion } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:27' -Severity Debug }
			 $baselineVersion = $null }
		}

		& $notifySupportBundleProgress -Stage 'FeatureMaturity' -Message 'Collecting feature maturity metadata...'
		$maturityManifest = @($Manifest)
		if ($maturityManifest.Count -eq 0 -and (Get-Command -Name 'Import-TweakManifestFromData' -ErrorAction SilentlyContinue))
		{
			try { $maturityManifest = @(Import-TweakManifestFromData) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:34' -Severity Debug }
			 $maturityManifest = @() }
		}

		$featureMaturityReport = $null
		if (Get-Command -Name 'Get-BaselineFeatureMaturityReport' -ErrorAction SilentlyContinue)
		{
			try { $featureMaturityReport = Get-BaselineFeatureMaturityReport -Manifest $maturityManifest } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:40' -Severity Debug }
			 $featureMaturityReport = $null }
		}

		$validationEvidenceReport = $null
		if (Get-Command -Name 'Get-BaselineValidationEvidenceReport' -ErrorAction SilentlyContinue)
		{
			& $notifySupportBundleProgress -Stage 'ValidationEvidence' -Message 'Collecting validation evidence...'
			$validationEvidenceRoot = $null
			if (Get-Command -Name 'Get-BaselineSupportBundleValidationEvidenceRoot' -ErrorAction SilentlyContinue)
			{
				try { $validationEvidenceRoot = Get-BaselineSupportBundleValidationEvidenceRoot } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:50' -Severity Debug }
				 $validationEvidenceRoot = $null }
			}
			try
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$validationEvidenceRoot))
				{
					$validationEvidenceReport = Get-BaselineValidationEvidenceReport -RepoRoot $validationEvidenceRoot
				}
				else
				{
					$validationEvidenceReport = Get-BaselineValidationEvidenceReport
				}
			}
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:63' -Severity Debug }
			 $validationEvidenceReport = $null }
		}

		$windowsUpdateStatusForBundle = $WindowsUpdateStatus
		if ($null -eq $windowsUpdateStatusForBundle)
		{
			& $notifySupportBundleProgress -Stage 'WindowsUpdate' -Message 'Recording Windows Update status snapshot...'
			$windowsUpdateStatusForBundle = New-BaselineSupportBundleWindowsUpdateStatusNotCollected
		}
		else
		{
			& $notifySupportBundleProgress -Stage 'WindowsUpdate' -Message 'Recording supplied Windows Update status snapshot...'
		}

		$windowsUpdateStatusSucceeded = $null
		$windowsUpdateSummary = $null
		if ($null -ne $windowsUpdateStatusForBundle)
		{
			if ($windowsUpdateStatusForBundle.PSObject.Properties['Succeeded'])
			{
				$windowsUpdateStatusSucceeded = [bool]$windowsUpdateStatusForBundle.Succeeded
			}
			if ($windowsUpdateStatusForBundle.PSObject.Properties['Summary'])
			{
				$windowsUpdateSummary = $windowsUpdateStatusForBundle.Summary
			}
		}

		$activeRunId = $null
		if (Get-Command -Name 'Get-BaselineRunId' -ErrorAction SilentlyContinue)
		{
			try { $activeRunId = [string](Get-BaselineRunId) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:94' -Severity Debug }
			 $activeRunId = $null }
		}
		$globalRunIdVariable = Get-Variable -Name 'BaselineRunId' -Scope Global -ErrorAction SilentlyContinue
		if ([string]::IsNullOrWhiteSpace($activeRunId) -and $globalRunIdVariable -and $globalRunIdVariable.Value)
		{
			$activeRunId = [string]$globalRunIdVariable.Value
		}

		& $notifySupportBundleProgress -Stage 'Metadata' -Message 'Writing support bundle metadata...'
		$selectedSessionLogPath = $null
		if (-not [string]::IsNullOrWhiteSpace($SessionLogPath))
		{
			try
			{
				$candidateSessionLogPath = [System.IO.Path]::GetFullPath([string]$SessionLogPath)
				if (Test-Path -LiteralPath $candidateSessionLogPath -PathType Leaf)
				{
					$selectedSessionLogPath = $candidateSessionLogPath
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:114' -Severity Debug }

				$selectedSessionLogPath = $null
			}
		}

		$metadata = [ordered]@{
			Schema          = 'Baseline.SupportBundle'
			SchemaVersion   = 2
			GeneratedAt     = [System.DateTime]::UtcNow.ToString('o')
			RunId           = $activeRunId
			MachineName     = $env:COMPUTERNAME
			UserName        = $env:USERNAME
			BaselineVersion = $baselineVersion
			PowerShell      = [ordered]@{
				Edition = $PSVersionTable.PSEdition
				Version = $PSVersionTable.PSVersion.ToString()
			}
			OS              = [System.Environment]::OSVersion.VersionString
			OutputFile      = [System.IO.Path]::GetFileName($OutputPath)
			ProfilePath     = $ProfilePath
			SelectedSessionLog = if ($selectedSessionLogPath) {
				[ordered]@{
					SourcePath     = $selectedSessionLogPath
					SourceFileName = [System.IO.Path]::GetFileName($selectedSessionLogPath)
				}
			} else { $null }
			AuditRetention  = [ordered]@{
				Days   = [int]$AuditRetentionDays
				Cutoff = (Get-Date).AddDays(-1 * [int]$AuditRetentionDays).ToString('o')
			}
			FeatureMaturitySummary = if ($featureMaturityReport) { $featureMaturityReport.Summary } else { $null }
			ValidationEvidenceSummary = if ($validationEvidenceReport) { $validationEvidenceReport.Summary } else { $null }
			ValidationEvidenceChannels = if ($validationEvidenceReport) { @($validationEvidenceReport.ValidationChannels) } else { @() }
			WindowsUpdateStatusSucceeded = $windowsUpdateStatusSucceeded
			WindowsUpdateSummary = $windowsUpdateSummary
			Immutable       = [bool]$Immutable
			SignoffBundle   = [bool]$Immutable
		}

		# --- Reproduction context: action sequence + CLI args ---
		# Caller hands us a hashtable / pscustomobject with optional
		# ActionSequence (string[]) and CommandLineArgs (string[]). Both are
		# emitted under metadata.ReproductionContext so a maintainer can
		# replay the user's path. ActionSequence comes from the in-process
		# action trail in Logging.psm1; CommandLineArgs is captured at
		# bootstrap. Either may be empty/null without breaking the bundle.
		$reproContext = $null
		if ($null -ne $ReproductionContext)
		{
			$actionTrail = @()
			$cliArgs = @()
			$reproProps = $ReproductionContext.PSObject.Properties
			if ($reproProps['ActionSequence']) { $actionTrail = @($ReproductionContext.ActionSequence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
			if ($reproProps['CommandLineArgs']) { $cliArgs = @($ReproductionContext.CommandLineArgs | Where-Object { $null -ne $_ }) }
			$reproContext = [ordered]@{
				ActionSequence  = $actionTrail
				CommandLineArgs = $cliArgs
			}
		}
		else
		{
			# Auto-pull from Logging if available so callers that don't pass
			# explicit context still get the action trail.
			$autoTrail = @()
			if (Get-Command -Name 'Get-BaselineActionTrail' -ErrorAction SilentlyContinue)
			{
				try { $autoTrail = @(Get-BaselineActionTrail) } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:181' -Severity Debug }
				 $autoTrail = @() }
			}
			$autoCli = @()
			$globalCliVariable = Get-Variable -Name 'BaselineCommandLineArgs' -Scope Global -ErrorAction SilentlyContinue
			if ($globalCliVariable -and $globalCliVariable.Value) { $autoCli = @($globalCliVariable.Value) }
			if ($autoTrail.Count -gt 0 -or $autoCli.Count -gt 0)
			{
				$reproContext = [ordered]@{
					ActionSequence  = $autoTrail
					CommandLineArgs = $autoCli
				}
			}
		}
		if ($null -ne $reproContext)
		{
			$metadata['ReproductionContext'] = $reproContext
		}

		if ($Immutable)
		{
			$metadata['SignoffProvenance'] = [ordered]@{
				Reason       = if (-not [string]::IsNullOrWhiteSpace($SignoffReason)) { $SignoffReason } else { 'Enterprise signoff bundle' }
				SignedBy     = $env:USERNAME
				SignedOn     = $env:COMPUTERNAME
				SignedAt     = [System.DateTime]::UtcNow.ToString('o')
				Domain       = $env:USERDOMAIN
			}
		}

		$metadataPath = Join-Path $stagingDir 'metadata.json'
		[System.IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json -Depth 8), $utf8NoBom)
		$bundleEntries.Add([pscustomobject]@{ Name = 'metadata.json'; Source = $metadataPath })

		$bundleIndex = [ordered]@{
			Schema        = 'Baseline.SupportBundleIndex'
			SchemaVersion = 1
			GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
			Files         = [ordered]@{
				Metadata = 'metadata.json'
			}
		}

		try
		{
			$versionInfo = New-BaselineSupportBundleVersionInfo -BaselineVersion $baselineVersion
			$versionInfoPath = Join-Path $stagingDir 'baseline-version.json'
			[System.IO.File]::WriteAllText($versionInfoPath, ($versionInfo | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'baseline-version.json'; Source = $versionInfoPath })
			$bundleIndex.Files['BaselineVersion'] = 'baseline-version.json'
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.BaselineVersion' -Severity Warning }

		try
		{
			& $notifySupportBundleProgress -Stage 'Environment' -Message 'Collecting environment details...'
			$environmentInfo = New-BaselineSupportBundleEnvironmentInfo
			$environmentInfoPath = Join-Path $stagingDir 'environment.json'
			[System.IO.File]::WriteAllText($environmentInfoPath, ($environmentInfo | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'environment.json'; Source = $environmentInfoPath })
			$bundleIndex.Files['Environment'] = 'environment.json'
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.Environment' -Severity Warning }

		try
		{
			& $notifySupportBundleProgress -Stage 'WindowsFeatures' -Message 'Collecting Windows feature and service state...'
			$windowsFeatures = New-BaselineSupportBundleWindowsFeatures -ProgressCallback $notifySupportBundleProgress
			$windowsFeaturesPath = Join-Path $stagingDir 'windows-features.json'
			[System.IO.File]::WriteAllText($windowsFeaturesPath, ($windowsFeatures | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'windows-features.json'; Source = $windowsFeaturesPath })
			$bundleIndex.Files['WindowsFeatures'] = 'windows-features.json'
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.WindowsFeatures' -Severity Warning }

		try
		{
			& $notifySupportBundleProgress -Stage 'StorageSummary' -Message 'Collecting Baseline storage summary...'
			$storageSummary = New-BaselineSupportBundleStorageSummary
			$storageSummaryPath = Join-Path $stagingDir 'storage-summary.json'
			[System.IO.File]::WriteAllText($storageSummaryPath, ($storageSummary | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'storage-summary.json'; Source = $storageSummaryPath })
			$bundleIndex.Files['StorageSummary'] = 'storage-summary.json'
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.StorageSummary' -Severity Warning }

		try
		{
			& $notifySupportBundleProgress -Stage 'UserActionContext' -Message 'Collecting GUI session context...'
			$userActionContext = New-BaselineSupportBundleUserActionContext -ProfilePath $ProfilePath -ReproductionContext $reproContext -ConfigStatePre $ConfigStatePre -ConfigStatePost $ConfigStatePost
			$userActionContextPath = Join-Path $stagingDir 'user-action-context.json'
			[System.IO.File]::WriteAllText($userActionContextPath, ($userActionContext | ConvertTo-Json -Depth 10), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'user-action-context.json'; Source = $userActionContextPath })
			$bundleIndex.Files['UserActionContext'] = 'user-action-context.json'
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.UserActionContext' -Severity Warning }

		if ($featureMaturityReport)
		{
			$featureMaturityPath = Join-Path $stagingDir 'feature-maturity.json'
			[System.IO.File]::WriteAllText($featureMaturityPath, ($featureMaturityReport | ConvertTo-Json -Depth 10), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'feature-maturity.json'; Source = $featureMaturityPath })
			$bundleIndex.Files['FeatureMaturity'] = 'feature-maturity.json'
		}

		if ($validationEvidenceReport)
		{
			$validationEvidencePath = Join-Path $stagingDir 'validation-evidence.json'
			[System.IO.File]::WriteAllText($validationEvidencePath, ($validationEvidenceReport | ConvertTo-Json -Depth 10), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'validation-evidence.json'; Source = $validationEvidencePath })
			$bundleIndex.Files['ValidationEvidence'] = 'validation-evidence.json'
		}

		if ($null -ne $windowsUpdateStatusForBundle)
		{
			$windowsUpdateStatusPath = Join-Path $stagingDir 'windows-update-status.json'
			[System.IO.File]::WriteAllText($windowsUpdateStatusPath, ($windowsUpdateStatusForBundle | ConvertTo-Json -Depth 10), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'windows-update-status.json'; Source = $windowsUpdateStatusPath })
			$bundleIndex.Files['WindowsUpdateStatus'] = 'windows-update-status.json'
		}

		$deepLinkItems = [System.Collections.Generic.List[pscustomobject]]::new()
		if ((($deepLinkFilters.RunId.Count -gt 0) -or ($deepLinkFilters.ComputerName.Count -gt 0) -or ($deepLinkFilters.Operation.Count -gt 0)) -and (Get-Command -Name 'Get-BaselineSupportBundleDeepLinks' -ErrorAction SilentlyContinue))
		{
			try
			{
				$deepLinkItems = [System.Collections.Generic.List[pscustomobject]]::new()
				$links = Get-BaselineSupportBundleDeepLinks -RunId $deepLinkFilters.RunId -ComputerName $deepLinkFilters.ComputerName -Operation $deepLinkFilters.Operation
				foreach ($link in @($links))
				{
					if ($null -ne $link) { [void]$deepLinkItems.Add($link) }
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:313' -Severity Debug }

				$deepLinkItems = [System.Collections.Generic.List[pscustomobject]]::new()
			}
		}

		if ($IncludeAuditLog)
		{
			& $notifySupportBundleProgress -Stage 'AuditLog' -Message 'Collecting audit log records...'
			$auditLogPath = Get-AuditLogPath
			if (Test-Path -LiteralPath $auditLogPath)
			{
				$destAuditLogPath = Join-Path $stagingDir 'audit.jsonl'
				$auditRecords = @()
				try
				{
					$auditRecords = @(Get-AuditLog -Since (Get-Date).AddDays(-1 * [int]$AuditRetentionDays) -MaxRecords 10000)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:331' -Severity Debug }

					$auditRecords = @()
				}

				if ($auditRecords.Count -gt 0)
				{
					$lines = foreach ($record in $auditRecords) { $record | ConvertTo-Json -Compress -Depth 6 }
					[System.IO.File]::WriteAllLines($destAuditLogPath, $lines, $utf8NoBom)
				}
				else
				{
					Copy-Item -LiteralPath $auditLogPath -Destination $destAuditLogPath -Force
				}
				$bundleEntries.Add([pscustomobject]@{ Name = 'audit.jsonl'; Source = $destAuditLogPath })
				$bundleIndex.Files['Audit'] = 'audit.jsonl'
			}
		}

		$remoteHistoryPath = $null
		$getRemoteHistoryPathCommand = Get-Command -Name 'Get-BaselineRemoteOrchestrationHistoryPath' -ErrorAction SilentlyContinue
		if ($getRemoteHistoryPathCommand)
		{
			try { $remoteHistoryPath = & $getRemoteHistoryPathCommand } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:354' -Severity Debug }
			 $remoteHistoryPath = $null }
		}
		if ([string]::IsNullOrWhiteSpace($remoteHistoryPath))
		{
			$remoteHistoryPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Baseline') 'remote-orchestration.jsonl'
		}

		if (-not [string]::IsNullOrWhiteSpace($remoteHistoryPath) -and (Test-Path -LiteralPath $remoteHistoryPath))
		{
			& $notifySupportBundleProgress -Stage 'RemoteHistory' -Message 'Collecting remote orchestration history...'
			$destRemoteHistoryPath = Join-Path $stagingDir 'remote-orchestration.jsonl'
			Copy-Item -LiteralPath $remoteHistoryPath -Destination $destRemoteHistoryPath -Force
			$bundleEntries.Add([pscustomobject]@{ Name = 'remote-orchestration.jsonl'; Source = $destRemoteHistoryPath })
			$bundleIndex.Files['RemoteHistory'] = 'remote-orchestration.jsonl'

			$remoteHistorySummary = @()
			$getRemoteHistorySummaryCommand = Get-Command -Name 'Get-BaselineRemoteOrchestrationSummary' -ErrorAction SilentlyContinue
			if ($getRemoteHistorySummaryCommand)
			{
				try
				{
					$remoteHistorySummary = @(& $getRemoteHistorySummaryCommand -MaxRecords 25)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:377' -Severity Debug }

					$remoteHistorySummary = @()
				}
			}
			if ($remoteHistorySummary.Count -eq 0)
			{
				$remoteHistorySummary = [System.Collections.Generic.List[string]]::new()
				try
				{
					$historyLines = [System.IO.File]::ReadAllLines($remoteHistoryPath, [System.Text.UTF8Encoding]::new($false))
					foreach ($line in $historyLines)
					{
						if ([string]::IsNullOrWhiteSpace($line)) { continue }
						try
						{
							$record = $line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:395' -Severity Debug }

							continue
						}

						$stamp = $null
						try { $stamp = ([datetime]::Parse([string]$record.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:401' -Severity Debug }
						 $stamp = [string]$record.Timestamp }
						$status = if ($record.Status) { [string]$record.Status } else { 'Unknown' }
						$target = if ($record.ComputerName) { [string]$record.ComputerName } else { 'unknown target' }
						$operation = if ($record.Operation) { [string]$record.Operation } else { 'Remote' }
						$retry = if ($record.Retryable -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$record.RetryReason)) { ' | Retryable: {0}' -f [string]$record.RetryReason } else { '' }
						[void]$remoteHistorySummary.Add(('{0} | {1} | {2} | {3}{4}' -f $stamp, $operation, $target, $status, $retry))
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:409' -Severity Debug }

					$remoteHistorySummary = @()
				}
			}

			if ($remoteHistorySummary.Count -gt 0)
			{
				$remoteSummaryPath = Join-Path $stagingDir 'remote-orchestration-summary.txt'
				[System.IO.File]::WriteAllLines($remoteSummaryPath, $remoteHistorySummary, $utf8NoBom)
				$bundleEntries.Add([pscustomobject]@{ Name = 'remote-orchestration-summary.txt'; Source = $remoteSummaryPath })
				$bundleIndex.Files['RemoteSummary'] = 'remote-orchestration-summary.txt'
			}

			$remoteRunSummaries = @()
			$getRemoteRunSummariesCommand = Get-Command -Name 'Get-BaselineRemoteRunSummaries' -ErrorAction SilentlyContinue
			if ($getRemoteRunSummariesCommand)
			{
				try
				{
					$remoteRunSummaries = @(& $getRemoteRunSummariesCommand -MaxRecords 100)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:431' -Severity Debug }

					$remoteRunSummaries = @()
				}
			}

			if ($remoteRunSummaries.Count -gt 0)
			{
				$remoteRunSummariesPath = Join-Path $stagingDir 'remote-orchestration-runs.json'
				[System.IO.File]::WriteAllText($remoteRunSummariesPath, ($remoteRunSummaries | ConvertTo-Json -Depth 8), $utf8NoBom)
				$bundleEntries.Add([pscustomobject]@{ Name = 'remote-orchestration-runs.json'; Source = $remoteRunSummariesPath })
				$bundleIndex.Files['RemoteRuns'] = 'remote-orchestration-runs.json'
			}

			$remoteReconciliation = $null
			try
			{
				$recentRemoteRuns = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords 100)
				if ($recentRemoteRuns.Count -eq 0)
				{
					$fallbackRemoteRuns = [System.Collections.Generic.List[object]]::new()
					$historyLines = [System.IO.File]::ReadAllLines($remoteHistoryPath, [System.Text.UTF8Encoding]::new($false))
					foreach ($line in $historyLines)
					{
						if ([string]::IsNullOrWhiteSpace($line)) { continue }
						try
						{
							[void]$fallbackRemoteRuns.Add(($line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop))
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:460' -Severity Debug }

							continue
						}
					}
					$recentRemoteRuns = @($fallbackRemoteRuns)
				}
				if ($recentRemoteRuns.Count -gt 0)
				{
					$remoteReconciliation = Get-BaselineRemoteOrchestrationReconciliation -Records $recentRemoteRuns
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:472' -Severity Debug }

				$remoteReconciliation = $null
			}

			if ($null -ne $remoteReconciliation)
			{
				$remoteReconciliationPath = Join-Path $stagingDir 'remote-orchestration-reconciliation.json'
				[System.IO.File]::WriteAllText($remoteReconciliationPath, ($remoteReconciliation | ConvertTo-Json -Depth 8), $utf8NoBom)
				$bundleEntries.Add([pscustomobject]@{ Name = 'remote-orchestration-reconciliation.json'; Source = $remoteReconciliationPath })
				$bundleIndex.Files['RemoteReconciliation'] = 'remote-orchestration-reconciliation.json'
			}

			$remoteDetails = @()
			$getRemoteHistoryDetailsCommand = Get-Command -Name 'Get-BaselineRemoteOrchestrationDetails' -ErrorAction SilentlyContinue
			if ($getRemoteHistoryDetailsCommand)
			{
				try
				{
					$remoteDetails = @(& $getRemoteHistoryDetailsCommand -MaxRecords 100)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:493' -Severity Debug }

					$remoteDetails = @()
				}
			}
			if ($remoteDetails.Count -eq 0)
			{
				try
				{
					$historyLines = [System.IO.File]::ReadAllLines($remoteHistoryPath, [System.Text.UTF8Encoding]::new($false))
					foreach ($line in $historyLines)
					{
						if ([string]::IsNullOrWhiteSpace($line)) { continue }
						try
						{
							$record = $line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:510' -Severity Debug }

							continue
						}

						$errors = @()
						if ($record.PSObject.Properties['Errors'] -and $record.Errors)
						{
							$errors = @($record.Errors | ForEach-Object { [string]$_ })
						}

						$remoteDetails += [pscustomobject]@{
							Timestamp       = if ($record.PSObject.Properties['Timestamp']) { [string]$record.Timestamp } else { $null }
							ComputerName    = if ($record.PSObject.Properties['ComputerName'] -and $record.ComputerName) { [string]$record.ComputerName } else { 'unknown target' }
							Operation       = if ($record.PSObject.Properties['Operation'] -and $record.Operation) { [string]$record.Operation } else { 'Remote' }
							Status          = if ($record.PSObject.Properties['Status'] -and $record.Status) { [string]$record.Status } else { 'Unknown' }
							LifecycleState  = if ($record.PSObject.Properties['LifecycleState'] -and $record.LifecycleState) { [string]$record.LifecycleState } else { 'Unknown' }
							RunId           = if ($record.PSObject.Properties['RunId'] -and $record.RunId) { [string]$record.RunId } else { $null }
							AttemptCount    = if ($record.PSObject.Properties['AttemptCount']) { [int]$record.AttemptCount } else { 1 }
							RetryCount      = if ($record.PSObject.Properties['RetryCount']) { [int]$record.RetryCount } else { 0 }
							SessionState    = if ($record.PSObject.Properties['SessionState']) { [string]$record.SessionState } else { 'Unknown' }
							SessionReused   = if ($record.PSObject.Properties['SessionReused']) { [bool]$record.SessionReused } else { $false }
							Retryable       = if ($record.PSObject.Properties['Retryable']) { [bool]$record.Retryable } else { $false }
							RetryReason     = if ($record.PSObject.Properties['RetryReason']) { [string]$record.RetryReason } else { $null }
							FailureCategory = if ($record.PSObject.Properties['FailureCategory']) { [string]$record.FailureCategory } else { 'Unknown' }
							Errors          = @($errors)
						}
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:539' -Severity Debug }

					$remoteDetails = @()
				}
			}

			if ($remoteDetails.Count -gt 0)
			{
				$remoteDetailsPath = Join-Path $stagingDir 'remote-orchestration-details.json'
				[System.IO.File]::WriteAllText($remoteDetailsPath, ($remoteDetails | ConvertTo-Json -Depth 8), $utf8NoBom)
				$bundleEntries.Add([pscustomobject]@{ Name = 'remote-orchestration-details.json'; Source = $remoteDetailsPath })
				$bundleIndex.Files['RemoteDetails'] = 'remote-orchestration-details.json'
			}
		}

		# --- Connect-to-Computer dialog pre-flight results ---
		# Snapshot of the most recent Test-BaselineRemoteConnectivity output
		# captured by the GUI dialog (Set-GuiRemoteConnectivityResults stores
		# this on the GUI context's Remote.LastConnectivityResults). Distinct from
		# remote-orchestration.jsonl, which only logs actual operations.
		if ($null -ne $ConnectivityResults -and $ConnectivityResults.Count -gt 0)
		{
			$connectivityPayload = [ordered]@{
				Schema        = 'Baseline.RemoteConnectivity'
				SchemaVersion = 1
				CapturedAt    = [System.DateTime]::UtcNow.ToString('o')
				Results       = @($ConnectivityResults)
			}
			$connectivityPath = Join-Path $stagingDir 'remote-connectivity.json'
			[System.IO.File]::WriteAllText($connectivityPath, ($connectivityPayload | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'remote-connectivity.json'; Source = $connectivityPath })
			$bundleIndex.Files['RemoteConnectivity'] = 'remote-connectivity.json'
		}

		if ($deepLinkItems.Count -gt 0)
		{
			$deepLinksPath = Join-Path $stagingDir 'remote-orchestration-deeplinks.json'
			[System.IO.File]::WriteAllText($deepLinksPath, ($deepLinkItems | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'remote-orchestration-deeplinks.json'; Source = $deepLinksPath })
			$bundleIndex.Files['RemoteDeepLinks'] = 'remote-orchestration-deeplinks.json'
			$bundleIndex.DeepLinks = @($deepLinkItems)
		}

		# --- Logs/ directory: daily baseline.log + perf.log ---
		# Both are best-effort. Bundle export must continue if either is locked
		# or missing. perf.log only exists when BASELINE_PERF_LOG=1 (or
		# Debug Mode is on, which force-enables it).
		$logsDir = Join-Path $stagingDir 'Logs'
		$null = New-Item -Path $logsDir -ItemType Directory -Force -ErrorAction SilentlyContinue
		try
		{
			& $notifySupportBundleProgress -Stage 'Logs' -Message 'Collecting Baseline log files...'
			$globalLogFileVariable = Get-Variable -Name 'LogFilePath' -Scope Global -ErrorAction SilentlyContinue
			$dailyLogPath = if ($selectedSessionLogPath) { $selectedSessionLogPath } elseif ($globalLogFileVariable -and $globalLogFileVariable.Value) { [string]$globalLogFileVariable.Value } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($dailyLogPath) -and (Test-Path -LiteralPath $dailyLogPath))
			{
				$destDailyLogPath = Join-Path $logsDir 'baseline.log'
				try
				{
					Copy-Item -LiteralPath $dailyLogPath -Destination $destDailyLogPath -Force -ErrorAction Stop
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:600' -Severity Debug }

					# File-locked fallback: stream-copy with FileShare.ReadWrite
					$fs = [System.IO.File]::Open($dailyLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
					try
					{
						$reader = [System.IO.StreamReader]::new($fs, [System.Text.UTF8Encoding]::new($false))
						try { [System.IO.File]::WriteAllText($destDailyLogPath, $reader.ReadToEnd(), $utf8NoBom) }
						finally { $reader.Dispose() }
					}
					finally { $fs.Dispose() }
				}
				$bundleEntries.Add([pscustomobject]@{ Name = 'Logs/baseline.log'; Source = $destDailyLogPath })
				$bundleIndex.Files['DailyLog'] = 'Logs/baseline.log'
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.DailyLog' -Severity Warning }

		try
		{
			$perfLogPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Temp\Baseline') 'perf.log'
			if (Test-Path -LiteralPath $perfLogPath)
			{
				$destPerfLogPath = Join-Path $logsDir 'perf.log'
				Copy-Item -LiteralPath $perfLogPath -Destination $destPerfLogPath -Force -ErrorAction SilentlyContinue
				if (Test-Path -LiteralPath $destPerfLogPath)
				{
					$bundleEntries.Add([pscustomobject]@{ Name = 'Logs/perf.log'; Source = $destPerfLogPath })
					$bundleIndex.Files['PerfLog'] = 'Logs/perf.log'
				}
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.PerfLog' -Severity Warning }

		try
		{
			$launchTracePath = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline') 'Baseline-launch-trace.txt'
			if (Test-Path -LiteralPath $launchTracePath)
			{
				$destLaunchTracePath = Join-Path $logsDir 'Baseline-launch-trace.txt'
				Copy-Item -LiteralPath $launchTracePath -Destination $destLaunchTracePath -Force -ErrorAction SilentlyContinue
				if (Test-Path -LiteralPath $destLaunchTracePath)
				{
					$bundleEntries.Add([pscustomobject]@{ Name = 'Logs/Baseline-launch-trace.txt'; Source = $destLaunchTracePath })
					$bundleIndex.Files['LaunchTrace'] = 'Logs/Baseline-launch-trace.txt'
				}
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.LaunchTrace' -Severity Warning }

		# --- system-info.json: richer environment context than metadata.json ---
		try
		{
			& $notifySupportBundleProgress -Stage 'SystemInfo' -Message 'Collecting detailed system information...'
			$systemInfo = New-BaselineSupportBundleSystemInfo
			$systemInfoPath = Join-Path $stagingDir 'system-info.json'
			[System.IO.File]::WriteAllText($systemInfoPath, ($systemInfo | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'system-info.json'; Source = $systemInfoPath })
			$bundleIndex.Files['SystemInfo'] = 'system-info.json'
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.SystemInfo' -Severity Warning }

		# --- execution-summary.json: per-run statistics from the live session ---
		try
		{
			if (Get-Command -Name 'Get-SessionStatistics' -ErrorAction SilentlyContinue)
			{
				$stats = Get-SessionStatistics
				if ($stats)
				{
					$execSummary = [ordered]@{
						Schema        = 'Baseline.ExecutionSummary'
						SchemaVersion = 1
						GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
						DebugMode     = if (Get-Command -Name 'Get-BaselineDebugLogging' -ErrorAction SilentlyContinue) { [bool](Get-BaselineDebugLogging) } else { $false }
						Statistics    = $stats
					}
					$execSummaryPath = Join-Path $stagingDir 'execution-summary.json'
					[System.IO.File]::WriteAllText($execSummaryPath, ($execSummary | ConvertTo-Json -Depth 8), $utf8NoBom)
					$bundleEntries.Add([pscustomobject]@{ Name = 'execution-summary.json'; Source = $execSummaryPath })
					$bundleIndex.Files['ExecutionSummary'] = 'execution-summary.json'
				}
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.ExecutionSummary' -Severity Warning }

		# --- ConfigState.json: GUI / preset / mode state, before/after a run ---
		# Pre-run state is captured by ExecutionOrchestration.ps1 into
		# the pre-run config snapshot; post-run state is the live snapshot at
		# bundle time. If no run has happened this session, only Post is
		# populated and the diff is null. Field selection follows todo.md #14
		# (preset, overrides, Safe Mode, Onboarding, Game Mode, Preview Run).
		try
		{
			if ($null -ne $ConfigStatePre -or $null -ne $ConfigStatePost)
			{
				$configStatePayload = New-BaselineSupportBundleConfigState -PreState $ConfigStatePre -PostState $ConfigStatePost
				if ($configStatePayload)
				{
					$configStatePath = Join-Path $stagingDir 'ConfigState.json'
					[System.IO.File]::WriteAllText($configStatePath, ($configStatePayload | ConvertTo-Json -Depth 10), $utf8NoBom)
					$bundleEntries.Add([pscustomobject]@{ Name = 'ConfigState.json'; Source = $configStatePath })
					$bundleIndex.Files['ConfigState'] = 'ConfigState.json'
				}
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.ConfigState' -Severity Warning }

		# --- RemoteTargets.json: per-target redacted detail ---
		# Sanitized projection of the live remote-target context: hostname only
		# (no FQDN, no domain leak), connection method, state, credential type
		# only (never the secret). Distinct from remote-connectivity.json (which
		# is the dialog's pre-flight test results) and remote-orchestration.jsonl
		# (which is the per-operation history).
		try
		{
			if ($null -ne $RemoteTargets -and $RemoteTargets.Count -gt 0)
			{
				$remoteTargetsPayload = New-BaselineSupportBundleRemoteTargets -Targets $RemoteTargets
				if ($remoteTargetsPayload)
				{
					$remoteTargetsPath = Join-Path $stagingDir 'RemoteTargets.json'
					[System.IO.File]::WriteAllText($remoteTargetsPath, ($remoteTargetsPayload | ConvertTo-Json -Depth 6), $utf8NoBom)
					$bundleEntries.Add([pscustomobject]@{ Name = 'RemoteTargets.json'; Source = $remoteTargetsPath })
					$bundleIndex.Files['RemoteTargets'] = 'RemoteTargets.json'
				}
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.RemoteTargets' -Severity Warning }

		# --- errors.json: classified errors scraped from the daily log ---
		try
		{
			$globalLogFileVariable = Get-Variable -Name 'LogFilePath' -Scope Global -ErrorAction SilentlyContinue
			$dailyLogPath = if ($selectedSessionLogPath) { $selectedSessionLogPath } elseif ($globalLogFileVariable -and $globalLogFileVariable.Value) { [string]$globalLogFileVariable.Value } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($dailyLogPath) -and (Test-Path -LiteralPath $dailyLogPath))
			{
				$classified = Get-BaselineSupportBundleClassifiedErrors -LogPath $dailyLogPath -MaxErrors 20
				if ($classified -and $classified.Errors.Count -gt 0)
				{
					$errorsPath = Join-Path $stagingDir 'errors.json'
					[System.IO.File]::WriteAllText($errorsPath, ($classified | ConvertTo-Json -Depth 6), $utf8NoBom)
					$bundleEntries.Add([pscustomobject]@{ Name = 'errors.json'; Source = $errorsPath })
					$bundleIndex.Files['Errors'] = 'errors.json'
				}
			}
		}
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.Errors' -Severity Warning }

		$bundleIndexPath = Join-Path $stagingDir 'bundle-index.json'
		[System.IO.File]::WriteAllText($bundleIndexPath, ($bundleIndex | ConvertTo-Json -Depth 8), $utf8NoBom)
		$bundleEntries.Add([pscustomobject]@{ Name = 'bundle-index.json'; Source = $bundleIndexPath })

		if (-not [string]::IsNullOrWhiteSpace($ProfilePath) -and (Test-Path -LiteralPath $ProfilePath))
		{
			$destProfilePath = Join-Path $stagingDir (Split-Path -Path $ProfilePath -Leaf)
			Copy-Item -LiteralPath $ProfilePath -Destination $destProfilePath -Force
			$bundleEntries.Add([pscustomobject]@{ Name = (Split-Path -Path $ProfilePath -Leaf); Source = $destProfilePath })
		}

		if ($null -eq $SystemSnapshot -and $Manifest)
		{
			try
			{
				& $notifySupportBundleProgress -Stage 'SystemSnapshot' -Message 'Capturing system state snapshot...'
				$SystemSnapshot = New-SystemStateSnapshot -Manifest $Manifest
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:767' -Severity Debug }

				$SystemSnapshot = $null
			}
		}

		if ($null -ne $SystemSnapshot)
		{
			$snapshotPath = Join-Path $stagingDir 'system-state-snapshot.json'
			Export-SystemStateSnapshot -Snapshot $SystemSnapshot -Path $snapshotPath
			$bundleEntries.Add([pscustomobject]@{ Name = 'system-state-snapshot.json'; Source = $snapshotPath })
		}

		# --- SnapshotDiff.json: pre/post field-level diff ---
		# Catches unintended side-effects from a run and verifies rollback
		# completeness. Emits the snapshot pair plus the diff. If only one
		# side is supplied, that side is still embedded so a maintainer can
		# eyeball the captured state without the diff.
		if ($null -ne $PreSnapshot -or $null -ne $PostSnapshot)
		{
			try
			{
				& $notifySupportBundleProgress -Stage 'SnapshotDiff' -Message 'Writing run snapshot diff...'
				$diff = $null
				if ($null -ne $PreSnapshot -and $null -ne $PostSnapshot -and (Get-Command -Name 'Compare-SystemStateSnapshots' -ErrorAction SilentlyContinue))
				{
					try { $diff = Compare-SystemStateSnapshots -Before $PreSnapshot -After $PostSnapshot } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:793' -Severity Debug }
					 $diff = $null }
				}

				$snapshotDiffPayload = [ordered]@{
					Schema        = 'Baseline.SnapshotDiff'
					SchemaVersion = 1
					GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
					HasPre        = ($null -ne $PreSnapshot)
					HasPost       = ($null -ne $PostSnapshot)
					Pre           = $PreSnapshot
					Post          = $PostSnapshot
					Diff          = if ($diff) {
						[ordered]@{
							AddedCount     = @($diff.Added).Count
							RemovedCount   = @($diff.Removed).Count
							ChangedCount   = @($diff.Changed).Count
							UnchangedCount = @($diff.Unchanged).Count
							Added          = @($diff.Added)
							Removed        = @($diff.Removed)
							Changed        = @($diff.Changed)
						}
					} else { $null }
				}

				$snapshotDiffPath = Join-Path $stagingDir 'SnapshotDiff.json'
				[System.IO.File]::WriteAllText($snapshotDiffPath, ($snapshotDiffPayload | ConvertTo-Json -Depth 10), $utf8NoBom)
				$bundleEntries.Add([pscustomobject]@{ Name = 'SnapshotDiff.json'; Source = $snapshotDiffPath })
				# bundle-index.json is already written by this point; SnapshotDiff
				# lands in contents.json (which is rewritten after every entry)
				# alongside the other optional artifacts (system-state-snapshot,
				# compliance-report, preflight-report).
			}
			catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.Assembly.SnapshotDiff' -Severity Warning }
		}

		if ($null -ne $ComplianceReport)
		{
			$compliancePath = Join-Path $stagingDir 'compliance-report.json'
			Export-ComplianceReport -Report $ComplianceReport -FilePath $compliancePath -Format Json
			$bundleEntries.Add([pscustomobject]@{ Name = 'compliance-report.json'; Source = $compliancePath })
		}

		$preflightCommand = Get-Command -Name 'Invoke-PreflightChecks' -ErrorAction SilentlyContinue
		if ($preflightCommand)
		{
			try
			{
				& $notifySupportBundleProgress -Stage 'Preflight' -Message 'Collecting preflight check report...'
				$preflightReport = & $preflightCommand
				if ($null -ne $preflightReport)
				{
					$preflightPath = Join-Path $stagingDir 'preflight-report.json'
					[System.IO.File]::WriteAllText($preflightPath, ($preflightReport | ConvertTo-Json -Depth 8), $utf8NoBom)
					$bundleEntries.Add([pscustomobject]@{ Name = 'preflight-report.json'; Source = $preflightPath })
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:849' -Severity Debug }

				# Preflight capture is best-effort and should not block bundle creation.
			}
		}

		if ($IncludeTestReport)
		{
			& $notifySupportBundleProgress -Stage 'TestReports' -Message 'Collecting test report artifacts...'
			$testReportsBundleDir = Join-Path $stagingDir 'TestReports'
			$testReportSources = New-Object 'System.Collections.Generic.List[object]'
			$testReportRoots = New-Object 'System.Collections.Generic.List[string]'
			$usedTestReportNames = @{}
			$usedTestReportPaths = @{}

			$addTestReportRoot = {
				param([string]$Root)

				if ([string]::IsNullOrWhiteSpace([string]$Root))
				{
					return
				}

				try
				{
					$resolvedRoot = [System.IO.Path]::GetFullPath([string]$Root)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:876' -Severity Debug }

					return
				}

				if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container))
				{
					return
				}

				foreach ($existingRoot in $testReportRoots)
				{
					if ([string]::Equals([string]$existingRoot, $resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase))
					{
						return
					}
				}

				[void]$testReportRoots.Add($resolvedRoot)
			}.GetNewClosure()

			$addTestReportSource = {
				param(
					[string]$Name,
					[string]$Path
				)

				if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf))
				{
					return
				}

				try
				{
					$resolvedPath = [System.IO.Path]::GetFullPath([string]$Path)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:912' -Severity Debug }

					return
				}

				$pathKey = $resolvedPath.ToLowerInvariant()
				if ($usedTestReportPaths.ContainsKey($pathKey))
				{
					return
				}

				$candidateName = if ([string]::IsNullOrWhiteSpace([string]$Name)) { [System.IO.Path]::GetFileName($resolvedPath) } else { [string]$Name }
				$nameExtension = [System.IO.Path]::GetExtension($candidateName)
				$nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($candidateName)
				$nameIndex = 2
				while ($usedTestReportNames.ContainsKey($candidateName))
				{
					if ([string]::IsNullOrWhiteSpace($nameExtension))
					{
						$candidateName = '{0}-{1}' -f $nameWithoutExtension, $nameIndex
					}
					else
					{
						$candidateName = '{0}-{1}{2}' -f $nameWithoutExtension, $nameIndex, $nameExtension
					}
					$nameIndex++
				}

				$usedTestReportNames[$candidateName] = $true
				$usedTestReportPaths[$pathKey] = $true
				[void]$testReportSources.Add([pscustomobject]@{ Name = $candidateName; Path = $resolvedPath })
			}.GetNewClosure()

			& $addTestReportRoot $Script:SharedHelpersRepoRoot
			$launcherPath = [string]$env:BASELINE_LAUNCHER_PATH
			if (-not [string]::IsNullOrWhiteSpace($launcherPath) -and [System.IO.Path]::IsPathRooted($launcherPath))
			{
				& $addTestReportRoot (Split-Path -Path $launcherPath -Parent)
			}
			try { & $addTestReportRoot ([System.AppDomain]::CurrentDomain.BaseDirectory) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:951' -Severity Debug }
			 $null = $_ }
			try { & $addTestReportRoot ((Get-Location).ProviderPath) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:952' -Severity Debug }
			 $null = $_ }

			foreach ($testReportRoot in $testReportRoots)
			{
				& $addTestReportSource 'test-report.json' (Join-Path $testReportRoot 'Tests\TestReport.json')

				$guiTestReportsDir = Join-Path $testReportRoot '.artifacts\gui-tests'
				if (Test-Path -LiteralPath $guiTestReportsDir -PathType Container)
				{
					foreach ($guiTestReport in (Get-ChildItem -LiteralPath $guiTestReportsDir -Filter 'TestReport_*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc))
					{
						& $addTestReportSource $guiTestReport.Name $guiTestReport.FullName
					}
				}
			}

			if ($testReportSources.Count -gt 0)
			{
				New-Item -Path $testReportsBundleDir -ItemType Directory -Force | Out-Null
				foreach ($testReport in $testReportSources)
				{
					$destTestReportPath = Join-Path $testReportsBundleDir ([string]$testReport.Name)
					Copy-Item -LiteralPath ([string]$testReport.Path) -Destination $destTestReportPath -Force
					$bundleEntries.Add([pscustomobject]@{ Name = ('TestReports/{0}' -f [string]$testReport.Name); Source = $destTestReportPath })
				}
			}
		}

		$contentsPath = Join-Path $stagingDir 'contents.json'
		$contents = [ordered]@{
			Files = @($bundleEntries)
		}
		[System.IO.File]::WriteAllText($contentsPath, ($contents | ConvertTo-Json -Depth 6), $utf8NoBom)

		# Generate integrity manifest for immutable/signoff bundles
		$integrityManifest = $null
		if ($Immutable)
		{
			$fileChecksums = [System.Collections.Generic.List[pscustomobject]]::new()
			foreach ($entry in $bundleEntries)
			{
				if (Test-Path -LiteralPath $entry.Source)
				{
					try
					{
						$hash = Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256
						$fileChecksums.Add([pscustomobject]@{
							FileName  = $entry.Name
							SHA256    = $hash.Hash
							Size      = (Get-Item -LiteralPath $entry.Source).Length
						})
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:1004' -Severity Debug }

						$fileChecksums.Add([pscustomobject]@{
							FileName  = $entry.Name
							SHA256    = 'CHECKSUM_ERROR'
							Size      = 0
							Error     = $_.Exception.Message
						})
					}
				}
			}

			# Add contents.json to the checksum list
			try
			{
				$contentsHash = Get-FileHash -LiteralPath $contentsPath -Algorithm SHA256
				$fileChecksums.Add([pscustomobject]@{
					FileName  = 'contents.json'
					SHA256    = $contentsHash.Hash
					Size      = (Get-Item -LiteralPath $contentsPath).Length
				})
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1:1026' -Severity Debug }

				$fileChecksums.Add([pscustomobject]@{
					FileName  = 'contents.json'
					SHA256    = 'CHECKSUM_ERROR'
					Size      = 0
					Error     = $_.Exception.Message
				})
			}

			$integrityManifest = [ordered]@{
				Schema         = 'Baseline.IntegrityManifest'
				SchemaVersion  = 1
				GeneratedAt    = [System.DateTime]::UtcNow.ToString('o')
				BundleType     = 'SignoffBundle'
				Immutable      = $true
				Provenance     = [ordered]@{
					Reason     = if (-not [string]::IsNullOrWhiteSpace($SignoffReason)) { $SignoffReason } else { 'Enterprise signoff bundle' }
					SignedBy   = $env:USERNAME
					SignedOn   = $env:COMPUTERNAME
					SignedAt   = [System.DateTime]::UtcNow.ToString('o')
					Domain     = $env:USERDOMAIN
				}
				FileCount      = $fileChecksums.Count
				Files          = @($fileChecksums)
				Verification   = [ordered]@{
					Algorithm  = 'SHA256'
					Instruction = 'To verify integrity: extract bundle, recompute SHA256 for each file, compare against this manifest.'
				}
			}

			$integrityManifestPath = Join-Path $stagingDir 'integrity-manifest.json'
			[System.IO.File]::WriteAllText($integrityManifestPath, ($integrityManifest | ConvertTo-Json -Depth 8), $utf8NoBom)
			$bundleEntries.Add([pscustomobject]@{ Name = 'integrity-manifest.json'; Source = $integrityManifestPath })
			$bundleIndex.Files['IntegrityManifest'] = 'integrity-manifest.json'

			# Set read-only attributes on all staged files for immutable bundles
			Get-ChildItem -LiteralPath $stagingDir -File | ForEach-Object {
				$_.Attributes = $_.Attributes -bor [System.IO.FileAttributes]::ReadOnly
			}
		}

		if (Test-Path -LiteralPath $OutputPath)
		{
			Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
		}

		& $notifySupportBundleProgress -Stage 'Compress' -Message 'Creating ZIP archive...'
		Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $OutputPath -Force
		$zipItem = Get-Item -LiteralPath $OutputPath -ErrorAction Stop
		if ($zipItem.Length -le 0)
		{
			throw "Support bundle archive was not created correctly: $OutputPath"
		}

		# Set read-only on the ZIP file itself for immutable bundles
		if ($Immutable)
		{
			$zipItem.Attributes = $zipItem.Attributes -bor [System.IO.FileAttributes]::ReadOnly
		}

		$__baselineExtractedPartReturnValue = & { [pscustomobject]@{
			OutputPath        = $OutputPath
			FileCount         = $bundleEntries.Count + 2
			BundleFiles       = @($bundleEntries)
			Immutable         = [bool]$Immutable
			IntegrityManifest = $integrityManifest
		} }; $__baselineExtractedPartHasReturnValue = $true; $__baselineExtractedPartDidReturn = $true
	}
	finally
	{
		if (Test-Path -LiteralPath $tempRoot)
		{
			Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
