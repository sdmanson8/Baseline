Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $applicationsPath = Join-Path $PSScriptRoot '../../Module/Regions/Applications.psm1'
    $script:ApplicationsContent = Get-BaselineTestSourceText -Path $applicationsPath
    $applicationsAst = [System.Management.Automation.Language.Parser]::ParseFile($applicationsPath, [ref]$null, [ref]$null)
    $applicationsFunctions = $applicationsAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $applicationsFunctions)
    {
        Invoke-Expression $fn.Extent.Text
    }

    # Apps functions live in Module/GUI/AppsModule.ps1.
    # during Phase 2 decomposition. Parse both so tests find the definitions
    # regardless of which file they currently live in.
    $guiSourceFiles = @(
        (Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'),
        (Join-Path $PSScriptRoot '../../Module/GUI/AppsModule.ps1'),
        (Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/CatalogHelpers.ps1'),
        (Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/SelectionQueueState.ps1'),
        (Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/ProgressNavChrome.ps1')
    )
    $targetAppsFunctions = @(
        'Get-ApplicationEntityType',
        'Test-ApplicationExecutionSupport',
        'Get-ApplicationCatalogIdentityKey',
        'Get-ApplicationExecutionState',
        'Initialize-AppsSelectionState',
        'Update-AppsSelectionSummary',
        'Start-AppsModuleActionAsync',
        'Start-AppsModuleBatchActionAsync',
        'Initialize-AppsQueuedActionState'
    )
    foreach ($srcFile in $guiSourceFiles)
    {
        if (-not (Test-Path -LiteralPath $srcFile)) { continue }
        $srcAst = [System.Management.Automation.Language.Parser]::ParseFile($srcFile, [ref]$null, [ref]$null)
        $srcFunctions = $srcAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $srcFunctions)
        {
            if ($fn.Name -in $targetAppsFunctions)
            {
                Invoke-Expression $fn.Extent.Text
            }
        }
    }

    $appsViewPath = Join-Path $PSScriptRoot '../../Module/GUI/ApplicationsView.ps1'
    $appsViewAst = [System.Management.Automation.Language.Parser]::ParseFile($appsViewPath, [ref]$null, [ref]$null)
    $appsViewFunctions = $appsViewAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $appsViewFunctions)
    {
        Invoke-Expression $fn.Extent.Text
    }

    <#
        .SYNOPSIS
    #>

    function Get-BaselineLocalizedString {
        param (
            [string]$Key,
            [string]$Fallback,
            [object[]]$FormatArgs = @()
        )

        if ($FormatArgs.Count -gt 0)
        {
            return ($Fallback -f $FormatArgs)
        }

        return $Fallback
    }

    <#
        .SYNOPSIS
    #>

    function Get-UxLocalizedString {
        param (
            [string]$Key,
            [string]$Fallback,
            [object[]]$FormatArgs = @()
        )

        if ($FormatArgs.Count -gt 0)
        {
            return ($Fallback -f $FormatArgs)
        }

        return $Fallback
    }

    <#
        .SYNOPSIS
    #>

    function Get-GuiCurrentTheme {
        return $script:TestTheme
    }

    <#
        .SYNOPSIS
    #>
    function New-SafeBrushConverter {
        param (
            [string]$Context
        )

        $converter = [pscustomobject]@{}
        $null = $converter | Add-Member -MemberType ScriptMethod -Name ConvertFromString -Value {
            param([string]$Value)
            return $Value
        } -Force
        return $converter
    }

    <#
        .SYNOPSIS
    #>

    function Get-SelectedAppsCatalogItems {
        return @($script:SelectedAppsForSummary)
    }

    <#
        .SYNOPSIS
    #>
    function Resolve-WinGetExecutable {
        return 'winget.exe'
    }

    <#
        .SYNOPSIS
    #>
    function Resolve-ChocolateyExecutable {
        return 'choco.exe'
    }

    <#
        .SYNOPSIS
    #>
    function Resolve-ApplicationPackageId {
        param([string]$PackageId)
        return $PackageId
    }

    <#
        .SYNOPSIS
    #>

    function Test-WinGetAvailable {
        param (
            [switch]$Refresh
        )

        $null = $Refresh
        return [bool]$script:TestWinGetAvailable
    }

    <#
        .SYNOPSIS
    #>
    function Test-ChocolateyAvailable {
        param (
            [switch]$Refresh
        )

        $null = $Refresh
        return [bool]$script:TestChocolateyAvailable
    }

    <#
        .SYNOPSIS
    #>

    function Write-ConsoleStatus { param([object]$Action) }
    <#
        .SYNOPSIS
    #>
    function LogInfo { param([object]$Message) }
    <#
        .SYNOPSIS
    #>
    function LogWarning { param([object]$Message) }
    <#
        .SYNOPSIS
    #>
    function LogError { param([object]$Message) }

    <#
        .SYNOPSIS
    #>
    function Reset-ChocolateyAvailabilityState { }

    <#
        .SYNOPSIS
    #>
    function Invoke-ChocolateyBootstrap { param([int]$TimeoutSeconds) }

    $script:GuiModuleBasePath = $TestDrive
    $script:GuiLocalizationDirectoryPath = $TestDrive
    $script:SelectedLanguage = 'en'
    $Global:LogFilePath = Join-Path $TestDrive 'baseline.log'
    $env:TEMP = $TestDrive
    $env:TMP = $TestDrive

    <#
        .SYNOPSIS
    #>
    function Start-GuiAppExecutionRun {
        param (
            [string]$Action,
            [string]$LoaderPath,
            [string]$LocalizationDirectory,
            [string]$UICulture,
            [string]$LogFilePath,
            [string]$LogMode,
            [string]$WinGetId,
            [string]$ChocoId,
            [string]$DisplayName,
            [object]$Application,
            [object[]]$SelectedApps = @(),
            [string]$PreferredSource = $null,
            [object]$PackageManagerAvailabilityState = $null
        )

        $script:CapturedExecutionArgs = $PSBoundParameters
    }

    $script:TestTheme = [pscustomobject]@{
        AccentBlue = '#2d8cff'
        TextPrimary = '#ffffff'
        TextSecondary = '#d0d0d0'
        TextMuted = '#909090'
    }

    $script:TestWinGetAvailable = $true
    $script:TestChocolateyAvailable = $true
    $script:AppsPackageSourcePreference = 'winget'
    $script:AppsSourceUiUpdating = $false
    $script:AppsPackageManagerAvailabilityState = $null
    $script:SelectedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:AppsSelectionControls = [System.Collections.Generic.List[object]]::new()
    $script:AppsBulkActionButtons = [System.Collections.Generic.List[object]]::new()
    $script:AppsSelectionUiUpdating = $false
}

Describe 'Resolve-ApplicationExecutionRoute' {
    It 'prefers EntityType over Type for routing' {
        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Mozilla Firefox'
            Type       = 'choco'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        }

        $route.EntityType | Should -Be 'winget'
        $route.Route | Should -Be 'winget'
        $route.PackageId | Should -Be 'Mozilla.Firefox'
        $route.IdentityKey | Should -Be 'winget:mozilla.firefox'
    }

    It 'falls back to Type when EntityType is missing' {
        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name    = 'Krita'
            Type    = 'choco'
            ChocoId = 'krita'
        }

        $route.Route | Should -Be 'choco'
        $route.PackageId | Should -Be 'krita'
    }

    It 'prefers the requested source when both package ids are available' {
        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Mozilla Firefox'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        } -PreferredSource 'choco'

        $route.Route | Should -Be 'choco'
        $route.SelectedSource | Should -Be 'choco'
        $route.PackageId | Should -Be 'firefox'
        $route.PreferredSource | Should -Be 'choco'
    }

    It 'uses supplied package-manager availability state without probing' {
        Mock Test-WinGetAvailable { throw 'WinGet availability should not be probed when state is supplied.' }
        Mock Test-ChocolateyAvailable { throw 'Chocolatey availability should not be probed when state is supplied.' }

        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $false
        }

        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Mozilla Firefox'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        } -PackageManagerAvailabilityState $availabilityState

        $route.Route | Should -Be 'winget'
        Should -Invoke Test-WinGetAvailable -Times 0
        Should -Invoke Test-ChocolateyAvailable -Times 0
    }

    It 'marks placeholder entries as unsupported' {
        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Placeholder App'
            EntityType = 'placeholder'
        }

        $route.Route | Should -Be 'unsupported'
        $route.Reason | Should -BeLike '*No install method available*'
    }

    It 'routes store entries through the Microsoft Store adapter' {
        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Paint'
            EntityType = 'store'
            ExtraArgs  = @{
                StoreUri = 'ms-windows-store://pdp/?ProductId=9PCFS5B6T72H'
            }
        }

        $route.Route | Should -Be 'store'
        $route.SelectedSource | Should -Be 'store'
        $route.PackageId | Should -Be 'ms-windows-store://pdp/?ProductId=9PCFS5B6T72H'
    }

    It 'rejects winget entries that do not define a WinGetId' {
        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Broken App'
            EntityType = 'winget'
        }

        $route.Route | Should -Be 'unsupported'
        $route.Reason | Should -BeLike '*does not define a WinGetId*'
    }
}

Describe 'WinGet availability' {
    BeforeEach {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $true
    }

    AfterEach {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $true
    }

    It 'marks winget-only routes unsupported when WinGet is unavailable' {
        $script:TestWinGetAvailable = $false

        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Arc Browser'
            EntityType = 'winget'
            WinGetId   = 'TheBrowserCompany.Arc'
        }

        $route.Route | Should -Be 'unsupported'
        $route.Reason | Should -BeLike '*WinGet is not available*'
    }

    It 'falls back to Chocolatey when WinGet is unavailable and Chocolatey is available' {
        $script:TestWinGetAvailable = $false
        $script:TestChocolateyAvailable = $true

        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Krita'
            EntityType = 'winget'
            WinGetId   = 'KDE.Krita'
            ChocoId    = 'krita'
        }

        $route.Route | Should -Be 'choco'
        $route.SelectedSource | Should -Be 'choco'
        $route.PackageId | Should -Be 'krita'
    }

    It 'falls back to WinGet when Chocolatey is unavailable and WinGet is available' {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $false

        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Notepad++'
            EntityType = 'choco'
            WinGetId   = 'Notepad++.Notepad++'
            ChocoId    = 'notepadplusplus'
        }

        $route.Route | Should -Be 'winget'
        $route.SelectedSource | Should -Be 'winget'
        $route.PackageId | Should -Be 'Notepad++.Notepad++'
    }

    It 'marks winget entries unsupported when both WinGet and Chocolatey are unavailable' {
        $script:TestWinGetAvailable = $false
        $script:TestChocolateyAvailable = $false

        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Krita'
            EntityType = 'winget'
            WinGetId   = 'KDE.Krita'
            ChocoId    = 'krita'
        }

        $route.Route | Should -Be 'unsupported'
        $route.Reason | Should -BeLike '*Neither WinGet nor Chocolatey is available*'
    }

    It 'marks choco entries unsupported when both Chocolatey and WinGet are unavailable' {
        $script:TestWinGetAvailable = $false
        $script:TestChocolateyAvailable = $false

        $route = Resolve-ApplicationExecutionRoute -Application @{
            Name       = 'Notepad++'
            EntityType = 'choco'
            WinGetId   = 'Notepad++.Notepad++'
            ChocoId    = 'notepadplusplus'
        } -PreferredSource 'choco'

        $route.Route | Should -Be 'unsupported'
        $route.Reason | Should -BeLike '*Neither Chocolatey nor WinGet is available*'
    }

    It 'returns an empty installed-app cache when WinGet is unavailable' {
        $script:TestWinGetAvailable = $false
        Mock Start-Process { throw 'Start-Process should not be called when WinGet is unavailable.' }

        $cache = Get-InstalledAppCache

        $cache.Count | Should -Be 0
        Should -Invoke Start-Process -Times 0
    }

    It 'returns an empty update cache when WinGet is unavailable' {
        $script:TestWinGetAvailable = $false
        Mock Start-Process { throw 'Start-Process should not be called when WinGet is unavailable.' }

        $cache = Get-AvailableAppUpdateCache

        $cache.Count | Should -Be 0
        Should -Invoke Start-Process -Times 0
    }

    It 'launches winget installs with non-interactive flags' {
        Mock Invoke-StreamingProcess { 0 }

        Invoke-WingetInstall -WinGetId 'Google.Chrome' -DisplayName 'Google Chrome'

        Should -Invoke Invoke-StreamingProcess -Times 1 -ParameterFilter {
            $FilePath -eq 'winget.exe' -and
            @($ArgumentList) -contains 'install' -and
            @($ArgumentList) -contains '--disable-interactivity'
        }
    }

    It 'launches winget cache scans in a hidden window with non-interactive flags' {
        Mock Resolve-WinGetExecutable { 'winget.exe' }
        Mock Invoke-ProcessTextCapture {
            [pscustomobject]@{
                ExitCode = 0
                StandardOutput = ''
                StandardError = ''
            }
        }

        $cache = Get-InstalledAppCache

        $cache.Count | Should -Be 0
        Should -Invoke Invoke-ProcessTextCapture -Times 1 -ParameterFilter {
            $FilePath -eq 'winget.exe' -and
            @($ArgumentList) -contains '--disable-interactivity'
        }
    }

    It 'launches winget update scans in a hidden window with non-interactive flags' {
        Mock Resolve-WinGetExecutable { 'winget.exe' }
        Mock Invoke-ProcessTextCapture {
            [pscustomobject]@{
                ExitCode = 0
                StandardOutput = ''
                StandardError = ''
            }
        }

        $cache = Get-AvailableAppUpdateCache

        $cache.Count | Should -Be 0
        Should -Invoke Invoke-ProcessTextCapture -Times 1 -ParameterFilter {
            $FilePath -eq 'winget.exe' -and
            @($ArgumentList) -contains '--disable-interactivity'
        }
    }
}

Describe 'Application timeout propagation' {
    It 'detects timeout exceptions inside nested error records' {
        try
        {
            throw ([System.TimeoutException]::new('Timed out after 900 second(s).'))
        }
        catch
        {
            $timeoutException = Get-ApplicationActionTimeoutException -ErrorRecord $_

            $timeoutException | Should -Not -BeNullOrEmpty
            $timeoutException.GetType().FullName | Should -Be 'System.TimeoutException'
        }
    }

    It 'rethrows timeout failures as TimeoutException' {
        try
        {
            throw ([System.TimeoutException]::new('Timed out after 900 second(s).'))
        }
        catch
        {
            {
                Throw-ApplicationActionFailure -TargetName 'Visual Studio Code' -ActionLabel 'Install' -TimeoutSeconds 900 -ErrorRecord $_
            } | Should -Throw -ExceptionType ([System.TimeoutException])
        }
    }

    It 'forwards TimeoutSeconds to the selected route handler' {
        Mock Resolve-ApplicationExecutionRoute {
            [pscustomobject]@{
                Route = 'winget'
                PackageId = 'Microsoft.VisualStudioCode'
                DisplayName = 'Visual Studio Code'
                Reason = $null
            }
        }
        Mock Invoke-WingetInstall {}

        Invoke-ApplicationAction -Action 'Install' -Application ([pscustomobject]@{ Name = 'Visual Studio Code'; WinGetId = 'Microsoft.VisualStudioCode' }) -TimeoutSeconds 321

        Should -Invoke Invoke-WingetInstall -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 321 -and $WinGetId -eq 'Microsoft.VisualStudioCode'
        }
    }
}

Describe 'Chocolatey availability' {
    BeforeEach {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $true
    }

    AfterEach {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $true
    }

    It 'returns an empty installed Chocolatey cache when Chocolatey is unavailable' {
        $script:TestChocolateyAvailable = $false

        $cache = Get-InstalledChocolateyAppCache

        $cache.Count | Should -Be 0
    }

    It 'returns an empty Chocolatey update cache when Chocolatey is unavailable' {
        $script:TestChocolateyAvailable = $false

        $cache = Get-AvailableChocolateyUpdateCache

        $cache.Count | Should -Be 0
    }

    It 'launches Chocolatey installs without forcing a hidden window' {
        Mock Resolve-ChocolateyExecutable { 'choco.exe' }
        Mock Invoke-StreamingProcess { 0 }

        Invoke-ChocoInstall -ChocoId 'googlechrome' -DisplayName 'Google Chrome'

        Should -Invoke Invoke-StreamingProcess -Times 1 -ParameterFilter {
            $FilePath -eq 'choco.exe' -and
            @($ArgumentList) -contains 'install' -and
            @($ArgumentList) -contains '--no-progress'
        }
    }
}

Describe 'Chocolatey bootstrap' {
    BeforeEach {
        Mock Invoke-ChocolateyBootstrap {
            [pscustomobject]@{
                Success = $true
                Error   = $null
            }
        }
        Mock Reset-ChocolateyAvailabilityState {}
    }

    It 'delegates Chocolatey bootstrap to the reviewed shared helper' {
        Invoke-ChocolateyBootstrapInstall -TimeoutSeconds 321

        Should -Invoke Invoke-ChocolateyBootstrap -Times 1 -ParameterFilter {
            $TimeoutSeconds -eq 321
        }
        Should -Invoke Reset-ChocolateyAvailabilityState -Times 1
    }

    It 'throws when the shared Chocolatey bootstrap helper fails' {
        Mock Invoke-ChocolateyBootstrap {
            [pscustomobject]@{
                Success = $false
                Error   = 'Chocolatey bootstrap failed.'
            }
        }

        { Invoke-ChocolateyBootstrapInstall } | Should -Throw '*Chocolatey bootstrap failed*'

        Should -Invoke Reset-ChocolateyAvailabilityState -Times 0
    }
}

Describe 'Test-ChocolateyBootstrapInteractiveHost' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $packageManagementPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/PackageManagement.Helpers.ps1'
        $packageManagementAst = [System.Management.Automation.Language.Parser]::ParseFile($packageManagementPath, [ref]$null, [ref]$null)
        $targetFn = $packageManagementAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-ChocolateyBootstrapInteractiveHost' }, $true) | Select-Object -First 1
        if ($targetFn) { Invoke-Expression $targetFn.Extent.Text }
    }

    BeforeEach {
        $script:rawUi = [pscustomobject]@{}
        $script:baselineHost = [pscustomobject]@{
            Name = 'BaselineHost'
            UI = [pscustomobject]@{ RawUI = $script:rawUi }
        }
        $script:remoteHost = [pscustomobject]@{
            Name = 'ServerRemoteHost'
            UI = [pscustomobject]@{ RawUI = $script:rawUi }
        }
        $script:defaultHost = [pscustomobject]@{
            Name = 'Default Host'
            UI = [pscustomobject]@{ RawUI = $script:rawUi }
        }
        $script:consoleHost = [pscustomobject]@{
            Name = 'ConsoleHost'
            UI = [pscustomobject]@{ RawUI = $script:rawUi }
        }
    }

    It 'rejects the BaselineHost launcher even though RawUI is present' {
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $script:baselineHost -UserInteractive $true | Should -BeFalse
    }

    It 'rejects PSRemoting ServerRemoteHost' {
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $script:remoteHost -UserInteractive $true | Should -BeFalse
    }

    It 'rejects Default Host automation contexts' {
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $script:defaultHost -UserInteractive $true | Should -BeFalse
    }

    It 'rejects when UserInteractive is false' {
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $script:consoleHost -UserInteractive $false | Should -BeFalse
    }

    It 'accepts a ConsoleHost when UserInteractive is true' {
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $script:consoleHost -UserInteractive $true | Should -BeTrue
    }

    It 'rejects a null host' {
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $null -UserInteractive $true | Should -BeFalse
    }

    It 'rejects a host with no UI' {
        $hostNoUi = [pscustomobject]@{ Name = 'ConsoleHost'; UI = $null }
        Test-ChocolateyBootstrapInteractiveHost -HostInstance $hostNoUi -UserInteractive $true | Should -BeFalse
    }
}

Describe 'Command execution routes' {
    BeforeEach {
        $script:CapturedCommandInvocation = $null
    }

    It 'parses literal command strings into a command name and argument list' {
        $invocation = ConvertTo-ApplicationCommandInvocation -Command "winget install -s msstore 'Microsoft Solitaire Collection'"

        $invocation.CommandName | Should -Be 'winget'
        @($invocation.CommandArguments).Count | Should -Be 4
        $invocation.CommandArguments[0] | Should -Be 'install'
        $invocation.CommandArguments[1] | Should -Be '-s'
        $invocation.CommandArguments[2] | Should -Be 'msstore'
        $invocation.CommandArguments[3] | Should -Be 'Microsoft Solitaire Collection'
        $invocation.HasSingleCommandInvocation | Should -BeTrue
    }

    It 'parses safe pipelines and semicolon-separated statements' {
        $invocation = ConvertTo-ApplicationCommandInvocation -Command 'Get-AppxPackage -Name *3DViewer* | Remove-AppxPackage; Get-AppxPackage -AllUsers -Name *3DViewer* | Remove-AppxProvisionedAppxPackage'

        $invocation.HasSingleCommandInvocation | Should -BeFalse
        @($invocation.CommandNames) | Should -Be @(
            'Get-AppxPackage',
            'Remove-AppxPackage',
            'Get-AppxPackage',
            'Remove-AppxProvisionedAppxPackage'
        )
    }

    It 'rejects unsafe subexpressions and scriptblocks' {
        {
            ConvertTo-ApplicationCommandInvocation -Command 'Get-AppxPackage $(Get-Date)'
        } | Should -Throw '*contains unsupported syntax*'
    }

    It 'rejects dot-source invocation against a literal script path' {
        {
            ConvertTo-ApplicationCommandInvocation -Command ". '.\foo.ps1'"
        } | Should -Throw '*contains unsupported syntax*'
    }

    It 'rejects call-operator invocation against a literal script path' {
        {
            ConvertTo-ApplicationCommandInvocation -Command "& '.\foo.ps1'"
        } | Should -Throw '*contains unsupported syntax*'
    }

    It 'rejects dot-source invocation against a bareword path' {
        {
            ConvertTo-ApplicationCommandInvocation -Command '. C:\Temp\foo.ps1'
        } | Should -Throw '*contains unsupported syntax*'
    }

    It 'rejects call-operator invocation of a command name' {
        {
            ConvertTo-ApplicationCommandInvocation -Command '& winget install git'
        } | Should -Throw '*contains unsupported syntax*'
    }

    It 'executes parsed commands without Invoke-Expression' {
        Mock Invoke-StreamingProcess {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [int]$TimeoutSeconds
            )

            $script:CapturedCommandInvocation = [pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
                TimeoutSeconds = $TimeoutSeconds
            }

            return 0
        }

        Invoke-CommandInstall -Command 'Invoke-TestApplicationCommand install baseline' -DisplayName 'Baseline Test App'

        $script:CapturedCommandInvocation.FilePath | Should -Be 'Invoke-TestApplicationCommand'
        $script:CapturedCommandInvocation.TimeoutSeconds | Should -Be 1800
        @($script:CapturedCommandInvocation.ArgumentList) | Should -Be @('install', 'baseline')
        Should -Invoke Invoke-StreamingProcess -Times 1
    }

    It 'rejects pipelines for direct command execution' {
        Mock Invoke-StreamingProcess {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [int]$TimeoutSeconds
            )

            $script:CapturedCommandInvocation = [pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
                TimeoutSeconds = $TimeoutSeconds
            }

            return 0
        }

        {
            Invoke-CommandInstall -Command 'Get-TestApplicationItem | Invoke-TestPipelineCommand' -DisplayName 'Baseline Pipeline App'
        } | Should -Throw '*must resolve to a single executable invocation*'

        Should -Invoke Invoke-StreamingProcess -Times 0
    }
}

Describe 'Process capture cleanup' {
    It 'routes subprocess drain and dispose failures through Write-SwallowedException' {
        $script:ApplicationsContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Applications\.Invoke-ProcessCapture\.StdoutAwait'''
        $script:ApplicationsContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Applications\.Invoke-ProcessCapture\.StderrAwait'''
        $script:ApplicationsContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Applications\.Invoke-ProcessCapture\.DisposeProcess'''
    }
}

Describe 'Applications manual Store dialog' {
    It 'loads GUICommon and calls the exported common dialog function' {
        $script:ApplicationsContent | Should -Match '(?m)^using module \.\.\\GUICommon\.psm1'
        $script:ApplicationsContent | Should -Match 'GUICommon\\Show-GuiCommonThemedDialog'
        $script:ApplicationsContent | Should -Not -Match 'GUICommon\\Show-ThemedDialog'
    }

    It 'resolves dialog theme state shared into the background runspace' {
        $script:ApplicationsContent | Should -Match 'function Get-ApplicationDialogTheme'
        $script:ApplicationsContent | Should -Match 'Variable:\\Global:BaselineCurrentTheme'
        $script:ApplicationsContent | Should -Match 'Variable:\\Global:BaselineCurrentThemeName'
        $script:ApplicationsContent | Should -Match 'Variable:\\Global:BaselineUseDarkMode'
        $script:ApplicationsContent | Should -Match '\$env:BASELINE_USE_DARK_MODE'
        $script:ApplicationsContent | Should -Match '\$env:BASELINE_THEME_NAME'
    }
}

Describe 'Apps package manager availability' {
    BeforeEach {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $true
        $script:AppsPackageManagerBanner = [pscustomobject]@{
            Visibility = $null
        }
        $script:TxtAppsPackageManagerBanner = [pscustomobject]@{
            Text = $null
        }
    }

    AfterEach {
        $script:TestWinGetAvailable = $true
        $script:TestChocolateyAvailable = $true
        $script:AppsPackageManagerBanner = $null
        $script:TxtAppsPackageManagerBanner = $null
    }

    It 'returns a banner state that stays hidden when at least one package manager is available' {
        $state = Get-AppsPackageManagerAvailabilityState

        $state.BothUnavailable | Should -BeFalse
        $state.BannerText | Should -BeNullOrEmpty

        Update-AppsPackageManagerBanner -AvailabilityState $state

        $script:AppsPackageManagerBanner.Visibility.ToString() | Should -Be 'Collapsed'
        $script:TxtAppsPackageManagerBanner.Text | Should -BeNullOrEmpty
    }

    It 'shows a banner when both package managers are unavailable' {
        $script:TestWinGetAvailable = $false
        $script:TestChocolateyAvailable = $false

        $state = Get-AppsPackageManagerAvailabilityState
        $state.BothUnavailable | Should -BeTrue
        $state.BannerText | Should -BeLike '*WinGet and Chocolatey are unavailable*'

        Update-AppsPackageManagerBanner -AvailabilityState $state

        $script:AppsPackageManagerBanner.Visibility.ToString() | Should -Be 'Visible'
        $script:TxtAppsPackageManagerBanner.Text | Should -BeLike '*WinGet and Chocolatey are unavailable*'
    }

    It 'includes package manager availability in the apps render signature' {
        $script:TestWinGetAvailable = $false
        $script:TestChocolateyAvailable = $false

        $state = Get-AppsPackageManagerAvailabilityState
        $signature = Get-AppsViewRenderSignature -PackageManagerAvailabilityState $state

        $signature | Should -Match 'PackageManagers=WinGet=False\|Chocolatey=False'
    }
}

Describe 'Application catalog execution state' {
    It 'treats store entries with StoreUri metadata as executable install routes' {
        $state = Get-ApplicationExecutionState -Entry ([pscustomobject]@{
            Name       = 'Paint'
            SubCategory = 'Imaging'
            EntityType = 'store'
            ExtraArgs  = [pscustomobject]@{
                StoreUri = 'ms-windows-store://pdp/?ProductId=9PCFS5B6T72H'
            }
            SupportsExecution = $true
        })

        $state.SupportsExecution | Should -BeTrue
        $state.State | Should -Be 'Not installed'
        $state.Action | Should -Be 'Install'
        $state.Route | Should -Be 'store'
        $state.SelectedSource | Should -Be 'store'
    }
}

Describe 'Applications catalog store metadata' {
    It 'does not leave StoreUri-backed app entries marked as placeholders' {
        $catalogRoot = Join-Path $PSScriptRoot '../../Module/Data/AppsCategory'
        $offenders = @(
            Get-ChildItem -LiteralPath $catalogRoot -Filter '*.json' | ForEach-Object {
                $file = $_.Name
                $json = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
                foreach ($entry in @($json.Entries))
                {
                    if (-not $entry -or -not $entry.ExtraArgs) { continue }
                    $storeUri = if ($entry.ExtraArgs.PSObject.Properties['StoreUri']) { [string]$entry.ExtraArgs.StoreUri } else { $null }
                    if ([string]::IsNullOrWhiteSpace($storeUri)) { continue }
                    if ([string]$entry.EntityType -eq 'placeholder' -or ($entry.PSObject.Properties['SupportsExecution'] -and -not [bool]$entry.SupportsExecution))
                    {
                        "{0}::{1}" -f $file, [string]$entry.Name
                    }
                }
            }
        )

        @($offenders).Count | Should -Be 0
    }
}

Describe 'Invoke-ApplicationAction' {
    BeforeEach {
        Mock Invoke-WingetInstall {}
        Mock Invoke-WingetUninstall {}
        Mock Invoke-WingetUpdate {}
        Mock Invoke-ChocoInstall {}
        Mock Invoke-ChocoUninstall {}
        Mock Invoke-ChocoUpdate {}
        Mock Invoke-StoreInstall {}
        Mock LogError {}
    }

    It 'routes winget installs to the winget adapter' {
        $application = [pscustomobject]@{
            Name       = 'Mozilla Firefox'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        }
        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $false
        }

        Invoke-ApplicationAction -Action Install -Application $application -PackageManagerAvailabilityState $availabilityState

        Should -Invoke Invoke-WingetInstall -Times 1 -ParameterFilter {
            $WinGetId -eq 'Mozilla.Firefox' -and
            $DisplayName -eq 'Mozilla Firefox' -and
            $PackageManagerAvailabilityState.WinGetAvailable -eq $true -and
            $PackageManagerAvailabilityState.ChocolateyAvailable -eq $false
        }
        Should -Invoke Invoke-ChocoInstall -Times 0
    }

    It 'routes choco updates to the chocolatey adapter' {
        $application = [pscustomobject]@{
            Name       = '7-Zip'
            EntityType = 'choco'
            ChocoId    = '7zip'
        }
        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $false
            ChocolateyAvailable = $true
        }

        Invoke-ApplicationAction -Action Update -Application $application -PackageManagerAvailabilityState $availabilityState

        Should -Invoke Invoke-ChocoUpdate -Times 1 -ParameterFilter {
            $ChocoId -eq '7zip' -and
            $DisplayName -eq '7-Zip' -and
            $PackageManagerAvailabilityState.WinGetAvailable -eq $false -and
            $PackageManagerAvailabilityState.ChocolateyAvailable -eq $true
        }
        Should -Invoke Invoke-WingetUpdate -Times 0
    }

    It 'routes store installs to the Microsoft Store adapter' {
        $application = [pscustomobject]@{
            Name       = 'Paint'
            EntityType = 'store'
            ExtraArgs  = [pscustomobject]@{
                StoreUri = 'ms-windows-store://pdp/?ProductId=9PCFS5B6T72H'
            }
            SupportsExecution = $true
        }

        Invoke-ApplicationAction -Action Install -Application $application

        Should -Invoke Invoke-StoreInstall -Times 1 -ParameterFilter {
            $StoreUri -eq 'ms-windows-store://pdp/?ProductId=9PCFS5B6T72H' -and
            $DisplayName -eq 'Paint'
        }
    }

    It 'throws for unsupported routes' {
        {
            Invoke-ApplicationAction -Action Install -Application @{
                Name       = 'Placeholder'
                EntityType = 'placeholder'
            }
        } | Should -Throw '*No install method available*'
    }
}

Describe 'AppInstall' {
    BeforeEach {
        Mock Invoke-ApplicationAction {}
    }

    It 'delegates install actions to the unified router' {
        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $true
        }

        AppInstall -Install -WinGetId 'Mozilla.Firefox' -ChocoId 'firefox' -DisplayName 'Mozilla Firefox' -PreferredSource 'choco' -PackageManagerAvailabilityState $availabilityState

        Should -Invoke Invoke-ApplicationAction -Times 1 -ParameterFilter {
            $Action -eq 'Install' -and $WinGetId -eq 'Mozilla.Firefox' -and $ChocoId -eq 'firefox' -and $DisplayName -eq 'Mozilla Firefox' -and $PreferredSource -eq 'choco' -and $PackageManagerAvailabilityState -eq $availabilityState
        }
    }
}

Describe 'AppUpdate' {
    BeforeEach {
        Mock Resolve-WinGetExecutable { 'winget.exe' }
        Mock Get-Command { [pscustomobject]@{ Name = 'choco' } }
        <#
            .SYNOPSIS
        #>

        function Resolve-ApplicationPackageId
        {
            param([string]$PackageId)
            return $PackageId
        }
        Mock Invoke-ApplicationAction {}
        Mock Invoke-WingetUpdateAll {}
        Mock Invoke-ChocoUpdateAll {}
    }

    It 'delegates update-all actions to the bulk adapters' {
        AppUpdate -All

        Should -Invoke Invoke-WingetUpdateAll -Times 1
        Should -Invoke Invoke-ChocoUpdateAll -Times 1
    }

    It 'forwards preferred source for single app updates' {
        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $true
        }

        AppUpdate -WinGetId 'Mozilla.Firefox' -ChocoId 'firefox' -DisplayName 'Mozilla Firefox' -PreferredSource 'choco' -PackageManagerAvailabilityState $availabilityState

        Should -Invoke Invoke-ApplicationAction -Times 1 -ParameterFilter {
            $Action -eq 'Update' -and $WinGetId -eq 'Mozilla.Firefox' -and $ChocoId -eq 'firefox' -and $DisplayName -eq 'Mozilla Firefox' -and $PreferredSource -eq 'choco' -and $PackageManagerAvailabilityState -eq $availabilityState
        }
    }

    It 'forwards availability state to the bulk update adapters' {
        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $true
        }

        Mock Test-WinGetAvailable { throw 'WinGet availability should not be probed when cached state is supplied.' }
        Mock Test-ChocolateyAvailable { throw 'Chocolatey availability should not be probed when cached state is supplied.' }

        AppUpdate -All -PackageManagerAvailabilityState $availabilityState

        Should -Invoke Invoke-WingetUpdateAll -Times 1 -ParameterFilter {
            $PackageManagerAvailabilityState.WinGetAvailable -eq $true -and
            $PackageManagerAvailabilityState.ChocolateyAvailable -eq $true
        }
        Should -Invoke Invoke-ChocoUpdateAll -Times 1 -ParameterFilter {
            $PackageManagerAvailabilityState.WinGetAvailable -eq $true -and
            $PackageManagerAvailabilityState.ChocolateyAvailable -eq $true
        }
        Should -Invoke Test-WinGetAvailable -Times 0
        Should -Invoke Test-ChocolateyAvailable -Times 0
    }
}

Describe 'Invoke-AppBatchAction' {
    BeforeEach {
        Mock Invoke-ApplicationAction {}
    }

    It 'routes each unique application once and records unsupported entries' {
        $wingetApp = [pscustomobject]@{
            Name       = 'Mozilla Firefox'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        }
        $duplicateWingetApp = [pscustomobject]@{
            Name       = 'Mozilla Firefox Duplicate'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        }
        $chocoApp = [pscustomobject]@{
            Name       = '7-Zip'
            EntityType = 'choco'
            ChocoId    = '7zip'
        }
        $placeholderApp = [pscustomobject]@{
            Name       = 'Placeholder App'
            EntityType = 'placeholder'
        }

        $result = Invoke-AppBatchAction -Action Install -Applications @(
            $wingetApp,
            $duplicateWingetApp,
            $chocoApp,
            $placeholderApp
        )

        $result.Outcome | Should -Be 'Partial'
        $result.SuccessCount | Should -Be 2
        $result.FailureCount | Should -Be 1
        $result.TotalCount | Should -Be 3
        $result.FailedApps[0].Error | Should -BeLike '*No install method available*'

        Should -Invoke Invoke-ApplicationAction -Times 2
    }

    It 'honors the preferred source for batch execution' {
        $application = [pscustomobject]@{
            Name       = 'Mozilla Firefox'
            EntityType = 'winget'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
        }

        $availabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $true
        }

        $result = Invoke-AppBatchAction -Action Install -Applications @($application) -PreferredSource 'choco' -PackageManagerAvailabilityState $availabilityState

        $result.Outcome | Should -Be 'Success'
        $result.SuccessfulApps[0].SelectedSource | Should -Be 'choco'
        Should -Invoke Invoke-ApplicationAction -Times 1 -ParameterFilter {
            $Action -eq 'Install' -and $PreferredSource -eq 'choco' -and $PackageManagerAvailabilityState -eq $availabilityState
        }
    }
}

Describe 'Start-AppsModuleActionAsync' {
    BeforeEach {
        $script:CapturedExecutionArgs = $null
    }

    AfterEach {
        $script:AppsPackageManagerAvailabilityState = $null
    }

    It 'forwards the application object and derived identifiers to the execution runner' {
        $application = [pscustomobject]@{
            Name       = 'Mozilla Firefox'
            WinGetId   = 'Mozilla.Firefox'
            ChocoId    = 'firefox'
            EntityType = 'winget'
        }
        $script:AppsPackageManagerAvailabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $true
        }

        Start-AppsModuleActionAsync -Action Install -Application $application -PreferredSource 'choco'

        $script:CapturedExecutionArgs.Action | Should -Be 'Install'
        $script:CapturedExecutionArgs.WinGetId | Should -Be 'Mozilla.Firefox'
        $script:CapturedExecutionArgs.ChocoId | Should -Be 'firefox'
        $script:CapturedExecutionArgs.DisplayName | Should -Be 'Mozilla Firefox'
        $script:CapturedExecutionArgs.Application.Name | Should -Be 'Mozilla Firefox'
        $script:CapturedExecutionArgs.PreferredSource | Should -Be 'choco'
        $script:CapturedExecutionArgs.PackageManagerAvailabilityState.WinGetAvailable | Should -BeTrue
        $script:CapturedExecutionArgs.PackageManagerAvailabilityState.ChocolateyAvailable | Should -BeTrue
    }
}

Describe 'Start-AppsModuleBatchActionAsync' {
    BeforeEach {
        $script:CapturedExecutionArgs = $null
    }

    AfterEach {
        $script:AppsPackageManagerAvailabilityState = $null
    }

    It 'forwards the selected apps and preferred source to the execution runner' {
        $selectedApps = @(
            [pscustomobject]@{
                Name       = 'Mozilla Firefox'
                WinGetId   = 'Mozilla.Firefox'
                ChocoId    = 'firefox'
                EntityType = 'winget'
            }
        )
        $script:AppsPackageManagerAvailabilityState = [pscustomobject]@{
            WinGetAvailable = $true
            ChocolateyAvailable = $false
        }

        Start-AppsModuleBatchActionAsync -Action Install -SelectedApps $selectedApps -PreferredSource 'choco'

        $script:CapturedExecutionArgs.Action | Should -Be 'Install'
        $script:CapturedExecutionArgs.SelectedApps.Count | Should -Be 1
        $script:CapturedExecutionArgs.SelectedApps[0].Name | Should -Be 'Mozilla Firefox'
        $script:CapturedExecutionArgs.PreferredSource | Should -Be 'choco'
        $script:CapturedExecutionArgs.PackageManagerAvailabilityState.WinGetAvailable | Should -BeTrue
        $script:CapturedExecutionArgs.PackageManagerAvailabilityState.ChocolateyAvailable | Should -BeFalse
    }
}

Describe 'Update-AppsSelectionSummary' {
    BeforeEach {
        $script:SelectedAppsForSummary = @(
            [pscustomobject]@{
                Name = 'Mozilla Firefox'
            }
        )

        $script:AppsViewLoaded = $false
        $script:AppsViewDirty = $false
        $script:AppsOperationInProgress = $false
        $script:AppsCacheRefreshInProgress = $false
        $script:SelectedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $script:AppsSelectionControls = [System.Collections.Generic.List[object]]::new()
        $script:AppsBulkActionButtons = [System.Collections.Generic.List[object]]::new()
        $script:TxtAppSelectionStatus = [pscustomobject]@{
            Text = $null
            Foreground = $null
        }
        $script:BtnInstallSelectedApps = [pscustomobject]@{
            IsEnabled = $false
            ToolTip = $null
        }
        $script:BtnUninstallSelectedApps = [pscustomobject]@{
            IsEnabled = $false
            ToolTip = $null
        }
        $script:BtnUpdateSelectedApps = [pscustomobject]@{
            IsEnabled = $false
            ToolTip = $null
        }
        $script:BtnClearQueuedActions = [pscustomobject]@{
            IsEnabled = $false
            ToolTip = $null
        }
        $script:BtnScanInstalledApps = [pscustomobject]@{
            IsEnabled = $false
            ToolTip = $null
        }
        $script:AppsSelectionUiUpdating = $false
    }

    It 'allows installation without a scanned installed-app cache' {
        Update-AppsSelectionSummary

        $script:BtnInstallSelectedApps.IsEnabled | Should -BeTrue
        $script:BtnUninstallSelectedApps.IsEnabled | Should -BeFalse
        $script:BtnUpdateSelectedApps.IsEnabled | Should -BeFalse
        $script:BtnClearQueuedActions.IsEnabled | Should -BeTrue
        $script:BtnScanInstalledApps.IsEnabled | Should -BeTrue
        $script:BtnInstallSelectedApps.ToolTip | Should -Be 'Stage installs for every checked app. They run when you click Apply Changes.'
        $script:BtnUninstallSelectedApps.ToolTip | Should -Match 'Scan installed apps before uninstalling or updating\.'
        $script:BtnUpdateSelectedApps.ToolTip | Should -Match 'Scan installed apps before uninstalling or updating\.'
        $script:BtnScanInstalledApps.ToolTip | Should -Be 'Scan installed apps to update install status.'
    }

    It 'enables update and uninstall actions once the installed-app cache is ready' {
        $script:AppsViewLoaded = $true
        Update-AppsSelectionSummary

        $script:BtnInstallSelectedApps.IsEnabled | Should -BeTrue
        $script:BtnUninstallSelectedApps.IsEnabled | Should -BeTrue
        $script:BtnUpdateSelectedApps.IsEnabled | Should -BeTrue
        $script:BtnClearQueuedActions.IsEnabled | Should -BeTrue
        $script:BtnScanInstalledApps.IsEnabled | Should -BeTrue
    }
}
