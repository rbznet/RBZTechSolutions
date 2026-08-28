$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'
if(-not(Test-Path -LiteralPath $mainPath)){throw "Required file not found: $mainPath"}

$main=Get-Content -LiteralPath $mainPath -Raw

$fixed=$false

if($main -match "(?m)^='Light'\r?\n=False\s*$"){
    $main=[regex]::Replace(
        $main,
        "(?m)^='Light'\r?\n=False\s*$",
        "`$script:Theme='Light'`r`n`$script:RestartRequired=`$false"
    )
    $fixed=$true
}

if(-not $fixed -and $main -match "(?m)^[A-Za-z]+='Light'\r?\n=False\s*$"){
    $main=[regex]::Replace(
        $main,
        "(?m)^[A-Za-z]+='Light'\r?\n=False\s*$",
        "`$script:Theme='Light'`r`n`$script:RestartRequired=`$false"
    )
    $fixed=$true
}

if(-not $fixed -and $main -match '(?m)^=False\s*$'){
    $main=[regex]::Replace(
        $main,
        '(?m)^=False\s*$',
        '$script:RestartRequired=$false'
    )

    if($main -notmatch [regex]::Escape('$script:Theme=''Light''')){
        throw 'RC9e fixed RestartRequired but could not confirm Theme initialization.'
    }

    $fixed=$true
}

if(-not $fixed){
    if($main -match [regex]::Escape('$script:RestartRequired=$false')){
        Write-Host 'RC9e initialization is already correct.' -ForegroundColor Yellow
        exit 0
    }

    throw 'RC9e could not find the malformed RC9d initialization block.'
}

Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $mainPath,
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $msg=($errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"

    throw "RBZHealth.ps1 still has parser errors after RC9e:`n$msg"
}

Write-Host 'RBZ PC Health v0.8.0 RC9e applied.' -ForegroundColor Green
Write-Host 'Fixed the malformed RC9d restart-state initialization.' -ForegroundColor Cyan
Write-Host 'RBZHealth.ps1 passed a PowerShell parser check.' -ForegroundColor Cyan
Write-Host 'No Repair Centre action logic was changed.' -ForegroundColor DarkGray
