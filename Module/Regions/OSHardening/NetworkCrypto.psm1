#region Network & Cryptography Hardening

<#
    .SYNOPSIS
    Enable or disable DCOM and legacy remote command surfaces.

    .DESCRIPTION
    Controls DCOM remote activation and device metadata file associations.
    DCOM is required by SCCM, remote WMI, and many enterprise tools.
    Disabling reduces attack surface but may break remote management.

    .PARAMETER Disable
    Disable DCOM and remove device metadata associations (hardened).

    .PARAMETER Enable
    Re-enable DCOM for enterprise/remote management compatibility.

    .EXAMPLE
    Disable-RemoteCommands -Disable

    .EXAMPLE
    Disable-RemoteCommands -Enable

    .NOTES
    Machine-wide
#>
function Disable-RemoteCommands {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable,

		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable
	)

	$action   = if ($Disable) { "Disabling" } else { "Enabling" }
	$dcomVal  = if ($Disable) { "N" }         else { "Y" }

    Write-ConsoleStatus -Action "$action Remote Commands (DCOM)"
	LogInfo "$action Remote Commands (DCOM)"
    try
    {
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\OLE" -Name "EnableDCOM" -Value $dcomVal -ErrorAction Stop | Out-Null

		if ($Disable)
		{
			if (Test-Path "HKLM:\SOFTWARE\Classes\.devicemetadata-ms")
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Classes\.devicemetadata-ms" -Name "default" | Out-Null
			}

			if (Test-Path "HKLM:\SOFTWARE\Classes\.devicemanifest-ms")
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Classes\.devicemanifest-ms" -Name "default" | Out-Null
			}
		}

		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to $($action.ToLower()) remote commands: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Configure the SCHANNEL cipher suite list used by this preset.

    .EXAMPLE
    Update-CipherSuites

    .NOTES
    Machine-wide
#>
function Update-CipherSuites
{
    Write-ConsoleStatus -Action "Configure Cipher Suites"
	LogInfo "Configuring Cipher Suites"
    try
	{
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\CipherSuites" -Name "TLS_RSA_WITH_AES_256_CBC_SHA256" -Value 0x1 -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\CipherSuites" -Name "TLS_RSA_WITH_AES_128_CBC_SHA256" -Value 0x1 -ErrorAction Stop | Out-Null
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure cipher suites: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Configure SCHANNEL key exchange algorithm settings.

    .EXAMPLE
    Update-KeyExchanges

    .NOTES
    Machine-wide
#>
function Update-KeyExchanges
{
    Write-ConsoleStatus -Action "Configure Key Exchanges"
	LogInfo "Configuring Key Exchanges"
    try
	{
        $keyPaths = @(
            'Diffie-Hellman', 'ECDH', 'PKCS'
        )

        foreach ($keyPath in $keyPaths)
		{
            $fullPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\$keyPath"

            if (-not (Test-Path $fullPath))
			{
                New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms" -Name $keyPath -Force -ErrorAction Stop | Out-Null
            }

            Set-ItemProperty -Path $fullPath -Name 'Enabled' -Value 0xffffffff -ErrorAction Stop | Out-Null
        }
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure key exchange algorithms: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Configure SSL and TLS protocol settings in SCHANNEL.

    .DESCRIPTION
    Manages legacy protocol state (TLS 1.0, TLS 1.1) in the Windows SCHANNEL
    registry. Older broken protocols (PCT 1.0, SSL 2.0, SSL 3.0, Multi-Protocol
    Unified Hello) are always disabled regardless of the toggle.

    .PARAMETER Disable
    Disable TLS 1.0 and TLS 1.1 (recommended). Both protocols are deprecated
    per RFC 8996 and have known vulnerabilities (BEAST, POODLE).

    .PARAMETER Enable
    Re-enable TLS 1.0 and TLS 1.1 for legacy compatibility. Only use this if
    you have devices or services that cannot negotiate TLS 1.2+.

    .EXAMPLE
    Update-Protocols -Disable

    .EXAMPLE
    Update-Protocols -Enable

    .NOTES
    Machine-wide
#>
function Update-Protocols
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable,

		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable
	)

	$action = if ($Disable) { "Disabling" } else { "Enabling" }
    Write-ConsoleStatus -Action "$action legacy TLS protocols (TLS 1.0/1.1)"
	LogInfo "$action legacy TLS protocols (TLS 1.0/1.1)"
    try
	{
		# Legacy TLS 1.0/1.1 values based on toggle
		$legacyEnabled        = if ($Enable) { 0xffffffff } else { 0 }
		$legacyDisabledByDflt = if ($Enable) { 0 }          else { 1 }

        $protocols = @{
            'Multi-Protocol Unified Hello\Client' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'Multi-Protocol Unified Hello\Server' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'PCT 1.0\Client' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'PCT 1.0\Server' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'SSL 2.0\Client' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'SSL 2.0\Server' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'SSL 3.0\Client' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'SSL 3.0\Server' = @{'Enabled' = 0; 'DisabledByDefault' = 1}
            'TLS 1.0\Client' = @{'Enabled' = $legacyEnabled; 'DisabledByDefault' = $legacyDisabledByDflt}
            'TLS 1.0\Server' = @{'Enabled' = $legacyEnabled; 'DisabledByDefault' = $legacyDisabledByDflt}
            'TLS 1.1\Client' = @{'Enabled' = $legacyEnabled; 'DisabledByDefault' = $legacyDisabledByDflt}
            'TLS 1.1\Server' = @{'Enabled' = $legacyEnabled; 'DisabledByDefault' = $legacyDisabledByDflt}
            'TLS 1.2\Client' = @{'Enabled' = 0xffffffff; 'DisabledByDefault' = 0}
            'TLS 1.2\Server' = @{'Enabled' = 0xffffffff; 'DisabledByDefault' = 0}
        }
        foreach ($protocol in $protocols.Keys)
		{
            foreach ($key in $protocols[$protocol].Keys)
			{
                $protocolPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$protocol"

                if (Update-RegistryPaths -path $protocolPath)
				{
                    Set-ItemProperty -Path $protocolPath -Name $key -Value $protocols[$protocol][$key] -ErrorAction Stop | Out-Null
				}
            }
        }
        Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure SSL/TLS protocol settings: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Enable strong .NET authentication behavior.

    .EXAMPLE
    Update-DotNetStrongAuth

    .NOTES
    Machine-wide
#>
function Update-DotNetStrongAuth
{
    Write-ConsoleStatus -Action "Use Strong .Net Authentication"
	LogInfo "Using Strong .Net Authentication"
    try
	{
        $paths = @(
            "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319",
            "HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727"
        )

        foreach ($path in $paths)
        {
            if (-not (Test-Path -Path $path))
            {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }

            New-ItemProperty -Path $path -Name "SchUseStrongCrypto" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $path -Name "SystemDefaultTlsVersions" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        }
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to enable strong .NET authentication: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable SCHANNEL cipher entries defined in this preset.

    .EXAMPLE
    Disable-AESCiphers

    .NOTES
    Machine-wide
#>
function Disable-AESCiphers
{
    Write-ConsoleStatus -Action "Disable AES Ciphers"
	LogInfo "Disabling AES Ciphers"
    try
	{
        $ciphers = @(
            'AES 128/128', 'AES 256/256', 'DES 56/56', 'RC2 128/128', 'RC4 128/128'
        )
        foreach ($cipher in $ciphers)
		{
            $cipherPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$cipher"

            if (-not (Test-Path $cipherPath))
			{
                New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers" -Name $cipher -Force -ErrorAction Stop | Out-Null
            }

            Set-ItemProperty -Path $cipherPath -Name 'Enabled' -Value 0 -ErrorAction Stop | Out-Null
        }
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable AES ciphers: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable IPv6.

    .EXAMPLE
    Disable-IPv6

    .NOTES
    Machine-wide
#>
function Disable-IPv6
{
    Write-ConsoleStatus -Action "Disable IPv6"
	LogInfo "Disabling IPv6"
    try
    {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\tcpip6\parameters" -Name "DisabledComponents" -Value 0xFF -ErrorAction Stop | Out-Null
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable IPv6: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable RC2 and RC4 SCHANNEL ciphers.

    .EXAMPLE
    Disable-RC2RC4Ciphers

    .NOTES
    Machine-wide
#>
function Disable-RC2RC4Ciphers
{
    Write-ConsoleStatus -Action "Disable RC2 and RC4 Ciphers"
	LogInfo "Disabling RC2 and RC4 Ciphers"
    try
	{
        $rcCiphers = @("RC2 128/128", "RC2 40/128", "RC2 56/128", "RC4 128/128", "RC4 40/128", "RC4 56/128", "RC4 64/128")
        foreach ($cipher in $rcCiphers)
		{
            $cipherPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$cipher"

            if (-not (Test-Path $cipherPath))
			{
                New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers" -Name $cipher -Force -ErrorAction Stop | Out-Null
            }

            Set-ItemProperty -Path $cipherPath -Name 'Enabled' -Value 0 -ErrorAction Stop | Out-Null
        }
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable RC2 and RC4 ciphers: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable SMBv3 compression.

    .DESCRIPTION
    Turns off SMB compression at the server service level as part of the
    module's network hardening preset.

    .EXAMPLE
    Disable-SMBv3Compression

    .NOTES
    Machine-wide
#>
function Disable-SMBv3Compression
{
    Write-ConsoleStatus -Action "Disable SMB version 3 Compression"
	LogInfo "Disabling SMB version 3 Compression"
    try
    {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "DisableCompression" -Value 1 -ErrorAction Stop | Out-Null
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable SMBv3 compression: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable TCP timestamps.

    .EXAMPLE
    Disable-TCPTimestamps

    .NOTES
    Machine-wide
#>
function Disable-TCPTimestamps
{
    Write-ConsoleStatus -Action "Disable TCP Timestamps"
	LogInfo "Disabling TCP Timestamps"
    try
	{
        netsh int tcp set global timestamps=disabled 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            throw "netsh returned exit code $LASTEXITCODE"
        }
		Write-ConsoleStatus -Status success
    }
    catch
    {
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable TCP timestamps: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Disable the Triple DES SCHANNEL cipher.

    .EXAMPLE
    Disable-TripleDESCipher

    .NOTES
    Machine-wide
#>
function Disable-TripleDESCipher
{
    Write-ConsoleStatus -Action "Disable Triple DES Ciphers"
	LogInfo "Disabling Triple DES Ciphers"
    try
	{
        $cipherPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168'

        if (-not (Test-Path $cipherPath))
		{
            New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers' -Name 'Triple DES 168' -Force -ErrorAction Stop | Out-Null
        }

        Set-ItemProperty -Path $cipherPath -Name 'Enabled' -Value 0 -ErrorAction Stop | Out-Null
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to disable the Triple DES cipher: $($_.Exception.Message)"
    }
}

<#
    .SYNOPSIS
    Configure SCHANNEL hash algorithm settings.

    .EXAMPLE
    Disable-HashAlgorithms

    .NOTES
    Machine-wide
#>
function Disable-HashAlgorithms
{
    Write-ConsoleStatus -Action "Disable Hash Algorithms"
	LogInfo "Disabling Hash Algorithms"
    try
	{
        $hashes = @('MD5', 'SHA', 'SHA256', 'SHA384', 'SHA512')

        foreach ($hash in $hashes)
		{
            $hashPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\$hash"

            if (-not (Test-Path $hashPath))
			{
                New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes" -Name $hash -Force -ErrorAction Stop | Out-Null
            }

            Set-ItemProperty -Path $hashPath -Name 'Enabled' -Value 0xffffffff -ErrorAction Stop | Out-Null
        }
		Write-ConsoleStatus -Status success
    }
    catch
	{
        Write-ConsoleStatus -Status failed
        LogError "Failed to configure SCHANNEL hash algorithms: $($_.Exception.Message)"
    }
}

#endregion Network & Cryptography Hardening

Export-ModuleMember -Function '*'
