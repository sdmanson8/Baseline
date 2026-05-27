try
	{
		$regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
			"Software\Microsoft\Windows NT\CurrentVersion\Windows",
			[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
			[System.Security.AccessControl.RegistryRights]::ChangePermissions
		)

		if ($null -eq $regKey)
		{
			throw "Could not open HKCU registry key for ACL modification."
		}

		$acl = $regKey.GetAccessControl()
		$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
		$systemAcc = (New-Object System.Security.Principal.SecurityIdentifier(
			[System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null
		)).Translate([System.Security.Principal.NTAccount]).Value

		foreach ($id in @($currentUser, $systemAcc))
		{
			$rule = New-Object System.Security.AccessControl.RegistryAccessRule(
				$id,
				[System.Security.AccessControl.RegistryRights]::FullControl,
				[System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
				[System.Security.AccessControl.PropagationFlags]::None,
				[System.Security.AccessControl.AccessControlType]::Allow
			)
			$acl.SetAccessRule($rule)
			LogInfo "FullControl on HKCU\\..\\Windows -> $id"
		}

		$regKey.SetAccessControl($acl)
		$regKey.Close()
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not set HKCU registry ACL: $($_.Exception.Message)"
	}
