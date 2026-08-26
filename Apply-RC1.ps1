$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$settingsPath=Join-Path $root 'Config\settings.json'
if(-not(Test-Path $settingsPath)){throw "settings.json not found: $settingsPath"}
$c=Get-Content -Raw $settingsPath | ConvertFrom-Json
$c.app.version='0.8.0'
if(-not($c.PSObject.Properties.Name -contains 'priority')){
    $c | Add-Member -NotePropertyName priority -NotePropertyValue ([pscustomobject]@{
        enabled=$true
        topTechnicianActions=3
        includeInfoInPriorityList=$false
    })
}
$c | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
Write-Host 'RBZ PC Health config updated to v0.8.0 RC1.' -ForegroundColor Green
