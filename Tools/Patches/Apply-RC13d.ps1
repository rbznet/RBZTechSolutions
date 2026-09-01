$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target=Join-Path $repoRoot 'bootstrap.ps1'

if(-not(Test-Path -LiteralPath $target)){
    throw "Required file not found: $target"
}

$text=Get-Content -LiteralPath $target -Raw

if($text -match 'RBZ080RC13D_UTF8_NO_BOM'){
    Write-Host 'RBZ PC Health v0.8.0 RC13d is already applied.' -ForegroundColor Yellow
    exit 0
}

if(-not $text.Contains('RBZ080RC13C_IEX_SAFE_STABLE_BOOTSTRAP')){
    throw 'RC13d baseline validation failed. Apply RC13c first.'
}

if(-not $text.Contains('# RBZ PC Health bootstrapper')){
    throw 'RC13d could not validate bootstrap.ps1 header.'
}

$text=$text.Replace(
    '# RBZ PC Health bootstrapper',
    "# RBZ PC Health bootstrapper`r`n# RBZ080RC13D_UTF8_NO_BOM"
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target,$text,$utf8NoBom)

$bytes=[System.IO.File]::ReadAllBytes($target)
if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){
    throw 'RC13d failed: bootstrap.ps1 still contains a UTF-8 BOM.'
}

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $target,[ref]$tokens,[ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $message=($errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"
    throw "bootstrap.ps1 parser check failed after RC13d:`n$message"
}

Write-Host 'RBZ PC Health v0.8.0 RC13d applied.' -ForegroundColor Green
Write-Host 'Stable bootstrap is now UTF-8 without BOM for irm | iex compatibility.' -ForegroundColor Cyan
Write-Host 'bootstrap.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
