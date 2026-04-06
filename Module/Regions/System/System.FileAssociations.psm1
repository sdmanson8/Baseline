using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Associate a file extension with a desktop program or ProgID.

	.DESCRIPTION
	Creates or updates the file association data for the requested extension and
	optionally sets a custom icon for the associated program.

	.PARAMETER ProgramPath
	The executable path or ProgID to associate with the file extension.

	.PARAMETER Extension
	The file extension to associate, including the leading dot.

	.PARAMETER Icon
	Optional icon resource to use for the file association.

	.EXAMPLE
	Set-Association -ProgramPath '%ProgramFiles%\\Notepad++\\notepad++.exe' -Extension .txt

	.NOTES
	Current user
#>
function Set-Association
{
	[CmdletBinding()]
	Param
	(
		[Parameter(
			Mandatory = $true,
			Position = 0
		)]
		[string]
		$ProgramPath,

		[Parameter(
			Mandatory = $true,
			Position = 1
		)]
		[string]
		$Extension,

		[Parameter(
			Mandatory = $false,
			Position = 2
		)]
		[string]
		$Icon
	)

	$TempPowerShellPath = Get-UCPDTemporaryPowerShellPath
	$AssociationFailed = $false

	# Suppress all output from the entire function
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
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts -Name "$($ProgID)_$($Extension)" -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			$Name = "{0}_$($Extension)" -f (Split-Path -Path $ProgId -Leaf)
			New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts -Name $Name -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

			if ("$($ProgID)_$($Extension)" -ne $Name)
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts -Name "$($ProgID)_$($Extension)" -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			# If ProgId doesn't exist set the specified ProgId for the extensions
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if (-not [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$Extension", "", $null))
			{
				if (-not (Test-Path -Path "HKCU:\Software\Classes\$Extension"))
				{
					New-Item -Path "HKCU:\Software\Classes\$Extension" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
				}
				New-ItemProperty -Path "HKCU:\Software\Classes\$Extension" -Name "(default)" -PropertyType String -Value $ProgId -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			# Set the specified ProgId in the possible options for the assignment
			if (-not (Test-Path -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids"))
			{
				New-Item -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			New-ItemProperty -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Name $ProgId -PropertyType None -Value ([byte[]]@()) -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

			# Set the system ProgId to the extension parameters for File Explorer to the possible options for the assignment, and if absent set the specified ProgId
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			if ($OrigProgID)
			{
				if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithProgids"))
				{
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithProgids" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
				}
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\OpenWithProgids" -Name $OrigProgID -PropertyType None -Value ([byte[]]@()) -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			if (-not (Test-Path -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids"))
			{
				New-Item -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			New-ItemProperty -Path "HKCU:\Software\Classes\$Extension\OpenWithProgids" -Name $ProgID -PropertyType None -Value ([byte[]]@()) -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

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

				# We need to use here an approach with "-Command & {}" as there's a variable inside
				# Escape single quotes in interpolated values to prevent command-string injection
				$EscExtension = $Extension -replace "'", "''"
				$EscProgID    = $ProgID    -replace "'", "''"
				# ExecutionPolicy Bypass: required for scheduled task creation / child process execution
				& $TempPowerShellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$EscExtension\UserChoice' -Name ProgId -PropertyType String -Value '$EscProgID' -Force -ErrorAction Stop | Out-Null }" 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "Temporary PowerShell copy returned exit code $LASTEXITCODE while setting ProgId for $Extension"
				}
			}
			else
			{
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Name ProgId -PropertyType String -Value $ProgID -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			# Getting a hash based on the time of the section's last modification. After creating and setting the first parameter
			$ProgHash = Get-Hash -ProgId $ProgId -Extension $Extension -SubKey "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"

			if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"))
			{
				New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			if (@(".pdf", "http", "https") -contains $Extension)
			{
				# We need to use here an approach with "-Command & {}" as there's a variable inside
				# Escape single quotes; $EscExtension already set above in this scope
				$EscProgHash = $ProgHash -replace "'", "''"
				# ExecutionPolicy Bypass: required for scheduled task creation / child process execution
				& $TempPowerShellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$EscExtension\UserChoice' -Name Hash -PropertyType String -Value '$EscProgHash' -Force -ErrorAction Stop | Out-Null }" 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "Temporary PowerShell copy returned exit code $LASTEXITCODE while setting Hash for $Extension"
				}
			}
			else
			{
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -Name Hash -PropertyType String -Value $ProgHash -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
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
				New-ItemProperty -Path Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\FileAssociations\ProgIds -Name "_$($Extension)" -PropertyType DWord -Value 1 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
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
								Remove-ItemProperty -Path "HKCU:\Software\Classes\$AppxProgID" -Name NoOpenWith -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
								Remove-ItemProperty -Path "HKCU:\Software\Classes\$AppxProgID" -Name NoStaticDefaultVerb -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
							}
							else
							{
								New-ItemProperty -Path "HKCU:\Software\Classes\$AppxProgID" -Name NoOpenWith -PropertyType String -Value "" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
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
					New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts -Name "PBrush_$($Extension)" -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
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
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" -Name "$($UserProgID)_$($Extension)" -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
		}

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

			function Get-KeyLastWriteTime ($SubKey)
			{
				$LastModified = [WinAPI.Action]::GetLastModified([Microsoft.Win32.RegistryHive]::CurrentUser,$SubKey)
				$FileTime = ([DateTime]::New($LastModified.Year, $LastModified.Month, $LastModified.Day, $LastModified.Hour, $LastModified.Minute, 0, $LastModified.Kind)).ToFileTime()

				return [string]::Format("{0:x8}{1:x8}", $FileTime -shr 32, $FileTime -band [uint32]::MaxValue)
			}

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
				New-ItemProperty -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Name "(Default)" -PropertyType String -Value $ProgramPath -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			else
			{
				New-ItemProperty -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Name "(Default)" -PropertyType String -Value "`"$ProgramPath`" `"%1`"" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}

			$FileNameEXE = Split-Path -Path $ProgramPath -Leaf
			if (-not (Test-Path -Path "HKCU:\Software\Classes\Applications\$FileNameEXE\shell\open\command"))
			{
				New-Item -Path "HKCU:\Software\Classes\Applications\$FileNameEXE\shell\open\command" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			New-ItemProperty -Path "HKCU:\Software\Classes\Applications\$FileNameEXE\shell\open\command" -Name "(Default)" -PropertyType String -Value "`"$ProgramPath`" `"%1`"" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
		}

		if ($Icon)
		{
			if (-not (Test-Path -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon"))
			{
				New-Item -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon" -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
			}
			New-ItemProperty -Path "HKCU:\Software\Classes\$ProgId\DefaultIcon" -Name "(default)" -PropertyType String -Value $Icon -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
		}

		New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts -Name "$($ProgID)_$($Extension)"  -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null

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

				# We need to use here an approach with "-Command & {}" as there's a variable inside
				# Escape single quotes in interpolated values to prevent command-string injection
				$EscExtension = $Extension -replace "'", "''"
				$EscProgID    = $ProgID    -replace "'", "''"
				$EscProgHash  = $ProgHash  -replace "'", "''"
				# ExecutionPolicy Bypass: required for scheduled task creation / child process execution
				& $TempPowerShellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$EscExtension\UserChoice' -Name ProgId -PropertyType String -Value '$EscProgID' -Force -ErrorAction Stop | Out-Null }" 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "Temporary PowerShell copy returned exit code $LASTEXITCODE while setting URL ProgId for $Extension"
				}
				# ExecutionPolicy Bypass: required for scheduled task creation / child process execution
				& $TempPowerShellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$EscExtension\UserChoice' -Name Hash -PropertyType String -Value '$EscProgHash' -Force -ErrorAction Stop | Out-Null }" 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "Temporary PowerShell copy returned exit code $LASTEXITCODE while setting URL Hash for $Extension"
				}
			}
			else
			{
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice" -Name ProgId -PropertyType String -Value $ProgId -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$Extension\UserChoice" -Name Hash -PropertyType String -Value $ProgHash -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
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

	if ($AssociationFailed)
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
	Export all Windows associations

	.EXAMPLE
	Export-Associations

	.NOTES
	Associations will be exported as Application_Associations.json file in script root folder

	.NOTES
	You need to install all apps according to an exported JSON file to restore all associations

	.NOTES
	Machine-wide
#>
function Export-Associations
{
	Write-ConsoleStatus -Action "Exporting associations"
	LogInfo "Exporting associations"
	try
	{
		Dism.exe /Online /Export-DefaultAppAssociations:"$env:TEMP\Application_Associations.xml" 2>$null | Out-Null
		if ($LASTEXITCODE -ne 0) { throw "Dism.exe returned exit code $LASTEXITCODE" }
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to export application associations: $($_.Exception.Message)"
		return
	}

	Clear-Variable -Name AllJSON, ProgramPath, Icon -ErrorAction SilentlyContinue | Out-Null

	$AllJSON = @()
	$AppxProgIds = @((Get-ChildItem -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\ProgIDs").PSChildName)

	[xml]$XML = Get-Content -Path "$env:TEMP\Application_Associations.xml" -Encoding UTF8 -Force
	$XML.DefaultAssociations.Association | ForEach-Object -Process {
		if ($AppxProgIds -contains $_.ProgId)
		{
			# if ProgId is a UWP app
			# ProgrammPath
			if (Test-Path -Path "HKCU:\Software\Classes\$($_.ProgId)\Shell\Open\Command")
			{

				if ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\shell\open\command", "DelegateExecute", $null))
				{
					$ProgramPath, $Icon = ""
				}
			}
		}
		else
		{
			if (Test-Path -Path "Registry::HKEY_CLASSES_ROOT\$($_.ProgId)")
			{
				# ProgrammPath
				if ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\shell\open\command", "", $null))
				{
					$PartProgramPath = (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$($_.ProgId)\Shell\Open\Command" -Name "(default)").Trim()
					$Program = $PartProgramPath.Substring(0, ($PartProgramPath.IndexOf(".exe") + 4)).Trim('"')

					if ($Program)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($Program)))
						{
							$ProgramPath = $PartProgramPath
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command", "", $null))
				{
					$PartProgramPath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command" -Name "(default)").Trim()
					$Program = $PartProgramPath.Substring(0, ($PartProgramPath.IndexOf(".exe") + 4)).Trim('"')

					if ($Program)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($Program)))
						{
							$ProgramPath = $PartProgramPath
						}
					}
				}

				# Icon
				if ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\DefaultIcon", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$($_.ProgId)\DefaultIcon" -Name "(default)")
					if ($IconPartPath.EndsWith(".ico"))
					{
						$IconPath = $IconPartPath
					}
					else
					{
						if ($IconPartPath.Contains(","))
						{
							$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(",")).Trim('"')
						}
						else
						{
							$IconPath = $IconPartPath.Trim('"')
						}
					}

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = $IconPartPath
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($_.ProgId)\DefaultIcon", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Classes\$($_.ProgId)\DefaultIcon" -Name "(default)").Trim()
					if ($IconPartPath.EndsWith(".ico"))
					{
						$IconPath = $IconPartPath
					}
					else
					{
						if ($IconPartPath.Contains(","))
						{
							$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(",")).Trim('"')
						}
						else
						{
							$IconPath = $IconPartPath.Trim('"')
						}
					}

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = $IconPartPath
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Classes\$($_.ProgId)\shell\open\command", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKCU:\Software\Classes\$($_.ProgId)\shell\open\command" -Name "(default)").Trim()
					$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(".exe") + 4).Trim('"')

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = "$IconPath,0"
						}
					}
				}
				elseif ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command", "", $null))
				{
					$IconPartPath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Classes\$($_.ProgId)\Shell\Open\Command" -Name "(default)").Trim()
					$IconPath = $IconPartPath.Substring(0, $IconPartPath.IndexOf(".exe") + 4)

					if ($IconPath)
					{
						if (Test-Path -Path $([System.Environment]::ExpandEnvironmentVariables($IconPath)))
						{
							$Icon = "$IconPath,0"
						}
					}
				}
			}
		}

		$_.ProgId = $_.ProgId.Replace("\", "\\")
		$ProgramPath = $ProgramPath.Replace("\", "\\").Replace('"', '\"')
		if ($Icon)
		{
			$Icon = $Icon.Replace("\", "\\").Replace('"', '\"')
		}

		# Create a hash table
		$JSON = @"
[
  {
     "ProgId":  "$($_.ProgId)",
     "ProgrammPath": "$ProgramPath",
     "Extension": "$($_.Identifier)",
     "Icon": "$Icon"
  }
]
"@ | ConvertFrom-JSON
		$AllJSON += $JSON
	}

	Clear-Variable -Name ProgramPath, Icon -ErrorAction SilentlyContinue | Out-Null

	# Save in UTF-8 without BOM; use explicit depth and UTF-8 encoding for cross-edition consistency
	[System.IO.File]::WriteAllText(
		(Join-Path $PSScriptRoot '..\Application_Associations.json'),
		($AllJSON | ConvertTo-Json -Depth 16),
		[System.Text.Encoding]::UTF8
	)

	Remove-Item -Path "$env:TEMP\Application_Associations.xml" -Force -ErrorAction SilentlyContinue | Out-Null
	Write-ConsoleStatus -Status success
}

<#
	.SYNOPSIS
	Import all Windows associations

	.EXAMPLE
	Import-Associations

	.NOTES
	You have to install all apps according to an exported JSON file to restore all associations

	.NOTES
	Current user
#>
function Import-Associations
{
	Write-ConsoleStatus -Action "Importing associations"
	LogInfo "Importing associations"

	Add-Type -AssemblyName System.Windows.Forms
	$OpenFileDialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.Filter = "*.json|*.json|{0} (*.*)|*.*" -f $Localization.AllFilesFilter
	$OpenFileDialog.InitialDirectory = $PSScriptRoot
	$OpenFileDialog.Multiselect = $false

	# Force move the open file dialog to the foreground
	$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
	$OpenFileDialog.ShowDialog($Focus)

	if ($OpenFileDialog.FileName)
	{
		$AppxProgIds = @((Get-ChildItem -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\ProgIDs").PSChildName)

		try
		{
			$JSON = Get-Content -Path $OpenFileDialog.FileName -Encoding UTF8 -Force | ConvertFrom-JSON
		}
		catch [System.Exception]
		{
			LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))

			return
		}

		$JSON | ForEach-Object -Process {
			if ($AppxProgIds -contains $_.ProgId)
			{
				Set-Association -ProgramPath $_.ProgId -Extension $_.Extension
			}
			else
			{
				Set-Association -ProgramPath $_.ProgrammPath -Extension $_.Extension -Icon $_.Icon
			}
		}
	}
	Write-ConsoleStatus -Status success
}

<#
	.SYNOPSIS
	Change User folders location

	.PARAMETER Root
	Change user folders location to the root of any drive using the interactive menu

	.PARAMETER Custom
	Select folders for user folders location manually using a folder browser dialog

	.PARAMETER Default
	Change user folders location to the default values

	.EXAMPLE
	Set-UserShellFolderLocation -Root

	.EXAMPLE
	Set-UserShellFolderLocation -Custom

	.EXAMPLE
	Set-UserShellFolderLocation -Default

	.NOTES
	User files or folders won't be moved to a new location

	.NOTES
	Current user
#>
function Set-UserShellFolderLocation
{

	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Root"
		)]
		[switch]
		$Root,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Custom"
		)]
		[switch]
		$Custom,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	<#
		.SYNOPSIS
		Change the location of the each user folder using SHSetKnownFolderPath function

		.EXAMPLE
		Set-UserShellFolder -UserFolder Desktop -FolderPath "$env:SystemDrive:\Desktop"

		.LINK
		https://docs.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath

		.NOTES
		User files or folders won't be moved to a new location
	#>
	function Set-UserShellFolder
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			[ValidateSet("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos")]
			[string]
			$UserFolder,

			[Parameter(Mandatory = $true)]
			[string]
			$FolderPath
		)

		<#
			.SYNOPSIS
			Redirect user folders to a new location

			.EXAMPLE
			Set-KnownFolderPath -KnownFolder Desktop -Path "$env:SystemDrive:\Desktop"
		#>
		function Set-KnownFolderPath
		{
			[CmdletBinding()]
			param
			(
				[Parameter(Mandatory = $true)]
				[ValidateSet("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos")]
				[string]
				$KnownFolder,

				[Parameter(Mandatory = $true)]
				[string]
				$Path
			)

			$KnownFolders = @{
				"Desktop"   = @("B4BFCC3A-DB2C-424C-B029-7FE99A87C641")
				"Documents" = @("FDD39AD0-238F-46AF-ADB4-6C85480369C7", "f42ee2d3-909f-4907-8871-4c22fc0bf756")
				"Downloads" = @("374DE290-123F-4565-9164-39C4925E467B", "7d83ee9b-2244-4e70-b1f5-5404642af1e4")
				"Music"     = @("4BD8D571-6D19-48D3-BE97-422220080E43", "a0c69a99-21c8-4671-8703-7934162fcf1d")
				"Pictures"  = @("33E28130-4E1E-4676-835A-98395C3BC3BB", "0ddd015d-b06c-45d5-8c4c-f59713854639")
				"Videos"    = @("18989B1D-99B5-455B-841C-AB7C74E4DDFC", "35286a68-3c57-41a1-bbb1-0eae73d76c95")
			}

			$Signature = @{
				Namespace          = "WinAPI"
				Name               = "KnownFolders"
				Language           = "CSharp"
				CompilerParameters = $CompilerParameters
				MemberDefinition   = @"
[DllImport("shell32.dll")]
public extern static int SHSetKnownFolderPath(ref Guid folderId, uint flags, IntPtr token, [MarshalAs(UnmanagedType.LPWStr)] string path);
"@
			}
			if (-not ("WinAPI.KnownFolders" -as [type]))
			{
				Add-Type @Signature
			}

			foreach ($GUID in $KnownFolders[$KnownFolder])
			{
				[WinAPI.KnownFolders]::SHSetKnownFolderPath([ref]$GUID, 0, 0, $Path)
			}
			(Get-Item -Path $Path -Force).Attributes = "ReadOnly"
		}

		$UserShellFoldersRegistryNames = @{
			"Desktop"   = "Desktop"
			"Documents" = "Personal"
			"Downloads" = "{374DE290-123F-4565-9164-39C4925E467B}"
			"Music"     = "My Music"
			"Pictures"  = "My Pictures"
			"Videos"    = "My Video"
		}

		$UserShellFoldersGUIDs = @{
			"Desktop"   = "{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}"
			"Documents" = "{F42EE2D3-909F-4907-8871-4C22FC0BF756}"
			"Downloads" = "{7D83EE9B-2244-4E70-B1F5-5404642AF1E4}"
			"Music"     = "{A0C69A99-21C8-4671-8703-7934162FCF1D}"
			"Pictures"  = "{0DDD015D-B06C-45D5-8C4C-F59713854639}"
			"Videos"    = "{35286A68-3C57-41A1-BBB1-0EAE73D76C95}"
		}

		# Contents of the hidden desktop.ini file for each type of user folders
		$DesktopINI = @{
			"Desktop"   = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21769",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-183"
			"Documents" = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21770",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-112",
                          "IconFile=%SystemRoot%\System32\shell32.dll",
                          "IconIndex=-235"
			"Downloads" = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21798",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-184"
			"Music"     = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21790",
                          "InfoTip=@%SystemRoot%\System32\shell32.dll,-12689",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-108",
                          "IconFile=%SystemRoot%\System32\shell32.dll","IconIndex=-237"
			"Pictures"  = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21779",
                          "InfoTip=@%SystemRoot%\System32\shell32.dll,-12688",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-113",
                          "IconFile=%SystemRoot%\System32\shell32.dll",
                          "IconIndex=-236"
			"Videos"    = "",
                          "[.ShellClassInfo]",
                          "LocalizedResourceName=@%SystemRoot%\System32\shell32.dll,-21791",
                          "InfoTip=@%SystemRoot%\System32\shell32.dll,-12690",
                          "IconResource=%SystemRoot%\System32\imageres.dll,-189",
                          "IconFile=%SystemRoot%\System32\shell32.dll","IconIndex=-238"
		}

		# Determining the current user folder path
		$CurrentUserFolderPath = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name $UserShellFoldersRegistryNames[$UserFolder]
		if ($CurrentUserFolder -ne $FolderPath)
		{
			# Creating a new folder if there is no one
			if (-not (Test-Path -Path $FolderPath))
			{
				New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
			}

			# Removing old desktop.ini
			Remove-Item -Path "$CurrentUserFolderPath\desktop.ini" -Force -ErrorAction SilentlyContinue | Out-Null

			Set-KnownFolderPath -KnownFolder $UserFolder -Path $FolderPath | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name $UserShellFoldersGUIDs[$UserFolder] -PropertyType ExpandString -Value $FolderPath -Force | Out-Null

			# Save desktop.ini in the UTF-16 LE encoding
			Set-Content -Path "$FolderPath\desktop.ini" -Value $DesktopINI[$UserFolder] -Encoding Unicode -Force | Out-Null
			(Get-Item -Path "$FolderPath\desktop.ini" -Force).Attributes = "Hidden", "System", "Archive"
			(Get-Item -Path "$FolderPath\desktop.ini" -Force).Refresh()

			if ((Get-ChildItem -Path $CurrentUserFolderPath -ErrorAction SilentlyContinue | Measure-Object).Count -ne 0)
			{
				LogError ($Localization.UserShellFolderNotEmpty -f $CurrentUserFolderPath)
			}
		}
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Root"
		{
			# Write-Host: intentional — user-visible progress indicator
			Write-Host "Changing user folders location to the root of a drive"
			LogInfo "Changing user folders location to the root of a drive"
			# Store all fixed disks' letters except C (system drive) to use them within Show-Menu function
			# https://learn.microsoft.com/en-us/dotnet/api/system.io.drivetype
			$DriveLetters = @((Get-CimInstance -ClassName CIM_LogicalDisk | Where-Object -FilterScript {($_.DriveType -eq 3) -and ($_.Name -ne $env:SystemDrive)}).DeviceID | Sort-Object)

			if (-not $DriveLetters)
			{
				LogError $Localization.UserFolderLocationMove

				return
			}

			# Desktop
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21769), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Desktop -FolderPath "$($Choice)\Desktop" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Documents
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21770), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Documents -FolderPath "$($Choice)\Documents" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Downloads
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21798), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Downloads -FolderPath "$($Choice)\Downloads" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Music
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Music"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21790), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Music -FolderPath "$($Choice)\Music" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Pictures
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Pictures"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21779), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Pictures -FolderPath "$($Choice)\Pictures" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Videos
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Video"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21791), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $DriveLetters -Default $DriveLetters.Count[-1] -AddSkip

				switch ($Choice)
				{
					{$DriveLetters -contains $Choice}
					{
						Set-UserShellFolder -UserFolder Videos -FolderPath "$($Choice)\Videos" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)
		}
		"Custom"
		{
			# Write-Host: intentional — user-visible progress indicator
			Write-Host "Changing user folders location to the custom one selected"
			LogInfo "Changing user folders location to the custom one selected"
			# Desktop
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21769), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						# Force move the open file dialog to the foreground
						$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
						$FolderBrowserDialog.ShowDialog($Focus)

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Desktop -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Documents
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21770), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						# Force move the open file dialog to the foreground
						$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
						$FolderBrowserDialog.ShowDialog($Focus)

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Documents -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Downloads
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21798), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						# Force move the open file dialog to the foreground
						$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
						$FolderBrowserDialog.ShowDialog($Focus)

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Downloads -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Music
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Music"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21790), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						# Force move the open file dialog to the foreground
						$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
						$FolderBrowserDialog.ShowDialog($Focus)

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Music -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Pictures
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Pictures"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21779), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						# Force move the open file dialog to the foreground
						$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
						$FolderBrowserDialog.ShowDialog($Focus)

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Pictures -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Videos
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Video"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21791), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

				switch ($Choice)
				{
					$Browse
					{
						Add-Type -AssemblyName System.Windows.Forms
						$FolderBrowserDialog = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
						$FolderBrowserDialog.Description = $Localization.FolderSelect
						$FolderBrowserDialog.RootFolder = "MyComputer"

						# Force move the open file dialog to the foreground
						$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
						$FolderBrowserDialog.ShowDialog($Focus)

						if ($FolderBrowserDialog.SelectedPath)
						{
							if ($FolderBrowserDialog.SelectedPath -eq "C:\")
							{
								continue
							}
							else
							{
								Set-UserShellFolder -UserFolder Videos -FolderPath $FolderBrowserDialog.SelectedPath | Out-Null
							}
						}
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)
		}
		"Default"
		{
			# Write-Host: intentional — user-visible progress indicator
			Write-Host "Changing user folders location to the default one"
			LogInfo "Changing user folders location to the default one"
			# Desktop
			# Extract the localized "Desktop" string from shell32.dll
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21769), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Desktop -FolderPath "$env:USERPROFILE\Desktop" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Documents
			# Extract the localized "Documents" string from shell32.dll
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Personal
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21770), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Documents -FolderPath "$env:USERPROFILE\Documents" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Downloads
			# Extract the localized "Downloads" string from shell32.dll
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21798), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Downloads -FolderPath "$env:USERPROFILE\Downloads" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Music
			# Extract the localized "Music" string from shell32.dll
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Music"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21790), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Music -FolderPath "$env:USERPROFILE\Music" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Pictures
			# Extract the localized "Pictures" string from shell32.dll
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Pictures"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21779), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Pictures -FolderPath "$env:USERPROFILE\Pictures" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)

			# Videos
			# Extract the localized "Pictures" string from shell32.dll
			$CurrentUserFolderLocation = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "My Video"
			Write-Verbose -Message ($Localization.CurrentUserFolderLocation -f [WinAPI.GetStrings]::GetString(21791), $CurrentUserFolderLocation) -Verbose
			LogWarning $Localization.FilesWontBeMoved

			do
			{
				$Choice = Show-Menu -Menu $Yes -Default 1 -AddSkip

				switch ($Choice)
				{
					$Yes
					{
						Set-UserShellFolder -UserFolder Videos -FolderPath "$env:USERPROFILE\Videos" | Out-Null
					}
					$Skip
					{
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
					$KeyboardArrows {}
				}
			}
			until ($Choice -ne $KeyboardArrows)
		}
	}
}

<#
	.SYNOPSIS
	The location to save screenshots by pressing Win+PrtScr

	.PARAMETER Desktop
	Save screenshots by pressing Win+PrtScr on the Desktop

	.PARAMETER Default
	Save screenshots by pressing Win+PrtScr in the Pictures folder (default value)

	.EXAMPLE
	WinPrtScrFolder -Desktop

	.EXAMPLE
	WinPrtScrFolder -Default

	.NOTES
	The function will be applied only if the preset is configured to remove the OneDrive application, or the app was already uninstalled
	otherwise the backup functionality for the "Desktop" and "Pictures" folders in OneDrive breaks

	.NOTES
	Current user
#>
function WinPrtScrFolder
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Desktop"
		)]
		[switch]
		$Desktop,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Desktop"
		{
			Write-ConsoleStatus -Action "Setting the location to save screenshots by pressing Win+PrtScr to the Desktop"
			LogInfo "Setting the location to save screenshots by pressing Win+PrtScr to the Desktop"
			# Checking whether user is logged into OneDrive (Microsoft account)
			$UserEmail = Get-ItemProperty -Path HKCU:\Software\Microsoft\OneDrive\Accounts\Personal -Name UserEmail -ErrorAction SilentlyContinue
			if ($UserEmail)
			{
				LogError $Localization.OneDriveWarning
				LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

				return
			}

			# Checking how the script was invoked: via a preset or Functions.ps1
			# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-variable
			# This function works only if OneDrive was already uninstalled, or user is intended to uninstall "OneDrive -Uninstall" within commandline
			$PresetName = (Get-Variable -Name MyInvocation -Scope Script).Value.PSCommandPath
			$PSCallStack = (Get-PSCallStack).Position.Text
			$OneDriveInstalled = Get-Package -Name "Microsoft OneDrive" -ProviderName Programs -Force -ErrorAction Ignore -WarningAction SilentlyContinue
			$HeadlessCommands = Get-Variable -Name BaselineHeadlessCommands -Scope Global -ErrorAction SilentlyContinue

			# Headless runs pass the requested command list through a global variable.
			if ($HeadlessCommands -and $HeadlessCommands.Value)
			{
				$RequestedCommands = [string[]]@($HeadlessCommands.Value)
				if (($RequestedCommands -contains 'OneDrive -Uninstall') -or (-not $OneDriveInstalled))
				{
					$DesktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
					New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -PropertyType ExpandString -Value $DesktopFolder -Force | Out-Null
				}
				else
				{
					LogError ($Localization.OneDriveWarning -f (Get-TweakSkipLabel $MyInvocation))
					LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
				}
			}
			# Checking whether function was called from Functions.ps1
			elseif ($PresetName -match "Functions.ps1")
			{
				# Checking whether command contains "WinPrtScrFolder -Desktop"
				if ($PSCallStack -match "WinPrtScrFolder -Desktop")
				{
					# Checking whether other commands contains "OneDrive -Uninstall" which means that user is intended to uninstall "OneDrive -Uninstall", or OneDrive was uinstalled
					if (($PSCallStack -match "OneDrive -Uninstall") -or (-not $OneDriveInstalled))
					{
						$DesktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
						New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -PropertyType ExpandString -Value $DesktopFolder -Force | Out-Null
					}
					else
					{
						LogError ($Localization.OneDriveWarning -f (Get-TweakSkipLabel $MyInvocation))
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
				}
			}
			else
			{
				# Checking whether function was called from Baseline.ps1, and preset contains the "OneDrive -Uninstall" string is uncommented that means OneDrive will be unistalled
				if (Select-String -Path $PresetName -Pattern "OneDrive -Uninstall" -SimpleMatch)
				{
					# Checking whether string exists and is uncommented
					$IsOneDriveToUninstall = (Select-String -Path $PresetName -Pattern "OneDrive -Uninstall" -SimpleMatch).Line.StartsWith("#") -eq $false
					# Checking whether string exists and is uncommented, or OneDrive was uninstalled, or user called "OneDrive -Uninstall" from Baseline.ps1 alongside with "WinPrtScrFolder -Desktop"
					if ($IsOneDriveToUninstall -or (-not $OneDriveInstalled) -or ($PSCallStack -match "OneDrive -Uninstall"))
					{
						$DesktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name Desktop
						New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -PropertyType ExpandString -Value $DesktopFolder -Force | Out-Null
					}
					else
					{
						LogError ($Localization.OneDriveWarning -f (Get-TweakSkipLabel $MyInvocation))
						LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					}
				}
			}
			Write-ConsoleStatus -Status success
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Setting the location to save screenshots by pressing Win+PrtScr to the default one"
			LogInfo "Setting the location to save screenshots by pressing Win+PrtScr to the default one"
			Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{B7BEDE81-DF94-4682-A7D8-57A52620B86F}" -Force -ErrorAction Ignore | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

Export-ModuleMember -Function '*'
