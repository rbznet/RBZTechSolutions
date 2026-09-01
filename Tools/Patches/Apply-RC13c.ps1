$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target=Join-Path $repoRoot 'bootstrap.ps1'

if(-not(Test-Path -LiteralPath $target)){
    throw "Required file not found: $target"
}

$text=Get-Content -LiteralPath $target -Raw

if($text -match 'RBZ080RC13C_IEX_SAFE_STABLE_BOOTSTRAP'){
    Write-Host 'RBZ PC Health v0.8.0 RC13c is already applied.' -ForegroundColor Yellow
    exit 0
}

if(-not $text.Contains('RBZ080RC13B_NORMALISE_CONFIG_CONTENT')){
    throw 'RC13c baseline validation failed. Apply RC13, RC13a and RC13b first.'
}

$old=@'
[CmdletBinding()]
param([string]$ConfigUrl='https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/Config/settings.json')
'@

$new=@'
# RBZ080RC13C_IEX_SAFE_STABLE_BOOTSTRAP
# Keep the stable bootstrap compatible with:
# irm https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/bootstrap.ps1 | iex
$ConfigUrl='https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/Config/settings.json'
'@

if(-not $text.Contains($old)){
    throw 'RC13c could not locate the stable bootstrap CmdletBinding/param block.'
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
    throw "bootstrap.ps1 parser check failed after RC13c:`n$message"
}

Write-Host 'RBZ PC Health v0.8.0 RC13c applied.' -ForegroundColor Green
Write-Host 'Stable bootstrap is now compatible with the public irm | iex command.' -ForegroundColor Cyan
Write-Host 'Config URL is defined directly inside bootstrap.ps1.' -ForegroundColor Cyan
Write-Host 'bootstrap.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
