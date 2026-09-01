$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target=Join-Path $repoRoot 'bootstrap.ps1'
if(-not(Test-Path -LiteralPath $target)){throw "Required file not found: $target"}

$text=Get-Content -LiteralPath $target -Raw

if($text -match 'RBZ080RC13A_PARSE_JSON_CONFIG'){
    Write-Host 'RBZ PC Health v0.8.0 RC13a is already applied.' -ForegroundColor Yellow
    exit 0
}

if(-not $text.Contains('RBZ080RC13_STABLE_SESSION_CLEANUP')){
    throw 'RC13a baseline validation failed. Apply RC13 first.'
}

$old='$config=Invoke-RestMethod -Uri $ConfigUrl -UseBasicParsing'
if(-not $text.Contains($old)){
    throw 'RC13a could not locate the stable bootstrap config-loading line.'
}

$new=@'
# RBZ080RC13A_PARSE_JSON_CONFIG
# raw.githubusercontent.com is commonly returned as text/plain to Windows
# PowerShell 5.1, so Invoke-RestMethod may return a String rather than a
# deserialized JSON object. Parse the response content explicitly.
$configResponse=Invoke-WebRequest -Uri $ConfigUrl -UseBasicParsing
if([string]::IsNullOrWhiteSpace([string]$configResponse.Content)){
    throw "RBZ configuration download returned empty content: $ConfigUrl"
}
try{
    $config=$configResponse.Content | ConvertFrom-Json -ErrorAction Stop
}
catch{
    throw "RBZ configuration could not be parsed as JSON: $($_.Exception.Message)"
}
'@

$text=$text.Replace($old,$new.TrimEnd())
Set-Content -LiteralPath $target -Value $text -Encoding UTF8

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $target,[ref]$tokens,[ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $message=($errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"
    throw "bootstrap.ps1 parser check failed after RC13a:`n$message"
}

Write-Host 'RBZ PC Health v0.8.0 RC13a applied.' -ForegroundColor Green
Write-Host 'Stable bootstrap now explicitly parses downloaded settings.json.' -ForegroundColor Cyan
Write-Host 'bootstrap.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
