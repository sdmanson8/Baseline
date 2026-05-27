if (Test-Path $uwpPhotosSettings) {
        [GC]::Collect()
        $null = Invoke-AIRemovalReg -ArgumentList @('unload', 'HKU\TEMP') -AllowedExitCodes @(0, 1)
        $null = Invoke-AIRemovalNativeProcess -FilePath 'taskkill.exe' -ArgumentList @('/im', 'photos.exe', '/f') -TimeoutSeconds 60 -AllowedExitCodes @(0, 128)
        $photosLoadResult = Invoke-AIRemovalReg -ArgumentList @('LOAD', 'HKU\TEMP', $uwpPhotosSettings) -AllowedExitCodes @(0, 1)
        $global:LASTEXITCODE = $photosLoadResult.ExitCode
        if ($LASTEXITCODE -ne 0) {
            LogWarning "Unable to load Photos settings.dat. Skipping Photos AI preference update."
        }
        else {
            if (!$revert) {
                $regContent = @'
Windows Registry Editor Version 5.00

[HKEY_USERS\TEMP\LocalState]
"ImageCategorizationConsentDismissed"=hex(5f5e10c):74,00,72,00,75,00,65,00,00,\
  00,4c,a0,89,0c,f7,2e,dc,01
"ImageCategorizationConsent"=hex(5f5e10c):66,00,61,00,6c,00,73,00,65,00,00,00,\
  6c,c4,53,ae,c5,51,dc,01
'@
            }
            else {
                $regContent = @'
Windows Registry Editor Version 5.00

[HKEY_USERS\TEMP\LocalState]
"ImageCategorizationConsentDismissed"=hex(5f5e10c):74,00,72,00,75,00,65,00,00,\
  00,4c,a0,89,0c,f7,2e,dc,01
"ImageCategorizationConsent"=hex(5f5e10c):74,00,72,00,75,00,65,00,00,00,79,e7,\
  fe,c5,c4,51,dc,01
'@
            }

            $photosRegFilePath = "$($tempDir)DisableAIPhotos.reg"
            try {
                New-Item $photosRegFilePath -Value $regContent -Force >$null
                regedit.exe /s $photosRegFilePath >$null
                Start-Sleep 1
            }
            finally {
                $null = Invoke-AIRemovalReg -ArgumentList @('UNLOAD', 'HKU\TEMP') -AllowedExitCodes @(0, 1)
                Remove-Item $photosRegFilePath -Force -ErrorAction SilentlyContinue >$null
            }
        }
    }
