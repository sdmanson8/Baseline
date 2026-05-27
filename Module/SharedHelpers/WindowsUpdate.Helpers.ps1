<#
    .SYNOPSIS
    Windows Update Agent helper functions for Baseline runtime update operations.
#>

function New-BaselineWindowsUpdateSession
{
    [CmdletBinding()]
    param ()

    try
    {
        return New-Object -ComObject 'Microsoft.Update.Session'
    }
    catch
    {
        throw "Could not create Microsoft.Update.Session: $($_.Exception.Message)"
    }
}

function New-BaselineWindowsUpdateCollection
{
    [CmdletBinding()]
    param (
        [scriptblock]$CollectionFactory
    )

    if ($CollectionFactory)
    {
        return & $CollectionFactory
    }

    try
    {
        return New-Object -ComObject 'Microsoft.Update.UpdateColl'
    }
    catch
    {
        throw "Could not create Microsoft.Update.UpdateColl: $($_.Exception.Message)"
    }
}

function Get-BaselineObjectPropertyValue
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$Required
    )

    if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name))
    {
        return $InputObject[$Name]
    }

    $matchedProperty = $null
    try
    {
        $matchedProperties = @($InputObject.PSObject.Properties.Match($Name))
        if ($matchedProperties.Count -gt 0)
        {
            $matchedProperty = $matchedProperties[0]
        }
    }
    catch
    {
        if ($Required)
        {
            throw "Could not inspect property '$Name': $($_.Exception.Message)"
        }
    }

    if ($matchedProperty)
    {
        try
        {
            return $matchedProperty.Value
        }
        catch
        {
            throw "Could not read property '$Name': $($_.Exception.Message)"
        }
    }

    try
    {
        return $InputObject.$Name
    }
    catch
    {
        if ($Required -or ($_.Exception -is [System.Runtime.InteropServices.COMException]))
        {
            throw "Could not read property '$Name': $($_.Exception.Message)"
        }
    }

    return $null
}

function Get-BaselineIndexedCollectionItems
{
    [CmdletBinding()]
    param (
        [object]$Collection,
        [string]$Label = 'collection'
    )

    if ($null -eq $Collection)
    {
        return @()
    }

    if ($Collection -is [string])
    {
        return @([string]$Collection)
    }

    $countValue = Get-BaselineObjectPropertyValue -InputObject $Collection -Name 'Count'
    if ($null -ne $countValue)
    {
        $items = New-Object 'System.Collections.Generic.List[object]'
        for ($index = 0; $index -lt [int]$countValue; $index++)
        {
            $item = $null
            $itemResolved = $false
            try
            {
                $item = $Collection.Item($index)
                $itemResolved = $true
            }
            catch
            {
                try
                {
                    $item = $Collection[$index]
                    $itemResolved = $true
                }
                catch
                {
                    throw ("Could not read {0} item at index {1}: {2}" -f $Label, $index, $_.Exception.Message)
                }
            }

            if ($itemResolved)
            {
                [void]$items.Add($item)
            }
        }

        return [object[]]$items.ToArray()
    }

    return @($Collection)
}

function ConvertTo-BaselineStringArray
{
    [CmdletBinding()]
    param (
        [object]$Value
    )

    $strings = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @(Get-BaselineIndexedCollectionItems -Collection $Value -Label 'string collection'))
    {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text))
        {
            [void]$strings.Add($text)
        }
    }

    return [string[]]$strings.ToArray()
}

function Get-BaselineWindowsUpdateCategories
{
    [CmdletBinding()]
    param (
        [object]$Update
    )

    $categoryCollection = Get-BaselineObjectPropertyValue -InputObject $Update -Name 'Categories'
    $categories = New-Object 'System.Collections.Generic.List[object]'
    foreach ($category in @(Get-BaselineIndexedCollectionItems -Collection $categoryCollection -Label 'update category collection'))
    {
        if ($null -eq $category) { continue }
        [void]$categories.Add([pscustomobject]@{
            Name       = [string](Get-BaselineObjectPropertyValue -InputObject $category -Name 'Name')
            CategoryId = [string](Get-BaselineObjectPropertyValue -InputObject $category -Name 'CategoryID')
            Type       = [string](Get-BaselineObjectPropertyValue -InputObject $category -Name 'Type')
        })
    }

    return [object[]]$categories.ToArray()
}

function Test-BaselineWindowsUpdateCategoryName
{
    [CmdletBinding()]
    param (
        [object[]]$Categories,
        [string]$Name
    )

    foreach ($category in @($Categories))
    {
        if ($category -and ([string]$category.Name).Equals($Name, [System.StringComparison]::OrdinalIgnoreCase))
        {
            return $true
        }
    }

    return $false
}

function Get-BaselineWindowsUpdateTypeName
{
    [CmdletBinding()]
    param (
        [object]$Type
    )

    if ($null -eq $Type)
    {
        return ''
    }

    switch ([string]$Type)
    {
        '1' { return 'Software' }
        '2' { return 'Driver' }
        default { return [string]$Type }
    }
}

function Get-BaselineWindowsUpdateClassification
{
    [CmdletBinding()]
    param (
        [string]$MsrcSeverity,
        [object[]]$Categories,
        [object]$Type
    )

    $typeName = Get-BaselineWindowsUpdateTypeName -Type $Type
    if ($typeName.Equals('Driver', [System.StringComparison]::OrdinalIgnoreCase) -or
        (Test-BaselineWindowsUpdateCategoryName -Categories $Categories -Name 'Drivers'))
    {
        return 'Drivers'
    }

    if (([string]$MsrcSeverity).Equals('Critical', [System.StringComparison]::OrdinalIgnoreCase) -or
        (Test-BaselineWindowsUpdateCategoryName -Categories $Categories -Name 'Critical Updates'))
    {
        return 'Critical'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$MsrcSeverity) -or
        (Test-BaselineWindowsUpdateCategoryName -Categories $Categories -Name 'Security Updates'))
    {
        return 'Security'
    }

    return 'Optional'
}

function ConvertTo-BaselineWindowsUpdateRecord
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Update
    )

    $identity = Get-BaselineObjectPropertyValue -InputObject $Update -Name 'Identity' -Required
    $type = Get-BaselineObjectPropertyValue -InputObject $Update -Name 'Type'
    $categories = @(Get-BaselineWindowsUpdateCategories -Update $Update)
    $msrcSeverity = [string](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'MsrcSeverity')

    return [pscustomobject]@{
        Id             = [string](Get-BaselineObjectPropertyValue -InputObject $identity -Name 'UpdateID' -Required)
        RevisionNumber = [int](Get-BaselineObjectPropertyValue -InputObject $identity -Name 'RevisionNumber' -Required)
        Title          = [string](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'Title' -Required)
        Description    = [string](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'Description')
        KBArticleIDs   = [string[]](ConvertTo-BaselineStringArray -Value (Get-BaselineObjectPropertyValue -InputObject $Update -Name 'KBArticleIDs'))
        MsrcSeverity   = $msrcSeverity
        Categories     = $categories
        Classification = Get-BaselineWindowsUpdateClassification -MsrcSeverity $msrcSeverity -Categories $categories -Type $type
        IsInstalled    = [bool](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'IsInstalled')
        IsHidden       = [bool](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'IsHidden')
        IsDownloaded   = [bool](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'IsDownloaded')
        Type           = Get-BaselineWindowsUpdateTypeName -Type $type
        RebootRequired = [bool](Get-BaselineObjectPropertyValue -InputObject $Update -Name 'RebootRequired')
        Update         = $Update
    }
}

function Get-BaselineWindowsUpdateResultName
{
    [CmdletBinding()]
    param (
        [object]$ResultCode
    )

    if ($null -eq $ResultCode)
    {
        return 'Unknown'
    }

    switch ([int]$ResultCode)
    {
        0 { return 'NotStarted' }
        1 { return 'InProgress' }
        2 { return 'Succeeded' }
        3 { return 'SucceededWithErrors' }
        4 { return 'Failed' }
        5 { return 'Aborted' }
        default { return 'Unknown' }
    }
}

function Get-BaselineWindowsUpdateHistoryOperationName
{
    [CmdletBinding()]
    param (
        [object]$Operation
    )

    if ($null -eq $Operation)
    {
        return 'Unknown'
    }

    switch ([int]$Operation)
    {
        1 { return 'Installation' }
        2 { return 'Uninstallation' }
        default { return 'Unknown' }
    }
}

function Resolve-BaselineWindowsUpdateObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    $rawUpdate = Get-BaselineObjectPropertyValue -InputObject $InputObject -Name 'Update'
    if ($null -ne $rawUpdate)
    {
        return $rawUpdate
    }

    return $InputObject
}

function Add-BaselineWindowsUpdatesToCollection
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Collection,

        [object[]]$Updates
    )

    $count = 0
    foreach ($update in @($Updates))
    {
        if ($null -eq $update) { continue }
        $rawUpdate = Resolve-BaselineWindowsUpdateObject -InputObject $update
        if ($null -eq $rawUpdate) { continue }
        try
        {
            [void]$Collection.Add($rawUpdate)
            $count++
        }
        catch
        {
            throw "Could not add Windows Update item to operation collection: $($_.Exception.Message)"
        }
    }

    return $count
}

function New-BaselineWindowsUpdateOperationResult
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [object]$Result,

        [int]$UpdateCount,

        [bool]$RebootRequired = $false
    )

    $resultCode = if ($null -eq $Result) { $null } else { Get-BaselineObjectPropertyValue -InputObject $Result -Name 'ResultCode' }
    $resultName = if ($null -eq $Result) { 'NoUpdates' } else { Get-BaselineWindowsUpdateResultName -ResultCode $resultCode }
    return [pscustomobject]@{
        Operation      = $Operation
        UpdateCount    = $UpdateCount
        ResultCode     = $resultCode
        Result         = $resultName
        Succeeded      = ($null -eq $Result -or ([int]$resultCode -eq 2))
        RebootRequired = $RebootRequired
    }
}

function Get-WindowsUpdateRestartRequired
{
    [CmdletBinding()]
    param (
        [object]$SystemInfo
    )

    if (-not $SystemInfo)
    {
        $SystemInfo = New-Object -ComObject 'Microsoft.Update.SystemInfo'
    }

    return [bool](Get-BaselineObjectPropertyValue -InputObject $SystemInfo -Name 'RebootRequired')
}

function New-BaselineWindowsUpdateProgressRecord
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [object]$Progress
    )

    $percentComplete = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'PercentComplete'
    if ($null -eq $percentComplete)
    {
        $percentComplete = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'CurrentUpdatePercentComplete'
    }

    return [pscustomobject]@{
        Operation                    = $Operation
        PercentComplete              = if ($null -eq $percentComplete) { $null } else { [int]$percentComplete }
        CurrentUpdateIndex           = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'CurrentUpdateIndex'
        CurrentUpdatePercentComplete = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'CurrentUpdatePercentComplete'
        CurrentUpdateBytesDownloaded = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'CurrentUpdateBytesDownloaded'
        CurrentUpdateBytesToDownload = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'CurrentUpdateBytesToDownload'
        TotalBytesDownloaded         = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'TotalBytesDownloaded'
        TotalBytesToDownload         = Get-BaselineObjectPropertyValue -InputObject $Progress -Name 'TotalBytesToDownload'
    }
}

function Invoke-BaselineWindowsUpdateProgressCallback
{
    [CmdletBinding()]
    param (
        [scriptblock]$ProgressCallback,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [object]$Progress
    )

    if (-not $ProgressCallback -or $null -eq $Progress)
    {
        return
    }

    $progressRecord = New-BaselineWindowsUpdateProgressRecord -Operation $Operation -Progress $Progress
    & $ProgressCallback -Progress $progressRecord
}

function Wait-BaselineWindowsUpdateAsyncJob
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Job,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [scriptblock]$ProgressCallback,

        [int]$ProgressPollMilliseconds = 500
    )

    while (-not [bool](Get-BaselineObjectPropertyValue -InputObject $Job -Name 'IsCompleted'))
    {
        Invoke-BaselineWindowsUpdateProgressCallback -ProgressCallback $ProgressCallback -Operation $Operation -Progress ($Job.GetProgress())
        if ($ProgressPollMilliseconds -gt 0)
        {
            Start-Sleep -Milliseconds $ProgressPollMilliseconds
        }
    }

    Invoke-BaselineWindowsUpdateProgressCallback -ProgressCallback $ProgressCallback -Operation $Operation -Progress ($Job.GetProgress())
}

function New-BaselineWindowsUpdateAsyncCallback
{
    [CmdletBinding()]
    param ()

    $callbackTypeName = 'Baseline.WindowsUpdateAsyncCallback'
    $callbackType = $callbackTypeName -as [type]
    if (-not $callbackType)
    {
        $callbackSource = @'
namespace Baseline
{
    using System;
    using System.Runtime.InteropServices;

    [ComVisible(true)]
    [Guid("0649B03E-F40B-4F7B-B4F7-A42F4409CBA0")]
    [InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
    public interface IWindowsUpdateAsyncCallback
    {
        [DispId(0)]
        void Invoke(object job, object callbackArgs);
    }

    [ComVisible(true)]
    [Guid("62705F98-C7D7-4862-8AB9-9D45085FE64D")]
    [ClassInterface(ClassInterfaceType.None)]
    public sealed class WindowsUpdateAsyncCallback : IWindowsUpdateAsyncCallback
    {
        public void Invoke(object job, object callbackArgs)
        {
        }
    }
}
'@

        try
        {
            Add-Type -TypeDefinition $callbackSource -Language CSharp -ErrorAction Stop
            $callbackType = $callbackTypeName -as [type]
        }
        catch
        {
            throw "Could not create Windows Update async callback type: $($_.Exception.Message)"
        }
    }

    return [System.Activator]::CreateInstance($callbackType)
}

function Get-BaselineWindowsUpdateScheduledResultPath
{
    [CmdletBinding()]
    param ()

    $basePath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Baseline'
    return (Join-Path -Path $basePath -ChildPath 'windows-update-scheduled-last-result.json')
}

function Get-BaselineWindowsUpdateSummary
{
    [CmdletBinding()]
    param (
        [object[]]$Updates = @()
    )

    $critical = @($Updates | Where-Object { [string]$_.Classification -eq 'Critical' })
    $security = @($Updates | Where-Object { [string]$_.Classification -eq 'Security' })
    $drivers = @($Updates | Where-Object { [string]$_.Classification -eq 'Drivers' })
    $optional = @($Updates | Where-Object { [string]$_.Classification -eq 'Optional' })

    return [pscustomobject]@{
        Total    = @($Updates).Count
        Critical = $critical.Count
        Security = $security.Count
        Drivers  = $drivers.Count
        Optional = $optional.Count
    }
}

function Select-WindowsSecurityUpdates
{
    [CmdletBinding()]
    param (
        [object[]]$Updates = @()
    )

    $selected = New-Object 'System.Collections.Generic.List[object]'
    foreach ($update in @($Updates))
    {
        if (-not $update) { continue }
        if ([string]$update.Classification -in @('Critical', 'Security'))
        {
            [void]$selected.Add($update)
        }
    }

    return [object[]]$selected.ToArray()
}

function Get-WindowsUpdateList
{
    [CmdletBinding()]
    param (
        [string]$Criteria = 'IsInstalled=0 and IsHidden=0',

        [object]$Session
    )

    if ([string]::IsNullOrWhiteSpace($Criteria))
    {
        throw 'Windows Update search criteria cannot be empty.'
    }

    if (-not $Session)
    {
        $Session = New-BaselineWindowsUpdateSession
    }

    $searcher = $null
    try
    {
        $searcher = $Session.CreateUpdateSearcher()
    }
    catch
    {
        throw "Could not create Windows Update searcher: $($_.Exception.Message)"
    }

    try
    {
        $searchResult = $searcher.Search($Criteria)
    }
    catch
    {
        throw "Windows Update search failed for criteria '$Criteria': $($_.Exception.Message)"
    }

    $updates = Get-BaselineObjectPropertyValue -InputObject $searchResult -Name 'Updates' -Required
    foreach ($update in @(Get-BaselineIndexedCollectionItems -Collection $updates -Label 'Windows Update search result collection'))
    {
        ConvertTo-BaselineWindowsUpdateRecord -Update $update
    }
}

function Install-WindowsSecurityUpdates
{
    [CmdletBinding()]
    param (
        [object]$Session,

        [scriptblock]$CollectionFactory,

        [object]$SystemInfo
    )

    if (-not $Session)
    {
        $Session = New-BaselineWindowsUpdateSession
    }

    $availableUpdates = @(Get-WindowsUpdateList -Session $Session)
    $securityUpdates = @(Select-WindowsSecurityUpdates -Updates $availableUpdates)
    $downloadResult = Download-WindowsUpdates -Updates $securityUpdates -Session $Session -CollectionFactory $CollectionFactory
    $installResult = $null
    if ([bool]$downloadResult.Succeeded)
    {
        $installResult = Install-WindowsUpdates -Updates $securityUpdates -Session $Session -CollectionFactory $CollectionFactory -SystemInfo $SystemInfo
    }

    return [pscustomobject]@{
        Schema         = 'Baseline.WindowsUpdateSecurityInstall'
        GeneratedAt    = [System.DateTime]::UtcNow.ToString('o')
        AvailableCount = $availableUpdates.Count
        SelectedCount  = $securityUpdates.Count
        Summary        = Get-BaselineWindowsUpdateSummary -Updates $availableUpdates
        SelectedTitles = @($securityUpdates | ForEach-Object { [string]$_.Title })
        DownloadResult = $downloadResult
        InstallResult  = $installResult
        RebootRequired = if ($installResult) { [bool]$installResult.RebootRequired } else { $false }
        Succeeded      = if ($installResult) { [bool]$installResult.Succeeded } else { [bool]$downloadResult.Succeeded }
    }
}

function Download-WindowsUpdates
{
    [CmdletBinding()]
    param (
        [object[]]$Updates = @(),

        [object]$Session,

        [scriptblock]$CollectionFactory,

        [scriptblock]$ProgressCallback,

        [ValidateRange(0, 60000)]
        [int]$ProgressPollMilliseconds = 500
    )

    if (-not $Session)
    {
        $Session = New-BaselineWindowsUpdateSession
    }

    $collection = New-BaselineWindowsUpdateCollection -CollectionFactory $CollectionFactory
    $updateCount = Add-BaselineWindowsUpdatesToCollection -Collection $collection -Updates $Updates
    if ($updateCount -eq 0)
    {
        return New-BaselineWindowsUpdateOperationResult -Operation 'Download' -UpdateCount 0
    }

    $downloader = $null
    try
    {
        $downloader = $Session.CreateUpdateDownloader()
        $downloader.Updates = $collection
        if ($ProgressCallback)
        {
            $downloadCallback = New-BaselineWindowsUpdateAsyncCallback
            $downloadJob = $downloader.BeginDownload($downloadCallback, $downloadCallback, 'Baseline.WindowsUpdate.Download')
            try
            {
                Wait-BaselineWindowsUpdateAsyncJob -Job $downloadJob -Operation 'Download' -ProgressCallback $ProgressCallback -ProgressPollMilliseconds $ProgressPollMilliseconds
                $downloadResult = $downloader.EndDownload($downloadJob)
            }
            finally
            {
                if ($downloadJob)
                {
                    $downloadJob.CleanUp()
                }
            }
        }
        else
        {
            $downloadResult = $downloader.Download()
        }
    }
    catch
    {
        throw "Windows Update download failed: $($_.Exception.Message)"
    }

    return New-BaselineWindowsUpdateOperationResult -Operation 'Download' -Result $downloadResult -UpdateCount $updateCount
}

function Install-WindowsUpdates
{
    [CmdletBinding()]
    param (
        [object[]]$Updates = @(),

        [object]$Session,

        [scriptblock]$CollectionFactory,

        [scriptblock]$ProgressCallback,

        [ValidateRange(0, 60000)]
        [int]$ProgressPollMilliseconds = 500,

        [object]$SystemInfo
    )

    if (-not $Session)
    {
        $Session = New-BaselineWindowsUpdateSession
    }

    $collection = New-BaselineWindowsUpdateCollection -CollectionFactory $CollectionFactory
    $updateCount = Add-BaselineWindowsUpdatesToCollection -Collection $collection -Updates $Updates
    if ($updateCount -eq 0)
    {
        return New-BaselineWindowsUpdateOperationResult -Operation 'Install' -UpdateCount 0
    }

    $installer = $null
    try
    {
        $installer = $Session.CreateUpdateInstaller()
        $installer.Updates = $collection
        if ($ProgressCallback)
        {
            $installCallback = New-BaselineWindowsUpdateAsyncCallback
            $installJob = $installer.BeginInstall($installCallback, $installCallback, 'Baseline.WindowsUpdate.Install')
            try
            {
                Wait-BaselineWindowsUpdateAsyncJob -Job $installJob -Operation 'Install' -ProgressCallback $ProgressCallback -ProgressPollMilliseconds $ProgressPollMilliseconds
                $installResult = $installer.EndInstall($installJob)
            }
            finally
            {
                if ($installJob)
                {
                    $installJob.CleanUp()
                }
            }
        }
        else
        {
            $installResult = $installer.Install()
        }
    }
    catch
    {
        throw "Windows Update install failed: $($_.Exception.Message)"
    }

    $installerRebootRequired = [bool](Get-BaselineObjectPropertyValue -InputObject $installer -Name 'RebootRequired')
    $systemRebootRequired = Get-WindowsUpdateRestartRequired -SystemInfo $SystemInfo
    $rebootRequired = ($installerRebootRequired -or $systemRebootRequired)
    return New-BaselineWindowsUpdateOperationResult -Operation 'Install' -Result $installResult -UpdateCount $updateCount -RebootRequired:$rebootRequired
}

function Get-WindowsUpdateStatus
{
    [CmdletBinding()]
    param (
        [object]$Session,

        [int]$HistoryCount = 10
    )

    try
    {
        if (-not $Session)
        {
            $Session = New-BaselineWindowsUpdateSession
        }

        $availableUpdates = @(Get-WindowsUpdateList -Session $Session)
        $history = @(Get-WindowsUpdateHistory -Session $Session -Count $HistoryCount)
        $scheduledResultPath = Get-BaselineWindowsUpdateScheduledResultPath
        $lastScheduledRun = $null
        if (-not [string]::IsNullOrWhiteSpace($scheduledResultPath) -and (Test-Path -LiteralPath $scheduledResultPath))
        {
            $lastScheduledRun = Get-Content -LiteralPath $scheduledResultPath -Raw -ErrorAction Stop | ConvertFrom-Json
        }

        return [pscustomobject]@{
            Schema           = 'Baseline.WindowsUpdateStatus'
            GeneratedAt      = [System.DateTime]::UtcNow.ToString('o')
            Succeeded        = $true
            Summary          = Get-BaselineWindowsUpdateSummary -Updates $availableUpdates
            AvailableUpdates = @($availableUpdates | ForEach-Object {
                [pscustomobject]@{
                    Id             = [string]$_.Id
                    RevisionNumber = [int]$_.RevisionNumber
                    Title          = [string]$_.Title
                    KBArticleIDs   = [string[]]$_.KBArticleIDs
                    MsrcSeverity   = [string]$_.MsrcSeverity
                    Classification = [string]$_.Classification
                    IsDownloaded   = [bool]$_.IsDownloaded
                    RebootRequired = [bool]$_.RebootRequired
                    Type           = [string]$_.Type
                }
            })
            RecentHistory    = @($history)
            LastScheduledRun = $lastScheduledRun
        }
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowsUpdate.Helpers.Get-WindowsUpdateStatus:catch876' -Severity Debug }

        return [pscustomobject]@{
            Schema      = 'Baseline.WindowsUpdateStatus'
            GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
            Succeeded   = $false
            Error       = $_.Exception.Message
        }
    }
}

function Get-WindowsUpdateCompliance
{
    [CmdletBinding()]
    param (
        [object]$Session
    )

    $status = Get-WindowsUpdateStatus -Session $Session
    if (-not [bool]$status.Succeeded)
    {
        return [pscustomobject]@{
            Schema         = 'Baseline.WindowsUpdateCompliance'
            GeneratedAt    = [System.DateTime]::UtcNow.ToString('o')
            Status         = 'Unknown'
            SecurityPending = $null
            CriticalPending = $null
            Error          = [string]$status.Error
            UpdateStatus   = $status
        }
    }

    $criticalPending = [int]$status.Summary.Critical
    $securityPending = [int]$status.Summary.Security
    return [pscustomobject]@{
        Schema          = 'Baseline.WindowsUpdateCompliance'
        GeneratedAt     = [System.DateTime]::UtcNow.ToString('o')
        Status          = if (($criticalPending + $securityPending) -gt 0) { 'NonCompliant' } else { 'Compliant' }
        SecurityPending = $securityPending
        CriticalPending = $criticalPending
        UpdateStatus    = $status
    }
}

function Invoke-BaselineWindowsUpdateScheduledRun
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param (
        [object]$Session,

        [scriptblock]$CollectionFactory
    )

    $scheduledRunFailure = $null
    try
    {
        $result = Install-WindowsSecurityUpdates -Session $Session -CollectionFactory $CollectionFactory
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowsUpdate.Helpers.Invoke-BaselineWindowsUpdateScheduledRun:catch935' -Severity Debug }

        $scheduledRunFailure = $_
        $result = [pscustomobject]@{
            Schema      = 'Baseline.WindowsUpdateSecurityInstall'
            GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
            Operation   = 'ScheduledSecurityInstall'
            Succeeded   = $false
            Error       = $_.Exception.Message
        }
    }

    $resultPath = Get-BaselineWindowsUpdateScheduledResultPath
    $resultDirectory = Split-Path -Path $resultPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($resultDirectory) -and -not (Test-Path -LiteralPath $resultDirectory))
    {
        New-Item -Path $resultDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 8), $utf8NoBom)

    if ($scheduledRunFailure)
    {
        throw "Baseline Windows Update scheduled run failed: $($scheduledRunFailure.Exception.Message)"
    }

    return $result
}

function Get-WindowsUpdateHistory
{
    [CmdletBinding()]
    param (
        [ValidateRange(1, 1000)]
        [int]$Count = 50,

        [object]$Session
    )

    if (-not $Session)
    {
        $Session = New-BaselineWindowsUpdateSession
    }

    $searcher = $null
    try
    {
        $searcher = $Session.CreateUpdateSearcher()
    }
    catch
    {
        throw "Could not create Windows Update searcher: $($_.Exception.Message)"
    }

    try
    {
        $totalCount = [int]$searcher.GetTotalHistoryCount()
    }
    catch
    {
        throw "Could not read Windows Update history count: $($_.Exception.Message)"
    }

    if ($totalCount -le 0)
    {
        return @()
    }

    $queryCount = [Math]::Min($Count, $totalCount)
    try
    {
        $historyEntries = $searcher.QueryHistory(0, $queryCount)
    }
    catch
    {
        throw "Could not query Windows Update history: $($_.Exception.Message)"
    }

    foreach ($entry in @(Get-BaselineIndexedCollectionItems -Collection $historyEntries -Label 'Windows Update history collection'))
    {
        $operation = Get-BaselineObjectPropertyValue -InputObject $entry -Name 'Operation'
        $resultCode = Get-BaselineObjectPropertyValue -InputObject $entry -Name 'ResultCode'
        [pscustomobject]@{
            Date          = Get-BaselineObjectPropertyValue -InputObject $entry -Name 'Date'
            Title         = [string](Get-BaselineObjectPropertyValue -InputObject $entry -Name 'Title')
            Description   = [string](Get-BaselineObjectPropertyValue -InputObject $entry -Name 'Description')
            Operation     = $operation
            OperationName = Get-BaselineWindowsUpdateHistoryOperationName -Operation $operation
            ResultCode    = $resultCode
            Result        = Get-BaselineWindowsUpdateResultName -ResultCode $resultCode
            HResult       = Get-BaselineObjectPropertyValue -InputObject $entry -Name 'HResult'
            SupportUrl    = [string](Get-BaselineObjectPropertyValue -InputObject $entry -Name 'SupportUrl')
        }
    }
}
