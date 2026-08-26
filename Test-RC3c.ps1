$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$module=Join-Path $root 'Modules\Priority.psm1'

if(-not(Test-Path $module)){
    throw "Priority.psm1 not found: $module"
}

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $module,
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $message=($errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"

    throw "Priority.psm1 contains parser error(s):`n$message"
}

Import-Module $module -Force

$testFinding=[pscustomobject]@{
    Category='System'
    Name='Application crash history'
    Status='Warning'
    Summary='17 application crash/hang event(s) detected; top recurring application: DayZ_x64.exe (6).'
    Details='Application failures can involve anti-cheat or security-related software.'
    Recommendation='Review recurring application names and faulting modules.'
}

$p=Get-RBZFindingPriority -Finding $testFinding

if($p.Reason -ne 'Repeated application crashes or hangs indicate a recurring software, driver or component stability issue that warrants investigation.'){
    throw "RC3c validation failed. Application crash priority reason returned: $($p.Reason)"
}

Write-Host 'RBZ PC Health v0.8.0 RC3c priority module validation passed.' -ForegroundColor Green
Write-Host "Application crash test reason: $($p.Reason)" -ForegroundColor Green
