$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$main=Join-Path $root 'RBZHealth.ps1'

if(-not(Test-Path $main)){
    throw "RBZHealth.ps1 not found: $main"
}

$text=Get-Content -Raw $main
$original=$text

# RC3a could duplicate the variable token while patching the
# no-priority fallback block. Repair that exact corruption.
$text=$text.Replace(
    '$PriorityDetailAction$PriorityDetailAction.Text',
    '$PriorityDetailAction.Text'
)

# Defensive cleanup in case the same token was duplicated more than once.
while($text.Contains('$PriorityDetailAction$PriorityDetailAction')){
    $text=$text.Replace(
        '$PriorityDetailAction$PriorityDetailAction',
        '$PriorityDetailAction'
    )
}

if($text -eq $original){
    Write-Host 'RC3b: no duplicated PriorityDetailAction token was found.' -ForegroundColor Yellow
}
else{
    Copy-Item $main "$main.v080rc3b.bak" -Force
    Set-Content -LiteralPath $main -Value $text -Encoding UTF8
    Write-Host 'RC3b: repaired duplicated PriorityDetailAction token.' -ForegroundColor Green
}

# Basic syntax parse before we tell the technician to launch the app.
$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $main,
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $message=($errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"
    throw "RBZHealth.ps1 still contains parser error(s):`n$message"
}

Write-Host 'RBZHealth.ps1 syntax check passed.' -ForegroundColor Green
