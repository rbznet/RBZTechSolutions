$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target=Join-Path $repoRoot 'bootstrap.ps1'
$template=Join-Path $PSScriptRoot 'bootstrap-RC13.ps1'
if(-not(Test-Path $target)){throw "Required file not found: $target"}
if(-not(Test-Path $template)){throw "Required file not found: $template"}
$current=Get-Content $target -Raw
if($current -match 'RBZ080RC13_STABLE_SESSION_CLEANUP'){Write-Host 'RBZ PC Health v0.8.0 RC13 is already applied.' -ForegroundColor Yellow;exit}
foreach($fragment in @('releaseApi','packageAssetPattern','hashAssetPattern','Get-FileHash','powershell.exe -NoProfile -ExecutionPolicy Bypass')){
    if(-not $current.Contains($fragment)){throw "RC13 baseline validation failed. Missing stable bootstrap capability: $fragment"}
}
Copy-Item $template $target -Force
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw (($errors|ForEach-Object{"Line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n")}
Write-Host 'RBZ PC Health v0.8.0 RC13 applied.' -ForegroundColor Green
Write-Host 'Stable bootstrap now uses isolated TEMP sessions with safe cleanup.' -ForegroundColor Cyan
Write-Host 'Stable reports are preserved under Documents\RBZ PC Health Reports\Stable.' -ForegroundColor Cyan
Write-Host 'Release ZIP SHA256 verification remains enabled.' -ForegroundColor Cyan
Write-Host 'bootstrap.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
