for ($__hi = 0; $__hi -lt $Script:TweakManifest.Count; $__hi++)
	{
		$__t = $Script:TweakManifest[$__hi]
		if (-not $__t) { continue }
		$__owning = Resolve-GuiPrimaryTabForTweak -Tweak $__t
		if (-not [string]::IsNullOrWhiteSpace([string]$__owning))
		{
			if (-not $Script:TweakIndicesByPrimaryTab.ContainsKey($__owning))
			{
				$Script:TweakIndicesByPrimaryTab[$__owning] = [System.Collections.Generic.List[int]]::new()
			}
			[void]$Script:TweakIndicesByPrimaryTab[$__owning].Add($__hi)
		}
		$__sb = [System.Text.StringBuilder]::new(256)
		foreach ($__p in @([string]$__t.Name, [string]$__t.Description, [string]$__t.Detail, [string]$__t.WhyThisMatters,
		                    [string]$__t.Category, [string]$__t.SubCategory, [string]$__t.Function, $__owning,
		                    [string]$__t.Risk, [string]$__t.PresetTier))
		{
			if (-not [string]::IsNullOrWhiteSpace($__p)) { [void]$__sb.Append($__p); [void]$__sb.Append(' ') }
		}
		if ($__t.Tags) { $__tags = $__t.Tags -join ' '; if ($__tags) { [void]$__sb.Append($__tags); [void]$__sb.Append(' ') } }
		[void]$__sb.Append($(if ($__t.Safe) { 'safe' } else { 'not-safe' }))
		[void]$__sb.Append(' ')
		[void]$__sb.Append($(if ($__t.Impact) { 'impact' } else { 'standard' }))
		[void]$__sb.Append(' ')
		[void]$__sb.Append($(if ($__t.RequiresRestart) { 'restart reboot requires-restart' } else { 'no-restart' }))
		$Script:TweakSearchHaystacks[$__hi] = $__sb.ToString()
	}
