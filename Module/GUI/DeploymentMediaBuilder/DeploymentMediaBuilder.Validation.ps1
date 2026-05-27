# DeploymentMediaBuilder.Validation.ps1
# Validation and plan helpers extracted from DeploymentMediaBuilderDialog.ps1.

function Write-GuiDeploymentMediaBuilderValidationDebugLog
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Message,

		[string]$Source = 'DeploymentMediaBuilder.Validation.DebugLog'
	)

	try { LogDebug $Message }
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source $Source -Severity Warning
		}
	}
}

function Import-GuiDeploymentMediaExecutionHelpers
{
	[CmdletBinding()]
	param ()

	$requiredHelpers = @(
		'New-GuiDeploymentMediaCancellationState',
		'Assert-GuiDeploymentMediaNotCancelled',
		'Invoke-GuiDeploymentMediaPowerShellStage',
		'Import-GuiDeploymentMediaDismModule',
		'Invoke-GuiDeploymentMediaIsoDismountCleanup'
	)

	$missingHelpers = @($requiredHelpers | Where-Object { -not (Get-Command -Name $_ -CommandType Function -ErrorAction SilentlyContinue) })
	if ($missingHelpers.Count -eq 0) { return }

	$candidates = [System.Collections.Generic.List[string]]::new()
	foreach ($root in @($PSScriptRoot, (Split-Path -Parent $PSScriptRoot)))
	{
		if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
		[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilder.Execution.ps1'))
		[void]$candidates.Add((Join-Path ([string]$root) 'DeploymentMediaBuilder\DeploymentMediaBuilder.Execution.ps1'))
	}

	foreach ($candidate in @($candidates))
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
		$fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
		if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
		. $fullPath
		break
	}

	$stillMissing = @($requiredHelpers | Where-Object { -not (Get-Command -Name $_ -CommandType Function -ErrorAction SilentlyContinue) })
	if ($stillMissing.Count -gt 0)
	{
		throw ('Deployment Media Builder execution helpers are required before ISO validation can run. Missing: {0}' -f ($stillMissing -join ', '))
	}
}

function New-GuiDeploymentMediaBuildPlan
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$SourceIso,
		[string]$WorkingDirectory,
		[int]$EditionIndex = 1,
		[string]$EditionName = '',
		[string]$AutounattendPath = '',
		[string]$DriverSource = '',
		[string]$UsbTargetRoot = '',
		[object]$IsoImageInfo,
		[ValidateSet('Create ISO', 'Create USB', 'Export Working Folder Only')]
		[string]$OutputMode = 'Create ISO',
		[switch]$InjectBootDrivers,
		[switch]$IncludeBaselineTweaks
	)

	$errors = [System.Collections.Generic.List[string]]::new()
	$resolvedWorkingDirectory = $WorkingDirectory
	if ([string]::IsNullOrWhiteSpace($resolvedWorkingDirectory))
	{
		$resolvedWorkingDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\Working'
	}

	if ([string]::IsNullOrWhiteSpace($SourceIso))
	{
		[void]$errors.Add('Source ISO is required.')
	}
	elseif ([System.IO.Path]::GetExtension($SourceIso) -ne '.iso')
	{
		[void]$errors.Add('Source ISO must be an .iso file.')
	}
	elseif (-not (Test-Path -LiteralPath $SourceIso -PathType Leaf))
	{
		[void]$errors.Add(('Source ISO does not exist: {0}' -f $SourceIso))
	}

	if ($EditionIndex -lt 1)
	{
		[void]$errors.Add('Selected edition index must be 1 or higher.')
	}

	if (-not $IsoImageInfo)
	{
		[void]$errors.Add('Run Detect Editions before starting a build so WIM/ESD presence and available editions are verified.')
	}
	elseif (-not $IsoImageInfo.PSObject.Properties['ImagePath'] -or [string]::IsNullOrWhiteSpace([string]$IsoImageInfo.ImagePath))
	{
		[void]$errors.Add('Detected ISO image details are incomplete; run Detect Editions again.')
	}
	elseif ($IsoImageInfo.PSObject.Properties['SourceIso'] -and [string]$IsoImageInfo.SourceIso -ne [string]$SourceIso)
	{
		[void]$errors.Add('Detected ISO image details belong to a different source ISO; run Detect Editions again.')
	}

	if (-not [System.IO.Path]::IsPathRooted($resolvedWorkingDirectory))
	{
		[void]$errors.Add('Working directory must be an absolute path.')
	}

	if (-not [string]::IsNullOrWhiteSpace($AutounattendPath))
	{
		if ([System.IO.Path]::GetExtension($AutounattendPath) -ne '.xml')
		{
			[void]$errors.Add('Autounattend file must be an .xml file.')
		}
		elseif (-not (Test-Path -LiteralPath $AutounattendPath -PathType Leaf))
		{
			[void]$errors.Add(('Autounattend file does not exist: {0}' -f $AutounattendPath))
		}
	}

	if (-not [string]::IsNullOrWhiteSpace($DriverSource))
	{
		if (-not (Test-Path -LiteralPath $DriverSource -PathType Container))
		{
			[void]$errors.Add(('Driver source directory does not exist: {0}' -f $DriverSource))
		}
	}

	if ($OutputMode -eq 'Create USB')
	{
		if ([string]::IsNullOrWhiteSpace($UsbTargetRoot))
		{
			[void]$errors.Add('USB target root is required when output mode is Create USB.')
		}
		elseif (-not (Test-Path -LiteralPath $UsbTargetRoot -PathType Container))
		{
			[void]$errors.Add(('USB target root does not exist: {0}' -f $UsbTargetRoot))
		}
		else
		{
			$normalizedUsbRoot = [System.IO.Path]::GetFullPath($UsbTargetRoot)
			$driveRoot = [System.IO.Path]::GetPathRoot($normalizedUsbRoot)
			if ($normalizedUsbRoot.TrimEnd('\') -ne $driveRoot.TrimEnd('\'))
			{
				[void]$errors.Add('USB target must be the root of a removable drive, for example E:\.')
			}
			else
			{
				$driveLetter = $driveRoot.TrimEnd('\')
				$logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveLetter.Replace("'", "''")) -ErrorAction SilentlyContinue
				if (-not $logicalDisk -or [int]$logicalDisk.DriveType -ne 2)
				{
					[void]$errors.Add('USB target must be a removable drive.')
				}
				elseif (@([System.IO.Directory]::GetFileSystemEntries($driveRoot)).Count -gt 0)
				{
					[void]$errors.Add('USB target root must be empty before Baseline copies media to it.')
				}
			}
		}
	}

	$steps = [System.Collections.Generic.List[string]]::new()
	[void]$steps.Add('Confirm the selected source is an official Microsoft Windows 10/11 ISO.')
	[void]$steps.Add('Copy the ISO contents into the working directory; never modify the original ISO.')
	[void]$steps.Add('Verify sources\install.wim or sources\install.esd before image customization.')
	if ($IsoImageInfo -and $IsoImageInfo.PSObject.Properties['ImagePath'])
	{
		[void]$steps.Add(('Detected install image: {0}' -f $IsoImageInfo.ImagePath))
	}
	[void]$steps.Add(('Use selected image index {0}{1}.' -f $EditionIndex, $(if ([string]::IsNullOrWhiteSpace($EditionName)) { '' } else { " ($EditionName)" })))
	if (-not [string]::IsNullOrWhiteSpace($AutounattendPath)) { [void]$steps.Add(('Stage autounattend.xml from {0}.' -f $AutounattendPath)) }
	if ($IncludeBaselineTweaks) { [void]$steps.Add('Stage selected Baseline setup customizations as an auditable first-logon plan.') }
	if (-not [string]::IsNullOrWhiteSpace($DriverSource)) { [void]$steps.Add(('Inject drivers from {0} into install.wim.' -f $DriverSource)) }
	if ($InjectBootDrivers) { [void]$steps.Add('Inject selected storage/network drivers into boot.wim.') }
	[void]$steps.Add(('Produce output mode: {0}.' -f $OutputMode))
	if ($OutputMode -eq 'Create USB') { [void]$steps.Add(('Copy prepared media to empty removable USB target: {0}' -f $UsbTargetRoot)) }
	[void]$steps.Add('Save the build report, clean up mounts, and fail visibly on DISM or oscdimg errors.')

	$safety = @(
		'Official Microsoft ISO only.',
		'Never modify the original ISO.',
		'Always use a temp/working directory.',
		'Always verify WIM/ESD presence and selected image index.',
		'Always show the selected edition before build.',
		'Always produce a build log/report.',
		'Always cleanup mounts.',
		'Support safe cancellation.',
		'Never silently ignore DISM or oscdimg failures.',
		'Preview Build Plan remains optional before Start ISO Build.'
	)

	return [pscustomobject]@{
		IsValid = ($errors.Count -eq 0)
		Errors = @($errors.ToArray())
		SourceIso = $SourceIso
		WorkingDirectory = $resolvedWorkingDirectory
		OutputMode = $OutputMode
		EditionIndex = $EditionIndex
		EditionName = $EditionName
		IsoImageInfo = $IsoImageInfo
		AutounattendPath = $AutounattendPath
		DriverSource = $DriverSource
		UsbTargetRoot = $UsbTargetRoot
		InjectBootDrivers = [bool]$InjectBootDrivers
		IncludeBaselineTweaks = [bool]$IncludeBaselineTweaks
		Safety = $safety
		Steps = @($steps.ToArray())
		CreatedUtc = [DateTime]::UtcNow
	}
}

function Get-GuiDeploymentMediaIsoImageInfo
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$SourceIso,
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 900
	)

	Import-GuiDeploymentMediaExecutionHelpers

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}
	Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'ISO edition detection'

	if ([string]::IsNullOrWhiteSpace($SourceIso))
	{
		throw 'Source ISO is required.'
	}
	if ([System.IO.Path]::GetExtension($SourceIso) -ne '.iso')
	{
		throw 'Source ISO must be an .iso file.'
	}
	if (-not (Test-Path -LiteralPath $SourceIso -PathType Leaf))
	{
		throw ('Source ISO does not exist: {0}' -f $SourceIso)
	}
	if (-not (Get-Command -Name 'Mount-DiskImage' -CommandType Function, Cmdlet -ErrorAction SilentlyContinue))
	{
		throw 'Mount-DiskImage is required to inspect Windows ISO media.'
	}
	Import-GuiDeploymentMediaDismModule

	$diskImage = $null
	$result = $null
	$primaryError = $null
	$cleanupError = $null
	try
	{
		$diskImage = $true
		$mountInfo = Invoke-GuiDeploymentMediaPowerShellStage -Name 'Mount source ISO for edition detection' -ScriptBlock {
			param ([string]$Path)
			$mountedImage = Mount-DiskImage -ImagePath $Path -StorageType ISO -Access ReadOnly -PassThru -ErrorAction Stop
			$volume = $mountedImage | Get-Volume -ErrorAction Stop | Select-Object -First 1
			if (-not $volume -or [string]::IsNullOrWhiteSpace([string]$volume.DriveLetter))
			{
				throw 'Mounted ISO did not expose a drive letter.'
			}
			[pscustomobject]@{
				DriveLetter = [string]$volume.DriveLetter
			}
		} -ArgumentList @($SourceIso) -TimeoutSeconds ([Math]::Min($TimeoutSeconds, 300)) -CancellationState $CancellationState
		$isoRoot = ('{0}:\' -f $mountInfo.DriveLetter)
		$wimPath = Join-Path $isoRoot 'sources\install.wim'
		$esdPath = Join-Path $isoRoot 'sources\install.esd'
		$imagePath = $null
		$imageKind = $null
		if (Test-Path -LiteralPath $wimPath -PathType Leaf)
		{
			$imagePath = $wimPath
			$imageKind = 'WIM'
		}
		elseif (Test-Path -LiteralPath $esdPath -PathType Leaf)
		{
			$imagePath = $esdPath
			$imageKind = 'ESD'
		}
		else
		{
			throw 'The ISO does not contain sources\install.wim or sources\install.esd.'
		}

		$editions = [System.Collections.Generic.List[object]]::new()
		$imageTimeoutSeconds = [Math]::Max(1, ($TimeoutSeconds - 300))
		foreach ($image in @(Invoke-GuiDeploymentMediaPowerShellStage -Name 'Read install image editions' -ScriptBlock {
			param ([string]$Path)
			Import-Module -Name 'Dism' -ErrorAction Stop -WarningAction SilentlyContinue
			foreach ($windowsImage in @(Get-WindowsImage -ImagePath $Path -ErrorAction Stop))
			{
				$architecture = ''
				if ($windowsImage.PSObject.Properties['Architecture'])
				{
					$architecture = [string]$windowsImage.Architecture
				}
				[pscustomobject]@{
					ImageIndex = [int]$windowsImage.ImageIndex
					ImageName = [string]$windowsImage.ImageName
					ImageDescription = [string]$windowsImage.ImageDescription
					ImageSize = $windowsImage.ImageSize
					Architecture = $architecture
				}
			}
		} -ArgumentList @($imagePath) -TimeoutSeconds $imageTimeoutSeconds -CancellationState $CancellationState))
		{
			[void]$editions.Add([pscustomobject]@{
				Index = [int]$image.ImageIndex
				Name = [string]$image.ImageName
				Description = [string]$image.ImageDescription
				Size = $image.ImageSize
				Architecture = [string]$image.Architecture
			})
		}
		if ($editions.Count -lt 1)
		{
			throw 'The install image did not expose any editions.'
		}

		$result = [pscustomobject]@{
			SourceIso = $SourceIso
			IsoRoot = $isoRoot
			ImagePath = $imagePath
			ImageKind = $imageKind
			Editions = @($editions.ToArray())
			DetectedUtc = [DateTime]::UtcNow
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.Validation.Get-GuiDeploymentMediaIsoImageInfo:catch288' -Severity Debug }

		$primaryError = $_
	}
	finally
	{
		if ($diskImage)
		{
			try { Invoke-GuiDeploymentMediaIsoDismountCleanup -ImagePath $SourceIso -CancellationState $CancellationState }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.Validation.Get-GuiDeploymentMediaIsoImageInfo:catch297' -Severity Debug }
			 $cleanupError = $_ }
		}
	}

	if ($cleanupError -and $primaryError)
	{
		throw ('ISO edition detection failed before source ISO cleanup completed. Detection error: {0} Cleanup error: {1}' -f $primaryError.Exception.Message, $cleanupError.Exception.Message)
	}
	if ($cleanupError)
	{
		throw ('Failed to cleanup mounted ISO: {0}' -f $cleanupError.Exception.Message)
	}
	if ($primaryError)
	{
		throw $primaryError
	}

	return $result
}

function Get-GuiDeploymentMediaMicrosoftIsoOptions
{
	[CmdletBinding()]
	[OutputType([object[]])]
	param ()

	return @(
		[pscustomobject]@{
			Id = 'Windows11MctX64'
			Label = 'Windows 11 ISO via Media Creation Tool (official x64)'
			ProductName = 'Windows 11'
			Architecture = 'x64'
			Language = 'English'
			LanguageLabel = 'English'
			PageUrl = 'https://www.microsoft.com/en-us/software-download/windows11'
			AcquisitionTier = 1
			AcquisitionMode = 'MediaCreationTool'
			MediaCreationToolUrl = 'https://go.microsoft.com/fwlink/?linkid=2156295'
			ToolFileName = 'MediaCreationToolW11.exe'
			FilePrefix = 'Win11_MCT_x64'
		}
		[pscustomobject]@{
			Id = 'Windows10MctX64'
			Label = 'Windows 10 ISO via Media Creation Tool (official x64)'
			ProductName = 'Windows 10'
			Architecture = 'x64'
			Language = 'English'
			LanguageLabel = 'English'
			PageUrl = 'https://www.microsoft.com/en-us/software-download/windows10'
			AcquisitionTier = 1
			AcquisitionMode = 'MediaCreationTool'
			MediaCreationToolUrl = 'https://go.microsoft.com/fwlink/?LinkId=691209'
			ToolFileName = 'MediaCreationTool22H2.exe'
			FilePrefix = 'Win10_MCT_x64'
		}
		[pscustomobject]@{
			Id = 'Windows11ManualPage'
			Label = 'Windows 11 manual download page (official)'
			ProductName = 'Windows 11'
			Architecture = 'x64'
			Language = 'English'
			LanguageLabel = 'English'
			PageUrl = 'https://www.microsoft.com/en-us/software-download/windows11'
			AcquisitionTier = 3
			AcquisitionMode = 'ManualPage'
			FilePrefix = 'Win11_Manual_x64'
		}
		[pscustomobject]@{
			Id = 'Windows10ManualPage'
			Label = 'Windows 10 manual download page (official)'
			ProductName = 'Windows 10'
			Architecture = 'x64'
			Language = 'English'
			LanguageLabel = 'English'
			PageUrl = 'https://www.microsoft.com/en-us/software-download/windows10'
			AcquisitionTier = 3
			AcquisitionMode = 'ManualPage'
			FilePrefix = 'Win10_Manual_x64'
		}
		[pscustomobject]@{
			Id = 'WindowsUupWebsiteAssembly'
			Label = 'Advanced: UUP dump local ISO assembly'
			ProductName = 'Windows UUP'
			Architecture = 'x64'
			Language = 'English'
			LanguageLabel = 'English'
			PageUrl = 'https://uupdump.net/'
			AcquisitionTier = 2
			AcquisitionMode = 'UUPLocal'
			ComplianceLabel = 'Generated installation media using Microsoft UUP files.'
			FilePrefix = 'Windows_UUP_Local'
		}
	)
}

function Get-GuiDeploymentMediaMicrosoftIsoDefaultDirectory
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$userProfile = [Environment]::GetFolderPath('UserProfile')
	if ([string]::IsNullOrWhiteSpace($userProfile))
	{
		return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\ISOs')
	}

	return (Join-Path (Join-Path $userProfile 'Downloads') 'Baseline\Windows ISO')
}

function Get-GuiDeploymentMediaMicrosoftMediaCreationToolDirectory
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\MediaCreationTool')
}

function New-GuiDeploymentMediaMicrosoftHttpRequest
{
	[CmdletBinding()]
	[OutputType([System.Net.HttpWebRequest])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Uri,
		[AllowNull()]
		[System.Net.CookieContainer]$CookieContainer,
		[string]$Referer = '',
		[string]$Accept = '*/*',
		[int]$TimeoutSeconds = 60
	)

	[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
	$request = [System.Net.HttpWebRequest]([System.Net.WebRequest]::Create($Uri))
	$request.Method = 'GET'
	$request.UserAgent = 'Baseline Deployment Media Builder'
	$request.Accept = $Accept
	$request.Headers['Accept-Language'] = 'en-US,en;q=0.9'
	$request.Headers['Cache-Control'] = 'no-cache'
	if (-not [string]::IsNullOrWhiteSpace($Referer))
	{
		$request.Referer = $Referer
	}
	if ($CookieContainer)
	{
		$request.CookieContainer = $CookieContainer
	}
	$timeout = [Math]::Max(1, $TimeoutSeconds) * 1000
	$request.Timeout = $timeout
	$request.ReadWriteTimeout = $timeout
	$request.AllowAutoRedirect = $true
	return $request
}

function Test-GuiDeploymentMediaMicrosoftDownloadUri
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Uri
	)

	try
	{
		$parsed = New-Object System.Uri -ArgumentList $Uri
		if ($parsed.Scheme -ne 'https') { return $false }
		$uriHost = $parsed.Host.ToLowerInvariant()
		if ($uriHost -eq 'download.microsoft.com') { return $true }
		if ($uriHost.EndsWith('.microsoft.com')) { return $true }
		if ($uriHost -eq 'download.windowsupdate.com') { return $true }
		if ($uriHost.EndsWith('.download.windowsupdate.com')) { return $true }
		return $false
	}
	catch
	{
		LogDebug ('Trusted Microsoft download URI parse failed. Uri="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Uri, $_.Exception.GetType().FullName, $_.Exception.Message)
		return $false
	}
}

function Get-GuiDeploymentMediaMicrosoftConnectorErrorMessage
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Operation,
		[Parameter(Mandatory = $true)]
		[string]$Json
	)

	$normalizedJson = $Json -replace '\s+', ' '
	try
	{
		$data = $Json | ConvertFrom-Json
	}
	catch
	{
		LogDebug ('Microsoft connector error JSON parse failed. Operation="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Operation, $_.Exception.GetType().FullName, $_.Exception.Message)
		return ('Microsoft rejected the {0}: {1}' -f $Operation, $normalizedJson)
	}

	$errors = @()
	if ($data -and $data.PSObject.Properties['Errors'])
	{
		$errors = @($data.Errors)
	}
	if ($errors.Count -eq 0)
	{
		return ('Microsoft rejected the {0}: {1}' -f $Operation, $normalizedJson)
	}

	$details = New-Object System.Collections.Generic.List[string]
	$hasSentinelRejection = $false
	foreach ($errorItem in $errors)
	{
		$key = [string]$errorItem.Key
		$value = [string]$errorItem.Value
		if ($key -eq 'ErrorSettings.SentinelReject')
		{
			$hasSentinelRejection = $true
		}
		if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($value))
		{
			[void]$details.Add(('{0} - {1}' -f $key, $value))
		}
		elseif (-not [string]::IsNullOrWhiteSpace($key))
		{
			[void]$details.Add($key)
		}
		elseif (-not [string]::IsNullOrWhiteSpace($value))
		{
			[void]$details.Add($value)
		}
	}

	if ($hasSentinelRejection)
	{
		return 'Microsoft temporarily rejected the automated ISO download request. This can happen when Microsoft rate-limits or blocks automated download sessions. Try again later, download the ISO manually from Microsoft, or import an existing ISO.'
	}

	if ($details.Count -eq 0)
	{
		return ('Microsoft rejected the {0}: {1}' -f $Operation, $normalizedJson)
	}

	return ('Microsoft rejected the {0}: {1}' -f $Operation, ($details -join '; '))
}

function Resolve-GuiDeploymentMediaMicrosoftIsoDownloadLink
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option,
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 600)]
		[int]$TimeoutSeconds = 90
	)

	throw 'Legacy direct Microsoft web connector ISO acquisition is disabled. Use Media Creation Tool orchestration, the official Microsoft download page, or import an existing ISO.'
}

function Get-GuiDeploymentMediaUniqueFilePath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Directory,
		[Parameter(Mandatory = $true)]
		[string]$FileName
	)

	$targetPath = Join-Path $Directory $FileName
	if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf))
	{
		return $targetPath
	}

	$baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
	$extension = [System.IO.Path]::GetExtension($FileName)
	for ($index = 1; $index -le 999; $index++)
	{
		$candidate = Join-Path $Directory ('{0}_{1}{2}' -f $baseName, $index, $extension)
		if (-not (Test-Path -LiteralPath $candidate -PathType Leaf))
		{
			return $candidate
		}
	}

	return (Join-Path $Directory ('{0}_{1:yyyyMMddHHmmss}{2}' -f $baseName, [DateTime]::Now, $extension))
}

function Get-GuiDeploymentMediaFileSha256
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		throw ('File not found for SHA256 calculation: {0}' -f $Path)
	}

	return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-GuiDeploymentMediaMicrosoftExecutableSignature
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	$signature = Get-AuthenticodeSignature -LiteralPath $Path
	if ($signature.Status -ne 'Valid')
	{
		throw ('Downloaded Microsoft executable signature is not valid. Status: {0}' -f $signature.Status)
	}

	$subject = ''
	if ($signature.SignerCertificate)
	{
		$subject = [string]$signature.SignerCertificate.Subject
	}
	if ($subject -notmatch 'Microsoft')
	{
		throw ('Downloaded executable is not signed by Microsoft. Signer: {0}' -f $subject)
	}

	return [pscustomobject]@{
		Status = [string]$signature.Status
		Signer = $subject
		Thumbprint = $(if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { '' })
	}
}

function Save-GuiDeploymentMediaMicrosoftMediaCreationTool
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option,
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 600)]
		[int]$TimeoutSeconds = 300
	)

	Import-GuiDeploymentMediaExecutionHelpers

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}

	$toolUri = [string]$Option.MediaCreationToolUrl
	if (-not (Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri $toolUri))
	{
		throw ('Media Creation Tool URL is not a trusted Microsoft HTTPS URL: {0}' -f $toolUri)
	}

	$toolDirectory = Get-GuiDeploymentMediaMicrosoftMediaCreationToolDirectory
	if (-not (Test-Path -LiteralPath $toolDirectory -PathType Container))
	{
		[void][System.IO.Directory]::CreateDirectory($toolDirectory)
	}

	$fileName = [string]$Option.ToolFileName
	if ([string]::IsNullOrWhiteSpace($fileName))
	{
		$fileName = ('MediaCreationTool_{0}.exe' -f ([string]$Option.ProductName -replace '\W+', ''))
	}
	$targetPath = Join-Path $toolDirectory $fileName
	$partialPath = $targetPath + '.partial'
	$response = $null
	$responseStream = $null
	$targetStream = $null
	$sha256 = [System.Security.Cryptography.SHA256]::Create()
	$totalRead = [int64]0
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool download prepared. Product="{0}"; Uri="{1}"; TargetPath="{2}"; PartialPath="{3}"; TimeoutSeconds={4}' -f [string]$Option.ProductName, $toolUri, $targetPath, $partialPath, $TimeoutSeconds) -Source 'DeploymentMediaBuilder.Validation.MctDownload.Prepared'

	try
	{
		Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'Media Creation Tool download'
		$CancellationState.Status = ('Downloading Microsoft Media Creation Tool for {0}.' -f $Option.ProductName)
		if (Test-Path -LiteralPath $partialPath -PathType Leaf)
		{
			Remove-Item -LiteralPath $partialPath -Force -ErrorAction Stop
		}

		$request = New-GuiDeploymentMediaMicrosoftHttpRequest -Uri $toolUri -Accept 'application/octet-stream,*/*' -TimeoutSeconds $TimeoutSeconds
		$response = $request.GetResponse()
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool download response received. Product="{0}"; ResponseUri="{1}"; ContentLength={2}' -f [string]$Option.ProductName, $(if ($response.ResponseUri) { [string]$response.ResponseUri.AbsoluteUri } else { '' }), [int64]$response.ContentLength) -Source 'DeploymentMediaBuilder.Validation.MctDownload.Response'
		if ($response.ResponseUri -and -not (Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri ([string]$response.ResponseUri.AbsoluteUri)))
		{
			throw ('Media Creation Tool download redirected to an unexpected host: {0}' -f $response.ResponseUri.AbsoluteUri)
		}
		$responseStream = $response.GetResponseStream()
		$targetStream = [System.IO.File]::Create($partialPath)
		$buffer = New-Object byte[] 262144
		do
		{
			Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'Media Creation Tool download'
			$read = $responseStream.Read($buffer, 0, $buffer.Length)
			if ($read -gt 0)
			{
				$targetStream.Write($buffer, 0, $read)
				[void]$sha256.TransformBlock($buffer, 0, $read, $buffer, 0)
				$totalRead += [int64]$read
			}
		}
		while ($read -gt 0)

		if ($totalRead -le 0)
		{
			throw 'Microsoft returned an empty Media Creation Tool download.'
		}
		[void]$sha256.TransformFinalBlock((New-Object byte[] 0), 0, 0)
		$streamHash = ([BitConverter]::ToString($sha256.Hash) -replace '-', '').ToUpperInvariant()
		$targetStream.Dispose()
		$targetStream = $null
		if (Test-Path -LiteralPath $targetPath -PathType Leaf)
		{
			Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
		}
		[System.IO.File]::Move($partialPath, $targetPath)
		$fileHash = Get-GuiDeploymentMediaFileSha256 -Path $targetPath
		if ($fileHash -ne $streamHash)
		{
			throw 'Downloaded Media Creation Tool hash verification failed after writing the file.'
		}
		$signatureInfo = Test-GuiDeploymentMediaMicrosoftExecutableSignature -Path $targetPath
		$CancellationState.Status = ('Verified Microsoft Media Creation Tool for {0}.' -f $Option.ProductName)
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool download verified. Product="{0}"; Path="{1}"; Bytes={2}; Sha256="{3}"; Signer="{4}"; Thumbprint="{5}"' -f [string]$Option.ProductName, $targetPath, $totalRead, $fileHash, [string]$signatureInfo.Signer, [string]$signatureInfo.Thumbprint) -Source 'DeploymentMediaBuilder.Validation.MctDownload.Verified'

		return [pscustomobject]@{
			Path = $targetPath
			FileName = [System.IO.Path]::GetFileName($targetPath)
			Bytes = $totalRead
			Sha256 = $fileHash
			Signature = $signatureInfo
			Uri = $toolUri
			ProductName = [string]$Option.ProductName
			DownloadedUtc = [DateTime]::UtcNow
		}
	}
	finally
	{
		if ($targetStream) { $targetStream.Dispose() }
		if ($responseStream) { $responseStream.Dispose() }
		if ($response) { $response.Dispose() }
		if ($sha256) { $sha256.Dispose() }
	}
}

function Get-GuiDeploymentMediaMctWatchDirectories
{
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[string]$DestinationDirectory = ''
	)

	$candidates = New-Object System.Collections.Generic.List[string]
	if (-not [string]::IsNullOrWhiteSpace($DestinationDirectory))
	{
		if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container))
		{
			[void][System.IO.Directory]::CreateDirectory($DestinationDirectory)
		}
		[void]$candidates.Add([System.IO.Path]::GetFullPath($DestinationDirectory))
	}

	foreach ($knownFolder in @([Environment]::GetFolderPath('UserProfile'), [Environment]::GetFolderPath('Desktop')))
	{
		if ([string]::IsNullOrWhiteSpace($knownFolder)) { continue }
		$directory = $knownFolder
		if ([System.IO.Path]::GetFileName($knownFolder) -ne 'Desktop')
		{
			$directory = Join-Path $knownFolder 'Downloads'
		}
		if (Test-Path -LiteralPath $directory -PathType Container)
		{
			[void]$candidates.Add([System.IO.Path]::GetFullPath($directory))
		}
	}

	$unique = @{}
	foreach ($candidate in $candidates)
	{
		$key = $candidate.ToLowerInvariant()
		if (-not $unique.ContainsKey($key))
		{
			$unique[$key] = $candidate
		}
	}

	return @($unique.Values)
}

function Test-GuiDeploymentMediaFileFinalized
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[hashtable]$State,
		[string[]]$AllowedExtensions = @(),
		[int64]$MinimumBytes = 1
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
	$item = Get-Item -LiteralPath $Path -ErrorAction Stop
	if ($AllowedExtensions.Count -gt 0 -and $item.Extension.ToLowerInvariant() -notin @($AllowedExtensions | ForEach-Object { ([string]$_).ToLowerInvariant() })) { return $false }
	if ($item.Length -lt $MinimumBytes) { return $false }

	$key = $item.FullName.ToLowerInvariant()
	$stamp = ('{0}:{1}' -f $item.Length, $item.LastWriteTimeUtc.Ticks)
	if (-not $State.ContainsKey($key) -or $State[$key].Stamp -ne $stamp)
	{
		$State[$key] = [pscustomobject]@{ Stamp = $stamp; StableCount = 0 }
		return $false
	}

	$State[$key].StableCount = [int]$State[$key].StableCount + 1
	if ([int]$State[$key].StableCount -lt 2) { return $false }

	$stream = $null
	try
	{
		$stream = [System.IO.File]::Open($item.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
		return $true
	}
	catch
	{
		LogDebug ('Deployment media file finalization check could not acquire exclusive read lock. Path="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Path, $_.Exception.GetType().FullName, $_.Exception.Message)
		return $false
	}
	finally
	{
		if ($stream) { $stream.Dispose() }
	}
}

function Test-GuiDeploymentMediaIsoFileFinalized
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[hashtable]$State
	)

	return (Test-GuiDeploymentMediaFileFinalized -Path $Path -State $State -AllowedExtensions @('.iso') -MinimumBytes 1)
}

function Get-GuiDeploymentMediaLiveProcessTreeSnapshot
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[int]$RootProcessId,
		[int[]]$KnownProcessIds = @()
	)

	$seen = @{}
	$known = @{}
	$live = @{}
	$queue = [System.Collections.Generic.Queue[int]]::new()
	foreach ($processId in @($RootProcessId) + @($KnownProcessIds))
	{
		if ($processId -gt 0 -and -not $known.ContainsKey($processId))
		{
			$known[$processId] = $true
			$queue.Enqueue($processId)
		}
	}

	while ($queue.Count -gt 0)
	{
		$processId = [int]$queue.Dequeue()
		if ($seen.ContainsKey($processId)) { continue }
		$seen[$processId] = $true

		$process = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId={0}' -f $processId) -ErrorAction SilentlyContinue
		if ($process)
		{
			$live[$processId] = $true
		}

		foreach ($child in @(Get-CimInstance -ClassName Win32_Process -Filter ('ParentProcessId={0}' -f $processId) -ErrorAction SilentlyContinue))
		{
			$childProcessId = [int]$child.ProcessId
			if ($childProcessId -le 0) { continue }
			if (-not $known.ContainsKey($childProcessId))
			{
				$known[$childProcessId] = $true
				$queue.Enqueue($childProcessId)
			}
			$live[$childProcessId] = $true
		}
	}

	return [pscustomobject]@{
		KnownProcessIds = @($known.Keys)
		LiveProcessIds = @($live.Keys)
	}
}

function Wait-GuiDeploymentMediaMctIsoFile
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string[]]$WatchDirectories,
		[Parameter(Mandatory = $true)]
		[DateTime]$StartedUtc,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[object]$Process,
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 28800,
		[string]$StageName = 'Media Creation Tool ISO monitoring',
		[string]$StatusMessage = 'Waiting for the Microsoft Media Creation Tool to finish writing an ISO file.',
		[string]$ProcessExitMessage = 'The Microsoft Media Creation Tool closed before Baseline detected a completed ISO in the watched folders. Use Import ISO if the ISO was saved elsewhere.',
		[string]$TimeoutMessage = '',
		[ValidateRange(1, 3600)]
		[int]$ProcessExitGraceSeconds = 15,
		[ValidateRange(1, 3600)]
		[int]$IsoFinalizationGraceSeconds = 90,
		[switch]$IncludeSubdirectories
	)

	Import-GuiDeploymentMediaExecutionHelpers

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}

	$deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	$candidatePaths = @{}
	$fileStates = @{}
	$queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
	$watchers = New-Object System.Collections.Generic.List[object]
	$processExitedUtc = $null
	$lastStatusUtc = [DateTime]::MinValue
	$rootProcessId = 0
	$knownProcessIds = @()
	$lastProcessRunningState = $null
	$loggedCandidatePaths = @{}
	if ($Process -and $Process.PSObject.Properties['Id'])
	{
		$rootProcessId = [int]$Process.Id
		$knownProcessIds = @($rootProcessId)
	}
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher initialized. Stage="{0}"; WatchDirectories="{1}"; StartedUtc="{2:o}"; TimeoutSeconds={3}; RootProcessId={4}; IncludeSubdirectories={5}' -f $StageName, (@($WatchDirectories) -join ';'), $StartedUtc, $TimeoutSeconds, $rootProcessId, [bool]$IncludeSubdirectories) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.Initialized'

	try
	{
		foreach ($directory in $WatchDirectories)
		{
			if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
			$watcher = New-Object System.IO.FileSystemWatcher
			$watcher.Path = $directory
			$watcher.Filter = '*.iso'
			$watcher.IncludeSubdirectories = [bool]$IncludeSubdirectories
			$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
			$handler = {
				param ($Sender, $EventArgs)
				if ($EventArgs -and -not [string]::IsNullOrWhiteSpace([string]$EventArgs.FullPath))
				{
					$queue.Enqueue([string]$EventArgs.FullPath)
				}
			}.GetNewClosure()
			$watcher.add_Created($handler)
			$watcher.add_Changed($handler)
			$watcher.add_Renamed($handler)
			$watcher.EnableRaisingEvents = $true
			[void]$watchers.Add($watcher)
		}
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher registered filesystem watchers. Stage="{0}"; WatcherCount={1}' -f $StageName, $watchers.Count) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.WatchersRegistered'

		while ([DateTime]::UtcNow -lt $deadlineUtc)
		{
			Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage $StageName
			$nowUtc = [DateTime]::UtcNow
			if (($nowUtc - $lastStatusUtc).TotalSeconds -ge 5)
			{
				$lastStatusUtc = $nowUtc
				if ($processExitedUtc)
				{
					$CancellationState.Status = 'Microsoft Media Creation Tool is closed; checking for completed ISO output.'
				}
				else
				{
					$CancellationState.Status = $StatusMessage
				}
			}

			if ($Process)
			{
				$processIsRunning = $false
				$liveProcessIds = @()
				if ($rootProcessId -gt 0)
				{
					$snapshot = Get-GuiDeploymentMediaLiveProcessTreeSnapshot -RootProcessId $rootProcessId -KnownProcessIds $knownProcessIds
					$knownProcessIds = @($snapshot.KnownProcessIds)
					$liveProcessIds = @($snapshot.LiveProcessIds)
					$processIsRunning = (@($snapshot.LiveProcessIds).Count -gt 0)
				}
				else
				{
					try
					{
						$Process.Refresh()
						$processIsRunning = (-not $Process.HasExited)
					}
					catch
					{
						LogDebug ('ISO output watcher process refresh failed. Stage="{0}"; RootProcessId={1}; ExceptionType="{2}"; Message="{3}"' -f $StageName, $rootProcessId, $_.Exception.GetType().FullName, $_.Exception.Message)
						$processIsRunning = $false
					}
				}
				if (-not $processIsRunning)
				{
					if (-not $processExitedUtc)
					{
						$processExitedUtc = [DateTime]::UtcNow
						Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher observed process tree exit. Stage="{0}"; RootProcessId={1}; KnownProcessIds="{2}"; CandidateCount={3}' -f $StageName, $rootProcessId, (@($knownProcessIds) -join ','), @($candidatePaths.Values).Count) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.ProcessExited'
					}
				}
				else
				{
					if ($processExitedUtc)
					{
						Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher observed process tree activity after an exit state. Stage="{0}"; RootProcessId={1}; LiveProcessIds="{2}"' -f $StageName, $rootProcessId, (@($liveProcessIds) -join ',')) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.ProcessResumed'
					}
					$processExitedUtc = $null
				}
				if ($lastProcessRunningState -ne $processIsRunning)
				{
					$lastProcessRunningState = $processIsRunning
					Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher process state changed. Stage="{0}"; Running={1}; RootProcessId={2}; KnownProcessIds="{3}"' -f $StageName, [bool]$processIsRunning, $rootProcessId, (@($knownProcessIds) -join ',')) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.ProcessState'
				}
			}

			$queuedPath = ''
			while ($queue.TryDequeue([ref]$queuedPath))
			{
				if (-not [string]::IsNullOrWhiteSpace($queuedPath))
				{
					$candidatePaths[$queuedPath.ToLowerInvariant()] = $queuedPath
					if (-not $loggedCandidatePaths.ContainsKey($queuedPath.ToLowerInvariant()))
					{
						$loggedCandidatePaths[$queuedPath.ToLowerInvariant()] = $true
						Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher queued candidate from filesystem event. Stage="{0}"; Path="{1}"; CandidateCount={2}' -f $StageName, $queuedPath, @($candidatePaths.Values).Count) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.EventCandidate'
					}
				}
			}

			foreach ($directory in $WatchDirectories)
			{
				if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
				$getChildItemParameters = @{
					LiteralPath = $directory
					Filter = '*.iso'
					File = $true
					ErrorAction = 'SilentlyContinue'
				}
				if ($IncludeSubdirectories)
				{
					$getChildItemParameters['Recurse'] = $true
				}
				foreach ($item in @(Get-ChildItem @getChildItemParameters))
				{
					if ($item.LastWriteTimeUtc -ge $StartedUtc.AddMinutes(-5))
					{
						$candidatePaths[$item.FullName.ToLowerInvariant()] = $item.FullName
						if (-not $loggedCandidatePaths.ContainsKey($item.FullName.ToLowerInvariant()))
						{
							$loggedCandidatePaths[$item.FullName.ToLowerInvariant()] = $true
							Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher discovered candidate by polling. Stage="{0}"; Path="{1}"; Bytes={2}; LastWriteUtc="{3:o}"; CandidateCount={4}' -f $StageName, $item.FullName, [int64]$item.Length, $item.LastWriteTimeUtc, @($candidatePaths.Values).Count) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.PollCandidate'
						}
					}
				}
			}

			foreach ($candidatePath in @($candidatePaths.Values))
			{
				if (Test-GuiDeploymentMediaIsoFileFinalized -Path $candidatePath -State $fileStates)
				{
					Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher finalized candidate. Stage="{0}"; Path="{1}"; CandidateCount={2}; ElapsedSeconds={3:n1}' -f $StageName, $candidatePath, @($candidatePaths.Values).Count, ([DateTime]::UtcNow - $StartedUtc).TotalSeconds) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.Finalized'
					return $candidatePath
				}
			}

			if ($processExitedUtc)
			{
				$exitGraceSeconds = $ProcessExitGraceSeconds
				if (@($candidatePaths.Values).Count -gt 0)
				{
					$exitGraceSeconds = $IsoFinalizationGraceSeconds
				}
				if (([DateTime]::UtcNow - $processExitedUtc).TotalSeconds -ge $exitGraceSeconds)
				{
					Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher process-exit grace expired. Stage="{0}"; ExitGraceSeconds={1}; CandidateCount={2}; ProcessExitMessage="{3}"' -f $StageName, $exitGraceSeconds, @($candidatePaths.Values).Count, $ProcessExitMessage) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.ProcessExitGraceExpired'
					throw $ProcessExitMessage
				}
			}

			Start-Sleep -Seconds 2
		}

		if ([string]::IsNullOrWhiteSpace($TimeoutMessage))
		{
			$TimeoutMessage = ('Timed out waiting for the Microsoft Media Creation Tool to create an ISO after {0} second(s).' -f $TimeoutSeconds)
		}
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher timeout reached. Stage="{0}"; TimeoutSeconds={1}; CandidateCount={2}; WatcherCount={3}; TimeoutMessage="{4}"' -f $StageName, $TimeoutSeconds, @($candidatePaths.Values).Count, $watchers.Count, $TimeoutMessage) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.Timeout'
		throw $TimeoutMessage
	}
	finally
	{
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('ISO output watcher disposing filesystem watchers. Stage="{0}"; WatcherCount={1}; CandidateCount={2}' -f $StageName, $watchers.Count, @($candidatePaths.Values).Count) -Source 'DeploymentMediaBuilder.Validation.IsoWatcher.Dispose'
		foreach ($watcher in $watchers)
		{
			try
			{
				$watcher.EnableRaisingEvents = $false
				$watcher.Dispose()
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.MctWatcher.Dispose' -Severity Warning
				}
			}
		}
	}
}

function Start-GuiDeploymentMediaMicrosoftMediaCreationToolIsoWorkflow
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option,
		[string]$DestinationDirectory = '',
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 28800
	)

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}
	if ([string]$Option.AcquisitionMode -ne 'MediaCreationTool')
	{
		throw ('The selected ISO source is not a Media Creation Tool workflow: {0}' -f $Option.Label)
	}
	if ([string]::IsNullOrWhiteSpace($DestinationDirectory))
	{
		$DestinationDirectory = Get-GuiDeploymentMediaMicrosoftIsoDefaultDirectory
	}
	if (-not [System.IO.Path]::IsPathRooted($DestinationDirectory))
	{
		throw 'Media Creation Tool watch directory must be an absolute path.'
	}

	$startedUtc = [DateTime]::UtcNow
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool ISO workflow resolved. Product="{0}"; DestinationDirectory="{1}"; TimeoutSeconds={2}; PageUrl="{3}"' -f [string]$Option.ProductName, $DestinationDirectory, $TimeoutSeconds, [string]$Option.PageUrl) -Source 'DeploymentMediaBuilder.Validation.MctWorkflow.Resolved'
	$tool = Save-GuiDeploymentMediaMicrosoftMediaCreationTool -Option $Option -CancellationState $CancellationState -TimeoutSeconds ([Math]::Min(600, $TimeoutSeconds))
	$watchDirectories = @(Get-GuiDeploymentMediaMctWatchDirectories -DestinationDirectory $DestinationDirectory)
	if ($watchDirectories.Count -eq 0)
	{
		throw 'No valid folders are available for Media Creation Tool ISO monitoring.'
	}
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool ISO workflow prepared launcher. Product="{0}"; ToolPath="{1}"; ToolSha256="{2}"; WatchDirectories="{3}"' -f [string]$Option.ProductName, [string]$tool.Path, [string]$tool.Sha256, (@($watchDirectories) -join ';')) -Source 'DeploymentMediaBuilder.Validation.MctWorkflow.Prepared'

	$CancellationState.Status = ('Launching Microsoft Media Creation Tool for {0}. Choose ISO file in the Microsoft window and save it to the watched folder.' -f $Option.ProductName)
	$process = Start-Process -FilePath ([string]$tool.Path) -PassThru -WindowStyle Normal -ErrorAction Stop
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool process launched. Product="{0}"; ProcessId={1}; ToolPath="{2}"' -f [string]$Option.ProductName, [int]$process.Id, [string]$tool.Path) -Source 'DeploymentMediaBuilder.Validation.MctWorkflow.ProcessLaunched'
	$isoPath = Wait-GuiDeploymentMediaMctIsoFile -WatchDirectories $watchDirectories -StartedUtc $startedUtc -CancellationState $CancellationState -Process $process -TimeoutSeconds $TimeoutSeconds
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool ISO detected. Product="{0}"; IsoPath="{1}"' -f [string]$Option.ProductName, $isoPath) -Source 'DeploymentMediaBuilder.Validation.MctWorkflow.IsoDetected'

	$CancellationState.Status = ('Validating ISO created by Microsoft Media Creation Tool: {0}' -f $isoPath)
	$isoInfo = Get-GuiDeploymentMediaIsoImageInfo -SourceIso $isoPath -CancellationState $CancellationState -TimeoutSeconds 900
	$isoHash = Get-GuiDeploymentMediaFileSha256 -Path $isoPath
	$CancellationState.Status = ('Imported {0} ISO created by Microsoft Media Creation Tool.' -f $Option.ProductName)
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Media Creation Tool ISO validation completed. Product="{0}"; IsoPath="{1}"; Sha256="{2}"; EditionCount={3}' -f [string]$Option.ProductName, $isoPath, $isoHash, @($isoInfo.Editions).Count) -Source 'DeploymentMediaBuilder.Validation.MctWorkflow.Validated'

	return [pscustomobject]@{
		Path = $isoPath
		FileName = [System.IO.Path]::GetFileName($isoPath)
		Bytes = (Get-Item -LiteralPath $isoPath).Length
		Sha256 = $isoHash
		ProductName = [string]$Option.ProductName
		Architecture = [string]$Option.Architecture
		Language = [string]$Option.Language
		PageUrl = [string]$Option.PageUrl
		AcquisitionMode = 'MediaCreationTool'
		ToolPath = [string]$tool.Path
		ToolSha256 = [string]$tool.Sha256
		ToolSigner = [string]$tool.Signature.Signer
		WatchedDirectories = @($watchDirectories)
		EditionCount = @($isoInfo.Editions).Count
		StartedUtc = $startedUtc
		CompletedUtc = [DateTime]::UtcNow
	}
}

function Get-GuiDeploymentMediaUupWatchDirectories
{
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$WorkspaceRoot,
		[string]$DestinationDirectory = ''
	)

	$candidates = New-Object System.Collections.Generic.List[string]
	if (-not [string]::IsNullOrWhiteSpace($DestinationDirectory))
	{
		[void]$candidates.Add($DestinationDirectory)
	}
	if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot))
	{
		[void]$candidates.Add($WorkspaceRoot)
	}
	foreach ($directory in @(Get-GuiDeploymentMediaMctWatchDirectories -DestinationDirectory $DestinationDirectory))
	{
		[void]$candidates.Add($directory)
	}

	$unique = @{}
	foreach ($candidate in $candidates)
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
		if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
		$fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
		$key = $fullPath.ToLowerInvariant()
		if (-not $unique.ContainsKey($key))
		{
			$unique[$key] = $fullPath
		}
	}

	return @($unique.Values)
}

function Test-GuiDeploymentMediaUupPackageArchive
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
	try
	{
		Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
	}
	catch
	{
		LogDebug ('UUP package archive compression assembly load failed. Path="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Path, $_.Exception.GetType().FullName, $_.Exception.Message)
		return $false
	}

	$archive = $null
	try
	{
		$archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
		foreach ($entry in @($archive.Entries))
		{
			$leafName = [System.IO.Path]::GetFileName(([string]$entry.FullName).Replace('/', '\'))
			if ($leafName -ieq 'uup_download_windows.cmd' -or $leafName -ieq 'convert-UUP.cmd')
			{
				return $true
			}
		}
		return $false
	}
	catch
	{
		LogDebug ('UUP package archive scan failed. Path="{0}"; ExceptionType="{1}"; Message="{2}"' -f $Path, $_.Exception.GetType().FullName, $_.Exception.Message)
		return $false
	}
	finally
	{
		if ($archive) { $archive.Dispose() }
	}
}

function Wait-GuiDeploymentMediaUupPackageArchive
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string[]]$WatchDirectories,
		[Parameter(Mandatory = $true)]
		[DateTime]$StartedUtc,
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 7200
	)

	Import-GuiDeploymentMediaExecutionHelpers
	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}

	$deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	$candidatePaths = @{}
	$rejectedPaths = @{}
	$fileStates = @{}
	$queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
	$watchers = New-Object System.Collections.Generic.List[object]
	$lastStatusUtc = [DateTime]::MinValue
	$loggedCandidatePaths = @{}
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher initialized. WatchDirectories="{0}"; StartedUtc="{1:o}"; TimeoutSeconds={2}' -f (@($WatchDirectories) -join ';'), $StartedUtc, $TimeoutSeconds) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.Initialized'

	try
	{
		foreach ($directory in $WatchDirectories)
		{
			if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
			$watcher = New-Object System.IO.FileSystemWatcher
			$watcher.Path = $directory
			$watcher.Filter = '*.zip'
			$watcher.IncludeSubdirectories = $false
			$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
			$handler = {
				param ($Sender, $EventArgs)
				if ($EventArgs -and -not [string]::IsNullOrWhiteSpace([string]$EventArgs.FullPath))
				{
					$queue.Enqueue([string]$EventArgs.FullPath)
				}
			}.GetNewClosure()
			$watcher.add_Created($handler)
			$watcher.add_Changed($handler)
			$watcher.add_Renamed($handler)
			$watcher.EnableRaisingEvents = $true
			[void]$watchers.Add($watcher)
		}
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher registered filesystem watchers. WatcherCount={0}' -f $watchers.Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.WatchersRegistered'

		while ([DateTime]::UtcNow -lt $deadlineUtc)
		{
			Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'UUP package download monitoring'
			$nowUtc = [DateTime]::UtcNow
			if (($nowUtc - $lastStatusUtc).TotalSeconds -ge 5)
			{
				$lastStatusUtc = $nowUtc
				$CancellationState.Status = 'Waiting for a UUP dump download package ZIP. Choose "Download and convert to ISO" on the website and save the ZIP to Downloads or the UUP workspace.'
			}

			$queuedPath = ''
			while ($queue.TryDequeue([ref]$queuedPath))
			{
				if (-not [string]::IsNullOrWhiteSpace($queuedPath))
				{
					$candidatePaths[$queuedPath.ToLowerInvariant()] = $queuedPath
					if (-not $loggedCandidatePaths.ContainsKey($queuedPath.ToLowerInvariant()))
					{
						$loggedCandidatePaths[$queuedPath.ToLowerInvariant()] = $true
						Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher queued ZIP candidate from filesystem event. Path="{0}"; CandidateCount={1}' -f $queuedPath, @($candidatePaths.Values).Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.EventCandidate'
					}
				}
			}

			foreach ($directory in $WatchDirectories)
			{
				if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
				foreach ($item in @(Get-ChildItem -LiteralPath $directory -Filter '*.zip' -File -ErrorAction SilentlyContinue))
				{
					if ($item.LastWriteTimeUtc -ge $StartedUtc.AddMinutes(-5))
					{
						$candidatePaths[$item.FullName.ToLowerInvariant()] = $item.FullName
						if (-not $loggedCandidatePaths.ContainsKey($item.FullName.ToLowerInvariant()))
						{
							$loggedCandidatePaths[$item.FullName.ToLowerInvariant()] = $true
							Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher discovered ZIP candidate by polling. Path="{0}"; Bytes={1}; LastWriteUtc="{2:o}"; CandidateCount={3}' -f $item.FullName, [int64]$item.Length, $item.LastWriteTimeUtc, @($candidatePaths.Values).Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.PollCandidate'
						}
					}
				}
			}

			foreach ($candidatePath in @($candidatePaths.Values))
			{
				$key = $candidatePath.ToLowerInvariant()
				if ($rejectedPaths.ContainsKey($key)) { continue }
				if (-not (Test-GuiDeploymentMediaFileFinalized -Path $candidatePath -State $fileStates -AllowedExtensions @('.zip') -MinimumBytes 1024)) { continue }
				if (Test-GuiDeploymentMediaUupPackageArchive -Path $candidatePath)
				{
					Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher accepted finalized ZIP package. Path="{0}"; CandidateCount={1}; RejectedCount={2}' -f $candidatePath, @($candidatePaths.Values).Count, $rejectedPaths.Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.Accepted'
					return $candidatePath
				}
				$rejectedPaths[$key] = $true
				Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher rejected finalized ZIP because it did not contain a supported command script. Path="{0}"; RejectedCount={1}' -f $candidatePath, $rejectedPaths.Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.Rejected'
			}

			Start-Sleep -Seconds 2
		}

		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher timeout reached. TimeoutSeconds={0}; CandidateCount={1}; RejectedCount={2}; WatcherCount={3}' -f $TimeoutSeconds, @($candidatePaths.Values).Count, $rejectedPaths.Count, $watchers.Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.Timeout'
		throw ('Timed out waiting for a UUP dump download package ZIP after {0} second(s).' -f $TimeoutSeconds)
	}
	finally
	{
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package watcher disposing filesystem watchers. WatcherCount={0}; CandidateCount={1}; RejectedCount={2}' -f $watchers.Count, @($candidatePaths.Values).Count, $rejectedPaths.Count) -Source 'DeploymentMediaBuilder.Validation.UupPackageWatcher.Dispose'
		foreach ($watcher in $watchers)
		{
			try
			{
				$watcher.EnableRaisingEvents = $false
				$watcher.Dispose()
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.UupPackageWatcher.Dispose' -Severity Warning
				}
			}
		}
	}
}

function Expand-GuiDeploymentMediaUupPackageArchive
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$ArchivePath,
		[Parameter(Mandatory = $true)]
		[string]$WorkspaceRoot
	)

	if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf))
	{
		throw ('UUP package archive does not exist: {0}' -f $ArchivePath)
	}
	if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container))
	{
		[void][System.IO.Directory]::CreateDirectory($WorkspaceRoot)
	}

	$archiveName = [System.IO.Path]::GetFileNameWithoutExtension($ArchivePath)
	$safeName = [regex]::Replace($archiveName, '[^A-Za-z0-9._-]', '_')
	if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'UupPackage' }
	$extractRoot = Join-Path $WorkspaceRoot ('Package_{0:yyyyMMdd_HHmmss}_{1}' -f [DateTime]::UtcNow, $safeName)
	[void][System.IO.Directory]::CreateDirectory($extractRoot)
	Expand-Archive -LiteralPath $ArchivePath -DestinationPath $extractRoot -Force
	return $extractRoot
}

function Find-GuiDeploymentMediaUupCommandScript
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Root
	)

	if (-not (Test-Path -LiteralPath $Root -PathType Container))
	{
		throw ('UUP package extraction folder does not exist: {0}' -f $Root)
	}

	$scripts = @(Get-ChildItem -LiteralPath $Root -Filter '*.cmd' -File -Recurse -ErrorAction SilentlyContinue)
	foreach ($scriptName in @('uup_download_windows.cmd', 'convert-UUP.cmd'))
	{
		$match = @($scripts | Where-Object { $_.Name -ieq $scriptName } | Sort-Object @{ Expression = { $_.FullName.Length } }, FullName | Select-Object -First 1)
		if ($match.Count -gt 0)
		{
			return [string]$match[0].FullName
		}
	}

	throw ('The UUP package did not contain uup_download_windows.cmd or convert-UUP.cmd under {0}.' -f $Root)
}

function Start-GuiDeploymentMediaUupCommandProcess
{
	[CmdletBinding()]
	[OutputType([System.Diagnostics.Process])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$CommandScriptPath,
		[Parameter(Mandatory = $true)]
		[string]$WorkingDirectory,
		[AllowNull()]
		[hashtable]$CancellationState
	)

	Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'Run UUP command script'
	Set-GuiDeploymentMediaCurrentStage -CancellationState $CancellationState -Stage 'Run UUP command script'
	if (-not (Test-Path -LiteralPath $CommandScriptPath -PathType Leaf))
	{
		throw ('UUP command script does not exist: {0}' -f $CommandScriptPath)
	}
	if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container))
	{
		throw ('UUP command working directory does not exist: {0}' -f $WorkingDirectory)
	}

	$cmdPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
	$arguments = @('/d', '/c', 'call', $CommandScriptPath)
	$psi = [System.Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = $cmdPath
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $false
	$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
	$psi.WorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)
	$argumentListProperty = $psi.GetType().GetProperty('ArgumentList')
	if ($argumentListProperty)
	{
		foreach ($argument in $arguments)
		{
			[void]$psi.ArgumentList.Add([string]$argument)
		}
	}
	elseif (Get-Command -Name 'ConvertTo-BaselineProcessArgumentString' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$psi.Arguments = ConvertTo-BaselineProcessArgumentString -ArgumentList $arguments
	}
	else
	{
		$psi.Arguments = ('/d /c call "{0}"' -f $CommandScriptPath.Replace('"', ''))
	}

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $psi
	[void]$process.Start()
	return $process
}

function Wait-GuiDeploymentMediaUupCommandExit
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Diagnostics.Process]$Process,
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 3600)]
		[int]$TimeoutSeconds = 600
	)

	$deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
	while (-not $Process.WaitForExit(500))
	{
		if (Test-GuiDeploymentMediaCancellationRequested -CancellationState $CancellationState)
		{
			Stop-BaselineProcessTree -Process $Process -Source 'DeploymentMedia.UUP.Cancel'
			throw ([System.OperationCanceledException]::new('UUP command script cancelled. Deployment media operation cancelled by operator.'))
		}
		if ([DateTime]::UtcNow -ge $deadlineUtc)
		{
			Stop-BaselineProcessTree -Process $Process -Source 'DeploymentMedia.UUP.ExitTimeout'
			throw ([System.TimeoutException]::new(('UUP command script did not close within {0} second(s) after ISO detection.' -f $TimeoutSeconds)))
		}
	}
	[void]$Process.WaitForExit()
	$Process.Refresh()
	if ($Process.ExitCode -ne 0)
	{
		throw ('UUP command script failed with exit code {0}.' -f $Process.ExitCode)
	}
}

function Start-GuiDeploymentMediaUupLocalIsoWorkflow
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option,
		[string]$DestinationDirectory = '',
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 28800
	)

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}

	$plan = New-GuiDeploymentMediaUupAssemblyPlan -Option $Option
	$workspace = New-GuiDeploymentMediaUupWorkspaceTemplate -WorkspaceRoot $plan.WorkspaceRoot
	if ([string]::IsNullOrWhiteSpace($DestinationDirectory))
	{
		$DestinationDirectory = [string]$workspace.OutputDirectory
	}
	$outputDirectory = [string]$workspace.OutputDirectory
	if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container))
	{
		[void][System.IO.Directory]::CreateDirectory($outputDirectory)
	}

	$startedUtc = [DateTime]::UtcNow
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP local ISO workflow resolved. Product="{0}"; PageUrl="{1}"; WorkspaceRoot="{2}"; OutputDirectory="{3}"; DestinationDirectory="{4}"; TimeoutSeconds={5}' -f [string]$Option.ProductName, [string]$Option.PageUrl, [string]$plan.WorkspaceRoot, $outputDirectory, $DestinationDirectory, $TimeoutSeconds) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.Resolved'
	Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'Open UUP package generator'
	$CancellationState.Status = 'Opening the UUP dump package generator. Choose a build, select "Download and convert to ISO", and save the ZIP package.'
	Start-Process -FilePath ([string]$Option.PageUrl) -ErrorAction Stop | Out-Null
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package generator opened in default browser. Product="{0}"; PageUrl="{1}"' -f [string]$Option.ProductName, [string]$Option.PageUrl) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.BrowserOpened'

	$downloadTimeoutSeconds = [Math]::Min($TimeoutSeconds, 7200)
	$watchDirectories = @(Get-GuiDeploymentMediaUupWatchDirectories -WorkspaceRoot $plan.WorkspaceRoot -DestinationDirectory $DestinationDirectory)
	if ($watchDirectories.Count -eq 0)
	{
		throw 'No valid folders are available for UUP package monitoring.'
	}
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package archive watcher prepared. Product="{0}"; WatchDirectories="{1}"; DownloadTimeoutSeconds={2}' -f [string]$Option.ProductName, (@($watchDirectories) -join ';'), $downloadTimeoutSeconds) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.PackageWatcher'

	Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'UUP package download monitoring'
	$packageArchivePath = Wait-GuiDeploymentMediaUupPackageArchive -WatchDirectories $watchDirectories -StartedUtc $startedUtc -CancellationState $CancellationState -TimeoutSeconds $downloadTimeoutSeconds
	$packageArchiveHash = Get-GuiDeploymentMediaFileSha256 -Path $packageArchivePath
	$packageArchiveItem = Get-Item -LiteralPath $packageArchivePath -ErrorAction Stop
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package archive detected. Product="{0}"; Path="{1}"; Bytes={2}; Sha256="{3}"' -f [string]$Option.ProductName, $packageArchivePath, [int64]$packageArchiveItem.Length, $packageArchiveHash) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.PackageDetected'

	$CancellationState.Status = ('Extracting UUP package: {0}' -f $packageArchivePath)
	$extractRoot = Expand-GuiDeploymentMediaUupPackageArchive -ArchivePath $packageArchivePath -WorkspaceRoot $plan.WorkspaceRoot
	$commandScriptPath = Find-GuiDeploymentMediaUupCommandScript -Root $extractRoot
	$commandScriptHash = Get-GuiDeploymentMediaFileSha256 -Path $commandScriptPath
	$commandWorkingDirectory = Split-Path -Path $commandScriptPath -Parent
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP package extracted and command script resolved. Product="{0}"; ExtractRoot="{1}"; CommandScriptPath="{2}"; CommandScriptSha256="{3}"' -f [string]$Option.ProductName, $extractRoot, $commandScriptPath, $commandScriptHash) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.CommandResolved'

	$packageValidation = [pscustomobject]@{
		IsValid = $true
		Errors = @()
		Packages = @(
			[pscustomobject]@{
				Path = $packageArchivePath
				FileName = $packageArchiveItem.Name
				Extension = '.zip'
				Bytes = [int64]$packageArchiveItem.Length
				Sha256 = $packageArchiveHash
				Uri = [string]$Option.PageUrl
			}
		)
	}
	Save-GuiDeploymentMediaUupTransparencyManifest -Plan $plan -ManifestPath '' -PackageArchivePath $packageArchivePath -ExtractedPackageRoot $extractRoot -PackageValidation $packageValidation -ConvertScriptPath $commandScriptPath -ConvertScriptSha256 $commandScriptHash -OutputDirectory $outputDirectory -Stage 'PreAssembly'

	Assert-GuiDeploymentMediaNotCancelled -CancellationState $CancellationState -Stage 'Local UUP ISO assembly'
	$CancellationState.Status = ('Starting UUP command script in a visible console window: {0}' -f $commandScriptPath)
	$process = Start-GuiDeploymentMediaUupCommandProcess -CommandScriptPath $commandScriptPath -WorkingDirectory $commandWorkingDirectory -CancellationState $CancellationState
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP command process launched. Product="{0}"; ProcessId={1}; CommandScriptPath="{2}"; WorkingDirectory="{3}"' -f [string]$Option.ProductName, [int]$process.Id, $commandScriptPath, $commandWorkingDirectory) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.ProcessLaunched'

	$isoWatchDirectories = New-Object System.Collections.Generic.List[string]
	[void]$isoWatchDirectories.Add($outputDirectory)
	[void]$isoWatchDirectories.Add([string]$plan.WorkspaceRoot)
	[void]$isoWatchDirectories.Add($extractRoot)
	[void]$isoWatchDirectories.Add($commandWorkingDirectory)
	if (-not [string]::IsNullOrWhiteSpace($DestinationDirectory))
	{
		if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container))
		{
			[void][System.IO.Directory]::CreateDirectory($DestinationDirectory)
		}
		[void]$isoWatchDirectories.Add([System.IO.Path]::GetFullPath($DestinationDirectory))
	}
	$uniqueWatchDirectories = @($isoWatchDirectories.ToArray() | Select-Object -Unique)
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP ISO watcher prepared. Product="{0}"; WatchDirectories="{1}"' -f [string]$Option.ProductName, (@($uniqueWatchDirectories) -join ';')) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.IsoWatcher'

	$isoPath = $null
	try
	{
		$CancellationState.Status = 'Waiting for UUP command output ISO.'
		$remainingSeconds = [Math]::Max(300, [Math]::Min(28800, $TimeoutSeconds))
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP ISO monitoring started. Product="{0}"; RemainingSeconds={1}; ProcessId={2}' -f [string]$Option.ProductName, $remainingSeconds, [int]$process.Id) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.IsoMonitoringStarted'
		$isoPath = Wait-GuiDeploymentMediaMctIsoFile -WatchDirectories $uniqueWatchDirectories -StartedUtc $startedUtc -CancellationState $CancellationState -Process $process -TimeoutSeconds $remainingSeconds -StageName 'Local UUP ISO monitoring' -StatusMessage 'Waiting for the UUP command script to finish writing an ISO file.' -ProcessExitMessage 'The UUP command window closed before Baseline detected a completed ISO in the watched folders.' -TimeoutMessage ('Timed out waiting for local UUP assembly to create an ISO after {0} second(s).' -f $remainingSeconds) -ProcessExitGraceSeconds 300 -IsoFinalizationGraceSeconds 300 -IncludeSubdirectories
		$CancellationState.Status = 'ISO detected. Waiting for the UUP command window to close.'
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP ISO detected. Product="{0}"; IsoPath="{1}"; WaitingForProcessExit=True' -f [string]$Option.ProductName, $isoPath) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.IsoDetected'
		Wait-GuiDeploymentMediaUupCommandExit -Process $process -CancellationState $CancellationState -TimeoutSeconds 600
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP command process exited after ISO detection. Product="{0}"; ProcessId={1}' -f [string]$Option.ProductName, [int]$process.Id) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.ProcessExited'
	}
	catch
	{
		Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP local ISO workflow failed during assembly monitoring. Product="{0}"; ExceptionType="{1}"; Message="{2}"; ProcessStarted={3}' -f [string]$Option.ProductName, $_.Exception.GetType().FullName, $_.Exception.Message, [bool]$process) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.AssemblyFailed'
		if ($process)
		{
			try
			{
				$process.Refresh()
				if (-not $process.HasExited)
				{
					Stop-BaselineProcessTree -Process $process -Source 'DeploymentMedia.UUP.WorkflowFailure'
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.UupProcess.StopAfterFailure' -Severity Warning
				}
			}
		}
		throw
	}
	finally
	{
		if ($process) { $process.Dispose() }
	}

	$CancellationState.Status = ('Validating ISO assembled from local UUP packages: {0}' -f $isoPath)
	$isoInfo = Get-GuiDeploymentMediaIsoImageInfo -SourceIso $isoPath -CancellationState $CancellationState -TimeoutSeconds 900
	$isoHash = Get-GuiDeploymentMediaFileSha256 -Path $isoPath
	$reportPath = Save-GuiDeploymentMediaUupTransparencyManifest -Plan $plan -ManifestPath '' -PackageArchivePath $packageArchivePath -ExtractedPackageRoot $extractRoot -PackageValidation $packageValidation -ConvertScriptPath $commandScriptPath -ConvertScriptSha256 $commandScriptHash -OutputDirectory $outputDirectory -IsoPath $isoPath -IsoSha256 $isoHash -Stage 'Completed'
	$CancellationState.Status = 'Imported ISO assembled locally from official Microsoft UUP packages.'
	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('UUP local ISO workflow validated output. Product="{0}"; IsoPath="{1}"; IsoSha256="{2}"; EditionCount={3}; ReportPath="{4}"' -f [string]$Option.ProductName, $isoPath, $isoHash, @($isoInfo.Editions).Count, $reportPath) -Source 'DeploymentMediaBuilder.Validation.UupWorkflow.Validated'

	return [pscustomobject]@{
		Path = $isoPath
		FileName = [System.IO.Path]::GetFileName($isoPath)
		Bytes = (Get-Item -LiteralPath $isoPath).Length
		Sha256 = $isoHash
		ProductName = [string]$Option.ProductName
		Architecture = [string]$Option.Architecture
		Language = [string]$Option.Language
		PageUrl = [string]$Option.PageUrl
		AcquisitionMode = 'UUPLocal'
		ComplianceLabel = [string]$plan.ComplianceLabel
		OutputLabel = [string]$plan.OutputLabel
		WorkspaceRoot = [string]$plan.WorkspaceRoot
		ManifestPath = ''
		PackageArchivePath = $packageArchivePath
		PackageArchiveSha256 = $packageArchiveHash
		ExtractedPackageRoot = $extractRoot
		PackageCount = @($packageValidation.Packages).Count
		ConvertScriptPath = $commandScriptPath
		ConvertScriptSha256 = $commandScriptHash
		CommandScriptPath = $commandScriptPath
		CommandScriptSha256 = $commandScriptHash
		TransparencyManifestPath = $reportPath
		WatchedDirectories = @($uniqueWatchDirectories)
		EditionCount = @($isoInfo.Editions).Count
		StartedUtc = $startedUtc
		CompletedUtc = [DateTime]::UtcNow
	}
}

function Get-GuiDeploymentMediaUupWorkflowLayout
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option
	)

	return [pscustomobject]@{
		AcquisitionTier = 2
		AcquisitionMode = 'UUPLocal'
		ProductName = [string]$Option.ProductName
		Architecture = [string]$Option.Architecture
		ComplianceLabel = 'Generated installation media using Microsoft UUP files.'
		DiscoveryPolicy = @(
			'Open the UUP dump package generator in the default browser.',
			'Wait for a downloaded ZIP package containing uup_download_windows.cmd or convert-UUP.cmd.',
			'Run the reviewed command script locally and persist an auditable transparency manifest.'
		)
		PackageTypes = @('.cab', '.esd', '.psf')
		RequiredTools = @('dism.exe', 'Microsoft.OSCDIMG')
		OptionalTools = @('wimlib-imagex.exe')
		AssemblyStages = @(
			'Open the UUP package generator website.',
			'Detect and extract the downloaded UUP ZIP package.',
			'Run uup_download_windows.cmd or convert-UUP.cmd in a visible console window.',
			'Detect and validate the generated ISO.',
			'Write transparency manifest and build report.'
		)
		OutputLabel = 'ISO assembled locally from official Microsoft UUP packages.'
	}
}

function Get-GuiDeploymentMediaUupDefaultDirectory
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\UUP')
}

function Resolve-GuiDeploymentMediaUupWorkspacePath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$WorkspaceRoot,
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if ([string]::IsNullOrWhiteSpace($WorkspaceRoot))
	{
		throw 'UUP workspace root is required.'
	}
	if ([string]::IsNullOrWhiteSpace($Path))
	{
		throw 'UUP workspace path is required.'
	}
	if (-not [System.IO.Path]::IsPathRooted($WorkspaceRoot))
	{
		throw 'UUP workspace root must be an absolute path.'
	}

	$workspaceFull = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
	$resolved = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) } else { [System.IO.Path]::GetFullPath((Join-Path $workspaceFull $Path)) }
	$workspacePrefix = $workspaceFull + '\'
	if ($resolved.TrimEnd('\').Equals($workspaceFull, [System.StringComparison]::OrdinalIgnoreCase))
	{
		return $resolved
	}
	if (-not $resolved.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase))
	{
		throw ('UUP workspace path must stay under {0}: {1}' -f $workspaceFull, $resolved)
	}

	return $resolved
}

function New-GuiDeploymentMediaUupWorkspaceTemplate
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[string]$WorkspaceRoot = ''
	)

	if ([string]::IsNullOrWhiteSpace($WorkspaceRoot))
	{
		$WorkspaceRoot = Get-GuiDeploymentMediaUupDefaultDirectory
	}
	if (-not [System.IO.Path]::IsPathRooted($WorkspaceRoot))
	{
		throw 'UUP workspace root must be an absolute path.'
	}

	$workspaceRootFull = [System.IO.Path]::GetFullPath($WorkspaceRoot)
	$packagesDirectory = Join-Path $workspaceRootFull 'Packages'
	$outputDirectory = Join-Path $workspaceRootFull 'Output'
	foreach ($directory in @($workspaceRootFull, $packagesDirectory, $outputDirectory))
	{
		if (-not (Test-Path -LiteralPath $directory -PathType Container))
		{
			[void][System.IO.Directory]::CreateDirectory($directory)
		}
	}

	$manifestPath = Join-Path $workspaceRootFull 'uup-packages.json'
	$exampleManifestPath = Join-Path $workspaceRootFull 'uup-packages.example.json'
	if (-not (Test-Path -LiteralPath $exampleManifestPath -PathType Leaf))
	{
		$template = [ordered]@{
			Schema = 'Baseline.UUP.LocalPackageManifest.v1'
			OutputDirectory = 'Output'
			ConvertScript = 'convert-UUP.cmd'
			ConvertScriptSha256 = ''
			ConvertArguments = @()
			Packages = @(
				[ordered]@{
					FileName = 'replace-with-downloaded-uup-package.cab'
					Path = 'Packages\replace-with-downloaded-uup-package.cab'
					Sha256 = ''
					Uri = 'https://download.windowsupdate.com/example/replace-with-downloaded-uup-package.cab'
				}
			)
		}
		Set-Content -LiteralPath $exampleManifestPath -Value ($template | ConvertTo-Json -Depth 8) -Encoding UTF8
	}

	return [pscustomobject]@{
		WorkspaceRoot = $workspaceRootFull
		PackagesDirectory = $packagesDirectory
		OutputDirectory = $outputDirectory
		ManifestPath = $manifestPath
		ExampleManifestPath = $exampleManifestPath
	}
}

function Import-GuiDeploymentMediaUupPackageManifest
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		throw ('UUP package manifest does not exist: {0}' -f $Path)
	}

	try
	{
		$raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
		$manifest = $raw | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		throw ('Failed to read UUP package manifest: {0}' -f $_.Exception.Message)
	}
	if (-not $manifest -or -not $manifest.PSObject.Properties['Packages'])
	{
		throw 'UUP package manifest must define a Packages array.'
	}
	if (@($manifest.Packages).Count -lt 1)
	{
		throw 'UUP package manifest must include at least one package.'
	}

	return $manifest
}

function Test-GuiDeploymentMediaUupPackageManifest
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Manifest,
		[Parameter(Mandatory = $true)]
		[string]$WorkspaceRoot
	)

	$errors = [System.Collections.Generic.List[string]]::new()
	$packages = [System.Collections.Generic.List[object]]::new()
	$allowedExtensions = @('.cab', '.esd', '.psf')

	foreach ($package in @($Manifest.Packages))
	{
		$declaredPath = ''
		if ($package.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace([string]$package.Path))
		{
			$declaredPath = [string]$package.Path
		}
		elseif ($package.PSObject.Properties['FileName'] -and -not [string]::IsNullOrWhiteSpace([string]$package.FileName))
		{
			$declaredPath = Join-Path 'Packages' ([string]$package.FileName)
		}
		else
		{
			[void]$errors.Add('Each UUP package entry must include Path or FileName.')
			continue
		}

		$packagePath = ''
		try
		{
			$packagePath = Resolve-GuiDeploymentMediaUupWorkspacePath -WorkspaceRoot $WorkspaceRoot -Path $declaredPath
		}
		catch
		{
			LogDebug ('UUP manifest workspace path resolution failed. WorkspaceRoot="{0}"; DeclaredPath="{1}"; ExceptionType="{2}"; Message="{3}"' -f $WorkspaceRoot, $declaredPath, $_.Exception.GetType().FullName, $_.Exception.Message)
			[void]$errors.Add($_.Exception.Message)
			continue
		}

		$extension = [System.IO.Path]::GetExtension($packagePath).ToLowerInvariant()
		if ($extension -notin $allowedExtensions)
		{
			[void]$errors.Add(('Unsupported UUP package extension for {0}. Allowed extensions: {1}' -f $packagePath, ($allowedExtensions -join ', ')))
			continue
		}

		$uri = ''
		if ($package.PSObject.Properties['Uri'])
		{
			$uri = [string]$package.Uri
			if (-not [string]::IsNullOrWhiteSpace($uri) -and -not (Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri $uri))
			{
				[void]$errors.Add(('UUP package URI must be a trusted Microsoft HTTPS URL: {0}' -f $uri))
			}
		}

		if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf))
		{
			[void]$errors.Add(('UUP package file does not exist: {0}' -f $packagePath))
			continue
		}

		$sha256 = Get-GuiDeploymentMediaFileSha256 -Path $packagePath
		$expectedSha256 = ''
		if ($package.PSObject.Properties['Sha256'])
		{
			$expectedSha256 = ([string]$package.Sha256).Trim().ToUpperInvariant()
		}
		if ([string]::IsNullOrWhiteSpace($expectedSha256))
		{
			[void]$errors.Add(('UUP package manifest must include Sha256 for {0}.' -f $packagePath))
		}
		elseif ($expectedSha256 -notmatch '^[A-F0-9]{64}$')
		{
			[void]$errors.Add(('UUP package Sha256 must be a 64-character hash for {0}.' -f $packagePath))
		}
		elseif ($expectedSha256 -ne $sha256)
		{
			[void]$errors.Add(('UUP package hash mismatch for {0}. Expected {1}; actual {2}.' -f $packagePath, $expectedSha256, $sha256))
		}

		$item = Get-Item -LiteralPath $packagePath -ErrorAction Stop
		[void]$packages.Add([pscustomobject]@{
			Path = $packagePath
			FileName = $item.Name
			Extension = $extension
			Bytes = [int64]$item.Length
			Sha256 = $sha256
			Uri = $uri
		})
	}

	return [pscustomobject]@{
		IsValid = ($errors.Count -eq 0)
		Errors = @($errors.ToArray())
		Packages = @($packages.ToArray())
	}
}

function Save-GuiDeploymentMediaUupTransparencyManifest
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan,
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$ManifestPath,
		[AllowEmptyString()]
		[string]$PackageArchivePath = '',
		[AllowEmptyString()]
		[string]$ExtractedPackageRoot = '',
		[Parameter(Mandatory = $true)]
		[object]$PackageValidation,
		[Parameter(Mandatory = $true)]
		[string]$ConvertScriptPath,
		[Parameter(Mandatory = $true)]
		[string]$ConvertScriptSha256,
		[Parameter(Mandatory = $true)]
		[string]$OutputDirectory,
		[string]$IsoPath = '',
		[string]$IsoSha256 = '',
		[ValidateSet('PreAssembly', 'Completed')]
		[string]$Stage = 'PreAssembly'
	)

	$reportDirectory = Join-Path ([string]$Plan.WorkspaceRoot) 'Reports'
	if (-not (Test-Path -LiteralPath $reportDirectory -PathType Container))
	{
		[void][System.IO.Directory]::CreateDirectory($reportDirectory)
	}
	$reportPath = Join-Path $reportDirectory ('uup-assembly-{0:yyyyMMdd-HHmmss}-{1}.json' -f [DateTime]::UtcNow, $Stage.ToLowerInvariant())
	$payload = [ordered]@{
		Schema = 'Baseline.UUP.TransparencyManifest.v1'
		Stage = $Stage
		ProductName = [string]$Plan.ProductName
		Architecture = [string]$Plan.Architecture
		ComplianceLabel = [string]$Plan.ComplianceLabel
		OutputLabel = [string]$Plan.OutputLabel
		WorkspaceRoot = [string]$Plan.WorkspaceRoot
		ManifestPath = $ManifestPath
		PackageArchivePath = $PackageArchivePath
		ExtractedPackageRoot = $ExtractedPackageRoot
		OutputDirectory = $OutputDirectory
		ConvertScriptPath = $ConvertScriptPath
		ConvertScriptSha256 = $ConvertScriptSha256
		PackageCount = @($PackageValidation.Packages).Count
		Packages = @($PackageValidation.Packages)
		IsoPath = $IsoPath
		IsoSha256 = $IsoSha256
		WrittenUtc = [DateTime]::UtcNow
	}
	Set-Content -LiteralPath $reportPath -Value ($payload | ConvertTo-Json -Depth 8) -Encoding UTF8
	return $reportPath
}

function Test-GuiDeploymentMediaUupToolchain
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param ()

	$dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
	$oscdimgPath = ''
	if (Get-Command -Name 'Resolve-GuiDeploymentMediaOscdimgPath' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try
		{
			$oscdimgPath = [string](Resolve-GuiDeploymentMediaOscdimgPath)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.Validation.TestUupToolchain.ResolveOscdimg' -Severity Debug
			}
			$oscdimgPath = ''
		}
	}
	if ([string]::IsNullOrWhiteSpace($oscdimgPath))
	{
		$oscdimgCommand = Get-Command -Name 'oscdimg.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($oscdimgCommand -and -not [string]::IsNullOrWhiteSpace([string]$oscdimgCommand.Source))
		{
			$oscdimgPath = [string]$oscdimgCommand.Source
		}
	}
	$wimlibCommand = Get-Command -Name 'wimlib-imagex.exe' -CommandType Application -ErrorAction SilentlyContinue

	return [pscustomobject]@{
		DismPath = $dismPath
		DismAvailable = (Test-Path -LiteralPath $dismPath -PathType Leaf)
		OscdimgPath = $oscdimgPath
		OscdimgAvailable = (-not [string]::IsNullOrWhiteSpace($oscdimgPath))
		WimlibPath = $(if ($wimlibCommand) { [string]$wimlibCommand.Source } else { '' })
		WimlibAvailable = [bool]$wimlibCommand
	}
}

function New-GuiDeploymentMediaUupAssemblyPlan
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option
	)

	$layout = Get-GuiDeploymentMediaUupWorkflowLayout -Option $Option
	$toolchain = Test-GuiDeploymentMediaUupToolchain
	$workspaceRoot = Get-GuiDeploymentMediaUupDefaultDirectory
	if ($Option.PSObject.Properties['WorkspaceRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$Option.WorkspaceRoot))
	{
		$workspaceRoot = [string]$Option.WorkspaceRoot
	}
	$workspaceRoot = [System.IO.Path]::GetFullPath($workspaceRoot)

	return [pscustomobject]@{
		IsEnabled = $true
		AcquisitionTier = [int]$layout.AcquisitionTier
		AcquisitionMode = [string]$layout.AcquisitionMode
		ProductName = [string]$layout.ProductName
		Architecture = [string]$layout.Architecture
		ComplianceLabel = [string]$layout.ComplianceLabel
		OutputLabel = [string]$layout.OutputLabel
		WorkspaceRoot = $workspaceRoot
		ManifestPath = Join-Path $workspaceRoot 'uup-packages.json'
		ExampleManifestPath = Join-Path $workspaceRoot 'uup-packages.example.json'
		ConvertScriptPath = Join-Path $workspaceRoot 'convert-UUP.cmd'
		OutputDirectory = Join-Path $workspaceRoot 'Output'
		SourcePageUrl = [string]$Option.PageUrl
		CommandScriptNames = @('uup_download_windows.cmd', 'convert-UUP.cmd')
		DiscoveryPolicy = @($layout.DiscoveryPolicy)
		PackageTypes = @($layout.PackageTypes)
		AssemblyStages = @($layout.AssemblyStages)
		Toolchain = $toolchain
	}
}

function Save-GuiDeploymentMediaMicrosoftLatestIso
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Option,
		[string]$DestinationDirectory = '',
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 28800
	)

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}

	Write-GuiDeploymentMediaBuilderValidationDebugLog -Message ('Microsoft ISO acquisition dispatch resolved. Product="{0}"; AcquisitionMode="{1}"; DestinationDirectory="{2}"; TimeoutSeconds={3}' -f [string]$Option.ProductName, [string]$Option.AcquisitionMode, $DestinationDirectory, $TimeoutSeconds) -Source 'DeploymentMediaBuilder.Validation.IsoAcquisition.Dispatch'
	switch ([string]$Option.AcquisitionMode)
	{
		'MediaCreationTool' { return Start-GuiDeploymentMediaMicrosoftMediaCreationToolIsoWorkflow -Option $Option -DestinationDirectory $DestinationDirectory -CancellationState $CancellationState -TimeoutSeconds $TimeoutSeconds }
		'UUPLocal' { return Start-GuiDeploymentMediaUupLocalIsoWorkflow -Option $Option -DestinationDirectory $DestinationDirectory -CancellationState $CancellationState -TimeoutSeconds $TimeoutSeconds }
		default { throw ('Unsupported ISO acquisition mode: {0}' -f $Option.AcquisitionMode) }
	}
}

function Convert-GuiDeploymentMediaBuildPlanToText
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan
	)

	$lines = [System.Collections.Generic.List[string]]::new()
	[void]$lines.Add('Deployment Media Builder plan')
	[void]$lines.Add(('Source ISO: {0}' -f $Plan.SourceIso))
	[void]$lines.Add(('Working directory: {0}' -f $Plan.WorkingDirectory))
	[void]$lines.Add(('Output: {0}' -f $Plan.OutputMode))
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.UsbTargetRoot)) { [void]$lines.Add(('USB target: {0}' -f $Plan.UsbTargetRoot)) }
	[void]$lines.Add(('Selected edition index: {0}' -f $Plan.EditionIndex))
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.EditionName)) { [void]$lines.Add(('Selected edition: {0}' -f $Plan.EditionName)) }
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.AutounattendPath)) { [void]$lines.Add(('Autounattend: {0}' -f $Plan.AutounattendPath)) }
	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.DriverSource)) { [void]$lines.Add(('Drivers: {0}' -f $Plan.DriverSource)) }
	if ($Plan.IsoImageInfo -and $Plan.IsoImageInfo.PSObject.Properties['ImagePath'])
	{
		[void]$lines.Add(('Detected image: {0} ({1})' -f $Plan.IsoImageInfo.ImagePath, $Plan.IsoImageInfo.ImageKind))
		[void]$lines.Add('Available editions:')
		foreach ($edition in @($Plan.IsoImageInfo.Editions))
		{
			[void]$lines.Add((' - {0}: {1}' -f $edition.Index, $edition.Name))
		}
	}
	[void]$lines.Add(('Boot driver injection: {0}' -f [bool]$Plan.InjectBootDrivers))
	[void]$lines.Add(('Baseline setup customizations: {0}' -f [bool]$Plan.IncludeBaselineTweaks))
	[void]$lines.Add('')

	if (-not [bool]$Plan.IsValid)
	{
		[void]$lines.Add('Blocking validation errors:')
		foreach ($errorText in @($Plan.Errors)) { [void]$lines.Add((' - {0}' -f $errorText)) }
		[void]$lines.Add('')
	}

	[void]$lines.Add('Safety contract:')
	foreach ($item in @($Plan.Safety)) { [void]$lines.Add((' - {0}' -f $item)) }
	[void]$lines.Add('')
	[void]$lines.Add('Build steps:')
	foreach ($step in @($Plan.Steps)) { [void]$lines.Add((' - {0}' -f $step)) }

	return ($lines.ToArray() -join [Environment]::NewLine)
}

