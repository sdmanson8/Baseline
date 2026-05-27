if ($Splash -is [hashtable])
	{
		if ($Splash.ContainsKey('Window'))            { $window         = $Splash['Window'] }
		if ($Splash.ContainsKey('Dispatcher'))        { $dispatcher     = $Splash['Dispatcher'] }
		if ($Splash.ContainsKey('StepGlyphs'))        { $stepGlyphs     = $Splash['StepGlyphs'] }
		if ($Splash.ContainsKey('StepIdleDots'))      { $stepIdleDots   = $Splash['StepIdleDots'] }
		if ($Splash.ContainsKey('StepPulseDots'))     { $stepPulseDots  = $Splash['StepPulseDots'] }
		if ($Splash.ContainsKey('StepChecks'))        { $stepChecks     = $Splash['StepChecks'] }
		if ($Splash.ContainsKey('StepLabels'))        { $stepLabels     = $Splash['StepLabels'] }
		if ($Splash.ContainsKey('StepStates'))        { $stepStates     = $Splash['StepStates'] }
		if ($Splash.ContainsKey('StatusText'))        { $statusControl  = $Splash['StatusText'] }
		if ($Splash.ContainsKey('SubActionPanel'))    { $subActionPanel = $Splash['SubActionPanel'] }
		if ($Splash.ContainsKey('ProgressBar'))       { $progressBar    = $Splash['ProgressBar'] }
		if ($Splash.ContainsKey('SplashTheme'))       { $theme          = $Splash['SplashTheme'] }
		if ($Splash.ContainsKey('StepOrder') -and $Splash['StepOrder']) { $stepOrder = @($Splash['StepOrder']) }
	}
