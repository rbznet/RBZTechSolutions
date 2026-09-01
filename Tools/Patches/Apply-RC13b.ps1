$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target=Join-Path $repoRoot 'bootstrap.ps1'

if(-not(Test-Path -LiteralPath $target)){
    throw "Required file not found: $target"
}

$text=Get-Content -LiteralPath $target -Raw

if($text -match 'RBZ080RC13B_NORMALISE_CONFIG_CONTENT'){
    Write-Host 'RBZ PC Health v0.8.0 RC13b is already applied.' -ForegroundColor Yellow
    exit 0
}

if(-not $text.Contains('RBZ080RC13A_PARSE_JSON_CONFIG')){
    throw 'RC13b baseline validation failed. Apply RC13 and RC13a first.'
}

$old=@'
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

$new=@'
# RBZ080RC13B_NORMALISE_CONFIG_CONTENT
# Windows PowerShell 5.1 can expose Invoke-WebRequest.Content as either text
# or a byte array depending on the response/content handling. Normalise it
# to one UTF-8 string before handing it to ConvertFrom-Json.
$configResponse=Invoke-WebRequest -Uri $ConfigUrl -UseBasicParsing

if($configResponse.Content -is [byte[]]){
    $configText=[Text.Encoding]::UTF8.GetString([byte[]]$configResponse.Content)
}
else{
    $configText=[string]$configResponse.Content
}

$configText=$configText.TrimStart([char]0xFEFF)

if([string]::IsNullOrWhiteSpace($configText)){
    throw "RBZ configuration download returned empty content: $ConfigUrl"
}

try{
    $config=$configText | ConvertFrom-Json -ErrorAction Stop
}
catch{
    throw "RBZ configuration could not be parsed as JSON: $($_.Exception.Message)"
}
'@

if(-not $text.Contains($old)){
    throw 'RC13b could not locate the RC13a configuration parsing block.'
}

$text=$text.Replace($old,$new)
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
    throw "bootstrap.ps1 parser check failed after RC13b:`n$message"
}

Write-Host 'RBZ PC Health v0.8.0 RC13b applied.' -ForegroundColor Green
Write-Host 'Stable bootstrap now normalises settings.json response content before JSON parsing.' -ForegroundColor Cyan
Write-Host 'bootstrap.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
