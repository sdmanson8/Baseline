#region Protection & Hardening

<#
    .SYNOPSIS
    Increase the Security event log size.

    .EXAMPLE
    Update-EventLogSize

    .NOTES
    Machine-wide
#>
function Update-EventLogSize
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
    Enable-BiometricsAntiSpoofing

    .NOTES
    Machine-wide
#>
function Enable-BiometricsAntiSpoofing
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
        Set-ItemProperty -Path "HKLM:\$path" -Name "EnhancedAntiSpoofing" -Value 1 -ErrorAction Stop | Out-Null
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

    .PARAMETER path
    The registry path to create if it does not already exist.

    .EXAMPLE
    Update-RegistryPaths -path 'HKLM:\Software\Example'

    .NOTES
    Machine-wide
#>
function Update-RegistryPaths
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
    Protect-FileSystemPerformance

    .NOTES
    Machine-wide

    .CAUTION
    Disabling 8.3 short names can affect legacy applications, installers, or
    scripts that still depend on short path name behavior.
#>
function Protect-FileSystemPerformance
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
    Protect-OS

    .NOTES
    Machine-wide

    .CAUTION
    Changes authentication, networking, shell, and smart card related policy
    values. Review carefully in environments with legacy authentication,
    specialized networking, or smart-card workflows.
#>
function Protect-OS
{
    Write-ConsoleStatus -Action "Configure OS to be Hardened"
	LogInfo "Configuring OS to be Hardened"
    try
    {
        $wdigestPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
        if (Test-Path $wdigestPath)
		{
            Set-ItemProperty -Path $wdigestPath -Name "UseLogonCredential" -Value 0 -ErrorAction Stop | Out-Null
        }

        $kerberosPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters"
        if (Test-Path $kerberosPath)
		{
            Set-ItemProperty -Path $kerberosPath -Name "SupportedEncryptionTypes" -Value 2147483640 -ErrorAction Stop | Out-Null
        }

        $tcpipPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        if (Test-Path $tcpipPath)
		{
            Set-ItemProperty -Path $tcpipPath -Name "EnableICMPRedirect" -Value 0 -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $tcpipPath -Name "DisableIPSourceRouting" -Value 2 -ErrorAction Stop | Out-Null
        }

        $systemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        if (Test-Path $systemPath)
		{
            Set-ItemProperty -Path $systemPath -Name "EnableLUA" -Value 1 -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $systemPath -Name "EnableVirtualization" -Value 1 -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $systemPath -Name "ConsentPromptBehaviorAdmin" -Value 2 -ErrorAction Stop | Out-Null
        }

        $explorerPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        if (!(Test-Path $explorerPolicyPath))
		{
            New-Item -Path $explorerPolicyPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $explorerPolicyPath -Name "NoDataExecutionPrevention" -Value 0 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $explorerPolicyPath -Name "NoHeapTerminationOnCorruption" -Value 0 -ErrorAction Stop | Out-Null

        $wcmPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy"
        if (!(Test-Path $wcmPath))
		{
            New-Item -Path $wcmPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $wcmPath -Name "fMinimizeConnections" -Value 1 -ErrorAction Stop | Out-Null

        $netbtPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netbt\Parameters"
        if (Test-Path $netbtPath)
		{
            Set-ItemProperty -Path $netbtPath -Name "NoNameReleaseOnDemand" -Value 1 -ErrorAction Stop | Out-Null
        }

        $msv10Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
        if (Test-Path $msv10Path)
		{
            Set-ItemProperty -Path $msv10Path -Name "NTLMMinServerSec" -Value 537395200 -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $msv10Path -Name "NTLMMinClientSec" -Value 537395200 -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $msv10Path -Name "allownullsessionfallback" -Value 0 -ErrorAction Stop | Out-Null
        }

        $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        if (Test-Path $lsaPath)
		{
            Set-ItemProperty -Path $lsaPath -Name "RestrictRemoteSAM" -Value "O:BAG:BAD:(A;;RC;;;BA)" -ErrorAction Stop | Out-Null
        }

        $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        if (Test-Path $winlogonPath)
		{
            Set-ItemProperty -Path $winlogonPath -Name "SCRemoveOption" -Value 2 -ErrorAction Stop | Out-Null
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
    Apply the Adobe Reader DC security settings used by this preset.

    .DESCRIPTION
    Applies a broad Adobe Reader DC policy set when Reader is detected,
    including maintenance, services, protected mode, protected view, and
    feature lockdown related settings.

    .EXAMPLE
    Update-AdobereaderDCSTIG

    .NOTES
    Machine-wide

    .CAUTION
    Can affect Adobe update behavior, cloud/share integrations, and document
    handling features that depend on less restrictive Reader settings.
#>
function Update-AdobereaderDCSTIG
{
    Write-ConsoleStatus -Action "Configure Adobe Reader Security"
	LogInfo "Configuring Adobe Reader Security"
    $adobePolicyRoot = "HKLM:\Software\Policies\Adobe\Acrobat Reader\DC"
    $adobeWowInstallerPath = "HKLM:\Software\Wow6432Node\Adobe\Acrobat Reader\DC\Installer"
    $adobeCurrentUserPath = "HKCU:\Software\Policies\Adobe\Acrobat Reader\DC\Privileged"
    $adobeInstalled = (Test-Path "HKLM:\Software\Adobe\Acrobat Reader\DC") -or
        (Test-Path "HKLM:\Software\Policies\Adobe\Acrobat Reader\DC") -or
        (Test-Path "HKCU:\Software\Adobe\Acrobat Reader\DC") -or
        (Test-Path $adobeCurrentUserPath)

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
        Set-ItemProperty -Path "HKLM:\Software\Adobe\Acrobat Reader\DC\Installer" -Name "DisableMaintenance" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $adobeWowInstallerPath -Name "DisableMaintenance" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bAcroSuppressUpsell" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bDisablePDFHandlerSwitching" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bDisableTrustedFolders" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bDisableTrustedSites" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bEnableFlash" -Value 0 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bEnhancedSecurityInBrowser" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bEnhancedSecurityStandalone" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "bProtectedMode" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "iFileAttachmentPerms" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $featureLockDownPath -Name "iProtectedView" -Value 2 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cCloud" -Name "bAdobeSendPluginToggle" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cDefaultLaunchURLPerms" -Name "iURLPerms" -Value 3 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cDefaultLaunchURLPerms" -Name "iUnknownURLPerms" -Value 2 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cServices" -Name "bToggleAdobeDocumentServices" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cServices" -Name "bToggleAdobeSign" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cServices" -Name "bTogglePrefsSync" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cServices" -Name "bToggleWebConnectors" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cServices" -Name "bUpdater" -Value 0 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cSharePoint" -Name "bDisableSharePointFeatures" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cWebmailProfiles" -Name "bDisableWebmail" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "$featureLockDownPath\cWelcomeScreen" -Name "bShowWelcomeScreen" -Value 0 -ErrorAction Stop | Out-Null

        if (Test-Path $adobeCurrentUserPath)
		{
            Set-ItemProperty -Path $adobeCurrentUserPath -Name "bProtectedMode" -Value 0 -ErrorAction SilentlyContinue | Out-Null
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
    Protect-ClickOnce

    .NOTES
    Machine-wide

    .CAUTION
    Advanced. Can break ClickOnce-based installers, updates, or internal
    applications that depend on trust prompts.
#>
function Protect-ClickOnce
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
            Set-ItemProperty -Path $promptingPath -Name $zone -Value "Disabled" -ErrorAction Stop | Out-Null
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
    Protect-MSOffice

    .NOTES
    Current user

    .CAUTION
    Can affect macros, Office automation, downloaded Office documents, and
    workflows that rely on active content or permissive Outlook trust behavior.
#>
function Protect-MSOffice
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
                Set-ItemProperty -Path $wordPath -Name "vbawarnings" -Value 4 -ErrorAction Stop | Out-Null
            }

            if (Test-Path $publisherPath)
			{
                Set-ItemProperty -Path $publisherPath -Name "vbawarnings" -Value 4 -ErrorAction Stop | Out-Null
            }

            if (($version -in @("15.0", "16.0")) -and (Test-Path $excelPath))
			{
                Set-ItemProperty -Path $excelPath -Name "blockcontentexecutionfrominternet" -Value 1 -ErrorAction Stop | Out-Null
            }

            if (($version -in @("15.0", "16.0")) -and (Test-Path $powerPointPath))
			{
                Set-ItemProperty -Path $powerPointPath -Name "blockcontentexecutionfrominternet" -Value 1 -ErrorAction Stop | Out-Null
            }

            if (($version -in @("15.0", "16.0")) -and (Test-Path $outlookPath))
			{
                Set-ItemProperty -Path $outlookPath -Name "markinternalasunsafe" -Value 0 -ErrorAction Stop | Out-Null
            }
        }

        $word15Path = "HKCU:\Software\Policies\Microsoft\Office\15.0\Word\Security"
        $word16Path = "HKCU:\Software\Policies\Microsoft\Office\16.0\Word\Security"

        if (Test-Path $word15Path)
		{
            Set-ItemProperty -Path $word15Path -Name "blockcontentexecutionfrominternet" -Value 1 -ErrorAction Stop | Out-Null
        }

        if (Test-Path $word16Path)
		{
            Set-ItemProperty -Path $word16Path -Name "blockcontentexecutionfrominternet" -Value 1 -ErrorAction Stop | Out-Null
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
    Protect-MSOfficeLinks

    .NOTES
    Current user

    .CAUTION
    Can affect documents or mail workflows that intentionally rely on
    automatic external link refresh behavior.
#>
function Protect-MSOfficeLinks
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

            Set-ItemProperty -Path $wordPath -Name "DontUpdateLinks" -Value 1 -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $wordMailPath -Name "DontUpdateLinks" -Value 1 -ErrorAction Stop | Out-Null
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
    Protect-WinRM

    .NOTES
    Machine-wide

    .CAUTION
    Can break legacy WinRM clients or management tooling that relies on digest
    authentication or weaker transport settings.
#>
function Protect-WinRM
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
        Set-ItemProperty -Path $servicePath -Name "AllowUnencryptedTraffic" -Value 0 -ErrorAction Stop | Out-Null

        $clientPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
        if (!(Test-Path $clientPath))
		{
            New-Item -Path $clientPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $clientPath -Name "AllowDigest" -Value 0 -ErrorAction Stop | Out-Null

        # Restart WinRM only if it was running before — the service may be disabled or unavailable
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
    Set-DLLHijackingPrevention

    .NOTES
    Machine-wide
#>
function Set-DLLHijackingPrevention
{
    Write-ConsoleStatus -Action "Configure DLL Hijacking Prevention"
	LogInfo "Configuring DLL Hijacking Prevention"
    try
    {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "CWDIllegalInDllSearch" -Value 2 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "SafeDLLSearchMode" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "ProtectionMode" -Value 1 -ErrorAction Stop | Out-Null
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
    Suspend-AirstrikeAttack

    .NOTES
    Machine-wide
#>
function Suspend-AirstrikeAttack
{
    Write-ConsoleStatus -Action "Restrict local Windows wireless exploitation"
	LogInfo "Restricting local Windows wireless exploitation"
    try
    {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DontDisplayNetworkSelectionUI" -Value 1 -ErrorAction Stop | Out-Null
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
    Protect-RPCSurface

    .NOTES
    Machine-wide

    .CAUTION
    Can break remote task scheduling, remote service control, and management
    products that depend on those RPC paths.
#>
function Protect-RPCSurface
{
    Write-ConsoleStatus -Action "Configure RPC surface reduction"
	LogInfo "Configuring RPC surface reduction"
    try
    {
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Schedule" -Name "DisableRpcOverTcp" -Value 1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "DisableRemoteScmEndpoints" -Value 1 -ErrorAction Stop | Out-Null
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
    Disable-AutoRun

    .NOTES
    Current user, Machine-wide
#>
function Disable-AutoRun
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

            New-ItemProperty -Path $path -Name "NoDriveTypeAutoRun" -PropertyType DWord -Value 0xFF -Force -ErrorAction Stop | Out-Null
        }
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable AutoRun: $($_.Exception.Message)"
    }
}

#endregion Protection & Hardening

Export-ModuleMember -Function '*'
