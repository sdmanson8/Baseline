if (Test-Path $config) {
        #powershell core bug where json that has empty strings will error
        try {
            $jsonContent = (Get-Content $config).Replace('""', '"_empty"') | ConvertFrom-Json -ErrorAction Stop
            $fail = $false
        }
        catch {
            LogError 'Unable to set Edge flags to disable Copilot due to a different langauge being used'
            LogError 'You can manually disable the Copilot flags at [edge://flags] in the browser'
            $fail = $true
        }

        if (!$fail) {
            try {
                if ($null -eq ($jsonContent.browser | Get-Member -MemberType NoteProperty enabled_labs_experiments -ErrorAction SilentlyContinue)) {
                    $jsonContent.browser | Add-Member -MemberType NoteProperty -Name enabled_labs_experiments -Value @() -ErrorAction SilentlyContinue
                    }
                $flags = @(
                    'edge-copilot-mode@2',
                    'edge-ntp-composer@2', #disables the copilot search in new tab page
                    'edge-compose@2' #disables the ai writing help
                )
                if ($revert) {
                    $jsonContent.browser.enabled_labs_experiments = $jsonContent.browser.enabled_labs_experiments | Where-Object { $_ -notin $flags }
                }
                else {
                    foreach ($flag in $flags) {
                        if ($jsonContent.browser.enabled_labs_experiments -notcontains $flag) {
                            $jsonContent.browser.enabled_labs_experiments += $flag
                        }
                    }
                }

                $newContent = $jsonContent | ConvertTo-Json -Compress -Depth 10
                #add back the empty strings
                $newContent = $newContent.replace('"_empty"', '""')
                Set-Content $config -Value $newContent -Encoding UTF8 -Force -ErrorAction SilentlyContinue
            }
            catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\UWPApps\AIRemoval\Disable-Registry-Keys\EdgeCopilotFlagPolicy.ps1:39' -Severity Debug }

                #LogError 'Edge Browser has never been opened on this machine unable to set flags '
                #LogError 'Open Edge once and run this tweak again'
            }
        }

    }
