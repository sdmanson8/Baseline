if ($IsAdmin)
	{
		# Remove harmful blocked DNS domains list from https://github.com/schrebra/Windows.10.DNS.Block.List
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_RemovingBlockedDnsDomainsList' -Fallback 'Remove harmful blocked DNS domains list from {0}' -FormatArgs @('https://github.com/schrebra/Windows.10.DNS.Block.List'))
		Get-NetFirewallRule -DisplayName Block.MSFT* -ErrorAction Ignore | Remove-NetFirewallRule | Out-Null

		# Remove firewalled IP addresses that block Microsoft recourses added by harmful tweakers
		# https://wpd.app
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_RemovingBlockedMicrosoftIpAddresses' -Fallback 'Remove firewalled IP addresses that block Microsoft recourses added by harmful tweakers')
		Get-NetFirewallRule -DisplayName "Blocker MicrosoftTelemetry*", "Blocker MicrosoftExtra*", "windowsSpyBlocker*" -ErrorAction Ignore | Remove-NetFirewallRule | Out-Null

		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_RemovingHostsEntries' -Fallback 'Remove IP addresses from hosts file that block Microsoft resources')
		try
		{
			$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
			$HostsContent = Get-Content -Path $HostsPath -Encoding Default -Force
			$ActiveHostsEntries = @(
				$HostsContent | Where-Object {
					$Line = $_.Trim()
					$Line -and (-not $Line.StartsWith("#"))
				}
			)

			if ($ActiveHostsEntries.Count -eq 0)
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_NoActiveHostsEntries' -Fallback 'No active hosts entries detected; skipping Baseline hosts cleanup lookup.')
			}
			else
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingGitHubAlive' -Fallback 'Checking whether {0} is alive' -FormatArgs @('https://github.com'))
				$Parameters = @{
					Uri              = "https://github.com"
					Method           = "Head"
					DisableKeepAlive = $true
					UseBasicParsing  = $true
					TimeoutSec       = 15
				}
				(Invoke-WebRequest @Parameters).StatusDescription | Out-Null

				Clear-Variable -Name IPArray -ErrorAction Ignore

				$Parameters = @{
					Uri             = "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/extra.txt"
					UseBasicParsing = $true
					TimeoutSec      = 15
				}
				$extra = (Invoke-WebRequest @Parameters).Content

			$Parameters = @{
				Uri             = "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/extra_v6.txt"
				UseBasicParsing = $true
				TimeoutSec      = 15
			}
			$extra_v6 = (Invoke-WebRequest @Parameters).Content

			$Parameters = @{
				Uri             = "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt"
				UseBasicParsing = $true
				TimeoutSec      = 15
			}
			$spy = (Invoke-WebRequest @Parameters).Content

			$Parameters = @{
				Uri             = "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy_v6.txt"
				UseBasicParsing = $true
				TimeoutSec      = 15
			}
			$spy_v6 = (Invoke-WebRequest @Parameters).Content

			$Parameters = @{
				Uri             = "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/update.txt"
				UseBasicParsing = $true
				TimeoutSec      = 15
			}
			$update = (Invoke-WebRequest @Parameters).Content

			$Parameters = @{
				Uri             = "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/update_v6.txt"
				UseBasicParsing = $true
				TimeoutSec      = 15
			}
			$update_v6 = (Invoke-WebRequest @Parameters).Content

			$IPArray = Get-BaselineHostsCandidateEntries -Content (@($extra, $extra_v6, $spy, $spy_v6, $update, $update_v6) -split "`r?`n")

			# Validate downloaded hosts entries for integrity
			$TotalLines = @($IPArray).Count
			$InvalidLines = @($IPArray | Where-Object { -not (Test-BaselineHostsEntry -Line $_) })
			$ValidLines = @($IPArray | Where-Object { Test-BaselineHostsEntry -Line $_ })

			if ($InvalidLines.Count -gt 0)
			{
				foreach ($BadLine in $InvalidLines)
				{
					LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_InvalidHostsEntrySkipped' -Fallback 'Invalid hosts entry skipped: {0}' -FormatArgs @($BadLine))
				}
			}

			if (Test-BaselineHostsDownloadSuspect -InvalidCount $InvalidLines.Count -TotalCount $TotalLines)
			{
				LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_MoreThanHalfHostsEntriesFailedValidation' -Fallback 'More than 50% of downloaded hosts entries failed validation ({0}/{1}). Downloaded data may be corrupted or tampered. Skipping Baseline hosts cleanup.' -FormatArgs @($InvalidLines.Count, $TotalLines))
				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}

			$IPArray = $ValidLines

			$MatchedHostsEntries = $ActiveHostsEntries | Where-Object {
				$Line = $_.Trim()
				$Line -and
				(-not $Line.StartsWith("#")) -and
				($IPArray | Select-String -SimpleMatch -Pattern $Line -Quiet)
			}

			if ($MatchedHostsEntries)
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_BaselineHostsEntriesDetectedInHostsFile' -Fallback 'Third-party hosts entries detected in hosts file')

				$prefValue = $null
				$prefPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Baseline') -ChildPath 'UserState\Profiles') -ChildPath 'Baseline-user-prefs.json'
				if (Test-Path -LiteralPath $prefPath)
				{
					try
					{
						$rawPrefs = [System.IO.File]::ReadAllText($prefPath, [System.Text.Encoding]::UTF8)
						if (-not [string]::IsNullOrWhiteSpace($rawPrefs))
						{
							$parsedPrefs = ConvertFrom-Json -InputObject $rawPrefs -ErrorAction Stop
							if ($parsedPrefs -and $parsedPrefs.Values -and ($parsedPrefs.Values.PSObject.Properties.Name -contains 'AutoStripBaselineHosts'))
							{
								$prefValue = $parsedPrefs.Values.AutoStripBaselineHosts
							}
						}
					}
					catch
					{
						LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_HostsCleanupPrefReadFailed' -Fallback 'Could not read AutoStripBaselineHosts preference from {0}: {1}. Falling back to the warn-and-skip default.' -FormatArgs @($prefPath, $_.Exception.Message))
					}
				}

				$hostsPolicy = Resolve-BaselineHostsCleanupPolicy -EnvValue $env:BASELINE_AUTO_STRIP_HOSTS -PreferenceValue $prefValue

				if (-not $hostsPolicy.AutoStrip)
				{
					foreach ($DetectedEntry in $MatchedHostsEntries)
					{
						LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_HostsEntryDetectedSkipping' -Fallback 'Detected Baseline hosts entry: {0}' -FormatArgs @(([string]$DetectedEntry).Trim()))
					}
					LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_HostsCleanupSkipped' -Fallback 'Detected Baseline hosts entries that may block legitimate Microsoft resources, but automatic cleanup is opt-in. Set the BASELINE_AUTO_STRIP_HOSTS environment variable to 1, or enable AutoStripBaselineHosts in Settings, to allow Baseline to remove them.')
				}
				else
				{
					$FilteredHosts = $HostsContent | Where-Object {
						$Line = $_.Trim()

						if (-not $Line -or $Line.StartsWith("#"))
						{
							return $true
						}

						-not ($IPArray | Select-String -SimpleMatch -Pattern $Line -Quiet)
					}

					LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CleaningHostsFile' -Fallback 'Cleaning hosts file (auto-strip source: {0})' -FormatArgs @([string]$hostsPolicy.Source))
					$FilteredHosts | Set-Content -Path $HostsPath -Encoding Default -Force

					Invoke-UserLaunch -FilePath 'notepad.exe' -ArgumentList @($HostsPath) -Description 'cleaned hosts file' | Out-Null
				}
			}
			}
		}
		catch [System.Net.WebException]
		{
			LogWarning (((Get-BaselineBilingualString -Key 'NoResponse' -Fallback 'A connection could not be established with {0}.') -f 'https://github.com') + ' ' + (Get-BaselineBilingualString -Key 'Bootstrap_SkippingBaselineHostsCleanup' -Fallback 'Skipping Baseline hosts cleanup.'))
		}
	}
	else
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_SkippingFirewallHostsRemediationNotElevated' -Fallback 'Skipping firewall and hosts remediation because Baseline is not running elevated.')
	}
