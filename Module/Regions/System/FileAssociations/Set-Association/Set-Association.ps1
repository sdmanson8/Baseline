try
	{
	$null = @(
		Write-ConsoleStatus -Action "Associating $Extension files with $ProgramPath"
		LogInfo "Associating $Extension files with $ProgramPath"

		# Microsoft has blocked write access to UserChoice key for .pdf extention and http/https protocols with KB5034765 release, so we have to write values with a copy of powershell.exe to bypass a UCPD driver restrictions
		# UCPD driver tracks all executables to block the access to the registry so all registry records will be made within powershell_temp.exe in this function just in case
		Copy-Item -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination $TempPowerShellPath -Force -ErrorAction Stop 2>&1 | Out-Null
		if (-not (Test-Path -Path $TempPowerShellPath))
		{
			throw "Temporary PowerShell copy was not created"
		}
		$invokeTempPowerShellScript = {
			param (
				[Parameter(Mandatory = $true)]
				[string]$ScriptText,

				[Parameter(Mandatory = $true)]
				[string]$Operation
			)

			$tempScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('Baseline-Association-{0}.ps1' -f ([guid]::NewGuid().ToString('N')))
			try
			{
				Set-Content -LiteralPath $tempScriptPath -Value $ScriptText -Encoding UTF8 -Force -ErrorAction Stop
				$null = Invoke-BaselineProcess `
					-FilePath $TempPowerShellPath `
					-ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $tempScriptPath) `
					-TimeoutSeconds 300 `
					-AllowedExitCodes @(0)
			}
			catch
			{
				throw "$Operation failed: $($_.Exception.Message)"
			}
			finally
			{
				Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue | Out-Null
			}
		}.GetNewClosure()

		$ProgramPath = [System.Environment]::ExpandEnvironmentVariables($ProgramPath)

		if ($ProgramPath.Contains(":"))
		{
			# Cut string to get executable path to check
			$ProgramPath = $ProgramPath.Substring(0, $ProgramPath.IndexOf(".exe") + 4).Trim('"')
			if (-not (Test-Path -Path $ProgramPath))
			{
				# We cannot call here (Get-TweakSkipLabel $MyInvocation) to print function with error
				if ($Icon)
				{
					LogError ($Localization.RestartFunction -f "Set-Association -ProgramPath `"$ProgramPath`" -Extension $Extension -Icon `"$Icon`"")
				}
				else
				{
					LogError ($Localization.RestartFunction -f "Set-Association -ProgramPath `"$ProgramPath`" -Extension $Extension")
				}
				throw "Program path was not found: $ProgramPath"
			}
		}
		else
		{
			# ProgId is not registered
			if (-not (Test-Path -Path "Registry::HKEY_CLASSES_ROOT\$ProgramPath"))
			{
				# We cannot call here (Get-TweakSkipLabel $MyInvocation) to print function with error
				if ($Icon)
				{
					LogError ($Localization.RestartFunction -f "Set-Association -ProgramPath `"$ProgramPath`" -Extension `"$Extension`" -Icon `"$Icon`"")
				}
				else
				{
					LogError ($Localization.RestartFunction -f "Set-Association -ProgramPath `"$ProgramPath`" -Extension `"$Extension`"")
				}
				throw "Program path or ProgID was not found: $ProgramPath"
			}
		}

		if ($Icon)
		{
			$Icon = [System.Environment]::ExpandEnvironmentVariables($Icon)
		}

		if (Test-Path -Path $ProgramPath)
		{
			# Generate ProgId
			$ProgId = (Get-Item -Path $ProgramPath).BaseName + $Extension.ToUpper()
		}
		else
		{
			$ProgId = $ProgramPath
		}

		#region functions
		$Signature = @{
			Namespace          = "WinAPI"
			Name               = "Action"
			Language           = "CSharp"
			UsingNamespace     = "System.Text", "System.Security.AccessControl", "Microsoft.Win32"
			CompilerParameters = $CompilerParameters
			MemberDefinition   = @"
[DllImport("advapi32.dll", CharSet = CharSet.Auto)]
private static extern int RegOpenKeyEx(UIntPtr hKey, string subKey, int ulOptions, int samDesired, out UIntPtr hkResult);

[DllImport("advapi32.dll", SetLastError = true)]
private static extern int RegCloseKey(UIntPtr hKey);

[DllImport("advapi32.dll", SetLastError=true, CharSet = CharSet.Unicode)]
private static extern uint RegDeleteKey(UIntPtr hKey, string subKey);

[DllImport("advapi32.dll", EntryPoint = "RegQueryInfoKey", CallingConvention = CallingConvention.Winapi, SetLastError = true)]
private static extern int RegQueryInfoKey(UIntPtr hkey, out StringBuilder lpClass, ref uint lpcbClass, IntPtr lpReserved,
	out uint lpcSubKeys, out uint lpcbMaxSubKeyLen, out uint lpcbMaxClassLen, out uint lpcValues, out uint lpcbMaxValueNameLen,
	out uint lpcbMaxValueLen, out uint lpcbSecurityDescriptor, ref System.Runtime.InteropServices.ComTypes.FILETIME lpftLastWriteTime);

[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);

[DllImport("kernel32.dll", ExactSpelling = true)]
internal static extern IntPtr GetCurrentProcess();

[DllImport("advapi32.dll", SetLastError = true)]
internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

[DllImport("advapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
private static extern int RegLoadKey(uint hKey, string lpSubKey, string lpFile);

[DllImport("advapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
private static extern int RegUnLoadKey(uint hKey, string lpSubKey);

[StructLayout(LayoutKind.Sequential, Pack = 1)]
internal struct TokPriv1Luid
{
	public int Count;
	public long Luid;
	public int Attr;
}

public static void DeleteKey(RegistryHive registryHive, string subkey)
{
	UIntPtr hKey = UIntPtr.Zero;

	try
	{
		var hive = new UIntPtr(unchecked((uint)registryHive));
		RegOpenKeyEx(hive, subkey, 0, 0x20019, out hKey);
		RegDeleteKey(hive, subkey);
	}
	finally
	{
		if (hKey != UIntPtr.Zero)
		{
			RegCloseKey(hKey);
		}
	}
}

private static DateTime ToDateTime(System.Runtime.InteropServices.ComTypes.FILETIME ft)
{
	IntPtr buf = IntPtr.Zero;
	try
	{
		long[] longArray = new long[1];
		int cb = Marshal.SizeOf(ft);
		buf = Marshal.AllocHGlobal(cb);
		Marshal.StructureToPtr(ft, buf, false);
		Marshal.Copy(buf, longArray, 0, 1);
		return DateTime.FromFileTime(longArray[0]);
	}
	finally
	{
		if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
	}
}

public static DateTime? GetLastModified(RegistryHive registryHive, string subKey)
{
	var lastModified = new System.Runtime.InteropServices.ComTypes.FILETIME();
	var lpcbClass = new uint();
	var lpReserved = new IntPtr();
	UIntPtr hKey = UIntPtr.Zero;

	try
	{
		try
		{
			var hive = new UIntPtr(unchecked((uint)registryHive));
			if (RegOpenKeyEx(hive, subKey, 0, (int)RegistryRights.ReadKey, out hKey) != 0)
			{
				return null;
			}

			uint lpcbSubKeys;
			uint lpcbMaxKeyLen;
			uint lpcbMaxClassLen;
			uint lpcValues;
			uint maxValueName;
			uint maxValueLen;
			uint securityDescriptor;
			StringBuilder sb;

			if (RegQueryInfoKey(hKey, out sb, ref lpcbClass, lpReserved, out lpcbSubKeys, out lpcbMaxKeyLen, out lpcbMaxClassLen,
			out lpcValues, out maxValueName, out maxValueLen, out securityDescriptor, ref lastModified) != 0)
			{
				return null;
			}

			var result = ToDateTime(lastModified);
			return result;
		}
		finally
		{
			if (hKey != UIntPtr.Zero)
			{
				RegCloseKey(hKey);
			}
		}
	}
	catch (Exception)
	{
		return null;
	}
}

internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
internal const int TOKEN_QUERY = 0x00000008;
internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

public enum RegistryHives : uint
{
	HKEY_USERS = 0x80000003,
	HKEY_LOCAL_MACHINE = 0x80000002
}

public static void AddPrivilege(string privilege)
{
	bool retVal;
	TokPriv1Luid tp;
	IntPtr hproc = GetCurrentProcess();
	IntPtr htok = IntPtr.Zero;
	retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
	tp.Count = 1;
	tp.Luid = 0;
	tp.Attr = SE_PRIVILEGE_ENABLED;
	retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
	retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
	///return retVal;
}

public static int LoadHive(RegistryHives hive, string subKey, string filePath)
{
	AddPrivilege("SeRestorePrivilege");
	AddPrivilege("SeBackupPrivilege");

	uint regHive = (uint)hive;
	int result = RegLoadKey(regHive, subKey, filePath);

	return result;
}

public static int UnloadHive(RegistryHives hive, string subKey)
{
	AddPrivilege("SeRestorePrivilege");
	AddPrivilege("SeBackupPrivilege");

	uint regHive = (uint)hive;
	int result = RegUnLoadKey(regHive, subKey);

	return result;
}
"@
		}

		if (-not ("WinAPI.Action" -as [type]))
		{
			Add-Type @Signature -ErrorAction SilentlyContinue 2>&1 | Out-Null
		}

		Clear-Variable -Name RegisteredProgIDs -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

		[array]$Script:RegisteredProgIDs = @()

		<#
		    .SYNOPSIS
		    Writes extension keys.

				#>

		function Write-ExtensionKeys
		{
			Param
			(
				[Parameter(
					Mandatory = $true,
					Position = 0
				)]
				[string]
				$ProgId,

				[Parameter(
					Mandatory = $true,
					Position = 1
				)]
				[string]
				$Extension
			)

			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			$OrigProgID = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$Extension", "", $null)
			if ($OrigProgID)
			{
				# Save ProgIds history with extensions or protocols for the system ProgId
				$Script:RegisteredProgIDs += $OrigProgID
			}

			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$Extension", "", $null) -ne "")
			{
				# Save possible ProgIds history with extension
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name "$($ProgID)_$($Extension)" -Type DWord -Value 0 | Out-Null
			}

			$Name = "{0}_$($Extension)" -f (Split-Path -Path $ProgId -Leaf)
			Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name $Name -Type DWord -Value 0 | Out-Null

			if ("$($ProgID)_$($Extension)" -ne $Name)
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name "$($ProgID)_$($Extension)" -Type DWord -Value 0 | Out-Null
			}

			# If ProgId doesn't exist set the specified ProgId for the extensions
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if (-not [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$Extension", "", $null))
			{
				if (-not (Test-Path -Path "HKCU:\Software\Classes\$Extension"))
				{
					New-Item -Path "HKCU:\Software\Classes\$Extension" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$Extension" -Name "(default)" -Type String -Value $ProgId | Out-Null
			}

			# Set the specified ProgId in the possible options for the assignment
			if (-not (Test-Path -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids"))
			{
				New-Item -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Name $ProgId -Type None -Value ([byte[]]@()) | Out-Null

			# Set the system ProgId to the extension parameters for File Explorer to the possible options for the assignment, and if absent set the specified ProgId
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if ($OrigProgID)
			{
				if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithProgids"))
				{
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithProgids" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithProgids" -Name $OrigProgID -Type None -Value ([byte[]]@()) | Out-Null
			}

			if (-not (Test-Path -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids"))
			{
				New-Item -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Name $ProgID -Type None -Value ([byte[]]@()) | Out-Null

			# A small pause added to complete all operations, unless sometimes PowerShell has not time to clear reguistry permissions
			Start-Sleep -Seconds 1

			# Removing the UserChoice key
			[WinAPI.Action]::DeleteKey([Microsoft.Win32.RegistryHive]::CurrentUser, "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice")
			Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

			# Setting parameters in UserChoice. The key is being autocreated
			if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"))
			{
				New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			# We need to remove DENY permission set for user before setting a value
			if (@(".pdf", "http", "https") -contains $Extension)
			{
				# https://powertoe.wordpress.com/2010/08/28/controlling-registry-acl-permissions-with-powershell/
				$Key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice",[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::ChangePermissions)
				$ACL = $key.GetAccessControl()
				$Principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
				# https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights
				$Rule = New-Object -TypeName System.Security.AccessControl.RegistryAccessRule -ArgumentList ($Principal,"FullControl","Deny")
				$ACL.RemoveAccessRule($Rule)
				$Key.SetAccessControl($ACL)

				# Write the protected values through a temporary script executed by the UCPD-bypassed PowerShell copy.
				# Escape single quotes in interpolated values to prevent command-string injection.
				$EscExtension = $Extension -replace "'", "''"
				$EscProgID    = $ProgID    -replace "'", "''"
				$setProgIdScript = "New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$EscExtension\UserChoice' -Name ProgId -PropertyType String -Value '$EscProgID' -Force -ErrorAction Stop | Out-Null"
				& $invokeTempPowerShellScript -ScriptText $setProgIdScript -Operation "Setting ProgId for $Extension"
			}
			else
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Name ProgId -Type String -Value $ProgID | Out-Null
			}

			# Getting a hash based on the time of the section's last modification. After creating and setting the first parameter
			$ProgHash = Get-Hash -ProgId $ProgId -Extension $Extension -SubKey "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"

			if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"))
			{
				New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			if (@(".pdf", "http", "https") -contains $Extension)
			{
				# Write the protected hash through the same temporary-script path.
				$EscProgHash = $ProgHash -replace "'", "''"
				$setHashScript = "New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$EscExtension\UserChoice' -Name Hash -PropertyType String -Value '$EscProgHash' -Force -ErrorAction Stop | Out-Null"
				& $invokeTempPowerShellScript -ScriptText $setHashScript -Operation "Setting Hash for $Extension"
			}
			else
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Name Hash -Type String -Value $ProgHash | Out-Null
			}

			# Setting a block on changing the UserChoice section
			# We have to use OpenSubKey() due to "Set-StrictMode -Version Latest"
			$OpenSubKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice", "ReadWriteSubTree", "TakeOwnership")
			if ($OpenSubKey)
			{
				$Acl = [System.Security.AccessControl.RegistrySecurity]::new()
				# Get current user SID
				$UserSID = (Get-CimInstance -ClassName Win32_UserAccount | Where-Object -FilterScript {$_.Name -eq $env:USERNAME}).SID
				$Acl.SetSecurityDescriptorSddlForm("O:$UserSID`G:$UserSID`D:AI(D;;DC;;;$UserSID)")
				$OpenSubKey.SetAccessControl($Acl)
				$OpenSubKey.Close()
			}
		}

		<#
		    .SYNOPSIS
		    Writes additional keys.

				#>

		function Write-AdditionalKeys
		{
			Param
			(
				[Parameter(
					Mandatory = $true,
					Position = 0
				)]
				[string]
				$ProgId,

				[Parameter(
					Mandatory = $true,
					Position = 1
				)]
				[string]
				$Extension
			)

			# If there is the system extension ProgId, write it to the already configured by default
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$Extension", "", $null))
			{
				if (-not (Test-Path -Path Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\FileAssociations\ProgIds))
				{
					New-Item -Path Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\FileAssociations\ProgIds -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
				}
				Set-RegistryValueSafe -Path "Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\FileAssociations\ProgIds" -Name "_$($Extension)" -Type DWord -Value 1 | Out-Null
			}

			# Setting 'NoOpenWith' for all registered the extension ProgIDs
			# We have to check everything due to "Set-StrictMode -Version Latest"
			if (Get-Item -Path "Registry::HKEY_CLASSES_ROOT\$Extension\OpenWithProgids" -ErrorAction SilentlyContinue)
			{
				[psobject]$OpenSubkey = (Get-Item -Path "Registry::HKEY_CLASSES_ROOT\$Extension\OpenWithProgids" -ErrorAction SilentlyContinue).Property
				if ($OpenSubkey)
				{
					foreach ($AppxProgID in ($OpenSubkey | Where-Object -FilterScript {$_ -match "AppX"}))
					{
						# If an app is installed
						if (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$AppxProgID\Shell\open" -Name PackageId -ErrorAction SilentlyContinue)
						{
							# If the specified ProgId is equal to UWP installed ProgId
							if ($ProgId -eq $AppxProgID)
							{
								# Remove association limitations for this UWP apps
								Remove-RegistryValueSafe -Path "HKCU:\Software\Classes\$AppxProgID" -Name NoOpenWith | Out-Null
								Remove-RegistryValueSafe -Path "HKCU:\Software\Classes\$AppxProgID" -Name NoStaticDefaultVerb | Out-Null
							}
							else
							{
								Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$AppxProgID" -Name NoOpenWith -Type String -Value "" | Out-Null
							}

							$Script:RegisteredProgIDs += $AppxProgID
						}
					}
				}
			}

			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\KindMap", $Extension, $null))
			{
				$picture = (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\KindMap -Name $Extension -ErrorAction Ignore).$Extension
			}
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\PBrush\CLSID", "", $null))
			{
				$PBrush = (Get-ItemProperty -Path HKLM:\SOFTWARE\Classes\PBrush\CLSID -Name "(default)" -ErrorAction Ignore)."(default)"
			}

			# We have to check everything due to "Set-StrictMode -Version Latest"
			if (Get-Variable -Name picture -ErrorAction Ignore)
			{
				if (($picture -eq "picture") -and $PBrush)
				{
					Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name "PBrush_$($Extension)" -Type DWord -Value 0 | Out-Null
				}
			}

			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if (([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\KindMap", $Extension, $null)) -eq "picture")
			{
				$Script:RegisteredProgIDs += "PBrush"
			}

			if ($Extension.Contains("."))
			{
				[string]$Associations = "FileAssociations"
			}
			else
			{
				[string]$Associations = "UrlAssociations"
			}

			foreach ($Item in @((Get-Item -Path "HKLM:\SOFTWARE\RegisteredApplications" -ErrorAction SilentlyContinue).Property))
			{
				$Subkey = (Get-ItemProperty -Path "HKLM:\SOFTWARE\RegisteredApplications" -Name $Item -ErrorAction Ignore).$Item
				if ($Subkey)
				{
					if (Test-Path -Path "HKLM:\$Subkey\$Associations")
					{
						$isProgID = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\$Subkey\$Associations", $Extension, $null)
						if ($isProgID)
						{
							$Script:RegisteredProgIDs += $isProgID
						}
					}
				}
			}

			Clear-Variable -Name UserRegisteredProgIDs -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			[array]$UserRegisteredProgIDs = @()

			foreach ($Item in (Get-Item -Path "HKCU:\Software\RegisteredApplications" -ErrorAction SilentlyContinue).Property)
			{
				$Subkey = (Get-ItemProperty -Path "HKCU:\Software\RegisteredApplications" -Name $Item -ErrorAction SilentlyContinue).$Item
				if ($Subkey)
				{
					if (Test-Path -Path "HKCU:\$Subkey\$Associations")
					{
						$isProgID = [Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\$Subkey\$Associations", $Extension, $null)
						if ($isProgID)
						{
							$UserRegisteredProgIDs += $isProgID
						}
					}
				}
			}

			$UserRegisteredProgIDs = ($Script:RegisteredProgIDs + $UserRegisteredProgIDs | Sort-Object -Unique)
			foreach ($UserProgID in $UserRegisteredProgIDs)
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name "$($UserProgID)_$($Extension)" -Type DWord -Value 0 | Out-Null
			}
		}

		<#
		    .SYNOPSIS
		    Gets hash.

				#>

		function Get-Hash
		{
			[CmdletBinding()]
			[OutputType([string])]
			Param
			(
				[Parameter(
					Mandatory = $true,
					Position = 0
				)]
				[string]
				$ProgId,

				[Parameter(
					Mandatory = $true,
					Position = 1
				)]
				[string]
				$Extension,

				[Parameter(
					Mandatory = $true,
					Position = 2
				)]
				[string]
				$SubKey
			)

			$Signature = @{
				Namespace          = "WinAPI"
				Name               = "PatentHash"
				Language           = "CSharp"
				CompilerParameters = $CompilerParameters
				MemberDefinition   = @"
public static uint[] WordSwap(byte[] a, int sz, byte[] md5)
{
	if (sz < 2 || (sz & 1) == 1)
	{
		throw new ArgumentException(String.Format("Invalid input size: {0}", sz), "sz");
	}

	unchecked
	{
		uint o1 = 0;
		uint o2 = 0;
		int ta = 0;
		int ts = sz;
		int ti = ((sz - 2) >> 1) + 1;

		uint c0 = (BitConverter.ToUInt32(md5, 0) | 1) + 0x69FB0000;
		uint c1 = (BitConverter.ToUInt32(md5, 4) | 1) + 0x13DB0000;

		for (uint i = (uint)ti; i > 0; i--)
		{
			uint n = BitConverter.ToUInt32(a, ta) + o1;
			ta += 8;
			ts -= 2;

			uint v1 = 0x79F8A395 * (n * c0 - 0x10FA9605 * (n >> 16)) + 0x689B6B9F * ((n * c0 - 0x10FA9605 * (n >> 16)) >> 16);
			uint v2 = 0xEA970001 * v1 - 0x3C101569 * (v1 >> 16);
			uint v3 = BitConverter.ToUInt32(a, ta - 4) + v2;
			uint v4 = v3 * c1 - 0x3CE8EC25 * (v3 >> 16);
			uint v5 = 0x59C3AF2D * v4 - 0x2232E0F1 * (v4 >> 16);

			o1 = 0x1EC90001 * v5 + 0x35BD1EC9 * (v5 >> 16);
			o2 += o1 + v2;
		}

		if (ts == 1)
		{
			uint n = BitConverter.ToUInt32(a, ta) + o1;

			uint v1 = n * c0 - 0x10FA9605 * (n >> 16);
			uint v2 = 0xEA970001 * (0x79F8A395 * v1 + 0x689B6B9F * (v1 >> 16)) - 0x3C101569 * ((0x79F8A395 * v1 + 0x689B6B9F * (v1 >> 16)) >> 16);
			uint v3 = v2 * c1 - 0x3CE8EC25 * (v2 >> 16);

			o1 = 0x1EC90001 * (0x59C3AF2D * v3 - 0x2232E0F1 * (v3 >> 16)) + 0x35BD1EC9 * ((0x59C3AF2D * v3 - 0x2232E0F1 * (v3 >> 16)) >> 16);
			o2 += o1 + v2;
		}

		uint[] ret = new uint[2];
		ret[0] = o1;
		ret[1] = o2;
		return ret;
	}
}

public static uint[] Reversible(byte[] a, int sz, byte[] md5)
{
	if (sz < 2 || (sz & 1) == 1)
	{
		throw new ArgumentException(String.Format("Invalid input size: {0}", sz), "sz");
	}

	unchecked
	{
		uint o1 = 0;
		uint o2 = 0;
		int ta = 0;
		int ts = sz;
		int ti = ((sz - 2) >> 1) + 1;

		uint c0 = BitConverter.ToUInt32(md5, 0) | 1;
		uint c1 = BitConverter.ToUInt32(md5, 4) | 1;

		for (uint i = (uint)ti; i > 0; i--)
		{
			uint n = (BitConverter.ToUInt32(a, ta) + o1) * c0;
			n = 0xB1110000 * n - 0x30674EEF * (n >> 16);
			ta += 8;
			ts -= 2;

			uint v1 = 0x5B9F0000 * n - 0x78F7A461 * (n >> 16);
			uint v2 = 0x1D830000 * (0x12CEB96D * (v1 >> 16) - 0x46930000 * v1) + 0x257E1D83 * ((0x12CEB96D * (v1 >> 16) - 0x46930000 * v1) >> 16);
			uint v3 = BitConverter.ToUInt32(a, ta - 4) + v2;

			uint v4 = 0x16F50000 * c1 * v3 - 0x5D8BE90B * (c1 * v3 >> 16);
			uint v5 = 0x2B890000 * (0x96FF0000 * v4 - 0x2C7C6901 * (v4 >> 16)) + 0x7C932B89 * ((0x96FF0000 * v4 - 0x2C7C6901 * (v4 >> 16)) >> 16);

			o1 = 0x9F690000 * v5 - 0x405B6097 * (v5 >> 16);
			o2 += o1 + v2;
		}

		if (ts == 1)
		{
			uint n = BitConverter.ToUInt32(a, ta) + o1;

			uint v1 = 0xB1110000 * c0 * n - 0x30674EEF * ((c0 * n) >> 16);
			uint v2 = 0x5B9F0000 * v1 - 0x78F7A461 * (v1 >> 16);
			uint v3 = 0x1D830000 * (0x12CEB96D * (v2 >> 16) - 0x46930000 * v2) + 0x257E1D83 * ((0x12CEB96D * (v2 >> 16) - 0x46930000 * v2) >> 16);
			uint v4 = 0x16F50000 * c1 * v3 - 0x5D8BE90B * ((c1 * v3) >> 16);
			uint v5 = 0x96FF0000 * v4 - 0x2C7C6901 * (v4 >> 16);
			o1 = 0x9F690000 * (0x2B890000 * v5 + 0x7C932B89 * (v5 >> 16)) - 0x405B6097 * ((0x2B890000 * v5 + 0x7C932B89 * (v5 >> 16)) >> 16);
			o2 += o1 + v2;
		}

		uint[] ret = new uint[2];
		ret[0] = o1;
		ret[1] = o2;
		return ret;
	}
}

public static long MakeLong(uint left, uint right)
{
	return (long)left << 32 | (long)right;
}
"@
			}

			if (-not ("WinAPI.PatentHash" -as [type]))
			{
				Add-Type @Signature -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			<#
			    .SYNOPSIS
			    Gets key last write time.

						#>

			function Get-KeyLastWriteTime ($SubKey)
			{
				$LastModified = [WinAPI.Action]::GetLastModified([Microsoft.Win32.RegistryHive]::CurrentUser,$SubKey)
				$FileTime = ([DateTime]::New($LastModified.Year, $LastModified.Month, $LastModified.Day, $LastModified.Hour, $LastModified.Minute, 0, $LastModified.Kind)).ToFileTime()

				return [string]::Format("{0:x8}{1:x8}", $FileTime -shr 32, $FileTime -band [uint32]::MaxValue)
			}

			<#
			    .SYNOPSIS
			    Gets data array.

						#>
			function Get-DataArray
			{
				[OutputType([array])]

				# Secret static string stored in %SystemRoot%\SysWOW64\shell32.dll
				$userExperience        = "User Choice set via Windows User Experience {D18B6DD5-6124-4341-9318-804003BAFA0B}"
				# Get user SID
				$userSID               = (Get-CimInstance -ClassName Win32_UserAccount | Where-Object -FilterScript {$_.Name -eq $env:USERNAME}).SID
				$KeyLastWriteTime      = Get-KeyLastWriteTime -SubKey $SubKey
				$baseInfo              = ("{0}{1}{2}{3}{4}" -f $Extension, $userSID, $ProgId, $KeyLastWriteTime, $userExperience).ToLowerInvariant()
				$StringToUTF16LEArray  = [System.Collections.ArrayList]@([System.Text.Encoding]::Unicode.GetBytes($baseInfo))
				$StringToUTF16LEArray += (0,0)

				return $StringToUTF16LEArray
			}

			<#
			    .SYNOPSIS
			    Gets patent hash.

						#>

			function Get-PatentHash
			{
				[OutputType([string])]
				param
				(
					[Parameter(Mandatory = $true)]
					[byte[]]
					$Array,

					[Parameter(Mandatory = $true)]
					[byte[]]
					$MD5
				)

				$Size = $Array.Count
				$ShiftedSize = ($Size -shr 2) - ($Size -shr 2 -band 1) * 1

				[uint32[]]$Array1 = [WinAPI.PatentHash]::WordSwap($Array, [int]$ShiftedSize, $MD5)
				[uint32[]]$Array2 = [WinAPI.PatentHash]::Reversible($Array, [int]$ShiftedSize, $MD5)

				$Ret = [WinAPI.PatentHash]::MakeLong($Array1[1] -bxor $Array2[1], $Array1[0] -bxor $Array2[0])

				return [System.Convert]::ToBase64String([System.BitConverter]::GetBytes([Int64]$Ret))
			}

			$DataArray = Get-DataArray
			$DataMD5   = [System.Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash($DataArray)
			$Hash      = Get-PatentHash -Array $DataArray -MD5 $DataMD5

			return $Hash
		}
		#endregion functions

		# Register %1 argument if ProgId exists as an executable file
		if (Test-Path -Path $ProgramPath)
		{
			if (-not (Test-Path -Path "HKCU:\Software\Classes\$ProgId\shell\open\command"))
			{
				New-Item -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			if ($ProgramPath.Contains("%1"))
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Name "(Default)" -Type String -Value $ProgramPath | Out-Null
			}
			else
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Name "(Default)" -Type String -Value "`"$ProgramPath`" `"%1`"" | Out-Null
			}

			$FileNameEXE = Split-Path -Path $ProgramPath -Leaf
			if (-not (Test-Path -Path "HKCU:\Software\Classes\Applications\$FileNameEXE\shell\open\command"))
			{
				New-Item -Path "HKCU:\Software\Classes\Applications\$FileNameEXE\shell\open\command" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			Set-RegistryValueSafe -Path "HKCU:\Software\Classes\Applications\$FileNameEXE\shell\open\command" -Name "(Default)" -Type String -Value "`"$ProgramPath`" `"%1`"" | Out-Null
		}

		if ($Icon)
		{
			if (-not (Test-Path -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon"))
			{
				New-Item -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			Set-RegistryValueSafe -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon" -Name "(default)" -Type String -Value $Icon | Out-Null
		}

		Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name "$($ProgID)_$($Extension)" -Type DWord -Value 0 | Out-Null

		if ($Extension.Contains("."))
		{
			# If the file extension specified configure the extension
			Write-ExtensionKeys -ProgId $ProgId -Extension $Extension
		}
		else
		{
			[WinAPI.Action]::DeleteKey([Microsoft.Win32.RegistryHive]::CurrentUser, "Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice")

			if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice"))
			{
				New-Item -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			$ProgHash = Get-Hash -ProgId $ProgId -Extension $Extension -SubKey "Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice"

			# We need to remove DENY permission set for user before setting a value
			if (@(".pdf", "http", "https") -contains $Extension)
			{
				# https://powertoe.wordpress.com/2010/08/28/controlling-registry-acl-permissions-with-powershell/
				$Key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice",[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::ChangePermissions)
				$ACL = $key.GetAccessControl()
				$Principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
				# https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights
				$Rule = New-Object -TypeName System.Security.AccessControl.RegistryAccessRule -ArgumentList ($Principal,"FullControl","Deny")
				$ACL.RemoveAccessRule($Rule)
				$Key.SetAccessControl($ACL)

				# Write protected URL association values through temporary scripts.
				# Escape single quotes in interpolated values to prevent command-string injection.
				$EscExtension = $Extension -replace "'", "''"
				$EscProgID    = $ProgID    -replace "'", "''"
				$EscProgHash  = $ProgHash  -replace "'", "''"
				$setUrlProgIdScript = "New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$EscExtension\UserChoice' -Name ProgId -PropertyType String -Value '$EscProgID' -Force -ErrorAction Stop | Out-Null"
				& $invokeTempPowerShellScript -ScriptText $setUrlProgIdScript -Operation "Setting URL ProgId for $Extension"
				$setUrlHashScript = "New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$EscExtension\UserChoice' -Name Hash -PropertyType String -Value '$EscProgHash' -Force -ErrorAction Stop | Out-Null"
				& $invokeTempPowerShellScript -ScriptText $setUrlHashScript -Operation "Setting URL Hash for $Extension"
			}
			else
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice" -Name ProgId -Type String -Value $ProgId | Out-Null
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice" -Name Hash -Type String -Value $ProgHash | Out-Null
			}
		}

		# Setting additional parameters to comply with the requirements before configuring the extension
		Write-AdditionalKeys -ProgId $ProgId -Extension $Extension

		# Refresh the desktop icons
		$Signature = @{
			Namespace          = "WinAPI"
			Name               = "Signature"
			Language           = "CSharp"
			CompilerParameters = $CompilerParameters
			MemberDefinition   = @"
[DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = false)]
private static extern int SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);

public static void Refresh()
{
	// Update desktop icons
	SHChangeNotify(0x8000000, 0x1000, IntPtr.Zero, IntPtr.Zero);
}
"@
		}
		if (-not ("WinAPI.Signature" -as [type]))
		{
			Add-Type @Signature -ErrorAction SilentlyContinue 2>&1 | Out-Null
		}

		[WinAPI.Signature]::Refresh()
	) 2>&1 | Out-Null
	}
	catch
	{
		$AssociationFailed = $true
		LogError "Failed to associate $Extension files with ${ProgramPath}: $($_.Exception.Message)"
	}
	finally
	{
		Remove-Item -Path $TempPowerShellPath -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
	}
