if ($hiveloaded) {
        try {
            Write-Status -msg "$(@('Disabling', 'Enabling')[$revert]) AI for new users - "
            LogInfo "$(@('Disabling', 'Enabling')[$revert]) AI for new users"
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v 'TurnOffWindowsCopilot' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableAIDataAnalysis' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'AllowRecallEnablement' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableClickToDo' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'TurnOffSavingSnapshots' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableSettingsAgent' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableAgentConnectors' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableAgentWorkspaces' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableRemoteAgentConnectors' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat" /v 'IsUserEligible' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v 'IsCopilotAvailable' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v 'CopilotDisabledReason' /t REG_SZ /d @('FeatureIsDisabled', ' ')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\Microsoft.Copilot_8wekyb3d8bbwe" /v 'Value' /t REG_SZ /d @('Deny', 'Prompt')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps" /v 'AgentActivationEnabled' /t REG_DWORD /d @('0', '1')[$revert]  /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v 'ShowCopilotButton' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\input\Settings" /v 'InsightsEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\Windows\Shell\ClickToDo" /v 'DisableClickToDo' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v 'DisableSearchBoxSuggestions' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot" /v 'AllowCopilotRuntime' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" /v 'CopilotPWAPin' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Reg.exe add "$defaultUserHiveMount\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" /v 'RecallPin' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name 'TaskbarCompanion' -Type DWord -Value @([int]0, [int]1)[$revert]
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\Windows\Shell\BrandedKey" -Name 'BrandedKeyChoiceType' -Type String -Value @('Search', 'App')[$revert] -TryTrustedInstallerOnAccessDenied -SkipOnAccessDenied | Out-Null
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\Windows\Shell\BrandedKey" -Name 'AppAumid' -Type String -Value @(' ', 'Microsoft.Copilot_8wekyb3d8bbwe!App')[$revert] -TryTrustedInstallerOnAccessDenied -SkipOnAccessDenied | Out-Null
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\SOFTWARE\Policies\Microsoft\Windows\CopilotKey" -Name 'SetCopilotHardwareKey' -Type String -Value @(' ', 'Microsoft.Copilot_8wekyb3d8bbwe!App')[$revert]
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\Windows\CurrentVersion\SettingSync\WindowsSettingHandlers" -Name 'A9HomeContentEnabled' -Type DWord -Value @([int]0, [int]1)[$revert]
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\InputPersonalization" -Name 'RestrictImplicitInkCollection' -Type DWord -Value @([int]1, [int]0)[$revert]
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\InputPersonalization" -Name 'RestrictImplicitTextCollection' -Type DWord -Value @([int]1, [int]0)[$revert]
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\InputPersonalization\TrainedDataStore" -Name 'HarvestContacts' -Type DWord -Value @([int]0, [int]1)[$revert]
            Set-AIRemovalRegistryValue -Path "$defaultUserHivePsPath\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization" -Name 'Value' -Type DWord -Value @([int]0, [int]1)[$revert]
            if ($revert) {
                Reg.exe delete "$defaultUserHiveMount\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' /f *>$null
            }
            else {
                Reg.exe add "$defaultUserHiveMount\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' /t REG_SZ /d 'Ask Copilot' /f *>$null
            }
        }
        finally {
            Dismount-RegistryHive -MountPath $defaultUserHiveMount -PsPath $defaultUserHivePsPath | Out-Null
        }
    }
