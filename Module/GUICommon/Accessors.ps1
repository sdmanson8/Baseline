<#
    .SYNOPSIS
#>
function Test-GuiCommonObjectField
{
	param([object]$Object, [string]$FieldName)
	if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($FieldName)) { return $false }
	if ($Object -is [System.Collections.IDictionary]) { return [bool]$Object.Contains($FieldName) }
	return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
}

<#
    .SYNOPSIS
#>
function Get-GuiCommonObjectField
{
	param([object]$Object, [string]$FieldName)
	if (-not (Test-GuiCommonObjectField -Object $Object -FieldName $FieldName)) { return $null }
	if ($Object -is [System.Collections.IDictionary]) { return $Object[$FieldName] }
	return $Object.$FieldName
}
