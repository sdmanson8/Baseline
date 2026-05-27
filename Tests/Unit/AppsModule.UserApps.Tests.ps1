Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $appsModulePath = Join-Path $PSScriptRoot '../../Module/GUI/AppsModule.ps1'
    $appsModuleSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/AppsModule'
    $script:AppsModuleContent = Get-BaselineTestSourceText -Path @(
        $appsModulePath
        (Join-Path $appsModuleSplitRoot 'CatalogHelpers.ps1')
        (Join-Path $appsModuleSplitRoot 'SelectionQueueState.ps1')
        (Join-Path $appsModuleSplitRoot 'ProgressNavChrome.ps1')
    )
}

Describe 'Get-BaselineApplicationsCatalog: user-added apps integration (#29 / spec #18)' {
    # Wires Module/SharedHelpers/UserApps.Helpers.ps1 (Get-BaselineUserAppEntries
    # + Merge-BaselineUserAppEntries) into the External Software tab loader.
    # Built-ins always win on conflict. The merge runs against the raw JSON
    # entries (not the projected output), so the existing per-entry projection
    # downstream consumes user entries identically to built-ins.

    It 'invokes Get-BaselineUserAppEntries via Get-Command guard so the loader runs even if SharedHelpers is unloaded' {
        $script:AppsModuleContent | Should -Match "Get-Command -Name 'Get-BaselineUserAppEntries' -CommandType Function -ErrorAction SilentlyContinue"
        $script:AppsModuleContent | Should -Match '\$userAppsResult = Get-BaselineUserAppEntries'
    }

    It 'surfaces Get-BaselineUserAppEntries warnings via LogWarning' {
        $script:AppsModuleContent | Should -Match 'foreach \(\$warning in @\(\$userAppsResult\.Warnings\)\)'
        $script:AppsModuleContent | Should -Match 'LogWarning \$warning'
    }

    It 'injects safe defaults (Risk=Low, Safe=true, Function=AppInstall) onto user entries before projection' {
        $script:AppsModuleContent | Should -Match '\$bag\[''Risk''\] = ''Low'''
        $script:AppsModuleContent | Should -Match '\$bag\[''Safe''\] = \$true'
        $script:AppsModuleContent | Should -Match '\$bag\[''Function''\] = ''AppInstall'''
        $script:AppsModuleContent | Should -Match '\$bag\[''Caution''\] = \$false'
        $script:AppsModuleContent | Should -Match '\$bag\[''RequiresRestart''\] = \$false'
        $script:AppsModuleContent | Should -Match '\$bag\[''SourceRegion''\] = ''User'''
    }

    It 'runs Merge-BaselineUserAppEntries against the flat built-in entries list and surfaces conflict warnings' {
        $script:AppsModuleContent | Should -Match 'Merge-BaselineUserAppEntries -BuiltInEntries \$builtInRawEntries -UserEntries \$userEntriesNormalized'
        $script:AppsModuleContent | Should -Match 'foreach \(\$warning in @\(\$mergeResult\.Warnings\)\)'
    }

    It 'appends only the non-conflicting user entries (Source=User) as a synthetic catalog file' {
        $script:AppsModuleContent | Should -Match 'PSObject\.Properties\[''Source''\] -and \(\[string\]\$_\.Source -eq ''User''\)'
        $script:AppsModuleContent | Should -Match 'Path = ''<UserApps>'''
        $script:AppsModuleContent | Should -Match '\$catalogFilesJson \+= \[pscustomobject\]@\{'
    }

    It 'wraps the user-apps load in a try/catch so a corrupted user JSON never breaks the External Software tab' {
        # Locate the integration block bounded by the unique '<UserApps>' tag.
        $userAppsIndex = $script:AppsModuleContent.IndexOf("Path = '<UserApps>'")
        $userAppsIndex | Should -BeGreaterThan 0

        # The catch must route through Write-SwallowedException with a stable Source label.
        $tail = $script:AppsModuleContent.Substring($userAppsIndex)
        $tail | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Catalog\.UserAppsLoad'''
    }

    It 'normalizes $catalogFilesJson to an array before appending so single-file environments do not collapse' {
        # PowerShell's `$x = foreach (...) {...}` returns scalar when one
        # item, array when many. The += append below the integration block
        # would silently drop existing entries on a scalar. Pin the @() wrap.
        $script:AppsModuleContent | Should -Match '\$catalogFilesJson = @\(\$catalogFilesJson\)'
    }
}
