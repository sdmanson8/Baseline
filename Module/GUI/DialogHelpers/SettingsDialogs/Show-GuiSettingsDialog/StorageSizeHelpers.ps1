$formatGuiStorageSize = {
			param ([Int64]$Bytes)

			if ($Bytes -lt 0) { $Bytes = 0 }
			$units = @('B', 'KB', 'MB', 'GB', 'TB')
			$value = [double]$Bytes
			$unitIndex = 0
			while (($value -ge 1024) -and ($unitIndex -lt ($units.Count - 1)))
			{
				$value = $value / 1024
				$unitIndex++
			}

			if ($unitIndex -eq 0) { return ('{0} {1}' -f [Int64]$value, $units[$unitIndex]) }
			return ('{0:N1} {1}' -f $value, $units[$unitIndex])
		}.GetNewClosure()

		$getGuiDirectorySize = {
			param ([string]$Path)

			if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Directory]::Exists($Path)) { return 0 }

			$total = [Int64]0
			foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue))
			{
				try { $total += [Int64]$file.Length } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\SettingsDialogs\Show-GuiSettingsDialog\StorageSizeHelpers.ps1:26' -Severity Debug }
				 $null = $_ }
			}
			return $total
		}.GetNewClosure()

		$getGuiBaselineStorageUsage = {
			$appDataRoot = & $getGuiBaselineStorageRoot
			$tempRoot = & $getGuiBaselineTempStorageRoot
			$appDataBytes = if ($appDataRoot) { & $getGuiDirectorySize -Path $appDataRoot } else { 0 }
			$tempBytes = if ($tempRoot) { & $getGuiDirectorySize -Path $tempRoot } else { 0 }
			return [pscustomobject]@{
				AppDataRoot = $appDataRoot
				TempRoot = $tempRoot
				AppDataBytes = $appDataBytes
				TempBytes = $tempBytes
				TotalBytes = ([Int64]$appDataBytes + [Int64]$tempBytes)
			}
		}.GetNewClosure()

		$formatGuiBaselineStorageLocation = {
			param ([string]$Path)

			if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
			$localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
			if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
			if (-not [string]::IsNullOrWhiteSpace($localAppData))
			{
				$baselineRoot = [System.IO.Path]::Combine($localAppData, 'Baseline')
				if ([string]::Equals([System.IO.Path]::GetFullPath($Path), [System.IO.Path]::GetFullPath($baselineRoot), [System.StringComparison]::OrdinalIgnoreCase))
				{
					return '%LOCALAPPDATA%\Baseline'
				}
				$tempRoot = [System.IO.Path]::Combine($localAppData, 'Temp', 'Baseline')
				if ([string]::Equals([System.IO.Path]::GetFullPath($Path), [System.IO.Path]::GetFullPath($tempRoot), [System.StringComparison]::OrdinalIgnoreCase))
				{
					return '%LOCALAPPDATA%\Temp\Baseline'
				}
			}
			return $Path
		}.GetNewClosure()

		$testGuiPathInsideRoot = {
			param (
				[string]$Path,
				[string]$Root
			)

			if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
			$fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
			$fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
			return (
				[string]::Equals($fullPath, $fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
				$fullPath.StartsWith(($fullRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase) -or
				$fullPath.StartsWith(($fullRoot + [System.IO.Path]::AltDirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
			)
		}.GetNewClosure()

		$removeGuiStoragePath = {
			param (
				[string]$Path,
				[string]$Root
			)

			if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return 0 }
			if (-not (& $testGuiPathInsideRoot -Path $Path -Root $Root)) { return 0 }
			if (-not (Test-Path -LiteralPath $Path)) { return 0 }

			$removed = 0
			$item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
			if ($item.PSIsContainer)
			{
				foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue))
				{
					Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
					$removed++
				}
			}
			else
			{
				Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
				$removed = 1
			}

			return $removed
		}.GetNewClosure()

		$removeGuiWorkingCache = {
			param ([string]$Root)

			if ([string]::IsNullOrWhiteSpace($Root)) { return 0 }
			$rcRoot = [System.IO.Path]::Combine($Root, 'RC')
			if (-not (& $testGuiPathInsideRoot -Path $rcRoot -Root $Root)) { return 0 }
			if (-not [System.IO.Directory]::Exists($rcRoot)) { return 0 }

			$activeExtractedRoot = ''
			if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiExtractedRoot))
			{
				try { $activeExtractedRoot = [System.IO.Path]::GetFullPath([string]$Script:GuiExtractedRoot) } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\SettingsDialogs\Show-GuiSettingsDialog\StorageSizeHelpers.ps1:123' -Severity Debug }
				 $activeExtractedRoot = '' }
			}

			$removed = 0
			foreach ($child in @(Get-ChildItem -LiteralPath $rcRoot -Force -ErrorAction SilentlyContinue))
			{
				$childPath = [System.IO.Path]::GetFullPath([string]$child.FullName)
				if (
					-not [string]::IsNullOrWhiteSpace($activeExtractedRoot) -and
					($activeExtractedRoot.StartsWith(($childPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase) -or
					[string]::Equals($activeExtractedRoot.TrimEnd('\', '/'), $childPath.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase))
				)
				{
					continue
				}

				try
				{
					Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
					$removed++
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.ClearWorkingCache'
				}
			}

			return $removed
		}.GetNewClosure()

		$clearGuiBaselineStorageCache = {
			param (
				[bool]$TemporaryCacheFiles,
				[bool]$WorkingFiles,
				[bool]$Logs,
				[bool]$AuditHistory,
				[bool]$SavedSessionState,
				[string]$LogDirectory
			)

			$appDataRoot = & $getGuiBaselineStorageRoot
			$tempRoot = & $getGuiBaselineTempStorageRoot
			if ([string]::IsNullOrWhiteSpace($appDataRoot) -or [string]::IsNullOrWhiteSpace($tempRoot)) { throw 'Baseline storage location is unavailable.' }

			$before = ([Int64](& $getGuiDirectorySize -Path $appDataRoot) + [Int64](& $getGuiDirectorySize -Path $tempRoot))
			$removed = 0

			if ($TemporaryCacheFiles)
			{
				$removed += & $removeGuiWorkingCache -Root $tempRoot
			}

			if ($WorkingFiles)
			{
				foreach ($path in @(
					[System.IO.Path]::Combine($tempRoot, '.hydrate.lock'),
					[System.IO.Path]::Combine($tempRoot, 'detect-cache.json')
				))
				{
					$removed += & $removeGuiStoragePath -Path $path -Root $tempRoot
				}
			}

			if ($Logs)
			{
				$removed += & $removeGuiStoragePath -Path ([System.IO.Path]::Combine($tempRoot, 'perf.log')) -Root $tempRoot
				$logRoots = New-Object System.Collections.Generic.List[string]
				$defaultLogRoot = [System.IO.Path]::Combine($tempRoot, 'Logs')
				if (-not [string]::IsNullOrWhiteSpace($defaultLogRoot)) { [void]$logRoots.Add($defaultLogRoot) }
				if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) { [void]$logRoots.Add([string]$LogDirectory) }
				$currentLogPath = if ($global:LogFilePath) { [System.IO.Path]::GetFullPath([string]$global:LogFilePath) } else { '' }
				foreach ($logRoot in @($logRoots | Select-Object -Unique))
				{
					if ([string]::IsNullOrWhiteSpace($logRoot) -or -not [System.IO.Directory]::Exists($logRoot)) { continue }
					foreach ($logFile in @(Get-ChildItem -LiteralPath $logRoot -Recurse -File -ErrorAction SilentlyContinue))
					{
						$logPath = [System.IO.Path]::GetFullPath([string]$logFile.FullName)
						if (-not [string]::IsNullOrWhiteSpace($currentLogPath) -and [string]::Equals($logPath, $currentLogPath, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
						Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
						$removed++
					}
				}
			}

			if ($AuditHistory)
			{
				$removed += & $removeGuiStoragePath -Path ([System.IO.Path]::Combine($appDataRoot, 'audit.jsonl')) -Root $appDataRoot
			}

			if ($SavedSessionState)
			{
				$removed += & $removeGuiStoragePath -Path ([System.IO.Path]::Combine($appDataRoot, 'UserState')) -Root $appDataRoot
			}

			$after = ([Int64](& $getGuiDirectorySize -Path $appDataRoot) + [Int64](& $getGuiDirectorySize -Path $tempRoot))
			return [pscustomobject]@{
				Removed = $removed
				Before = $before
				After = $after
			}
		}.GetNewClosure()
