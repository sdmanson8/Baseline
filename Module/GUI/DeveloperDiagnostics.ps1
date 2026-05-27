# Developer diagnostics menu and external-process runner for validation tools.

$Script:GuiDeveloperDiagnosticsLauncherOpen = $false
$Script:GuiDeveloperDiagnosticsPesterInstallOpen = $false
$Script:GuiDeveloperDiagnosticsPesterStepPrefix = 'BASELINE_DIAGNOSTICS_STEP:'
$Script:GuiDeveloperDiagnosticsPesterMinimumSupportedVersion = [version]'5.5.0'
$Script:GuiDeveloperDiagnosticsPesterRecommendedMajorVersion = 5
$Script:GuiDeveloperDiagnosticsPesterStatusCacheDays = 7
$Script:GuiDeveloperDiagnosticsPesterStatusCheckTimeoutSeconds = 60
$Script:GuiDeveloperDiagnosticsPesterInstallNoOutputWarningSeconds = 60

function Add-GuiDeveloperDiagnosticsCandidateRoot
{
    param(
        [System.Collections.Generic.List[string]]$Roots,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path))
    {
        return
    }

    try
    {
        $resolvedPath = [System.IO.Path]::GetFullPath([string]$Path)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Add-GuiDeveloperDiagnosticsCandidateRoot:catch28' -Severity Debug }

        return
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container))
    {
        return
    }

    foreach ($root in $Roots)
    {
        if ([string]::Equals([string]$root, $resolvedPath, [System.StringComparison]::OrdinalIgnoreCase))
        {
            return
        }
    }

    [void]$Roots.Add($resolvedPath)
}

function Test-GuiDeveloperDiagnosticsPayloadRoot
{
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path))
    {
        return $false
    }

    return (
        (Test-Path -LiteralPath (Join-Path $Path 'Tools') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'Tests') -PathType Container)
    )
}

function Get-GuiDeveloperDiagnosticsCandidateRoots
{
    $roots = New-Object 'System.Collections.Generic.List[string]'

    if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
    {
        Add-GuiDeveloperDiagnosticsCandidateRoot -Roots $roots -Path (Split-Path -Path $Script:GuiModuleBasePath -Parent)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot))
    {
        Add-GuiDeveloperDiagnosticsCandidateRoot -Roots $roots -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent)
    }

    $launcherPath = [string]$env:BASELINE_LAUNCHER_PATH
    if (-not [string]::IsNullOrWhiteSpace($launcherPath) -and [System.IO.Path]::IsPathRooted($launcherPath))
    {
        Add-GuiDeveloperDiagnosticsCandidateRoot -Roots $roots -Path (Split-Path -Path $launcherPath -Parent)
    }

    try
    {
        Add-GuiDeveloperDiagnosticsCandidateRoot -Roots $roots -Path ([System.AppDomain]::CurrentDomain.BaseDirectory)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Get-GuiDeveloperDiagnosticsCandidateRoots:catch88' -Severity Debug }

        $null = $_
    }

    try
    {
        Add-GuiDeveloperDiagnosticsCandidateRoot -Roots $roots -Path ((Get-Location).ProviderPath)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Get-GuiDeveloperDiagnosticsCandidateRoots:catch97' -Severity Debug }

        $null = $_
    }

    return @($roots)
}

function Get-GuiDeveloperDiagnosticsRepoRoot
{
    $candidateRoots = @(Get-GuiDeveloperDiagnosticsCandidateRoots)
    foreach ($root in $candidateRoots)
    {
        if (Test-GuiDeveloperDiagnosticsPayloadRoot -Path $root)
        {
            return $root
        }
    }

    if ($candidateRoots.Count -gt 0)
    {
        return [string]$candidateRoots[0]
    }

    return (Get-Location).ProviderPath
}

function Get-GuiDeveloperDiagnosticsArtifactsDirectory
{
    return (Join-Path (Get-GuiDeveloperDiagnosticsRepoRoot) '.artifacts\gui-tests')
}

function Get-GuiDeveloperDiagnosticsTempDirectory
{
    $tempRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'Baseline', 'DeveloperDiagnostics')
    if (-not (Test-Path -LiteralPath $tempRoot -PathType Container))
    {
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    }

    return $tempRoot
}

function Get-GuiDeveloperDiagnosticsDataDirectory
{
    $dataRoot = [System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData), 'Baseline', 'DeveloperDiagnostics')
    if (-not (Test-Path -LiteralPath $dataRoot -PathType Container))
    {
        New-Item -Path $dataRoot -ItemType Directory -Force | Out-Null
    }

    return $dataRoot
}

function Get-GuiDeveloperDiagnosticsPesterStatusCachePath
{
    return (Join-Path (Get-GuiDeveloperDiagnosticsDataDirectory) 'PesterStatus.json')
}

function Get-GuiDeveloperDiagnosticsPowerShellPath
{
    $systemPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $systemPowerShell -PathType Leaf)
    {
        return $systemPowerShell
    }

    $command = Get-Command -Name 'powershell.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source))
    {
        return [string]$command.Source
    }

    return $null
}

function ConvertTo-GuiDeveloperDiagnosticsVersion
{
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    try
    {
        return ([version]([string]$Value))
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.ConvertTo-GuiDeveloperDiagnosticsVersion:catch182' -Severity Debug }

        return $null
    }
}

function Get-GuiDeveloperDiagnosticsInstalledPesterModule
{
    Get-Module -ListAvailable -Name Pester -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Get-GuiDeveloperDiagnosticsInstalledPesterStatus
{
    $pesterModule = Get-GuiDeveloperDiagnosticsInstalledPesterModule
    $installedVersion = if ($pesterModule) { [string]$pesterModule.Version } else { '' }
    $installedVersionObject = ConvertTo-GuiDeveloperDiagnosticsVersion -Value $installedVersion
    $installedSupported = (
        $null -ne $installedVersionObject -and
        $installedVersionObject.Major -eq $Script:GuiDeveloperDiagnosticsPesterRecommendedMajorVersion -and
        $installedVersionObject -ge $Script:GuiDeveloperDiagnosticsPesterMinimumSupportedVersion
    )

    return [pscustomobject]@{
        InstalledVersion = $installedVersion
        InstalledSupported = [bool]$installedSupported
        MinimumSupportedVersion = [string]$Script:GuiDeveloperDiagnosticsPesterMinimumSupportedVersion
        RecommendedMajorVersion = [int]$Script:GuiDeveloperDiagnosticsPesterRecommendedMajorVersion
    }
}

function Test-GuiDeveloperDiagnosticsPesterAvailable
{
    try
    {
        $pesterStatus = Get-GuiDeveloperDiagnosticsInstalledPesterStatus
        return [bool]$pesterStatus.InstalledSupported
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Test-GuiDeveloperDiagnosticsPesterAvailable:catch221' -Severity Debug }

        return $false
    }
}

function Test-GuiDeveloperDiagnosticsPesterMissing
{
    param([object]$Availability)

    if ($null -eq $Availability -or $null -eq $Availability.Reasons)
    {
        return $false
    }

    foreach ($reason in @($Availability.Reasons))
    {
        if ([string]::Equals([string]$reason, 'Supported Pester 5.x 5.5.0 or newer is not available.', [System.StringComparison]::Ordinal))
        {
            return $true
        }
    }

    return $false
}

function Get-GuiDeveloperDiagnosticsPesterInstallScript
{
    return @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'
$PSDefaultParameterValues['*:Confirm'] = $false
trap
{
    [Console]::Error.WriteLine((($_ | Out-String).Trim()))
    try { [Console]::Error.Flush() } catch { $null = $_ }
    [Environment]::Exit(1)
}

function Write-BaselineDiagnosticsStep
{
    param([string]$Step)
    Write-Output ("BASELINE_DIAGNOSTICS_STEP:{0}" -f $Step)
}

function Stop-BaselineDiagnosticsInstall
{
    param(
        [string]$Message,
        [int]$ExitCode
    )

    [Console]::Error.WriteLine($Message)
    try { [Console]::Error.Flush() } catch { $null = $_ }
    [Environment]::Exit([int]$ExitCode)
}

function Get-BaselineDiagnosticsCurrentUserModuleRoot
{
    $documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if ([string]::IsNullOrWhiteSpace([string]$documentsPath))
    {
        $documentsPath = [System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile), 'Documents')
    }

    return [System.IO.Path]::Combine($documentsPath, 'WindowsPowerShell', 'Modules')
}

function Get-BaselineDiagnosticsMissingPowerShellGetCommand
{
    param([string[]]$CommandNames)

    $missing = @()
    foreach ($commandName in $CommandNames)
    {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue))
        {
            $missing += $commandName
        }
    }

    return @($missing)
}

function ConvertTo-BaselineDiagnosticsVersion
{
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $versionText = [string]$Value
    if ([string]::IsNullOrWhiteSpace($versionText)) { return $null }
    if ($versionText -match '-')
    {
        return $null
    }

    $parsedVersion = [version]'0.0'
    if ([version]::TryParse($versionText, [ref]$parsedVersion))
    {
        return $parsedVersion
    }

    return $null
}

function Invoke-BaselineDiagnosticsWebText
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [int]$TimeoutMilliseconds = 60000
    )

    $request = [System.Net.WebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutMilliseconds
    $request.ReadWriteTimeout = $TimeoutMilliseconds
    $request.UserAgent = 'Baseline Developer Diagnostics'
    $response = $request.GetResponse()
    try
    {
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8, $true)
        try
        {
            return $reader.ReadToEnd()
        }
        finally
        {
            $reader.Dispose()
            if ($responseStream) { $responseStream.Dispose() }
        }
    }
    finally
    {
        if ($response) { $response.Close() }
    }
}

function Get-BaselineDiagnosticsGalleryPackageVersions
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $versions = New-Object 'System.Collections.Generic.List[string]'
    $escapedPackageName = [Uri]::EscapeDataString(("'{0}'" -f $Name.Replace("'", "''")))
    $uri = 'https://www.powershellgallery.com/api/v2/FindPackagesById()?id={0}' -f $escapedPackageName
    while (-not [string]::IsNullOrWhiteSpace([string]$uri))
    {
        $xmlText = Invoke-BaselineDiagnosticsWebText -Uri $uri
        [xml]$feed = $xmlText
        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($feed.NameTable)
        $namespaceManager.AddNamespace('atom', 'http://www.w3.org/2005/Atom')
        $namespaceManager.AddNamespace('m', 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')
        $namespaceManager.AddNamespace('d', 'http://schemas.microsoft.com/ado/2007/08/dataservices')

        $versionNodes = $feed.SelectNodes('//atom:entry/atom:content/m:properties/d:Version', $namespaceManager)
        foreach ($versionNode in @($versionNodes))
        {
            if (-not [string]::IsNullOrWhiteSpace([string]$versionNode.InnerText))
            {
                [void]$versions.Add([string]$versionNode.InnerText)
            }
        }
        if (@($versionNodes).Count -eq 0)
        {
            foreach ($match in [regex]::Matches($xmlText, '<d:Version[^>]*>([^<]+)</d:Version>'))
            {
                if ($match.Groups.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace([string]$match.Groups[1].Value))
                {
                    [void]$versions.Add([string]$match.Groups[1].Value)
                }
            }
        }

        $nextLink = $feed.SelectSingleNode('//atom:link[@rel="next"]', $namespaceManager)
        if ($nextLink -and -not [string]::IsNullOrWhiteSpace([string]$nextLink.href))
        {
            $uri = [string]$nextLink.href
        }
        else
        {
            $uri = $null
        }
    }

    return @($versions.ToArray())
}

function Select-BaselineDiagnosticsStablePackageVersion
{
    param(
        [string[]]$Versions,
        [int]$Major = 5
    )

    $stableVersions = @()
    foreach ($version in @($Versions))
    {
        $packageVersion = ConvertTo-BaselineDiagnosticsVersion -Value $version
        if ($packageVersion -and $packageVersion.Major -eq $Major)
        {
            $stableVersions += $packageVersion
        }
    }

    $selectedVersion = $stableVersions |
        Sort-Object -Descending |
        Select-Object -First 1
    if ($selectedVersion)
    {
        return $selectedVersion
    }

    return $null
}

function Select-BaselineDiagnosticsStablePesterPackage
{
    param(
        [object[]]$Packages,
        [int]$Major = 5
    )

    $stablePackages = @()
    foreach ($package in @($Packages))
    {
        if (-not $package) { continue }
        $packageVersion = ConvertTo-BaselineDiagnosticsVersion -Value $package.Version
        if ($packageVersion -and $packageVersion.Major -eq $Major)
        {
            $stablePackages += [pscustomobject]@{
                Package = $package
                Version = $packageVersion
            }
        }
    }

    $selectedPackage = $stablePackages |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($selectedPackage)
    {
        return $selectedPackage.Package
    }

    return $null
}

function Test-BaselineDiagnosticsServerOperatingSystem
{
    try
    {
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return ($operatingSystem -and [int]$operatingSystem.ProductType -ne 1)
    }
    catch
    {
        return $false
    }
}

function Install-BaselineDiagnosticsGalleryModulePackage
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $moduleRoot = Get-BaselineDiagnosticsCurrentUserModuleRoot
    $moduleDirectory = Join-Path (Join-Path $moduleRoot $Name) $Version
    $moduleManifest = Join-Path $moduleDirectory ('{0}.psd1' -f $Name)
    if (Test-Path -LiteralPath $moduleManifest -PathType Leaf)
    {
        [Console]::Out.WriteLine(("{0} {1} is already installed for the current user." -f $Name, $Version))
        return $moduleManifest
    }

    [Console]::Out.WriteLine(("Installing {0} {1} from PowerShell Gallery for the current user..." -f $Name, $Version))
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselinePowerShellGet_{0}_{1}' -f $Name, [guid]::NewGuid().ToString('N'))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try
    {
        $packagePath = Join-Path $tempRoot ('{0}.{1}.nupkg' -f $Name, $Version)
        $extractPath = Join-Path $tempRoot 'extract'
        New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

        $packageUri = 'https://www.powershellgallery.com/api/v2/package/{0}/{1}' -f $Name, $Version
        $request = [System.Net.WebRequest]::Create($packageUri)
        $request.Method = 'GET'
        $request.Timeout = 60000
        $request.ReadWriteTimeout = 60000
        $request.UserAgent = 'Baseline Developer Diagnostics'
        $response = $request.GetResponse()
        try
        {
            $responseStream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Create($packagePath)
            try
            {
                $responseStream.CopyTo($fileStream)
            }
            finally
            {
                $fileStream.Dispose()
                if ($responseStream) { $responseStream.Dispose() }
            }
        }
        finally
        {
            if ($response) { $response.Close() }
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractPath)

        foreach ($metadataName in @('_rels', 'package', '[Content_Types].xml', ('{0}.nuspec' -f $Name)))
        {
            $metadataPath = Join-Path $extractPath $metadataName
            if (Test-Path -LiteralPath $metadataPath)
            {
                Remove-Item -LiteralPath $metadataPath -Recurse -Force
            }
        }

        $moduleParent = Split-Path -Path $moduleDirectory -Parent
        New-Item -Path $moduleParent -ItemType Directory -Force | Out-Null
        if (Test-Path -LiteralPath $moduleDirectory)
        {
            Remove-Item -LiteralPath $moduleDirectory -Recurse -Force
        }
        New-Item -Path $moduleDirectory -ItemType Directory -Force | Out-Null
        Get-ChildItem -LiteralPath $extractPath -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $moduleDirectory -Recurse -Force
        }
    }
    finally
    {
        if (Test-Path -LiteralPath $tempRoot)
        {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf))
    {
        throw ('PowerShell Gallery package {0} {1} did not contain {0}.psd1 after extraction.' -f $Name, $Version)
    }

    return $moduleManifest
}

function Install-BaselineDiagnosticsPowerShellGetComponents
{
    param([string[]]$MissingCommandNames)

    Write-BaselineDiagnosticsStep 'Installing PowerShellGet'
    Write-Output ('Installing missing PowerShellGet/PackageManagement components: {0}' -f ($MissingCommandNames -join ', '))

    $packageManagementManifest = Install-BaselineDiagnosticsGalleryModulePackage -Name 'PackageManagement' -Version '1.4.8.1'
    Import-Module -Name $packageManagementManifest -Force -Global -ErrorAction Stop

    $powerShellGetManifest = Install-BaselineDiagnosticsGalleryModulePackage -Name 'PowerShellGet' -Version '2.2.5'
    Import-Module -Name $powerShellGetManifest -Force -Global -ErrorAction Stop
}

try
{
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
}
catch
{
    $null = $_
}

$galleryUri = 'https://www.powershellgallery.com/api/v2'
Write-BaselineDiagnosticsStep 'Checking PSGallery'
Write-Output 'Checking PowerShell Gallery connectivity...'
try
{
    $request = [System.Net.WebRequest]::Create($galleryUri)
    $request.Method = 'GET'
    $request.Timeout = 15000
    $response = $request.GetResponse()
    if ($response) { $response.Close() }
    Write-Output 'PowerShell Gallery is reachable.'
}
catch
{
    Stop-BaselineDiagnosticsInstall -Message ("PowerShell Gallery is not reachable: {0}" -f $_.Exception.Message) -ExitCode 42
}

$useServerPesterPackageFeedInstall = Test-BaselineDiagnosticsServerOperatingSystem
if ($useServerPesterPackageFeedInstall)
{
    Write-BaselineDiagnosticsStep 'Resolving Pester version'
    Write-Output 'Windows Server detected; using the PowerShell Gallery package feed directly to avoid legacy PowerShellGet prerelease parsing.'
    $latestPesterVersion = Select-BaselineDiagnosticsStablePackageVersion -Versions @(Get-BaselineDiagnosticsGalleryPackageVersions -Name 'Pester') -Major 5
    if (-not $latestPesterVersion)
    {
        throw 'PowerShell Gallery did not return a stable Pester 5.x package.'
    }

    Write-BaselineDiagnosticsStep 'Installing Pester'
    Write-Output ("Installing Pester {0} for current user from the PowerShell Gallery package feed..." -f $latestPesterVersion)
    Install-BaselineDiagnosticsGalleryModulePackage -Name 'Pester' -Version ([string]$latestPesterVersion) | Out-Null
}
else
{
    Write-BaselineDiagnosticsStep 'Checking PowerShellGet'
    Write-Output 'Checking Windows PowerShellGet and PackageManagement commands...'
    $requiredCommandNames = @(
        'Get-PackageProvider'
        'Install-PackageProvider'
        'Find-Module'
        'Install-Module'
    )
    $missingCommandNames = @(Get-BaselineDiagnosticsMissingPowerShellGetCommand -CommandNames $requiredCommandNames)
    if ($missingCommandNames.Count -gt 0)
    {
        try
        {
            Install-BaselineDiagnosticsPowerShellGetComponents -MissingCommandNames $missingCommandNames
        }
        catch
        {
            Stop-BaselineDiagnosticsInstall -Message ('PowerShellGet/PackageManagement automatic installation failed: {0}' -f $_.Exception.Message) -ExitCode 43
        }

        $missingCommandNames = @(Get-BaselineDiagnosticsMissingPowerShellGetCommand -CommandNames $requiredCommandNames)
        if ($missingCommandNames.Count -gt 0)
        {
            Stop-BaselineDiagnosticsInstall -Message ('PowerShellGet/PackageManagement automatic installation completed, but required command(s) are still missing: {0}.' -f ($missingCommandNames -join ', ')) -ExitCode 43
        }
    }

    Write-BaselineDiagnosticsStep 'Checking NuGet provider'
    $getRepositoryCommand = Get-Command -Name Get-PSRepository -ErrorAction SilentlyContinue
    $registerRepositoryCommand = Get-Command -Name Register-PSRepository -ErrorAction SilentlyContinue
    $setRepositoryCommand = Get-Command -Name Set-PSRepository -ErrorAction SilentlyContinue
    $repository = $null
    if ($getRepositoryCommand)
    {
        $repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    }
    else
    {
        Write-Warning 'Get-PSRepository is not available; skipping PSGallery registration check.'
    }
    if (-not $repository -and $registerRepositoryCommand)
    {
        Write-Output 'Registering PowerShell Gallery repository...'
        $registerRepositoryParameters = @{
            Default = $true
            ErrorAction = 'Stop'
        }
        if ($registerRepositoryCommand.Parameters.ContainsKey('Confirm'))
        {
            $registerRepositoryParameters.Confirm = $false
        }
        Register-PSRepository @registerRepositoryParameters
    }
    elseif (-not $repository)
    {
        Write-Warning 'Register-PSRepository is not available; continuing with existing package sources.'
    }

    if ($setRepositoryCommand)
    {
        try
        {
            $setRepositoryParameters = @{
                Name = 'PSGallery'
                InstallationPolicy = 'Trusted'
                ErrorAction = 'Stop'
            }
            if ($setRepositoryCommand.Parameters.ContainsKey('Confirm'))
            {
                $setRepositoryParameters.Confirm = $false
            }
            Set-PSRepository @setRepositoryParameters
        }
        catch
        {
            Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.SetPSGalleryTrusted' -Severity Warning
        }
    }
    else
    {
        Write-Warning 'Set-PSRepository is not available; continuing without marking PSGallery trusted. Install-Module runs with -Force and -Confirm:$false.'
    }

    $nugetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $nugetProvider -or $nugetProvider.Version -lt [version]'2.8.5.201')
    {
        Write-BaselineDiagnosticsStep 'Installing NuGet provider'
        Write-Output 'Installing NuGet package provider for current user...'
        $providerCommand = Get-Command -Name Install-PackageProvider -ErrorAction Stop
        $providerParameters = @{
            Name = 'NuGet'
            MinimumVersion = '2.8.5.201'
            Force = $true
            ErrorAction = 'Stop'
        }
        if ($providerCommand.Parameters.ContainsKey('Scope'))
        {
            $providerParameters.Scope = 'CurrentUser'
        }
        if ($providerCommand.Parameters.ContainsKey('Confirm'))
        {
            $providerParameters.Confirm = $false
        }
        if ($providerCommand.Parameters.ContainsKey('ForceBootstrap'))
        {
            $providerParameters.ForceBootstrap = $true
        }
        Install-PackageProvider @providerParameters | Out-Null
    }

    try
    {
        $importProviderCommand = Get-Command -Name Import-PackageProvider -ErrorAction Stop
        $importProviderParameters = @{
            Name = 'NuGet'
            MinimumVersion = '2.8.5.201'
            Force = $true
            ErrorAction = 'Stop'
        }
        if ($importProviderCommand.Parameters.ContainsKey('Confirm'))
        {
            $importProviderParameters.Confirm = $false
        }
        Import-PackageProvider @importProviderParameters | Out-Null
    }
    catch
    {
        Write-Warning ("Could not import NuGet provider before installing Pester:`r`n{0}" -f (($_ | Out-String).Trim()))
    }

    $latestPester = Select-BaselineDiagnosticsStablePesterPackage -Packages @(Find-Module -Name Pester -Repository PSGallery -AllVersions -ErrorAction Stop) -Major 5
    if (-not $latestPester)
    {
        throw 'PowerShell Gallery did not return a stable Pester 5.x package.'
    }

    Write-BaselineDiagnosticsStep 'Installing Pester'
    Write-Output 'Running Pester install in non-interactive mode; prompts are suppressed.'
    Write-Output ("Installing Pester {0} for current user..." -f $latestPester.Version)
    $installModuleCommand = Get-Command -Name Install-Module -ErrorAction Stop
    $installModuleParameters = @{
        Name = 'Pester'
        RequiredVersion = $latestPester.Version
        Scope = 'CurrentUser'
        Repository = 'PSGallery'
        Force = $true
        AllowClobber = $true
        SkipPublisherCheck = $true
        ErrorAction = 'Stop'
    }
    if ($installModuleCommand.Parameters.ContainsKey('AcceptLicense'))
    {
        $installModuleParameters.AcceptLicense = $true
    }
    if ($installModuleCommand.Parameters.ContainsKey('Confirm'))
    {
        $installModuleParameters.Confirm = $false
    }
    Install-Module @installModuleParameters
}

Write-BaselineDiagnosticsStep 'Verifying version'
$pesterModule = Get-Module -ListAvailable -Name Pester -ErrorAction Stop |
    Where-Object {
        $pesterVersion = ConvertTo-BaselineDiagnosticsVersion -Value $_.Version
        $pesterVersion -and $pesterVersion.Major -eq 5 -and $pesterVersion -ge [version]'5.5.0'
    } |
    Sort-Object -Property { ConvertTo-BaselineDiagnosticsVersion -Value $_.Version } -Descending |
    Select-Object -First 1

if (-not $pesterModule)
{
    throw 'Supported Pester 5.x 5.5.0 or newer was not available after installation.'
}

Write-BaselineDiagnosticsStep 'Ready'
Write-Output ("Pester {0} is available at {1}" -f $pesterModule.Version, $pesterModule.ModuleBase)
'@
}

function New-GuiDeveloperDiagnosticsPesterInstallCommandContext
{
    $powershellPath = Get-GuiDeveloperDiagnosticsPowerShellPath
    if ([string]::IsNullOrWhiteSpace([string]$powershellPath))
    {
        throw 'Windows PowerShell is not available.'
    }

    $installScript = Get-GuiDeveloperDiagnosticsPesterInstallScript
    $installScriptPath = Join-Path (Get-GuiDeveloperDiagnosticsTempDirectory) ('InstallPester_{0}.ps1' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    Set-Content -LiteralPath $installScriptPath -Value $installScript -Encoding UTF8 -Force
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $installScriptPath)

    return [pscustomobject]@{
        PowerShellPath = $powershellPath
        ScriptPath = $installScriptPath
        Arguments = $arguments
        ArgumentList = (Join-GuiDeveloperDiagnosticsArgumentList -Arguments $arguments)
        CommandText = ('{0} {1}' -f (ConvertTo-GuiDeveloperDiagnosticsArgument -Value $powershellPath), (Join-GuiDeveloperDiagnosticsArgumentList -Arguments $arguments))
    }
}

function Start-GuiDeveloperDiagnosticsPesterInstallProcess
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$StdoutPath,

        [Parameter(Mandatory = $true)]
        [string]$StderrPath,

        [object]$CommandContext
    )

    if (-not $CommandContext)
    {
        $CommandContext = New-GuiDeveloperDiagnosticsPesterInstallCommandContext
    }

    return (Start-Process -FilePath ([string]$CommandContext.PowerShellPath) `
        -ArgumentList ([string]$CommandContext.ArgumentList) `
        -WorkingDirectory (Get-GuiDeveloperDiagnosticsRepoRoot) `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath `
        -WindowStyle Hidden `
        -PassThru)
}

function Get-GuiDeveloperDiagnosticsPesterStatusCheckScript
{
    return @'
param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$minimumSupported = [version]'5.5.0'
$recommendedMajor = 5
$nowUtc = [DateTime]::UtcNow.ToString('o')

function ConvertTo-BaselineDiagnosticsVersion
{
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $versionText = [string]$Value
    if ([string]::IsNullOrWhiteSpace($versionText)) { return $null }
    if ($versionText -match '-')
    {
        return $null
    }

    $parsedVersion = [version]'0.0'
    if ([version]::TryParse($versionText, [ref]$parsedVersion))
    {
        return $parsedVersion
    }

    return $null
}

function Select-BaselineDiagnosticsStablePesterPackage
{
    param(
        [object[]]$Packages,
        [int]$Major = 5
    )

    $stablePackages = @()
    foreach ($package in @($Packages))
    {
        if (-not $package) { continue }
        $packageVersion = ConvertTo-BaselineDiagnosticsVersion -Value $package.Version
        if ($packageVersion -and $packageVersion.Major -eq $Major)
        {
            $stablePackages += [pscustomobject]@{
                Package = $package
                Version = $packageVersion
            }
        }
    }

    $selectedPackage = $stablePackages |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($selectedPackage)
    {
        return $selectedPackage.Package
    }

    return $null
}

function Invoke-BaselineDiagnosticsWebText
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [int]$TimeoutMilliseconds = 60000
    )

    $request = [System.Net.WebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.Timeout = $TimeoutMilliseconds
    $request.ReadWriteTimeout = $TimeoutMilliseconds
    $request.UserAgent = 'Baseline Developer Diagnostics'
    $response = $request.GetResponse()
    try
    {
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8, $true)
        try
        {
            return $reader.ReadToEnd()
        }
        finally
        {
            $reader.Dispose()
            if ($responseStream) { $responseStream.Dispose() }
        }
    }
    finally
    {
        if ($response) { $response.Close() }
    }
}

function Get-BaselineDiagnosticsGalleryPackageVersions
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $versions = New-Object 'System.Collections.Generic.List[string]'
    $escapedPackageName = [Uri]::EscapeDataString(("'{0}'" -f $Name.Replace("'", "''")))
    $uri = 'https://www.powershellgallery.com/api/v2/FindPackagesById()?id={0}' -f $escapedPackageName
    while (-not [string]::IsNullOrWhiteSpace([string]$uri))
    {
        $xmlText = Invoke-BaselineDiagnosticsWebText -Uri $uri
        [xml]$feed = $xmlText
        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($feed.NameTable)
        $namespaceManager.AddNamespace('atom', 'http://www.w3.org/2005/Atom')
        $namespaceManager.AddNamespace('m', 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')
        $namespaceManager.AddNamespace('d', 'http://schemas.microsoft.com/ado/2007/08/dataservices')

        $versionNodes = $feed.SelectNodes('//atom:entry/atom:content/m:properties/d:Version', $namespaceManager)
        foreach ($versionNode in @($versionNodes))
        {
            if (-not [string]::IsNullOrWhiteSpace([string]$versionNode.InnerText))
            {
                [void]$versions.Add([string]$versionNode.InnerText)
            }
        }
        if (@($versionNodes).Count -eq 0)
        {
            foreach ($match in [regex]::Matches($xmlText, '<d:Version[^>]*>([^<]+)</d:Version>'))
            {
                if ($match.Groups.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace([string]$match.Groups[1].Value))
                {
                    [void]$versions.Add([string]$match.Groups[1].Value)
                }
            }
        }

        $nextLink = $feed.SelectSingleNode('//atom:link[@rel="next"]', $namespaceManager)
        if ($nextLink -and -not [string]::IsNullOrWhiteSpace([string]$nextLink.href))
        {
            $uri = [string]$nextLink.href
        }
        else
        {
            $uri = $null
        }
    }

    return @($versions.ToArray())
}

function Select-BaselineDiagnosticsStablePackageVersion
{
    param(
        [string[]]$Versions,
        [int]$Major = 5
    )

    $stableVersions = @()
    foreach ($version in @($Versions))
    {
        $packageVersion = ConvertTo-BaselineDiagnosticsVersion -Value $version
        if ($packageVersion -and $packageVersion.Major -eq $Major)
        {
            $stableVersions += $packageVersion
        }
    }

    $selectedVersion = $stableVersions |
        Sort-Object -Descending |
        Select-Object -First 1
    if ($selectedVersion)
    {
        return $selectedVersion
    }

    return $null
}

function Test-BaselineDiagnosticsServerOperatingSystem
{
    try
    {
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return ($operatingSystem -and [int]$operatingSystem.ProductType -ne 1)
    }
    catch
    {
        return $false
    }
}

$installedModule = Get-Module -ListAvailable -Name Pester -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

$installedVersion = if ($installedModule) { [string]$installedModule.Version } else { '' }
$installedVersionValue = if ($installedModule) { ConvertTo-BaselineDiagnosticsVersion -Value $installedModule.Version } else { $null }
$installedSupported = ($installedVersionValue -and $installedVersionValue.Major -eq $recommendedMajor -and $installedVersionValue -ge $minimumSupported)
$result = [ordered]@{
    InstalledVersion = $installedVersion
    LatestVersion = ''
    MinimumSupportedVersion = [string]$minimumSupported
    RecommendedMajorVersion = $recommendedMajor
    LastCheckedUtc = $nowUtc
    CheckSucceeded = $false
    UpdateAvailable = $false
    InstalledSupported = [bool]$installedSupported
    ErrorMessage = ''
}

try
{
    try
    {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    }
    catch
    {
        $null = $_
    }

    if (Test-BaselineDiagnosticsServerOperatingSystem)
    {
        $latestPesterVersion = Select-BaselineDiagnosticsStablePackageVersion -Versions @(Get-BaselineDiagnosticsGalleryPackageVersions -Name 'Pester') -Major $recommendedMajor
        if (-not $latestPesterVersion)
        {
            throw 'PowerShell Gallery did not return a stable Pester 5.x package.'
        }

        $result.LatestVersion = [string]$latestPesterVersion
        $latestVersionValue = $latestPesterVersion
    }
    else
    {
        $latestPester = Select-BaselineDiagnosticsStablePesterPackage -Packages @(Find-Module -Name Pester -Repository PSGallery -AllVersions -ErrorAction Stop) -Major $recommendedMajor
        if (-not $latestPester)
        {
            throw 'PowerShell Gallery did not return a stable Pester 5.x package.'
        }

        $result.LatestVersion = [string]$latestPester.Version
        $latestVersionValue = ConvertTo-BaselineDiagnosticsVersion -Value $latestPester.Version
    }

    $result.CheckSucceeded = $true
    if ($installedVersionValue -and $latestVersionValue)
    {
        $result.UpdateAvailable = ($installedVersionValue -lt $latestVersionValue)
    }
}
catch
{
    $result.ErrorMessage = $_.Exception.Message
}

$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force
if (-not $result.CheckSucceeded)
{
    exit 42
}
'@
}

function Start-GuiDeveloperDiagnosticsPesterStatusCheckProcess
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultPath,

        [Parameter(Mandatory = $true)]
        [string]$StdoutPath,

        [Parameter(Mandatory = $true)]
        [string]$StderrPath
    )

    $powershellPath = Get-GuiDeveloperDiagnosticsPowerShellPath
    if ([string]::IsNullOrWhiteSpace([string]$powershellPath))
    {
        throw 'Windows PowerShell is not available.'
    }

    $checkScript = Get-GuiDeveloperDiagnosticsPesterStatusCheckScript
    $checkScriptPath = Join-Path (Get-GuiDeveloperDiagnosticsTempDirectory) ('CheckPesterStatus_{0}.ps1' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    Set-Content -LiteralPath $checkScriptPath -Value $checkScript -Encoding UTF8 -Force
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $checkScriptPath, '-ResultPath', $ResultPath)
    return (Start-Process -FilePath $powershellPath `
        -ArgumentList (Join-GuiDeveloperDiagnosticsArgumentList -Arguments $arguments) `
        -WorkingDirectory (Get-GuiDeveloperDiagnosticsRepoRoot) `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath `
        -WindowStyle Hidden `
        -PassThru)
}

function Add-GuiDeveloperDiagnosticsOutputText
{
    param(
        [object]$TextBox,
        [string]$Text,
        [switch]$Reveal
    )

    if (-not $TextBox) { return }
    if ([string]::IsNullOrEmpty($Text)) { return }
    if ($Reveal)
    {
        $TextBox.Visibility = [System.Windows.Visibility]::Visible
    }
    $TextBox.AppendText($Text)
    $TextBox.ScrollToEnd()
}

function Add-GuiDeveloperDiagnosticsFileDeltaOutput
{
    param(
        [object]$TextBox,
        [string]$Path,
        [hashtable]$State,
        [string]$Key,
        [switch]$Reveal
    )

    $text = Read-GuiDeveloperDiagnosticsFileDelta -Path $Path -State $State -Key $Key
    Add-GuiDeveloperDiagnosticsOutputText -TextBox $TextBox -Text $text -Reveal:$Reveal
}

function Read-GuiDeveloperDiagnosticsTextFile
{
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) { return '' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try
    {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try
        {
            return $reader.ReadToEnd()
        }
        finally
        {
            $reader.Dispose()
        }
    }
    finally
    {
        $stream.Dispose()
    }
}

function Open-GuiDeveloperDiagnosticsPath
{
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace([string]$Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    Start-Process -FilePath $Path | Out-Null
    return $true
}

function Read-GuiDeveloperDiagnosticsPesterStatusCache
{
    try
    {
        $cachePath = Get-GuiDeveloperDiagnosticsPesterStatusCachePath
        if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf))
        {
            return $null
        }

        return (Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Read-GuiDeveloperDiagnosticsPesterStatusCache:catch1247' -Severity Debug }

        return $null
    }
}

function Write-GuiDeveloperDiagnosticsPesterStatusCache
{
    param([object]$Status)

    try
    {
        $cachePath = Get-GuiDeveloperDiagnosticsPesterStatusCachePath
        $Status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding UTF8 -Force
    }
    catch
    {
        Write-GuiDeveloperDiagnosticsError -Message ('Could not write Pester status cache: {0}' -f $_.Exception.Message)
    }
}

function New-GuiDeveloperDiagnosticsPesterStatusFailure
{
    param([string]$ErrorMessage)

    $installedStatus = Get-GuiDeveloperDiagnosticsInstalledPesterStatus
    return [pscustomobject]@{
        InstalledVersion = [string]$installedStatus.InstalledVersion
        LatestVersion = ''
        MinimumSupportedVersion = [string]$installedStatus.MinimumSupportedVersion
        RecommendedMajorVersion = [int]$installedStatus.RecommendedMajorVersion
        LastCheckedUtc = [DateTime]::UtcNow.ToString('o')
        CheckSucceeded = $false
        UpdateAvailable = $false
        InstalledSupported = [bool]$installedStatus.InstalledSupported
        ErrorMessage = [string]$ErrorMessage
    }
}

function Get-GuiDeveloperDiagnosticsPesterStatusSummary
{
    $installedStatus = Get-GuiDeveloperDiagnosticsInstalledPesterStatus
    $cache = Read-GuiDeveloperDiagnosticsPesterStatusCache
    $latestVersion = if ($cache -and $cache.PSObject.Properties.Name -contains 'LatestVersion') { [string]$cache.LatestVersion } else { '' }
    $lastCheckedUtc = if ($cache -and $cache.PSObject.Properties.Name -contains 'LastCheckedUtc') { [string]$cache.LastCheckedUtc } else { '' }
    $checkSucceeded = if ($cache -and $cache.PSObject.Properties.Name -contains 'CheckSucceeded') { [bool]$cache.CheckSucceeded } else { $false }
    $errorMessage = if ($cache -and $cache.PSObject.Properties.Name -contains 'ErrorMessage') { [string]$cache.ErrorMessage } else { '' }
    $installedVersionObject = ConvertTo-GuiDeveloperDiagnosticsVersion -Value $installedStatus.InstalledVersion
    $latestVersionObject = ConvertTo-GuiDeveloperDiagnosticsVersion -Value $latestVersion
    $updateAvailable = ($null -ne $installedVersionObject -and $null -ne $latestVersionObject -and $installedVersionObject -lt $latestVersionObject)

    return [pscustomobject]@{
        InstalledVersion = [string]$installedStatus.InstalledVersion
        InstalledSupported = [bool]$installedStatus.InstalledSupported
        LatestVersion = [string]$latestVersion
        MinimumSupportedVersion = [string]$installedStatus.MinimumSupportedVersion
        RecommendedMajorVersion = [int]$installedStatus.RecommendedMajorVersion
        LastCheckedUtc = [string]$lastCheckedUtc
        CheckSucceeded = [bool]$checkSucceeded
        UpdateAvailable = [bool]$updateAvailable
        ErrorMessage = [string]$errorMessage
    }
}

function Test-GuiDeveloperDiagnosticsPesterStatusCheckDue
{
    param([object]$Summary)

    if ($null -eq $Summary) { return $true }
    if ([string]::IsNullOrWhiteSpace([string]$Summary.LastCheckedUtc)) { return $true }

    try
    {
        $lastChecked = ([datetime]::Parse([string]$Summary.LastCheckedUtc)).ToUniversalTime()
        return (([DateTime]::UtcNow - $lastChecked).TotalDays -ge [double]$Script:GuiDeveloperDiagnosticsPesterStatusCacheDays)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Test-GuiDeveloperDiagnosticsPesterStatusCheckDue:catch1323' -Severity Debug }

        return $true
    }
}

function Format-GuiDeveloperDiagnosticsPesterStatusText
{
    param(
        [object]$Summary,
        [string]$ActivityText
    )

    $installedText = if (-not [string]::IsNullOrWhiteSpace([string]$Summary.InstalledVersion))
    {
        if ([bool]$Summary.InstalledSupported)
        {
            [string]$Summary.InstalledVersion
        }
        else
        {
            ('{0} (unsupported)' -f [string]$Summary.InstalledVersion)
        }
    }
    else
    {
        'not installed'
    }

    $latestText = if (-not [string]::IsNullOrWhiteSpace([string]$Summary.LatestVersion))
    {
        [string]$Summary.LatestVersion
    }
    elseif ([bool]$Summary.CheckSucceeded)
    {
        'not found'
    }
    else
    {
        'unknown'
    }

    $lastCheckedText = if (-not [string]::IsNullOrWhiteSpace([string]$Summary.LastCheckedUtc))
    {
        try
        {
            $lastChecked = ([datetime]::Parse([string]$Summary.LastCheckedUtc)).ToLocalTime()
            ('{0:g}' -f $lastChecked)
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Format-GuiDeveloperDiagnosticsPesterStatusText:catch1372' -Severity Debug }

            [string]$Summary.LastCheckedUtc
        }
    }
    else
    {
        'never'
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add(('Installed: {0}' -f $installedText))
    [void]$lines.Add(('Latest stable 5.x: {0}' -f $latestText))
    [void]$lines.Add(('Last checked: {0}' -f $lastCheckedText))
    [void]$lines.Add(('Policy: minimum supported {0}; recommended latest stable {1}.x.' -f [string]$Summary.MinimumSupportedVersion, [int]$Summary.RecommendedMajorVersion))
    if (-not [string]::IsNullOrWhiteSpace($ActivityText))
    {
        [void]$lines.Add($ActivityText)
    }
    elseif (-not [bool]$Summary.CheckSucceeded -and -not [string]::IsNullOrWhiteSpace([string]$Summary.ErrorMessage))
    {
        [void]$lines.Add(('Could not check PSGallery. Using installed Pester {0}.' -f $installedText))
    }
    elseif ([bool]$Summary.UpdateAvailable)
    {
        [void]$lines.Add('A newer stable Pester 5.x version is available.')
    }
    elseif ([bool]$Summary.CheckSucceeded -and -not [string]::IsNullOrWhiteSpace([string]$Summary.LatestVersion))
    {
        [void]$lines.Add('Pester is up to date.')
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-GuiDeveloperDiagnosticsPesterInstallStatusText
{
    param([hashtable]$State)

    $currentStep = if ($State.ContainsKey('CurrentStep') -and -not [string]::IsNullOrWhiteSpace([string]$State.CurrentStep))
    {
        [string]$State.CurrentStep
    }
    else
    {
        'Starting'
    }

    $elapsedSeconds = 0
    if ($State.ContainsKey('StartTime') -and $State.StartTime)
    {
        $elapsedSeconds = [int]([DateTime]::Now - [datetime]$State.StartTime).TotalSeconds
    }

    $lastOutputText = 'not yet'
    $secondsSinceOutput = $elapsedSeconds
    if ($State.ContainsKey('LastOutputTime') -and $State.LastOutputTime)
    {
        $secondsSinceOutput = [int]([DateTime]::Now - [datetime]$State.LastOutputTime).TotalSeconds
        $lastOutputText = ('{0:N0}s ago' -f $secondsSinceOutput)
    }

    $processText = if ($State.ContainsKey('Process') -and $State.Process)
    {
        ('Pester installer process PID {0} is running.' -f $State.Process.Id)
    }
    else
    {
        'Pester installer process is starting.'
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add($processText)
    [void]$lines.Add(('Current step: {0}' -f $currentStep))
    [void]$lines.Add(('Elapsed: {0:N0}s. Last output received: {1}.' -f $elapsedSeconds, $lastOutputText))
    if ($elapsedSeconds -ge [int]$Script:GuiDeveloperDiagnosticsPesterInstallNoOutputWarningSeconds -and $secondsSinceOutput -ge [int]$Script:GuiDeveloperDiagnosticsPesterInstallNoOutputWarningSeconds)
    {
        [void]$lines.Add(('No output received for {0:N0} seconds.' -f $secondsSinceOutput))
        [void]$lines.Add('The installer may be waiting on PowerShellGet, provider bootstrap, or network activity.')
    }

    return ($lines -join "`r`n")
}

function Add-GuiDeveloperDiagnosticsPesterInstallFileDeltaOutput
{
    param(
        [object]$TextBox,
        [string]$Path,
        [hashtable]$State,
        [string]$Key,
        [switch]$Reveal
    )

    $text = Read-GuiDeveloperDiagnosticsFileDelta -Path $Path -State $State -Key $Key
    if ([string]::IsNullOrEmpty($text)) { return }

    $State.LastOutputTime = Get-Date
    if ($State.ContainsKey('LogPath') -and -not [string]::IsNullOrWhiteSpace([string]$State.LogPath))
    {
        [System.IO.File]::AppendAllText([string]$State.LogPath, $text, [System.Text.Encoding]::UTF8)
    }

    $visibleOutput = New-Object System.Text.StringBuilder
    $reader = New-Object System.IO.StringReader($text)
    try
    {
        while ($null -ne ($line = $reader.ReadLine()))
        {
            if ($line.StartsWith($Script:GuiDeveloperDiagnosticsPesterStepPrefix, [System.StringComparison]::Ordinal))
            {
                $State.CurrentStep = $line.Substring($Script:GuiDeveloperDiagnosticsPesterStepPrefix.Length).Trim()
                continue
            }

            [void]$visibleOutput.AppendLine($line)
        }
    }
    finally
    {
        $reader.Dispose()
    }

    Add-GuiDeveloperDiagnosticsOutputText -TextBox $TextBox -Text $visibleOutput.ToString() -Reveal:$Reveal
}

function Set-GuiDeveloperDiagnosticsActionButtonsState
{
    param(
        [object[]]$Buttons,
        [bool]$Enabled,
        [string]$ToolTipText
    )

    foreach ($button in @($Buttons))
    {
        if ($button -and ($button -is [System.Windows.Controls.Button]))
        {
            $button.IsEnabled = $Enabled
            $button.ToolTip = $ToolTipText
        }
    }
}

function Set-GuiDeveloperDiagnosticsControlState
{
    param(
        [object]$Control,
        [bool]$Enabled,
        [string]$ToolTip
    )

    if ($Control -isnot [System.Windows.Controls.Control])
    {
        return
    }

    $Control.IsEnabled = $Enabled
    $Control.ToolTip = $ToolTip
}

function Get-GuiDeveloperDiagnosticsFunctionCapture
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command -Name $Name -CommandType Function -ErrorAction Stop
    if ($command.ScriptBlock -isnot [scriptblock])
    {
        throw ("Developer diagnostics function capture did not resolve to a scriptblock: {0}" -f $Name)
    }

    return $command.ScriptBlock
}

function Update-GuiDeveloperDiagnosticsLauncherAvailabilityView
{
    param(
        [object[]]$ActionButtons,
        [object]$OpenLatestReportButton,
        [object]$CopyCommandsButton
    )

    $refreshedAvailability = Get-GuiDeveloperDiagnosticsAvailability
    $refreshedLatestReport = Get-GuiDeveloperDiagnosticsLatestReport
    $refreshedTooltip = if ($refreshedAvailability.Reasons.Count -gt 0)
    {
        ($refreshedAvailability.Reasons -join [Environment]::NewLine)
    }
    else
    {
        'Run validation tools in an external PowerShell process.'
    }

    Set-GuiDeveloperDiagnosticsActionButtonsState -Buttons $ActionButtons -Enabled ([bool]$refreshedAvailability.Enabled) -ToolTipText $refreshedTooltip
    $openTooltip = if ($refreshedLatestReport) { [string]$refreshedLatestReport.FullName } else { 'Generate a test report first.' }
    Set-GuiDeveloperDiagnosticsControlState -Control $OpenLatestReportButton -Enabled ($null -ne $refreshedLatestReport) -ToolTip $openTooltip
    Set-GuiDeveloperDiagnosticsControlState -Control $CopyCommandsButton -Enabled ([bool]$refreshedAvailability.ShowMenu) -ToolTip 'Copy the external PowerShell commands for manual execution.'
    Update-GuiDeveloperDiagnosticsMenuState
    return $refreshedAvailability
}

function Write-GuiDeveloperDiagnosticsError
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (Get-Command -Name 'LogError' -ErrorAction SilentlyContinue)
    {
        LogError $Message -Scope 'GUI'
    }
}

function Get-GuiDeveloperDiagnosticsAvailability
{
    $repoRoot = Get-GuiDeveloperDiagnosticsRepoRoot
    $toolsDir = Join-Path $repoRoot 'Tools'
    $testsDir = Join-Path $repoRoot 'Tests'
    $runnerPath = Join-Path $toolsDir 'Invoke-GuiDeveloperDiagnostics.ps1'
    $reasons = New-Object 'System.Collections.Generic.List[string]'

    $expertMode = if (Get-Command -Name 'Test-GuiModeActive' -CommandType Function -ErrorAction SilentlyContinue)
    {
        [bool](Test-GuiModeActive -Mode 'Expert')
    }
    else
    {
        [bool]$Script:AdvancedMode
    }

    if (-not $expertMode)
    {
        [void]$reasons.Add('Enable Expert Mode to use Developer Diagnostics.')
    }
    if (-not (Test-Path -LiteralPath $toolsDir -PathType Container))
    {
        [void]$reasons.Add('The Tools directory is not installed.')
    }
    if (-not (Test-Path -LiteralPath $testsDir -PathType Container))
    {
        [void]$reasons.Add('The Tests directory is not installed.')
    }
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf))
    {
        [void]$reasons.Add('The developer diagnostics runner is not installed.')
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-GuiDeveloperDiagnosticsPowerShellPath)))
    {
        [void]$reasons.Add('Windows PowerShell is not available.')
    }
    if (-not (Test-GuiDeveloperDiagnosticsPesterAvailable))
    {
        [void]$reasons.Add('Supported Pester 5.x 5.5.0 or newer is not available.')
    }
    if (Get-Command -Name 'Test-GuiRunInProgress' -CommandType Function -ErrorAction SilentlyContinue)
    {
        if (Test-GuiRunInProgress)
        {
            [void]$reasons.Add('A Baseline run is currently in progress.')
        }
    }

    $showMenu = $expertMode -and
        (Test-Path -LiteralPath $toolsDir -PathType Container) -and
        (Test-Path -LiteralPath $testsDir -PathType Container)

    return [pscustomobject]@{
        ShowMenu = [bool]$showMenu
        Enabled = ($reasons.Count -eq 0)
        Reasons = @($reasons)
        RepoRoot = $repoRoot
        ToolsDir = $toolsDir
        TestsDir = $testsDir
        RunnerPath = $runnerPath
    }
}

function Get-GuiDeveloperDiagnosticsLatestReport
{
    $reportDir = Get-GuiDeveloperDiagnosticsArtifactsDirectory
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container))
    {
        return $null
    }

    return (Get-ChildItem -LiteralPath $reportDir -Filter 'TestReport_*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1)
}

function Get-GuiDeveloperDiagnosticsReportPath
{
    $reportDir = Get-GuiDeveloperDiagnosticsArtifactsDirectory
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container))
    {
        New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
    }

    return (Join-Path $reportDir ('TestReport_{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
}

function ConvertTo-GuiDeveloperDiagnosticsArgument
{
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    $text = [string]$Value
    if ($text -notmatch '[\s"]')
    {
        return $text
    }

    return ('"{0}"' -f ($text.Replace('"', '\"')))
}

function Join-GuiDeveloperDiagnosticsArgumentList
{
    param([string[]]$Arguments)

    return (($Arguments | ForEach-Object { ConvertTo-GuiDeveloperDiagnosticsArgument -Value $_ }) -join ' ')
}

function ConvertTo-GuiDeveloperDiagnosticsCommandLiteral
{
    param([string]$Value)

    if ($null -eq $Value) { return "''" }
    return ("'{0}'" -f ([string]$Value).Replace("'", "''"))
}

function Get-GuiDeveloperDiagnosticsCommands
{
    $reportPath = Join-Path '.\.artifacts\gui-tests' ('TestReport_{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $runner = '.\Tools\Invoke-GuiDeveloperDiagnostics.ps1'
    return @(
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File {0} -Action ExportReport -OutputPath {1}' -f (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $runner), (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $reportPath))
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File {0} -Action SourceQuality -OutputPath {1}' -f (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $runner), (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $reportPath))
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File {0} -Action Unit -OutputPath {1}' -f (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $runner), (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $reportPath))
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File {0} -Action GuiComposition -OutputPath {1}' -f (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $runner), (ConvertTo-GuiDeveloperDiagnosticsCommandLiteral $reportPath))
    )
}

function Set-GuiDeveloperDiagnosticsMenuItemState
{
    param(
        [object]$MenuItem,
        [bool]$Enabled,
        [string]$ToolTip
    )

    if ($null -eq $MenuItem) { return }
    $MenuItem.IsEnabled = $Enabled
    $MenuItem.ToolTip = $ToolTip
}

function Update-GuiDeveloperDiagnosticsMenuState
{
    $availability = Get-GuiDeveloperDiagnosticsAvailability
    $visible = if ($availability.ShowMenu) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $latestReport = Get-GuiDeveloperDiagnosticsLatestReport
    $tooltip = if ($availability.Reasons.Count -gt 0)
    {
        ($availability.Reasons -join [Environment]::NewLine)
    }
    else
    {
        'Run validation tools in an external PowerShell process.'
    }

    if ($Script:MenuToolsSepDeveloperDiagnostics)
    {
        $Script:MenuToolsSepDeveloperDiagnostics.Visibility = $visible
    }
    if ($Script:MenuToolsDeveloperDiagnostics)
    {
        $Script:MenuToolsDeveloperDiagnostics.Visibility = $visible
        $Script:MenuToolsDeveloperDiagnostics.IsEnabled = [bool]$availability.ShowMenu
        $Script:MenuToolsDeveloperDiagnostics.ToolTip = $tooltip
    }

    foreach ($item in @(
        $Script:MenuToolsDeveloperDiagnosticsGenerateReport
        $Script:MenuToolsDeveloperDiagnosticsSourceQuality
        $Script:MenuToolsDeveloperDiagnosticsUnitTests
        $Script:MenuToolsDeveloperDiagnosticsGuiComposition
    ))
    {
        Set-GuiDeveloperDiagnosticsMenuItemState -MenuItem $item -Enabled ([bool]$availability.Enabled) -ToolTip $tooltip
    }

    $openTooltip = if ($latestReport) { [string]$latestReport.FullName } else { 'Generate a test report first.' }
    Set-GuiDeveloperDiagnosticsMenuItemState -MenuItem $Script:MenuToolsDeveloperDiagnosticsOpenLatestReport -Enabled ($null -ne $latestReport) -ToolTip $openTooltip
    Set-GuiDeveloperDiagnosticsMenuItemState -MenuItem $Script:MenuToolsDeveloperDiagnosticsCopyCommands -Enabled ([bool]$availability.ShowMenu) -ToolTip 'Copy the external PowerShell commands for manual execution.'

    $integrationFlag = Join-Path $availability.RepoRoot '.baseline-enable-integration-diagnostics'
    $integrationVisible = (Test-Path -LiteralPath $integrationFlag -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $availability.TestsDir 'Integration') -PathType Container)
    $integrationVisibility = if ($integrationVisible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    if ($Script:MenuToolsDeveloperDiagnosticsIntegrationSeparator)
    {
        $Script:MenuToolsDeveloperDiagnosticsIntegrationSeparator.Visibility = $integrationVisibility
    }
    if ($Script:MenuToolsDeveloperDiagnosticsIntegrationTests)
    {
        $Script:MenuToolsDeveloperDiagnosticsIntegrationTests.Visibility = $integrationVisibility
        $Script:MenuToolsDeveloperDiagnosticsIntegrationTests.IsEnabled = ([bool]$availability.Enabled -and $integrationVisible)
        $Script:MenuToolsDeveloperDiagnosticsIntegrationTests.ToolTip = 'VM only. Modifies registry, services, and packages. Recommended only in disposable VMs.'
    }
}

function Add-GuiDeveloperDiagnosticsLauncherButton
{
    param(
        [System.Windows.Controls.Panel]$Panel,
        [string]$Text,
        [bool]$Enabled,
        [string]$ToolTip,
        [scriptblock]$Click
    )

    $button = New-Object System.Windows.Controls.Button
    $button.Content = $Text
    $button.HorizontalContentAlignment = 'Left'
    $button.MinHeight = 34
    $button.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $button.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
    $button.IsEnabled = $Enabled
    $button.ToolTip = $ToolTip
    if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
    {
        Set-GuiButtonChrome -Button $button -Variant 'Secondary'
    }
    if ($Click)
    {
        $button.Add_Click($Click)
    }

    [void]$Panel.Children.Add($button)
    return $button
}

function Show-GuiDeveloperDiagnosticsLauncher
{
    if ([bool]$Script:GuiDeveloperDiagnosticsLauncherOpen)
    {
        return
    }

    $Script:GuiDeveloperDiagnosticsLauncherOpen = $true
    try
    {
        Update-GuiDeveloperDiagnosticsMenuState
        $availability = Get-GuiDeveloperDiagnosticsAvailability
        $latestReport = Get-GuiDeveloperDiagnosticsLatestReport
        $tooltip = if ($availability.Reasons.Count -gt 0)
        {
            ($availability.Reasons -join [Environment]::NewLine)
        }
        else
        {
            'Run validation tools in an external PowerShell process.'
        }

        $theme = if ($Script:CurrentTheme) { $Script:CurrentTheme } else { @{ WindowBg = '#FFFFFF'; PanelBg = '#F4F4F5'; BorderColor = '#D1D5DB'; TextPrimary = '#111827'; TextSecondary = '#4B5563'; AccentBlue = '#2563EB' } }
        $window = New-Object System.Windows.Window
        $window.Title = 'Developer Diagnostics'
        $window.Width = 560
        $window.Height = 560
        $window.MinWidth = 480
        $window.MinHeight = 460
        $window.WindowStartupLocation = 'CenterOwner'
        $window.ResizeMode = 'CanResizeWithGrip'
        $window.ShowInTaskbar = $false
        $window.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.WindowBg -DefaultColor '#FFFFFF'
        $window.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
        try { if ($Script:MainForm) { $window.Owner = $Script:MainForm } } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch1850' -Severity Debug }
         $null = $_ }

        $root = New-Object System.Windows.Controls.Grid
        [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
        [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
        [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))

        $header = New-Object System.Windows.Controls.Border
        $header.Padding = [System.Windows.Thickness]::new(18, 16, 18, 14)
        $header.BorderBrush = New-GuiDeveloperDiagnosticsBrush -Color $theme.BorderColor -DefaultColor '#D1D5DB'
        $header.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $header.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.PanelBg -DefaultColor '#F4F4F5'
        $headerStack = New-Object System.Windows.Controls.StackPanel

        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text = 'Developer Diagnostics'
        $titleText.FontSize = 18
        $titleText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $titleText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
        [void]$headerStack.Children.Add($titleText)

        $statusText = New-Object System.Windows.Controls.TextBlock
        $statusText.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
        $statusText.TextWrapping = 'Wrap'
        $statusText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextSecondary -DefaultColor '#4B5563'
        $statusText.Text = if ($availability.Enabled)
        {
            'Choose a validation action. Diagnostics run outside the GUI process.'
        }
        else
        {
            $tooltip
        }
        [void]$headerStack.Children.Add($statusText)
        $header.Child = $headerStack
        [System.Windows.Controls.Grid]::SetRow($header, 0)
        [void]$root.Children.Add($header)

        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Padding = [System.Windows.Thickness]::new(18)
        $content = New-Object System.Windows.Controls.StackPanel
        $scroll.Content = $content
        [System.Windows.Controls.Grid]::SetRow($scroll, 1)
        [void]$root.Children.Add($scroll)

        $startDiagnosticsActionScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Start-GuiDeveloperDiagnosticsAction'
        $startPesterInstallScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Start-GuiDeveloperDiagnosticsPesterInstallProcess'
        $newPesterInstallCommandContextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'New-GuiDeveloperDiagnosticsPesterInstallCommandContext'
        $getPesterInstallTempDirectoryScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Get-GuiDeveloperDiagnosticsTempDirectory'
        $openLatestReportScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Open-GuiDeveloperDiagnosticsLatestReport'
        $copyCommandsScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Copy-GuiDeveloperDiagnosticsCommands'
        $stopProcessTreeScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Stop-GuiDeveloperDiagnosticsProcessTree'
        $setActionButtonsStateScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Set-GuiDeveloperDiagnosticsActionButtonsState'
        $setControlStateScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Set-GuiDeveloperDiagnosticsControlState'
        $updateLauncherAvailabilityViewScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Update-GuiDeveloperDiagnosticsLauncherAvailabilityView'
        $addOutputTextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Add-GuiDeveloperDiagnosticsOutputText'
        $addFileDeltaOutputScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Add-GuiDeveloperDiagnosticsFileDeltaOutput'
        $addPesterInstallFileDeltaOutputScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Add-GuiDeveloperDiagnosticsPesterInstallFileDeltaOutput'
        $getPesterInstallStatusTextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Get-GuiDeveloperDiagnosticsPesterInstallStatusText'
        $readTextFileScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Read-GuiDeveloperDiagnosticsTextFile'
        $openPathScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Open-GuiDeveloperDiagnosticsPath'
        $getPesterStatusSummaryScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Get-GuiDeveloperDiagnosticsPesterStatusSummary'
        $formatPesterStatusTextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Format-GuiDeveloperDiagnosticsPesterStatusText'
        $testPesterStatusCheckDueScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Test-GuiDeveloperDiagnosticsPesterStatusCheckDue'
        $startPesterStatusCheckScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Start-GuiDeveloperDiagnosticsPesterStatusCheckProcess'
        $writePesterStatusCacheScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Write-GuiDeveloperDiagnosticsPesterStatusCache'
        $newPesterStatusFailureScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'New-GuiDeveloperDiagnosticsPesterStatusFailure'
        $testPesterMissingScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Test-GuiDeveloperDiagnosticsPesterMissing'
        $writeErrorScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Write-GuiDeveloperDiagnosticsError'

        $installProgressPanel = New-Object System.Windows.Controls.StackPanel
        $installProgressPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $installProgressPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $installProgressText = New-Object System.Windows.Controls.TextBlock
        $installProgressText.TextWrapping = 'Wrap'
        $installProgressText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
        $installProgressText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextSecondary -DefaultColor '#4B5563'
        [void]$installProgressPanel.Children.Add($installProgressText)
        $installProgressBar = New-Object System.Windows.Controls.ProgressBar
        $installProgressBar.Height = 8
        $installProgressBar.Minimum = 0
        $installProgressBar.Maximum = 1
        $installProgressBar.Value = 0
        $installProgressBar.IsIndeterminate = $false
        $installProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
        $installProgressBar.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.AccentBlue -DefaultColor '#2563EB'
        $installProgressBar.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.BorderColor -DefaultColor '#D1D5DB'
        [void]$installProgressPanel.Children.Add($installProgressBar)
        [void]$content.Children.Add($installProgressPanel)

        $installTrustExpander = New-Object System.Windows.Controls.Expander
        $installTrustExpander.Header = 'About the Pester install'
        $installTrustExpander.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $installTrustExpander.Visibility = [System.Windows.Visibility]::Collapsed
        $installTrustText = New-Object System.Windows.Controls.TextBlock
        $installTrustText.TextWrapping = 'Wrap'
        $installTrustText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextSecondary -DefaultColor '#4B5563'
        $installTrustText.Text = 'Developer Diagnostics installs Pester from the official PowerShell Gallery in a separate Windows PowerShell process. Pester is installed outside the GUI process so diagnostics cannot interfere with the running Baseline session.'
        $installTrustExpander.Content = $installTrustText
        [void]$content.Children.Add($installTrustExpander)

        $installOutputBox = New-Object System.Windows.Controls.TextBox
        $installOutputBox.IsReadOnly = $true
        $installOutputBox.AcceptsReturn = $true
        $installOutputBox.VerticalScrollBarVisibility = 'Auto'
        $installOutputBox.HorizontalScrollBarVisibility = 'Auto'
        $installOutputBox.TextWrapping = 'NoWrap'
        $installOutputBox.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $installOutputBox.FontSize = 12
        $installOutputBox.Height = 160
        $installOutputBox.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
        $installOutputBox.Padding = [System.Windows.Thickness]::new(10)
        $installOutputBox.Visibility = [System.Windows.Visibility]::Collapsed
        $installOutputBox.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.WindowBg -DefaultColor '#FFFFFF'
        $installOutputBox.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
        [void]$content.Children.Add($installOutputBox)

        $installCommandBox = New-Object System.Windows.Controls.TextBox
        $installCommandBox.IsReadOnly = $true
        $installCommandBox.AcceptsReturn = $true
        $installCommandBox.VerticalScrollBarVisibility = 'Auto'
        $installCommandBox.HorizontalScrollBarVisibility = 'Auto'
        $installCommandBox.TextWrapping = 'NoWrap'
        $installCommandBox.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $installCommandBox.FontSize = 12
        $installCommandBox.Height = 70
        $installCommandBox.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
        $installCommandBox.Padding = [System.Windows.Thickness]::new(10)
        $installCommandBox.Visibility = [System.Windows.Visibility]::Collapsed
        $installCommandBox.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.WindowBg -DefaultColor '#FFFFFF'
        $installCommandBox.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
        [void]$content.Children.Add($installCommandBox)

        $pesterMissing = & $testPesterMissingScript -Availability $availability
        $pesterStatusSummary = & $getPesterStatusSummaryScript
        $pesterStatusPanel = New-Object System.Windows.Controls.StackPanel
        $pesterStatusPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
        $pesterStatusTitle = New-Object System.Windows.Controls.TextBlock
        $pesterStatusTitle.Text = 'Pester Status'
        $pesterStatusTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
        $pesterStatusTitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
        $pesterStatusTitle.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
        [void]$pesterStatusPanel.Children.Add($pesterStatusTitle)
        $pesterStatusText = New-Object System.Windows.Controls.TextBlock
        $pesterStatusText.TextWrapping = 'Wrap'
        $pesterStatusText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextSecondary -DefaultColor '#4B5563'
        $pesterStatusText.Text = (& $formatPesterStatusTextScript -Summary $pesterStatusSummary)
        [void]$pesterStatusPanel.Children.Add($pesterStatusText)

        $pesterStatusButtonPanel = New-Object System.Windows.Controls.WrapPanel
        $pesterStatusButtonPanel.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
        $checkPesterStatusButton = New-Object System.Windows.Controls.Button
        $checkPesterStatusButton.Content = 'Check Now'
        $checkPesterStatusButton.MinWidth = 100
        $checkPesterStatusButton.Height = 32
        $checkPesterStatusButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $checkPesterStatusButton.ToolTip = 'Check the latest stable Pester 5.x version from PowerShell Gallery.'
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $checkPesterStatusButton -Variant 'Secondary'
        }
        [void]$pesterStatusButtonPanel.Children.Add($checkPesterStatusButton)

        $updatePesterButton = New-Object System.Windows.Controls.Button
        $updatePesterButton.Content = 'Update Pester'
        $updatePesterButton.MinWidth = 116
        $updatePesterButton.Height = 32
        $updatePesterButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $updatePesterButton.Visibility = if ((-not $pesterMissing) -and [bool]$pesterStatusSummary.UpdateAvailable) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $updatePesterButton.ToolTip = 'Install the latest stable Pester 5.x version from PowerShell Gallery.'
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $updatePesterButton -Variant 'Primary'
        }
        [void]$pesterStatusButtonPanel.Children.Add($updatePesterButton)
        [void]$pesterStatusPanel.Children.Add($pesterStatusButtonPanel)
        [void]$content.Children.Add($pesterStatusPanel)

        $windowForActionButtons = $window
        $startDiagnosticsActionForButtons = $startDiagnosticsActionScript

        $actionButtons = @()
        $actionButtons += (Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Generate Test Report' -Enabled ([bool]$availability.Enabled) -ToolTip $tooltip -Click ({
            $windowForActionButtons.Close()
            & $startDiagnosticsActionForButtons -Action 'ExportReport'
        }.GetNewClosure()))
        $actionButtons += (Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Run Source Quality Guards' -Enabled ([bool]$availability.Enabled) -ToolTip $tooltip -Click ({
            $windowForActionButtons.Close()
            & $startDiagnosticsActionForButtons -Action 'SourceQuality'
        }.GetNewClosure()))
        $actionButtons += (Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Run Unit Tests' -Enabled ([bool]$availability.Enabled) -ToolTip $tooltip -Click ({
            $windowForActionButtons.Close()
            & $startDiagnosticsActionForButtons -Action 'Unit'
        }.GetNewClosure()))
        $actionButtons += (Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Run GUI Composition Tests' -Enabled ([bool]$availability.Enabled) -ToolTip $tooltip -Click ({
            $windowForActionButtons.Close()
            & $startDiagnosticsActionForButtons -Action 'GuiComposition'
        }.GetNewClosure()))

        $reportTooltip = if ($latestReport) { [string]$latestReport.FullName } else { 'Generate a test report first.' }
        $openLatestReportForClick = $openLatestReportScript
        $openLatestReportButton = Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Open Latest Test Report' -Enabled ($null -ne $latestReport) -ToolTip $reportTooltip -Click ({
            & $openLatestReportForClick
        }.GetNewClosure())
        $copyCommandsForClick = $copyCommandsScript
        $statusTextForCopyCommands = $statusText
        $copyCommandsButton = Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Copy PowerShell Commands' -Enabled ([bool]$availability.ShowMenu) -ToolTip 'Copy the external PowerShell commands for manual execution.' -Click ({
            & $copyCommandsForClick
            $statusTextForCopyCommands.Text = 'PowerShell commands copied.'
        }.GetNewClosure())

        $integrationFlag = Join-Path $availability.RepoRoot '.baseline-enable-integration-diagnostics'
        $integrationVisible = (Test-Path -LiteralPath $integrationFlag -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $availability.TestsDir 'Integration') -PathType Container)
        if ($integrationVisible)
        {
            $actionButtons += (Add-GuiDeveloperDiagnosticsLauncherButton -Panel $content -Text 'Run Integration Tests...' -Enabled ([bool]$availability.Enabled) -ToolTip 'VM only. Modifies registry, services, and packages. Recommended only in disposable VMs.' -Click ({
                $windowForActionButtons.Close()
                & $startDiagnosticsActionForButtons -Action 'Integration'
            }.GetNewClosure()))
        }

        $pesterInstallState = @{
            Process = $null
            Timer = $null
            StdoutPath = ''
            StderrPath = ''
            LogPath = ''
            CommandContext = $null
            CommandText = ''
            OutputPosition = [int64]0
            ErrorPosition = [int64]0
            Completed = $true
            StartTime = $null
            LastOutputTime = $null
            CurrentStep = 'Ready'
            TimeoutSeconds = [int]600
            CancelRequested = $false
            TimedOut = $false
        }
        if ($pesterMissing)
        {
            foreach ($actionButton in @($actionButtons))
            {
                if ($actionButton)
                {
                    $actionButton.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }
        }

        $pesterStatusCheckState = @{
            Process = $null
            Timer = $null
            ResultPath = ''
            StdoutPath = ''
            StderrPath = ''
            StartedAt = $null
            Running = $false
            TimeoutSeconds = [int]$Script:GuiDeveloperDiagnosticsPesterStatusCheckTimeoutSeconds
        }
        $pesterStatusTextForRender = $pesterStatusText
        $updatePesterButtonForRender = $updatePesterButton
        $checkPesterStatusButtonForRender = $checkPesterStatusButton
        $getPesterStatusSummaryForRender = $getPesterStatusSummaryScript
        $formatPesterStatusTextForRender = $formatPesterStatusTextScript
        $pesterStatusCheckStateForRender = $pesterStatusCheckState
        $pesterMissingForRender = $pesterMissing
        $renderPesterStatus = {
            param([string]$ActivityText)

            $summary = & $getPesterStatusSummaryForRender
            $pesterStatusTextForRender.Text = (& $formatPesterStatusTextForRender -Summary $summary -ActivityText $ActivityText)
            $updatePesterButtonForRender.Visibility = if ((-not [bool]$pesterMissingForRender) -and [bool]$summary.UpdateAvailable) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
            $updatePesterButtonForRender.IsEnabled = (-not [bool]$pesterStatusCheckStateForRender.Running -and -not [bool]$Script:GuiDeveloperDiagnosticsPesterInstallOpen)
            $checkPesterStatusButtonForRender.IsEnabled = (-not [bool]$pesterStatusCheckStateForRender.Running -and -not [bool]$Script:GuiDeveloperDiagnosticsPesterInstallOpen)
        }.GetNewClosure()

        $beginPesterStatusCheck = {
            param([bool]$Manual)

            if ([bool]$pesterStatusCheckState.Running)
            {
                return
            }

            $pesterStatusCheckState.Running = $true
            $pesterStatusCheckState.StartedAt = Get-Date
            $pesterStatusCheckState.Process = $null
            $pesterStatusCheckState.Timer = $null
            $checkPesterStatusButton.IsEnabled = $false
            $updatePesterButton.IsEnabled = $false
            & $renderPesterStatus -ActivityText 'Checking PSGallery in background...'

            $tempDirectory = & $getPesterInstallTempDirectoryScript
            $checkTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
            $resultPath = Join-Path $tempDirectory ('PesterStatus_{0}.json' -f $checkTimestamp)
            $stdoutPath = Join-Path $tempDirectory ('PesterStatus_{0}.out.log' -f $checkTimestamp)
            $stderrPath = Join-Path $tempDirectory ('PesterStatus_{0}.err.log' -f $checkTimestamp)
            $pesterStatusCheckState.ResultPath = $resultPath
            $pesterStatusCheckState.StdoutPath = $stdoutPath
            $pesterStatusCheckState.StderrPath = $stderrPath

            try
            {
                $process = & $startPesterStatusCheckScript -ResultPath $resultPath -StdoutPath $stdoutPath -StderrPath $stderrPath
                $pesterStatusCheckState.Process = $process
            }
            catch
            {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2158' -Severity Debug }

                $pesterStatusCheckState.Running = $false
                $failureStatus = & $newPesterStatusFailureScript -ErrorMessage $_.Exception.Message
                & $writePesterStatusCacheScript -Status $failureStatus
                & $renderPesterStatus -ActivityText ''
                return
            }

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            $pesterStatusCheckState.Timer = $timer
            $pesterStatusCheckStateForTimer = $pesterStatusCheckState
            $writePesterStatusCacheForTimer = $writePesterStatusCacheScript
            $newPesterStatusFailureForTimer = $newPesterStatusFailureScript
            $readTextFileForTimer = $readTextFileScript
            $renderPesterStatusForTimer = $renderPesterStatus
            $stopProcessTreeForStatusTimer = $stopProcessTreeScript
            $timer.Add_Tick({
                $elapsedSeconds = [int]([DateTime]::Now - [datetime]$pesterStatusCheckStateForTimer.StartedAt).TotalSeconds
                if ($pesterStatusCheckStateForTimer.Process -and -not $pesterStatusCheckStateForTimer.Process.HasExited -and $elapsedSeconds -ge [int]$pesterStatusCheckStateForTimer.TimeoutSeconds)
                {
                    $timer.Stop()
                    & $stopProcessTreeForStatusTimer -Process $pesterStatusCheckStateForTimer.Process
                    $failureStatus = & $newPesterStatusFailureForTimer -ErrorMessage ('Pester status check timed out after {0} seconds.' -f [int]$pesterStatusCheckStateForTimer.TimeoutSeconds)
                    & $writePesterStatusCacheForTimer -Status $failureStatus
                    $pesterStatusCheckStateForTimer.Running = $false
                    & $renderPesterStatusForTimer -ActivityText ''
                    return
                }

                if ($pesterStatusCheckStateForTimer.Process -and $pesterStatusCheckStateForTimer.Process.HasExited)
                {
                    $timer.Stop()
                    try { $pesterStatusCheckStateForTimer.Process.WaitForExit() } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2192' -Severity Debug }
                     $null = $_ }
                    $resultText = & $readTextFileForTimer -Path ([string]$pesterStatusCheckStateForTimer.ResultPath)
                    try
                    {
                        if ([string]::IsNullOrWhiteSpace($resultText))
                        {
                            throw 'Pester status check did not produce a result.'
                        }
                        $statusResult = $resultText | ConvertFrom-Json
                    }
                    catch
                    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2202' -Severity Debug }

                        $stderrText = & $readTextFileForTimer -Path ([string]$pesterStatusCheckStateForTimer.StderrPath)
                        $message = if ([string]::IsNullOrWhiteSpace($stderrText)) { $_.Exception.Message } else { $stderrText.Trim() }
                        $statusResult = & $newPesterStatusFailureForTimer -ErrorMessage $message
                    }

                    & $writePesterStatusCacheForTimer -Status $statusResult
                    $pesterStatusCheckStateForTimer.Running = $false
                    & $renderPesterStatusForTimer -ActivityText ''
                }
            }.GetNewClosure())
            $timer.Start()
        }.GetNewClosure()

        $statusTextForPesterInstall = $statusText
        $installProgressPanelForPesterInstall = $installProgressPanel
        $installProgressTextForPesterInstall = $installProgressText
        $installProgressBarForPesterInstall = $installProgressBar
        $installOutputBoxForPesterInstall = $installOutputBox
        $installCommandBoxForPesterInstall = $installCommandBox
        $installTrustExpanderForPesterInstall = $installTrustExpander

        $beginPesterInstall = {
            if ([bool]$Script:GuiDeveloperDiagnosticsPesterInstallOpen)
            {
                return
            }

            $Script:GuiDeveloperDiagnosticsPesterInstallOpen = $true
            if ([bool]$pesterStatusCheckState.Running)
            {
                if ($pesterStatusCheckState.Timer)
                {
                    try { $pesterStatusCheckState.Timer.Stop() } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2236' -Severity Debug }
                     $null = $_ }
                }
                if ($pesterStatusCheckState.Process -and -not $pesterStatusCheckState.Process.HasExited)
                {
                    & $stopProcessTreeScript -Process $pesterStatusCheckState.Process
                }
                $pesterStatusCheckState.Running = $false
            }
            $pesterInstallState.Completed = $false
            $pesterInstallState.StartTime = Get-Date
            $pesterInstallState.LastOutputTime = $null
            $pesterInstallState.CurrentStep = 'Starting'
            $pesterInstallState.CancelRequested = $false
            $pesterInstallState.TimedOut = $false
            $pesterInstallState.OutputPosition = [int64]0
            $pesterInstallState.ErrorPosition = [int64]0
            & $setActionButtonsStateScript -Buttons $actionButtons -Enabled $false -ToolTipText 'Installing supported Pester 5.x...'
            & $setControlStateScript -Control $copyCommandsButton -Enabled $false -ToolTip 'Installing supported Pester 5.x...'
            & $setControlStateScript -Control $installPesterButton -Enabled $false -ToolTip 'Installing supported Pester 5.x...'
            & $setControlStateScript -Control $updatePesterButton -Enabled $false -ToolTip 'Installing supported Pester 5.x...'
            & $setControlStateScript -Control $checkPesterStatusButton -Enabled $false -ToolTip 'Pester install is running.'
            & $setControlStateScript -Control $openPesterLogButton -Enabled $false -ToolTip 'Pester install log is not available yet.'
            & $setControlStateScript -Control $copyPesterLogButton -Enabled $false -ToolTip 'Pester install log is not available yet.'
            $cancelPesterInstallButton.Visibility = [System.Windows.Visibility]::Visible
            $statusTextForPesterInstall.Text = 'Installing supported Pester 5.x in an external PowerShell process...'
            $installProgressPanelForPesterInstall.Visibility = [System.Windows.Visibility]::Visible
            $installTrustExpanderForPesterInstall.Visibility = [System.Windows.Visibility]::Visible
            $installProgressTextForPesterInstall.Text = (& $getPesterInstallStatusTextScript -State $pesterInstallState)
            $installProgressBarForPesterInstall.Visibility = [System.Windows.Visibility]::Visible
            $installProgressBarForPesterInstall.Maximum = 1
            $installProgressBarForPesterInstall.Value = 0
            $installProgressBarForPesterInstall.IsIndeterminate = $true
            $installOutputBoxForPesterInstall.Visibility = [System.Windows.Visibility]::Visible
            $installOutputBoxForPesterInstall.Text = ''

            $tempDirectory = & $getPesterInstallTempDirectoryScript
            $installTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
            $stdoutPath = Join-Path $tempDirectory ('PesterInstall_{0}.out.log' -f $installTimestamp)
            $stderrPath = Join-Path $tempDirectory ('PesterInstall_{0}.err.log' -f $installTimestamp)
            $combinedLogPath = Join-Path $tempDirectory ('PesterInstall_{0}.log' -f $installTimestamp)
            $pesterInstallState.StdoutPath = $stdoutPath
            $pesterInstallState.StderrPath = $stderrPath
            $pesterInstallState.LogPath = $combinedLogPath
            [System.IO.File]::WriteAllText($combinedLogPath, '', [System.Text.Encoding]::UTF8)
            & $setControlStateScript -Control $openPesterLogButton -Enabled $true -ToolTip $combinedLogPath
            & $setControlStateScript -Control $copyPesterLogButton -Enabled $true -ToolTip 'Copy the Pester install log.'

            try
            {
                if (-not $pesterInstallState.CommandContext -or [string]::IsNullOrWhiteSpace([string]$pesterInstallState.CommandContext.ScriptPath) -or -not (Test-Path -LiteralPath ([string]$pesterInstallState.CommandContext.ScriptPath) -PathType Leaf))
                {
                    $pesterInstallState.CommandContext = & $newPesterInstallCommandContextScript
                }
                $pesterInstallState.CommandText = [string]$pesterInstallState.CommandContext.CommandText
                if ($installCommandBoxForPesterInstall.Visibility -eq [System.Windows.Visibility]::Visible)
                {
                    $installCommandBoxForPesterInstall.Text = [string]$pesterInstallState.CommandText
                }

                $process = & $startPesterInstallScript -StdoutPath $stdoutPath -StderrPath $stderrPath -CommandContext $pesterInstallState.CommandContext
                $pesterInstallState.Process = $process
                $pesterInstallState.CurrentStep = 'Checking PSGallery'
                $pesterInstallState.LastOutputTime = Get-Date
                $startMessage = ("PowerShell command:`r`n{0}`r`nStarted Pester installer process PID {1}.`r`n" -f [string]$pesterInstallState.CommandText, $process.Id)
                [System.IO.File]::AppendAllText($combinedLogPath, $startMessage, [System.Text.Encoding]::UTF8)
                $installProgressTextForPesterInstall.Text = (& $getPesterInstallStatusTextScript -State $pesterInstallState)
                & $addOutputTextScript -TextBox $installOutputBoxForPesterInstall -Text $startMessage -Reveal
            }
            catch
            {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2304' -Severity Debug }

                $Script:GuiDeveloperDiagnosticsPesterInstallOpen = $false
                $pesterInstallState.Completed = $true
                $pesterInstallState.CurrentStep = 'Failed'
                $statusTextForPesterInstall.Text = ('Could not start Pester installation: {0}' -f $_.Exception.Message)
                $installProgressTextForPesterInstall.Text = 'Pester installer process could not be started.'
                $installProgressBarForPesterInstall.IsIndeterminate = $false
                $installProgressBarForPesterInstall.Value = 0
                if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallState.LogPath))
                {
                    [System.IO.File]::AppendAllText([string]$pesterInstallState.LogPath, ("Failed to start Pester installation: {0}`r`n" -f $_.Exception.Message), [System.Text.Encoding]::UTF8)
                }
                & $addOutputTextScript -TextBox $installOutputBoxForPesterInstall -Text ("Failed to start Pester installation: {0}`r`n" -f $_.Exception.Message) -Reveal
                [void](& $updateLauncherAvailabilityViewScript -ActionButtons $actionButtons -OpenLatestReportButton $openLatestReportButton -CopyCommandsButton $copyCommandsButton)
                & $setControlStateScript -Control $installPesterButton -Enabled $true -ToolTip 'Install supported Pester 5.x.'
                & $renderPesterStatus -ActivityText ''
                $cancelPesterInstallButton.Visibility = [System.Windows.Visibility]::Collapsed
                return
            }

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(400)
            $pesterInstallState.Timer = $timer
            $pesterInstallStateForTimer = $pesterInstallState
            $addPesterInstallFileDeltaOutputForTimer = $addPesterInstallFileDeltaOutputScript
            $getPesterInstallStatusTextForTimer = $getPesterInstallStatusTextScript
            $updateLauncherAvailabilityViewForTimer = $updateLauncherAvailabilityViewScript
            $testPesterMissingForTimer = $testPesterMissingScript
            $addOutputTextForTimer = $addOutputTextScript
            $actionButtonsForTimer = $actionButtons
            $openLatestReportButtonForTimer = $openLatestReportButton
            $copyCommandsButtonForTimer = $copyCommandsButton
            $writeErrorForTimer = $writeErrorScript
            $installPesterButtonForTimer = $installPesterButton
            $cancelPesterInstallButtonForTimer = $cancelPesterInstallButton
            $setControlStateForTimer = $setControlStateScript
            $stopProcessTreeForTimer = $stopProcessTreeScript
            $readTextFileForTimer = $readTextFileScript
            $renderPesterStatusForInstallTimer = $renderPesterStatus
            $statusTextForTimer = $statusTextForPesterInstall
            $installProgressTextForTimer = $installProgressTextForPesterInstall
            $installProgressBarForTimer = $installProgressBarForPesterInstall
            $installOutputBoxForTimer = $installOutputBoxForPesterInstall
            $timer.Add_Tick({
                & $addPesterInstallFileDeltaOutputForTimer -TextBox $installOutputBoxForTimer -Path $stdoutPath -State $pesterInstallStateForTimer -Key 'OutputPosition' -Reveal
                & $addPesterInstallFileDeltaOutputForTimer -TextBox $installOutputBoxForTimer -Path $stderrPath -State $pesterInstallStateForTimer -Key 'ErrorPosition' -Reveal

                if (-not [bool]$pesterInstallStateForTimer.Completed)
                {
                    $elapsedSeconds = [int]([DateTime]::Now - [datetime]$pesterInstallStateForTimer.StartTime).TotalSeconds
                    $installProgressTextForTimer.Text = (& $getPesterInstallStatusTextForTimer -State $pesterInstallStateForTimer)
                    if ($pesterInstallStateForTimer.Process -and -not $pesterInstallStateForTimer.Process.HasExited -and $elapsedSeconds -ge [int]$pesterInstallStateForTimer.TimeoutSeconds)
                    {
                        $timer.Stop()
                        $timeoutMinutes = [int]([math]::Ceiling(([double]$pesterInstallStateForTimer.TimeoutSeconds) / 60))
                        $timeoutMessage = ('Pester installation timed out after {0} minutes.' -f $timeoutMinutes)
                        $timeoutCleanupMessage = 'Installer process tree was stopped after timeout.'
                        $timeoutDisplayMessage = ($timeoutMessage + "`r`n" + $timeoutCleanupMessage)
                        $pesterInstallStateForTimer.TimedOut = $true
                        $pesterInstallStateForTimer.Completed = $true
                        $pesterInstallStateForTimer.CurrentStep = 'Timed out'
                        $Script:GuiDeveloperDiagnosticsPesterInstallOpen = $false
                        & $stopProcessTreeForTimer -Process $pesterInstallStateForTimer.Process
                        $installProgressBarForTimer.IsIndeterminate = $false
                        $installProgressBarForTimer.Value = 0
                        $statusTextForTimer.Text = ($timeoutMessage + ' ' + $timeoutCleanupMessage)
                        $installProgressTextForTimer.Text = $timeoutDisplayMessage
                        & $writeErrorForTimer -Message ($timeoutMessage + ' ' + $timeoutCleanupMessage)
                        if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForTimer.LogPath))
                        {
                            [System.IO.File]::AppendAllText([string]$pesterInstallStateForTimer.LogPath, ($timeoutDisplayMessage + "`r`n"), [System.Text.Encoding]::UTF8)
                        }
                        & $addOutputTextForTimer -TextBox $installOutputBoxForTimer -Text ($timeoutDisplayMessage + "`r`n") -Reveal
                        & $setControlStateForTimer -Control $installPesterButtonForTimer -Enabled $true -ToolTip 'Retry the Pester install.'
                        $cancelPesterInstallButtonForTimer.Visibility = [System.Windows.Visibility]::Collapsed
                        & $renderPesterStatusForInstallTimer -ActivityText ''
                        return
                    }
                }

                if ($pesterInstallStateForTimer.Process -and $pesterInstallStateForTimer.Process.HasExited)
                {
                    $timer.Stop()
                    try { $pesterInstallStateForTimer.Process.WaitForExit() } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2388' -Severity Debug }
                     $null = $_ }
                    & $addPesterInstallFileDeltaOutputForTimer -TextBox $installOutputBoxForTimer -Path $stdoutPath -State $pesterInstallStateForTimer -Key 'OutputPosition' -Reveal
                    & $addPesterInstallFileDeltaOutputForTimer -TextBox $installOutputBoxForTimer -Path $stderrPath -State $pesterInstallStateForTimer -Key 'ErrorPosition' -Reveal

                    $exitCode = [int]$pesterInstallStateForTimer.Process.ExitCode
                    $pesterInstallLogText = & $readTextFileForTimer -Path ([string]$pesterInstallStateForTimer.LogPath)
                    $powerShellGetBootstrapFailed = (
                        $exitCode -eq 43 -or
                        $pesterInstallLogText -match 'PowerShellGet/PackageManagement automatic installation failed:' -or
                        $pesterInstallLogText -match 'PowerShellGet/PackageManagement automatic installation completed, but required command\(s\) are still missing:'
                    )
                    $Script:GuiDeveloperDiagnosticsPesterInstallOpen = $false
                    $pesterInstallStateForTimer.Completed = $true
                    $installProgressBarForTimer.IsIndeterminate = $false
                    $installProgressBarForTimer.Value = 1
                    $cancelPesterInstallButtonForTimer.Visibility = [System.Windows.Visibility]::Collapsed
                    $refreshedAvailability = & $updateLauncherAvailabilityViewForTimer -ActionButtons $actionButtonsForTimer -OpenLatestReportButton $openLatestReportButtonForTimer -CopyCommandsButton $copyCommandsButtonForTimer

                    if ($exitCode -eq 0 -and -not (& $testPesterMissingForTimer -Availability $refreshedAvailability))
                    {
                        $pesterInstallStateForTimer.CurrentStep = 'Ready'
                        $statusTextForTimer.Text = 'Supported Pester 5.x is installed. Choose a validation action.'
                        $installProgressTextForTimer.Text = 'Pester installation completed successfully.'
                        $installPesterButtonForTimer.Visibility = [System.Windows.Visibility]::Collapsed
                        foreach ($actionButton in @($actionButtonsForTimer))
                        {
                            if ($actionButton)
                            {
                                $actionButton.Visibility = [System.Windows.Visibility]::Visible
                            }
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForTimer.LogPath))
                        {
                            [System.IO.File]::AppendAllText([string]$pesterInstallStateForTimer.LogPath, "Pester installation completed successfully.`r`n", [System.Text.Encoding]::UTF8)
                        }
                        & $addOutputTextForTimer -TextBox $installOutputBoxForTimer -Text "Pester installation completed successfully.`r`n" -Reveal
                        & $renderPesterStatusForInstallTimer -ActivityText ''
                    }
                    elseif ($exitCode -eq 42)
                    {
                        $pesterInstallStateForTimer.CurrentStep = 'Failed'
                        $statusTextForTimer.Text = 'PowerShell Gallery is not reachable. Connect to the internet and reopen Developer Diagnostics.'
                        $installProgressTextForTimer.Text = 'Pester installation stopped because PowerShell Gallery is not reachable.'
                        & $setControlStateForTimer -Control $installPesterButtonForTimer -Enabled $true -ToolTip 'Retry the Pester install after network access is available.'
                        if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForTimer.LogPath))
                        {
                            [System.IO.File]::AppendAllText([string]$pesterInstallStateForTimer.LogPath, "Pester installation stopped because PowerShell Gallery is not reachable.`r`n", [System.Text.Encoding]::UTF8)
                        }
                        & $addOutputTextForTimer -TextBox $installOutputBoxForTimer -Text "Pester installation stopped because PowerShell Gallery is not reachable.`r`n" -Reveal
                        & $renderPesterStatusForInstallTimer -ActivityText ''
                    }
                    elseif ($powerShellGetBootstrapFailed)
                    {
                        $pesterInstallStateForTimer.CurrentStep = 'Failed'
                        $powerShellGetMessage = 'Pester installation stopped because PowerShellGet/PackageManagement could not be installed automatically. Open the install log for the exact bootstrap error, then retry.'
                        $statusTextForTimer.Text = $powerShellGetMessage
                        $installProgressTextForTimer.Text = $powerShellGetMessage
                        & $writeErrorForTimer -Message $powerShellGetMessage
                        & $setControlStateForTimer -Control $installPesterButtonForTimer -Enabled $true -ToolTip 'Retry the automatic PowerShellGet/PackageManagement bootstrap.'
                        if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForTimer.LogPath))
                        {
                            [System.IO.File]::AppendAllText([string]$pesterInstallStateForTimer.LogPath, ($powerShellGetMessage + "`r`n"), [System.Text.Encoding]::UTF8)
                        }
                        & $addOutputTextForTimer -TextBox $installOutputBoxForTimer -Text ($powerShellGetMessage + "`r`n") -Reveal
                        & $renderPesterStatusForInstallTimer -ActivityText ''
                    }
                    else
                    {
                        $pesterInstallStateForTimer.CurrentStep = 'Failed'
                        $failureMessage = if ($exitCode -lt 0)
                        {
                            ('Pester installation process was stopped before completion. Exit code: {0}.' -f $exitCode)
                        }
                        else
                        {
                            ('Pester installation did not complete successfully. Exit code: {0}.' -f $exitCode)
                        }

                        $statusTextForTimer.Text = $failureMessage
                        $installProgressTextForTimer.Text = $failureMessage
                        & $writeErrorForTimer -Message $failureMessage
                        & $setControlStateForTimer -Control $installPesterButtonForTimer -Enabled $true -ToolTip 'Retry the Pester install.'
                        if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForTimer.LogPath))
                        {
                            [System.IO.File]::AppendAllText([string]$pesterInstallStateForTimer.LogPath, ($failureMessage + "`r`n"), [System.Text.Encoding]::UTF8)
                        }
                        & $addOutputTextForTimer -TextBox $installOutputBoxForTimer -Text ($failureMessage + "`r`n") -Reveal
                        & $renderPesterStatusForInstallTimer -ActivityText ''
                    }
                }
            }.GetNewClosure())

            $timer.Start()
        }

        $checkPesterStatusButton.Add_Click({ & $beginPesterStatusCheck -Manual $true }.GetNewClosure())
        $updatePesterButton.Add_Click($beginPesterInstall.GetNewClosure())

        if (& $testPesterStatusCheckDueScript -Summary $pesterStatusSummary)
        {
            & $beginPesterStatusCheck -Manual $false
        }

        if ($pesterMissing)
        {
            $installProgressPanel.Visibility = [System.Windows.Visibility]::Visible
            $installTrustExpander.Visibility = [System.Windows.Visibility]::Visible
            $installProgressText.Text = 'Supported Pester 5.x 5.5.0 or newer is required. Install Pester to enable diagnostics, or close this dialog.'
            $installProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
            $installProgressBar.IsIndeterminate = $false
            $installProgressBar.Value = 0
        }

        $footer = New-Object System.Windows.Controls.Border
        $footer.Padding = [System.Windows.Thickness]::new(18, 12, 18, 12)
        $footer.BorderBrush = New-GuiDeveloperDiagnosticsBrush -Color $theme.BorderColor -DefaultColor '#D1D5DB'
        $footer.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
        $footer.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.PanelBg -DefaultColor '#F4F4F5'
        $footerPanel = New-Object System.Windows.Controls.WrapPanel
        $footerPanel.HorizontalAlignment = 'Right'

        $viewPesterCommandButton = New-Object System.Windows.Controls.Button
        $viewPesterCommandButton.Content = 'View Command'
        $viewPesterCommandButton.MinWidth = 116
        $viewPesterCommandButton.Height = 32
        $viewPesterCommandButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $viewPesterCommandButton.ToolTip = 'Show the Windows PowerShell command used for the Pester install or update.'
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $viewPesterCommandButton -Variant 'Secondary'
        }
        [void]$footerPanel.Children.Add($viewPesterCommandButton)

        $openPesterLogButton = New-Object System.Windows.Controls.Button
        $openPesterLogButton.Content = 'Open Log'
        $openPesterLogButton.MinWidth = 92
        $openPesterLogButton.Height = 32
        $openPesterLogButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $openPesterLogButton.Visibility = if ($pesterMissing) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $openPesterLogButton.ToolTip = 'Pester install log is not available yet.'
        $openPesterLogButton.IsEnabled = $false
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $openPesterLogButton -Variant 'Secondary'
        }
        [void]$footerPanel.Children.Add($openPesterLogButton)

        $copyPesterLogButton = New-Object System.Windows.Controls.Button
        $copyPesterLogButton.Content = 'Copy Log'
        $copyPesterLogButton.MinWidth = 92
        $copyPesterLogButton.Height = 32
        $copyPesterLogButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $copyPesterLogButton.Visibility = if ($pesterMissing) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $copyPesterLogButton.ToolTip = 'Pester install log is not available yet.'
        $copyPesterLogButton.IsEnabled = $false
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $copyPesterLogButton -Variant 'Secondary'
        }
        [void]$footerPanel.Children.Add($copyPesterLogButton)

        $reportFolderPath = Get-GuiDeveloperDiagnosticsArtifactsDirectory
        $openReportFolderButton = New-Object System.Windows.Controls.Button
        $openReportFolderButton.Content = 'Open Report Folder'
        $openReportFolderButton.MinWidth = 142
        $openReportFolderButton.Height = 32
        $openReportFolderButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $openReportFolderButton.ToolTip = if (Test-Path -LiteralPath $reportFolderPath -PathType Container) { $reportFolderPath } else { 'No report folder exists yet.' }
        $openReportFolderButton.IsEnabled = (Test-Path -LiteralPath $reportFolderPath -PathType Container)
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $openReportFolderButton -Variant 'Secondary'
        }
        [void]$footerPanel.Children.Add($openReportFolderButton)

        $installPesterButton = New-Object System.Windows.Controls.Button
        $installPesterButton.Content = 'Install Pester'
        $installPesterButton.MinWidth = 132
        $installPesterButton.Height = 32
        $installPesterButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $installPesterButton.Visibility = if ($pesterMissing) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $installPesterButton.ToolTip = 'Install the latest stable Pester 5.x from the official PowerShell Gallery.'
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $installPesterButton -Variant 'Primary'
        }
        [void]$footerPanel.Children.Add($installPesterButton)

        $cancelPesterInstallButton = New-Object System.Windows.Controls.Button
        $cancelPesterInstallButton.Content = 'Cancel'
        $cancelPesterInstallButton.MinWidth = 100
        $cancelPesterInstallButton.Height = 32
        $cancelPesterInstallButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
        $cancelPesterInstallButton.Visibility = [System.Windows.Visibility]::Collapsed
        $cancelPesterInstallButton.ToolTip = 'Stop the external Pester installer process.'
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Set-GuiButtonChrome -Button $cancelPesterInstallButton -Variant 'Secondary'
        }
        [void]$footerPanel.Children.Add($cancelPesterInstallButton)
        $installPesterButton.Add_Click($beginPesterInstall.GetNewClosure())

        $closeButton = New-Object System.Windows.Controls.Button
        $closeButton.Content = 'Close'
        $closeButton.MinWidth = 100
        $closeButton.Height = 32
        $closeButton.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
        if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
        {
            $closeButtonVariant = if ($pesterMissing) { 'Secondary' } else { 'Primary' }
            Set-GuiButtonChrome -Button $closeButton -Variant $closeButtonVariant
        }
        $closeButton.Add_Click({ $window.Close() }.GetNewClosure())
        [void]$footerPanel.Children.Add($closeButton)

        $openPathForFooter = $openPathScript
        $readTextFileForFooter = $readTextFileScript
        $pesterInstallStateForFooter = $pesterInstallState
        $statusTextForFooter = $statusText
        $reportFolderPathForFooter = $reportFolderPath
        $newPesterInstallCommandContextForFooter = $newPesterInstallCommandContextScript
        $installCommandBoxForFooter = $installCommandBox
        $viewPesterCommandButton.Add_Click({
            try
            {
                if (-not $pesterInstallStateForFooter.CommandContext -or [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForFooter.CommandContext.ScriptPath) -or -not (Test-Path -LiteralPath ([string]$pesterInstallStateForFooter.CommandContext.ScriptPath) -PathType Leaf))
                {
                    $pesterInstallStateForFooter.CommandContext = & $newPesterInstallCommandContextForFooter
                }

                $pesterInstallStateForFooter.CommandText = [string]$pesterInstallStateForFooter.CommandContext.CommandText
                $installCommandBoxForFooter.Text = [string]$pesterInstallStateForFooter.CommandText
                $installCommandBoxForFooter.Visibility = [System.Windows.Visibility]::Visible
                $statusTextForFooter.Text = 'Pester install command is shown below.'
            }
            catch
            {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2623' -Severity Debug }

                $statusTextForFooter.Text = ('Could not prepare the Pester install command: {0}' -f $_.Exception.Message)
            }
        }.GetNewClosure())

        $openPesterLogButton.Add_Click({
            $logPath = [string]$pesterInstallStateForFooter.LogPath
            if (-not (& $openPathForFooter -Path $logPath))
            {
                $statusTextForFooter.Text = 'No Pester install log is available yet.'
            }
        }.GetNewClosure())

        $copyPesterLogButton.Add_Click({
            $logPath = [string]$pesterInstallStateForFooter.LogPath
            $logText = & $readTextFileForFooter -Path $logPath
            if ([string]::IsNullOrEmpty($logText))
            {
                $statusTextForFooter.Text = 'No Pester install log is available yet.'
                return
            }

            [System.Windows.Clipboard]::SetText($logText)
            $statusTextForFooter.Text = 'Pester install log copied.'
        }.GetNewClosure())

        $openReportFolderButton.Add_Click({
            if (-not (& $openPathForFooter -Path $reportFolderPathForFooter))
            {
                $statusTextForFooter.Text = 'No report folder exists yet.'
            }
        }.GetNewClosure())

        $pesterInstallStateForCancel = $pesterInstallState
        $stopProcessTreeForCancel = $stopProcessTreeScript
        $setControlStateForCancel = $setControlStateScript
        $updateLauncherAvailabilityViewForCancel = $updateLauncherAvailabilityViewScript
        $addOutputTextForCancel = $addOutputTextScript
        $addPesterInstallFileDeltaOutputForCancel = $addPesterInstallFileDeltaOutputScript
        $statusTextForCancel = $statusText
        $installProgressTextForCancel = $installProgressText
        $installProgressBarForCancel = $installProgressBar
        $installOutputBoxForCancel = $installOutputBox
        $installPesterButtonForCancel = $installPesterButton
        $cancelPesterInstallButtonForCancel = $cancelPesterInstallButton
        $actionButtonsForCancel = $actionButtons
        $openLatestReportButtonForCancel = $openLatestReportButton
        $copyCommandsButtonForCancel = $copyCommandsButton
        $renderPesterStatusForCancel = $renderPesterStatus
        $cancelPesterInstallButton.Add_Click({
            if ([bool]$pesterInstallStateForCancel.Completed)
            {
                return
            }

            $stopMessage = 'Stopping installer process tree...'
            $cancelMessage = 'Installation canceled safely.'
            if ($pesterInstallStateForCancel.Timer)
            {
                try { $pesterInstallStateForCancel.Timer.Stop() } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2683' -Severity Debug }
                 $null = $_ }
            }

            $statusTextForCancel.Text = $stopMessage
            $installProgressTextForCancel.Text = $stopMessage
            $cancelPesterInstallButtonForCancel.IsEnabled = $false
            if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForCancel.LogPath))
            {
                [System.IO.File]::AppendAllText([string]$pesterInstallStateForCancel.LogPath, ($stopMessage + "`r`n"), [System.Text.Encoding]::UTF8)
            }
            & $addOutputTextForCancel -TextBox $installOutputBoxForCancel -Text ($stopMessage + "`r`n") -Reveal

            & $addPesterInstallFileDeltaOutputForCancel -TextBox $installOutputBoxForCancel -Path ([string]$pesterInstallStateForCancel.StdoutPath) -State $pesterInstallStateForCancel -Key 'OutputPosition' -Reveal
            & $addPesterInstallFileDeltaOutputForCancel -TextBox $installOutputBoxForCancel -Path ([string]$pesterInstallStateForCancel.StderrPath) -State $pesterInstallStateForCancel -Key 'ErrorPosition' -Reveal
            if ($pesterInstallStateForCancel.Process -and -not $pesterInstallStateForCancel.Process.HasExited)
            {
                & $stopProcessTreeForCancel -Process $pesterInstallStateForCancel.Process
            }

            $Script:GuiDeveloperDiagnosticsPesterInstallOpen = $false
            $pesterInstallStateForCancel.CancelRequested = $true
            $pesterInstallStateForCancel.Completed = $true
            $pesterInstallStateForCancel.CurrentStep = 'Canceled'
            $installProgressBarForCancel.IsIndeterminate = $false
            $installProgressBarForCancel.Value = 0
            $statusTextForCancel.Text = $cancelMessage
            $installProgressTextForCancel.Text = $cancelMessage
            if (-not [string]::IsNullOrWhiteSpace([string]$pesterInstallStateForCancel.LogPath))
            {
                [System.IO.File]::AppendAllText([string]$pesterInstallStateForCancel.LogPath, ($cancelMessage + "`r`n"), [System.Text.Encoding]::UTF8)
            }
            & $addOutputTextForCancel -TextBox $installOutputBoxForCancel -Text ($cancelMessage + "`r`n") -Reveal
            [void](& $updateLauncherAvailabilityViewForCancel -ActionButtons $actionButtonsForCancel -OpenLatestReportButton $openLatestReportButtonForCancel -CopyCommandsButton $copyCommandsButtonForCancel)
            & $setControlStateForCancel -Control $installPesterButtonForCancel -Enabled $true -ToolTip 'Retry the Pester install.'
            $cancelPesterInstallButtonForCancel.Visibility = [System.Windows.Visibility]::Collapsed
            $cancelPesterInstallButtonForCancel.IsEnabled = $true
            & $renderPesterStatusForCancel -ActivityText ''
        }.GetNewClosure())

        $footer.Child = $footerPanel
        [System.Windows.Controls.Grid]::SetRow($footer, 2)
        [void]$root.Children.Add($footer)

        $window.Content = $root
        $stopPesterProcessTree = $stopProcessTreeScript
        $pesterInstallStateForClose = $pesterInstallState
        $pesterStatusCheckStateForClose = $pesterStatusCheckState
        $writeErrorForClose = $writeErrorScript
        $window.Add_Closed({
            try
            {
                if ($pesterStatusCheckStateForClose.Timer)
                {
                    $pesterStatusCheckStateForClose.Timer.Stop()
                }
                if ($pesterInstallStateForClose.Timer)
                {
                    $pesterInstallStateForClose.Timer.Stop()
                }
            }
            catch
            {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Show-GuiDeveloperDiagnosticsLauncher:catch2743' -Severity Debug }

                $null = $_
            }

            if (-not [bool]$pesterInstallStateForClose.Completed -and $pesterInstallStateForClose.Process -and -not $pesterInstallStateForClose.Process.HasExited)
            {
                & $writeErrorForClose -Message ('Pester installation process was stopped before completion because the Developer Diagnostics window closed. PID: {0}.' -f $pesterInstallStateForClose.Process.Id)
                & $stopPesterProcessTree -Process $pesterInstallStateForClose.Process
            }

            if ($pesterStatusCheckStateForClose.Process -and -not $pesterStatusCheckStateForClose.Process.HasExited)
            {
                & $stopPesterProcessTree -Process $pesterStatusCheckStateForClose.Process
            }

            $Script:GuiDeveloperDiagnosticsPesterInstallOpen = $false
        }.GetNewClosure())

        [void]$window.ShowDialog()
    }
    finally
    {
        $Script:GuiDeveloperDiagnosticsLauncherOpen = $false
    }
}

function Open-GuiDeveloperDiagnosticsLauncherFromMenu
{
    Update-GuiDeveloperDiagnosticsMenuState
    try
    {
        if ($Script:MenuToolsDeveloperDiagnostics)
        {
            $Script:MenuToolsDeveloperDiagnostics.IsSubmenuOpen = $false
        }
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Open-GuiDeveloperDiagnosticsLauncherFromMenu:catch2780' -Severity Debug }

        $null = $_
    }

    Show-GuiDeveloperDiagnosticsLauncher
}

function Read-GuiDeveloperDiagnosticsFileDelta
{
    param(
        [string]$Path,
        [hashtable]$State,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path))
    {
        return ''
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        return ''
    }

    $position = if ($State.ContainsKey($Key)) { [int64]$State[$Key] } else { [int64]0 }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try
    {
        if ($stream.Length -le $position)
        {
            return ''
        }

        [void]$stream.Seek($position, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::Default, $true)
        try
        {
            $text = $reader.ReadToEnd()
            $State[$Key] = [int64]$stream.Length
            return $text
        }
        finally
        {
            $reader.Dispose()
        }
    }
    finally
    {
        $stream.Dispose()
    }
}

function Stop-GuiDeveloperDiagnosticsProcessTree
{
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) { return }
    if ($Process.HasExited) { return }

    if (Get-Command -Name 'Stop-BaselineProcessTree' -CommandType Function -ErrorAction SilentlyContinue)
    {
        Stop-BaselineProcessTree -Process $Process -Source 'GuiDeveloperDiagnostics.Cancel'
        return
    }

    $taskKill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskKill -PathType Leaf)
    {
        & $taskKill /PID $Process.Id /T /F | Out-Null
        return
    }

    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
}

function Get-GuiDeveloperDiagnosticsReportSummary
{
    param(
        [string]$ReportPath,
        [int]$ExitCode
    )

    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf))
    {
        return ("Completed with exit code {0}. Report was not created." -f $ExitCode)
    }

    try
    {
        $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
        if ($report.summary)
        {
            return ("Passed: {0} | Failed: {1} | Skipped: {2} | Result: {3} | Report: {4}" -f $report.summary.totalPassed, $report.summary.totalFailed, $report.summary.totalSkipped, $report.summary.overallResult, $ReportPath)
        }
    }
    catch
    {
        if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.ReportSummary'
        }
    }

    return ("Completed with exit code {0}. Report: {1}" -f $ExitCode, $ReportPath)
}

function New-GuiDeveloperDiagnosticsBrush
{
    param(
        [string]$Color,
        [string]$DefaultColor
    )

    $value = if ([string]::IsNullOrWhiteSpace([string]$Color)) { $DefaultColor } else { $Color }
    try
    {
        $converter = if ($Script:SharedBrushConverter) { $Script:SharedBrushConverter } else { [System.Windows.Media.BrushConverter]::new() }
        return $converter.ConvertFromString($value)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.New-GuiDeveloperDiagnosticsBrush:catch2901' -Severity Debug }

        $converter = [System.Windows.Media.BrushConverter]::new()
        return $converter.ConvertFromString($DefaultColor)
    }
}

function Start-GuiDeveloperDiagnosticsAction
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ExportReport', 'SourceQuality', 'Unit', 'GuiComposition', 'Integration')]
        [string]$Action
    )

    Update-GuiDeveloperDiagnosticsMenuState
    $availability = Get-GuiDeveloperDiagnosticsAvailability
    if (-not $availability.Enabled)
    {
        [void](Show-ThemedDialog -Title 'Developer Diagnostics' -Message ($availability.Reasons -join [Environment]::NewLine) -Buttons @('OK') -AccentButton 'OK')
        return
    }

    $reportPath = Get-GuiDeveloperDiagnosticsReportPath
    $reportDir = Split-Path -Path $reportPath -Parent
    $stdoutPath = Join-Path $reportDir ('Diagnostics_{0}.out.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $stderrPath = Join-Path $reportDir ('Diagnostics_{0}.err.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $actionLabels = @{
        ExportReport = 'Generate Test Report'
        SourceQuality = 'Run Source Quality Guards'
        Unit = 'Run Unit Tests'
        GuiComposition = 'Run GUI Composition Tests'
        Integration = 'Run Integration Tests'
    }
    $actionLabel = [string]$actionLabels[$Action]

    $theme = if ($Script:CurrentTheme) { $Script:CurrentTheme } else { @{ WindowBg = '#FFFFFF'; PanelBg = '#F4F4F5'; BorderColor = '#D1D5DB'; TextPrimary = '#111827'; TextSecondary = '#4B5563' } }
    $window = New-Object System.Windows.Window
    $window.Title = ('Developer Diagnostics - {0}' -f $actionLabel)
    $window.Width = 900
    $window.Height = 620
    $window.MinWidth = 720
    $window.MinHeight = 420
    $window.WindowStartupLocation = 'CenterOwner'
    $window.ResizeMode = 'CanResizeWithGrip'
    $window.ShowInTaskbar = $false
    $window.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.WindowBg -DefaultColor '#FFFFFF'
    $window.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
    try { if ($Script:MainForm) { $window.Owner = $Script:MainForm } } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Start-GuiDeveloperDiagnosticsAction:catch2949' -Severity Debug }
     $null = $_ }

    $root = New-Object System.Windows.Controls.Grid
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))

    $header = New-Object System.Windows.Controls.Border
    $header.Padding = [System.Windows.Thickness]::new(16, 14, 16, 12)
    $header.BorderBrush = New-GuiDeveloperDiagnosticsBrush -Color $theme.BorderColor -DefaultColor '#D1D5DB'
    $header.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $header.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.PanelBg -DefaultColor '#F4F4F5'
    $headerStack = New-Object System.Windows.Controls.StackPanel
    $titleText = New-Object System.Windows.Controls.TextBlock
    $titleText.Text = $actionLabel
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
    [void]$headerStack.Children.Add($titleText)
    $statusText = New-Object System.Windows.Controls.TextBlock
    $statusText.Text = 'Starting external diagnostics process...'
    $statusText.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
    $statusText.TextWrapping = 'Wrap'
    $statusText.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextSecondary -DefaultColor '#4B5563'
    [void]$headerStack.Children.Add($statusText)
    $header.Child = $headerStack
    [System.Windows.Controls.Grid]::SetRow($header, 0)
    [void]$root.Children.Add($header)

    $outputBox = New-Object System.Windows.Controls.TextBox
    $outputBox.IsReadOnly = $true
    $outputBox.AcceptsReturn = $true
    $outputBox.AcceptsTab = $true
    $outputBox.VerticalScrollBarVisibility = 'Auto'
    $outputBox.HorizontalScrollBarVisibility = 'Auto'
    $outputBox.TextWrapping = 'NoWrap'
    $outputBox.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $outputBox.FontSize = 12
    $outputBox.Padding = [System.Windows.Thickness]::new(12)
    $outputBox.BorderThickness = [System.Windows.Thickness]::new(0)
    $outputBox.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.WindowBg -DefaultColor '#FFFFFF'
    $outputBox.Foreground = New-GuiDeveloperDiagnosticsBrush -Color $theme.TextPrimary -DefaultColor '#111827'
    [System.Windows.Controls.Grid]::SetRow($outputBox, 1)
    [void]$root.Children.Add($outputBox)

    $footer = New-Object System.Windows.Controls.Border
    $footer.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
    $footer.BorderBrush = New-GuiDeveloperDiagnosticsBrush -Color $theme.BorderColor -DefaultColor '#D1D5DB'
    $footer.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
    $footer.Background = New-GuiDeveloperDiagnosticsBrush -Color $theme.PanelBg -DefaultColor '#F4F4F5'
    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'

    $openReportButton = New-Object System.Windows.Controls.Button
    $openReportButton.Content = 'Open Report'
    $openReportButton.MinWidth = 110
    $openReportButton.Height = 32
    $openReportButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $openReportButton.IsEnabled = $false
    if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue) { Set-GuiButtonChrome -Button $openReportButton -Variant 'Secondary' }
    [void]$buttonPanel.Children.Add($openReportButton)

    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $cancelButton.MinWidth = 100
    $cancelButton.Height = 32
    if (Get-Command -Name 'Set-GuiButtonChrome' -CommandType Function -ErrorAction SilentlyContinue) { Set-GuiButtonChrome -Button $cancelButton -Variant 'Primary' }
    [void]$buttonPanel.Children.Add($cancelButton)
    $footer.Child = $buttonPanel
    [System.Windows.Controls.Grid]::SetRow($footer, 2)
    [void]$root.Children.Add($footer)

    $window.Content = $root

    $stopProcessTreeScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Stop-GuiDeveloperDiagnosticsProcessTree'
    $addFileDeltaOutputScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Add-GuiDeveloperDiagnosticsFileDeltaOutput'
    $getReportSummaryScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Get-GuiDeveloperDiagnosticsReportSummary'
    $updateMenuStateScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Update-GuiDeveloperDiagnosticsMenuState'

    $state = @{ OutputPosition = [int64]0; ErrorPosition = [int64]0; Completed = $false; Process = $null }

    $diagnosticsStateForControls = $state
    $openReportButton.Add_Click({
        if (Test-Path -LiteralPath $reportPath -PathType Leaf)
        {
            Start-Process -FilePath $reportPath | Out-Null
        }
    }.GetNewClosure())

    $cancelButton.Add_Click({
        if (-not [bool]$diagnosticsStateForControls.Completed)
        {
            $statusText.Text = 'Cancelling diagnostics process...'
            & $stopProcessTreeScript -Process $diagnosticsStateForControls.Process
            $diagnosticsStateForControls.Completed = $true
            $cancelButton.Content = 'Close'
            return
        }
        $window.Close()
    }.GetNewClosure())

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $availability.RunnerPath, '-Action', $Action, '-OutputPath', $reportPath)
    if ($Action -eq 'Integration')
    {
        $arguments += '-AllowIntegration'
    }

    try
    {
        $process = Start-Process -FilePath (Get-GuiDeveloperDiagnosticsPowerShellPath) `
            -ArgumentList (Join-GuiDeveloperDiagnosticsArgumentList -Arguments $arguments) `
            -WorkingDirectory $availability.RepoRoot `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru
        $diagnosticsStateForControls.Process = $process
        $statusText.Text = ('Running in external process PID {0}...' -f $process.Id)
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Start-GuiDeveloperDiagnosticsAction:catch3069' -Severity Debug }

        $statusText.Text = ('Failed to start diagnostics: {0}' -f $_.Exception.Message)
        $cancelButton.Content = 'Close'
        $diagnosticsStateForControls.Completed = $true
        [void]$window.ShowDialog()
        return
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $diagnosticsStateForTimer = $state
    $addFileDeltaOutputForTimer = $addFileDeltaOutputScript
    $getReportSummaryForTimer = $getReportSummaryScript
    $updateMenuStateForTimer = $updateMenuStateScript
    $timer.Add_Tick({
        & $addFileDeltaOutputForTimer -TextBox $outputBox -Path $stdoutPath -State $diagnosticsStateForTimer -Key 'OutputPosition'
        & $addFileDeltaOutputForTimer -TextBox $outputBox -Path $stderrPath -State $diagnosticsStateForTimer -Key 'ErrorPosition'

        if ($diagnosticsStateForTimer.Process -and $diagnosticsStateForTimer.Process.HasExited)
        {
            $timer.Stop()
            try { $diagnosticsStateForTimer.Process.WaitForExit() } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Start-GuiDeveloperDiagnosticsAction:catch3091' -Severity Debug }
             $null = $_ }
            & $addFileDeltaOutputForTimer -TextBox $outputBox -Path $stdoutPath -State $diagnosticsStateForTimer -Key 'OutputPosition'
            & $addFileDeltaOutputForTimer -TextBox $outputBox -Path $stderrPath -State $diagnosticsStateForTimer -Key 'ErrorPosition'
            $exitCode = [int]$diagnosticsStateForTimer.Process.ExitCode
            $summary = & $getReportSummaryForTimer -ReportPath $reportPath -ExitCode $exitCode
            $statusText.Text = $summary
            $openReportButton.IsEnabled = (Test-Path -LiteralPath $reportPath -PathType Leaf)
            $cancelButton.Content = 'Close'
            $diagnosticsStateForTimer.Completed = $true
            & $updateMenuStateForTimer
        }
    }.GetNewClosure())

    $stopDiagnosticsProcessTree = $stopProcessTreeScript
    $diagnosticsStateForClose = $state
    $window.Add_Closed({
        try { $timer.Stop() } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Start-GuiDeveloperDiagnosticsAction:catch3107' -Severity Debug }
         $null = $_ }
        if ($diagnosticsStateForClose.Process -and -not $diagnosticsStateForClose.Process.HasExited)
        {
            & $stopDiagnosticsProcessTree -Process $diagnosticsStateForClose.Process
        }
    }.GetNewClosure())

    $timer.Start()
    [void]$window.ShowDialog()
}

function Open-GuiDeveloperDiagnosticsLatestReport
{
    $latestReport = Get-GuiDeveloperDiagnosticsLatestReport
    if (-not $latestReport)
    {
        [void](Show-ThemedDialog -Title 'Developer Diagnostics' -Message 'No GUI test report exists yet.' -Buttons @('OK') -AccentButton 'OK')
        return
    }

    Start-Process -FilePath $latestReport.FullName | Out-Null
}

function Copy-GuiDeveloperDiagnosticsCommands
{
    $commands = Get-GuiDeveloperDiagnosticsCommands
    [System.Windows.Clipboard]::SetText(($commands -join [Environment]::NewLine))
    if (Get-Command -Name 'Set-GuiStatusText' -CommandType Function -ErrorAction SilentlyContinue)
    {
        Set-GuiStatusText -Text 'Developer diagnostics commands copied.' -Tone 'accent'
    }
}

function Initialize-GuiDeveloperDiagnosticsMenu
{
    $updateMenuStateScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Update-GuiDeveloperDiagnosticsMenuState'
    $openLauncherFromMenuScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Open-GuiDeveloperDiagnosticsLauncherFromMenu'
    $startActionScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Start-GuiDeveloperDiagnosticsAction'
    $openLatestReportScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Open-GuiDeveloperDiagnosticsLatestReport'
    $copyCommandsScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name 'Copy-GuiDeveloperDiagnosticsCommands'

    if ($Script:MenuTools)
    {
        Register-GuiEventHandler -Source $Script:MenuTools -EventName 'SubmenuOpened' -Handler ({ & $updateMenuStateScript }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnostics)
    {
        $openDeveloperDiagnosticsLauncher = {
            param($sender, $eventArgs)
            try
            {
                if ($eventArgs -and ($eventArgs.PSObject.Properties.Name -contains 'Handled'))
                {
                    $eventArgs.Handled = $true
                }
            }
            catch
            {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Initialize-GuiDeveloperDiagnosticsMenu:catch3163' -Severity Debug }

                $null = $_
            }
            & $openLauncherFromMenuScript
        }.GetNewClosure()

        $openDeveloperDiagnosticsLauncherFromKeyboard = {
            param($sender, $eventArgs)
            if ($eventArgs -and (($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) -or ($eventArgs.Key -eq [System.Windows.Input.Key]::Space)))
            {
                try { $eventArgs.Handled = $true } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeveloperDiagnostics.Initialize-GuiDeveloperDiagnosticsMenu:catch3174' -Severity Debug }
                 $null = $_ }
                & $openLauncherFromMenuScript
            }
        }.GetNewClosure()

        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnostics -EventName 'Click' -Handler $openDeveloperDiagnosticsLauncher | Out-Null
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnostics -EventName 'PreviewMouseLeftButtonUp' -Handler $openDeveloperDiagnosticsLauncher | Out-Null
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnostics -EventName 'KeyUp' -Handler $openDeveloperDiagnosticsLauncherFromKeyboard | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsGenerateReport)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsGenerateReport -EventName 'Click' -Handler ({ & $startActionScript -Action 'ExportReport' }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsSourceQuality)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsSourceQuality -EventName 'Click' -Handler ({ & $startActionScript -Action 'SourceQuality' }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsUnitTests)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsUnitTests -EventName 'Click' -Handler ({ & $startActionScript -Action 'Unit' }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsGuiComposition)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsGuiComposition -EventName 'Click' -Handler ({ & $startActionScript -Action 'GuiComposition' }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsOpenLatestReport)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsOpenLatestReport -EventName 'Click' -Handler ({ & $openLatestReportScript }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsCopyCommands)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsCopyCommands -EventName 'Click' -Handler ({ & $copyCommandsScript }.GetNewClosure()) | Out-Null
    }
    if ($Script:MenuToolsDeveloperDiagnosticsIntegrationTests)
    {
        Register-GuiEventHandler -Source $Script:MenuToolsDeveloperDiagnosticsIntegrationTests -EventName 'Click' -Handler ({ & $startActionScript -Action 'Integration' }.GetNewClosure()) | Out-Null
    }

    & $updateMenuStateScript
}
