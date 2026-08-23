# RBZ PC Health bootstrapper
[CmdletBinding()]
param([string]$ConfigUrl = 'https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/Config/settings.json')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

function Assert-Admin {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=[Security.Principal.WindowsPrincipal]$id
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Open PowerShell as Administrator and run the command again.'}
}
Assert-Admin
$config=Invoke-RestMethod -Uri $ConfigUrl -UseBasicParsing
$tempRoot=[Environment]::ExpandEnvironmentVariables([string]$config.bootstrap.tempRoot)
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$headers=@{'User-Agent'='RBZ-PC-Health-Bootstrap'}
$release=Invoke-RestMethod -Uri $config.github.releaseApi -Headers $headers
$zipAsset=$release.assets | Where-Object name -like $config.bootstrap.packageAssetPattern | Select-Object -First 1
$hashAsset=$release.assets | Where-Object name -like $config.bootstrap.hashAssetPattern | Select-Object -First 1
if(-not $zipAsset -or -not $hashAsset){throw 'Latest GitHub release is missing the expected ZIP or SHA256 asset.'}
$zipPath=Join-Path $tempRoot $zipAsset.name
$hashPath=Join-Path $tempRoot $hashAsset.name
Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
Invoke-WebRequest -Uri $hashAsset.browser_download_url -OutFile $hashPath -UseBasicParsing
$expected=((Get-Content -Raw $hashPath).Trim().Split(' ')[0]).ToUpperInvariant()
$actual=(Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
if($expected -ne $actual){Remove-Item $zipPath -Force -ErrorAction SilentlyContinue; throw "Package verification failed. Expected $expected but downloaded $actual."}
$extract=Join-Path $tempRoot ([IO.Path]::GetFileNameWithoutExtension($zipAsset.name))
if(Test-Path $extract){Remove-Item $extract -Recurse -Force}
Expand-Archive -Path $zipPath -DestinationPath $extract -Force
$entry=Get-ChildItem $extract -Filter $config.bootstrap.entryPoint -Recurse | Select-Object -First 1
if(-not $entry){throw "Entry point '$($config.bootstrap.entryPoint)' was not found in the package."}
Write-Host "RBZ PC Health $($release.tag_name) verified successfully." -ForegroundColor Green
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry.FullName
