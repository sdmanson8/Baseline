Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ConfigProfilePath = Join-Path $script:RepoRoot 'Module/SharedHelpers/ConfigProfile.Helpers.ps1'
    $script:UserAppsHelpersPath = Join-Path $script:RepoRoot 'Module/SharedHelpers/UserApps.Helpers.ps1'
    $script:SharedHelpersManifestPath = Join-Path $script:RepoRoot 'Module/SharedHelpers.psm1'
    $script:ActionHandlersPath = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers'

    . (Join-Path $script:RepoRoot 'Module/SharedHelpers/Json.Helpers.ps1')
    . $script:UserAppsHelpersPath
    . $script:ConfigProfilePath

    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:ConfigProfileContent = Get-BaselineTestSourceText -Path $script:ConfigProfilePath
    $script:SharedHelpersContent = Get-BaselineTestSourceText -Path $script:SharedHelpersManifestPath

    # Selections is [Parameter(Mandatory)][array] so empty arrays don't bind.
    # New-ConfigurationProfile drops selections with no Function field, so a
    # single placeholder hashtable yields an Entries[] of zero without
    # tripping the mandatory-binding gate.
    function New-MinimalProfile {
        param (
            [array]$UserApps = @(),
            [array]$IncludePaths = @()
        )
        return New-ConfigurationProfile `
            -Name 'TestProfile' `
            -Selections @(@{}) `
            -AppActions @() `
            -UserApps $UserApps `
            -IncludePaths $IncludePaths `
            -BaselineVersion 'test'
    }
}

Describe 'ConfigProfile schema bump' {
    It 'declares SchemaVersion 3' {
        $script:ConfigProfileContent | Should -Match '\$Script:ConfigProfileSchemaVersion = 3'
    }

    It 'New-ConfigurationProfile accepts a -UserApps parameter' {
        (Get-Command New-ConfigurationProfile).Parameters.Keys | Should -Contain 'UserApps'
    }

    It 'New-ConfigurationProfile accepts an -IncludePaths parameter' {
        (Get-Command New-ConfigurationProfile).Parameters.Keys | Should -Contain 'IncludePaths'
    }

    It 'omitting -UserApps still produces a valid profile with an empty UserApps array' {
        $profile = New-ConfigurationProfile -Name 'NoUserApps' -Selections @(@{}) -AppActions @() -BaselineVersion 'test'
        $profile.PSObject.Properties['UserApps'] | Should -Not -BeNullOrEmpty
        @($profile.UserApps).Count | Should -Be 0
    }
}

Describe 'New-ConfigurationProfile UserApps inlining' {
    It 'carries Name / SubCategory / Function / ExtraArgs through to the profile' {
        $entry = [pscustomobject]@{
            Name        = 'Notepad++'
            SubCategory = 'Utilities'
            Function    = 'AppInstall'
            ExtraArgs   = [pscustomobject]@{ WinGetId = 'Notepad++.Notepad++'; ChocoId = 'notepadplusplus' }
        }
        $profile = New-MinimalProfile -UserApps @($entry)
        @($profile.UserApps).Count | Should -Be 1
        $profile.UserApps[0].Name | Should -Be 'Notepad++'
        $profile.UserApps[0].SubCategory | Should -Be 'Utilities'
        $profile.UserApps[0].Function | Should -Be 'AppInstall'
        $profile.UserApps[0].ExtraArgs.WinGetId | Should -Be 'Notepad++.Notepad++'
        $profile.UserApps[0].ExtraArgs.ChocoId | Should -Be 'notepadplusplus'
    }

    It 'strips Source and SourceFile runtime annotations' {
        $entry = [pscustomobject]@{
            Name        = 'CustomApp'
            SubCategory = 'Utilities'
            Source      = 'User'
            SourceFile  = 'C:\some\path.json'
            ExtraArgs   = [pscustomobject]@{ WinGetId = 'Custom.App' }
        }
        $profile = New-MinimalProfile -UserApps @($entry)
        $serialized = $profile.UserApps[0]
        $hasSource = $false
        $hasSourceFile = $false
        if ($serialized -is [System.Collections.IDictionary]) {
            $hasSource = $serialized.Contains('Source')
            $hasSourceFile = $serialized.Contains('SourceFile')
        } else {
            $hasSource = [bool]($serialized.PSObject.Properties['Source'])
            $hasSourceFile = [bool]($serialized.PSObject.Properties['SourceFile'])
        }
        $hasSource | Should -BeFalse
        $hasSourceFile | Should -BeFalse
    }

    It 'defaults Function to AppInstall when the source entry omits it' {
        $entry = [pscustomobject]@{
            Name        = 'NoFunctionApp'
            SubCategory = 'Utilities'
            ExtraArgs   = [pscustomobject]@{ WinGetId = 'NoFunc.App' }
        }
        $profile = New-MinimalProfile -UserApps @($entry)
        $profile.UserApps[0].Function | Should -Be 'AppInstall'
    }

    It 'drops entries with no Name' {
        $entry = [pscustomobject]@{
            SubCategory = 'Utilities'
            ExtraArgs   = [pscustomobject]@{ WinGetId = 'Anonymous.App' }
        }
        $profile = New-MinimalProfile -UserApps @($entry)
        @($profile.UserApps).Count | Should -Be 0
    }

    It 'survives a full JSON round-trip via Export- / Import-ConfigurationProfile' {
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-userapps-{0}.json" -f ([guid]::NewGuid().ToString('N')))
        try {
            $entry = [pscustomobject]@{
                Name        = 'RoundTripApp'
                SubCategory = 'Productivity'
                Function    = 'AppInstall'
                Description = 'Carried across the round-trip'
                ExtraArgs   = [pscustomobject]@{ WinGetId = 'RoundTrip.App'; ChocoId = 'roundtripapp' }
            }
            $profile = New-MinimalProfile -UserApps @($entry)
            Export-ConfigurationProfile -Profile $profile -FilePath $tempFile

            # Read raw JSON to confirm the field is present even before Import.
            $raw = [System.IO.File]::ReadAllText($tempFile)
            $raw | Should -Match '"UserApps"'
            $raw | Should -Match '"RoundTripApp"'

            $reimported = Import-ConfigurationProfile -FilePath $tempFile
            @($reimported.UserApps).Count | Should -Be 1
            $reimported.UserApps[0].Name | Should -Be 'RoundTripApp'
            $reimported.UserApps[0].ExtraArgs.WinGetId | Should -Be 'RoundTrip.App'
            $reimported.SchemaVersion | Should -Be 3
        }
        finally {
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'survives IncludePaths across a JSON round-trip' {
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-include-paths-{0}.json" -f ([guid]::NewGuid().ToString('N')))
        try {
            $profile = New-MinimalProfile -IncludePaths @(
                'C:\Libraries\CustomOne.psm1'
                'C:\Libraries\CustomTwo.psd1'
            )
            Export-ConfigurationProfile -Profile $profile -FilePath $tempFile

            $raw = [System.IO.File]::ReadAllText($tempFile)
            $raw | Should -Match '"IncludePaths"'

            $reimported = Import-ConfigurationProfile -FilePath $tempFile
            @($reimported.IncludePaths).Count | Should -Be 2
            $reimported.IncludePaths | Should -Contain 'C:\Libraries\CustomOne.psm1'
            $reimported.IncludePaths | Should -Contain 'C:\Libraries\CustomTwo.psd1'
        }
        finally {
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Save-BaselineUserAppEntriesFromProfile' {
    BeforeEach {
        $script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-userapps-restore-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $script:Sandbox -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:Sandbox) { Remove-Item -LiteralPath $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes one JSON file per profile entry under the target directory' {
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'AppOne'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ WinGetId = 'App.One' } }
                [pscustomobject]@{ Name = 'AppTwo'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ ChocoId = 'apptwo' } }
            )
        }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 2
        @($result.Skipped).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:Sandbox -Filter '*.json').Count | Should -Be 2
    }

    It 'persists each entry in the single-entry catalog shape (Tab=Applications + Entries[])' {
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'CatalogShape'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ WinGetId = 'Catalog.Shape' } }
            )
        }
        $null = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        $written = Get-ChildItem -LiteralPath $script:Sandbox -Filter '*.json' | Select-Object -First 1
        $payload = (Get-Content -LiteralPath $written.FullName -Raw) | ConvertFrom-Json
        $payload.Tab | Should -Be 'Applications'
        @($payload.Entries).Count | Should -Be 1
        $payload.Entries[0].Name | Should -Be 'CatalogShape'
    }

    It 'skips entries that collide with existing user-app files by Name' {
        $existing = '{ "Tab": "Applications", "Entries": [ { "Name": "Existing", "SubCategory": "Utilities", "Function": "AppInstall", "ExtraArgs": { "WinGetId": "Existing.App" } } ] }'
        Set-Content -LiteralPath (Join-Path $script:Sandbox 'existing.json') -Value $existing -Encoding UTF8
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'Existing'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ WinGetId = 'Different.Id' } }
            )
        }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 0
        @($result.Skipped).Count | Should -Be 1
        $result.Skipped[0].Name | Should -Be 'Existing'
        $result.Skipped[0].Reason | Should -Match 'already exists'
    }

    It 'skips entries that collide by WinGetId even when Name differs' {
        $existing = '{ "Tab": "Applications", "Entries": [ { "Name": "ExistingByName", "SubCategory": "Utilities", "Function": "AppInstall", "ExtraArgs": { "WinGetId": "Shared.WinGetId" } } ] }'
        Set-Content -LiteralPath (Join-Path $script:Sandbox 'existing.json') -Value $existing -Encoding UTF8
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'DifferentName'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ WinGetId = 'Shared.WinGetId' } }
            )
        }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 0
        @($result.Skipped).Count | Should -Be 1
        $result.Skipped[0].Reason | Should -Match 'WinGetId'
    }

    It 'skips entries that fail Test-BaselineUserAppEntry validation' {
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'NoIds'; SubCategory = 'Utilities' }
            )
        }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 0
        @($result.Skipped).Count | Should -Be 1
        $result.Skipped[0].Reason | Should -Match 'WinGetId|ChocoId'
    }

    It 'returns empty result when the profile carries no UserApps field' {
        $profile = [pscustomobject]@{ Name = 'OldProfile'; SchemaVersion = 2 }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 0
        @($result.Skipped).Count | Should -Be 0
        @($result.Failed).Count | Should -Be 0
    }

    It 'returns empty result when the profile carries an empty UserApps array' {
        $profile = [pscustomobject]@{ UserApps = @() }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 0
    }

    It 'creates the target directory if it does not exist' {
        $missingDir = Join-Path $script:Sandbox 'nested/created/by-test'
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'NestedDir'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ WinGetId = 'Nested.Dir' } }
            )
        }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $missingDir
        @($result.Imported).Count | Should -Be 1
        Test-Path -LiteralPath $missingDir | Should -BeTrue
    }

    It 'suffixes filenames -2, -3 when a sanitized slug already exists on disk' {
        Set-Content -LiteralPath (Join-Path $script:Sandbox 'My_App.json') -Value '{}' -Encoding UTF8
        $profile = [pscustomobject]@{
            UserApps = @(
                [pscustomobject]@{ Name = 'My App'; SubCategory = 'Utilities'; Function = 'AppInstall'; ExtraArgs = [pscustomobject]@{ WinGetId = 'My.App' } }
            )
        }
        $result = Save-BaselineUserAppEntriesFromProfile -Profile $profile -Directory $script:Sandbox
        @($result.Imported).Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:Sandbox 'My_App-2.json') | Should -BeTrue
    }
}

Describe 'SharedHelpers manifest exports' {
    It 'exports Save-BaselineUserAppEntriesFromProfile' {
        $script:SharedHelpersContent | Should -Match "'Save-BaselineUserAppEntriesFromProfile'"
    }
}

Describe 'GUI Export-Config wiring' {
    It 'loads user-app entries via Get-BaselineUserAppEntries before building the profile' {
        $script:ActionHandlersContent | Should -Match "Get-Command -Name 'Get-BaselineUserAppEntries'"
        $script:ActionHandlersContent | Should -Match '\$userAppResult = Get-BaselineUserAppEntries'
    }

    It 'passes the snapshot to New-ConfigurationProfile via -UserApps' {
        $script:ActionHandlersContent | Should -Match '-UserApps @\(\$userAppSnapshot\)'
    }

    It 'wraps the user-apps load in a debug-routed try/catch' {
        $script:ActionHandlersContent | Should -Match "Source 'ActionHandlers\.ExportConfigProfile\.UserApps'"
    }
}

Describe 'GUI Import-Config wiring' {
    It 'detects UserApps on the imported profile' {
        $script:ActionHandlersContent | Should -Match "Properties\['UserApps'\]"
    }

    It 'prompts the user with Yes/No/Cancel before restoring user apps' {
        $script:ActionHandlersContent | Should -Match "Buttons @\('Yes','No','Cancel'\)"
    }

    It 'cancels the entire import when the user clicks Cancel on the user-apps prompt' {
        $idx = $script:ActionHandlersContent.IndexOf("if (`$userAppChoice -eq 'Cancel')")
        $idx | Should -BeGreaterThan 0
    }

    It 'invokes Save-BaselineUserAppEntriesFromProfile when the user accepts' {
        $script:ActionHandlersContent | Should -Match 'Save-BaselineUserAppEntriesFromProfile -Profile \$importedProfile'
    }

    It 'refreshes the applications catalog after a successful restore' {
        $idx = $script:ActionHandlersContent.IndexOf("if (`$userAppChoice -eq 'Yes')")
        $tail = $script:ActionHandlersContent.Substring($idx)
        $tail | Should -Match 'Get-BaselineApplicationsCatalog -Force'
        $tail | Should -Match 'Build-AppsViewCards'
    }

    It 'routes user-app catalog refresh failures through Write-SwallowedException' {
        $idx = $script:ActionHandlersContent.IndexOf("if (`$userAppChoice -eq 'Yes')")
        $tail = $script:ActionHandlersContent.Substring($idx)
        $tail | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.ImportConfigProfile\.RefreshUserAppsCatalog'''
    }

    It 'short-circuits to a UserApps-only success path when the profile has no matching tweaks' {
        $script:ActionHandlersContent | Should -Match 'Imported \{0\} custom app definition\(s\) from profile'
    }
}
