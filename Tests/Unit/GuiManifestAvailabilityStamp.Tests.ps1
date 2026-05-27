Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $guiRegionPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path $guiRegionPath
}

Describe 'GUI bootstrap PlatformSupport stamp (P2 #18)' {
    # The TweakRowFactory hide-unavailable gate and the ExecutionOrchestration
    # Not-applicable partition both read $entry.Availability. Without a stamp
    # call after manifest load, the block never gets populated and both gates
    # silently no-op. This test pins the wiring so a refactor cannot drop it.

    It 'stamps availability after importing the manifest' {
        $importIndex = $script:GuiRegionContent.IndexOf('$Script:TweakManifest = Import-TweakManifestFromData `')
        $stampIndex = $script:GuiRegionContent.IndexOf('Update-BaselineManifestAvailability `')
        $importIndex | Should -BeGreaterThan 0
        $stampIndex | Should -BeGreaterThan $importIndex
    }

    It 'keeps structural integrity validation out of the GUI startup path' {
        $script:GuiRegionContent | Should -Not -Match 'Test-TweakManifestIntegrity\s+-Manifest\s+\$Script:TweakManifest'
    }

    It 'feeds Get-BaselineSystemPlatformInfo with no override (real host) into the stamp' {
        $script:GuiRegionContent | Should -Match '\$Script:BaselineSystemPlatformInfo = Get-BaselineSystemPlatformInfo'
        $script:GuiRegionContent | Should -Match '-SystemInfo \$Script:BaselineSystemPlatformInfo'
    }

    It 'wraps the stamp in a try/catch routed through Write-SwallowedException' {
        $script:GuiRegionContent | Should -Match "Source 'GUI\.ManifestLoad\.AvailabilityStamp'"
    }

    It 'sets ManifestLoadedFromData only after the stamp has run' {
        $stampIndex = $script:GuiRegionContent.IndexOf('Update-BaselineManifestAvailability `')
        $loadedFlagIndex = $script:GuiRegionContent.IndexOf('$Script:ManifestLoadedFromData = $true')
        $stampIndex | Should -BeGreaterThan 0
        $loadedFlagIndex | Should -BeGreaterThan $stampIndex
    }
}
