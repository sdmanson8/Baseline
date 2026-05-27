if (-not $Script:ManifestLoadedFromData)
	{
		try
		{
			$Script:TweakManifest = Import-TweakManifestFromData `
				-DetectScriptblocks $Script:DetectScriptblocks `
				-VisibleIfScriptblocks $Script:VisibleIfScriptblocks
			& $traceGuiStartup 'Manifest import complete'
			# Keep startup limited to runtime-required manifest work. Structural
			# integrity validation is a maintainer/test concern; it only emits
			# warnings and does not change rendered tweak behavior.
			# Stamp Availability onto every entry so the row-factory hide-unavailable
			# gate (TweakRowFactory.ps1) and the apply-path partition
			# (ExecutionOrchestration.ps1) both see a populated block instead of
			# treating absence as "available". No override -> real host platform.
			try
			{
				$Script:BaselineSystemPlatformInfo = Get-BaselineSystemPlatformInfo
				$null = Update-BaselineManifestAvailability `
					-Manifest $Script:TweakManifest `
					-SystemInfo $Script:BaselineSystemPlatformInfo
				$null = Update-BaselineManifestExecutionSupport -Manifest $Script:TweakManifest
				& $traceGuiStartup 'Manifest availability stamped'
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'GUI.ManifestLoad.AvailabilityStamp'
			}
			$Script:ManifestLoadedFromData = $true
			$Script:Ctx.Data.TweakManifest = $Script:TweakManifest
			$Script:Ctx.Data.ManifestLoaded = $true
		}
		catch
		{
			Write-Warning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to load tweak metadata from Module/Data')
			$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
	}
}
