$Script:DownloadStartEvent = {
		$uri = if (Get-Variable -Name 'PendingUpdateDownloadUri' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:PendingUpdateDownloadUri } else { '' }
		if ([string]::IsNullOrWhiteSpace($uri))
		{
			LogWarning 'No resolved update release asset is available to download.'
			return
		}
		$tempPath = if (Get-Variable -Name 'PendingUpdateArchivePath' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:PendingUpdateArchivePath } else { '' }
		if ([string]::IsNullOrWhiteSpace($tempPath))
		{
			LogWarning 'No resolved update archive path is available for the download.'
			return
		}
		if ($startBaselineDownloadScript)
		{
			& $startBaselineDownloadScript -Uri $uri -DestinationPath $tempPath
		}
		else
		{
			LogWarning 'Start-BaselineDownload not available; update download action was skipped.'
		}
	}.GetNewClosure()

	$Script:DownloadExtractEvent = {
		if ($TxtDownloadProgressLabel) { $TxtDownloadProgressLabel.Text = (Get-UxLocalizedString -Key 'GuiStatusExtractingArchive' -Fallback 'Extracting archive...') }
		if ($BtnDownloadYes) { $BtnDownloadYes.IsEnabled = $false }
		if ($BtnDownloadNo) { $BtnDownloadNo.IsEnabled = $false }

		$zipPath = if (Get-Variable -Name 'PendingUpdateArchivePath' -Scope Script -ErrorAction SilentlyContinue) { [string]$Script:PendingUpdateArchivePath } else { '' }
		if ([string]::IsNullOrWhiteSpace($zipPath))
		{
			LogWarning 'No downloaded update archive path is available to extract.'
			return
		}
		$extractPath = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline_New'

		Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

		if ($TxtDownloadProgressLabel) { $TxtDownloadProgressLabel.Text = (Get-UxLocalizedString -Key 'GuiStatusReadyToRestart' -Fallback 'Ready to restart!') }

		# Add your custom bootstrap/overwrite logic here to finalize the update
	}.GetNewClosure()
