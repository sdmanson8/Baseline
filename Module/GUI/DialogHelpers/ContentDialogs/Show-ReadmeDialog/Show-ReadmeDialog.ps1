try
		{
			$webView2RuntimeLoaded = Test-BaselineWebView2RuntimeReady
			if (-not $webView2RuntimeLoaded)
			{
				[void](Initialize-BaselineWebView2Runtime)
			}
			if ((Test-BaselineWebView2RuntimeReady) -and $readmeWebHost)
			{
				$readmeWebView = New-Object Microsoft.Web.WebView2.WinForms.WebView2
				$readmeWebView.Dock = [System.Windows.Forms.DockStyle]::Fill
				$readmeWebHost.Child = $readmeWebView
				$null = $readmeWebView.EnsureCoreWebView2Async().GetAwaiter().GetResult()
				$webView2Ready = $true

				$readmeWebView.CoreWebView2.add_NavigationStarting({
					param($navSender, $navArgs)
					$null = $navSender
					try
					{
						$navUri = [string]$navArgs.Uri
						if ([string]::IsNullOrWhiteSpace($navUri)) { return }
						if ($navUri.StartsWith('about:', [System.StringComparison]::OrdinalIgnoreCase) -or $navUri.StartsWith('data:', [System.StringComparison]::OrdinalIgnoreCase)) { return }
						if ($navUri.StartsWith('http://', [System.StringComparison]::OrdinalIgnoreCase) -or $navUri.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase) -or $navUri.StartsWith('mailto:', [System.StringComparison]::OrdinalIgnoreCase))
						{
							$navArgs.Cancel = $true
							try { [System.Diagnostics.Process]::Start($navUri) | Out-Null }
							catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.OpenReadmeWebLink' -Severity Warning }
						}
						elseif ($navUri.StartsWith('file://', [System.StringComparison]::OrdinalIgnoreCase))
						{
							$navArgs.Cancel = $true
							try
							{
								$localPath = [System.Uri]::new($navUri).LocalPath
								[System.Diagnostics.Process]::Start($localPath) | Out-Null
							}
							catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.OpenReadmeFileLink' -Severity Warning }
						}
					}
					catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.ReadmeWebViewNavigation' -Severity Warning }
				})
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\ContentDialogs\Show-ReadmeDialog\Show-ReadmeDialog.ps1:45' -Severity Debug }

			$webView2Ready = $false
			$readmeWebView = $null
		}

		$showReadmeAsWebView = {
			param([string]$Html)

			if ($webView2Ready -and $readmeWebView)
			{
				$readmeFlowViewer.Document = $null
				$readmeFlowViewer.Visibility = [System.Windows.Visibility]::Collapsed
				$readmeWebHost.Visibility = [System.Windows.Visibility]::Visible
				$readmeWebView.NavigateToString($Html)
				return $true
			}

			return $false
		}.GetNewClosure()

		$wireFlowDocumentNavigation = {
			param(
				[Parameter(Mandatory = $true)]
				$Result,

				[string]$ReadmeDirectory
			)

			if (-not $Result) { return }
			$anchorMap = $Result.AnchorMap
			$localReadmeDir = [string]$ReadmeDirectory

			foreach ($hyperlink in $Result.Hyperlinks)
			{
				$hyperlink.add_RequestNavigate({
					param($linkSender, $linkArgs)
					try
					{
						$linkUri = if ($linkArgs -and $linkArgs.Uri) { $linkArgs.Uri } else { $linkSender.NavigateUri }
						if (-not $linkUri) { return }
						if ($linkArgs) { $linkArgs.Handled = $true }
						$uriText = [string]$linkUri.OriginalString
						if ([string]::IsNullOrWhiteSpace($uriText)) { return }

						if ($uriText.StartsWith('#'))
						{
							$fragment = $uriText.Substring(1)
							if ($anchorMap -and $anchorMap.ContainsKey($fragment))
							{
								$target = $anchorMap[$fragment]
								try { $target.BringIntoView() }
								catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.ReadmeAnchorBringIntoView' -Severity Debug }
							}
						}
						elseif ($linkUri.IsAbsoluteUri)
						{
							$scheme = [string]$linkUri.Scheme
							if ($scheme -eq 'http' -or $scheme -eq 'https' -or $scheme -eq 'mailto')
							{
								try { [System.Diagnostics.Process]::Start($linkUri.AbsoluteUri) | Out-Null }
								catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.OpenFlowDocumentWebLink' -Severity Warning }
							}
							elseif ($scheme -eq 'file')
							{
								try { [System.Diagnostics.Process]::Start($linkUri.LocalPath) | Out-Null }
								catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.OpenFlowDocumentFileLink' -Severity Warning }
							}
						}
						else
						{
							$resolved = $uriText
							if (-not [string]::IsNullOrWhiteSpace($localReadmeDir))
							{
								try { $resolved = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($localReadmeDir, $uriText)) }
								catch
								{
									Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.ResolveRelativeReadmeLink' -Severity Debug
									$resolved = $uriText
								}
							}
							if (Test-Path -LiteralPath $resolved -ErrorAction SilentlyContinue)
							{
								try { [System.Diagnostics.Process]::Start($resolved) | Out-Null }
								catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.OpenRelativeReadmeLink' -Severity Warning }
							}
						}
					}
					catch { Write-SwallowedException -ErrorRecord $_ -Source 'ContentDialogs.FlowDocumentNavigation' -Severity Warning }
				}.GetNewClosure())
			}
		}.GetNewClosure()

		$loadReadmeContent = {
			param([hashtable]$ThemeOverride = $null)

			$activeTheme = & $getReadmeTheme -ThemeOverride $ThemeOverride
			& $applyReadmeDialogTheme -ThemeOverride $activeTheme

			$resolvedPath = if ([string]::IsNullOrWhiteSpace([string]$ReadmePath)) { & $resolveReadmePathScript } else { $ReadmePath }
			$txtReadmePath.Text = if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) { '' } else { $resolvedPath }

			if ([string]::IsNullOrWhiteSpace([string]$resolvedPath) -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf -ErrorAction SilentlyContinue))
			{
				$message = if ([string]::IsNullOrWhiteSpace([string]$resolvedPath))
				{
					$missingMessage
				}
				else
				{
					"{0}`r`n`r`n{1}" -f $missingMessage, $resolvedPath
				}
				& $showReadmeAsText -Content $message -ForegroundHex $activeTheme.RiskHighBadge -ThemeOverride $activeTheme
				return
			}

			try
			{
				$resolvedFullPath = [System.IO.Path]::GetFullPath($resolvedPath)
				$txtReadmePath.Text = $resolvedFullPath
				$markdownText = [System.IO.File]::ReadAllText($resolvedFullPath)
				$html = ConvertFrom-BaselineMarkdownToHtml `
					-Markdown $markdownText `
					-BackgroundColor $activeTheme.SearchBg `
					-ForegroundColor $activeTheme.TextPrimary `
					-MutedForegroundColor $activeTheme.TextMuted `
					-LinkColor $activeTheme.AccentBlue `
					-CodeBackgroundColor $activeTheme.HeaderBg

				if (-not (& $showReadmeAsWebView -Html $html))
				{
					$flowDocument = $null
					$anchoredResult = $null
					if (Test-BaselineMarkdownRuntimeReady)
					{
						try { $anchoredResult = ConvertFrom-BaselineMarkdownToAnchoredFlowDocument -Markdown $markdownText }
						catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\ContentDialogs\Show-ReadmeDialog\Show-ReadmeDialog.ps1:181' -Severity Debug }
						 $anchoredResult = $null }
						if ($anchoredResult) { $flowDocument = $anchoredResult.Document }
					}

					if ($flowDocument)
					{
						$readmeDirectory = [System.IO.Path]::GetDirectoryName($resolvedFullPath)
						if ($anchoredResult) { & $wireFlowDocumentNavigation -Result $anchoredResult -ReadmeDirectory $readmeDirectory }
						& $showReadmeAsFlowDocument -Document $flowDocument -ThemeOverride $activeTheme
					}
					else
					{
						& $showReadmeAsText -Content $markdownText -ForegroundHex $activeTheme.TextSecondary -ThemeOverride $activeTheme
					}
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\ContentDialogs\Show-ReadmeDialog\Show-ReadmeDialog.ps1:197' -Severity Debug }

				& $showReadmeAsText -Content ("Failed to read README.`r`n`r`n{0}" -f $_.Exception.Message) -ForegroundHex $activeTheme.RiskHighBadge -ThemeOverride $activeTheme
			}
		}.GetNewClosure()
