if ($revert) {
        if (Test-Path "$backupPath\$backupFileWSAI") {
            Reg.exe import "$backupPath\$backupFileWSAI" *>$null
            $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('create', 'WSAIFabricSvc', 'binPath=', "$env:windir\System32\svchost.exe -k WSAIFabricSvcGroup -p") -TimeoutSeconds 60
        }
        else {
            LogError "Path Not Found: $backupPath\$backupFileWSAI"
        }

    }
    else {
        if ($backup) {
            Write-Status -msg 'Backing up WSAIFabricSvc - '
            LogInfo 'Backing up WSAIFabricSvc'
            #export the service to a reg file before removing it
            if (!(Test-Path $backupPath)) {
                New-Item $backupPath -Force -ItemType Directory | Out-Null
            }
            #this will hang if the service has already been exported
            # if (!(Test-Path "$backupPath\$backupFileWSAI")) {
            Reg.exe export 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WSAIFabricSvc' "$backupPath\$backupFileWSAI" /y > $null 2>&1 #add overwrite file /y switch
            # }
            Write-ConsoleStatus -Status success
}
        Write-Status -msg 'Removing WSAIFabricSvc - '
        LogInfo 'Removing WSAIFabricSvc'
        #delete the service
        $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('delete', 'WSAIFabricSvc') -TimeoutSeconds 60
        Write-ConsoleStatus -Status success
}
    if (!$revert) {
        # Remove the conversational agent service used by Cortana-era and AI agent components.
        try {
            $aarSVCName = (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.name -like '*aarsvc*' }).Name
        }
        catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\UWPApps\AIRemoval\Disable-Registry-Keys\WSAIFabricServicePolicy.ps1:36' -Severity Debug }

            #aarsvc already removed
        }


        if ($aarSVCName) {
            if ($backup) {
                Write-Status -msg 'Backing up Agent Activation Runtime Service - '
                LogInfo 'Backing up Agent Activation Runtime Service'
                #export the service to a reg file before removing it
                if (!(Test-Path $backupPath)) {
                    New-Item $backupPath -Force -ItemType Directory | Out-Null
                }
                #this will hang if the service has already been exported
                # if (!(Test-Path "$backupPath\$backupFileAAR")) {
                Reg.exe export 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\AarSvc' "$backupPath\$backupFileAAR" /y > $null 2>&1
                # }
                Write-ConsoleStatus -Status success
}
            Write-Status -msg 'Removing Agent Activation Runtime Service - '
            LogInfo 'Removing Agent Activation Runtime Service'
            #delete the service
            try {
                Stop-Service -Name $aarSVCName -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\UWPApps\AIRemoval\Disable-Registry-Keys\WSAIFabricServicePolicy.ps1:61' -Severity Debug }

                try {
                    Stop-Service -Name AarSvc -Force -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\UWPApps\AIRemoval\Disable-Registry-Keys\WSAIFabricServicePolicy.ps1:65' -Severity Debug }

                    #neither are running
                }

            }

            $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('delete', 'AarSvc') -TimeoutSeconds 60
            Write-ConsoleStatus -Status success
}
    }
    else {
        Write-Status 'Restoring Agent Activation Runtime Service - '
        LogInfo 'Restoring Agent Activation Runtime Service'

        if (Test-Path "$backupPath\$backupFileAAR") {
            Reg.exe import "$backupPath\$backupFileAAR" *>$null
            $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('create', 'AarSvc', 'binPath=', "$env:windir\system32\svchost.exe -k AarSvcGroup -p") -TimeoutSeconds 60
        }
        else {
            LogError "Path Not Found: $backupPath\$backupFileAAR"
        }
        Write-ConsoleStatus -Status success
}

    #block copilot from communicating with server
    if ($revert) {
        Write-Status -msg 'Adding .copilot File Extension - '
        LogInfo 'Adding .copilot File Extension'
        if ((Test-Path "$backupPath\HKCR_Copilot.reg") -or (Test-Path "$backupPath\HKCU_Copilot.reg")) {
            Reg.exe import "$backupPath\HKCR_Copilot.reg" *>$null
            Reg.exe import "$backupPath\HKCU_Copilot.reg" *>$null
        }
        else {
           # LogInfo -msg "Unable to Find HKCR_Copilot.reg or HKCU_Copilot.reg in [$backupPath]"
        }
        Write-ConsoleStatus -Status success
}
    else {
        if ($backup) {
            #backup .copilot file extension
            Reg.exe export 'HKEY_CLASSES_ROOT\.copilot' "$backupPath\HKCR_Copilot.reg" /y *>$null
            Reg.exe export 'HKEY_CURRENT_USER\Software\Classes\.copilot' "$backupPath\HKCU_Copilot.reg" /y *>$null
        }
        Write-Status -msg 'Removing .copilot File Extension - '
        LogInfo 'Removing .copilot File Extension'
        Reg.exe delete 'HKCU\Software\Classes\.copilot' /f *>$null
        Reg.exe delete 'HKCR\.copilot' /f *>$null
        Write-ConsoleStatus -Status success
}
