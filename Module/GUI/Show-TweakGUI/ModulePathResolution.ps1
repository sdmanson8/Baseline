if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		Write-Warning "GUI module base path could not be resolved - preset directory will not be available"
	}
	elseif ((Split-Path -Path $Script:GuiModuleBasePath -Leaf) -ieq 'Regions')
	{
		$normalizedGuiModuleBasePath = Split-Path -Path $Script:GuiModuleBasePath -Parent
		if (-not [string]::IsNullOrWhiteSpace([string]$normalizedGuiModuleBasePath))
		{
			$Script:GuiModuleBasePath = $normalizedGuiModuleBasePath
		}
	}
	elseif ((Split-Path -Path $Script:GuiModuleBasePath -Leaf) -ieq 'GUI')
	{
		$normalizedGuiModuleBasePath = Split-Path -Path $Script:GuiModuleBasePath -Parent
		if (-not [string]::IsNullOrWhiteSpace([string]$normalizedGuiModuleBasePath))
		{
			$Script:GuiModuleBasePath = $normalizedGuiModuleBasePath
		}
	}
	else
	{
		$parentGuiModuleBasePath = Split-Path -Path $Script:GuiModuleBasePath -Parent
		if (-not [string]::IsNullOrWhiteSpace([string]$parentGuiModuleBasePath) -and (Split-Path -Path $parentGuiModuleBasePath -Leaf) -ieq 'GUI')
		{
			$normalizedGuiModuleBasePath = Split-Path -Path $parentGuiModuleBasePath -Parent
			if (-not [string]::IsNullOrWhiteSpace([string]$normalizedGuiModuleBasePath))
			{
				$Script:GuiModuleBasePath = $normalizedGuiModuleBasePath
			}
		}
	}
