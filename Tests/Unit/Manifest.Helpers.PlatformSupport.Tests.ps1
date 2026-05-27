Set-StrictMode -Version Latest

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
    Import-Module $modulePath -Force

    function script:NewSyntheticManifestRoot {
        param(
            [Parameter(Mandatory)][string]$Json
        )
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-mtest-" + [guid]::NewGuid().ToString('N'))
        $dataDir = Join-Path $root 'Data'
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        $jsonFile = Join-Path $dataDir 'Synthetic.json'
        Set-Content -LiteralPath $jsonFile -Value $Json -Encoding UTF8
        return $root
    }
}

Describe 'Import-TweakManifestFromData PlatformSupport pass-through' {
    It 'carries a PlatformSupport block onto the loaded entry verbatim' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Synthetic Tweak",
            "Function": "Test-SyntheticTweak",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "PlatformSupport": {
                "Windows10": false,
                "Windows11": true,
                "Server": false,
                "MinBuild": 22621,
                "UnavailableReason": "Synthetic gate"
            }
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            # NOTE: do NOT wrap with @() — Import-TweakManifestFromData uses the
            # `,@(...)` return idiom; @() at the call site re-wraps and you get
            # Object[1] containing Object[N] instead of a flat Object[N].
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $manifest.Count | Should -Be 1
            $entry = $manifest[0]
            $entry.Contains('PlatformSupport') | Should -BeTrue
            $ps = $entry['PlatformSupport']
            $ps.Windows10 | Should -BeFalse
            $ps.Windows11 | Should -BeTrue
            $ps.Server | Should -BeFalse
            $ps.MinBuild | Should -Be 22621
            $ps.UnavailableReason | Should -Be 'Synthetic gate'
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'omits PlatformSupport when the JSON entry has no such block' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Plain Tweak",
            "Function": "Test-PlainTweak",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $entry = $manifest[0]
            $entry.Contains('PlatformSupport') | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'carries SupportsExecution=false through the loader verbatim' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "NotExecutable",
            "Function": "Test-NotExecutable",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "PlatformSupport": { "Windows10": true, "Windows11": true, "Server": false },
            "SupportsExecution": false
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $entry = $manifest[0]
            $entry.Contains('SupportsExecution') | Should -BeTrue
            $entry['SupportsExecution'] | Should -BeFalse
            # And the helper agrees:
            Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'carries CounterpartFunction through the loader verbatim' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Synthetic Tweak",
            "Function": "Enable-Synthetic",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "CounterpartFunction": "Disable-Synthetic"
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $entry = $manifest[0]
            $entry.Contains('CounterpartFunction') | Should -BeTrue
            $entry['CounterpartFunction'] | Should -Be 'Disable-Synthetic'
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'carries TimeoutSeconds through the loader verbatim' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Slow Tweak",
            "Function": "Test-SlowTweak",
            "Type": "Action",
            "Default": null,
            "WinDefault": null,
            "TimeoutSeconds": 900
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $entry = $manifest[0]
            $entry.Contains('TimeoutSeconds') | Should -BeTrue
            [int]$entry['TimeoutSeconds'] | Should -Be 900
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'omits SupportsExecution (defaults to executable) when JSON does not declare it' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Plain",
            "Function": "Test-PlainExec",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $entry = $manifest[0]
            $entry.Contains('SupportsExecution') | Should -BeFalse
            # Default-presumed executable per spec.
            Test-BaselineEntrySupportsExecution -Entry $entry | Should -BeTrue
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'cascades a file-level PlatformSupportDefault onto entries that omit their own block' {
        $json = @'
{
    "Tab": "Synthetic",
    "PlatformSupportDefault": {
        "Windows10": true,
        "Windows11": true,
        "Server": false,
        "UnavailableReason": "Client-only synthetic"
    },
    "Entries": [
        {
            "Name": "Inherits Default",
            "Function": "Test-InheritsDefault",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false
        },
        {
            "Name": "Has Override",
            "Function": "Test-HasOverride",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "PlatformSupport": { "Windows10": false, "Windows11": true, "Server": false }
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $manifest.Count | Should -Be 2
            # Entry without its own block inherits the default verbatim.
            $inh = $manifest[0]
            $inh.Contains('PlatformSupport') | Should -BeTrue
            $inh['PlatformSupport'].Windows10 | Should -BeTrue
            $inh['PlatformSupport'].Windows11 | Should -BeTrue
            $inh['PlatformSupport'].Server | Should -BeFalse
            $inh['PlatformSupport'].UnavailableReason | Should -Be 'Client-only synthetic'
            # Entry with its own block keeps it; the default does NOT clobber.
            $ovr = $manifest[1]
            $ovr['PlatformSupport'].Windows10 | Should -BeFalse
            $ovr['PlatformSupport'].Windows11 | Should -BeTrue
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'plays nicely with Update-BaselineManifestAvailability after load' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Win11 Only",
            "Function": "Test-Win11Only",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "PlatformSupport": { "Windows10": false, "Windows11": true, "Server": false }
        },
        {
            "Name": "Cross-platform",
            "Function": "Test-Shared",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            $sys = Get-BaselineSystemPlatformInfo -Override @{ MajorVersion = 10; BuildNumber = 19045; ProductType = 1 }
            $null = Update-BaselineManifestAvailability -Manifest $manifest -SystemInfo $sys
            $manifest[0]['Availability'].Available | Should -BeFalse
            $manifest[0]['Availability'].Reason   | Should -Be 'Not available on Windows 10.'
            $manifest[1]['Availability'].Available | Should -BeTrue
            $manifest[1]['Availability'].Source   | Should -Be 'NoPlatformMetadata'
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}

Describe 'Test-TweakManifestIntegrity PlatformSupport hint validation' {
    BeforeEach {
        $script:CapturedManifestWarnings = [System.Collections.Generic.List[string]]::new()
        function global:LogWarning {
            param([string]$Message)
            [void]$script:CapturedManifestWarnings.Add([string]$Message)
        }
        function global:Write-Warning {
            param([string]$Message)
            [void]$script:CapturedManifestWarnings.Add([string]$Message)
        }
    }

    AfterEach {
        Remove-Item function:LogWarning -ErrorAction SilentlyContinue
        Remove-Item function:Write-Warning -ErrorAction SilentlyContinue
    }

    It 'warns when OS-sensitive Tags are present without PlatformSupport' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Widgets Flyout",
            "Function": "Test-WidgetsFlyout",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "Risk": "Low",
            "PresetTier": "Basic",
            "Impact": false,
            "Safe": true,
            "RequiresRestart": false,
            "Restorable": true,
            "RecoveryLevel": "Direct",
            "WhyThisMatters": "Keeps the UI toggle available.",
            "Tags": [ "Windows11Only", "widgets" ]
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            Test-TweakManifestIntegrity -Manifest $manifest

            $script:CapturedManifestWarnings.Count | Should -Be 2
            $script:CapturedManifestWarnings[0] | Should -Match 'Manifest validation: 1 issue\(s\) found'
            $script:CapturedManifestWarnings[1] | Should -Match 'Test-WidgetsFlyout : OS-sensitive Tags'
            $script:CapturedManifestWarnings[1] | Should -Match 'windows11only'
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'stays quiet when PlatformSupport is declared for the same OS-sensitive Tags' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Widgets Flyout",
            "Function": "Test-WidgetsFlyout",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "Risk": "Low",
            "PresetTier": "Basic",
            "Impact": false,
            "Safe": true,
            "RequiresRestart": false,
            "Restorable": true,
            "RecoveryLevel": "Direct",
            "WhyThisMatters": "Keeps the UI toggle available.",
            "Tags": [ "Windows11Only", "widgets" ],
            "PlatformSupport": { "Windows10": false, "Windows11": true, "Server": false }
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            Test-TweakManifestIntegrity -Manifest $manifest

            $script:CapturedManifestWarnings.Count | Should -Be 0
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'stays quiet when CounterpartFunction resolves to another manifest entry' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Enable Synthetic",
            "Function": "Enable-Synthetic",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "Risk": "Low",
            "PresetTier": "Basic",
            "Impact": false,
            "Safe": true,
            "RequiresRestart": false,
            "Restorable": true,
            "RecoveryLevel": "Direct",
            "CounterpartFunction": "Disable-Synthetic"
        },
        {
            "Name": "Disable Synthetic",
            "Function": "Disable-Synthetic",
            "Type": "Toggle",
            "Default": true,
            "WinDefault": true,
            "Risk": "Low",
            "PresetTier": "Basic",
            "Impact": false,
            "Safe": true,
            "RequiresRestart": false,
            "Restorable": true,
            "RecoveryLevel": "Direct"
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            Test-TweakManifestIntegrity -Manifest $manifest

            $script:CapturedManifestWarnings.Count | Should -Be 0
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'warns when CounterpartFunction does not resolve to a manifest entry' {
        $json = @'
{
    "Tab": "Synthetic",
    "Entries": [
        {
            "Name": "Enable Synthetic",
            "Function": "Enable-Synthetic",
            "Type": "Toggle",
            "Default": false,
            "WinDefault": false,
            "Risk": "Low",
            "PresetTier": "Basic",
            "Impact": false,
            "Safe": true,
            "RequiresRestart": false,
            "Restorable": true,
            "RecoveryLevel": "Direct",
            "CounterpartFunction": "Missing-Synthetic"
        }
    ]
}
'@
        $root = NewSyntheticManifestRoot -Json $json
        try {
            $manifest = Import-TweakManifestFromData -ModuleRoot $root
            Test-TweakManifestIntegrity -Manifest $manifest

            $script:CapturedManifestWarnings.Count | Should -Be 2
            $script:CapturedManifestWarnings[1] | Should -Match 'CounterpartFunction'
            $script:CapturedManifestWarnings[1] | Should -Match 'Missing-Synthetic'
        } finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
