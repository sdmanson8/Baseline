using module ..\..\SharedHelpers.psm1

#region Protection & Hardening

<#
    .SYNOPSIS
    Configures security and protection hardening.



.DESCRIPTION

Applies Baseline's security and protection hardening in GUI and headless runs.
    .EXAMPLE
    EventLogSize

    .NOTES
    Machine-wide
#>
function EventLogSize
{
    Write-ConsoleStatus -Action "Configure Event Log Sizes"
	LogInfo "Configuring Event Log Sizes"
    try
	{
        wevtutil sl Security /ms:1024000 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "wevtutil returned exit code $LASTEXITCODE" }
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure the Security event log size: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Enable anti-spoofing protection for Windows Hello biometrics.

    .DESCRIPTION
    Creates the required policy path if necessary and enables enhanced
    anti-spoofing for supported biometric sign-in hardware.

    .EXAMPLE
    BiometricsAntiSpoofing

    .NOTES
    Machine-wide
#>
function BiometricsAntiSpoofing
{
    Write-ConsoleStatus -Action "Enable Biometrics Anti-Spoofing"
    LogInfo "Enabling Biometrics Anti-Spoofing"
    $path = "SOFTWARE\Policies\Microsoft\Biometrics\FacialFeatures"

    # Ensure the path exists, creating it if necessary
    if (-not (Test-Path -Path "HKLM:\$path"))
	{
        try
		{
            New-Item -Path "HKLM:\$path" -Force | Out-Null
        }
		catch
		{
            LogError "Failed to create registry path: $path"
        }
    }

    try
    {
        Set-RegistryValueSafe -Path "HKLM:\$path" `
            -Name "EnhancedAntiSpoofing" `
            -Value 1 `
            -Type DWord
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to enable biometrics anti-spoofing: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Ensure a registry path exists before other hardening settings use it.



.DESCRIPTION

Applies the Baseline behavior for ensure a registry path exists before other hardening settings use it..
    .PARAMETER path
    The registry path to create if it does not already exist.

    .EXAMPLE
    RegistryPaths -path 'HKLM:\Software\Example'

    .NOTES
    Machine-wide
#>
function RegistryPaths
{
    param (
        [string]$path
    )

    # Ensure $path is not empty before proceeding
    if ([string]::IsNullOrWhiteSpace($path))
	{
        return
    }

    if (-not (Test-Path -Path $path))
	{
        try
		{
            New-Item -Path $path -Force | Out-Null
        }
		catch
		{
           LogError "Failed to create registry path: $path"
        }
    }
}

<#
    .SYNOPSIS
    Configure filesystem performance settings.

    .DESCRIPTION
    Disables 8.3 short names and keeps NTFS last access timestamps enabled.

    .EXAMPLE
    FileSystemPerformance

    .NOTES
    Machine-wide

    Caution:
    Disabling 8.3 short names can affect legacy applications, installers, or
    scripts that still depend on short path name behavior.
#>
function FileSystemPerformance
{
    Write-ConsoleStatus -Action "Configure filesystem performance settings"
	LogInfo "Configuring filesystem performance settings"
    try
    {
        fsutil behavior set disable8dot3 1 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "fsutil disable8dot3 returned exit code $LASTEXITCODE" }

        fsutil behavior set disablelastaccess 0 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "fsutil disablelastaccess returned exit code $LASTEXITCODE" }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure filesystem performance settings: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Apply core operating system hardening settings.

    .DESCRIPTION
    Enables the OS-wide registry values used by this preset for credential,
    UAC, virtualization, NTLM, TCP/IP, Explorer, wireless connection, and
    smart-card-removal hardening.

    .EXAMPLE
    OS

    .NOTES
    Machine-wide

    Caution:
    Changes authentication, networking, shell, and smart card related policy
    values. Review carefully in environments with legacy authentication,
    specialized networking, or smart-card workflows.
#>
function OS
{
    Write-ConsoleStatus -Action "Configure OS to be Hardened"
	LogInfo "Configuring OS to be Hardened"
    try
    {
        $wdigestPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
        if (Test-Path $wdigestPath)
		{
            Set-RegistryValueSafe -Path $wdigestPath `
                -Name "UseLogonCredential" `
                -Value 0 `
                -Type DWord
        }

        $kerberosPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters"
        if (Test-Path $kerberosPath)
		{
            Set-RegistryValueSafe -Path $kerberosPath `
                -Name "SupportedEncryptionTypes" `
                -Value 2147483640 `
                -Type DWord
        }

        $tcpipPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        if (Test-Path $tcpipPath)
		{
            Set-RegistryValueSafe -Path $tcpipPath `
                -Name "EnableICMPRedirect" `
                -Value 0 `
                -Type DWord
            Set-RegistryValueSafe -Path $tcpipPath `
                -Name "DisableIPSourceRouting" `
                -Value 2 `
                -Type DWord
        }

        $systemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        if (Test-Path $systemPath)
		{
            Set-RegistryValueSafe -Path $systemPath `
                -Name "EnableLUA" `
                -Value 1 `
                -Type DWord
            Set-RegistryValueSafe -Path $systemPath `
                -Name "EnableVirtualization" `
                -Value 1 `
                -Type DWord
            Set-RegistryValueSafe -Path $systemPath `
                -Name "ConsentPromptBehaviorAdmin" `
                -Value 2 `
                -Type DWord
        }

        $explorerPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        if (!(Test-Path $explorerPolicyPath))
		{
            New-Item -Path $explorerPolicyPath -Force -ErrorAction Stop | Out-Null
        }
        Set-RegistryValueSafe -Path $explorerPolicyPath `
            -Name "NoDataExecutionPrevention" `
            -Value 0 `
            -Type DWord
        Set-RegistryValueSafe -Path $explorerPolicyPath `
            -Name "NoHeapTerminationOnCorruption" `
            -Value 0 `
            -Type DWord

        $wcmPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy"
        if (!(Test-Path $wcmPath))
		{
            New-Item -Path $wcmPath -Force -ErrorAction Stop | Out-Null
        }
        Set-RegistryValueSafe -Path $wcmPath `
            -Name "fMinimizeConnections" `
            -Value 1 `
            -Type DWord

        $netbtPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netbt\Parameters"
        if (Test-Path $netbtPath)
		{
            Set-RegistryValueSafe -Path $netbtPath `
                -Name "NoNameReleaseOnDemand" `
                -Value 1 `
                -Type DWord
        }

        $msv10Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
        if (Test-Path $msv10Path)
		{
            Set-RegistryValueSafe -Path $msv10Path `
                -Name "NTLMMinServerSec" `
                -Value 537395200 `
                -Type DWord
            Set-RegistryValueSafe -Path $msv10Path `
                -Name "NTLMMinClientSec" `
                -Value 537395200 `
                -Type DWord
            Set-RegistryValueSafe -Path $msv10Path `
                -Name "allownullsessionfallback" `
                -Value 0 `
                -Type DWord
        }

        $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        if (Test-Path $lsaPath)
		{
            Set-RegistryValueSafe -Path $lsaPath `
                -Name "RestrictRemoteSAM" `
                -Value "O:BAG:BAD:(A;;RC;;;BA)" `
                -Type String
        }

        $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        if (Test-Path $winlogonPath)
		{
            Set-RegistryValueSafe -Path $winlogonPath `
                -Name "SCRemoveOption" `
                -Value 2 `
                -Type DWord
        }
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure OS hardening settings: $($_.Exception.Message)"
	}
}
<#
    .SYNOPSIS
    Return whether Adobe Reader DC policy paths are present.

    .DESCRIPTION
    Checks the Adobe Reader DC registry locations Baseline uses for hardening so the Adobe Reader STIG preset only runs when Reader is installed.

    .EXAMPLE
    Test-BaselineAdobeReaderInstalled
#>
function Test-BaselineAdobeReaderInstalled
{
    [CmdletBinding()]
    param ()

    foreach ($candidatePath in @(
        'HKLM:\Software\Adobe\Acrobat Reader\DC'
        'HKLM:\Software\Policies\Adobe\Acrobat Reader\DC'
        'HKCU:\Software\Adobe\Acrobat Reader\DC'
        'HKCU:\Software\Policies\Adobe\Acrobat Reader\DC\Privileged'
    ))
    {
        if (Test-Path $candidatePath)
        {
            return $true
        }
    }

    return $false
}

<#
    .SYNOPSIS
    Apply the Adobe Reader DC security settings used by this preset.

    .DESCRIPTION
    Applies a broad Adobe Reader DC policy set when Reader is detected,
    including maintenance, services, protected mode, protected view, and
    feature lockdown related settings.

    .EXAMPLE
    AdobereaderDCSTIG

    .NOTES
    Machine-wide

    Caution:
    Can affect Adobe update behavior, cloud/share integrations, and document
    handling features that depend on less restrictive Reader settings.
#>
function AdobereaderDCSTIG
{
    Write-ConsoleStatus -Action "Configure Adobe Reader Security"
	LogInfo "Configuring Adobe Reader Security"
    $adobePolicyRoot = "HKLM:\Software\Policies\Adobe\Acrobat Reader\DC"
    $adobeWowInstallerPath = "HKLM:\Software\Wow6432Node\Adobe\Acrobat Reader\DC\Installer"
    $adobeCurrentUserPath = "HKCU:\Software\Policies\Adobe\Acrobat Reader\DC\Privileged"
    $adobeInstalled = Test-BaselineAdobeReaderInstalled

    if ($adobeInstalled)
	{
        foreach ($subPath in @(
            $adobePolicyRoot,
            "$adobePolicyRoot\FeatureLockDown",
            "$adobePolicyRoot\FeatureLockDown\cCloud",
            "$adobePolicyRoot\FeatureLockDown\cDefaultLaunchURLPerms",
            "$adobePolicyRoot\FeatureLockDown\cServices",
            "$adobePolicyRoot\FeatureLockDown\cSharePoint",
            "$adobePolicyRoot\FeatureLockDown\cWebmailProfiles",
            "$adobePolicyRoot\FeatureLockDown\cWelcomeScreen",
            "HKLM:\Software\Adobe\Acrobat Reader\DC\Installer",
            $adobeWowInstallerPath
        ))
		{
            if (!(Test-Path $subPath))
			{
                New-Item -Path $subPath -Force -ErrorAction Stop | Out-Null
            }
        }

        $featureLockDownPath = "$adobePolicyRoot\FeatureLockDown"
        Set-RegistryValueSafe -Path "HKLM:\Software\Adobe\Acrobat Reader\DC\Installer" `
            -Name "DisableMaintenance" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $adobeWowInstallerPath `
            -Name "DisableMaintenance" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bAcroSuppressUpsell" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bDisablePDFHandlerSwitching" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bDisableTrustedFolders" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bDisableTrustedSites" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bEnableFlash" `
            -Value 0 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bEnhancedSecurityInBrowser" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bEnhancedSecurityStandalone" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "bProtectedMode" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "iFileAttachmentPerms" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $featureLockDownPath `
            -Name "iProtectedView" `
            -Value 2 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cCloud" `
            -Name "bAdobeSendPluginToggle" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cDefaultLaunchURLPerms" `
            -Name "iURLPerms" `
            -Value 3 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cDefaultLaunchURLPerms" `
            -Name "iUnknownURLPerms" `
            -Value 2 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cServices" `
            -Name "bToggleAdobeDocumentServices" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cServices" `
            -Name "bToggleAdobeSign" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cServices" `
            -Name "bTogglePrefsSync" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cServices" `
            -Name "bToggleWebConnectors" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cServices" `
            -Name "bUpdater" `
            -Value 0 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cSharePoint" `
            -Name "bDisableSharePointFeatures" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cWebmailProfiles" `
            -Name "bDisableWebmail" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "$featureLockDownPath\cWelcomeScreen" `
            -Name "bShowWelcomeScreen" `
            -Value 0 `
            -Type DWord

        if (Test-Path $adobeCurrentUserPath)
		{
            Set-RegistryValueSafe -Path $adobeCurrentUserPath `
                -Name "bProtectedMode" `
                -Value 0 `
                -Type DWord
        }

        Write-ConsoleStatus -Status success
    }
    else
	{
        Write-ConsoleStatus -Status success
        LogWarning "Adobe Reader is not installed or the registry path does not exist. Skipping configuration."
    }

}

<#
    .SYNOPSIS
    Harden ClickOnce trust prompts.

    .DESCRIPTION
    Disables ClickOnce trust prompts for all zones in the .NET TrustManager.

    .EXAMPLE
    ClickOnce

    .NOTES
    Machine-wide

    Caution:
    Advanced. Can break ClickOnce-based installers, updates, or internal
    applications that depend on trust prompts.
#>
function ClickOnce
{
    Write-ConsoleStatus -Action "Configure ClickOnce trust prompt hardening"
	LogInfo "Configuring ClickOnce trust prompt hardening"
    try
    {
        $promptingPath = "HKLM:\SOFTWARE\MICROSOFT\.NETFramework\Security\TrustManager\PromptingLevel"
        if (!(Test-Path $promptingPath))
		{
            New-Item -Path $promptingPath -Force -ErrorAction Stop | Out-Null
        }

        foreach ($zone in @("MyComputer", "LocalIntranet", "Internet", "TrustedSites", "UntrustedSites"))
		{
            Set-RegistryValueSafe -Path $promptingPath `
                -Name $zone `
                -Value "Disabled" `
                -Type String
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure ClickOnce trust prompt hardening: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Apply hardened Microsoft Office security settings.

    .DESCRIPTION
    Sets Office macro and content execution policies for supported Office
    versions to reduce document-based attack surface in Word and Publisher.
    Also hardens Outlook handling of internal content and blocks
    Internet-origin active content in supported Word, Excel, and PowerPoint
    policy paths.

    .EXAMPLE
    MSOffice

    .NOTES
    Current user

    Caution:
    Can affect macros, Office automation, downloaded Office documents, and
    workflows that rely on active content or permissive Outlook trust behavior.
#>
function MSOffice
{
    Write-ConsoleStatus -Action "Configure Office to be Hardened"
	LogInfo "Configuring Office to be Hardened"
    try
    {
        $officeVersions = @("12.0", "14.0", "15.0", "16.0")

        foreach ($version in $officeVersions)
		{
            $wordPath = "HKCU:\Software\Policies\Microsoft\Office\$version\Word\Security"
            $publisherPath = "HKCU:\Software\Policies\Microsoft\Office\$version\Publisher\Security"
            $excelPath = "HKCU:\Software\Policies\Microsoft\Office\$version\Excel\Security"
            $powerPointPath = "HKCU:\Software\Policies\Microsoft\Office\$version\PowerPoint\Security"
            $outlookPath = "HKCU:\Software\Policies\Microsoft\Office\$version\Outlook\Security"

            if (Test-Path $wordPath)
			{
                Set-RegistryValueSafe -Path $wordPath `
                    -Name "vbawarnings" `
                    -Value 4 `
                    -Type DWord
            }

            if (Test-Path $publisherPath)
			{
                Set-RegistryValueSafe -Path $publisherPath `
                    -Name "vbawarnings" `
                    -Value 4 `
                    -Type DWord
            }

            if (($version -in @("15.0", "16.0")) -and (Test-Path $excelPath))
			{
                Set-RegistryValueSafe -Path $excelPath `
                    -Name "blockcontentexecutionfrominternet" `
                    -Value 1 `
                    -Type DWord
            }

            if (($version -in @("15.0", "16.0")) -and (Test-Path $powerPointPath))
			{
                Set-RegistryValueSafe -Path $powerPointPath `
                    -Name "blockcontentexecutionfrominternet" `
                    -Value 1 `
                    -Type DWord
            }

            if (($version -in @("15.0", "16.0")) -and (Test-Path $outlookPath))
			{
                Set-RegistryValueSafe -Path $outlookPath `
                    -Name "markinternalasunsafe" `
                    -Value 0 `
                    -Type DWord
            }
        }

        $word15Path = "HKCU:\Software\Policies\Microsoft\Office\15.0\Word\Security"
        $word16Path = "HKCU:\Software\Policies\Microsoft\Office\16.0\Word\Security"

        if (Test-Path $word15Path)
		{
            Set-RegistryValueSafe -Path $word15Path `
                -Name "blockcontentexecutionfrominternet" `
                -Value 1 `
                -Type DWord
        }

        if (Test-Path $word16Path)
		{
            Set-RegistryValueSafe -Path $word16Path `
                -Name "blockcontentexecutionfrominternet" `
                -Value 1 `
                -Type DWord
        }
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure Office hardening settings: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Configure Office link update hardening.

    .DESCRIPTION
    Disables automatic external link updates in Word and WordMail for the
    supported Office versions used by this preset.

    .EXAMPLE
    MSOfficeLinks

    .NOTES
    Current user

    Caution:
    Can affect documents or mail workflows that intentionally rely on
    automatic external link refresh behavior.
#>
function MSOfficeLinks
{
    Write-ConsoleStatus -Action "Configure Office link update hardening"
	LogInfo "Configuring Office link update hardening"
    try
    {
        $officeVersions = @("14.0", "15.0", "16.0")
        foreach ($version in $officeVersions)
		{
            $wordPath = "HKCU:\Software\Microsoft\Office\$version\Word\Options"
            $wordMailPath = "HKCU:\Software\Microsoft\Office\$version\Word\Options\WordMail"

            if (!(Test-Path $wordPath))
			{
                New-Item -Path $wordPath -Force -ErrorAction Stop | Out-Null
            }

            if (!(Test-Path $wordMailPath))
			{
                New-Item -Path $wordMailPath -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $wordPath `
                -Name "DontUpdateLinks" `
                -Value 1 `
                -Type DWord
            Set-RegistryValueSafe -Path $wordMailPath `
                -Name "DontUpdateLinks" `
                -Value 1 `
                -Type DWord
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure Office link update hardening: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Harden WinRM configuration.

    .DESCRIPTION
    Disables unencrypted WinRM traffic and client digest authentication while
    restarting the WinRM service to apply the settings.

    .EXAMPLE
    WinRM

    .NOTES
    Machine-wide

    Caution:
    Can break legacy WinRM clients or management tooling that relies on digest
    authentication or weaker transport settings.
#>
function WinRM
{
    Write-ConsoleStatus -Action "Configure WinRM hardening"
	LogInfo "Configuring WinRM hardening"
    try
    {
        Stop-Service -Name WinRM -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

        $servicePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"
        if (!(Test-Path $servicePath))
		{
            New-Item -Path $servicePath -Force -ErrorAction Stop | Out-Null
        }
        Set-RegistryValueSafe -Path $servicePath `
            -Name "AllowUnencryptedTraffic" `
            -Value 0 `
            -Type DWord

        $clientPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
        if (!(Test-Path $clientPath))
		{
            New-Item -Path $clientPath -Force -ErrorAction Stop | Out-Null
        }
        Set-RegistryValueSafe -Path $clientPath `
            -Name "AllowDigest" `
            -Value 0 `
            -Type DWord

        # Restart WinRM only if it was running before - the service may be disabled or unavailable
        try { Start-Service -Name WinRM -ErrorAction Stop | Out-Null }
        catch { LogInfo "WinRM service not restarted (may be disabled or unavailable on this system)." }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure WinRM hardening: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Enable DLL hijacking prevention settings.

    .DESCRIPTION
    Configures the Session Manager DLL search order protections used by this
    preset to reduce common DLL hijacking paths.

    .EXAMPLE
    DLLHijackingPrevention

    .NOTES
    Machine-wide
#>
function DLLHijackingPrevention
{
    Write-ConsoleStatus -Action "Configure DLL Hijacking Prevention"
	LogInfo "Configuring DLL Hijacking Prevention"
    try
    {
        Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name "CWDIllegalInDllSearch" `
            -Value 2 `
            -Type DWord
        Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name "SafeDLLSearchMode" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name "ProtectionMode" `
            -Value 1 `
            -Type DWord
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure DLL hijacking prevention: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Restrict wireless sign-in options on the lock screen.

    .DESCRIPTION
    Hides the network selection UI from the sign-in screen to reduce wireless
    attack surface before a user signs in.

    .EXAMPLE
    AirstrikeAttack

    .NOTES
    Machine-wide
#>
function AirstrikeAttack
{
    Write-ConsoleStatus -Action "Restrict local Windows wireless exploitation"
	LogInfo "Restricting local Windows wireless exploitation"
    try
    {
        Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
            -Name "DontDisplayNetworkSelectionUI" `
            -Value 1 `
            -Type DWord
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to restrict lock screen network selection: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Reduce RPC surface area.

    .DESCRIPTION
    Disables RPC-over-TCP for the Task Scheduler service and remote SCM
    endpoints for service control.

    .EXAMPLE
    RPCSurface

    .NOTES
    Machine-wide

    Caution:
    Can break remote task scheduling, remote service control, and management
    products that depend on those RPC paths.
#>
function RPCSurface
{
    Write-ConsoleStatus -Action "Configure RPC surface reduction"
	LogInfo "Configuring RPC surface reduction"
    try
    {
        Set-RegistryValueSafe -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Schedule" `
            -Name "DisableRpcOverTcp" `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control" `
            -Name "DisableRemoteScmEndpoints" `
            -Value 1 `
            -Type DWord
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure RPC surface reduction: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable AutoRun for current-user and machine-wide Explorer policies.

    .DESCRIPTION
    Creates the Explorer policy paths if needed and sets the AutoRun block
    value used by this preset for both HKLM and HKCU.

    .EXAMPLE
    AutoRun

    .NOTES
    Current user, Machine-wide
#>
function AutoRun
{
    Write-ConsoleStatus -Action "Disable AutoRun"
    LogInfo "Disabling Autorun"
    # Ensure paths exist or suppress the error
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    )

    # Create missing paths and set registry values
    try
    {
        foreach ($path in $paths)
		{
            if (-not (Test-Path -Path $path))
			{
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path `
                -Name "NoDriveTypeAutoRun" `
                -Value 0xFF `
                -Type DWord
        }
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable AutoRun: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable automatic mounting of newly attached volumes.

    .DESCRIPTION
    Sets or clears the MountMgr NoAutoMount value so Windows either blocks or allows automatic mounting of newly attached volumes.

    .PARAMETER Enable
    Apply the Baseline setting that disables automatic mounting of newly attached volumes.

    .PARAMETER Disable
    Remove the Baseline setting and allow Windows to resume automatic mounting.

    .EXAMPLE
    MountManagerAutoMount -Enable
#>
function MountManagerAutoMount
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\MountMgr'

    if ($PSCmdlet.ParameterSetName -eq 'Enable')
    {
        Write-ConsoleStatus -Action "Disabling automatic mount of new volumes (MountMgr\NoAutoMount=1)"
        LogInfo "Setting MountMgr\NoAutoMount=1 to block automatic mounting of newly attached volumes"
        try
        {
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path -Name 'NoAutoMount' -Value 1 -Type DWord
            Write-ConsoleStatus -Status success
        }
        catch
        {
            Write-ConsoleStatus -Status failed
            LogError "Failed to set MountMgr\NoAutoMount: $($_.Exception.Message)"
        }
    }
    else
    {
        Write-ConsoleStatus -Action "Restoring default automatic volume mounting (MountMgr\NoAutoMount removed)"
        LogInfo "Removing MountMgr\NoAutoMount to restore Windows default behaviour"
        try
        {
            Remove-RegistryValueSafe -Path $path -Name 'NoAutoMount'
            Write-ConsoleStatus -Status success
        }
        catch
        {
            Write-ConsoleStatus -Status failed
            LogError "Failed to remove MountMgr\NoAutoMount: $($_.Exception.Message)"
        }
    }
}
<#
    .SYNOPSIS
    Force Office AMSI macro runtime scanning.

    .DESCRIPTION
    Creates the Office 16.0 security policy keys used by Baseline and sets MacroRuntimeScanScope so Office macros are scanned through AMSI at runtime.

    .EXAMPLE
    MacroRuntimeScanScope
#>
function MacroRuntimeScanScope
{
    Write-ConsoleStatus -Action "Force AMSI macro runtime scanning"
    LogInfo "Forcing AMSI macro runtime scanning for Office"
    try
    {
        foreach ($app in @('Word', 'Excel', 'PowerPoint', 'Publisher', 'Visio', 'Access'))
        {
            $path = "HKCU:\Software\Policies\Microsoft\Office\16.0\$app\Security"
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path `
                -Name 'MacroRuntimeScanScope' `
                -Value 2 `
                -Type DWord
        }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure Office AMSI macro scanning: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Block legacy RTF documents in Word.

    .DESCRIPTION
    Writes the Word FileBlock policy values Baseline uses to block legacy RTF documents across the supported Office versions.

    .EXAMPLE
    RtfDocuments
#>
function RtfDocuments
{
    Write-ConsoleStatus -Action "Block legacy RTF documents in Word"
    LogInfo "Blocking legacy RTF documents in Word"
    try
    {
        foreach ($version in @('14.0', '15.0', '16.0'))
        {
            $path = "HKCU:\Software\Policies\Microsoft\Office\$version\Word\Security\FileBlock"
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path `
                -Name 'RtfFiles' `
                -Value 2 `
                -Type DWord
            Set-RegistryValueSafe -Path $path `
                -Name 'OpenInProtectedView' `
                -Value 0 `
                -Type DWord
        }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to block legacy RTF documents: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Restrict embedded files in OneNote.

    .DESCRIPTION
    Enables the OneNote policy values Baseline uses to block embedded files and disallow risky attachment extensions.

    .EXAMPLE
    OneNoteEmbeds
#>
function OneNoteEmbeds
{
    Write-ConsoleStatus -Action "Restrict OneNote embedded files"
    LogInfo "Restricting OneNote embedded files"
    try
    {
        $blockedExtensions = '.ade;.adp;.app;.application;.appref-ms;.asx;.bas;.bat;.chm;.cmd;.com;.cpl;.crt;.csh;.der;.diagcab;.exe;.fxp;.gadget;.grp;.hlp;.hta;.inf;.ins;.isp;.iso;.its;.jar;.jnlp;.js;.jse;.ksh;.lnk;.mad;.maf;.mag;.mam;.maq;.mar;.mas;.mat;.mau;.mav;.maw;.mda;.mdb;.mde;.mdt;.mdw;.mdz;.msc;.msh;.msh1;.msh1xml;.msh2;.msh2xml;.mshxml;.msi;.msp;.mst;.ops;.pcd;.pif;.pl;.prf;.prg;.ps1;.ps1xml;.ps2;.ps2xml;.psc1;.psc2;.pst;.reg;.scf;.scr;.sct;.shb;.shs;.tmp;.url;.vb;.vbe;.vbs;.vsmacros;.vss;.vst;.vsw;.ws;.wsc;.wsf;.wsh;.xnk'

        foreach ($version in @('14.0', '15.0', '16.0'))
        {
            $path = "HKCU:\Software\Policies\Microsoft\Office\$version\OneNote\Options"
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path `
                -Name 'DisableEmbeddedFiles' `
                -Value 1 `
                -Type DWord
            Set-RegistryValueSafe -Path $path `
                -Name 'BlockedExtensions' `
                -Value $blockedExtensions `
                -Type String
        }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to restrict OneNote embedded files: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Disable WDigest credential caching.

    .DESCRIPTION
    Creates the WDigest policy path if needed and sets UseLogonCredential to 0 so cleartext credential caching stays off.

    .EXAMPLE
    WDigestCaching
#>
function WDigestCaching
{
    Write-ConsoleStatus -Action "Disable WDigest credential caching"
    LogInfo "Disabling WDigest credential caching"
    try
    {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
        if (-not (Test-Path -Path $path))
        {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }

        Set-RegistryValueSafe -Path $path `
            -Name 'UseLogonCredential' `
            -Value 0 `
            -Type DWord
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable WDigest credential caching: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable Protected Credentials delegation.

    .DESCRIPTION
    Creates the CredentialsDelegation policy path if needed and sets AllowProtectedCreds to the Baseline value.

    .EXAMPLE
    ProtectedCreds
#>
function ProtectedCreds
{
    Write-ConsoleStatus -Action "Enable Protected Credentials delegation"
    LogInfo "Enabling Protected Credentials delegation"
    try
    {
        $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
        if (-not (Test-Path -Path $path))
        {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }

        Set-RegistryValueSafe -Path $path `
            -Name 'AllowProtectedCreds' `
            -Value 1 `
            -Type DWord
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to enable Protected Credentials delegation: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Apply the Baseline auditing policy set.

    .DESCRIPTION
    Enables command-line process auditing and runs auditpol for the subcategories Baseline expects for security investigation and logging.

    .EXAMPLE
    AuditingBaseline
#>
function AuditingBaseline
{
    Write-ConsoleStatus -Action "Enable Auditing Baseline"
    LogInfo "Enabling Auditing Baseline"

    $failed = $false
    try
    {
        $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        if (-not (Test-Path -Path $path))
        {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }

        Set-RegistryValueSafe -Path $path `
            -Name 'ProcessCreationIncludeCmdLine_Enabled' `
            -Value 1 `
            -Type DWord
    }
    catch
    {
        $failed = $true
        LogError "Failed to enable ProcessCreationIncludeCmdLine_Enabled: $($_.Exception.Message)"
    }

    $subcategories = @(
        @{ Name = 'Process Creation';        Guid = '{0CCE922B-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'Logon';                   Guid = '{0CCE9215-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'Special Logon';           Guid = '{0CCE921B-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'Removable Storage';       Guid = '{0CCE9245-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'IPsec Driver';            Guid = '{0CCE9213-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'Security State Change';   Guid = '{0CCE9210-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'System Integrity';        Guid = '{0CCE9212-69AE-11D9-BED3-505054503030}' }
        @{ Name = 'Sensitive Privilege Use'; Guid = '{0CCE9228-69AE-11D9-BED3-505054503030}' }
    )

    foreach ($subcategory in $subcategories)
    {
        try
        {
            auditpol /set /subcategory:"$($subcategory.Guid)" /success:enable /failure:enable | Out-Null
            if ($LASTEXITCODE -ne 0)
            {
                throw "auditpol returned exit code $LASTEXITCODE"
            }
        }
        catch
        {
            $failed = $true
            LogError "Failed to configure audit policy $($subcategory.Name): $($_.Exception.Message)"
        }
    }

    if ($failed)
    {
        Write-ConsoleStatus -Status failed
    }
    else
    {
        Write-ConsoleStatus -Status success
    }
}
<#
    .SYNOPSIS
    Enable PowerShell transcription logging.

    .DESCRIPTION
    Creates the transcription output directory and policy keys so PowerShell sessions write transcripts with invocation headers.

    .EXAMPLE
    PowerShellTranscription
#>
function PowerShellTranscription
{
    Write-ConsoleStatus -Action "Enable PowerShell Transcription"
    LogInfo "Enabling PowerShell Transcription"
    try
    {
        $transcriptPath = Join-Path -Path $env:SystemDrive -ChildPath 'PSTranscripts'
        if (-not (Test-Path -Path $transcriptPath))
        {
            New-Item -Path $transcriptPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'
        if (-not (Test-Path -Path $policyPath))
        {
            New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
        }

        Set-RegistryValueSafe -Path $policyPath `
            -Name 'EnableTranscripting' `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $policyPath `
            -Name 'EnableInvocationHeader' `
            -Value 1 `
            -Type DWord
        Set-RegistryValueSafe -Path $policyPath `
            -Name 'OutputDirectory' `
            -Value $transcriptPath `
            -Type String
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to enable PowerShell Transcription: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Disable Windows PowerShell 2.0 optional features.

    .DESCRIPTION
    Disables the Windows optional features that install the PowerShell 2.0 engine and root components.

    .EXAMPLE
    PowerShellV2
#>
function PowerShellV2
{
    [CmdletBinding()]
    param (
        [int]$TimeoutSeconds = 300
    )

    Write-ConsoleStatus -Action "Disable Windows PowerShell 2.0"
    LogInfo "Disabling Windows PowerShell 2.0"
    $failed = $false
    $dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
    if (-not (Test-Path -LiteralPath $dismPath -PathType Leaf))
    {
        $dismPath = 'dism.exe'
    }

    foreach ($feature in @('MicrosoftWindowsPowerShellV2', 'MicrosoftWindowsPowerShellV2Root'))
    {
        try
        {
            $null = Invoke-BaselineProcess `
                -FilePath $dismPath `
                -ArgumentList @('/Online', '/Disable-Feature', "/FeatureName:$feature", '/NoRestart') `
                -TimeoutSeconds $TimeoutSeconds `
                -AllowedExitCodes @(0, 3010) `
                -CaptureOutput
        }
        catch
        {
            $failed = $true
            LogError "Failed to disable optional feature ${feature}: $($_.Exception.Message)"
        }
    }

    if ($failed)
    {
        Write-ConsoleStatus -Status failed
    }
    else
    {
        Write-ConsoleStatus -Status success
    }
}
<#
    .SYNOPSIS
    Enable the Authenticode padding check.

    .DESCRIPTION
    Creates the Wintrust configuration keys and sets EnableCertPaddingCheck for both the 64-bit and Wow6432Node policy paths.

    .EXAMPLE
    CertPaddingCheck
#>
function CertPaddingCheck
{
    Write-ConsoleStatus -Action "Enable Authenticode padding check"
    LogInfo "Enabling Authenticode padding check"
    try
    {
        foreach ($path in @(
            'HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config',
            'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
        ))
        {
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path `
                -Name 'EnableCertPaddingCheck' `
                -Value 1 `
                -Type DWord
        }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to enable Authenticode padding check: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Lock down ActiveX controls across Internet zones.

    .DESCRIPTION
    Sets URL action 1004 to the restricted value for zones 0 through 4 so legacy ActiveX content is blocked more aggressively.

    .EXAMPLE
    ActiveXLockdown
#>
function ActiveXLockdown
{
    Write-ConsoleStatus -Action "Lock down ActiveX controls"
    LogInfo "Locking down ActiveX controls"
    try
    {
        foreach ($zone in 0..4)
        {
            $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\$zone"
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            Set-RegistryValueSafe -Path $path `
                -Name '1004' `
                -Value 3 `
                -Type DWord
        }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to lock down ActiveX controls: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Remove the ms-msdt protocol handler.

    .DESCRIPTION
    Deletes the ms-msdt protocol registration from HKCR so MSDT-based protocol launches are no longer available.

    .EXAMPLE
    MsMsdtHandler
#>
function MsMsdtHandler
{
    Write-ConsoleStatus -Action "Remove ms-msdt protocol handler"
    LogInfo "Removing ms-msdt protocol handler"
    try
    {
        $path = 'Registry::HKEY_CLASSES_ROOT\ms-msdt'
        if (Test-Path -Path $path)
        {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
        }
        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to remove ms-msdt protocol handler: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable script association lockdown for ransomware hardening.

    .DESCRIPTION
    Applies or removes the Baseline file-type mitigation records used to stop common script extensions from executing through shell associations.

    .PARAMETER Enable
    Apply the Baseline script association lockdown.

    .PARAMETER Disable
    Remove the Baseline script association lockdown and restore the saved associations.

    .EXAMPLE
    RansomwareScriptLockdown -Enable
#>
function RansomwareScriptLockdown
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure ransomware script extension lockdown"
    LogInfo "Configuring ransomware script extension lockdown"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        $extensions = @(Get-BaselineRansomwareFtypeExtensions)

        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $records = foreach ($extension in $extensions)
            {
                $record = Set-BaselineRansomwareFtypeMitigation -Extension $extension
                if (-not $record.PSObject.Properties['Extension'])
                {
                    $record | Add-Member -NotePropertyName 'Extension' -NotePropertyValue $extension -Force
                }
                $record
            }

            $mitigated = @($records | Where-Object { [bool]$_.Mitigated }).Count
            $already = @($records | Where-Object { [bool]$_.AlreadyMitigated }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "Ransomware lockdown summary: extensions=$($records.Count) mitigated=$mitigated already=$already skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.Extension): $($record.SkipReason)"
            }
        }
        else
        {
            $records = foreach ($extension in $extensions)
            {
                $record = Restore-BaselineRansomwareFtypeMitigation -Extension $extension
                if (-not $record.PSObject.Properties['Extension'])
                {
                    $record | Add-Member -NotePropertyName 'Extension' -NotePropertyValue $extension -Force
                }
                $record
            }

            $restored = @($records | Where-Object { [bool]$_.Restored }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "Ransomware lockdown reversal summary: extensions=$($records.Count) restored=$restored skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.Extension): $($record.SkipReason)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure ransomware script extension lockdown: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable the Baseline network hardening registry settings.

    .DESCRIPTION
    Applies or restores the registry-backed network surface reduction settings tracked by the Baseline network hardening helpers.

    .PARAMETER Enable
    Apply the Baseline network hardening registry settings.

    .PARAMETER Disable
    Restore the saved network hardening registry settings.

    .EXAMPLE
    NetworkHardeningRegistry -Enable
#>
function NetworkHardeningRegistry
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure network surface hardening"
    LogInfo "Configuring network surface hardening"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $records = @(Set-BaselineNetworkHardeningRegistrySettings)
            $applied = @($records | Where-Object { [bool]$_.Applied }).Count
            $skipped = @($records | Where-Object { -not [bool]$_.Applied }).Count
            LogInfo "Network hardening summary: settings=$($records.Count) applied=$applied skipped=$skipped"
        }
        else
        {
            $records = @(Restore-BaselineNetworkHardeningRegistrySettings)
            $restored = @($records | Where-Object { [bool]$_.Restored }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "Network hardening reversal summary: settings=$($records.Count) restored=$restored skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.Id): $($record.SkipReason)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure network surface hardening: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable NetBIOS over TCP/IP hardening.

    .DESCRIPTION
    Disables or restores NetBIOS over TCP/IP on network adapters through the Baseline NetBIOS helper workflow.

    .PARAMETER Enable
    Apply the Baseline setting that disables NetBIOS over TCP/IP.

    .PARAMETER Disable
    Restore the saved NetBIOS over TCP/IP state.

    .EXAMPLE
    NetbiosOverTcpip -Enable
#>
function NetbiosOverTcpip
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure NetBIOS over TCP/IP"
    LogInfo "Configuring NetBIOS over TCP/IP"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $records = @(Disable-BaselineNetBiosOverTcpip)
            $applied = @($records | Where-Object { [bool]$_.Applied }).Count
            $skipped = @($records | Where-Object { -not [bool]$_.Applied }).Count
            LogInfo "NetBIOS over TCP/IP summary: adapters=$($records.Count) applied=$applied skipped=$skipped"
        }
        else
        {
            $records = @(Restore-BaselineNetBiosOverTcpip)
            $restored = @($records | Where-Object { [bool]$_.Restored }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "NetBIOS over TCP/IP reversal summary: adapters=$($records.Count) restored=$restored skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.AdapterId): $($record.SkipReason)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure NetBIOS over TCP/IP: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable the Baseline WinRM service lockdown.

    .DESCRIPTION
    Stops and disables WinRM when enabled, or restores the captured service state when disabled, using the Baseline service helper.

    .PARAMETER Enable
    Apply the Baseline setting that stops and disables WinRM.

    .PARAMETER Disable
    Restore the saved WinRM service state.

    .EXAMPLE
    WinRMService -Enable
#>
function WinRMService
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure WinRM service state"
    LogInfo "Configuring WinRM service state"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $record = Disable-BaselineWinRMService
            if ([bool]$record.Skipped)
            {
                LogInfo "WinRM service skipped: $($record.SkipReason)"
            }
            else
            {
                LogInfo "WinRM service summary: stopped=$($record.Stopped) disabled=$($record.Disabled) priorStartType=$($record.PriorStartType) priorStatus=$($record.PriorStatus)"
            }
        }
        else
        {
            $record = Restore-BaselineWinRMService
            if ([bool]$record.Skipped)
            {
                LogInfo "WinRM service restore skipped: $($record.SkipReason)"
            }
            else
            {
                LogInfo "WinRM service reversal summary: startTypeRestored=$($record.StartTypeRestored) started=$($record.Started) priorStartType=$($record.PriorStartType) priorStatus=$($record.PriorStatus)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure WinRM service state: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable the Baseline browser enterprise policies.

    .DESCRIPTION
    Applies or restores the Edge and Chrome policy values Baseline uses for enterprise-style browser hardening.

    .PARAMETER Enable
    Apply the Baseline browser enterprise policy set.

    .PARAMETER Disable
    Restore the saved browser enterprise policy values.

    .EXAMPLE
    BrowserEnterprisePolicies -Enable
#>
function BrowserEnterprisePolicies
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure browser enterprise policies"
    LogInfo "Configuring browser enterprise policies (Edge + Chrome + Firefox + Brave)"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $records = @(Set-BaselineBrowserPolicySettings)
            $applied = @($records | Where-Object { [bool]$_.Applied }).Count
            $skipped = @($records | Where-Object { -not [bool]$_.Applied }).Count
            $edgeCount    = @($records | Where-Object { $_.Browser -eq 'Edge' }).Count
            $chromeCount  = @($records | Where-Object { $_.Browser -eq 'Chrome' }).Count
            $firefoxCount = @($records | Where-Object { $_.Browser -eq 'Firefox' }).Count
            $braveCount   = @($records | Where-Object { $_.Browser -eq 'Brave' }).Count
            LogInfo "Browser policies summary: settings=$($records.Count) applied=$applied skipped=$skipped edge=$edgeCount chrome=$chromeCount firefox=$firefoxCount brave=$braveCount"
        }
        else
        {
            $records = @(Restore-BaselineBrowserPolicySettings)
            $restored = @($records | Where-Object { [bool]$_.Restored }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "Browser policies reversal summary: settings=$($records.Count) restored=$restored skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.Id): $($record.SkipReason)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure browser enterprise policies: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable the standard authentication hardening registry set.

    .DESCRIPTION
    Applies or restores the non-caution Kerberos, LDAP, Netlogon, smart card, and related authentication hardening settings managed by Baseline.

    .PARAMETER Enable
    Apply the standard Baseline authentication hardening settings.

    .PARAMETER Disable
    Restore the saved standard authentication hardening settings.

    .EXAMPLE
    AuthHardeningRegistry -Enable
#>
function AuthHardeningRegistry
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure authentication and domain hardening"
    LogInfo "Configuring authentication and domain hardening (Kerberos / LDAP / Netlogon / smart card / DLL search)"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        $auditSafe = @(Get-BaselineAuthHardeningSettings | Where-Object { -not [bool]$_.Caution })

        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $records = @(Set-BaselineAuthHardeningSettings -Settings $auditSafe)
            $applied = @($records | Where-Object { [bool]$_.Applied }).Count
            $skipped = @($records | Where-Object { -not [bool]$_.Applied }).Count
            LogInfo "Auth hardening summary: settings=$($records.Count) applied=$applied skipped=$skipped"
        }
        else
        {
            $records = @(Restore-BaselineAuthHardeningSettings -Settings $auditSafe)
            $restored = @($records | Where-Object { [bool]$_.Restored }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "Auth hardening reversal summary: settings=$($records.Count) restored=$restored skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.Id): $($record.SkipReason)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure authentication and domain hardening: $($_.Exception.Message)"
    }
}
<#
    .SYNOPSIS
    Enable or disable the caution authentication hardening registry set.

    .DESCRIPTION
    Applies or restores the higher-risk authentication settings, including the caution-marked NTLM audit and PowerShell lockdown entries managed by Baseline.

    .PARAMETER Enable
    Apply the caution Baseline authentication hardening settings.

    .PARAMETER Disable
    Restore the saved caution authentication hardening settings.

    .EXAMPLE
    AuthHardeningCautionRegistry -Enable
#>
function AuthHardeningCautionRegistry
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    Write-ConsoleStatus -Action "Configure NTLM audit + PowerShell CLM lockdown"
    LogInfo "Configuring NTLM audit traffic + PowerShell Constrained Language Mode"
    if ($PSCmdlet.ParameterSetName -eq 'None')
    {
        throw "Specify either -Enable or -Disable."
    }

    try
    {
        $cautionOnly = @(Get-BaselineAuthHardeningSettings | Where-Object { [bool]$_.Caution })

        if ($PSCmdlet.ParameterSetName -eq 'Enable')
        {
            $records = @(Set-BaselineAuthHardeningSettings -Settings $cautionOnly -IncludeCaution)
            $applied = @($records | Where-Object { [bool]$_.Applied }).Count
            $skipped = @($records | Where-Object { -not [bool]$_.Applied }).Count
            LogInfo "Auth hardening (caution) summary: settings=$($records.Count) applied=$applied skipped=$skipped"
        }
        else
        {
            $records = @(Restore-BaselineAuthHardeningSettings -Settings $cautionOnly)
            $restored = @($records | Where-Object { [bool]$_.Restored }).Count
            $skipped = @($records | Where-Object { [bool]$_.Skipped }).Count
            LogInfo "Auth hardening (caution) reversal summary: settings=$($records.Count) restored=$restored skipped=$skipped"
            foreach ($record in @($records | Where-Object { [bool]$_.Skipped }))
            {
                LogInfo "Skipped $($record.Id): $($record.SkipReason)"
            }
        }

        Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure NTLM audit + PowerShell CLM lockdown: $($_.Exception.Message)"
    }
}

#endregion Protection & Hardening
$ExportedFunctions = @(
    'ActiveXLockdown',
    'AdobereaderDCSTIG',
    'AirstrikeAttack',
    'AuditingBaseline',
    'AuthHardeningCautionRegistry',
    'AuthHardeningRegistry',
    'AutoRun',
    'BiometricsAntiSpoofing',
    'BrowserEnterprisePolicies',
    'CertPaddingCheck',
    'ClickOnce',
    'DLLHijackingPrevention',
    'EventLogSize',
    'FileSystemPerformance',
    'MacroRuntimeScanScope',
    'MountManagerAutoMount',
    'MsMsdtHandler',
    'MSOffice',
    'MSOfficeLinks',
    'NetbiosOverTcpip',
    'NetworkHardeningRegistry',
    'OneNoteEmbeds',
    'OS',
    'PowerShellTranscription',
    'PowerShellV2',
    'ProtectedCreds',
    'RansomwareScriptLockdown',
    'RegistryPaths',
    'RPCSurface',
    'RtfDocuments',
    'Test-BaselineAdobeReaderInstalled',
    'WDigestCaching',
    'WinRM',
    'WinRMService'
)
Export-ModuleMember -Function $ExportedFunctions
