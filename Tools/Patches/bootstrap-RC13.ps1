# RBZ PC Health bootstrapper
# RBZ080RC13_STABLE_SESSION_CLEANUP
# Stable channel remains release-based and SHA256 verified.
[CmdletBinding()]
param([string]$ConfigUrl='https://raw.githubusercontent.com/rbznet/RBZTechSolutions/main/Config/settings.json')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

function Assert-RBZAdministrator {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=[Security.Principal.WindowsPrincipal]$id
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        throw 'Open PowerShell as Administrator and run the command again.'
    }
}
function Preserve-RBZReports {
    param([string]$RepositoryRoot,[string]$Destination)
    try {
        $source=Join-Path $RepositoryRoot 'Reports'
        if(-not(Test-Path -LiteralPath $source)){return}
        $files=@(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue | Where-Object Name -ne '.gitkeep')
        if(-not $files.Count){return}
        New-Item -ItemType Directory -Path $Destination -Force|Out-Null
        foreach($file in $files){
            $relative=$file.FullName.Substring($source.Length).TrimStart('\')
            $target=Join-Path $Destination $relative
            $parent=Split-Path -Parent $target
            if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
        Write-Host "Preserved $($files.Count) report file(s): $Destination" -ForegroundColor DarkGray
    } catch { Write-Warning "RBZ report preservation failed: $($_.Exception.Message)" }
}
function Remove-RBZSessionFolder {
    param([string]$SessionRoot)
    if(-not(Test-Path -LiteralPath $SessionRoot)){return}
    try {
        Remove-Item -LiteralPath $SessionRoot -Recurse -Force -ErrorAction Stop
        Write-Host "Cleaned stable session folder: $SessionRoot" -ForegroundColor DarkGray
    } catch { Write-Warning "RBZ session cleanup could not remove '$SessionRoot': $($_.Exception.Message)" }
}
function Remove-RBZAbandonedSessions {
    param([string]$BasePath,[int]$OlderThanHours=24)
    if(-not(Test-Path -LiteralPath $BasePath)){return}
    $cutoff=(Get-Date).AddHours(-1*[math]::Abs($OlderThanHours))
    foreach($folder in @(Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue)){
        $marker=Join-Path $folder.FullName '.rbz-session'
        if(-not(Test-Path -LiteralPath $marker)){continue}
        if($folder.LastWriteTime -gt $cutoff){continue}
        try { Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop }
        catch { Write-Warning "Could not remove abandoned stable session '$($folder.FullName)': $($_.Exception.Message)" }
    }
}

Assert-RBZAdministrator
$config=Invoke-RestMethod -Uri $ConfigUrl -UseBasicParsing
$headers=@{'User-Agent'='RBZ-PC-Health-Bootstrap'}
$release=Invoke-RestMethod -Uri $config.github.releaseApi -Headers $headers
$zipAsset=$release.assets|Where-Object name -like $config.bootstrap.packageAssetPattern|Select-Object -First 1
$hashAsset=$release.assets|Where-Object name -like $config.bootstrap.hashAssetPattern|Select-Object -First 1
if(-not $zipAsset -or -not $hashAsset){throw 'Latest GitHub release is missing the expected ZIP or SHA256 asset.'}

$tempRoot=[Environment]::ExpandEnvironmentVariables([string]$config.bootstrap.tempRoot)
$tempBase=Join-Path $tempRoot 'Stable'
$sessionRoot=Join-Path $tempBase ([guid]::NewGuid().ToString('N'))
$zipPath=Join-Path $sessionRoot $zipAsset.name
$hashPath=Join-Path $sessionRoot $hashAsset.name
$extract=Join-Path $sessionRoot 'package'
$repoRoot=$null
$documents=[Environment]::GetFolderPath('MyDocuments')
if([string]::IsNullOrWhiteSpace($documents)){$documents=Join-Path $env:USERPROFILE 'Documents'}
$reportDestination=Join-Path $documents 'RBZ PC Health Reports\Stable'

New-Item -ItemType Directory -Path $tempBase -Force|Out-Null
Remove-RBZAbandonedSessions -BasePath $tempBase
New-Item -ItemType Directory -Path $sessionRoot -Force|Out-Null
Set-Content -LiteralPath (Join-Path $sessionRoot '.rbz-session') -Value (Get-Date).ToString('o') -Encoding ASCII -Force

try {
    Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Invoke-WebRequest -Uri $hashAsset.browser_download_url -OutFile $hashPath -UseBasicParsing
    $expected=((Get-Content -Raw $hashPath).Trim().Split(' ')[0]).ToUpperInvariant()
    $actual=(Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if($expected -ne $actual){throw "Package verification failed. Expected $expected but downloaded $actual."}

    Expand-Archive -Path $zipPath -DestinationPath $extract -Force
    $entry=Get-ChildItem -LiteralPath $extract -Filter $config.bootstrap.entryPoint -File -Recurse|Select-Object -First 1
    if(-not $entry){throw "Entry point '$($config.bootstrap.entryPoint)' was not found in the package."}
    $repoRoot=Split-Path -Parent $entry.FullName

    foreach($required in @((Join-Path $repoRoot 'Config\settings.json'),(Join-Path $repoRoot 'Modules'),(Join-Path $repoRoot 'Assets'))){
        if(-not(Test-Path -LiteralPath $required)){throw "Downloaded release package is incomplete. Missing: $required"}
    }

    Write-Host "RBZ PC Health $($release.tag_name) verified successfully." -ForegroundColor Green
    Write-Host "Session: $sessionRoot" -ForegroundColor DarkGray
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry.FullName
    if($LASTEXITCODE -and $LASTEXITCODE -ne 0){Write-Warning "RBZ PC Health exited with code $LASTEXITCODE."}
}
finally {
    if($repoRoot){Preserve-RBZReports -RepositoryRoot $repoRoot -Destination $reportDestination}
    if([bool]$config.bootstrap.cleanupAfterExit){
        Remove-RBZSessionFolder -SessionRoot $sessionRoot
        try {
            if((Test-Path -LiteralPath $tempBase) -and @(Get-ChildItem -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue).Count -eq 0){
                Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
            }
            if((Test-Path -LiteralPath $tempRoot) -and @(Get-ChildItem -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue).Count -eq 0){
                Remove-Item -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
