Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/UserApps.Helpers.ps1'
    . $filePath
}

Describe 'Get-BaselineUserAppsDirectory' {
    BeforeEach {
        Remove-Item -LiteralPath Env:BASELINE_USER_APPS_DIR -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_USER_APPS_DIR -ErrorAction SilentlyContinue
    }

    It 'returns the override path when BASELINE_USER_APPS_DIR is set' {
        $env:BASELINE_USER_APPS_DIR = 'C:\Sandbox\BaselineUserApps'
        Get-BaselineUserAppsDirectory | Should -Be 'C:\Sandbox\BaselineUserApps'
    }

    It 'falls through to LocalAppData\Baseline\UserApps when no override is set' {
        $env:LOCALAPPDATA = 'C:\TestLocalAppData'
        Get-BaselineUserAppsDirectory | Should -Be 'C:\TestLocalAppData\Baseline\UserApps'
    }

    It 'derives a profile-relative path when LOCALAPPDATA is empty' {
        $originalLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = ''
            $env:USERPROFILE = 'C:\Users\TestUser'
            Get-BaselineUserAppsDirectory | Should -Be 'C:\Users\TestUser\AppData\Local\Baseline\UserApps'
        }
        finally {
            $env:LOCALAPPDATA = $originalLocalAppData
        }
    }
}

Describe 'Test-BaselineUserAppEntry' {
    It 'accepts a minimal valid hashtable entry' {
        $entry = @{
            Name        = 'Notepad++'
            SubCategory = 'Utilities'
            ExtraArgs   = @{ WinGetId = 'Notepad++.Notepad++' }
        }
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'accepts a pscustomobject entry' {
        $entry = [pscustomobject]@{
            Name        = 'Notepad++'
            SubCategory = 'Utilities'
            ExtraArgs   = [pscustomobject]@{ WinGetId = 'Notepad++.Notepad++' }
        }
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeTrue
    }

    It 'accepts an entry with only ChocoId (no WinGetId)' {
        $entry = @{
            Name        = 'SomeApp'
            SubCategory = 'Utilities'
            ExtraArgs   = @{ ChocoId = 'someapp' }
        }
        Test-BaselineUserAppEntry -Entry $entry | Select-Object -ExpandProperty IsValid | Should -BeTrue
    }

    It 'rejects $null entries' {
        $result = Test-BaselineUserAppEntry -Entry $null
        $result.IsValid | Should -BeFalse
        $result.Errors[0] | Should -Match 'is \$null'
    }

    It 'rejects entries missing Name' {
        $entry = @{
            SubCategory = 'Utilities'
            ExtraArgs   = @{ WinGetId = 'Foo.Bar' }
        }
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match "'Name' is required"
    }

    It 'rejects entries with whitespace-only Name' {
        $entry = @{
            Name        = '   '
            SubCategory = 'Utilities'
            ExtraArgs   = @{ WinGetId = 'Foo.Bar' }
        }
        Test-BaselineUserAppEntry -Entry $entry | Select-Object -ExpandProperty IsValid | Should -BeFalse
    }

    It 'rejects entries missing SubCategory' {
        $entry = @{
            Name      = 'Foo'
            ExtraArgs = @{ WinGetId = 'Foo.Bar' }
        }
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match "'SubCategory' is required"
    }

    It 'rejects entries with neither WinGetId nor ChocoId' {
        $entry = @{
            Name        = 'Foo'
            SubCategory = 'Utilities'
            ExtraArgs   = @{}
        }
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match "WinGetId.*ChocoId"
    }

    It 'rejects entries with no ExtraArgs at all' {
        $entry = @{
            Name        = 'Foo'
            SubCategory = 'Utilities'
        }
        Test-BaselineUserAppEntry -Entry $entry | Select-Object -ExpandProperty IsValid | Should -BeFalse
    }

    It 'rejects entries with Function != AppInstall (security: prevent registry-write smuggling)' {
        $entry = @{
            Name        = 'EvilEntry'
            Function    = 'Set-RegistryValueSafe'
            SubCategory = 'Utilities'
            ExtraArgs   = @{ WinGetId = 'Foo.Bar' }
        }
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match "'Function' must be 'AppInstall'"
    }

    It 'accepts entries with explicit Function = AppInstall' {
        $entry = @{
            Name        = 'Foo'
            Function    = 'AppInstall'
            SubCategory = 'Utilities'
            ExtraArgs   = @{ WinGetId = 'Foo.Bar' }
        }
        Test-BaselineUserAppEntry -Entry $entry | Select-Object -ExpandProperty IsValid | Should -BeTrue
    }

    It 'reports multiple errors at once when several fields are missing' {
        $entry = @{}
        $result = Test-BaselineUserAppEntry -Entry $entry
        $result.IsValid | Should -BeFalse
        $result.Errors.Count | Should -BeGreaterOrEqual 3
    }

    It 'rejects raw scalar entries (string, int)' {
        Test-BaselineUserAppEntry -Entry 'just a string' | Select-Object -ExpandProperty IsValid | Should -BeFalse
        Test-BaselineUserAppEntry -Entry 42 | Select-Object -ExpandProperty IsValid | Should -BeFalse
    }
}

Describe 'Get-BaselineUserAppEntries' {
    BeforeEach {
        $script:sandboxRoot = Join-Path $TestDrive 'UserApps'
        $env:BASELINE_USER_APPS_DIR = $script:sandboxRoot
        if (Test-Path -LiteralPath $script:sandboxRoot) {
            Remove-Item -LiteralPath $script:sandboxRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:sandboxRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_USER_APPS_DIR -ErrorAction SilentlyContinue
    }

    It 'returns empty Entries / Warnings when the directory does not exist' {
        Remove-Item -LiteralPath $script:sandboxRoot -Recurse -Force
        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 0
        $result.Warnings.Count | Should -Be 0
    }

    It 'returns empty Entries / Warnings when the directory is empty' {
        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 0
        $result.Warnings.Count | Should -Be 0
    }

    It 'loads valid entries from a single file with the {Tab,Entries} shape' {
        $content = @'
{
    "Tab": "Applications",
    "Entries": [
        {
            "Name": "Notepad++",
            "SubCategory": "Utilities",
            "ExtraArgs": { "WinGetId": "Notepad++.Notepad++" }
        }
    ]
}
'@
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'custom.json') -Value $content -Encoding UTF8

        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].Name | Should -Be 'Notepad++'
        $result.Entries[0].Source | Should -Be 'User'
        $result.Entries[0].SourceFile | Should -BeLike '*custom.json'
        $result.Warnings.Count | Should -Be 0
    }

    It 'loads valid entries from a top-level array file' {
        $content = @'
[
    {
        "Name": "AppA",
        "SubCategory": "Utilities",
        "ExtraArgs": { "WinGetId": "User.AppA" }
    }
]
'@
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'array.json') -Value $content -Encoding UTF8

        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].Name | Should -Be 'AppA'
    }

    It 'merges entries across multiple JSON files' {
        $a = '{"Entries":[{"Name":"AppA","SubCategory":"Utilities","ExtraArgs":{"WinGetId":"User.AppA"}}]}'
        $b = '{"Entries":[{"Name":"AppB","SubCategory":"Utilities","ExtraArgs":{"WinGetId":"User.AppB"}}]}'
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'a.json') -Value $a -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'b.json') -Value $b -Encoding UTF8

        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 2
        ($result.Entries.Name | Sort-Object) -join ',' | Should -Be 'AppA,AppB'
    }

    It 'skips invalid entries and emits a warning, keeping valid siblings' {
        $content = @'
{
    "Entries": [
        { "Name": "GoodOne", "SubCategory": "Utilities", "ExtraArgs": { "WinGetId": "User.Good" } },
        { "Name": "BadOne" }
    ]
}
'@
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'mixed.json') -Value $content -Encoding UTF8

        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].Name | Should -Be 'GoodOne'
        $result.Warnings.Count | Should -Be 1
        $result.Warnings[0] | Should -Match 'BadOne'
    }

    It 'emits a warning and keeps going when a JSON file is malformed' {
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'broken.json') -Value '{ this is not json' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'good.json') -Value '{"Entries":[{"Name":"OkApp","SubCategory":"Utilities","ExtraArgs":{"WinGetId":"X.Y"}}]}' -Encoding UTF8

        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].Name | Should -Be 'OkApp'
        $result.Warnings.Count | Should -Be 1
        $result.Warnings[0] | Should -Match 'broken.json'
    }

    It 'emits a warning when a JSON file has neither Entries nor a top-level array' {
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'wrong-shape.json') -Value '{"foo":"bar"}' -Encoding UTF8

        $result = Get-BaselineUserAppEntries
        $result.Entries.Count | Should -Be 0
        $result.Warnings.Count | Should -Be 1
        $result.Warnings[0] | Should -Match "does not contain an 'Entries' array"
    }

    It 'honours the -Path parameter as an explicit override' {
        $alt = Join-Path $TestDrive 'AltUserApps'
        New-Item -ItemType Directory -Path $alt -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $alt 'alt.json') -Value '{"Entries":[{"Name":"AltOnly","SubCategory":"Utilities","ExtraArgs":{"WinGetId":"X.Y"}}]}' -Encoding UTF8

        $result = Get-BaselineUserAppEntries -Path $alt
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].Name | Should -Be 'AltOnly'
    }
}

Describe 'Merge-BaselineUserAppEntries' {
    It 'returns built-in entries first, user entries appended' {
        $built = @(
            [pscustomobject]@{ Name = 'BuiltA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'B.A' } }
        )
        $user = @(
            [pscustomobject]@{ Name = 'UserA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'U.A' } }
        )
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 2
        $result.Entries[0].Name | Should -Be 'BuiltA'
        $result.Entries[1].Name | Should -Be 'UserA'
        $result.Warnings.Count | Should -Be 0
    }

    It 'drops user entries whose Name collides with a built-in entry' {
        $built = @([pscustomobject]@{ Name = 'Notepad++'; ExtraArgs = [pscustomobject]@{ WinGetId = 'B.NP' } })
        $user = @([pscustomobject]@{ Name = 'Notepad++'; ExtraArgs = [pscustomobject]@{ WinGetId = 'U.NP' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].ExtraArgs.WinGetId | Should -Be 'B.NP'
        $result.Warnings.Count | Should -Be 1
        $result.Warnings[0] | Should -Match "Name 'Notepad\+\+'"
    }

    It 'name collision is case-insensitive' {
        $built = @([pscustomobject]@{ Name = 'notepad++'; ExtraArgs = [pscustomobject]@{ WinGetId = 'B.NP' } })
        $user = @([pscustomobject]@{ Name = 'NOTEPAD++'; ExtraArgs = [pscustomobject]@{ WinGetId = 'U.NP' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Warnings.Count | Should -Be 1
    }

    It 'drops user entries whose WinGetId collides with a built-in entry' {
        $built = @([pscustomobject]@{ Name = 'BuiltA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'Shared.Id' } })
        $user = @([pscustomobject]@{ Name = 'UserA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'shared.id' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Warnings[0] | Should -Match "WinGetId 'shared.id'"
    }

    It 'drops user entries whose ChocoId collides with a built-in entry' {
        $built = @([pscustomobject]@{ Name = 'BuiltA'; ExtraArgs = [pscustomobject]@{ ChocoId = 'shared-choco' } })
        $user = @([pscustomobject]@{ Name = 'UserA'; ExtraArgs = [pscustomobject]@{ ChocoId = 'shared-choco' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Warnings[0] | Should -Match "ChocoId 'shared-choco'"
    }

    It 'drops a second user entry when it collides with a previously-merged user entry' {
        $built = @()
        $user = @(
            [pscustomobject]@{ Name = 'UserA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'U.A' } }
            [pscustomobject]@{ Name = 'UserA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'U.A2' } }
        )
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].ExtraArgs.WinGetId | Should -Be 'U.A'
        $result.Warnings.Count | Should -Be 1
    }

    It 'tolerates an empty user list' {
        $built = @([pscustomobject]@{ Name = 'BuiltA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'B.A' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries @()
        $result.Entries.Count | Should -Be 1
        $result.Warnings.Count | Should -Be 0
    }

    It 'tolerates an empty built-in list' {
        $user = @([pscustomobject]@{ Name = 'UserA'; ExtraArgs = [pscustomobject]@{ WinGetId = 'U.A' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries @() -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Entries[0].Name | Should -Be 'UserA'
    }

    It 'works with hashtable entries (not just pscustomobjects)' {
        $built = @(@{ Name = 'BuiltA'; ExtraArgs = @{ WinGetId = 'B.A' } })
        $user = @(@{ Name = 'BuiltA'; ExtraArgs = @{ WinGetId = 'X.A' } })
        $result = Merge-BaselineUserAppEntries -BuiltInEntries $built -UserEntries $user
        $result.Entries.Count | Should -Be 1
        $result.Warnings.Count | Should -Be 1
    }
}
